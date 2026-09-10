import '../../utils/gem_amount.dart';
import '../json_utils.dart';
import 'membership_benefit.dart';
import 'membership_order_product.dart';
import 'membership_purchase.dart';

export 'membership_order_product.dart';

class MembershipProductList {
  const MembershipProductList({required this.products});

  factory MembershipProductList.fromJson(Map<String, dynamic> json) {
    final list = json['list'];
    if (list is! List || list.any((item) => item is! Map)) {
      throw const FormatException('Invalid membership product list');
    }
    return MembershipProductList(
      products: List.unmodifiable(
        list.map((item) => MembershipProduct.fromJson(asJsonMap(item))),
      ),
    );
  }

  final List<MembershipProduct> products;
}

class MembershipProduct extends MembershipOrderProduct {
  const MembershipProduct({
    required this.title,
    required this.benefits,
    required super.planCode,
    required super.provider,
    required super.storeProductId,
    required this.billingMonths,
    required this.monthlyGemsCent,
    required this.priceCurrencyCode,
    required this.priceAmount,
    required this.canPurchase,
    required this.purchaseBlockReason,
    this.upgradeAccountUuid,
    this.upgradePurchaseToken,
    super.basePlanId,
    super.offerId,
  });

  factory MembershipProduct.fromJson(Map<String, dynamic> json) {
    final title = json['title'];
    if (title is! String || title.trim().isEmpty) {
      throw const FormatException('Invalid membership product title');
    }
    final rawBenefits = json['benefits'];
    if (rawBenefits is! List || rawBenefits.any((item) => item is! Map)) {
      throw const FormatException('Invalid membership benefits');
    }
    final benefits = rawBenefits
        .map((item) => MembershipBenefit.fromJson(asJsonMap(item)))
        .toList();
    if (benefits.map((benefit) => benefit.code).toSet().length !=
        benefits.length) {
      throw const FormatException('Duplicate membership benefit code');
    }
    final planCode = asString(json['plan_code']);
    final provider = switch (json['provider']) {
      'apple' => MembershipProvider.apple,
      'google' => MembershipProvider.google,
      _ => throw const FormatException('Invalid membership provider'),
    };
    final months = json['billing_months'];
    final gems = requireGemCent(
      json['monthly_gems_cent'],
      fieldName: 'monthly_gems_cent',
    );
    final storeId = asString(json['store_product_id']).trim();
    final basePlan = asString(json['base_plan_id']).trim();
    final currency = json['price_currency_code'];
    final amount = json['price_amount'];
    if (currency is! String ||
        !json.containsKey('price_amount') ||
        !RegExp(r'^([A-Z]{3})?$').hasMatch(currency) ||
        (amount != null && (amount is! int || amount <= 0)) ||
        (currency.isEmpty != (amount == null))) {
      throw const FormatException('Invalid membership display price');
    }
    final canPurchase = json['can_purchase'];
    final blockReason = json['purchase_block_reason'];
    if (canPurchase is! bool ||
        blockReason is! String ||
        !const {
          '',
          'device_id_required',
          'already_subscribed',
          'downgrade_not_allowed',
          'cross_platform_upgrade_not_allowed',
          'subscription_requires_action',
          'purchase_processing',
          'sale_disabled',
        }.contains(blockReason)) {
      throw const FormatException('Invalid membership purchase eligibility');
    }
    if (!((planCode == 'pro_monthly' && months == 1) ||
            (planCode == 'pro_yearly' && months == 12)) ||
        months is! int ||
        storeId.isEmpty ||
        (provider == MembershipProvider.google && basePlan.isEmpty) ||
        gems < 0) {
      throw const FormatException('Invalid membership product configuration');
    }
    final upgradeUuid = json['account_uuid'];
    final upgradeToken = json['purchase_token'];
    final hasUpgrade = json.containsKey('account_uuid');
    final hasToken = json.containsKey('purchase_token');
    if ((hasUpgrade &&
            (upgradeUuid is! String ||
                !isMembershipAccountUuid(upgradeUuid) ||
                planCode != 'pro_yearly' ||
                !canPurchase ||
                blockReason.isNotEmpty)) ||
        (provider == MembershipProvider.google &&
            (hasUpgrade != hasToken ||
                hasToken &&
                    (upgradeToken is! String ||
                        upgradeToken.trim().isEmpty))) ||
        (provider == MembershipProvider.apple && hasToken)) {
      throw const FormatException('Invalid membership upgrade credentials');
    }
    return MembershipProduct(
      title: title,
      benefits: List.unmodifiable(benefits),
      planCode: planCode,
      provider: provider,
      storeProductId: storeId,
      basePlanId: basePlan,
      offerId: asString(json['offer_id']).trim(),
      billingMonths: months,
      monthlyGemsCent: gems,
      priceCurrencyCode: currency,
      priceAmount: amount as int?,
      canPurchase: canPurchase,
      purchaseBlockReason: blockReason,
      upgradeAccountUuid: (upgradeUuid as String?)?.toLowerCase(),
      upgradePurchaseToken: upgradeToken as String?,
    );
  }

  final String title;
  final List<MembershipBenefit> benefits;
  final int billingMonths;
  final int monthlyGemsCent;
  final String priceCurrencyCode;
  final bool canPurchase;
  final String purchaseBlockReason;

  /// Original subscription identity, supplied only for an authenticated upgrade.
  /// Kept in memory; never include these credentials in catalog/order snapshots.
  final String? upgradeAccountUuid;
  final String? upgradePurchaseToken;

  /// Full billing cycle price, in hundredths of the currency's main unit.
  final int? priceAmount;

  /// Display metadata only; upgrade credentials must be fetched again at checkout.
  Map<String, Object?> toJson() => {
    'title': title,
    'benefits': [for (final benefit in benefits) benefit.toJson()],
    'provider': provider.name,
    'plan_code': planCode,
    'store_product_id': storeProductId,
    if (provider == MembershipProvider.google) 'base_plan_id': basePlanId,
    if (offerId.isNotEmpty) 'offer_id': offerId,
    'billing_months': billingMonths,
    'monthly_gems_cent': monthlyGemsCent,
    'price_currency_code': priceCurrencyCode,
    'price_amount': priceAmount,
    'can_purchase': canPurchase,
    'purchase_block_reason': purchaseBlockReason,
  };

  @override
  bool get isYearly => billingMonths == 12;
  String get label => isYearly ? 'Yearly' : 'Monthly';
}
