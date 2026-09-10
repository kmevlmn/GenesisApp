/// A backend ownership snapshot, not a membership entitlement check.
class MembershipGuestPurchaseCheck {
  const MembershipGuestPurchaseCheck({required this.hasUnboundOrder});

  factory MembershipGuestPurchaseCheck.fromJson(Map<String, dynamic> json) {
    final value = json['has_unbound_order'];
    if (value is! bool) {
      throw const FormatException('Missing membership unbound order status');
    }
    return MembershipGuestPurchaseCheck(hasUnboundOrder: value);
  }

  // Expired/refunded orders can also be unbound in the current API contract.
  final bool hasUnboundOrder;
}
