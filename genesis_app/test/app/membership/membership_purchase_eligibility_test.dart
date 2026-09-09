import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/membership/membership_purchase_service.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';

import '../../support/membership_fixtures.dart';
import 'membership_purchase_service_test.dart' as support;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final guest in [false, true]) {
    for (final yearly in [true, false]) {
      test(
        'active annual blocks guest=$guest yearly=$yearly before store lookup',
        () async {
          final h = support.Harness();
          if (guest) h.uid = null;
          final reason = yearly
              ? 'already_subscribed'
              : 'downgrade_not_allowed';
          h.productsHandler = () async => [
            membershipProduct(
              yearly: yearly,
              canPurchase: false,
              purchaseBlockReason: reason,
            ),
          ];
          final event = h.service.checkoutEvents.firstWhere(
            (e) => e.state == MembershipCheckoutState.failed,
          );
          // The page's cached product still says it can be purchased.
          await h.service.purchase(h.product(yearly: yearly));
          expect((await event).reason, reason);
          expect(h.eligibilityQueries, 1);
          expect(h.platform.product, isNull);
          expect(h.platform.launches, 0);
          expect(h.guestPrepares, 0);
          expect(h.store.records, isEmpty);
        },
      );
    }
  }

  for (final provider in MembershipProvider.values) {
    for (final guest in [false, true]) {
      test(
        '$provider guest=$guest ignores action during checkout and report',
        () async {
          for (final action in ['upgrade', 'none']) {
            final h = support.Harness(provider: provider);
            if (guest) h.uid = null;
            h.productsHandler = () async => [
              MembershipProduct.fromJson({
                ...h.product(yearly: true).toJson(),
                'purchase_action': action,
              }),
            ];
            await h.service.purchase(h.product(yearly: true));
            expect(h.eligibilityQueries, 1);
            expect(h.platform.product?.isYearly, isTrue);
            expect(h.platform.launches, 1);
            expect(h.guestPrepares, guest ? 1 : 0);
            expect(h.reports, isEmpty);

            await h.service.interceptPurchase(h.purchase(yearly: true));
            expect(h.reports, hasLength(1));
            expect(h.reports.single.product.isYearly, isTrue);
            expect(h.reports.single.guest != null, guest);
            expect(
              h.reports.single.toJson(),
              isNot(contains('purchase_action')),
            );
          }
        },
      );
    }
  }

  for (final (canPurchase, blockReason, expectedReason) in [
    (false, '', 'eligibility_unavailable'),
    (
      true,
      'cross_platform_upgrade_not_allowed',
      'cross_platform_upgrade_not_allowed',
    ),
  ]) {
    test(
      'eligibility still blocks canPurchase=$canPurchase reason=$blockReason',
      () async {
        final h = support.Harness();
        h.productsHandler = () async => [
          membershipProduct(
            canPurchase: canPurchase,
            purchaseBlockReason: blockReason,
          ),
        ];
        final event = h.service.checkoutEvents.firstWhere(
          (e) => e.state == MembershipCheckoutState.failed,
        );
        await h.service.purchase(h.product());
        expect((await event).reason, expectedReason);
        expect(h.platform.product, isNull);
        expect(h.platform.launches, 0);
        expect(h.guestPrepares, 0);
      },
    );
  }

  test(
    'unavailable or changed eligibility cannot launch using cached product data',
    () async {
      for (final failure in ['offline', 'missing', 'changed_offer']) {
        final h = support.Harness();
        h.productsHandler = () async {
          if (failure == 'offline') throw StateError('offline');
          return failure == 'missing'
              ? []
              : [membershipProduct(offerId: 'different-offer')];
        };
        final event = h.service.checkoutEvents.firstWhere(
          (e) => e.state == MembershipCheckoutState.failed,
        );
        await h.service.purchase(h.product());
        expect((await event).reason, 'eligibility_unavailable');
        expect(h.platform.product, isNull);
        expect(h.platform.launches, 0);
      }
    },
  );

  test(
    'session switch while checking eligibility cannot prepare a store purchase',
    () async {
      final h = support.Harness();
      final gate = Completer<List<MembershipProduct>>();
      h.productsHandler = () => gate.future;
      final task = h.service.purchase(h.product());
      await pumpEventQueue();
      h.uid = 'another-user';
      gate.complete([h.product()]);
      await task;
      expect(h.platform.product, isNull);
      expect(h.platform.launches, 0);
    },
  );

  for (final status in ['accepted', 'offline', 'pending']) {
    test('$status order blocks another plan and survives restart', () async {
      final h = support.Harness();
      h.reportHandler = (_) async {
        if (status == 'offline') throw StateError('offline');
        return const MembershipPurchaseReport(
          status: MembershipReportStatus.accepted,
          reportId: 'accepted',
        );
      };
      await h.service.purchase(h.product(yearly: true));
      await h.service.interceptPurchase(
        h.purchase(
          yearly: true,
          status: status == 'pending'
              ? BillingPurchaseStatus.pending
              : BillingPurchaseStatus.purchased,
        ),
      );
      final restarted = support.Harness(storage: h.store);
      final event = restarted.service.checkoutEvents.firstWhere(
        (e) => e.state == MembershipCheckoutState.failed,
      );
      await restarted.service.purchase(restarted.product());
      expect((await event).reason, 'purchase_processing');
      expect(restarted.eligibilityQueries, 0);
      expect(restarted.platform.launches, 0);
      expect(h.store.records, hasLength(1));
      expect(h.store.confirmed, isEmpty);
    });
  }

  test(
    'confirmed historical order does not block an expired member allowed by server',
    () async {
      final h = support.Harness();
      await h.service.purchase(h.product(yearly: true));
      await h.service.interceptPurchase(h.purchase(yearly: true));
      expect(h.store.confirmed, hasLength(1));
      // A later server response allows new purchase after the old plan expired.
      await h.service.purchase(h.product());
      expect(h.platform.launches, 2);
      expect(h.eligibilityQueries, 2);
    },
  );

  test(
    'accepted pending payment can complete by retry without another store callback',
    () async {
      final h = support.Harness(provider: MembershipProvider.apple);
      h.reportHandler = (_) async => const MembershipPurchaseReport(
        status: MembershipReportStatus.accepted,
        reportId: 'accepted',
      );
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(
        h.purchase(status: BillingPurchaseStatus.pending),
      );
      expect(h.platform.finishes, 0);
      expect(h.store.records.values.single.state, 'pending');
      expect(h.service.catalogRevision.value, 1);
      h.reportHandler = null;
      await h.service.recover();
      expect(h.reports.last.toJson(), h.reports.first.toJson());
      expect(h.service.state.value, MembershipCheckoutState.completed);
      expect(h.platform.finishes, 1);
      expect(h.store.records, isEmpty);
      expect(h.store.confirmed.values.single.paid, isTrue);
      expect(h.service.catalogRevision.value, 2);
    },
  );

  test(
    'rejected pending payment is terminal and preserves reason without finishing unpaid transaction',
    () async {
      final h = support.Harness(provider: MembershipProvider.apple);
      h.reportHandler = (_) async => const MembershipPurchaseReport(
        status: MembershipReportStatus.rejected,
        reportId: 'rejected',
        reason: 'purchase_canceled',
      );
      final rejected = h.service.checkoutEvents.firstWhere(
        (e) => e.state == MembershipCheckoutState.rejected,
      );
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(
        h.purchase(status: BillingPurchaseStatus.pending),
      );
      expect((await rejected).reason, 'purchase_canceled');
      await h.service.recover();
      expect(h.reports, hasLength(1));
      expect(h.store.records, isEmpty);
      expect(h.store.confirmed.values.single.reportReason, 'purchase_canceled');
      expect(h.platform.finishes, 0);
      expect(h.refreshes, 0);
      expect(h.service.catalogRevision.value, 1);
    },
  );

  test(
    'rejected account mismatch never finishes another account Apple transaction',
    () async {
      final h = support.Harness(provider: MembershipProvider.apple);
      h.reportHandler = (_) async => const MembershipPurchaseReport(
        status: MembershipReportStatus.rejected,
        reportId: 'rejected',
        reason: 'account_mismatch',
      );
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      await h.service.recover();
      expect(h.platform.finishes, 0);
      expect(h.reports, hasLength(1));
      expect(h.store.records, isEmpty);
    },
  );
}
