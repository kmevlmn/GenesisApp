import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/models/membership_claim.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/platform/billing/membership_pending_store.dart';
import 'package:genesis_flutter_android/platform/billing/membership_guest_claim_record.dart';

import 'membership_purchase_service_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Apple guest claim after restart reloads signed proof for the original transaction',
    () async {
      final h = Harness(provider: MembershipProvider.apple, claimEnabled: true)
        ..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      final report = h.reports.single;
      expect(report.toJson()['signed_transaction'], 'test.header.signature');
      expect(h.signedTransactionQueries, 0);
      expect(
        h.store.confirmed.values.single.toJson(),
        isNot(contains('signed_transaction')),
      );
      final restarted = Harness(
        provider: MembershipProvider.apple,
        claimEnabled: true,
        storage: h.store,
      )..uid = 'first-login';
      restarted.signedTransactionHandler = (request) async {
        expect(request.requestId, report.requestId);
        expect(request.transactionId, report.transactionId);
        expect(request.guest!.accountUuid, guest.accountUuid);
        return 'new.header.signature';
      };
      await restarted.service.recover();
      expect(restarted.signedTransactionQueries, 1);
      expect(restarted.claimRequests.single.toJson(), {
        ...report.toJson(),
        'signed_transaction': 'new.header.signature',
      });
      expect(restarted.refreshes, 1);
      expect(restarted.store.claims, isEmpty);
    },
  );

  test(
    'missing Apple signed proof preserves guest cache and never sends UUID-only claim',
    () async {
      final h = Harness(provider: MembershipProvider.apple, claimEnabled: true)
        ..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      final restarted = Harness(
        provider: MembershipProvider.apple,
        claimEnabled: true,
        storage: h.store,
      )..uid = 'first-login';
      restarted.signedTransactionHandler = (_) async => '';
      await restarted.service.recover();
      expect(restarted.claimRequests, isEmpty);
      expect(restarted.store.claims, hasLength(1));
      expect(restarted.store.confirmed, hasLength(1));
      restarted.signedTransactionHandler = (_) async =>
          'fresh.header.signature';
      await restarted.service.recover();
      expect(restarted.claimRequests, hasLength(1));
      expect(restarted.store.claims, isEmpty);
    },
  );

  for (final provider in MembershipProvider.values) {
    test(
      '$provider bound receipt still deduplicates callbacks and supports restore',
      () async {
        final h = Harness(
          provider: provider,
          claimEnabled: true,
          restoreEnabled: true,
        )..uid = null;
        await h.service.purchase(h.product());
        final purchase = h.purchase(uuid: guest.accountUuid);
        await h.service.interceptPurchase(purchase);
        final originalRequestId = h.reports.single.requestId;
        h.uid = 'first-login';
        await h.service.recover();
        expect(h.store.claims, isEmpty);
        await h.service.interceptPurchase(purchase);
        expect(h.reports, hasLength(1));
        expect(h.claimRequests, hasLength(1));
        h.recoverable = [purchase];
        await h.service.restorePurchases(products: [h.product()]);
        expect(h.reports, hasLength(1));
        expect(h.reports.single.requestId, originalRequestId);
        expect(h.store.records, isEmpty);
        expect(h.store.restores, isEmpty);
        expect(h.store.claims, isEmpty);
        expect(h.service.guestLoginRequestId.value, isNull);
      },
    );
  }

  test(
    'a UUID-only paid guest cache requires login but cannot claim without proof',
    () async {
      final storage = PendingStore();
      await storage.saveGuestClaim(
        const MembershipGuestClaimRecord(
          guest: guest,
          purchaseRequestId: 'paid-order',
          purchaseConfirmed: true,
        ),
      );
      final h = Harness(storage: storage, claimEnabled: true)..uid = null;
      await h.service.start();
      expect(h.service.guestLoginRequestId.value, 'paid-order');
      expect(h.claimRequests, isEmpty);
      h.uid = 'first-login';
      h.service.resetForSession();
      await h.service.recover();
      expect(h.claimRequests, isEmpty);
      expect(storage.claims, hasLength(1));
      expect(h.service.guestLoginRequestId.value, isNull);
      final restarted = Harness(storage: storage, claimEnabled: true)
        ..uid = null;
      await restarted.service.start();
      expect(restarted.service.guestLoginRequestId.value, 'paid-order');
      expect(restarted.claimRequests, isEmpty);
    },
  );

  test(
    'startup requires login before an unrelated report retry completes',
    () async {
      final storage = PendingStore();
      await storage.saveGuestClaim(
        const MembershipGuestClaimRecord(
          guest: guest,
          purchaseRequestId: 'paid-order',
          purchaseConfirmed: true,
        ),
      );
      final h = Harness(storage: storage, claimEnabled: true)..uid = null;
      await storage.save(
        MembershipPurchaseRecord(
          requestId: 'retrying-order',
          product: h.product(),
          accountUuid: guest.accountUuid,
          ownerUid: null,
          guest: guest,
          purchaseToken: 'pending-token',
          state: 'purchased',
        ),
      );
      final entered = Completer<void>();
      final response = Completer<MembershipPurchaseReport>();
      h.reportHandler = (_) {
        entered.complete();
        return response.future;
      };
      final recovery = h.service.start();
      await entered.future;
      expect(h.service.guestLoginRequestId.value, 'paid-order');
      expect(storage.claims.values.single.guest.accountUuid, guest.accountUuid);
      response.complete(completed);
      await recovery;
    },
  );

  test(
    'a failed binding followed by logout still requires login after restart',
    () async {
      final h = Harness(claimEnabled: true)..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      h.uid = 'first-login';
      h.claimHandler = (_) async => throw StateError('offline');
      await h.service.recover();
      final restarted = Harness(storage: h.store, claimEnabled: true)
        ..uid = null;
      await restarted.service.start();
      expect(restarted.service.guestLoginRequestId.value, isNotNull);
      expect(restarted.store.claims.values.single.ownerUid, 'first-login');
      restarted.uid = 'first-login';
      await restarted.service.recover();
      expect(restarted.claimRequests, hasLength(1));
      expect(restarted.store.claims, isEmpty);
    },
  );

  test(
    'completed binding cleanup is retried on restart without binding twice',
    () async {
      final h = Harness(claimEnabled: true)..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      h.store.failClaimCleanup = true;
      h.uid = 'first-login';
      await h.service.recover();
      expect(h.store.claims.values.single.status, 'completed');
      expect(h.store.confirmed.values.single.guest, isNotNull);
      h.store.failClaimCleanup = false;
      final restarted = Harness(storage: h.store, claimEnabled: true)
        ..uid = null;
      await restarted.service.start();
      expect(restarted.claimRequests, isEmpty);
      expect(restarted.store.claims, isEmpty);
      expect(restarted.store.confirmed.values.single.guest, isNull);
      expect(restarted.store.confirmed.values.single.ownerUid, 'first-login');
      expect(restarted.service.guestLoginRequestId.value, isNull);
    },
  );

  test(
    'completed claim preserves an unconfirmed guest report until it settles',
    () async {
      final h = Harness(claimEnabled: true)..uid = null;
      h.reportHandler = (_) async => const MembershipPurchaseReport(
        status: MembershipReportStatus.accepted,
        reportId: 'processing-report',
      );
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      final originalRequest = h.reports.single.toJson();
      h.uid = 'first-login';
      await h.service.recover();
      expect(h.store.claims.values.single.status, 'completed');
      expect(
        h.store.records.values.single.guest?.accountUuid,
        guest.accountUuid,
      );
      h.reportHandler = null;
      await h.service.recover();
      expect(h.reports.last.toJson(), originalRequest);
      expect(h.claimRequests, hasLength(1));
      expect(h.store.claims, isEmpty);
      expect(h.store.records, isEmpty);
      expect(h.store.confirmed.values.single.guest, isNull);
    },
  );

  test(
    'rejected binding retains its secret and never transfers to another login',
    () async {
      final h = Harness(claimEnabled: true)..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      h.uid = 'first-login';
      h.claimHandler = (identity) async =>
          MembershipClaimResult(status: MembershipReportStatus.rejected);
      await h.service.recover();
      expect(h.store.claims.values.single.status, 'rejected');
      expect(h.store.claims.values.single.guest.accountUuid, guest.accountUuid);
      h.uid = 'other-login';
      await h.service.recover();
      expect(h.claimRequests, hasLength(1));
      expect(h.store.claims.values.single.ownerUid, 'first-login');
    },
  );

  test(
    'guest pending payment verified on retry still requires success OK then login',
    () async {
      final h = Harness(claimEnabled: true)..uid = null;
      h.reportHandler = (_) async => const MembershipPurchaseReport(
        status: MembershipReportStatus.accepted,
        reportId: 'accepted',
      );
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(
        h.purchase(status: BillingPurchaseStatus.pending),
      );
      expect(h.service.guestLoginRequestId.value, isNull);
      h.reportHandler = null;
      await h.service.recover();
      final requestId = h.store.confirmed.keys.single;
      expect(h.service.guestLoginRequestId.value, requestId);
      expect(h.service.hasAcknowledgedGuestPurchase(requestId), isFalse);
      expect(h.store.claims.values.single.guest.accountUuid, guest.accountUuid);
      expect(h.store.records, isEmpty);
      await h.service.confirmGuestPurchase(requestId);
      expect(h.service.hasAcknowledgedGuestPurchase(requestId), isTrue);
      h.uid = 'first-login';
      await h.service.recover();
      expect(h.claimRequests, hasLength(1));
      expect(h.store.claims, isEmpty);
    },
  );

  test('guest uses prepare UUID and claims only after a real login', () async {
    final h = Harness(claimEnabled: true)..uid = null;
    await h.service.purchase(h.product());
    expect(h.platform.uuid, guest.accountUuid);
    expect(h.store.records.values.single.guest?.accountUuid, guest.accountUuid);
    await h.service.interceptPurchase(h.purchase());
    expect(h.claimRequests, isEmpty);
    expect(h.refreshes, 0);
    expect(h.service.catalogRevision.value, 1);
    expect(h.store.records, isEmpty);
    final requestId = h.store.confirmed.keys.single;
    expect(h.service.guestLoginRequestId.value, requestId);
    await h.service.confirmGuestPurchase(requestId);
    expect(h.store.claims.values.single.loginRequired, isTrue);
    h.uid = 'first-login';
    await h.service.recover();
    expect(h.claimRequests.single.guest!.accountUuid, guest.accountUuid);
    expect(h.store.claims, isEmpty);
    expect(h.store.confirmed.values.single.ownerUid, 'first-login');
    expect(h.store.confirmed.values.single.guest, isNull);
    expect(h.service.guestLoginRequestId.value, isNull);
    expect(h.refreshes, 1);
    expect(h.service.catalogRevision.value, 2);
    await h.service.recover();
    expect(h.claimRequests, hasLength(1));
  });

  test(
    'failed claim keeps first owner through restart and account switches',
    () async {
      final h = Harness(claimEnabled: true)..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      h.uid = 'first-login';
      h.claimHandler = (_) async => throw StateError('offline');
      await h.service.recover();
      expect(h.store.claims.values.single.ownerUid, 'first-login');
      expect(h.store.claims.values.single.status, isNull);
      final restarted = Harness(storage: h.store, claimEnabled: true)
        ..uid = 'other-login';
      await restarted.service.recover();
      expect(restarted.claimRequests, isEmpty);
      restarted.uid = 'first-login';
      await restarted.service.recover();
      expect(
        restarted.claimRequests.single.guest!.accountUuid,
        guest.accountUuid,
      );
      expect(restarted.store.claims, isEmpty);
    },
  );

  test('claim ownership must be durable before sending any claim', () async {
    final h = Harness(claimEnabled: true)..uid = null;
    await h.service.purchase(h.product());
    await h.service.interceptPurchase(h.purchase());
    h.uid = 'first-login';
    h.store.failClaim = true;
    await h.service.recover();
    expect(h.claimRequests, isEmpty);
    h.store.failClaim = false;
    h.uid = 'other-login';
    await h.service.recover();
    expect(h.claimRequests, isEmpty);
    h.uid = 'first-login';
    await h.service.recover();
    expect(h.claimRequests, hasLength(1));
  });

  testWidgets(
    'accepted claim replays original receipt before retry without refinish',
    (tester) async {
      final h = Harness(
        provider: MembershipProvider.apple,
        claimEnabled: true,
        retryDelay: const Duration(seconds: 15),
      )..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      final request = h.reports.single;
      h.uid = 'first-login';
      h.claimHandler = (identity) async =>
          MembershipClaimResult(status: MembershipReportStatus.accepted);
      await h.service.recover();
      expect(h.store.records.values.single.requestId, request.requestId);
      expect(h.store.records.values.single.finished, isTrue);
      h.claimHandler = null;
      await tester.pump(const Duration(seconds: 15));
      await h.service.recover();
      expect(h.reports, hasLength(2));
      expect(h.reports.last.toJson(), request.toJson());
      expect(h.platform.finishes, 1);
      expect(h.store.records, isEmpty);
      expect(h.store.claims, isEmpty);
    },
  );

  test('cancelled purchase never requests a login or claims a guest', () async {
    final h = Harness(claimEnabled: true)..uid = null;
    h.platform.launchResult = false;
    await h.service.purchase(h.product());
    await h.service.recover();
    expect(h.service.guestLoginRequestId.value, isNull);
    expect(h.store.claims, isEmpty);
    expect(h.claimRequests, isEmpty);
  });

  test(
    'failed claim-result write retries persistence without claiming twice',
    () async {
      final h = Harness(claimEnabled: true)..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      h.uid = 'first-login';
      h.claimHandler = (identity) async {
        h.store.failClaim = true;
        return MembershipClaimResult(status: MembershipReportStatus.completed);
      };
      await h.service.recover();
      expect(h.store.claims.values.single.status, isNull);
      h.store.failClaim = false;
      await h.service.recover();
      expect(h.store.claims, isEmpty);
      expect(h.claimRequests, hasLength(1));
      expect(h.refreshes, 1);
    },
  );
}
