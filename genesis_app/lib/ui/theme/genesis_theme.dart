import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../system/genesis_system_ui.dart';
import '../tokens/genesis_colors.dart';
import '../tokens/genesis_radii.dart';
import '../tokens/genesis_typography.dart';
import 'genesis_ui_theme.dart';

/// App-wide scrolling behavior that keeps platform scroll physics while
/// removing Material overscroll decorations such as Android's stretch effect.
class GenesisScrollBehavior extends MaterialScrollBehavior {
  const GenesisScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

// GenesisTheme is the single entry point for app-level ThemeData.
// This class connects the Flutter Material theme with the custom Genesis UI component theme.
abstract final class GenesisTheme {
  /// Production defaults. Light remains available for developer tools.
  static ThemeData dark() => asDark(light());

  /// Shared by the root theme and existing local dark scopes.
  static ThemeData asDark(ThemeData base) {
    final baseUi = base.extension<GenesisUiTheme>() ?? GenesisUiTheme.light();
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
      tabSelectedColor: GenesisColors.darkTextPrimary,
      tabUnselectedColor: GenesisColors.darkTextSecondary,
      tabIndicatorColor: GenesisColors.redPrimary,
      searchBackgroundColor: GenesisColors.darkFaintFill,
      searchIconColor: GenesisColors.darkTextSecondary,
      searchHintStyle: baseUi.searchHintStyle.copyWith(
        color: GenesisColors.darkInputPlaceholder,
      ),
      searchTextStyle: baseUi.searchTextStyle.copyWith(
        color: GenesisColors.darkTextPrimary,
      ),
    );
    final scheme =
        ColorScheme.fromSeed(
          seedColor: GenesisColors.redPrimary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: GenesisColors.redPrimary,
          onPrimary: GenesisColors.darkTextPrimary,
          surface: GenesisColors.darkBackground,
          surfaceDim: GenesisColors.darkBackground,
          surfaceBright: GenesisColors.darkRaisedBackground,
          surfaceContainerLowest: GenesisColors.darkBackground,
          surfaceContainerLow: GenesisColors.darkRaisedBackground,
          surfaceContainer: GenesisColors.darkRaisedBackground,
          surfaceContainerHigh: GenesisColors.darkRaisedBackground,
          surfaceContainerHighest: GenesisColors.darkFaintSurface,
          onSurface: GenesisColors.darkTextPrimary,
          onSurfaceVariant: GenesisColors.darkTextSecondary,
          outline: GenesisColors.darkFaintFill,
          outlineVariant: GenesisColors.darkCardBorder,
        );
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: GenesisColors.darkBackground,
      canvasColor: GenesisColors.darkBackground,
      cardColor: GenesisColors.darkRaisedBackground,
      disabledColor: GenesisColors.darkTextTertiary,
      hintColor: GenesisColors.darkInputPlaceholder,
      dividerColor: GenesisColors.darkFaintFill,
      textTheme: base.textTheme
          .apply(
            bodyColor: GenesisColors.darkTextPrimary,
            displayColor: GenesisColors.darkTextPrimary,
          )
          .copyWith(
            bodySmall: base.textTheme.bodySmall?.copyWith(
              color: GenesisColors.darkTextTertiary,
            ),
            labelMedium: base.textTheme.labelMedium?.copyWith(
              color: GenesisColors.darkTextSecondary,
            ),
          ),
      iconTheme: base.iconTheme.copyWith(
        color: GenesisColors.darkTextSecondary,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: GenesisColors.darkBackground,
        foregroundColor: GenesisColors.darkTextPrimary,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: kGenesisLightStatusIconsSystemUiOverlayStyle,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: GenesisColors.darkRaisedBackground,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: GenesisColors.darkRaisedBackground,
        modalBackgroundColor: GenesisColors.darkRaisedBackground,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: (base.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? GenesisColors.darkButtonDisabledBackground
                : GenesisColors.redPrimary,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? GenesisColors.darkButtonDisabledForeground
                : GenesisColors.darkTextPrimary,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: (base.textButtonTheme.style ?? const ButtonStyle()).copyWith(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? GenesisColors.darkTextTertiary
                : GenesisColors.darkTextSecondary,
          ),
        ),
      ),
      progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
        color: GenesisColors.darkTextSecondary,
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        labelColor: GenesisColors.darkTextPrimary,
        unselectedLabelColor: GenesisColors.darkTextSecondary,
        indicatorColor: GenesisColors.redPrimary,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: GenesisColors.darkFaintFill,
        hintStyle: (base.inputDecorationTheme.hintStyle ?? const TextStyle())
            .copyWith(color: GenesisColors.darkInputPlaceholder),
      ),
      textSelectionTheme: base.textSelectionTheme.copyWith(
        cursorColor: GenesisColors.darkTextPrimary,
        selectionHandleColor: GenesisColors.darkTextPrimary,
        selectionColor: GenesisColors.darkFaintFill,
      ),
      extensions: [
        ...base.extensions.values.where((value) => value is! GenesisUiTheme),
        ui,
      ],
    );
  }

  static ThemeData light() {
    // The base palette for Material components; seedColor determines derived Material colors such as default button and state colors.
    final colorScheme = ColorScheme.fromSeed(
      // Use the shared brand color as the seed for Material component defaults.
      seedColor: GenesisColors.brandBright,
      // Retained for explicitly excluded developer tools.
      brightness: Brightness.light,
    ).copyWith(primary: GenesisColors.brand);

    return ThemeData(
      // The standard color system consumed by Flutter Material components.
      colorScheme: colorScheme,
      fontFamily: GenesisTypography.fontFamily,
      fontFamilyFallback: GenesisTypography.fontFamilyFallback,
      // Product interactions use state changes rather than Material ripple,
      // pressed, hover, or focus overlays.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      // The default page background color, used when a Scaffold does not set one explicitly.
      scaffoldBackgroundColor: GenesisColors.surface,
      // The standard app TextTheme, available to regular Text widgets through Theme.of(context).textTheme.
      textTheme: GenesisTypography.textTheme,
      // Keep Material 3 enabled to avoid mixing legacy and current Material defaults.
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        systemOverlayStyle: kGenesisDefaultSystemUiOverlayStyle,
      ),
      // The global default FilledButton style, also inherited by GenesisPrimaryButton.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Primary button background color when enabled.
          backgroundColor: GenesisColors.brand,
          // Primary button background color when disabled.
          disabledBackgroundColor: GenesisColors.brandSoft,
          // Primary button text and icon foreground color.
          foregroundColor: GenesisColors.surface,
          // Use an 8dp radius for all buttons; locally sized buttons should follow the same radius rule.
          shape: const RoundedRectangleBorder(
            borderRadius: GenesisRadii.button,
          ),
          // Default primary button text style.
          textStyle: GenesisTypography.bodyStrong,
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(
            borderRadius: GenesisRadii.button,
          ),
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(
            borderRadius: GenesisRadii.button,
          ),
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: const RoundedRectangleBorder(
            borderRadius: GenesisRadii.button,
          ),
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        splashColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
      ),
      checkboxTheme: const CheckboxThemeData(
        overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        splashRadius: 0,
      ),
      radioTheme: const RadioThemeData(
        overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        splashRadius: 0,
      ),
      switchTheme: const SwitchThemeData(
        overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        splashRadius: 0,
      ),
      tabBarTheme: const TabBarThemeData(
        overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
      ),
      // The default TextField and InputDecorator style; editable GenesisSearchField instances reuse part of it.
      inputDecorationTheme: const InputDecorationTheme(
        // Do not draw a Material border by default; the outer container provides the background and radius.
        border: InputBorder.none,
        // Collapse the default TextField height so Material padding does not make the search field too tall.
        isCollapsed: true,
        // Default input placeholder style.
        hintStyle: TextStyle(
          color: GenesisColors.textDisabled,
          fontSize: 14,
          letterSpacing: 0,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: GenesisColors.textPrimary,
        selectionColor: GenesisColors.create.withValues(alpha: 0.32),
        selectionHandleColor: GenesisColors.create,
      ),
      // Theme extension for custom Genesis UI components.
      // SearchField, PageTitle, BottomNavigation, TabBar, and similar components read styles from this extension first.
      extensions: <ThemeExtension<dynamic>>[GenesisUiTheme.light()],
    );
  }
}

/// Keeps explicitly excluded developer tools in their original light appearance.
class GenesisLightTheme extends StatelessWidget {
  const GenesisLightTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: GenesisTheme.light(),
    child: DefaultTextStyle(
      style: GenesisTypography.body,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: kGenesisDefaultSystemUiOverlayStyle,
        child: child,
      ),
    ),
  );
}
