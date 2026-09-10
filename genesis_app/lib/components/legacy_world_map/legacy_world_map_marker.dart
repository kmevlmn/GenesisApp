import 'dart:async';
import 'dart:math' as math;

import '../../ui/components/genesis_character_avatar.dart';
import '../../ui/components/recent_chat_marker.dart';
import '../../ui/tokens/genesis_avatar_radii.dart';
import '../../ui/tokens/genesis_typography.dart';
import 'package:flutter/material.dart';

import '../world_map_avatar_logic.dart';
import '../world_map_contract.dart';
import '../world_event_count_badge.dart';
import '../world_new_badge.dart';
import '../world_point.dart';
import 'legacy_world_map_background.dart';
import 'legacy_world_map_bubble.dart';

@visibleForTesting
Color? worldMapAvatarBorderColorForTesting({
  required bool isPlayerControlledRole,
}) {
  return legacyWorldMapAvatarBorderColor(
    isPlayerControlledRole: isPlayerControlledRole,
  );
}

Color? legacyWorldMapAvatarBorderColor({required bool isPlayerControlledRole}) {
  return worldMapAvatarBorderColor(
    isPlayerControlledRole: isPlayerControlledRole,
  );
}

@visibleForTesting
Offset? worldMapInitialZoomFocusForTesting(List<WorldPoint> points) {
  return legacyWorldMapInitialZoomFocus(points);
}

Offset? legacyWorldMapInitialZoomFocus(List<WorldPoint> points) {
  WorldPoint? target;
  for (final point in points) {
    final users = worldMapVisibleAvatarsForPoint(point);
    if (users.isEmpty) continue;
    final current = target;
    if (current == null ||
        users.length > worldMapVisibleAvatarsForPoint(current).length) {
      target = point;
    }
  }
  return target?.position;
}

class _WorldPointMarkerGeometry {
  const _WorldPointMarkerGeometry({
    required this.labelLayout,
    required this.markerWidth,
    required this.markerHeight,
    required this.pointCenterY,
  });

  final _WorldPointLabelLayout labelLayout;
  final double markerWidth;
  final double markerHeight;
  final double pointCenterY;
}

const double _worldPointLabelHorizontalPadding = 6;
const double _worldPointLabelVerticalPadding = 8;
const double _worldPointMaxLabelTextWidth = 135;
const double _worldPointActivityIconGap = 3;
const double _worldPointActivityIconExtraWidth =
    _worldPointActivityIconGap + kRecentChatMapBadgeSize;
const double _worldPointEventBadgeExtraWidth =
    _worldPointActivityIconGap + WorldEventCountBadge.minWidth;
const double _worldPointNewBadgeExtraWidth =
    _worldPointActivityIconGap + WorldNewBadge.compactWidth;
const double _worldPointMaxLabelBoxWidth =
    _worldPointMaxLabelTextWidth + _worldPointLabelHorizontalPadding;
const double _worldPointDotSize = 8;
const double _worldPointAvatarSize = legacyWorldMapAvatarImageLogicalSize;
const double _worldPointAvatarSpacing = 4;
const double _worldPointLabelToDotSpacing = 6;
const double _worldPointAvatarTopGap = 10;
// Keep a small, intentional tolerance around the visible controls, without
// making the empty space between a location's label, pin and avatars tappable.
const double _worldPointTapTargetPadding = 6;
const TextStyle _worldPointLabelTextStyle = TextStyle(
  inherit: false,
  fontFamily: GenesisTypography.fontFamily,
  fontFamilyFallback: GenesisTypography.fontFamilyFallback,
  fontSize: 12,
  height: 1.2,
  leadingDistribution: TextLeadingDistribution.even,
  fontWeight: FontWeight.w600,
  color: Colors.white,
);

class _WorldPointLabelLayout {
  const _WorldPointLabelLayout({
    required this.bubbleWidth,
    required this.layoutWidth,
    required this.height,
    required this.lineCount,
  });

  final double bubbleWidth;
  final double layoutWidth;
  final double height;
  final int lineCount;
}

