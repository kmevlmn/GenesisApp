import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/models/membership_guest_purchase_check.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/platform/billing/membership_guest_claim_record.dart';
import 'package:genesis_flutter_android/platform/billing/membership_store_purchase.dart';
import 'membership_purchase_service_test.dart' as support;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a new guest purchase can reuse a bound cached UUID without reusing its claim owner',
    () async {
      final h = support.Harness(claimEnabled: true)..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      h.uid = 'first-login';
      await h.service.recover();
      expect(h.store.claims.values.single.status, 'completed');
      h.uid = null;
      h.service.resetForSession();
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(
        h.purchase(token: 'new-token', transaction: 'new-transaction'),
      );
      final claim = h.store.claims.values.single;
      expect(claim.ownerUid, isNull);
      expect(claim.status, isNull);
      expect(claim.purchaseConfirmed, isTrue);
      expect(h.store.confirmed.values.single.purchaseToken, 'new-token');
      h.uid = 'second-login';
      await h.service.recover();
      expect(h.claimRequests.last.purchaseToken, 'new-token');
      expect(h.store.claims.values.single.ownerUid, 'second-login');
      expect(h.store.confirmed, isEmpty);
    },
  );
  test(
    'empty store after reinstall does not call check or manufacture an order',
    () async {
      final h = support.Harness(guestRecoveryEnabled: true)..uid = null;
      await h.service.checkGuestPurchasesOnHome();
      await h.service.checkGuestPurchasesOnHome();
      expect(h.guestChecks, isEmpty);
      expect(h.guestDiscoveries, 1);
      expect(h.eligibilityQueries, 0);
      expect(h.store.records, isEmpty);
      expect(h.store.restores, isEmpty);
      expect(h.store.claims, isEmpty);
    },
  );
  for (final provider in MembershipProvider.values) {
    for (final unbound in [false, true]) {
      test(
        '$provider reinstall discovers original UUID and check=$unbound decides login without storing orders',
        () async {
          final h = support.Harness(
            provider: provider,
            guestRecoveryEnabled: true,
            claimEnabled: true,
          )..uid = null;
          h.guestPurchases = [
            MembershipStorePurchase(purchase: h.purchase()),
            MembershipStorePurchase(
              purchase: h.purchase(
                uuid: support.guest.accountUuid.toUpperCase(),
              ),
            ),
          ];
          h.guestCheckHandler = (_) async =>
              MembershipGuestPurchaseCheck(hasUnboundOrder: unbound);
          await h.service.start();
          expect(h.guestDiscoveries, 0);
          await Future.wait([
            h.service.checkGuestPurchasesOnHome(),
            h.service.checkGuestPurchasesOnHome(),
          ]);
          await h.service.checkGuestPurchasesOnHome();
          expect(h.guestDiscoveries, 1);
          expect(h.guestChecks, [support.guest.accountUuid]);
          expect(
            h.service.guestLoginRequestId.value,
            unbound ? support.guest.accountUuid : isNull,
          );
          expect(h.guestPrepares, 0);
          expect(h.eligibilityQueries, 0);
          expect(h.platform.launches, 0);
          expect(h.reports, isEmpty);
          expect(h.claimRequests, isEmpty);
          expect(h.store.records, isEmpty);
          expect(h.store.confirmed, isEmpty);
          expect(h.store.restores, isEmpty);
          expect(h.store.claims, hasLength(unbound ? 1 : 0));
          if (unbound) {
            final proof = h.store.claims.values.single.recoveredProof!;
            expect(proof.storeProductId, h.purchase().productId);
            expect(proof.toJson(), isNot(contains('plan_code')));
            expect(proof.requestId, isNotEmpty);
            expect(h.store.claims.values.single.purchaseConfirmed, isFalse);
          }
          h.uid = 'first-login';
          h.service.resetForSession();
          await h.service.recover();
          expect(h.service.guestLoginRequestId.value, isNull);
          if (unbound) {
            expect(h.claimRequests, hasLength(1));
            if (provider == MembershipProvider.apple) {
              expect(h.claimRequests.single.transactionId, '100');
              expect(
                h.claimRequests.single.signedTransaction,
                'test.header.signature',
              );
            } else {
              expect(h.claimRequests.single.purchaseToken, 'test-token');
              expect(
                h.claimRequests.single.toJson().containsKey('plan_code'),
                isFalse,
              );
              expect(h.eligibilityQueries, 0);
            }
            expect(
              h.claimRequests.single.guest.accountUuid,
              support.guest.accountUuid,
            );
            expect(h.store.claims.values.single.recoveredProof, isNull);
            expect(h.store.claims.values.single.status, 'completed');
            expect(h.refreshes, 1);
          } else {
            expect(h.claimRequests, isEmpty);
          }
          expect(h.reports, isEmpty);
          expect(h.store.records, isEmpty);
          expect(h.store.confirmed, isEmpty);
          expect(h.store.restores, isEmpty);
        },
      );
      test(
        '$provider cached purchase check=$unbound alone decides startup login',
        () async {
          final first = support.Harness(provider: provider)..uid = null;
          await first.service.purchase(first.product(yearly: true));
          await first.service.interceptPurchase(first.purchase(yearly: true));
          first.service.dispose();
          final h = support.Harness(
            provider: provider,
            storage: first.store,
            guestRecoveryEnabled: true,
            claimEnabled: true,
          )..uid = null;
          h.guestCheckHandler = (_) async =>
              MembershipGuestPurchaseCheck(hasUnboundOrder: unbound);
          await h.service.start();
          expect(h.service.guestLoginRequestId.value, isNull);
          await Future.wait([
            h.service.checkGuestPurchasesOnHome(),
            h.service.checkGuestPurchasesOnHome(),
          ]);
          await h.service.checkGuestPurchasesOnHome();
          expect(h.guestChecks, [support.guest.accountUuid]);
          expect(h.guestDiscoveries, 0);
          expect(h.eligibilityQueries, 0);
          expect(
            h.service.guestLoginRequestId.value,
            unbound ? isNotNull : isNull,
          );
          h.uid = 'first-login';
          await h.service.recover();
          expect(h.claimRequests, hasLength(unbound ? 1 : 0));
          if (unbound) {
            expect(
              h.claimRequests.single.toJson(),
              isNot(contains('plan_code')),
            );
            expect(
              h.claimRequests.single.toJson(),
              first.reports.single.toJson(),
            );
            expect(h.store.claims.values.single.status, 'completed');
            expect(h.store.confirmed, isEmpty);
            final restart = support.Harness(
              provider: provider,
              storage: h.store,
              guestRecoveryEnabled: true,
              claimEnabled: true,
            )..uid = null;
            restart.guestCheckHandler = (_) async =>
                const MembershipGuestPurchaseCheck(hasUnboundOrder: false);
            await restart.service.checkGuestPurchasesOnHome();
            expect(restart.guestChecks, [support.guest.accountUuid]);
            expect(restart.service.guestLoginRequestId.value, isNull);
            restart.uid = 'another-login';
            await restart.service.recover();
            expect(restart.claimRequests, isEmpty);
          }
        },
      );
    }
  }
  for (final stage in ['store', 'check']) {
    test('reinstall $stage failure retries on next entry', () async {
      final h = support.Harness(guestRecoveryEnabled: true)..uid = null;
      h.guestPurchases = [MembershipStorePurchase(purchase: h.purchase())];
      if (stage == 'store') {
        h.guestPurchasesHandler = () async => throw StateError('store offline');
      } else {
        h.guestCheckHandler = (_) async => throw StateError('check offline');
      }
      await h.service.checkGuestPurchasesOnHome();
      expect(h.service.guestLoginRequestId.value, isNull);
      expect(h.service.guestOrderChecks, isEmpty);
      h.guestPurchasesHandler = null;
      h.guestCheckHandler = null;
      await h.service.checkGuestPurchasesOnHome();
      expect(h.guestDiscoveries, 2);
      expect(h.guestChecks, hasLength(stage == 'store' ? 1 : 2));
      expect(h.service.guestLoginRequestId.value, support.guest.accountUuid);
      expect(h.store.records, isEmpty);
      expect(h.store.restores, isEmpty);
    });
  }
  test(
    'pending, invalid or expired store identities do not trigger check',
    () async {
      final h = support.Harness(guestRecoveryEnabled: true)..uid = null;
      h.guestPurchases = [
        MembershipStorePurchase(
          purchase: h.purchase(status: BillingPurchaseStatus.pending),
        ),
        MembershipStorePurchase(purchase: h.purchase(uuid: '')),
        MembershipStorePurchase(purchase: h.purchase(uuid: 'invalid-uuid')),
        MembershipStorePurchase(
          purchase: h.purchase(),
          expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ];
      await h.service.checkGuestPurchasesOnHome();
      expect(h.guestDiscoveries, 1);
      expect(h.guestChecks, isEmpty);
      expect(h.service.guestLoginRequestId.value, isNull);
    },
  );
  test(
    'login during store discovery discards its UUIDs before check',
    () async {
      final h = support.Harness(guestRecoveryEnabled: true)..uid = null;
      final purchases = [MembershipStorePurchase(purchase: h.purchase())];
      final discovery = Completer<List<MembershipStorePurchase>>();
      h.guestPurchasesHandler = () => discovery.future;
      final check = h.service.checkGuestPurchasesOnHome();
      await pumpEventQueue();
      expect(h.guestDiscoveries, 1);
      h.uid = 'first-login';
      h.service.resetForSession();
      discovery.complete(purchases);
      await check;
      expect(h.guestChecks, isEmpty);
      expect(h.service.guestOrderChecks, isEmpty);
      expect(h.service.guestLoginRequestId.value, isNull);
      expect(h.store.claims, isEmpty);
    },
  );
  test(
    'check failure keeps UUID and retries next entry without forcing login',
    () async {
      final h = support.Harness(guestRecoveryEnabled: true)..uid = null;
      await h.store.saveGuestClaim(
        const MembershipGuestClaimRecord(
          guest: support.guest,
          purchaseConfirmed: true,
        ),
      );
      h.guestCheckHandler = (_) async => throw StateError('offline');
      await h.service.checkGuestPurchasesOnHome();
      expect(h.service.guestLoginRequestId.value, isNull);
      expect(h.store.claims, hasLength(1));
      h.guestCheckHandler = null;
      await h.service.checkGuestPurchasesOnHome();
      expect(h.guestChecks, hasLength(2));
      expect(h.service.guestLoginRequestId.value, isNotNull);
    },
  );
  test(
    'login during check discards result without enabling a foreign claim',
    () async {
      final h = support.Harness(guestRecoveryEnabled: true)..uid = null;
      await h.store.saveGuestClaim(
        const MembershipGuestClaimRecord(
          guest: support.guest,
          purchaseConfirmed: true,
        ),
      );
      final response = Completer<MembershipGuestPurchaseCheck>();
      h.guestCheckHandler = (_) => response.future;
      final check = h.service.checkGuestPurchasesOnHome();
      await pumpEventQueue();
      h.uid = 'first-login';
      h.service.resetForSession();
      response.complete(
        const MembershipGuestPurchaseCheck(hasUnboundOrder: true),
      );
      await check;
      expect(h.service.guestOrderChecks, isEmpty);
      expect(h.service.guestLoginRequestId.value, isNull);
      expect(h.claimRequests, isEmpty);
    },
  );
  test(
    'logged-in startup skips checks even with a cached guest UUID',
    () async {
      final h = support.Harness(guestRecoveryEnabled: true);
      await h.store.saveGuestClaim(
        const MembershipGuestClaimRecord(guest: support.guest),
      );
      await h.service.checkGuestPurchasesOnHome();
      expect(h.guestChecks, isEmpty);
      expect(h.guestDiscoveries, 0);
    },
  );
}
