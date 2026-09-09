import 'dart:ui';

import 'package:flutter/material.dart';

import '../tokens/genesis_colors.dart';
import '../tokens/genesis_radii.dart';
import '../tokens/genesis_typography.dart';

// GenesisUiTheme is the ThemeExtension dedicated to the UI component library.
// Material ThemeData does not know about custom components such as GenesisSearchField or GenesisBottomNavigation,
// so their colors, typography, radii, and indicator dimensions are centralized here.
class GenesisUiTheme extends ThemeExtension<GenesisUiTheme> {
  const GenesisUiTheme({
    // Page title style, currently used by GenesisPageTitle.
    required this.pageTitleStyle,
    // General body style, currently used by components such as unselected GenesisTabBar labels.
    required this.bodyStyle,
    // Emphasized body style, currently used by components such as selected GenesisTabBar labels.
    required this.bodyStrongStyle,
    // Bottom navigation label style, currently used by GenesisBottomNavigationTile.
    required this.tabLabelStyle,
    // Search field background color, currently used by the GenesisSearchField outer container.
    required this.searchBackgroundColor,
    // Color of the search icon on the left side of the search field.
    required this.searchIconColor,
    // Search field placeholder text style.
    required this.searchHintStyle,
    // Search field input text style.
    required this.searchTextStyle,
    // Search field border radius.
    required this.searchBorderRadius,
    // Bottom navigation bar background color.
    required this.bottomNavigationBackgroundColor,
    // Selected color for regular bottom navigation tabs.
    required this.bottomNavigationSelectedColor,
    // Unselected color for regular bottom navigation tabs.
    required this.bottomNavigationUnselectedColor,
    // Color for prominent bottom navigation tabs, such as the center Create button.
    required this.bottomNavigationProminentColor,
    // Selected label color for the secondary TabBar.
    required this.tabSelectedColor,
    // Unselected label color for the secondary TabBar.
    required this.tabUnselectedColor,
    // Underline indicator color for the secondary TabBar.
    required this.tabIndicatorColor,
    // Underline indicator width for the secondary TabBar.
    required this.tabIndicatorWidth,
    // Underline indicator height for the secondary TabBar.
    required this.tabIndicatorHeight,
    // General panel and button radius, currently used by GenesisPrimaryButton.
    required this.panelBorderRadius,
  });

  // Default values for the light theme.
  // This is the main entry point for changing the overall UI library appearance; update it here instead of hard-coding colors inside components.
  factory GenesisUiTheme.light() {
    return GenesisUiTheme(
      // Use the global title token for page titles.
      pageTitleStyle: GenesisTypography.pageTitle,
      // Use the global body token for regular body text.
      bodyStyle: GenesisTypography.body,
      // Use the global emphasis token for emphasized body text.
      bodyStrongStyle: GenesisTypography.bodyStrong,
      // Use the dedicated small-text token for bottom tab labels.
      tabLabelStyle: GenesisTypography.tabLabel,
      // Use a light gray search field background by default.
      searchBackgroundColor: GenesisColors.surfaceInput,
      // Use a muted gray for the search icon by default.
      searchIconColor: GenesisColors.textDisabled,
      // Reuse the body text size for search hints, with a muted color.
      searchHintStyle: GenesisTypography.body.copyWith(
        color: GenesisColors.textDisabled,
        letterSpacing: 0,
      ),
      // Reuse the body style for search input text.
      searchTextStyle: GenesisTypography.body,
      // Use the input radius token for the search field.
      searchBorderRadius: GenesisRadii.input,
      // Bottom navigation background color.
      bottomNavigationBackgroundColor: GenesisColors.darkBackground,
      // Bottom navigation selected-state color.
      bottomNavigationSelectedColor: GenesisColors.darkTextPrimary,
      // Bottom navigation unselected-state color.
      bottomNavigationUnselectedColor: GenesisColors.darkTextSecondary,
      // Bottom navigation prominent-item color, such as Create.
      bottomNavigationProminentColor: GenesisColors.create,
      // Secondary tab selected color.
      tabSelectedColor: GenesisColors.tabSelected,
      // Secondary tab unselected color.
      tabUnselectedColor: GenesisColors.tabUnselected,
      // Use the status red color for the secondary tab indicator.
      tabIndicatorColor: GenesisColors.danger,
      // Keep the secondary tab indicator at a fixed width to match the current design.
      tabIndicatorWidth: 34,
      // Secondary tab indicator height.
      tabIndicatorHeight: 3,
      // General panel border radius.
      panelBorderRadius: GenesisRadii.panel,
    );
  }