_WorldPointLabelLayout _worldPointLabelLayout(
  BuildContext context,
  String text, {
  required double maxBoxWidth,
}) {
  final layoutWidth = math.max(_worldPointLabelHorizontalPadding, maxBoxWidth);
  final painter =
      TextPainter(
        text: TextSpan(text: text, style: _worldPointLabelTextStyle),
        textAlign: TextAlign.center,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(
        maxWidth: math.max(0, layoutWidth - _worldPointLabelHorizontalPadding),
      );
  final lines = painter.computeLineMetrics();
  final longestLine = lines.fold<double>(
    0,
    (width, line) => math.max(width, line.width),
  );
  final paddedLongestLine =
      longestLine.ceilToDouble() + _worldPointLabelHorizontalPadding;
  return _WorldPointLabelLayout(
    bubbleWidth: paddedLongestLine.clamp(
      _worldPointLabelHorizontalPadding,
      layoutWidth,
    ),
    layoutWidth: layoutWidth,
    height: painter.height + _worldPointLabelVerticalPadding,
    lineCount: math.max(1, lines.length),
  );
}

_WorldPointMarkerGeometry _geometryForPoint(
  BuildContext context,
  WorldPoint point,
  double width, {
  required bool showRecentChatIcon,
  required bool showEventIcon,
}) {
  final users = worldMapVisibleAvatarsForPoint(point);
  final activityIconsWidth =
      ((showEventIcon ? _worldPointEventBadgeExtraWidth : 0.0) +
          (showRecentChatIcon ? _worldPointActivityIconExtraWidth : 0.0) +
          (point.isNew ? _worldPointNewBadgeExtraWidth : 0.0)) *
      2;
  final labelMaxWidth = math.min(
    _worldPointMaxLabelBoxWidth,
    math.max(0.0, width - activityIconsWidth),
  );
  final labelLayout = _worldPointLabelLayout(
    context,
    point.name,
    maxBoxWidth: labelMaxWidth,
  );
  final labelGroupWidth = math.min(
    labelLayout.bubbleWidth + activityIconsWidth,
    width,
  );
  final avatarWidth = _worldPointAvatarGroupWidth(users.length);
  final visibleMarkerWidth = math.max(
    math.max(_worldPointDotSize, avatarWidth),
    labelGroupWidth,
  );
  final pointCenterY =
      labelLayout.height +
      _worldPointTapTargetPadding +
      _worldPointLabelToDotSpacing +
      _worldPointDotSize / 2;
  final markerWidth = visibleMarkerWidth + _worldPointTapTargetPadding * 2;
  final markerHeight =
      _worldPointMarkerHeight(
        userCount: users.length,
        pointCenterY: pointCenterY,
      ) +
      _worldPointTapTargetPadding;
  return _WorldPointMarkerGeometry(
    labelLayout: labelLayout,
    markerWidth: markerWidth,
    markerHeight: markerHeight,
    pointCenterY: pointCenterY,
  );
}

double _worldPointMarkerHeight({
  required int userCount,
  required double pointCenterY,
}) {
  final count = userCount;
  if (count <= 0) return pointCenterY + _worldPointDotSize / 2;
  if (count < 4) {
    return pointCenterY + _worldPointAvatarTopGap + _worldPointAvatarSize;
  }
  if (count == 4) {
    return pointCenterY +
        _worldPointAvatarTopGap +
        _worldPointAvatarSize * 2 +
        _worldPointAvatarSpacing;
  }

  final radius = _worldPointAvatarRingRadius(count);
  return pointCenterY +
      radius * 2 +
      _worldPointAvatarTopGap +
      _worldPointAvatarSize;
}

double _worldPointAvatarGroupWidth(int count) {
  if (count <= 0) return 0;
  if (count < 4) {
    return count * _worldPointAvatarSize +
        (count - 1) * _worldPointAvatarSpacing;
  }
  if (count == 4) return _worldPointAvatarSize * 2 + _worldPointAvatarSpacing;
  return _worldPointAvatarRingRadius(count) * 2 + _worldPointAvatarSize;
}

double _worldPointAvatarRingRadius(int count) {
  if (count < 4) return 0;
  final minimumChord = count > 5
      ? _worldPointAvatarSize * 0.88
      : _worldPointAvatarSize + _worldPointAvatarSpacing;
  final radius = minimumChord / (2 * math.sin(math.pi / count));
  return math.max(_worldPointAvatarSize * 0.88, radius);
}

double _worldPointAvatarLeft(int index, int count, double markerWidth) {
  if (count < 4) {
    final rowWidth =
        count * _worldPointAvatarSize + (count - 1) * _worldPointAvatarSpacing;
    return markerWidth / 2 -
        rowWidth / 2 +
        index * (_worldPointAvatarSize + _worldPointAvatarSpacing);
  }
  if (count == 4) {
    final gridWidth = _worldPointAvatarSize * 2 + _worldPointAvatarSpacing;
    final column = index % 2;
    return markerWidth / 2 -
        gridWidth / 2 +
        column * (_worldPointAvatarSize + _worldPointAvatarSpacing);
  }

  final radius = _worldPointAvatarRingRadius(count);
  final ringCenterX = markerWidth / 2;
  final angle = -math.pi / 2 + math.pi * 2 * index / count;
  return ringCenterX + math.cos(angle) * radius - _worldPointAvatarSize / 2;
}

double _worldPointAvatarTop(int index, int count, double pointCenterY) {
  if (count < 4) return pointCenterY + _worldPointAvatarTopGap;
  if (count == 4) {
    final row = index ~/ 2;
    return pointCenterY +
        _worldPointAvatarTopGap +
        row * (_worldPointAvatarSize + _worldPointAvatarSpacing);
  }

  final radius = _worldPointAvatarRingRadius(count);
  final ringCenterY =
      pointCenterY +
      radius +
      _worldPointAvatarTopGap +
      _worldPointAvatarSize / 2;
  final angle = -math.pi / 2 + math.pi * 2 * index / count;
  return ringCenterY + math.sin(angle) * radius - _worldPointAvatarSize / 2;
}

Offset _transformedWorldPointAnchor(Matrix4? transform, double x, double y) {
  if (transform == null) return Offset(x, y);
  final values = transform.storage;
  return Offset(
    values[0] * x + values[4] * y + values[12],
    values[1] * x + values[5] * y + values[13],
  );
}

class LegacyWorldMapPointPositioned extends StatelessWidget {
  const LegacyWorldMapPointPositioned({
    super.key,
    required this.point,
    required this.showRecentChatIcon,
    required this.showEventIcon,
    required this.width,
    required this.height,
    this.transform,
    required this.enableAvatarScaleReboundHint,
    required this.onPointerDown,
    required this.onTap,
  });

  final WorldPoint point;
  final bool showRecentChatIcon;
  final bool showEventIcon;
  final double width;
  final double height;
  final Matrix4? transform;
  final bool enableAvatarScaleReboundHint;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final users = worldMapVisibleAvatarsForPoint(point);
    final geometry = _geometryForPoint(
      context,
      point,
      width,
      showRecentChatIcon: showRecentChatIcon,
      showEventIcon: showEventIcon,
    );
    final labelLayout = geometry.labelLayout;
    final markerWidth = geometry.markerWidth;
    final markerHeight = geometry.markerHeight;
    final pointCenterY = geometry.pointCenterY;

    final baseX = (point.position.dx * width).clamp(0, width).toDouble();
    final baseY = (point.position.dy * height).clamp(0, height).toDouble();
    final transformedAnchor = _transformedAnchor(baseX, baseY);
    final x = transformedAnchor.dx;
    final y = transformedAnchor.dy;

    final shouldClamp = transform == null;
    final maxLeft = (width - markerWidth) > 0 ? (width - markerWidth) : 0.0;
    final maxTop = (height - markerHeight) > 0 ? (height - markerHeight) : 0.0;

    final rawLeft = x - markerWidth / 2;
    final rawTop = y - pointCenterY;
    final left = shouldClamp ? rawLeft.clamp(0.0, maxLeft).toDouble() : rawLeft;
    final top = shouldClamp ? rawTop.clamp(0.0, maxTop).toDouble() : rawTop;

    return Positioned(
      left: left,
      top: top,
      width: markerWidth,
      height: markerHeight,
      child: _WorldPointMarker(
        point: point,
        showRecentChatIcon: showRecentChatIcon,
        showEventIcon: showEventIcon,
        users: users,
        labelLayout: labelLayout,
        markerWidth: markerWidth,
        markerHeight: markerHeight,
        pointCenterY: pointCenterY,
        enableAvatarScaleReboundHint: enableAvatarScaleReboundHint,
        onPointerDown: onPointerDown,
        onTap: onTap,
      ),
    );
  }

  Offset _transformedAnchor(double x, double y) {
    return _transformedWorldPointAnchor(transform, x, y);
  }
}

