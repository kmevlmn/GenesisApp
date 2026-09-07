import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/config/app_config.dart';
import 'package:genesis_flutter_android/app/telemetry/firebase_analytics_monitoring.dart';
import 'package:genesis_flutter_android/app/telemetry/genesis_telemetry.dart';
import 'package:genesis_flutter_android/network/api_client.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/genesis_api.dart';
import 'package:genesis_flutter_android/network/gateway_auth.dart';
import 'package:genesis_flutter_android/network/models/gem_purchase_report.dart';
import 'package:genesis_flutter_android/network/http_transport.dart';
import 'package:genesis_flutter_android/network/local_mock_genesis_transport.dart';
import 'package:genesis_flutter_android/network/models/search_v2.dart';
import 'package:genesis_flutter_android/network/models/tilemap_definition.dart';
import 'package:genesis_flutter_android/network/v1/upload_api.dart';
import 'package:genesis_flutter_android/app/config/platform_config.dart';
import 'package:genesis_flutter_android/platform/auth/auth_session.dart';
import 'package:genesis_flutter_android/platform/auth/backend_auth_coordinator.dart';
import 'package:genesis_flutter_android/platform/auth/identity_auth_service.dart';
import 'package:genesis_flutter_android/platform/device/device_id_service.dart';
import 'package:genesis_flutter_android/platform/session/memory_user_session_store.dart';

class _FakeTransport implements HttpTransport {
  _FakeTransport({required this.handler});

  final FutureOr<TransportResponse> Function(TransportRequest request) handler;
  TransportRequest? lastRequest;
  final List<TransportRequest> requests = <TransportRequest>[];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    lastRequest = request;
    return handler(request);
  }
}

class _TestPlatformConfig implements PlatformConfig {
  const _TestPlatformConfig({this.apiBaseUrl = 'http://localhost:8080/api/'});

  @override
  final String apiBaseUrl;

  @override
  String get assetBaseUrl => GenesisApi.defaultAssetBaseUrl;
}

class _FakeGatewayKeyStore implements GatewayDeviceKeyStore {
  @override
  Future<String> publicKeyBase64Url() async => 'AQID';

  @override
  Future<void> reset() async {}

  @override
  Future<String> signCanonical(String canonical) async => 'fake-signature';
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

GenesisApi _apiWith(
  _FakeTransport apiTransport,
  _FakeTransport healthTransport, {
  MemoryUserSessionStore? sessionStore,
}) {
  final apiClient = ApiClient(
    baseUrl: 'http://localhost:8080/api/',
    defaultHeaders: const {
      'content-type': 'application/json',
      'accept': 'application/json',
    },
    transport: apiTransport,
    responseProcessor: (r) => ApiClient.defaultResponseProcessor(r),
  );

  final healthClient = ApiClient(
    baseUrl: 'http://localhost:8080/',
    defaultHeaders: const {'accept': 'application/json'},
    transport: healthTransport,
    responseProcessor: (r) => ApiClient.defaultResponseProcessor(r),
  );

  final resolvedSessionStore = sessionStore ?? MemoryUserSessionStore();
  if (sessionStore == null) {
    resolvedSessionStore.saveUid('u_1');
    resolvedSessionStore.saveAuthToken('test-auth-token');
  }
  return GenesisApi(
    apiClient: apiClient,
    healthClient: healthClient,
    deviceIdService: const _TestDeviceIdService(),
    sessionStore: resolvedSessionStore,
  );
}

void main() {
  test('AppConfig switches production and mock network environments', () {
    expect(const AppConfig().useMock, false);
    expect(const AppConfig(apiEnvironment: 'mock').useMock, true);
    expect(const AppConfig(apiEnvironment: 'production').useMock, false);
    expect(
      const AppConfig(apiEnvironment: 'production', useMock: true).useMock,
      true,
    );
  });

  test('AppConfig endpoint defaults follow build mode defaults', () {
    expect(const AppConfig().apiBaseUrl, GenesisApi.defaultApiBaseUrl);
    expect(
      const AppConfig().gatewayApiBaseUrl,
      GenesisApi.defaultGatewayApiBaseUrl,
    );
    expect(
      const AppConfig().chatroomHttpBaseUrl,
      GenesisApi.defaultChatroomHttpBaseUrl,
    );
    expect(
      const AppConfig().chatroomWsBaseUrl,
      GenesisApi.defaultChatroomWsBaseUrl,
    );
  });

  test('GenesisApi retries a retryable business GET once by default', () async {
    var attempts = 0;
    final transport = _FakeTransport(
      handler: (_) {
        attempts += 1;
        if (attempts == 1) throw Exception('connection closed');
        return const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body:
              '{"err_no":0,"err_msg":"succ","data":{"user":{"uid":"u_retry"},"relation":{}}}',
        );
      },
    );
    final api = GenesisApi(
      useMock: false,
      transport: transport,
      platformConfig: const _TestPlatformConfig(),
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: MemoryUserSessionStore(),
      appHeaderProvider: () async => const <String, String>{},
    );

    final result = await api.v1.user.info(uid: 'u_retry');

    expect((result['user'] as Map)['uid'], 'u_retry');
    expect(attempts, 2);
  });

  test('AppConfig provides default version check app id and channel', () {
    expect(const AppConfig().appId, 'aitown');
    expect(const AppConfig().appChannel, 'default');
  });

  test('AppConfig provides default agent control config', () {
    expect(const AppConfig().agentControlEnabled, false);
    expect(const AppConfig().agentControlPort, 17317);
    expect(const AppConfig().agentControlToken, '');
  });

  test('AppConfig copies agent control config', () {
    final config = const AppConfig().copyWith(
      agentControlEnabled: true,
      agentControlPort: 18080,
      agentControlToken: 'secret',
    );

    expect(config.agentControlEnabled, true);
    expect(config.agentControlPort, 18080);
    expect(config.agentControlToken, 'secret');
  });

  test('resolveAssetUrl keeps predata default CDN images as remote URLs', () {
    expect(
      resolveAssetUrl('https://cdn-001.worldo.ai/predata/root_default.webp'),
      'https://cdn-001.worldo.ai/predata/root_default.webp',
    );
    expect(
      resolveAssetUrl('https://cdn-001.worldo.ai/predata/l1_default.webp'),
      'https://cdn-001.worldo.ai/predata/l1_default.webp',
    );
    expect(
      resolveAssetUrl('https://cdn-001.worldo.ai/predata/l2_default.webp'),
      'https://cdn-001.worldo.ai/predata/l2_default.webp',
    );
    expect(
      resolveAssetUrl(
        'https://cdn-001.worldo.ai/predata/location_default.webp',
      ),
      'https://cdn-001.worldo.ai/predata/location_default.webp',
    );
  });

