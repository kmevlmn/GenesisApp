import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/dio_http_transport.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/io_http_transport.dart';
import 'package:genesis_flutter_android/network/platform_http3_transport.dart';
import 'package:http/http.dart' as http;

void main() {
  for (final engine in ['native', 'dio', 'io']) {
    for (final userCancelled in [false, true]) {
      test(
        '$engine never sends after cancellation during metric preparation ($userCancelled)',
        () async {
          final metric = _DelayedMetric();
          var sends = 0;
          final dio = Dio()
            ..httpClientAdapter = _StreamingAdapter(() {
              sends++;
              return const Stream.empty();
            });
          addTearDown(() => dio.close(force: true));
          final HttpTransport transport = switch (engine) {
            'native' => PlatformHttp3Transport(
              client: _StreamClient(() {
                sends++;
                return const Stream.empty();
              }),
              performanceMetricFactory: (_, __) => metric,
              performanceMetricReady: () => true,
            ),
            'dio' => DioHttpTransport(
              dio: dio,
              performanceMetricFactory: (_, __) => metric,
              performanceMetricReady: () => true,
            ),
            _ => IoHttpTransport(
              client: _UnexpectedHttpClient(() => sends++),
              performanceMetricFactory: (_, __) => metric,
              performanceMetricReady: () => true,
            ),
          };
          final token = NetworkCancellationToken();
          final result = transport.send(_request(timeoutMs: 50, token: token));
          final checked = expectLater(
            result,
            throwsA(
              userCancelled
                  ? isA<NetworkRequestCancelledException>()
                  : isA<TimeoutException>(),
            ),
          );
          await metric.started.future;
          if (userCancelled) token.cancel();
          await checked;
          metric.release.complete();
          await metric.stopped.future;
          expect(sends, 0);
          // Expiry cancels only the request's child, not a reusable caller token.
          expect(token.isCancelled, userCancelled);
        },
      );
    }
  }

  for (final engine in ['native', 'dio', 'io']) {
    test(
      '$engine deadline cancels a continuously arriving response body',
      () async {
        final streamCancelled = Completer<void>();
        var receivedChunks = 0;
        Timer? producer;
        final stream = StreamController<List<int>>(
          onCancel: () {
            producer?.cancel();
            if (!streamCancelled.isCompleted) streamCancelled.complete();
          },
        );
        producer = Timer.periodic(const Duration(milliseconds: 5), (_) {
          stream.add([65]);
        });
        addTearDown(() {
          producer?.cancel();
          unawaited(stream.close());
        });
        final dio = Dio()
          ..httpClientAdapter = _StreamingAdapter(() => stream.stream);
        addTearDown(() => dio.close(force: true));
        HttpServer? server;
        HttpClient? ioClient;
        Uri uri = Uri.parse('https://example.invalid/send');
        if (engine == 'io') {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          uri = Uri.parse('http://127.0.0.1:${server.port}/send');
          server.listen((request) async {
            await request.drain<void>();
            request.response.bufferOutput = false;
            try {
              await request.response.addStream(stream.stream);
              await request.response.close();
            } catch (_) {
              // Client closes the connection at its deadline.
            }
          });
          ioClient = HttpClient();
          addTearDown(() async {
            ioClient!.close(force: true);
            await server!.close(force: true);
          });
        }
        final HttpTransport transport = switch (engine) {
          'native' => PlatformHttp3Transport(
            client: _StreamClient(() => stream.stream),
            performanceMetricReady: () => false,
          ),
          'dio' => DioHttpTransport(
            dio: dio,
            performanceMetricReady: () => false,
          ),
          _ => IoHttpTransport(
            client: ioClient,
            performanceMetricReady: () => false,
          ),
        };
        await expectLater(
          transport.send(
            TransportRequest(
              method: 'POST',
              uri: uri,
              headers: const {},
              bodyBytes: [1],
              timeoutMs: 200,
              onReceiveProgress: (_, __) => receivedChunks++,
            ),
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(receivedChunks, greaterThan(1));
        await streamCancelled.future.timeout(const Duration(seconds: 2));
      },
    );
  }
}

TransportRequest _request({
  required int timeoutMs,
  NetworkCancellationToken? token,
}) => TransportRequest(
  method: 'POST',
  uri: Uri.parse('https://example.invalid/send'),
  headers: const {},
  bodyBytes: [1],
  timeoutMs: timeoutMs,
  cancellationToken: token,
);

class _DelayedMetric implements HttpRequestPerformanceMetric {
  final started = Completer<void>();
  final release = Completer<void>();
  final stopped = Completer<void>();
  @override
  Future<void> start() {
    started.complete();
    return release.future;
  }

  @override
  Future<void> stop() async {
    if (!stopped.isCompleted) stopped.complete();
  }

  @override
  void putAttribute(String name, String value) {}
  @override
  set httpResponseCode(int? value) {}
  @override
  set requestPayloadSize(int? value) {}
  @override
  set responseContentType(String? value) {}
  @override
  set responsePayloadSize(int? value) {}
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this.body);
  final Stream<List<int>> Function() body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(body(), 200);
}

class _StreamingAdapter implements HttpClientAdapter {
  _StreamingAdapter(this.body);
  final Stream<List<int>> Function() body;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody(body().map(Uint8List.fromList), 200);
  @override
  void close({bool force = false}) {}
}

class _UnexpectedHttpClient implements HttpClient {
  _UnexpectedHttpClient(this.onOpen);
  final void Function() onOpen;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    onOpen();
    throw StateError('Cancelled preparation must not open a connection.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
