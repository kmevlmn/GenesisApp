import 'package:flutter/foundation.dart';

import '../../network/models/membership_product.dart';

class MembershipPurchaseBlocked implements Exception {
  const MembershipPurchaseBlocked(this.reason);
  final String reason;
}

String? membershipPurchaseBlockReason(MembershipProduct product) {
  if (!product.canPurchase || product.purchaseBlockReason.isNotEmpty) {
    return product.purchaseBlockReason.isEmpty
        ? 'eligibility_unavailable'
        : product.purchaseBlockReason;
  }
  return null;
}

String membershipPurchaseFailureMessage(String reason) {
  final message = switch (reason) {
    'already_subscribed' => 'You already have this VIP plan.',
    'downgrade_not_allowed' =>
      'An active yearly VIP plan cannot be changed to monthly.',
    'purchase_processing' =>
      'Your previous VIP purchase is still being confirmed.',
    'cross_platform_upgrade_not_allowed' =>
      'Please use the original store to upgrade your VIP plan.',
    'subscription_requires_action' =>
      'Please resolve your current subscription in the store before purchasing.',
    'sale_disabled' => 'VIP purchase is currently unavailable.',
    'device_id_required' || 'eligibility_unavailable' =>
      'Unable to verify VIP purchase eligibility. Please try again.',
    'account_mismatch' => 'This VIP purchase belongs to a different account.',
    'invalid_purchase' => 'The store could not verify this VIP purchase.',
    'product_mismatch' => 'The VIP purchase does not match the selected plan.',
    'purchase_canceled' => 'This VIP purchase was cancelled.',
    'purchase_revoked' => 'This VIP purchase was revoked.',
    _ => 'VIP purchase failed.',
  };
  final isPurchaseBlockReason = const {
    'device_id_required',
    'already_subscribed',
    'downgrade_not_allowed',
    'cross_platform_upgrade_not_allowed',
    'subscription_requires_action',
    'purchase_processing',
    'sale_disabled',
    'eligibility_unavailable',
  }.contains(reason);
  return kDebugMode && isPurchaseBlockReason
      ? 'debug:$reason\n$message'
      : message;
}
