import 'package:flutter/material.dart';

import 'legacy_world_map/legacy_world_map.dart';
import 'legacy_world_map/legacy_world_map_config.dart';
import 'tilemap/tilemap.dart';
import 'world_map_contract.dart';
import 'world_point.dart';

export 'legacy_world_map/legacy_world_map_background.dart'
    show kWorldMapFallbackBackgroundAsset;
export 'legacy_world_map/legacy_world_map_bubble.dart'
    show worldMapMessageBubblePagesForTesting;
export 'legacy_world_map/legacy_world_map_config.dart'
    show LegacyWorldMapConfig;
export 'legacy_world_map/legacy_world_map_marker.dart'
    show
        worldMapAvatarBorderColorForTesting,
        worldMapInitialZoomFocusForTesting;
export 'tilemap/tilemap.dart' show TilemapRestorationController;
export 'world_location_list.dart';
export 'world_map_avatar_logic.dart';
export 'world_map_contract.dart';
export 'world_point.dart';

const Color kWorldMapLoadingBackgroundColor = Colors.black;

@immutable
class WorldMapTilemapOptions {
  const WorldMapTilemapOptions({
    this.implementationKey,
    this.locationId = 'root',
    this.locationNodes,
    this.preferredFocusLocationId = '',
    this.centerContentInitially = false,
    this.showVisualModeToggle = true,
    this.visualModeToggleTop,
    this.visualModeToggleRight = 9.5,
    this.zoomControlBottom,
    this.recentChatLocationIds = const <String>{},
    this.eventLocationIds = const <String>{},
    this.animationsPaused = false,
    this.locationImageFlowPaused = false,
    this.reloadRevision = 0,
    this.restorationController,
    this.onMapTap,
    this.onDisplayReadinessChanged,
    this.onDisplayError,
    this.onCurrentLocationsChanged,
  });

  final Key? implementationKey;
  final String locationId;

  /// Full, uncollapsed tree used to resolve map_json tile location IDs.
  /// Falls back to [WorldMapCommonConfig.locationNodes] when omitted.
  final List<WorldMapLocationNode>? locationNodes;
  final String preferredFocusLocationId;
  final bool centerContentInitially;
  final bool showVisualModeToggle;
  final double? visualModeToggleTop;
  final double visualModeToggleRight;
  final double? zoomControlBottom;
  final Set<String> recentChatLocationIds;
  final Set<String> eventLocationIds;
  final bool animationsPaused;
  final bool locationImageFlowPaused;
  final int reloadRevision;
  final TilemapRestorationController? restorationController;
  final VoidCallback? onMapTap;
  final ValueChanged<bool>? onDisplayReadinessChanged;
  final ValueChanged<Object>? onDisplayError;
  final TilemapCurrentLocationsChanged? onCurrentLocationsChanged;
}

enum _WorldMapSource { origin, world }

class WorldMap extends StatelessWidget {
  const WorldMap.origin({
    super.key,
    required this.definitionVersion,
    required String originId,
    required this.common,
    required this.legacy,
    this.tilemap = const WorldMapTilemapOptions(),
  }) : _source = _WorldMapSource.origin,
       _entityId = originId;

  const WorldMap.world({
    super.key,
    required this.definitionVersion,
    required String worldId,
    required this.common,
    required this.legacy,
    this.tilemap = const WorldMapTilemapOptions(),
  }) : _source = _WorldMapSource.world,
       _entityId = worldId;

  final int? definitionVersion;
  final WorldMapCommonConfig common;
  final LegacyWorldMapConfig legacy;
  final WorldMapTilemapOptions tilemap;
  final _WorldMapSource _source;
  final String _entityId;

  bool get _usesTilemap => definitionVersion == 2;

  @override
  Widget build(BuildContext context) {
    final legacyMap = LegacyWorldMap(
      key: legacy.implementationKey,
      common: common,
      config: legacy,
    );
    if (!_usesTilemap) return legacyMap;

    final tilemapMap = switch (_source) {
      _WorldMapSource.origin => Tilemap.origin(
        key: tilemap.implementationKey,
        originId: _entityId,
        locationId: tilemap.locationId,
        locationNodes: tilemap.locationNodes ?? common.locationNodes,
        preferredFocusLocationId: tilemap.preferredFocusLocationId,
        centerContentInitially: tilemap.centerContentInitially,
        drillExitBottom: common.drillExitBottom,
        drillExitMaxWidth: legacy.drillExitMaxWidth,
        showVisualModeToggle: tilemap.showVisualModeToggle,
        visualModeToggleTop: tilemap.visualModeToggleTop,
        visualModeToggleRight: tilemap.visualModeToggleRight,
        zoomControlBottom: tilemap.zoomControlBottom,
        recentChatLocationIds: tilemap.recentChatLocationIds,
        eventLocationIds: tilemap.eventLocationIds,
        animationsPaused: tilemap.animationsPaused,
        locationImageFlowPaused: tilemap.locationImageFlowPaused,
        reloadRevision: tilemap.reloadRevision,
        messageBubbles: common.messageBubbles,
        messageBubblePlaybackPaused:
            common.messageBubblePlaybackPaused || legacy.showPointsList,
        onDrillIntoLocation: common.onDrillIntoLocation,
        onMapTap: tilemap.onMapTap ?? common.onMapTap,
        onPointTap: common.onPointTap,
        restorationController: tilemap.restorationController,
        onDisplayReadinessChanged: tilemap.onDisplayReadinessChanged,
        onDisplayError: tilemap.onDisplayError,
        onCurrentLocationsChanged: tilemap.onCurrentLocationsChanged,
      ),
      _WorldMapSource.world => Tilemap.world(
        key: tilemap.implementationKey,
        worldId: _entityId,
        locationId: tilemap.locationId,
        locationNodes: tilemap.locationNodes ?? common.locationNodes,
        preferredFocusLocationId: tilemap.preferredFocusLocationId,
        centerContentInitially: tilemap.centerContentInitially,
        drillExitBottom: common.drillExitBottom,
        drillExitMaxWidth: legacy.drillExitMaxWidth,
        showVisualModeToggle: tilemap.showVisualModeToggle,
        visualModeToggleTop: tilemap.visualModeToggleTop,
        visualModeToggleRight: tilemap.visualModeToggleRight,
        zoomControlBottom: tilemap.zoomControlBottom,
        recentChatLocationIds: tilemap.recentChatLocationIds,
        eventLocationIds: tilemap.eventLocationIds,
        animationsPaused: tilemap.animationsPaused,
        locationImageFlowPaused: tilemap.locationImageFlowPaused,
        reloadRevision: tilemap.reloadRevision,
        messageBubbles: common.messageBubbles,
        messageBubblePlaybackPaused: common.messageBubblePlaybackPaused,
        onDrillIntoLocation: common.onDrillIntoLocation,
        onMapTap: tilemap.onMapTap ?? common.onMapTap,
        onPointTap: common.onPointTap,
        restorationController: tilemap.restorationController,
        onDisplayReadinessChanged: tilemap.onDisplayReadinessChanged,
        onDisplayError: tilemap.onDisplayError,
        onCurrentLocationsChanged: tilemap.onCurrentLocationsChanged,
      ),
    };

    if (_source == _WorldMapSource.origin) {
      return Stack(
        fit: StackFit.expand,
        children: [
          tilemapMap,
          if (legacy.showPointsList) Positioned.fill(child: legacyMap),
        ],
      );
    }
    if (_source == _WorldMapSource.world && legacy.showPointsList) {
      return legacyMap;
    }
    return tilemapMap;
  }
}
