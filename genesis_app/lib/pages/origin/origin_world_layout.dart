import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_radii.dart';
import '../../ui/tokens/genesis_colors.dart';

const Color originWorldDetailSheetBackgroundColor =
    GenesisColors.darkBackground;
const Color originWorldDetailSheetPrimaryTextColor =
    GenesisColors.darkTextPrimary;
const Color originWorldDetailSheetSecondaryTextColor =
    GenesisColors.darkTextSecondary;
const Color originWorldDetailSheetTertiaryTextColor =
    GenesisColors.darkTextTertiary;
const Color originWorldDetailSheetSoftWhiteColor = Color(0xFFF4F3F6);
const Color originWorldDetailSheetAccentSoftColor = Color(0xFFFF8A9A);
const Color originWorldDetailSheetInactiveIndicatorColor = Color(0x40FFFFFF);
const Color originWorldDetailSheetSubtleSurfaceColor = Color(0x14FFFFFF);
const Color originWorldDetailSheetFaintSurfaceColor =
    GenesisColors.darkFaintFill;
const Color originWorldDetailSheetFaintPlaceholderColor =
    GenesisColors.darkInputPlaceholder;
const Color originWorldDetailSheetSelectRoleArrowColor = Color(0x8CFFFFFF);
const double originWorldMapPanelTopGap = 50;
const double originWorldMapHeightFraction = 0.65;
const double originWorldCollapsedSheetHeightFraction =
    1 - originWorldMapHeightFraction;
const double originWorldCollapsedSheetContentMaxHeight = 270;
const double originWorldMapSheetUnderlap = GenesisRadii.sheetTopRadiusValue;
const double originWorldDetailExpandedTopOffset = 50;
const double originWorldOpeningRoleAvatarMaxDevicePixelRatio = 2;

double originWorldDetailExpandedSheetTopFor({required double topSafeArea}) {
  return topSafeArea + originWorldDetailExpandedTopOffset;
}

double originWorldMapHeightFor({
  required double viewportHeight,
  required double bottomSafeArea,
}) {
  final collapsedSheetHeight = originWorldCollapsedSheetHeightFor(
    viewportHeight: viewportHeight,
    bottomSafeArea: bottomSafeArea,
  );
  final maxMapHeight =
      (viewportHeight - originWorldMapPanelTopGap - bottomSafeArea)
          .clamp(0.0, viewportHeight)
          .toDouble();
  return (viewportHeight - collapsedSheetHeight)
      .clamp(0.0, maxMapHeight)
      .toDouble();
}

double originWorldCollapsedSheetHeightFor({
  required double viewportHeight,
  required double bottomSafeArea,
}) {
  final resolvedViewportHeight = viewportHeight.clamp(0.0, double.infinity);
  final resolvedBottomSafeArea = bottomSafeArea.clamp(
    0.0,
    resolvedViewportHeight,
  );
  final contentHeight =
      (resolvedViewportHeight * originWorldCollapsedSheetHeightFraction)
          .clamp(0.0, originWorldCollapsedSheetContentMaxHeight)
          .toDouble();
  return (contentHeight + resolvedBottomSafeArea)
      .clamp(0.0, resolvedViewportHeight)
      .toDouble();
}

double originWorldRenderedMapHeightFor({
  required double viewportHeight,
  required double bottomSafeArea,
}) {
  final sheetTop = originWorldMapHeightFor(
    viewportHeight: viewportHeight,
    bottomSafeArea: bottomSafeArea,
  );
  return (sheetTop + originWorldMapSheetUnderlap)
      .clamp(0.0, viewportHeight)
      .toDouble();
}
