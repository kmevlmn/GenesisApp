import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/app/membership/membership_catalog.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';

import '../../support/membership_fixtures.dart';

void main() {
  test(
    'catalog sends provider and joins each plan to its own store price',
    () async {
      final monthly = membershipProduct(monthlyGemsCent: 120000);
      final yearly = membershipProduct(yearly: true, monthlyGemsCent: 180025);
      final catalog = MembershipCatalog(
        provider: MembershipProvider.google,
        readLoginUid: () async => 'u_test',
        loadProducts: (provider) async {
          expect(provider, MembershipProvider.google);
          return MembershipProductList(products: [monthly, yearly]);
        },
        loadPrices: (products) async {
          expect(products, [yearly, monthly]);
          return {yearly.planCode: membershipPrice(yearly: true)};
        },
      );
      final offers = await catalog.load();
      expect(offers.first.product.monthlyGemsCent, 180025);
      expect(offers.first.price?.formattedPrice, r'$99.99');
      expect(offers.last.price, isNull);
      expect(offers.last.available, isFalse);
    },
  );

  test('guest does not query account catalog or store', () async {
    final catalog = MembershipCatalog(
      provider: MembershipProvider.apple,
      readLoginUid: () async => null,
      loadProducts: (_) async => throw StateError('must not query'),
      loadPrices: (_) async => throw StateError('must not query'),
    );
    await expectLater(catalog.load(), throwsA(isA<MembershipLoginRequired>()));
  });

  test('empty catalog does not query store', () async {
    final catalog = MembershipCatalog(
      provider: MembershipProvider.google,
      readLoginUid: () async => 'u_test',
      loadProducts: (_) async => const MembershipProductList(products: []),
      loadPrices: (_) async => throw StateError('must not query'),
    );
    expect(await catalog.load(), isEmpty);
  });

  test(
    'store failure preserves configuration without preview prices',
    () async {
      final product = membershipProduct();
      final catalog = MembershipCatalog(
        provider: MembershipProvider.google,
        readLoginUid: () async => 'u_test',
        loadProducts: (_) async => MembershipProductList(products: [product]),
        loadPrices: (_) async => throw StateError('store offline'),
      );
      final offer = (await catalog.load()).single;
      expect(offer.product, product);
      expect(offer.price, isNull);
      expect(offer.available, isFalse);
    },
  );

  test('provider mismatch and duplicate plan codes are rejected', () async {
    for (final products in [
      [membershipProduct(provider: MembershipProvider.apple)],
      [membershipProduct(), membershipProduct()],
    ]) {
      final catalog = MembershipCatalog(
        provider: MembershipProvider.google,
        readLoginUid: () async => 'u_test',
        loadProducts: (_) async => MembershipProductList(products: products),
        loadPrices: (_) async => throw StateError('must not query'),
      );
      await expectLater(catalog.load(), throwsFormatException);
    }
  });

  test('savings require comparable prices and equal monthly quota', () async {
    final offers = await loadTestMembershipOffers();
    expect(membershipYearlySavings(offers.first, offers), 17);
    for (final monthly in [
      MembershipOffer(
        product: membershipProduct(),
        price: membershipPrice(currency: 'EUR'),
      ),
      MembershipOffer(
        product: membershipProduct(monthlyGemsCent: 240000),
        price: membershipPrice(),
      ),
      MembershipOffer(
        product: membershipProduct(),
        price: membershipPrice(introductory: true),
      ),
    ]) {
      expect(
        membershipYearlySavings(offers.first, [offers.first, monthly]),
        isNull,
      );
    }
    final disabled = [
      for (final yearly in [true, false])
        MembershipOffer(
          product: membershipProduct(yearly: yearly, saleEnabled: false),
          price: membershipPrice(yearly: yearly),
        ),
    ];
    expect(disabled.every((offer) => !offer.available), isTrue);
    expect(membershipYearlySavings(disabled.first, disabled), 17);
  });
}
