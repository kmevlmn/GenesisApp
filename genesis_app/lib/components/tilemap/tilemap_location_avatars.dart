import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/config/genesis_image_config.dart';
import '../../ui/components/genesis_character_avatar.dart';
import '../../ui/tokens/genesis_avatar_radii.dart';
import '../world_map_avatar_logic.dart';
import '../world_point.dart';

const double tilemapLocationAvatarSize = 36;
const double tilemapLocationAvatarSpacing = 4;
const double tilemapLocationLabelToDotSpacing = 6;
const double tilemapLocationDotSize = 7;
const double tilemapLocationDotToAvatarSpacing = 6;
const double tilemapLocationDotCenterToAvatarSpacing =
    tilemapLocationDotSize / 2 + tilemapLocationDotToAvatarSpacing;
const double tilemapLocationLabelToAvatarSpacing =
    tilemapLocationLabelToDotSpacing +
    tilemapLocationDotSize +
    tilemapLocationDotToAvatarSpacing;
const int tilemapLocationAvatarColumnCount = 3;
const double tilemapLocationAvatarGroupWidth =
    tilemapLocationAvatarSize * tilemapLocationAvatarColumnCount +
    tilemapLocationAvatarSpacing * (tilemapLocationAvatarColumnCount - 1);

double tilemapLocationAvatarLeft(int index, int avatarCount) {
  final rowStart =
      (index ~/ tilemapLocationAvatarColumnCount) *
      tilemapLocationAvatarColumnCount;
  final rowCount = (avatarCount - rowStart)
      .clamp(0, tilemapLocationAvatarColumnCount)
      .toInt();
  final rowWidth =
      rowCount * tilemapLocationAvatarSize +
      math.max(0, rowCount - 1) * tilemapLocationAvatarSpacing;
  return (tilemapLocationAvatarGroupWidth - rowWidth) / 2 +
      (index % tilemapLocationAvatarColumnCount) *
          (tilemapLocationAvatarSize + tilemapLocationAvatarSpacing);
}

double tilemapLocationAvatarTop(int index) {
  return (index ~/ tilemapLocationAvatarColumnCount) *
      (tilemapLocationAvatarSize + tilemapLocationAvatarSpacing);
}

class TilemapLocationAvatars extends StatelessWidget {
  const TilemapLocationAvatars({
    super.key,
    required this.avatars,
    this.onAvatarTap,
  });

  final List<UserAvatar> avatars;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    if (avatars.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      key: const ValueKey<String>('tilemap-location-avatars'),
      width: tilemapLocationAvatarGroupWidth,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: tilemapLocationAvatarSpacing,
        runSpacing: tilemapLocationAvatarSpacing,
        children: [
          for (final avatar in avatars)
            _TilemapLocationAvatar(
              key: ValueKey<String>(
                'tilemap-location-avatar-${worldMapAvatarStableId(avatar)}',
              ),
              avatar: avatar,
              onTap: onAvatarTap,
            ),
        ],
      ),
    );
  }
}

class _TilemapLocationAvatar extends StatelessWidget {
  const _TilemapLocationAvatar({
    super.key,
    required this.avatar,
    required this.onTap,
  });

  final UserAvatar avatar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = worldMapAvatarBorderColor(
      isPlayerControlledRole: avatar.isPlayerControlledRole,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(
        dimension: tilemapLocationAvatarSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GenesisCharacterAvatar(
              url: avatar.avatarUrl,
              name: (avatar.name ?? avatar.initials).trim(),
              size: tilemapLocationAvatarSize,
              borderRadius: GenesisAvatarRadii.character,
              showFallbackWhileLoading: false,
              showFallbackWhenUnavailable: true,
              maxDevicePixelRatio:
                  GenesisImageConfig.tilemapAvatarMaxDevicePixelRatio,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.26),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 3,
                  offset: const Offset(0, 2),
                ),
              ],
              border: borderColor == null
                  ? null
                  : Border.all(
                      color: borderColor,
                      width: avatar.isPlayerControlledRole ? 2 : 1,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