class LegacyWorldMapPointMessageBubblePositioned extends StatelessWidget {
  const LegacyWorldMapPointMessageBubblePositioned({
    super.key,
    required this.point,
    required this.width,
    required this.height,
    required this.onPointerDown,
    required this.onTap,
    this.transform,
    required this.messageBubble,
  });

  final WorldPoint point;
  final double width;
  final double height;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final VoidCallback? onTap;
  final Matrix4? transform;
  final WorldMapMessageBubble? messageBubble;

  @override
  Widget build(BuildContext context) {
    final bubble = messageBubble;
    if (bubble == null) return const SizedBox.shrink();

    final users = worldMapVisibleAvatarsForPoint(point);
    final bubbleIndex = users.indexWhere(
      (avatar) => avatar.id.trim() == bubble.characterId.trim(),
    );
    if (bubbleIndex < 0) return const SizedBox.shrink();

    final geometry = _geometryForPoint(
      context,
      point,
      width,
      showRecentChatIcon: false,
      showEventIcon: false,
    );
    final markerWidth = geometry.markerWidth;
    final markerHeight = geometry.markerHeight;
    final pointCenterY = geometry.pointCenterY;

    final baseX = (point.position.dx * width).clamp(0, width).toDouble();
    final baseY = (point.position.dy * height).clamp(0, height).toDouble();
    final transformedAnchor = _transformedWorldPointAnchor(
      transform,
      baseX,
      baseY,
    );
    final x = transformedAnchor.dx;
    final y = transformedAnchor.dy;

    final shouldClamp = transform == null;
    final maxLeft = (width - markerWidth) > 0 ? (width - markerWidth) : 0.0;
    final maxTop = (height - markerHeight) > 0 ? (height - markerHeight) : 0.0;
    final rawLeft = x - markerWidth / 2;
    final rawTop = y - pointCenterY;
    final left = shouldClamp ? rawLeft.clamp(0.0, maxLeft).toDouble() : rawLeft;
    final top = shouldClamp ? rawTop.clamp(0.0, maxTop).toDouble() : rawTop;

    return LegacyWorldMapPositionedMessageBubble(
      text: bubble.content,
      preservePageWidth: bubble.preservePageWidth,
      markerLeft: left,
      markerTop: top,
      avatarLeft: _worldPointAvatarLeft(bubbleIndex, users.length, markerWidth),
      avatarTop: _worldPointAvatarTop(bubbleIndex, users.length, pointCenterY),
      markerWidth: markerWidth,
      onPointerDown: onPointerDown,
      onTap: onTap,
    );
  }
}

