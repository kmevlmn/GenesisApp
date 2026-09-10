part of 'google_play_billing_service.dart';

extension _GooglePlayBillingRecovery on GooglePlayBillingService {
  Future<bool> _recoverStorePurchases({
    List<GemProduct>? productCatalog,
  }) async {
    await start();
    if (_disposed || !_state.value.storeAvailable) return false;

    String billingAccountId;
    try {
      billingAccountId = await _resolveBillingAccountId();
    } catch (_) {
      return false;
    }
    if (billingAccountId.isEmpty || _disposed) return false;

    late final List<BillingPurchase> purchases;
    try {
      purchases = await _platform.queryRecoverablePurchases();
    } catch (error) {
      debugPrint('[Billing] store recovery query failed: $error');
      return false;
    }

    final seenPurchaseKeys = <String>{};
    for (final purchase in purchases) {
      if (await _routeSubscription(purchase, productCatalog: productCatalog)) {
        continue;
      }
      final purchaseIdentity = purchase.purchaseToken.trim();
      final purchaseKey = '${purchase.provider.name}:$purchaseIdentity';
      if (purchaseIdentity.isNotEmpty && !seenPurchaseKeys.add(purchaseKey)) {
        continue;
      }
      _recordVerifiedPurchaseForAnalytics(purchase);
      await _recoverStorePurchase(
        purchase,
        billingAccountId: billingAccountId,
        productCatalog: productCatalog,
      );
    }
    return true;
  }

  Future<void> _recoverStorePurchase(
    BillingPurchase purchase, {
    required String billingAccountId,
    List<GemProduct>? productCatalog,
  }) async {
    final token = purchase.purchaseToken.trim();
    if (token.isEmpty) {
      debugPrint('[Billing] skipped store recovery without purchase identity');
      return;
    }

    BillingPendingPurchase? persistedRecord;
    try {
      persistedRecord = await _findPendingPurchase(
        provider: purchase.provider,
        purchaseToken: token,
      );
    } catch (error) {
      debugPrint('[Billing] store recovery local lookup failed: $error');
    }

    final fallbackAttemptId = newBillingAttemptId();
    final recoveredAttempt = persistedRecord == null
        ? await _recoveredAttemptFor(
            purchase,
            source: BillingRecoverySource.foreground,
            fallbackAttemptId: fallbackAttemptId,
            productCatalog: productCatalog,
          )
        : null;
    final now = DateTime.now();
    final productId = persistedRecord?.productId.trim().isNotEmpty == true
        ? persistedRecord!.productId.trim()
        : recoveredAttempt?.product.productId ?? purchase.productId;
    final record = persistedRecord == null
        ? _purchaseRecord(
            purchase: purchase,
            attemptId: recoveredAttempt?.id ?? fallbackAttemptId,
            billingAccountId:
                recoveredAttempt?.billingAccountId ?? billingAccountId,
            productId: productId,
            status: BillingPendingPurchaseStatus.received,
            createdAt: now,
            updatedAt: now,
          )
        : _purchaseRecord(
            purchase: purchase,
            attemptId: persistedRecord.attemptId,
            billingAccountId: persistedRecord.billingAccountId,
            productId: productId,
            status: persistedRecord.status,
            createdAt: persistedRecord.createdAt,
            updatedAt: now,
            retryCount: persistedRecord.retryCount,
            reportTimeoutTracked: persistedRecord.reportTimeoutTracked,
          );
    final belongsToCurrentAccount = _storePurchaseBelongsToCurrentAccount(
      purchase,
      billingAccountId,
      persistedRecord: persistedRecord,
    );
    final processingKey = record.key;
    _completedPurchaseKeys.remove(processingKey);
    await _runExclusivePurchase(processingKey, () async {
      if (persistedRecord != null && belongsToCurrentAccount) {
        await _processRecord(
          record,
          purchase: purchase,
          source: BillingRecoverySource.foreground,
          allowAnyAccount: true,
        );
        return;
      }
      await _processTransientStoreRecovery(
        record,
        purchase: purchase,
        handleResult: belongsToCurrentAccount,
      );
    });
  }

  Future<void> _recoverInternal(
    BillingRecoverySource source, {
    required int sessionGeneration,
  }) async {
    if (_disposed || sessionGeneration != _sessionGeneration) return;
    String uid;
    try {
      uid = (await _readUid())?.trim() ?? '';
    } catch (_) {
      return;
    }
    if (uid.isEmpty || uid.startsWith('guest_')) {
      return;
    }
    String billingAccountId;
    try {
      billingAccountId = await _resolveBillingAccountId();
    } catch (_) {
      return;
    }
    if (billingAccountId.isEmpty ||
        _disposed ||
        sessionGeneration != _sessionGeneration) {
      return;
    }

    List<BillingPendingPurchase> records;
    try {
      records = await _pendingPurchaseStore.loadAll();
    } catch (_) {
      return;
    }
    for (final record in records) {
      if (record.provider != _platform.provider ||
          record.billingAccountId != billingAccountId) {
        continue;
      }
      await _runExclusivePurchase(
        record.key,
        () => _processRecord(record, source: source),
      );
    }
  }

