import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/gems/gem_purchase_bottom_sheet.dart';
import 'package:genesis_flutter_android/app/gems/gem_wallet_store.dart';
import 'package:genesis_flutter_android/network/models/gem_wallet.dart';
import 'package:genesis_flutter_android/network/chatroom/world_chatroom_service.dart';
import 'package:genesis_flutter_android/platform/billing/billing_service.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/components/common/genesis_modal_routes.dart';
import 'package:genesis_flutter_android/components/gems/pro_subscription_content.dart';
import 'package:genesis_flutter_android/components/gems/purchase_options_sheet.dart';
import 'package:genesis_flutter_android/components/gems/wallet_purchase_tabs.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

import '../support/membership_fixtures.dart';

void main() {
  for (final initialTab in PurchaseSheetTab.values) {
    testWidgets(
      'sheet loads only selected tab $initialTab, including canceled swipes',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var memberships = 0;
        var products = 0;
        var balances = 0;
        final wallet = GemWalletStore(
          readUid: () async => 'u_test',
          loadWallet: () async {
            balances++;
            return const GemWallet(balanceCent: 43000);
          },
        );
        final billing = _SheetBillingService();
        addTearDown(wallet.dispose);
        addTearDown(billing.state.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: GenesisTheme.light(),
            home: Scaffold(
              body: PurchaseOptionsSheet(
                initialTab: initialTab,
                membershipProductsLoader: () {
                  memberships++;
                  return loadTestMembershipOffers();
                },
                gemsBuilder: (_) => GemPurchaseBottomSheet(
                  embedded: true,
                  alert: const GemBalanceAlert(kind: GemBalanceAlertKind.low),
                  productsLoader: () async {
                    products++;
                    return [];
                  },
                  walletStore: wallet,
                  billingService: billing,
                  payTrackPageId: 'test',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final subscriptionFirst = initialTab == PurchaseSheetTab.subscription;
        expect(memberships, subscriptionFirst ? 1 : 0);
        expect(products, subscriptionFirst ? 0 : 1);
        expect(balances, products);
        expect(billing.starts, products);
        final pages = find.byKey(const ValueKey('purchase-sheet-pages'));
        final gesture = await tester.startGesture(tester.getCenter(pages));
        final direction = subscriptionFirst ? -1.0 : 1.0;
        await gesture.moveBy(Offset(direction * 60, 0));
        await tester.pump();
        expect(memberships, subscriptionFirst ? 1 : 0);
        expect(products, subscriptionFirst ? 0 : 1);
        await gesture.moveBy(Offset(-direction * 60, 0));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(memberships, subscriptionFirst ? 1 : 0);
        expect(products, subscriptionFirst ? 0 : 1);
        await tester.drag(pages, Offset(direction * 330, 0));
        await tester.pumpAndSettle();
        expect([memberships, products, balances, billing.starts], [1, 1, 1, 1]);
        for (final key in [
          'wallet-subscription-tab',
          'wallet-buy-gems-tab',
          'wallet-subscription-tab',
        ]) {
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
        }
        expect([memberships, products, balances, billing.starts], [1, 1, 1, 1]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('both purchase tabs dismiss downward only at the list top', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: GenesisTheme.light(),
        scrollBehavior: const GenesisScrollBehavior(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showGenesisModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => FractionallySizedBox(
                  heightFactor: .8,
                  child: PurchaseOptionsSheet(
                    membershipProductsLoader: loadTestMembershipOffers,
                    initialTab: PurchaseSheetTab.subscription,
                    gemsBuilder: (_) => ListView.builder(
                      key: const ValueKey('scrollable-gems'),
                      itemExtent: 60,
                      itemCount: 30,
                      itemBuilder: (_, index) => Text('Gem pack $index'),
                    ),
                  ),
                ),
              ),
              child: const Text('Open purchase'),
            ),
          ),
        ),
      ),
    );
    for (final tab in PurchaseSheetTab.values) {
      await tester.tap(find.text('Open purchase'));
      await tester.pumpAndSettle();
      if (tab == PurchaseSheetTab.buyGems) {
        await tester.drag(
          find.byKey(const ValueKey('purchase-sheet-pages')),
          const Offset(-320, 0),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PurchaseOptionsSheet), findsOneWidget);
      }
      final list = tab == PurchaseSheetTab.subscription
          ? find.byKey(const PageStorageKey('pro-benefits-scroll'))
          : find.byKey(const ValueKey('scrollable-gems'));
      await tester.drag(list, const Offset(0, -180));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      expect(position.pixels, greaterThan(50));
      await tester.drag(list, const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(find.byType(PurchaseOptionsSheet), findsOneWidget);
      position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(find.byType(PurchaseOptionsSheet), findsNothing);
      expect(find.text('Open purchase'), findsOneWidget);
    }
  });

  testWidgets('sheet shares Wallet UI and preserves both tabs while swiping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var gemsBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: GenesisTheme.light(),
        scrollBehavior: const GenesisScrollBehavior(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: .8,
              child: PurchaseOptionsSheet(
                membershipProductsLoader: loadTestMembershipOffers,
                initialTab: PurchaseSheetTab.subscription,
                gemsBuilder: (_) {
                  gemsBuilds++;
                  return const TextField(key: ValueKey('demo-gems-state'));
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WalletPurchaseTabs), findsOneWidget);
    expect(find.byType(ProSubscriptionContent), findsOneWidget);
    expect(gemsBuilds, 0);
    final subscription = tester.getRect(
      find.byKey(const ValueKey('wallet-subscription-tab')),
    );
    final gems = tester.getRect(
      find.byKey(const ValueKey('wallet-buy-gems-tab')),
    );
    expect(subscription.width, closeTo(gems.width, .01));
    expect((subscription.right + gems.left) / 2, closeTo(195, .01));
    await tester.tap(find.byKey(const ValueKey('pro-plan-monthly')));
    await tester.pumpAndSettle();
    final pages = find.byKey(const ValueKey('purchase-sheet-pages'));
    await tester.drag(pages, const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(gemsBuilds, greaterThan(0));
    await tester.enterText(
      find.byKey(const ValueKey('demo-gems-state')),
      'Preserved',
    );
    await tester.tap(find.byKey(const ValueKey('wallet-subscription-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Monthly: \$9.99'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wallet-buy-gems-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Preserved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SheetBillingService implements BillingService {
  int starts = 0;
  @override
  final ValueNotifier<BillingState> state = ValueNotifier<BillingState>(
    BillingState(storeAvailable: true),
  );
  @override
  Stream<BillingUiEvent> get events => const Stream.empty();
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
