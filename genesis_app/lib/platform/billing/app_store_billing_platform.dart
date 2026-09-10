import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import '../../app/telemetry/storekit2_transaction_analytics.dart';
import 'billing_models.dart';
import 'google_play_billing_platform.dart';

class AppStoreBillingPlatform implements BillingPlatform {
  AppStoreBillingPlatform({
    InAppPurchase? inAppPurchase,
    StoreKit2TransactionAnalytics? transactionAnalytics,
  }) : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance,
       _transactionAnalytics =
           transactionAnalytics ?? StoreKit2TransactionAnalytics();

  final InAppPurchase _inAppPurchase;
  final StoreKit2TransactionAnalytics _transactionAnalytics;

  @override
  BillingProvider get provider => BillingProvider.appStore;

  @override
  Stream<List<BillingPurchase>> get purchaseStream {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const Stream<List<BillingPurchase>>.empty();
    }
    return _inAppPurchase.purchaseStream.map(
      (purchases) => purchases.map(_toBillingPurchase).toList(growable: false),
    );
  }

  @override
  Future<bool> isAvailable() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    return _inAppPurchase.isAvailable();
  }

  @override
  Future<List<BillingPurchase>> queryRecoverablePurchases() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const <BillingPurchase>[];
    }
    try {
      final transactions = await SK2Transaction.unfinishedTransactions();
      return transactions
          .map(
            (transaction) => BillingPurchase(
              provider: BillingProvider.appStore,
              productId: transaction.productId,
              purchaseToken: transaction.id,
              transactionId: transaction.id,
              originalTransactionId: transaction.originalId,
              signedTransaction: transaction.receiptData ?? '',
              originalJson:
                  transaction.receiptData ??
                  transaction.jsonRepresentation ??
                  '',
              purchaseTime: transaction.purchaseDate,
              status: BillingPurchaseStatus.purchased,
              obfuscatedAccountId: transaction.appAccountToken,
              errorCode: transaction.error?.code.toString(),
              errorMessage: transaction.error?.userInfo.toString(),
            ),
          )
          .toList(growable: false);
    } on Object catch (error) {
      throw BillingPlatformException('query_purchases_failed', '$error');
    }
  }

  @override
  void recordVerifiedPurchaseForAnalytics(BillingPurchase purchase) {
    if (purchase.provider != BillingProvider.appStore ||
        (purchase.status != BillingPurchaseStatus.purchased &&
            purchase.status != BillingPurchaseStatus.restored) ||
        purchase.transactionId.trim().isEmpty) {
      return;
    }
    unawaited(
      _transactionAnalytics.logVerifiedTransaction(purchase.transactionId),
    );
  }

  @override
  Future<BillingProductQueryResult> queryProduct(
    String storeProductId,
    BillingStoreProductType expectedType, {
    String? purchaseOptionId,
    String? offerId,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const BillingProductQueryResult.failure('platform_unavailable');
    }
    if (expectedType != BillingStoreProductType.inApp) {
      return const BillingProductQueryResult.failure(
        'unsupported_product_type',
      );
    }
    try {
      final response = await _inAppPurchase.queryProductDetails({
        storeProductId,
      });
      if (response.error != null) {
        debugPrint(
          '[Billing][AppStore] product query failed id=$storeProductId '
          'code=${response.error!.code}',
        );
        return BillingProductQueryResult.failure(response.error!.code);
      }
      for (final product in response.productDetails) {
        if (product.id != storeProductId) continue;
        debugPrint(
          '[Billing][AppStore] product ready id=$storeProductId '
          'price="${product.price}" rawPrice=${product.rawPrice} '
          'currency=${product.currencyCode}',
        );
        return BillingProductQueryResult.success(
          BillingStoreProduct(
            id: product.id,
            type: BillingStoreProductType.inApp,
            nativeProduct: product,
            formattedPrice: product.price,
            priceAmountMicros: (product.rawPrice * 1000000).round(),
            priceCurrencyCode: product.currencyCode,
          ),
        );
      }
      return const BillingProductQueryResult.failure('product_not_found');
    } on Object catch (error) {
      throw BillingPlatformException('query_product_failed', '$error');
    }
  }

  @override
  Future<bool> buyConsumable({
    required BillingStoreProduct product,
    required String billingAccountId,
    bool Function()? onStoreHandoff,
  }) async {
    final nativeProduct = product.nativeProduct;
    if (nativeProduct is! ProductDetails) {
      throw const BillingPlatformException('invalid_app_store_product');
    }
    if (product.type != BillingStoreProductType.inApp) {
      throw const BillingPlatformException('unsupported_product_type');
    }
    final accepted = await _inAppPurchase.buyConsumable(
      purchaseParam: Sk2PurchaseParam(
        productDetails: nativeProduct,
        applicationUserName: billingAccountId,
        onStoreHandoff: onStoreHandoff,
      ),
      // The StoreKit adapter requires this flag when launching an iOS
      // consumable. The client does not call completePurchase; settlement
      // remains server-owned after the purchase callback.
      autoConsume: true,
    );
    debugPrint('[Billing][AppStore] launch purchase accepted=$accepted');
    if (!accepted) {
      throw const BillingPlatformException('purchase_rejected');
    }
    return true;
  }
}

BillingPurchase _toBillingPurchase(PurchaseDetails purchase) {
  final status = switch (purchase.status) {
    PurchaseStatus.pending => BillingPurchaseStatus.pending,
    PurchaseStatus.purchased => BillingPurchaseStatus.purchased,
    PurchaseStatus.restored => BillingPurchaseStatus.restored,
    PurchaseStatus.canceled => BillingPurchaseStatus.canceled,
    PurchaseStatus.error => BillingPurchaseStatus.error,
  };
  final transactionId = purchase.purchaseID ?? '';
  return BillingPurchase(
    provider: BillingProvider.appStore,
    productId: purchase.productID,
    purchaseToken: transactionId,
    transactionId: transactionId,
    originalTransactionId: '',
    originalJson: purchase.verificationData.localVerificationData,
    signedTransaction: purchase is SK2PurchaseDetails
        ? purchase.verificationData.serverVerificationData
        : '',
    purchaseTime: purchase.transactionDate ?? '',
    status: status,
    obfuscatedAccountId: purchase is SK2PurchaseDetails
        ? purchase.appAccountToken
        : null,
    errorCode: purchase.error?.code,
    errorMessage: purchase.error?.message,
  );
}
