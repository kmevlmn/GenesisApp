import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/network/models/membership_claim.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';

import 'membership_purchase_service_test.dart';

void main() {
  for (final response in ['failure', 'accepted']) {
    testWidgets(
      '$response claim retries five times without recovery bypassing backoff',
      (tester) async {
        final h = Harness(
          claimEnabled: true,
          retryDelay: const Duration(seconds: 15),
        )..uid = null;
        await h.service.purchase(h.product());
        await h.service.interceptPurchase(h.purchase());
        h.uid = 'first-login';
        h.claimHandler = (_) async {
          if (response == 'failure') throw StateError('offline');
          return const MembershipClaimResult(
            status: MembershipReportStatus.accepted,
          );
        };
        await h.service.recover();
        expect(h.claimRequests, hasLength(1));
        var calls = 1;
        for (final seconds in [15, 30, 60, 120, 240]) {
          await h.service.recover();
          h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
          await h.service.recover();
          expect(h.claimRequests, hasLength(calls));
          await tester.pump(Duration(milliseconds: seconds * 1000 - 1));
          expect(h.claimRequests, hasLength(calls));
          await tester.pump(const Duration(milliseconds: 1));
          await h.service.recover();
          expect(h.claimRequests, hasLength(++calls));
        }
        await tester.pump(const Duration(days: 1));
        h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await h.service.recover();
        expect(h.claimRequests, hasLength(6));
        for (final request in h.claimRequests) {
          expect(request.toJson(), h.reports.first.toJson());
        }
        expect(
          h.store.claims.values.single.guest.accountUuid,
          guest.accountUuid,
        );
        expect(h.store.claims.values.single.ownerUid, 'first-login');
        expect(h.platform.launches, 1);
        expect(h.refreshes, 0);
        // An explicit new login starts a new bounded round using the same owner.
        h.claimHandler = null;
        h.service.resetForSession();
        await h.service.recover();
        expect(h.claimRequests, hasLength(7));
        expect(h.store.claims, isEmpty);
        expect(h.refreshes, 1);
      },
    );
  }

  testWidgets('successful retry cancels the remaining binding attempts', (
    tester,
  ) async {
    final h = Harness(
      claimEnabled: true,
      retryDelay: const Duration(seconds: 15),
    )..uid = null;
    await h.service.purchase(h.product());
    await h.service.interceptPurchase(h.purchase());
    h.uid = 'first-login';
    h.claimHandler = (_) async => throw StateError('offline');
    await h.service.recover();
    h.claimHandler = null;
    await tester.pump(const Duration(seconds: 15));
    await h.service.recover();
    expect(h.claimRequests, hasLength(2));
    expect(h.store.claims, isEmpty);
    await tester.pump(const Duration(days: 1));
    await h.service.recover();
    expect(h.claimRequests, hasLength(2));
  });

  testWidgets(
    'logout during a binding request never retries as another owner',
    (tester) async {
      final h = Harness(
        claimEnabled: true,
        retryDelay: const Duration(seconds: 15),
      )..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      h.uid = 'first-login';
      final entered = Completer<void>();
      final response = Completer<MembershipClaimResult>();
      h.claimHandler = (_) {
        entered.complete();
        return response.future;
      };
      final recovery = h.service.recover();
      await entered.future;
      h.uid = 'second-login';
      h.service.resetForSession();
      response.completeError(StateError('offline'));
      await recovery;
      await tester.pump();
      await h.service.recover();
      await tester.pump(const Duration(minutes: 10));
      expect(h.claimRequests, hasLength(1));
      expect(h.store.claims.values.single.ownerUid, 'first-login');
      expect(h.refreshes, 0);
      h.uid = 'first-login';
      h.claimHandler = null;
      h.service.resetForSession();
      await h.service.recover();
      expect(h.claimRequests, hasLength(2));
      expect(h.store.claims, isEmpty);
    },
  );

  test(
    'wallet refresh failure keeps completed binding without another claim',
    () async {
      final h = Harness(claimEnabled: true)..uid = null;
      await h.service.purchase(h.product());
      await h.service.interceptPurchase(h.purchase());
      h.uid = 'first-login';
      h.walletRefreshHandler = () async => throw StateError('wallet offline');
      await h.service.recover();
      expect(h.claimRequests, hasLength(1));
      expect(h.store.claims.values.single.status, 'completed');
      expect(h.store.confirmed.values.single.guest, isNotNull);
      h.walletRefreshHandler = null;
      await h.service.recover();
      expect(h.claimRequests, hasLength(1));
      expect(h.refreshes, 2);
      expect(h.store.claims, isEmpty);
    },
  );
}
