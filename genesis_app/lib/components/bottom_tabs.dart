import 'package:flutter/material.dart';

import '../icons/custom_icon_assets.dart';
import '../ui/genesis_ui.dart';

class BottomTabs extends StatelessWidget {
  const BottomTabs({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.messagesUnreadCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int messagesUnreadCount;

  @override
  Widget build(BuildContext context) {
    return GenesisBottomNavigation(
      currentIndex: currentIndex,
      onTap: onTap,
      items: [
        const GenesisBottomNavigationItem(
          label: 'Home',
          iconAsset: bottomNavHomeIconAsset,
          selectedIconAsset: bottomNavHomePressIconAsset,
        ),
        const GenesisBottomNavigationItem(
          label: 'Worldo',
          iconAsset: bottomNavOriginIconAsset,
          selectedIconAsset: bottomNavOriginPressIconAsset,
        ),
        const GenesisBottomNavigationItem(
          label: 'Create',
          icon: Icons.add_rounded,
          prominent: true,
          showLabel: false,
          iconSize: 26,
          iconShadows: [
            Shadow(
              color: GenesisColors.darkTextPrimary,
              offset: Offset(0.5, 0),
            ),
            Shadow(
              color: GenesisColors.darkTextPrimary,
              offset: Offset(-0.5, 0),
            ),
            Shadow(
              color: GenesisColors.darkTextPrimary,
              offset: Offset(0, 0.5),
            ),
            Shadow(
              color: GenesisColors.darkTextPrimary,
              offset: Offset(0, -0.5),
            ),
          ],
        ),
        GenesisBottomNavigationItem(
          label: 'Inbox',
          iconAsset: bottomNavInboxIconAsset,
          selectedIconAsset: bottomNavInboxPressIconAsset,
          badgeCount: messagesUnreadCount,
        ),
        const GenesisBottomNavigationItem(
          label: 'Me',
          iconAsset: bottomNavMeIconAsset,
          selectedIconAsset: bottomNavMePressIconAsset,
        ),
      ],
    );
  }
}
