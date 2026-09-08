import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/io_http_transport.dart';
import 'package:genesis_flutter_android/network/platform_http3_transport.dart';
import 'package:http/http.dart' as http;

void main() {
  test('maps HTTPS request and negotiated HTTP/3 response', () async {
    final client = _RecordingClient(
      response: http.StreamedResponse(
        Stream<List<int>>.fromIterable(<List<int>>[
          utf8.encode('he'),
          utf8.encode('llo'),
        ]),
        206,
        headers: const <String, String>{
          'content-type': 'text/plain',
          'content-length': '5',
        },
        contentLength: 5,
      ),
    );
    final metrics = <_FakePerformanceMetric>[];
    final receiveProgress = <({int current, int total})>[];
    final transport = PlatformHttp3Transport(
      client: client,
      protocolResolver: (_) => 'h3-29',
      performanceMetricReady: () => true,
      performanceMetricUrlFilter: (_) => true,
      performanceMetricFactory: (url, method) {
        final metric = _FakePerformanceMetric(url: url, method: method);
        metrics.add(metric);
        return metric;
      },
    );

    final response = await transport.send(
      TransportRequest(
        method: 'GET',
        uri: Uri.parse('https://cdn-001.worldo.ai/tile.webp?version=1'),
        headers: const <String, String>{'accept': 'image/webp'},
        bodyBytes: null,
        timeoutMs: 5000,
        onReceiveProgress: (current, total) {
          receiveProgress.add((current: current, total: total));
        },
      ),
    );

    expect(client.requests, hasLength(1));
    expect(client.requests.single, isA<http.AbortableRequest>());
    expect(client.requests.single.method, 'GET');
    expect(client.requests.single.headers['accept'], 'image/webp');
    expect(response.statusCode, 206);
    expect(response.body, 'hello');
    expect(response.bodyBytes, utf8.encode('hello'));
    expect(response.bodyBytes, isA<Uint8List>());
    expect(response.httpProtocolVersion, 'h3');
    expect(receiveProgress.last, (current: 5, total: 5));
    expect(metrics, hasLength(1));
    expect(metrics.single.started, true);
    expect(metrics.single.stopped, true);
    expect(metrics.single.httpResponseCode, 206);
    expect(metrics.single.responsePayloadSize, 5);
    expect(metrics.single.attributes, const <String, String>{
      'network_protocol': 'h3',
    });
  });

  test('keeps explicit byte responses out of the UTF-8 body string', () async {
    final bytes = <int>[0, 255, 1, 2];
    final transport = PlatformHttp3Transport(
      client: _RecordingClient(
        response: http.StreamedResponse(
          Stream<List<int>>.fromIterable(<List<int>>[
            bytes.sublist(0, 2),
            bytes.sublist(2),
          ]),
          200,
        ),
      ),
      protocolResolver: (_) => 'h3',
      performanceMetricReady: () => false,
    );

    final response = await transport.send(
      TransportRequest(
        method: 'GET',
        uri: Uri.parse('https://cdn-001.worldo.ai/image.webp'),
        headers: const <String, String>{},
        bodyBytes: null,
        timeoutMs: 5000,
        decodeResponseBody: false,
      ),
    );

    expect(response.body, isEmpty);
    expect(response.bodyBytes, bytes);
    expect(response.bodyBytes, isA<Uint8List>());
  });

  test('maps multipart body and reports upload completion once', () async {
    final client = _RecordingClient(
      response: http.StreamedResponse(const Stream<List<int>>.empty(), 204),
    );
    final sendProgress = <({int current, int total})>[];
    final transport = PlatformHttp3Transport(
      client: client,
      protocolResolver: (_) => 'h2',
      performanceMetricReady: () => false,
    );
    final body = utf8.encode(
      '--test-boundary\r\n'
      'content-disposition: form-data; name="file"; filename="tile.webp"\r\n'
      'content-type: image/webp\r\n\r\n'
      'image-bytes\r\n'
      '--test-boundary--\r\n',
    );

    final response = await transport.send(
      TransportRequest(
        method: 'POST',
        uri: Uri.parse('https://api.worldo.ai/api/v1/upload'),
        headers: const <String, String>{
          'content-type': 'multipart/form-data; boundary=test-boundary',
        },
        bodyBytes: body,
        timeoutMs: 5000,
        onSendProgress: (current, total) {
          sendProgress.add((current: current, total: total));
        },
      ),
    );

    final request = client.requests.single as http.Request;
    expect(
      request.headers['content-type'],
      'multipart/form-data; boundary=test-boundary',
    );
    expect(request.bodyBytes, body);
    expect(sendProgress, <({int current, int total})>[
      (current: body.length, total: body.length),
    ]);
    expect(response.statusCode, 204);
    expect(response.httpProtocolVersion, 'h2');
  });

  test(
    'returns non-2xx responses without treating them as transport errors',
    () async {
      final metrics = <_FakePerformanceMetric>[];
      final transport = PlatformHttp3Transport(
        client: _RecordingClient(
          response: http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode('unauthorized')),
            401,
          ),
        ),
        protocolResolver: (_) => 'h3',
        performanceMetricReady: () => true,
        performanceMetricFactory: (url, method) {
          final metric = _FakePerformanceMetric(url: url, method: method);
          metrics.add(metric);
          return metric;
        },
      );

      final response = await transport.send(
        TransportRequest(
          method: 'GET',
          uri: Uri.parse('https://api.worldo.ai/private'),
          headers: const <String, String>{},
          bodyBytes: null,
          timeoutMs: 5000,
        ),
      );

      expect(response.statusCode, 401);
      expect(response.body, 'unauthorized');
      expect(metrics.single.httpResponseCode, 401);
      expect(metrics.single.stopped, isTrue);
    },
  );

  for (final protocol in ['http/1.1', 'h2', 'h3', null]) {
    test('accepts HTTPS response over $protocol without replay', () async {
      final client = _RecordingClient(
        response: http.StreamedResponse(
          Stream.value(utf8.encode('{"err_no":10001}')),
          200,
        ),
      );
      final metric = _FakePerformanceMetric(
        url: 'https://api.worldo.ai',
        method: HttpMethod.Post,
      );
      final transport = PlatformHttp3Transport(
        client: client,
        protocolResolver: (_) => protocol,
        performanceMetricReady: () => true,
        performanceMetricUrlFilter: (_) => true,
        performanceMetricFactory: (_, __) => metric,
      );
      final response = await transport.send(
        TransportRequest(
          method: 'POST',
          uri: Uri.parse('https://api.worldo.ai/api/v1/health'),
          headers: const {},
          bodyBytes: utf8.encode('{}'),
          timeoutMs: 5000,
        ),
      );
      expect(response.statusCode, 200);
      expect(response.body, '{"err_no":10001}');
      expect(response.httpProtocolVersion, protocol);
      expect(client.requests, hasLength(1));
      expect(metric.attributes['network_protocol'], protocol);
    });
  }

  test('maps cancellation to NetworkRequestCancelledException', () async {
    final cancellationToken = NetworkCancellationToken();
    final metrics = <_FakePerformanceMetric>[];
    final transport = PlatformHttp3Transport(
      client: _AbortAwareClient(),
      protocolResolver: (_) => 'h3',
      performanceMetricReady: () => true,
      performanceMetricFactory: (url, method) {
        final metric = _FakePerformanceMetric(url: url, method: method);
        metrics.add(metric);
        return metric;
      },
    );

    final future = transport.send(
      TransportRequest(
        method: 'GET',
        uri: Uri.parse('https://api.worldo.ai/slow'),
        headers: const <String, String>{},
        bodyBytes: null,
        timeoutMs: 5000,
        cancellationToken: cancellationToken,
      ),
    );
    cancellationToken.cancel();

    await expectLater(future, throwsA(isA<NetworkRequestCancelledException>()));
    expect(metrics.single.stopped, isTrue);
  });

  test('aborts native request when timeout expires', () async {
    final metrics = <_FakePerformanceMetric>[];
    final transport = PlatformHttp3Transport(
      client: _NeverCompletingClient(),
      protocolResolver: (_) => 'h3',
      performanceMetricReady: () => true,
      performanceMetricFactory: (url, method) {
        final metric = _FakePerformanceMetric(url: url, method: method);
        metrics.add(metric);
        return metric;
      },
    );

    await expectLater(
      transport.send(
        TransportRequest(
          method: 'GET',
          uri: Uri.parse('https://api.worldo.ai/slow'),
          headers: const <String, String>{},
          bodyBytes: null,
          timeoutMs: 5,
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(metrics.single.stopped, isTrue);
  });

  test('delegates plain HTTP to the fallback transport', () async {
    final fallback = _RecordingTransport(
      const TransportResponse(
        statusCode: 200,
        headers: <String, String>{},
        body: 'fallback',
      ),
    );
    final nativeClient = _RecordingClient(
      response: http.StreamedResponse(const Stream.empty(), 200),
    );
    final transport = PlatformHttp3Transport(
      client: nativeClient,
      nonHttpsTransport: fallback,
      performanceMetricReady: () => false,
    );

    final response = await transport.send(
      TransportRequest(
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1/health'),
        headers: const <String, String>{},
        bodyBytes: null,
        timeoutMs: 5000,
      ),
    );

    expect(response.body, 'fallback');
    expect(fallback.requests, hasLength(1));
    expect(nativeClient.requests, isEmpty);
  });
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient({required this.response});

  final http.StreamedResponse response;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return response;
  }
}

class _AbortAwareClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abortTrigger = (request as http.AbortableRequest).abortTrigger;
    await abortTrigger;
    throw http.RequestAbortedException(request.url);
  }
}

class _NeverCompletingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Completer<http.StreamedResponse>().future;
  }
}

class _RecordingTransport implements HttpTransport {
  _RecordingTransport(this.response);

  final TransportResponse response;
  final List<TransportRequest> requests = <TransportRequest>[];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return response;
  }
}

class _FakePerformanceMetric implements HttpRequestPerformanceMetric {
  _FakePerformanceMetric({required this.url, required this.method});

  final String url;
  final HttpMethod method;
  final Map<String, String> attributes = <String, String>{};
  bool started = false;
  bool stopped = false;

  @override
  int? httpResponseCode;

  @override
  int? requestPayloadSize;

  @override
  String? responseContentType;

  @override
  int? responsePayloadSize;

  @override
  void putAttribute(String name, String value) {
    attributes[name] = value;
  }

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}