  test(
    'v1 app version check posts documented body and parses response',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body:
              '{"err_no":0,"err_msg":"succ","data":{"need_upgrade":true,"force_upgrade":true,"latest_version_name":"1.1.0","latest_version_code":"10100","min_version_code":"10000","upgrade_type":"2","title":"发现新版本","content":"请升级","download_url":"https://example.com/app.apk","store_url":"https://apps.apple.com/app/id000000","package_size":"0","package_md5":"","can_ignore":false}}',
        ),
      );
      final api = _apiWith(
        apiTransport,
        _FakeTransport(
          handler: (_) => const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body: '{"status":"ok"}',
          ),
        ),
      );

      final response = await api.v1.app.versionCheck(
        appId: 'aitown',
        platform: 'ios',
        channel: 'appstore',
        versionName: '1.0.0',
        versionCode: 10000,
        deviceId: 'device_xxx',
        uid: 'u_4LA63V',
      );

      expect(apiTransport.lastRequest!.method, 'POST');
      expect(
        apiTransport.lastRequest!.uri.toString(),
        'http://localhost:8080/api/v1/app/version/check',
      );
      expect(jsonDecode(utf8.decode(apiTransport.lastRequest!.bodyBytes!)), {
        'app_id': 'aitown',
        'platform': 'ios',
        'channel': 'appstore',
        'version_name': '1.0.0',
        'version_code': 10000,
        'device_id': 'device_xxx',
        'uid': 'u_4LA63V',
      });
      expect(response.shouldForceUpgrade, true);
      expect(response.latestVersionCode, 10100);
      expect(response.minVersionCode, 10000);
      expect(response.upgradeType, 2);
      expect(response.updateUrl, 'https://apps.apple.com/app/id000000');
    },
  );

  test('v1 app config gets documented path and returns global flags', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"show_opening_sheet":true}}',
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final config = await api.v1.app.config(uid: 'u_startup');

    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/app/config');
    expect(apiTransport.lastRequest!.uri.queryParameters['uid'], 'u_startup');
    expect(apiTransport.lastRequest!.bodyBytes, isNull);
    expect(config['show_opening_sheet'], isTrue);
  });

  test('v1 app config omits uid for an anonymous startup', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":0,"err_msg":"succ","data":{}}',
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    await api.v1.app.config();

    expect(apiTransport.lastRequest!.uri.queryParameters, isEmpty);
  });

  test(
    'local mock returns business errors through err_no on HTTP 200',
    () async {
      final response = await LocalMockGenesisTransport.instance.send(
        TransportRequest(
          method: 'POST',
          uri: Uri.parse('https://example.test/api/v1/report/create'),
          headers: const {'content-type': 'application/json'},
          bodyBytes: utf8.encode(
            jsonEncode({
              'target_type': 'unsupported',
              'target_id': 'target_1',
              'content': 'content',
            }),
          ),
          timeoutMs: 1000,
        ),
      );

      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), containsPair('err_no', 20801));
    },
  );

  test(
    'v1 app version check throws ApiException for non-zero err_no',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":4004,"err_msg":"ErrorParamInvalid","data":{}}',
        ),
      );
      final api = _apiWith(
        apiTransport,
        _FakeTransport(
          handler: (_) => const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body: '{"status":"ok"}',
          ),
        ),
      );

      expect(
        () => api.v1.app.versionCheck(
          appId: 'aitown',
          platform: 'ios',
          channel: 'default',
          versionCode: 1,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('v1 gem product and task lists parse their independent endpoints', () async {
    final apiTransport = _FakeTransport(
      handler: (request) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: request.uri.path.endsWith('/products')
            ? '{"err_no":0,"err_msg":"succ","data":{"list":[{"product_id":"gem_pack_500","apple_product_id":"com.worldo.gems.500","google_product_id":"worldo_gems_500","base_gems_cent":50000,"bonus_gems_cent":5000,"price_currency_code":"USD","price_amount":149,"can_purchase":true,"activity_type":"first_purchase_bonus","activity_text":"First Top-up","activity_color":"#E85C39","activity_ext":{"google_purchase_option_id":"500-gems-new","google_offer_id":"500-gems-new-discount"}}]}}'
            : '{"err_no":0,"err_msg":"succ","data":{"list":[{"group_code":"daily","group_title":"Daily","tasks":[{"task_code":"send_message","title":"Send a message (0/3)","description":"Send messages in a location chat today.","reward_gems_cent":5000,"reward_valid_days":30,"cycle_type":"daily","cycle_key":"today","progress":0,"target_count":3,"progress_text":"0/3","status":"in_progress","action_text":"Go"}]}]}}',
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final products = await api.v1.gem.products();
    final tasks = await api.v1.gem.tasks();

    expect(apiTransport.requests.map((request) => request.uri.path), [
      '/api/v1/gem/products',
      '/api/v1/gem/tasks',
    ]);
    expect(products.products.single.productId, 'gem_pack_500');
    expect(products.products.single.googlePurchaseOptionId, '500-gems-new');
    expect(products.products.single.googleOfferId, '500-gems-new-discount');
    expect(products.products.single.totalGemsCent, 55000);
    expect(products.products.single.activityType, 'first_purchase_bonus');
    expect(products.products.single.tagText, 'First Top-up');
    expect(products.products.single.activityColor, '#E85C39');
    expect(tasks.groups.single.groupTitle, 'Daily');
    expect(tasks.groups.single.tasks.single.taskCode, 'send_message');
    expect(tasks.groups.single.tasks.single.cycleKey, 'today');
    expect(tasks.groups.single.tasks.single.actionText, 'Go');
  });

  test('v1 unread summary coalesces concurrent requests', () async {
    final unreadCompleter = Completer<TransportResponse>();
    var unreadResponseCount = 0;
    final apiTransport = _FakeTransport(
      handler: (request) {
        if (request.uri.path == '/api/v1/message/unread') {
          unreadResponseCount += 1;
          if (unreadResponseCount == 1) return unreadCompleter.future;
        }
        return const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body:
              '{"err_no":0,"err_msg":"succ","data":{"world_apply_unread":1,"follow_unread":1,"interaction_unread":1,"direct_message_unread":1,"total_unread":4}}',
        );
      },
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final first = api.v1.messages.unreadSummary();
    final second = api.v1.messages.unreadSummary();
    await Future<void>.delayed(Duration.zero);

    expect(
      apiTransport.requests
          .where((request) => request.uri.path == '/api/v1/message/unread')
          .length,
      1,
    );

    unreadCompleter.complete(
      const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"world_apply_unread":1,"follow_unread":1,"interaction_unread":1,"direct_message_unread":1,"total_unread":4}}',
      ),
    );
    final summaries = await Future.wait([first, second]);
    expect(summaries.map((summary) => summary.totalUnread), [4, 4]);

    await api.v1.messages.unreadSummary();

    expect(
      apiTransport.requests
          .where((request) => request.uri.path == '/api/v1/message/unread')
          .length,
      2,
    );
  });

  test('v1 gem wallet parses the server balance', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"wallet":{"balance_cent":98000}}}',
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final wallet = await api.v1.gem.wallet();

    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/gem/wallet');
    expect(wallet.balanceCent, 98000);
  });

  test('v1 gem model list and selection send current world context', () async {
    final apiTransport = _FakeTransport(
      handler: (request) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: request.method == 'GET'
            ? '{"err_no":0,"err_msg":"succ","data":{"selected_model_code":"top_pick_v3","list":[{"group_code":"recommended","group_title":"Recommended","models":[{"model_code":"top_pick_v3","title":"Top Pick V3","tag":["hot"],"estimated_next_message_gems_cent":400,"estimated_next_tick_gems_cent":400,"description":"Balanced storytelling.","range_text":"4-320 gems"}]}]}}'
            : '{"err_no":0,"err_msg":"succ","data":{"selected_model_code":"sake_pro"}}',
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final catalog = await api.v1.gem.models(worldId: 'W_000001');
    final selection = await api.v1.gem.selectModel(
      worldId: 'W_000001',
      modelCode: 'sake_pro',
    );

    final listRequest = apiTransport.requests.first;
    expect(listRequest.method, 'GET');
    expect(listRequest.uri.path, '/api/v1/gem/model/list');
    expect(listRequest.uri.queryParameters, {'world_id': 'W_000001'});
    expect(catalog.selectedModelCode, 'top_pick_v3');
    expect(catalog.groups.single.groupTitle, 'Recommended');
    expect(catalog.groups.single.models.single.tags, ['hot']);
    expect(
      catalog.groups.single.models.single.estimatedNextMessageGemsCent,
      400,
    );

    final selectRequest = apiTransport.requests.last;
    expect(selectRequest.method, 'POST');
    expect(selectRequest.uri.path, '/api/v1/gem/model/select');
    expect(jsonDecode(utf8.decode(selectRequest.bodyBytes!)), {
      'world_id': 'W_000001',
      'model_code': 'sake_pro',
    });
    expect(selection.selectedModelCode, 'sake_pro');
  });

  test('v1 gem task report and claim send only task_code', () async {
    final apiTransport = _FakeTransport(
      handler: (request) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: request.uri.path.endsWith('/report')
            ? '{"err_no":0,"err_msg":"succ","data":{"status":"claimable"}}'
            : '{"err_no":0,"err_msg":"succ","data":{"status":"claimed"}}',
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final reported = await api.v1.gem.reportTask('discord_follow');
    final claimed = await api.v1.gem.claimTask('discord_follow');

    expect(reported.status, 'claimable');
    expect(claimed.status, 'claimed');
    expect(apiTransport.requests.map((request) => request.uri.path), [
      '/api/v1/gem/task/report',
      '/api/v1/gem/task/claim',
    ]);
    for (final request in apiTransport.requests) {
      expect(jsonDecode(utf8.decode(request.bodyBytes!)), {
        'task_code': 'discord_follow',
      });
    }
  });

  test('v1 gem records parses ledger items and sends scene query', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"list":[{"ledger_id":"gl_1","amount_cent":-2000,"scene":"world_tick","reason_code":"message","title":"Message","subtitle":"Location chat","world_name":"Thorn Haven","world_id":"w_1","order_id":"ord_1","created_at":1783586400,"expires_at":0}],"total":1,"pn":1,"rn":20}}',
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final records = await api.v1.gem.records(scene: 'spent', pn: 1, rn: 20);

    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/gem/records');
    expect(apiTransport.lastRequest!.uri.queryParameters['scene'], 'spent');
    expect(apiTransport.lastRequest!.uri.queryParameters['pn'], '1');
    expect(records.total, 1);
    expect(records.items.single.ledgerId, 'gl_1');
    expect(records.items.single.amountCent, -2000);
    expect(records.items.single.title, 'Message');
    expect(records.items.single.worldName, 'Thorn Haven');
    expect(records.items.single.worldId, 'w_1');
    expect(records.items.single.orderId, 'ord_1');
  });

  test('v1 gem purchase report posts the Google purchase payload', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"status":"completed","granted_gems_cent":55000,"transaction_id":"GPA.1"}}',
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final report = await api.v1.gem.reportPurchase(
      const GemPurchaseReportRequest(
        provider: 'google',
        productId: 'gem_pack_500',
        storeProductId: 'worldo_gems_500',
        transactionId: 'GPA.1',
        purchaseToken: 'purchase-token-1',
        requestId: 'pay_1',
      ),
    );

    expect(apiTransport.lastRequest!.method, 'POST');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/gem/purchase/report');
    expect(jsonDecode(utf8.decode(apiTransport.lastRequest!.bodyBytes!)), {
      'provider': 'google',
      'environment': 'unknown',
      'product_id': 'gem_pack_500',
      'store_product_id': 'worldo_gems_500',
      'transaction_id': 'GPA.1',
      'purchase_token': 'purchase-token-1',
      'request_id': 'pay_1',
    });
    expect(report.status, GemPurchaseReportStatus.completed);
    expect(report.grantedGemsCent, 55000);
    expect(report.transactionId, 'GPA.1');
  });

  test(
    'v1 gem wallet rejects a missing balance_cent instead of using zero',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":0,"err_msg":"succ","data":{"wallet":{}}}',
        ),
      );
      final api = _apiWith(
        apiTransport,
        _FakeTransport(
          handler: (_) => const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body: '{"status":"ok"}',
          ),
        ),
      );

      await expectLater(api.v1.gem.wallet(), throwsA(isA<FormatException>()));
    },
  );

  test('bindDevice validates a complete local session with user info', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"user":{"uid":"u_1","name":"n","avatar":"a"},"relation":{"is_self":true},"uuid":"4b74ec68-7abc-4cce-a223-e997e31dc811"}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUid('u_1');
    await sessionStore.saveAuthToken('backend-token');
    final api = _apiWith(
      apiTransport,
      healthTransport,
      sessionStore: sessionStore,
    );
    final user = await api.bindDevice(did: 'd1');

    expect(apiTransport.lastRequest!.method, 'GET');
    expect(
      apiTransport.lastRequest!.uri.toString(),
      'http://localhost:8080/api/v1/user/info?uid=u_1',
    );
    expect(
      apiTransport.lastRequest!.headers['authorization'],
      'Bearer backend-token',
    );
    expect(user.uid, 'u_1');
  });

  test(
    'bindDevice skips user info and preserves local state when uid is missing',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => throw StateError('user info must not be requested'),
      );
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveAuthToken('orphaned-token');
      await sessionStore.saveUserInfo({'name': 'stale user'});
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
      );

      final user = await api.bindDevice(did: 'd1');

      expect(user.uid, isEmpty);
      expect(apiTransport.requests, isEmpty);
      expect(await sessionStore.readUid(), isNull);
      expect(await sessionStore.readAuthToken(), 'orphaned-token');
      expect(await sessionStore.readUserInfo(), {'name': 'stale user'});
    },
  );

  test('v1 user info keeps UUID and selected model alongside user', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"user":{"uid":"u_1","name":"n"},"relation":{"is_self":true},"uuid":"4b74ec68-7abc-4cce-a223-e997e31dc811","selected_model_code":"top_pick_v3"}}',
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final response = await api.v1.user.info();

    expect(response['uuid'], '4b74ec68-7abc-4cce-a223-e997e31dc811');
    expect(response['selected_model_code'], 'top_pick_v3');
    expect((response['user'] as Map).containsKey('uuid'), isFalse);
    expect(
      (response['user'] as Map).containsKey('selected_model_code'),
      isFalse,
    );
    expect(apiTransport.lastRequest!.uri.queryParameters['uid'], 'u_1');
    expect(
      apiTransport.lastRequest!.headers['authorization'],
      'Bearer test-auth-token',
    );
  });

  test(
    'current user info keeps uid and authorization from one session snapshot',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body:
              '{"err_no":0,"err_msg":"succ","data":{"user":{"uid":"u_snapshot"},"relation":{"is_self":true}}}',
        ),
      );
      final sessionStore = _SecondAuthTokenReadThrowsSessionStore();
      await sessionStore.saveUid('u_snapshot');
      await sessionStore.saveAuthToken('snapshot-token');
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
      );

      final response = await api.v1.user.info();

      expect((response['user'] as Map)['uid'], 'u_snapshot');
      expect(
        apiTransport.lastRequest!.uri.queryParameters['uid'],
        'u_snapshot',
      );
      expect(
        apiTransport.lastRequest!.headers['authorization'],
        'Bearer snapshot-token',
      );
    },
  );

  test(
    'current user info rejects an anonymous public profile response',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body:
              '{"err_no":0,"err_msg":"succ","data":{"user":{"uid":"u_1"},"relation":{"is_self":false}}}',
        ),
      );
      final api = _apiWith(
        apiTransport,
        _FakeTransport(
          handler: (_) => const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body: '{"status":"ok"}',
          ),
        ),
      );

      await expectLater(
        api.v1.user.info(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', isNull)
              .having(
                (error) => error.kind,
                'kind',
                ApiExceptionKind.gatewayAuth,
              ),
        ),
      );
    },
  );

  test('current user info skips transport when local uid is missing', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => throw StateError('user info must not be requested'),
    );
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveAuthToken('orphaned-token');
    final api = GenesisApi(
      transport: apiTransport,
      useMock: false,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: sessionStore,
    );

    await expectLater(
      api.v1.user.info(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Authentication is required',
        ),
      ),
    );

    expect(apiTransport.requests, isEmpty);
    expect(await sessionStore.readAuthToken(), 'orphaned-token');
  });

  test(
    'current user info skips transport when auth token is missing',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => throw StateError('user info must not be requested'),
      );
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveUid('u_orphaned');
      await sessionStore.saveUserInfo({'uid': 'u_orphaned'});
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
      );

      await expectLater(
        api.v1.user.info(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            'Authentication is required',
          ),
        ),
      );

      expect(apiTransport.requests, isEmpty);
      expect(await sessionStore.readUid(), 'u_orphaned');
      expect(await sessionStore.readUserInfo(), {'uid': 'u_orphaned'});
    },
  );

  test(
    'current user info does not clear session when storage read fails',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => throw StateError('user info must not be requested'),
      );
      final sessionStore = _ThrowingAuthTokenSessionStore();
      await sessionStore.saveUid('u_1');
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
      );

      await expectLater(api.v1.user.info(), throwsStateError);

      expect(apiTransport.requests, isEmpty);
      expect(sessionStore.clearCount, 0);
      expect(await sessionStore.readUid(), 'u_1');
    },
  );

  test('public user info remains available with an explicit uid', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"user":{"uid":"u_public"}}}',
      ),
    );
    final api = GenesisApi(
      transport: apiTransport,
      useMock: false,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: MemoryUserSessionStore(),
    );

    await api.v1.user.info(uid: 'u_public');

    expect(apiTransport.requests, hasLength(1));
    expect(apiTransport.requests.single.uri.queryParameters['uid'], 'u_public');
  });

  test('v1 user World History settings use GET PUT and DELETE contract', () async {
    final apiTransport = _FakeTransport(
      handler: (request) {
        final responseData = switch (request.method) {
          'PUT' =>
            '{"high_watermark":28,"low_watermark":12,"stored_high_watermark":28,"stored_low_watermark":12,"source":"stored","degraded":false}',
          _ =>
            '{"high_watermark":25,"low_watermark":15,"stored_high_watermark":0,"stored_low_watermark":0,"source":"default","degraded":false}',
        };
        return TransportResponse(
          statusCode: 200,
          headers: const {'content-type': 'application/json'},
          body: '{"err_no":0,"err_msg":"succ","data":$responseData}',
        );
      },
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final fetched = await api.v1.user.worldHistorySettings();
    final updated = await api.v1.user.updateWorldHistorySettings(
      highWatermark: 28,
      lowWatermark: 12,
    );
    final reset = await api.v1.user.resetWorldHistorySettings();

    expect(fetched.highWatermark, 25);
    expect(fetched.lowWatermark, 15);
    expect(fetched.storedHighWatermark, 0);
    expect(fetched.source, 'default');
    expect(updated.highWatermark, 28);
    expect(updated.lowWatermark, 12);
    expect(updated.storedLowWatermark, 12);
    expect(updated.source, 'stored');
    expect(reset.highWatermark, 25);
    expect(reset.degraded, isFalse);
    expect(apiTransport.requests.map((request) => request.method), [
      'GET',
      'PUT',
      'DELETE',
    ]);
    expect(
      apiTransport.requests.map((request) => request.uri.path),
      List<String>.filled(3, '/api/v1/user/world-history-settings'),
    );
    expect(jsonDecode(utf8.decode(apiTransport.requests[1].bodyBytes!)), {
      'high_watermark': 28,
      'low_watermark': 12,
    });
    expect(apiTransport.requests[2].bodyBytes, isNull);
  });

  test('bindDevice ignores but preserves a legacy guest uid', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 500,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":500,"err_msg":"server error","data":{}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUid('guest_old');
    final apiClient = ApiClient(
      baseUrl: 'http://localhost:8080/api/',
      defaultHeaders: const {
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      transport: apiTransport,
      responseProcessor: (r) => ApiClient.defaultResponseProcessor(r),
    );
    final healthClient = ApiClient(
      baseUrl: 'http://localhost:8080/',
      defaultHeaders: const {'accept': 'application/json'},
      transport: healthTransport,
      responseProcessor: (r) => ApiClient.defaultResponseProcessor(r),
    );
    final api = GenesisApi(
      apiClient: apiClient,
      healthClient: healthClient,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: sessionStore,
    );

    final user = await api.bindDevice(did: 'd1');

    expect(user.uid, isEmpty);
    expect(await sessionStore.readUid(), 'guest_old');
  });

  test('ensureUid throws instead of generating guest uid', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 500,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":500,"err_msg":"server error","data":{}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveAuthToken('orphaned-token');
    final apiClient = ApiClient(
      baseUrl: 'http://localhost:8080/api/',
      defaultHeaders: const {
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      transport: apiTransport,
      responseProcessor: (r) => ApiClient.defaultResponseProcessor(r),
    );
    final healthClient = ApiClient(
      baseUrl: 'http://localhost:8080/',
      defaultHeaders: const {'accept': 'application/json'},
      transport: healthTransport,
      responseProcessor: (r) => ApiClient.defaultResponseProcessor(r),
    );
    final api = GenesisApi(
      apiClient: apiClient,
      healthClient: healthClient,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: sessionStore,
    );

    expect(api.ensureUid(), throwsA(isA<ApiException>()));
    expect(await sessionStore.readUid(), isNull);
    expect(await sessionStore.readAuthToken(), 'orphaned-token');
    expect(apiTransport.requests, isEmpty);
  });

  test(
    'v1 err_no 10001 triggers session expired callback with fixed message',
    () async {
      final expired = Completer<String>();
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body:
              '{"err_no":10001,"err_msg":"Your account was logged in elsewhere.","data":{}}',
        ),
      );
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveUid('u_1');
      await sessionStore.saveAuthToken('test-auth-token');
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
        onSessionExpired: (message) async {
          if (!expired.isCompleted) expired.complete(message);
        },
      );

      await expectLater(
        api.v1.user.info(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 10001)
              .having(
                (error) => error.message,
                'message',
                'Your account is logged in on another device.',
              ),
        ),
      );
      expect(
        await expired.future,
        'Your account is logged in on another device.',
      );
      expect(apiTransport.lastRequest!.uri.path, '/api/v1/user/info');
    },
  );

  test('v1 err_no 1404 triggers page not found callback', () async {
    final notFound = Completer<String>();
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":1404,"err_msg":"missing","data":{}}',
      ),
    );
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUid('u_1');
    await sessionStore.saveAuthToken('test-auth-token');
    final api = GenesisApi(
      transport: apiTransport,
      useMock: false,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: sessionStore,
      onPageNotFound: (message) async {
        if (!notFound.isCompleted) notFound.complete(message);
      },
    );

    await expectLater(
      api.v1.user.info(),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 1404)
            .having((error) => error.message, 'message', 'Page not found.'),
      ),
    );
    expect(await notFound.future, 'Page not found.');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/user/info');
  });

  test('HTTP status 404 does not trigger page not found callback', () async {
    var pageNotFoundCalled = false;
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 404,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":1404,"err_msg":"missing","data":{}}',
      ),
    );
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUid('u_1');
    await sessionStore.saveAuthToken('test-auth-token');
    final api = GenesisApi(
      transport: apiTransport,
      useMock: false,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: sessionStore,
      onPageNotFound: (message) async {
        pageNotFoundCalled = true;
      },
    );

    await expectLater(
      api.v1.user.info(),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 404)
            .having((error) => error.kind, 'kind', ApiExceptionKind.httpStatus),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(pageNotFoundCalled, isFalse);
  });

  test('getOrigins uses GET /v1/origin/list for default category', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":0,"err_msg":"succ","data":{"list":[],"total":0}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    await api.getOrigins(category: 'For you', limit: 20, offset: 0);

    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/origin/list');
    expect(apiTransport.lastRequest!.uri.queryParameters['scene'], 'foryou');
    expect(apiTransport.lastRequest!.uri.queryParameters['pn'], '1');
    expect(apiTransport.lastRequest!.uri.queryParameters['rn'], '20');
    expect(apiTransport.lastRequest!.uri.queryParameters['tag'], isNull);
    expect(apiTransport.lastRequest!.uri.queryParameters['tag_name'], isNull);
  });

  test('Origin feed uses cursor query and exposure body', () async {
    final apiTransport = _FakeTransport(
      handler: (request) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: request.method == 'GET'
            ? '{"err_no":0,"err_msg":"succ","data":{"list":[],"rn":10,"next_score":27,"has_more":true}}'
            : '{"err_no":0,"err_msg":"succ","data":{"recorded_count":2}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );
    final api = _apiWith(apiTransport, healthTransport);

    final page = await api.v1.origin.feed(startScore: 11, rn: 10);

    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/origin/feed');
    expect(apiTransport.lastRequest!.uri.queryParameters, {
      'start_score': '11',
      'rn': '10',
    });
    expect(page['next_score'], 27);
    expect(page['has_more'], true);

    final recorded = await api.v1.origin.reportFeedExposure([
      'o_ABC001',
      'o_ABC002',
      'o_ABC001',
    ]);

    expect(apiTransport.lastRequest!.method, 'POST');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/origin/feed/exposure');
    expect(jsonDecode(utf8.decode(apiTransport.lastRequest!.bodyBytes!)), {
      'origin_ids': ['o_ABC001', 'o_ABC002'],
    });
    expect(recorded, 2);
  });

  test('Origin feed validates cursor, page size, and exposure batch', () async {
    final api = _apiWith(
      _FakeTransport(
        handler: (_) => throw StateError('request should not be sent'),
      ),
      _FakeTransport(
        handler: (_) => throw StateError('request should not be sent'),
      ),
    );

    expect(() => api.v1.origin.feed(startScore: -1), throwsArgumentError);
    expect(
      () => api.v1.origin.feed(startScore: 0, rn: 101),
      throwsArgumentError,
    );
    await expectLater(
      api.v1.origin.reportFeedExposure(const []),
      throwsArgumentError,
    );
    await expectLater(
      api.v1.origin.reportFeedExposure(
        List<String>.generate(101, (index) => 'o_$index'),
      ),
      throwsArgumentError,
    );
  });

  test('getOrigins maps non-default category to scene tag', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":0,"err_msg":"succ","data":{"list":[],"total":0}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    await api.getOrigins(category: 'Billionare', limit: 20, offset: 0);

    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/origin/list');
    expect(apiTransport.lastRequest!.uri.queryParameters['scene'], 'tag');
    expect(apiTransport.lastRequest!.uri.queryParameters['tag'], 'Billionare');
    expect(apiTransport.lastRequest!.uri.queryParameters['tag_name'], isNull);
    expect(apiTransport.lastRequest!.uri.queryParameters['rn'], '20');
  });

  test('profile list facades use Apifox origin and world list endpoints', () async {
    final apiTransport = _FakeTransport(
      handler: (request) {
        if (request.uri.path.endsWith('/v1/origin/list')) {
          return const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body:
                '{"err_no":0,"err_msg":"succ","data":{"list":[{"info":{"origin_id":"o_1","origin_name":"Origin One","definition_version":2,"default_map_location_id":"loc_origin","owner_name":"Origin Owner","brief":"origin brief","cover":"","tags":["tag"],"created_at":1716000000},"stats":{"copy_cnt":2,"connect_cnt":3}}],"total":1}}',
          );
        }
        if (request.uri.path.endsWith('/v1/world/list')) {
          return const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body:
                '{"err_no":0,"err_msg":"succ","data":{"list":[{"info":{"world_id":"w_1","world_name":"World One","definition_version":2,"default_map_location_id":"loc_world","cover":"","created_at":1716000000,"last_active_at":1717000000},"stats":{"tick_cnt":4,"sub_tick_no":0,"player_cnt":5},"last_tick":{"tick_no":4,"sub_tick_no":2}}],"total":1}}',
          );
        }
        return const TransportResponse(
          statusCode: 404,
          headers: {'content-type': 'application/json'},
          body: '{"error":"unexpected path"}',
        );
      },
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final origins = await api.getMyLaunchedOrigins(
      uid: 'u_2',
      scene: 'mine',
      limit: 10,
      offset: 10,
    );
    final worlds = await api.getMyWorlds(
      uid: 'u_2',
      scene: 'mine',
      limit: 10,
      offset: 10,
    );
    await api.getMyLaunchedOrigins(
      uid: 'u_2',
      scene: 'uid',
      limit: 10,
      offset: 0,
    );
    await api.getMyWorlds(uid: 'u_2', scene: 'uid', limit: 10, offset: 0);

    expect(origins.data.single.oid, 'o_1');
    expect(origins.data.single.originator, 'Origin Owner');
    expect(origins.data.single.definitionVersion, 2);
    expect(origins.data.single.defaultMapLocationId, 'loc_origin');
    expect(worlds.single.wid, 'w_1');
    expect(worlds.single.progressCount, 4);
    expect(worlds.single.subTickNo, 2);
    expect(worlds.single.definitionVersion, 2);
    expect(worlds.single.defaultMapLocationId, 'loc_world');
    expect(
      worlds.single.updatedAtText,
      DateTime.fromMillisecondsSinceEpoch(1717000000 * 1000).toIso8601String(),
    );
    expect(apiTransport.requests[0].uri.path, '/api/v1/origin/list');
    expect(apiTransport.requests[0].uri.queryParameters['scene'], 'mine');
    expect(
      apiTransport.requests[0].uri.queryParameters.containsKey('owner_uid'),
      false,
    );
    expect(
      apiTransport.requests[0].uri.queryParameters.containsKey('uid'),
      false,
    );
    expect(apiTransport.requests[0].uri.queryParameters['pn'], '2');
    expect(apiTransport.requests[0].uri.queryParameters['rn'], '10');
    expect(apiTransport.requests[1].uri.path, '/api/v1/world/list');
    expect(apiTransport.requests[1].uri.queryParameters['scene'], 'mine');
    expect(
      apiTransport.requests[1].uri.queryParameters.containsKey('owner_uid'),
      false,
    );
    expect(
      apiTransport.requests[1].uri.queryParameters.containsKey('uid'),
      false,
    );
    expect(apiTransport.requests[1].uri.queryParameters['pn'], '2');
    expect(apiTransport.requests[1].uri.queryParameters['rn'], '10');
    expect(apiTransport.requests[2].uri.path, '/api/v1/origin/list');
    expect(apiTransport.requests[2].uri.queryParameters['scene'], 'uid');
    expect(apiTransport.requests[2].uri.queryParameters['uid'], 'u_2');
    expect(
      apiTransport.requests[2].uri.queryParameters.containsKey('owner_uid'),
      false,
    );
    expect(apiTransport.requests[3].uri.path, '/api/v1/world/list');
    expect(apiTransport.requests[3].uri.queryParameters['scene'], 'uid');
    expect(apiTransport.requests[3].uri.queryParameters['uid'], 'u_2');
    expect(
      apiTransport.requests[3].uri.queryParameters.containsKey('owner_uid'),
      false,
    );
  });

  test('getOrigin maps the complete v1 origin detail contract', () async {
    final apiTransport = _FakeTransport(
      handler: (request) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'err_no': 0,
          'err_msg': 'succ',
          'data': {
            'info': {
              'origin_id': 'o_1',
              'origin_name': 'Origin One',
              'origin_version': '7',
              'origin_version_time': 1716000060,
              'definition_version': 2,
              'language': 'zh-Hans',
              'current_time': 'Day 7, 19:10',
              'owner_uid': 'u_1',
              'owner_name': 'Tester',
              'owner_user': {
                'uid': 'u_1',
                'name': 'Tester',
                'avatar': {
                  'sm_url': 'https://cdn.example.com/owner-sm.webp',
                  'xl_url': 'https://cdn.example.com/owner-xl.webp',
                  'object_key': 'owner-xl.webp',
                },
                'deleted': false,
                'follower_cnt': 11,
                'following_cnt': 12,
                'friend_cnt': 13,
                'create_origin_cnt': 14,
                'launch_world_cnt': 15,
                'join_world_cnt': 16,
              },
              'brief': 'Brief shown in World View.',
              'tags': const <Object?>['adventure', 'school'],
              'metric': const <String, Object?>{'unit': '%'},
              'created_at': 1716000000,
              'cover': {
                'sm_url': 'https://cdn.example.com/cover-sm.webp',
                'xl_url': 'https://cdn.example.com/cover-xl.webp',
                'object_key': 'cover-xl.webp',
              },
              'map_url': 'https://cdn.example.com/map.webp',
              'status': 10,
            },
            'stats': const <String, Object?>{
              'copy_cnt': 21,
              'discuss_cnt': 22,
              'character_cnt': 23,
              'connect_cnt': 24,
              'location_cnt': 25,
              'max_tick_cnt': 26,
            },
            'init_location_group': const {
              'location_id': 'loc_1',
              'initial_dialogue': [
                {
                  'char_id': 'nar',
                  'char_name': 'Narrator',
                  'content': 'The gate opens.',
                },
                {
                  'char_id': 'char_1',
                  'char_name': 'Sam',
                  'content': 'We should go.',
                },
                {
                  'char_id': 'nar_pic',
                  'char_name': 'Narrator',
                  'content': 'https://cdn.example.com/opening.webp',
                },
              ],
            },
            'characters': const [
              {
                'char_id': 'char_1',
                'type': 'ai',
                'player_uid': '',
                'player_username': '',
                'player_user': {
                  'uid': '',
                  'name': '',
                  'avatar': <String, Object?>{},
                  'deleted': false,
                  'follower_cnt': 0,
                  'following_cnt': 0,
                  'friend_cnt': 0,
                  'create_origin_cnt': 0,
                  'launch_world_cnt': 0,
                  'join_world_cnt': 0,
                },
                'player_joined_at': 0,
                'name': 'Sam',
                'identity': 'Guide',
                'brief': 'Knows the old roads.',
                'goal': 'Reach the gate.',
                'avatar': {
                  'sm_url': 'https://cdn.example.com/sam-sm.webp',
                  'xl_url': 'https://cdn.example.com/sam-xl.webp',
                  'object_key': 'sam-xl.webp',
                },
                'initial_location_id': 'loc_1',
                'location_id': 'loc_2',
                'metric_value': 9,
                'delta': -2,
                'is_recommend': 1,
              },
            ],
            'locations': const [
              {
                'location_id': 'loc_1',
                'level': 1,
                'location_pid': '',
                'location_name': 'Gate',
                'location_paragraph': 'Gate launch paragraph.',
                'location_timestamp': 'Day 1, 08:30',
                'location_summary': 'The gate is open.',
                'image': {
                  'sm_url': 'https://cdn.example.com/gate-sm.webp',
                  'xl_url': 'https://cdn.example.com/gate-xl.webp',
                  'object_key': 'gate-xl.webp',
                },
                'x_percent': 20,
                'y_percent': 30,
                'x': 128.5,
                'y': -64.25,
                'map_url': 'https://cdn.example.com/gate-map.webp',
                'dialogue': [
                  {
                    'char_id': 'char_1',
                    'char_name': 'Sam',
                    'content': 'Doors open at eight.',
                  },
                ],
              },
            ],
            'ticks': const [
              {
                'tick_id': 'tick_1',
                'tick_no': 1,
                'sub_tick_no': 1,
                'status': 50,
                'created_at': 1716000000,
                'tick_result': {
                  'current_time': 'Day 1, 08:30',
                  'narrator': 'Narrator from origin tick result.',
                  'paragraphs': [
                    {
                      'location_id': 'loc_1',
                      'timestamp': 'Day 1, 08:30',
                      'text': 'The gate opens.',
                      'visibility': 'char_only',
                      'visible_to': ['char_1'],
                      'clue': 'Move through the gate.',
                      'character_deltas': <Object?>[],
                    },
                  ],
                },
              },
            ],
          },
        }),
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final origin = await api.getOrigin('o_1');

    expect(apiTransport.lastRequest!.uri.path, '/api/v1/origin/detail');
    expect(apiTransport.requests, hasLength(1));
    expect(apiTransport.lastRequest!.uri.queryParameters['origin_id'], 'o_1');
    expect(origin.worldView, 'Brief shown in World View.');
    expect(origin.description, 'Brief shown in World View.');
    expect(origin.originVersion, '7');
    expect(origin.versionNum, 7);
    expect(origin.originVersionTime?.millisecondsSinceEpoch, 1716000060000);
    expect(origin.language, 'zh-Hans');
    expect(origin.currentTime, 'Day 7, 19:10');
    expect(origin.status, 10);
    expect(origin.ownerUser.uid, 'u_1');
    expect(origin.ownerUser.followerCount, 11);
    expect(origin.ownerUser.avatarResource.objectKey, 'owner-xl.webp');
    expect(origin.coverResource.objectKey, 'cover-xl.webp');
    expect(origin.copyCount, 21);
    expect(origin.discussCount, 22);
    expect(origin.characterCount, 23);
    expect(origin.connectCount, 24);
    expect(origin.locationCount, 25);
    expect(origin.maxTickCount, 26);
    expect(origin.tags, ['adventure', 'school']);
    expect(origin.initLocationGroup?.locationId, 'loc_1');
    expect(
      origin.initLocationGroup?.initialDialogue.map((line) => line.charId),
      ['nar', 'char_1', 'nar_pic'],
    );
    final character = origin.characters.single;
    expect(character.type, 'ai');
    expect(character.playerUid, isEmpty);
    expect(character.playerUser.uid, isEmpty);
    expect(character.playerJoinedAt, 0);
    expect(character.currentLocationBusinessId, 'loc_2');
    expect(character.initialLocationBusinessId, 'loc_1');
    expect(character.currentLocationId, isNot(character.initialLocationId));
    expect(character.metricValue, 9);
    expect(character.delta, -2);
    expect(character.isRecommend, 1);
    expect(character.isRecommended, isTrue);
    expect(character.avatarResource.objectKey, 'sam-xl.webp');
    expect(origin.ticks.single['tick_result'], isA<Map>());
    expect(
      (origin.ticks.single['tick_result'] as Map)['narrator'],
      'Narrator from origin tick result.',
    );
    expect(
      (origin.ticks.single['tick_result'] as Map)['current_time'],
      'Day 1, 08:30',
    );
    expect(origin.ticks.single['sub_tick_no'], 1);
    expect(origin.ticks.single['status'], 50);
    final tickResult = origin.ticks.single['tick_result'] as Map;
    expect(tickResult, isNot(contains('location_groups')));
    final tickParagraph = (tickResult['paragraphs'] as List).single as Map;
    expect(tickParagraph['visibility'], 'char_only');
    expect(tickParagraph['visible_to'], ['char_1']);
    expect(tickParagraph['clue'], 'Move through the gate.');
    expect(origin.metric['unit'], '%');
    expect(origin.definitionVersion, 2);
    final location = origin.locations.single;
    expect(location.level, 1);
    expect(location.locationParagraph, 'Gate launch paragraph.');
    expect(location.locationTimestamp, 'Day 1, 08:30');
    expect(location.locationSummary, 'The gate is open.');
    expect(location.description, 'The gate is open.');
    expect(location.xPercent, 20);
    expect(location.yPercent, 30);
    expect(location.x, 128.5);
    expect(location.y, -64.25);
    expect(location.imageResource.objectKey, 'gate-xl.webp');
    expect(location.dialogue.single.content, 'Doors open at eight.');
  });

  test('getOriginMap uses map contract and preserves tilemap JSON', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'err_no': 0,
          'err_msg': 'succ',
          'data': {
            'tile_types': {'grass': 'https://cdn.example.com/tiles/grass.png'},
            'map_json': {
              'width': 2,
              'height': 3,
              'tiles': [
                {
                  'x': 0,
                  'y': 1,
                  'type': 'grass',
                  'shadow': 1,
                  'location_id': 'loc_grass',
                },
              ],
            },
          },
        }),
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final definition = await api.getOriginMap(
      originId: 'o_1',
      locationId: 'root',
    );

    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/origin/map');
    expect(apiTransport.lastRequest!.uri.queryParameters, {
      'origin_id': 'o_1',
      'location_id': 'root',
    });
    expect(definition.isAvailable, true);
    expect(
      definition.tileTypes!['grass'],
      'https://cdn.example.com/tiles/grass.png',
    );
    expect(definition.tiles, hasLength(1));
    expect(definition.tiles.single.x, 0);
    expect(definition.tiles.single.y, 1);
    expect(definition.tiles.single.type, 'grass');
    expect(definition.tiles.single.shadow, 1);
    expect(definition.tiles.single.locationId, 'loc_grass');
    expect(definition.mapJson!.width, 2);
    expect(definition.mapJson!.height, 3);
  });

  test('tilemap shadow defaults to zero and rejects unsupported values', () {
    Map<String, dynamic> definitionWithShadow(Object? shadow) {
      return {
        'tile_types': {'grass': 'https://cdn.example.com/tiles/grass.png'},
        'map_json': {
          'width': 1,
          'height': 1,
          'tiles': [
            {
              'x': 0,
              'y': 0,
              'type': 'grass',
              if (shadow != null) 'shadow': shadow,
            },
          ],
        },
      };
    }

    expect(
      TilemapDefinition.fromJson(
        definitionWithShadow(null),
      ).tiles.single.shadow,
      0,
    );
    expect(
      () => TilemapDefinition.fromJson(definitionWithShadow(2)),
      throwsArgumentError,
    );
  });

  test('getOriginInfo uses lightweight origin info contract', () async {
    final apiTransport = _FakeTransport(
      handler: (request) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'err_no': 0,
          'err_msg': 'succ',
          'data': {
            'info': {
              'origin_id': 'o_info_1',
              'origin_name': 'Origin Info',
              'origin_version': '2',
              'owner_uid': 'u_1',
              'owner_name': 'Tester',
              'brief': 'Lightweight brief.',
              'tags': ['light'],
              'created_at': 1716000000,
              'cover': const <String, Object?>{
                'sm_url': 'https://cdn.example.com/origin_400.webp',
                'xl_url': 'https://cdn.example.com/origin_800.webp',
                'object_key': 'uploads/origin_800.webp',
              },
              'map_url': 'https://cdn.example.com/map.png',
              'status': 10,
            },
            'stats': {
              'copy_cnt': 3,
              'discuss_cnt': 4,
              'character_cnt': 5,
              'connect_cnt': 6,
              'location_cnt': 7,
              'max_tick_cnt': 8,
            },
          },
        }),
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final origin = await api.getOriginInfo('o_info_1');

    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/origin/info');
    expect(
      apiTransport.lastRequest!.uri.queryParameters['origin_id'],
      'o_info_1',
    );
    expect(origin.oid, 'o_info_1');
    expect(origin.name, 'Origin Info');
    expect(origin.worldView, 'Lightweight brief.');
    expect(origin.copyCount, 3);
    expect(origin.discussCount, 4);
    expect(origin.interactCount, 6);
    expect(origin.characterCount, 5);
    expect(origin.characters, isEmpty);
    expect(origin.allLocations, isEmpty);
    expect(origin.ticks, isEmpty);
  });

  test(
    'getMyLaunchPresetCharacters uses contract query and common headers',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => TransportResponse(
          statusCode: 200,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'err_no': 0,
            'err_msg': 'succ',
            'data': {
              'list': [
                {
                  'char_id': 'char_1',
                  'type': 'ai',
                  'name': 'Alice',
                  'identity': 'Detective',
                  'brief': 'Calm and observant',
                  'goal': 'Find the truth',
                  'avatar': {
                    'sm_url': 'https://cdn.example.com/alice_400.webp',
                    'xl_url': 'https://cdn.example.com/alice_800.webp',
                    'object_key': 'uploads/alice_800.webp',
                  },
                  'initial_location_id': 'loc_1_1_1',
                  'last_launched_at': 1785292800,
                  'world_id': 'w_history_1',
                  'tick_no': 7,
                  'sub_tick_no': 2,
                  'connect_cnt': 24,
                  'current_time': 'Day 3',
                  'last_active_at': 1785296400,
                },
              ],
            },
          }),
        ),
      );
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveAuthToken('backend-token');
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        sessionStore: sessionStore,
        appHeaderProvider: () async => const {
          'user-agent': 'Android 15',
          'x-system-language': 'zh-CN',
          'x-app-version-code': '123',
          'x-app-timezone': 'Asia/Shanghai',
          'device-id': 'legacy-device-id',
        },
      );

      final characters = await api.getMyLaunchPresetCharacters('o_1', limit: 5);

      final request = apiTransport.lastRequest!;
      expect(request.method, 'GET');
      expect(request.uri.path, '/api/v1/origin/my_launch_preset_characters');
      expect(request.uri.queryParameters, {'origin_id': 'o_1', 'limit': '5'});
      expect(request.headers['user-agent'], 'Android 15');
      expect(request.headers['x-system-language'], 'zh-CN');
      expect(request.headers['x-app-version-code'], '123');
      expect(request.headers['x-app-timezone'], 'Asia/Shanghai');
      expect(request.headers['authorization'], 'Bearer backend-token');
      expect(request.headers.containsKey('device-id'), isFalse);

      expect(characters, hasLength(1));
      final character = characters.single;
      expect(character.charId, 'char_1');
      expect(character.type, 'ai');
      expect(character.name, 'Alice');
      expect(character.identity, 'Detective');
      expect(character.brief, 'Calm and observant');
      expect(character.goal, 'Find the truth');
      expect(character.avatar, 'https://cdn.example.com/alice_800.webp');
      expect(character.avatarResource.objectKey, 'uploads/alice_800.webp');
      expect(character.initialLocationId, 'loc_1_1_1');
      expect(character.lastLaunchedAt, 1785292800);
      expect(character.worldId, 'w_history_1');
      expect(character.tickCount, 7);
      expect(character.subTickNo, 2);
      expect(character.messageCount, 24);
      expect(character.currentTime, 'Day 3');
      expect(character.lastActiveAt, '1785296400');
    },
  );

  test(
    'v2 origin forEdit uses query and nested OriginDetail response',
    () async {
      final apiTransport = _FakeTransport(
        handler: (request) => TransportResponse(
          statusCode: 200,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'err_no': 0,
            'err_msg': 'succ',
            'data': {
              'info': {
                'origin_id': 'o_edit_1',
                'origin_name': 'Editable Origin',
                'definition_version': 2,
                'brief': 'Editable public view.',
                'tags': ['archive'],
                'metric': const <String, Object?>{
                  'label': 'Influence',
                  'label_note': 'Tracks archive trust.',
                },
                'cover': const <String, Object?>{
                  'sm_url': 'cover_400.png',
                  'xl_url': 'cover_800.png',
                  'object_key': 'covers/edit.png',
                },
              },
              'stats': const <String, Object?>{},
              'init_location_group': const <String, Object?>{
                'location_id': 'loc_1',
                'initial_dialogue': <Object?>[],
              },
              'characters': const <Object?>[
                {'char_id': 'char_1', 'name': 'Ari', 'is_recommend': 1},
              ],
              'locations': const <Object?>[],
              'ticks': const <Object?>[],
            },
          }),
        ),
      );
      final healthTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      );

      final api = _apiWith(apiTransport, healthTransport);
      final edit = await api.v2.origin.forEdit(originId: 'o_edit_1');

      expect(apiTransport.lastRequest!.method, 'GET');
      expect(apiTransport.lastRequest!.uri.path, '/api/v2/origin/foredit');
      expect(
        apiTransport.lastRequest!.uri.queryParameters['origin_id'],
        'o_edit_1',
      );
      expect((edit['info'] as Map)['origin_id'], 'o_edit_1');
      expect(
        ((edit['info'] as Map)['metric'] as Map)['label_note'],
        'Tracks archive trust.',
      );
      expect(edit['stats'], isA<Map>());
      expect(edit['ticks'], isEmpty);
      expect(((edit['characters'] as List).single as Map)['is_recommend'], 1);
    },
  );

  test('search upgrades the request path to /api/v2/search', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'err_no': 0,
          'err_msg': 'succ',
          'data': {
            'keyword': 'Alice',
            'type': 'origin',
            'origins': {
              'list': [
                {
                  'origin_id': 'o_1',
                  'origin_name': 'Alice Origin',
                  'origin_version': '3',
                  'brief': 'A😀Alice',
                  'language': 'en',
                  'cover': {
                    'sm_url': 'https://cdn.example.com/o_1_sm.webp',
                    'xl_url': 'https://cdn.example.com/o_1_xl.webp',
                    'object_key': 'origin/o_1.webp',
                  },
                  'tags': ['romance', 'campus'],
                  'characters': [
                    {'character_id': 'c_1', 'name': 'Alice'},
                  ],
                  'owner': {
                    'uid': 'u_owner',
                    'name': 'Owner',
                    'avatar': {
                      'sm_url': 'https://cdn.example.com/u_sm.webp',
                      'xl_url': 'https://cdn.example.com/u_xl.webp',
                      'object_key': 'user/u_owner.webp',
                    },
                  },
                  'stats': {
                    'copy_cnt': 1,
                    'discuss_cnt': 2,
                    'character_cnt': 3,
                    'connect_cnt': 4,
                    'location_cnt': 5,
                    'max_tick_cnt': 6,
                  },
                  'matches': [
                    {
                      'field': 'origin_name',
                      'highlight_ranges': [
                        {'start': 0, 'length': 5},
                      ],
                    },
                    {
                      'field': 'character_name',
                      'character_id': 'c_1',
                      'highlight_ranges': [
                        {'start': 0, 'length': 5},
                      ],
                    },
                    {
                      'field': 'brief',
                      'highlight_ranges': [
                        {'start': 3, 'length': 5},
                      ],
                    },
                    {
                      'field': 'tag',
                      'tag_index': 0,
                      'highlight_ranges': [
                        {'start': 0, 'length': 7},
                      ],
                    },
                  ],
                  'matches_truncated': false,
                },
              ],
              'total': 1,
              'pn': 2,
              'rn': 10,
            },
            'worlds': {
              'list': [
                {
                  'world_id': 'w_1',
                  'world_name': 'Alice World',
                  'origin_id': 'o_1',
                  'language': 'en',
                  'cover': {
                    'sm_url': 'https://cdn.example.com/w_sm.webp',
                    'xl_url': 'https://cdn.example.com/w_xl.webp',
                    'object_key': 'world/w_1.webp',
                  },
                  'tags': ['fantasy', 'campus'],
                  'owner': {
                    'uid': 'u_owner',
                    'name': 'Owner',
                    'avatar': {
                      'sm_url': 'https://cdn.example.com/u_sm.webp',
                      'xl_url': 'https://cdn.example.com/u_xl.webp',
                      'object_key': 'user/u_owner.webp',
                    },
                  },
                  'stats': {
                    'tick_cnt': 7,
                    'sub_tick_no': 3,
                    'connect_cnt': 8,
                    'character_cnt': 9,
                    'player_cnt': 10,
                  },
                  'created_at': 1770000000,
                  'matches': [
                    {
                      'field': 'world_name',
                      'highlight_ranges': [
                        {'start': 0, 'length': 5},
                      ],
                    },
                    {
                      'field': 'tag',
                      'tag_index': 1,
                      'highlight_ranges': [
                        {'start': 0, 'length': 6},
                      ],
                    },
                  ],
                },
              ],
              'total': 1,
              'pn': 2,
              'rn': 10,
            },
            'users': {
              'list': [
                {
                  'uid': 'u_1',
                  'name': 'Alice',
                  'avatar': {
                    'sm_url': 'https://cdn.example.com/a_sm.webp',
                    'xl_url': 'https://cdn.example.com/a_xl.webp',
                    'object_key': 'user/u_1.webp',
                  },
                  'matches': [
                    {
                      'field': 'user_name',
                      'highlight_ranges': [
                        {'start': 0, 'length': 5},
                      ],
                    },
                  ],
                },
              ],
              'total': 1,
              'pn': 2,
              'rn': 10,
            },
          },
        }),
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final result = await api.v1.search.search(
      query: 'Alice',
      type: 'origin',
      pn: 2,
      rn: 10,
    );

    final request = apiTransport.lastRequest!;
    expect(request.method, 'GET');
    expect(request.uri.path, '/api/v2/search');
    expect(request.uri.queryParameters, {
      'keyword': 'Alice',
      'type': 'origin',
      'pn': '2',
      'rn': '10',
    });
    expect(result.keyword, 'Alice');
    expect(result.type, 'origin');
    expect(result.origins.pageNumber, 2);
    expect(result.origins.pageSize, 10);
    expect(result.origins.total, 1);

    final origin = result.origins.items.single;
    expect(origin.originId, 'o_1');
    expect(origin.originName, 'Alice Origin');
    expect(origin.originVersion, '3');
    expect(origin.brief, 'A😀Alice');
    expect(origin.language, 'en');
    expect(origin.cover.smUrl, 'https://cdn.example.com/o_1_sm.webp');
    expect(origin.cover.xlUrl, 'https://cdn.example.com/o_1_xl.webp');
    expect(origin.cover.objectKey, 'origin/o_1.webp');
    expect(origin.tags, ['romance', 'campus']);
    expect(origin.characters.single.characterId, 'c_1');
    expect(origin.characters.single.name, 'Alice');
    expect(origin.owner.uid, 'u_owner');
    expect(origin.owner.name, 'Owner');
    expect(origin.owner.avatar.objectKey, 'user/u_owner.webp');
    expect(origin.stats.copyCount, 1);
    expect(origin.stats.discussCount, 2);
    expect(origin.stats.characterCount, 3);
    expect(origin.stats.connectCount, 4);
    expect(origin.stats.locationCount, 5);
    expect(origin.stats.maxTickCount, 6);
    expect(origin.matches, hasLength(4));
    expect(origin.matches.first, isA<SearchV2TextMatch>());
    expect(origin.matches.first.field, 'origin_name');
    expect(origin.matches.first.highlightRanges.single.start, 0);
    expect(origin.matches.first.highlightRanges.single.length, 5);
    expect(origin.matches[1], isA<SearchV2CharacterMatch>());
    expect(origin.matches[1].field, 'character_name');
    expect((origin.matches[1] as SearchV2CharacterMatch).characterId, 'c_1');
    final briefMatch = origin.matches.whereType<SearchV2TextMatch>().last;
    expect(briefMatch.field, 'brief');
    expect(briefMatch.highlightRanges.single.start, 3);
    expect(briefMatch.highlightRanges.single.length, 5);
    final originTagMatch = origin.matches.whereType<SearchV2TagMatch>().single;
    expect(originTagMatch.field, 'tag');
    expect(originTagMatch.tagIndex, 0);
    expect(originTagMatch.highlightRanges.single.length, 7);
    expect(origin.matchesTruncated, isFalse);

    final world = result.worlds.items.single;
    expect(world.worldId, 'w_1');
    expect(world.worldName, 'Alice World');
    expect(world.originId, 'o_1');
    expect(world.language, 'en');
    expect(world.cover.objectKey, 'world/w_1.webp');
    expect(world.tags, ['fantasy', 'campus']);
    expect(world.owner.uid, 'u_owner');
    expect(world.stats.tickCount, 7);
    expect(world.stats.subTickNo, 3);
    expect(world.stats.connectCount, 8);
    expect(world.stats.characterCount, 9);
    expect(world.stats.playerCount, 10);
    expect(world.createdAt, 1770000000);
    final worldNameMatch = world.matches
        .whereType<SearchV2WorldNameMatch>()
        .single;
    expect(worldNameMatch.field, 'world_name');
    expect(worldNameMatch.highlightRanges.single.start, 0);
    expect(worldNameMatch.highlightRanges.single.length, 5);
    final worldTagMatch = world.matches.whereType<SearchV2TagMatch>().single;
    expect(worldTagMatch.field, 'tag');
    expect(worldTagMatch.tagIndex, 1);
    expect(worldTagMatch.highlightRanges.single.length, 6);

    final user = result.users.items.single;
    expect(user.uid, 'u_1');
    expect(user.name, 'Alice');
    expect(user.avatar.objectKey, 'user/u_1.webp');
    expect(user.matches.single, isA<SearchV2UserNameMatch>());
    expect(user.matches.single.field, 'user_name');
    expect(user.matches.single.highlightRanges.single.start, 0);
    expect(user.matches.single.highlightRanges.single.length, 5);
  });

  test('createOrigin posts latest Apifox origin create body', () async {
    final apiTransport = _FakeTransport(
      handler: (request) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'err_no': 0,
          'err_msg': 'succ',
          'data': {
            'info': {'origin_id': 'o_created_1'},
            'stats': const <String, Object?>{},
            'characters': const <Object?>[],
            'locations': const <Object?>[],
            'ticks': const <Object?>[],
          },
        }),
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    await api.createOrigin(
      payload: {
        'name': 'Crystal City',
        'origin_version': 'draft-2',
        'world_view': 'A public world view.',
        'world_setting': 'Hidden rules.',
        'event_list': const [
          {'content': 'The gate opens.'},
        ],
        'tags': const ['city'],
        'metric': const <String, Object?>{
          'label': 'Influence',
          'label_note': 'Tracks public influence.',
        },
        'started_at': 'Day 1',
        'tick_duration_days': 30,
        'cover': 'cover.png',
        'map_url': 'map.png',
        'character_list': const [
          {
            'char_id': 'char_tmp_1',
            'name': 'Ari',
            'identity': 'Guide',
            'tagline': 'Calm',
            'description': 'Keeps the route.',
            'goal': 'Open the city.',
            'avatar': 'ari.png',
            'is_recommend': 1,
          },
        ],
        'location_list': const [
          {
            'location_id': 'loc_tmp_1',
            'location_pid': '',
            'name': 'Gate',
            'description': 'Entry point.',
            'image': 'gate.png',
            'initial_character_ids': ['char_tmp_1'],
          },
        ],
      },
    );

    expect(apiTransport.lastRequest!.method, 'POST');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/origin/create');
    final body =
        jsonDecode(utf8.decode(apiTransport.lastRequest!.bodyBytes!))
            as Map<String, dynamic>;
    expect(body.containsKey('name'), isFalse);
    expect(body.containsKey('world_view'), isFalse);
    expect(body.containsKey('world_setting'), isFalse);
    expect(body.containsKey('character_list'), isFalse);
    expect(body.containsKey('location_list'), isFalse);
    expect(body.containsKey('event_list'), isFalse);
    expect(body['origin_name'], 'Crystal City');
    expect(body['origin_version'], 'draft-2');
    expect(body['brief'], 'A public world view.');
    expect(body['setting'], 'Hidden rules.');
    expect(body['events'], ['The gate opens.']);
    expect(body['tags'], ['city']);
    expect(body['metric'], {
      'label': 'Influence',
      'label_note': 'Tracks public influence.',
    });
    expect(body['started_at'], 'Day 1');
    expect(body.containsKey('tick_duration_days'), isFalse);
    expect(body['tick_duration_time'], '30 days');
    expect(body['cover'], 'cover.png');
    expect(body.containsKey('map_url'), isFalse);

    final characters = body['characters'] as List;
    expect(characters, hasLength(1));
    expect(characters.single['char_id'], 'char_tmp_1');
    expect(characters.single['personality'], 'Calm');
    expect(characters.single['bio'], 'Keeps the route.');
    expect(characters.single['initial_location_id'], 'loc_tmp_1');
    expect(characters.single, isNot(contains('is_recommend')));

    final locations = body['locations'] as List;
    expect(locations, hasLength(1));
    expect(locations.single['location_id'], 'loc_tmp_1');
    expect(locations.single.containsKey('location_pid'), isFalse);
    expect(locations.single['location_name'], 'Gate');
    expect(locations.single['location_description'], 'Entry point.');
  });

  test('updateOrigin posts latest Apifox origin update body', () async {
    final apiTransport = _FakeTransport(
      handler: (request) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'err_no': 0,
          'err_msg': 'succ',
          'data': {
            'info': {'origin_id': 'o_update_1'},
            'stats': const <String, Object?>{},
            'characters': const <Object?>[],
            'locations': const <Object?>[],
            'ticks': const <Object?>[],
          },
        }),
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    await api.updateOrigin(
      oid: 'o_update_1',
      payload: {
        'origin_id': 'o_update_1',
        'origin_version': 'draft-3',
        'name': 'Updated Origin',
        'world_view': 'Updated brief.',
        'world_setting': 'Updated setting.',
        'event_list': const [
          {'content': 'The map changes.'},
        ],
        'tags': const ['updated'],
        'metric': const <String, Object?>{
          'mode': 'qualitative',
          'label': 'Progress',
          'label_note': 'Tracks story progress.',
          'unit': '%',
          'range': [0, 100],
          'default': 0,
        },
        'started_at': 'Day 2',
        'tick_duration_days': 7,
        'cover': 'updated-cover.png',
        'map_url': 'updated-map.png',
        'character_list': const [
          {
            'char_id': 'char_keep',
            'name': 'Mira',
            'identity': 'Archivist',
            'personality': 'Patient',
            'bio': 'Keeps the records.',
            'goal': 'Find the first page.',
            'avatar': 'mira.png',
            'initial_location_id': 'loc_keep',
            'is_recommend': 1,
          },
        ],
        'location_list': const [
          {
            'location_id': 'loc_keep',
            'name': 'Archive',
            'description': 'A quiet tower.',
            'image': 'archive.png',
          },
        ],
        'deleted_char_ids': const ['char_removed'],
        'deleted_location_ids': const ['loc_removed'],
        'update_notes': 'Adjusted archive.',
      },
    );

    expect(apiTransport.lastRequest!.method, 'POST');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/origin/update');
    final body =
        jsonDecode(utf8.decode(apiTransport.lastRequest!.bodyBytes!))
            as Map<String, dynamic>;
    expect(body.containsKey('oid'), isFalse);
    expect(body.containsKey('name'), isFalse);
    expect(body.containsKey('world_view'), isFalse);
    expect(body.containsKey('world_setting'), isFalse);
    expect(body.containsKey('character_list'), isFalse);
    expect(body.containsKey('location_list'), isFalse);
    expect(body.containsKey('event_list'), isFalse);
    expect(body['origin_id'], 'o_update_1');
    expect(body['origin_version'], 'draft-3');
    expect(body['origin_name'], 'Updated Origin');
    expect(body['brief'], 'Updated brief.');
    expect(body['setting'], 'Updated setting.');
    expect(body['events'], ['The map changes.']);
    expect(body['tags'], ['updated']);
    expect(body['metric'], {
      'mode': 'qualitative',
      'label': 'Progress',
      'label_note': 'Tracks story progress.',
      'unit': '%',
      'range': [0, 100],
      'default': 0,
    });
    final metric = body['metric'] as Map;
    expect(metric.containsKey('progress_metric'), isFalse);
    expect(metric.containsKey('starting_value'), isFalse);
    expect(metric.containsKey('start_time'), isFalse);
    expect(metric.containsKey('time_per_progress'), isFalse);
    expect(body['started_at'], 'Day 2');
    expect(body.containsKey('tick_duration_days'), isFalse);
    expect(body['tick_duration_time'], '7 days');
    expect(body['cover'], 'updated-cover.png');
    expect(body.containsKey('map_url'), isFalse);
    expect(body['update_notes'], 'Adjusted archive.');
    expect(body['deleted_char_ids'], ['char_removed']);
    expect(body['deleted_location_ids'], ['loc_removed']);

    final characters = body['characters'] as List;
    expect(characters.single['char_id'], 'char_keep');
    expect(characters.single['personality'], 'Patient');
    expect(characters.single['bio'], 'Keeps the records.');
    expect(characters.single['initial_location_id'], 'loc_keep');
    expect(characters.single, isNot(contains('is_recommend')));

    final locations = body['locations'] as List;
    expect(locations.single['location_id'], 'loc_keep');
    expect(locations.single.containsKey('location_pid'), isFalse);
    expect(locations.single['location_name'], 'Archive');
    expect(locations.single['location_description'], 'A quiet tower.');
  });

  test('createOriginV2 posts automatic-map create contract', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'err_no': 0,
          'err_msg': 'succ',
          'data': {
            'origin_id': 'o_v2_created',
            'origin_version': '1',
            'origin_version_time': 1780000000,
            'origin_name': 'Automatic Map Origin',
          },
        }),
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final result = await api.createOriginV2(
      payload: {
        'name': 'Automatic Map Origin',
        'origin_version': 'draft-1',
        'definition_version': 1,
        'world_view': 'A generated city.',
        'world_setting': 'Every street remembers.',
        'event_list': const [
          {'content': 'The city wakes.'},
        ],
        'tags': const ['city'],
        'metric': const {'label': 'Trust'},
        'started_at': 'Day 1',
        'tick_duration_days': 1,
        'cover': const {
          'sm_url': 'cover-small.webp',
          'xl_url': 'cover-large.webp',
          'object_key': 'covers/cover-large.webp',
        },
        'map_url': 'legacy-map.webp',
        'tile_types': const {
          'grass': {'texture': 'grass_01', 'walkable': true},
        },
        'character_list': const [
          {
            'char_id': 'char_1',
            'name': 'Ari',
            'is_recommend': 1,
            'avatar': {
              'sm_url': 'avatar-small.webp',
              'xl_url': 'avatar-large.webp',
              'object_key': 'avatars/avatar-large.webp',
            },
          },
        ],
        'location_list': const [
          {
            'location_id': 'loc_tmp_1',
            'location_pid': 'loc_tmp_parent',
            'level': 3,
            'name': 'Gate',
            'image': {
              'sm_url': 'gate-small.webp',
              'xl_url': 'gate-large.webp',
              'object_key': 'locations/gate-large.webp',
            },
          },
        ],
        'init_location_group': const {
          'location_id': 'loc_1_1_1',
          'initial_dialogue': [
            {'char_id': 'nar', 'content': 'The gate opens.'},
            {'char_id': 'nar_pic', 'content': 'opening.webp'},
          ],
        },
      },
    );

    expect(result.oid, 'o_v2_created');
    expect(apiTransport.lastRequest!.method, 'POST');
    expect(apiTransport.lastRequest!.uri.path, '/api/v2/origin/create');
    final body =
        jsonDecode(utf8.decode(apiTransport.lastRequest!.bodyBytes!))
            as Map<String, dynamic>;
    expect(body['origin_name'], 'Automatic Map Origin');
    expect(body['definition_version'], 1);
    expect(body['tick_duration_time'], '1 day');
    expect(body['cover'], isA<Map>());
    expect(body['map_url'], 'legacy-map.webp');
    expect(body['tile_types'], isA<Map>());
    expect(body['characters'], hasLength(1));
    expect(body['locations'], hasLength(1));
    expect((body['characters'] as List).single['avatar'], isA<Map>());
    expect((body['characters'] as List).single['is_recommend'], 1);
    expect(
      (body['locations'] as List).single['location_pid'],
      'loc_tmp_parent',
    );
    expect((body['locations'] as List).single['level'], 3);
    expect((body['locations'] as List).single['image'], isA<Map>());
    expect((body['init_location_group'] as Map)['location_id'], 'loc_1_1_1');
  });

  test('updateOriginV2 posts automatic-map update contract', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'err_no': 0,
          'err_msg': 'succ',
          'data': {
            'origin_id': 'o_v2_updated',
            'origin_version': '3',
            'origin_version_time': 1780000100,
            'origin_name': 'Updated Automatic Map Origin',
          },
        }),
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final result = await api.updateOriginV2(
      oid: 'o_v2_updated',
      payload: {
        'name': 'Updated Automatic Map Origin',
        'origin_version': '2',
        'world_view': 'Updated brief.',
        'world_setting': 'Updated setting.',
        'event_list': const <Map<String, Object?>>[],
        'cover': 'cover.webp',
        'character_list': const <Map<String, Object?>>[
          {'char_id': 'char_1', 'name': 'Ari', 'is_recommend': 0},
        ],
        'location_list': const <Map<String, Object?>>[],
        'deleted_char_ids': const ['char_removed'],
        'deleted_location_ids': const ['loc_removed'],
        'update_notes': 'Regenerate the map.',
      },
    );

    expect(result.oid, 'o_v2_updated');
    expect(apiTransport.lastRequest!.method, 'POST');
    expect(apiTransport.lastRequest!.uri.path, '/api/v2/origin/update');
    final body =
        jsonDecode(utf8.decode(apiTransport.lastRequest!.bodyBytes!))
            as Map<String, dynamic>;
    expect(body['origin_id'], 'o_v2_updated');
    expect(body['origin_name'], 'Updated Automatic Map Origin');
    expect(body['setting'], 'Updated setting.');
    expect(body['events'], isEmpty);
    expect((body['characters'] as List).single['is_recommend'], 0);
    expect(body['update_notes'], 'Regenerate the map.');
    expect(body['deleted_char_ids'], ['char_removed']);
    expect(body['deleted_location_ids'], ['loc_removed']);
    expect(body.containsKey('init_location_group'), isFalse);
  });

  test('getWorld maps tick_result narrator paragraphs from detail', () async {
    final apiTransport = _FakeTransport(
      handler: (request) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'err_no': 0,
          'err_msg': 'succ',
          'data': {
            'info': {
              'world_id': 'w_1',
              'world_name': 'World One',
              'origin_id': 'o_1',
              'definition_version': 2,
              'last_chat_location_id': 'loc_1',
              'owner_uid': 'u_1',
              'owner_name': 'Tester',
              'metric': const <String, Object?>{
                'mode': 'qualitative',
                'label': 'Goal Progress',
                'unit': '%',
                'range': <int>[0, 100],
                'default': 0,
              },
              'created_at': '2026-05-01T00:00:00Z',
              'updated_at': '2026-05-02T00:00:00Z',
              'status': 1,
            },
            'stats': {
              'tick_cnt': 1,
              'sub_tick_no': 3,
              'connect_cnt': 0,
              'character_cnt': 0,
              'player_cnt': 0,
            },
            'characters': const <Object?>[],
            'relation_status': 'owner',
            'locations': [
              {
                'location_id': 'loc_1',
                'location_name': 'Gate',
                'location_summary': '',
                'location_description': 'Gate fallback description.',
                'location_paragraph': 'Current Tick event.',
              },
            ],
            'ticks': [
              {
                'tick_no': 1,
                'created_at': '2026-05-02T00:00:00Z',
                'tick_result': {
                  'narrator': 'Narrator from tick result.',
                  'paragraphs': [
                    {
                      'location_id': 'loc_1',
                      'text': 'Location paragraph text.',
                      'character_deltas': [
                        {'name': 'Iris Vale', 'delta': '+3 focus'},
                      ],
                    },
                  ],
                },
              },
            ],
          },
        }),
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final world = await api.getWorld('w_1');
    final location = world.locations
        .where((item) => item['location_id'] == 'loc_1')
        .single;
    final tickResult = world.ticks.single['tick_result'] as Map;
    final paragraph = (tickResult['paragraphs'] as List).single as Map;

    expect(apiTransport.lastRequest!.uri.path, '/api/v1/world/detail');
    expect(apiTransport.lastRequest!.uri.queryParameters['world_id'], 'w_1');
    expect(location['location_summary'], '');
    expect(location['location_description'], 'Gate fallback description.');
    expect(location['location_paragraph'], 'Current Tick event.');
    expect(location['is_new'], false);
    expect(world.relationStatus, 'owner');
    expect(world.metric['label'], 'Goal Progress');
    expect(world.definitionVersion, 2);
    expect(world.subTickNo, 3);
    expect(world.lastChatLocationId, 'loc_1');
    expect(world.copyWith().lastChatLocationId, 'loc_1');
    expect(
      world.copyWith(lastChatLocationId: 'loc_2').lastChatLocationId,
      'loc_2',
    );
    expect(world.latestNarrator, 'Narrator from tick result.');
    expect(tickResult['narrator'], 'Narrator from tick result.');
    expect(paragraph['location_id'], 'loc_1');
    expect(paragraph['text'], 'Location paragraph text.');
    expect((paragraph['character_deltas'] as List).single, {
      'name': 'Iris Vale',
      'delta': '+3 focus',
    });
  });

  test('getWorld defaults a missing last chat location to empty', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"info":{"world_id":"w_1","world_name":"World One"},"stats":{}}}',
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final world = await api.getWorld('w_1');

    expect(world.lastChatLocationId, '');
  });

  test('getWorldMap accepts empty data for legacy definitions', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":0,"err_msg":"succ","data":{}}',
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final definition = await api.getWorldMap(
      worldId: 'w_1',
      locationId: 'loc_1',
    );

    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/world/map');
    expect(apiTransport.lastRequest!.uri.queryParameters, {
      'world_id': 'w_1',
      'location_id': 'loc_1',
    });
    expect(definition.isAvailable, false);
    expect(definition.tileTypes, isNull);
    expect(definition.mapJson, isNull);
  });

  test('getWorldInfo uses lightweight world info contract', () async {
    final apiTransport = _FakeTransport(
      handler: (request) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'err_no': 0,
          'err_msg': 'succ',
          'data': {
            'info': {
              'world_id': 'w_info_1',
              'world_name': 'World Info',
              'origin_id': 'o_info_1',
              'origin_version': '3',
              'current_time': 'Day 7, 19:10',
              'owner_uid': 'u_1',
              'owner_name': 'Tester',
              'brief': 'World brief.',
              'tags': ['light'],
              'created_at': 1716000000,
              'cover': const <String, Object?>{
                'sm_url': 'https://cdn.example.com/world_400.webp',
                'xl_url': 'https://cdn.example.com/world_800.webp',
                'object_key': 'uploads/world_800.webp',
              },
              'map_url': 'https://cdn.example.com/world-map.png',
              'status': 10,
            },
            'stats': {
              'character_cnt': 2,
              'connect_cnt': 3,
              'location_cnt': 4,
              'tick_cnt': 5,
              'player_cnt': 6,
            },
          },
        }),
      ),
    );
    final api = _apiWith(
      apiTransport,
      _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      ),
    );

    final world = await api.getWorldInfo('w_info_1');

    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/world/info');
    expect(
      apiTransport.lastRequest!.uri.queryParameters['world_id'],
      'w_info_1',
    );
    expect(world.worldId, 'w_info_1');
    expect(world.name, 'World Info');
    expect(world.ownerName, 'Tester');
    expect(world.brief, 'World brief.');
    expect(world.cover, 'https://cdn.example.com/world_800.webp');
    expect(world.origin.oid, 'o_info_1');
    expect(world.currentTime, 'Day 7, 19:10');
    expect(world.tickCount, 5);
    expect(world.connectCount, 3);
    expect(world.characterCount, 2);
    expect(world.playerCount, 6);
    expect(world.relationStatus, '');
    expect(world.characters, isEmpty);
    expect(world.locations, isEmpty);
    expect(world.ticks, isEmpty);
  });

  test('getWorld treats missing detail metric as empty map', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'err_no': 0,
          'err_msg': 'succ',
          'data': {
            'info': {
              'world_id': 'w_1',
              'world_name': 'World One',
              'origin_id': 'o_1',
              'owner_uid': 'u_1',
              'owner_name': 'Tester',
              'created_at': 1716000000,
              'status': 10,
            },
            'stats': const <String, Object?>{},
            'relation_status': 'anonymous',
            'characters': const <Object?>[],
            'locations': const <Object?>[],
            'ticks': const <Object?>[],
          },
        }),
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final world = await api.getWorld('w_1');

    expect(world.metric, isEmpty);
  });

  test(
    'getWorld accepts Apifox image objects except location map url',
    () async {
      Map<String, Object?> image(String name) => {
        'sm_url': 'https://cdn.example.com/${name}_400_300.webp',
        'xl_url': 'https://cdn.example.com/${name}_800_600.webp',
        'object_key': 'uploads/${name}_800_600.webp',
      };

      final apiTransport = _FakeTransport(
        handler: (_) => TransportResponse(
          statusCode: 200,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'err_no': 0,
            'err_msg': 'succ',
            'data': {
              'info': {
                'world_id': 'w_1',
                'world_name': 'World One',
                'origin_id': 'o_1',
                'owner_uid': 'u_1',
                'owner_name': 'Tester',
                'brief': 'Brief.',
                'setting': 'Setting.',
                'events': const <Object?>[],
                'tags': const <Object?>[],
                'metric': const <String, Object?>{},
                'created_at': 1716000000,
                'cover': image('world_cover'),
                'map_url': 'https://cdn.example.com/location_map.png',
                'status': 10,
              },
              'stats': const <String, Object?>{},
              'relation_status': 'owner',
              'characters': [
                {
                  'char_id': 'c_1',
                  'type': 'player',
                  'player_uid': 'u_1',
                  'player_username': 'Tester',
                  'player_deleted': 0,
                  'name': 'Iris',
                  'avatar': image('avatar'),
                  'location_id': 'loc_1',
                  'is_new': 1,
                },
              ],
              'locations': [
                {
                  'location_id': 'loc_1',
                  'level': 3,
                  'location_name': 'Gate',
                  'image': image('location'),
                  'map_url': 'https://cdn.example.com/location_map.png',
                  'is_new': true,
                },
              ],
              'ticks': const <Object?>[],
            },
          }),
        ),
      );
      final healthTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      );

      final api = _apiWith(apiTransport, healthTransport);
      final world = await api.getWorld('w_1');
      final character = world.characters.single;
      final mapCharacter =
          world.characterPositions.single['character'] as Map<String, dynamic>;
      final location = world.locations.single;

      expect(
        world.origin.mapImage,
        'https://cdn.example.com/world_cover_800_600.webp',
      );
      expect(
        character['avatar'],
        'https://cdn.example.com/avatar_800_600.webp',
      );
      expect(mapCharacter['player_uid'], 'u_1');
      expect(mapCharacter['player_username'], 'Tester');
      expect(mapCharacter['player_deleted'], false);
      expect(character['is_new'], true);
      expect(mapCharacter['is_new'], true);
      expect(location['icon'], 'https://cdn.example.com/location_800_600.webp');
      expect(location['map_url'], 'https://cdn.example.com/location_map.png');
      expect(location['level'], 3);
      expect(location['is_new'], true);
    },
  );

  test('launchWorld uses POST /worlds/launch with new body', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"ok":true,"wid":"wid_1","wid_str":"W_1"}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    await api.launchWorld(
      originId: 123,
      ownerUid: 'u_1',
      worldviewId: 'wv_1',
      worldName: 'World 1',
    );

    expect(apiTransport.lastRequest!.method, 'POST');
    expect(
      apiTransport.lastRequest!.uri.toString(),
      'http://localhost:8080/api/worlds/launch',
    );

    final body = utf8.decode(
      apiTransport.lastRequest!.bodyBytes ?? const <int>[],
    );
    expect(jsonDecode(body), {
      'user_id': 'u_1',
      'worldview_id': 'wv_1',
      'world_name': 'World 1',
    });
  });

  test('sendMessage uses POST /points/:point_id/messages/enqueue', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"ok":true,"user_message":{"id":"m_1"}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    await api.sendMessage(
      wid: 'wid_1',
      uid: 'u_1',
      pointId: 'pt_9',
      locationId: 'loc_3',
      content: 'Hello',
    );

    expect(apiTransport.lastRequest!.method, 'POST');
    expect(
      apiTransport.lastRequest!.uri.toString(),
      'http://localhost:8080/api/points/pt_9/messages/enqueue',
    );

    final body = utf8.decode(
      apiTransport.lastRequest!.bodyBytes ?? const <int>[],
    );
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    expect(decoded['user_id'], 'u_1');
    expect(decoded['wid'], 'wid_1');
    expect(decoded['location_id'], 'loc_3');
    expect(decoded['text'], 'Hello');
    expect(decoded['player_id'], 'player1');
  });

  test('health uses unsigned Gateway heartbeat', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"data":{}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final ok = await api.health();
    expect(ok, true);
    expect(
      healthTransport.lastRequest!.uri.toString(),
      'http://localhost:8080/v1/heartbeat',
    );
  });

  test('search uses GET /search with query', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"origins":[],"worlds":[],"users":[]}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    await api.search(query: 'ori', limit: 10);

    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/search');
    expect(apiTransport.lastRequest!.uri.queryParameters['q'], 'ori');
    expect(apiTransport.lastRequest!.uri.queryParameters['limit'], '10');
  });

  test(
    'default v1 client keeps business requests on configurable API base URL',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":0,"err_msg":"succ","data":{"list":[],"total":0}}',
        ),
      );

      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        platformConfig: const _TestPlatformConfig(
          apiBaseUrl: 'https://example.test/api/',
        ),
        gatewayApiBaseUrl: 'https://gateway.example.test/apix/',
      );
      await api.getOrigins();

      expect(
        apiTransport.lastRequest!.uri.toString(),
        'https://example.test/api/v1/origin/list?scene=foryou&pn=1&rn=20',
      );
    },
  );

  test('default v1 client targets dev API base URL', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":0,"err_msg":"succ","data":{"list":[],"total":0}}',
      ),
    );

    final api = GenesisApi(transport: apiTransport, useMock: false);
    await api.getOrigins();

    expect(
      apiTransport.lastRequest!.uri.toString(),
      '${GenesisApi.defaultApiBaseUrl}'
      'v1/origin/list?scene=foryou&pn=1&rn=20',
    );
  });

  test(
    'Origin feed carries signed X-Device-ID through the Gateway chain',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":0,"err_msg":"succ","data":{"list":[],"total":0}}',
        ),
      );
      final authTransport = _FakeTransport(handler: _gatewayAuthResponse);
      final interceptor = GatewayRequestInterceptor(
        coordinator: GatewayAuthCoordinator(
          gatewayBaseUrl: 'https://gateway.example.test/apix/',
          appHeaderProvider: () async => const {
            'app-id': 'hashed-app-id',
            'app-platform': 'ios',
            'app-version': '1.2.3',
          },
          deviceIdService: const _TestDeviceIdService(),
          keyStore: _FakeGatewayKeyStore(),
          registrationStore: _MemoryGatewayRegistrationStore(),
          transport: authTransport,
        ),
      );

      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        gatewayRequestInterceptor: interceptor,
      );
      await api.v1.origin.feed(startScore: 0, rn: 10);

      final request = apiTransport.lastRequest!;
      expect(request.uri.path, '/api/v1/origin/feed');
      expect(request.headers['X-App-ID'], 'hashed-app-id');
      expect(request.headers['X-Platform'], 'ios');
      expect(request.headers['X-Device-ID'], 'test-device-id');
      expect(request.headers['X-App-Version'], '1.2.3');
      expect(request.headers['X-Key-ID'], 'key-registered');
      expect(request.headers['X-Signature-Alg'], gatewaySignatureAlgorithm);
      expect(request.headers['X-Signature'], 'fake-signature');
      expect(request.headers['X-Body-SHA256'], gatewayBodySha256(null));
      expect(request.headers.containsKey('X-Timestamp'), isTrue);
      expect(request.headers.containsKey('X-Nonce'), isTrue);
      expect(
        authTransport.requests.map((request) => request.uri.path),
        containsAllInOrder([
          '/apix/v1/app/device/challenge',
          '/apix/v1/app/device/register',
          '/apix/v1/time',
        ]),
      );
    },
  );

  test(
    'chatroom API HTTP requests are signed when Gateway auth is enabled',
    () async {
      final apiTransport = _FakeTransport(
        handler: (request) {
          if (request.uri.path == '/aitown-chat/api/v2/messages') {
            return const TransportResponse(
              statusCode: 200,
              headers: {'content-type': 'application/json'},
              body:
                  '{"err_no":0,"err_msg":"succ","data":{"messages":[],"has_more":false,"newest_message_id":0}}',
            );
          }
          return const TransportResponse(
            statusCode: 404,
            headers: {'content-type': 'application/json'},
            body: '{"err_no":404,"err_msg":"not_found","data":{}}',
          );
        },
      );
      final authTransport = _FakeTransport(handler: _gatewayAuthResponse);
      final interceptor = GatewayRequestInterceptor(
        coordinator: GatewayAuthCoordinator(
          gatewayBaseUrl: 'https://gateway.example.test/apix/',
          appHeaderProvider: () async => const {
            'app-id': 'hashed-app-id',
            'app-platform': 'android',
            'app-version': '1.2.3',
          },
          deviceIdService: const _TestDeviceIdService(),
          keyStore: _FakeGatewayKeyStore(),
          registrationStore: _MemoryGatewayRegistrationStore(),
          transport: authTransport,
        ),
      );

      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        chatroomHttpBaseUrl: 'https://chat.example.test/',
        gatewayRequestInterceptor: interceptor,
      );
      await api.chatroomHttp.getMessages(
        worldId: 'world-1',
        locationId: 'loc-1',
      );

      final request = apiTransport.lastRequest!;
      expect(request.uri.path, '/aitown-chat/api/v2/messages');
      expect(request.headers['X-App-ID'], 'hashed-app-id');
      expect(request.headers['X-Platform'], 'android');
      expect(request.headers['X-Device-ID'], 'test-device-id');
      expect(request.headers['X-App-Version'], '1.2.3');
      expect(request.headers['X-Key-ID'], 'key-registered');
      expect(request.headers['X-Signature-Alg'], gatewaySignatureAlgorithm);
      expect(request.headers['X-Signature'], 'fake-signature');
      expect(request.headers['X-Body-SHA256'], gatewayBodySha256(null));
      expect(request.headers.containsKey('X-Timestamp'), isTrue);
      expect(request.headers.containsKey('X-Nonce'), isTrue);
    },
  );

  test('default client injects user agent and authorization headers', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":0,"err_msg":"succ","data":{"list":[],"total":0}}',
      ),
    );
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUid('u_1');
    await sessionStore.saveAuthToken('backend-token');

    final api = GenesisApi(
      transport: apiTransport,
      useMock: false,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: sessionStore,
      appHeaderProvider: () async => const {
        'user-agent': 'Android 15',
        'app-id': 'legacy-app-id',
        'app-version': '0.1.0',
        'app-platform': 'android',
        'device-id': 'legacy-device-id',
      },
    );
    await api.getOrigins();

    expect(apiTransport.lastRequest!.headers['user-agent'], 'Android 15');
    expect(apiTransport.lastRequest!.headers.containsKey('app-id'), isFalse);
    expect(
      apiTransport.lastRequest!.headers.containsKey('app-version'),
      isFalse,
    );
    expect(
      apiTransport.lastRequest!.headers.containsKey('app-platform'),
      isFalse,
    );
    expect(apiTransport.lastRequest!.headers.containsKey('device-id'), isFalse);
    expect(
      apiTransport.lastRequest!.headers.containsKey('x-platform'),
      isFalse,
    );
    expect(
      apiTransport.lastRequest!.headers.containsKey('x-device-id'),
      isFalse,
    );
    expect(apiTransport.lastRequest!.headers.containsKey('x-user-id'), isFalse);
    expect(
      apiTransport.lastRequest!.headers['authorization'],
      'Bearer backend-token',
    );
  });

  test(
    'loginWithGoogle stores backend token for later default auth header',
    () async {
      late final MemoryUserSessionStore sessionStore;
      final apiTransport = _FakeTransport(
        handler: (request) {
          if (request.uri.path.endsWith('/v1/user/oauth/google')) {
            final body =
                jsonDecode(utf8.decode(request.bodyBytes ?? const [])) as Map;
            expect(body.keys.toSet(), {'id_token', 'name', 'avatar'});
            expect(body['id_token'], 'google-token');
            expect(body['name'], 'Neo');
            expect(body['avatar'], 'https://cdn/neo.png');
            return const TransportResponse(
              statusCode: 200,
              headers: {'content-type': 'application/json'},
              body:
                  '{"err_no":0,"err_msg":"succ","data":{"token":"backend-token","user":{"uid":"u_2","name":"Neo"}}}',
            );
          }
          return const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body: '{"err_no":0,"err_msg":"succ","data":{"list":[],"total":0}}',
          );
        },
      );
      sessionStore = MemoryUserSessionStore();
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
      );

      await api.loginWithGoogle(
        idToken: 'google-token',
        name: 'Neo',
        avatar: 'https://cdn/neo.png',
      );
      expect(await sessionStore.readUid(), 'u_2');
      expect(await sessionStore.readAuthToken(), 'backend-token');
      expect(await sessionStore.readUserInfo(), containsPair('uid', 'u_2'));
      expect(await sessionStore.readUserInfo(), containsPair('name', 'Neo'));

      await api.getOrigins();
      expect(
        apiTransport.lastRequest!.headers['authorization'],
        'Bearer backend-token',
      );
    },
  );

  test('loginWithIdentity posts Apple tokens and stores backend token', () async {
    final apiTransport = _FakeTransport(
      handler: (request) {
        if (request.uri.path.endsWith('/v1/user/oauth/apple')) {
          final body =
              jsonDecode(utf8.decode(request.bodyBytes ?? const [])) as Map;
          expect(body.keys.toSet(), {'id_token', 'name', 'avatar'});
          expect(body['id_token'], 'apple-token');
          expect(body.containsKey('firebase_id_token'), isFalse);
          expect(body['name'], 'Ava');
          return const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body:
                '{"err_no":0,"err_msg":"succ","data":{"token":"apple-backend-token","user":{"uid":"apple_uid","name":"Ava"}}}',
          );
        }
        return const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":0,"err_msg":"succ","data":{"list":[],"total":0}}',
        );
      },
    );
    final sessionStore = MemoryUserSessionStore();
    final api = GenesisApi(
      transport: apiTransport,
      useMock: false,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: sessionStore,
    );

    await api.loginWithIdentity(
      const AuthSession(
        provider: IdentityProvider.apple,
        providerIdToken: 'apple-token',
        displayName: 'Ava',
        photoUrl: '',
      ),
    );

    expect(await sessionStore.readUid(), 'apple_uid');
    expect(await sessionStore.readAuthToken(), 'apple-backend-token');
    expect(await sessionStore.readUserInfo(), containsPair('uid', 'apple_uid'));
    expect(
      await sessionStore.readUserInfo(),
      containsPair('login_provider', 'apple'),
    );
  });

  test(
    'session check preserves token-only state without requesting user info',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => throw StateError('user info must not be requested'),
      );
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveAuthToken('orphaned-backend-token');
      await sessionStore.saveUserInfo({
        'name': 'Stale User',
        'login_provider': 'google',
      });
      final identityAuth = _FakeIdentityAuthService(
        refreshSession: const AuthSession(
          provider: IdentityProvider.google,
          providerIdToken: 'provider-token',
          displayName: 'Stale User',
          photoUrl: '',
        ),
      );
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
        identityAuthService: identityAuth,
      );

      expect(await api.hasAuthenticatedSession(), isFalse);
      expect(apiTransport.requests, isEmpty);
      expect(identityAuth.refreshCount, 0);
      expect(await sessionStore.readUid(), isNull);
      expect(await sessionStore.readAuthToken(), 'orphaned-backend-token');
      expect(
        await sessionStore.readUserInfo(),
        containsPair('login_provider', 'google'),
      );
    },
  );

  test('session check restores a missing backend token from identity', () async {
    final apiTransport = _FakeTransport(
      handler: (request) {
        if (request.uri.path.endsWith('/v1/user/oauth/google')) {
          return const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body:
                '{"err_no":0,"err_msg":"succ","data":{"token":"restored-token","user":{"uid":"u_google"}}}',
          );
        }
        if (request.uri.path.endsWith('/v1/user/info')) {
          return const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body:
                '{"err_no":0,"err_msg":"succ","data":{"user":{"uid":"u_google"},"relation":{"is_self":true}}}',
          );
        }
        throw StateError('unexpected request: ${request.uri}');
      },
    );
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUid('u_google');
    await sessionStore.saveUserInfo({
      'uid': 'u_google',
      'login_provider': 'google',
    });
    final identityAuth = _FakeIdentityAuthService(
      refreshSession: const AuthSession(
        provider: IdentityProvider.google,
        providerIdToken: 'provider-token',
        displayName: 'Google User',
        photoUrl: '',
      ),
    );
    final api = GenesisApi(
      transport: apiTransport,
      useMock: false,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: sessionStore,
      identityAuthService: identityAuth,
    );

    expect(await api.hasAuthenticatedSession(), isTrue);
    expect(identityAuth.refreshCount, 1);
    expect(await sessionStore.readUid(), 'u_google');
    expect(await sessionStore.readAuthToken(), 'restored-token');
  });

  test('failed token restoration preserves the UID login state', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => throw StateError('request must not be sent'),
    );
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUid('u_google');
    await sessionStore.saveUserInfo({
      'uid': 'u_google',
      'login_provider': 'google',
    });
    final identityAuth = _FakeIdentityAuthService();
    final api = GenesisApi(
      transport: apiTransport,
      useMock: false,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: sessionStore,
      identityAuthService: identityAuth,
    );

    expect(await api.hasAuthenticatedSession(), isFalse);
    expect(identityAuth.refreshCount, 1);
    expect(apiTransport.requests, isEmpty);
    expect(await sessionStore.readUid(), 'u_google');
    expect(await sessionStore.readAuthToken(), isNull);
  });

  test('err_no 10001 uses the global session-expired handler', () async {
    final sessionExpired = Completer<String>();
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":10001,"err_msg":"expired","data":{}}',
      ),
    );
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUid('u_google');
    await sessionStore.saveAuthToken('expired-backend-token');
    await sessionStore.saveUserInfo({
      'uid': 'u_google',
      'login_provider': 'google',
    });
    final identityAuth = _FakeIdentityAuthService(
      refreshSession: const AuthSession(
        provider: IdentityProvider.google,
        providerIdToken: 'provider-token',
        displayName: 'Google User',
        photoUrl: '',
      ),
    );
    final api = GenesisApi(
      transport: apiTransport,
      useMock: false,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: sessionStore,
      identityAuthService: identityAuth,
      onSessionExpired: (message) async {
        if (!sessionExpired.isCompleted) sessionExpired.complete(message);
      },
    );

    expect(await api.hasAuthenticatedSession(), isFalse);
    expect(
      await sessionExpired.future,
      'Your account is logged in on another device.',
    );
    expect(identityAuth.refreshCount, 0);
    expect(
      apiTransport.requests.where(
        (request) => request.uri.path.contains('/v1/user/oauth/'),
      ),
      isEmpty,
    );
  });

  test('HTTP 401 silently refreshes without triggering err_no handling', () async {
    var userInfoCount = 0;
    var sessionExpiredCalled = false;
    final apiTransport = _FakeTransport(
      handler: (request) {
        if (request.uri.path.endsWith('/v1/user/info')) {
          userInfoCount += 1;
          if (userInfoCount == 1) {
            return const TransportResponse(
              statusCode: 401,
              headers: {'content-type': 'application/json'},
              body: '{"err_no":10001,"err_msg":"expired","data":{}}',
            );
          }
          return const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body:
                '{"err_no":0,"err_msg":"succ","data":{"user":{"uid":"u_google"},"relation":{"is_self":true}}}',
          );
        }
        if (request.uri.path.endsWith('/v1/user/oauth/google')) {
          return const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body:
                '{"err_no":0,"err_msg":"succ","data":{"token":"new-backend-token","user":{"uid":"u_google"}}}',
          );
        }
        return const TransportResponse(
          statusCode: 404,
          headers: {'content-type': 'application/json'},
          body: '{"error":"not_found"}',
        );
      },
    );
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUid('u_google');
    await sessionStore.saveAuthToken('backend-token');
    await sessionStore.saveUserInfo({
      'uid': 'u_google',
      'login_provider': 'google',
    });
    final identityAuth = _FakeIdentityAuthService(
      refreshSession: const AuthSession(
        provider: IdentityProvider.google,
        providerIdToken: 'provider-token',
        displayName: 'Google User',
        photoUrl: '',
      ),
    );
    final api = GenesisApi(
      transport: apiTransport,
      useMock: false,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: sessionStore,
      identityAuthService: identityAuth,
      onSessionExpired: (_) async {
        sessionExpiredCalled = true;
      },
    );

    expect(await api.hasAuthenticatedSession(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(sessionExpiredCalled, isFalse);
    expect(identityAuth.refreshCount, 1);
    expect(await sessionStore.readAuthToken(), 'new-backend-token');
    expect(
      apiTransport.requests.where(
        (request) => request.uri.path.contains('/v1/user/oauth/'),
      ),
      hasLength(1),
    );
  });

  test('HTTP 403 does not trigger silent auth refresh', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 403,
        headers: {'content-type': 'application/json'},
        body: '{"error":"forbidden"}',
      ),
    );
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUid('u_google');
    await sessionStore.saveAuthToken('backend-token');
    await sessionStore.saveUserInfo({
      'uid': 'u_google',
      'login_provider': 'google',
    });
    final identityAuth = _FakeIdentityAuthService(
      refreshSession: const AuthSession(
        provider: IdentityProvider.google,
        providerIdToken: 'provider-token',
        displayName: 'Google User',
        photoUrl: '',
      ),
    );
    final api = GenesisApi(
      transport: apiTransport,
      useMock: false,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: sessionStore,
      identityAuthService: identityAuth,
    );

    expect(await api.hasAuthenticatedSession(), isFalse);
    expect(identityAuth.refreshCount, 0);
    expect(
      apiTransport.requests.where(
        (request) => request.uri.path.contains('/v1/user/oauth/'),
      ),
      isEmpty,
    );
  });

  test(
    'loginWithIdentity does not persist uid when backend omits user id',
    () async {
      final apiTransport = _FakeTransport(
        handler: (request) {
          if (request.uri.path.endsWith('/v1/user/oauth/apple')) {
            return const TransportResponse(
              statusCode: 200,
              headers: {'content-type': 'application/json'},
              body:
                  '{"err_no":0,"err_msg":"succ","data":{"token":"apple-backend-token","user":{}}}',
            );
          }
          return const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body: '{"err_no":0,"err_msg":"succ","data":{"list":[],"total":0}}',
          );
        },
      );
      final sessionStore = MemoryUserSessionStore();
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
      );

      await expectLater(
        api.loginWithIdentity(
          const AuthSession(
            provider: IdentityProvider.apple,
            providerIdToken: 'apple-token',
            displayName: 'Ava',
            photoUrl: '',
          ),
        ),
        throwsA(isA<ApiException>()),
      );

      expect(await sessionStore.readUid(), isNull);
      expect(await sessionStore.readAuthToken(), isNull);
      expect(await sessionStore.readUserInfo(), isNull);
    },
  );

  test(
    'backend login failure clears identity session for provider retry',
    () async {
      final apiTransport = _FakeTransport(
        handler: (request) {
          if (request.uri.path.endsWith('/v1/user/oauth/google')) {
            return const TransportResponse(
              statusCode: 200,
              headers: {'content-type': 'application/json'},
              body: '{"err_no":10013,"err_msg":"user banned","data":{}}',
            );
          }
          return const TransportResponse(
            statusCode: 404,
            headers: {'content-type': 'application/json'},
            body: '{"err_no":404,"err_msg":"not_found","data":{}}',
          );
        },
      );
      final sessionStore = MemoryUserSessionStore();
      final identityAuth = _FakeIdentityAuthService();
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
        identityAuthService: identityAuth,
      );
      final coordinator = GenesisBackendAuthCoordinator(
        api: api,
        identityAuth: identityAuth,
        sessionStore: sessionStore,
      );

      await expectLater(
        coordinator.loginWithIdentity(
          const AuthSession(
            provider: IdentityProvider.google,
            providerIdToken: 'google-token',
            displayName: 'User',
            photoUrl: '',
          ),
        ),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 10013)
              .having((error) => error.message, 'message', 'user banned'),
        ),
      );

      expect(identityAuth.signOutCount, 1);
      expect(await sessionStore.readUid(), isNull);
      expect(await sessionStore.readAuthToken(), isNull);
    },
  );

  test(
    'loginWithIdentity preserves existing state when backend omits auth token',
    () async {
      final apiTransport = _FakeTransport(
        handler: (request) {
          if (request.uri.path.endsWith('/v1/user/oauth/apple')) {
            return const TransportResponse(
              statusCode: 200,
              headers: {'content-type': 'application/json'},
              body:
                  '{"err_no":0,"err_msg":"succ","data":{"user":{"uid":"u_without_token"}}}',
            );
          }
          throw StateError('unexpected request');
        },
      );
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveUid('stale-uid');
      await sessionStore.saveAuthToken('stale-token');
      await sessionStore.saveUserInfo({'uid': 'stale-uid'});
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
      );

      await expectLater(
        api.loginWithIdentity(
          const AuthSession(
            provider: IdentityProvider.apple,
            providerIdToken: 'apple-token',
            displayName: '',
            photoUrl: '',
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            'Login response missing auth token',
          ),
        ),
      );

      expect(await sessionStore.readUid(), 'stale-uid');
      expect(await sessionStore.readAuthToken(), 'stale-token');
      expect(await sessionStore.readUserInfo(), {'uid': 'stale-uid'});
    },
  );

  for (final provider in IdentityProvider.values) {
    test(
      'successful ${provider.name} login records login and login_first',
      () async {
        final collectStore = MemoryCollectEventStore();
        final collectUploader = CollectTelemetryUploader(store: collectStore)
          ..configure(enabled: true);
        GenesisTelemetry.setCollectUploaderForTesting(collectUploader);
        addTearDown(GenesisTelemetry.resetForTesting);
        GenesisTelemetry.setUserId('u_previous');
        await GenesisTelemetry.collectLogAndWait(
          actionType: 'event',
          action: 'before_session_expired',
        );
        GenesisTelemetry.clearUser();
        await GenesisTelemetry.collectLogAndWait(
          actionType: 'event',
          action: 'after_session_expired',
        );

        final analytics = _RecordingFirebaseAnalyticsClient();
        FirebaseAnalyticsMonitoring.resetForTesting();
        FirebaseAnalyticsMonitoring.setClientForTesting(analytics);
        FirebaseAnalyticsMonitoring.setOnceEventStoreForTesting(
          _MemoryFirebaseAnalyticsOnceEventStore(),
        );
        FirebaseAnalyticsMonitoring.setEnabledForTesting(true);
        FirebaseAnalyticsMonitoring.setReadinessForTesting(
          Future<void>.value(),
        );
        FirebaseAnalyticsMonitoring.setDeviceIdReaderForTesting(
          () async => 'test-device-id',
        );
        addTearDown(FirebaseAnalyticsMonitoring.resetForTesting);

        final apiTransport = _FakeTransport(
          handler: (request) {
            expect(
              request.uri.path,
              endsWith('/v1/user/oauth/${provider.name}'),
            );
            return const TransportResponse(
              statusCode: 200,
              headers: {'content-type': 'application/json'},
              body:
                  '{"err_no":0,"err_msg":"succ","data":{"token":"backend-token","user":{"uid":"u_login","name":"User"}}}',
            );
          },
        );
        final sessionStore = MemoryUserSessionStore();
        final identityAuth = _FakeIdentityAuthService();
        final deviceInfoLoginUids = <String>[];
        final api = GenesisApi(
          transport: apiTransport,
          useMock: false,
          deviceIdService: const _TestDeviceIdService(),
          sessionStore: sessionStore,
          identityAuthService: identityAuth,
        );
        final coordinator = GenesisBackendAuthCoordinator(
          api: api,
          identityAuth: identityAuth,
          sessionStore: sessionStore,
          onLoginSuccess: (uid) async => deviceInfoLoginUids.add(uid),
        );

        await coordinator.loginWithIdentity(
          AuthSession(
            provider: provider,
            providerIdToken: '${provider.name}-token',
            displayName: 'User',
            photoUrl: '',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(analytics.events, <_FirebaseAnalyticsEvent>[
          _FirebaseAnalyticsEvent('login', <String, Object>{
            'method': provider.name,
            'device_id': 'test-device-id',
          }),
          _FirebaseAnalyticsEvent('login_first', <String, Object>{
            'method': provider.name,
            'device_id': 'test-device-id',
          }),
        ]);
        expect(deviceInfoLoginUids, <String>['u_login']);
        final identityEvents = collectStore.eventsForTesting.where(
          (event) => const {
            'before_session_expired',
            'after_session_expired',
            'login',
          }.contains(event.action),
        );
        expect(identityEvents.map((event) => (event.action, event.userId)), [
          ('before_session_expired', 'u_previous'),
          ('after_session_expired', ''),
          ('login', 'u_login'),
        ]);
      },
    );
  }

  test('backend login waits for gateway preparation', () async {
    final preparation = Completer<void>();
    final apiTransport = _FakeTransport(
      handler: (request) {
        expect(request.uri.path, endsWith('/v1/user/oauth/google'));
        return const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body:
              '{"err_no":0,"err_msg":"succ","data":{"token":"backend-token","user":{"uid":"u_2","name":"User"}}}',
        );
      },
    );
    final sessionStore = MemoryUserSessionStore();
    final identityAuth = _FakeIdentityAuthService();
    final api = GenesisApi(
      transport: apiTransport,
      useMock: false,
      deviceIdService: const _TestDeviceIdService(),
      sessionStore: sessionStore,
      identityAuthService: identityAuth,
    );
    final coordinator = GenesisBackendAuthCoordinator(
      api: api,
      identityAuth: identityAuth,
      sessionStore: sessionStore,
      prepareBackendRequest: () => preparation.future,
    );

    final login = coordinator.loginWithIdentity(
      const AuthSession(
        provider: IdentityProvider.google,
        providerIdToken: 'google-token',
        displayName: 'User',
        photoUrl: '',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(apiTransport.requests, isEmpty);

    preparation.complete();
    final user = await login;

    expect(user.uid, 'u_2');
    expect(apiTransport.requests, hasLength(1));
  });

  test(
    'backend signOut posts logout then clears identity and local session',
    () async {
      final apiTransport = _FakeTransport(
        handler: (request) {
          if (request.uri.path.endsWith('/v1/user/logout')) {
            expect(request.method, 'POST');
            expect(request.headers['authorization'], 'Bearer backend-token');
            return const TransportResponse(
              statusCode: 200,
              headers: {'content-type': 'application/json'},
              body: '{"err_no":0,"err_msg":"succ","data":{}}',
            );
          }
          return const TransportResponse(
            statusCode: 404,
            headers: {'content-type': 'application/json'},
            body: '{"error":"not_found"}',
          );
        },
      );
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveUid('u_2');
      await sessionStore.saveAuthToken('backend-token');
      final identityAuth = _FakeIdentityAuthService();
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
        identityAuthService: identityAuth,
      );
      final coordinator = GenesisBackendAuthCoordinator(
        api: api,
        identityAuth: identityAuth,
        sessionStore: sessionStore,
      );

      await coordinator.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(apiTransport.requests.single.uri.path, '/api/v1/user/logout');
      expect(
        apiTransport.requests.single.headers['authorization'],
        'Bearer backend-token',
      );
      expect(identityAuth.signOutCount, 1);
      expect(await sessionStore.readUid(), isNull);
      expect(await sessionStore.readAuthToken(), isNull);
      expect(await sessionStore.readUserInfo(), isNull);
    },
  );

  test(
    'backend signOut clears local session without waiting for logout response',
    () async {
      final logoutResponse = Completer<TransportResponse>();
      final apiTransport = _FakeTransport(
        handler: (_) => logoutResponse.future,
      );
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveUid('u_2');
      await sessionStore.saveAuthToken('backend-token');
      await sessionStore.saveUserInfo({'uid': 'u_2'});
      final identityAuth = _FakeIdentityAuthService();
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
        identityAuthService: identityAuth,
      );
      final coordinator = GenesisBackendAuthCoordinator(
        api: api,
        identityAuth: identityAuth,
        sessionStore: sessionStore,
      );

      await coordinator.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(logoutResponse.isCompleted, isFalse);
      expect(apiTransport.requests.single.uri.path, '/api/v1/user/logout');
      expect(
        apiTransport.requests.single.headers['authorization'],
        'Bearer backend-token',
      );
      expect(await sessionStore.readUid(), isNull);
      expect(await sessionStore.readAuthToken(), isNull);
      expect(await sessionStore.readUserInfo(), isNull);

      logoutResponse.complete(
        const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":0,"err_msg":"succ","data":{}}',
        ),
      );
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'backend signOut still clears local session when logout endpoint fails',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 500,
          headers: {'content-type': 'application/json'},
          body: '{"error":"server_error"}',
        ),
      );
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveUid('u_2');
      await sessionStore.saveAuthToken('backend-token');
      final identityAuth = _FakeIdentityAuthService();
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
        identityAuthService: identityAuth,
      );
      final coordinator = GenesisBackendAuthCoordinator(
        api: api,
        identityAuth: identityAuth,
        sessionStore: sessionStore,
      );

      await coordinator.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(identityAuth.signOutCount, 1);
      expect(await sessionStore.readUid(), isNull);
      expect(await sessionStore.readAuthToken(), isNull);
      expect(await sessionStore.readUserInfo(), isNull);
    },
  );

  test(
    'backend deleteAccount posts user delete then clears local session',
    () async {
      final deleteResponse = Completer<TransportResponse>();
      final apiTransport = _FakeTransport(
        handler: (request) {
          if (request.uri.path.endsWith('/v1/user/delete')) {
            expect(request.method, 'POST');
            expect(request.headers['authorization'], 'Bearer backend-token');
            return deleteResponse.future;
          }
          return const TransportResponse(
            statusCode: 404,
            headers: {'content-type': 'application/json'},
            body: '{"error":"not_found"}',
          );
        },
      );
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveUid('u_2');
      await sessionStore.saveAuthToken('backend-token');
      await sessionStore.saveUserInfo({'uid': 'u_2'});
      final identityAuth = _FakeIdentityAuthService();
      final api = GenesisApi(
        transport: apiTransport,
        useMock: false,
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
        identityAuthService: identityAuth,
      );
      final coordinator = GenesisBackendAuthCoordinator(
        api: api,
        identityAuth: identityAuth,
        sessionStore: sessionStore,
      );

      await coordinator.deleteAccount();
      await Future<void>.delayed(Duration.zero);

      expect(deleteResponse.isCompleted, isFalse);
      expect(apiTransport.requests.single.uri.path, '/api/v1/user/delete');
      expect(
        apiTransport.requests.single.headers['authorization'],
        'Bearer backend-token',
      );
      expect(identityAuth.signOutCount, 1);
      expect(await sessionStore.readUid(), isNull);
      expect(await sessionStore.readAuthToken(), isNull);
      expect(await sessionStore.readUserInfo(), isNull);

      deleteResponse.complete(
        const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":0,"err_msg":"succ","data":{}}',
        ),
      );
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('v1 origin list uses Apifox query format', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":0,"err_msg":"succ","data":{"list":[],"total":0}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final result = await api.v1.origin.list(
      scene: 'tag',
      tag: 'politics',
      keyword: 'steam',
      pn: 2,
      rn: 10,
    );

    expect(result['total'], 0);
    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/origin/list');
    expect(apiTransport.lastRequest!.uri.queryParameters['scene'], 'tag');
    expect(apiTransport.lastRequest!.uri.queryParameters['tag'], 'politics');
    expect(apiTransport.lastRequest!.uri.queryParameters['keyword'], 'steam');
    expect(
      apiTransport.lastRequest!.uri.queryParameters.containsKey('tag_name'),
      false,
    );
    expect(apiTransport.lastRequest!.uri.queryParameters['pn'], '2');
    expect(apiTransport.lastRequest!.uri.queryParameters['rn'], '10');
  });

  test('v1 list and feed responses preserve map metadata in info', () async {
    final apiTransport = _FakeTransport(
      handler: (request) => TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: request.uri.path.endsWith('/origin/list')
            ? '{"err_no":0,"err_msg":"succ","data":{"list":[{"info":{"origin_id":"o_1","definition_version":2,"default_map_location_id":"loc_origin"},"stats":{}}],"total":1,"pn":1,"rn":10}}'
            : request.uri.path.endsWith('/origin/feed')
            ? '{"err_no":0,"err_msg":"succ","data":{"list":[{"info":{"origin_id":"o_feed","definition_version":2,"default_map_location_id":"loc_feed"},"stats":{}}],"rn":10,"next_score":1,"has_more":false}}'
            : '{"err_no":0,"err_msg":"succ","data":{"list":[{"info":{"world_id":"w_1","definition_version":2,"default_map_location_id":"loc_world"},"stats":{}}],"total":1,"pn":1,"rn":10}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );
    final api = _apiWith(apiTransport, healthTransport);

    final originData = await api.v1.origin.list(scene: 'popular');
    final originFeedData = await api.v1.origin.feed(startScore: 0);
    final worldData = await api.v1.world.list(scene: 'mine');
    final originInfo =
        ((originData['list'] as List).single as Map)['info'] as Map;
    final worldInfo =
        ((worldData['list'] as List).single as Map)['info'] as Map;
    final originFeedInfo =
        ((originFeedData['list'] as List).single as Map)['info'] as Map;

    expect(originInfo['definition_version'], 2);
    expect(originInfo['default_map_location_id'], 'loc_origin');
    expect(originFeedInfo['definition_version'], 2);
    expect(originFeedInfo['default_map_location_id'], 'loc_feed');
    expect(worldInfo['definition_version'], 2);
    expect(worldInfo['default_map_location_id'], 'loc_world');
  });

  test('v1 origin hot tags uses Apifox response format', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":0,"err_msg":"succ","data":{"list":["校园","恋爱","校园"]}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final result = await api.v1.origin.hotTags();

    expect(result, <String>['校园', '恋爱', '校园']);
    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/origin/hot_tags');
  });

  test('v1 direct message send posts Apifox JSON body', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"message":{"msg_id":"m1"}}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    await api.v1.dm.send(peerUid: 'U_2', content: 'hello');

    expect(apiTransport.lastRequest!.method, 'POST');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/direct_message/send');
    final body = jsonDecode(utf8.decode(apiTransport.lastRequest!.bodyBytes!));
    expect(body['peer_uid'], 'U_2');
    expect(body['content'], 'hello');
    expect(body.containsKey('targetUid'), isFalse);
    expect(body.containsKey('peerUid'), isFalse);
    expect(body.containsKey('target_uid'), isFalse);
    expect(body.containsKey('client_msg_id'), isFalse);
  });

  test('v1 message notifications uses Apifox block query', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"list":[],"total":0,"pn":1,"rn":20}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    await api.v1.messages.notifications(block: 'interaction', pn: 1, rn: 20);

    expect(apiTransport.lastRequest!.method, 'GET');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/message/notifications');
    expect(
      apiTransport.lastRequest!.uri.queryParameters['block'],
      'interaction',
    );
    expect(apiTransport.lastRequest!.uri.queryParameters['pn'], '1');
    expect(apiTransport.lastRequest!.uri.queryParameters['rn'], '20');
    expect(
      apiTransport.lastRequest!.uri.queryParameters.containsKey('category'),
      isFalse,
    );
  });

  test('v1 mark notifications read posts Apifox block body', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":0,"err_msg":"succ","data":{}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    await api.v1.messages.markNotificationsRead(block: 'world_apply');

    expect(apiTransport.lastRequest!.method, 'POST');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/message/read');
    final body = jsonDecode(utf8.decode(apiTransport.lastRequest!.bodyBytes!));
    expect(body['block'], 'world_apply');
    expect(body.containsKey('category'), isFalse);
    expect(body.containsKey('notification_ids'), isFalse);
  });

  test(
    'v1 direct message conversations supports after_message_id cursor',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":0,"err_msg":"succ","data":{"list":[]}}',
        ),
      );
      final healthTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      );

      final api = _apiWith(apiTransport, healthTransport);
      await api.v1.dm.conversations(
        pn: 2,
        rn: 20,
        afterMessageId: 'DM_CURSOR_001',
      );

      expect(apiTransport.lastRequest!.method, 'GET');
      expect(
        apiTransport.lastRequest!.uri.path,
        '/api/v1/direct_message/conversations',
      );
      expect(
        apiTransport.lastRequest!.uri.queryParameters.containsKey('pn'),
        isFalse,
      );
      expect(
        apiTransport.lastRequest!.uri.queryParameters.containsKey('rn'),
        isFalse,
      );
      expect(
        apiTransport.lastRequest!.uri.queryParameters['after_message_id'],
        'DM_CURSOR_001',
      );
    },
  );

  test('v1 API throws ApiException when err_no is non-zero', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":1001,"err_msg":"bad request","data":{}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);

    expect(
      () => api.v1.user.info(),
      throwsA(
        isA<ApiException>().having((e) => e.message, 'message', 'bad request'),
      ),
    );
  });

  test(
    'v1 discuss list uses Apifox query and normalizes response keys',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body:
              '{"errNo":0,"errStr":"success","data":{"list":[{"comment":{"discussId":"dis_001","isLiked":true,"likeCnt":11},"latestReplies":[{"discussId":"dis_002","rootDiscussId":"dis_001"}]}],"topTotal":1,"totalAll":2,"pn":1,"rn":20}}',
        ),
      );
      final healthTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      );

      final api = _apiWith(apiTransport, healthTransport);
      final result = await api.v1.discuss.list(bizId: 'ori_001', pn: 1, rn: 20);

      expect(apiTransport.lastRequest!.method, 'GET');
      expect(apiTransport.lastRequest!.uri.path, '/api/v1/discuss/list');
      expect(apiTransport.lastRequest!.uri.queryParameters['biz_type'], '1');
      expect(
        apiTransport.lastRequest!.uri.queryParameters['biz_id'],
        'ori_001',
      );
      expect(
        apiTransport.lastRequest!.uri.queryParameters.containsKey('bizType'),
        isFalse,
      );
      final item = (result['list'] as List).first as Map<String, dynamic>;
      final comment = item['comment'] as Map<String, dynamic>;
      expect(comment['discuss_id'], 'dis_001');
      expect(comment['is_liked'], isTrue);
      expect(comment['like_cnt'], 11);
      expect(comment.containsKey('discussId'), isFalse);
      final replies = item['latest_replies'] as List;
      expect((replies.first as Map)['discuss_id'], 'dis_002');
      expect(result['top_total'], 1);
      expect(result['total_all'], 2);
    },
  );

  test(
    'v1 discuss replies uses Apifox root query and normalizes response keys',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body:
              '{"errNo":0,"errStr":"success","data":{"list":[{"discussId":"dis_reply_001","rootDiscussId":"dis_root","parentDiscussId":"dis_parent","isLiked":false,"likeCnt":3}],"total":1,"pn":2,"rn":20}}',
        ),
      );
      final healthTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      );

      final api = _apiWith(apiTransport, healthTransport);
      final result = await api.v1.discuss.replies(
        rootDiscussId: 'dis_root',
        pn: 2,
        rn: 20,
      );

      expect(apiTransport.lastRequest!.method, 'GET');
      expect(apiTransport.lastRequest!.uri.path, '/api/v1/discuss/replies');
      expect(
        apiTransport.lastRequest!.uri.queryParameters['root_discuss_id'],
        'dis_root',
      );
      expect(apiTransport.lastRequest!.uri.queryParameters['pn'], '2');
      expect(apiTransport.lastRequest!.uri.queryParameters['rn'], '20');
      expect(
        apiTransport.lastRequest!.uri.queryParameters.containsKey(
          'rootDiscussId',
        ),
        isFalse,
      );
      final reply = (result['list'] as List).first as Map<String, dynamic>;
      expect(reply['discuss_id'], 'dis_reply_001');
      expect(reply['root_discuss_id'], 'dis_root');
      expect(reply['parent_discuss_id'], 'dis_parent');
      expect(reply['is_liked'], isFalse);
      expect(reply['like_cnt'], 3);
      expect(result['total'], 1);
    },
  );

  test(
    'v1 world origin progress uses Apifox query and normalizes response',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body:
              '{"errNo":0,"errStr":"success","data":{"worldId":"w_a1b2c3","tickCnt":12}}',
        ),
      );
      final healthTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      );

      final api = _apiWith(apiTransport, healthTransport);
      final result = await api.v1.world.originProgress(
        uid: 'u_a1b2c3',
        originId: 'ori_a1b2c3',
      );

      expect(apiTransport.lastRequest!.method, 'GET');
      expect(
        apiTransport.lastRequest!.uri.path,
        '/api/v1/world/origin_progress',
      );
      expect(apiTransport.lastRequest!.uri.queryParameters['uid'], 'u_a1b2c3');
      expect(
        apiTransport.lastRequest!.uri.queryParameters['origin_id'],
        'ori_a1b2c3',
      );
      expect(
        apiTransport.lastRequest!.uri.queryParameters.containsKey('originId'),
        isFalse,
      );
      expect(result['world_id'], 'w_a1b2c3');
      expect(result['tick_cnt'], 12);
      expect(result.containsKey('worldId'), isFalse);
    },
  );

  test(
    'latest world summaries use Apifox query and normalize response',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body:
              '{"errNo":0,"errStr":"success","data":{"list":[{"worldId":"w_peer","originId":"o_1","tickNo":12,"subTickNo":3,"summary":"latest summary","tickTime":1780000000,"createdAt":1780000010}]}}',
        ),
      );
      final healthTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      );

      final api = _apiWith(apiTransport, healthTransport);
      final result = await api.getLatestWorldSummaries(
        originId: 'o_1',
        worldId: 'w_self',
      );

      expect(apiTransport.lastRequest!.method, 'GET');
      expect(
        apiTransport.lastRequest!.uri.path,
        '/api/v1/world/summary/latest',
      );
      expect(apiTransport.lastRequest!.uri.queryParameters['origin_id'], 'o_1');
      expect(
        apiTransport.lastRequest!.uri.queryParameters['world_id'],
        'w_self',
      );
      expect(
        apiTransport.lastRequest!.uri.queryParameters.containsKey('originId'),
        isFalse,
      );
      expect(
        apiTransport.lastRequest!.uri.queryParameters.containsKey('worldId'),
        isFalse,
      );
      expect(result.single.worldId, 'w_peer');
      expect(result.single.originId, 'o_1');
      expect(result.single.tickNo, 12);
      expect(result.single.subTickNo, 3);
      expect(result.single.summary, 'latest summary');
      expect(result.single.tickTime, 1780000000);
      expect(result.single.createdAt, 1780000010);
    },
  );

  test(
    'getWorldTicks uses Apifox tick list query and normalizes ticks',
    () async {
      final apiTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body:
              '{"errNo":0,"errStr":"success","data":{"list":[{"tickId":"tick_2","tickNo":2,"subTickNo":1,"status":50,"tickResult":{"currentTime":"Day 2, 19:10","narrator":"latest","paragraphs":[{"locationId":"loc_1","timestamp":"Day 2, 19:10","text":"paragraph","visibility":"char_only","visibleTo":["char_6"],"clue":"follow the signal","characterDeltas":[{"charId":"char_6","name":"Iris","delta":5}]}],"locationGroups":[]},"createdAt":1779271200}],"total":3,"pn":1,"rn":2}}',
        ),
      );
      final healthTransport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"status":"ok"}',
        ),
      );

      final api = _apiWith(apiTransport, healthTransport);
      final result = await api.getWorldTicks(wid: 'w_a1b2c3', limit: 2);

      expect(apiTransport.lastRequest!.method, 'GET');
      expect(apiTransport.lastRequest!.uri.path, '/api/v1/world/tick/list');
      expect(
        apiTransport.lastRequest!.uri.queryParameters['world_id'],
        'w_a1b2c3',
      );
      expect(apiTransport.lastRequest!.uri.queryParameters['pn'], '1');
      expect(apiTransport.lastRequest!.uri.queryParameters['rn'], '2');
      expect(
        apiTransport.lastRequest!.uri.queryParameters.containsKey('worldId'),
        isFalse,
      );
      expect(result.total, 3);
      expect(result.data.single['tick_id'], 'tick_2');
      expect(result.data.single['tick_no'], 2);
      expect(result.data.single['sub_tick_no'], 1);
      expect(result.data.single['status'], 50);
      final tickResult = result.data.single['tick_result'] as Map;
      expect(tickResult['current_time'], 'Day 2, 19:10');
      expect(tickResult['narrator'], 'latest');
      final paragraphs = tickResult['paragraphs'] as List;
      final paragraph = paragraphs.single as Map;
      expect(paragraph['location_id'], 'loc_1');
      expect(paragraph['visibility'], 'char_only');
      expect(paragraph['visible_to'], ['char_6']);
      expect(paragraph['clue'], 'follow the signal');
      expect(
        ((paragraph['character_deltas'] as List).single as Map)['delta'],
        5,
      );
    },
  );

  test('v1 world delete posts Apifox world_id field', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":0,"err_msg":"succ","data":{}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    await api.v1.world.deleteLaunched(worldId: ' w_delete_1 ');

    expect(apiTransport.lastRequest!.method, 'POST');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/world/delete');
    final body =
        jsonDecode(utf8.decode(apiTransport.lastRequest!.bodyBytes!)) as Map;
    expect(body['world_id'], 'w_delete_1');
    expect(body.containsKey('wid'), isFalse);
  });

  test('v1 discuss write APIs use Apifox paths and body fields', () async {
    final apiTransport = _FakeTransport(
      handler: (request) {
        if (request.uri.path.endsWith('/discuss/post')) {
          return const TransportResponse(
            statusCode: 200,
            headers: {'content-type': 'application/json'},
            body:
                '{"err_no":0,"err_msg":"succ","data":{"discuss_id":"dis_new","root_discuss_id":"dis_root","level":2}}',
          );
        }
        return const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":0,"err_msg":"succ","data":{}}',
        );
      },
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final created = await api.v1.discuss.post(
      bizId: 'ori_001',
      content: 'reply',
      images: const ['https://cdn.example.com/discuss/a.jpg'],
      rootDiscussId: 'dis_root',
      parentDiscussId: 'dis_parent',
    );

    expect(created['discuss_id'], 'dis_new');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/discuss/post');
    final postBody = jsonDecode(
      utf8.decode(apiTransport.lastRequest!.bodyBytes!),
    );
    expect(postBody['biz_type'], 1);
    expect(postBody['biz_id'], 'ori_001');
    expect(postBody['root_discuss_id'], 'dis_root');
    expect(postBody['parent_discuss_id'], 'dis_parent');
    expect(postBody.containsKey('rootDiscussId'), isFalse);

    await api.v1.discuss.like(discussId: 'dis_new');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/discuss/like');
    final likeBody = jsonDecode(
      utf8.decode(apiTransport.lastRequest!.bodyBytes!),
    );
    expect(likeBody, {'discuss_id': 'dis_new'});

    await api.v1.discuss.unlike(discussId: 'dis_new');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/discuss/unlike');

    await api.v1.discuss.delete(discussId: 'dis_new');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/discuss/delete');
    final deleteBody = jsonDecode(
      utf8.decode(apiTransport.lastRequest!.bodyBytes!),
    );
    expect(deleteBody, {'discuss_id': 'dis_new'});
  });

  test('v1 upload uses multipart body through ApiClient transport', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_str":"success","data":{"file_url":"https://cdn/x.png"}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final result = await api.v1.common.uploadFile(
      bytes: utf8.encode('abc'),
      bizType: 'avatar',
      filename: 'a.txt',
      contentType: 'text/plain',
    );

    expect(result['file_url'], 'https://cdn/x.png');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/common/upload');
    expect(apiTransport.lastRequest!.timeoutMs, 15000);
    expect(
      apiTransport.lastRequest!.headers['content-type'],
      startsWith('multipart/form-data; boundary='),
    );
    final body = utf8.decode(apiTransport.lastRequest!.bodyBytes!);
    expect(body, contains('name="biz_type"'));
    expect(body, contains('avatar'));
    expect(body, contains('filename="a.txt"'));
    expect(body, contains('abc'));
  });

  test('v1 upload image uses Apifox multipart contract', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"sm_url":"https://cdn.example.com/uploads/20260526/123_400_300.jpg","xl_url":"https://cdn.example.com/uploads/20260526/123_800_600.jpg","object_key":"uploads/20260526/123_800_600.jpg"}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final result = await api.v1.upload.image(
      bytes: utf8.encode('image-bytes'),
      filename: 'avatar.png',
      contentType: 'image/png',
    );

    expect(
      result['sm_url'],
      'https://cdn.example.com/uploads/20260526/123_400_300.jpg',
    );
    expect(
      result['xl_url'],
      'https://cdn.example.com/uploads/20260526/123_800_600.jpg',
    );
    expect(result['object_key'], 'uploads/20260526/123_800_600.jpg');
    expect(apiTransport.lastRequest!.method, 'POST');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/upload/image');
    expect(
      apiTransport.lastRequest!.timeoutMs,
      UploadV1Api.imageUploadTimeoutMs,
    );
    expect(
      apiTransport.lastRequest!.headers['content-type'],
      startsWith('multipart/form-data; boundary='),
    );
    final body = utf8.decode(apiTransport.lastRequest!.bodyBytes!);
    expect(body, contains('name="file"; filename="avatar.png"'));
    expect(body, contains('Content-Type: image/png'));
    expect(body, isNot(contains('name="biz_type"')));
  });

  test('v1 report create posts Apifox body and parses report id', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"report_id":"rpt_X9KQ4M2A1B2C"}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final result = await api.v1.report.create(
      targetType: 'origin',
      targetId: 'o_A1B2C3',
      content: '内容疑似违规',
    );

    expect(result['report_id'], 'rpt_X9KQ4M2A1B2C');
    expect(apiTransport.lastRequest!.method, 'POST');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/report/create');
    expect(jsonDecode(utf8.decode(apiTransport.lastRequest!.bodyBytes!)), {
      'target_type': 'origin',
      'target_id': 'o_A1B2C3',
      'content': '内容疑似违规',
    });
  });

  test('v1 feedback create posts Apifox body and parses feedback id', () async {
    final apiTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"feedback_id":"fbk_X9KQ4M2A1B2C"}}',
      ),
    );
    final healthTransport = _FakeTransport(
      handler: (_) => const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"status":"ok"}',
      ),
    );

    final api = _apiWith(apiTransport, healthTransport);
    final result = await api.v1.feedback.create(content: '希望增加夜间模式');

    expect(result['feedback_id'], 'fbk_X9KQ4M2A1B2C');
    expect(apiTransport.lastRequest!.method, 'POST');
    expect(apiTransport.lastRequest!.uri.path, '/api/v1/feedback/create');
    expect(jsonDecode(utf8.decode(apiTransport.lastRequest!.bodyBytes!)), {
      'content': '希望增加夜间模式',
    });
  });

  test(
    'user followers 1404 stays in list error path without page-not-found callback',
    () async {
      var pageNotFoundCount = 0;
      final transport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":1404,"err_msg":"Page not found","data":{}}',
        ),
      );
      final sessionStore = MemoryUserSessionStore();
      await sessionStore.saveAuthToken('token');
      final api = GenesisApi(
        useMock: false,
        transport: transport,
        platformConfig: const _TestPlatformConfig(),
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: sessionStore,
        onPageNotFound: (_) async {
          pageNotFoundCount += 1;
        },
      );

      await expectLater(
        api.v1.follow.followers(uid: 'u_peer', pn: 1, rn: 50),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 1404)
              .having((error) => error.kind, 'kind', ApiExceptionKind.business),
        ),
      );

      expect(transport.lastRequest!.uri.path, '/api/v1/user/followers');
      expect(pageNotFoundCount, 0);
    },
  );

  test('tilemap 1404 stays local without page-not-found callback', () async {
    for (final source in const <String>['origin', 'world']) {
      var pageNotFoundCount = 0;
      final transport = _FakeTransport(
        handler: (_) => const TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: '{"err_no":1404,"err_msg":"Page not found","data":{}}',
        ),
      );
      final api = GenesisApi(
        useMock: false,
        transport: transport,
        platformConfig: const _TestPlatformConfig(),
        deviceIdService: const _TestDeviceIdService(),
        sessionStore: MemoryUserSessionStore(),
        onPageNotFound: (_) async {
          pageNotFoundCount += 1;
        },
      );

      final request = source == 'origin'
          ? api.getOriginMap(originId: 'o_1', locationId: 'loc_1')
          : api.getWorldMap(worldId: 'w_1', locationId: 'loc_1');
      await expectLater(
        request,
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 1404)
              .having((error) => error.kind, 'kind', ApiExceptionKind.business),
        ),
      );

      expect(transport.lastRequest!.uri.path, '/api/v1/$source/map');
      expect(pageNotFoundCount, 0);
    }
  });
}

