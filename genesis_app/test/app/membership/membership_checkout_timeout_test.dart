import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/membership/membership_purchase_service.dart';
import 'package:genesis_flutter_android/network/api_exception.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';

import 'membership_purchase_service_test.dart';

void main() {
  for (final stage in [
    'cache',
    'identity',
    'eligibility',
    'store',
    'guest',
    'uuid',
  ]) {
    for (final failsLate in [false, true]) {
      testWidgets(
        '$stage timeout ignores late ${failsLate ? 'failure' : 'result'}',
        (tester) async {
          final h = Harness();
          final gate = Completer<void>();
          var entered = false;
          Future<void> block() {
            entered = true;
            return gate.future;
          }

          switch (stage) {
            case 'cache':
              h.store.onLoad = block;
            case 'identity':
              h.loginUidHandler = () async {
                await block();
                return h.uid;
              };
            case 'eligibility':
              h.productsHandler = () async {
                await block();
                return [h.product()];
              };
            case 'store':
              h.platform.onPrepare = block;
            case 'guest':
              h.uid = null;
              h.guestHandler = () async {
                await block();
                return guest;
              };
            case 'uuid':
              h.accountUuidHandler = () async {
                await block();
                return accountUuid;
              };
          }
          final events = <MembershipCheckoutEvent>[];
          h.service.checkoutEvents.listen(events.add);
          var returned = false;
          final purchase = h.service
              .purchase(h.product(), attemptId: 'old')
              .then((_) => returned = true);
          await tester.pump();
          expect(entered, isTrue);
          expect(h.service.isBusy, isTrue);
          await tester.pump(const Duration(seconds: 89));
          expect(returned, isFalse);
          await tester.pump(const Duration(seconds: 1));
          expect(returned, isTrue);
          expect(h.service.isBusy, isFalse);
          expect(events.last.state, MembershipCheckoutState.deferred);
          final count = events.length;
          if (failsLate) {
            gate.completeError(StateError('late failure'));
          } else {
            gate.complete();
          }
          await tester.pump();
          await purchase;
          expect(h.platform.launches, 0);
          expect(h.reports, isEmpty);
          expect(
            h.store.claims.values.where((r) => r.status != 'completed'),
            isEmpty,
          );
          expect(events, hasLength(count));
          expect(
            h.store.records.values.where((r) => r.state == 'prepared'),
            isEmpty,
          );
        },
      );
    }
  }

  testWidgets(
    'moving from eligibility to store query does not restart 90 seconds',
    (tester) async {
      final h = Harness();
      final eligibility = Completer<void>();
      final store = Completer<void>();
      h.productsHandler = () async {
        await eligibility.future;
        return [h.product()];
      };
      h.platform.onPrepare = () => store.future;
      var returned = false;
      final purchase = h.service
          .purchase(h.product())
          .then((_) => returned = true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
      eligibility.complete();
      await tester.pump();
      expect(h.platform.product, isNotNull);
      await tester.pump(const Duration(seconds: 30));
      expect(returned, isTrue);
      expect(h.service.isBusy, isFalse);
      store.complete();
      await tester.pump();
      await purchase;
      expect(h.platform.launches, 0);
    },
  );

  testWidgets('old preparation failure cannot release a new checkout', (
    tester,
  ) async {
    final h = Harness();
    final gate = Completer<void>();
    h.platform.onPrepare = () => gate.future;
    final old = h.service.purchase(h.product(), attemptId: 'old');
    await tester.pump();
    await tester.pump(const Duration(seconds: 90));
    await old;
    h.platform.onPrepare = null;
    await h.service.purchase(h.product(), attemptId: 'new');
    gate.completeError(StateError('late preparation failure'));
    await tester.pump();
    expect(h.service.isBusy, isTrue);
    expect(h.service.state.value, MembershipCheckoutState.store);
    expect(h.platform.launches, 1);
    h.service.dispose();
  });

  for (final provider in MembershipProvider.values) {
    for (final outcome in [
      BillingPurchaseStatus.purchased,
      BillingPurchaseStatus.canceled,
      BillingPurchaseStatus.error,
      BillingPurchaseStatus.pending,
    ]) {
      testWidgets(
        '$provider user can remain in store beyond 90 seconds before $outcome',
        (tester) async {
          final h = Harness(provider: provider);
          if (outcome == BillingPurchaseStatus.pending) {
            h.reportHandler = (_) async => const MembershipPurchaseReport(
              status: MembershipReportStatus.accepted,
              reportId: 'pending-test',
            );
          }
          final result = Completer<void>();
          if (provider == MembershipProvider.apple) {
            // StoreKit reports handoff before its launch Future returns a result.
            h.platform.onLaunch = () async {
              expectSync(h.platform.handoff!(), isTrue);
              await result.future;
            };
          }
          final purchase = h.service.purchase(h.product());
          await tester.pump();
          await tester.pump(const Duration(minutes: 3));
          expect(h.service.isBusy, isTrue);
          expect(h.service.state.value, MembershipCheckoutState.store);
          expect(h.reports, isEmpty);
          await h.service.interceptPurchase(h.purchase(status: outcome));
          result.complete();
          await purchase;
          expect(h.service.state.value, switch (outcome) {
            BillingPurchaseStatus.purchased =>
              MembershipCheckoutState.completed,
            BillingPurchaseStatus.canceled => MembershipCheckoutState.canceled,
            BillingPurchaseStatus.error => MembershipCheckoutState.failed,
            _ => MembershipCheckoutState.accepted,
          });
          expect(h.service.isBusy, isFalse);
          h.service.dispose();
        },
      );
    }

    testWidgets(
      '$provider callback stops store timeout while report is pending',
      (tester) async {
        final h = Harness(provider: provider);
        final response = Completer<MembershipPurchaseReport>();
        h.reportHandler = (_) => response.future;
        await h.service.purchase(h.product());
        await tester.pump(const Duration(seconds: 80));
        final callback = h.service.interceptPurchase(h.purchase());
        await tester.pump();
        expect(h.reports, hasLength(1));
        await tester.pump(const Duration(seconds: 20));
        expect(h.service.state.value, MembershipCheckoutState.reporting);
        expect(h.store.records, isEmpty);
        response.complete(completed);
        await callback;
        expect(h.service.state.value, MembershipCheckoutState.completed);
        expect(h.store.records, isEmpty);
        h.service.dispose();
        expect(h.refreshes, 1);
      },
    );

    testWidgets('$provider late paid callback after timeout still reports', (
      tester,
    ) async {
      final h = Harness(provider: provider)..uid = null;
      final launch = Completer<void>();
      h.platform.onLaunch = () => launch.future;
      var returned = false;
      final purchase = h.service
          .purchase(h.product(), attemptId: 'guest-order')
          .then((_) => returned = true);
      await tester.pump();
      expect(h.platform.launches, 1);
      await tester.pump(const Duration(seconds: 90));
      expect(returned, isTrue);
      expect(h.store.records, isEmpty);
      await h.service.interceptPurchase(h.purchase());
      expect(h.store.confirmed.keys.single, 'guest-order');
      expect(h.reports.single.toJson(), isNot(contains('request_id')));
      expect(h.store.confirmed.values.single.guest, guest);
      expect(h.store.claims, hasLength(1));
      // A late launch error cannot overwrite the verified receipt or success.
      launch.completeError(StateError('late launch failure'));
      await tester.pump();
      await purchase;
      expect(h.service.state.value, MembershipCheckoutState.completed);
      expect(h.store.records, isEmpty);
      h.service.dispose();
    });
  }

  testWidgets('completed callback wins over a late launch rejection', (
    tester,
  ) async {
    final h = Harness();
    final launch = Completer<void>();
    h.platform.onLaunch = () => launch.future;
    h.platform.launchResult = false;
    final purchase = h.service.purchase(h.product());
    await tester.pump();
    await h.service.interceptPurchase(h.purchase());
    await tester.pump(const Duration(seconds: 91));
    launch.complete();
    await tester.pump();
    await purchase;
    expect(h.service.state.value, MembershipCheckoutState.completed);
    expect(h.reports, hasLength(1));
  });

  testWidgets(
    'report HTTP timeout retains receipt and retries the same request',
    (tester) async {
      final h = Harness(retryDelay: const Duration(seconds: 15));
      final response = Completer<MembershipPurchaseReport>();
      h.reportHandler = (_) => response.future;
      await h.service.purchase(h.product());
      await tester.pump(const Duration(seconds: 89));
      final callback = h.service.interceptPurchase(h.purchase());
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      expect(h.service.state.value, MembershipCheckoutState.reporting);
      response.completeError(
        ApiException(
          message: 'request timed out',
          kind: ApiExceptionKind.timeout,
        ),
      );
      await callback;
      expect(h.service.state.value, MembershipCheckoutState.deferred);
      expect(h.store.records.values.single.hasReceipt, isTrue);
      h.reportHandler = null;
      await tester.pump(const Duration(seconds: 15));
      expect(h.reports, hasLength(2));
      expect(h.reports.first.toJson(), h.reports.last.toJson());
      expect(h.store.records, isEmpty);
    },
  );

  testWidgets('another order callback cannot cancel current store deadline', (
    tester,
  ) async {
    final h = Harness();
    await h.service.purchase(h.product());
    await h.service.interceptPurchase(h.purchase());
    h.platform.autoHandoff = false;
    await h.service.purchase(h.product(yearly: true), attemptId: 'new');
    await h.service.interceptPurchase(h.purchase(transaction: 'renewal'));
    await tester.pump(const Duration(seconds: 90));
    expect(h.service.isBusy, isFalse);
    expect(h.service.state.value, MembershipCheckoutState.deferred);
    h.service.dispose();
  });

  for (final action in ['session', 'stream']) {
    testWidgets('$action still ends the wait during reporting', (tester) async {
      final h = Harness();
      final response = Completer<MembershipPurchaseReport>();
      h.reportHandler = (_) => response.future;
      final events = <MembershipCheckoutEvent>[];
      h.service.checkoutEvents.listen(events.add);
      await h.service.purchase(h.product(), attemptId: 'reporting-order');
      final callback = h.service.interceptPurchase(h.purchase());
      await tester.pump();
      if (action == 'session') {
        h.uid = 'other-user';
        h.service.resetForSession();
      } else {
        h.service.handleStreamError();
      }
      await tester.pump();
      expect(events.last.attemptId, 'reporting-order');
      expect(
        events.last.state,
        action == 'session'
            ? MembershipCheckoutState.idle
            : MembershipCheckoutState.deferred,
      );
      response.complete(completed);
      await callback;
      await tester.pump();
      h.service.dispose();
    });
  }
}
