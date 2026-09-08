import 'package:flutter/material.dart';

import '../tokens/genesis_colors.dart';
import 'genesis_ui_theme.dart';

/// Opt-in dark surfaces without changing the application's light defaults.
class GenesisDarkTheme extends StatelessWidget {
  const GenesisDarkTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final baseUi = GenesisUiTheme.of(context);
    final ui = baseUi.copyWith(
      pageTitleStyle: baseUi.pageTitleStyle.copyWith(
        color: GenesisColors.darkTextPrimary,
      ),
      bodyStyle: baseUi.bodyStyle.copyWith(
        color: GenesisColors.darkTextPrimary,
      ),
      bodyStrongStyle: baseUi.bodyStrongStyle.copyWith(
        color: GenesisColors.darkTextPrimary,
      ),
      searchBackgroundColor: GenesisColors.darkFaintFill,
      searchIconColor: GenesisColors.darkTextSecondary,
      searchHintStyle: baseUi.searchHintStyle.copyWith(
        color: GenesisColors.darkInputPlaceholder,
      ),
      searchTextStyle: baseUi.searchTextStyle.copyWith(
        color: GenesisColors.darkTextPrimary,
      ),
    );
    return Theme(
      data: base.copyWith(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: GenesisColors.darkBackground,
        colorScheme: base.colorScheme.copyWith(
          brightness: Brightness.dark,
          surface: GenesisColors.darkBackground,
          onSurface: GenesisColors.darkTextPrimary,
          primary: GenesisColors.redPrimary,
        ),
        textTheme: base.textTheme.apply(
          bodyColor: GenesisColors.darkTextPrimary,
          displayColor: GenesisColors.darkTextPrimary,
        ),
        iconTheme: base.iconTheme.copyWith(
          color: GenesisColors.darkTextSecondary,
        ),
        dividerColor: GenesisColors.darkFaintFill,
        extensions: [
          ...base.extensions.values.where(
            (extension) => extension is! GenesisUiTheme,
          ),
          ui,
        ],
      ),
      child: child,
    );
  }
}