  // Text style for GenesisPageTitle.
  final TextStyle pageTitleStyle;
  // General body text style.
  final TextStyle bodyStyle;
  // General emphasized body text style.
  final TextStyle bodyStrongStyle;
  // Bottom navigation label style.
  final TextStyle tabLabelStyle;
  // Background color for GenesisSearchField.
  final Color searchBackgroundColor;
  // Search icon color for GenesisSearchField.
  final Color searchIconColor;
  // Placeholder style for GenesisSearchField.
  final TextStyle searchHintStyle;
  // Input text style for GenesisSearchField.
  final TextStyle searchTextStyle;
  // Outer border radius for GenesisSearchField.
  final BorderRadius searchBorderRadius;
  // Background color for GenesisBottomNavigation.
  final Color bottomNavigationBackgroundColor;
  // Selected color for regular GenesisBottomNavigation items.
  final Color bottomNavigationSelectedColor;
  // Unselected color for regular GenesisBottomNavigation items.
  final Color bottomNavigationUnselectedColor;
  // Color for prominent GenesisBottomNavigation items.
  final Color bottomNavigationProminentColor;
  // Selected label color for GenesisTabBar.
  final Color tabSelectedColor;
  // Unselected label color for GenesisTabBar.
  final Color tabUnselectedColor;
  // Indicator color for GenesisTabBar.
  final Color tabIndicatorColor;
  // Indicator width for GenesisTabBar.
  final double tabIndicatorWidth;
  // Indicator height for GenesisTabBar.
  final double tabIndicatorHeight;
  // Border radius for panel-like components such as GenesisPrimaryButton.
  final BorderRadius panelBorderRadius;

  // Unified theme accessor for components.
  // Fall back to the light defaults when the outer MaterialApp does not provide GenesisUiTheme, avoiding null theme access.
  static GenesisUiTheme of(BuildContext context) {
    return Theme.of(context).extension<GenesisUiTheme>() ??
        GenesisUiTheme.light();
  }

  @override
  // Used to override selected styles, such as changing only the search background without affecting other components.
  GenesisUiTheme copyWith({
    // Override the page title style.
    TextStyle? pageTitleStyle,
    // Override the regular body style.
    TextStyle? bodyStyle,
    // Override the emphasized body style.
    TextStyle? bodyStrongStyle,
    // Override the bottom navigation label style.
    TextStyle? tabLabelStyle,
    // Override the search field background color.
    Color? searchBackgroundColor,
    // Override the search icon color.
    Color? searchIconColor,
    // Override the search hint style.
    TextStyle? searchHintStyle,
    // Override the search input text style.
    TextStyle? searchTextStyle,
    // Override the search field border radius.
    BorderRadius? searchBorderRadius,
    // Override the bottom navigation background color.
    Color? bottomNavigationBackgroundColor,
    // Override the bottom navigation selected color.
    Color? bottomNavigationSelectedColor,
    // Override the bottom navigation unselected color.
    Color? bottomNavigationUnselectedColor,
    // Override the bottom navigation prominent-item color.
    Color? bottomNavigationProminentColor,
    // Override the secondary tab selected color.
    Color? tabSelectedColor,
    // Override the secondary tab unselected color.
    Color? tabUnselectedColor,
    // Override the secondary tab indicator color.
    Color? tabIndicatorColor,
    // Override the secondary tab indicator width.
    double? tabIndicatorWidth,
    // Override the secondary tab indicator height.
    double? tabIndicatorHeight,
    // Override the general panel border radius.
    BorderRadius? panelBorderRadius,
  }) {
    return GenesisUiTheme(
      // Retain the current theme value when an argument is omitted so copyWith only changes specified fields.
      pageTitleStyle: pageTitleStyle ?? this.pageTitleStyle,
      bodyStyle: bodyStyle ?? this.bodyStyle,
      bodyStrongStyle: bodyStrongStyle ?? this.bodyStrongStyle,
      tabLabelStyle: tabLabelStyle ?? this.tabLabelStyle,
      searchBackgroundColor:
          searchBackgroundColor ?? this.searchBackgroundColor,
      searchIconColor: searchIconColor ?? this.searchIconColor,
      searchHintStyle: searchHintStyle ?? this.searchHintStyle,
      searchTextStyle: searchTextStyle ?? this.searchTextStyle,
      searchBorderRadius: searchBorderRadius ?? this.searchBorderRadius,
      bottomNavigationBackgroundColor:
          bottomNavigationBackgroundColor ??
          this.bottomNavigationBackgroundColor,
      bottomNavigationSelectedColor:
          bottomNavigationSelectedColor ?? this.bottomNavigationSelectedColor,
      bottomNavigationUnselectedColor:
          bottomNavigationUnselectedColor ??
          this.bottomNavigationUnselectedColor,
      bottomNavigationProminentColor:
          bottomNavigationProminentColor ?? this.bottomNavigationProminentColor,
      tabSelectedColor: tabSelectedColor ?? this.tabSelectedColor,
      tabUnselectedColor: tabUnselectedColor ?? this.tabUnselectedColor,
      tabIndicatorColor: tabIndicatorColor ?? this.tabIndicatorColor,
      tabIndicatorWidth: tabIndicatorWidth ?? this.tabIndicatorWidth,
      tabIndicatorHeight: tabIndicatorHeight ?? this.tabIndicatorHeight,
      panelBorderRadius: panelBorderRadius ?? this.panelBorderRadius,
    );
  }

