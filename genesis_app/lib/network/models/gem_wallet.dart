import '../../utils/gem_amount.dart';

class GemWallet {
  const GemWallet({required this.balanceCent, this.membership});

  factory GemWallet.fromJson(Map<String, dynamic> json) {
    final rawWallet = json['wallet'];
    if (rawWallet is! Map) {
      throw const FormatException('Gem wallet payload is missing wallet');
    }
    return GemWallet(
      balanceCent: requireGemCent(
        rawWallet['balance_cent'],
        fieldName: 'wallet.balance_cent',
      ),
      membership: GemWalletMembership.tryParse(json['membership']),
    );
  }

  final int balanceCent;
  final GemWalletMembership? membership;
}

class GemWalletMembership {
  static GemWalletMembership? tryParse(Object? value) {
    if (value == null) return null;
    try {
      return GemWalletMembership.fromJson(value);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  const GemWalletMembership({
    required this.status,
    required this.planCode,
    required this.expiresAt,
    required this.autoRenew,
    required this.blueGemsCent,
    required this.hasOverlap,
  });

  factory GemWalletMembership.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid membership summary');
    }
    final status = value['membership_status'];
    final plan = value['plan_code'];
    final expiry = value['expires_at'];
    final autoRenew = value['auto_renew'];
    final overlap = value['has_overlap'];
    final blue = requireGemCent(
      value['blue_gems_cent'],
      fieldName: 'membership.blue_gems_cent',
    );
    if (status is! int ||
        !const [0, 1, 2].contains(status) ||
        !const ['', 'pro_monthly', 'pro_yearly'].contains(plan) ||
        (expiry != null && (expiry is! int || expiry < 0)) ||
        autoRenew is! bool ||
        overlap is! bool ||
        blue < 0) {
      throw const FormatException('Invalid membership summary');
    }
    return GemWalletMembership(
      status: status,
      planCode: plan as String,
      expiresAt: expiry == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (expiry as int) * 1000,
              isUtc: true,
            ),
      autoRenew: autoRenew,
      blueGemsCent: blue,
      hasOverlap: overlap,
    );
  }

  final int status;
  final String planCode;
  final DateTime? expiresAt;
  final bool autoRenew;
  final int blueGemsCent;
  final bool hasOverlap;

  bool get isActive => status == 1;
}
