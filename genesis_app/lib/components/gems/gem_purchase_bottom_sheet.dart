import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/gems/gem_wallet_store.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../network/chatroom/world_chatroom_service.dart';
import '../../network/models/gem_product.dart';
import '../../platform/billing/billing_models.dart';
import '../../platform/billing/billing_service.dart';
import '../../platform/billing/purchase_toast_diagnostics.dart';
import '../../utils/gem_amount.dart';
import '../common/genesis_center_toast.dart';
import '../common/genesis_bottom_sheet_panel.dart';
import '../common/genesis_modal_routes.dart';
import 'gem_billing_purchase_dialog.dart';
import 'gem_purchase_state.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import '../../ui/tokens/genesis_colors.dart';
import 'gem_purchase_catalog.dart';
import 'purchase_options_sheet.dart';
import 'purchase_session_builder.dart';

typedef GemPurchaseProductsLoader = Future<List<GemProduct>> Function();

Future<void> showGemPurchaseBottomSheet(
  BuildContext context, {
  required GemBalanceAlert alert,
  String? analyticsTrigger,
  GemPurchaseProductsLoader? productsLoader,
  GemWalletStore? walletStore,
  BillingService? billingService,
}) async {
  final services = AppServicesScope.maybeRead(context);
  final resolvedProductsLoader =
      productsLoader ??
      (services == null
          ? null
          : () async => (await services.api.v1.gem.products()).products);
  final resolvedWalletStore = walletStore ?? services?.gemWallet;
  final resolvedBillingService = billingService ?? services?.billing;
  if (resolvedProductsLoader == null ||
      resolvedWalletStore == null ||
      resolvedBillingService == null) {
    if (context.mounted) {
      showGenesisToast(
        context,
        purchaseToastMessage(
          'Unable to load gem packs.',
          debugInfo: purchaseDebugInfo(
            'gems.precheck',
            reason: 'service_unavailable',
          ),
        ),
      );
    }
    return;
  }

  final payTrackPageId = newBillingTrackPageId();
  _trackGemPurchaseSheetShow(analyticsTrigger, payTrackPageId);

  await showGenesisModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      key: const ValueKey<String>('gem-purchase-sheet-size'),
      heightFactor: 0.8,
      alignment: Alignment.bottomCenter,
      child: PurchaseOptionsSheet(
        gemsBuilder: (_) => GemPurchaseBottomSheet(
          embedded: true,
          alert: alert,
          productsLoader: resolvedProductsLoader,
          walletStore: resolvedWalletStore,
          billingService: resolvedBillingService,
          payTrackPageId: payTrackPageId,
        ),
      ),
    ),
  );
}

Future<void> showSubscriptionPurchaseBottomSheet(BuildContext context) async {
  final services = AppServicesScope.maybeRead(context);
  final billingService = services?.billing;
  final payTrackPageId = newBillingTrackPageId();
  await showGenesisModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.8,
      alignment: Alignment.bottomCenter,
      child: PurchaseSessionBuilder(
        backgroundColor: GenesisColors.darkRaisedBackground,
        builder: (_, showBuyGems) => PurchaseOptionsSheet(
          showBuyGems: showBuyGems,
          initialTab: PurchaseSheetTab.subscription,
          gemsBuilder: (_) => services == null || billingService == null
              ? const SizedBox.expand()
              : GemPurchaseBottomSheet(
                  embedded: true,
                  alert: const GemBalanceAlert(kind: GemBalanceAlertKind.low),
                  productsLoader: () async =>
                      (await services.api.v1.gem.products()).products,
                  walletStore: services.gemWallet,
                  billingService: billingService,
                  payTrackPageId: payTrackPageId,
                ),
        ),
      ),
    ),
  );
}

void _trackGemPurchaseSheetShow(
  String? analyticsTrigger,
  String payTrackPageId,
) {
  final trigger = analyticsTrigger?.trim() ?? '';
  GenesisTelemetry.collectLog(
    actionType: 'pay_event',
    action: 'buy_page_show',
    object1: BillingPurchaseSource.buyGemsSheet.value,
    object2: billingPageTrackId(payTrackPageId),
    object3: trigger.isEmpty ? null : trigger,
  );
}

