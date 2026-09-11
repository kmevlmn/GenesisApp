import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_colors.dart';
import '../../ui/components/genesis_map_top_glass_bar.dart';

const String worldSectionEventsIconAsset = 'assets/custom-icons/svg/events.svg';
const String worldSectionStatusIconAsset =
    'assets/custom-icons/svg/world_tab_status.svg';
const String worldSectionCastIconAsset =
    'assets/custom-icons/svg/world_tab_cast.svg';
const String worldDetailIconAsset =
    'assets/custom-icons/svg/worlddetail-icon.svg';
const String worldInfoIconAsset = 'assets/custom-icons/svg/info.svg';
const double worldMapTabsHeight = genesisMapBackButtonDimension;
const double worldMapBackButtonLeft = genesisMapBackButtonLeft;
const double worldMapBackButtonTop = genesisMapBackButtonTop;
const double worldMapTopBarRightInset = genesisMapTopBarRightInset;
const double worldMapIdentityHorizontalGap = 10;
// A glass bubble of section buttons floats over the foot of the map. Info rests
// as a low sheet under it; picking a section raises that same sheet.
const double worldBubbleHeight = 56;
const double worldBubbleInnerPadding = 6;
// Rounder than a panel, short of a pill; the selected item inside stays
// concentric at 14, the resting card around it at 26.
const double worldBubbleRadius = 20;
const double worldFloatingSideInset = 12;
const double worldFloatingBottomGap = 8;
const double worldInfoToBubbleGap = 8;
// The sheet's top strip carries only the page indicator; section titles ride
// on their own pages so Info can sit directly under it.
const double worldSheetStripHeight = 15;
const double worldSheetTitleRowHeight = 28;
const double worldSheetTitleToContentGap = 5;
const double worldInfoPageHorizontalPadding = 16;
// Info at rest is a glass card wrapped around the section bar, which sits
// exactly where it stays once the sheet is raised; raised, the card becomes
// the opaque sheet.
const double worldRestingCardBubblePadding = 6;
const double worldRestingCardInset =
    worldFloatingSideInset - worldRestingCardBubblePadding;
const double worldRestingCardBottomLift =
    worldFloatingBottomGap - worldRestingCardBubblePadding;
const double worldRestingCardRadius =
    worldBubbleRadius + worldRestingCardBubblePadding;
// Denser than the top bar's glass so the player line reads over busy tiles.
const Color worldRestingCardGlassColor = Color(0xB8151517);
const Color worldBubbleFillColor = Color(0x14FFFFFF);
const double worldSheetVisibleContentTopGap = 15;
const double worldSheetPageIndicatorTopOffset = 8.5;
const double worldDetailSheetExpandedTopOffset = 50;
// Reserve the same footer space even when the visitor has no role avatar.
const double worldInfoHeaderHeight = 60;
const double worldLaunchedInfoHeaderHeight = worldInfoHeaderHeight;
// The bubble and its gap above the bottom safe area; sheet content clears it.
const double worldBubbleReservedHeight =
    worldBubbleHeight + worldFloatingBottomGap;
// Under the Info row: the gap, the section bar and the card padding below it.
const double worldRestingCardBubbleArea =
    worldInfoToBubbleGap + worldBubbleHeight + worldRestingCardBubblePadding;
const double worldRestingCardHeight =
    worldSheetStripHeight + worldInfoHeaderHeight + worldRestingCardBubbleArea;
// Info at rest above the bottom safe area: the card and its lift.
const double worldFloatingChromeBaseHeight =
    worldRestingCardBottomLift + worldRestingCardHeight;
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
