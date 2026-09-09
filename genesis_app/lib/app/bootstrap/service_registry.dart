import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../components/common/genesis_center_toast.dart';
import '../../app/genesis_navigator.dart';
import '../../network/app_request_headers.dart';
import '../../network/chatroom/chatroom_client.dart';
import '../../network/chatroom/chatroom_message_storage.dart';
import '../../network/direct_message_conversation_store.dart';
import '../../network/direct_message_message_store.dart';
import '../../network/gateway_auth.dart';
import '../../network/genesis_api.dart';
import '../../network/json_utils.dart';
import '../../network/local_mock_runtime.dart';
import '../../network/network_runtime_factory.dart';
import '../../network/network_capture.dart';
import '../../routers/app_router.dart';
import '../../platform/platform_services.dart';
import '../../platform/session/user_info_cache.dart';
import '../config/app_config.dart';
import '../config/app_global_config.dart';
import '../config/platform_config.dart';
import '../debug/location_chat_debug_storage.dart';
import '../gems/gem_wallet_store.dart';
import '../membership/membership_catalog.dart';
import '../membership/membership_access_store.dart';
import '../membership/membership_purchase_service.dart';
import '../../platform/billing/membership_checkout_platform.dart';
import '../../platform/billing/membership_pending_store.dart';
import '../../platform/billing/membership_store_restorer.dart';
import '../telemetry/device_info_telemetry.dart';
import '../telemetry/genesis_telemetry.dart';
import '../version/app_version_check_service.dart';
import '../../platform/billing/app_store_billing_platform.dart';
import '../../platform/billing/billing_service.dart';
import '../../platform/billing/google_play_billing_platform.dart';
import '../../platform/billing/pending_purchase_store.dart';

class AppServices {
  AppServices({
    required this.config,
    required this.platformConfig,
    required this.deviceId,
    required this.sessionStore,
    required this.identityAuth,
    required this.backendAuth,
    required this.api,
    required this.chatroom,
    required this.chatroomMessages,
    required this.directMessageConversations,
    required this.directMessageMessages,
    required this.appVersionCheck,
    required this.externalUrlOpener,
    DeviceInfoTelemetryReporter? deviceInfoTelemetry,
    this.gatewayAuth,
    GemWalletStore? gemWallet,
    this.billing,
    this.membershipPurchases,
    MembershipCatalog? membershipCatalog,
    ValueNotifier<int>? sessionRevision,
    AppGlobalConfigStore? appGlobalConfig,
  }) : membershipCatalog =
           membershipCatalog ??
           MembershipCatalog(
             loadProducts: (provider) async => api.v1.membership.products(
               provider: provider,
               deviceId: await deviceId.getDeviceId(),
             ),
             provider: MembershipCatalog.currentProvider,
           ),
       deviceInfoTelemetry =
           deviceInfoTelemetry ??
           DeviceInfoTelemetryReporter(deviceIdService: deviceId),
       gemWallet =
           gemWallet ??
           GemWalletStore(
             loadWallet: api.v1.gem.wallet,
             readUid: sessionStore.readUid,
           ),
       appGlobalConfig =
           appGlobalConfig ??
           AppGlobalConfigStore(loadConfig: api.v1.app.config),
       sessionRevision = sessionRevision ?? ValueNotifier<int>(0) {
    membership = MembershipAccessStore(
      wallet: this.gemWallet,
      readLoginUid: sessionStore.readLoginUid,
      hasBackendSession: () async =>
          (await sessionStore.readAuthToken())?.trim().isNotEmpty == true,
      serverNow: () => gatewayAuth?.serverClock.now,
    );
    this.sessionRevision.addListener(_membershipSessionChanged);
  }

