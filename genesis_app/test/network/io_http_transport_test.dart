import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/telemetry/firebase_performance_monitoring.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/io_http_transport.dart';

void main() {
  test('normalizes only valid HTTP proxy authorities', () {
    expect(normalizeHttpProxyAddress('127.0.0.1:9090'), '127.0.0.1:9090');
    expect(
      normalizeHttpProxyAddress(' http://LOCALHOST:9090/ '),
      'localhost:9090',
    );
    expect(normalizeHttpProxyAddress('http://[::1]:9090'), '[::1]:9090');
    for (final invalid in <String>[
      '',
      '[',
      '127.0.0.1:abc',
      'https://127.0.0.1:9090',
      '127.0.0.1:0',
      '127.0.0.1:65536',
      'http://127.0.0.1:9090/path',
    ]) {
      expect(normalizeHttpProxyAddress(invalid), isNull, reason: invalid);
    }
  });

  test('Firebase URL filter includes every HTTP/S request', () {
    expect(
      isFirebasePerformanceMetricUrl(
        Uri.parse(
          'https://cdn-001.worldo.ai/predata/tiles/L2/tile.webp'
          '?x-oss-process=image/resize,w_512',
        ),
      ),
      true,
    );
    expect(
      isFirebasePerformanceMetricUrl(
        Uri.parse('https://cdn-001.worldo.ai/avatars/user.webp'),
      ),
      true,
    );
    expect(
      isFirebasePerformanceMetricUrl(
        Uri.parse('https://api.worldo.ai/api/v1/world/map'),
      ),
      true,
    );
    expect(
      isFirebasePerformanceMetricUrl(
        Uri.parse('wss://api.worldo.ai/aitown-chat/ws'),
      ),
      false,
    );
  });

  test('records Firebase HTTP metric data for completed requests', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/v1/search');
      expect(request.uri.queryParameters['keyword'], 'worldo');
      await utf8.decodeStream(request);
      final responseBody = utf8.encode('{"ok":true}');
      request.response
        ..statusCode = 201
        ..headers.contentType = ContentType.json
        ..contentLength = responseBody.length
        ..add(responseBody);
      await request.response.close();
    });

    final metrics = <_FakePerformanceMetric>[];
    final transport = IoHttpTransport(
      performanceMetricUrlFilter: (_) => true,
      performanceMetricReady: () => true,
      performanceMetricFactory: (url, method) {
        final metric = _FakePerformanceMetric(url: url, method: method);
        metrics.add(metric);
        return metric;
      },
    );
    final body = utf8.encode('{"q":"worldo"}');

    final response = await transport.send(
      TransportRequest(
        method: 'POST',
        uri: Uri.parse(
          'http://127.0.0.1:${server.port}/api/v1/search?keyword=worldo',
        ),
        headers: const {'content-type': 'application/json'},
        bodyBytes: body,
        timeoutMs: 5000,
      ),
    );

    expect(response.statusCode, 201);
    expect(metrics, hasLength(1));
    final metric = metrics.single;
    expect(metric.url, 'http://127.0.0.1:${server.port}/api/v1/search');
    expect(metric.method, HttpMethod.Post);
    expect(metric.started, true);
    expect(metric.stopped, true);
    expect(metric.requestPayloadSize, body.length);
    expect(metric.httpResponseCode, 201);
    expect(metric.responseContentType, 'application/json; charset=utf-8');
    expect(metric.responsePayloadSize, utf8.encode('{"ok":true}').length);
  });

  test('records manual metrics for every HTTP host by default', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = 200
        ..write('ok');
      await request.response.close();
    });

    final metrics = <_FakePerformanceMetric>[];
    final transport = IoHttpTransport(
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
        uri: Uri.parse('http://127.0.0.1:${server.port}/collect'),
        headers: const {},
        bodyBytes: null,
        timeoutMs: 5000,
      ),
    );

    expect(response.statusCode, 200);
    expect(metrics, hasLength(1));
    expect(metrics.single.url, 'http://127.0.0.1:${server.port}/collect');
  });

  test('records business metric URL without adding port zero', () async {
    final metrics = <_FakePerformanceMetric>[];
    final transport = IoHttpTransport(
      client: _FakeHttpClient(
        statusCode: 200,
        responseBody: '{"ok":true}',
        contentType: ContentType.json,
      ),
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
        uri: Uri.parse(
          'https://api.worldo.ai/api/v1/origin/list?scene=foryou&pn=1&rn=20',
        ),
        headers: const {},
        bodyBytes: null,
        timeoutMs: 5000,
      ),
    );

    expect(response.statusCode, 200);
    expect(metrics, hasLength(1));
    expect(metrics.single.url, 'https://api.worldo.ai/api/v1/origin/list');
    expect(metrics.single.url, isNot(contains(':0')));
  });

  test('Firebase metric URL removes credentials, query, and fragment', () {
    expect(
      firebaseMetricUrl(
        Uri.parse(
          'https://user:secret@api.worldo.ai/api/v1/world/w_1'
          '?token=secret#section',
        ),
      ),
      'https://api.worldo.ai/api/v1/world/w_1',
    );
  });

  test('continues request when metric creation fails', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = 200
        ..write('ok');
      await request.response.close();
    });

    final transport = IoHttpTransport(
      performanceMetricUrlFilter: (_) => true,
      performanceMetricReady: () => true,
      performanceMetricFactory: (_, _) => throw StateError('metric failed'),
    );

    final response = await transport.send(
      TransportRequest(
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1:${server.port}/ping'),
        headers: const {},
        bodyBytes: null,
        timeoutMs: 5000,
      ),
    );

    expect(response.statusCode, 200);
    expect(response.body, 'ok');
  });

  test(
    'metric start timeout does not block HTTP and disables later metrics',
    () async {
      FirebasePerformanceMonitoring.resetForTesting();
      addTearDown(FirebasePerformanceMonitoring.resetForTesting);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response
          ..statusCode = 200
          ..write('ok');
        await request.response.close();
      });
      final startCompleter = Completer<void>();
      final metrics = <_FakePerformanceMetric>[];
      final transport = IoHttpTransport(
        performanceMetricUrlFilter: (_) => true,
        performanceMetricReady: () => true,
        performanceMetricFactory: (url, method) {
          final metric = _FakePerformanceMetric(
            url: url,
            method: method,
            startCompleter: startCompleter,
          );
          metrics.add(metric);
          return metric;
        },
      );
      final request = TransportRequest(
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1:${server.port}/ping'),
        headers: const <String, String>{},
        bodyBytes: null,
        timeoutMs: 5000,
      );

      final firstResponse = await transport.send(request);
      final secondResponse = await transport.send(request);

      expect(firstResponse.body, 'ok');
      expect(secondResponse.body, 'ok');
      expect(metrics, hasLength(1));
      expect(FirebasePerformanceMonitoring.isCircuitBroken, isTrue);
      expect(metrics.single.stopped, isFalse);

      startCompleter.complete();
      await Future<void>.delayed(Duration.zero);
      expect(metrics.single.stopped, isTrue);
    },
  );

  test('metric stop never delays a completed HTTP response', () async {
    FirebasePerformanceMonitoring.resetForTesting();
    addTearDown(FirebasePerformanceMonitoring.resetForTesting);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = 200
        ..write('ok');
      await request.response.close();
    });
    final stopCompleter = Completer<void>();
    late _FakePerformanceMetric metric;
    final transport = IoHttpTransport(
      performanceMetricUrlFilter: (_) => true,
      performanceMetricReady: () => true,
      performanceMetricFactory: (url, method) {
        return metric = _FakePerformanceMetric(
          url: url,
          method: method,
          stopCompleter: stopCompleter,
        );
      },
    );

    final response = await transport
        .send(
          TransportRequest(
            method: 'GET',
            uri: Uri.parse('http://127.0.0.1:${server.port}/ping'),
            headers: const <String, String>{},
            bodyBytes: null,
            timeoutMs: 5000,
          ),
        )
        .timeout(const Duration(seconds: 1));

    expect(response.body, 'ok');
    expect(metric.stopped, isTrue);
    stopCompleter.complete();
  });

  test('reports receive progress and keeps raw response bytes', () async {
    final responseBody = <int>[0, 1, 2, 250, 255];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.binary
        ..contentLength = responseBody.length;
      request.response.add(responseBody.sublist(0, 2));
      await request.response.flush();
      request.response.add(responseBody.sublist(2));
      await request.response.close();
    });

    final progressEvents = <({int receivedBytes, int totalBytes})>[];
    final transport = IoHttpTransport(performanceMetricUrlFilter: (_) => false);

    final response = await transport.send(
      TransportRequest(
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1:${server.port}/asset.bin'),
        headers: const {},
        bodyBytes: null,
        timeoutMs: 5000,
        decodeResponseBody: false,
        onReceiveProgress: (receivedBytes, totalBytes) {
          progressEvents.add((
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ));
        },
      ),
    );

    expect(response.statusCode, 200);
    expect(response.body, isEmpty);
    expect(response.bodyBytes, responseBody);
    expect(response.bodyBytes, isA<Uint8List>());
    expect(progressEvents, isNotEmpty);
    expect(progressEvents.last.receivedBytes, responseBody.length);
    expect(progressEvents.last.totalBytes, responseBody.length);
  });

  test('records HTTP errors and stops their metric', () async {
    final metrics = <_FakePerformanceMetric>[];
    final transport = IoHttpTransport(
      client: _FakeHttpClient(
        statusCode: 401,
        responseBody: 'unauthorized',
        contentType: ContentType.text,
      ),
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
    expect(metrics.single.httpResponseCode, 401);
    expect(metrics.single.stopped, isTrue);
  });

  test('stops metrics when opening a request times out', () async {
    final metrics = <_FakePerformanceMetric>[];
    final transport = IoHttpTransport(
      client: _NeverOpeningHttpClient(),
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

    expect(metrics.single.started, isTrue);
    expect(metrics.single.stopped, isTrue);
  });

  test('stops metrics when a request is cancelled', () async {
    final client = _ControllableOpeningHttpClient();
    final metrics = <_FakePerformanceMetric>[];
    final cancellationToken = NetworkCancellationToken();
    final transport = IoHttpTransport(
      client: client,
      performanceMetricReady: () => true,
      performanceMetricFactory: (url, method) {
        final metric = _FakePerformanceMetric(url: url, method: method);
        metrics.add(metric);
        return metric;
      },
    );

    final sending = transport.send(
      TransportRequest(
        method: 'GET',
        uri: Uri.parse('https://api.worldo.ai/slow'),
        headers: const <String, String>{},
        bodyBytes: null,
        timeoutMs: 5000,
        cancellationToken: cancellationToken,
      ),
    );
    await client.opened.future;
    cancellationToken.cancel();
    client.completeOpen();

    await expectLater(
      sending,
      throwsA(isA<NetworkRequestCancelledException>()),
    );
    expect(metrics.single.started, isTrue);
    expect(metrics.single.stopped, isTrue);
  });

  test(
    'skips manual metrics while Firebase Performance is not ready',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response
          ..statusCode = 200
          ..write('ok');
        await request.response.close();
      });

      final metrics = <_FakePerformanceMetric>[];
      final transport = IoHttpTransport(
        performanceMetricUrlFilter: (_) => true,
        performanceMetricReady: () => false,
        performanceMetricFactory: (url, method) {
          final metric = _FakePerformanceMetric(url: url, method: method);
          metrics.add(metric);
          return metric;
        },
      );

      final response = await transport.send(
        TransportRequest(
          method: 'GET',
          uri: Uri.parse('http://127.0.0.1:${server.port}/ping'),
          headers: const {},
          bodyBytes: null,
          timeoutMs: 5000,
        ),
      );

      expect(response.statusCode, 200);
      expect(response.body, 'ok');
      expect(metrics, isEmpty);
    },
  );
}

