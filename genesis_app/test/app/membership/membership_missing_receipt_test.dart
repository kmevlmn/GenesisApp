import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/platform/billing/membership_pending_store.dart';
import 'membership_purchase_service_test.dart' as support;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final provider in MembershipProvider.values) {
    for (final state in [
      'prepared',
      'pending',
      'purchased',
      'receipt_missing',
      'canceled',
      'error',
    ]) {
      test(
        '$provider legacy $state without proof is removed without a store query',
        () async {
          final h = support.Harness(provider: provider, restoreEnabled: true);
          await h.store.save(
            MembershipPurchaseRecord(
              requestId: 'legacy',
              product: h.product(),
              accountUuid: support.accountUuid,
              ownerUid: h.uid,
              state: state,
            ),
          );
          await h.service.recover();
          expect(h.store.records, isEmpty);
          expect(h.store.confirmed, isEmpty);
          expect(h.recoverQueries + h.restoreQueries, 0);
          expect(h.reports, isEmpty);
          await h.service.purchase(h.product());
          expect(h.platform.launches, 1);
        },
      );
    }
    test(
      '$provider incomplete callback creates no durable purchase and a late receipt still reports',
      () async {
        final h = support.Harness(provider: provider);
        await h.service.purchase(h.product());
        await h.service.interceptPurchase(
          h.purchase(token: '', transaction: ''),
        );
        expect(h.store.records, isEmpty);
        expect(h.reports, isEmpty);
        await h.service.interceptPurchase(h.purchase());
        expect(h.reports, hasLength(1));
        expect(h.store.records, isEmpty);
      },
    );
  }
}
