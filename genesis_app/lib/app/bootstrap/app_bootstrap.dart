import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../telemetry/genesis_telemetry.dart';
import '../telemetry/firebase_crash_reporting.dart';
import '../telemetry/firebase_performance_monitoring.dart';
import '../telemetry/firebase_runtime.dart';
import '../telemetry/telemetry_upload_policy.dart';
import '../../network/devtools_http_profile.dart';
import '../../network/genesis_http_cache_manager.dart';
import '../../network/genesis_http_transport_pool.dart';
import '../../network/network_runtime_factory.dart';
import '../../network/network_capture.dart';
import '../../network/websocket_capture.dart';
import '../../platform/session/user_session_store.dart';
import 'service_registry.dart';

class AppBootstrap {
  const AppBootstrap._();

  static const _gatewayPrepareTimeout = Duration(seconds: 8);
  static const _sessionReadTimeout = Duration(seconds: 2);
  static Future<void>? _firebasePerformanceInitialization;

  static AppServices createInitialServices({
    AppConfig config = const AppConfig(),
  }) {
    WidgetsFlutterBinding.ensureInitialized();
    enableGenesisDevToolsHttpProfiling();
    final httpTransport = GenesisHttpTransportRegistry.configure(
      httpEngine: kGenesisHttpEngine,
      debugProxy: config.debugProxy,
    );
    GenesisHttpCacheManager.configureTransport(httpTransport);
    unawaited(_warmUpStaticImageConnections());
    final services = ServiceRegistry.build(config: config);
    final billing = services.billing;
    if (billing != null) unawaited(billing.start());
    unawaited(services.membershipPurchases?.start());
    return services;
  }

  static Future<void> _warmUpStaticImageConnections() async {
    try {
      await GenesisHttpCacheManager().warmUpConnections();
    } catch (e, st) {
      debugPrint('[Network][Image] connection warm-up failed: $e');
      debugPrint('[Network][Image] stacktrace:\n$st');
    }
  }

  static Future<AppServices> initialize() async {
    if (kDebugMode) {
      await Future.wait<bool>(<Future<bool>>[
        networkCaptureController.loadEnabled(),
        webSocketCaptureController.loadSettings(),
      ]);
    }
    final services = createInitialServices();
    await warmUp(services);
    return services;
  }

  static Future<void> ensureFirebasePerformanceMonitoring() {
    final inFlight = _firebasePerformanceInitialization;
    if (inFlight != null) return inFlight;
    final future = _initializeFirebasePerformanceMonitoring();
    _firebasePerformanceInitialization = future;
    return future;
  }

  static Future<void> _initializeFirebasePerformanceMonitoring() async {
    try {
      await FirebaseRuntime.ensureInitialized();
      await FirebasePerformanceMonitoring.configure(
        TelemetryUploadPolicy.state.value.performanceEnabled,
      );
    } catch (e, st) {
      _firebasePerformanceInitialization = null;
      debugPrint('[Auth][Firebase] initialize failed: $e');
      debugPrint('[Auth][Firebase] stacktrace:\n$st');
    }
  }

  static Future<void> warmUp(AppServices services) async {
    unawaited(ensureFirebasePerformanceMonitoring());
    unawaited(_enableCrashReportingAfterFirebaseReady());

    String? uid;
    String? authToken;
    var sessionReadSucceeded = false;
    try {
      final values = await Future.wait<Object?>(<Future<Object?>>[
        services.sessionStore.readLoginUid(),
        services.sessionStore.readAuthToken(),
      ]).timeout(_sessionReadTimeout);
      uid = values[0] as String?;
      authToken = (values[1] as String?)?.trim();
      sessionReadSucceeded = true;
    } catch (e, st) {
      debugPrint('[Auth][Bootstrap] session read failed: $e');
      debugPrint('[Auth][Bootstrap] stacktrace:\n$st');
    }
    final reportUid = uid ?? '';
    if (uid != null) {
      GenesisTelemetry.setUserId(uid);
    } else if (sessionReadSucceeded) {
      GenesisTelemetry.clearUser();
    }
    unawaited(services.deviceInfoTelemetry.reportStartup(uid: reportUid));

    try {
      await services.gatewayAuth?.prepare().timeout(_gatewayPrepareTimeout);
    } catch (e, st) {
      debugPrint('[GatewayAuth] warm-up prepare failed: $e');
      debugPrint('[GatewayAuth] stacktrace:\n$st');
    }

    if (uid != null && (authToken == null || authToken.isEmpty)) {
      unawaited(
        _restoreMissingBackendToken(
          services,
        ).then((_) => services.membership.start()),
      );
    } else {
      unawaited(services.membership.start());
    }
  }

  static Future<void> _restoreMissingBackendToken(AppServices services) async {
    try {
      final restored = await services.backendAuth
          .hasAuthenticatedBackendSession();
      if (!restored) {
        debugPrint(
          '[Auth][Bootstrap] backend token restoration unavailable; preserving local UID',
        );
      }
    } catch (e, st) {
      debugPrint(
        '[Auth][Bootstrap] backend token restoration failed; preserving local UID: $e',
      );
      debugPrint('[Auth][Bootstrap] stacktrace:\n$st');
    }
  }

  static Future<void> _enableCrashReportingAfterFirebaseReady() async {
    await ensureFirebasePerformanceMonitoring();
    await FirebaseCrashReporting.configure(
      TelemetryUploadPolicy.state.value.crashlyticsEnabled,
    );
  }
}
