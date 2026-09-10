import 'package:flutter/material.dart';

import '../tokens/genesis_colors.dart';
import '../tokens/genesis_typography.dart';

/// Shared number layout for unread and map event badges.
/// Callers decide when to hide the badge and where to position it.
class GenesisCountBadge extends StatelessWidget {
  const GenesisCountBadge({
    super.key,
    required this.count,
    this.height = 16,
    this.fontSize = 10,
    this.fontWeight = FontWeight.w600,
    this.horizontalPadding = 4,
  });

  final int count;
  final double height;
  final double fontSize;
  final FontWeight fontWeight;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    final isSingleDigit = count >= 0 && count < 10;
    return Container(
      width: isSingleDigit ? height : null,
      height: height,
      constraints: BoxConstraints(minWidth: height),
      padding: isSingleDigit
          ? EdgeInsets.zero
          : EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: GenesisColors.redPrimary,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            inherit: false,
            fontFamily: GenesisTypography.fontFamily,
            fontFamilyFallback: GenesisTypography.fontFamilyFallback,
            color: Colors.white,
            fontSize: fontSize,
            height: 1,
            fontWeight: fontWeight,
          ),
        ),
      ),
    );
  }
}
