import '../../network/models/membership_purchase.dart';

/// Separately persists the guest's claim and the first login chosen to own it.
class MembershipGuestClaimRecord {
  const MembershipGuestClaimRecord({
    required this.guest,
    this.ownerUid,
    this.status,
    this.loginRequired = false,
    this.purchaseRequestId,
    this.purchaseConfirmed = false,
  });

  final MembershipGuestIdentity guest;
  final String? ownerUid;
  final String? status;
  final bool loginRequired;
  final String? purchaseRequestId;
  final bool purchaseConfirmed;

  bool get requiresLogin =>
      status != 'completed' && (purchaseConfirmed || loginRequired);

  bool get needsRetry => status == null || status == 'accepted';

  MembershipGuestClaimRecord copyWith({
    String? ownerUid,
    String? status,
    bool? loginRequired,
    String? purchaseRequestId,
    bool? purchaseConfirmed,
  }) => MembershipGuestClaimRecord(
    guest: guest,
    ownerUid: ownerUid ?? this.ownerUid,
    status: status ?? this.status,
    loginRequired: loginRequired ?? this.loginRequired,
    purchaseRequestId: purchaseRequestId ?? this.purchaseRequestId,
    purchaseConfirmed: purchaseConfirmed ?? this.purchaseConfirmed,
  );

  Map<String, Object?> toJson() => {
    'guest': guest.toJson(),
    'owner_uid': ownerUid,
    'status': status,
    'login_required': loginRequired,
    'purchase_request_id': purchaseRequestId,
    'purchase_confirmed': purchaseConfirmed,
  };

  factory MembershipGuestClaimRecord.fromJson(Map<String, dynamic> json) =>
      MembershipGuestClaimRecord(
        guest: MembershipGuestIdentity.fromJson(
          Map<String, dynamic>.from(json['guest'] as Map),
        ),
        ownerUid: json['owner_uid'] as String?,
        status: json['status'] as String?,
        loginRequired: json['login_required'] as bool? ?? false,
        purchaseRequestId: json['purchase_request_id'] as String?,
        purchaseConfirmed: json['purchase_confirmed'] as bool? ?? false,
      );
}