  @override
  // Flutter calls lerp during theme changes and animated transitions.
  // Interpolate all colors, typography, radii, and dimensions to avoid abrupt jumps during theme changes.
  GenesisUiTheme lerp(ThemeExtension<GenesisUiTheme>? other, double t) {
    // Keep the current theme unchanged when the target theme has a different type.
    if (other is! GenesisUiTheme) return this;
    return GenesisUiTheme(
      // Interpolate the title text style.
      pageTitleStyle: TextStyle.lerp(pageTitleStyle, other.pageTitleStyle, t)!,
      // Interpolate the body text style.
      bodyStyle: TextStyle.lerp(bodyStyle, other.bodyStyle, t)!,
      // Interpolate the emphasized body style.
      bodyStrongStyle: TextStyle.lerp(
        bodyStrongStyle,
        other.bodyStrongStyle,
        t,
      )!,
      // Interpolate the bottom navigation label text style.
      tabLabelStyle: TextStyle.lerp(tabLabelStyle, other.tabLabelStyle, t)!,
      // Interpolate the search field background color.
      searchBackgroundColor: Color.lerp(
        searchBackgroundColor,
        other.searchBackgroundColor,
        t,
      )!,
      // Interpolate the search icon color.
      searchIconColor: Color.lerp(searchIconColor, other.searchIconColor, t)!,
      // Interpolate the search hint style.
      searchHintStyle: TextStyle.lerp(
        searchHintStyle,
        other.searchHintStyle,
        t,
      )!,
      // Interpolate the search input text style.
      searchTextStyle: TextStyle.lerp(
        searchTextStyle,
        other.searchTextStyle,
        t,
      )!,
      // Interpolate the search field border radius.
      searchBorderRadius: BorderRadius.lerp(
        searchBorderRadius,
        other.searchBorderRadius,
        t,
      )!,
      // Interpolate the bottom navigation background color.
      bottomNavigationBackgroundColor: Color.lerp(
        bottomNavigationBackgroundColor,
        other.bottomNavigationBackgroundColor,
        t,
      )!,
      // Interpolate the bottom navigation selected color.
      bottomNavigationSelectedColor: Color.lerp(
        bottomNavigationSelectedColor,
        other.bottomNavigationSelectedColor,
        t,
      )!,
      // Interpolate the bottom navigation unselected color.
      bottomNavigationUnselectedColor: Color.lerp(
        bottomNavigationUnselectedColor,
        other.bottomNavigationUnselectedColor,
        t,
      )!,
      // Interpolate the bottom navigation prominent-item color.
      bottomNavigationProminentColor: Color.lerp(
        bottomNavigationProminentColor,
        other.bottomNavigationProminentColor,
        t,
      )!,
      // Interpolate the secondary tab selected color.
      tabSelectedColor: Color.lerp(
        tabSelectedColor,
        other.tabSelectedColor,
        t,
      )!,
      // Interpolate the secondary tab unselected color.
      tabUnselectedColor: Color.lerp(
        tabUnselectedColor,
        other.tabUnselectedColor,
        t,
      )!,
      // Interpolate the secondary tab indicator color.
      tabIndicatorColor: Color.lerp(
        tabIndicatorColor,
        other.tabIndicatorColor,
        t,
      )!,
      // Interpolate the secondary tab indicator width.
      tabIndicatorWidth: lerpDouble(
        tabIndicatorWidth,
        other.tabIndicatorWidth,
        t,
      )!,
      // Interpolate the secondary tab indicator height.
      tabIndicatorHeight: lerpDouble(
        tabIndicatorHeight,
        other.tabIndicatorHeight,
        t,
      )!,
      // Interpolate the general panel border radius.
      panelBorderRadius: BorderRadius.lerp(
        panelBorderRadius,
        other.panelBorderRadius,
        t,
      )!,
    );
  }
}