  final AppConfig config;
  final PlatformConfig platformConfig;
  final DeviceIdService deviceId;
  final UserSessionStore sessionStore;
  final IdentityAuthService identityAuth;
  final BackendAuthCoordinator backendAuth;
  final GenesisApi api;
  final ChatroomClient chatroom;
  final ChatroomMessageStorage chatroomMessages;
  final DirectMessageConversationStore directMessageConversations;
  final DirectMessageMessageStore directMessageMessages;
  final AppVersionCheckService appVersionCheck;
  final ExternalUrlOpener externalUrlOpener;
  final DeviceInfoTelemetryReporter deviceInfoTelemetry;
  final GatewayAuthCoordinator? gatewayAuth;
  final GemWalletStore gemWallet;
  late final MembershipAccessStore membership;
  final BillingService? billing;
  final MembershipPurchaseService? membershipPurchases;
  final MembershipCatalog membershipCatalog;
  final AppGlobalConfigStore appGlobalConfig;
  final ValueNotifier<int> sessionRevision;
  final ValueNotifier<String?> pendingLoginCheckInUid = ValueNotifier(null);

  void _membershipSessionChanged() {
    membership.resetForSession();
    unawaited(membership.start());
    membershipPurchases?.resetForSession();
  }

  void notifySessionChanged() {
    pendingLoginCheckInUid.value = null;
    gemWallet.reset();
    billing?.resetForSession();
    sessionRevision.value += 1;
  }

  void dispose() {
    sessionRevision.removeListener(_membershipSessionChanged);
    pendingLoginCheckInUid.dispose();
    billing?.dispose();
    membershipPurchases?.dispose();
    membership.dispose();
    gemWallet.dispose();
    appGlobalConfig.dispose();
  }
}

class ServiceRegistry {
  const ServiceRegistry._();

