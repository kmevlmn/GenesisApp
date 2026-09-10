import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_colors.dart';

abstract final class DiscussDarkColors {
  static const background = GenesisColors.darkBackground;
  static const surface = GenesisColors.darkFaintSurface;
  static const inputFill = GenesisColors.darkFaintFill;
  static const primary = GenesisColors.darkTextPrimary;
  static const secondary = GenesisColors.darkTextSecondary;
  static const muted = GenesisColors.darkTextTertiary;
  static const border = Color(0x24FFFFFF);
  static const accent = GenesisColors.brand;
}

/// Scopes default text, loading and action colors to the discussion pages.
class DiscussDarkTheme extends StatelessWidget {
  const DiscussDarkTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: DiscussDarkColors.background,
        colorScheme: base.colorScheme.copyWith(
          brightness: Brightness.dark,
          surface: DiscussDarkColors.surface,
          onSurface: DiscussDarkColors.primary,
          primary: DiscussDarkColors.accent,
        ),
        textTheme: base.textTheme.apply(
          bodyColor: DiscussDarkColors.primary,
          displayColor: DiscussDarkColors.primary,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: DiscussDarkColors.secondary,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: DiscussDarkColors.secondary,
            disabledForegroundColor: DiscussDarkColors.muted,
          ),
        ),
      ),
      child: child,
    );
  }
}
