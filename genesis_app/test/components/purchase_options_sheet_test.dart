import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/common/genesis_modal_routes.dart';
import 'package:genesis_flutter_android/components/gems/pro_subscription_content.dart';
import 'package:genesis_flutter_android/components/gems/purchase_options_sheet.dart';
import 'package:genesis_flutter_android/components/gems/wallet_purchase_tabs.dart';
import 'package:genesis_flutter_android/ui/theme/genesis_theme.dart';

void main() {
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
