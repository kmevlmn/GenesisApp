import 'dart:convert';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import '../../network/models/membership_product.dart';
import '../../network/models/membership_purchase.dart';
import '../../network/models/membership_claim.dart';
import 'billing_models.dart';
import 'membership_store_purchase.dart';

/// Read-only store recovery. It does not emit into the shared Gems stream.
class MembershipStoreRestorer {
  MembershipStoreRestorer({
    required this.provider,
    Future<PurchasesResultWrapper> Function()? googleQuery,
    Future<List<SK2Transaction>> Function()? appleQuery,
    DateTime Function()? now,
  }) : _googleQuery = googleQuery ?? _queryGoogle,
       _appleQuery = appleQuery ?? SK2Transaction.transactions,
       _now = now ?? DateTime.now;

  final MembershipProvider provider;
  final Future<PurchasesResultWrapper> Function() _googleQuery;
  final Future<List<SK2Transaction>> Function() _appleQuery;
  final DateTime Function() _now;

  /// Finds original purchase identities without a local catalog or a payment
  /// prompt. This lookup does not report/claim/finish transactions or emit Gems
  /// callbacks. Backend ownership checks still do not establish entitlement.
  Future<List<MembershipStorePurchase>> discoverGuestPurchases() async {
    final purchases = <MembershipStorePurchase>[];

    if (provider == MembershipProvider.google) {
      final result = await _googleQuery();
      if (result.responseCode != BillingResponse.ok) {
        throw BillingPlatformException(
          'membership_guest_query_failed',
          result.responseCode.name,
        );
      }
      // querySubscriptionPurchases queries SUBS only. Pending payments do not
      // prove a completed purchase; no current base plan/expiry is invented.
      for (final purchase in result.purchasesList) {
        if (purchase.purchaseState == PurchaseStateWrapper.purchased &&
            isMembershipAccountUuid(purchase.obfuscatedAccountId ?? '') &&
            purchase.purchaseToken.isNotEmpty) {
          for (final id in purchase.products) {
            purchases.add(
              MembershipStorePurchase(
                purchase: BillingPurchase(
                  provider: BillingProvider.googlePlay,
                  productId: id,
                  purchaseToken: purchase.purchaseToken,
                  transactionId: purchase.orderId,
                  originalTransactionId: '',
                  originalJson: '',
                  purchaseTime: purchase.purchaseTime.toString(),
                  status: BillingPurchaseStatus.restored,
                  obfuscatedAccountId: purchase.obfuscatedAccountId!
                      .toLowerCase(),
                ),
              ),
            );
          }
        }
      }
    } else {
      final latest = <String, SK2Transaction>{};
      for (final transaction in await _appleQuery()) {
        // Consumable Gems do not have a subscription expiration date.
        if (transaction.error != null || transaction.expirationDate == null) {
          continue;
        }
        final key = transaction.originalId.isEmpty
            ? transaction.id
            : transaction.originalId;
        final previous = latest[key];
        if (previous == null || _compare(transaction, previous) > 0) {
          latest[key] = transaction;
        }
      }
      for (final transaction in latest.values) {
        final expires = int.tryParse(transaction.expirationDate!);
        if (expires == null || expires <= _now().millisecondsSinceEpoch) {
          continue;
        }
        final raw = transaction.jsonRepresentation;
        if (raw != null) {
          final json = jsonDecode(raw);
          if (json is! Map) {
            throw const BillingPlatformException(
              'membership_guest_receipt_invalid',
            );
          }
          if (json['revocationDate'] != null || json['isUpgraded'] == true) {
            continue;
          }
        }
        if (!isMembershipAccountUuid(transaction.appAccountToken ?? '')) {
          continue;
        }
        purchases.add(
          MembershipStorePurchase(
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              expires,
              isUtc: true,
            ),
            purchase: BillingPurchase(
              provider: BillingProvider.appStore,
              productId: transaction.productId,
              purchaseToken: transaction.id,
              transactionId: transaction.id,
              originalTransactionId: transaction.originalId,
              originalJson: '',
              purchaseTime: transaction.purchaseDate,
              status: BillingPurchaseStatus.restored,
              obfuscatedAccountId: transaction.appAccountToken!.toLowerCase(),
              signedTransaction: transaction.receiptData ?? '',
            ),
          ),
        );
      }
    }
    return purchases;
  }

  static Future<PurchasesResultWrapper> _queryGoogle() => InAppPurchase.instance
      .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
      .querySubscriptionPurchases();

  /// Look up the exact transaction, including finished purchases after restart.
  /// Do not replace a receipt with the latest renewal's different transaction.
  Future<String> signedTransaction(MembershipClaimRequest request) async {
    final uuid = request.guest.accountUuid;
    if (provider != MembershipProvider.apple ||
        request.provider != MembershipProvider.apple) {
      throw const BillingPlatformException('invalid_guest_apple_request');
    }
    for (final transaction in await _appleQuery()) {
      if (transaction.id == request.transactionId &&
          transaction.productId == request.storeProductId &&
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