class _FakePerformanceMetric implements HttpRequestPerformanceMetric {
  _FakePerformanceMetric({
    required this.url,
    required this.method,
    this.startCompleter,
    this.stopCompleter,
  });

  final String url;
  final HttpMethod method;
  final Completer<void>? startCompleter;
  final Completer<void>? stopCompleter;

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

  final Map<String, String> attributes = <String, String>{};

  @override
  void putAttribute(String name, String value) {
    attributes[name] = value;
  }

  @override
  Future<void> start() async {
    started = true;
    await startCompleter?.future;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    await stopCompleter?.future;
  }
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({
    required this.statusCode,
    required this.responseBody,
    required this.contentType,
  });

  final int statusCode;
  final String responseBody;
  final ContentType contentType;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    return _FakeHttpClientRequest(
      statusCode: statusCode,
      responseBody: responseBody,
      contentType: contentType,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NeverOpeningHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    return Completer<HttpClientRequest>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControllableOpeningHttpClient implements HttpClient {
  final Completer<void> opened = Completer<void>();
  final Completer<HttpClientRequest> _request = Completer<HttpClientRequest>();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    opened.complete();
    return _request.future;
  }

  void completeOpen() {
    _request.complete(
      _FakeHttpClientRequest(
        statusCode: 200,
        responseBody: 'ok',
        contentType: ContentType.text,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest({
    required this.statusCode,
    required this.responseBody,
    required this.contentType,
  });

  final int statusCode;
  final String responseBody;
  final ContentType contentType;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  void add(List<int> data) {}

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> get done => close();

  @override
  Future<HttpClientResponse> close() async {
    return _FakeHttpClientResponse(
      statusCode: statusCode,
      body: responseBody,
      contentType: contentType,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse({
    required this.statusCode,
    required String body,
    required ContentType contentType,
  }) : _bodyBytes = utf8.encode(body),
       headers = _FakeHttpHeaders(contentType: contentType);

  final List<int> _bodyBytes;

  @override
  final int statusCode;

  @override
  final HttpHeaders headers;

  @override
  int get contentLength => _bodyBytes.length;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_bodyBytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  _FakeHttpHeaders({ContentType? contentType}) : _contentType = contentType;

  final ContentType? _contentType;
  final Map<String, List<String>> _values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name] = <String>['$value'];
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    if (_contentType != null) {
      action(HttpHeaders.contentTypeHeader, <String>[_contentType.toString()]);
    }
    _values.forEach(action);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
