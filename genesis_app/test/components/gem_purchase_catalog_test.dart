import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/ui/components/genesis_primary_button.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/components/gems/gem_purchase_catalog.dart';
import 'package:genesis_flutter_android/network/models/gem_product.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';

void main() {
  testWidgets('price and card each buy once, and loading blocks both', (
    tester,
  ) async {
    var purchases = 0;
    Future<void> showCard({required bool buying}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 105,
            height: kGemProductCardHeight,
            child: GemProductCard(
              product: _product(),
              isBuying: buying,
              isPurchaseInProgress: buying,
              onPurchase: () => purchases++,
            ),
          ),
        ),
      ),
    );
    final price = find.byKey(const ValueKey('gem-product-price-gem_pack_500'));
    final card = find.byKey(const ValueKey('gem-product-gem_pack_500'));
    await showCard(buying: false);
    await tester.tap(price);
    expect(purchases, 1);
    await tester.tap(card);
    expect(purchases, 2);
    await showCard(buying: true);
    await tester.tap(price);
    await tester.tap(card);
    expect(purchases, 2);
    final button = tester.widget<FilledButton>(
      find.descendant(of: price, matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNull);
    expect(
      button.style?.backgroundColor?.resolve({WidgetState.disabled}),
      GenesisColors.redPrimary,
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color,
      GenesisColors.darkTextPrimary,
    );
  });

  testWidgets('new user product card uses backend activity label and color', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 105,
            height: kGemProductCardHeight,
            child: GemProductCard(
              product: _product(
                activityType: 'Backend New User',
                activityText: 'Backend New User',
                activityColor: '#123456',
                priceCurrencyCode: 'HKD',
              ),
              isBuying: false,
              isPurchaseInProgress: false,
              onPurchase: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Backend New User'), findsOneWidget);
    expect(find.text('HKD1.49'), findsOneWidget);
    expect(find.text('+550'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);

    final tagStyle = tester.widget<Text>(find.text('Backend New User')).style;
    expect(tagStyle?.fontSize, 10);
    expect(tagStyle?.height, 14 / 10);
    expect(tagStyle?.fontWeight, FontWeight.w400);
    final tagContainer = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('Backend New User'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (tagContainer.decoration as BoxDecoration).color,
      const Color(0xFF123456),
    );

    final amountStyle = tester.widget<Text>(find.text('+550')).style;
    expect(amountStyle?.fontSize, 14);
    expect(amountStyle?.height, 20 / 14);
    expect(amountStyle?.fontWeight, FontWeight.w600);
    expect(amountStyle?.color, GenesisColors.darkTextPrimary);

    final originalAmount = find.text('500');
    final originalAmountStyle = tester.widget<Text>(originalAmount).style;
    expect(originalAmountStyle?.fontSize, 12);
    expect(originalAmountStyle?.fontWeight, FontWeight.w400);
    expect(originalAmountStyle?.color, GenesisColors.darkTextTertiary);
    expect(originalAmountStyle?.decoration, TextDecoration.lineThrough);

    final currentAmountRect = tester.getRect(find.text('+550'));
    final originalAmountRect = tester.getRect(originalAmount);
    final priceButtonRect = tester.getRect(
      find.byKey(const ValueKey('gem-product-price-gem_pack_500')),
    );
    expect(
      priceButtonRect.top - originalAmountRect.bottom,
      closeTo(originalAmountRect.top - currentAmountRect.bottom + 4, 0.1),
    );

    final price = find.byKey(const ValueKey('gem-product-price-gem_pack_500'));
    expect(tester.widget(price), isA<GenesisPrimaryButton>());
    final priceStyle = tester
        .widget<FilledButton>(
          find.descendant(of: price, matching: find.byType(FilledButton)),
        )
        .style!;
    expect(priceStyle.textStyle?.resolve({})?.fontSize, 14);
    expect(priceStyle.textStyle?.resolve({})?.fontWeight, FontWeight.w600);
    expect(
      priceStyle.foregroundColor?.resolve({}),
      GenesisColors.darkTextPrimary,
    );
    expect(priceStyle.backgroundColor?.resolve({}), GenesisColors.redPrimary);
    final productIconSize = tester.getSize(
      find.byKey(const ValueKey<String>('gem-product-icon-gem_pack_500')),
    );
    expect(productIconSize.width, closeTo(44 * 308 / 252, 0.1));
    expect(productIconSize.height, 44);
  });

  testWidgets('balance panel uses the Gem Wallet typography', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GemBalancePanel(balanceCent: 43000)),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('gem-balance-panel'))).height,
      95,
    );
    final labelStyle = tester.widget<Text>(find.text('My Balance')).style;
    expect(labelStyle?.fontSize, 14);
    expect(labelStyle?.height, 18 / 14);
    expect(labelStyle?.fontWeight, FontWeight.w600);
    expect(labelStyle?.color, GenesisColors.darkTextSecondary);

    final balanceStyle = tester.widget<Text>(find.text('430.0')).style;
    expect(balanceStyle?.fontSize, 30);
    expect(balanceStyle?.height, 40 / 30);
    expect(balanceStyle?.fontWeight, FontWeight.w600);
    expect(balanceStyle?.color, GenesisColors.darkTextPrimary);
    final balanceIconSize = tester.getSize(
      find.byKey(const ValueKey('gem-balance-icon')),
    );
    expect(balanceIconSize.width, closeTo(31 * 164 / 256, 0.1));
    expect(balanceIconSize.height, 31);
    final panelRect = tester.getRect(
      find.byKey(const ValueKey('gem-balance-panel')),
    );
    final topGap =
        tester.getRect(find.byKey(const ValueKey('gem-balance-icon'))).top -
        panelRect.top;
    final bottomGap =
        panelRect.bottom - tester.getRect(find.text('430.0')).bottom;
    expect(topGap, closeTo(8, 0.1));
    expect(bottomGap, closeTo(8, 0.1));
  });

  testWidgets('other products use backend activity label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 105,
            height: kGemProductCardHeight,
            child: GemProductCard(
              product: _product(
                productId: 'gem_pack_1100',
                activityType: 'Backend Top-up',
                activityText: 'Backend Top-up',
                activityColor: '#654321',
              ),
              isBuying: false,
              isPurchaseInProgress: false,
              onPurchase: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Backend Top-up'), findsOneWidget);
    final tagContainer = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('Backend Top-up'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (tagContainer.decoration as BoxDecoration).color,
      const Color(0xFF654321),
    );
  });

  testWidgets('sold out new user product keeps its card styling', (
    tester,
  ) async {
    var purchaseCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 105,
            height: kGemProductCardHeight,
            child: GemProductCard(
              product: _product(canPurchase: false),
              isBuying: false,
              isPurchaseInProgress: false,
              onPurchase: () => purchaseCalls += 1,
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('gem-product-gem_pack_500')),
    );
    await tester.pump();

    expect(purchaseCalls, 0);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    expect(find.byType(ColorFiltered), findsNothing);
    expect(find.text('Sold Out'), findsOneWidget);
    expect(find.text(r'$1.49'), findsNothing);
    final soldOutButton = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('gem-product-price-gem_pack_500')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(soldOutButton.onPressed, isNull);
    expect(
      soldOutButton.style?.backgroundColor?.resolve({WidgetState.disabled}),
      Colors.transparent,
    );
    expect(
      soldOutButton.style?.foregroundColor?.resolve({WidgetState.disabled}),
      GenesisColors.darkTextTertiary,
    );
    expect(
      soldOutButton.style?.side?.resolve({WidgetState.disabled})?.color,
      GenesisColors.darkFaintFill,
    );
  });

  testWidgets('product without bonus keeps price bottom inset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 105,
            height: kGemProductCardHeight,
            child: GemProductCard(
              product: _product(bonusGemsCent: 0, canPurchase: false),
              isBuying: false,
              isPurchaseInProgress: false,
              onPurchase: () {},
            ),
          ),
        ),
      ),
    );

    final stackRect = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is Stack && widget.clipBehavior == Clip.none,
      ),
    );
    final priceButtonRect = tester.getRect(
      find.byKey(const ValueKey('gem-product-price-gem_pack_500')),
    );
    expect(stackRect.bottom - priceButtonRect.bottom, 10);
  });

  testWidgets('other unavailable products remain greyed out', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 105,
            height: kGemProductCardHeight,
            child: GemProductCard(
              product: _product(productId: 'gem_pack_1100', canPurchase: false),
              isBuying: false,
              isPurchaseInProgress: false,
              onPurchase: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.45);
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(find.text('Sold Out'), findsNothing);
  });

  testWidgets('product grid keeps fixed heights and adapts widths', (
    tester,
  ) async {
    final billingState = ValueNotifier<BillingState>(BillingState());
    addTearDown(billingState.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: GemProductGrid(
              products: [
                _product(productId: 'gem_pack_500'),
                _product(productId: 'gem_pack_1000'),
                _product(productId: 'gem_pack_4000'),
              ],
              billingStateListenable: billingState,
              onPurchase: (_) {},
            ),
          ),
        ),
      ),
    );

    final cardSize = tester.getSize(
      find.byKey(const ValueKey<String>('gem-product-gem_pack_500')),
    );
    final buttonSize = tester.getSize(
      find.byKey(const ValueKey<String>('gem-product-price-gem_pack_500')),
    );

    expect(cardSize.height, kGemProductCardHeight);
    expect(cardSize.width, greaterThan(105));
    expect(buttonSize.height, kGemPriceButtonHeight);
    expect(buttonSize.width, closeTo(cardSize.width - 22, 0.1));
  });
}

GemProduct _product({
  String productId = 'gem_pack_500',
  String activityType = 'none',
  String activityText = 'none',
  String activityColor = '',
  String priceCurrencyCode = 'USD',
  bool canPurchase = true,
  int bonusGemsCent = 5000,
}) {
  return GemProduct(
    productId: productId,
    appleProductId: 'com.worldo.gems.500',
    googleProductId: 'worldo_gems_500',
    baseGemsCent: 50000,
    bonusGemsCent: bonusGemsCent,
    priceCurrencyCode: priceCurrencyCode,
    priceAmount: 149,
    canPurchase: canPurchase,
    activityType: activityType,
    activityText: activityText,
    activityColor: activityColor,
  );
}
