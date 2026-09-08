import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';

void main() {
  for (final stage in ['headers', 'interceptor']) {
    for (final cancel in [false, true]) {
      test(
        '$stage ${cancel ? 'cancellation' : 'timeout'} prevents late dispatch',
        () async {
          final entered = Completer<void>();
          final release = Completer<void>();
          final lateFinished = Completer<void>();
          final transport = _Transport();
          final parent = NetworkCancellationToken();
          final client = ApiClient(
            baseUrl: 'https://example.invalid/',
            timeoutMs: 50,
            transport: transport,
            requestHeaderProvider: stage == 'headers'
                ? () async {
                    entered.complete();
                    await release.future;
                    lateFinished.complete();
                    return {};
                  }
                : null,
            requestInterceptor: stage == 'interceptor'
                ? (request, send) async {
                    entered.complete();
                    await release.future;
                    try {
                      return await send(request);
                    } finally {
                      lateFinished.complete();
                    }
                  }
                : null,
            retryPolicy: ApiRetryPolicy.safe,
          );
          final checked = expectLater(
            client.get('/api/v1/example', cancellationToken: parent),
            throwsA(
              cancel
                  ? isA<NetworkRequestCancelledException>()
                  : isA<ApiException>().having(
                      (e) => e.transportErrorKind,
                      'kind',
                      TransportErrorKind.timeout,
                    ),
            ),
          );
          await entered.future;
          if (cancel) parent.cancel();
          await checked.timeout(const Duration(seconds: 2));
          release.complete();
          await lateFinished.future;
          expect(transport.requests, isEmpty);
          expect(parent.isCancelled, cancel);
        },
      );
    }
  }

  test(
    'headers and transport share one deadline, without a fresh retry budget',
    () async {
      final transport = _Transport()..neverComplete = true;
      final headers = Completer<Map<String, String>>();
      final client = ApiClient(
        baseUrl: 'https://example.invalid/',
        timeoutMs: 1000,
        requestHeaderProvider: () => headers.future,
        transport: transport,
        retryPolicy: ApiRetryPolicy.safe,
      );
      final watch = Stopwatch()..start();
      final checked = expectLater(
        client.get('/api/v1/example'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.transportErrorKind,
            'kind',
            TransportErrorKind.timeout,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      headers.complete({});
      await checked;
      expect(transport.requests, hasLength(1));
      expect(transport.requests.single.cancellationToken!.isCancelled, isTrue);
      expect(watch.elapsedMilliseconds, lessThan(1350));
    },
  );

  test('late transport response cannot run the response processor', () async {
    final transport = _Transport()..neverComplete = true;
    var processed = 0;
    final client = ApiClient(
      baseUrl: 'https://example.invalid/',
      timeoutMs: 40,
      transport: transport,
      responseProcessor: (_) => processed++,
    );
    await expectLater(
      client.post('/api/v1/example'),
      throwsA(isA<ApiException>()),
    );
    transport.response.complete(_success);
    await Future<void>.delayed(Duration.zero);
    expect(processed, 0);
    expect(transport.requests, hasLength(1));
  });
}

const _success = TransportResponse(statusCode: 200, headers: {}, body: '{}');

class _Transport implements HttpTransport {
  final requests = <TransportRequest>[];
  bool neverComplete = false;
  final response = Completer<TransportResponse>();
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return neverComplete ? response.future : _success;
  }
}
