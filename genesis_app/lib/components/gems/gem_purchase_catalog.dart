import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../network/models/gem_product.dart';
import '../../platform/billing/billing_models.dart';
import '../../utils/gem_amount.dart';
import 'gem_assets.dart';
import 'gem_balance_text.dart';
import 'gem_colors.dart';

const double kGemProductCardHeight = 140;
const double kGemPriceButtonHeight = 24;

class GemPurchaseCatalogSection extends StatelessWidget {
  const GemPurchaseCatalogSection({
    super.key,
    required this.balanceCent,
    required this.catalog,
    this.balanceKey = const ValueKey<String>('gem-wallet-balance'),
  });

  final int balanceCent;
  final Key balanceKey;
  final Widget catalog;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GemBalancePanel(balanceCent: balanceCent, balanceKey: balanceKey),
        const SizedBox(height: 10),
        catalog,
      ],
    );
  }
}

class GemBalancePanel extends StatelessWidget {
  const GemBalancePanel({
    super.key,
    required this.balanceCent,
    this.balanceKey = const ValueKey<String>('gem-wallet-balance'),
  });

  final int balanceCent;
  final Key balanceKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('gem-balance-panel'),
      width: double.infinity,
      height: 95,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SvgPicture.asset(
                  gemIconAsset,
                  key: const ValueKey('gem-balance-icon'),
                  width: gemLargeIconSize,
                  height: gemLargeIconSize,
                ),
                const SizedBox(width: 8),
                const Text(
                  'My Balance',
                  style: TextStyle(
                    fontSize: 14,
                    height: 18 / 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text.rich(
              gemBalanceTextSpan(balanceCent, fontSize: 30),
              key: balanceKey,
              style: const TextStyle(
                fontSize: 30,
                height: 40 / 30,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GemProductGrid extends StatelessWidget {
  const GemProductGrid({
    super.key,
    required this.products,
    required this.billingStateListenable,
    required this.onPurchase,
  });

  final List<GemProduct> products;
  final ValueListenable<BillingState> billingStateListenable;
  final ValueChanged<GemProduct> onPurchase;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BillingState>(
      valueListenable: billingStateListenable,
      builder: (context, billingState, _) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: products.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 12,
          mainAxisExtent: kGemProductCardHeight,
        ),
        itemBuilder: (context, index) {
          final product = products[index];
          return GemProductCard(
            product: product,
            isBuying: billingState.isBusy(product.productId),
            isPurchaseInProgress: billingState.hasBusyPurchase,
            onPurchase: () => onPurchase(product),
          );
        },
      ),
    );
  }
}

class GemProductCard extends StatelessWidget {
  const GemProductCard({
    super.key,
    required this.product,
    required this.isBuying,
    required this.isPurchaseInProgress,
    required this.onPurchase,
  });

  final GemProduct product;
  final bool isBuying;
  final bool isPurchaseInProgress;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    final isNewUserProduct = product.productId.trim() == 'gem_pack_500';
    final isSoldOut = isNewUserProduct && !product.canPurchase;
    final tag = product.tagText;
    final hasBonusGems = product.bonusGemsCent > 0;
    final defaultTagColor = isNewUserProduct
        ? const Color(0xFFE85C39)
        : const Color(0xFFB53B52);
    final tagColor = _parseActivityColor(
      product.activityColor,
      fallback: defaultTagColor,
    );
    const tagTextStyle = TextStyle(
      fontSize: 10,
      height: 14 / 10,
      fontWeight: FontWeight.w400,
      color: Colors.white,
    );
    final tagPainter = TextPainter(
      text: TextSpan(text: tag, style: tagTextStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final tagWidth = (tagPainter.width + 8).clamp(46.0, 86.0).toDouble();
    final enabled = product.canPurchase && !isPurchaseInProgress;
    return Semantics(
      button: true,
      enabled: enabled,
      label: isSoldOut
          ? 'Sold out ${product.productId}'
          : 'Buy ${product.productId}',
      child: GestureDetector(
        key: ValueKey<String>('gem-product-${product.productId}'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPurchase : null,
        child: Opacity(
          opacity: product.canPurchase || isSoldOut ? 1 : 0.45,
          child: _UnavailableProductFilter(
            unavailable: !product.canPurchase && !isSoldOut,
            child: Container(
              clipBehavior: Clip.none,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEBEBEB)),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (tag.isNotEmpty)
                    Positioned(
                      left: -1,
                      top: -1,
                      child: SizedBox(
                        width: tagWidth,
                        height: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tagColor,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(tag, maxLines: 1, style: tagTextStyle),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 18,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: SvgPicture.asset(
                        gemStackIconAsset,
                        key: ValueKey<String>(
                          'gem-product-icon-${product.productId}',
                        ),
                        width: gemStackIconWidth,
                        height: gemStackIconHeight,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 68,
                    left: 8,
                    right: 8,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '+${formatWholeGemCent(product.totalGemsCent)}',
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111111),
                        ),
                      ),
                    ),
                  ),
                  if (hasBonusGems)
                    Positioned(
                      top: 88,
                      bottom: 38,
                      left: 8,
                      right: 8,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatWholeGemCent(product.baseGemsCent),
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 14 / 12,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF888888),
                            decoration: TextDecoration.lineThrough,
                            decorationColor: Color(0xFF888888),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    height: kGemPriceButtonHeight,
                    child: Container(
                      key: ValueKey<String>(
                        'gem-product-price-${product.productId}',
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSoldOut ? Colors.transparent : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSoldOut
                              ? kGemSoldOutBorderColor
                              : kGemAccentColor,
                        ),
                      ),
                      child: isBuying && !isSoldOut
                          ? const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: kGemAccentColor,
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                isSoldOut
                                    ? 'Sold Out'
                                    : formatGemPrice(
                                        product.priceAmount,
                                        product.priceCurrencyCode,
                                      ),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 14 / 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSoldOut
                                      ? kGemSoldOutForegroundColor
                                      : kGemAccentColor,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnavailableProductFilter extends StatelessWidget {
  const _UnavailableProductFilter({
    required this.unavailable,
    required this.child,
  });

  final bool unavailable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!unavailable) return child;
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation),
      child: child,
    );
  }
}

String formatGemPrice(int cents, String currencyCode) {
  final amount = cents / 100;
  var text = amount.toStringAsFixed(2);
  if (text.endsWith('0')) text = text.substring(0, text.length - 1);
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  final cleanCurrencyCode = currencyCode.trim().toUpperCase();
  final currencyLabel = cleanCurrencyCode == 'USD' ? r'$' : cleanCurrencyCode;
  return '$currencyLabel$text';
}

Color _parseActivityColor(String value, {required Color fallback}) {
  final normalized = value.trim().replaceFirst('#', '');
  if (normalized.length != 6 && normalized.length != 8) return fallback;
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return fallback;
  if (normalized.length == 6) return Color(0xFF000000 | parsed);
  return Color(parsed);
}