class GemPurchaseBottomSheet extends StatefulWidget {
  const GemPurchaseBottomSheet({
    super.key,
    required this.alert,
    required this.productsLoader,
    required this.walletStore,
    required this.billingService,
    required this.payTrackPageId,
    this.embedded = false,
  });

  final GemBalanceAlert alert;
  final GemPurchaseProductsLoader productsLoader;
  final GemWalletStore walletStore;
  final BillingService billingService;
  final String payTrackPageId;
  final bool embedded;

  @override
  State<GemPurchaseBottomSheet> createState() => _GemPurchaseBottomSheetState();
}

class _GemPurchaseBottomSheetState extends State<GemPurchaseBottomSheet> {
  List<GemProduct>? _products;
  Object? _productsError;
  bool _productsLoading = false;
  int _productsRequestGeneration = 0;
  StreamSubscription<BillingUiEvent>? _billingEvents;
  final Set<String> _startedProductIds = <String>{};
  ValueNotifier<GemBillingPurchaseDialogState>? _purchaseDialogState;
  bool _purchaseDialogShowing = false;
  bool _purchaseDialogDismissing = false;
  bool _closeSheetAfterDialog = false;

  @override
  void initState() {
    super.initState();
    _billingEvents = widget.billingService.events.listen(_handleBillingEvent);
    unawaited(widget.billingService.start());
    unawaited(widget.walletStore.refresh());
    unawaited(_loadProducts());
  }

