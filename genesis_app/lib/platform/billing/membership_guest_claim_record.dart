import '../../network/models/membership_purchase.dart';
import 'membership_guest_claim_proof.dart';

/// Separately persists the guest's claim and the first login chosen to own it.
class MembershipGuestClaimRecord {
  const MembershipGuestClaimRecord({
    required this.guest,
    this.ownerUid,
    this.status,
    this.loginRequired = false,
    this.purchaseRequestId,
    this.purchaseConfirmed = false,
    this.autoClaimAllowed = true,
    this.recoveredProof,
  });

  final MembershipGuestIdentity guest;
  final String? ownerUid;
  final String? status;
  final bool loginRequired;
  final String? purchaseRequestId;
  final bool purchaseConfirmed;
  // Startup may discover several independent subscriptions. Only the selected
  // current subscription may be claimed; claiming a lower plan could replace it.
  final bool autoClaimAllowed;
  final MembershipGuestClaimProof? recoveredProof;

  bool get requiresLogin =>
      status != 'completed' && (purchaseConfirmed || loginRequired);

  bool get needsRetry => status == null || status == 'accepted';

  MembershipGuestClaimRecord get boundIdentity => MembershipGuestClaimRecord(
    guest: guest,
    ownerUid: ownerUid,
    status: 'completed',
    autoClaimAllowed: false,
  );

  MembershipGuestClaimRecord copyWith({
    String? ownerUid,
    String? status,
    bool? loginRequired,
    String? purchaseRequestId,
    bool? purchaseConfirmed,
    bool? autoClaimAllowed,
    MembershipGuestClaimProof? recoveredProof,
  }) => MembershipGuestClaimRecord(
    guest: guest,
    ownerUid: ownerUid ?? this.ownerUid,
    status: status ?? this.status,
    loginRequired: loginRequired ?? this.loginRequired,
    purchaseRequestId: purchaseRequestId ?? this.purchaseRequestId,
    purchaseConfirmed: purchaseConfirmed ?? this.purchaseConfirmed,
    autoClaimAllowed: autoClaimAllowed ?? this.autoClaimAllowed,
    recoveredProof: recoveredProof ?? this.recoveredProof,
  );

  Map<String, Object?> toJson() => {
    'guest': guest.toJson(),
    'owner_uid': ownerUid,
    'status': status,
    'login_required': loginRequired,
    'purchase_request_id': purchaseRequestId,
    'purchase_confirmed': purchaseConfirmed,
    'auto_claim_allowed': autoClaimAllowed,
    if (recoveredProof != null) 'recovered_proof': recoveredProof!.toJson(),
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
        autoClaimAllowed: json['auto_claim_allowed'] as bool? ?? true,
        recoveredProof: json['recovered_proof'] == null
            ? null
            : MembershipGuestClaimProof.fromJson(
                Map<String, dynamic>.from(json['recovered_proof'] as Map),
              ),
      );
}
