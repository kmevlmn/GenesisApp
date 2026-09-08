import 'package:genesis_flutter_android/app/membership/membership_catalog.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/platform/billing/membership_product_store.dart';

// Synthetic test inputs, not a production product catalog.
MembershipProduct membershipProduct({
  bool yearly = false,
  MembershipProvider provider = MembershipProvider.google,
  String offerId = '',
  int monthlyGemsCent = 120000,
  bool saleEnabled = true,
}) => MembershipProduct.fromJson({
  'plan_code': yearly ? 'pro_yearly' : 'pro_monthly',
  'provider': provider.name,
  'store_product_id': provider == MembershipProvider.google
      ? 'test_pro'
      : yearly
      ? 'test_annual'
      : 'test_month',
  if (provider == MembershipProvider.google)
    'base_plan_id': yearly ? 'test-annual' : 'test-month',
  if (offerId.isNotEmpty) 'offer_id': offerId,
  'billing_months': yearly ? 12 : 1,
  'monthly_gems_cent': monthlyGemsCent,
  'config_version': 'test-v1',
  'sale_enabled': saleEnabled,
});

MembershipStorePrice membershipPrice({
  bool yearly = false,
  String currency = 'USD',
  bool introductory = false,
}) => MembershipStorePrice(
  formattedPrice: yearly ? r'$99.99' : r'$9.99',
  amountMicros: yearly ? 99990000 : 9990000,
  currencyCode: currency,
  currencySymbol: r'$',
  hasIntroductoryPrice: introductory,
);

Future<List<MembershipOffer>> loadTestMembershipOffers() async => [
  for (final yearly in [true, false])
    MembershipOffer(
      product: membershipProduct(yearly: yearly),
      price: membershipPrice(yearly: yearly),
    ),
];
