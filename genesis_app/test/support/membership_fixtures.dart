import 'package:genesis_flutter_android/app/membership/membership_catalog.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_benefit.dart';

// Synthetic test inputs, not a production product catalog.
MembershipProduct membershipProduct({
  String title = 'Pro',
  List<MembershipBenefit>? benefits,
  bool yearly = false,
  MembershipProvider provider = MembershipProvider.google,
  String offerId = '',
  int monthlyGemsCent = 120000,
  bool canPurchase = true,
  String purchaseBlockReason = '',
  String currency = 'USD',
  int? priceAmount,
  bool hasPrice = true,
  String? upgradeAccountUuid,
  String? upgradePurchaseToken,
}) => MembershipProduct.fromJson({
  'title': title,
  'benefits': [
    for (final benefit in benefits ?? testMembershipBenefits) benefit.toJson(),
  ],
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
  'can_purchase': canPurchase,
  'purchase_block_reason': purchaseBlockReason,
  'price_currency_code': hasPrice ? currency : '',
  'price_amount': hasPrice ? priceAmount ?? (yearly ? 9999 : 999) : null,
  if (upgradeAccountUuid != null) 'account_uuid': upgradeAccountUuid,
  if (upgradePurchaseToken != null) 'purchase_token': upgradePurchaseToken,
});

// Mirrors the pre-existing UI only for rendering regression tests.
final testMembershipBenefits = <MembershipBenefit>[
  for (final (code, title, icon, display) in const [
    ('monthly_bonus_gems', 'Monthly bonus Gems', 'blue_gem', 'enhanced'),
    ('character_slots', 'More character slots', 'character_slots', 'enhanced'),
    ('inspirations', 'Unlimited inspirations', 'inspiration', 'enhanced'),
    ('edit_replies', 'Edit AI replies', 'edit_reply', 'enhanced'),
    ('conversation_memory', 'Longer conversation memory', 'memory', 'enhanced'),
    (
      'save_conversations',
      'Save your conversations',
      'save_conversation',
      'locked',
    ),
    (
      'chat_backgrounds',
      'Custom chat backgrounds',
      'chat_background',
      'enhanced',
    ),
    ('no_watermark', 'Download without watermark', 'no_watermark', 'locked'),
    (
      'custom_characters',
      'Create custom characters',
      'custom_character',
      'included',
    ),
    (
      'community_worlds',
      'Explore community worlds',
      'community_world',
      'included',
    ),
  ])
    MembershipBenefit.fromJson({
      'code': code,
      'title': title,
      'icon_key': icon,
      'display_type': display,
    }),
];

Future<MembershipCatalogData> loadTestMembershipOffers() async =>
    MembershipCatalogData(
      offers: [
        for (final yearly in [true, false])
          MembershipOffer(product: membershipProduct(yearly: yearly)),
      ],
    );
