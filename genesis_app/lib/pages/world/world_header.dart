// ignore_for_file: use_key_in_widget_constructors

import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_colors.dart';

import '../../network/models/world.dart';
import '../../ui/components/genesis_character_avatar.dart';
import '../../ui/components/genesis_map_top_glass_bar.dart';
import '../../ui/components/genesis_primary_button.dart';
import '../../ui/components/genesis_safe_area.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/entity_deleted.dart';
import '../../utils/stat_count_formatter.dart';
import 'world_constants.dart';
import 'world_models.dart';
import 'world_value_helpers.dart';

class WorldMapBackButton extends StatelessWidget {
  const WorldMapBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GenesisMapGlassBackButton(
      dimension: worldMapTabsHeight,
      onPressed: onPressed,
      glassKey: const ValueKey<String>('world-top-back-glass'),
      surfaceKey: const ValueKey<String>('world-top-back-surface'),
    );
  }
}

class WorldMapTopBar extends StatelessWidget {
  const WorldMapTopBar({
    required this.title,
    required this.timeText,
    required this.maxIdentityWidth,
    required this.onBackPressed,
  });

  final String title;
  final String timeText;
  final double maxIdentityWidth;
  final VoidCallback onBackPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey<String>('world-top-overlay-bar'),
      height: worldMapTabsHeight,
      child: Row(
        children: [
          WorldMapBackButton(onPressed: onBackPressed),
          const SizedBox(width: worldMapIdentityHorizontalGap),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: WorldMapIdentityPill(
                title: title,
                timeText: timeText,
                maxWidth: maxIdentityWidth,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WorldMapIdentityPill extends StatelessWidget {
  const WorldMapIdentityPill({
    required this.title,
    required this.timeText,
    required this.maxWidth,
  });

  final String title;
  final String timeText;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(
        height: worldMapTabsHeight,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Text(
                  title,
                  key: const ValueKey<String>('world-top-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                    shadows: [
                      Shadow(
                        color: Color(0x99000000),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              if (title.isNotEmpty) const SizedBox(height: 3),
              // Reserve the time row before detail loads so the title never
              // shifts from a single-line center to the final two-line layout.
              Visibility(
                visible: timeText.isNotEmpty,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: _WorldMapTimeLabel(
                  text: timeText.isEmpty ? 'Tick 0 · 00:00' : timeText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorldMapTimeLabel extends StatelessWidget {
  const _WorldMapTimeLabel({required this.text});

  static const _textStyle = TextStyle(
    color: Colors.white,
    fontSize: 10,
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: FontWeight.w400,
    decoration: TextDecoration.none,
    shadows: [
      Shadow(color: Color(0xB3000000), blurRadius: 4, offset: Offset(0, 1)),
    ],
  );
  static const _strutStyle = StrutStyle(
    fontSize: 10,
    height: 1,
    forceStrutHeight: true,
  );
  static const _textHeightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  final String text;

  @override
  Widget build(BuildContext context) {
    final parts = _splitWorldMapTimeLabel(text);
    return Row(
      key: const ValueKey<String>('world-top-time'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        if (parts.tick.isNotEmpty) ...[
          Text(
            parts.tick,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
            style: _textStyle,
            strutStyle: _strutStyle,
            textHeightBehavior: _textHeightBehavior,
          ),
          if (parts.time.isNotEmpty)
            const Text(' · ', style: _textStyle, strutStyle: _strutStyle),
        ],
        if (parts.time.isNotEmpty) ...[
          const Icon(
            Icons.schedule,
            size: 10,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Color(0xB3000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              parts.time,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: _textStyle,
              strutStyle: _strutStyle,
              textHeightBehavior: _textHeightBehavior,
            ),
          ),
        ],
      ],
    );
  }
}

({String tick, String time}) _splitWorldMapTimeLabel(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return (tick: '', time: '');
  final separatorIndex = trimmed.indexOf(' · ');
  if (separatorIndex <= 0) {
    return trimmed.startsWith('Tick ')
        ? (tick: trimmed, time: '')
        : (tick: '', time: trimmed);
  }
  final tick = trimmed.substring(0, separatorIndex).trim();
  final time = trimmed.substring(separatorIndex + 3).trim();
  if (!tick.startsWith('Tick ')) return (tick: '', time: trimmed);
  return (tick: tick, time: time);
}

String worldTimeLabel({
  required int tickIndex,
  int subTickNo = 0,
  required String worldTime,
}) {
  final parts = <String>[];
  if (tickIndex >= 0) {
    parts.add('Tick $tickIndex${subTickNo > 0 ? '-$subTickNo' : ''}');
  }
  final resolvedWorldTime = worldTime.trim();
  if (resolvedWorldTime.isNotEmpty) {
    parts.add(resolvedWorldTime);
  }
  return parts.join(' · ');
}

class WorldFeedContent extends StatelessWidget {
  const WorldFeedContent({
    required this.world,
    required this.currentUid,
    required this.worldActionRunning,
    required this.onWorldAction,
    required this.onPullUp,
  });

  final WorldDetail world;
  final String currentUid;
  final bool worldActionRunning;
  final Future<void> Function(WorldHeaderActionKind action) onWorldAction;
  final VoidCallback onPullUp;

  @override
  Widget build(BuildContext context) {
    final infoHeaderHeight = worldInfoHeaderHeightFor(world);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: WorldSectionSheetPullGesture(
            onPullUp: onPullUp,
            child: SizedBox(
              key: const ValueKey<String>('world-panel-info-row'),
              height: infoHeaderHeight,
              child: WorldInfoHeader(
                world: world,
                currentUid: currentUid,
                worldActionRunning: worldActionRunning,
                onWorldAction: onWorldAction,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class WorldSectionSheetPullGesture extends StatefulWidget {
  const WorldSectionSheetPullGesture({
    required this.child,
    required this.onPullUp,
  });

  final Widget child;
  final VoidCallback onPullUp;

  @override
  State<WorldSectionSheetPullGesture> createState() =>
      WorldSectionSheetPullGestureState();
}

class WorldSectionSheetPullGestureState
    extends State<WorldSectionSheetPullGesture> {
  static const double _triggerDistance = 56;
  static const double _triggerVelocity = 520;

  var _dragDy = 0.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) {
        _dragDy = 0;
      },
      onVerticalDragUpdate: (details) {
        _dragDy += details.delta.dy;
      },
      onVerticalDragEnd: (details) {
        final upwardVelocity = -(details.primaryVelocity ?? 0);
        if (_dragDy <= -_triggerDistance ||
            upwardVelocity >= _triggerVelocity) {
          widget.onPullUp();
        }
        _dragDy = 0;
      },
      onVerticalDragCancel: () {
        _dragDy = 0;
      },
      child: widget.child,
    );
  }
}

class WorldKeepAlivePage extends StatefulWidget {
  const WorldKeepAlivePage({required this.child});

  final Widget child;

  @override
  State<WorldKeepAlivePage> createState() => WorldKeepAlivePageState();
}

class WorldKeepAlivePageState extends State<WorldKeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class WorldInfoHeader extends StatelessWidget {
  const WorldInfoHeader({
    required this.world,
    required this.currentUid,
    required this.worldActionRunning,
    required this.onWorldAction,
  });

  final WorldDetail world;
  final String currentUid;
  final bool worldActionRunning;
  final Future<void> Function(WorldHeaderActionKind action) onWorldAction;

  @override
  Widget build(BuildContext context) {
    final action = worldHeaderActionFor(world.relationStatus);
    final infoHeaderHeight = worldInfoHeaderHeightFor(world);
    final canTapRunningProgress =
        action.kind == WorldHeaderActionKind.progress &&
        worldActionRunning &&
        action.isClickable &&
        !world.deleted;
    final actionEnabled =
        !world.deleted && !worldActionRunning && action.isClickable;
    final usesCompactProgressButton =
        action.kind == WorldHeaderActionKind.progress;
    final isLaunched = shouldConnectWorldChatroom(world.relationStatus);
    final currentCharacter = _worldCurrentUserCharacter(
      world.characters,
      currentUid,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: const ValueKey<String>('world-info-header-content'),
          height: infoHeaderHeight,
          child: Align(
            alignment: Alignment.center,
            child: SizedBox(
              height: worldCharacterAvatarLogicalSize,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: isLaunched
                        ? _WorldLaunchedCharacterSummary(
                            character: currentCharacter,
                            tickCount: world.tickCount,
                            subTickNo: world.subTickNo,
                            messageCount: world.connectCount,
                          )
                        : _WorldUnlaunchedSummary(
                            tickCount: world.tickCount,
                            subTickNo: world.subTickNo,
                            messageCount: world.connectCount,
                          ),
                  ),
                  const SizedBox(width: 18),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: canTapRunningProgress
                        ? () => onWorldAction(action.kind)
                        : null,
                    child: AbsorbPointer(
                      absorbing: canTapRunningProgress,
                      child: GenesisPrimaryButton(
                        key: const ValueKey<String>(
                          'world-header-action-button',
                        ),
                        label: action.label,
                        onPressed: actionEnabled
                            ? () => onWorldAction(action.kind)
                            : null,
                        height: usesCompactProgressButton ? 34 : 35,
                        width: usesCompactProgressButton ? 92 : 140,
                        backgroundColor: GenesisColors.redPrimary,
                        disabledBackgroundColor:
                            GenesisColors.darkButtonDisabledBackground,
                        disabledForegroundColor:
                            GenesisColors.darkButtonDisabledForeground,
                        foregroundColor: Colors.white,
                        fontSize: usesCompactProgressButton ? 14 : 16,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        isLoading: worldActionRunning,
                        loadingSize: 18,
                        loadingStrokeWidth: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WorldLaunchedCharacterSummary extends StatelessWidget {
  const _WorldLaunchedCharacterSummary({
    required this.character,
    required this.tickCount,
    required this.subTickNo,
    required this.messageCount,
  });

  final Map<String, dynamic>? character;
  final int tickCount;
  final int subTickNo;
  final int messageCount;

  @override
  Widget build(BuildContext context) {
    final character = this.character;
    final name = character == null
        ? 'Character'
        : worldMapString(character, const ['name'], fallback: 'Character');
    final avatarUrl = character == null
        ? ''
        : worldMapString(character, const ['avatar']);
    final tickLabel = 'Tick $tickCount${subTickNo > 0 ? '-$subTickNo' : ''}';

    return Row(
      key: const ValueKey<String>('world-launched-character-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          key: const ValueKey<String>(
            'world-current-character-avatar-placeholder',
          ),
          decoration: BoxDecoration(
            color: GenesisColors.darkFaintFill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: GenesisCharacterAvatar(
            key: const ValueKey<String>('world-current-character-avatar'),
            url: avatarUrl,
            name: name,
            size: worldCharacterAvatarLogicalSize,
            showFallbackWhileLoading: false,
            maxDevicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                key: const ValueKey<String>('world-current-character-name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GenesisColors.darkTextPrimary,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$tickLabel · ${formatMessageCountLabel(messageCount)}',
                key: const ValueKey<String>('world-header-messages'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GenesisColors.darkTextSecondary,
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorldUnlaunchedSummary extends StatelessWidget {
  const _WorldUnlaunchedSummary({
    required this.tickCount,
    required this.subTickNo,
    required this.messageCount,
  });

  final int tickCount;
  final int subTickNo;
  final int messageCount;

  @override
  Widget build(BuildContext context) {
    final tickLabel = 'Tick $tickCount${subTickNo > 0 ? '-$subTickNo' : ''}';
    return Text(
      '$tickLabel · ${formatMessageCountLabel(messageCount)}',
      key: const ValueKey<String>('world-unlaunched-summary'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: GenesisColors.darkTextSecondary,
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

Map<String, dynamic>? _worldCurrentUserCharacter(
  List<Map<String, dynamic>> characters,
  String currentUid,
) {
  final uid = currentUid.trim();
  if (uid.isEmpty) return null;
  for (final character in characters) {
    if (worldIsCurrentUserCharacter(character, uid)) return character;
  }
  return null;
}

double worldInfoHeaderHeightFor(
  WorldDetail? world, {
  bool assumeLaunched = false,
}) {
  if (assumeLaunched ||
      (world != null && shouldConnectWorldChatroom(world.relationStatus))) {
    return worldLaunchedInfoHeaderHeight;
  }
  return worldInfoHeaderHeight;
}

double worldCollapsedPanelHeightFor(
  BuildContext context, {
  WorldDetail? world,
  bool assumeLaunched = false,
}) {
  final bottomSafeArea = worldBottomSafeAreaOf(context);
  final infoHeaderHeightDelta =
      worldInfoHeaderHeightFor(world, assumeLaunched: assumeLaunched) -
      worldInfoHeaderHeight;
  return worldCollapsedPanelBaseHeight + infoHeaderHeightDelta + bottomSafeArea;
}

String worldOwnerDisplayName(WorldDetail world) {
  if (world.ownerDeleted) return deletedEntityDisplayText;
  final ownerName = world.ownerName.trim();
  if (ownerName.isNotEmpty) return ownerName;
  final originator = world.origin.originator.trim();
  if (originator.isNotEmpty) return originator;
  return formatUidForDisplay(world.ownerUid);
}

double worldBottomSafeAreaOf(BuildContext context) {
  return GenesisSafeAreaInsets.bottom(context);
}
