import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/platform/billing/membership_product_store.dart';
import '../../support/membership_fixtures.dart';

PricingPhaseWrapper phase({
  String period = 'P1M',
  int micros = 12990000,
  bool trial = false,
}) => PricingPhaseWrapper(
  billingCycleCount: trial ? 1 : 0,
  billingPeriod: period,
  formattedPrice: trial
      ? r'$0.00'
      : period == 'P1M'
      ? r'$12.99'
      : r'$109.99',
  priceAmountMicros: trial ? 0 : micros,
  priceCurrencyCode: 'USD',
  recurrenceMode: trial
      ? RecurrenceMode.finiteRecurring
      : RecurrenceMode.infiniteRecurring,
);
SubscriptionOfferDetailsWrapper offer({
  bool yearly = false,
  String? id,
  bool trial = false,
}) => SubscriptionOfferDetailsWrapper(
  basePlanId: yearly ? 'test-annual' : 'test-month',
  offerId: id,
  offerTags: const [],
  offerIdToken: 'test-token-${yearly ? 'annual' : 'month'}-${id ?? 'base'}',
  pricingPhases: [
    if (trial) phase(period: 'P1W', trial: true),
    phase(
      period: yearly ? 'P1Y' : 'P1M',
      micros: yearly ? 109990000 : 12990000,
    ),
  ],
);
List<ProductDetails> details(List<SubscriptionOfferDetailsWrapper> offers) =>
    GooglePlayProductDetails.fromProductDetails(
      ProductDetailsWrapper(
        description: 'test',
        name: 'test',
        productId: 'test_pro',
        productType: ProductType.subs,
        title: 'test',
        subscriptionOfferDetails: offers,
      ),
    );

void main() {
  test(
    'disabled plans still query store prices without purchase operations',
    () async {
      final store = _MembershipStore(details([offer(), offer(yearly: true)]));
      final prices = await MembershipProductStore(inAppPurchase: store)
          .loadPrices([
            membershipProduct(saleEnabled: false),
            membershipProduct(yearly: true, saleEnabled: false),
          ]);
      expect(store.queriedIds, {'test_pro'});
      expect(prices['pro_monthly']?.formattedPrice, r'$12.99');
      expect(prices['pro_yearly']?.formattedPrice, r'$109.99');
    },
  );
  test(
    'Google matches the configured base plan, not the first shared product ID',
    () {
      final products = details([offer(), offer(yearly: true)]);
      expect(
        matchMembershipStorePrice(
          membershipProduct(yearly: true),
          products,
        )?.formattedPrice,
        r'$109.99',
      );
      expect(
        matchMembershipStorePrice(
          membershipProduct(),
          products,
        )?.formattedPrice,
        r'$12.99',
      );
    },
  );
  test(
    'base plan excludes promotions and configured offers never fall back',
    () {
      final products = details([offer(id: 'trial', trial: true), offer()]);
      final base = matchMembershipStorePrice(membershipProduct(), products)!;
      expect(base.hasIntroductoryPrice, isFalse);
      final promo = matchMembershipStorePrice(
        membershipProduct(offerId: 'trial'),
        products,
      )!;
      expect(promo.formattedPrice, r'$12.99');
      expect(promo.hasIntroductoryPrice, isTrue);
      expect(
        matchMembershipStorePrice(
          membershipProduct(offerId: 'missing'),
          products,
        ),
        isNull,
      );
      expect(
        matchMembershipStorePrice(membershipProduct(yearly: true), products),
        isNull,
      );
    },
  );
  test('Apple uses exact product ID and localized store price', () {
    final config = membershipProduct(
      yearly: true,
      provider: MembershipProvider.apple,
    );
    final product = ProductDetails(
      id: config.storeProductId,
      title: 'test',
      description: 'test',
      price: '109,99 €',
      rawPrice: 109.99,
      currencyCode: 'EUR',
      currencySymbol: '€',
    );
    final price = matchMembershipStorePrice(config, [product])!;
    expect(price.formattedPrice, '109,99 €');
    expect(price.amountMicros, 109990000);
    expect(
      matchMembershipStorePrice(
        membershipProduct(provider: MembershipProvider.apple),
        [product],
      ),
      isNull,
    );
  });
  test(
    'wrong billing period does not attach a monthly price to a yearly plan',
    () {
      final products = details([
        SubscriptionOfferDetailsWrapper(
          basePlanId: 'test-annual',
          offerTags: const [],
          offerIdToken: 'test',
          pricingPhases: [phase()],
        ),
      ]);
      expect(
        matchMembershipStorePrice(membershipProduct(yearly: true), products),
        isNull,
      );
    },
  );
}

class _MembershipStore extends Fake implements InAppPurchase {
  _MembershipStore(this.products);
  final List<ProductDetails> products;
  Set<String>? queriedIds;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    queriedIds = identifiers;
    return ProductDetailsResponse(productDetails: products, notFoundIDs: []);
  }
}
