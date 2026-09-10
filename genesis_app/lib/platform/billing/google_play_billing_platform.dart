import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'billing_models.dart';

abstract interface class BillingPlatform {
  BillingProvider get provider;

  Stream<List<BillingPurchase>> get purchaseStream;

  Future<bool> isAvailable();

  Future<List<BillingPurchase>> queryRecoverablePurchases();

  /// Records a store-verified purchase using the platform's native Analytics
  /// integration. Implementations must be best-effort and non-blocking.
  void recordVerifiedPurchaseForAnalytics(BillingPurchase purchase);

  Future<BillingProductQueryResult> queryProduct(
    String storeProductId,
    BillingStoreProductType expectedType, {
    String? purchaseOptionId,
    String? offerId,
  });

  Future<bool> buyConsumable({
    required BillingStoreProduct product,
    required String billingAccountId,
    bool Function()? onStoreHandoff,
  });
}

class GooglePlayBillingPlatform implements BillingPlatform {
  GooglePlayBillingPlatform({InAppPurchase? inAppPurchase})
    : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;

  @override
  BillingProvider get provider => BillingProvider.googlePlay;

  @override
  Stream<List<BillingPurchase>> get purchaseStream {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const Stream<List<BillingPurchase>>.empty();
    }
    return _inAppPurchase.purchaseStream.map(
      (purchases) => purchases.map(_toBillingPurchase).toList(growable: false),
    );
  }

  @override
  Future<bool> isAvailable() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return _inAppPurchase.isAvailable();
  }

  @override
  Future<List<BillingPurchase>> queryRecoverablePurchases() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const <BillingPurchase>[];
    }
    try {
      final addition = _inAppPurchase
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await addition.queryPastPurchases();
      final error = response.error;
      if (error != null) {
        throw BillingPlatformException('query_purchases_failed', error.code);
      }
      return response.pastPurchases
          .map(_toBillingPurchase)
          .toList(growable: false);
    } on BillingPlatformException {
      rethrow;
    } on Object catch (error) {
      throw BillingPlatformException('query_purchases_failed', '$error');
    }
  }

  @override
  void recordVerifiedPurchaseForAnalytics(BillingPurchase purchase) {
    // Google Play purchases are collected automatically after the Analytics
    // property is linked to Play. Manually logging would double-count them.
  }

  @override
  Future<BillingProductQueryResult> queryProduct(
    String storeProductId,
    BillingStoreProductType expectedType, {
    String? purchaseOptionId,
    String? offerId,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const BillingProductQueryResult.failure('unknown');
    }
    try {
      final productType = switch (expectedType) {
        BillingStoreProductType.inApp => ProductType.inapp,
        BillingStoreProductType.subscription => ProductType.subs,
      };
      final addition = _inAppPurchase
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await addition.queryProductDetails(
        productId: storeProductId,
        productType: productType,
      );
      if (response.billingResult.responseCode != BillingResponse.ok) {
        final errorCode = googlePlayBillingQueryErrorCode(
          response.billingResult.responseCode,
        );
        debugPrint(
          '[Billing] product query failed id=$storeProductId '
          'response=${response.billingResult.responseCode.name} '
          'code=$errorCode message=${response.billingResult.debugMessage}',
        );
        return BillingProductQueryResult.failure(errorCode);
      }
      final products = response.productDetailsList.expand(
        GooglePlayProductDetails.fromProductDetails,
      );
      for (final product in products) {
        if (product.id != storeProductId) continue;
        final type = switch (product.productDetails.productType) {
          ProductType.inapp => BillingStoreProductType.inApp,
          ProductType.subs => BillingStoreProductType.subscription,
        };
        if (type != expectedType) continue;
        _logGoogleProductDetails(product);
        final requestedPurchaseOptionId = purchaseOptionId?.trim() ?? '';
        final requestedOfferId = offerId?.trim() ?? '';
        final shouldMatchDiscount =
            requestedPurchaseOptionId.isNotEmpty && requestedOfferId.isNotEmpty;
        final selectedOffer = selectGooglePlayOneTimeOffer(
          product.productDetails.oneTimePurchaseOfferDetailsList,
          purchaseOptionId: shouldMatchDiscount
              ? requestedPurchaseOptionId
              : null,
          offerId: shouldMatchDiscount ? requestedOfferId : null,
        );
        if (type == BillingStoreProductType.inApp &&
            shouldMatchDiscount &&
            (selectedOffer == null ||
                selectedOffer.offerToken?.trim().isEmpty != false)) {
          debugPrint(
            '[Billing] requested offer unavailable, fallback to base price '
            'id=$storeProductId '
            'purchaseOption=$purchaseOptionId offer=$offerId '
            'availableOffers=${product.productDetails.oneTimePurchaseOfferDetailsList?.length ?? 0}',
          );
        }
        debugPrint(
          '[Billing] product ready id=$storeProductId '
          'type=${type.value} purchaseOption=${selectedOffer?.purchaseOptionId} '
          'offer=${selectedOffer?.offerId} '
          'hasOfferToken=${selectedOffer?.offerToken?.isNotEmpty == true}',
        );
        return BillingProductQueryResult.success(
          BillingStoreProduct(
            id: product.id,
            type: type,
            nativeProduct: product,
            purchaseOptionId: selectedOffer?.purchaseOptionId,
            offerId: selectedOffer?.offerId,
            offerToken: selectedOffer?.offerToken,
            formattedPrice: selectedOffer?.formattedPrice ?? product.price,
            priceAmountMicros:
                selectedOffer?.priceAmountMicros ??
                (product.rawPrice * 1000000).round(),
            priceCurrencyCode:
                selectedOffer?.priceCurrencyCode ?? product.currencyCode,
          ),
        );
      }
      for (final unfetched in response.unfetchedProductList) {
        if (unfetched.productId != storeProductId) continue;
        final errorCode = googlePlayUnfetchedProductErrorCode(
          unfetched.statusCode,
        );
        debugPrint(
          '[Billing] product not fetched id=$storeProductId '
          'status=${unfetched.statusCode} code=$errorCode',
        );
        return BillingProductQueryResult.failure(errorCode);
      }
      return const BillingProductQueryResult.failure('unknown');
    } on Object catch (error) {
      throw BillingPlatformException('unknown', '$error');
    }
  }

  @override
  Future<bool> buyConsumable({
    required BillingStoreProduct product,
    required String billingAccountId,
    bool Function()? onStoreHandoff,
  }) async {
    final nativeProduct = product.nativeProduct;
    if (nativeProduct is! GooglePlayProductDetails) {
      throw const BillingPlatformException('invalid_google_product');
    }
    if (product.type != BillingStoreProductType.inApp) {
      throw const BillingPlatformException('unsupported_product_type');
    }
    final purchaseParam = GooglePlayPurchaseParam(
      productDetails: nativeProduct,
      applicationUserName: billingAccountId,
      offerToken: product.offerToken,
    );
    final platform = InAppPurchasePlatform.instance;
    if (platform is InAppPurchaseAndroidPlatform) {
      debugPrint(
        '[Billing] launch purchase id=${nativeProduct.id} '
        'offer=${product.offerId} '
        'hasOfferToken=${product.offerToken?.isNotEmpty == true} '
        'platform=${platform.runtimeType}',
      );
      final result = await platform.launchBillingFlow(
        product: nativeProduct.id,
        offerToken: product.offerToken,
        accountId: billingAccountId,
      );
      if (result.responseCode != BillingResponse.ok) {
        throw BillingPlatformException(
          'purchase_${result.responseCode.name}',
          result.debugMessage ?? '',
        );
      }
      onStoreHandoff?.call();
      return true;
    }

    final accepted = await _inAppPurchase.buyConsumable(
      purchaseParam: purchaseParam,
      autoConsume: false,
    );
    debugPrint(
      '[Billing] launch purchase accepted=$accepted '
      'platform=${platform.runtimeType}',
    );
    if (!accepted) {
      throw const BillingPlatformException('purchase_rejected');
    }
    onStoreHandoff?.call();
    return true;
  }
}

