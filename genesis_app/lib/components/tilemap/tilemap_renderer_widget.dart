part of 'tilemap_renderer_library.dart';

const int _foregroundVisibleTileMountBatchSize = 6;
const int _backgroundVisibleTileMountBatchSize = 2;
const int _retainedTileMountBatchSize = 2;
const int _newTileAssetMountBatchSize = 2;

class TilemapRenderer extends StatefulWidget {
  const TilemapRenderer({
    super.key,
    required this.config,
    this.initialTransform,
    this.onTransformChanged,
    this.onTileAction,
    this.locationNameForTile,
    this.locationAvatarsForTile,
    this.showRecentChatForTile,
    this.showEventForTile,
    this.showNewForTile,
    this.preferredFocusLocationId = '',
    this.centerContentInitially = false,
    this.messageBubbles = const <WorldMapMessageBubble>[],
    this.messageBubblePlaybackPaused = false,
    this.onMapTap,
    this.onImageError,
    this.onViewportReady,
    this.waitForVisibleTileImageFrames = true,
    this.isForeground = true,
    this.animationsPaused = false,
    this.locationImageFlowPaused = false,
    this.visualMode = tilemapDefaultVisualMode,
    this.fogControlPoints = tilemapDefaultFogControlPoints,
    this.blendFogWithShadowTiles = tilemapDefaultBlendFogWithShadowTiles,
    this.cacheFogTileBitmaps = tilemapDefaultCacheFogTileBitmaps,
    this.showShadowZeroBorders = tilemapDefaultShowShadowZeroBorders,
    this.showLocationImageFlow = tilemapDefaultShowLocationImageFlow,
    this.locationImageFlowAngleDegrees =
        tilemapDefaultLocationImageFlowAngleDegrees,
    this.locationImageFlowGradientPoints =
        tilemapDefaultLocationImageFlowGradientPoints,
    this.locationImageFlowOpacity = tilemapDefaultLocationImageFlowOpacity,
    this.locationImageFlowDurationSeconds =
        tilemapDefaultLocationImageFlowDurationSeconds,
    this.locationImageFlowBlendMode = tilemapDefaultLocationImageFlowBlendMode,
    this.initialScale = tilemapDefaultInitialScale,
    this.dragBoundaryPaddingTiles = tilemapDefaultDragBoundaryPaddingTiles,
    this.zoomControlBottom,
  });

  final TilemapConfig config;
  final Matrix4? initialTransform;
  final ValueChanged<Matrix4>? onTransformChanged;
  final TilemapTileActionHandler? onTileAction;
  final TilemapLocationNameResolver? locationNameForTile;
  final TilemapLocationAvatarsResolver? locationAvatarsForTile;
  final TilemapRecentChatResolver? showRecentChatForTile;
  final TilemapEventResolver? showEventForTile;
  final TilemapNewLocationResolver? showNewForTile;
  final String preferredFocusLocationId;
  final bool centerContentInitially;
  final List<WorldMapMessageBubble> messageBubbles;
  final bool messageBubblePlaybackPaused;
  final VoidCallback? onMapTap;
  final ValueChanged<Object>? onImageError;
  final VoidCallback? onViewportReady;
  final bool waitForVisibleTileImageFrames;
  final bool isForeground;
  final bool animationsPaused;
  final bool locationImageFlowPaused;
  final TilemapVisualMode visualMode;
  final List<TilemapFogControlPoint> fogControlPoints;
  final bool blendFogWithShadowTiles;
  final bool cacheFogTileBitmaps;
  final bool showShadowZeroBorders;
  final bool showLocationImageFlow;
  final double locationImageFlowAngleDegrees;
  final List<TilemapLocationImageFlowGradientPoint>
  locationImageFlowGradientPoints;
  final double locationImageFlowOpacity;
  final double locationImageFlowDurationSeconds;
  final TilemapLocationImageFlowBlendMode locationImageFlowBlendMode;
  final double initialScale;
  final double dragBoundaryPaddingTiles;

  /// Gap from the map's bottom edge to the zoom control. Hosts that float
  /// chrome over the map raise it clear; null keeps the legacy gap.
  final double? zoomControlBottom;

  @override
  State<TilemapRenderer> createState() => _TilemapRendererState();
}

