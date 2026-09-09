import 'membership_order_product.dart';

class MembershipGuestIdentity {
  const MembershipGuestIdentity({
    required this.guestId,
    required this.accountUuid,
    required this.claimToken,
  });

  factory MembershipGuestIdentity.fromJson(Map<String, dynamic> json) {
    final guestId = _requiredString(json, 'guest_id');
    final uuid = _requiredString(json, 'account_uuid');
    final token = _requiredString(json, 'claim_token');
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token) ||
        !isMembershipAccountUuid(uuid)) {
      throw const FormatException('Invalid membership guest identity');
    }
    return MembershipGuestIdentity(
      guestId: guestId,
      accountUuid: uuid,
      claimToken: token,
    );
  }

  final String guestId;
  final String accountUuid;
  final String claimToken;

  Map<String, Object?> toJson() => {
    'guest_id': guestId,
    'account_uuid': accountUuid,
    'claim_token': claimToken,
  };
}

bool isMembershipAccountUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
).hasMatch(value);

class MembershipPurchaseRequest {
  const MembershipPurchaseRequest({
    required this.product,
    required this.requestId,
    this.transactionId = '',
    this.purchaseToken = '',
    this.guest,
  });

  final MembershipOrderProduct product;
  final String requestId;
  final String transactionId;
  final String purchaseToken;
  final MembershipGuestIdentity? guest;

  Map<String, Object?> toJson() {
    final google = product.provider == MembershipProvider.google;
    if (requestId.isEmpty ||
        requestId.length > 64 ||
        (google ? purchaseToken.isEmpty : transactionId.isEmpty)) {
      throw const FormatException('Incomplete membership purchase');
    }
    return {
      'provider': product.provider.name,
      'plan_code': product.planCode,
      'store_product_id': product.storeProductId,
      'request_id': requestId,
      if (google) 'purchase_token': purchaseToken,
      if (!google) 'transaction_id': transactionId,
      if (guest != null) 'guest_id': guest!.guestId,
      if (guest != null) 'claim_token': guest!.claimToken,
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
