import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/multipart_body.dart';

class _FakeTransport implements HttpTransport {
  _FakeTransport({required this.handler});

  final TransportResponse Function(TransportRequest request) handler;
  TransportRequest? lastRequest;

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    lastRequest = request;
    return handler(request);
  }
}

void main() {
  test('merges baseUrl, path and query', () async {
    final transport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"ok":true}',
      ),
    );

    final client = ApiClient(
      baseUrl: 'https://example.com/api/',
      transport: transport,
    );

    await client.get<Object?>('v1/ping', query: {'a': 1, 'b': 'x'});

    expect(
      transport.lastRequest!.uri.toString(),
      'https://example.com/api/v1/ping?a=1&b=x',
    );
  });

  test('merges default headers and per-request headers', () async {
    final transport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"ok":true}',
      ),
    );

    final client = ApiClient(
      baseUrl: 'https://example.com/',
      defaultHeaders: {'x-a': '1', 'x-b': '2'},
      transport: transport,
    );

    await client.get<Object?>(
      '/ping',
      headers: {'x-b': 'override', 'x-c': '3'},
    );

    expect(transport.lastRequest!.headers['x-a'], '1');
    expect(transport.lastRequest!.headers['x-b'], 'override');
    expect(transport.lastRequest!.headers['x-c'], '3');
  });

  test('merges runtime headers before per-request headers', () async {
    final transport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"ok":true}',
      ),
    );

    final client = ApiClient(
      baseUrl: 'https://example.com/',
      defaultHeaders: {'x-a': 'default', 'x-b': 'default'},
      requestHeaderProvider: () async => {'x-b': 'runtime', 'x-c': 'runtime'},
      transport: transport,
    );

    await client.get<Object?>(
      '/ping',
      headers: {'x-c': 'request', 'x-d': 'request'},
    );

    expect(transport.lastRequest!.headers['x-a'], 'default');
    expect(transport.lastRequest!.headers['x-b'], 'runtime');
    expect(transport.lastRequest!.headers['x-c'], 'request');
    expect(transport.lastRequest!.headers['x-d'], 'request');
  });

  test('default response processor throws typed non-2xx error', () async {
    final transport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 401,
        headers: {'content-type': 'application/json'},
        body: '{"message":"unauthorized"}',
      ),
    );

    final client = ApiClient(
      baseUrl: 'https://example.com/',
      transport: transport,
    );

    await expectLater(
      client.get<Object?>('/ping'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.kind, 'kind', ApiExceptionKind.httpStatus),
      ),
    );
  });

  test('uses custom response processor', () async {
    final transport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"code":0,"data":{"v":123}}',
      ),
    );

    Object? processor(ApiResponse r) {
      final json = r.data as Map<String, dynamic>;
      if (json['code'] == 0) return (json['data'] as Map<String, dynamic>)['v'];
      throw ApiException(message: 'biz error');
    }

    final client = ApiClient(
      baseUrl: 'https://example.com/',
      transport: transport,
      responseProcessor: processor,
    );

    final v = await client.get<int>('/ping');
    expect(v, 123);
  });

  test('prepares multipart body and content type', () async {
    final transport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"ok":true}',
      ),
    );
    final client = ApiClient(
      baseUrl: 'https://example.com/',
      transport: transport,
    );

    await client.post<Object?>(
      '/upload',
      body: MultipartBody.singleFile(
        boundary: 'test-boundary',
        fields: const {'biz_type': 'avatar'},
        bytes: 'abc'.codeUnits,
        filename: 'a.txt',
        contentType: 'text/plain',
      ),
    );

    expect(
      transport.lastRequest!.headers['content-type'],
      'multipart/form-data; boundary=test-boundary',
    );
    final body = String.fromCharCodes(transport.lastRequest!.bodyBytes!);
    expect(body, contains('--test-boundary'));
    expect(body, contains('name="biz_type"'));
    expect(body, contains('filename="a.txt"'));
    expect(body, contains('Content-Type: text/plain'));
    expect(body, contains('abc'));
  });

  test('returns text and bytes without forcing json decoding', () async {
    var response = const TransportResponse(
      statusCode: 200,
      headers: {'content-type': 'application/json'},
      body: '{"ok":true}',
    );
    final transport = _FakeTransport(handler: (_) => response);
    final client = ApiClient(
      baseUrl: 'https://example.com/',
      transport: transport,
    );

    expect(await client.getText('/text'), '{"ok":true}');
    expect(transport.lastRequest!.decodeResponseBody, true);

    response = const TransportResponse(
      statusCode: 200,
      headers: {'content-type': 'application/octet-stream'},
      body: '',
      bodyBytes: <int>[0, 255, 1, 2],
    );

    expect(await client.getBytes('/file'), <int>[0, 255, 1, 2]);
    expect(transport.lastRequest!.decodeResponseBody, false);
  });

  test('keeps an error body for failed byte responses', () async {
    final transport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 503,
        headers: {'content-type': 'application/json'},
        body: '',
        bodyBytes: <int>[
          123,
          34,
          101,
          114,
          114,
          111,
          114,
          34,
          58,
          34,
          117,
          110,
          97,
          118,
          97,
          105,
          108,
          97,
          98,
          108,
          101,
          34,
          125,
        ],
      ),
    );
    final client = ApiClient(
      baseUrl: 'https://example.com/',
      transport: transport,
    );

    await expectLater(
      client.getBytes('/file'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.responseBody,
          'responseBody',
          '{"error":"unavailable"}',
        ),
      ),
    );
    expect(transport.lastRequest!.decodeResponseBody, false);
  });

  test(
    'wires receive progress and a request-owned cancellation token to transport',
    () async {
      final progressEvents = <({int receivedBytes, int totalBytes})>[];
      final token = NetworkCancellationToken();
      final transport = _FakeTransport(
        handler: (request) {
          request.onReceiveProgress?.call(3, 9);
          return const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/octet-stream'},
            body: 'abc',
            bodyBytes: <int>[97, 98, 99],
          );
        },
      );
      final client = ApiClient(
        baseUrl: 'https://example.com/',
        transport: transport,
      );

      await client.downloadBytes(
        '/file',
        onReceiveProgress: (receivedBytes, totalBytes) {
          progressEvents.add((
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ));
        },
        cancellationToken: token,
      );

      expect(transport.lastRequest!.cancellationToken, isNot(same(token)));
      expect(transport.lastRequest!.cancellationToken!.isCancelled, isFalse);
      expect(token.isCancelled, isFalse);
      expect(progressEvents, [(receivedBytes: 3, totalBytes: 9)]);
    },
  );

  test('propagates request cancellation without wrapping as ApiException', () {
    final token = NetworkCancellationToken()..cancel();
    final transport = _FakeTransport(
      handler: (request) {
        request.cancellationToken?.throwIfCancelled();
        return const TransportResponse(statusCode: 200, headers: {}, body: '');
      },
    );
    final client = ApiClient(
      baseUrl: 'https://example.com/',
      transport: transport,
    );

    expect(
      () => client.getBytes('/file', cancellationToken: token),
      throwsA(isA<NetworkRequestCancelledException>()),
    );
  });

  test('wraps transport timeout with typed retryable error', () async {
    final transport = _FakeTransport(
      handler: (_) => throw TimeoutException('slow'),
    );
    final client = ApiClient(
      baseUrl: 'https://example.com/',
      transport: transport,
    );

    await expectLater(
      client.get<Object?>('/ping'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiExceptionKind.timeout)
            .having(
              (e) => e.transportErrorKind,
              'transportErrorKind',
              TransportErrorKind.timeout,
            )
            .having((e) => e.retryable, 'retryable', isTrue),
      ),
    );
  });

  test('transport errors expose redacted diagnostics', () async {
    final transport = _FakeTransport(
      handler: (_) => throw Exception('connection closed'),
    );
    final client = ApiClient(
      baseUrl: 'https://example.com/',
      transport: transport,
    );

    try {
      await client.get<Object?>('/user/info', query: {'uid': 'u_private'});
      fail('Expected a transport ApiException.');
    } on ApiException catch (error) {
      expect(error.transportErrorKind, TransportErrorKind.connection);
      expect(error.toString(), contains('(cause=_Exception)'));
      expect(error.toString(), contains('(uri=https://example.com/user/info)'));
      expect(error.toString(), isNot(contains('u_private')));
    }
  });

  test('safe retry policy retries GET transport timeouts', () async {
    var attempts = 0;
    final transport = _FakeTransport(
      handler: (_) {
        attempts += 1;
        if (attempts == 1) throw TimeoutException('slow');
        return const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"ok":true}',
        );
      },
    );
    final client = ApiClient(
      baseUrl: 'https://example.com/',
      transport: transport,
      retryPolicy: ApiRetryPolicy.safe,
    );

    expect(await client.get<Object?>('/ping'), {'ok': true});
    expect(attempts, 2);
  });

  test('safe retry policy does not retry POST transport timeouts', () async {
    var attempts = 0;
    final transport = _FakeTransport(
      handler: (_) {
        attempts += 1;
        throw TimeoutException('slow');
      },
    );
    final client = ApiClient(
      baseUrl: 'https://example.com/',
      transport: transport,
      retryPolicy: ApiRetryPolicy.safe,
    );

    await expectLater(
      client.post<Object?>('/ping', body: const <String, Object?>{}),
      throwsA(isA<ApiException>()),
    );
    expect(attempts, 1);
  });
}
