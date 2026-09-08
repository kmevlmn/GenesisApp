import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/bootstrap/service_registry.dart';
import '../../app/membership/membership_catalog.dart';
import '../../icons/custom_icon_assets.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_primary_button.dart';
import '../../ui/components/genesis_soft_italic_text.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/tokens/genesis_typography.dart';
import '../common/genesis_center_toast.dart';
import 'pro_colors.dart';

enum _ProPlan {
  yearly('pro_yearly', 'Yearly', 'year'),
  monthly('pro_monthly', 'Monthly', 'month');

  const _ProPlan(this.code, this.label, this.period);
  final String code;
  final String label;
  final String period;
}

enum _PreviewBenefitStatus { upgraded, unchanged, locked }

class ProSubscriptionContent extends StatefulWidget {
  const ProSubscriptionContent({super.key, this.productsLoader});

  final MembershipCatalogLoader? productsLoader;

  @override
  State<ProSubscriptionContent> createState() => _ProSubscriptionContentState();
}

class _ProSubscriptionContentState extends State<ProSubscriptionContent> {
  _ProPlan _plan = _ProPlan.yearly;
  AppServices? _services;
  List<MembershipOffer> _offers = [];
  bool _loading = false;
  bool _started = false;
  int _requestGeneration = 0;

  MembershipOffer? _offerFor(_ProPlan plan) {
    for (final offer in _offers) {
      if (offer.product.planCode == plan.code) return offer;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServicesScope.maybeOf(context);
    if (!_started || !identical(services, _services)) {
      _services?.sessionRevision.removeListener(_sessionChanged);
      _services = services;
      services?.sessionRevision.addListener(_sessionChanged);
      _started = true;
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(ProSubscriptionContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productsLoader != widget.productsLoader) unawaited(_load());
  }

  void _sessionChanged() {
    _plan = _ProPlan.yearly;
    unawaited(_load());
  }

  @override
  void dispose() {
    _requestGeneration++;
    _services?.sessionRevision.removeListener(_sessionChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_requestGeneration;
    setState(() {
      _loading = true;
      _offers = [];
    });
    try {
      final loader = widget.productsLoader ?? _services?.membershipCatalog.load;
      if (loader == null) throw MembershipPlatformUnavailable();
      final offers = await loader();
      if (!mounted || request != _requestGeneration) return;
      setState(() {
        _offers = offers;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _requestGeneration) return;
      debugPrint('[Membership] catalog load failed: ${error.runtimeType}');
      setState(() => _loading = false);
    }
  }

  void _onSubscribePressed() {
    if (_loading) return;
    final offer = _offerFor(_plan);
    if (offer == null || offer.price == null) {
      unawaited(_load());
      return;
    }
    // Sale availability is a business guard, not a presentation state.
    if (!offer.product.saleEnabled) return;
    showGenesisToast(context, 'Pro subscriptions are coming soon.');
  }

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
                  for (final plan in _ProPlan.values) ...[
                    if (plan == _ProPlan.monthly) const SizedBox(width: 20),
                    Expanded(
                      child: _ProPlanCard(
                        plan: plan,
                        offer: _offerFor(plan),
                        savings: _offerFor(plan) == null
                            ? null
                            : membershipYearlySavings(
                                _offerFor(plan)!,
                                _offers,
                              ),
                        selected: _plan == plan,
                        onTap: () => setState(() => _plan = plan),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 34),
              DecoratedBox(
                key: const ValueKey('pro-subscribe-gold-surface'),
                decoration: BoxDecoration(
                  gradient: proPurchaseButtonGradient,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x18A86A17),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: GenesisPrimaryButton(
                  key: const ValueKey('pro-subscribe-button'),
                  backgroundColor: Colors.transparent,
                  foregroundColor: proPurchaseInk,
                  side: const BorderSide(color: Color(0xFFC69A45)),
                  label:
                      '${_plan.label}: ${_offerFor(_plan)?.price?.formattedPrice ?? ''}',
                  height: 44,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  borderRadius: BorderRadius.circular(8),
                  onPressed: _onSubscribePressed,
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
                          textStyle: GenesisTypography.resolve(
                            context,
                            const TextStyle(fontSize: 11),
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
        proCopperAccent,
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
    required this.offer,
    required this.savings,
    required this.selected,
    required this.onTap,
  });

  final _ProPlan plan;
  final MembershipOffer? offer;
  final int? savings;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = offer?.price;
    final monthlyPrice = price == null
        ? ''
        : plan == _ProPlan.yearly
        ? NumberFormat.simpleCurrency(
            locale: Localizations.localeOf(context).toString(),
            name: price.currencyCode,
          ).format(price.amountMicros / 1000000 / offer!.product.billingMonths)
        : price.formattedPrice;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${plan.label} Pro, ${price?.formattedPrice ?? ''} per ${plan.period}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: selected ? proPurchaseTint : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: selected ? proPurchaseAccent : const Color(0xFFEBEBEB),
                width: 1,
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
                        style: TextStyle(
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
                                text: monthlyPrice,
                                style: TextStyle(
                                  fontSize: 24,
                                  height: 28 / 24,
                                  fontWeight: FontWeight.w400,
                                  color: GenesisColors.textPrimary,
                                ),
                              ),
                              TextSpan(
                                text: '/mo',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: const Color(0xFF888888),
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
          if (plan == _ProPlan.yearly)
            Positioned(
              left: 0,
              top: -9,
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('pro-yearly-savings-badge'),
                  height: 21,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: const BoxDecoration(
                    color: proCopperAccent,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(3),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: 12,
                        color: Colors.white,
                      ),
                      SizedBox(width: 3),
                      Text(
                        savings == null ? '' : 'Save $savings%',
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
