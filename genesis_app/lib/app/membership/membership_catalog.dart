import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../network/models/membership_product.dart';

class MembershipPlatformUnavailable implements Exception {}

class MembershipOffer {
  const MembershipOffer({required this.product});
  final MembershipProduct product;
  MembershipDisplayPrice? get price => product.priceAmount == null
      ? null
      : MembershipDisplayPrice(
          amountCent: product.priceAmount!,
          currencyCode: product.priceCurrencyCode,
        );
  bool get available => price != null;
}

class MembershipDisplayPrice {
  const MembershipDisplayPrice({
    required this.amountCent,
    required this.currencyCode,
  });
  final int amountCent;
  final String currencyCode;

  String get formattedPrice => NumberFormat.simpleCurrency(
    name: currencyCode,
    decimalDigits: 2,
  ).format(amountCent / 100);
}

class MembershipCatalogData {
  const MembershipCatalogData({this.offers = const []});
  final List<MembershipOffer> offers;
}

typedef MembershipCatalogLoader = Future<MembershipCatalogData> Function();

class MembershipCatalog {
  MembershipCatalog({required this.loadProducts, required this.provider});

  final Future<MembershipProductList> Function(MembershipProvider provider)
  loadProducts;
  final MembershipProvider? provider;

  static MembershipProvider? get currentProvider => kIsWeb
      ? null
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => MembershipProvider.google,
          TargetPlatform.iOS => MembershipProvider.apple,
          _ => null,
        };

  Future<MembershipCatalogData> load() async {
    final platform = provider;
    if (platform == null) throw MembershipPlatformUnavailable();
    final response = await loadProducts(platform);
    final products = response.products.toList();
    if (products.any((product) => product.provider != platform) ||
        products.map((product) => product.planCode).toSet().length !=
            products.length) {
      throw const FormatException('Invalid membership catalog');
    }
    products.sort((a, b) => b.billingMonths.compareTo(a.billingMonths));
    return MembershipCatalogData(
      offers: List.unmodifiable([
        for (final product in products) MembershipOffer(product: product),
      ]),
    );
  }
}

int? membershipYearlySavings(
  MembershipOffer yearly,
  List<MembershipOffer> offers,
) {
  if (yearly.price == null || !yearly.product.isYearly) {
    return null;
  }
  for (final monthly in offers) {
    if (monthly.price == null ||
        monthly.product.isYearly ||
        monthly.price!.currencyCode != yearly.price!.currencyCode ||
        monthly.product.monthlyGemsCent != yearly.product.monthlyGemsCent) {
      continue;
    }
    final fullYear = monthly.price!.amountCent * 12;
    if (fullYear <= yearly.price!.amountCent) return null;
    final savings = ((fullYear - yearly.price!.amountCent) * 100 / fullYear)
        .round();
    return savings > 0 && savings < 100 ? savings : null;
  }
  return null;
}
