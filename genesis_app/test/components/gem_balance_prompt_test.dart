import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/ui/components/genesis_dark_close_button.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:genesis_flutter_android/app/gems/gem_wallet_store.dart';
import 'package:genesis_flutter_android/app/telemetry/genesis_telemetry.dart';
import 'package:genesis_flutter_android/components/common/genesis_bottom_sheet_panel.dart';
import 'package:genesis_flutter_android/components/gems/gem_balance_prompt.dart';
import 'package:genesis_flutter_android/components/gems/gem_purchase_catalog.dart';
import 'package:genesis_flutter_android/network/chatroom/world_chatroom_service.dart';
import 'package:genesis_flutter_android/network/models/gem_product.dart';
import 'package:genesis_flutter_android/network/models/gem_wallet.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/platform/billing/billing_service.dart';

void main() {
  tearDown(GenesisTelemetry.resetForTesting);

  testWidgets('insufficient balance opens the purchase bottom sheet', (
    tester,
  ) async {
    final telemetry = _CapturingTelemetrySink();
    GenesisTelemetry.setSinkForTesting(telemetry);
    final fixture = _PromptFixture();
    addTearDown(fixture.dispose);
    await _pumpPrompt(
      tester,
      const GemBalanceAlert(kind: GemBalanceAlertKind.insufficient),
      fixture,
    );

    expect(find.text('Buy Gems'), findsOneWidget);
    expect(find.text(insufficientGemBalancePrompt), findsNothing);
    expect(find.text(lowGemBalancePrompt), findsNothing);
    expect(find.byType(GenesisBottomSheetPanel), findsOneWidget);
    expect(find.byType(GemPurchaseCatalogSection), findsOneWidget);
    expect(find.byType(GenesisDarkCloseButton), findsOneWidget);
    final closeButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byType(GenesisDarkCloseButton),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      closeButton.style?.foregroundColor?.resolve({}),
      GenesisColors.darkTextPrimary,
    );
    expect(
      closeButton.style?.backgroundColor?.resolve({}),
      GenesisColors.darkFaintFill,
    );
    expect(find.text('430.0'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('gem-balance-icon'))).dx,
      tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('gem-product-gem_pack_500')),
          )
          .dx,
    );
    expect(
      tester
              .getTopLeft(
                find.byKey(const ValueKey<String>('gem-product-gem_pack_500')),
              )
              .dy -
          tester
              .getBottomLeft(find.byKey(const ValueKey('gem-balance-panel')))
              .dy,
      10,
    );
    expect(
      tester.widget<SizedBox>(find.byKey(const ValueKey('gem-balance-panel'))),
      isA<SizedBox>(),
    );
    expect(find.text('+550'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text(formatGemPrice(149, 'USD')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('gem-purchase-sheet-close')),
      findsOneWidget,
    );
    final sheet = tester.widget<FractionallySizedBox>(
      find.byKey(const ValueKey<String>('gem-purchase-sheet-size')),
    );
    expect(sheet.heightFactor, 0.8);
    _expectSheetShowEvent(telemetry, gemPurchaseSheetTriggerMessageNoBalance);
  });

  testWidgets(
    'low balance uses the same purchase sheet without an alert title',
    (tester) async {
      final telemetry = _CapturingTelemetrySink();
      GenesisTelemetry.setSinkForTesting(telemetry);
      final fixture = _PromptFixture();
      addTearDown(fixture.dispose);
      await _pumpPrompt(
        tester,
        const GemBalanceAlert(kind: GemBalanceAlertKind.low, balanceCent: 1000),
        fixture,
      );

      expect(find.text('Buy Gems'), findsOneWidget);
      expect(find.text(lowGemBalancePrompt), findsNothing);
      expect(find.text('+550'), findsOneWidget);
      _expectSheetShowEvent(
        telemetry,
        gemPurchaseSheetTriggerMessageLowBalance,
      );
    },
  );

  testWidgets('tick balance prompt reports tick purchase sheet trigger', (
    tester,
  ) async {
    final telemetry = _CapturingTelemetrySink();
    GenesisTelemetry.setSinkForTesting(telemetry);
    final fixture = _PromptFixture();
    addTearDown(fixture.dispose);
    await _pumpPrompt(
      tester,
      const GemBalanceAlert(kind: GemBalanceAlertKind.insufficient),
      fixture,
      analyticsTrigger: gemPurchaseSheetTriggerTick,
    );

    expect(find.text('Buy Gems'), findsOneWidget);
    _expectSheetShowEvent(telemetry, gemPurchaseSheetTriggerTick);
  });

  testWidgets('purchase sheet uses the standard bottom safe area', (
    tester,
  ) async {
    final fixture = _PromptFixture();
    addTearDown(fixture.dispose);
    await _pumpPrompt(
      tester,
      const GemBalanceAlert(kind: GemBalanceAlertKind.insufficient),
      fixture,
      bottomViewPadding: 40,
    );

    final safeArea = tester.widget<SafeArea>(
      find.descendant(
        of: find.byType(GenesisBottomSheetPanel),
        matching: find.byType(SafeArea),
      ),
    );
    expect(safeArea.top, isFalse);
    expect(safeArea.bottom, isTrue);
  });

  testWidgets('purchase sheet starts one purchase and closes on success', (
    tester,
  ) async {
    final telemetry = _CapturingTelemetrySink();
    GenesisTelemetry.setSinkForTesting(telemetry);
    final fixture = _PromptFixture(
      products: [_product('gem_pack_500'), _product('gem_pack_1100')],
    );
    addTearDown(fixture.dispose);
    await _pumpPrompt(
      tester,
      const GemBalanceAlert(kind: GemBalanceAlertKind.insufficient),
      fixture,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('gem-product-gem_pack_500')),
    );
    await tester.pump();

    expect(fixture.billing.purchasedProducts, hasLength(1));
    expect(fixture.billing.purchasedProducts.single.productId, 'gem_pack_500');
    expect(fixture.billing.purchaseSources, [
      BillingPurchaseSource.buyGemsSheet,
    ]);
    final showEvent = telemetry.events.singleWhere(
      (event) =>
          event.category == 'collect.log' && event.name == 'buy_page_show',
    );
    expect(fixture.billing.purchaseTrackIds, hasLength(1));
    final showMatch = RegExp(
      r'^track_id_([^_]+)$',
    ).firstMatch('${showEvent.data['object2']}');
    final purchaseMatch = RegExp(
      r'^track_id_([^_]+)_([^_]+)$',
    ).firstMatch(fixture.billing.purchaseTrackIds.single);
    expect(showMatch, isNotNull);
    expect(purchaseMatch, isNotNull);
    expect(purchaseMatch!.group(1), showMatch!.group(1));
    expect(purchaseMatch.group(2), isNotEmpty);
    expect(find.textContaining('Purchasing Gems'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    fixture.billing.emitSuccess('gem_pack_500');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Purchase successful!'), findsOneWidget);
    expect(find.text('Buy Gems'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Buy Gems'), findsNothing);
  });

  testWidgets('purchase sheet closes from its close button', (tester) async {
    final fixture = _PromptFixture();
    addTearDown(fixture.dispose);
    await _pumpPrompt(
      tester,
      const GemBalanceAlert(kind: GemBalanceAlertKind.insufficient),
      fixture,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('gem-purchase-sheet-close')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Buy Gems'), findsNothing);
  });
}

Future<void> _pumpPrompt(
  WidgetTester tester,
  GemBalanceAlert alert,
  _PromptFixture fixture, {
  String? analyticsTrigger,
  double bottomViewPadding = 0,
}) async {
  tester.view.viewPadding = FakeViewPadding(
    bottom: bottomViewPadding * tester.view.devicePixelRatio,
  );
  addTearDown(tester.view.resetViewPadding);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showGemBalancePrompt(
              context,
              alert,
              analyticsTrigger: analyticsTrigger,
              productsLoader: () async => fixture.products,
              walletStore: fixture.walletStore,
              billingService: fixture.billing,
            ),
            child: const Text('Show prompt'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Show prompt'));
  await tester.pumpAndSettle();
}

void _expectSheetShowEvent(_CapturingTelemetrySink telemetry, String trigger) {
  final events = telemetry.events
      .where(
        (event) =>
            event.category == 'collect.log' && event.name == 'buy_page_show',
      )
      .toList();
  expect(events, hasLength(1));
  expect(events.single.data['action_type'], 'pay_event');
  expect(events.single.data['action'], 'buy_page_show');
  expect(events.single.data['object1'], 'buy_gems_sheet');
  expect(events.single.data['object2'], isA<String>());
  final trackId = '${events.single.data['object2']}';
  final match = RegExp(r'^track_id_([^_]+)$').firstMatch(trackId);
  expect(match, isNotNull);
  expect(events.single.data['object3'], trigger);
}

class _CapturingTelemetrySink implements GenesisTelemetrySink {
  final events = <GenesisTelemetryEvent>[];

  @override
  Future<void> captureException(Object error, StackTrace stackTrace) async {}

  @override
  Future<void> record(GenesisTelemetryEvent event) async {
    events.add(event);
  }

  @override
  Future<void> setContext(GenesisTelemetryContext context) async {}

  @override
  Future<void> setUserId(String? uid) async {}
}

class _PromptFixture {
  _PromptFixture({List<GemProduct>? products})
    : products = products ?? [_product('gem_pack_500')],
      walletStore = GemWalletStore(
        loadWallet: () async => const GemWallet(balanceCent: 43000),
        readUid: () async => 'u_user',
      );

  final List<GemProduct> products;
  final GemWalletStore walletStore;
  final _FakeBillingService billing = _FakeBillingService();

  void dispose() {
    walletStore.dispose();
    billing.dispose();
  }
}

class _FakeBillingService implements BillingService {
  final ValueNotifier<BillingState> _state = ValueNotifier<BillingState>(
    BillingState(storeAvailable: true),
  );
  final StreamController<BillingUiEvent> _events =
      StreamController<BillingUiEvent>.broadcast();
  final List<GemProduct> purchasedProducts = <GemProduct>[];
  final List<BillingPurchaseSource> purchaseSources = <BillingPurchaseSource>[];
  final List<String> purchaseTrackIds = <String>[];

  @override
  Stream<BillingUiEvent> get events => _events.stream;

  @override
  ValueListenable<BillingState> get state => _state;

  @override
  Future<void> purchaseGem(
    GemProduct product, {
    BillingPurchaseSource source = BillingPurchaseSource.buyGemsPage,
    String payTrackId = '',
  }) async {
    if (_state.value.hasBusyPurchase) return;
    purchasedProducts.add(product);
    purchaseSources.add(source);
    purchaseTrackIds.add(payTrackId);
    _state.value = BillingState(
      storeAvailable: true,
      busyProductIds: <String>{product.productId},
    );
  }

  void emitSuccess(String productId) {
    _state.value = BillingState(storeAvailable: true);
    _events.add(
      BillingUiEvent(
        kind: BillingUiEventKind.success,
        productId: productId,
        attemptId: 'pay_test',
        message: 'Purchase successful!',
        grantedGemsCent: 55000,
      ),
    );
  }

  @override
  Future<void> recover(BillingRecoverySource source) async {}

  @override
  Future<bool> recoverStorePurchases({
    List<GemProduct>? productCatalog,
  }) async => true;

  @override
  void resetForSession() {}

  @override
  Future<void> start() async {}

  @override
  void dispose() {
    _state.dispose();
    _events.close();
  }
}

GemProduct _product(String productId) {
  return GemProduct(
    productId: productId,
    appleProductId: productId,
    googleProductId: productId,
    baseGemsCent: productId == 'gem_pack_500' ? 50000 : 110000,
    bonusGemsCent: 5000,
    priceCurrencyCode: 'USD',
    priceAmount: 149,
    canPurchase: true,
    activityType: 'first_purchase_bonus',
  );
}
