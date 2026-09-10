import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/membership/membership_purchase_service.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/platform/billing/membership_pending_store.dart';

import '../../support/membership_fixtures.dart';
import 'membership_purchase_service_test.dart' as support;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MembershipProduct upgrade(MembershipProvider provider) => membershipProduct(
    provider: provider,
    yearly: true,
    upgradeAccountUuid: support.guest.accountUuid,
    upgradePurchaseToken: provider == MembershipProvider.google
        ? 'old-month-token'
        : null,
  );

  for (final provider in MembershipProvider.values) {
    test(
      '$provider upgrade uses refreshed original identity and reports new receipt',
      () async {
        final h = support.Harness(provider: provider);
        final current = upgrade(provider);
        h.productsHandler = () async => [current];
        h.accountUuidHandler = () async =>
            throw StateError('must not use login UUID');
        await h.service.purchase(h.product(yearly: true));
        expect(h.eligibilityQueries, 1);
        expect(h.platform.product, same(current));
        expect(h.platform.uuid, support.guest.accountUuid);
        expect(h.guestPrepares, 0);
        expect(h.store.records, isEmpty);
        await h.service.interceptPurchase(
          h.purchase(
            yearly: true,
            uuid: support.guest.accountUuid,
            token: 'new-year-token',
            transaction: '200',
          ),
        );
        final report = h.reports.single;
        expect(report.guest, isNull);
        expect(report.product.planCode, 'pro_yearly');
        expect(report.transactionId, '200');
        if (provider == MembershipProvider.google) {
          expect(report.toJson()['purchase_token'], 'new-year-token');
        }
        expect(report.toJson(), isNot(contains('request_id')));
        expect(jsonEncode(report.toJson()), isNot(contains('old-month-token')));
        expect(h.store.records, isEmpty);
        expect(h.refreshes, 1);
        expect(h.service.state.value, MembershipCheckoutState.completed);
      },
    );

    test('$provider rejects upgrade credentials returned to a guest', () async {
      final h = support.Harness(provider: provider)..uid = null;
      h.productsHandler = () async => [upgrade(provider)];
      await h.service.purchase(h.product(yearly: true));
      expect(h.service.state.value, MembershipCheckoutState.failed);
      expect(h.platform.launches, 0);
      expect(h.platform.product, isNull);
      expect(h.guestPrepares, 0);
    });

    test(
      '$provider removed upgrade credentials do not reuse cached identity',
      () async {
        final h = support.Harness(provider: provider);
        await h.service.purchase(upgrade(provider));
        expect(h.platform.uuid, support.accountUuid);
        expect(h.platform.product!.upgradeAccountUuid, isNull);
        expect(h.platform.product!.upgradePurchaseToken, isNull);
      },
    );
  }

  test(
    'catalog failure never launches using stale upgrade credentials',
    () async {
      final h = support.Harness();
      h.productsHandler = () async => throw StateError('server unavailable');
      await h.service.purchase(upgrade(MembershipProvider.google));
      expect(h.service.state.value, MembershipCheckoutState.failed);
      expect(h.platform.launches, 0);
      expect(h.store.records, isEmpty);
    },
  );

  for (final restart in [false, true]) {
    test(
      'old Google callback cannot become an annual receipt restart=$restart',
      () async {
        final first = support.Harness();
        first.productsHandler = () async => [
          upgrade(MembershipProvider.google),
        ];
        await first.service.purchase(first.product(yearly: true));
        final h = restart
            ? support.Harness(
                storage: support.PendingStore()
                  ..records.addAll({
                    for (final record in first.store.records.values)
                      record.requestId: MembershipPurchaseRecord.fromJson(
                        jsonDecode(jsonEncode(record.toJson()))
                            as Map<String, dynamic>,
                      ),
                  }),
              )
            : first;
        await h.service.interceptPurchase(
          h.purchase(
            token: 'old-month-token',
            transaction: '100',
            uuid: support.guest.accountUuid,
            status: BillingPurchaseStatus.restored,
          ),
        );
        expect(h.reports, isEmpty);
        expect(h.store.records, isEmpty);
        await h.service.interceptPurchase(
          h.purchase(
            yearly: true,
            token: 'new-year-token',
            transaction: '200',
            uuid: support.guest.accountUuid,
          ),
        );
        if (restart) {
          expect(h.reports, isEmpty);
        } else {
          expect(h.reports.single.purchaseToken, 'new-year-token');
          expect(h.reports.single.product.planCode, 'pro_yearly');
        }
      },
    );
  }
}
