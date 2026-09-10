import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/telemetry/genesis_telemetry.dart';
import 'genesis_safe_area.dart';
import 'genesis_unread_badge.dart';
import '../tokens/genesis_spacing.dart';
import '../tokens/genesis_colors.dart';
import '../theme/genesis_ui_theme.dart';

class GenesisBottomNavigationItem {
  const GenesisBottomNavigationItem({
    required this.label,
    this.icon,
    this.iconAsset,
    this.selectedIconAsset,
    this.enabled = true,
    this.prominent = false,
    this.showLabel = true,
    this.iconSize,
    this.iconShadows,
    this.badgeCount = 0,
  }) : assert(icon != null || iconAsset != null);

  final String label;
  final IconData? icon;
  final String? iconAsset;
  final String? selectedIconAsset;
  final bool enabled;
  final bool prominent;
  final bool showLabel;
  final double? iconSize;
  final List<Shadow>? iconShadows;
  final int badgeCount;
}

class GenesisBottomNavigation extends StatelessWidget {
  const GenesisBottomNavigation({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.height = defaultHeight,
  });

  static const double defaultHeight = 49;
  static const double minBottomPadding = 4;

  final List<GenesisBottomNavigationItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = GenesisUiTheme.of(
      context,
    ).bottomNavigationBackgroundColor;
    return GenesisBottomSystemBarStyleScope(
      style: GenesisBottomSystemBarStyle(color: backgroundColor),
      child: ColoredBox(
        color: backgroundColor,
        child: Stack(
          children: [
            GenesisBottomSafePadding(
              minimum: minBottomPadding,
              child: SizedBox(
                height: height,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (var index = 0; index < items.length; index += 1)
                      GenesisBottomNavigationTile(
                        item: items[index],
                        selected: currentIndex == index,
                        onTap: () => onTap(index),
                      ),
                  ],
                ),
              ),
            ),
            // Paint inside the bar without moving its content or hit targets.
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 1,
              child: IgnorePointer(
                child: ColoredBox(color: GenesisColors.darkFaintFill),
              ),
            ),
            Positioned(
              top: 1,
              left: 0,
              right: 0,
              height: 3,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        GenesisColors.darkFaintFill.withValues(alpha: 0.04),
                        GenesisColors.darkFaintFill.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GenesisBottomNavigationTile extends StatelessWidget {
  const GenesisBottomNavigationTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final GenesisBottomNavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final uiTheme = GenesisUiTheme.of(context);
    final color = item.prominent
        ? uiTheme.bottomNavigationProminentColor
        : selected
        ? uiTheme.bottomNavigationSelectedColor
        : uiTheme.bottomNavigationUnselectedColor;
    final iconSize =
        item.iconSize ??
        (item.prominent
            ? 22.0
            : item.iconAsset == null
            ? 20.0
            : 24.0);
    final iconAsset = selected
        ? item.selectedIconAsset ?? item.iconAsset
        : item.iconAsset;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.enabled
            ? () {
                GenesisTelemetry.click(
                  actionId: 'bottom_tab.${_actionSlug(item.label)}',
                  component: 'GenesisBottomNavigationTile',
                  enabled: true,
                  data: <String, Object?>{
                    'label': item.label,
                    'selected': selected,
                  },
                );
                onTap();
              }
            : null,
        child: Semantics(
          key: ValueKey<String>('bottom-nav-${item.label}'),
          button: true,
          enabled: item.enabled,
          selected: selected,
          label: item.label,
          excludeSemantics: true,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (item.prominent)
                _ProminentNavigationIcon(
                  icon: item.icon,
                  assetName: iconAsset,
                  size: iconSize,
                  shadows: item.iconShadows,
                  backgroundColor: color,
                )
              else
                _BadgedIcon(
                  icon: item.icon,
                  assetName: iconAsset,
                  color: color,
                  size: iconSize,
                  badgeCount: item.badgeCount,
                  badgeKey: ValueKey('bottom-nav-${item.label}-unread-badge'),
                ),
              if (item.showLabel) ...[
                SizedBox(height: item.prominent ? 1 : GenesisSpacing.xxs),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiTheme.tabLabelStyle.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProminentNavigationIcon extends StatelessWidget {
  const _ProminentNavigationIcon({
    required this.icon,
    required this.assetName,
    required this.size,
    required this.shadows,
    required this.backgroundColor,
  });

  final IconData? icon;
  final String? assetName;
  final double size;
  final List<Shadow>? shadows;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 33,
      decoration: ShapeDecoration(
        color: backgroundColor,
        shape: const ContinuousRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      alignment: Alignment.center,
      child: assetName != null
          ? assetName!.endsWith('.svg')
                ? SvgPicture.asset(
                    assetName!,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    colorFilter: const ColorFilter.mode(
                      GenesisColors.darkTextPrimary,
                      BlendMode.srcIn,
                    ),
                  )
                : Image.asset(
                    assetName!,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    color: GenesisColors.darkTextPrimary,
                  )
          : Icon(
              icon,
              color: GenesisColors.darkTextPrimary,
              size: size,
              shadows: shadows,
            ),
    );
  }
}

String _actionSlug(String label) {
  final normalized = label
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return normalized.isEmpty ? 'unknown' : normalized;
}

class _BadgedIcon extends StatelessWidget {
  const _BadgedIcon({
    required this.icon,
    required this.assetName,
    required this.color,
    required this.size,
    required this.badgeCount,
    required this.badgeKey,
  });

  final IconData? icon;
  final String? assetName;
  final Color color;
  final double size;
  final int badgeCount;
  final Key badgeKey;

  @override
  Widget build(BuildContext context) {
    final boxSize = size + 12;
    return SizedBox(
      width: boxSize,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (assetName != null)
            assetName!.endsWith('.svg')
                ? SvgPicture.asset(
                    assetName!,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    colorMapper: _NavigationIconColorMapper(
                      foreground: color,
                      background: GenesisUiTheme.of(
                        context,
                      ).bottomNavigationBackgroundColor,
                    ),
                  )
                : Image.asset(
                    assetName!,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                  )
          else if (icon != null)
            Icon(icon, color: color, size: size)
          else
            SizedBox.square(dimension: size),
          if (badgeCount > 0)
            Positioned(
              left: boxSize / 2 + size / 2 - 11,
              top: -1,
              child: GenesisUnreadBadge(key: badgeKey, count: badgeCount),
            ),
        ],
      ),
    );
  }
}

// White SVG details are cutouts; recoloring the whole SVG would erase them.
class _NavigationIconColorMapper extends ColorMapper {
  const _NavigationIconColorMapper({
    required this.foreground,
    required this.background,
  });

  final Color foreground;
  final Color background;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    if (color == Colors.white) return background;
    if (color.a == 0) return color;
    return foreground;
  }

  @override
  bool operator ==(Object other) =>
      other is _NavigationIconColorMapper &&
      foreground == other.foreground &&
      background == other.background;

  @override
  int get hashCode => Object.hash(foreground, background);
}
