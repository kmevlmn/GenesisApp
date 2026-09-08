import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../../network/models/membership_product.dart';

class MembershipStorePrice {
  const MembershipStorePrice({
    required this.formattedPrice,
    required this.amountMicros,
    required this.currencyCode,
    required this.currencySymbol,
    this.hasIntroductoryPrice = false,
  });

  final String formattedPrice;
  final int amountMicros;
  final String currencyCode;
  final String currencySymbol;
  final bool hasIntroductoryPrice;
}

typedef MembershipPricesLoader =
    Future<Map<String, MembershipStorePrice>> Function(
      List<MembershipProduct> products,
    );

/// Read-only store lookup. It never launches, restores or completes purchases.
class MembershipProductStore {
  MembershipProductStore({InAppPurchase? inAppPurchase})
    : _store = inAppPurchase;
  final InAppPurchase? _store;

  Future<Map<String, MembershipStorePrice>> loadPrices(
    List<MembershipProduct> products,
  ) async {
    if (products.isEmpty) return {};
    final store = _store ?? InAppPurchase.instance;
    if (!await store.isAvailable()) return {};
    final response = await store.queryProductDetails(
      products.map((product) => product.storeProductId).toSet(),
    );
    // Preserve successfully returned products even when another product failed.
    return {
      for (final product in products)
        if (matchMembershipStorePrice(product, response.productDetails)
            case final price?)
          product.planCode: price,
    };
  }
}

MembershipStorePrice? matchMembershipStorePrice(
  MembershipProduct config,
  List<ProductDetails> products,
) {
  for (final product in products) {
    if (product.id != config.storeProductId) continue;
    if (config.provider == MembershipProvider.google) {
      if (product is! GooglePlayProductDetails) continue;
      final index = product.subscriptionIndex;
      final offers = product.productDetails.subscriptionOfferDetails;
      if (index == null ||
          offers == null ||
          index < 0 ||
          index >= offers.length) {
        continue;
      }
      final offer = offers[index];
      if (offer.basePlanId != config.basePlanId ||
          (offer.offerId ?? '') != config.offerId ||
          offer.installmentPlanDetails != null) {
        continue;
      }
      // The first phase may be a free trial. Show the recurring price explicitly.
      final recurring = offer.pricingPhases.where(
        (phase) =>
            phase.recurrenceMode == RecurrenceMode.infiniteRecurring &&
            (phase.billingPeriod == 'P${config.billingMonths}M' ||
                (config.isYearly && phase.billingPeriod == 'P1Y')),
      );
      if (recurring.length != 1) continue;
      final phase = recurring.single;
      if (phase.priceAmountMicros <= 0 ||
          phase.formattedPrice.isEmpty ||
          phase.priceCurrencyCode.isEmpty) {
        continue;
      }
      return MembershipStorePrice(
        formattedPrice: phase.formattedPrice,
        amountMicros: phase.priceAmountMicros,
        currencyCode: phase.priceCurrencyCode,
        // An introductory phase may use a different price string. The ISO
        // currency code remains unambiguous for calculated monthly equivalents.
        currencySymbol: product.currencySymbol,
        hasIntroductoryPrice: offer.pricingPhases.length > 1,
      );
    }
    if (product is GooglePlayProductDetails ||
        product.rawPrice <= 0 ||
        product.price.isEmpty ||
        product.currencyCode.isEmpty) {
      continue;
    }
    return MembershipStorePrice(
      formattedPrice: product.price,
      amountMicros: (product.rawPrice * 1000000).round(),
      currencyCode: product.currencyCode,
      currencySymbol: product.currencySymbol,
    );
  }
  return null;
}
