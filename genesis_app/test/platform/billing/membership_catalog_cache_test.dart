import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/platform/billing/membership_catalog_cache.dart';

import '../../support/membership_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'display cache persists across instances and excludes upgrade credentials',
    () async {
      final product = membershipProduct(
        yearly: true,
        title: 'Cached annual',
        upgradeAccountUuid: '4b74ec68-7abc-4cce-a223-e997e31dc811',
        upgradePurchaseToken: 'private-upgrade-token',
      );
      final cache = MembershipCatalogCache(namespace: 'production');
      await cache.save(MembershipProvider.google, 'user-a', [product]);
      final loaded = await MembershipCatalogCache(
        namespace: 'production',
      ).load(MembershipProvider.google, 'user-a');
      expect(loaded!.products.single.toJson(), product.toJson());
      expect(loaded.products.single.upgradeAccountUuid, isNull);
      expect(loaded.products.single.upgradePurchaseToken, isNull);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefs.getKeys().single)!;
      expect(raw, isNot(contains('private-upgrade-token')));
      expect(raw, isNot(contains('account_uuid')));
    },
  );

  test(
    'account, provider, and environment each isolate display data',
    () async {
      final cache = MembershipCatalogCache(namespace: 'production');
      await cache.save(MembershipProvider.google, 'user-a', [
        membershipProduct(),
      ]);
      expect(await cache.load(MembershipProvider.google, 'user-b'), isNull);
      expect(await cache.load(MembershipProvider.google, null), isNull);
      expect(await cache.load(MembershipProvider.apple, 'user-a'), isNull);
      expect(
        await MembershipCatalogCache(
          namespace: 'debug',
        ).load(MembershipProvider.google, 'user-a'),
        isNull,
      );
      await cache.save(MembershipProvider.google, 'user-a', []);
      expect(
        (await cache.load(MembershipProvider.google, 'user-a'))!.products,
        isEmpty,
      );
    },
  );

  test('corrupt display cache is a cache miss', () async {
    final cache = MembershipCatalogCache(namespace: 'production');
    await cache.save(MembershipProvider.google, null, [membershipProduct()]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefs.getKeys().single, '{invalid');
    expect(await cache.load(MembershipProvider.google, null), isNull);
  });
}