TransportResponse _gatewayAuthResponse(TransportRequest request) {
  switch (request.uri.path) {
    case '/apix/v1/time':
      return const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body: '{"err_no":0,"err_msg":"succ","data":{"server_time_ms":1}}',
      );
    case '/apix/v1/app/device/challenge':
      return const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"register_id":"reg-1","challenge":"challenge","expires_in":300}}',
      );
    case '/apix/v1/app/device/register':
      return const TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        body:
            '{"err_no":0,"err_msg":"succ","data":{"key_id":"key-registered"}}',
      );
  }
  return const TransportResponse(
    statusCode: 404,
    headers: {'content-type': 'application/json'},
    body: '{"err_no":404,"err_msg":"unexpected","data":{}}',
  );
}

class _TestDeviceIdService implements DeviceIdService {
  const _TestDeviceIdService();

  @override
  Future<String> getDeviceId() async => 'test-device-id';
}

class _ThrowingAuthTokenSessionStore extends MemoryUserSessionStore {
  var clearCount = 0;

  @override
  Future<String?> readAuthToken() async {
    throw StateError('auth token storage unavailable');
  }

  @override
  Future<void> clearUid() async {
    clearCount += 1;
    await super.clearUid();
  }
}

class _SecondAuthTokenReadThrowsSessionStore extends MemoryUserSessionStore {
  var _readCount = 0;

