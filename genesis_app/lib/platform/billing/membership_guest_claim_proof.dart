import '../../network/models/membership_order_product.dart';

/// Store proof retained only to claim a guest purchase after reinstall.
/// It is independent of report retries and contains no Apple signed JWS.
class MembershipGuestClaimProof {
  const MembershipGuestClaimProof({
    required this.provider,
    required this.storeProductId,
    required this.requestId,
    this.purchaseToken = '',
    this.transactionId = '',
  });

  final MembershipProvider provider;
  final String storeProductId;
  final String requestId;
  final String purchaseToken;
  final String transactionId;

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'store_product_id': storeProductId,
    'request_id': requestId,
    if (provider == MembershipProvider.google) 'purchase_token': purchaseToken,
    if (provider == MembershipProvider.apple) 'transaction_id': transactionId,
  };

  factory MembershipGuestClaimProof.fromJson(Map<String, dynamic> json) {
    final provider = switch (json['provider']) {
      'google' => MembershipProvider.google,
      'apple' => MembershipProvider.apple,
      _ => throw const FormatException('Invalid guest claim proof provider'),
    };
    final storeId = json['store_product_id'];
    final requestId = json['request_id'];
    final token = json['purchase_token'] ?? '';
    final transaction = json['transaction_id'] ?? '';
    if (storeId is! String ||
        storeId.isEmpty ||
        requestId is! String ||
        requestId.isEmpty ||
        requestId.length > 64 ||
        token is! String ||
        transaction is! String ||
        (provider == MembershipProvider.google
            ? token.isEmpty
            : transaction.isEmpty)) {
      throw const FormatException('Incomplete guest claim proof');
    }
    return MembershipGuestClaimProof(
      provider: provider,
      storeProductId: storeId,
      requestId: requestId,
      purchaseToken: token,
      transactionId: transaction,
    );
  }
}