@visibleForTesting
String googlePlayUnfetchedProductErrorCode(int statusCode) {
  return switch (statusCode) {
    2 => 'invalid_product_id_format',
    3 => 'product_not_found',
    4 => 'no_eligible_offer',
    _ => 'unknown',
  };
}

@visibleForTesting
String googlePlayBillingQueryErrorCode(BillingResponse responseCode) {
  return switch (responseCode) {
    BillingResponse.serviceTimeout => 'service_timeout',
    BillingResponse.featureNotSupported => 'feature_not_supported',
    BillingResponse.serviceDisconnected => 'service_disconnected',
    BillingResponse.ok => 'unknown',
    BillingResponse.userCanceled => 'user_canceled',
    BillingResponse.serviceUnavailable => 'service_unavailable',
    BillingResponse.billingUnavailable => 'billing_unavailable',
    BillingResponse.itemUnavailable => 'item_unavailable',
    BillingResponse.developerError => 'developer_error',
    BillingResponse.error => 'error',
    BillingResponse.itemAlreadyOwned => 'item_already_owned',
    BillingResponse.itemNotOwned => 'item_not_owned',
    BillingResponse.networkError => 'network_error',
  };
}

void _logGoogleProductDetails(GooglePlayProductDetails product) {
  final details = product.productDetails;
  debugPrint(
    '[Billing][ProductDetails] '
    'id=${details.productId} '
    'type=${details.productType} '
    'title="${details.title}" '
    'name="${details.name}" '
    'description="${details.description}" '
    'price="${product.price}" '
    'rawPrice=${product.rawPrice} '
    'currency=${product.currencyCode}',
  );

  final legacyOffer = details.oneTimePurchaseOfferDetails;
  debugPrint(
    '[Billing][ProductDetails] legacyOneTimeOffer='
    '${_formatOneTimeOffer(legacyOffer)}',
  );

  final oneTimeOffers =
      details.oneTimePurchaseOfferDetailsList ??
      const <OneTimePurchaseOfferDetailsWrapper>[];
  debugPrint(
    '[Billing][ProductDetails] oneTimeOffers.count=${oneTimeOffers.length}',
  );
  for (var index = 0; index < oneTimeOffers.length; index++) {
    debugPrint(
      '[Billing][ProductDetails] oneTimeOffer[$index]='
      '${_formatOneTimeOffer(oneTimeOffers[index])}',
    );
  }

  final subscriptionOffers =
      details.subscriptionOfferDetails ??
      const <SubscriptionOfferDetailsWrapper>[];
  debugPrint(
    '[Billing][ProductDetails] subscriptionOffers.count='
    '${subscriptionOffers.length}',
  );
  for (var index = 0; index < subscriptionOffers.length; index++) {
    final offer = subscriptionOffers[index];
    debugPrint(
      '[Billing][ProductDetails] subscriptionOffer[$index] '
      'basePlanId=${offer.basePlanId} offerId=${offer.offerId} '
      'offerToken=${_maskBillingToken(offer.offerIdToken)} '
      'tags=${offer.offerTags} '
      'pricingPhases=${offer.pricingPhases.map(_formatPricingPhase).toList()}',
    );
  }
}

