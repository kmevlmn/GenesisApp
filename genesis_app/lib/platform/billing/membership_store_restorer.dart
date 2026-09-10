import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import '../../network/models/membership_product.dart';
import '../../network/models/membership_purchase.dart';
import 'billing_models.dart';

/// Read-only store recovery. It does not emit into the shared Gems stream.
class MembershipStoreRestorer {
  MembershipStoreRestorer({
    required this.provider,
    Future<PurchasesResultWrapper> Function()? googleQuery,
    Future<List<SK2Transaction>> Function()? appleQuery,
  }) : _googleQuery = googleQuery ?? _queryGoogle,
       _appleQuery = appleQuery ?? SK2Transaction.transactions;

  final MembershipProvider provider;
  final Future<PurchasesResultWrapper> Function() _googleQuery;
  final Future<List<SK2Transaction>> Function() _appleQuery;

  static Future<PurchasesResultWrapper> _queryGoogle() => InAppPurchase.instance
      .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
      .querySubscriptionPurchases();

  /// Look up the exact transaction, including finished purchases after restart.
  /// Do not replace a receipt with the latest renewal's different transaction.
  Future<String> signedTransaction(MembershipPurchaseRequest request) async {
    final uuid = request.guest?.accountUuid;
    if (provider != MembershipProvider.apple || uuid == null) {
      throw const BillingPlatformException('invalid_guest_apple_request');
    }
    for (final transaction in await _appleQuery()) {
      if (transaction.id == request.transactionId &&
          transaction.productId == request.product.storeProductId &&
          transaction.appAccountToken?.toLowerCase() == uuid.toLowerCase() &&
          transaction.error == null &&
          transaction.receiptData?.isNotEmpty == true) {
        return transaction.receiptData!;
      }
    }
    throw const BillingPlatformException(
      'membership_signed_transaction_missing',
    );
  }

  Future<List<BillingPurchase>> query(Set<String> productIds) async {
    if (productIds.isEmpty) return [];
    if (provider == MembershipProvider.google) {
      final result = await _googleQuery();
      if (result.responseCode != BillingResponse.ok) {
        throw BillingPlatformException(
          'membership_restore_query_failed',
          result.responseCode.name,
        );
      }
      return [
        for (final purchase in result.purchasesList)
          for (final id in purchase.products.where(productIds.contains))
            if (purchase.purchaseState == PurchaseStateWrapper.purchased ||
                purchase.purchaseState == PurchaseStateWrapper.pending)
              BillingPurchase(
                provider: BillingProvider.googlePlay,
                productId: id,
                purchaseToken: purchase.purchaseToken,
                transactionId: purchase.orderId,
                originalTransactionId: '',
                originalJson: '',
                purchaseTime: purchase.purchaseTime.toString(),
                status: purchase.purchaseState == PurchaseStateWrapper.pending
                    ? BillingPurchaseStatus.pending
                    : BillingPurchaseStatus.restored,
                obfuscatedAccountId: purchase.obfuscatedAccountId,
              ),
      ];
    }
    // Finished subscriptions must be recoverable too; unfinished-only is for Gems.
    // Keep the newest transaction per subscription chain, including expired chains.
    final latest = <String, SK2Transaction>{};
    for (final transaction in await _appleQuery()) {
      if (!productIds.contains(transaction.productId)) continue;
      final key = transaction.originalId.isEmpty
          ? transaction.id
          : transaction.originalId;
      final previous = latest[key];
      if (previous == null || _compare(transaction, previous) > 0) {
        latest[key] = transaction;
      }
    }
    return latest.values
        .map(
          (transaction) => BillingPurchase(
            provider: BillingProvider.appStore,
            productId: transaction.productId,
            purchaseToken: transaction.id,
            transactionId: transaction.id,
            originalTransactionId: transaction.originalId,
            signedTransaction: transaction.receiptData ?? '',
            originalJson: '',
            purchaseTime: transaction.purchaseDate,
            status: BillingPurchaseStatus.restored,
            obfuscatedAccountId: transaction.appAccountToken,
          ),
        )
        .toList();
  }

  int _compare(SK2Transaction a, SK2Transaction b) {
    final time = (int.tryParse(a.purchaseDate) ?? 0).compareTo(
      int.tryParse(b.purchaseDate) ?? 0,
    );
    return time != 0
        ? time
        : (BigInt.tryParse(a.id) ?? BigInt.zero).compareTo(
            BigInt.tryParse(b.id) ?? BigInt.zero,
          );
  }
}
