part of 'membership_purchase_service.dart';

extension _MembershipPurchaseRestore on MembershipPurchaseService {
  Future<void> _saveRestore(MembershipRestoreRecord record) async {
    _restoreRecords[record.requestId] = record;
    _pendingRestoreIds.add(record.requestId);
    await store.saveRestore(record);
  }

  Future<void> _restoreStorePurchases({
    List<MembershipProduct>? products,
  }) async {
    if (_disposed || queryRestorePurchases == null) {
      return;
    }
    if (products != null) {
      _restoreProducts = products.where((p) => p.provider == provider).toList();
      _restoreEnabled = true;
    }
    final session = _session;
    final running = _restoring;
    if (running != null) {
      await running;
      if (!_disposed && session == _session && _lastRestoreSession != session) {
        await _restoreStorePurchases();
      }
      return;
    }
    late final Future<void> task;
    task =
        () async {
          try {
            final uid = await readLoginUid();
            if (uid == null || _disposed || session != _session) return;
            await _load();
            final retrying = {
              for (final record in _restoreRecords.values)
                if (record.ownerUid == uid &&
                    _pendingRestoreIds.contains(record.requestId))
                  record.receiptKey: record.requestId,
            };
            final pendingPurchases =
                _records.values
                    .where(
                      (r) =>
                          r.ownerUid == uid &&
                          _pendingRequestIds.contains(r.requestId),
                    )
                    .map((r) => r.requestId)
                    .toSet()
                  ..addAll(_pendingRestoreIds);
            await recover();
            if (_disposed ||
                session != _session ||
                _busy ||
                (otherPurchaseBusy?.call() ?? false)) {
              return;
            }
            final ids = <String>{
              ..._restoreProducts.map((p) => p.storeProductId),
              ..._records.values
                  .where((r) => r.product.provider == provider)
                  .map((r) => r.product.storeProductId),
              ..._restoreRecords.values
                  .where((r) => r.purchase.provider.apiValue == provider.name)
                  .map((r) => r.purchase.productId),
            };
            if (ids.isEmpty) return;
            final receipts = await queryRestorePurchases!(ids);
            _retryStoreRestore = false;
            final seen = <String>{};
            for (final purchase in receipts) {
              if (_disposed ||
                  session != _session ||
                  await readLoginUid() != uid) {
                return;
              }
              if (!ids.contains(purchase.productId) ||
                  !seen.add(
                    '${membershipReceiptKey(purchase)}:${purchase.transactionId}',
                  )) {
                continue;
              }
              final retried =
                  _restoreRecords[retrying[membershipReceiptKey(purchase)]];
              // recover() already processed this receipt in this batch. Only a
              // newer transaction or a pending -> paid store update needs work
              // now; unchanged accepted results retain their scheduled retry.
              if (retried != null &&
                  retried.purchase.transactionId == purchase.transactionId &&
                  (retried.paid ||
                      purchase.status == BillingPurchaseStatus.pending)) {
                continue;
              }
              if (_alreadyRetriedReceipt(purchase, pendingPurchases)) {
                continue;
              }
              await _serialize(() async {
                if (!_disposed &&
                    session == _session &&
                    await readLoginUid() == uid) {
                  await _restoreReceipt(purchase);
                }
              });
            }
          } catch (error) {
            _retryStoreRestore = true;
            _scheduleRetry();
            _log('store restore deferred', error);
          }
        }().whenComplete(() {
          _lastRestoreSession = session;
          if (identical(_restoring, task)) _restoring = null;
        });
    _restoring = task;
    await task;
  }

  // Google can reuse a token for renewals. Prefer an exact transaction so a
  // late callback cannot make an older completed order look like a new renewal.
  MembershipPurchaseRecord? _purchaseForRestore(BillingPurchase purchase) {
    MembershipPurchaseRecord? tokenMatch;
    for (final record in _records.values.toList().reversed) {
      if (record.product.provider != provider ||
          record.product.storeProductId != purchase.productId) {
        continue;
      }
      if (provider == MembershipProvider.google) {
        if (purchase.purchaseToken.isEmpty ||
            record.purchaseToken != purchase.purchaseToken) {
          continue;
        }
        tokenMatch ??= record;
      }
      if (purchase.transactionId.isNotEmpty &&
          record.transactionId == purchase.transactionId) {
        return record;
      }
    }
    return tokenMatch;
  }

  bool _alreadyRetriedReceipt(
    BillingPurchase purchase,
    Set<String> requestIds,
  ) {
    final record = _purchaseForRestore(purchase);
    return record != null &&
        requestIds.contains(record.requestId) &&
        record.transactionId == purchase.transactionId &&
        (record.paid || purchase.status == BillingPurchaseStatus.pending);
  }

