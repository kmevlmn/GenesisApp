import 'dart:ui';

import '../tokens/genesis_blur.dart';

import 'package:flutter/material.dart';

const Color genesisMapTopGlassBarColor = Color(0x80151517);
const double genesisMapTopGlassBarBlurSigma = GenesisBlur.strong;
const double genesisMapTopGlassBarRadius = 12;

// Match Location Chat's unchanged 48px back-button slot in its 50px header.
// The 38px glass plate centers its 17px arrow at (24, safeTop + 25).
const double genesisMapBackButtonDimension = 38;
const double genesisMapBackButtonLeft =
    (48 - genesisMapBackButtonDimension) / 2;
const double genesisMapBackButtonTop = (50 - genesisMapBackButtonDimension) / 2;
const double genesisMapBackIconSize = 17;
const double genesisMapTopBarRightInset = 12;

class GenesisMapGlassBackButton extends StatelessWidget {
  const GenesisMapGlassBackButton({
    super.key,
    required this.dimension,
    required this.onPressed,
    this.glassKey,
    this.surfaceKey,
  });

  final double dimension;
  final VoidCallback onPressed;
  final Key? glassKey;
  final Key? surfaceKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: dimension,
      height: dimension,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(genesisMapTopGlassBarRadius),
        child: BackdropFilter(
          key: glassKey,
          filter: ImageFilter.blur(
            sigmaX: genesisMapTopGlassBarBlurSigma,
            sigmaY: genesisMapTopGlassBarBlurSigma,
          ),
          child: Material(
            key: surfaceKey,
            color: genesisMapTopGlassBarColor,
            child: IconButton(
              iconSize: genesisMapBackIconSize,
              onPressed: onPressed,
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }
}
