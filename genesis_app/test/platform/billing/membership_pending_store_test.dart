import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/platform/billing/membership_pending_store.dart';
import 'package:genesis_flutter_android/platform/billing/membership_restore_record.dart';
import 'package:genesis_flutter_android/platform/billing/membership_guest_claim_record.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/app/membership/membership_purchase_service.dart';
import '../../app/membership/membership_purchase_service_test.dart' as support;
import '../../support/membership_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'known-plan receipt without base plan survives restart and can be reported',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureMembershipPendingStore();
      await store.save(
        const MembershipPurchaseRecord(
          requestId: 'no-base-plan',
          product: MembershipOrderProduct(
            provider: MembershipProvider.google,
            planCode: 'pro_monthly',
            storeProductId: 'test_pro',
          ),
          accountUuid: support.accountUuid,
          ownerUid: 'user-test',
          purchaseToken: 'stored-token',
          state: 'purchased',
        ),
      );
      final saved = (await SecureMembershipPendingStore().loadAll()).single;
      expect(saved.product.basePlanId, isEmpty);
      expect(saved.request.toJson(), {
        'provider': 'google',
        'plan_code': 'pro_monthly',
        'store_product_id': 'test_pro',
        'request_id': 'no-base-plan',
        'purchase_token': 'stored-token',
      });
    },
  );

  for (final interruptedAfter in [0, 1, 2]) {
    test(
      'completed claim resumes cleanup after $interruptedAfter receipt writes',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        final store = SecureMembershipPendingStore();
        const claim = MembershipGuestClaimRecord(
          guest: support.guest,
          purchaseRequestId: 'confirmed-order',
          purchaseConfirmed: true,
          ownerUid: 'first-login',
          status: 'completed',
        );
        final confirmed = MembershipPurchaseRecord(
          requestId: 'confirmed-order',
          product: membershipProduct(),
          accountUuid: support.guest.accountUuid,
          ownerUid: null,
          guest: support.guest,
          purchaseToken: 'confirmed-token',
          transactionId: '100',
          state: 'purchased',
          reportStatus: 'completed',
          reportId: 'report-test',
        );
        final pendingFinish = confirmed.copyWith(requestId: 'pending-finish');
        await store.complete(confirmed);
        await store.save(pendingFinish);
        await store.saveGuestClaim(claim);
        // Recreate the on-disk state after each write boundary of cleanup.
        if (interruptedAfter >= 1) {
          await store.complete(confirmed.bindGuestToAccount('first-login'));
        }
        if (interruptedAfter >= 2) {
          await store.save(pendingFinish.bindGuestToAccount('first-login'));
        }
        final restarted = SecureMembershipPendingStore();
        await restarted.completeGuestClaim(
          (await restarted.loadGuestClaims()).single,
        );
        expect(await restarted.loadGuestClaims(), isEmpty);
        expect(
          await const FlutterSecureStorage().read(
            key: 'membership_guest_claims_v1',
          ),
          isNull,
        );
        final receipts = [
          ...(await restarted.loadAll()),
          ...(await restarted.loadConfirmedReceipts()),
        ];
        expect(receipts, hasLength(2));
        for (final receipt in receipts) {
          expect(receipt.ownerUid, 'first-login');
          expect(receipt.guest, isNull);
          expect(receipt.accountUuid, support.guest.accountUuid);
          expect(receipt.purchaseToken, 'confirmed-token');
          expect(receipt.product.basePlanId, confirmed.product.basePlanId);
          expect(jsonEncode(receipt.toJson()), isNot(contains('claim_token')));
        }
        // Cleanup is safe to replay even after the final delete succeeded.
        await restarted.completeGuestClaim(claim);
        expect(await restarted.loadGuestClaims(), isEmpty);
      },
    );
  }

  test(
    'cleanup preserves other guests and rejects unconfirmed binding',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureMembershipPendingStore();
      const claim = MembershipGuestClaimRecord(
        guest: support.guest,
        ownerUid: 'first-login',
        status: 'accepted',
        purchaseConfirmed: true,
      );
      const other = MembershipGuestClaimRecord(
        guest: MembershipGuestIdentity(
          guestId: 'another-guest',
          accountUuid: support.accountUuid,
          claimToken: '1234567890123456789012345678901234567890123',
        ),
        purchaseConfirmed: true,
      );
      await store.saveGuestClaim(claim);
      await store.saveGuestClaim(other);
      await expectLater(store.completeGuestClaim(claim), throwsStateError);
      expect(await store.loadGuestClaims(), hasLength(2));
      final completedClaim = claim.copyWith(status: 'completed');
      await expectLater(
        store.completeGuestClaim(completedClaim),
        throwsStateError,
      );
      await store.saveGuestClaim(completedClaim);
      await store.completeGuestClaim(completedClaim);
      expect(
        (await store.loadGuestClaims()).single.guest.guestId,
        other.guest.guestId,
      );
    },
  );
  test(
    'guest login acknowledgement and owner survive store recreation',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureMembershipPendingStore();
      await store.saveGuestClaim(
        const MembershipGuestClaimRecord(
          guest: support.guest,
          loginRequired: true,
          purchaseRequestId: 'paid-order',
          purchaseConfirmed: true,
        ),
      );
      final first =
          (await SecureMembershipPendingStore().loadGuestClaims()).single;
      expect(first.loginRequired, isTrue);
      expect(first.purchaseRequestId, 'paid-order');
      expect(first.purchaseConfirmed, isTrue);
      expect(first.ownerUid, isNull);
      await store.saveGuestClaim(
        first.copyWith(ownerUid: 'first-login', status: 'accepted'),
      );
      final claimed =
          (await SecureMembershipPendingStore().loadGuestClaims()).single;
      expect(claimed.guest.claimToken, support.guest.claimToken);
      expect(claimed.ownerUid, 'first-login');
      expect(claimed.needsRetry, isTrue);
      expect(await store.loadAll(), isEmpty);
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'old local order without catalog fields no longer blocks checkout',
    () async {
      final old = legacyOrder();
      expect(
        () => MembershipProduct.fromJson(
          Map<String, dynamic>.from(old['product'] as Map),
        ),
        throwsFormatException,
      );
      FlutterSecureStorage.setMockInitialValues({
        'membership_purchase_records_v1': jsonEncode([old]),
      });
      final store = SecureMembershipPendingStore();
      final platform = support.Checkout();
      final service = MembershipPurchaseService(
        platform: platform,
        store: store,
        provider: MembershipProvider.google,
        readLoginUid: () async => 'user-test',
        loadProducts: () async => [membershipProduct(yearly: true)],
        loadAccountUuid: () async => support.accountUuid,
        prepareGuest: () async => support.guest,
        reportPurchase: (_) async => support.completed,
        queryPurchases: () async => [],
      );
      addTearDown(service.dispose);
      await service.recover();
      await service.purchase(membershipProduct(yearly: true));
      expect(platform.launches, 1);
      expect(platform.product?.basePlanId, 'test-annual');
      final pending = await store.loadAll();
      expect(pending, hasLength(1));
      expect(pending.first.accountUuid, support.accountUuid);
      for (final row in pending) {
        expect(
          (row.toJson()['product'] as Map).keys,
          isNot(anyOf(contains('title'), contains('benefits'))),
        );
        expect(
          (row.toJson()['product'] as Map).keys,
          isNot(contains('price_amount')),
        );
        expect(
          (row.toJson()['product'] as Map).keys,
          isNot(contains('can_purchase')),
        );
      }
      await service.recover();
      expect(
        (await store.loadAll()).map((r) => r.requestId),
        isNot(contains('old-order')),
      );
      expect(
        (await store.loadConfirmedReceipts()).single.purchaseToken,
        'old-token',
      );
    },
  );

  test('old restore product without display fields stays readable', () async {
    final record = MembershipRestoreRecord(
      requestId: 'old-restore',
      ownerUid: 'user-test',
      purchase: support.Harness().purchase(),
      product: membershipProduct(),
    ).toJson();
    record['product'] = legacyOrder()['product'];
    FlutterSecureStorage.setMockInitialValues({
      'membership_restore_records_v1': jsonEncode([record]),
    });
    final restored =
        (await SecureMembershipPendingStore().loadRestores()).single;
    expect(restored.requestId, 'old-restore');
    expect(restored.request.product.basePlanId, 'test-month');
    expect(restored.request.purchaseToken, 'test-token');
  });

  test(
    'completion removes only pending order and preserves guest restore identity',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureMembershipPendingStore();
      final record = MembershipPurchaseRecord(
        requestId: 'guest-order',
        product: membershipProduct(yearly: true),
        accountUuid: support.guest.accountUuid,
        ownerUid: null,
        guest: support.guest,
        purchaseToken: 'guest-token',
        transactionId: '100',
        state: 'purchased',
        reportStatus: 'completed',
        reportId: 'report-test',
      );
      await store.save(record);
      await Future.wait([
        store.complete(record),
        store.save(
          record.copyWith(requestId: 'still-pending', newReport: true),
        ),
      ]);
      final restarted = SecureMembershipPendingStore();
      expect((await restarted.loadAll()).map((r) => r.requestId), [
        'still-pending',
      ]);
      final saved = (await restarted.loadConfirmedReceipts()).single;
      expect(saved.product.basePlanId, 'test-annual');
      expect(saved.guest?.claimToken, support.guest.claimToken);
      expect(saved.requestId, record.requestId);
      expect(saved.purchaseToken, record.purchaseToken);
      expect((saved.toJson()['product'] as Map).keys.toSet(), {
        'provider',
        'plan_code',
        'store_product_id',
        'base_plan_id',
      });
    },
  );
  test(
    'unresolved restore receipts survive secure-store recreation independently of purchases',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureMembershipPendingStore();
      await store.saveRestore(
        const MembershipRestoreRecord(
          requestId: 'restore-1',
          ownerUid: 'user-test',
          purchase: BillingPurchase(
            provider: BillingProvider.googlePlay,
            productId: 'pro',
            purchaseToken: 'restore-token',
            transactionId: '100',
            originalTransactionId: '',
            originalJson: '',
            purchaseTime: '',
            status: BillingPurchaseStatus.restored,
          ),
        ),
      );
      final recreated = SecureMembershipPendingStore();
      expect(await recreated.loadAll(), isEmpty);
      final record = (await recreated.loadRestores()).single;
      expect(record.requestId, 'restore-1');
      expect(record.product, isNull);
      expect(record.purchase.purchaseToken, 'restore-token');
    },
  );
  test(
    'secure store survives recreation and serializes concurrent receipt updates',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureMembershipPendingStore();
      MembershipPurchaseRecord record(String id) => MembershipPurchaseRecord(
        requestId: id,
        product: membershipProduct(),
        accountUuid: '4b74ec68-7abc-4cce-a223-e997e31dc811',
        ownerUid: 'user-test',
        purchaseToken: 'token-$id',
        state: 'purchased',
      );
      await Future.wait([
        store.save(record('first')),
        store.save(record('second')),
      ]);
      await store.save(
        record(
          'first',
        ).copyWith(reportStatus: 'accepted', reportId: 'report-test'),
      );
      final restored = await SecureMembershipPendingStore().loadAll();
      expect(restored, hasLength(2));
      expect(restored.first.request.purchaseToken, 'token-first');
      expect(restored.first.reportStatus, 'accepted');
      expect(
        restored.first.product.toOrderJson(),
        record('first').product.toOrderJson(),
      );
      expect(restored.last.requestId, 'second');
    },
  );
}

Map<String, Object?> legacyOrder() {
  final record = MembershipPurchaseRecord(
    requestId: 'old-order',
    product: membershipProduct(),
    accountUuid: support.accountUuid,
    ownerUid: 'user-test',
    purchaseToken: 'old-token',
    transactionId: 'old-transaction',
    state: 'purchased',
  ).toJson();
  record['product'] = {
    ...membershipProduct().toOrderJson(),
    'billing_months': 1,
    'monthly_gems_cent': 30000,
    'config_version': 'old-config',
    'sale_enabled': true,
  };
  return record;
}
