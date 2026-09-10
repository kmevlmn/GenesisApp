part of 'gem_wallet_page.dart';

extension _GemWalletBillingFlow on _GemWalletPageState {
  void _bindBillingService(BillingService service) {
    if (identical(_billingService, service)) return;
    _billingEvents?.cancel();
    _billingService = service;
    _billingEvents = service.events.listen(_handleBillingEvent);
    unawaited(service.start());
    final products = _products;
    if (products != null) _startStoreRecovery(products);
    if (mounted) _updateState(() {});
  }

  void _startStoreRecovery(List<GemProduct> productCatalog) {
    if (_storeRecoveryStarted) return;
    final service = _billingService;
    if (service == null) return;
    _storeRecoveryStarted = true;
    unawaited(_recoverStorePurchases(service, productCatalog));
  }

  Future<void> _recoverStorePurchases(
    BillingService service,
    List<GemProduct> productCatalog,
  ) async {
    try {
      await service.recoverStorePurchases(productCatalog: productCatalog);
    } catch (error, stackTrace) {
      debugPrint('[Billing] store recovery failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _purchaseProduct(GemProduct product) async {
    final service =
        _billingService ??
        widget.billingService ??
        AppServicesScope.maybeRead(context)?.billing;
    if (service == null) {
      showGenesisToast(
        context,
        purchaseToastMessage(
          'Google Play is unavailable.',
          debugInfo: purchaseDebugInfo(
            'gems.precheck',
            reason: 'service_unavailable',
          ),
        ),
      );
      return;
    }
    _bindBillingService(service);
    if (service.state.value.hasBusyPurchase) return;
    _showBillingPurchaseProcessing();
    try {
      await service.purchaseGem(
        product,
        source: BillingPurchaseSource.buyGemsPage,
        payTrackId: billingPurchaseTrackId(_payTrackPageId),
      );
    } catch (error) {
      if (!mounted) return;
      _dismissBillingPurchaseDialog();
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
    if (!service.state.value.hasBusyPurchase &&
        _billingPurchaseDialogState?.value.phase ==
            GemBillingPurchaseDialogPhase.processing) {
      _dismissBillingPurchaseDialog();
    }
  }

  void _handleBillingEvent(BillingUiEvent event) {
    if (!mounted) return;
    switch (event.kind) {
      case BillingUiEventKind.processing:
        _showBillingPurchaseProcessing(attemptId: event.attemptId);
        return;
      case BillingUiEventKind.success:
        _showBillingPurchaseSuccess(event);
        unawaited(_refreshAll(silent: true));
        return;
      case BillingUiEventKind.accepted:
      case BillingUiEventKind.failure:
      case BillingUiEventKind.pending:
      case BillingUiEventKind.deferred:
        _dismissBillingPurchaseDialog();
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

  void _showBillingPurchaseProcessing({String attemptId = ''}) {
    final nextState = GemBillingPurchaseDialogState.processing(
      attemptId: attemptId,
    );
    final notifier = _billingPurchaseDialogState;
    if (notifier != null) {
      notifier.value = nextState;
    } else {
      _billingPurchaseDialogState =
          ValueNotifier<GemBillingPurchaseDialogState>(nextState);
    }
    _presentBillingPurchaseDialog();
  }

  void _showBillingPurchaseSuccess(BillingUiEvent event) {
    final grantedGemsCent = event.grantedGemsCent;
    final grantedText = formatGemCent(grantedGemsCent);
    final nextState = GemBillingPurchaseDialogState.success(
      attemptId: event.attemptId,
      grantedText: grantedText,
    );
    final notifier = _billingPurchaseDialogState;
    if (notifier != null) {
      notifier.value = nextState;
      return;
    }
    _billingPurchaseDialogState = ValueNotifier<GemBillingPurchaseDialogState>(
      nextState,
    );
    _presentBillingPurchaseDialog();
  }

  void _presentBillingPurchaseDialog() {
    _billingPurchaseDialogState ??=
        ValueNotifier<GemBillingPurchaseDialogState>(
          GemBillingPurchaseDialogState.processing(attemptId: ''),
        );
    if (_billingPurchaseDialogShowing) return;
    _billingPurchaseDialogShowing = true;
    if (mounted) _updateState(() {});
    final dialogState = _billingPurchaseDialogState!;
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierColor: kGenesisModalBarrierColor,
        barrierDismissible: false,
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return Center(
            child: GemBillingPurchaseDialog(
              state: dialogState,
              onConfirm: _dismissBillingPurchaseDialog,
            ),
          );
        },
      ).whenComplete(() {
        if (!mounted) {
          _disposeBillingPurchaseDialogState();
          return;
        }
        _billingPurchaseDialogShowing = false;
        _billingPurchaseDialogDismissing = false;
        _disposeBillingPurchaseDialogState();
        _updateState(() {});
      }),
    );
  }

  void _dismissBillingPurchaseDialog() {
    if (!_billingPurchaseDialogShowing) {
      _disposeBillingPurchaseDialogState();
      return;
    }
    if (_billingPurchaseDialogDismissing) return;
    _billingPurchaseDialogDismissing = true;
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _disposeBillingPurchaseDialogState() {
    final dialogState = _billingPurchaseDialogState;
    if (dialogState != null) {
      _billingPurchaseDialogState = null;
      dialogState.dispose();
    }
  }
}
