import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../icons/custom_icon_assets.dart';
import '../../routers/app_router.dart';
import '../../ui/tokens/genesis_colors.dart';
import 'pro_colors.dart';

/// Membership entry on the profile, per design 9k / 9k2.
///
/// Two states share one ground: 9k offers the plan and carries a Subscribe
/// button, 9k2 reports an active plan with an ACTIVE tag and an expiry date.
/// Uses the server's membership status; dates and balances are display data.
class ProfileMembershipCard extends StatelessWidget {
  const ProfileMembershipCard({
    super.key,
    this.isActive = false,
    this.isExpired = false,
    this.membershipExpiresAt,
    this.blueBalanceCent,
    this.blueGemsExpiresAt,
  });

  final DateTime? membershipExpiresAt;
  final bool isActive;
  final bool isExpired;
  final int? blueBalanceCent;
  final DateTime? blueGemsExpiresAt;

  /// 9k is one line taller than 9k2 — the offer copy wraps to two lines.
  static const double _offerHeight = 82;
  static const double _activeHeight = 68;

  static const TextStyle _bodyStyle = TextStyle(
    color: proCardBody,
    fontSize: 12,
    height: 1.25,
    fontWeight: FontWeight.w400,
  );

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final expiry = membershipExpiresAt;
    final isMember = isActive;
    final isLapsed = !isMember && isExpired;
    // Only 9k's two-line offer copy needs the taller ground.
    final height = isMember || isLapsed ? _activeHeight : _offerHeight;
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
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: proCardGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -22,
                top: -28,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.42,
                    child: SvgPicture.asset(
                      proCrownWatermarkIconAsset,
                      key: const ValueKey('user-profile-membership-pattern'),
                      width: 176,
                      height: 125,
                    ),
                  ),
                ),
              ),
              // Light catches the top half of the card only.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: height / 2,
                child: const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x1AFFE296), Color(0x00FFFFFF)],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  // +4 on the left so the crown's art lines up with the red
                  // gem below it, which sits inset inside its own 26 box.
                  padding: const EdgeInsets.only(left: 20, right: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SvgPicture.asset(
                                  proCrownGoldIconAsset,
                                  width: 26,
                                  height: 17,
                                ),
                                const SizedBox(width: 8),
                                // The wordmark yields before the status tag on
                                // a narrow screen rather than overflowing.
                                const Flexible(child: _ProTitle()),
                                if (isMember) ...[
                                  const SizedBox(width: 8),
                                  const _StatusTag.active(),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (isMember)
                              Text(
                                'Expires ${expiry == null ? '—' : _date(expiry)}',
                                key: const ValueKey(
                                  'user-profile-membership-expiry',
                                ),
                                maxLines: 1,
                                style: _bodyStyle,
                              )
                            else if (isLapsed)
                              // The lapsed plan has no artboard; it borrows
                              // 9k2's status line and 9k's Subscribe button.
                              Row(
                                children: [
                                  const _StatusTag.expired(),
                                  if (expiry != null) ...[
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _date(expiry),
                                        key: const ValueKey(
                                          'user-profile-membership-expiry',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: _bodyStyle,
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            else
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: _OfferCopy(),
                              ),
                          ],
                        ),
                      ),
                      if (!isMember) ...[
                        const SizedBox(width: 12),
                        _SubscribeButton(onPressed: openMembership),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Worldo Premium" — a gold sweep clipped to the glyphs.
class _ProTitle extends StatelessWidget {
  const _ProTitle();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => proTitleGradient.createShader(bounds),
      child: const Text(
        'Worldo Premium',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          height: 1,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.08,
        ),
      ),
    );
  }
}

/// The chip beside the wordmark. 9k2 specifies ACTIVE; the lapsed plan has no
/// artboard of its own, so it borrows the same chip in a neutral tone.
class _StatusTag extends StatelessWidget {
  const _StatusTag.active()
    : label = 'ACTIVE',
      fill = proActiveTagFill,
      ink = proActiveTagInk,
      tagKey = const ValueKey('user-profile-membership-active-tag');

  const _StatusTag.expired()
    : label = 'Expired',
      fill = const Color(0x1FFFFFFF),
      ink = GenesisColors.darkTextSecondary,
      tagKey = const ValueKey('user-profile-membership-expired-tag');

  final String label;
  final Color fill;
  final Color ink;
  final Key tagKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: tagKey,
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ink,
          fontSize: 12,
          height: 20 / 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.72,
        ),
      ),
    );
  }
}

class _OfferCopy extends StatelessWidget {
  const _OfferCopy();

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Up to '),
          TextSpan(
            text: '3,500',
            style: TextStyle(
              color: proCardBodyStrong,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(text: ' Gems monthly, plus full premium access.'),
        ],
      ),
      key: ValueKey('user-profile-membership-offer'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: proCardBody,
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _SubscribeButton extends StatelessWidget {
  const _SubscribeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('user-profile-membership-subscribe'),
      onTap: onPressed,
      child: Container(
        height: 30,
        width: 82,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: proSubscribeFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Subscribe',
          style: TextStyle(
            color: proSubscribeInk,
            fontSize: 12,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
