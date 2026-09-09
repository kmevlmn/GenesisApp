import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/gems/pro_subscription_content.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

import '../app/membership/membership_purchase_service_test.dart' as service;
import '../support/membership_fixtures.dart';

Widget subscription(service.Harness h, {bool closeOnSuccess = false}) =>
    ProSubscriptionContent(
      productsLoader: loadTestMembershipOffers,
      purchaseService: h.service,
      closeOnPurchaseSuccess: closeOnSuccess,
    );

Future<void> open(WidgetTester tester, service.Harness h) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: GenesisTheme.light(),
      home: Scaffold(body: subscription(h)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('pro-subscribe-button')));
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets(
    'purchase dialog spans store launch and reporting, then requires OK',
    (tester) async {
      final h = service.Harness();
      final prepare = Completer<void>();
      final report = Completer<MembershipPurchaseReport>();
      h.platform.onPrepare = () => prepare.future;
      h.reportHandler = (_) => report.future;
      await open(tester, h);
      expect(find.text('Purchasing VIP'), findsOneWidget);
      expect(find.text('Purchasing Gems'), findsNothing);
      expect(h.platform.launches, 0);
      final dialog = find.byType(Dialog);
      final indicator = find.descendant(
        of: dialog,
        matching: find.byType(CircularProgressIndicator),
      );
      expect(tester.getSize(indicator), const Size(28, 28));
      await tester.tapAt(const Offset(5, 100));
      await tester.pump();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pump();
      expect(dialog, findsOneWidget);
      prepare.complete();
      await tester.pump();
      await tester.pump();
      expect(h.platform.launches, 1);
      final callback = h.service.interceptPurchase(h.purchase(yearly: true));
      await tester.pump();
      expect(h.reports, hasLength(1));
      expect(find.text('Purchasing VIP'), findsOneWidget);
      // A matched store callback ends the 90-second store wait; the report
      // request owns its timeout and continues using the same processing UI.
      await tester.pump(const Duration(seconds: 91));
      expect(find.text('Purchasing VIP'), findsOneWidget);
      report.complete(service.completed);
      await callback;
      await tester.pumpAndSettle();
      expect(find.text('VIP purchase successful!'), findsOneWidget);
      expect(
        find.text('Your VIP purchase is confirmed.', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Gems have been granted.', findRichText: true),
        findsNothing,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await navigator.maybePop();
      await tester.pump();
      expect(find.text('OK'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(find.byType(ProSubscriptionContent), findsOneWidget);
    },
  );

  for (final outcome in [
    'cancelled',
    'pending',
    'accepted',
    'rejected',
    'failed',
    'deferred',
    'storage failure',
    'stream failure',
  ]) {
    testWidgets(
      '$outcome dismisses processing with VIP feedback and leaves the page open',
      (tester) async {
        final h = service.Harness();
        if (outcome == 'failed') h.platform.launchResult = false;
        if (outcome == 'deferred') {
          h.reportHandler = (_) async => throw StateError('offline');
        }
        if (outcome == 'accepted' || outcome == 'rejected') {
          h.reportHandler = (_) async => MembershipPurchaseReport(
            status: outcome == 'accepted'
                ? MembershipReportStatus.accepted
                : MembershipReportStatus.rejected,
            reportId: 'test-report',
            reason: outcome == 'rejected' ? 'invalid_receipt' : null,
          );
        }
        await open(tester, h);
        if (outcome == 'storage failure') h.store.fail = true;
        if (outcome == 'stream failure') {
          h.service.handleStreamError();
        } else if (outcome != 'failed') {
          await h.service.interceptPurchase(
            h.purchase(
              yearly: true,
              status: switch (outcome) {
                'cancelled' => BillingPurchaseStatus.canceled,
                'pending' => BillingPurchaseStatus.pending,
                _ => BillingPurchaseStatus.purchased,
              },
            ),
          );
        }
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(Dialog), findsNothing);
        expect(find.text('VIP purchase successful!'), findsNothing);
        expect(find.byType(ProSubscriptionContent), findsOneWidget);
        final message = switch (outcome) {
          'cancelled' => 'VIP purchase cancelled.',
          'pending' => 'VIP payment is pending.',
          'accepted' => 'Your VIP purchase is being confirmed.',
          'deferred' || 'storage failure' || 'stream failure' =>
            'VIP purchase confirmation is delayed. Please check again later.',
          _ => 'VIP purchase failed.',
        };
        expect(find.text(message), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        h.service.dispose();
      },
    );
  }

  testWidgets(
    'another saved order cannot complete the current purchase dialog',
    (tester) async {
      final h = service.Harness();
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(
        h.purchase(token: 'older-token', transaction: 'older-transaction'),
      );
      await open(tester, h);
      await h.service.interceptPurchase(
        h.purchase(token: 'older-token', transaction: 'renewal-transaction'),
      );
      await tester.pump();
      expect(find.text('Purchasing VIP'), findsOneWidget);
      expect(find.text('VIP purchase successful!'), findsNothing);
      await h.service.interceptPurchase(h.purchase(yearly: true));
      await tester.pumpAndSettle();
      expect(find.text('VIP purchase successful!'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'session change closes the dialog without turning recovery into success UI',
    (tester) async {
      final h = service.Harness();
      await open(tester, h);
      h.uid = 'another-user';
      h.service.resetForSession();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(ProSubscriptionContent), findsOneWidget);
    },
  );

  testWidgets(
    'a delayed store preparation releases the dialog without launching later',
    (tester) async {
      final h = service.Harness();
      final prepare = Completer<void>();
      h.platform.onPrepare = () => prepare.future;
      await open(tester, h);
      await tester.pump(const Duration(seconds: 91));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(Dialog), findsNothing);
      expect(h.service.isBusy, isFalse);
      prepare.complete();
      await tester.pump();
      await tester.pump();
      expect(h.platform.launches, 0);
      await tester.pump(const Duration(seconds: 3));
      h.service.dispose();
    },
  );

  testWidgets('disposing the page closes only its purchase dialog', (
    tester,
  ) async {
    final h = service.Harness();
    final visible = ValueNotifier(true);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, value, _) =>
                value ? subscription(h) : const Text('Destination'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pro-subscribe-button')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Purchasing VIP'), findsOneWidget);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Destination'), findsOneWidget);
    await h.service.interceptPurchase(h.purchase(yearly: true));
    await tester.pumpAndSettle();
    expect(h.reports, hasLength(1));
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Destination'), findsOneWidget);
  });

  testWidgets(
    'success OK closes the purchase sheet, while cancellation keeps it open',
    (tester) async {
      final h = service.Harness();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: GenesisTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SizedBox(
                    height: 740,
                    child: subscription(h, closeOnSuccess: true),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pro-subscribe-button')));
      await tester.pump(const Duration(milliseconds: 250));
      await h.service.interceptPurchase(
        h.purchase(yearly: true, status: BillingPurchaseStatus.canceled),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProSubscriptionContent), findsOneWidget);
      expect(h.service.isBusy, isFalse);
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('pro-subscribe-button')));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Purchasing VIP'), findsOneWidget);
      expect(h.platform.launches, 2);
      await h.service.interceptPurchase(h.purchase(yearly: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(ProSubscriptionContent), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    },
  );
}
