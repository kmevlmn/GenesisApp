import '../../utils/gem_amount.dart';
import '../json_utils.dart';

enum MembershipProvider { apple, google }

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

class MembershipProduct {
  const MembershipProduct({
    required this.planCode,
    required this.provider,
    required this.storeProductId,
    required this.billingMonths,
    required this.monthlyGemsCent,
    required this.configVersion,
    required this.saleEnabled,
    this.basePlanId = '',
    this.offerId = '',
  });

  factory MembershipProduct.fromJson(Map<String, dynamic> json) {
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
    final version = asString(json['config_version']).trim();
    final saleEnabled = json['sale_enabled'];
    if (!((planCode == 'pro_monthly' && months == 1) ||
            (planCode == 'pro_yearly' && months == 12)) ||
        months is! int ||
        storeId.isEmpty ||
        version.isEmpty ||
        (provider == MembershipProvider.google && basePlan.isEmpty) ||
        saleEnabled is! bool ||
        gems < 0 ||
        (saleEnabled && gems == 0)) {
      throw const FormatException('Invalid membership product configuration');
    }
    return MembershipProduct(
      planCode: planCode,
      provider: provider,
      storeProductId: storeId,
      basePlanId: basePlan,
      offerId: asString(json['offer_id']).trim(),
      billingMonths: months,
      monthlyGemsCent: gems,
      configVersion: version,
      saleEnabled: saleEnabled,
    );
  }

  final String planCode;
  final MembershipProvider provider;
  final String storeProductId;
  final String basePlanId;
  final String offerId;
  final int billingMonths;
  final int monthlyGemsCent;
  final String configVersion;
  final bool saleEnabled;

  bool get isYearly => billingMonths == 12;
  String get label => isYearly ? 'Yearly' : 'Monthly';
}
