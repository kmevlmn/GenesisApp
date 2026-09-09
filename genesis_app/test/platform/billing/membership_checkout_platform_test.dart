import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/platform/billing/membership_checkout_platform.dart';
import 'package:genesis_flutter_android/platform/billing/app_store_billing_platform.dart';

import '../../support/membership_fixtures.dart';
import 'membership_product_store_test.dart' as google;

class _Store extends Fake implements InAppPurchase {
  _Store(this.products);
  final List<ProductDetails> products;
  PurchaseParam? param;
  Set<String>? ids;
  Future<bool> Function()? buyHandler;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    ids = identifiers;
    return ProductDetailsResponse(productDetails: products, notFoundIDs: []);
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    param = purchaseParam;
    return buyHandler == null ? true : await buyHandler!();
  }

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    expect(autoConsume, isTrue);
    return buyNonConsumable(purchaseParam: purchaseParam);
  }
}

void main() {
  test(
    'Google launches exact base plan and offer token through subscription purchase',
    () async {
      final store = _Store(
        google.details([
          google.offer(),
          google.offer(yearly: true),
          google.offer(yearly: true, id: 'test-offer', trial: true),
        ]),
      );
      final checkout = StoreMembershipCheckoutPlatform(store: store);
      final product = membershipProduct(yearly: true, offerId: 'test-offer');
      final native = await checkout.prepare(product);
      var handoff = false;
      final launched = Completer<bool>();
      store.buyHandler = () => launched.future;
      final purchase = checkout.launch(
        native,
        '4b74ec68-7abc-4cce-a223-e997e31dc811',
        onStoreHandoff: () {
          handoff = true;
          return true;
        },
      );
      await pumpEventQueue();
      expect(handoff, isFalse);
      launched.complete(true);
      await purchase;
      expect(handoff, isTrue);
      final param = store.param! as GooglePlayPurchaseParam;
      expect(store.ids, {'test_pro'});
      expect(param.offerToken, 'test-token-annual-test-offer');
      expect(param.applicationUserName, '4b74ec68-7abc-4cce-a223-e997e31dc811');
      expect(param.productDetails, same(native));
    },
  );
  test(
    'missing configured Google offer never falls back to another plan',
    () async {
      final checkout = StoreMembershipCheckoutPlatform(
        store: _Store(
          google.details([google.offer(), google.offer(yearly: true)]),
        ),
      );
      await expectLater(
        checkout.prepare(membershipProduct(yearly: true, offerId: 'missing')),
        throwsA(isA<BillingPlatformException>()),
      );
    },
  );
  test(
    'Apple subscription passes account UUID and exact product to store',
    () async {
      final product = membershipProduct(
        provider: MembershipProvider.apple,
        yearly: true,
      );
      final native = AppStoreProduct2Details.fromSK2Product(
        SK2Product(
          id: product.storeProductId,
          displayName: 'test',
          displayPrice: r'$99.99',
          description: 'test',
          price: 99.99,
          type: SK2ProductType.autoRenewable,
          priceLocale: SK2PriceLocale(
            currencyCode: 'USD',
            currencySymbol: r'$',
          ),
        ),
      );
      final store = _Store([native]);
      final checkout = StoreMembershipCheckoutPlatform(store: store);
      bool onHandoff() => true;
      await checkout.launch(
        await checkout.prepare(product),
        '4b74ec68-7abc-4cce-a223-e997e31dc811',
        onStoreHandoff: onHandoff,
      );
      expect((store.param as Sk2PurchaseParam).onStoreHandoff, same(onHandoff));
      expect(store.param?.productDetails.id, product.storeProductId);
      expect(
        store.param?.applicationUserName,
        '4b74ec68-7abc-4cce-a223-e997e31dc811',
      );

      // Gems forwards the same native handoff hook and keeps its own SKU/flow.
      final gems = AppStoreBillingPlatform(inAppPurchase: store);
      await gems.buyConsumable(
        product: BillingStoreProduct(
          id: native.id,
          type: BillingStoreProductType.inApp,
          nativeProduct: native,
        ),
        billingAccountId: '4b74ec68-7abc-4cce-a223-e997e31dc811',
        onStoreHandoff: onHandoff,
      );
      expect((store.param as Sk2PurchaseParam).onStoreHandoff, same(onHandoff));
    },
  );
  test(
    'consumable product cannot be launched by membership checkout',
    () async {
      final product = membershipProduct(provider: MembershipProvider.apple);
      final native = AppStoreProduct2Details.fromSK2Product(
        SK2Product(
          id: product.storeProductId,
          displayName: 'test',
          displayPrice: r'$9.99',
          description: 'test',
          price: 9.99,
          type: SK2ProductType.consumable,
          priceLocale: SK2PriceLocale(
            currencyCode: 'USD',
            currencySymbol: r'$',
          ),
        ),
      );
      final checkout = StoreMembershipCheckoutPlatform(store: _Store([native]));
      expect(await checkout.isSubscription(product.storeProductId), isFalse);
      await expectLater(
        checkout.prepare(product),
        throwsA(isA<BillingPlatformException>()),
      );
    },
  );
}
