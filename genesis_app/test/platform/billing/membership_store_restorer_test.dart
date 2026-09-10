import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/network/models/membership_claim.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/platform/billing/membership_store_restorer.dart';

void main() {
  test(
    'guest discovery queries Google SUBS without a catalog and ignores pending or missing identities',
    () async {
      const uuid = '4b74ec68-7abc-4cce-a223-e997e31dc811';
      PurchaseWrapper purchase(String? account, PurchaseStateWrapper state) =>
          PurchaseWrapper(
            orderId: 'order',
            packageName: 'test',
            purchaseTime: 100,
            purchaseToken: 'token',
            signature: '',
            products: ['subscription'],
            isAutoRenewing: false,
            originalJson: '',
            isAcknowledged: true,
            purchaseState: state,
            obfuscatedAccountId: account,
          );
      final restorer = MembershipStoreRestorer(
        provider: MembershipProvider.google,
        googleQuery: () async => PurchasesResultWrapper(
          responseCode: BillingResponse.ok,
          billingResult: const BillingResultWrapper(
            responseCode: BillingResponse.ok,
          ),
          purchasesList: [
            purchase(uuid, PurchaseStateWrapper.purchased),
            purchase(uuid.toUpperCase(), PurchaseStateWrapper.purchased),
            purchase(
              '8b74ec68-7abc-4cce-a223-e997e31dc811',
              PurchaseStateWrapper.pending,
            ),
            purchase(null, PurchaseStateWrapper.purchased),
            purchase('not-a-uuid', PurchaseStateWrapper.purchased),
          ],
        ),
      );
      expect(
        (await restorer.discoverGuestPurchases())
            .map((entry) => entry.purchase.obfuscatedAccountId)
            .toSet(),
        {uuid},
      );
    },
  );

  test(
    'guest Apple discovery excludes Gems, expired, revoked and replaced subscription chains',
    () async {
      const uuid = '4b74ec68-7abc-4cce-a223-e997e31dc811';
      const other = '8b74ec68-7abc-4cce-a223-e997e31dc811';
      SK2Transaction transaction(
        String id,
        String chain,
        String account,
        int? expires, {
        String json = '{}',
      }) => SK2Transaction(
        id: id,
        originalId: chain,
        productId: 'product-$id',
        purchaseDate: id,
        expirationDate: expires?.toString(),
        appAccountToken: account,
        jsonRepresentation: json,
      );
      final restorer = MembershipStoreRestorer(
        provider: MembershipProvider.apple,
        now: () => DateTime.fromMillisecondsSinceEpoch(1000),
        appleQuery: () async => [
          transaction('1', 'paid', uuid, 2000),
          transaction('2', 'paid', uuid.toUpperCase(), 3000),
          transaction('3', 'gems', other, null),
          transaction('4', 'expired', other, 1000),
          transaction(
            '5',
            'revoked',
            other,
            3000,
            json: '{"revocationDate":900}',
          ),
          transaction(
            '6',
            'upgraded',
            other,
            3000,
            json: '{"isUpgraded":true}',
          ),
          transaction('7', 'old-chain', other, 4000),
          transaction('8', 'old-chain', other, 900),
        ],
      );
      expect(
        (await restorer.discoverGuestPurchases())
            .map((entry) => entry.purchase.obfuscatedAccountId)
            .toSet(),
        {uuid},
      );
    },
  );

  test(
    'guest discovery store failure is not an empty successful result',
    () async {
      final restorer = MembershipStoreRestorer(
        provider: MembershipProvider.google,
        googleQuery: () async => const PurchasesResultWrapper(
          responseCode: BillingResponse.error,
          billingResult: BillingResultWrapper(
            responseCode: BillingResponse.error,
          ),
          purchasesList: [],
        ),
      );
      await expectLater(
        restorer.discoverGuestPurchases(),
        throwsA(isA<BillingPlatformException>()),
      );
    },
  );

  test(
    'Apple claim proof lookup matches transaction, product and UUID exactly',
    () async {
      const uuid = '4b74ec68-7abc-4cce-a223-e997e31dc811';
      final request = MembershipClaimRequest(
        provider: MembershipProvider.apple,
        storeProductId: 'test_pro',
        transactionId: '100',
        guest: const MembershipGuestIdentity(accountUuid: uuid),
      );
      var transactions = <SK2Transaction>[];
      final restorer = MembershipStoreRestorer(
        provider: MembershipProvider.apple,
        appleQuery: () async => transactions,
      );
      SK2Transaction transaction(String id, String product, String owner) =>
          SK2Transaction(
            id: id,
            originalId: 'chain',
            productId: product,
            purchaseDate: '1000',
            appAccountToken: owner,
            receiptData: 'signed.$id.proof',
          );
      for (final wrong in [
        transaction('101', 'test_pro', uuid),
        transaction('100', 'other_product', uuid),
        transaction('100', 'test_pro', 'other-uuid'),
      ]) {
        transactions = [wrong];
        await expectLater(
          restorer.signedTransaction(request),
          throwsA(isA<BillingPlatformException>()),
        );
      }
      transactions = [
        transaction('101', 'test_pro', uuid),
        transaction('100', 'test_pro', uuid.toUpperCase()),
      ];
      expect(await restorer.signedTransaction(request), 'signed.100.proof');
    },
  );
  test(
    'Apple finds completed subscriptions and selects the latest transaction per chain',
    () async {
      SK2Transaction transaction(
        String id,
        String chain,
        String product,
        int time,
      ) => SK2Transaction(
        id: id,
        originalId: chain,
        productId: product,
        purchaseDate: '$time',
        expirationDate: '${time + 1}',
        appAccountToken: 'account-uuid',
      );
      final restorer = MembershipStoreRestorer(
        provider: MembershipProvider.apple,
        appleQuery: () async => [
          transaction('1', 'chain-1', 'pro_monthly', 100),
          transaction('3', 'chain-2', 'pro_monthly', 300),
          transaction('2', 'chain-1', 'pro_yearly', 200),
          transaction('4', 'gem-chain', 'gems', 400),
        ],
      );
      final purchases = await restorer.query({'pro_monthly', 'pro_yearly'});
      expect(purchases.map((p) => p.transactionId).toSet(), {'2', '3'});
      expect(
        purchases.every((p) => p.status == BillingPurchaseStatus.restored),
        isTrue,
      );
      expect(purchases.first.obfuscatedAccountId, 'account-uuid');
    },
  );
  test(
    'Google filters product IDs and keeps pending separate from paid',
    () async {
      PurchaseWrapper purchase(String product, PurchaseStateWrapper state) =>
          PurchaseWrapper(
            orderId: state == PurchaseStateWrapper.pending ? '' : 'order',
            packageName: 'test',
            purchaseTime: 100,
            purchaseToken: 'token-$product',
            signature: '',
            products: [product],
            isAutoRenewing: false,
            originalJson: '',
            isAcknowledged: true,
            purchaseState: state,
          );
      final restorer = MembershipStoreRestorer(
        provider: MembershipProvider.google,
        googleQuery: () async => PurchasesResultWrapper(
          responseCode: BillingResponse.ok,
          billingResult: const BillingResultWrapper(
            responseCode: BillingResponse.ok,
          ),
          purchasesList: [
            purchase('pro', PurchaseStateWrapper.purchased),
            purchase('pro', PurchaseStateWrapper.pending),
            purchase('gems', PurchaseStateWrapper.purchased),
          ],
        ),
      );
      final purchases = await restorer.query({'pro'});
      expect(purchases, hasLength(2));
      expect(purchases.first.status, BillingPurchaseStatus.restored);
      expect(purchases.last.status, BillingPurchaseStatus.pending);
    },
  );
  test(
    'empty catalog does not query store and store errors propagate for retry',
    () async {
      var queries = 0;
      final restorer = MembershipStoreRestorer(
        provider: MembershipProvider.google,
        googleQuery: () async {
          queries++;
          return const PurchasesResultWrapper(
            responseCode: BillingResponse.error,
            billingResult: BillingResultWrapper(
              responseCode: BillingResponse.error,
            ),
            purchasesList: [],
          );
        },
      );
      expect(await restorer.query({}), isEmpty);
      expect(queries, 0);
      await expectLater(
        restorer.query({'pro'}),
        throwsA(isA<BillingPlatformException>()),
      );
    },
  );
}
