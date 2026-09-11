import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../ui/components/genesis_static_network_image.dart';
import '../world_map_avatar_logic.dart';
import '../world_map_contract.dart';
import '../world_map_location_action.dart';
import '../world_map_exit_location_button.dart';
import '../world_location_list.dart';
import '../world_point.dart';
import 'legacy_world_map_background.dart';
import 'legacy_world_map_bubble.dart';
import 'legacy_world_map_config.dart';
import 'legacy_world_map_gesture.dart';
import 'legacy_world_map_marker.dart';
import 'legacy_world_map_transition.dart';

class LegacyWorldMap extends StatefulWidget {
  const LegacyWorldMap({super.key, required this.common, required this.config});

  final WorldMapCommonConfig common;
  final LegacyWorldMapConfig config;

  List<WorldPoint> get points => config.points;
  List<WorldPoint>? get listPoints => config.listPoints;
  List<WorldMapLocationNode> get locationNodes => common.locationNodes;
  List<WorldMapLocationNode> get listLocationNodes => config.listLocationNodes;
  String get mapImageUrl => config.mapImageUrl;
  List<String> get preloadMapImageUrls => config.preloadMapImageUrls;
  bool get fallbackOnEmptyMapUrl => config.fallbackOnEmptyMapUrl;
  bool get dimmed => config.dimmed;
  bool get showPointsList => config.showPointsList;
  WidgetBuilder? get pointsListBuilder => config.pointsListBuilder;
  ScrollPhysics? get pointsListPhysics => config.pointsListPhysics;
  bool get pointsListOuterScrollHandoff => config.pointsListOuterScrollHandoff;
  double get overlayTop => config.overlayTop;
  double get drillExitBottom => common.drillExitBottom;
  double? get drillExitMaxWidth => config.drillExitMaxWidth;
  VoidCallback? get onDrillIntoLocation => common.onDrillIntoLocation;
  ValueChanged<WorldMapHorizontalPanState>? get onHorizontalPanStateChanged =>
      config.onHorizontalPanStateChanged;
  VoidCallback? get onMapTap => common.onMapTap;
  WorldPointTapCallback? get onPointTap => common.onPointTap;
  WorldMapMessageBubble? get activeBubble => config.activeBubble;
  List<WorldMapMessageBubble> get messageBubbles => common.messageBubbles;
  bool get messageBubblePlaybackPaused => common.messageBubblePlaybackPaused;
  double get initialZoomScale => config.initialZoomScale;
  bool get enableAvatarScaleReboundHint => config.enableAvatarScaleReboundHint;
  Set<String> get recentChatLocationIds => config.recentChatLocationIds;
  Set<String> get recentChatMapLocationIds => config.recentChatMapLocationIds;
  Set<String> get eventMapLocationIds => config.eventMapLocationIds;
  double? get zoomControlBottom => config.zoomControlBottom;

  @override
  State<LegacyWorldMap> createState() => _LegacyWorldMapState();
}

class _LegacyWorldMapState extends State<LegacyWorldMap> {
  final List<LegacyWorldMapLocationTrailEntry> _locationTrail =
      <LegacyWorldMapLocationTrailEntry>[];
  final Set<String> _pendingLocationTapKeys = <String>{};
  final Map<String, Size> _mapImageDimensionsByUrl = <String, Size>{};
  final Set<String> _pendingMapImageDimensionUrls = <String>{};
  Timer? _messageBubblePlaybackTimer;
  int _messageBubblePlaybackIndex = 0;
  int _messageBubblePageIndex = 0;
  bool _messageBubbleVisible = true;
  double _mapZoomScale = LegacyWorldMapZoomableContent.minScale;
  bool _mapZoomScaleRebuildScheduled = false;
  String _messageBubblePlaybackSignature = '';
  List<WorldMapMessageBubble> _visibleMessageBubblesForPlayback =
      const <WorldMapMessageBubble>[];
  String _lastLoggedLocationTreeSignature = '';
  WorldMapHorizontalPanState? _lastHorizontalPanState;
  Object? _activeZoomControlToken;
  void Function(double delta)? _zoomByControl;
  LegacyWorldMapTransitionSpec _mapTransition =
      const LegacyWorldMapTransitionSpec(
        origin: Alignment.center,
        direction: LegacyWorldMapTransitionDirection.drillIn,
      );

