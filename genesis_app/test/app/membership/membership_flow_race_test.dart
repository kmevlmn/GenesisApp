import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/bootstrap/service_registry.dart';
import 'package:genesis_flutter_android/app/config/app_config.dart';
import 'package:genesis_flutter_android/network/models/membership_claim.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';

import 'membership_purchase_service_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'session expiry notification reinstates the pending guest login gate',
    () async {
      final h = Harness(claimEnabled: true)..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      h.uid = 'first-login';
      final entered = Completer<void>();
      final response = Completer<MembershipClaimResult>();
      h.claimHandler = (_) {
        entered.complete();
        return response.future;
      };
      final recovery = h.service.recover();
      await entered.future;
      expect(h.service.guestLoginRequestId.value, isNull);
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final base = ServiceRegistry.build(
        config: const AppConfig(useMock: true),
      );
      debugDefaultTargetPlatformOverride = previous;
      final services = AppServices(
        config: base.config,
        platformConfig: base.platformConfig,
        deviceId: base.deviceId,
        sessionStore: base.sessionStore,
        identityAuth: base.identityAuth,
        backendAuth: base.backendAuth,
        api: base.api,
        chatroom: base.chatroom,
        chatroomMessages: base.chatroomMessages,
        directMessageConversations: base.directMessageConversations,
        directMessageMessages: base.directMessageMessages,
        appVersionCheck: base.appVersionCheck,
        externalUrlOpener: base.externalUrlOpener,
        membershipPurchases: h.service,
        sessionRevision: base.sessionRevision,
      );
      addTearDown(base.dispose);
      addTearDown(services.dispose);
      h.uid = null;
      // This is the session-expired path, which does not call notifySessionChanged.
      services.sessionRevision.value++;
      await Future<void>.delayed(Duration.zero);
      expect(h.service.guestLoginRequestId.value, isNotNull);
      expect(h.store.claims.values.single.ownerUid, 'first-login');
      expect(h.claimRequests, hasLength(1));
      response.completeError(StateError('session expired'));
      await recovery;
    },
  );

  test(
    'report rechecks account ownership before sending and retries only as original owner',
    () async {
      final h = Harness();
      await h.service.purchase(h.product());
      var reads = 0;
      h.loginUidHandler = () async => ++reads == 1 ? h.uid : 'other-login';
      await h.service.interceptPurchase(h.purchase());
      expect(h.reports, isEmpty);
      expect(h.store.records, isEmpty);
      h.loginUidHandler = null;
      h.uid = 'user-test';
      await h.service.recover();
      expect(h.reports, hasLength(1));
    },
  );

  testWidgets('claim timer firing during recovery schedules the next pass', (
    tester,
  ) async {
    final h = Harness(
      claimEnabled: true,
      retryDelay: const Duration(seconds: 15),
    )..uid = null;
    await h.service.purchase(h.product());
    await h.service.interceptPurchase(h.purchase());
    h.uid = 'first-login';
    h.claimHandler = (_) async =>
        const MembershipClaimResult(status: MembershipReportStatus.accepted);
    await h.service.recover();
    final entered = Completer<void>();
    final response = Completer<MembershipPurchaseReport>();
    h.reportHandler = (_) {
      entered.complete();
      return response.future;
    };
    final recovery = h.service.recover();
    await entered.future;
    await tester.pump(const Duration(seconds: 15));
    expect(h.claimRequests, hasLength(1));
    h.claimHandler = null;
    response.complete(completed);
    await recovery;
    await tester.pump();
    await h.service.recover();
    expect(h.claimRequests, hasLength(2));
    expect(
      h.store.claims.values.where((r) => r.status != 'completed'),
      isEmpty,
    );
  });
}