  @override
  void dispose() {
    _productsRequestGeneration += 1;
    _billingEvents?.cancel();
    _disposePurchaseDialogState();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final generation = ++_productsRequestGeneration;
    setState(() {
      _productsLoading = true;
      _productsError = null;
    });
    try {
      final products = await widget.productsLoader();
      if (!mounted || generation != _productsRequestGeneration) return;
      setState(() {
        _products = products;
        _productsLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _productsRequestGeneration) return;
      setState(() {
        _productsError = error;
        _productsLoading = false;
      });
    }
  }

  Future<void> _purchase(GemProduct product) async {
    if (widget.billingService.state.value.hasBusyPurchase) return;
    _startedProductIds.add(product.productId);
    _showPurchaseProcessing(attemptId: '');
    try {
      await widget.billingService.purchaseGem(
        product,
        source: BillingPurchaseSource.buyGemsSheet,
        payTrackId: billingPurchaseTrackId(widget.payTrackPageId),
      );
    } catch (error) {
      if (!mounted) return;
      _startedProductIds.remove(product.productId);
      _dismissPurchaseDialog();
      showGenesisToast(
        context,
        purchaseToastMessage(
          'Purchase failed.',
          debugInfo: purchaseDebugInfo('gems.checkout_exception', error: error),
        ),
      );
      return;
    }
    if (!mounted) return;
    if (!widget.billingService.state.value.hasBusyPurchase &&
        _purchaseDialogState?.value.phase ==
            GemBillingPurchaseDialogPhase.processing) {
      _dismissPurchaseDialog();
    }
  }

  void _handleBillingEvent(BillingUiEvent event) {
    if (!mounted || !_startedProductIds.contains(event.productId)) return;
    switch (event.kind) {
      case BillingUiEventKind.processing:
        _showPurchaseProcessing(attemptId: event.attemptId);
        return;
      case BillingUiEventKind.success:
        _showPurchaseSuccess(event);
        return;
      case BillingUiEventKind.accepted:
      case BillingUiEventKind.failure:
      case BillingUiEventKind.pending:
      case BillingUiEventKind.deferred:
        _startedProductIds.remove(event.productId);
        _dismissPurchaseDialog();
        showGenesisToast(
          context,
          purchaseToastMessage(
            event.message,
            debugInfo:
                event.debugInfo ??
                purchaseDebugInfo('gems.checkout', status: event.kind.name),
          ),
        );
    }
  }

  void _showPurchaseProcessing({required String attemptId}) {
    final nextState = GemBillingPurchaseDialogState.processing(
      attemptId: attemptId,
    );
    final notifier = _purchaseDialogState;
    if (notifier != null) {
      notifier.value = nextState;
    } else {
      _purchaseDialogState = ValueNotifier<GemBillingPurchaseDialogState>(
        nextState,
      );
    }
    _presentPurchaseDialog();
  }

  void _showPurchaseSuccess(BillingUiEvent event) {
    final grantedGemsCent = event.grantedGemsCent;
    final nextState = GemBillingPurchaseDialogState.success(
      attemptId: event.attemptId,
      grantedText: formatGemCent(grantedGemsCent),
    );
    _updatePurchaseDialog(nextState);
  }

  void _updatePurchaseDialog(GemBillingPurchaseDialogState nextState) {
    final notifier = _purchaseDialogState;
    if (notifier != null) {
      notifier.value = nextState;
      return;
    }
    _purchaseDialogState = ValueNotifier<GemBillingPurchaseDialogState>(
      nextState,
    );
    _presentPurchaseDialog();
  }

  void _presentPurchaseDialog() {
    _purchaseDialogState ??= ValueNotifier<GemBillingPurchaseDialogState>(
      GemBillingPurchaseDialogState.processing(attemptId: ''),
    );
    if (_purchaseDialogShowing) return;
    _purchaseDialogShowing = true;
    final dialogState = _purchaseDialogState!;
    unawaited(
      showGenesisGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return Center(
            child: GemBillingPurchaseDialog(
              state: dialogState,
              onConfirm: _confirmPurchaseDialog,
            ),
          );
        },
      ).whenComplete(() {
        if (!mounted) {
          _disposePurchaseDialogState();
          return;
        }
        final shouldCloseSheet = _closeSheetAfterDialog;
        _purchaseDialogShowing = false;
        _purchaseDialogDismissing = false;
        _closeSheetAfterDialog = false;
        _disposePurchaseDialogState();
        if (shouldCloseSheet) Navigator.of(context).maybePop();
      }),
    );
  }

  void _confirmPurchaseDialog() {
    _closeSheetAfterDialog = true;
    _dismissPurchaseDialog();
  }

  void _dismissPurchaseDialog() {
    if (!_purchaseDialogShowing) {
      _disposePurchaseDialogState();
      return;
    }
    if (_purchaseDialogDismissing) return;
    _purchaseDialogDismissing = true;
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _disposePurchaseDialogState() {
    final dialogState = _purchaseDialogState;
    if (dialogState == null) return;
    _purchaseDialogState = null;
    dialogState.dispose();
  }

  String get _title => widget.alert.kind == GemBalanceAlertKind.insufficient
      ? 'Insufficient Gems'
      : 'Low Gems';

  @override
  Widget build(BuildContext context) {
    final content = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 14),
      child: ValueListenableBuilder<GemWalletState>(
        valueListenable: widget.walletStore.state,
        builder: (context, walletState, _) => GemPurchaseCatalogSection(
          balanceCent: walletState.balanceCent ?? 0,
          balanceKey: const ValueKey<String>('gem-purchase-sheet-balance'),
          catalog: _buildProducts(),
        ),
      ),
    );
    if (widget.embedded) {
      return content;
    }
    return GenesisDarkTheme(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GenesisBottomSheetPanel(
            title: _title,
            height: constraints.maxHeight,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            trailing: GenesisBottomSheetCloseButton(
              buttonKey: const ValueKey<String>('gem-purchase-sheet-close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            child: content,
          );
        },
      ),
    );
  }

  Widget _buildProducts() {
    final products = _products;
    if (_productsLoading && products == null) {
      return const GemProductGridSkeleton();
    }
    if (_productsError != null && products == null) {
      return GemPurchaseState(
        message: 'Unable to load gem packs.',
        onRetry: () => unawaited(_loadProducts()),
      );
    }
    if (products == null || products.isEmpty) {
      return const GemPurchaseState(message: 'No gem packs available.');
    }
    return GemProductGrid(
      products: products,
      billingStateListenable: widget.billingService.state,
      onPurchase: (product) => unawaited(_purchase(product)),
    );
  }
}