class _WorldPointMarker extends StatelessWidget {
  const _WorldPointMarker({
    required this.point,
    required this.showRecentChatIcon,
    required this.showEventIcon,
    required this.users,
    required this.labelLayout,
    required this.markerWidth,
    required this.markerHeight,
    required this.pointCenterY,
    required this.enableAvatarScaleReboundHint,
    required this.onPointerDown,
    this.onTap,
  });

  final WorldPoint point;
  final bool showRecentChatIcon;
  final bool showEventIcon;
  final List<UserAvatar> users;
  final _WorldPointLabelLayout labelLayout;
  final double markerWidth;
  final double markerHeight;
  final double pointCenterY;
  final bool enableAvatarScaleReboundHint;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final VoidCallback? onTap;

  static const double _avatarSize = legacyWorldMapAvatarImageLogicalSize;
  static const double _avatarSpacing = 4;
  static const double _avatarTopGap = 10;
  static const double _pointSize = 8;

  double _ringRadius(int count) {
    if (count < 4) return 0;
    final minimumChord = count > 5
        ? _avatarSize * 0.88
        : _avatarSize + _avatarSpacing;
    final radius = minimumChord / (2 * math.sin(math.pi / count));
    return math.max(_avatarSize * 0.88, radius);
  }

  @override
  Widget build(BuildContext context) {
    final hasUsers = users.isNotEmpty;
    final avatars = users;
    final activityIconsWidth =
        (showEventIcon ? _worldPointEventBadgeExtraWidth : 0.0) +
        (showRecentChatIcon ? _worldPointActivityIconExtraWidth : 0.0) +
        (point.isNew ? _worldPointNewBadgeExtraWidth : 0.0);

    return SizedBox(
      width: markerWidth,
      height: markerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: _WorldPointTapTarget(
                onPointerDown: onPointerDown,
                onTap: onTap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (activityIconsWidth > 0)
                      SizedBox(
                        width: activityIconsWidth,
                        child: showRecentChatIcon
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  RecentChatMapBadge(
                                    badgeKey: ValueKey<String>(
                                      'world-map-recent-chat-icon',
                                    ),
                                  ),
                                  SizedBox(width: _worldPointActivityIconGap),
                                ],
                              )
                            : null,
                      ),
                    SizedBox(
                      width: labelLayout.bubbleWidth,
                      height: labelLayout.height,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              key: ValueKey<String>(
                                'world-map-location-label-${point.id}',
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 6,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: OverflowBox(
                              alignment: Alignment.center,
                              minWidth: labelLayout.layoutWidth,
                              maxWidth: labelLayout.layoutWidth,
                              minHeight: labelLayout.height,
                              maxHeight: labelLayout.height,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 4,
                                ),
                                child: _PointLabel(
                                  point: point,
                                  color: Colors.white,
                                  maxLines: labelLayout.lineCount,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (activityIconsWidth > 0)
                      SizedBox(
                        width: activityIconsWidth,
                        child: Row(
                          children: [
                            if (showEventIcon) ...[
                              const SizedBox(width: _worldPointActivityIconGap),
                              const WorldEventCountBadge(
                                key: ValueKey<String>(
                                  'world-map-location-event-count',
                                ),
                                count: 1,
                              ),
                            ],
                            if (point.isNew) ...[
                              const SizedBox(width: _worldPointActivityIconGap),
                              WorldNewBadge(
                                key: ValueKey<String>(
                                  'world-map-location-new-badge-${point.id}',
                                ),
                                compact: true,
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left:
                markerWidth / 2 - _pointSize / 2 - _worldPointTapTargetPadding,
            top: pointCenterY - _pointSize / 2 - _worldPointTapTargetPadding,
            width: _pointSize + _worldPointTapTargetPadding * 2,
            height: _pointSize + _worldPointTapTargetPadding * 2,
            child: _WorldPointTapTarget(
              onPointerDown: onPointerDown,
              onTap: onTap,
              child: const DecoratedBox(
                key: ValueKey<String>('world-map-location-dot'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF008D68),
                ),
              ),
            ),
          ),
          if (hasUsers)
            for (int i = 0; i < avatars.length; i++)
              _PositionedMapAvatar(
                key: ValueKey<String>(
                  'map-positioned-avatar-'
                  '${worldMapAvatarStableId(avatars[i])}',
                ),
                user: avatars[i],
                left:
                    _avatarLeft(i, avatars.length) -
                    _worldPointTapTargetPadding,
                top:
                    _avatarTop(i, avatars.length) - _worldPointTapTargetPadding,
                enableScaleReboundHint: enableAvatarScaleReboundHint,
                onPointerDown: onPointerDown,
                onTap: onTap,
              ),
        ],
      ),
    );
  }

  double _avatarLeft(int index, int count) {
    if (count < 4) {
      final rowWidth = count * _avatarSize + (count - 1) * _avatarSpacing;
      return markerWidth / 2 -
          rowWidth / 2 +
          index * (_avatarSize + _avatarSpacing);
    }
    if (count == 4) {
      final gridWidth = _avatarSize * 2 + _avatarSpacing;
      final column = index % 2;
      return markerWidth / 2 -
          gridWidth / 2 +
          column * (_avatarSize + _avatarSpacing);
    }

    final radius = _ringRadius(count);
    final ringCenterX = markerWidth / 2;
    final angle = -math.pi / 2 + math.pi * 2 * index / count;
    return ringCenterX + math.cos(angle) * radius - _avatarSize / 2;
  }

  double _avatarTop(int index, int count) {
    if (count < 4) return pointCenterY + _avatarTopGap;
    if (count == 4) {
      final row = index ~/ 2;
      return pointCenterY +
          _avatarTopGap +
          row * (_avatarSize + _avatarSpacing);
    }

    final radius = _ringRadius(count);
    final ringCenterY = pointCenterY + radius + _avatarTopGap + _avatarSize / 2;
    final angle = -math.pi / 2 + math.pi * 2 * index / count;
    return ringCenterY + math.sin(angle) * radius - _avatarSize / 2;
  }
}

class _PointLabel extends StatelessWidget {
  const _PointLabel({required this.point, required this.maxLines, this.color});

  final WorldPoint point;
  final int maxLines;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? Colors.black;
    final style = _worldPointLabelTextStyle.copyWith(color: textColor);
    return Text(
      point.name,
      textAlign: TextAlign.center,
      softWrap: true,
      maxLines: maxLines,
      overflow: TextOverflow.visible,
      style: style,
    );
  }
}

class _PositionedMapAvatar extends StatelessWidget {
  const _PositionedMapAvatar({
    super.key,
    required this.user,
    required this.left,
    required this.top,
    required this.enableScaleReboundHint,
    required this.onPointerDown,
    required this.onTap,
  });

  final UserAvatar user;
  final double left;
  final double top;
  final bool enableScaleReboundHint;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final stableId = worldMapAvatarStableId(user);
    final avatar = SizedBox.square(
      dimension: _worldPointAvatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _MapAvatarImage(
            key: ValueKey<String>('map-avatar-$stableId'),
            url: user.avatarUrl,
            name: (user.name ?? user.initials).trim(),
            isPlayerControlledRole: user.isPlayerControlledRole,
          ),
        ],
      ),
    );
    return Positioned(
      left: left,
      top: top,
      child: _WorldPointTapTarget(
        onPointerDown: onPointerDown,
        onTap: onTap,
        child: enableScaleReboundHint
            ? _MapAvatarScaleReboundHint(child: avatar)
            : avatar,
      ),
    );
  }
}

