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
    if (_disposed || restorePurchase == null || queryRestorePurchases == null) {
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
            final pendingPurchases = _records.values
                .where(
                  (r) =>
                      r.ownerUid == uid &&
                      _pendingRequestIds.contains(r.requestId),
                )
                .map((r) => r.requestId)
                .toSet();
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
                  !seen.add(membershipReceiptKey(purchase))) {
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
              if (pendingPurchases.contains(
                _purchaseForRestore(purchase)?.requestId,
              )) {
                continue;
              }
              await _serialize(() async {
                if (!_disposed &&
                    session == _session &&
                    await readLoginUid() == uid) {
                  await _restoreReceipt(
                    purchase,
                    newOperation: !retrying.containsKey(
                      membershipReceiptKey(purchase),
                    ),
                  );
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

  MembershipPurchaseRecord? _purchaseForRestore(BillingPurchase purchase) {
    for (final record in _records.values.toList().reversed) {
      if (record.product.provider != provider ||
          record.product.storeProductId != purchase.productId) {
        continue;
      }
      if (provider == MembershipProvider.google
          ? purchase.purchaseToken.isNotEmpty &&
                record.purchaseToken == purchase.purchaseToken
          : purchase.transactionId.isNotEmpty &&
                record.transactionId == purchase.transactionId) {
        return record;
      }
    }
    return null;
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

  Future<void> _restoreReceipt(
    BillingPurchase purchase, {
    bool newOperation = false,
  }) async {
    if (_disposed ||
        restorePurchase == null ||
        purchase.provider.apiValue != provider.name) {
      return;
    }
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
    if (original?.guest != null) {
      // Guest receipts retain their separate report/claim ownership.
      if (_pendingRequestIds.contains(original!.requestId)) {
        await _handle(purchase);
      }
      return;
    }
    if (original != null &&
        _pendingRequestIds.contains(original.requestId) &&
        original.ownerUid == uid) {
      await _handle(purchase);
      return;
    }
    MembershipRestoreRecord? record;
    for (final candidate in _restoreRecords.values.toList().reversed) {
      if (candidate.ownerUid == uid &&
          candidate.receiptKey == membershipReceiptKey(purchase)) {
        if (candidate.needsRetry || !newOperation) record = candidate;
        break;
      }
    }
    record ??= MembershipRestoreRecord(
      requestId: newBillingAttemptId(),
      ownerUid: uid,
      purchase: purchase,
      product: _restoreProduct(purchase),
    );
    // A pending -> paid update keeps the original operation and receipt fields.
    if (!record.paid && purchase.status != BillingPurchaseStatus.pending) {
      record = record.copyWith(purchase: purchase);
    }
    await _saveRestore(record);
    await _processRestore(record);
  }

  Future<void> _processRestore(MembershipRestoreRecord record) async {
    if (_disposed ||
        restorePurchase == null ||
        await readLoginUid() != record.ownerUid) {
      return;
    }
    final session = _session;
    final previousResult = _restoreCatalogResult(record);
    try {
      if (record.product == null) {
        record = record.copyWith(product: _restoreProduct(record.purchase));
      }
      // Save even when the API cannot yet accept an unresolved plan.
      await _saveRestore(record);
      if (record.product == null) return;
      if (_disposed ||
          session != _session ||
          await readLoginUid() != record.ownerUid) {
        return;
      }
      if (record.reportStatus == null || record.reportStatus == 'accepted') {
        final report = await restorePurchase!(record.request);
        record = record.copyWith(
          reportStatus: report.status.name,
          reportId: report.reportId,
          reportReason: report.reason,
          finished: report.reason == 'account_mismatch' ? true : null,
        );
        await _saveRestore(record);
        if (_disposed ||
            session != _session ||
            await readLoginUid() != record.ownerUid) {
          return;
        }
      }
      if (record.reportStatus == 'completed') {
        try {
          await refreshWallet?.call();
        } catch (_) {}
      }
      if (provider == MembershipProvider.apple &&
          record.paid &&
          !record.finished) {
        await platform.finishAppleTransaction(record.purchase.transactionId);
        record = record.copyWith(finished: true);
        await _saveRestore(record);
      }
      if ((record.paid || record.reportStatus == 'rejected') &&
          (record.reportStatus == 'completed' ||
              record.reportStatus == 'rejected')) {
        await store.removeRestore(record.requestId);
        _pendingRestoreIds.remove(record.requestId);
      } else if (record.reportStatus == 'accepted') {
        _scheduleRetry();
      }
      if (!_busy) {
        _setState(switch (record.reportStatus) {
          'completed' => MembershipCheckoutState.completed,
          'accepted' => MembershipCheckoutState.accepted,
          'rejected' => MembershipCheckoutState.rejected,
          _ => MembershipCheckoutState.deferred,
        });
      }
    } catch (error) {
      if (!_busy) _setState(MembershipCheckoutState.deferred);
      _scheduleRetry();
      _log('restore report deferred', error);
    } finally {
      if (session == _session &&
          record.reportStatus != null &&
          previousResult != (record.reportStatus, record.reportReason)) {
        _catalogChanged();
      }
    }
  }

  (String?, String?) _restoreCatalogResult(MembershipRestoreRecord record) {
    if (record.reportStatus != null) {
      return (record.reportStatus, record.reportReason);
    }
    // A new restore operation can reconfirm an already reported transaction.
    // Compare its result with that transaction, not the new operation's null
    // status. Keep account and renewal boundaries intact.
    for (final previous in _restoreRecords.values.toList().reversed) {
      if (previous.ownerUid == record.ownerUid &&
          previous.receiptKey == record.receiptKey &&
          previous.purchase.transactionId == record.purchase.transactionId &&
          previous.reportStatus != null) {
        return (previous.reportStatus, previous.reportReason);
      }
    }
    final original = _purchaseForRestore(record.purchase);
    if (original != null &&
        original.guest == null &&
        original.ownerUid == record.ownerUid &&
        original.transactionId == record.purchase.transactionId) {
      return (original.reportStatus, original.reportReason);
    }
    return (null, null);
  }
}
