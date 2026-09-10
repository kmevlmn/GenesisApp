part of 'membership_purchase_service.dart';

extension _MembershipReceiptReconciliation on MembershipPurchaseService {
  Future<void> _reconcileMissingReceipts(
    String? uid, {
    bool Function()? canContinue,
  }) async {
    final session = _session;
    bool current() =>
        !_disposed && session == _session && (canContinue?.call() ?? true);
    bool belongs(MembershipPurchaseRecord record) => record.guest == null
        ? record.ownerUid == uid
        : uid == null || _guestClaims[record.guest!.guestId]?.ownerUid == uid;
    final missing = _records.values
        .where(
          (r) =>
              r.product.provider == provider &&
              _pendingRequestIds.contains(r.requestId) &&
              r.needsReceiptRecovery &&
              belongs(r),
        )
        .toList();
    if (missing.isEmpty || !current()) return;
    try {
      final ids = missing.map((r) => r.product.storeProductId).toSet();
      // Use the subscription-only query in production. An unsuccessful query
      // must never clear an outstanding purchase signal.
      final purchases = queryRestorePurchases != null
          ? await queryRestorePurchases!(ids)
          : await queryPurchases();
      if (!current() || await readLoginUid() != uid) return;
      await _serialize(() async {
        for (final snapshot in missing) {
          if (!current() || await readLoginUid() != uid) return;
          var record = _records[snapshot.requestId];
          if (record == null || !record.needsReceiptRecovery) continue;
          final matches = purchases
              .where(
                (p) =>
                    p.provider.apiValue == provider.name &&
                    p.productId == record!.product.storeProductId &&
                    (p.status == BillingPurchaseStatus.purchased ||
                        p.status == BillingPurchaseStatus.restored ||
                        p.status == BillingPurchaseStatus.pending) &&
                    (p.obfuscatedAccountId?.isNotEmpty != true ||
                        p.obfuscatedAccountId!.toLowerCase() ==
                            record.accountUuid.toLowerCase()),
              )
              .toList();
          for (final purchase in matches) {
            if (!current()) return;
            await _handle(purchase);
          }
          // A callback may have persisted a real receipt during the query or
          // report. Re-read before changing only the unsubstantiated signal.
          record = _records[snapshot.requestId];
          if (!current() ||
              record == null ||
              !record.needsReceiptRecovery ||
              matches.isNotEmpty ||
              record.transactionId.isNotEmpty ||
              record.purchaseToken.isNotEmpty) {
            continue;
          }
          // Successful store lookup found no matching purchase. Retain the
          // attempt/guest identity for late callbacks without calling it paid.
          await _save(record.copyWith(state: 'receipt_missing'));
        }
      });
    } catch (error) {
      _scheduleRetry();
      _log('missing receipt recovery deferred', error);
      throw const MembershipPurchaseBlocked('purchase_processing');
    }
  }
}