  @override
  Future<String?> readAuthToken() async {
    _readCount += 1;
    if (_readCount > 1) {
      throw StateError('auth token storage unavailable');
    }
    return super.readAuthToken();
  }
}

class _FakeIdentityAuthService implements IdentityAuthService {
  _FakeIdentityAuthService({this.refreshSession});

  final AuthSession? refreshSession;
  int signOutCount = 0;
  int refreshCount = 0;

  @override
  Future<AuthSession?> refreshSilently() async {
    refreshCount += 1;
    return refreshSession;
  }

  @override
  Future<AuthSession> signIn(IdentityProvider provider) {
    throw UnimplementedError();
  }

  @override
  Future<void> signOutIdentity() async {
    signOutCount += 1;
  }
}

class _RecordingFirebaseAnalyticsClient implements AppAnalyticsClient {
  final List<_FirebaseAnalyticsEvent> events = <_FirebaseAnalyticsEvent>[];

  @override
  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
  }) async {
    events.add(
      _FirebaseAnalyticsEvent(
        name,
        Map<String, Object>.of(parameters ?? const <String, Object>{}),
      ),
    );
  }
}

class _MemoryFirebaseAnalyticsOnceEventStore
    implements FirebaseAnalyticsOnceEventStore {
  final Set<String> sentEvents = <String>{};

  @override
  Future<void> markSent(String eventName) async {
    sentEvents.add(eventName);
  }

  @override
  Future<bool> wasSent(String eventName) async {
    return sentEvents.contains(eventName);
  }
}

class _FirebaseAnalyticsEvent {
  const _FirebaseAnalyticsEvent(this.name, this.parameters);

  final String name;
  final Map<String, Object> parameters;

  @override
  bool operator ==(Object other) {
    return other is _FirebaseAnalyticsEvent &&
        other.name == name &&
        _objectMapsEqual(other.parameters, parameters);
  }

  @override
  int get hashCode =>
      Object.hash(name, Object.hashAllUnordered(parameters.entries));
}

bool _objectMapsEqual(Map<String, Object> first, Map<String, Object> second) {
  if (first.length != second.length) return false;
  for (final entry in first.entries) {
    if (second[entry.key] != entry.value) return false;
  }
  return true;
}