  static AppServices build({
    AppConfig config = const AppConfig(),
    DeviceIdService? deviceIdOverride,
    UserSessionStore? sessionStoreOverride,
    IdentityAuthService? identityAuthOverride,
    ValueNotifier<int>? sessionRevisionOverride,
    ChatroomMessageStorage? chatroomMessagesOverride,
  }) {
    final platformConfig = DefaultPlatformConfig(appConfig: config);
    final deviceId = deviceIdOverride ?? const NativeDeviceIdService();
    final deviceInfoTelemetry = DeviceInfoTelemetryReporter(
      deviceIdService: deviceId,
    );
    final sessionStore = sessionStoreOverride ?? NativeUserSessionStore();
    final identityAuth =
        identityAuthOverride ??
        ProviderIdentityAuthService(sessionStore: sessionStore);
    final sessionRevision = sessionRevisionOverride ?? ValueNotifier<int>(0);
    GemWalletStore? gemWalletStore;
    var handlingPageNotFound = false;
    var handlingSessionExpired = false;
    Future<void> handlePageNotFound(String _) async {
      if (handlingPageNotFound) return;
      handlingPageNotFound = true;
      try {
        final navigator = genesisNavigatorKey.currentState;
        await navigator?.pushReplacementNamed(RouteNames.pageNotFound);
      } finally {
        await Future<void>.delayed(const Duration(seconds: 1));
        handlingPageNotFound = false;
      }
    }

    Future<void> handleSessionExpired(String _) async {
      if (handlingSessionExpired) return;
      handlingSessionExpired = true;
      try {
        GenesisTelemetry.clearUser();
        await sessionStore.clearUid();
        gemWalletStore?.reset();
        sessionRevision.value += 1;
        try {
          await identityAuth.signOutIdentity();
        } catch (error) {
          debugPrint('[Auth][SessionExpired] identity sign out failed: $error');
        }

        final navigator = genesisNavigatorKey.currentState;
        navigator?.pushNamedAndRemoveUntil(RouteNames.origin, (_) => false);
        const toastMessage = 'Your account is logged in on another device.';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final overlay = genesisNavigatorKey.currentState?.overlay;
          if (overlay == null) return;
          showGenesisToastInOverlay(
            overlay,
            toastMessage,
            duration: const Duration(seconds: 4),
          );
        });
      } finally {
        await Future<void>.delayed(const Duration(seconds: 1));
        handlingSessionExpired = false;
      }
    }

    final debugProxy = config.debugProxy.trim();
    final effectiveUseMock =
        config.useMock == true && kLocalMockTransportAvailable;
    const networkRuntimeFactory = NetworkRuntimeFactory();
    final baseHttpTransport = networkRuntimeFactory.buildHttpTransport(
      debugProxy: debugProxy,
      useMock: effectiveUseMock,
    );
    final httpTransport = baseHttpTransport == null
        ? null
        : debugNetworkCaptureTransport(delegate: baseHttpTransport);
    final socketTransport = networkRuntimeFactory.buildWebSocketTransport(
      debugProxy: debugProxy,
      debugLogFrames: config.debugWsLog,
      logName: 'ChatroomSocket',
      frameLogName: 'ChatroomSocketFrame',
    );
    final appRequestHeaders = AppRequestHeaderProvider();
    GatewayRequestInterceptor? gatewayRequestInterceptor;
    GatewayHandshakeHeaderSigner? gatewayWsHandshakeHeaderSigner;
    GatewayAuthCoordinator? gatewayAuthCoordinator;
    if (!effectiveUseMock) {
      gatewayAuthCoordinator = GatewayAuthCoordinator(
        gatewayBaseUrl: config.gatewayApiBaseUrl,
        appHeaderProvider: appRequestHeaders.headers,
        identityProvider: appRequestHeaders.gatewayIdentity,
        deviceIdService: deviceId,
        keyStore: const NativeGatewayDeviceKeyStore(),
        transport: httpTransport,
      );
      gatewayRequestInterceptor = GatewayRequestInterceptor(
        coordinator: gatewayAuthCoordinator,
      );
      gatewayWsHandshakeHeaderSigner = gatewayHandshakeHeaderSigner(
        coordinator: gatewayAuthCoordinator,
      );
    }
    final api = GenesisApi(
      useMock: effectiveUseMock,
      transport: httpTransport,
      platformConfig: platformConfig,
      gatewayApiBaseUrl: config.gatewayApiBaseUrl,
      chatroomHttpBaseUrl: config.chatroomHttpBaseUrl,
      deviceIdService: deviceId,
      sessionStore: sessionStore,
      identityAuthService: identityAuth,
      appHeaderProvider: appRequestHeaders.headers,
      gatewayRequestInterceptor: gatewayRequestInterceptor,
      onSessionExpired: handleSessionExpired,
      onPageNotFound: handlePageNotFound,
      onChatroomMessageMutationError: (message) {
        final overlay = genesisNavigatorKey.currentState?.overlay;
        if (overlay != null) showGenesisToastInOverlay(overlay, message);
      },
    );
    final chatroom = ChatroomClient(
      wsBaseUrl: config.chatroomWsBaseUrl,
      sessionStore: sessionStore,
      deviceIdService: deviceId,
      transport: socketTransport,
      heartbeatInterval: config.chatroomHeartbeatInterval,
      ackTimeout: config.chatroomAckTimeout,
      requestHeaderProvider: appRequestHeaders.headers,
      handshakeHeaderSigner: gatewayWsHandshakeHeaderSigner,
    );
    final backendAuth = GenesisBackendAuthCoordinator(
      api: api,
      identityAuth: identityAuth,
      sessionStore: sessionStore,
      prepareBackendRequest: gatewayAuthCoordinator?.prepare,
      onLoginSuccess: deviceInfoTelemetry.reportLoginSuccess,
    );
    final gemWallet = GemWalletStore(
      loadWallet: api.v1.gem.wallet,
      readUid: sessionStore.readUid,
    );
    gemWalletStore = gemWallet;
    final billingPlatform = switch (defaultTargetPlatform) {
      TargetPlatform.android => GooglePlayBillingPlatform(),
      TargetPlatform.iOS => AppStoreBillingPlatform(),
      _ => null,
    };
    Future<String> loadBillingAccountUuid() async {
      await api.ensureUid();
      final userInfo = await api.v1.user.info();
      await cacheCurrentUserInfoResponse(
        sessionStore: sessionStore,
        response: userInfo,
      );
      return asString(userInfo['uuid']);
    }

    BillingService? billing;
    final membershipProvider = MembershipCatalog.currentProvider;
    final membershipPurchases =
        billingPlatform == null || membershipProvider == null
        ? null
        : MembershipPurchaseService(
            platform: StoreMembershipCheckoutPlatform(),
            store: SecureMembershipPendingStore(),
            provider: membershipProvider,
            readLoginUid: sessionStore.readLoginUid,
            loadProducts: () async => (await api.v1.membership.products(
              provider: membershipProvider,
              deviceId: await deviceId.getDeviceId(),
            )).products,
            loadAccountUuid: loadBillingAccountUuid,
            prepareGuest: () async => api.v1.membership.prepareGuest(
              provider: membershipProvider,
              deviceId: await deviceId.getDeviceId(),
            ),
            reportPurchase: api.v1.membership.reportPurchase,
            claimGuest: api.v1.membership.claimGuest,
            restorePurchase: api.v1.membership.restorePurchase,
            queryRestorePurchases: MembershipStoreRestorer(
              provider: membershipProvider,
            ).query,
            queryPurchases: billingPlatform.queryRecoverablePurchases,
            otherPurchaseBusy: () =>
                billing?.state.value.hasBusyPurchase ?? false,
            refreshWallet: gemWallet.refreshAfterMembershipChanged,
          );
    billing = billingPlatform == null
        ? null
        : GooglePlayBillingService(
            platform: billingPlatform,
            pendingPurchaseStore: SqfliteBillingPendingPurchaseStore(),
            loadBillingAccountId: loadBillingAccountUuid,
            loadProductCatalog: () async =>
                (await api.v1.gem.products()).products,
            reportPurchase: api.v1.gem.reportPurchase,
            refreshWallet: gemWallet.refreshAfterEntitlementGranted,
            readUid: sessionStore.readUid,
            interceptPurchase: membershipPurchases?.interceptPurchase,
            otherPurchaseBusy: () => membershipPurchases?.isBusy ?? false,
            onPurchaseStreamError: membershipPurchases?.handleStreamError,
          );
    final directMessageConversations = DirectMessageConversationStore(
      api: api,
      sessionStore: sessionStore,
      storage: SqfliteDirectMessageConversationStorage(),
    );
    final directMessageMessages = DirectMessageMessageStore(
      api: api,
      sessionStore: sessionStore,
      storage: SqfliteDirectMessageMessageStorage(),
    );
    final chatroomMessages = LocationChatDebugChatroomMessageStorage.wrap(
      chatroomMessagesOverride ?? SqfliteChatroomMessageStorage(),
    );
    final appVersionCheck = GenesisAppVersionCheckService(
      config: config,
      api: api,
      deviceIdService: deviceId,
      sessionStore: sessionStore,
    );
    return AppServices(
      config: config,
      platformConfig: platformConfig,
      deviceId: deviceId,
      sessionStore: sessionStore,
      identityAuth: identityAuth,
      backendAuth: backendAuth,
      api: api,
      chatroom: chatroom,
      chatroomMessages: chatroomMessages,
      directMessageConversations: directMessageConversations,
      directMessageMessages: directMessageMessages,
      appVersionCheck: appVersionCheck,
      externalUrlOpener: const NativeExternalUrlOpener(),
      deviceInfoTelemetry: deviceInfoTelemetry,
      gatewayAuth: gatewayAuthCoordinator,
      gemWallet: gemWallet,
      billing: billing,
      membershipPurchases: membershipPurchases,
      sessionRevision: sessionRevision,
    );
  }

  static AppServices rebuildFrom(
    AppServices current, {
    required AppConfig config,
  }) {
    final updated = build(
      config: config,
      deviceIdOverride: current.deviceId,
      sessionStoreOverride: current.sessionStore,
      identityAuthOverride: current.identityAuth,
      sessionRevisionOverride: current.sessionRevision,
      chatroomMessagesOverride: current.chatroomMessages,
    );
    unawaited(updated.membership.start());
    return updated;
  }
}
