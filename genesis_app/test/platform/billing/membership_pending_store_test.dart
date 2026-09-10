import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/platform/billing/membership_pending_store.dart';
import 'package:genesis_flutter_android/platform/billing/membership_restore_record.dart';
import 'package:genesis_flutter_android/platform/billing/membership_guest_claim_record.dart';
import 'package:genesis_flutter_android/platform/billing/membership_guest_claim_proof.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/app/membership/membership_purchase_service.dart';
import '../../app/membership/membership_purchase_service_test.dart' as support;
import '../../support/membership_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final provider in MembershipProvider.values) {
    test(
      '$provider legacy claim proof drops stored plan without losing credentials',
      () async {
        final proof = MembershipGuestClaimProof.fromJson({
          'provider': provider.name,
          'store_product_id': 'original-store-product',
          'request_id': 'original-request',
          'purchase_token': 'original-token',
          'transaction_id': 'original-transaction',
          'plan_code': 'pro_yearly',
        });
        FlutterSecureStorage.setMockInitialValues({});
        final store = SecureMembershipPendingStore();
        await store.saveGuestClaim(
          MembershipGuestClaimRecord(
            guest: support.guest,
            ownerUid: 'first-login',
            status: 'accepted',
            recoveredProof: proof,
          ),
        );
        final saved =
            (await SecureMembershipPendingStore().loadGuestClaims()).single;
        expect(saved.recoveredProof!.toJson(), {
          'provider': provider.name,
          'store_product_id': 'original-store-product',
          'request_id': 'original-request',
          if (provider == MembershipProvider.google)
            'purchase_token': 'original-token',
          if (provider == MembershipProvider.apple)
            'transaction_id': 'original-transaction',
        });
        expect(saved.ownerUid, 'first-login');
        expect(saved.status, 'accepted');
      },
    );
    test(
      '$provider reinstall claim proof survives restart and is removed after binding',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        final store = SecureMembershipPendingStore();
        final claim = MembershipGuestClaimRecord(
          guest: support.guest,
          loginRequired: true,
          recoveredProof: MembershipGuestClaimProof(
            provider: provider,
            storeProductId: 'store-subscription',
            requestId: 'stable-claim-attempt',
            purchaseToken: 'google-proof',
            transactionId: 'apple-transaction',
          ),
        );
        await store.saveGuestClaim(claim);
        final restarted = SecureMembershipPendingStore();
        final restored = (await restarted.loadGuestClaims()).single;
        expect(restored.recoveredProof!.requestId, 'stable-claim-attempt');
        expect(restored.recoveredProof!.provider, provider);
        expect(restored.recoveredProof!.toJson(), isNot(contains('plan_code')));
        expect(restored.guest.accountUuid, support.guest.accountUuid);
        expect(await restarted.loadAll(), isEmpty);
        expect(await restarted.loadRestores(), isEmpty);
        expect(await restarted.loadConfirmedReceipts(), isEmpty);
        final saved = restored.copyWith(
          ownerUid: 'first-login',
          status: 'accepted',
        );
        await restarted.saveGuestClaim(saved);
        final retry =
            (await SecureMembershipPendingStore().loadGuestClaims()).single;
        expect(retry.ownerUid, 'first-login');
        expect(retry.recoveredProof!.toJson(), saved.recoveredProof!.toJson());
        final completed = retry.copyWith(status: 'completed');
        await restarted.saveGuestClaim(completed);
        await restarted.completeGuestClaim(completed);
        final bound =
            (await SecureMembershipPendingStore().loadGuestClaims()).single;
        expect(bound.guest.accountUuid, support.guest.accountUuid);
        expect(bound.ownerUid, 'first-login');
        expect(bound.recoveredProof, isNull);
        expect(bound.needsRetry, isFalse);
      },
    );
  }

  test(
    'legacy guest credentials migrate without losing receipt or binding progress',
    () async {
      final purchase = MembershipPurchaseRecord(
        requestId: 'legacy-request',
        product: membershipProduct(),
        accountUuid: support.guest.accountUuid,
        ownerUid: null,
        guest: support.guest,
        purchaseToken: 'saved-paid-receipt',
        state: 'purchased',
        reportStatus: 'completed',
        reportId: 'saved-report',
        finished: true,
      );
      final claim = MembershipGuestClaimRecord(
        guest: support.guest,
        ownerUid: 'first-login',
        status: 'accepted',
        purchaseConfirmed: true,
        loginRequired: true,
        purchaseRequestId: purchase.requestId,
      );
      final oldGuest = {
        ...support.guest.toJson(),
        'guest_id': 'legacy-guest',
        'claim_token': 'legacy-secret',
      };
      final keys = {
        'membership_purchase_records_v1': [
          {...purchase.toJson(), 'guest': oldGuest},
        ],
        'membership_confirmed_receipts_v1': [
          {...purchase.toJson(), 'guest': oldGuest},
        ],
        'membership_guest_claims_v1': [
          {...claim.toJson(), 'guest': oldGuest},
        ],
      };
      FlutterSecureStorage.setMockInitialValues({
        for (final entry in keys.entries) entry.key: jsonEncode(entry.value),
      });
      final store = SecureMembershipPendingStore();
      final restored = (await store.loadGuestClaims()).single;
      expect(restored.toJson(), claim.toJson());
      expect((await store.loadAll()).single.toJson(), purchase.toJson());
      expect(
        (await store.loadConfirmedReceipts()).single.toJson(),
        purchase.toJson(),
      );
      for (final key in keys.keys) {
        final saved = (await const FlutterSecureStorage().read(key: key))!;
        expect(saved, isNot(contains('guest_id')));
        expect(saved, isNot(contains('claim_token')));
        expect(saved, isNot(contains('signed_transaction')));
      }
    },
  );

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
        'store_product_id': 'test_pro',
        'purchase_token': 'stored-token',
      });
    },
  );

  test(
    'binding keeps UUID and removes purchase proof, including repeated cleanup',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureMembershipPendingStore();
      const claim = MembershipGuestClaimRecord(
        guest: support.guest,
        ownerUid: 'first-login',
        status: 'completed',
        purchaseRequestId: 'guest-order',
        purchaseConfirmed: true,
      );
      await store.complete(
        MembershipPurchaseRecord(
          requestId: 'guest-order',
          product: membershipProduct(),
          accountUuid: support.guest.accountUuid,
          ownerUid: null,
          guest: support.guest,
          purchaseToken: 'guest-receipt',
          state: 'purchased',
          reportStatus: 'completed',
        ),
      );
      await store.saveGuestClaim(claim);
      await store.completeGuestClaim(claim);
      final restarted = SecureMembershipPendingStore();
      final cached = (await restarted.loadGuestClaims()).single;
      expect(cached.guest.accountUuid, support.guest.accountUuid);
      expect(cached.status, 'completed');
      expect(cached.needsRetry, isFalse);
      expect(cached.purchaseRequestId, isNull);
      expect(cached.autoClaimAllowed, isFalse);
      expect(await restarted.loadConfirmedReceipts(), isEmpty);
      expect(await restarted.loadAll(), isEmpty);
      await restarted.completeGuestClaim(claim);
      expect(await restarted.loadGuestClaims(), hasLength(1));
    },
  );

  test('successful logged-in order is deleted rather than archived', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureMembershipPendingStore();
    final record = MembershipPurchaseRecord(
      requestId: 'report-retry',
      product: membershipProduct(),
      accountUuid: support.accountUuid,
      ownerUid: 'user-test',
      purchaseToken: 'receipt',
      state: 'purchased',
    );
    await store.save(record);
    await store.complete(record.copyWith(reportStatus: 'completed'));
    expect(await SecureMembershipPendingStore().loadAll(), isEmpty);
    expect(
      await SecureMembershipPendingStore().loadConfirmedReceipts(),
      isEmpty,
    );
  });

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
        guest: MembershipGuestIdentity(accountUuid: support.accountUuid),
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
        (await store.loadGuestClaims())
            .where((record) => record.status != 'completed')
            .single
            .guest
            .accountUuid,
        other.guest.accountUuid,
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
      expect(claimed.guest.accountUuid, support.guest.accountUuid);
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
      expect(pending, isEmpty);
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
      expect(await store.loadConfirmedReceipts(), isEmpty);
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
      expect(saved.guest?.accountUuid, support.guest.accountUuid);
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
