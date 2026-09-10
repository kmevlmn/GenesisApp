import 'membership_order_product.dart';
import 'membership_purchase.dart';

/// Both stores determine the claimed plan from the original purchase proof.
/// Guest reports use the same proof, without a plan or local attempt ID.
class MembershipClaimRequest {
  const MembershipClaimRequest({
    required this.provider,
    required this.storeProductId,
    required this.guest,
    this.purchaseToken = '',
    this.transactionId = '',
    this.signedTransaction = '',
  });

  factory MembershipClaimRequest.fromPurchase(
    MembershipPurchaseRequest request,
  ) {
    final guest = request.guest;
    if (guest == null) {
      throw const FormatException(
        'Membership claim requires guest purchase proof',
      );
    }
    return MembershipClaimRequest(
      provider: request.product.provider,
      storeProductId: request.product.storeProductId,
      guest: guest,
      purchaseToken: request.purchaseToken,
      transactionId: request.transactionId,
      signedTransaction: request.signedTransaction,
    );
  }

  final MembershipProvider provider;
  final String storeProductId;
  final MembershipGuestIdentity guest;
  final String purchaseToken;
  final String transactionId;
  final String signedTransaction;

  MembershipClaimRequest withSignedTransaction(String value) =>
      MembershipClaimRequest(
        provider: provider,
        storeProductId: storeProductId,
        guest: guest,
        purchaseToken: purchaseToken,
        transactionId: transactionId,
        signedTransaction: value,
      );

  Map<String, Object?> toJson() {
    final google = provider == MembershipProvider.google;
    if (storeProductId.trim().isEmpty ||
        !isMembershipAccountUuid(guest.accountUuid) ||
        (google
            ? purchaseToken.isEmpty
            : transactionId.isEmpty || signedTransaction.isEmpty)) {
      throw const FormatException('Incomplete membership claim proof');
    }
    return {
      'provider': provider.name,
      'store_product_id': storeProductId,
      'account_uuid': guest.accountUuid,
      if (google) 'purchase_token': purchaseToken,
      if (!google) 'transaction_id': transactionId,
      if (!google) 'signed_transaction': signedTransaction,
    };
  }
}

/// Claim only confirms binding progress. Current VIP state comes from wallet.
class MembershipClaimResult {
  const MembershipClaimResult({required this.status});

  final MembershipReportStatus status;

  factory MembershipClaimResult.fromJson(Map<String, dynamic> json) {
    final status = switch (json['status']) {
      'completed' => MembershipReportStatus.completed,
      'accepted' => MembershipReportStatus.accepted,
      'rejected' => MembershipReportStatus.rejected,
      _ => throw const FormatException('Invalid membership claim status'),
    };
    return MembershipClaimResult(status: status);
  }
}
