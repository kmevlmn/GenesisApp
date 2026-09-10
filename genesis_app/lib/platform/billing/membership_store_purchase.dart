import 'billing_models.dart';

/// A current, paid subscription returned by the store's read-only query.
/// The receipt is retained so a discovered UUID can actually be claimed.
class MembershipStorePurchase {
  const MembershipStorePurchase({required this.purchase, this.expiresAt});

  final BillingPurchase purchase;
  // Google queryPurchases(SUBS) filters inactive subscriptions but provides no
  // expiry/base plan. Apple supplies the verified transaction's expiration.
  final DateTime? expiresAt;

  bool isCurrent(DateTime now) => expiresAt == null || expiresAt!.isAfter(now);
}
