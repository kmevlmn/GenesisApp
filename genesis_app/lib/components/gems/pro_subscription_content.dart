import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/bootstrap/service_registry.dart';
import '../../app/membership/membership_catalog.dart';
import '../../app/membership/membership_purchase_service.dart';
import '../../app/membership/membership_purchase_eligibility.dart';
import '../../platform/billing/purchase_toast_diagnostics.dart';
import '../../icons/custom_icon_assets.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_primary_button.dart';
import '../../ui/components/genesis_soft_italic_text.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/tokens/genesis_typography.dart';
import '../../network/models/membership_product.dart';
import '../../network/models/membership_benefit.dart';
import 'gem_purchase_state.dart';
import 'membership_purchase_presentation.dart';
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

class ProSubscriptionContent extends StatefulWidget {
  const ProSubscriptionContent({
    super.key,
    this.productsLoader,
    this.purchaseHandler,
    this.purchaseService,
    this.closeOnPurchaseSuccess = false,
  });

  final MembershipCatalogLoader? productsLoader;
  final Future<void> Function(MembershipProduct)? purchaseHandler;
  final MembershipPurchaseService? purchaseService;
  final bool closeOnPurchaseSuccess;

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
  MembershipPurchasePresentation? _purchasePresentation;
  MembershipPurchaseService? _presentationService;
  MembershipPurchaseService? _catalogService;

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
      _bindPurchaseUpdates();
      _purchasePresentation?.dispose();
      _purchasePresentation = null;
      _presentationService = null;
      services?.sessionRevision.addListener(_sessionChanged);
      _started = true;
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(ProSubscriptionContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productsLoader != widget.productsLoader) unawaited(_load());
    _bindPurchaseUpdates();
  }

  void _bindPurchaseUpdates() {
    final service = widget.purchaseService ?? _services?.membershipPurchases;
    if (identical(service, _catalogService)) return;
    _catalogService?.catalogRevision.removeListener(_purchaseChanged);
    _catalogService = service;
    service?.catalogRevision.addListener(_purchaseChanged);
  }

  void _purchaseChanged() {
    // A catalog refresh caused by restore must not start another restore.
    unawaited(_load(silent: true, restorePurchases: false));
  }

  void _sessionChanged() {
    _plan = _ProPlan.yearly;
    unawaited(_load());
  }

  @override
  void dispose() {
    _purchasePresentation?.dispose();
    _requestGeneration++;
    _services?.sessionRevision.removeListener(_sessionChanged);
    _catalogService?.catalogRevision.removeListener(_purchaseChanged);
    super.dispose();
  }

  Future<void> _load({
    bool silent = false,
    bool restorePurchases = true,
  }) async {
    final request = ++_requestGeneration;
    setState(() {
      if (!silent) {
        _loading = true;
        _offers = [];
      }
    });
    try {
      final loader = widget.productsLoader ?? _services?.membershipCatalog.load;
      if (loader == null) throw MembershipPlatformUnavailable();
      final catalog = await loader();
      if (!mounted || request != _requestGeneration) return;
      setState(() {
        _offers = catalog.offers;
        if (_offerFor(_plan) == null && _offers.isNotEmpty) {
          _plan = _ProPlan.values.firstWhere((plan) => _offerFor(plan) != null);
        }
        _loading = false;
      });
      if (restorePurchases) {
        unawaited(
          (widget.purchaseService ?? _services?.membershipPurchases)
              ?.restorePurchases(
                products: catalog.offers.map((offer) => offer.product).toList(),
              ),
        );
      }
    } catch (error) {
      if (!mounted || request != _requestGeneration) return;
      debugPrint('[Membership] catalog load failed: ${error.runtimeType}');
      setState(() => _loading = false);
    }
  }

  Future<void> _onSubscribePressed() async {
    if (_loading) return;
    final offer = _offerFor(_plan);
    if (offer == null || offer.price == null) {
      unawaited(_load());
      return;
    }
    final blocked = membershipPurchaseBlockReason(offer.product);
    if (blocked != null) {
      showGenesisToast(context, membershipPurchaseFailureMessage(blocked));
      unawaited(_load(silent: true, restorePurchases: false));
      return;
    }
    final handler = widget.purchaseHandler;
    if (handler != null) {
      await handler(offer.product);
      return;
    }
    final service = widget.purchaseService ?? _services?.membershipPurchases;
    if (service == null) {
      showGenesisToast(
        context,
        purchaseToastMessage(
          'VIP purchase is unavailable.',
          debugInfo: purchaseDebugInfo(
            'vip.precheck',
            reason: 'service_unavailable',
          ),
        ),
      );
      return;
    }
    if (!identical(service, _presentationService)) {
      _purchasePresentation?.dispose();
      _presentationService = service;
      _purchasePresentation = MembershipPurchasePresentation(
        context: context,
        service: service,
      );
    }
    final confirmed = await _purchasePresentation!.purchase(offer.product);
    if (confirmed &&
        mounted &&
        widget.closeOnPurchaseSuccess &&
        ModalRoute.of(context)?.isCurrent == true) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedProduct = _offerFor(_plan)?.product;
    if (_loading) {
      // Match Buy Gems' initial loading indicator in the same tab content area.
      return const GemPurchaseLoading();
    }
    return Column(
      children: [
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            key: const ValueKey('pro-benefits-card'),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: GenesisColors.darkCardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: GenesisColors.darkCardBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GenesisSoftItalicText(
                        'Premium',
                        key: const ValueKey('pro-tier-title'),
                        style: const TextStyle(
                          fontSize: 28,
                          height: 34 / 28,
                          fontWeight: FontWeight.w700,
                          color: GenesisColors.darkTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Divider(
                        height: 1,
                        color: GenesisColors.darkFaintFill,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    key: const PageStorageKey('pro-benefits-scroll'),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    children: [
                      for (final benefit
                          in selectedProduct?.benefits ??
                              const <MembershipBenefit>[])
                        _ProBenefit(
                          key: ValueKey('pro-benefit-${benefit.code}'),
                          label: benefit.title,
                          status: benefit.displayType,
                          asset: _benefitIcon(benefit.iconKey).$1,
                          icon: _benefitIcon(benefit.iconKey).$2,
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
                      selectedProduct?.canPurchase == false &&
                          selectedProduct?.purchaseBlockReason ==
                              'already_subscribed'
                      ? 'Subscribed'
                      : '${_plan.label}: ${_offerFor(_plan)?.price?.formattedPrice ?? ''}',
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
                          foregroundColor: GenesisColors.darkTextSecondary,
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

// The API supplies icon identifiers, never asset paths or executable content.
// Keep the existing local artwork; unknown identifiers use a generic benefit icon.
(String?, IconData?) _benefitIcon(String key) => switch (key) {
  'blue_gem' => (null, Icons.diamond_outlined),
  'character_slots' => (characterStatIconAsset, null),
  'inspiration' => (inspirationIconAsset, null),
  'edit_reply' => (editSquareIconAsset, null),
  'memory' => (null, Icons.memory_outlined),
  'save_conversation' => (null, Icons.download_outlined),
  'chat_background' => (null, Icons.wallpaper_outlined),
  'no_watermark' => (null, Icons.hide_image_outlined),
  'custom_character' => (createOriginCharactersIconAsset, null),
  'community_world' => (null, Icons.public_outlined),
  _ => (null, Icons.stars_outlined),
};

class _ProBenefit extends StatelessWidget {
  const _ProBenefit({
    super.key,
    required this.label,
    required this.status,
    this.asset,
    this.icon,
  });

  final String label;
  final MembershipBenefitDisplay status;
  final String? asset;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final locked = status == MembershipBenefitDisplay.locked;
    final color = locked
        ? GenesisColors.darkTextTertiary
        : GenesisColors.darkTextSecondary;
    final (statusIcon, statusColor, statusLabel) = switch (status) {
      MembershipBenefitDisplay.enhanced => (
        null,
        proCopperAccent,
        'Improved with Pro',
      ),
      MembershipBenefitDisplay.included => (
        Icons.check_rounded,
        GenesisColors.darkTextPrimary,
        'Same as free',
      ),
      MembershipBenefitDisplay.locked => (
        Icons.lock_outline_rounded,
        GenesisColors.darkTextTertiary,
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
              color: GenesisColors.darkFaintFill,
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
          if (status == MembershipBenefitDisplay.enhanced)
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
            decimalDigits: 2,
          ).format(price.amountCent / 100 / offer!.product.billingMonths)
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
            color: selected
                ? proPurchaseTint
                : GenesisColors.darkCardBackground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: selected
                    ? proPurchaseAccent
                    : GenesisColors.darkCardBorder,
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
                          color: GenesisColors.darkTextPrimary,
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
                                  color: GenesisColors.darkTextPrimary,
                                ),
                              ),
                              TextSpan(
                                text: '/mo',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: GenesisColors.darkTextTertiary,
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
