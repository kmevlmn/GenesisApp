import 'dart:async';
import 'dart:convert';

import 'package:genesis_flutter_android/network/http_transport.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/bootstrap/service_registry.dart';
import 'package:genesis_flutter_android/app/config/app_config.dart';
import 'package:genesis_flutter_android/app/startup/app_startup_coordinator.dart';
import 'package:genesis_flutter_android/app/telemetry/genesis_telemetry.dart';
import 'package:genesis_flutter_android/app/telemetry/native_app_lifecycle.dart';
import 'package:genesis_flutter_android/platform/app/app_metadata_service.dart';
import 'package:genesis_flutter_android/platform/device/device_id_service.dart';
import 'package:genesis_flutter_android/platform/session/memory_user_session_store.dart';

class _TestDeviceIdService implements DeviceIdService {
  const _TestDeviceIdService();

  @override
  Future<String> getDeviceId() async => 'device-test-1';
}

class _NeverCompletingDeviceIdService implements DeviceIdService {
  _NeverCompletingDeviceIdService(this.calls);

  final List<String> calls;

  @override
  Future<String> getDeviceId() {
    calls.add('device_id');
    return Completer<String>().future;
  }
}

class _RetryingDeviceIdService implements DeviceIdService {
  int calls = 0;

  @override
  Future<String> getDeviceId() {
    calls += 1;
    if (calls == 1) return Completer<String>().future;
    return Future<String>.value('device-recovered');
  }
}

class _FakeCollectClient implements CollectTelemetryClient {
  _FakeCollectClient({this.onCollect});

  final VoidCallback? onCollect;
  final List<Map<String, String>> headers = <Map<String, String>>[];
  final List<List<CollectEvent>> batches = <List<CollectEvent>>[];

  @override
  Future<void> collectBatch(
    List<CollectEvent> events, {
    Map<String, String> headers = const <String, String>{},
    NetworkCancellationToken? cancellationToken,
  }) async {
    onCollect?.call();
    this.headers.add(Map<String, String>.of(headers));
    batches.add(List<CollectEvent>.of(events));
  }
}