class _WorldPointTapTarget extends StatelessWidget {
  const _WorldPointTapTarget({
    required this.onPointerDown,
    required this.onTap,
    required this.child,
  });

  final ValueChanged<PointerDownEvent> onPointerDown;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: onPointerDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(_worldPointTapTargetPadding),
          child: child,
        ),
      ),
    );
  }
}

class _MapAvatarScaleReboundHint extends StatefulWidget {
  const _MapAvatarScaleReboundHint({required this.child});

  final Widget child;

  @override
  State<_MapAvatarScaleReboundHint> createState() =>
      _MapAvatarScaleReboundHintState();
}

class _MapAvatarScaleReboundHintState extends State<_MapAvatarScaleReboundHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleNext();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _controller.forward(from: 0).whenComplete(() {
        if (mounted) _scheduleNext();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final progress = _controller.value;
        final rebound =
            math.sin(math.pi * 2.2 * progress) * math.pow(1 - progress, 1.4);
        return Transform.scale(scale: 1 + 0.08 * rebound, child: child);
      },
    );
  }
}

class _MapAvatarImage extends StatelessWidget {
  const _MapAvatarImage({
    super.key,
    required this.url,
    required this.name,
    required this.isPlayerControlledRole,
  });

  final String url;
  final String name;
  final bool isPlayerControlledRole;

  static const double _size = legacyWorldMapAvatarImageLogicalSize;

  @override
  Widget build(BuildContext context) {
    final borderColor = legacyWorldMapAvatarBorderColor(
      isPlayerControlledRole: isPlayerControlledRole,
    );
    return GenesisCharacterAvatar(
      url: url,
      name: name,
      size: _size,
      borderRadius: GenesisAvatarRadii.character,
      showFallbackWhileLoading: false,
      showFallbackWhenUnavailable: true,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ],
      border: borderColor == null
          ? null
          : Border.all(
              color: borderColor,
              width: isPlayerControlledRole ? 2 : 1,
            ),
    );
  }
}
