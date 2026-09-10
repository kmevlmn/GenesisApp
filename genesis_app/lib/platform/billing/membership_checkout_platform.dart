import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import '../../network/models/membership_product.dart';
import 'billing_models.dart';
import 'membership_product_store.dart';

abstract interface class MembershipCheckoutPlatform {
  Future<Object> prepare(MembershipProduct product);
  Future<bool> launch(
    Object product,
    String accountUuid, {
    bool Function()? onStoreHandoff,
  });
  Future<bool> isSubscription(String productId);
  Future<void> finishAppleTransaction(String transactionId);
}

class StoreMembershipCheckoutPlatform implements MembershipCheckoutPlatform {
  StoreMembershipCheckoutPlatform({
    InAppPurchase? store,
    Future<PurchasesResultWrapper> Function()? googleQuery,
  }) : _override = store,
       _googleQuery = googleQuery;
  final InAppPurchase? _override;
  final Future<PurchasesResultWrapper> Function()? _googleQuery;
  InAppPurchase get _store => _override ?? InAppPurchase.instance;
  final Map<String, bool> _types = {};

  @override
  Future<Object> prepare(MembershipProduct product) async {
    if (!await _store.isAvailable()) {
      throw const BillingPlatformException('store_unavailable');
    }
    final response = await _store.queryProductDetails({product.storeProductId});
    for (final detail in response.productDetails) {
      if (detail.id != product.storeProductId || !_subscription(detail)) {
        continue;
      }
      _types[detail.id] = true;
      if (matchMembershipStorePrice(product, [detail]) == null) continue;
      if (detail is GooglePlayProductDetails &&
          detail.offerToken?.isNotEmpty != true) {
        continue;
      }
      if (detail is GooglePlayProductDetails &&
          product.upgradePurchaseToken != null) {
        return _GoogleMembershipUpgrade(
          product: detail,
          accountUuid: product.upgradeAccountUuid!,
          previousPurchase: await _previousGooglePurchase(product),
        );
      }
      return detail;
    }
    throw const BillingPlatformException('membership_product_not_found');
  }

  Future<GooglePlayPurchaseDetails> _previousGooglePurchase(
    MembershipProduct product,
  ) async {
    final result =
        await (_googleQuery?.call() ??
            _store
                .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
                .querySubscriptionPurchases());
    if (result.responseCode != BillingResponse.ok) {
      throw BillingPlatformException(
        'membership_upgrade_query_failed',
        result.responseCode.name,
      );
    }
    final matches = result.purchasesList
        .where(
          (purchase) => purchase.purchaseToken == product.upgradePurchaseToken,
        )
        .toList();
    if (matches.length != 1 ||
        !matches.single.products.contains(product.storeProductId)) {
      throw const BillingPlatformException(
        'membership_upgrade_purchase_missing',
      );
    }
    final purchase = matches.single;
    if (purchase.obfuscatedAccountId?.toLowerCase() !=
        product.upgradeAccountUuid) {
      throw const BillingPlatformException(
        'membership_upgrade_account_mismatch',
      );
    }
    if (purchase.purchaseState != PurchaseStateWrapper.purchased ||
        !purchase.isAcknowledged ||
        purchase.pendingPurchaseUpdate != null) {
      throw const BillingPlatformException('membership_upgrade_not_ready');
    }
    return GooglePlayPurchaseDetails.fromPurchase(
      purchase,
    ).singleWhere((detail) => detail.productID == product.storeProductId);
  }

  @override
  Future<bool> launch(
    Object product,
    String accountUuid, {
    bool Function()? onStoreHandoff,
  }) async {
    final upgrade = product is _GoogleMembershipUpgrade ? product : null;
    if (upgrade != null) {
      if (accountUuid != upgrade.accountUuid) {
        throw const BillingPlatformException(
          'membership_upgrade_account_mismatch',
        );
      }
      product = upgrade.product;
    }
    if (product is! ProductDetails || !_subscription(product)) {
      throw const BillingPlatformException('invalid_membership_product');
    }
    final param = product is GooglePlayProductDetails
        ? GooglePlayPurchaseParam(
            productDetails: product,
            offerToken: product.offerToken,
            applicationUserName: accountUuid,
            changeSubscriptionParam: upgrade == null
                ? null
                : ChangeSubscriptionParam(
                    oldPurchaseDetails: upgrade.previousPurchase,
                    replacementMode: ReplacementMode.chargeFullPrice,
                  ),
          )
        : Sk2PurchaseParam(
            productDetails: product,
            applicationUserName: accountUuid,
            onStoreHandoff: onStoreHandoff,
          );
    final accepted = await _store.buyNonConsumable(purchaseParam: param);
    // Play returns when its purchase UI is launched; StoreKit calls back from
    // native preparation before waiting for the user's purchase result.
    if (accepted && product is GooglePlayProductDetails) {
      onStoreHandoff?.call();
    }
    return accepted;
  }

  @override
  Future<bool> isSubscription(String productId) async {
    final cached = _types[productId];
    if (cached != null) return cached;
    final response = await _store.queryProductDetails({productId});
    final products = response.productDetails.where((p) => p.id == productId);
    if (products.isEmpty) {
      throw const BillingPlatformException('unknown_purchase_type');
    }
    return _types[productId] = products.any(_subscription);
  }

  bool _subscription(ProductDetails product) => switch (product) {
    GooglePlayProductDetails() =>
      product.productDetails.productType == ProductType.subs,
    AppStoreProduct2Details() =>
      product.sk2Product.type == SK2ProductType.autoRenewable,
    AppStoreProductDetails() => product.skProduct.subscriptionPeriod != null,
    _ => false,
  };

  @override
  Future<void> finishAppleTransaction(String transactionId) =>
      SK2Transaction.finish(int.parse(transactionId));
}

class _GoogleMembershipUpgrade {
  const _GoogleMembershipUpgrade({
    required this.product,
    required this.accountUuid,
    required this.previousPurchase,
  });

  final GooglePlayProductDetails product;
  final String accountUuid;
  final GooglePlayPurchaseDetails previousPurchase;
}
