import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genesis_flutter_android/app/membership/membership_catalog.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/platform/billing/membership_catalog_cache.dart';

import '../../support/membership_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'failed refresh retains cache, empty success replaces it and survives restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = MembershipCatalogCache(namespace: 'catalog-test');
      var failed = false;
      var products = [membershipProduct(title: 'Cached')];
      MembershipCatalog create() => MembershipCatalog(
        provider: MembershipProvider.google,
        cacheStore: store,
        loadProducts: (_) async {
          if (failed) throw StateError('offline');
          return MembershipProductList(products: products);
        },
      );
      final catalog = create();
      await catalog.load();
      expect(catalog.cached!.offers.single.product.title, 'Cached');
      failed = true;
      await expectLater(catalog.load(), throwsStateError);
      expect(
        (await create().loadCached())!.offers.single.product.title,
        'Cached',
      );
      failed = false;
      products = [];
      await catalog.load();
      expect(catalog.cached!.offers, isEmpty);
      expect((await create().loadCached())!.offers, isEmpty);
    },
  );

  test(
    'session change discards old response and reads only the new account cache',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = MembershipCatalogCache(namespace: 'catalog-session');
      await store.save(MembershipProvider.google, 'user-b', [
        membershipProduct(title: 'B cache'),
      ]);
      var owner = 'user-a';
      final pending = Completer<MembershipProductList>();
      final catalog = MembershipCatalog(
        provider: MembershipProvider.google,
        cacheStore: store,
        readOwnerUid: () async => owner,
        loadProducts: (_) => pending.future,
      );
      final old = catalog.load();
      await pumpEventQueue();
      owner = 'user-b';
      catalog.resetForSession();
      expect(catalog.cached, isNull);
      expect(
        (await catalog.loadCached())!.offers.single.product.title,
        'B cache',
      );
      pending.complete(
        MembershipProductList(products: [membershipProduct(title: 'A late')]),
      );
      await old;
      expect(catalog.cached!.offers.single.product.title, 'B cache');
      expect(
        (await store.load(
          MembershipProvider.google,
          'user-b',
        ))!.products.single.title,
        'B cache',
      );
    },
  );

  test(
    'out of order refresh responses cannot roll back the shared cache',
    () async {
      final responses = [
        Completer<MembershipProductList>(),
        Completer<MembershipProductList>(),
      ];
      var calls = 0;
      final catalog = MembershipCatalog(
        provider: MembershipProvider.google,
        loadProducts: (_) => responses[calls++].future,
      );
      final old = catalog.load();
      final latest = catalog.load();
      await pumpEventQueue();
      responses.last.complete(
        MembershipProductList(products: [membershipProduct(title: 'New')]),
      );
      await latest;
      responses.first.complete(
        MembershipProductList(products: [membershipProduct(title: 'Old')]),
      );
      await old;
      expect(catalog.cached!.offers.single.product.title, 'New');
    },
  );
  test(
    'one API response supplies each plan title, price and ordered benefits',
    () async {
      for (final provider in MembershipProvider.values) {
        var requests = 0;
        final monthly = membershipProduct(
          title: 'Server Monthly',
          provider: provider,
          priceAmount: 1499,
        );
        final yearly = membershipProduct(
          title: 'Server Annual',
          benefits: testMembershipBenefits.reversed.toList(),
          provider: provider,
          yearly: true,
          priceAmount: 11999,
        );
        final catalog = MembershipCatalog(
          provider: provider,
          loadProducts: (requested) async {
            requests++;
            expect(requested, provider);
            return MembershipProductList(products: [monthly, yearly]);
          },
        );
        final result = await catalog.load();
        expect(requests, 1);
        expect(result.offers.map((offer) => offer.product), [yearly, monthly]);
        expect(result.offers.first.price?.formattedPrice, r'$119.99');
        expect(result.offers.last.price?.formattedPrice, r'$14.99');
        expect(result.offers.first.product.title, 'Server Annual');
        expect(result.offers.last.product.title, 'Server Monthly');
        expect(
          result.offers.first.product.benefits.map((benefit) => benefit.code),
          testMembershipBenefits.reversed.map((benefit) => benefit.code),
        );
        expect(
          result.offers.last.product.benefits.map((benefit) => benefit.code),
          testMembershipBenefits.map((benefit) => benefit.code),
        );
      }
    },
  );

  test('title and benefits survive missing configured prices', () async {
    final result = await MembershipCatalog(
      provider: MembershipProvider.google,
      loadProducts: (_) async => MembershipProductList(
        products: [membershipProduct(title: 'Unpriced', hasPrice: false)],
      ),
    ).load();
    expect(result.offers.single.product.title, 'Unpriced');
    expect(
      result.offers.single.product.benefits.map((benefit) => benefit.code),
      testMembershipBenefits.map((benefit) => benefit.code),
    );
    expect(result.offers.every((offer) => offer.price == null), isTrue);
  });

  test('empty server catalog remains empty', () async {
    final result = await MembershipCatalog(
      provider: MembershipProvider.google,
      loadProducts: (_) async => const MembershipProductList(products: []),
    ).load();
    expect(result.offers, isEmpty);
  });

  test('provider mismatch and duplicate plans are rejected', () async {
    for (final products in [
      [membershipProduct(provider: MembershipProvider.apple)],
      [membershipProduct(), membershipProduct()],
    ]) {
      final catalog = MembershipCatalog(
        provider: MembershipProvider.google,
        loadProducts: (_) async => MembershipProductList(products: products),
      );
      await expectLater(catalog.load(), throwsFormatException);
    }
  });

  test(
    'savings use API full cycle amounts with equal currency and quota',
    () async {
      final offers = (await loadTestMembershipOffers()).offers;
      expect(membershipYearlySavings(offers.first, offers), 17);
      for (final monthly in [
        membershipProduct(currency: 'EUR'),
        membershipProduct(monthlyGemsCent: 240000),
        membershipProduct(hasPrice: false),
        membershipProduct(priceAmount: 100),
      ]) {
        expect(
          membershipYearlySavings(offers.first, [
            offers.first,
            MembershipOffer(product: monthly),
          ]),
          isNull,
        );
      }
      final changed = [
        MembershipOffer(
          product: membershipProduct(yearly: true, priceAmount: 12000),
        ),
        MembershipOffer(product: membershipProduct(priceAmount: 2000)),
      ];
      expect(membershipYearlySavings(changed.first, changed), 50);
    },
  );
}
