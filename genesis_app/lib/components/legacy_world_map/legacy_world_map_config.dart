import 'package:flutter/material.dart';

import '../world_point.dart';
import '../world_map_contract.dart';

@immutable
class LegacyWorldMapConfig {
  const LegacyWorldMapConfig({
    required this.points,
    this.implementationKey,
    this.listPoints,
    this.listLocationNodes = const <WorldMapLocationNode>[],
    this.mapImageUrl = '',
    this.preloadMapImageUrls = const <String>[],
    this.fallbackOnEmptyMapUrl = true,
    this.dimmed = false,
    this.showPointsList = false,
    this.pointsListBuilder,
    this.pointsListPhysics,
    this.pointsListOuterScrollHandoff = true,
    this.overlayTop = 0,
    this.drillExitMaxWidth,
    this.onHorizontalPanStateChanged,
    this.activeBubble,
    this.initialZoomScale = 1,
    this.enableAvatarScaleReboundHint = false,
    this.recentChatLocationIds = const <String>{},
    this.recentChatMapLocationIds = const <String>{},
    this.eventMapLocationIds = const <String>{},
    this.zoomControlBottom,
  });

  final Key? implementationKey;
  final List<WorldPoint> points;
  final List<WorldPoint>? listPoints;
  final List<WorldMapLocationNode> listLocationNodes;
  final String mapImageUrl;
  final List<String> preloadMapImageUrls;
  final bool fallbackOnEmptyMapUrl;
  final bool dimmed;
  final bool showPointsList;
  final WidgetBuilder? pointsListBuilder;
  final ScrollPhysics? pointsListPhysics;
  final bool pointsListOuterScrollHandoff;
  final double overlayTop;
  final double? drillExitMaxWidth;
  final ValueChanged<WorldMapHorizontalPanState>? onHorizontalPanStateChanged;
  final WorldMapMessageBubble? activeBubble;
  final double initialZoomScale;
  final bool enableAvatarScaleReboundHint;
  final Set<String> recentChatLocationIds;
  final Set<String> recentChatMapLocationIds;
  final Set<String> eventMapLocationIds;

  /// Gap from the map bottom to the zoom control; null keeps the legacy gap.
  final double? zoomControlBottom;
}
