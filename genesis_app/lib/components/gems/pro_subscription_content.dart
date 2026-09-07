import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../icons/custom_icon_assets.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_primary_button.dart';
import '../../ui/components/genesis_soft_italic_text.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/tokens/genesis_typography.dart';
import '../common/genesis_center_toast.dart';

// Demo prices and benefits only, not store products or entitlement rules.
enum _PreviewProPlan {
  yearly('Yearly', '79.99', '6.67', 'year'),
  monthly('Monthly', '9.99', '9.99', 'month');

  const _PreviewProPlan(this.label, this.total, this.perMonth, this.period);
  final String label;
  final String total;
  final String perMonth;
  final String period;
}

enum _PreviewBenefitStatus { upgraded, unchanged, locked }

class ProSubscriptionContent extends StatefulWidget {
  const ProSubscriptionContent({super.key});

  @override
  State<ProSubscriptionContent> createState() => _ProSubscriptionContentState();
}

class _ProSubscriptionContentState extends State<ProSubscriptionContent> {
  _PreviewProPlan _plan = _PreviewProPlan.yearly;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            key: const ValueKey('pro-benefits-card'),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEBEBEB)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GenesisSoftItalicText(
                        'Pro',
                        key: ValueKey('pro-tier-title'),
                        style: TextStyle(
                          fontSize: 28,
                          height: 34 / 28,
                          fontWeight: FontWeight.w700,
                          color: GenesisColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 10),
                      Divider(height: 1, color: Color(0xFFEBEBEB)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    key: const PageStorageKey('pro-benefits-scroll'),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    children: const [
                      _ProBenefit(
                        label: 'Monthly bonus Gems',
                        icon: Icons.diamond_outlined,
                        status: _PreviewBenefitStatus.upgraded,
                      ),
                      _ProBenefit(
                        label: 'More character slots',
                        asset: characterStatIconAsset,
                        status: _PreviewBenefitStatus.upgraded,
                      ),
                      _ProBenefit(
                        label: 'Unlimited inspirations',
                        asset: inspirationIconAsset,
                        status: _PreviewBenefitStatus.upgraded,
                      ),
                      _ProBenefit(
                        label: 'Edit AI replies',
                        asset: editSquareIconAsset,
                        status: _PreviewBenefitStatus.upgraded,
                      ),
                      _ProBenefit(
                        label: 'Longer conversation memory',
                        icon: Icons.memory_outlined,
                        status: _PreviewBenefitStatus.upgraded,
                      ),
                      _ProBenefit(
                        label: 'Save your conversations',
                        icon: Icons.download_outlined,
                        status: _PreviewBenefitStatus.locked,
                      ),
                      _ProBenefit(
                        label: 'Custom chat backgrounds',
                        icon: Icons.wallpaper_outlined,
                        status: _PreviewBenefitStatus.upgraded,
                      ),
                      _ProBenefit(
                        label: 'Download without watermark',
                        icon: Icons.hide_image_outlined,
                        status: _PreviewBenefitStatus.locked,
                      ),
                      _ProBenefit(
                        label: 'Create custom characters',
                        asset: createOriginCharactersIconAsset,
                        status: _PreviewBenefitStatus.unchanged,
                      ),
                      _ProBenefit(
                        label: 'Explore community worlds',
                        icon: Icons.public_outlined,
                        status: _PreviewBenefitStatus.unchanged,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 36, 20, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (final plan in _PreviewProPlan.values) ...[
                    if (plan == _PreviewProPlan.monthly)
                      const SizedBox(width: 20),
                    Expanded(
                      child: _ProPlanCard(
                        plan: plan,
                        selected: _plan == plan,
                        onTap: () => setState(() => _plan = plan),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 34),
              GenesisPrimaryButton(
                key: const ValueKey('pro-subscribe-button'),
                label: '${_plan.label}: \$${_plan.total}',
                height: 44,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: GenesisTypography.fontFamily,
                borderRadius: BorderRadius.circular(8),
                onPressed: () => showGenesisToast(
                  context,
                  'Pro subscriptions are coming soon.',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final document in const {
                    'privacy': 'Privacy Policy',
                    'terms': 'Terms of Service',
                  }.entries)
                    Flexible(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pushNamed(
                          RouteNames.legal,
                          arguments: {'document': document.key},
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF888888),
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontFamily: GenesisTypography.fontFamily,
                          ),
                          minimumSize: const Size(0, 20),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(document.value),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProBenefit extends StatelessWidget {
  const _ProBenefit({
    required this.label,
    required this.status,
    this.asset,
    this.icon,
  });

  final String label;
  final _PreviewBenefitStatus status;
  final String? asset;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final locked = status == _PreviewBenefitStatus.locked;
    final color = locked ? const Color(0xFF999999) : GenesisColors.textPrimary;
    final (statusIcon, statusColor, statusLabel) = switch (status) {
      _PreviewBenefitStatus.upgraded => (
        null,
        GenesisColors.brand,
        'Improved with Pro',
      ),
      _PreviewBenefitStatus.unchanged => (
        Icons.check_rounded,
        GenesisColors.textPrimary,
        'Same as free',
      ),
      _PreviewBenefitStatus.locked => (
        Icons.lock_outline_rounded,
        const Color(0xFF999999),
        'Higher tier required',
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GenesisColors.surfacePanel,
              borderRadius: BorderRadius.circular(8),
            ),
            child: asset != null
                ? SvgPicture.asset(
                    asset!,
                    width: 20,
                    height: 20,
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  )
                : Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, height: 20 / 14, color: color),
            ),
          ),
          const SizedBox(width: 10),
          if (status == _PreviewBenefitStatus.upgraded)
            SvgPicture.asset(
              upgradeIconAsset,
              key: ValueKey('pro-benefit-status-$label'),
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(statusColor, BlendMode.srcIn),
              semanticsLabel: statusLabel,
            )
          else
            Icon(
              statusIcon,
              key: ValueKey('pro-benefit-status-$label'),
              size: 20,
              color: statusColor,
              semanticLabel: statusLabel,
            ),
        ],
      ),
    );
  }
}

class _ProPlanCard extends StatelessWidget {
  const _ProPlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final _PreviewProPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${plan.label} Pro, \$${plan.total} per ${plan.period}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: selected ? const Color(0xFFFFF5F6) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: selected ? GenesisColors.brand : const Color(0xFFEBEBEB),
                width: selected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('pro-plan-${plan.name}'),
              onTap: onTap,
              child: SizedBox(
                height: 92,
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 20, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        plan.label,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w400,
                          color: GenesisColors.textPrimary,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '\$${plan.perMonth}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  height: 28 / 24,
                                  fontWeight: FontWeight.w400,
                                  color: GenesisColors.textPrimary,
                                ),
                              ),
                              const TextSpan(
                                text: '/mo',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF888888),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (plan == _PreviewProPlan.yearly)
            Positioned(
              left: 0,
              top: -9,
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('pro-yearly-savings-badge'),
                  height: 21,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: const BoxDecoration(
                    color: GenesisColors.brand,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(3),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: 12,
                        color: Color(0xFFFFD154),
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Save 33%',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
