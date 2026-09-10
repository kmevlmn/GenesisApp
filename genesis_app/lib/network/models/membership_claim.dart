import 'membership_purchase.dart';

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