class _TilemapRendererState extends State<TilemapRenderer>
    with TickerProviderStateMixin {
  late final TransformationController _transformationController;
  late final AnimationController _locationImageFlowController;
  Matrix4 _gestureStartTransform = Matrix4.identity();
  Offset _gestureStartFocalPoint = Offset.zero;
  Size? _lastViewportSize;
  Size? _lastMapSize;
  Rect? _lastContentBounds;
  double? _lastInitialScale;
  Offset? _lastInitialFocus;
  Rect? _lastDragBoundary;
  TilemapConfig? _renderIndexConfig;
  double? _renderIndexMapWidth;
  double? _renderIndexMapHeight;
  double? _renderIndexTileExtent;
  double? _renderIndexOriginX;
  _TilemapRenderIndex? _renderIndex;
  TilemapFogGeometry? _fogGeometry;
  Rect? _retainedSceneBounds;
  List<_TilemapRenderRecord> _retainedRecords = const [];
  List<TilemapCell> _retainedTiles = const [];
  Rect? _fogBounds;
  List<TilemapFogControlPoint>? _fogControlPoints;
  List<TilemapCell>? _fogRenderTiles;
  TilemapFogField? _fogField;
  bool _hasLocationImageFlowTiles = false;
  bool _locationImageFlowSyncScheduled = false;
  bool _hasUserTransformedMap = false;
  bool _isRunningTileAction = false;
  Set<String>? _initialViewportTileKeys;

  final Set<String> _initialViewportFramedTileKeys = <String>{};
  final List<VoidCallback> _notifiedViewportReadyCallbacks = <VoidCallback>[];
  bool _viewportReadyCallbackScheduled = false;
  bool _isViewportReady = false;
  int _viewportReadyGeneration = 0;
  final Set<String> _revealedTileKeys = <String>{};
  final Map<String, String> _revealedTileAssets = <String, String>{};
  final Set<String> _probingTileAssets = <String>{};
  final Set<String> _readyTileAssets = <String>{};
  List<_TilemapRenderRecord> _pendingVisibleRecords = const [];
  List<_TilemapRenderRecord> _pendingRetainedRecords = const [];
  double _progressiveMountTilePixelSize = 0;
  bool _hasStartedProgressiveMount = false;
  bool _progressiveMountCallbackScheduled = false;
  int _progressiveMountGeneration = 0;
  int _progressiveMountScheduleGeneration = 0;
  bool _hasViewportReadinessEnvironment = false;
  Size? _viewportReadinessSize;
  double? _viewportReadinessDevicePixelRatio;
  double? _viewportReadinessInitialScale;
  Offset? _viewportReadinessInitialFocus;
  Rect? _viewportReadinessDragBoundary;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController(
      widget.initialTransform?.clone(),
    )..addListener(_handleTransformChanged);
    _hasUserTransformedMap = widget.initialTransform != null;
    _locationImageFlowController = AnimationController(
      vsync: this,
      duration: tilemapLocationImageFlowDurationForSeconds(
        widget.locationImageFlowDurationSeconds,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLocationImageFlowAnimation();
  }

  @override
  void didUpdateWidget(covariant TilemapRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.config, widget.config)) {
      _resetViewportReadiness();
      _resetProgressiveTileMount();
    } else if (!identical(oldWidget.onViewportReady, widget.onViewportReady) &&
        _isViewportReady) {
      _scheduleViewportReadyCallback();
    }
    final animationsPausedChanged =
        oldWidget.animationsPaused != widget.animationsPaused;
    final locationImageFlowPausedChanged =
        oldWidget.locationImageFlowPaused != widget.locationImageFlowPaused;
    if (oldWidget.isForeground != widget.isForeground ||
        animationsPausedChanged) {
      _restartProgressiveTileMountSchedule();
    }
    if (oldWidget.showLocationImageFlow != widget.showLocationImageFlow ||
        animationsPausedChanged ||
        locationImageFlowPausedChanged) {
      _syncLocationImageFlowAnimation();
    }
    if (oldWidget.locationImageFlowDurationSeconds !=
        widget.locationImageFlowDurationSeconds) {
      _locationImageFlowController
        ..stop()
        ..duration = tilemapLocationImageFlowDurationForSeconds(
          widget.locationImageFlowDurationSeconds,
        );
      _syncLocationImageFlowAnimation();
    }
  }

  void _syncLocationImageFlowAnimation() {
    if (widget.animationsPaused || widget.locationImageFlowPaused) {
      _locationImageFlowController.stop();
      return;
    }
    final shouldAnimate =
        widget.showLocationImageFlow &&
        _hasLocationImageFlowTiles &&
        !MediaQuery.disableAnimationsOf(context);
    if (shouldAnimate) {
      if (!_locationImageFlowController.isAnimating) {
        _locationImageFlowController.repeat(
          period: tilemapLocationImageFlowDurationForSeconds(
            widget.locationImageFlowDurationSeconds,
          ),
        );
      }
      return;
    }
    _locationImageFlowController
      ..stop()
      ..value = 0;
  }

  void _updateLocationImageFlowDemand(bool hasTiles) {
    if (_hasLocationImageFlowTiles == hasTiles) return;
    _hasLocationImageFlowTiles = hasTiles;
    if (_locationImageFlowSyncScheduled) return;
    _locationImageFlowSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _locationImageFlowSyncScheduled = false;
      if (mounted) _syncLocationImageFlowAnimation();
    });
  }

  @override
  void dispose() {
    _progressiveMountGeneration += 1;
    _progressiveMountScheduleGeneration += 1;
    _handleTransformChanged();
    _locationImageFlowController.dispose();
    _transformationController
      ..removeListener(_handleTransformChanged)
      ..dispose();
    super.dispose();
  }

  void _handleTransformChanged() {
    widget.onTransformChanged?.call(_transformationController.value.clone());
  }

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final showLocationImageFlow =
        widget.showLocationImageFlow &&
        !MediaQuery.disableAnimationsOf(context);
    final visualStyle = tilemapVisualStyleFor(widget.visualMode);
    return ColoredBox(
      key: const ValueKey<String>('tilemap-renderer-background'),
      color: visualStyle.backgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final viewportHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height;
          final projection = TilemapProjection.fixed(
            mapWidth: widget.config.width,
            mapHeight: widget.config.height,
          );
          final renderIndex = _ensureRenderIndex(projection);
          final viewportSize = Size(viewportWidth, viewportHeight);
          final mapSize = Size(projection.mapWidth, projection.mapHeight);
          final contentBounds = projection.imageBoundsForTiles(
            tilemapInitialContentTiles(widget.config.tiles),
          );
          final initialFocusTile = tilemapInitialFocusLocationTile(
            tiles: widget.config.tiles,
            locationAvatarsForTile: widget.locationAvatarsForTile,
            preferredLocationId: widget.preferredFocusLocationId,
            centerContentInitially: widget.centerContentInitially,
          );
          final initialFocus = initialFocusTile == null
              ? null
              : projection.centerForTile(initialFocusTile);
          final dragBoundary = tilemapDragBoundaryForShadowTiles(
            projection: projection,
            tiles: widget.config.tiles,
            paddingTiles: widget.dragBoundaryPaddingTiles,
          );
          _syncViewportReadinessEnvironment(
            viewportSize: viewportSize,
            devicePixelRatio: devicePixelRatio,
            initialScale: widget.initialScale,
            initialFocus: initialFocus,
            dragBoundary: dragBoundary,
          );
          _syncInitialTransform(
            viewportSize: viewportSize,
            mapSize: mapSize,
            contentBounds: contentBounds,
            initialFocus: initialFocus,
            initialScale: widget.initialScale,
            dragBoundary: dragBoundary,
          );
          return SizedBox(
            width: viewportWidth,
            height: viewportHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRect(
                    child: GestureDetector(
                      key: const ValueKey<String>('tilemap-gesture-layer'),
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (details) {
                        _hasUserTransformedMap = true;
                        _gestureStartTransform = _transformationController.value
                            .clone();
                        _gestureStartFocalPoint = details.localFocalPoint;
                      },
                      onScaleUpdate: (details) {
                        final gestureTransform = tilemapGestureTransform(
                          startTransform: _gestureStartTransform,
                          startFocalPoint: _gestureStartFocalPoint,
                          currentFocalPoint: details.localFocalPoint,
                          gestureScale: details.scale,
                        );
                        _transformationController.value =
                            tilemapConstrainTransformToBoundary(
                              transform: gestureTransform,
                              viewportSize: viewportSize,
                              sceneBoundary: dragBoundary,
                            );
                      },
                      onTapUp: (details) {
                        widget.onMapTap?.call();
                        unawaited(
                          _handleTap(details.localPosition, projection),
                        );
                      },
                      child: ValueListenableBuilder<Matrix4>(
                        valueListenable: _transformationController,
                        builder: (context, matrix, _) {
                          final scale = tilemapTransformScale(matrix);
                          final tilePixelSize = projection.tilePixelSize(
                            scale: scale,
                            devicePixelRatio: devicePixelRatio,
                          );
                          final visibleSceneBounds = tilemapVisibleSceneBounds(
                            transform: matrix,
                            viewportSize: viewportSize,
                          );
                          final records = _resolveRetainedRecords(
                            renderIndex: renderIndex,
                            visibleSceneBounds: visibleSceneBounds,
                          );
                          _syncProgressiveTileMount(
                            records: records,
                            visibleSceneBounds: visibleSceneBounds,
                            tilePixelSize: tilePixelSize,
                          );
                          _captureInitialViewportTiles(
                            records: records,
                            visibleSceneBounds: visibleSceneBounds,
                          );
                          final tiles = _retainedTiles;
                          final fogBounds = _retainedSceneBounds!.inflate(
                            projection.tileExtent /
                                tilemapFogSamplesPerTileExtent,
                          );
                          final fogField = !renderIndex.hasFogTiles
                              ? null
                              : _resolveFogField(
                                  projection: projection,
                                  fogBounds: fogBounds,
                                );
                          final locationLabels = <_TilemapLocationLabelData>[];
                          final locationImageFlowTileKeys = <String>{};
                          for (final tile in tiles) {
                            if (!tile.isLocationTile) continue;
                            final name =
                                widget.locationNameForTile
                                    ?.call(tile)
                                    ?.trim() ??
                                '';
                            if (name.isEmpty) continue;
                            if (!tile.hasShadow) {
                              locationImageFlowTileKeys.add(tile.cellKey);
                            }
                            locationLabels.add(
                              _TilemapLocationLabelData(
                                tile: tile,
                                name: name,
                                avatars:
                                    widget.locationAvatarsForTile?.call(tile) ??
                                    const <UserAvatar>[],
                                showRecentChat:
                                    widget.showRecentChatForTile?.call(tile) ??
                                    false,
                                showEvent:
                                    widget.showEventForTile?.call(tile) ??
                                    false,
                                showNew:
                                    widget.showNewForTile?.call(tile) ?? false,
                              ),
                            );
                          }
                          _updateLocationImageFlowDemand(
                            showLocationImageFlow &&
                                locationImageFlowTileKeys.isNotEmpty,
                          );
                          return Builder(
                            builder: (context) {
                              final visibleCharacterIds = <String>{
                                for (final label in locationLabels)
                                  for (final avatar in label.avatars)
                                    if (avatar.id.trim().isNotEmpty)
                                      avatar.id.trim(),
                              };
                              return TilemapMessageBubblePlayback(
                                messageBubbles: widget.messageBubbles,
                                visibleCharacterIds: visibleCharacterIds,
                                paused: widget.messageBubblePlaybackPaused,
                                frozen: widget.animationsPaused,
                                builder: (context, activeBubble) {
                                  _TilemapLocationLabelData? activeBubbleLabel;
                                  var activeBubbleAvatarIndex = -1;
                                  if (activeBubble != null) {
                                    for (final label in locationLabels) {
                                      final avatarIndex = label.avatars
                                          .indexWhere(
                                            (avatar) =>
                                                avatar.id.trim() ==
                                                activeBubble.characterId.trim(),
                                          );
                                      if (avatarIndex < 0) continue;
                                      activeBubbleLabel = label;
                                      activeBubbleAvatarIndex = avatarIndex;
                                      break;
                                    }
                                  }
                                  final activeBubbleLocationAnchor =
                                      activeBubbleLabel == null
                                      ? null
                                      : MatrixUtils.transformPoint(
                                          matrix,
                                          tilemapLocationBubbleSceneAnchor(
                                            projection,
                                            activeBubbleLabel.tile,
                                          ),
                                        );
                                  final activeBubbleAvatarTopLeft =
                                      activeBubbleLocationAnchor == null
                                      ? null
                                      : tilemapMessageBubbleAvatarTopLeft(
                                          locationBubbleAnchor:
                                              activeBubbleLocationAnchor,
                                          avatarIndex: activeBubbleAvatarIndex,
                                          avatarCount:
                                              activeBubbleLabel!.avatars.length,
                                        );
                                  return Stack(
                                    fit: StackFit.expand,
                                    clipBehavior: Clip.none,
                                    children: [
                                      Positioned.fill(
                                        child: CustomPaint(
                                          key: const ValueKey<String>(
                                            'tilemap-grid',
                                          ),
                                          painter: _TilemapInfiniteGridPainter(
                                            projection: projection,
                                            scale: scale,
                                            translation: Offset(
                                              matrix.getTranslation().x,
                                              matrix.getTranslation().y,
                                            ),
                                            lineColor:
                                                visualStyle.gridLineColor,
                                          ),
                                        ),
                                      ),
                                      if (renderIndex.hasFogTiles)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            key: const ValueKey<String>(
                                              'tilemap-fog-layer',
                                            ),
                                            child: Transform(
                                              transform: matrix,
                                              alignment: Alignment.topLeft,
                                              child: SizedBox(
                                                width: projection.mapWidth,
                                                height: projection.mapHeight,
                                                child: CustomPaint(
                                                  key: const ValueKey<String>(
                                                    'tilemap-fog-paint',
                                                  ),
                                                  painter: _TilemapFogPainter(
                                                    fogField!,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      Transform(
                                        key: const ValueKey<String>(
                                          'tilemap-tile-transform',
                                        ),
                                        transform: matrix,
                                        alignment: Alignment.topLeft,
                                        child: SizedBox(
                                          width: projection.mapWidth,
                                          height: projection.mapHeight,
                                          child: _TilemapCanvasTileLayer(
                                            key: const ValueKey<String>(
                                              'tilemap-canvas-tile-mount',
                                            ),
                                            mapSize: mapSize,
                                            frameGeneration:
                                                _progressiveMountGeneration,
                                            tiles: [
                                              for (final record in records)
                                                if (_revealedTileKeys.contains(
                                                  record.tile.cellKey,
                                                ))
                                                  _TilemapCanvasTileEntry(
                                                    record: record,
                                                    asset:
                                                        _revealedAssetForRecord(
                                                          record,
                                                        ),
                                                    extent:
                                                        projection.tileExtent,
                                                    locationImageFlowAnimation:
                                                        showLocationImageFlow &&
                                                            locationImageFlowTileKeys
                                                                .contains(
                                                                  record
                                                                      .tile
                                                                      .cellKey,
                                                                )
                                                        ? _locationImageFlowController
                                                        : null,
                                                    locationImageFlowPhase:
                                                        tilemapLocationImageFlowPhase(
                                                          record.tile,
                                                        ),
                                                    locationImageFlowAngleDegrees:
                                                        widget
                                                            .locationImageFlowAngleDegrees,
                                                    locationImageFlowGradientPoints:
                                                        widget
                                                            .locationImageFlowGradientPoints,
                                                    locationImageFlowOpacity: widget
                                                        .locationImageFlowOpacity,
                                                    locationImageFlowBlendMode:
                                                        widget
                                                            .locationImageFlowBlendMode,
                                                    fogField:
                                                        widget.blendFogWithShadowTiles &&
                                                            record
                                                                .tile
                                                                .hasShadow
                                                        ? fogField
                                                        : null,
                                                    rasterizeFogComposite:
                                                        widget
                                                            .cacheFogTileBitmaps &&
                                                        widget.isForeground &&
                                                        _rectsOverlapWithVisibleArea(
                                                          record.imageBounds,
                                                          visibleSceneBounds,
                                                        ),
                                                    onImageError:
                                                        _tileImageErrorCallback(
                                                          record,
                                                        ),
                                                    onImageFrame:
                                                        _tileImageFrameCallback(
                                                          record,
                                                        ),
                                                  ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (widget.showShadowZeroBorders &&
                                          renderIndex.hasShadowZeroTiles)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            key: const ValueKey<String>(
                                              'tilemap-shadow-zero-border-layer',
                                            ),
                                            child: Transform(
                                              transform: matrix,
                                              alignment: Alignment.topLeft,
                                              child: SizedBox(
                                                width: projection.mapWidth,
                                                height: projection.mapHeight,
                                                child: CustomPaint(
                                                  key: const ValueKey<String>(
                                                    'tilemap-shadow-zero-border-paint',
                                                  ),
                                                  painter:
                                                      _TilemapShadowZeroBorderPainter(
                                                        projection: projection,
                                                        tiles: tiles,
                                                        scale: scale,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      for (final label in locationLabels)
                                        _TilemapLocationBubble(
                                          key: ValueKey<String>(
                                            'tile-location-label-'
                                            '${label.tile.x}-${label.tile.y}',
                                          ),
                                          name: label.name,
                                          avatars: label.avatars,
                                          showRecentChat: label.showRecentChat,
                                          showEvent: label.showEvent,
                                          showNew: label.showNew,
                                          newBadgeKey: ValueKey<String>(
                                            'tilemap-location-new-badge-'
                                            '${label.tile.x}-${label.tile.y}',
                                          ),
                                          onLabelTap:
                                              widget.onTileAction == null
                                              ? null
                                              : () => _handleOverlayTileTap(
                                                  label.tile,
                                                ),
                                          onAvatarTap:
                                              widget.onTileAction == null
                                              ? null
                                              : () => _handleOverlayTileTap(
                                                  label.tile,
                                                ),
                                          anchor: MatrixUtils.transformPoint(
                                            matrix,
                                            tilemapLocationBubbleSceneAnchor(
                                              projection,
                                              label.tile,
                                            ),
                                          ),
                                        ),
                                      if (activeBubble != null &&
                                          activeBubbleLabel != null &&
                                          activeBubbleAvatarTopLeft != null)
                                        TilemapCharacterMessageBubble(
                                          text: activeBubble.content,
                                          avatarTopLeft:
                                              activeBubbleAvatarTopLeft,
                                          viewportWidth: viewportSize.width,
                                          preservePageWidth:
                                              activeBubble.preservePageWidth,
                                          onTap: widget.onTileAction == null
                                              ? null
                                              : () => _handleOverlayTileTap(
                                                  activeBubbleLabel!.tile,
                                                ),
                                        ),
                                    ],
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: legacyWorldMapZoomControlRightGap,
                  bottom:
                      widget.zoomControlBottom ??
                      legacyWorldMapZoomControlBottomGap,
                  child: ValueListenableBuilder<Matrix4>(
                    valueListenable: _transformationController,
                    builder: (context, matrix, child) {
                      final scale = tilemapTransformScale(matrix);
                      return LegacyWorldMapZoomControl(
                        value: scale,
                        min: tilemapMinScale,
                        max: tilemapMaxScale,
                        onChanged: (targetScale) => _zoomToScaleByControl(
                          targetScale: targetScale,
                          viewportSize: viewportSize,
                          dragBoundary: dragBoundary,
                        ),
                        canZoomIn: scale < tilemapMaxScale - 0.001,
                        canZoomOut: scale > tilemapMinScale + 0.001,
                        onZoomIn: () => _zoomByControl(
                          zoomIn: true,
                          viewportSize: viewportSize,
                          dragBoundary: dragBoundary,
                        ),
                        onZoomOut: () => _zoomByControl(
                          zoomIn: false,
                          viewportSize: viewportSize,
                          dragBoundary: dragBoundary,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  _TilemapRenderIndex _ensureRenderIndex(TilemapProjection projection) {
    final existing = _renderIndex;
    if (existing != null &&
        identical(_renderIndexConfig, widget.config) &&
        _renderIndexMapWidth == projection.mapWidth &&
        _renderIndexMapHeight == projection.mapHeight &&
        _renderIndexTileExtent == projection.tileExtent &&
        _renderIndexOriginX == projection.originX) {
      return existing;
    }

    final index = _TilemapRenderIndex(
      projection: projection,
      tiles: widget.config.tiles,
    );
    _renderIndexConfig = widget.config;
    _renderIndexMapWidth = projection.mapWidth;
    _renderIndexMapHeight = projection.mapHeight;
    _renderIndexTileExtent = projection.tileExtent;
    _renderIndexOriginX = projection.originX;
    _renderIndex = index;
    _fogGeometry = index.hasFogTiles
        ? prepareTilemapFogGeometry(
            tiles: widget.config.tiles,
            polygonForTile: projection.polygonForTile,
            tileExtent: projection.tileExtent,
            verticalScale: projection.tileDiamondWidthToHeightRatio,
          )
        : null;
    _retainedSceneBounds = null;
    _retainedRecords = const [];
    _retainedTiles = const [];
    _resetProgressiveTileMount();
    _fogBounds = null;
    _fogControlPoints = null;
    _fogRenderTiles = null;
    _fogField = null;
    return index;
  }

  void _resetViewportReadiness() {
    _viewportReadyGeneration += 1;
    _initialViewportTileKeys = null;
    _initialViewportFramedTileKeys.clear();
    _notifiedViewportReadyCallbacks.clear();
    _viewportReadyCallbackScheduled = false;
    _isViewportReady = false;
  }

  void _syncViewportReadinessEnvironment({
    required Size viewportSize,
    required double devicePixelRatio,
    required double initialScale,
    required Offset? initialFocus,
    required Rect? dragBoundary,
  }) {
    final environmentChanged =
        _hasViewportReadinessEnvironment &&
        (_viewportReadinessSize != viewportSize ||
            _viewportReadinessDevicePixelRatio != devicePixelRatio ||
            _viewportReadinessInitialScale != initialScale ||
            _viewportReadinessInitialFocus != initialFocus ||
            _viewportReadinessDragBoundary != dragBoundary);
    _hasViewportReadinessEnvironment = true;
    _viewportReadinessSize = viewportSize;
    _viewportReadinessDevicePixelRatio = devicePixelRatio;
    _viewportReadinessInitialScale = initialScale;
    _viewportReadinessInitialFocus = initialFocus;
    _viewportReadinessDragBoundary = dragBoundary;
    if (environmentChanged) {
      _resetViewportReadiness();
      _resetProgressiveTileMount();
    }
  }

  void _captureInitialViewportTiles({
    required List<_TilemapRenderRecord> records,
    required Rect visibleSceneBounds,
  }) {
    if (_initialViewportTileKeys != null) {
      if (!widget.waitForVisibleTileImageFrames &&
          _hasRevealedInitialViewportTiles) {
        _scheduleViewportReadyCallback();
      }
      return;
    }

    _initialViewportTileKeys = <String>{
      for (final record in records)
        if (_rectsOverlapWithVisibleArea(
          record.imageBounds,
          visibleSceneBounds,
        ))
          record.tile.cellKey,
    };
    if (!widget.waitForVisibleTileImageFrames ||
        _initialViewportTileKeys!.isEmpty) {
      if (_hasRevealedInitialViewportTiles) {
        _scheduleViewportReadyCallback();
      }
    }
  }

  bool _rectsOverlapWithVisibleArea(Rect first, Rect second) {
    final intersection = first.intersect(second);
    return intersection.width > 0 && intersection.height > 0;
  }

  VoidCallback _tileImageFrameCallback(_TilemapRenderRecord record) {
    final generation = _progressiveMountGeneration;
    final tileKey = record.tile.cellKey;
    final asset = _revealedAssetForRecord(record);
    return () => _handleTileImageFrame(
      tileKey,
      asset: asset,
      progressiveMountGeneration: generation,
    );
  }

  ValueChanged<Object> _tileImageErrorCallback(_TilemapRenderRecord record) {
    final generation = _progressiveMountGeneration;
    final asset = _revealedAssetForRecord(record);
    return (error) {
      if (generation != _progressiveMountGeneration) return;
      _markTileAssetReady(asset);
      widget.onImageError?.call(error);
    };
  }

  void _handleTileImageFrame(
    String tileKey, {
    required String asset,
    required int progressiveMountGeneration,
  }) {
    if (progressiveMountGeneration != _progressiveMountGeneration) return;
    _markTileAssetReady(asset);
    if (_isViewportReady || !widget.waitForVisibleTileImageFrames) {
      return;
    }
    final initialTileKeys = _initialViewportTileKeys;
    if (initialTileKeys == null || !initialTileKeys.contains(tileKey)) return;
    if (!_initialViewportFramedTileKeys.add(tileKey)) return;
    if (_initialViewportFramedTileKeys.containsAll(initialTileKeys)) {
      _scheduleViewportReadyCallback();
    }
  }

  void _markTileAssetReady(String asset) {
    if (!_readyTileAssets.add(asset)) return;
    _probingTileAssets.remove(asset);
    _scheduleProgressiveTileMount();
  }

  void _scheduleViewportReadyCallback() {
    if (_viewportReadyCallbackScheduled) return;
    _viewportReadyCallbackScheduled = true;
    final generation = _viewportReadyGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _viewportReadyGeneration) return;
      _viewportReadyCallbackScheduled = false;
      final initialTileKeys = _initialViewportTileKeys;
      if (initialTileKeys == null) return;
      if (!_hasRevealedInitialViewportTiles) return;
      if (!_isViewportReady &&
          widget.waitForVisibleTileImageFrames &&
          initialTileKeys.isNotEmpty &&
          !_initialViewportFramedTileKeys.containsAll(initialTileKeys)) {
        return;
      }
      _isViewportReady = true;
      final callback = widget.onViewportReady;
      if (callback == null ||
          _notifiedViewportReadyCallbacks.any(
            (notifiedCallback) => identical(notifiedCallback, callback),
          )) {
        return;
      }
      _notifiedViewportReadyCallbacks.add(callback);
      callback();
    });
  }

  List<_TilemapRenderRecord> _resolveRetainedRecords({
    required _TilemapRenderIndex renderIndex,
    required Rect visibleSceneBounds,
  }) {
    final retainedBounds = _retainedSceneBounds;
    if (retainedBounds != null &&
        _rectContainsRect(retainedBounds, visibleSceneBounds)) {
      return _retainedRecords;
    }

    final nextBounds = tilemapRetainedSceneBounds(visibleSceneBounds);
    final nextRecords = renderIndex.query(nextBounds);
    _retainedSceneBounds = nextBounds;
    _retainedRecords = nextRecords;
    _retainedTiles = List<TilemapCell>.unmodifiable(
      nextRecords.map((record) => record.tile),
    );
    return nextRecords;
  }

  bool get _hasRevealedInitialViewportTiles {
    final initialTileKeys = _initialViewportTileKeys;
    return initialTileKeys != null &&
        _revealedTileKeys.containsAll(initialTileKeys);
  }

  void _resetProgressiveTileMount() {
    _progressiveMountGeneration += 1;
    _progressiveMountScheduleGeneration += 1;
    _revealedTileKeys.clear();
    _revealedTileAssets.clear();
    _probingTileAssets.clear();
    _readyTileAssets.clear();
    _pendingVisibleRecords = const [];
    _pendingRetainedRecords = const [];
    _progressiveMountTilePixelSize = 0;
    _hasStartedProgressiveMount = false;
    _progressiveMountCallbackScheduled = false;
  }

  void _restartProgressiveTileMountSchedule() {
    _progressiveMountScheduleGeneration += 1;
    _progressiveMountCallbackScheduled = false;
  }

  void _syncProgressiveTileMount({
    required List<_TilemapRenderRecord> records,
    required Rect visibleSceneBounds,
    required double tilePixelSize,
  }) {
    _progressiveMountTilePixelSize = tilePixelSize;
    final retainedTileKeys = <String>{
      for (final record in records) record.tile.cellKey,
    };
    final removedTileAssets = <String>{
      for (final entry in _revealedTileAssets.entries)
        if (!retainedTileKeys.contains(entry.key)) entry.value,
    };
    _revealedTileKeys.removeWhere(
      (tileKey) => !retainedTileKeys.contains(tileKey),
    );
    _revealedTileAssets.removeWhere(
      (tileKey, _) => !retainedTileKeys.contains(tileKey),
    );
    for (final asset in _probingTileAssets.toList(growable: false)) {
      if (removedTileAssets.contains(asset) &&
          !_revealedTileAssets.containsValue(asset)) {
        _probingTileAssets.remove(asset);
      }
    }

    final visibleRecords = <_TilemapRenderRecord>[];
    final retainedRecords = <_TilemapRenderRecord>[];
    for (final record in records) {
      final tileKey = record.tile.cellKey;
      final desiredAsset = resolveTilemapAssetForDisplaySize(
        widget.config.baseAssetUrlForTile(record.tile),
        tilePixelSize,
      );
      if (_revealedTileKeys.contains(tileKey) &&
          _revealedTileAssets[tileKey] == desiredAsset) {
        continue;
      }
      if (_rectsOverlapWithVisibleArea(
        record.imageBounds,
        visibleSceneBounds,
      )) {
        visibleRecords.add(record);
      } else {
        retainedRecords.add(record);
      }
    }
    final viewportCenter = visibleSceneBounds.center;
    visibleRecords.sort(
      (first, second) => _compareProgressiveMountPriority(
        first,
        second,
        viewportCenter: viewportCenter,
      ),
    );
    retainedRecords.sort(
      (first, second) => _compareProgressiveMountPriority(
        first,
        second,
        viewportCenter: viewportCenter,
      ),
    );
    _pendingVisibleRecords = visibleRecords;
    _pendingRetainedRecords = retainedRecords;

    if (!_hasStartedProgressiveMount && !widget.animationsPaused) {
      _hasStartedProgressiveMount = true;
      final visibleBatchSize = _visibleTileMountBatchSize;
      final initialVisibleRecords = _selectProgressiveMountBatch(
        visibleRecords,
        maxCellCount: visibleBatchSize,
      );
      _revealProgressiveRecords(initialVisibleRecords);
      final remainingInitialCapacity =
          visibleBatchSize - initialVisibleRecords.length;
      if (initialVisibleRecords.length == visibleRecords.length &&
          remainingInitialCapacity > 0) {
        final initialRetainedRecords = _selectProgressiveMountBatch(
          retainedRecords,
          maxCellCount: math.min(
            _retainedTileMountBatchSize,
            remainingInitialCapacity,
          ),
        );
        _revealProgressiveRecords(initialRetainedRecords);
      }
      _pendingVisibleRecords = visibleRecords
          .where((record) => !_revealedTileKeys.contains(record.tile.cellKey))
          .toList(growable: false);
      _pendingRetainedRecords = retainedRecords
          .where((record) => !_revealedTileKeys.contains(record.tile.cellKey))
          .toList(growable: false);
    }
    _scheduleProgressiveTileMount();
  }

  int _compareProgressiveMountPriority(
    _TilemapRenderRecord first,
    _TilemapRenderRecord second, {
    required Offset viewportCenter,
  }) {
    final preferredLocationId = widget.preferredFocusLocationId.trim();
    final firstIsPreferred =
        preferredLocationId.isNotEmpty &&
        first.tile.locationId?.trim() == preferredLocationId;
    final secondIsPreferred =
        preferredLocationId.isNotEmpty &&
        second.tile.locationId?.trim() == preferredLocationId;
    if (firstIsPreferred != secondIsPreferred) {
      return firstIsPreferred ? -1 : 1;
    }
    if (first.tile.isLocationTile != second.tile.isLocationTile) {
      return first.tile.isLocationTile ? -1 : 1;
    }
    final firstDelta = first.imageBounds.center - viewportCenter;
    final secondDelta = second.imageBounds.center - viewportCenter;
    final distanceOrder = firstDelta.distanceSquared.compareTo(
      secondDelta.distanceSquared,
    );
    if (distanceOrder != 0) return distanceOrder;
    return first.paintOrder.compareTo(second.paintOrder);
  }

  void _scheduleProgressiveTileMount() {
    if (widget.animationsPaused ||
        _progressiveMountCallbackScheduled ||
        (_pendingVisibleRecords.isEmpty && _pendingRetainedRecords.isEmpty)) {
      return;
    }
    _progressiveMountCallbackScheduled = true;
    final generation = _progressiveMountScheduleGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _progressiveMountScheduleGeneration) {
        return;
      }
      _progressiveMountCallbackScheduled = false;
      if (widget.animationsPaused) return;

      final hasVisibleRecords = _pendingVisibleRecords.isNotEmpty;
      final pendingRecords = hasVisibleRecords
          ? _pendingVisibleRecords
          : _pendingRetainedRecords;
      final batchSize = hasVisibleRecords
          ? _visibleTileMountBatchSize
          : _retainedTileMountBatchSize;
      final nextRecords = _selectProgressiveMountBatch(
        pendingRecords,
        maxCellCount: batchSize,
      );
      if (nextRecords.isEmpty) return;
      setState(() {
        _revealProgressiveRecords(nextRecords);
      });
      if (_hasRevealedInitialViewportTiles &&
          !widget.waitForVisibleTileImageFrames) {
        _scheduleViewportReadyCallback();
      }
    });
  }

  void _revealProgressiveRecords(Iterable<_TilemapRenderRecord> records) {
    for (final record in records) {
      _revealedTileKeys.add(record.tile.cellKey);
    }
  }

  int get _visibleTileMountBatchSize => widget.isForeground
      ? _foregroundVisibleTileMountBatchSize
      : _backgroundVisibleTileMountBatchSize;

  List<_TilemapRenderRecord> _selectProgressiveMountBatch(
    List<_TilemapRenderRecord> pendingRecords, {
    required int maxCellCount,
  }) {
    final selectedRecords = <_TilemapRenderRecord>[];
    for (final record in pendingRecords) {
      final tileKey = record.tile.cellKey;
      final asset = resolveTilemapAssetForDisplaySize(
        widget.config.baseAssetUrlForTile(record.tile),
        _progressiveMountTilePixelSize,
      );
      final previousAsset = _revealedTileAssets[tileKey];
      final replacesSoleProbe =
          previousAsset != null &&
          previousAsset != asset &&
          _probingTileAssets.contains(previousAsset) &&
          !_revealedTileAssets.entries.any(
            (entry) => entry.key != tileKey && entry.value == previousAsset,
          );
      if (!_readyTileAssets.contains(asset)) {
        if (_probingTileAssets.contains(asset)) {
          continue;
        }
        final effectiveProbeCount =
            _probingTileAssets.length - (replacesSoleProbe ? 1 : 0);
        if (effectiveProbeCount >= _newTileAssetMountBatchSize) continue;
        if (replacesSoleProbe) _probingTileAssets.remove(previousAsset);
        _probingTileAssets.add(asset);
      } else if (replacesSoleProbe) {
        _probingTileAssets.remove(previousAsset);
      }
      selectedRecords.add(record);
      _revealedTileAssets[tileKey] = asset;
      if (selectedRecords.length >= maxCellCount) break;
    }
    return selectedRecords;
  }

  String _revealedAssetForRecord(_TilemapRenderRecord record) {
    return _revealedTileAssets[record.tile.cellKey] ??
        resolveTilemapAssetForDisplaySize(
          widget.config.baseAssetUrlForTile(record.tile),
          _progressiveMountTilePixelSize,
        );
  }

  TilemapFogField _resolveFogField({
    required TilemapProjection projection,
    required Rect fogBounds,
  }) {
    final controlPointsMatch = listEquals(
      _fogControlPoints,
      widget.fogControlPoints,
    );
    if (_fogBounds == fogBounds &&
        controlPointsMatch &&
        identical(_fogRenderTiles, _retainedTiles) &&
        _fogField != null) {
      return _fogField!;
    }
    final field = buildTilemapFogField(
      fieldBounds: fogBounds,
      tiles: widget.config.tiles,
      polygonForTile: projection.polygonForTile,
      imageBoundsForTile: (tile) =>
          projection.imageTopLeftForTile(tile) &
          Size.square(projection.tileExtent),
      tileExtent: projection.tileExtent,
      tileDiamondWidth: projection.tileDiamondWidth,
      tileDiamondHeight: projection.tileDiamondHeight,
      verticalScale: projection.tileDiamondWidthToHeightRatio,
      controlPoints: widget.fogControlPoints,
      geometry: _fogGeometry,
      renderTiles: _retainedTiles,
      reusableShadowTileVertices: controlPointsMatch
          ? _fogField?.shadowTileVertices
          : null,
    );
    _fogBounds = fogBounds;
    _fogControlPoints = List<TilemapFogControlPoint>.unmodifiable(
      widget.fogControlPoints,
    );
    _fogRenderTiles = _retainedTiles;
    _fogField = field;
    return field;
  }

  Future<void> _handleTap(
    Offset localPosition,
    TilemapProjection projection,
  ) async {
    if (_isRunningTileAction) return;
    final scenePosition = MatrixUtils.transformPoint(
      Matrix4.inverted(_transformationController.value),
      localPosition,
    );
    final renderIndex = _ensureRenderIndex(projection);
    final candidates = renderIndex.queryPoint(scenePosition);
    for (final record in candidates.reversed) {
      final tile = record.tile;
      if (!tile.isLocationTile) continue;
      if (!projection.containsPointInTile(tile, scenePosition)) continue;
      await _runTileAction(tile);
      return;
    }
  }

  Future<void> _runTileAction(TilemapCell tile) async {
    final onTileAction = widget.onTileAction;
    if (onTileAction == null) return;
    _isRunningTileAction = true;
    try {
      await onTileAction(tile);
    } finally {
      _isRunningTileAction = false;
    }
  }

  void _handleOverlayTileTap(TilemapCell tile) {
    if (_isRunningTileAction) return;
    widget.onMapTap?.call();
    unawaited(_runTileAction(tile));
  }

  void _syncInitialTransform({
    required Size viewportSize,
    required Size mapSize,
    required Rect contentBounds,
    required Offset? initialFocus,
    required double initialScale,
    required Rect? dragBoundary,
  }) {
    final dragBoundaryChanged = _lastDragBoundary != dragBoundary;
    if (_lastViewportSize == viewportSize &&
        _lastMapSize == mapSize &&
        _lastContentBounds == contentBounds &&
        _lastInitialFocus == initialFocus &&
        _lastInitialScale == initialScale &&
        !dragBoundaryChanged) {
      return;
    }
    _lastViewportSize = viewportSize;
    _lastMapSize = mapSize;
    _lastContentBounds = contentBounds;
    _lastInitialFocus = initialFocus;
    _lastInitialScale = initialScale;
    _lastDragBoundary = dragBoundary;
    if (_hasUserTransformedMap) {
      if (dragBoundaryChanged) {
        _transformationController.value = tilemapConstrainTransformToBoundary(
          transform: _transformationController.value,
          viewportSize: viewportSize,
          sceneBoundary: dragBoundary,
        );
      }
      return;
    }
    final initialTransform = tilemapInitialTransform(
      viewportSize: viewportSize,
      mapSize: mapSize,
      contentBounds: contentBounds,
      focus: initialFocus,
      initialScale: initialScale,
    );
    _transformationController.value = tilemapConstrainTransformToBoundary(
      transform: initialTransform,
      viewportSize: viewportSize,
      sceneBoundary: dragBoundary,
    );
  }

  void _zoomByControl({
    required bool zoomIn,
    required Size viewportSize,
    required Rect? dragBoundary,
  }) {
    _hasUserTransformedMap = true;
    final currentTransform = _transformationController.value;
    final currentScale = tilemapTransformScale(currentTransform);
    final targetScale =
        (zoomIn
                ? currentScale * tilemapZoomControlScaleFactor
                : currentScale / tilemapZoomControlScaleFactor)
            .clamp(tilemapMinScale, tilemapMaxScale)
            .toDouble();
    _zoomToScaleByControl(
      targetScale: targetScale,
      viewportSize: viewportSize,
      dragBoundary: dragBoundary,
    );
  }

  void _zoomToScaleByControl({
    required double targetScale,
    required Size viewportSize,
    required Rect? dragBoundary,
  }) {
    _hasUserTransformedMap = true;
    final currentTransform = _transformationController.value;
    final currentScale = tilemapTransformScale(currentTransform);
    final clampedTargetScale = targetScale
        .clamp(tilemapMinScale, tilemapMaxScale)
        .toDouble();
    if ((clampedTargetScale - currentScale).abs() < 0.001) return;
    final viewportCenter = viewportSize.center(Offset.zero);
    final sceneCenter = MatrixUtils.transformPoint(
      Matrix4.inverted(currentTransform),
      viewportCenter,
    );
    final nextTransform = tilemapTransformForSceneFocalPoint(
      sceneFocalPoint: sceneCenter,
      viewportFocalPoint: viewportCenter,
      scale: clampedTargetScale,
    );
    _transformationController.value = tilemapConstrainTransformToBoundary(
      transform: nextTransform,
      viewportSize: viewportSize,
      sceneBoundary: dragBoundary,
    );
  }
}