  Future<void> _handlePurchases(
    List<BillingPurchase> purchases, {
    required BillingRecoverySource source,
    String? billingAccountId,
    int? sessionGeneration,
  }) async {
    final gemPurchases = <BillingPurchase>[];
    for (final purchase in purchases) {
      if (!await _routeSubscription(purchase)) gemPurchases.add(purchase);
    }
    purchases = gemPurchases;
    if (purchases.isEmpty) return;
    for (final purchase in purchases) {
      _recordVerifiedPurchaseForAnalytics(purchase);
    }
    var currentBillingAccountId = billingAccountId?.trim() ?? '';
    if (purchases.isNotEmpty && currentBillingAccountId.isEmpty) {
      try {
        currentBillingAccountId = await _resolveBillingAccountId();
      } catch (_) {
        return;
      }
    }
    for (final purchase in purchases) {
      if (sessionGeneration != null &&
          sessionGeneration != _sessionGeneration) {
        return;
      }
      await _handlePurchase(
        purchase,
        source: source,
        billingAccountId: currentBillingAccountId,
      );
    }
  }

  void _recordVerifiedPurchaseForAnalytics(BillingPurchase purchase) {
    if (purchase.status != BillingPurchaseStatus.purchased &&
        purchase.status != BillingPurchaseStatus.restored) {
      return;
    }
    if (purchase.status == BillingPurchaseStatus.purchased) {
      unawaited(
        FirebaseAnalyticsMonitoring.recordPurchase(
          provider: purchase.provider.apiValue,
          productId: purchase.productId,
        ),
      );
    }
    try {
      _platform.recordVerifiedPurchaseForAnalytics(purchase);
    } catch (error) {
      debugPrint('[Billing] store transaction analytics failed: $error');
    }
  }

