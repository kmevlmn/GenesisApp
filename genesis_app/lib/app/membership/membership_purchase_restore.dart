part of 'membership_purchase_service.dart';

extension _MembershipReportMigration on MembershipPurchaseService {
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

  Future<void> _removeRestore(MembershipRestoreRecord record) async {
    await store.removeRestore(record.requestId);
    _pendingRestoreIds.remove(record.requestId);
    _restoreRecords.remove(record.requestId);
  }

  Future<void> _processRestore(MembershipRestoreRecord record) async {
    // Keep a legacy request with a known plan and receipt for report retry,
    // including a failed request which never received a report status.
    // An unknown-plan store discovery cannot form a report request.
    if (record.product == null ||
        record.reportStatus == 'completed' ||
        record.reportStatus == 'rejected') {
      await _removeRestore(record);
      return;
    }
    if (_disposed || await readLoginUid() != record.ownerUid) return;
    final original = _purchaseForRestore(record.purchase);
    if (_records.containsKey(record.requestId) ||
        original?.transactionId == record.purchase.transactionId) {
      await _removeRestore(record);
      return;
    }
    final purchase = MembershipPurchaseRecord(
      requestId: record.requestId,
      ownerUid: record.ownerUid,
      accountUuid: record.purchase.obfuscatedAccountId ?? '',
      product: record.product!,
      transactionId: record.purchase.transactionId,
      originalTransactionId: record.purchase.originalTransactionId,
      purchaseToken: record.purchase.purchaseToken,
      state: record.paid ? 'restored' : record.purchase.status.name,
      reportStatus: record.reportStatus,
      reportId: record.reportId,
      reportReason: record.reportReason,
      finished: record.finished,
    );
    await store.save(purchase);
    await _save(purchase);
    await _removeRestore(record);
    await _report(purchase);
  }
}
