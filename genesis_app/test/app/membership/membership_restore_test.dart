import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/platform/billing/membership_restore_record.dart';
import 'membership_purchase_service_test.dart' as support;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final provider in MembershipProvider.values) {
    for (final status in [
      BillingPurchaseStatus.restored,
      BillingPurchaseStatus.purchased,
      BillingPurchaseStatus.pending,
    ]) {
      test(
        '$provider unsolicited $status receipt never becomes an old order',
        () async {
          final h = support.Harness(provider: provider, restoreEnabled: true);
          final receipt = h.purchase(status: status);
          h.recoverable = [receipt];
          await h.service.start();
          await h.service.restorePurchases(products: [h.product()]);
          expect(await h.service.interceptPurchase(receipt), isTrue);
          expect(h.store.records, isEmpty);
          expect(h.store.restores, isEmpty);
          expect(h.store.confirmed, isEmpty);
          expect(h.reports, isEmpty);
          expect(h.recoverQueries + h.restoreQueries, 0);
          await h.service.purchase(h.product());
          expect(h.platform.launches, 1);
        },
      );
    }
    test(
      '$provider existing unknown-plan restore is cleaned and cannot block checkout',
      () async {
        final h = support.Harness(provider: provider);
        await h.store.saveRestore(
          MembershipRestoreRecord(
            requestId: 'legacy',
            ownerUid: h.uid!,
            purchase: h.purchase(),
          ),
        );
        await h.service.start();
        expect(h.store.restores, isEmpty);
        expect(h.reports, isEmpty);
        await h.service.purchase(h.product());
        expect(h.platform.launches, 1);
      },
    );
  }
}
