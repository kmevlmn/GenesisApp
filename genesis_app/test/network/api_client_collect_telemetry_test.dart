import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/telemetry/genesis_telemetry.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/api_request_trace_sampling.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';

class _FakeTransport implements HttpTransport {
  _FakeTransport({required this.handler});

  final FutureOr<TransportResponse> Function(TransportRequest request) handler;

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    return handler(request);
  }
}

Map<String, Object?> _extData(CollectEvent event) {
  if (event.extData.isEmpty) return const <String, Object?>{};
  return Map<String, Object?>.from(jsonDecode(event.extData) as Map);
}

void main() {
  late MemoryCollectEventStore store;
  late CollectTelemetryUploader uploader;

  setUp(() {
    GenesisTelemetry.resetForTesting();
    ApiRequestTraceSampling.resetForTesting();
    ApiRequestTraceSampling.configureForLaunch(1, randomValue: 0);
    store = MemoryCollectEventStore();
    var nextEventId = 1;
    uploader = CollectTelemetryUploader(
      store: store,
      idGenerator: () => 'collect-event-${nextEventId++}',
    )..configure(enabled: true);
    GenesisTelemetry.setCollectUploaderForTesting(uploader);
  });

  tearDown(() async {
    await uploader.waitForPendingWrites();
    ApiRequestTraceSampling.resetForTesting();
    GenesisTelemetry.resetForTesting();
  });

  Future<List<CollectEvent>> events() async {
    await uploader.waitForPendingWrites();
    return store.eventsForTesting;
  }

  for (final stage in ['headers', 'interceptor']) {
    test(
      '$stage deadline records one timeout terminal even after late completion',
      () async {
        final release = Completer<void>();
        final lateFinished = Completer<void>();
        var sends = 0;
        final client = ApiClient(
          baseUrl: 'https://example.test/',
          timeoutMs: 40,
          transport: _FakeTransport(
            handler: (_) {
              sends++;
              return const TransportResponse(
                statusCode: 200,
                headers: {},
                body: '{}',
              );
            },
          ),
          requestHeaderProvider: stage == 'headers'
              ? () async {
                  await release.future;
                  lateFinished.complete();
                  return {};
                }
              : null,
          requestInterceptor: stage == 'interceptor'
              ? (request, send) async {
                  await release.future;
                  try {
                    return await send(request);
                  } finally {
                    lateFinished.complete();
                  }
                }
              : null,
        );
        await expectLater(
          client.post('/api/v1/example'),
          throwsA(isA<ApiException>()),
        );
        release.complete();
        await lateFinished.future;
        final recorded = await events();
        expect(recorded.map((e) => e.action), [
          'api_req_start',
          'api_req_fail_tech',
        ]);
        expect(recorded.last.object3, 'tech_client_1004');
        expect(sends, 0);
      },
    );
  }

  test(
    'outer deadline keeps transport duration separate from Gateway preparation',
    () async {
      final transportEntered = Completer<void>();
      final client = ApiClient(
        baseUrl: 'https://example.test/',
        timeoutMs: 1000,
        requestInterceptor: (request, send) async {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          return send(request);
        },
        transport: _FakeTransport(
          handler: (_) {
            transportEntered.complete();
            return Completer<TransportResponse>().future;
          },
        ),
      );
      final checked = expectLater(
        client.post('/api/v1/example'),
        throwsA(isA<ApiException>()),
      );
      await transportEntered.future;
      await checked;
      final recorded = await events();
      expect(recorded.map((e) => e.action), [
        'api_req_start',
        'api_req_fail_tech',
      ]);
      expect(recorded.last.object3, 'tech_client_1004');
      // The request waited about 1s overall, but the actual send used only the
      // remaining half of that budget. Preparation must not inflate object4.
      expect(int.parse(recorded.last.object4), inInclusiveRange(200, 800));
    },
  );

  test('successful business request emits start and success', () async {
    final client = ApiClient(
      baseUrl: 'https://example.test/api/',
      transport: _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":0,"data":{"ok":true}}',
        ),
      ),
    );

    await client.get<Object?>(
      'v1/world/list',
      query: const {'token': 'secret', 'page': 2},
    );

    final recorded = await events();
    expect(recorded.map((event) => event.action), <String>[
      'api_req_start',
      'api_req_success',
    ]);
    expect(recorded.map((event) => event.object1).toSet(), {
      '/api/v1/world/list',
    });
    expect(recorded.first.object2, isNotEmpty);
    expect(recorded.last.object2, recorded.first.object2);
    expect(recorded.first.object3, isEmpty);
    expect(recorded.first.object4, '0');
    expect(recorded.last.object3, isEmpty);
    expect(int.tryParse(recorded.last.object4), isNotNull);
  });

  test(
    'automatic retry followed by success emits one terminal event',
    () async {
      var attempts = 0;
      final client = ApiClient(
        baseUrl: 'https://example.test/api/',
        retryPolicy: ApiRetryPolicy.safe,
        transport: _FakeTransport(
          handler: (_) async {
            attempts += 1;
            if (attempts == 1) {
              await Future<void>.delayed(const Duration(milliseconds: 300));
              throw TimeoutException('slow');
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return const TransportResponse(
              statusCode: 200,
              headers: {'content-type': 'application/json'},
              body: '{"err_no":0,"data":{}}',
            );
          },
        ),
      );

      await client.get<Object?>('v1/profile');

      expect(attempts, 2);
      final recorded = await events();
      expect(recorded.map((event) => event.action), <String>[
        'api_req_start',
        'api_req_success',
      ]);
      expect(recorded.last.object2, recorded.first.object2);
      expect(int.parse(recorded.last.object4), lessThan(200));
    },
  );

  test(
    'a page-level retry records each logical request independently',
    () async {
      var shouldFail = true;
      final client = ApiClient(
        baseUrl: 'https://example.test/api/',
        transport: _FakeTransport(
          handler: (_) {
            if (shouldFail) throw Exception('connection reset');
            return const TransportResponse(
              statusCode: 200,
              headers: {'content-type': 'application/json'},
              body: '{"err_no":0,"data":{}}',
            );
          },
        ),
      );

      await expectLater(
        client.get<Object?>('v1/profile'),
        throwsA(isA<ApiException>()),
      );
      shouldFail = false;
      await client.get<Object?>('v1/profile');

      final recorded = await events();
      expect(recorded.map((event) => event.action), <String>[
        'api_req_start',
        'api_req_fail_tech',
        'api_req_start',
        'api_req_success',
      ]);
      final failure = recorded[1];
      expect(failure.actionType, 'monitor');
      expect(failure.object2, recorded.first.object2);
      expect(failure.object3, 'tech_client_1013');
      expect(int.tryParse(failure.object4), isNotNull);
      expect(_extData(failure), isEmpty);
    },
  );

  test('exhausted automatic retry reports one timeout failure', () async {
    var attempts = 0;
    final client = ApiClient(
      baseUrl: 'https://example.test/api/',
      retryPolicy: ApiRetryPolicy.safe,
      transport: _FakeTransport(
        handler: (_) {
          attempts += 1;
          throw TimeoutException('slow');
        },
      ),
    );

    await expectLater(
      client.get<Object?>('v1/profile'),
      throwsA(isA<ApiException>()),
    );

    final recorded = await events();
    expect(attempts, 2);
    expect(recorded.map((event) => event.action), <String>[
      'api_req_start',
      'api_req_fail_tech',
    ]);
    expect(recorded.last.object2, recorded.first.object2);
    expect(recorded.last.object3, 'tech_client_1004');
    expect(int.tryParse(recorded.last.object4), isNotNull);
    expect(_extData(recorded.last), <String, Object?>{'retry_count': 1});
  });

  test('HTTP and business failures use queryable scalar reasons', () async {
    var response = const TransportResponse(
      statusCode: 500,
      headers: {'content-type': 'application/json'},
      body: '{"message":"server error"}',
    );
    final client = ApiClient(
      baseUrl: 'https://example.test/api/',
      transport: _FakeTransport(handler: (_) => response),
    );

    await expectLater(
      client.get<Object?>('v1/world/detail'),
      throwsA(isA<ApiException>()),
    );
    response = const TransportResponse(
      statusCode: 200,
      headers: {'content-type': 'application/json'},
      body: '{"err_no":1001,"err_msg":"denied","data":{}}',
    );
    await client.get<Object?>('v1/world/detail');

    final recorded = await events();
    final technicalFailures = recorded
        .where((event) => event.action == 'api_req_fail_tech')
        .toList();
    final businessFailures = recorded
        .where((event) => event.action == 'api_req_fail_biz')
        .toList();
    expect(technicalFailures.single.object3, 'tech_http_500');
    expect(businessFailures.single.object3, 'biz_1001');
    expect(technicalFailures.single.object2, isNotEmpty);
    expect(businessFailures.single.object2, isNotEmpty);
    expect({
      technicalFailures.single.object2,
      businessFailures.single.object2,
    }, hasLength(2));
    expect(_extData(technicalFailures.single), <String, Object?>{
      'message': 'server error',
    });
    expect(_extData(businessFailures.single), <String, Object?>{
      'message': 'denied',
    });
    expect(
      recorded.where((event) => event.action == 'api_req_success'),
      isEmpty,
    );
  });

  test(
    'malformed JSON and response processing failures stay distinct',
    () async {
      var response = const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{invalid',
      );
      final client = ApiClient(
        baseUrl: 'https://example.test/api/',
        transport: _FakeTransport(handler: (_) => response),
      );

      await client.get<Object?>('v1/world/list');
      response = const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":0,"data":{}}',
      );
      await expectLater(
        client.get<Object?>(
          'v1/world/list',
          responseProcessor: (_) => throw StateError('mapping failed'),
        ),
        throwsStateError,
      );

      final failures = (await events())
          .where((event) => event.action == 'api_req_fail_tech')
          .toList();
      expect(failures.map((event) => _extData(event)['reason']), [
        'json_decode',
        'response_processing',
      ]);
      expect(failures.map((event) => event.object3), <String>[
        'tech_http_200',
        'tech_http_200',
      ]);
      expect(_extData(failures[0]), <String, Object?>{'reason': 'json_decode'});
      expect(_extData(failures[1])['message'], contains('mapping failed'));
    },
  );

  test('HTTP 200 invalid envelopes are technical failures', () async {
    var response = const TransportResponse(
      statusCode: 200,
      headers: {'content-type': 'application/json'},
      body: '{"data":{}}',
    );
    final client = ApiClient(
      baseUrl: 'https://example.test/api/',
      transport: _FakeTransport(handler: (_) => response),
    );

    await client.get<Object?>('v1/world/list');
    response = const TransportResponse(
      statusCode: 200,
      headers: {'content-type': 'application/json'},
      body: '{"err_no":"invalid","data":{}}',
    );
    await client.get<Object?>('v1/world/list');

    final failures = (await events())
        .where((event) => event.action == 'api_req_fail_tech')
        .toList();
    expect(failures.map((event) => event.object3), <String>[
      'tech_http_200',
      'tech_http_200',
    ]);
    expect(failures.map((event) => _extData(event)['reason']), <String>[
      'missing_err_no',
      'invalid_err_no',
    ]);
  });

  test('HTTP failure takes precedence over a body err_no', () async {
    final client = ApiClient(
      baseUrl: 'https://example.test/api/',
      transport: _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 503,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":10001,"err_msg":"not logged in"}',
        ),
      ),
    );

    await expectLater(
      client.get<Object?>('v1/profile'),
      throwsA(isA<ApiException>()),
    );

    final terminal = (await events()).last;
    expect(terminal.action, 'api_req_fail_tech');
    expect(terminal.object3, 'tech_http_503');
  });

  test('gateway auth and cancellation use their dedicated reasons', () async {
    final authClient = ApiClient(
      baseUrl: 'https://example.test/api/',
      requestHeaderProvider: () async => throw ApiException(
        message: 'auth unavailable',
        kind: ApiExceptionKind.gatewayAuth,
      ),
      transport: _FakeTransport(
        handler: (_) => throw StateError('transport must not run'),
      ),
    );
    await expectLater(
      authClient.get<Object?>('v1/profile'),
      throwsA(isA<ApiException>()),
    );

    final token = NetworkCancellationToken()..cancel();
    final cancelledClient = ApiClient(
      baseUrl: 'https://example.test/api/',
      transport: _FakeTransport(
        handler: (request) {
          request.cancellationToken?.throwIfCancelled();
          throw StateError('unreachable');
        },
      ),
    );
    await expectLater(
      cancelledClient.get<Object?>('v1/profile', cancellationToken: token),
      throwsA(isA<NetworkRequestCancelledException>()),
    );

    final failures = (await events())
        .where((event) => event.action == 'api_req_fail_tech')
        .toList();
    expect(failures.map((event) => event.object3), [
      'tech_client_1399',
      'tech_client_1030',
    ]);
    expect(_extData(failures[0]), <String, Object?>{
      'message': 'auth unavailable',
    });
    expect(_extData(failures[1]), isEmpty);
  });

  test('request preparation failures report the failing stage', () async {
    final headersClient = ApiClient(
      baseUrl: 'https://example.test/api/',
      requestHeaderProvider: () async => throw StateError('headers failed'),
      transport: _FakeTransport(
        handler: (_) => throw StateError('transport must not run'),
      ),
    );
    await expectLater(
      headersClient.get<Object?>('v1/profile'),
      throwsStateError,
    );

    final bodyClient = ApiClient(
      baseUrl: 'https://example.test/api/',
      transport: _FakeTransport(
        handler: (_) => throw StateError('transport must not run'),
      ),
    );
    await expectLater(
      bodyClient.post<Object?>('v1/profile', body: _ThrowingBody()),
      throwsStateError,
    );

    final apiUnknownClient = ApiClient(
      baseUrl: 'https://example.test/api/',
      requestHeaderProvider: () async =>
          throw ApiException(message: 'unclassified API failure'),
      transport: _FakeTransport(
        handler: (_) => throw StateError('transport must not run'),
      ),
    );
    await expectLater(
      apiUnknownClient.get<Object?>('v1/profile'),
      throwsA(isA<ApiException>()),
    );

    final failures = (await events())
        .where((event) => event.action == 'api_req_fail_tech')
        .toList();
    expect(failures.map((event) => event.object3), [
      'tech_client_1102',
      'tech_client_1103',
      'tech_client_1999',
    ]);
    expect(_extData(failures[0]), isEmpty);
    expect(_extData(failures[1]), isEmpty);
    expect(_extData(failures[2])['message'], 'unclassified API failure');
  });

  test('URI construction failures use their dedicated client code', () async {
    final client = ApiClient(
      baseUrl: 'https://example.test/api/',
      transport: _FakeTransport(
        handler: (_) => throw StateError('transport must not run'),
      ),
    );

    await expectLater(
      client.get<Object?>('v1/profile', query: {'bad': _ThrowingQueryValue()}),
      throwsStateError,
    );

    final recorded = await events();
    expect(recorded.map((event) => event.action), <String>[
      'api_req_start',
      'api_req_fail_tech',
    ]);
    expect(recorded.last.object1, '/api/v1/profile');
    expect(recorded.last.object3, 'tech_client_1101');
    expect(_extData(recorded.last), isEmpty);
  });

  test(
    'formerly unknown transport failures use stable subcategories',
    () async {
      for (final testCase in <({Object error, String reason})>[
        (
          error: Exception('certificate handshake failed'),
          reason: 'bad_certificate',
        ),
        (
          error: Exception(
            'HTTPS requires HTTP/2 or HTTP/3, but negotiated HTTP/1.1; '
            'uri=https://example.test/api/v1/profile?token=secret',
          ),
          reason: 'http_protocol',
        ),
        (
          error: Exception(
            'QuicException: protocol error, quicDetailedErrorCode=42',
          ),
          reason: 'http3_quic_42',
        ),
        (
          error: Exception('NetworkClientException: errorCode=6'),
          reason: 'cronet_6',
        ),
        (
          error: Exception('NSErrorClientException: code=-1009'),
          reason: 'ios_network_-1009',
        ),
        (
          error: Exception('DioException [connection error]: failed'),
          reason: 'dio_connection',
        ),
        (
          error: Exception('ClientException: invalid response'),
          reason: 'http_client',
        ),
        (
          error: StateError('transport state failed'),
          reason: 'transport_internal',
        ),
        (
          error: Exception('unexpected transport failure'),
          reason: 'transport_unknown',
        ),
      ]) {
        final client = ApiClient(
          baseUrl: 'https://example.test/api/',
          transport: _FakeTransport(handler: (_) => throw testCase.error),
        );
        await expectLater(
          client.get<Object?>('v1/profile'),
          throwsA(isA<ApiException>()),
        );
      }

      final failures = (await events())
          .where((event) => event.action == 'api_req_fail_tech')
          .toList();
      expect(failures.map((event) => event.object3), [
        'tech_client_1021',
        'tech_client_1015',
        'tech_client_1015',
        'tech_client_1019',
        'tech_client_1011',
        'tech_client_1019',
        'tech_client_1019',
        'tech_client_1999',
        'tech_client_1999',
      ]);
      expect(_extData(failures[1]), isEmpty);
      expect(_extData(failures[2])['native_code'], '42');
      expect(_extData(failures[3])['native_code'], '6');
      expect(_extData(failures[4])['native_code'], '-1009');
      expect(_extData(failures[7])['message'], contains('transport state'));
    },
  );

  test(
    'startup gateway endpoints are fixed-tracked while other paths stay excluded',
    () async {
      ApiRequestTraceSampling.resetForTesting();
      final transport = _FakeTransport(
        handler: (request) {
          final data = switch (request.uri.path) {
            '/apix/v1/time' => {'server_time_ms': 1},
            '/apix/v1/app/device/challenge' => {'register_id': 'register-1'},
            '/apix/v1/app/device/register' => {'key_id': 'key-1'},
            _ => <String, Object?>{},
          };
          return TransportResponse(
            statusCode: 200,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'err_no': 0, 'data': data}),
          );
        },
      );
      final gatewayClient = ApiClient(
        baseUrl: 'https://example.test/apix/',
        transport: transport,
      );

      await gatewayClient.get<Object?>('v1/time');
      await gatewayClient.post<Object?>('v1/app/device/challenge');
      await gatewayClient.post<Object?>('v1/app/device/register');
      await gatewayClient.get<Object?>('v1/heartbeat');
      await ApiClient(
        baseUrl: 'https://example.test/',
        transport: transport,
      ).get<Object?>('/aitown-chat/v1/message/list');
      await ApiClient(
        baseUrl: 'https://example.test/',
        transport: transport,
      ).get<Object?>('/assets/config.json');

      final recorded = await events();
      expect(recorded.map((event) => event.action), <String>[
        'api_req_start',
        'api_req_success',
        'api_req_start',
        'api_req_success',
        'api_req_start',
        'api_req_success',
      ]);
      expect(recorded.map((event) => event.object1), <String>[
        '/apix/v1/time',
        '/apix/v1/time',
        '/apix/v1/app/device/challenge',
        '/apix/v1/app/device/challenge',
        '/apix/v1/app/device/register',
        '/apix/v1/app/device/register',
      ]);
    },
  );

  test(
    'gateway dependency failure remains attributable from outer API',
    () async {
      final client = ApiClient(
        baseUrl: 'https://example.test/api/',
        requestInterceptor: (_, __) => throw ApiException(
          message: 'Gateway challenge failed',
          statusCode: 503,
          uri: Uri.parse('https://example.test/apix/v1/app/device/challenge'),
          kind: ApiExceptionKind.gatewayAuth,
          clientFailureCode: ApiClientFailureCode.gatewayRegistration,
        ),
        transport: _FakeTransport(
          handler: (_) => throw StateError('transport must not run'),
        ),
      );

      await expectLater(
        client.get<Object?>('v1/app/config'),
        throwsA(isA<ApiException>()),
      );

      final recorded = await events();
      expect(recorded.map((event) => event.action), <String>[
        'api_req_start',
        'api_req_fail_tech',
      ]);
      expect(recorded.last.object1, '/api/v1/app/config');
      expect(recorded.last.object3, 'tech_client_1304');
      expect(_extData(recorded.last), <String, Object?>{
        'message': 'Gateway challenge failed',
        'native_code': '503',
        'upstream_status': 503,
        'upstream_path': '/apix/v1/app/device/challenge',
      });
    },
  );

  test('business API latency excludes gateway preparation time', () async {
    final client = ApiClient(
      baseUrl: 'https://example.test/api/',
      requestInterceptor: (request, send) async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return send(request);
      },
      transport: _FakeTransport(
        handler: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body: '{"err_no":0,"data":{}}',
          );
        },
      ),
    );

    await client.get<Object?>('v1/app/config');

    final terminal = (await events()).last;
    expect(terminal.action, 'api_req_success');
    expect(int.parse(terminal.object4), lessThan(100));
  });

  test('chatroom and unrelated gateway paths are excluded', () async {
    final transport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":0,"data":{}}',
      ),
    );

    await ApiClient(
      baseUrl: 'https://example.test/apix/',
      transport: transport,
    ).get<Object?>('v1/heartbeat');
    await ApiClient(
      baseUrl: 'https://example.test/',
      transport: transport,
    ).get<Object?>('/aitown-chat/v1/message/list');
    await ApiClient(
      baseUrl: 'https://example.test/',
      transport: transport,
    ).get<Object?>('/assets/config.json');

    expect(await events(), isEmpty);
  });

  test('continuous message polling paths are excluded', () async {
    final requests = <Uri>[];
    final client = ApiClient(
      baseUrl: 'https://example.test/api/',
      transport: _FakeTransport(
        handler: (request) {
          requests.add(request.uri);
          return const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body: '{"err_no":0,"data":{}}',
          );
        },
      ),
    );

    await client.get<Object?>(
      'v1/message/unread',
      tracePolicy: ApiRequestTracePolicy.excluded,
    );
    await client.get<Object?>(
      'v1/direct_message/conversations',
      tracePolicy: ApiRequestTracePolicy.excluded,
    );
    await client.get<Object?>(
      'v1/direct_message/list',
      tracePolicy: ApiRequestTracePolicy.excluded,
    );

    expect(requests.map((uri) => uri.path), <String>[
      '/api/v1/message/unread',
      '/api/v1/direct_message/conversations',
      '/api/v1/direct_message/list',
    ]);
    expect(await events(), isEmpty);
  });

  test('successful non-polling direct message action is tracked', () async {
    final client = ApiClient(
      baseUrl: 'https://example.test/api/',
      transport: _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":0,"data":{}}',
        ),
      ),
    );

    await client.post<Object?>(
      'v1/direct_message/send',
      body: const {'peer_uid': 'user-1', 'content': 'hello'},
    );

    expect((await events()).map((event) => event.action), <String>[
      'api_req_start',
      'api_req_success',
    ]);
  });

  test(
    'ordinary requests are excluded when launch sampling is disabled',
    () async {
      ApiRequestTraceSampling.resetForTesting();
      final client = ApiClient(
        baseUrl: 'https://example.test/api/',
        transport: _FakeTransport(
          handler: (_) => const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body: '{"err_no":0,"data":{}}',
          ),
        ),
      );

      await client.get<Object?>('v1/world/list');

      expect(await events(), isEmpty);
    },
  );

  test(
    'global config is always tracked when launch sampling is disabled',
    () async {
      ApiRequestTraceSampling.resetForTesting();
      final client = ApiClient(
        baseUrl: 'https://example.test/api/',
        transport: _FakeTransport(
          handler: (_) => const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body: '{"err_no":0,"data":{"apiTraceSamplingRate":1}}',
          ),
        ),
      );

      await client.get<Object?>('v1/app/config');

      expect((await events()).map((event) => event.action), <String>[
        'api_req_start',
        'api_req_success',
      ]);
    },
  );

  test(
    'collect endpoint is always excluded from API request tracing',
    () async {
      final client = ApiClient(
        baseUrl: 'https://example.test/api/',
        transport: _FakeTransport(
          handler: (_) => const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body: '{"err_no":0,"data":{}}',
          ),
        ),
      );

      await client.post<Object?>('v1/collect', body: const {'events': []});
      await client.post<Object?>(
        '/api/v1/collect/',
        body: const {'events': []},
      );

      expect(await events(), isEmpty);
    },
  );
}

class _ThrowingBody {
  @override
  String toString() => throw StateError('body encoding failed');
}

class _ThrowingQueryValue {
  @override
  String toString() => throw StateError('query encoding failed');
}
