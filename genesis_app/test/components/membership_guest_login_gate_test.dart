import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genesis_flutter_android/app/debug/membership_guest_login_debug_settings.dart';
import 'package:genesis_flutter_android/components/gems/membership_guest_login_gate.dart';
import 'package:genesis_flutter_android/components/gems/pro_subscription_content.dart';
import 'package:genesis_flutter_android/components/login_sheet.dart';
import 'package:genesis_flutter_android/platform/auth/auth_cancelled_exception.dart';
import 'package:genesis_flutter_android/network/models/membership_claim.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/routers/app_router.dart';

import '../app/membership/membership_purchase_service_test.dart';
import '../support/membership_fixtures.dart';

Future<void> openGuestApp(
  WidgetTester tester,
  Harness h, {
  Future<bool> Function()? signIn,
  bool inPurchaseSheet = false,
  bool inPurchasePage = false,
  bool homeOnly = false,
}) async {
  final navigator = GlobalKey<NavigatorState>();
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Widget subscription() => ProSubscriptionContent(
    productsLoader: loadTestMembershipOffers,
    purchaseService: h.service,
    closeOnPurchaseSuccess: inPurchaseSheet,
  );
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      routes: {RouteNames.me: (_) => const Scaffold(body: Text('Me'))},
      builder: (context, child) => MembershipGuestLoginGate(
        service: h.service,
        navigatorKey: navigator,
        requestLogin: (context) => showLoginSheet(
          context: context,
          isDismissible: false,
          forceLoginRequired: membershipGuestLoginDebugSettings.listenable,
          onLogin: (_) async {
            if (signIn != null && !await signIn()) return false;
            h.uid = 'first-login';
            return true;
          },
        ),
        child: child!,
      ),
      home: Scaffold(
        body: homeOnly
            ? const Text('Home')
            : inPurchaseSheet || inPurchasePage
            ? Builder(
                builder: (context) => TextButton(
                  onPressed: () => inPurchasePage
                      ? Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            settings: const RouteSettings(
                              name: RouteNames.gemWallet,
                            ),
                            builder: (_) => Scaffold(body: subscription()),
                          ),
                        )
                      : showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) =>
                              SizedBox(height: 740, child: subscription()),
                        ),
                  child: const Text('Open purchases'),
                ),
              )
            : subscription(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    membershipGuestLoginDebugSettings.resetForTesting();
  });

  testWidgets(
    'cached Home purchase checks UUID then forces unclosable login and claims with its receipt',
    (tester) async {
      final h = Harness(
        provider: MembershipProvider.apple,
        guestRecoveryEnabled: true,
        claimEnabled: true,
      )..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      await openGuestApp(tester, h, homeOnly: true);
      expect(find.byType(LoginSheet), findsNothing);
      await h.service.checkGuestPurchasesOnHome();
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsOneWidget);
      expect(find.text('VIP purchase successful!'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsOneWidget);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsNothing);
      expect(find.text('Me'), findsOneWidget);
      expect(h.claimRequests, hasLength(1));
      expect(h.claimRequests.single.guest.accountUuid, guest.accountUuid);
      expect(
        h.store.claims.values.where((r) => r.status != 'completed'),
        isEmpty,
      );
      expect(h.refreshes, greaterThan(0));
    },
  );

  testWidgets(
    'startup recovery support preserves checkout success OK then login',
    (tester) async {
      final h = Harness(guestRecoveryEnabled: true, claimEnabled: true)
        ..uid = null;
      await openGuestApp(tester, h);
      await tester.tap(find.byKey(const ValueKey('pro-subscribe-button')));
      await tester.pump(const Duration(milliseconds: 250));
      await h.service.interceptPurchase(h.purchase(yearly: true));
      await tester.pumpAndSettle();
      expect(find.text('VIP purchase successful!'), findsOneWidget);
      expect(find.byType(LoginSheet), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsOneWidget);
    },
  );

  testWidgets(
    'successful forced login removes purchase routes before claim completes',
    (tester) async {
      final h = Harness(
        claimEnabled: true,
        retryDelay: const Duration(seconds: 15),
      )..uid = null;
      final binding = Completer<MembershipClaimResult>();
      h.claimHandler = (_) => binding.future;
      await openGuestApp(tester, h, inPurchasePage: true);
      await tester.tap(find.text('Open purchases'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pro-subscribe-button')));
      await tester.pump(const Duration(milliseconds: 250));
      await h.service.interceptPurchase(h.purchase(yearly: true));
      await tester.pumpAndSettle();
      expect(find.text('VIP purchase successful!'), findsOneWidget);
      expect(find.text('Me'), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsOneWidget);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(binding.isCompleted, isFalse);
      expect(find.text('Me'), findsOneWidget);
      expect(find.byType(LoginSheet, skipOffstage: false), findsNothing);
      expect(
        find.byType(ProSubscriptionContent, skipOffstage: false),
        findsNothing,
      );
      expect(find.text('Open purchases', skipOffstage: false), findsNothing);
      expect(Navigator.of(tester.element(find.text('Me'))).canPop(), isFalse);
      expect(h.claimRequests, hasLength(1));
      expect(h.store.claims, isNotEmpty);

      binding.completeError(StateError('temporary binding failure'));
      await tester.pumpAndSettle();
      expect(find.text('Me'), findsOneWidget);
      expect(h.store.claims, isNotEmpty);
      h.claimHandler = null;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(h.claimRequests, hasLength(2));
      expect(
        h.store.claims.values.where((r) => r.status != 'completed'),
        isEmpty,
      );
      expect(find.text('Me'), findsOneWidget);
      expect(h.refreshes, greaterThan(0));
    },
  );

  testWidgets(
    'debug bypass keeps purchase success and later manual login can claim',
    (tester) async {
      await membershipGuestLoginDebugSettings.setForceLogin(false);
      final h = Harness(claimEnabled: true)..uid = null;
      await openGuestApp(tester, h);
      await tester.tap(find.byKey(const ValueKey('pro-subscribe-button')));
      await tester.pump(const Duration(milliseconds: 250));
      await h.service.interceptPurchase(h.purchase(yearly: true));
      await tester.pumpAndSettle();
      expect(find.text('VIP purchase successful!'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsNothing);
      expect(h.store.claims.values.single.purchaseConfirmed, isTrue);
      expect(find.text('Me'), findsNothing);
      expect(find.byType(ProSubscriptionContent), findsOneWidget);
      expect(h.claimRequests, isEmpty);
      h.uid = 'first-login';
      h.service.resetForSession();
      await h.service.recover();
      expect(h.claimRequests, hasLength(1));
      expect(
        h.store.claims.values.where((r) => r.status != 'completed'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'saved debug bypass is loaded before startup login and can be re-enabled',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        MembershipGuestLoginDebugSettingsController.storageKey: false,
      });
      final h = Harness(claimEnabled: true)..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      final restarted = Harness(storage: h.store, claimEnabled: true)
        ..uid = null;
      await restarted.service.start();
      await openGuestApp(tester, restarted, homeOnly: true);
      expect(find.byType(LoginSheet), findsNothing);
      expect(h.store.claims, isNotEmpty);
      expect(restarted.claimRequests, isEmpty);
      await membershipGuestLoginDebugSettings.setForceLogin(true);
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsOneWidget);
      expect(find.byTooltip('Close'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsOneWidget);
    },
  );

  testWidgets(
    'turning off the switch dismisses only forced login beneath Debug Page',
    (tester) async {
      final h = Harness(claimEnabled: true)..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      await openGuestApp(tester, h, homeOnly: true);
      expect(find.byType(LoginSheet), findsOneWidget);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Debug Page')),
        ),
      );
      await tester.pumpAndSettle();
      await membershipGuestLoginDebugSettings.setForceLogin(false);
      await tester.pumpAndSettle();
      expect(find.text('Debug Page'), findsOneWidget);
      expect(find.byType(LoginSheet, skipOffstage: false), findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(LoginSheet), findsNothing);
      expect(h.store.claims, isNotEmpty);
      expect(h.claimRequests, isEmpty);
    },
  );

  testWidgets('a cache loaded after Home is idle schedules mandatory login', (
    tester,
  ) async {
    final h = Harness(claimEnabled: true)..uid = null;
    await h.service.purchase(h.product());
    await h.service.interceptPurchase(h.purchase());
    final restarted = Harness(storage: h.store, claimEnabled: true)..uid = null;
    await openGuestApp(tester, restarted, homeOnly: true);
    expect(find.byType(LoginSheet), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await restarted.service.start();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(LoginSheet), findsOneWidget);
    expect(find.text('VIP purchase successful!'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LoginSheet), findsOneWidget);
  });
  testWidgets('closing the purchase sheet after OK keeps forced login open', (
    tester,
  ) async {
    final h = Harness(claimEnabled: true)..uid = null;
    await openGuestApp(tester, h, inPurchaseSheet: true);
    await tester.tap(find.text('Open purchases'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pro-subscribe-button')));
    await tester.pump(const Duration(milliseconds: 250));
    await h.service.interceptPurchase(h.purchase(yearly: true));
    await tester.pumpAndSettle();
    expect(find.text('VIP purchase successful!'), findsOneWidget);
    expect(find.byType(LoginSheet), findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(ProSubscriptionContent), findsNothing);
    expect(find.byType(LoginSheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LoginSheet), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginSheet), findsNothing);
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('Open purchases', skipOffstage: false), findsNothing);
    expect(Navigator.of(tester.element(find.text('Me'))).canPop(), isFalse);
    expect(h.claimRequests, hasLength(1));
  });

  testWidgets(
    'success OK opens forced login; dismiss, failure and cancel keep it open',
    (tester) async {
      final h = Harness(claimEnabled: true)..uid = null;
      var outcome = 'cancel';
      await openGuestApp(
        tester,
        h,
        signIn: () async {
          if (outcome == 'cancel') throw const AuthCancelledException();
          return outcome == 'success';
        },
      );
      await tester.tap(find.byKey(const ValueKey('pro-subscribe-button')));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Purchasing VIP'), findsOneWidget);
      expect(find.byType(LoginSheet), findsNothing);
      await h.service.interceptPurchase(h.purchase(yearly: true));
      await tester.pumpAndSettle();
      expect(find.text('VIP purchase successful!'), findsOneWidget);
      expect(find.byType(LoginSheet), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('VIP purchase successful!'), findsNothing);
      expect(find.byType(LoginSheet), findsOneWidget);
      expect(find.byTooltip('Close'), findsNothing);
      await tester.tapAt(const Offset(5, 100));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.drag(find.text('Sign up to continue'), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsOneWidget);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsOneWidget);
      expect(h.uid, isNull);
      outcome = 'failure';
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsOneWidget);
      expect(h.claimRequests, isEmpty);
      outcome = 'success';
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsNothing);
      expect(h.claimRequests, hasLength(1));
      expect(h.uid, 'first-login');
      expect(find.text('Me'), findsOneWidget);
      expect(
        find.byType(ProSubscriptionContent, skipOffstage: false),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'every restart before binding opens forced login directly from the cache',
    (tester) async {
      final h = Harness(claimEnabled: true)..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      final restarted = Harness(storage: h.store, claimEnabled: true)
        ..uid = null;
      await restarted.service.recover();
      await openGuestApp(tester, restarted, homeOnly: true);
      expect(find.text('VIP purchase successful!'), findsNothing);
      expect(find.byType(LoginSheet), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final again = Harness(storage: h.store, claimEnabled: true)..uid = null;
      await again.service.recover();
      await openGuestApp(tester, again, homeOnly: true);
      expect(find.text('VIP purchase successful!'), findsNothing);
      expect(find.byType(LoginSheet), findsOneWidget);
      expect(find.byTooltip('Close'), findsNothing);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginSheet), findsNothing);
      expect(
        h.store.claims.values.where((r) => r.status != 'completed'),
        isEmpty,
      );
      expect(find.text('Me'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final afterBinding = Harness(storage: h.store, claimEnabled: true)
        ..uid = null;
      await afterBinding.service.recover();
      await openGuestApp(tester, afterBinding, homeOnly: true);
      expect(find.byType(LoginSheet), findsNothing);
      expect(find.text('VIP purchase successful!'), findsNothing);
      expect(afterBinding.claimRequests, isEmpty);
    },
  );
}
