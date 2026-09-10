import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/platform/billing/membership_restore_record.dart';

import 'membership_purchase_service_test.dart' as support;

MembershipRestoreRecord legacy(
  support.Harness h, {
  String id = 'legacy-restore',
  String? owner,
  String transaction = '100',
  String? status = 'accepted',
  String? reason,
  bool finished = false,
}) => MembershipRestoreRecord(
  requestId: id,
  ownerUid: owner ?? h.uid!,
  purchase: h.purchase(transaction: transaction),
  product: h.product(),
  reportStatus: status,
  reportId: 'legacy-report-id',
  reportReason: reason,
  finished: finished,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy report failure without a response preserves its request and receipt',
    () async {
      final h = support.Harness();
      final old = legacy(h, status: null);
      await h.store.saveRestore(old);
      h.reportHandler = (_) async => throw StateError('offline');
      await h.service.recover();
      expect(h.reports.single.toJson(), old.request.toJson());
      expect(h.store.records.keys.single, old.requestId);
      expect(h.reports.single.toJson(), isNot(contains('request_id')));
      expect(h.reports.single.toJson(), isNot(contains('plan_code')));
      expect(
        h.store.records.values.single.purchaseToken,
        old.purchase.purchaseToken,
      );
      expect(h.store.restores, isEmpty);
      h.service.dispose();
      final restarted = support.Harness(storage: h.store);
      await restarted.service.recover();
      expect(restarted.reports.single.toJson(), h.reports.single.toJson());
      expect(h.store.records, isEmpty);
      expect(h.store.confirmed, isEmpty);
    },
  );

  for (final provider in MembershipProvider.values) {
    test(
      '$provider old accepted receipt retries through report and survives restart',
      () async {
        final h = support.Harness(provider: provider);
        final old = legacy(h);
        await h.store.saveRestore(old);
        h.reportHandler = (_) async => const MembershipPurchaseReport(
          status: MembershipReportStatus.accepted,
          reportId: 'pending-report',
        );
        await h.service.start();
        expect(h.reports.single.toJson(), old.request.toJson());
        expect(h.store.records.keys.single, old.requestId);
        expect(h.reports.single.toJson(), isNot(contains('request_id')));
        expect(h.reports.single.toJson(), isNot(contains('plan_code')));
        expect(h.reports.single.purchaseToken, old.purchase.purchaseToken);
        expect(h.reports.single.transactionId, old.purchase.transactionId);
        expect(h.store.restores, isEmpty);
        expect(h.store.records.values.single.reportStatus, 'accepted');
        h.service.dispose();
        final restarted = support.Harness(provider: provider, storage: h.store);
        await restarted.service.start();
        expect(restarted.reports.single.toJson(), h.reports.single.toJson());
        expect(h.store.records, isEmpty);
        expect(h.store.confirmed, isEmpty);
        expect(restarted.refreshes, 1);
      },
    );
  }

  test(
    'duplicate legacy receipts use only one report in the same store query batch',
    () async {
      final h = support.Harness(restoreEnabled: true);
      await h.store.saveRestore(legacy(h));
      await h.store.saveRestore(legacy(h, id: 'duplicate'));
      h.recoverable = [h.purchase(), h.purchase()];
      h.reportHandler = (_) async => const MembershipPurchaseReport(
        status: MembershipReportStatus.accepted,
        reportId: 'pending-report',
      );
      await h.service.restorePurchases(products: [h.product()]);
      expect(h.reports, hasLength(1));
      expect(h.store.restores, isEmpty);
      expect(h.store.records, hasLength(1));
      await h.service.restorePurchases();
      expect(h.reports, hasLength(2));
      expect(h.reports.first.toJson(), h.reports.last.toJson());
    },
  );

  for (final status in ['completed', 'rejected']) {
    test(
      'legacy $status only finishes and cleans up without posting report',
      () async {
        final h = support.Harness(provider: MembershipProvider.apple);
        await h.store.saveRestore(
          legacy(
            h,
            status: status,
            reason: status == 'rejected' ? 'account_mismatch' : null,
            finished: status == 'rejected',
          ),
        );
        await h.service.start();
        expect(h.reports, isEmpty);
        expect(h.store.restores, isEmpty);
        expect(h.store.records, isEmpty);
        expect(h.platform.finishes, 0);
        expect(h.store.confirmed, isEmpty);
      },
    );
  }

  test(
    'failed purchase-queue persistence retains legacy receipt until retry',
    () async {
      final h = support.Harness();
      await h.store.saveRestore(legacy(h));
      h.store.fail = true;
      await h.service.recover();
      expect(h.reports, isEmpty);
      expect(h.store.restores, hasLength(1));
      expect(h.store.records, isEmpty);
      h.store.fail = false;
      h.service.dispose();
      final restarted = support.Harness(storage: h.store);
      await restarted.service.recover();
      expect(restarted.reports.single.toJson(), legacy(h).request.toJson());
      expect(h.store.restores, isEmpty);
      expect(h.store.records, isEmpty);
    },
  );

  test(
    'crash after migration save retries report once and removes the old backup',
    () async {
      final h = support.Harness();
      await h.store.saveRestore(legacy(h));
      h.store.failRestoreCleanup = true;
      await h.service.recover();
      expect(h.reports, isEmpty);
      expect(h.store.restores, hasLength(1));
      expect(h.store.records, hasLength(1));
      h.service.dispose();
      h.store.failRestoreCleanup = false;
      final restarted = support.Harness(storage: h.store);
      await restarted.service.recover();
      expect(restarted.reports.single.toJson(), legacy(h).request.toJson());
      expect(h.store.restores, isEmpty);
      expect(h.store.records, isEmpty);
      await restarted.service.recover();
      expect(restarted.reports, hasLength(1));
    },
  );

  test(
    'another account legacy receipt stays private and does not block current checkout',
    () async {
      final h = support.Harness();
      await h.store.saveRestore(legacy(h, owner: 'different-user'));
      await h.service.recover();
      expect(h.reports, isEmpty);
      expect(h.store.restores, hasLength(1));
      await h.service.purchase(h.product());
      expect(h.platform.launches, 1);
    },
  );
}
