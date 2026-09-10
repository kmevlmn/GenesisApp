import 'package:flutter/material.dart';

import 'genesis_colors.dart';

abstract final class GenesisTypography {
  /// Resolve theme typography for painters and controls that do not inherit
  /// DefaultTextStyle automatically. Local styles need only specify overrides.
  static TextStyle resolve(BuildContext context, TextStyle style) =>
      Theme.of(context).textTheme.bodyMedium!.merge(style);

  static const String fontFamily = 'Inter';
  static const List<String> fontFamilyFallback = <String>[
    'PingFang SC',
    'Noto Sans CJK SC',
    'Noto Sans SC',
  ];

  /// Keep the former iOS-only synthetic skew available without making it the
  /// default. Both platforms currently use the bundled Inter italic face.
  static const bool useIosSoftItalicSkew = false;
  static const double iosInlineEmphasisSkew = -0.16;

  static const TextStyle pageTitle = TextStyle(
    color: GenesisColors.textPrimary,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle body = TextStyle(
    color: GenesisColors.textPrimary,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14,
    height: 1.4,
  );

  static const TextStyle bodyStrong = TextStyle(
    color: GenesisColors.textPrimary,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle supporting = TextStyle(
    color: GenesisColors.textSecondary,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12,
    height: 1.4,
  );

  static const TextStyle tabLabel = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 11,
    height: 1.4,
  );

  static TextTheme get textTheme => const TextTheme(
    titleMedium: pageTitle,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: supporting,
    labelSmall: tabLabel,
  );

  static TextStyle withFallback(TextStyle style) {
    if (style.fontFamily != null) {
      return style;
    }
    return style.copyWith(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
  }

  static TextStyle inlineEmphasis(
    TextStyle baseStyle, {
    required TargetPlatform platform,
    Color? color,
    bool useIosSkew = useIosSoftItalicSkew,
  }) {
    final style = baseStyle.copyWith(color: color);
    if (platform == TargetPlatform.iOS && useIosSkew) {
      return style.copyWith(fontStyle: FontStyle.normal);
    }
    return style.copyWith(fontStyle: FontStyle.italic);
  }
}
