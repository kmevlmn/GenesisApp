import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../icons/custom_icon_assets.dart';
import '../../routers/app_router.dart';
import '../../ui/tokens/genesis_typography.dart';
import 'gem_balance_text.dart';
import 'gem_card_action_style.dart';

/// Membership data is optional until the wallet contract exposes these fields.
class ProfileMembershipCard extends StatelessWidget {
  const ProfileMembershipCard({
    super.key,
    this.membershipExpiresAt,
    this.blueBalanceCent,
    this.blueGemsExpiresAt,
  });

  final DateTime? membershipExpiresAt;
  final int? blueBalanceCent;
  final DateTime? blueGemsExpiresAt;

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final expiry = membershipExpiresAt;
    final isMember = expiry != null && expiry.isAfter(DateTime.now());
    void openMembership() => Navigator.of(
      context,
    ).pushNamed(RouteNames.gemWallet, arguments: 'subscription');

    return Semantics(
      button: true,
      label: 'Pro membership',
      child: GestureDetector(
        key: const ValueKey('user-profile-membership-entry'),
        onTap: openMembership,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF841A32), Color(0xFF590C20), Color(0xFF3C0716)],
              stops: [0, 0.55, 1],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD8B568)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                top: isMember ? 20 : 12,
                height: isMember ? 76 : 56,
                right: isMember ? 60 : 73,
                width: isMember ? 98 : 72,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.18,
                    child: SvgPicture.asset(
                      'assets/custom-icons/svg/pro_crown_pattern.svg',
                      key: const ValueKey('user-profile-membership-pattern'),
                      fit: BoxFit.fitHeight,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SvgPicture.asset(
                          proCrownFilledIconAsset,
                          width: 28,
                          height: 28,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Pro',
                            style: TextStyle(
                              color: Color(0xFFF5DFA3),
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isMember)
                          Text(
                            'Expires ${_date(expiry)}',
                            maxLines: 1,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Color(0xB8FFFFFF),
                              fontSize: 11,
                              height: 1.4,
                            ),
                          )
                        else
                          TextButton(
                            onPressed: openMembership,
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFFE8C77F),
                              foregroundColor: const Color(0xFF590C20),
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: GenesisTypography.resolve(
                                context,
                                gemCardActionTextStyle,
                              ),
                            ),
                            child: const Text('Subscribe'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (!isMember)
                      const Text(
                        'Monthly Blue Gems included',
                        style: TextStyle(
                          color: Color(0xB8FFFFFF),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      )
                    else ...[
                      const Text(
                        'Free',
                        style: TextStyle(
                          fontSize: 12,
                          height: 14 / 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFFD4DA),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          SvgPicture.asset(
                            'assets/custom-icons/svg/icon_blue_gem.svg',
                            width: 16,
                            height: 24,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text.rich(
                              blueBalanceCent == null
                                  ? const TextSpan(text: '—')
                                  : gemBalanceTextSpan(
                                      blueBalanceCent!,
                                      fontSize: 18,
                                    ),
                              key: const ValueKey(
                                'user-profile-blue-gems-balance',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xF2FFFFFF),
                                fontSize: 18,
                                height: 22 / 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Temporary stacked state comparison in Me, using preview values only.
class ProfileMembershipCardPreview extends StatelessWidget {
  const ProfileMembershipCardPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProfileMembershipCard(),
        const SizedBox(height: 10),
        ProfileMembershipCard(
          membershipExpiresAt: DateTime(now.year + 1, now.month, now.day),
          blueBalanceCent: 30000,
          blueGemsExpiresAt: DateTime(now.year, now.month + 1, 0),
        ),
      ],
    );
  }
}
