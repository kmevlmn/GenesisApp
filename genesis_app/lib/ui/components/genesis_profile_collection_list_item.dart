import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../tokens/genesis_colors.dart';
import '../../components/origin/stat_item.dart';
import '../../icons/custom_icon_assets.dart';
import '../../utils/stat_count_formatter.dart';
import '../tokens/genesis_image_radii.dart';
import 'genesis_list_image.dart';
import 'genesis_origin_list_card_layout.dart';
import 'genesis_world_list_card_layout.dart';

class GenesisProfileCollectionItemData {
  const GenesisProfileCollectionItemData({
    this.animationKey,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    this.statsText = '',
    this.stats = const <GenesisProfileCollectionStat>[],
    this.useOriginCardLayout = false,
    this.useWorldCardLayout = false,
    this.isCollapsing = false,
    this.showPressedBackground = true,
    this.enableFeedback = true,
    this.onTap,
    this.onEdit,
    this.onLongPress,
    this.onCollapsed,
  });

  final Object? animationKey;
  final String imageUrl;
  final String title;
  final String subtitle;
  final String statsText;
  final List<GenesisProfileCollectionStat> stats;
  final bool useOriginCardLayout;
  final bool useWorldCardLayout;
  final bool isCollapsing;
  final bool showPressedBackground;
  final bool enableFeedback;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onLongPress;
  final VoidCallback? onCollapsed;
}

class GenesisProfileCollectionStat {
  const GenesisProfileCollectionStat({
    this.icon,
    this.iconAsset,
    this.preserveIconAssetColor = false,
    required this.value,
  }) : assert(icon != null || iconAsset != null);

  final IconData? icon;
  final String? iconAsset;
  final bool preserveIconAssetColor;
  final int value;
}

class GenesisProfileCollectionListItem extends StatelessWidget {
  const GenesisProfileCollectionListItem({super.key, required this.item});

  static const BorderRadius _borderRadius = BorderRadius.all(
    Radius.circular(14),
  );
  static const ShapeBorder _shape = RoundedRectangleBorder(
    borderRadius: _borderRadius,
  );

  final GenesisProfileCollectionItemData item;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final placeholder = dark
        ? const ColoredBox(
            color: GenesisColors.darkFaintFill,
            child: Center(
              child: Icon(
                Icons.image_outlined,
                size: 22,
                color: GenesisColors.darkTextTertiary,
              ),
            ),
          )
        : null;
    final worldSubtitleLines = item.subtitle
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final useSharedCardLayout =
        item.useWorldCardLayout || item.useOriginCardLayout;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(right: item.onEdit == null ? 0 : 32),
          child: Row(
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    color: dark
                        ? GenesisColors.darkTextPrimary
                        : const Color(0xFF4B6192),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: useSharedCardLayout ? 4 : 5),
        if (useSharedCardLayout)
          for (
            var index = 0;
            index < worldSubtitleLines.length;
            index += 1
          ) ...[
            if (index > 0) const SizedBox(height: 4),
            Text(
              worldSubtitleLines[index],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: dark
                    ? GenesisColors.darkTextSecondary
                    : const Color(0xFF888888),
                height: 1.2,
              ),
            ),
          ]
        else
          Text(
            item.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: dark
                  ? GenesisColors.darkTextSecondary
                  : const Color(0xFF6F6F6F),
              height: 1.3,
            ),
          ),
        if (item.statsText.isNotEmpty) ...[
          SizedBox(height: useSharedCardLayout ? 4 : 8),
          Text(
            item.statsText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: dark
                  ? GenesisColors.darkTextSecondary
                  : useSharedCardLayout
                  ? const Color(0xFF666666)
                  : Colors.black,
              fontSize: 12,
              height: item.useWorldCardLayout ? 1.2 : 1,
              fontWeight: FontWeight.w400,
            ),
          ),
        ] else if (item.stats.isNotEmpty) ...[
          SizedBox(height: useSharedCardLayout ? 4 : 8),
          _StatsRow(
            stats: item.stats,
            color: dark
                ? GenesisColors.darkTextSecondary
                : useSharedCardLayout
                ? const Color(0xFF666666)
                : Colors.black,
            iconSize: item.useOriginCardLayout ? 12 : 11,
            lineHeight: item.useOriginCardLayout ? 1.2 : 1,
          ),
        ],
      ],
    );
    final cardContent = item.useWorldCardLayout
        ? GenesisWorldListCardLayout(
            imageUrl: item.imageUrl,
            placeholder: placeholder,
            content: content,
          )
        : item.useOriginCardLayout
        ? GenesisOriginListCardLayout(
            imageUrl: item.imageUrl,
            placeholder: placeholder,
            content: content,
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GenesisListImage(
                imageUrl: item.imageUrl,
                placeholder: placeholder,
                width: 52,
                height: 52,
                borderRadius: GenesisImageRadii.content,
                maxDevicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
              const SizedBox(width: 10),
              Expanded(child: content),
            ],
          );
    return Material(
      color: dark ? GenesisColors.darkBackground : Colors.white,
      shape: _shape,
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          children: [
            cardContent,
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  overlayColor: item.showPressedBackground
                      ? null
                      : const WidgetStatePropertyAll<Color>(Colors.transparent),
                  enableFeedback: item.enableFeedback,
                  onTap: item.onTap,
                  onLongPress: item.onLongPress,
                ),
              ),
            ),
            if (item.onEdit case final onEdit?)
              Positioned(
                top: 0,
                right: 0,
                child: Semantics(
                  button: true,
                  label: 'Edit ${item.title}',
                  child: GestureDetector(
                    key: ValueKey<String>(
                      'profile-collection-item-edit-'
                      '${item.animationKey ?? item.title}',
                    ),
                    behavior: HitTestBehavior.opaque,
                    onTap: onEdit,
                    child: SizedBox(
                      width: 32,
                      height: 28,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Transform.scale(
                          // Match the previous edit icon within its existing layout slot.
                          scale: 32 / 37.36,
                          child: SvgPicture.asset(
                            editSquareIconAsset,
                            width: 16,
                            height: 16,
                            colorFilter: ColorFilter.mode(
                              dark
                                  ? GenesisColors.darkTextSecondary
                                  : const Color(0xFF4B6192),
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
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

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.stats,
    required this.color,
    required this.iconSize,
    required this.lineHeight,
  });

  final List<GenesisProfileCollectionStat> stats;
  final Color color;
  final double iconSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: stats
          .map(
            (stat) => _Stat(
              icon: stat.icon,
              iconAsset: stat.iconAsset,
              preserveIconAssetColor: stat.preserveIconAssetColor,
              value: stat.value,
              color: color,
              iconSize: iconSize,
              lineHeight: lineHeight,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    this.icon,
    this.iconAsset,
    this.preserveIconAssetColor = false,
    required this.value,
    required this.color,
    required this.iconSize,
    required this.lineHeight,
  }) : assert(icon != null || iconAsset != null);

  final IconData? icon;
  final String? iconAsset;
  final bool preserveIconAssetColor;
  final int value;
  final Color color;
  final double iconSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    return StatItem(
      icon: icon,
      iconAsset: iconAsset,
      preserveIconAssetColor: preserveIconAssetColor,
      iconSize: iconSize,
      iconColor: color,
      gap: 4,
      text: formatStatCount(value),
      textStyle: TextStyle(
        color: color,
        fontSize: 12,
        height: lineHeight,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}
