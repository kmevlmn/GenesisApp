import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../ui/tokens/genesis_colors.dart';

class GenesisLogo extends StatelessWidget {
  const GenesisLogo({
    super.key,
    this.height = 32,
    this.width,
    this.semanticsLabel,
  });

  final double height;
  final double? width;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      dark ? 'assets/svg/worldo-logo-dark.svg' : 'assets/svg/worldo-logo.svg',
      height: height,
      width: width,
      fit: BoxFit.contain,
      semanticsLabel: semanticsLabel,
      colorMapper: dark ? const _DarkLogoColorMapper() : null,
    );
  }
}

class _DarkLogoColorMapper extends ColorMapper {
  const _DarkLogoColorMapper();

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    if (color == GenesisColors.redPrimary) return GenesisColors.darkTextPrimary;
    if (color == Colors.white) return GenesisColors.redSecondary;
    return color;
  }
}