  MembershipOrderProduct? _restoreProduct(BillingPurchase purchase) {
    final original = _purchaseForRestore(purchase);
    if (original != null) return original.product;
    // The same Google product ID can represent either plan. The store receipt
    // does not contain basePlanId; do not infer it from the currently selected UI.
    if (provider == MembershipProvider.google) return null;
    final matches = _restoreProducts
        .where((p) => p.storeProductId == purchase.productId)
        .toList();
    if (matches.length == 1) return matches.single;
    for (final record in _records.values.toList().reversed) {
      if (record.product.provider == provider &&
          record.product.storeProductId == purchase.productId) {
        return record.product;
      }
    }
    return null;
  }

  Future<void> _restoreReceipt(BillingPurchase purchase) async {
    if (_disposed || purchase.provider.apiValue != provider.name) return;
    if (purchase.status != BillingPurchaseStatus.purchased &&
        purchase.status != BillingPurchaseStatus.restored &&
        purchase.status != BillingPurchaseStatus.pending) {
      return;
    }
    if (provider == MembershipProvider.google
        ? purchase.purchaseToken.isEmpty
        : purchase.transactionId.isEmpty) {
      return;
    }
    final uid = await readLoginUid();
    if (uid == null || _disposed) return;
    final original = _purchaseForRestore(purchase);
    if (original != null) {
      // Use the original purchase pipeline, including completed-transaction
      // deduplication, renewals and guest report/claim ownership.
      if (original.guest != null || original.ownerUid == uid) {
        await _handle(purchase);
      }
      return;
    }
    MembershipRestoreRecord? record;
    for (final candidate in _restoreRecords.values.toList().reversed) {
      if (candidate.ownerUid == uid &&
          candidate.receiptKey == membershipReceiptKey(purchase) &&
          candidate.purchase.transactionId == purchase.transactionId) {
        record = candidate;
        break;
      }
    }
    record ??= MembershipRestoreRecord(
      requestId: newBillingAttemptId(),
      ownerUid: uid,
      purchase: purchase,
      product: _restoreProduct(purchase),
    );
    if (!record.paid && purchase.status != BillingPurchaseStatus.pending) {
      record = record.copyWith(purchase: purchase);
    }
    await _saveRestore(record);
    await _processRestore(record);
  }

  Future<void> _removeRestore(MembershipRestoreRecord record) async {
    await store.removeRestore(record.requestId);
    _pendingRestoreIds.remove(record.requestId);
    _restoreRecords.remove(record.requestId);
  }

  Future<void> _processRestore(MembershipRestoreRecord record) async {
    if (_disposed ||
        !_pendingRestoreIds.contains(record.requestId) ||
        record.purchase.provider.apiValue != provider.name ||
        await readLoginUid() != record.ownerUid) {
      return;
    }
    final session = _session;
    try {
      final original = _purchaseForRestore(record.purchase);
      final migrated = _records[record.requestId];
      if (migrated != null && migrated.ownerUid == record.ownerUid ||
          original != null &&
              (original.ownerUid == record.ownerUid ||
                  original.guest != null) &&
              original.transactionId == record.purchase.transactionId) {
        // The purchase queue already owns this exact receipt (and recover()
        // already retried it). Old duplicate restore records must not block it.
        // Re-save pending records before removing the only durable backup.
        final purchase = migrated ?? original!;
        if (_pendingRequestIds.contains(purchase.requestId)) {
          await _save(purchase);
        }
        await _removeRestore(record);
        return;
      }
      final product = record.product ?? _restoreProduct(record.purchase);
      // Google receipts with a shared product ID cannot identify plan_code.
      // Keep the receipt safely until an exact purchase snapshot is available.
      if (product == null) return;
      if (_disposed ||
          session != _session ||
          await readLoginUid() != record.ownerUid) {
        return;
      }
      final purchase = MembershipPurchaseRecord(
        requestId: record.requestId,
        ownerUid: record.ownerUid,
        accountUuid:
            record.purchase.obfuscatedAccountId?.trim().toLowerCase() ?? '',
        product: product,
        transactionId: record.purchase.transactionId,
        originalTransactionId: record.purchase.originalTransactionId,
        purchaseToken: record.purchase.purchaseToken,
        state: record.paid ? 'restored' : record.purchase.status.name,
        reportStatus: record.reportStatus,
        reportId: record.reportId,
        reportReason: record.reportReason,
        finished: record.finished,
      );
      // Crash-safe handoff: persist the normal purchase before deleting the
      // legacy/unresolved receipt. Preserve its request key, status and owner.
      await _save(purchase);
      await _removeRestore(record);
      await _report(purchase);
    } catch (error) {
      if (!_busy) _setState(MembershipCheckoutState.deferred);
      _scheduleRetry();
      _log('receipt migration deferred', error);
    }
  }
}
