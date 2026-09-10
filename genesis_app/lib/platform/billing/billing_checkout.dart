part of 'google_play_billing_service.dart';

extension _GooglePlayBillingCheckout on GooglePlayBillingService {
  Future<bool> _routeSubscription(
    BillingPurchase purchase, {
    List<GemProduct>? productCatalog,
  }) async {
    final intercept = _interceptPurchase;
    if (intercept == null) return false;
    // Known Gems attempts/receipts keep their existing path without another SKU query.
    if (_attemptByStoreProductId.containsKey(purchase.productId) ||
        productCatalog?.any(
              (p) =>
                  _storeProductIdFor(p, purchase.provider) ==
                  purchase.productId,
            ) ==
            true) {
      return false;
    }
    try {
      if (purchase.purchaseToken.isNotEmpty &&
          await _findPendingPurchase(
                provider: purchase.provider,
                purchaseToken: purchase.purchaseToken,
              ) !=
              null) {
        return false;
      }
    } catch (_) {}
    return intercept(purchase);
  }

  Future<void> _start() async {
    _purchaseSubscription ??= _platform.purchaseStream.listen(
      (purchases) => unawaited(
        _handlePurchases(purchases, source: BillingRecoverySource.direct),
      ),
      onError: _handlePurchaseStreamError,
    );

    await _refreshStoreAvailability();
  }

  void _handlePurchaseStreamError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    _onPurchaseStreamError?.call();
    debugPrint('[Billing] purchase stream failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    final activeAttempts = Map<String, BillingPurchaseAttempt>.of(
      _attemptByStoreProductId,
    );
    for (final entry in activeAttempts.entries) {
      final attempt = entry.value;
      _clearActiveAttempt(entry.key, attempt);
      _emitFailure(
        attempt.product.productId,
        attempt.id,
        'Payment service is unavailable.',
        debugInfo: purchaseDebugInfo('gems.store_stream', error: error),
      );
    }
  }

  Future<bool> _refreshStoreAvailability() async {
    var available = false;
    try {
      available = await _platform.isAvailable();
    } catch (error) {
      debugPrint('[Billing] store availability check failed: $error');
    }
    if (_disposed) return false;
    _setState(storeAvailable: available);
    return available;
  }

  Future<BillingProductQueryResult> _queryStoreProduct(
    GemProduct product,
    String storeProductId,
  ) {
    final googlePurchaseOptionId = product.googlePurchaseOptionId.trim();
    final googleOfferId = product.googleOfferId.trim();
    final shouldUseGoogleOffer =
        _platform.provider == BillingProvider.googlePlay &&
        googlePurchaseOptionId.isNotEmpty &&
        googleOfferId.isNotEmpty;
    return _platform.queryProduct(
      storeProductId,
      BillingStoreProductType.inApp,
      purchaseOptionId: shouldUseGoogleOffer ? googlePurchaseOptionId : null,
      offerId: shouldUseGoogleOffer ? googleOfferId : null,
    );
  }

  Future<GemProduct?> _reloadProduct(String productId) async {
    try {
      final products = await _loadProductCatalog();
      for (final product in products) {
        if (product.productId == productId) return product;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
