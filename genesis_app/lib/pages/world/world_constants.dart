import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_colors.dart';

import '../../components/world_details_shell.dart';

const String worldSectionEventsIconAsset = 'assets/custom-icons/svg/events.svg';
const String worldSectionStatusIconAsset =
    'assets/custom-icons/svg/world_tab_status.svg';
const String worldSectionCastIconAsset =
    'assets/custom-icons/svg/world_tab_cast.svg';
const String worldDetailIconAsset =
    'assets/custom-icons/svg/worlddetail-icon.svg';
const double worldMapTabsHeight = 38;
const double worldMapBackButtonLeft = 12;
const double worldMapIdentityHorizontalGap = 10;
const double worldMainTabsHeight = 49;
const double worldBottomTagHeight = 34;
const double worldBottomTagToStatsGap = 10;
const double worldSheetVisibleContentTopGap = 15;
const double worldSheetPageIndicatorTopOffset = 8.5;
const double worldDetailSheetExpandedTopOffset = 50;
const double worldStatsTopSpacerHeight =
    (worldMainTabsHeight + worldBottomTagHeight) / 2 -
    WorldDetailsPageScaffold.inlineContentTopPadding +
    worldBottomTagToStatsGap;
// Reserve the same footer space even when the visitor has no role avatar.
const double worldInfoHeaderHeight = 60;
const double worldLaunchedInfoHeaderHeight = worldInfoHeaderHeight;
const double worldCollapsedPanelBaseHeight =
    WorldDetailsPageScaffold.inlineContentTopPadding +
    worldStatsTopSpacerHeight +
    worldInfoHeaderHeight;
const double worldInfoHeaderContentHeight = 35;
const double worldTimePillTopGap = 12;
const double worldTimePillHeight = 22;
const double worldTimePillMinWidth = 96;
const double worldSecondaryMapControlWidth = 160;
const double worldTimePillHorizontalPadding = 12;
const double worldMapContentTopOffset =
    worldMapTabsHeight + worldTimePillTopGap + worldTimePillHeight + 8;
const double worldCharacterAvatarLogicalSize = 48;
const int worldMainPageCount = 1;

const Color worldHeaderMetaColor = GenesisColors.darkTextSecondary;
const TextStyle worldHeaderMetaTextStyle = TextStyle(
  fontSize: 12,
  height: 1.1,
  fontWeight: FontWeight.w400,
  color: worldHeaderMetaColor,
);
const TextStyle worldDetailBodyTextStyle = TextStyle(
  fontSize: 13,
  height: 1.4,
  fontWeight: FontWeight.w400,
  color: GenesisColors.darkTextPrimary,
);