  bool get _hasDrillTree => widget.locationNodes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _mapZoomScale = widget.initialZoomScale
        .clamp(
          LegacyWorldMapZoomableContent.minScale,
          LegacyWorldMapZoomableContent.maxScale,
        )
        .toDouble();
    _debugPrintLocationTree('init');
  }

  @override
  void didUpdateWidget(covariant LegacyWorldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _debugPrintLocationTree('update');
    if (oldWidget.messageBubblePlaybackPaused !=
        widget.messageBubblePlaybackPaused) {
      if (widget.messageBubblePlaybackPaused) {
        _stopMessageBubblePlayback();
      } else {
        _ensureMessageBubblePlayback();
      }
    }
    if (!_hasDrillTree) {
      if (_locationTrail.isNotEmpty) {
        _locationTrail.clear();
      }
      return;
    }

    final currentId = _locationTrail.isEmpty ? '' : _locationTrail.last.id;
    if (currentId.isNotEmpty && _findNode(currentId) == null) {
      _locationTrail.clear();
    }
  }

  @override
  void dispose() {
    _stopMessageBubblePlayback();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentNode = _currentNode;
    final visibleNodes = _hasDrillTree
        ? (currentNode == null ? _initialVisibleNodes : currentNode.children)
        : const <WorldMapLocationNode>[];
    final visiblePoints = _hasDrillTree
        ? visibleNodes.map((node) => node.point).toList(growable: false)
        : widget.points;
    final flattenedPoints = _hasDrillTree
        ? _flattenNodes(
            widget.locationNodes,
          ).map((node) => node.point).toList(growable: false)
        : widget.listPoints ?? widget.points;
    final currentMapImageUrl =
        currentNode?.mapImageUrl.trim().isNotEmpty == true
        ? currentNode!.mapImageUrl
        : _initialMapImageUrl;
    final rawPreloadMapImageUrls = _hasDrillTree
        ? visibleNodes
              .map((node) => node.mapImageUrl.trim())
              .where((url) => url.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : widget.preloadMapImageUrls;
    final exitLocationLabel = currentNode?.point.name ?? '';
    final visibleMessageBubbles = _visibleMessageBubblesForPoints(
      visiblePoints,
    );
    if (widget.messageBubblePlaybackPaused) {
      _stopMessageBubblePlayback();
    } else {
      _syncMessageBubblePlayback(visibleMessageBubbles);
    }
    final activeBubble =
        widget.activeBubble ??
        (widget.messageBubblePlaybackPaused
            ? null
            : _activeBubbleFromVisible(visibleMessageBubbles));

    return LayoutBuilder(
      builder: (context, constraints) {
        final devicePixelRatio =
            MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1;
        final designSize = _mapDesignSize(currentMapImageUrl);
        final viewport = LegacyWorldMapViewport.cover(
          viewportWidth: constraints.maxWidth,
          viewportHeight: constraints.hasBoundedHeight
              ? constraints.maxHeight
              : constraints.maxWidth / (designSize.width / designSize.height),
          designWidth: designSize.width,
          designHeight: designSize.height,
        );
        final backgroundUrl = legacyWorldMapImageUrl(
          currentMapImageUrl,
          logicalWidth: viewport.width,
          devicePixelRatio: devicePixelRatio,
        );
        final backgroundPreviewUrl = legacyWorldMapPreviewImageUrl(
          currentMapImageUrl,
        );
        final preloadMapImageUrls = rawPreloadMapImageUrls
            .map(
              (url) => legacyWorldMapImageUrl(
                url,
                logicalWidth: viewport.width,
                devicePixelRatio: devicePixelRatio,
              ),
            )
            .where((url) => url.isNotEmpty)
            .toSet()
            .toList(growable: false);
        final preloadAvatarUrls = _preloadAvatarUrls(
          visiblePoints,
          devicePixelRatio: devicePixelRatio,
        );
        final mapKeyId = _locationTrail.isEmpty
            ? '__world_root__'
            : _locationTrail.last.id;
        final mapKey = ValueKey<String>(mapKeyId);
        final initialFocus = legacyWorldMapInitialZoomFocus(visiblePoints);
        final visibleViewportSize = Size(
          constraints.maxWidth,
          constraints.hasBoundedHeight
              ? constraints.maxHeight
              : viewport.height,
        );
        final initialTransformKey = [
          mapKeyId,
          currentMapImageUrl,
          widget.initialZoomScale.toStringAsFixed(3),
          visibleViewportSize.width.toStringAsFixed(2),
          visibleViewportSize.height.toStringAsFixed(2),
          viewport.width.toStringAsFixed(2),
          viewport.height.toStringAsFixed(2),
        ].join('|');
        return Stack(
          children: [
            Positioned.fill(
              child: LegacyWorldMapTransitionSurface(
                mapKey: mapKey,
                transition: _mapTransition,
                child: LegacyWorldMapZoomableContent(
                  background: LegacyWorldMapBackgroundDeck(
                    currentUrl: backgroundUrl,
                    previewUrl: backgroundPreviewUrl,
                    preloadUrls: preloadMapImageUrls,
                    preloadAvatarUrls: preloadAvatarUrls,
                    fallbackOnEmptyUrl: widget.fallbackOnEmptyMapUrl,
                  ),
                  contentSize: Size(viewport.width, viewport.height),
                  initialScale: widget.initialZoomScale,
                  initialFocus: initialFocus,
                  initialTransformKey: initialTransformKey,
                  initialViewportSize: visibleViewportSize,
                  overlayBuilder: (context, transform, onOverlayPointerDown) =>
                      Stack(
                        fit: StackFit.expand,
                        children: [
                          IgnorePointer(
                            ignoring: widget.showPointsList,
                            child: Opacity(
                              opacity: widget.showPointsList ? 0.6 : 1,
                              child: Stack(
                                children: [
                                  for (final p in visiblePoints)
                                    LegacyWorldMapPointPositioned(
                                      point: p,
                                      showRecentChatIcon:
                                          legacyWorldMapPointMatchesLocationIds(
                                            p,
                                            widget.recentChatMapLocationIds,
                                          ),
                                      showEventIcon:
                                          legacyWorldMapPointMatchesLocationIds(
                                            p,
                                            widget.eventMapLocationIds,
                                          ),
                                      width: viewport.width,
                                      height: viewport.height,
                                      transform: transform,
                                      enableAvatarScaleReboundHint:
                                          widget.enableAvatarScaleReboundHint,
                                      onPointerDown: onOverlayPointerDown,
                                      onTap: _pointTapHandler(p),
                                    ),
                                  if (activeBubble != null)
                                    for (final p in visiblePoints)
                                      LegacyWorldMapPointMessageBubblePositioned(
                                        point: p,
                                        width: viewport.width,
                                        height: viewport.height,
                                        transform: transform,
                                        onPointerDown: onOverlayPointerDown,
                                        onTap: _pointTapHandler(p),
                                        messageBubble: _bubbleForPoint(
                                          p,
                                          activeBubble,
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              color: widget.dimmed
                                  ? Colors.black.withValues(alpha: 0.08)
                                  : Colors.transparent,
                            ),
                          ),
                        ],
                      ),
                  onMapTap: widget.onMapTap,
                  onScaleChanged: _handleMapZoomScaleChanged,
                  onHorizontalPanStateChanged: _handleHorizontalPanStateChanged,
                  onZoomControlChanged: _handleZoomControlChanged,
                ),
              ),
            ),
            if (widget.showPointsList)
              Positioned.fill(child: ColoredBox(color: Colors.white)),
            if (widget.showPointsList)
              Positioned.fill(
                child:
                    widget.pointsListBuilder?.call(context) ??
                    Column(
                      children: [
                        Expanded(
                          child: WorldLocationList(
                            points: flattenedPoints,
                            locationNodes: widget.listLocationNodes.isNotEmpty
                                ? widget.listLocationNodes
                                : widget.locationNodes,
                            recentChatLocationIds: widget.recentChatLocationIds,
                            physics: widget.pointsListPhysics,
                            enableOuterScrollHandoff:
                                widget.pointsListOuterScrollHandoff,
                            padding: EdgeInsets.fromLTRB(
                              12,
                              widget.overlayTop + 8,
                              12,
                              12,
                            ),
                            onPointTap: (point) {
                              widget.onPointTap?.call(
                                _withCurrentMapImage(point),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
              ),
            if (_locationTrail.isNotEmpty && !widget.showPointsList)
              Positioned(
                left: 12,
                right: 12,
                bottom: widget.drillExitBottom,
                child: WorldMapCenteredExitLocationButton(
                  buttonKey: const ValueKey<String>(
                    'legacy-world-map-exit-location',
                  ),
                  label: exitLocationLabel,
                  maxWidth: widget.drillExitMaxWidth,
                  onPressed: _exitLocation,
                ),
              ),
            if (!widget.showPointsList)
              Positioned(
                right: legacyWorldMapZoomControlRightGap,
                bottom:
                    widget.zoomControlBottom ??
                    legacyWorldMapZoomControlBottomGap,
                child: LegacyWorldMapZoomControl(
                  value: _mapZoomScale,
                  min: LegacyWorldMapZoomableContent.minScale,
                  max: LegacyWorldMapZoomableContent.maxScale,
                  onChanged: (scale) =>
                      _zoomByControl?.call(scale - _mapZoomScale),
                  canZoomIn:
                      _mapZoomScale <
                      LegacyWorldMapZoomableContent.maxScale - 0.001,
                  canZoomOut:
                      _mapZoomScale >
                      LegacyWorldMapZoomableContent.minScale + 0.001,
                  onZoomIn: () => _zoomByControl?.call(0.25),
                  onZoomOut: () => _zoomByControl?.call(-0.25),
                ),
              ),
          ],
        );
      },
    );
  }

  void _handleMapZoomScaleChanged(double scale) {
    if (!mounted) return;
    if ((_mapZoomScale - scale).abs() < 0.001) return;
    _mapZoomScale = scale;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_mapZoomScaleRebuildScheduled) {
        _mapZoomScaleRebuildScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapZoomScaleRebuildScheduled = false;
          if (mounted) setState(() {});
        });
      }
    } else if (mounted) {
      setState(() {});
    }
  }

  void _handleHorizontalPanStateChanged(WorldMapHorizontalPanState state) {
    final callback = widget.onHorizontalPanStateChanged;
    if (callback == null) return;
    final previousState = _lastHorizontalPanState;
    if (previousState != null &&
        previousState.canScrollLeft == state.canScrollLeft &&
        previousState.canScrollRight == state.canScrollRight) {
      return;
    }
    _lastHorizontalPanState = state;
    callback(state);
  }

  void _handleZoomControlChanged(
    Object token,
    void Function(double delta)? zoomByControl,
  ) {
    if (zoomByControl == null) {
      if (identical(_activeZoomControlToken, token)) {
        _activeZoomControlToken = null;
        _zoomByControl = null;
      }
      return;
    }

    _activeZoomControlToken = token;
    _zoomByControl = zoomByControl;
  }

  VoidCallback? _pointTapHandler(WorldPoint point) {
    if (_hasDrillTree) {
      final node = _findPointNode(point);
      if (node == null) return null;
      final chatTarget = resolveWorldMapLocationAction(node).chatTarget;
      if (chatTarget != null && widget.onPointTap == null) return null;
      return () {
        unawaited(_handlePointTap(point));
      };
    }
    if (widget.onPointTap == null) return null;
    return () {
      unawaited(_handlePointTap(point));
    };
  }

  Future<void> _handlePointTap(WorldPoint point) async {
    if (_hasDrillTree) {
      final node = _findPointNode(point);
      if (node != null) {
        final action = resolveWorldMapLocationAction(node);
        final chatTarget = action.chatTarget;
        if (chatTarget != null) {
          await _runLocationTapLocked(
            _locationTapKey(chatTarget),
            () => widget.onPointTap?.call(_withCurrentMapImage(chatTarget)),
          );
          return;
        }
        final displayNode = action.drillTarget;
        if (displayNode == null) return;
        await _runLocationTapLocked(_locationTapKey(point), () async {
          widget.onDrillIntoLocation?.call();
          final origin = legacyWorldMapTransitionOrigin(point);
          final path = displayNode.id == node.id
              ? _nodePath(displayNode.id)
              : <String>[displayNode.id];
          setState(() {
            _mapTransition = LegacyWorldMapTransitionSpec(
              origin: origin,
              direction: LegacyWorldMapTransitionDirection.drillIn,
            );
            _locationTrail
              ..clear()
              ..addAll(
                (path.isEmpty ? <String>[displayNode.id] : path).map(
                  (id) => LegacyWorldMapLocationTrailEntry(
                    id: id,
                    origin: id == displayNode.id ? origin : Alignment.center,
                  ),
                ),
              );
          });
          await WidgetsBinding.instance.endOfFrame;
        });
        return;
      }
    }

    await _runLocationTapLocked(
      _locationTapKey(point),
      () => widget.onPointTap?.call(_withCurrentMapImage(point)),
    );
  }

  WorldPoint _withCurrentMapImage(WorldPoint point) {
    final currentMapImageUrl = _currentMapImageUrl.trim();
    if (currentMapImageUrl.isEmpty || point.mapImageUrl == currentMapImageUrl) {
      return point;
    }
    return WorldPoint(
      id: point.id,
      name: point.name,
      type: point.type,
      position: point.position,
      users: point.users,
      sceneId: point.sceneId,
      pointId: point.pointId,
      iconUrl: point.iconUrl,
      mapImageUrl: currentMapImageUrl,
      description: point.description,
      locationDescription: point.locationDescription,
      depth: point.depth,
      isLeafLocation: point.isLeafLocation,
      isNew: point.isNew,
    );
  }

  Future<void> _runLocationTapLocked(
    String key,
    FutureOr<void> Function() action,
  ) async {
    if (key.isNotEmpty && !_pendingLocationTapKeys.add(key)) return;
    try {
      await action();
    } finally {
      if (key.isNotEmpty) _pendingLocationTapKeys.remove(key);
    }
  }

  String _locationTapKey(WorldPoint point) {
    final sceneId = point.sceneId.trim();
    if (sceneId.isNotEmpty) return sceneId;
    final pointId = point.pointId.trim();
    if (pointId.isNotEmpty) return pointId;
    return point.id.trim();
  }

  void _exitLocation() {
    if (_locationTrail.isEmpty) return;
    widget.onDrillIntoLocation?.call();
    final origin = _locationTrail.last.origin;
    setState(() {
      _mapTransition = LegacyWorldMapTransitionSpec(
        origin: origin,
        direction: LegacyWorldMapTransitionDirection.drillOut,
      );
      _locationTrail.removeLast();
    });
  }

  WorldMapLocationNode? get _currentNode {
    if (_locationTrail.isEmpty) return null;
    return _findNode(_locationTrail.last.id);
  }

  List<WorldMapLocationNode> get _initialVisibleNodes {
    final explicitRootChildren = widget.locationNodes
        .where((node) => node.isRoot)
        .expand((node) => node.children)
        .toList(growable: false);
    if (explicitRootChildren.isNotEmpty ||
        widget.locationNodes.any((node) => node.isRoot)) {
      return explicitRootChildren;
    }

    return widget.locationNodes;
  }

  String get _initialMapImageUrl {
    final detailMapImageUrl = widget.mapImageUrl.trim();
    if (detailMapImageUrl.isNotEmpty) return widget.mapImageUrl;

    for (final node in widget.locationNodes) {
      if (!node.isRoot) continue;
      final rootMapImageUrl = node.mapImageUrl.trim();
      if (rootMapImageUrl.isNotEmpty) return rootMapImageUrl;
    }
    return widget.mapImageUrl;
  }

  String get _currentMapImageUrl {
    final currentNode = _currentNode;
    return currentNode?.mapImageUrl.trim().isNotEmpty == true
        ? currentNode!.mapImageUrl
        : _initialMapImageUrl;
  }

  WorldMapLocationNode? _findPointNode(WorldPoint point) {
    final targetId = legacyWorldMapPointLocationId(point);
    if (targetId.isEmpty) return null;
    return _findNode(targetId);
  }

  List<WorldMapMessageBubble> _visibleMessageBubblesForPoints(
    List<WorldPoint> points,
  ) {
    if (widget.messageBubbles.isEmpty) return const <WorldMapMessageBubble>[];
    final visibleCharacterIds = <String>{};
    for (final point in points) {
      for (final user in worldMapVisibleAvatarsForPoint(point)) {
        final id = user.id.trim();
        if (id.isNotEmpty) visibleCharacterIds.add(id);
      }
    }
    if (visibleCharacterIds.isEmpty) return const <WorldMapMessageBubble>[];
    return widget.messageBubbles
        .where(
          (bubble) =>
              visibleCharacterIds.contains(bubble.characterId.trim()) &&
              bubble.content.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  WorldMapMessageBubble? _activeBubbleFromVisible(
    List<WorldMapMessageBubble> visibleBubbles,
  ) {
    if (visibleBubbles.isEmpty) return null;
    if (!_messageBubbleVisible) return null;
    final index = _messageBubblePlaybackIndex % visibleBubbles.length;
    final bubble = visibleBubbles[index];
    final pages = _messageBubblePages(bubble.content);
    final page = pages.isEmpty
        ? ''
        : pages[_messageBubblePageIndex % pages.length];
    if (page.isEmpty) return null;
    return WorldMapMessageBubble(
      characterId: bubble.characterId,
      content: page,
      preservePageWidth: _messageBubblePageIndex > 0,
    );
  }

  void _syncMessageBubblePlayback(List<WorldMapMessageBubble> visibleBubbles) {
    final signature = _messageBubblePlaybackKey(visibleBubbles);
    if (signature.isEmpty) {
      _messageBubblePlaybackSignature = '';
      _visibleMessageBubblesForPlayback = const <WorldMapMessageBubble>[];
      _messageBubbleVisible = false;
      _stopMessageBubblePlayback();
      return;
    }
    if (_messageBubblePlaybackSignature != signature) {
      _messageBubblePlaybackSignature = signature;
      _visibleMessageBubblesForPlayback = visibleBubbles;
      _messageBubblePlaybackIndex = 0;
      _messageBubblePageIndex = 0;
      _messageBubbleVisible = true;
      _stopMessageBubblePlayback();
    } else {
      _visibleMessageBubblesForPlayback = visibleBubbles;
    }
    if (_messageBubblePlaybackIndex >= visibleBubbles.length) {
      _messageBubblePlaybackIndex = 0;
      _messageBubblePageIndex = 0;
    }
    _ensureMessageBubblePlayback();
  }

  void _ensureMessageBubblePlayback() {
    if (widget.messageBubblePlaybackPaused ||
        _messageBubblePlaybackTimer != null ||
        _messageBubblePlaybackSignature.isEmpty) {
      return;
    }
    final duration = _messageBubbleVisible
        ? legacyWorldMapBubbleDisplayDuration
        : legacyWorldMapBubbleGapDuration;
    _messageBubblePlaybackTimer = Timer(duration, () {
      _messageBubblePlaybackTimer = null;
      if (!mounted || _messageBubblePlaybackSignature.isEmpty) return;
      setState(() {
        if (_messageBubbleVisible) {
          final activeBubble = _activeBubbleForPlayback();
          final pageCount = activeBubble == null
              ? 1
              : _messageBubblePages(activeBubble.content).length;
          if (_messageBubblePageIndex + 1 < pageCount) {
            _messageBubblePageIndex += 1;
          } else {
            _messageBubbleVisible = false;
          }
        } else {
          _messageBubblePlaybackIndex += 1;
          _messageBubblePageIndex = 0;
          _messageBubbleVisible = true;
        }
      });
      _ensureMessageBubblePlayback();
    });
  }

  void _stopMessageBubblePlayback() {
    _messageBubblePlaybackTimer?.cancel();
    _messageBubblePlaybackTimer = null;
  }

  String _messageBubblePlaybackKey(List<WorldMapMessageBubble> bubbles) {
    if (bubbles.isEmpty) return '';
    return bubbles
        .map((bubble) => '${bubble.characterId.trim()}\u{1f}${bubble.content}')
        .join('\u{1e}');
  }

  List<String> _messageBubblePages(String content) {
    return resolveWorldMapMessageBubblePages(context, content);
  }

  WorldMapMessageBubble? _activeBubbleForPlayback() {
    final bubbles = _visibleMessageBubblesForPlayback;
    if (bubbles.isEmpty) return null;
    return bubbles[_messageBubblePlaybackIndex % bubbles.length];
  }

  WorldMapMessageBubble? _bubbleForPoint(
    WorldPoint point,
    WorldMapMessageBubble? bubble,
  ) {
    if (bubble == null) return null;
    final characterId = bubble.characterId.trim();
    if (characterId.isEmpty || bubble.content.trim().isEmpty) return null;
    for (final user in worldMapVisibleAvatarsForPoint(point)) {
      if (user.id.trim() == characterId) return bubble;
    }
    return null;
  }

  WorldMapLocationNode? _findNode(String nodeId) {
    return findWorldMapLocationNode(widget.locationNodes, nodeId);
  }

  List<String> _nodePath(String nodeId) {
    final targetId = nodeId.trim();
    if (targetId.isEmpty) return const <String>[];

    List<String>? visit(WorldMapLocationNode node) {
      if (node.id == targetId) return <String>[node.id];
      for (final child in node.children) {
        final childPath = visit(child);
        if (childPath != null) return <String>[node.id, ...childPath];
      }
      return null;
    }

    for (final root in widget.locationNodes) {
      final path = visit(root);
      if (path != null) {
        final hiddenRootId = root.id.trim();
        if (root.isRoot &&
            hiddenRootId.isNotEmpty &&
            path.isNotEmpty &&
            path.first == hiddenRootId) {
          return path.skip(1).toList(growable: false);
        }
        return path;
      }
    }
    return const <String>[];
  }

  List<WorldMapLocationNode> _flattenNodes(List<WorldMapLocationNode> nodes) {
    return <WorldMapLocationNode>[
      for (final node in nodes) ...[node, ..._flattenNodes(node.children)],
    ];
  }

  List<String> _preloadAvatarUrls(
    List<WorldPoint> visiblePoints, {
    required double devicePixelRatio,
  }) {
    return visiblePoints
        .expand(worldMapVisibleAvatarsForPoint)
        .map(
          (user) => legacyWorldMapAvatarUrl(
            user.avatarUrl,
            devicePixelRatio: devicePixelRatio,
          ).trim(),
        )
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Size _mapDesignSize(String mapImageUrl) {
    const fallbackSize = Size(1024, 1536);
    final url = mapImageUrl.trim();
    if (url.isEmpty) return fallbackSize;
    final cachedSize = _mapImageDimensionsByUrl[url];
    if (cachedSize != null && !cachedSize.isEmpty) return cachedSize;
    _resolveMapImageDimensions(url);
    return fallbackSize;
  }

  void _resolveMapImageDimensions(String url) {
    if (_pendingMapImageDimensionUrls.contains(url)) return;
    _pendingMapImageDimensionUrls.add(url);

    final ImageProvider imageProvider = url.startsWith('assets/')
        ? AssetImage(url)
        : GenesisStaticNetworkImageProvider(imageUrl: url);
    final stream = imageProvider.resolve(
      createLocalImageConfiguration(context),
    );
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (imageInfo, _) {
        stream.removeListener(listener);
        _pendingMapImageDimensionUrls.remove(url);
        final image = imageInfo.image;
        final size = Size(image.width.toDouble(), image.height.toDouble());
        if (size.isEmpty) return;
        _applyResolvedMapImageDimensions(url, size);
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        _pendingMapImageDimensionUrls.remove(url);
        debugPrint(
          '[WorldMap] resolve map dimensions failed url="$url": $error',
        );
      },
    );
    stream.addListener(listener);
  }

  void _applyResolvedMapImageDimensions(String url, Size size) {
    final previousSize = _mapImageDimensionsByUrl[url];
    if (previousSize == size) return;
    _mapImageDimensionsByUrl[url] = size;
    if (!mounted) return;

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }

    setState(() {});
  }

  void _debugPrintLocationTree(String reason) {
    if (!kDebugMode) return;

    final buffer = StringBuffer();
    for (final node in widget.locationNodes) {
      _writeLocationNodeDebug(buffer, node, 0);
    }

    final treeText = buffer.toString();
    final signature = [
      widget.mapImageUrl,
      _initialMapImageUrl,
      treeText,
    ].join('\n');
    if (signature == _lastLoggedLocationTreeSignature) return;
    _lastLoggedLocationTreeSignature = signature;

    debugPrint(
      '[WorldMap] location tree $reason: '
      'roots=${widget.locationNodes.length}, '
      'widgetMapUrl="${widget.mapImageUrl}", '
      'initialMapUrl="$_initialMapImageUrl"',
    );
    if (widget.locationNodes.isEmpty) {
      debugPrint('[WorldMap] location tree is empty');
      return;
    }
    debugPrint(treeText);
  }

  void _writeLocationNodeDebug(
    StringBuffer buffer,
    WorldMapLocationNode node,
    int depth,
  ) {
    final indent = '  ' * depth;
    buffer.writeln(
      '$indent- id="${node.id}" '
      'name="${node.point.name}" '
      'pointId="${node.point.id}" '
      'sceneId="${node.point.sceneId}" '
      'isRoot=${node.isRoot} '
      'pointDepth=${node.point.depth} '
      'isLeafPoint=${node.point.isLeafLocation} '
      'children=${node.children.length} '
      'mapUrl="${node.mapImageUrl}"',
    );
    for (final child in node.children) {
      _writeLocationNodeDebug(buffer, child, depth + 1);
    }
  }
}