  Future<void> _handlePurchase(
    BillingPurchase purchase, {
    required BillingRecoverySource source,
    required String billingAccountId,
  }) async {
    final token = purchase.purchaseToken.trim();
    BillingPendingPurchase? persistedRecord;
    var persistedRecordLookupSucceeded = true;
    try {
      persistedRecord = token.isEmpty
          ? null
          : await _findPendingPurchase(
              provider: purchase.provider,
              purchaseToken: token,
            );
    } catch (_) {
      persistedRecordLookupSucceeded = false;
    }
    final attempt = _attemptForPurchase(
      purchase,
      persistedRecord: persistedRecord,
    );
    if (!_purchaseBelongsToBillingAccount(
      purchase,
      attempt,
      billingAccountId,
      persistedRecord: persistedRecord,
    )) {
      debugPrint(
        '[Billing] ignored purchase callback without a matching account',
      );
      return;
    }
    final persistedAttemptId = persistedRecord?.attemptId.trim() ?? '';
    final persistedProductId = persistedRecord?.productId.trim() ?? '';
    final attemptId =
        attempt?.id ??
        (persistedAttemptId.isNotEmpty
            ? persistedAttemptId
            : newBillingAttemptId());
    final productId =
        attempt?.product.productId ??
        (persistedProductId.isNotEmpty
            ? persistedProductId
            : purchase.productId);
    _cancelAttemptTimeout(
      attempt == null
          ? purchase.productId
          : _storeProductIdFor(attempt.product, purchase.provider),
    );
    if (!persistedRecordLookupSucceeded &&
        (purchase.status == BillingPurchaseStatus.purchased ||
            purchase.status == BillingPurchaseStatus.restored)) {
      _emitDeferred(
        productId,
        attemptId,
        debugInfo: purchaseDebugInfo(
          'gems.load_local_orders',
          reason: 'receipt_lookup_failed',
        ),
      );
      return;
    }

    switch (purchase.status) {
      case BillingPurchaseStatus.pending:
        if (token.isNotEmpty && attempt != null) {
          _attemptByPurchaseToken[token] = attempt;
        }
        var pendingPersisted = false;
        if (token.isNotEmpty) {
          pendingPersisted = await _persistPendingPurchase(
            purchase: purchase,
            attempt: attempt,
            existing: persistedRecord,
            attemptId: attemptId,
            productId: productId,
            billingAccountId: billingAccountId,
            existingLookupSucceeded: persistedRecordLookupSucceeded,
          );
        }
        _setBusy(productId, false);
        if (persistedRecord == null &&
            _trackedPendingAttemptIds.add(attemptId)) {
          _trackPendingById(
            attemptId: attemptId,
            productId: productId,
            storeProductId: purchase.productId,
          );
        }
        _emitUiEvent(
          BillingUiEvent(
            kind: BillingUiEventKind.pending,
            productId: productId,
            attemptId: attemptId,
            message: 'Payment is pending.',
            debugInfo: purchaseDebugInfo(
              'gems.store_callback',
              status: purchase.status.name,
            ),
          ),
        );
        BillingPendingPurchase? pendingRecord = persistedRecord;
        if (pendingRecord == null && pendingPersisted) {
          try {
            pendingRecord = await _findPendingPurchase(
              provider: purchase.provider,
              purchaseToken: token,
            );
          } catch (_) {}
        }
        if (pendingRecord != null) {
          final recordToReport = pendingRecord;
          await _runExclusivePurchase(
            recordToReport.key,
            () => _processRecord(
              recordToReport,
              purchase: purchase,
              source: source,
            ),
          );
        }
        return;
      case BillingPurchaseStatus.canceled:
        await _removePendingPurchase(purchase);
        _clearAttempt(purchase, attempt);
        _emitUiEvent(
          BillingUiEvent(
            kind: BillingUiEventKind.failure,
            productId: productId,
            attemptId: attemptId,
            message: 'Purchase cancelled.',
            debugInfo: purchaseDebugInfo(
              'gems.store_callback',
              status: purchase.status.name,
            ),
          ),
        );
        _trackFlowResultById(
          attemptId: attemptId,
          productId: productId,
          storeProductId: purchase.productId,
          status: 'canceled',
          source: source,
        );
        return;
      case BillingPurchaseStatus.error:
        await _removePendingPurchase(purchase);
        _clearAttempt(purchase, attempt);
        _emitFailure(
          productId,
          attemptId,
          _purchaseDetailsFailureMessage(purchase),
          debugInfo: purchaseDebugInfo(
            'gems.store_callback',
            status: purchase.status.name,
            errorCode: purchase.errorCode,
            errorMessage: purchase.errorMessage,
          ),
        );
        _trackFlowResultById(
          attemptId: attemptId,
          productId: productId,
          storeProductId: purchase.productId,
          status: 'store_failed',
          source: source,
          errorCode: purchase.errorCode?.trim().isNotEmpty == true
              ? purchase.errorCode!.trim()
              : 'store_error',
        );
        return;
      case BillingPurchaseStatus.purchased:
      case BillingPurchaseStatus.restored:
        break;
    }

    if (token.isEmpty) {
      _clearAttempt(purchase, attempt);
      _emitFailure(
        productId,
        attemptId,
        'Purchase failed.',
        debugInfo: purchaseDebugInfo(
          'gems.store_callback',
          reason: 'receipt_missing',
        ),
      );
      _trackFlowResultById(
        attemptId: attemptId,
        productId: productId,
        storeProductId: purchase.productId,
        status: 'store_failed',
        source: source,
        errorCode: purchase.provider == BillingProvider.appStore
            ? 'store_error'
            : 'purchase_token_missing',
      );
      return;
    }
    if (attempt != null) _attemptByPurchaseToken[token] = attempt;

    final processingKey = '${purchase.provider.name}:$token';
    if (_disposed || _completedPurchaseKeys.contains(processingKey)) return;
    if (!_beginExclusivePurchase(processingKey)) return;
    _emitUiEvent(
      BillingUiEvent(
        kind: BillingUiEventKind.processing,
        productId: productId,
        attemptId: attemptId,
        message: 'Purchasing Gems',
      ),
    );
    try {
      var record = persistedRecord;
      if (record == null) {
        final resolvedAttempt =
            attempt ??
            await _recoveredAttemptFor(
              purchase,
              source: source,
              fallbackAttemptId: attemptId,
            );
        if (resolvedAttempt == null) {
          return;
        }
        final now = DateTime.now();
        record = _purchaseRecord(
          purchase: purchase,
          attemptId: resolvedAttempt.id,
          billingAccountId: resolvedAttempt.billingAccountId,
          productId: resolvedAttempt.product.productId,
          status: BillingPendingPurchaseStatus.received,
          createdAt: now,
          updatedAt: now,
        );
        try {
          await _pendingPurchaseStore.upsert(record);
        } catch (_) {
          _emitDeferred(
            resolvedAttempt.product.productId,
            resolvedAttempt.id,
            debugInfo: purchaseDebugInfo(
              'gems.save_order',
              reason: 'receipt_persistence_failed',
            ),
          );
          return;
        }
      } else if (record.status != BillingPendingPurchaseStatus.received) {
        record = _purchaseRecord(
          purchase: purchase,
          attemptId: record.attemptId,
          billingAccountId: record.billingAccountId,
          productId: record.productId,
          status: record.status == BillingPendingPurchaseStatus.accepted
              ? BillingPendingPurchaseStatus.accepted
              : BillingPendingPurchaseStatus.received,
          createdAt: record.createdAt,
          updatedAt: DateTime.now(),
          retryCount: record.retryCount,
          reportTimeoutTracked: record.reportTimeoutTracked,
        );
        try {
          await _pendingPurchaseStore.upsert(record);
        } catch (_) {
          _emitDeferred(
            record.productId,
            record.attemptId,
            debugInfo: purchaseDebugInfo(
              'gems.save_order',
              reason: 'receipt_persistence_failed',
            ),
          );
          return;
        }
      }
      await _processRecord(record, purchase: purchase, source: source);
    } finally {
      _endExclusivePurchase(processingKey);
    }
  }
}