String _formatOneTimeOffer(OneTimePurchaseOfferDetailsWrapper? offer) {
  if (offer == null) return 'null';
  return '{'
      'formattedPrice="${offer.formattedPrice}", '
      'priceAmountMicros=${offer.priceAmountMicros}, '
      'currency=${offer.priceCurrencyCode}, '
      'purchaseOptionId=${offer.purchaseOptionId}, '
      'offerId=${offer.offerId}, '
      'offerToken=${_maskBillingToken(offer.offerToken)}'
      '}';
}

String _formatPricingPhase(PricingPhaseWrapper phase) {
  return '{'
      'price="${phase.formattedPrice}", '
      'priceAmountMicros=${phase.priceAmountMicros}, '
      'currency=${phase.priceCurrencyCode}, '
      'period=${phase.billingPeriod}, '
      'cycleCount=${phase.billingCycleCount}, '
      'recurrence=${phase.recurrenceMode}'
      '}';
}

String _maskBillingToken(String? token) {
  final value = token?.trim() ?? '';
  if (value.isEmpty) return 'null';
  if (value.length <= 8) return '<redacted length=${value.length}>';
  return '<redacted ${value.substring(0, 4)}...'
      '${value.substring(value.length - 4)} length=${value.length}>';
}

OneTimePurchaseOfferDetailsWrapper? selectGooglePlayOneTimeOffer(
  List<OneTimePurchaseOfferDetailsWrapper>? offers, {
  String? purchaseOptionId,
  String? offerId,
}) {
  final requestedPurchaseOptionId = purchaseOptionId?.trim() ?? '';
  final requestedOfferId = offerId?.trim() ?? '';
  final availableOffers =
      offers ?? const <OneTimePurchaseOfferDetailsWrapper>[];
  if (requestedPurchaseOptionId.isEmpty || requestedOfferId.isEmpty) {
    return null;
  }
  for (final offer in availableOffers) {
    if (offer.purchaseOptionId != requestedPurchaseOptionId) {
      continue;
    }
    if (offer.offerId != requestedOfferId) {
      continue;
    }
    if (offer.offerToken?.trim().isEmpty != false) {
      continue;
    }
    return offer;
  }
  return null;
}

BillingPurchase _toBillingPurchase(PurchaseDetails purchase) {
  final status = switch (purchase.status) {
    PurchaseStatus.pending => BillingPurchaseStatus.pending,
    PurchaseStatus.purchased => BillingPurchaseStatus.purchased,
    PurchaseStatus.restored => BillingPurchaseStatus.restored,
    PurchaseStatus.canceled => BillingPurchaseStatus.canceled,
    PurchaseStatus.error => BillingPurchaseStatus.error,
  };
  final googlePurchase = purchase is GooglePlayPurchaseDetails
      ? purchase.billingClientPurchase
      : null;
  return BillingPurchase(
    provider: BillingProvider.googlePlay,
    productId: purchase.productID,
    purchaseToken: purchase.verificationData.serverVerificationData,
    transactionId: purchase.purchaseID ?? googlePurchase?.orderId ?? '',
    originalTransactionId: '',
    originalJson:
        googlePurchase?.originalJson ??
        purchase.verificationData.localVerificationData,
    purchaseTime: purchase.transactionDate ?? '',
    status: status,
    obfuscatedAccountId: googlePurchase?.obfuscatedAccountId,
    errorCode: googlePlayPurchaseErrorCode(
      code: purchase.error?.code,
      message: purchase.error?.message,
    ),
    errorMessage: purchase.error?.message,
  );
}

String? googlePlayPurchaseErrorCode({String? code, String? message}) {
  final rawMessage = message?.trim() ?? '';
  const responsePrefix = 'BillingResponse.';
  if (rawMessage.startsWith(responsePrefix)) {
    return _toSnakeCase(rawMessage.substring(responsePrefix.length));
  }

  final rawCode = code?.trim() ?? '';
  if (rawCode.isEmpty) return null;
  return _toSnakeCase(rawCode);
}

String _toSnakeCase(String value) {
  return value
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '')
      .toLowerCase();
}
