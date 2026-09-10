import 'membership_order_product.dart';

class MembershipGuestIdentity {
  const MembershipGuestIdentity({required this.accountUuid});

  factory MembershipGuestIdentity.fromJson(Map<String, dynamic> json) {
    final uuid = _requiredString(json, 'account_uuid');
    if (!isMembershipAccountUuid(uuid)) {
      throw const FormatException('Invalid membership guest identity');
    }
    return MembershipGuestIdentity(accountUuid: uuid.toLowerCase());
  }

  final String accountUuid;

  Map<String, Object?> toJson() => {'account_uuid': accountUuid};
}

bool isMembershipAccountUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
).hasMatch(value);

class MembershipPurchaseRequest {
  const MembershipPurchaseRequest({
    required this.product,
    this.transactionId = '',
    this.purchaseToken = '',
    this.signedTransaction = '',
    this.guest,
  });

  final MembershipOrderProduct product;
  final String transactionId;
  final String purchaseToken;

  /// Apple JWS is obtained from StoreKit and never serialized to local storage.
  final String signedTransaction;
  final MembershipGuestIdentity? guest;

  MembershipPurchaseRequest withSignedTransaction(String value) =>
      MembershipPurchaseRequest(
        product: product,
        transactionId: transactionId,
        purchaseToken: purchaseToken,
        signedTransaction: value,
        guest: guest,
      );

  Map<String, Object?> toJson() {
    final google = product.provider == MembershipProvider.google;
    if (google ? purchaseToken.isEmpty : transactionId.isEmpty) {
      throw const FormatException('Incomplete membership purchase');
    }
    if (guest != null &&
        (!isMembershipAccountUuid(guest!.accountUuid) ||
            !google && signedTransaction.isEmpty)) {
      throw const FormatException('Incomplete guest membership purchase proof');
    }
    return {
      'provider': product.provider.name,
      // Report and claim send the original store proof. Local attempt IDs and
      // selected plans are not part of either HTTP request.
      'store_product_id': product.storeProductId,
      if (google) 'purchase_token': purchaseToken,
      if (!google) 'transaction_id': transactionId,
      if (guest != null) 'account_uuid': guest!.accountUuid,
      if (guest != null && !google) 'signed_transaction': signedTransaction,
    };
  }
}

enum MembershipReportStatus { completed, accepted, rejected }

class MembershipPurchaseReport {
  const MembershipPurchaseReport({
    required this.status,
    required this.reportId,
    this.reason,
    this.membershipId,
  });

  factory MembershipPurchaseReport.fromJson(Map<String, dynamic> json) {
    final status = switch (json['status']) {
      'completed' => MembershipReportStatus.completed,
      'accepted' => MembershipReportStatus.accepted,
      'rejected' => MembershipReportStatus.rejected,
      _ => throw const FormatException('Missing membership report status'),
    };
    final reportId = _requiredString(json, 'report_id');
    final membershipId = json['membership_id'] as String?;
    final reason = json['reason'] as String?;
    if (status == MembershipReportStatus.completed &&
            (membershipId?.isNotEmpty != true) ||
        status == MembershipReportStatus.rejected &&
            (reason?.isNotEmpty != true)) {
      throw const FormatException('Incomplete membership report result');
    }
    return MembershipPurchaseReport(
      status: status,
      reportId: reportId,
      reason: reason,
      membershipId: membershipId,
    );
  }

  final MembershipReportStatus status;
  final String reportId;
  final String? reason;
  final String? membershipId;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing membership $key');
  }
  return value;
}