class _ThrowingUidSessionStore extends MemoryUserSessionStore {
  @override
  Future<String?> readUid() async {
    throw StateError('UID read failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CollectTelemetryUploader uploader;
  late AppServices services;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    AppStartupCoordinator.configure(
      appVersion: const AppVersionInfo(versionName: '1.2.3'),
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    services.dispose();
    uploader.dispose();
    AppStartupCoordinator.resetForTesting();
    GenesisTelemetry.resetForTesting();
  });

  Future<_FakeCollectClient> initializeWith(
    MemoryUserSessionStore sessionStore, {
    DeviceIdService deviceIdService = const _TestDeviceIdService(),
    Future<AppVersionInfo> Function()? appVersionReader,
    Duration appVersionTimeout = const Duration(seconds: 1),
    Duration deviceIdTimeout = const Duration(seconds: 2),
    List<Duration> metadataRetryDelays = const <Duration>[],
    VoidCallback? onCollect,
  }) async {
    final client = _FakeCollectClient(onCollect: onCollect);
    uploader = CollectTelemetryUploader(
      store: MemoryCollectEventStore(),
      interval: const Duration(hours: 1),
    )..configure(enabled: true, client: client);
    GenesisTelemetry.setCollectUploaderForTesting(uploader);
    services = ServiceRegistry.build(
      config: const AppConfig(apiEnvironment: 'test', useMock: true),
      deviceIdOverride: deviceIdService,
      sessionStoreOverride: sessionStore,
    );
    AppStartupCoordinator.recordStartupFirstReport();

    await AppStartupCoordinator.initializeTelemetry(
      services: services,
      appVersionReader: appVersionReader,
      appVersionTimeout: appVersionTimeout,
      deviceIdTimeout: deviceIdTimeout,
      metadataRetryDelays: metadataRetryDelays,
    );
    await _waitUntil(() => uploader.hasTimerForTesting);
    return client;
  }

  test('does not wait for the persisted UID before the first upload', () async {
    final sessionStore = MemoryUserSessionStore();
    await sessionStore.saveUid('user-123');

    final client = await initializeWith(sessionStore);

    expect(client.headers, isNotEmpty);
    expect(
      client.headers.every((headers) => !headers.containsKey('X-UID')),
      isTrue,
    );
  });

  test('starts Collect anonymously when there is no persisted UID', () async {
    final client = await initializeWith(MemoryUserSessionStore());

    expect(client.headers, isNotEmpty);
    expect(
      client.headers.every((headers) => !headers.containsKey('X-UID')),
      isTrue,
    );
  });

  test(
    'subscribes once to native lifecycle and cancels it when reset',
    () async {
      var listenCount = 0;
      var cancelCount = 0;
      final lifecycleEvents =
          StreamController<NativeAppLifecycleEvent>.broadcast(
            sync: true,
            onListen: () => listenCount += 1,
            onCancel: () => cancelCount += 1,
          );
      addTearDown(lifecycleEvents.close);
      AppStartupCoordinator.setAppLifecycleEventsForTesting(
        lifecycleEvents.stream,
      );

      final client = await initializeWith(MemoryUserSessionStore());
      await AppStartupCoordinator.initializeTelemetry(services: services);
      expect(listenCount, 1);

      lifecycleEvents.add(NativeAppLifecycleEvent.foreground);
      lifecycleEvents.add(NativeAppLifecycleEvent.background);
      lifecycleEvents.add(NativeAppLifecycleEvent.background);
      lifecycleEvents.add(NativeAppLifecycleEvent.foreground);
      lifecycleEvents.add(NativeAppLifecycleEvent.foreground);
      await GenesisTelemetry.waitForCollectWritesForTesting();
      // Lifecycle notifications also start a check. Wait for that actual check
      // to finish before requesting a second drain of newly queued events.
      await _waitUntil(() => !uploader.isCheckingForTesting);
      await uploader.checkNow(force: true);

      expect(
        client.batches
            .expand((batch) => batch)
            .map((event) => event.action)
            .where(
              (action) =>
                  action == 'app_background' || action == 'app_foreground',
            ),
        <String>['app_background', 'app_foreground'],
      );

      AppStartupCoordinator.resetForTesting();
      await Future<void>.delayed(Duration.zero);
      expect(cancelCount, 1);
    },
  );

  test(
    'starts Collect without reading UID in telemetry initialization',
    () async {
      final client = await initializeWith(_ThrowingUidSessionStore());

      expect(client.headers, isNotEmpty);
      expect(
        client.headers.every((headers) => !headers.containsKey('X-UID')),
        isTrue,
      );
    },
  );

  test('metadata timeouts do not block Collect startup', () async {
    AppStartupCoordinator.configure();
    final calls = <String>[];

    final client = await initializeWith(
      MemoryUserSessionStore(),
      appVersionReader: () {
        calls.add('app_version');
        return Completer<AppVersionInfo>().future;
      },
      deviceIdService: _NeverCompletingDeviceIdService(calls),
      appVersionTimeout: const Duration(milliseconds: 5),
      deviceIdTimeout: const Duration(milliseconds: 5),
      onCollect: () => calls.add('collect'),
    );

    expect(calls, <String>['app_version', 'device_id', 'collect']);
    expect(uploader.isStartedForTesting, isTrue);
    expect(client.headers, isNotEmpty);
    expect(
      client.headers.every((headers) => !headers.containsKey('X-Device-ID')),
      isTrue,
    );
  });

  test(
    'waits for an app version retry before uploading startup events',
    () async {
      AppStartupCoordinator.configure();
      final calls = <String>[];
      var appVersionCalls = 0;

      final client = await initializeWith(
        MemoryUserSessionStore(),
        appVersionReader: () {
          appVersionCalls += 1;
          calls.add('app_version_$appVersionCalls');
          if (appVersionCalls == 1) {
            return Completer<AppVersionInfo>().future;
          }
          return Future<AppVersionInfo>.value(
            const AppVersionInfo(versionName: '4.5.6'),
          );
        },
        appVersionTimeout: const Duration(milliseconds: 5),
        metadataRetryDelays: const <Duration>[Duration(milliseconds: 5)],
        onCollect: () => calls.add('collect'),
      );

      expect(appVersionCalls, 2);
      expect(calls, <String>['app_version_1', 'app_version_2', 'collect']);
      expect(client.headers, isNotEmpty);
      expect(
        client.headers.every((headers) => headers['X-App-Version'] == '4.5.6'),
        isTrue,
      );
    },
  );

  test(
    'starts Collect after non-empty app version retries are exhausted',
    () async {
      AppStartupCoordinator.configure();
      var appVersionCalls = 0;

      final client = await initializeWith(
        MemoryUserSessionStore(),
        appVersionReader: () {
          appVersionCalls += 1;
          return Completer<AppVersionInfo>().future;
        },
        appVersionTimeout: const Duration(milliseconds: 5),
        metadataRetryDelays: const <Duration>[
          Duration(milliseconds: 5),
          Duration(milliseconds: 5),
        ],
      );

      expect(appVersionCalls, 3);
      expect(uploader.isStartedForTesting, isTrue);
      expect(client.headers, isNotEmpty);
      expect(
        client.headers.every(
          (headers) => headers['X-App-Version'] == 'unknown',
        ),
        isTrue,
      );
    },
  );

  test('missing metadata is retried without clearing the user id', () async {
    final deviceIdService = _RetryingDeviceIdService();
    final client = await initializeWith(
      MemoryUserSessionStore(),
      deviceIdService: deviceIdService,
      deviceIdTimeout: const Duration(milliseconds: 5),
      metadataRetryDelays: const <Duration>[Duration(milliseconds: 20)],
    );
    GenesisTelemetry.setUserId('user-after-start');

    await _waitUntil(
      () => GenesisTelemetry.contextForTesting.deviceId == 'device-recovered',
    );
    GenesisTelemetry.collectLog(
      actionType: 'event',
      action: 'metadata_retry_test',
    );
    await GenesisTelemetry.waitForCollectWritesForTesting();
    await uploader.checkNow(force: true);

    expect(deviceIdService.calls, 2);
    expect(client.headers.last['X-Device-ID'], 'device-recovered');
    expect(client.headers.last['X-UID'], 'user-after-start');
  });

  test('records the agreed launch funnel fields once', () async {
    AppStartupCoordinator.beginLaunchTracking(startupId: 'startup-test-1');
    final client = await initializeWith(MemoryUserSessionStore());

    AppStartupCoordinator.setLaunchPageDecision(
      page: 'worldo',
      reason: 'no_session_worldo_cache_miss',
    );
    AppStartupCoordinator.recordLaunchSystemUiReady();
    AppStartupCoordinator.recordLaunchEndpointConfigReady();
    AppStartupCoordinator.recordLaunchLocalSettingsReady();
    AppStartupCoordinator.recordLaunchTelemetryReady();
    AppStartupCoordinator.recordLaunchAppConfigReady();
    AppStartupCoordinator.recordLaunchBootstrapReady();
    AppStartupCoordinator.recordLaunchFirstFrame();
    AppStartupCoordinator.recordLaunchRouteReady();
    AppStartupCoordinator.recordLaunchPage();
    AppStartupCoordinator.recordLaunchRequestStart(page: 'worldo');
    AppStartupCoordinator.recordLaunchRequestStart(page: 'worldo');
    AppStartupCoordinator.recordLaunchRequestEnd(
      page: 'worldo',
      result: 'success',
    );
    AppStartupCoordinator.recordLaunchRender(page: 'worldo', result: 'network');
    await GenesisTelemetry.waitForCollectWritesForTesting();
    await uploader.checkNow(force: true);

    final events = client.batches.expand((batch) => batch).toList();
    final launchEvents = events
        .where((event) => event.action.startsWith('launch_'))
        .toList();
    expect(launchEvents.map((event) => event.action), <String>[
      'launch_startup',
      'launch_page',
      'launch_req_start',
      'launch_req_end',
      'launch_render',
    ]);
    expect(
      launchEvents.every((event) => event.actionType == 'monitor'),
      isTrue,
    );
    expect(
      launchEvents.every((event) => event.object1 == 'startup-test-1'),
      isTrue,
    );
    expect(launchEvents.first.object2, 'launch');
    expect(launchEvents.first.object3, '0');
    expect(launchEvents.first.object4, 'started');
    expect(launchEvents[1].object2, 'worldo');
    expect(launchEvents[1].object4, 'no_session_worldo_cache_miss');
    final launchTiming = jsonDecode(launchEvents[1].extData);
    expect(launchTiming['schema_version'], 1);
    expect((launchTiming['milestones'] as Map<String, dynamic>).keys, <String>[
      'system_ui_ready_ms',
      'endpoint_config_ready_ms',
      'local_settings_ready_ms',
      'telemetry_ready_ms',
      'app_config_ready_ms',
      'bootstrap_ready_ms',
      'first_frame_ms',
      'route_ready_ms',
    ]);
    expect(launchEvents[2].object4, 'started');
    expect(launchEvents[3].object4, 'success');
    expect(launchEvents[4].object4, 'network');
    expect(
      launchEvents
          .skip(1)
          .every((event) => int.tryParse(event.object3) != null),
      isTrue,
    );
  });

  test(
    'classifies startup page reasons from session and cache state',
    () async {
      await initializeWith(MemoryUserSessionStore());

      expect(
        AppStartupCoordinator.resolveLaunchPageReason(
          hasSession: true,
          sessionReadFailed: false,
          hasHomeCache: true,
          hasWorldoCache: false,
        ),
        'session_home_cache_hit',
      );
      expect(
        AppStartupCoordinator.resolveLaunchPageReason(
          hasSession: true,
          sessionReadFailed: false,
          hasHomeCache: false,
          hasWorldoCache: true,
        ),
        'session_home_miss_worldo_cache_hit',
      );
      expect(
        AppStartupCoordinator.resolveLaunchPageReason(
          hasSession: true,
          sessionReadFailed: false,
          hasHomeCache: false,
          hasWorldoCache: false,
        ),
        'session_all_cache_miss',
      );
      expect(
        AppStartupCoordinator.resolveLaunchPageReason(
          hasSession: false,
          sessionReadFailed: false,
          hasHomeCache: false,
          hasWorldoCache: true,
        ),
        'no_session_worldo_cache_hit',
      );
      expect(
        AppStartupCoordinator.resolveLaunchPageReason(
          hasSession: false,
          sessionReadFailed: false,
          hasHomeCache: false,
          hasWorldoCache: false,
        ),
        'no_session_worldo_cache_miss',
      );
      expect(
        AppStartupCoordinator.resolveLaunchPageReason(
          hasSession: false,
          sessionReadFailed: true,
          hasHomeCache: false,
          hasWorldoCache: false,
        ),
        'session_error',
      );
    },
  );
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!predicate()) {
    if (stopwatch.elapsed >= timeout) {
      throw TimeoutException('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
