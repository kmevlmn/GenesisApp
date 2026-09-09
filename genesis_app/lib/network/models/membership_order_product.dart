enum MembershipProvider { apple, google }

/// Stable order identity. Catalog prices and eligibility are not receipt data.
class MembershipOrderProduct {
  const MembershipOrderProduct({
    required this.planCode,
    required this.provider,
    required this.storeProductId,
    this.basePlanId = '',
    this.offerId = '',
  });

  factory MembershipOrderProduct.fromJson(Map<String, dynamic> json) {
    final provider = switch (json['provider']) {
      'apple' => MembershipProvider.apple,
      'google' => MembershipProvider.google,
      _ => throw const FormatException('Invalid membership order provider'),
    };
    final plan = json['plan_code'];
    final storeId = json['store_product_id'];
    final basePlan = json['base_plan_id'] ?? '';
    final offer = json['offer_id'] ?? '';
    if (!const {'pro_monthly', 'pro_yearly'}.contains(plan) ||
        storeId is! String ||
        storeId.trim().isEmpty ||
        basePlan is! String ||
        offer is! String) {
      throw const FormatException('Invalid membership order product');
    }
    return MembershipOrderProduct(
      planCode: plan as String,
      provider: provider,
      storeProductId: storeId,
      basePlanId: basePlan,
      offerId: offer,
    );
  }

  final String planCode;
  final MembershipProvider provider;
  final String storeProductId;
  final String basePlanId;
  final String offerId;
  bool get isYearly => planCode == 'pro_yearly';

  Map<String, Object?> toOrderJson() => {
    'provider': provider.name,
    'plan_code': planCode,
    'store_product_id': storeProductId,
    if (provider == MembershipProvider.google) 'base_plan_id': basePlanId,
    if (offerId.isNotEmpty) 'offer_id': offerId,
  };
}
