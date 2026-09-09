import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/telemetry/genesis_telemetry.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/gateway_auth.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/platform/device/device_id_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeKeyStore implements GatewayDeviceKeyStore {
  String? lastCanonical;
  int resetCount = 0;
  int failSignCount = 0;

  @override
  Future<String> publicKeyBase64Url() async => 'AQID';

  @override
  Future<String> signCanonical(String canonical) async {
    if (failSignCount > 0) {
      failSignCount -= 1;
      throw ApiException(message: 'Gateway signature is unavailable');
    }
    lastCanonical = canonical;
    return 'fake-signature';
  }

  @override
  Future<void> reset() async {
    resetCount += 1;
  }
}

class _MemoryGatewayRegistrationStore implements GatewayRegistrationStore {
  String? keyId;

  @override
  Future<void> clearKeyId() async {
    keyId = null;
  }

  @override
  Future<String?> readKeyId() async => keyId;

  @override
  Future<void> saveKeyId(String keyId) async {
    this.keyId = keyId;
  }
}

class _TestDeviceIdService implements DeviceIdService {
  const _TestDeviceIdService();

  @override
  Future<String> getDeviceId() async => 'test-device-id';
}

class _FakeTransport implements HttpTransport {
  _FakeTransport({required this.handler});

  final FutureOr<TransportResponse> Function(TransportRequest request) handler;
  final List<TransportRequest> requests = <TransportRequest>[];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return handler(request);
  }
}

