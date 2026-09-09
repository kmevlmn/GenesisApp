import 'package:flutter/material.dart';

abstract final class GenesisColors {
  static const Color darkBackground = Color(0xFF151517);
  static const Color darkTextPrimary = Color(0xF2FFFFFF);
  static const Color darkTextSecondary = Color(0xB8FFFFFF);
  static const Color darkTextTertiary = Color(0x73FFFFFF);
  static const Color darkRaisedBackground = Color(0xFF181C1F);
  static const Color darkInputPlaceholder = Color(0x52FFFFFF);
  static const Color darkHandleActive = darkTextPrimary;
  static const Color darkHandleInactive = darkTextTertiary;

  // Worldo Detail's Write a post fill, shared by discussion surfaces.
  static const Color darkFaintFill = Color(0x1FFFFFFF);
  // The same fill composited over #151517 for surfaces that must be opaque.
  static const Color darkFaintSurface = Color(0xFF313133);

  // Opaque toast surface sampled from the approved dark reference.
  static const Color darkToastBackground = Color(0xFF424244);

  // Red hierarchy: actions, readable accent text, pale/disabled fills.
  static const Color redPrimary = Color(0xFFFF2442);
  static const Color redSecondary = Color(0xFFFF8A9A);
  static const Color redTertiary = Color(0xFFFFB8C3);

  // Disabled filled primary actions on dark surfaces; preserve icon-button styles.
  static final Color darkButtonDisabledBackground = redPrimary.withValues(
    alpha: 0.4,
  );
  // Flatten secondary white over the base surface so red cannot tint the text.
  static final Color darkButtonDisabledForeground = Color.alphaBlend(
    darkTextSecondary,
    darkBackground,
  );

  // Existing semantic names remain aliases of the shared red hierarchy.
  static const Color brand = redPrimary;
  static const Color brandBright = brand;
  static const Color brandSoft = redTertiary;
  static const Color create = redPrimary;
  static const Color createAdd = Color(0xFFC41F2E);

  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFF9F9F9);
  static const Color surfaceInput = Color(0xFFF2F2F2);
  static const Color surfacePanel = Color(0xFFF5F5F7);

  static const Color textPrimary = Color(0xFF111111);
  static const Color textSecondary = Color(0xFF6F6F6F);
  static const Color textTertiary = Color(0xFF8D8D8D);
  static const Color textDisabled = Color(0xFF9E9E9E);
  static const Color tabSelected = Color(0xFF000000);
  static const Color tabUnselected = Color(0xFF666666);

  static const Color border = Color(0xFFE6E6E8);
  static const Color borderStrong = Color(0xFFDCDCDC);
  static const Color danger = redPrimary;
}
