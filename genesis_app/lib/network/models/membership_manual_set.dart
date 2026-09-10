class MembershipManualSetRequest {
  const MembershipManualSetRequest({
    required this.uid,
    required this.planCode,
    required this.expiresAt,
    this.reason = '',
  });

  static const planCodes = ['pro_monthly', 'pro_yearly'];

  final String uid;
  final String planCode;
  final int expiresAt;
  final String reason;

  Map<String, Object> toJson() {
    final targetUid = uid.trim();
    final note = reason.trim();
    if (targetUid.isEmpty || targetUid.length > 32) {
      throw const FormatException('uid must contain 1–32 characters');
    }
    if (!planCodes.contains(planCode)) {
      throw const FormatException('Invalid manual membership plan_code');
    }
    if (expiresAt < 1) {
      throw const FormatException('expires_at must be positive Unix seconds');
    }
    if (note.length > 512) {
      throw const FormatException('reason must contain at most 512 characters');
    }
    return {
      'uid': targetUid,
      'plan_code': planCode,
      'expires_at': expiresAt,
      if (note.isNotEmpty) 'reason': note,
    };
  }
}

/// Fields used by the debug editor. Entitlements are reloaded from the wallet.
class MembershipManualSetResult {
  const MembershipManualSetResult({
    required this.uid,
    required this.planCode,
    required this.expiresAt,
    required this.membershipStatus,
  });

  factory MembershipManualSetResult.fromJson(Map<String, dynamic> json) {
    final uid = json['uid'];
    final plan = json['plan_code'];
    final expiresAt = json['expires_at'];
    final status = json['membership_status'];
    if (uid is! String ||
        uid.trim().isEmpty ||
        plan is! String ||
        !MembershipManualSetRequest.planCodes.contains(plan) ||
        expiresAt is! int ||
        status is! int ||
        !const [0, 1, 2].contains(status)) {
      throw const FormatException('Invalid manual membership response');
    }
    return MembershipManualSetResult(
      uid: uid,
      planCode: plan,
      expiresAt: expiresAt,
      membershipStatus: status,
    );
  }

  final String uid;
  final String planCode;
  final int expiresAt;
  final int membershipStatus;
}