void main() {
  late MemoryCollectEventStore collectStore;
  late CollectTelemetryUploader collectUploader;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GenesisTelemetry.resetForTesting();
    collectStore = MemoryCollectEventStore();
    collectUploader = CollectTelemetryUploader(store: collectStore)
      ..configure(enabled: true);
    GenesisTelemetry.setCollectUploaderForTesting(collectUploader);
  });

  tearDown(() async {
    await collectUploader.waitForPendingWrites();
    GenesisTelemetry.resetForTesting();
  });

  test('registration key ids are isolated by gateway environment', () async {
    expect(
      gatewayRegistrationNamespace('https://api.worldo.ai/apix/'),
      'https://api.worldo.ai',
    );
    final production = SharedPreferencesGatewayRegistrationStore(
      namespace: gatewayRegistrationNamespace('https://api.worldo.ai/apix/'),
    );
    final development = SharedPreferencesGatewayRegistrationStore(
      namespace: gatewayRegistrationNamespace(
        'https://dev-api.worldo.ai/apix/',
      ),
    );

    await production.saveKeyId('production-key');

    expect(await production.readKeyId(), 'production-key');
    expect(await development.readKeyId(), isNull);

    await development.saveKeyId('development-key');

    expect(await production.readKeyId(), 'production-key');
    expect(await development.readKeyId(), 'development-key');
  });

  test('canonical query sorts keys and repeated values', () {
    final uri = Uri.parse('https://gateway.test/api/v1/ping?z=2&a=1&a=0');

    expect(gatewayCanonicalQuery(uri), 'a=0&a=1&z=2');
  });

  test(
    'signed request matcher includes business API and chatroom API paths',
    () {
      expect(
        isGatewaySignedRequest(Uri.parse('https://x.test/api/v1/ping')),
        true,
      );
      expect(
        isGatewaySignedRequest(
          Uri.parse('https://x.test/aitown-chat/api/messages'),
        ),
        true,
      );
      expect(
        isGatewaySignedRequest(
          Uri.parse('https://x.test/aitown-chat/internal/tick/progress'),
        ),
        true,
      );
      expect(
        isGatewaySignedRequest(Uri.parse('https://x.test/apix/v1/time')),
        false,
      );
    },
  );

  test('signer adds Gateway headers and strips verified headers', () async {
    final keyStore = _FakeKeyStore();
    final request = TransportRequest(
      method: 'post',
      uri: Uri.parse('https://gateway.test/api/v1/ping?z=2&a=1'),
      headers: const {
        'content-type': 'application/json',
        'X-Verified-App-ID': 'spoofed',
      },
      bodyBytes: utf8.encode('{"a":1}'),
      timeoutMs: 15000,
      decodeResponseBody: false,
    );

    final signed = await const GatewayRequestSigner().sign(
      request,
      GatewaySigningContext(
        appId: 'hashed-app-id',
        platform: 'android',
        deviceId: 'android-id',
        appVersion: '1.0.0',
        keyId: 'key-1',
        serverTimeOffsetMs: 0,
        keyStore: keyStore,
      ),
    );

    expect(signed.headers['X-App-ID'], 'hashed-app-id');
    expect(signed.headers['X-Device-ID'], 'android-id');
    expect(signed.headers['X-App-Version'], '1.0.0');
    expect(signed.headers['X-Key-ID'], 'key-1');
    expect(signed.headers['X-Signature-Alg'], gatewaySignatureAlgorithm);
    expect(signed.headers['X-Signature'], 'fake-signature');
    expect(signed.decodeResponseBody, false);
    expect(signed.headers.containsKey('X-Verified-App-ID'), isFalse);
    expect(
      signed.headers['X-Body-SHA256'],
      gatewayBodySha256(utf8.encode('{"a":1}')),
    );
    expect(keyStore.lastCanonical, contains('\n\nhashed-app-id\n'));
  });

  test(
    'time sync exposes server UTC time for membership expiry checks',
    () async {
      final expectedTime = DateTime.utc(2040, 1, 1);
      final transport = _FakeTransport(
        handler: (_) => _json({
          'err_no': 0,
          'data': {'server_time_ms': expectedTime.millisecondsSinceEpoch},
        }),
      );
      final coordinator = GatewayAuthCoordinator(
        gatewayBaseUrl: 'https://gateway.test/apix/',
        appHeaderProvider: _testAppHeaders,
        deviceIdService: const _TestDeviceIdService(),
        keyStore: _FakeKeyStore(),
        registrationStore: _MemoryGatewayRegistrationStore(),
        transport: transport,
      );
      expect(coordinator.serverClock.now, isNull);
      await coordinator.syncServerTime();
      final actual = coordinator.serverClock.now!;
      expect(actual.isUtc, isTrue);
      expect(
        actual.difference(expectedTime).inMilliseconds,
        inInclusiveRange(0, 1000),
      );
      expect(transport.requests.single.uri.path, '/apix/v1/time');
    },
  );

  test('handshake signer adds Gateway headers for websocket connect', () async {
    final keyStore = _FakeKeyStore();
    final authTransport = _FakeTransport(handler: _gatewayAuthResponse);
    final coordinator = GatewayAuthCoordinator(
      gatewayBaseUrl: 'https://gateway.test/apix/',
      appHeaderProvider: _testAppHeaders,
      deviceIdService: const _TestDeviceIdService(),
      keyStore: keyStore,
      registrationStore: _MemoryGatewayRegistrationStore(),
      transport: authTransport,
    );

    final headers =
        await gatewayHandshakeHeaderSigner(coordinator: coordinator)(
          Uri.parse('wss://gateway.test/aitown-chat/ws?world_id=world-1'),
          const {'app-id': 'hashed-app-id', 'Authorization': 'Bearer token-1'},
        );

    expect(headers['Authorization'], 'Bearer token-1');
    expect(headers['X-App-ID'], 'hashed-app-id');
    expect(headers['X-Platform'], 'android');
    expect(headers['X-Device-ID'], 'test-device-id');
    expect(headers['X-App-Version'], '1.0.0');
    expect(headers['X-Key-ID'], 'key-registered');
    expect(headers['X-Signature-Alg'], gatewaySignatureAlgorithm);
    expect(headers['X-Signature'], 'fake-signature');
    expect(headers['X-Body-SHA256'], gatewayBodySha256(null));
    expect(headers.containsKey('X-Timestamp'), isTrue);
    expect(headers.containsKey('X-Nonce'), isTrue);
    expect(
      keyStore.lastCanonical,
      contains('/aitown-chat/ws\nworld_id=world-1'),
    );
  });

  test(
    'expired request leaves shared Gateway initialization available to another caller',
    () async {
      final release = Completer<void>();
      final entered = Completer<void>();
      final authTransport = _FakeTransport(
        handler: (request) async {
          if (request.uri.path == '/apix/v1/time') {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
          return _gatewayAuthResponse(request);
        },
      );
      final keyStore = _FakeKeyStore();
      final coordinator = GatewayAuthCoordinator(
        gatewayBaseUrl: 'https://gateway.test/apix/',
        appHeaderProvider: _testAppHeaders,
        deviceIdService: const _TestDeviceIdService(),
        keyStore: keyStore,
        registrationStore: _MemoryGatewayRegistrationStore(),
        transport: authTransport,
      );
      final business = _FakeTransport(
        handler: (_) => _json({'err_no': 0, 'data': {}}),
      );
      final client = ApiClient(
        baseUrl: 'https://gateway.test/',
        transport: business,
        timeoutMs: 50,
        requestInterceptor: GatewayRequestInterceptor(
          coordinator: coordinator,
        ).call,
      );
      final expired = expectLater(
        client.post('/api/v1/expired'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.transportErrorKind,
            'kind',
            TransportErrorKind.timeout,
          ),
        ),
      );
      await entered.future;
      final live = client.copyWith(timeoutMs: 5000).post('/api/v1/live');
      await expired;
      expect(business.requests, isEmpty);
      release.complete();
      await live;
      expect(business.requests.map((e) => e.uri.path), ['/api/v1/live']);
      expect(
        authTransport.requests.where((e) => e.uri.path == '/apix/v1/time'),
        hasLength(1),
      );
      expect(
        authTransport.requests.where(
          (e) => e.uri.path == '/apix/v1/app/device/register',
        ),
        hasLength(1),
      );
    },
  );

  test('interceptor syncs server time and retries once on 20502', () async {
    final keyStore = _FakeKeyStore();
    final authTransport = _FakeTransport(handler: _gatewayAuthResponse);
    final store = _MemoryGatewayRegistrationStore();
    final coordinator = GatewayAuthCoordinator(
      gatewayBaseUrl: 'https://gateway.test/apix/',
      appHeaderProvider: _testAppHeaders,
      deviceIdService: const _TestDeviceIdService(),
      keyStore: keyStore,
      registrationStore: store,
      transport: authTransport,
    );
    final interceptor = GatewayRequestInterceptor(coordinator: coordinator);
    var businessAttempts = 0;

    final response = await interceptor.call(
      TransportRequest(
        method: 'GET',
        uri: Uri.parse('https://gateway.test/api/v1/gateway/protected'),
        headers: const {},
        bodyBytes: null,
        timeoutMs: 15000,
        decodeResponseBody: false,
      ),
      (request) async {
        expect(request.decodeResponseBody, false);
        businessAttempts += 1;
        if (businessAttempts == 1) {
          return _json({
            'err_no': 20502,
            'err_msg': 'bad timestamp',
            'data': {},
          });
        }
        return _json({
          'err_no': 0,
          'err_msg': 'succ',
          'data': {'ok': true},
        });
      },
    );

    expect(gatewayErrNo(response.body), 0);
    expect(businessAttempts, 2);
    expect(
      authTransport.requests
          .where((request) => request.uri.path == '/apix/v1/time')
          .length,
      2,
    );
  });

  test('interceptor re-registers and retries once on 20504', () async {
    final keyStore = _FakeKeyStore();
    final authTransport = _FakeTransport(handler: _gatewayAuthResponse);
    final store = _MemoryGatewayRegistrationStore()..keyId = 'stale-key';
    final coordinator = GatewayAuthCoordinator(
      gatewayBaseUrl: 'https://gateway.test/apix/',
      appHeaderProvider: _testAppHeaders,
      deviceIdService: const _TestDeviceIdService(),
      keyStore: keyStore,
      registrationStore: store,
      transport: authTransport,
    );
    final interceptor = GatewayRequestInterceptor(coordinator: coordinator);
    var businessAttempts = 0;

    await interceptor.call(
      TransportRequest(
        method: 'GET',
        uri: Uri.parse('https://gateway.test/api/v1/gateway/protected'),
        headers: const {},
        bodyBytes: null,
        timeoutMs: 15000,
      ),
      (request) async {
        businessAttempts += 1;
        if (businessAttempts == 1) {
          return _json({
            'err_no': 20504,
            'err_msg': 'device missing',
            'data': {},
          });
        }
        return _json({
          'err_no': 0,
          'err_msg': 'succ',
          'data': {'ok': true},
        });
      },
    );

    expect(businessAttempts, 2);
    expect(keyStore.resetCount, 1);
    expect(store.keyId, 'key-registered');
    expect(
      authTransport.requests
          .where(
            (request) => request.uri.path == '/apix/v1/app/device/register',
          )
          .length,
      1,
    );
  });

  test('concurrent 20504 responses share one registration recovery', () async {
    final keyStore = _FakeKeyStore();
    final authTransport = _FakeTransport(handler: _gatewayAuthResponse);
    final store = _MemoryGatewayRegistrationStore()..keyId = 'stale-key';
    final coordinator = GatewayAuthCoordinator(
      gatewayBaseUrl: 'https://gateway.test/apix/',
      appHeaderProvider: _testAppHeaders,
      deviceIdService: const _TestDeviceIdService(),
      keyStore: keyStore,
      registrationStore: store,
      transport: authTransport,
    );
    final interceptor = GatewayRequestInterceptor(coordinator: coordinator);
    final bothStaleRequestsStarted = Completer<void>();
    var staleRequestCount = 0;

    Future<TransportResponse> send(TransportRequest request) async {
      if (request.headers['X-Key-ID'] == 'stale-key') {
        staleRequestCount += 1;
        if (staleRequestCount == 2) {
          bothStaleRequestsStarted.complete();
        }
        await bothStaleRequestsStarted.future;
        return _json({
          'err_no': 20504,
          'err_msg': 'device missing',
          'data': {},
        });
      }
      return _json({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {'ok': true},
      });
    }

    final responses = await Future.wait([
      interceptor.call(
        TransportRequest(
          method: 'GET',
          uri: Uri.parse('https://gateway.test/api/v1/first'),
          headers: const {},
          bodyBytes: null,
          timeoutMs: 15000,
        ),
        send,
      ),
      interceptor.call(
        TransportRequest(
          method: 'GET',
          uri: Uri.parse('https://gateway.test/api/v1/second'),
          headers: const {},
          bodyBytes: null,
          timeoutMs: 15000,
        ),
        send,
      ),
    ]);

    expect(
      responses.map((response) => gatewayErrNo(response.body)),
      everyElement(0),
    );
    expect(keyStore.resetCount, 1);
    expect(store.keyId, 'key-registered');
    expect(
      authTransport.requests
          .where(
            (request) => request.uri.path == '/apix/v1/app/device/challenge',
          )
          .length,
      1,
    );
    expect(
      authTransport.requests
          .where(
            (request) => request.uri.path == '/apix/v1/app/device/register',
          )
          .length,
      1,
    );
  });

  test(
    'interceptor re-runs registration flow once on signature errors',
    () async {
      final keyStore = _FakeKeyStore();
      final authTransport = _FakeTransport(handler: _gatewayAuthResponse);
      final store = _MemoryGatewayRegistrationStore()..keyId = 'stale-key';
      final coordinator = GatewayAuthCoordinator(
        gatewayBaseUrl: 'https://gateway.test/apix/',
        appHeaderProvider: _testAppHeaders,
        deviceIdService: const _TestDeviceIdService(),
        keyStore: keyStore,
        registrationStore: store,
        transport: authTransport,
      );
      final interceptor = GatewayRequestInterceptor(coordinator: coordinator);
      var businessAttempts = 0;

      await interceptor.call(
        TransportRequest(
          method: 'GET',
          uri: Uri.parse('https://gateway.test/api/v1/gateway/protected'),
          headers: const {},
          bodyBytes: null,
          timeoutMs: 15000,
        ),
        (request) async {
          businessAttempts += 1;
          if (businessAttempts == 1) {
            return _json({
              'err_no': 20505,
              'err_msg': 'bad signature',
              'data': {},
            });
          }
          return _json({
            'err_no': 0,
            'err_msg': 'succ',
            'data': {'ok': true},
          });
        },
      );

      expect(businessAttempts, 2);
      expect(keyStore.resetCount, 1);
      expect(store.keyId, 'key-registered');
      expect(
        authTransport.requests
            .where(
              (request) => request.uri.path == '/apix/v1/app/device/register',
            )
            .length,
        1,
      );
    },
  );

  test('prepare registers key and syncs time once for app startup', () async {
    final authTransport = _FakeTransport(handler: _gatewayAuthResponse);
    final store = _MemoryGatewayRegistrationStore();
    final coordinator = GatewayAuthCoordinator(
      gatewayBaseUrl: 'https://gateway.test/apix/',
      appHeaderProvider: _testAppHeaders,
      deviceIdService: const _TestDeviceIdService(),
      keyStore: _FakeKeyStore(),
      registrationStore: store,
      transport: authTransport,
    );

    await coordinator.prepare();
    await coordinator.prepare();

    expect(store.keyId, 'key-registered');
    expect(
      authTransport.requests.map((request) => request.uri.path),
      containsAllInOrder([
        '/apix/v1/app/device/challenge',
        '/apix/v1/app/device/register',
        '/apix/v1/time',
      ]),
    );
    expect(
      authTransport.requests
          .where(
            (request) => request.uri.path == '/apix/v1/app/device/register',
          )
          .length,
      1,
    );
    expect(
      authTransport.requests
          .where((request) => request.uri.path == '/apix/v1/time')
          .length,
      1,
    );
    await GenesisTelemetry.waitForCollectWritesForTesting();
    final interfaceEvents = collectStore.eventsForTesting;
    expect(interfaceEvents.map((event) => event.action), <String>[
      'api_req_start',
      'api_req_success',
      'api_req_start',
      'api_req_success',
      'api_req_start',
      'api_req_success',
    ]);
    expect(interfaceEvents.map((event) => event.object1), <String>[
      '/apix/v1/app/device/challenge',
      '/apix/v1/app/device/challenge',
      '/apix/v1/app/device/register',
      '/apix/v1/app/device/register',
      '/apix/v1/time',
      '/apix/v1/time',
    ]);
  });

  test('invalid challenge payload is reported on the challenge path', () async {
    final authTransport = _FakeTransport(
      handler: (_) => _json({'err_no': 0, 'err_msg': 'succ', 'data': {}}),
    );
    final coordinator = GatewayAuthCoordinator(
      gatewayBaseUrl: 'https://gateway.test/apix/',
      appHeaderProvider: _testAppHeaders,
      deviceIdService: const _TestDeviceIdService(),
      keyStore: _FakeKeyStore(),
      registrationStore: _MemoryGatewayRegistrationStore(),
      transport: authTransport,
    );

    await expectLater(
      coordinator.prepare(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.clientFailureCode,
          'clientFailureCode',
          ApiClientFailureCode.gatewayRegistration,
        ),
      ),
    );

    await GenesisTelemetry.waitForCollectWritesForTesting();
    final interfaceEvents = collectStore.eventsForTesting;
    expect(interfaceEvents.map((event) => event.action), <String>[
      'api_req_start',
      'api_req_fail_tech',
    ]);
    expect(interfaceEvents.last.object1, '/apix/v1/app/device/challenge');
    expect(interfaceEvents.last.object3, 'tech_http_200');
    final details = jsonDecode(interfaceEvents.last.extData) as Map;
    expect(details['reason'], 'response_processing');
    expect(
      details['message'],
      'Gateway challenge response missing register_id',
    );
  });

  test(
    'local signature failure resets key and re-registers before retry',
    () async {
      final keyStore = _FakeKeyStore()..failSignCount = 1;
      final authTransport = _FakeTransport(handler: _gatewayAuthResponse);
      final store = _MemoryGatewayRegistrationStore()..keyId = 'stale-key';
      final coordinator = GatewayAuthCoordinator(
        gatewayBaseUrl: 'https://gateway.test/apix/',
        appHeaderProvider: _testAppHeaders,
        deviceIdService: const _TestDeviceIdService(),
        keyStore: keyStore,
        registrationStore: store,
        transport: authTransport,
      );
      final interceptor = GatewayRequestInterceptor(coordinator: coordinator);
      var businessAttempts = 0;

      await interceptor.call(
        TransportRequest(
          method: 'GET',
          uri: Uri.parse('https://gateway.test/api/v1/gateway/protected'),
          headers: const {},
          bodyBytes: null,
          timeoutMs: 15000,
        ),
        (request) async {
          businessAttempts += 1;
          return _json({
            'err_no': 0,
            'err_msg': 'succ',
            'data': {'ok': true},
          });
        },
      );

      expect(businessAttempts, 1);
      expect(keyStore.resetCount, 1);
      expect(store.keyId, 'key-registered');
      expect(
        authTransport.requests
            .where(
              (request) => request.uri.path == '/apix/v1/app/device/register',
            )
            .length,
        1,
      );
    },
  );

  test(
    'server time offset is kept in memory and resynced by new coordinator',
    () async {
      final store = _MemoryGatewayRegistrationStore()..keyId = 'key-registered';
      final firstTransport = _FakeTransport(handler: _gatewayAuthResponse);
      final firstCoordinator = GatewayAuthCoordinator(
        gatewayBaseUrl: 'https://gateway.test/apix/',
        appHeaderProvider: _testAppHeaders,
        deviceIdService: const _TestDeviceIdService(),
        keyStore: _FakeKeyStore(),
        registrationStore: store,
        transport: firstTransport,
      );

      await firstCoordinator.signingContext();
      await firstCoordinator.signingContext();

      expect(
        firstTransport.requests
            .where((request) => request.uri.path == '/apix/v1/time')
            .length,
        1,
      );

      final secondTransport = _FakeTransport(handler: _gatewayAuthResponse);
      final secondCoordinator = GatewayAuthCoordinator(
        gatewayBaseUrl: 'https://gateway.test/apix/',
        appHeaderProvider: _testAppHeaders,
        deviceIdService: const _TestDeviceIdService(),
        keyStore: _FakeKeyStore(),
        registrationStore: store,
        transport: secondTransport,
      );

      await secondCoordinator.signingContext();

      expect(
        secondTransport.requests
            .where((request) => request.uri.path == '/apix/v1/time')
            .length,
        1,
      );
      expect(
        secondTransport.requests
            .where(
              (request) => request.uri.path == '/apix/v1/app/device/register',
            )
            .length,
        0,
      );
    },
  );

  test('verifyLocalSignature posts signed diagnostic request', () async {
    final keyStore = _FakeKeyStore();
    final authTransport = _FakeTransport(handler: _gatewayAuthResponse);
    final coordinator = GatewayAuthCoordinator(
      gatewayBaseUrl: 'https://gateway.test/apix/',
      appHeaderProvider: _testAppHeaders,
      deviceIdService: const _TestDeviceIdService(),
      keyStore: keyStore,
      registrationStore: _MemoryGatewayRegistrationStore(),
      transport: authTransport,
    );

    final response = await coordinator.verifyLocalSignature();
    final verifyRequest = authTransport.requests.last;

    expect(response.statusCode, 200);
    expect(response.prettyBody(), contains('"valid": true'));
    expect(
      verifyRequest.uri.toString(),
      'https://gateway.test/apix/v1/app/device/signature/verify',
    );
    expect(verifyRequest.method, 'POST');
    expect(utf8.decode(verifyRequest.bodyBytes!), '{}');
    expect(verifyRequest.headers['X-App-ID'], 'hashed-app-id');
    expect(verifyRequest.headers['X-Platform'], 'android');
    expect(verifyRequest.headers['X-Device-ID'], 'test-device-id');
    expect(verifyRequest.headers['X-App-Version'], '1.0.0');
    expect(verifyRequest.headers['X-Key-ID'], 'key-registered');
    expect(verifyRequest.headers['X-Signature'], 'fake-signature');
    expect(
      verifyRequest.headers['X-Body-SHA256'],
      gatewayBodySha256(utf8.encode('{}')),
    );
    expect(
      keyStore.lastCanonical,
      contains('/apix/v1/app/device/signature/verify'),
    );
  });
}

Future<Map<String, String>> _testAppHeaders() async {
  return const {
    'app-id': 'hashed-app-id',
    'app-platform': 'android',
    'app-version': '1.0.0',
  };
}

TransportResponse _gatewayAuthResponse(TransportRequest request) {
  switch (request.uri.path) {
    case '/apix/v1/time':
      return _json({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {'server_time_ms': DateTime.now().millisecondsSinceEpoch},
      });
    case '/apix/v1/app/device/challenge':
      return _json({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {
          'register_id': 'reg-1',
          'challenge': 'challenge',
          'expires_in': 300,
        },
      });
    case '/apix/v1/app/device/register':
      return _json({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {'key_id': 'key-registered'},
      });
    case '/apix/v1/app/device/signature/verify':
      return _json({
        'err_no': 0,
        'err_msg': 'succ',
        'data': {'valid': true},
      });
  }
  return _json({'err_no': 404, 'err_msg': 'unexpected', 'data': {}});
}

TransportResponse _json(Map<String, Object?> body) {
  return TransportResponse(
    statusCode: 200,
    headers: const {'content-type': 'application/json'},
    body: jsonEncode(body),
  );
}
