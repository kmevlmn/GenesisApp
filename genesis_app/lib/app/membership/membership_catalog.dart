import 'package:flutter/foundation.dart';

import '../../network/models/membership_product.dart';
import '../../platform/billing/membership_product_store.dart';

class MembershipLoginRequired implements Exception {}

class MembershipPlatformUnavailable implements Exception {}

class MembershipOffer {
  const MembershipOffer({required this.product, this.price});
  final MembershipProduct product;
  final MembershipStorePrice? price;
  bool get available => product.saleEnabled && price != null;
}

typedef MembershipCatalogLoader = Future<List<MembershipOffer>> Function();

class MembershipCatalog {
  MembershipCatalog({
    required this.readLoginUid,
    required this.loadProducts,
    required this.loadPrices,
    required this.provider,
  });

  final Future<String?> Function() readLoginUid;
  final Future<MembershipProductList> Function(MembershipProvider provider)
  loadProducts;
  final MembershipPricesLoader loadPrices;
  final MembershipProvider? provider;

  static MembershipProvider? get currentProvider => kIsWeb
      ? null
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => MembershipProvider.google,
          TargetPlatform.iOS => MembershipProvider.apple,
          _ => null,
        };

  Future<List<MembershipOffer>> load() async {
    if (await readLoginUid() == null) throw MembershipLoginRequired();
    final platform = provider;
    if (platform == null) throw MembershipPlatformUnavailable();
    final products = (await loadProducts(platform)).products.toList();
    if (products.any((product) => product.provider != platform) ||
        products.map((product) => product.planCode).toSet().length !=
            products.length) {
      throw const FormatException('Invalid membership catalog');
    }
    products.sort((a, b) => b.billingMonths.compareTo(a.billingMonths));
    Map<String, MembershipStorePrice> prices;
    try {
      prices = products.isEmpty
          ? {}
          : await loadPrices(products).timeout(const Duration(seconds: 15));
    } catch (_) {
      prices = {};
    }
    return [
      for (final product in products)
        MembershipOffer(product: product, price: prices[product.planCode]),
    ];
  }
}

int? membershipYearlySavings(
  MembershipOffer yearly,
  List<MembershipOffer> offers,
) {
  if (yearly.price == null ||
      !yearly.product.isYearly ||
      yearly.price!.hasIntroductoryPrice) {
    return null;
  }
  for (final monthly in offers) {
    if (monthly.price == null ||
        monthly.product.isYearly ||
        monthly.price!.hasIntroductoryPrice ||
        monthly.price!.currencyCode != yearly.price!.currencyCode ||
        monthly.product.monthlyGemsCent != yearly.product.monthlyGemsCent) {
      continue;
    }
    final fullYear = monthly.price!.amountMicros * 12;
    if (fullYear <= yearly.price!.amountMicros) return null;
    final savings = ((fullYear - yearly.price!.amountMicros) * 100 / fullYear)
        .round();
    return savings > 0 && savings < 100 ? savings : null;
  }
  return null;
}
