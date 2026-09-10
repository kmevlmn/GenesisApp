import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/membership/membership_purchase_service.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/platform/billing/membership_pending_store.dart';

import 'membership_purchase_service_test.dart' as support;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MembershipPurchaseRecord missing(
    support.Harness h, {
    String state = 'purchased',
  }) => MembershipPurchaseRecord(
    requestId: 'missing-receipt',
    product: h.product(),
    accountUuid: h.uid == null
        ? support.guest.accountUuid
        : support.accountUuid,
    ownerUid: h.uid,
    guest: h.uid == null ? support.guest : null,
    state: state,
  );

  for (final provider in MembershipProvider.values) {
    for (final guest in [false, true]) {
      test(
        '$provider guest=$guest empty store releases only a receiptless signal',
        () async {
          final h = support.Harness(provider: provider, restoreEnabled: true);
          if (guest) h.uid = null;
          final original = missing(h);
          h.store.records[original.requestId] = original;
          await h.service.purchase(h.product());
          expect(h.restoreQueries, 1);
          expect(h.platform.launches, 1);
          expect(h.store.records[original.requestId]!.state, 'receipt_missing');
          expect(h.store.records[original.requestId]!.guest, original.guest);
          expect(h.reports, isEmpty);
          expect(h.restoreRequests, isEmpty);
          expect(h.platform.finishes, 0);
        },
      );
    }

    test(
      '$provider recovers a real receipt with the original request',
      () async {
        final h = support.Harness(provider: provider, restoreEnabled: true);
        final original = missing(h);
        h.store.records[original.requestId] = original;
        h.recoverable = [h.purchase()];
        h.reportHandler = (_) async => const MembershipPurchaseReport(
          status: MembershipReportStatus.accepted,
          reportId: 'accepted',
        );
        final blocked = h.service.checkoutEvents.firstWhere(
          (e) => e.state == MembershipCheckoutState.failed,
        );
        await h.service.purchase(h.product());
        expect((await blocked).reason, 'purchase_processing');
        expect(h.reports.single.requestId, original.requestId);
        expect(h.store.records[original.requestId]!.hasReceipt, isTrue);
        expect(h.platform.launches, 0);
      },
    );

    test(
      '$provider restart retries missing receipts without a purchase click',
      () async {
        final h = support.Harness(provider: provider, restoreEnabled: true);
        final original = missing(h);
        h.store.records[original.requestId] = original;
        h.recoverable = [h.purchase()];
        await h.service.recover();
        expect(h.reports.single.requestId, original.requestId);
        expect(h.store.confirmed[original.requestId]!.hasReceipt, isTrue);
        expect(h.store.records, isEmpty);
      },
    );

    test(
      '$provider new receiptless callback schedules recovery and ends waiting',
      () async {
        final h = support.Harness(provider: provider, restoreEnabled: true);
        await h.service.purchase(h.product());
        await h.service.interceptPurchase(
          h.purchase(token: '', transaction: ''),
        );
        expect(h.service.state.value, MembershipCheckoutState.deferred);
        expect(h.service.isBusy, isFalse);
        expect(h.reports, isEmpty);
        h.recoverable = [h.purchase()];
        await h.service.recover();
        expect(h.reports, hasLength(1));
        expect(h.store.confirmed, hasLength(1));
      },
    );
  }

  for (final state in ['purchased', 'receipt_missing']) {
    test('query failure cannot launch or change a $state signal', () async {
      final h = support.Harness(restoreEnabled: true);
      final original = missing(h, state: state);
      h.store.records[original.requestId] = original;
      h.storeQuery = () async => throw StateError('offline');
      await h.service.purchase(h.product());
      expect(h.platform.launches, 0);
      expect(h.store.records[original.requestId]!.state, state);
      expect(h.reports, isEmpty);
    });
  }

  test(
    'pending payment and partial receipt evidence are never released',
    () async {
      for (final state in ['pending', 'purchased']) {
        final h = support.Harness(restoreEnabled: true);
        final original = missing(
          h,
          state: state,
        ).copyWith(transactionId: state == 'purchased' ? 'store-order-id' : '');
        h.store.records[original.requestId] = original;
        await h.service.purchase(h.product());
        expect(h.platform.launches, 0);
        expect(h.store.records[original.requestId]!.state, state);
      }
    },
  );

  test('receipt arriving during an empty query is not downgraded', () async {
    final h = support.Harness(restoreEnabled: true);
    final original = missing(h);
    h.store.records[original.requestId] = original;
    final query = Completer<List<BillingPurchase>>();
    h.storeQuery = () => query.future;
    h.reportHandler = (_) async => const MembershipPurchaseReport(
      status: MembershipReportStatus.accepted,
      reportId: 'accepted',
    );
    final checkout = h.service.purchase(h.product());
    await pumpEventQueue();
    await h.service.interceptPurchase(h.purchase());
    query.complete([]);
    await checkout;
    expect(h.store.records[original.requestId]!.hasReceipt, isTrue);
    expect(h.store.records[original.requestId]!.reportStatus, 'accepted');
    expect(h.platform.launches, 0);
  });

  test(
    'late callback can still recover a retained receipt_missing attempt',
    () async {
      final h = support.Harness(restoreEnabled: true);
      final original = missing(h, state: 'receipt_missing');
      h.store.records[original.requestId] = original;
      await h.service.interceptPurchase(h.purchase());
      expect(h.reports.single.requestId, original.requestId);
      expect(h.store.confirmed[original.requestId]!.hasReceipt, isTrue);
    },
  );

  test('old query cannot release a signal after account changes', () async {
    final h = support.Harness(restoreEnabled: true);
    final original = missing(h);
    h.store.records[original.requestId] = original;
    final query = Completer<List<BillingPurchase>>();
    h.storeQuery = () => query.future;
    final checkout = h.service.purchase(h.product());
    await pumpEventQueue();
    h.uid = 'different-account';
    query.complete([]);
    await checkout;
    expect(h.platform.launches, 0);
    expect(h.store.records[original.requestId]!.state, 'purchased');
  });

  testWidgets(
    'receipt query obeys the click deadline and ignores late emptiness',
    (tester) async {
      final h = support.Harness(restoreEnabled: true);
      final original = missing(h);
      h.store.records[original.requestId] = original;
      final query = Completer<List<BillingPurchase>>();
      h.storeQuery = () => query.future;
      final checkout = h.service.purchase(h.product());
      await tester.pump();
      await tester.pump(const Duration(seconds: 90));
      await checkout;
      query.complete([]);
      await tester.pump();
      expect(h.platform.launches, 0);
      expect(h.store.records[original.requestId]!.state, 'purchased');
      expect(h.service.state.value, MembershipCheckoutState.deferred);
    },
  );

  test('failed reconciliation persistence does not launch a payment', () async {
    final h = support.Harness(restoreEnabled: true);
    final original = missing(h);
    h.store.records[original.requestId] = original;
    h.store.fail = true;
    await h.service.purchase(h.product());
    expect(h.platform.launches, 0);
    expect(h.store.records[original.requestId]!.state, 'purchased');
    expect(h.reports, isEmpty);
  });

  test(
    'another account receiptless record is not queried or changed',
    () async {
      final h = support.Harness(restoreEnabled: true);
      final original = missing(h);
      h.store.records[original.requestId] = original;
      h.uid = 'different-account';
      await h.service.purchase(h.product());
      expect(h.platform.launches, 1);
      expect(h.restoreQueries, 0);
      expect(h.store.records[original.requestId]!.state, 'purchased');
    },
  );
}
