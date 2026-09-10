import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';

import 'membership_purchase_service_test.dart' as support;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unchanged accepted restore retries once per batch without catalog updates',
    () async {
      final h = support.Harness(
        provider: MembershipProvider.apple,
        restoreEnabled: true,
      );
      h.recoverable = [h.purchase(status: BillingPurchaseStatus.pending)];
      h.reportHandler = (_) async => const MembershipPurchaseReport(
        status: MembershipReportStatus.accepted,
        reportId: 'accepted',
      );
      await h.service.restorePurchases(products: [h.product()]);
      final revision = h.service.catalogRevision.value;
      final requestId = h.reports.single.requestId;
      await h.service.restorePurchases();
      expect(h.reports, hasLength(2));
      expect(h.reports.last.requestId, requestId);
      expect(h.service.catalogRevision.value, revision);
      expect(h.store.records.values.single.reportStatus, 'accepted');

      h.reportHandler = null;
      await h.service.recover();
      expect(h.service.catalogRevision.value, revision + 1);
      expect(h.store.restores, isEmpty);
    },
  );

  test(
    'batch deduplication still processes a pending to paid store update',
    () async {
      final h = support.Harness(
        provider: MembershipProvider.apple,
        restoreEnabled: true,
      );
      h.recoverable = [h.purchase(status: BillingPurchaseStatus.pending)];
      h.reportHandler = (_) async => const MembershipPurchaseReport(
        status: MembershipReportStatus.accepted,
        reportId: 'accepted',
      );
      await h.service.restorePurchases(products: [h.product()]);
      final revision = h.service.catalogRevision.value;
      final requestId = h.reports.single.requestId;
      h.storeQuery = () async {
        h.reportHandler = null;
        return [h.purchase()];
      };
      await h.service.restorePurchases();
      expect(h.reports, hasLength(3));
      expect(h.reports.every((r) => r.requestId == requestId), isTrue);
      expect(h.service.catalogRevision.value, revision + 1);
      expect(h.store.restores, isEmpty);
      expect(h.platform.finishes, 1);
    },
  );

  test(
    'renewal using the same Google token still invalidates the catalog',
    () async {
      final h = support.Harness(restoreEnabled: true);
      await h.service.purchase(h.product(yearly: true));
      await h.service.interceptPurchase(h.purchase(yearly: true));
      final revision = h.service.catalogRevision.value;
      h.recoverable = [h.purchase(yearly: true)];
      await h.service.restorePurchases(products: [h.product(yearly: true)]);
      expect(h.service.catalogRevision.value, revision);
      h.recoverable = [h.purchase(yearly: true, transaction: 'renewal')];
      await h.service.restorePurchases();
      expect(h.service.catalogRevision.value, revision + 1);
      expect(h.reports.last.transactionId, 'renewal');
    },
  );

  test(
    'pending restore remains queued and blocks checkout until official completion',
    () async {
      final h = support.Harness(
        provider: MembershipProvider.apple,
        restoreEnabled: true,
      );
      h.recoverable = [
        h.purchase(yearly: true, status: BillingPurchaseStatus.pending),
      ];
      h.reportHandler = (_) async => const MembershipPurchaseReport(
        status: MembershipReportStatus.accepted,
        reportId: 'accepted',
      );
      await h.service.restorePurchases(
        products: [h.product(), h.product(yearly: true)],
      );
      expect(h.store.records.values.single.reportStatus, 'accepted');
      expect(h.platform.finishes, 0);
      expect(h.service.catalogRevision.value, 1);
      await h.service.purchase(h.product());
      expect(h.platform.launches, 0);
      h.reportHandler = null;
      await h.service.recover();
      expect(h.reports.last.toJson(), h.reports.first.toJson());
      expect(h.store.restores, isEmpty);
      expect(h.platform.finishes, 1);
      expect(h.refreshes, 1);
      expect(h.service.catalogRevision.value, 2);
    },
  );

  test(
    'rejected pending restore preserves reason across cleanup retry and stops reporting',
    () async {
      final h = support.Harness(
        provider: MembershipProvider.apple,
        restoreEnabled: true,
      );
      h.recoverable = [h.purchase(status: BillingPurchaseStatus.pending)];
      h.store.failComplete = true;
      h.reportHandler = (_) async => const MembershipPurchaseReport(
        status: MembershipReportStatus.rejected,
        reportId: 'rejected',
        reason: 'purchase_canceled',
      );
      await h.service.restorePurchases(products: [h.product()]);
      expect(h.store.records.values.single.reportReason, 'purchase_canceled');
      h.store.failComplete = false;
      await h.service.recover();
      expect(h.store.restores, isEmpty);
      expect(h.reports, hasLength(1));
      expect(h.platform.finishes, 0);
      expect(h.refreshes, 0);
    },
  );

  test(
    'restore cleanup failure retries removal without submitting another report',
    () async {
      final h = support.Harness(
        provider: MembershipProvider.apple,
        restoreEnabled: true,
      );
      h.store.failComplete = true;
      h.recoverable = [h.purchase()];
      await h.service.restorePurchases(products: [h.product()]);
      expect(h.store.records.values.single.reportStatus, 'completed');
      h.store.failComplete = false;
      await h.service.recover();
      expect(h.reports, hasLength(1));
      expect(h.platform.finishes, 1);
      expect(h.store.restores, isEmpty);
    },
  );

  test(
    'completed purchases stay deduplicated across repeated store queries',
    () async {
      final h = support.Harness(restoreEnabled: true);
      await h.service.purchase(h.product(yearly: true));
      await h.service.interceptPurchase(h.purchase());
      final originalKey = h.reports.single.requestId;
      h.recoverable = [h.purchase(), h.purchase()];
      await h.service.restorePurchases(
        products: [h.product(), h.product(yearly: true)],
      );
      await h.service.restorePurchases();
      expect(h.reports, hasLength(1));
      expect(h.reports.single.requestId, originalKey);
      expect(h.platform.launches, 1);
      expect(h.store.records, isEmpty);
      expect(h.store.restores, isEmpty);
    },
  );

  test(
    'recovered receipt survives restart and retries report with its original key',
    () async {
      final h = support.Harness(
        provider: MembershipProvider.apple,
        restoreEnabled: true,
      );
      h.recoverable = [h.purchase()];
      h.reportHandler = (_) async => throw StateError('offline');
      await h.service.restorePurchases(products: [h.product()]);
      final key = h.reports.single.requestId;
      expect(h.platform.finishes, 0);
      final restored = support.Harness(
        provider: MembershipProvider.apple,
        restoreEnabled: true,
        storage: h.store,
      );
      await restored.service.recover();
      expect(restored.reports.single.requestId, key);
      expect(restored.reports, hasLength(1));
      expect(restored.platform.finishes, 1);
      expect(restored.refreshes, 1);
    },
  );

  test(
    'store restore retries an existing failure without immediately creating a second operation',
    () async {
      final h = support.Harness(
        provider: MembershipProvider.apple,
        restoreEnabled: true,
      );
      h.recoverable = [h.purchase()];
      h.reportHandler = (_) async => throw StateError('offline');
      await h.service.restorePurchases(products: [h.product()]);
      h.reportHandler = null;
      await h.service.restorePurchases();
      expect(h.reports, hasLength(2));
      expect(h.reports.first.requestId, h.reports.last.requestId);
    },
  );

  test(
    'unresolved Google base plan is durably retained instead of guessed from catalog',
    () async {
      final h = support.Harness(restoreEnabled: true);
      h.recoverable = [h.purchase()];
      await h.service.restorePurchases(
        products: [h.product(), h.product(yearly: true)],
      );
      expect(h.reports, isEmpty);
      expect(
        h.store.restores.values.single.purchase.purchaseToken,
        'test-token',
      );
      expect(h.store.restores.values.single.product, isNull);
      await h.service.recover();
      expect(h.reports, isEmpty);
      expect(h.platform.launches, 0);
    },
  );

  test(
    'Apple can restore without a local purchase and retry finish without reposting',
    () async {
      final h = support.Harness(
        provider: MembershipProvider.apple,
        restoreEnabled: true,
      );
      h.recoverable = [h.purchase(yearly: true)];
      h.platform.finishFails = true;
      await h.service.restorePurchases(
        products: [h.product(), h.product(yearly: true)],
      );
      expect(h.reports.single.product.isYearly, isTrue);
      h.platform.finishFails = false;
      await h.service.recover();
      expect(h.reports, hasLength(1));
      expect(h.platform.finishes, 2);
      expect(h.store.restores, isEmpty);
    },
  );

  test(
    'accepted and account mismatch do not grant Gems and guest never reports a store query under a logged-in account',
    () async {
      for (final result in [
        const MembershipPurchaseReport(
          status: MembershipReportStatus.accepted,
          reportId: 'accepted',
        ),
        const MembershipPurchaseReport(
          status: MembershipReportStatus.rejected,
          reportId: 'rejected',
          reason: 'account_mismatch',
        ),
      ]) {
        final h = support.Harness(
          provider: MembershipProvider.apple,
          restoreEnabled: true,
        );
        h.recoverable = [h.purchase()];
        h.reportHandler = (_) async => result;
        await h.service.restorePurchases(products: [h.product()]);
        await h.service.recover();
        expect(
          h.reports,
          hasLength(result.status == MembershipReportStatus.accepted ? 2 : 1),
        );
        expect(h.refreshes, 0);
        if (result.reason == 'account_mismatch') expect(h.platform.finishes, 0);
      }
      final h = support.Harness(restoreEnabled: true)..uid = null;
      h.recoverable = [h.purchase()];
      await h.service.restorePurchases(products: [h.product()]);
      expect(h.restoreQueries, 0);
      expect(h.reports, isEmpty);
    },
  );

  test(
    'startup only retries local records, and concurrent restore requests share a store query',
    () async {
      final h = support.Harness(
        provider: MembershipProvider.apple,
        restoreEnabled: true,
      );
      await h.service.start();
      expect(h.restoreQueries, 0);
      final gate = Completer<List<BillingPurchase>>();
      h.storeQuery = () => gate.future;
      final first = h.service.restorePurchases(products: [h.product()]);
      final second = h.service.restorePurchases(products: [h.product()]);
      await pumpEventQueue();
      expect(h.restoreQueries, 1);
      gate.complete([h.purchase()]);
      await Future.wait([first, second]);
      expect(h.reports, hasLength(1));
    },
  );

  test(
    'account switch during the store query cannot restore under the new account',
    () async {
      final h = support.Harness(
        provider: MembershipProvider.apple,
        restoreEnabled: true,
      );
      final gate = Completer<List<BillingPurchase>>();
      h.storeQuery = () => gate.future;
      final first = h.service.restorePurchases(products: [h.product()]);
      await pumpEventQueue();
      h.uid = 'another-user';
      gate.complete([h.purchase()]);
      await first;
      expect(h.reports, isEmpty);
    },
  );
}
