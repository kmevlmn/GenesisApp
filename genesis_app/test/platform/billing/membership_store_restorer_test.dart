import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:genesis_flutter_android/network/models/membership_product.dart';
import 'package:genesis_flutter_android/network/models/membership_purchase.dart';
import 'package:genesis_flutter_android/platform/billing/billing_models.dart';
import 'package:genesis_flutter_android/platform/billing/membership_store_restorer.dart';

void main() {
  test(
    'Apple claim proof lookup matches transaction, product and UUID exactly',
    () async {
      const uuid = '4b74ec68-7abc-4cce-a223-e997e31dc811';
      final request = MembershipPurchaseRequest(
        product: MembershipOrderProduct(
          provider: MembershipProvider.apple,
          planCode: 'pro_monthly',
          storeProductId: 'test_pro',
        ),
        requestId: 'original-key',
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
