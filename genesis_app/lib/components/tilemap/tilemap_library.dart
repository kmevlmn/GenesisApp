import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/telemetry/firebase_performance_monitoring.dart';
import '../../network/genesis_api.dart';
import '../../network/models/tilemap_definition.dart';
import '../../ui/components/genesis_static_network_image.dart';
import '../../ui/components/genesis_dark_close_button.dart';
import '../../ui/tokens/genesis_typography.dart';
import '../world_map_avatar_logic.dart';
import '../world_map_contract.dart';
import '../world_map_exit_location_button.dart';
import '../world_map_location_action.dart';
import '../world_point.dart';
import 'loading/tilemap_loading.dart';
import 'tilemap_model.dart';
import 'tilemap_renderer.dart';
import 'tilemap_settings_button_visibility.dart';
import 'tilemap_settings_store.dart';

part 'tilemap_settings_panel.dart';
part 'tilemap_fog_editor.dart';
part 'tilemap_image_flow_editor.dart';
part 'tilemap_controls_feedback.dart';

enum _TilemapSource { origin, world }

typedef TilemapTileImageLoader = Future<void> Function(String assetUrl);
typedef TilemapCurrentLocationsChanged =
    void Function(String mapId, Set<String> locationIds);

class TilemapRestorationController extends ChangeNotifier {
  String _scopeKey = '';
  String _initialLocationId = '';
  String _currentLocationId = '';
  final List<String> _locationTrail = <String>[];
  final Map<String, Matrix4> _viewportTransforms = <String, Matrix4>{};
  String _requestedLocationId = '';
  int _locationNavigationRevision = 0;
  int _mapPrefetchGeneration = 0;
  final Map<String, _TilemapMapPrefetch> _mapPrefetches =
      <String, _TilemapMapPrefetch>{};
  _TilemapWorldMapPrefetchRequest? _pendingWorldMapPrefetch;
  Future<void>? _worldMapPrefetchDrain;

  void requestLocationNavigation(String locationId) {
    final resolvedLocationId = locationId.trim();
    if (resolvedLocationId.isEmpty) return;
    _requestedLocationId = resolvedLocationId;
    _locationNavigationRevision += 1;
    notifyListeners();
  }

  void clear() {
    _scopeKey = '';
    _initialLocationId = '';
    _currentLocationId = '';
    _locationTrail.clear();
    _viewportTransforms.clear();
    _requestedLocationId = '';
    _locationNavigationRevision += 1;
    _clearMapPrefetches();
    notifyListeners();
  }

  @override
  void dispose() {
    _clearMapPrefetches();
    super.dispose();
  }

  Future<void> prefetchWorldMapUpdate({
    required GenesisApi api,
    required String worldId,
    required String initialLocationId,
    Iterable<String> drillableLocationIds = const <String>[],
    bool preloadRelatedMaps = tilemapRelatedMapPreloadingEnabled,
  }) {
    final resolvedWorldId = worldId.trim();
    final resolvedInitialLocationId = initialLocationId.trim();
    if (resolvedWorldId.isEmpty || resolvedInitialLocationId.isEmpty) {
      return Future<void>.value();
    }

    final scopeKey = '${_TilemapSource.world.name}:$resolvedWorldId';
    _ensureScope(
      scopeKey: scopeKey,
      initialLocationId: resolvedInitialLocationId,
    );
    final generation = ++_mapPrefetchGeneration;
    _pendingWorldMapPrefetch = _TilemapWorldMapPrefetchRequest(
      api: api,
      worldId: resolvedWorldId,
      initialLocationId: resolvedInitialLocationId,
      preloadRelatedMaps: preloadRelatedMaps,
      drillableLocationIds: preloadRelatedMaps
          ? drillableLocationIds
                .map((locationId) => locationId.trim())
                .where((locationId) => locationId.isNotEmpty)
                .toSet()
          : const <String>{},
      scopeKey: scopeKey,
      generation: generation,
    );
    return _startWorldMapPrefetchDrain();
  }

  Future<void> _startWorldMapPrefetchDrain() {
    final activeDrain = _worldMapPrefetchDrain;
    if (activeDrain != null) return activeDrain;
    final drain = _drainWorldMapPrefetches();
    _worldMapPrefetchDrain = drain;
    unawaited(
      drain.whenComplete(() {
        if (!identical(_worldMapPrefetchDrain, drain)) return;
        _worldMapPrefetchDrain = null;
        if (_pendingWorldMapPrefetch != null) {
          unawaited(_startWorldMapPrefetchDrain());
        }
      }),
    );
    return drain;
  }

  Future<void> _drainWorldMapPrefetches() async {
    while (true) {
      final request = _pendingWorldMapPrefetch;
      if (request == null) return;
      _pendingWorldMapPrefetch = null;
      try {
        await _runWorldMapPrefetch(request);
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            '[Tilemap] location chat map_updated prefetch drain failed: '
            '$error',
          );
        }
      }
    }
  }

  Future<void> _runWorldMapPrefetch(
    _TilemapWorldMapPrefetchRequest prefetchRequest,
  ) async {
    final locationId = _currentLocationId.trim().isNotEmpty
        ? _currentLocationId.trim()
        : prefetchRequest.initialLocationId;
    final generation = prefetchRequest.generation;
    _mapPrefetches.clear();
    final request = _loadMapUpdate(
      api: prefetchRequest.api,
      source: _TilemapSource.world,
      entityId: prefetchRequest.worldId,
      locationId: locationId,
      reason: 'location chat map_updated',
    );
    final entry = _TilemapMapPrefetch(generation: generation, request: request);
    _mapPrefetches[locationId] = entry;
    final definition = await request;
    if (_scopeKey != prefetchRequest.scopeKey ||
        generation != _mapPrefetchGeneration) {
      return;
    }
    if (!prefetchRequest.preloadRelatedMaps) return;

    final drillableIds = prefetchRequest.drillableLocationIds;
    final relatedLocationIds = <String>[];
    void addRelatedLocation(String rawLocationId) {
      final relatedLocationId = rawLocationId.trim();
      if (relatedLocationId.isEmpty ||
          relatedLocationId == locationId ||
          relatedLocationIds.contains(relatedLocationId)) {
        return;
      }
      relatedLocationIds.add(relatedLocationId);
    }

    if (_locationTrail.isNotEmpty) addRelatedLocation(_locationTrail.last);
    if (definition != null && drillableIds.isNotEmpty) {
      var drillTargetCount = 0;
      for (final tile in definition.tiles) {
        final targetLocationId = tile.locationId?.trim() ?? '';
        if (!drillableIds.contains(targetLocationId)) continue;
        final previousCount = relatedLocationIds.length;
        addRelatedLocation(targetLocationId);
        if (relatedLocationIds.length > previousCount) drillTargetCount += 1;
        if (drillTargetCount >= tilemapSilentPreloadMaxPendingTargets) break;
      }
    }
    for (final relatedLocationId in relatedLocationIds) {
      if (_scopeKey != prefetchRequest.scopeKey ||
          generation != _mapPrefetchGeneration) {
        return;
      }
      final relatedRequest = _loadMapUpdate(
        api: prefetchRequest.api,
        source: _TilemapSource.world,
        entityId: prefetchRequest.worldId,
        locationId: relatedLocationId,
        reason: 'location chat related map',
      );
      _mapPrefetches[relatedLocationId] = _TilemapMapPrefetch(
        generation: generation,
        request: relatedRequest,
      );
      await relatedRequest;
    }
  }

  Future<TilemapDefinition?> _loadMapUpdate({
    required GenesisApi api,
    required _TilemapSource source,
    required String entityId,
    required String locationId,
    required String reason,
  }) async {
    try {
      return switch (source) {
        _TilemapSource.origin => await api.getOriginMap(
          originId: entityId,
          locationId: locationId,
        ),
        _TilemapSource.world => await api.getWorldMap(
          worldId: entityId,
          locationId: locationId,
        ),
      };
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[Tilemap] $reason prefetch failed '
          '${source.name}=$entityId location=$locationId: $error',
        );
      }
      return null;
    }
  }

  Future<TilemapDefinition?>? _takePrefetchedMap({
    required String scopeKey,
    required String initialLocationId,
    required String locationId,
  }) {
    _ensureScope(scopeKey: scopeKey, initialLocationId: initialLocationId);
    final entry = _mapPrefetches.remove(locationId);
    if (entry == null || entry.generation != _mapPrefetchGeneration) {
      return null;
    }
    return entry.request;
  }

  void _clearMapPrefetches() {
    _mapPrefetchGeneration += 1;
    _pendingWorldMapPrefetch = null;
    _mapPrefetches.clear();
  }

  void _ensureScope({
    required String scopeKey,
    required String initialLocationId,
  }) {
    if (_scopeKey == scopeKey && _initialLocationId == initialLocationId) {
      return;
    }
    _scopeKey = scopeKey;
    _initialLocationId = initialLocationId;
    _currentLocationId = initialLocationId;
    _locationTrail.clear();
    _viewportTransforms.clear();
    _clearMapPrefetches();
  }

  void _saveNavigation({
    required String scopeKey,
    required String initialLocationId,
    required String currentLocationId,
    required List<String> locationTrail,
  }) {
    _ensureScope(scopeKey: scopeKey, initialLocationId: initialLocationId);
    _currentLocationId = currentLocationId;
    _locationTrail
      ..clear()
      ..addAll(locationTrail);
  }

  Matrix4? _viewportTransform({
    required String scopeKey,
    required String initialLocationId,
    required String mapId,
  }) {
    _ensureScope(scopeKey: scopeKey, initialLocationId: initialLocationId);
    return _viewportTransforms[mapId]?.clone();
  }

  void _saveViewportTransform({
    required String scopeKey,
    required String initialLocationId,
    required String mapId,
    required Matrix4 transform,
  }) {
    _ensureScope(scopeKey: scopeKey, initialLocationId: initialLocationId);
    _viewportTransforms[mapId] = transform.clone();
  }

  void _clearViewportTransform({
    required String scopeKey,
    required String initialLocationId,
    required String mapId,
  }) {
    _ensureScope(scopeKey: scopeKey, initialLocationId: initialLocationId);
    _viewportTransforms.remove(mapId);
  }

  void _consumeLocationNavigationRequest({
    required int revision,
    required String locationId,
  }) {
    if (_locationNavigationRevision != revision ||
        _requestedLocationId != locationId) {
      return;
    }
    _requestedLocationId = '';
  }
}

class _TilemapMapPrefetch {
  const _TilemapMapPrefetch({required this.generation, required this.request});

  final int generation;
  final Future<TilemapDefinition?> request;
}

class _TilemapWorldMapPrefetchRequest {
  const _TilemapWorldMapPrefetchRequest({
    required this.api,
    required this.worldId,
    required this.initialLocationId,
    required this.preloadRelatedMaps,
    required this.drillableLocationIds,
    required this.scopeKey,
    required this.generation,
  });

  final GenesisApi api;
  final String worldId;
  final String initialLocationId;
  final bool preloadRelatedMaps;
  final Set<String> drillableLocationIds;
  final String scopeKey;
  final int generation;
}

String resolveTilemapPreferredVisibleLocationId({
  required String preferredLocationId,
  required Iterable<String> visibleLocationIds,
  required List<WorldMapLocationNode> locationNodes,
}) {
  final preferredId = preferredLocationId.trim();
  if (preferredId.isEmpty) return '';
  final visibleIds = visibleLocationIds
      .map((locationId) => locationId.trim())
      .where((locationId) => locationId.isNotEmpty)
      .toSet();
  if (visibleIds.contains(preferredId)) return preferredId;

  String? resolvedId;
  bool visit(WorldMapLocationNode node) {
    var containsPreferred = node.id.trim() == preferredId;
    for (final child in node.children) {
      containsPreferred = visit(child) || containsPreferred;
    }
    final nodeId = node.id.trim();
    if (containsPreferred &&
        resolvedId == null &&
        visibleIds.contains(nodeId)) {
      resolvedId = nodeId;
    }
    return containsPreferred;
  }

  for (final node in locationNodes) {
    if (visit(node)) break;
  }
  return resolvedId ?? '';
}

class Tilemap extends StatefulWidget {
  const Tilemap.origin({
    super.key,
    required String originId,
    this.locationId = 'root',
    this.locationNodes = const <WorldMapLocationNode>[],
    this.preferredFocusLocationId = '',
    this.centerContentInitially = false,
    this.drillExitBottom = worldMapDrillExitBottom,
    this.zoomControlBottom,
    this.drillExitMaxWidth,
    this.showVisualModeToggle = true,
    this.visualModeToggleTop,
    this.visualModeToggleRight = 9.5,
    this.recentChatLocationIds = const <String>{},
    this.eventLocationIds = const <String>{},
    this.animationsPaused = false,
    this.locationImageFlowPaused = false,
    this.relatedMapPreloadingEnabled = tilemapRelatedMapPreloadingEnabled,
    this.reloadRevision = 0,
    this.messageBubbles = const <WorldMapMessageBubble>[],
    this.messageBubblePlaybackPaused = false,
    this.onDrillIntoLocation,
    this.onMapTap,
    this.onPointTap,
    this.tileImageLoader,
    this.restorationController,
    this.onDisplayReadinessChanged,
    this.onDisplayError,
    this.onCurrentLocationsChanged,
  }) : _source = _TilemapSource.origin,
       _entityId = originId;

  const Tilemap.world({
    super.key,
    required String worldId,
    this.locationId = 'root',
    this.locationNodes = const <WorldMapLocationNode>[],
    this.preferredFocusLocationId = '',
    this.centerContentInitially = false,
    this.drillExitBottom = worldMapDrillExitBottom,
    this.zoomControlBottom,
    this.drillExitMaxWidth,
    this.showVisualModeToggle = true,
    this.visualModeToggleTop,
    this.visualModeToggleRight = 9.5,
    this.recentChatLocationIds = const <String>{},
    this.eventLocationIds = const <String>{},
    this.animationsPaused = false,
    this.locationImageFlowPaused = false,
    this.relatedMapPreloadingEnabled = tilemapRelatedMapPreloadingEnabled,
    this.reloadRevision = 0,
    this.messageBubbles = const <WorldMapMessageBubble>[],
    this.messageBubblePlaybackPaused = false,
    this.onDrillIntoLocation,
    this.onMapTap,
    this.onPointTap,
    this.tileImageLoader,
    this.restorationController,
    this.onDisplayReadinessChanged,
    this.onDisplayError,
    this.onCurrentLocationsChanged,
  }) : _source = _TilemapSource.world,
       _entityId = worldId;

  final _TilemapSource _source;
  final String _entityId;
  final String locationId;
  final List<WorldMapLocationNode> locationNodes;
  final String preferredFocusLocationId;
  final bool centerContentInitially;
  final double drillExitBottom;
  final double? zoomControlBottom;
  final double? drillExitMaxWidth;
  final bool showVisualModeToggle;
  final double? visualModeToggleTop;
  final double visualModeToggleRight;
  final Set<String> recentChatLocationIds;
  final Set<String> eventLocationIds;
  final bool animationsPaused;
  final bool locationImageFlowPaused;
  final bool relatedMapPreloadingEnabled;
  final int reloadRevision;
  final List<WorldMapMessageBubble> messageBubbles;
  final bool messageBubblePlaybackPaused;
  final VoidCallback? onDrillIntoLocation;
  final VoidCallback? onMapTap;
  final FutureOr<void> Function(WorldPoint point)? onPointTap;
  final TilemapTileImageLoader? tileImageLoader;
  final TilemapRestorationController? restorationController;
  final ValueChanged<bool>? onDisplayReadinessChanged;
  final ValueChanged<Object>? onDisplayError;
  final TilemapCurrentLocationsChanged? onCurrentLocationsChanged;

  @override
  State<Tilemap> createState() => _TilemapState();
}

class _TilemapState extends State<Tilemap> with WidgetsBindingObserver {
  static const Duration _settingsSaveDelay = Duration(milliseconds: 250);
  static const String _loadPerformanceTraceName = 'tilemap_load';
  static const String _firstRenderPerformanceTraceName = 'tilemap_first_render';
  static const int _maxCachedMapResults = 8;

  GenesisApi? _api;
  final TilemapSettingsStore _settingsStore = const TilemapSettingsStore();
  final Map<String, Future<_TilemapLoadResult>> _mapRequests =
      <String, Future<_TilemapLoadResult>>{};
  final LinkedHashMap<String, _TilemapLoadResult> _mapResults =
      LinkedHashMap<String, _TilemapLoadResult>();
  TilemapConfig? _currentConfig;
  Object? _mapError;
  Object? _imageError;
  late String _currentLocationId;
  final List<String> _locationTrail = <String>[];
  int _appliedLocationNavigationRevision = 0;
  String _requestedPreferredFocusLocationId = '';
  int _cacheGeneration = 0;
  int _mapDataGeneration = 0;
  bool _mapDataRefreshRunning = false;
  bool _mapDataRefreshPending = false;
  bool _mapDataRefreshDeferredUntilResume = false;
  final Map<String, int> _rendererRevisionByMapId = <String, int>{};
  final Map<TilemapConfig, double> _initialScaleByConfig =
      Map<TilemapConfig, double>.identity();
  late final TilemapLoadingCoordinator _loadingCoordinator;
  late final TilemapPrerenderController _prerenderController;
  final Map<String, VoidCallback> _liveViewportReadyCallbacks =
      <String, VoidCallback>{};
  final Map<String, AppPerformanceTrace> _firstRenderTraces =
      <String, AppPerformanceTrace>{};
  bool _hasRequestedFirstRenderTrace = false;
  int _prerenderEnvironmentGeneration = 0;
  bool _hasRevealedInitialMap = false;
  String? _configuredPrerenderEnvironmentKey;
  Size? _configuredPrerenderViewportSize;
  double? _configuredPrerenderDevicePixelRatio;
  bool? _reportedDisplayReady;
  String _reportedCurrentLocationsSignature = '';
  String _scheduledCurrentLocationsSignature = '';
  TilemapVisualMode _visualMode = tilemapVisualModeController.value;
  TilemapLoadingStyle _loadingStyle = tilemapDefaultLoadingStyle;
  List<TilemapFogControlPoint> _fogControlPoints =
      tilemapDefaultFogControlPoints;
  bool _blendFogWithShadowTiles = tilemapDefaultBlendFogWithShadowTiles;
  bool _cacheFogTileBitmaps = tilemapDefaultCacheFogTileBitmaps;
  bool _showShadowZeroBorders = tilemapDefaultShowShadowZeroBorders;
  bool _showLocationImageFlow = tilemapDefaultShowLocationImageFlow;
  double _locationImageFlowAngleDegrees =
      tilemapDefaultLocationImageFlowAngleDegrees;
  List<TilemapLocationImageFlowGradientPoint> _locationImageFlowGradientPoints =
      tilemapDefaultLocationImageFlowGradientPoints;
  double _locationImageFlowOpacity = tilemapDefaultLocationImageFlowOpacity;
  double _locationImageFlowDurationSeconds =
      tilemapDefaultLocationImageFlowDurationSeconds;
  TilemapLocationImageFlowBlendMode _locationImageFlowBlendMode =
      tilemapDefaultLocationImageFlowBlendMode;
  double _nearbyLocationDistanceTiles =
      tilemapDefaultNearbyLocationDistanceTiles;
  double _distantLocationDistanceTiles =
      tilemapDefaultDistantLocationDistanceTiles;
  double _nearbyLocationInitialScale = tilemapDefaultNearbyLocationInitialScale;
  double _distantLocationInitialScale =
      tilemapDefaultDistantLocationInitialScale;
  double _dragBoundaryPaddingTiles = tilemapDefaultDragBoundaryPaddingTiles;
  bool _showSettings = false;
  bool _settingsReady = false;
  Timer? _settingsSaveTimer;
  Future<void> _settingsPersistence = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialLocationId = widget.locationId.trim();
    final restorationController = widget.restorationController;
    restorationController?._ensureScope(
      scopeKey: _restorationScopeKey,
      initialLocationId: initialLocationId,
    );
    _currentLocationId =
        restorationController?._currentLocationId ?? initialLocationId;
    _locationTrail.addAll(
      restorationController?._locationTrail ?? const <String>[],
    );
    _loadingCoordinator = TilemapLoadingCoordinator(
      onChanged: _handleLoadingCoordinatorChanged,
      onSilentMapReady: _handleSilentMapReady,
      backgroundWorkSuspended: widget.animationsPaused,
    );
    _prerenderController = TilemapPrerenderController(
      onChanged: _handlePrerenderControllerChanged,
      warmupSuspended: widget.animationsPaused,
    );
    restorationController?.addListener(
      _handleRestorationControllerNavigationRequested,
    );
    _applyRequestedLocationNavigation(reload: false);
    tilemapSettingsButtonVisibility.listenable.addListener(
      _handleSettingsButtonVisibilityChanged,
    );
    unawaited(tilemapSettingsButtonVisibility.load());
    unawaited(_loadCachedSettings());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = AppServicesScope.read(context).api;
    if (identical(_api, api)) return;
    _api = api;
    _resetMapCache();
    _loadCurrentLocation(rebuild: false);
  }

  @override
  void didUpdateWidget(covariant Tilemap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.restorationController != widget.restorationController) {
      oldWidget.restorationController?.removeListener(
        _handleRestorationControllerNavigationRequested,
      );
      widget.restorationController?.addListener(
        _handleRestorationControllerNavigationRequested,
      );
      _appliedLocationNavigationRevision = 0;
    }
    if (oldWidget.onCurrentLocationsChanged !=
        widget.onCurrentLocationsChanged) {
      _reportedCurrentLocationsSignature = '';
      _scheduledCurrentLocationsSignature = '';
    }
    if (oldWidget.onDisplayReadinessChanged !=
        widget.onDisplayReadinessChanged) {
      _reportedDisplayReady = null;
      _reportDisplayReadiness(_isCurrentDisplayReady);
    }
    if (oldWidget.animationsPaused != widget.animationsPaused) {
      _loadingCoordinator.setBackgroundWorkSuspended(widget.animationsPaused);
      _prerenderController.setWarmupSuspended(widget.animationsPaused);
    }
    final reloadRevisionChanged =
        oldWidget.reloadRevision != widget.reloadRevision;
    if (widget._source == _TilemapSource.world && reloadRevisionChanged) {
      if (widget.animationsPaused) {
        _mapDataRefreshDeferredUntilResume = true;
      } else {
        _mapDataRefreshDeferredUntilResume = false;
        _scheduleMapDataRefresh();
      }
    } else if (widget._source == _TilemapSource.world &&
        oldWidget.animationsPaused &&
        !widget.animationsPaused &&
        _mapDataRefreshDeferredUntilResume) {
      _mapDataRefreshDeferredUntilResume = false;
      _scheduleMapDataRefresh();
    }
    final entityChanged =
        oldWidget._source != widget._source ||
        oldWidget._entityId != widget._entityId;
    final initialLocationChanged = oldWidget.locationId != widget.locationId;
    if (!entityChanged && !initialLocationChanged) {
      _applyRequestedLocationNavigation(reload: true);
      return;
    }
    _currentLocationId = widget.locationId.trim();
    _locationTrail.clear();
    _requestedPreferredFocusLocationId = '';
    widget.restorationController?._ensureScope(
      scopeKey: _restorationScopeKey,
      initialLocationId: _currentLocationId,
    );
    _saveRestorationNavigation();
    if (entityChanged) {
      _resetMapCache();
    } else {
      _loadingCoordinator.retargetInitialEntry();
    }
    _applyRequestedLocationNavigation(reload: false);
    _loadCurrentLocation(rebuild: false);
  }

  @override
  void dispose() {
    _saveRestorationNavigation();
    widget.restorationController?.removeListener(
      _handleRestorationControllerNavigationRequested,
    );
    _cacheGeneration += 1;
    _mapDataGeneration += 1;
    _stopAllFirstRenderTraces(result: 'cancelled');
    _loadingCoordinator.dispose();
    _prerenderController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    tilemapSettingsButtonVisibility.listenable.removeListener(
      _handleSettingsButtonVisibilityChanged,
    );
    final shouldFlushSettings = _settingsSaveTimer?.isActive ?? false;
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = null;
    if (_settingsReady && shouldFlushSettings) {
      unawaited(_persistSettings(_currentSettings));
    }
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    _prerenderController.handleMemoryPressure();
  }

  TilemapRenderSettings get _currentSettings {
    return TilemapRenderSettings(
      visualMode: _visualMode,
      loadingStyle: _loadingStyle,
      fogControlPoints: _fogControlPoints,
      blendFogWithShadowTiles: _blendFogWithShadowTiles,
      cacheFogTileBitmaps: _cacheFogTileBitmaps,
      showShadowZeroBorders: _showShadowZeroBorders,
      showLocationImageFlow: _showLocationImageFlow,
      locationImageFlowAngleDegrees: _locationImageFlowAngleDegrees,
      locationImageFlowGradientPoints: _locationImageFlowGradientPoints,
      locationImageFlowOpacity: _locationImageFlowOpacity,
      locationImageFlowDurationSeconds: _locationImageFlowDurationSeconds,
      locationImageFlowBlendMode: _locationImageFlowBlendMode,
      nearbyLocationDistanceTiles: _nearbyLocationDistanceTiles,
      distantLocationDistanceTiles: _distantLocationDistanceTiles,
      nearbyLocationInitialScale: _nearbyLocationInitialScale,
      distantLocationInitialScale: _distantLocationInitialScale,
      dragBoundaryPaddingTiles: _dragBoundaryPaddingTiles,
    );
  }

  Future<void> _loadCachedSettings() async {
    final settings = (await _settingsStore.load()).resolveForRuntime(
      releaseMode: kReleaseMode,
    );
    if (!mounted) return;
    if (settings.loadingStyle == TilemapLoadingStyle.disabled) {
      _loadingCoordinator.completeInitialEntryWithoutOverlay();
    }
    setState(() {
      _visualMode = settings.visualMode;
      _loadingStyle = settings.loadingStyle;
      _fogControlPoints = settings.fogControlPoints;
      _blendFogWithShadowTiles = settings.blendFogWithShadowTiles;
      _cacheFogTileBitmaps = settings.cacheFogTileBitmaps;
      _showShadowZeroBorders = settings.showShadowZeroBorders;
      _showLocationImageFlow = settings.showLocationImageFlow;
      _locationImageFlowAngleDegrees = settings.locationImageFlowAngleDegrees;
      _locationImageFlowGradientPoints =
          settings.locationImageFlowGradientPoints;
      _locationImageFlowOpacity = settings.locationImageFlowOpacity;
      _locationImageFlowDurationSeconds =
          settings.locationImageFlowDurationSeconds;
      _locationImageFlowBlendMode = settings.locationImageFlowBlendMode;
      _nearbyLocationDistanceTiles = settings.nearbyLocationDistanceTiles;
      _distantLocationDistanceTiles = settings.distantLocationDistanceTiles;
      _nearbyLocationInitialScale = settings.nearbyLocationInitialScale;
      _distantLocationInitialScale = settings.distantLocationInitialScale;
      _dragBoundaryPaddingTiles = settings.dragBoundaryPaddingTiles;
      _settingsReady = true;
    });
  }

  void _handleLoadingCoordinatorChanged() {
    if (!mounted) return;
    final error = _loadingCoordinator.initialLoadError;
    if (error != null) {
      final mapId = _currentConfig?.id;
      if (mapId != null) {
        _finishFirstRenderTrace(mapId: mapId, result: 'failure');
      }
      _reportDisplayReadiness(false);
      _reportDisplayError(error);
    }
    setState(() {});
  }

  void _handlePrerenderControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleSilentMapReady(TilemapConfig config) {
    if (!mounted) return;
    _prerenderController.rememberConfig(config);
  }

  void _handleSettingsButtonVisibilityChanged() {
    if (!mounted) return;
    final wasOpen = _showSettings;
    setState(() {
      if (!tilemapSettingsButtonVisibility.value) {
        _showSettings = false;
      }
    });
    if (wasOpen && !_showSettings) {
      _flushSettingsSave();
    }
  }

  void _scheduleSettingsSave() {
    if (!_settingsReady) return;
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = Timer(_settingsSaveDelay, () {
      _settingsSaveTimer = null;
      unawaited(_persistSettings(_currentSettings));
    });
  }

  void _flushSettingsSave() {
    if (!_settingsReady || _settingsSaveTimer == null) return;
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = null;
    unawaited(_persistSettings(_currentSettings));
  }

  Future<void> _persistSettings(TilemapRenderSettings settings) {
    final operation = _settingsPersistence.then((_) async {
      try {
        await _settingsStore.save(settings);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('[Tilemap] settings save failed: $error');
        }
      }
    });
    _settingsPersistence = operation;
    return operation;
  }

  Future<void> _copySettingsToClipboard() async {
    await Clipboard.setData(
      ClipboardData(text: _currentSettings.toSerializedJson()),
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Tilemap settings JSON copied'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Future<void> _resetSettings() async {
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = null;
    await _settingsPersistence;
    try {
      await _settingsStore.clear();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Tilemap] settings reset failed: $error');
      }
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Tilemap settings reset failed'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }
    if (!mounted) return;
    final defaults = TilemapRenderSettings.defaults();
    setState(() {
      _visualMode = defaults.visualMode;
      _loadingStyle = defaults.loadingStyle;
      _fogControlPoints = defaults.fogControlPoints;
      _blendFogWithShadowTiles = defaults.blendFogWithShadowTiles;
      _cacheFogTileBitmaps = defaults.cacheFogTileBitmaps;
      _showShadowZeroBorders = defaults.showShadowZeroBorders;
      _showLocationImageFlow = defaults.showLocationImageFlow;
      _locationImageFlowAngleDegrees = defaults.locationImageFlowAngleDegrees;
      _locationImageFlowGradientPoints =
          defaults.locationImageFlowGradientPoints;
      _locationImageFlowOpacity = defaults.locationImageFlowOpacity;
      _locationImageFlowDurationSeconds =
          defaults.locationImageFlowDurationSeconds;
      _locationImageFlowBlendMode = defaults.locationImageFlowBlendMode;
      _nearbyLocationDistanceTiles = defaults.nearbyLocationDistanceTiles;
      _distantLocationDistanceTiles = defaults.distantLocationDistanceTiles;
      _nearbyLocationInitialScale = defaults.nearbyLocationInitialScale;
      _distantLocationInitialScale = defaults.distantLocationInitialScale;
      _dragBoundaryPaddingTiles = defaults.dragBoundaryPaddingTiles;
    });
    tilemapVisualModeController.setVisualMode(defaults.visualMode);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Tilemap settings reset'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Future<TilemapConfig> _load(
    GenesisApi api, {
    required String locationId,
  }) async {
    final source = widget._source;
    final entityId = widget._entityId.trim();
    if (entityId.isEmpty) {
      throw const TilemapConfigException('Map entity id must not be empty.');
    }
    if (locationId.isEmpty) {
      throw const TilemapConfigException('location_id must not be empty.');
    }

    final prefetchedRequest = widget.restorationController?._takePrefetchedMap(
      scopeKey: _restorationScopeKey,
      initialLocationId: widget.locationId.trim(),
      locationId: locationId,
    );
    final prefetchedDefinition = prefetchedRequest == null
        ? null
        : await prefetchedRequest;
    final definition =
        prefetchedDefinition ??
        switch (source) {
          _TilemapSource.origin => await api.getOriginMap(
            originId: entityId,
            locationId: locationId,
          ),
          _TilemapSource.world => await api.getWorldMap(
            worldId: entityId,
            locationId: locationId,
          ),
        };
    return _configFromDefinition(
      definition,
      mapId: '${source.name}:$entityId:$locationId',
    );
  }

  Future<_TilemapLoadResult> _loadSafely(
    GenesisApi api, {
    required String locationId,
    required bool reportFailure,
  }) async {
    final trace = await FirebasePerformanceMonitoring.startTrace(
      _loadPerformanceTraceName,
      attributes: <String, String>{'source': widget._source.name},
    );
    try {
      final config = await _load(api, locationId: locationId);
      unawaited(
        FirebasePerformanceMonitoring.stopTrace(
          trace,
          attributes: const <String, String>{'result': 'success'},
          metrics: <String, int>{
            'tile_count': config.tiles.length,
            'map_width': config.width,
            'map_height': config.height,
          },
        ),
      );
      if (reportFailure &&
          !_hasRequestedFirstRenderTrace &&
          _isCurrentMapId(config.id)) {
        _hasRequestedFirstRenderTrace = true;
        await _startFirstRenderTrace(config);
      }
      return _TilemapLoadResult.success(config);
    } catch (error) {
      unawaited(
        FirebasePerformanceMonitoring.stopTrace(
          trace,
          attributes: const <String, String>{'result': 'failure'},
        ),
      );
      if (kDebugMode && reportFailure) {
        debugPrint('[Tilemap] load failed: $error');
      }
      return _TilemapLoadResult.failure(error);
    }
  }

  Future<void> _startFirstRenderTrace(TilemapConfig config) async {
    final generation = _cacheGeneration;
    final trace = await FirebasePerformanceMonitoring.startTrace(
      _firstRenderPerformanceTraceName,
      attributes: <String, String>{
        'source': widget._source.name,
        'renderer': 'canvas',
      },
    );
    if (trace == null) return;

    if (!mounted ||
        generation != _cacheGeneration ||
        !_isCurrentMapId(config.id)) {
      unawaited(
        FirebasePerformanceMonitoring.stopTrace(
          trace,
          attributes: const <String, String>{'result': 'cancelled'},
        ),
      );
      return;
    }

    final previous = _firstRenderTraces.remove(config.id);
    if (previous != null) {
      unawaited(
        FirebasePerformanceMonitoring.stopTrace(
          previous,
          attributes: const <String, String>{'result': 'cancelled'},
        ),
      );
    }
    _firstRenderTraces[config.id] = trace;
  }

  void _finishFirstRenderTrace({
    required String mapId,
    required String result,
    TilemapConfig? config,
    TilemapImageLoadPlan? plan,
  }) {
    final trace = _firstRenderTraces.remove(mapId);
    if (trace == null) return;
    final imageAssets = plan == null
        ? const <String>{}
        : plan.tileCountByAsset.keys.toSet();
    unawaited(
      FirebasePerformanceMonitoring.stopTrace(
        trace,
        attributes: <String, String>{'result': result},
        metrics: config == null || plan == null
            ? const <String, int>{}
            : <String, int>{
                'visible_tile_count': plan.totalTileCount,
                'image_count': imageAssets.length,
                'map_width': config.width,
                'map_height': config.height,
              },
      ),
    );
  }

  void _stopFirstRenderTracesExcept(String retainedMapId) {
    for (final mapId in _firstRenderTraces.keys.toList(growable: false)) {
      if (mapId == retainedMapId) continue;
      _finishFirstRenderTrace(mapId: mapId, result: 'cancelled');
    }
  }

  void _stopAllFirstRenderTraces({required String result}) {
    for (final mapId in _firstRenderTraces.keys.toList(growable: false)) {
      _finishFirstRenderTrace(mapId: mapId, result: result);
    }
  }

  Future<_TilemapLoadResult> _requestMap(
    GenesisApi api,
    String rawLocationId, {
    required bool reportFailure,
  }) {
    final locationId = rawLocationId.trim();
    final cached = _cachedMapResult(locationId);
    if (cached != null) return Future<_TilemapLoadResult>.value(cached);

    final existing = _mapRequests[locationId];
    if (existing != null) return existing;

    final generation = _cacheGeneration;
    final mapDataGeneration = _mapDataGeneration;
    final request =
        _loadSafely(api, locationId: locationId, reportFailure: reportFailure)
            .then((result) {
              if (generation == _cacheGeneration &&
                  mapDataGeneration == _mapDataGeneration) {
                _storeMapResult(locationId, result);
              }
              return result;
            })
            .whenComplete(() {
              if (generation == _cacheGeneration &&
                  mapDataGeneration == _mapDataGeneration) {
                _mapRequests.remove(locationId);
              }
            });
    _mapRequests[locationId] = request;
    return request;
  }

  _TilemapLoadResult? _cachedMapResult(String locationId) {
    final result = _mapResults.remove(locationId);
    if (result != null) _mapResults[locationId] = result;
    return result;
  }

  void _storeMapResult(String locationId, _TilemapLoadResult result) {
    _mapResults.remove(locationId);
    _mapResults[locationId] = result;
    _pruneMapResults();
  }

  void _pruneMapResults() {
    final protectedMapIds = <String>{
      ..._prerenderController.residentMapIds,
      if (_currentConfig case final config?) config.id,
    };
    while (_mapResults.length > _maxCachedMapResults) {
      String? evictionLocationId;
      for (final entry in _mapResults.entries) {
        final mapId = entry.value.config?.id;
        if (entry.key != _currentLocationId &&
            (mapId == null || !protectedMapIds.contains(mapId))) {
          evictionLocationId = entry.key;
          break;
        }
      }
      if (evictionLocationId == null) return;
      _mapResults.remove(evictionLocationId);
    }
  }

  void _resetMapCache() {
    _reportDisplayReadiness(false);
    _cacheGeneration += 1;
    _mapDataGeneration += 1;
    _mapDataRefreshPending = false;
    _mapDataRefreshDeferredUntilResume = false;
    _stopAllFirstRenderTraces(result: 'cancelled');
    _hasRequestedFirstRenderTrace = false;
    _loadingCoordinator.resetSession();
    _prerenderController.resetSession();
    if (_settingsReady && _loadingStyle == TilemapLoadingStyle.disabled) {
      _loadingCoordinator.completeInitialEntryWithoutOverlay();
    }
    _mapRequests.clear();
    _mapResults.clear();
    _currentConfig = null;
    _mapError = null;
    _imageError = null;
    _rendererRevisionByMapId.clear();
    _initialScaleByConfig.clear();
    _hasRevealedInitialMap = false;
    _configuredPrerenderEnvironmentKey = null;
    _configuredPrerenderViewportSize = null;
    _configuredPrerenderDevicePixelRatio = null;
    _liveViewportReadyCallbacks.clear();
    _reportedCurrentLocationsSignature = '';
    _scheduledCurrentLocationsSignature = '';
    _prerenderEnvironmentGeneration += 1;
  }

  void _scheduleMapDataRefresh() {
    if (!mounted || widget._source != _TilemapSource.world) return;
    _mapDataGeneration += 1;
    _mapDataRefreshPending = true;
    _mapRequests.clear();
    _loadingCoordinator.invalidatePreloadCaches();
    if (_mapDataRefreshRunning) return;
    unawaited(_drainMapDataRefreshes());
  }

  Future<void> _drainMapDataRefreshes() async {
    if (_mapDataRefreshRunning) return;
    _mapDataRefreshRunning = true;
    try {
      while (mounted && _mapDataRefreshPending) {
        _mapDataRefreshPending = false;
        final generation = _mapDataGeneration;
        try {
          await _refreshCurrentMapData(generation);
        } catch (error) {
          if (kDebugMode) {
            debugPrint('[Tilemap] map_updated refresh failed: $error');
          }
        }
      }
    } finally {
      _mapDataRefreshRunning = false;
      if (mounted && _mapDataRefreshPending) {
        unawaited(_drainMapDataRefreshes());
      }
    }
  }

  Future<void> _refreshCurrentMapData(int generation) async {
    final api = _api;
    if (api == null) return;
    if (_deferMapDataRefreshIfPaused()) return;
    final locationId = _currentLocationId.trim();
    if (locationId.isEmpty) return;

    final previousCurrentConfig = _currentConfig;
    final currentResult = await _loadSafely(
      api,
      locationId: locationId,
      reportFailure: false,
    );
    if (_deferMapDataRefreshIfPaused()) return;
    if (!_mapDataRefreshIsCurrent(generation, locationId)) {
      _restartMapDataRefreshIfLocationChanged(locationId);
      return;
    }

    final loadedCurrentConfig = currentResult.config;
    if (loadedCurrentConfig == null) {
      final error = currentResult.error;
      if (kDebugMode && error != null) {
        debugPrint('[Tilemap] map_updated refresh failed: $error');
      }
      if (previousCurrentConfig == null) {
        if (error != null) _reportDisplayError(error);
        setState(() => _mapError = error);
      } else {
        setState(() {});
        _scheduleRefreshedPreloadWork(previousCurrentConfig);
      }
      return;
    }

    final currentConfigChanged = !tilemapConfigDataEquals(
      previousCurrentConfig,
      loadedCurrentConfig,
    );
    final nextCurrentConfig = currentConfigChanged
        ? loadedCurrentConfig
        : previousCurrentConfig ?? loadedCurrentConfig;
    final nextPreloadLocationIds = _preferredPreloadLocationIds(
      nextCurrentConfig,
    );
    final previousPreloadResults = <String, _TilemapLoadResult?>{
      for (final preloadLocationId in nextPreloadLocationIds)
        preloadLocationId: _mapResults[preloadLocationId],
    };
    final refreshedPreloadResults = <MapEntry<String, _TilemapLoadResult>>[];
    for (final preloadLocationId in nextPreloadLocationIds) {
      if (!_mapDataRefreshIsCurrent(generation, locationId)) {
        _restartMapDataRefreshIfLocationChanged(locationId);
        return;
      }
      final preloadResult = await _loadSafely(
        api,
        locationId: preloadLocationId,
        reportFailure: false,
      );
      if (_deferMapDataRefreshIfPaused()) return;
      refreshedPreloadResults.add(MapEntry(preloadLocationId, preloadResult));
    }
    if (!_mapDataRefreshIsCurrent(generation, locationId)) {
      _restartMapDataRefreshIfLocationChanged(locationId);
      return;
    }

    final resolvedPreloadConfigs = <String, TilemapConfig>{};
    final changedPreloadMapIds = <String>{};
    for (final entry in refreshedPreloadResults) {
      final previousResult = previousPreloadResults[entry.key];
      final previousConfig = previousResult?.config;
      final loadedConfig = entry.value.config;
      if (loadedConfig == null) {
        final error = entry.value.error;
        if (kDebugMode && error != null) {
          debugPrint(
            '[Tilemap] map_updated preload refresh failed '
            'location=${entry.key}: $error',
          );
        }
        if (previousConfig != null) {
          resolvedPreloadConfigs[entry.key] = previousConfig;
        }
        continue;
      }
      final changed = !tilemapConfigDataEquals(previousConfig, loadedConfig);
      final resolvedConfig = changed
          ? loadedConfig
          : previousConfig ?? loadedConfig;
      resolvedPreloadConfigs[entry.key] = resolvedConfig;
      if (changed && previousConfig != null) {
        changedPreloadMapIds.add(resolvedConfig.id);
      }
    }

    final retainedLocationIds = <String>{
      locationId,
      ...resolvedPreloadConfigs.keys,
    };
    _mapResults.removeWhere(
      (cachedLocationId, _) => !retainedLocationIds.contains(cachedLocationId),
    );
    _storeMapResult(locationId, _TilemapLoadResult.success(nextCurrentConfig));
    for (final entry in resolvedPreloadConfigs.entries) {
      _storeMapResult(entry.key, _TilemapLoadResult.success(entry.value));
    }
    if (currentConfigChanged && _loadingCoordinator.initialLoadError != null) {
      _loadingCoordinator.retryInitialTileLoad();
    }
    setState(() {
      _currentConfig = nextCurrentConfig;
      _mapError = null;
      if (currentConfigChanged) _imageError = null;
    });
    for (final config in resolvedPreloadConfigs.values) {
      _prerenderController.rememberConfig(config);
    }
    if (currentConfigChanged) {
      _bumpRendererRevisionForMapId(nextCurrentConfig.id);
      _activateConfig(nextCurrentConfig);
    }
    for (final mapId in changedPreloadMapIds) {
      _bumpRendererRevisionForMapId(mapId);
    }
    _prerenderController.retainKnownMapIds({
      nextCurrentConfig.id,
      for (final preloadLocationId in nextPreloadLocationIds)
        _mapIdForLocation(preloadLocationId),
    });
    _scheduleRefreshedPreloadWork(nextCurrentConfig);
  }

  bool _deferMapDataRefreshIfPaused() {
    if (!mounted || !widget.animationsPaused) return false;
    _mapDataRefreshDeferredUntilResume = true;
    return true;
  }

  bool _mapDataRefreshIsCurrent(int generation, String locationId) {
    return mounted &&
        generation == _mapDataGeneration &&
        locationId == _currentLocationId.trim();
  }

  void _restartMapDataRefreshIfLocationChanged(String requestedLocationId) {
    if (!mounted || requestedLocationId == _currentLocationId.trim()) return;
    _mapDataGeneration += 1;
    _mapDataRefreshPending = true;
    _mapRequests.clear();
  }

  List<String> _preferredPreloadLocationIds([TilemapConfig? config]) {
    if (!widget.relatedMapPreloadingEnabled) return const <String>[];
    final result = <String>[];
    void add(String rawLocationId) {
      final locationId = rawLocationId.trim();
      if (locationId.isEmpty ||
          locationId == _currentLocationId.trim() ||
          result.contains(locationId)) {
        return;
      }
      result.add(locationId);
    }

    if (_locationTrail.isNotEmpty) add(_locationTrail.last);
    final currentConfig = config ?? _currentConfig;
    if (currentConfig != null) {
      for (final locationId in tilemapDrillTargetLocationIds(
        config: currentConfig,
        locationNodes: widget.locationNodes,
      ).take(tilemapSilentPreloadMaxPendingTargets)) {
        add(locationId);
      }
    }
    return result;
  }

  void _scheduleRefreshedPreloadWork(TilemapConfig config) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_currentConfig, config)) return;
      final viewportSize = _configuredPrerenderViewportSize;
      final devicePixelRatio = _configuredPrerenderDevicePixelRatio;
      if (viewportSize == null || devicePixelRatio == null) return;
      final plan = _imageLoadPlanForViewport(
        config: config,
        viewportSize: viewportSize,
        devicePixelRatio: devicePixelRatio,
      );
      _loadingCoordinator.scheduleBackgroundTilePreload(
        config: config,
        plan: plan,
        loadImage: _loadTileImage,
      );
      _scheduleSilentDrillDownPreload(
        config,
        displayTilePixelSize:
            tilemapBaseTileExtent *
            _initialScaleForConfig(config) *
            tilemapImageDevicePixelRatio(devicePixelRatio),
      );
    });
  }

  Future<TilemapConfig?> _preloadMap(String locationId) async {
    final api = _api;
    if (api == null) return null;

    final generation = _cacheGeneration;
    final result = await _requestMap(api, locationId, reportFailure: false);
    if (!mounted || generation != _cacheGeneration) return null;

    final config = result.config;
    if (config != null) return config;

    // A silent optimization must not leave a negative cache entry that would
    // prevent the user's later interactive navigation from retrying.
    if (_currentLocationId.trim() != locationId &&
        identical(_mapResults[locationId], result)) {
      _mapResults.remove(locationId);
    }
    return null;
  }

  void _loadCurrentLocation({required bool rebuild}) {
    final api = _api;
    if (api == null) return;
    _reportDisplayReadiness(false);
    final locationId = _currentLocationId.trim();
    _stopFirstRenderTracesExcept(_mapIdForLocation(locationId));
    final cached = _cachedMapResult(locationId);
    final cachedConfig = cached?.config;
    if (cachedConfig != null) _activateConfig(cachedConfig);

    void applyPendingOrCached() {
      _imageError = null;
      _mapError = cached?.error;
      _currentConfig = cachedConfig;
      final error = cached?.error;
      if (error != null) _reportDisplayError(error);
    }

    if (rebuild) {
      setState(applyPendingOrCached);
    } else {
      applyPendingOrCached();
    }
    if (cached != null) {
      return;
    }

    final generation = _cacheGeneration;
    final mapDataGeneration = _mapDataGeneration;
    unawaited(
      _requestMap(api, locationId, reportFailure: true).then((result) {
        if (!mounted ||
            generation != _cacheGeneration ||
            mapDataGeneration != _mapDataGeneration ||
            locationId != _currentLocationId.trim()) {
          return;
        }
        final config = result.config;
        if (config != null) _activateConfig(config);
        final error = result.error;
        if (error != null) _reportDisplayError(error);
        setState(() {
          _mapError = error;
          _currentConfig = config;
        });
      }),
    );
  }

  bool _activateConfig(TilemapConfig config) {
    return _prerenderController.activateMap(
      config,
      preferredMapIds: _preferredPrerenderMapIds(config),
    );
  }

  TilemapConfig _configFromDefinition(
    TilemapDefinition definition, {
    required String mapId,
  }) {
    final tileTypes = definition.tileTypes;
    final mapJson = definition.mapJson;
    if (!definition.isAvailable || tileTypes == null || mapJson == null) {
      throw const TilemapConfigException('Tilemap data is unavailable.');
    }
    return TilemapConfig.fromTiles(
      id: mapId,
      width: mapJson.width,
      height: mapJson.height,
      tileTypes: tileTypes,
      tiles: definition.tiles.map(
        (tile) => TilemapCell(
          x: tile.x,
          y: tile.y,
          type: tile.type,
          shadow: tile.shadow,
          locationId: tile.locationId,
        ),
      ),
    );
  }

  Future<void> _handleTileAction(TilemapCell tile) async {
    final locationId = tile.locationId?.trim() ?? '';
    if (locationId.isEmpty) return;
    final node = findWorldMapLocationNode(widget.locationNodes, locationId);
    if (node == null) return;

    final action = resolveWorldMapLocationAction(node);
    final chatTarget = action.chatTarget;
    if (chatTarget != null) {
      await widget.onPointTap?.call(chatTarget);
      return;
    }

    final drillTarget = action.drillTarget;
    if (drillTarget == null) return;
    widget.onDrillIntoLocation?.call();
    _locationTrail.add(_currentLocationId);
    _currentLocationId = drillTarget.id.trim();
    _saveRestorationNavigation();
    _loadCurrentLocation(rebuild: true);
  }

  String? _locationNameForTile(TilemapCell tile) {
    final locationId = tile.locationId?.trim() ?? '';
    if (locationId.isEmpty) return null;
    final node = findWorldMapLocationNode(widget.locationNodes, locationId);
    final name = node?.point.name.trim() ?? '';
    return name.isEmpty ? null : name;
  }

  bool _showRecentChatForTile(TilemapCell tile) {
    final recentLocationIds = widget.recentChatLocationIds;
    if (recentLocationIds.isEmpty) return false;
    final locationId = tile.locationId?.trim() ?? '';
    if (locationId.isEmpty) return false;
    if (recentLocationIds.contains(locationId)) return true;
    final node = findWorldMapLocationNode(widget.locationNodes, locationId);
    final sceneId = node?.point.sceneId.trim() ?? '';
    return sceneId.isNotEmpty && recentLocationIds.contains(sceneId);
  }

  bool _showEventForTile(TilemapCell tile) {
    final eventLocationIds = widget.eventLocationIds;
    if (eventLocationIds.isEmpty) return false;
    final locationId = tile.locationId?.trim() ?? '';
    if (locationId.isEmpty) return false;
    if (eventLocationIds.contains(locationId)) return true;
    final node = findWorldMapLocationNode(widget.locationNodes, locationId);
    final sceneId = node?.point.sceneId.trim() ?? '';
    return sceneId.isNotEmpty && eventLocationIds.contains(sceneId);
  }

  bool _showNewForTile(TilemapCell tile) {
    final locationId = tile.locationId?.trim() ?? '';
    if (locationId.isEmpty) return false;
    final node = findWorldMapLocationNode(widget.locationNodes, locationId);
    return node?.point.isNew ?? false;
  }

  List<UserAvatar> _locationAvatarsForTile(TilemapCell tile) {
    final locationId = tile.locationId?.trim() ?? '';
    if (locationId.isEmpty) return const <UserAvatar>[];
    return worldMapVisibleAvatarsForLocation(
      findWorldMapLocationNode(widget.locationNodes, locationId),
    );
  }

  String _preferredVisibleFocusLocationId(TilemapConfig config) {
    return resolveTilemapPreferredVisibleLocationId(
      preferredLocationId: _requestedPreferredFocusLocationId.isNotEmpty
          ? _requestedPreferredFocusLocationId
          : widget.preferredFocusLocationId,
      visibleLocationIds: config.tiles
          .map((tile) => tile.locationId?.trim() ?? '')
          .where((locationId) => locationId.isNotEmpty),
      locationNodes: widget.locationNodes,
    );
  }

  void _exitLocation() {
    if (_locationTrail.isEmpty) return;
    widget.onDrillIntoLocation?.call();
    _currentLocationId = _locationTrail.removeLast();
    _saveRestorationNavigation();
    _loadCurrentLocation(rebuild: true);
  }

  String get _restorationScopeKey =>
      '${widget._source.name}:${widget._entityId.trim()}';

  void _saveRestorationNavigation() {
    widget.restorationController?._saveNavigation(
      scopeKey: _restorationScopeKey,
      initialLocationId: widget.locationId.trim(),
      currentLocationId: _currentLocationId,
      locationTrail: _locationTrail,
    );
  }

  void _handleRestorationControllerNavigationRequested() {
    _applyRequestedLocationNavigation(reload: true);
  }

  void _applyRequestedLocationNavigation({required bool reload}) {
    final controller = widget.restorationController;
    if (controller == null) return;
    final revision = controller._locationNavigationRevision;
    final targetLocationId = controller._requestedLocationId.trim();
    if (targetLocationId.isEmpty ||
        revision == _appliedLocationNavigationRevision) {
      return;
    }
    final navigation = resolveWorldMapChatTargetNavigation(
      initialLocationId: widget.locationId,
      targetLocationId: targetLocationId,
      locationNodes: widget.locationNodes,
    );
    if (navigation == null) {
      _appliedLocationNavigationRevision = revision;
      controller._consumeLocationNavigationRequest(
        revision: revision,
        locationId: targetLocationId,
      );
      return;
    }

    _appliedLocationNavigationRevision = revision;
    _currentLocationId = navigation.currentLocationId;
    _locationTrail
      ..clear()
      ..addAll(navigation.locationTrail);
    _requestedPreferredFocusLocationId = targetLocationId;
    final targetMapId = _mapIdForLocation(_currentLocationId);
    controller._clearViewportTransform(
      scopeKey: _restorationScopeKey,
      initialLocationId: widget.locationId.trim(),
      mapId: targetMapId,
    );
    _saveRestorationNavigation();
    controller._consumeLocationNavigationRequest(
      revision: revision,
      locationId: targetLocationId,
    );
    if (!reload) return;

    _bumpRendererRevisionForMapId(targetMapId);
    _loadCurrentLocation(rebuild: true);
  }

  void _retry() {
    if (_loadingCoordinator.initialLoadError != null) {
      _bumpCurrentRendererRevision();
      _loadingCoordinator.retryInitialTileLoad();
      return;
    }

    if (_imageError != null) {
      setState(() {
        _imageError = null;
        _bumpCurrentRendererRevision();
      });
      return;
    }

    final locationId = _currentLocationId.trim();
    _mapResults.remove(locationId);
    _mapRequests.remove(locationId);
    _loadCurrentLocation(rebuild: true);
  }

  void _setVisualMode(TilemapVisualMode visualMode) {
    if (_visualMode == visualMode) return;
    setState(() => _visualMode = visualMode);
    tilemapVisualModeController.setVisualMode(visualMode);
    _scheduleSettingsSave();
  }

  void _setLoadingStyle(TilemapLoadingStyle loadingStyle) {
    if (_loadingStyle == loadingStyle) return;
    if (loadingStyle == TilemapLoadingStyle.disabled) {
      _loadingCoordinator.completeInitialEntryWithoutOverlay();
    }
    setState(() => _loadingStyle = loadingStyle);
    _scheduleSettingsSave();
  }

  void _setFogControlPoints(List<TilemapFogControlPoint> controlPoints) {
    setState(() {
      _fogControlPoints = List<TilemapFogControlPoint>.unmodifiable(
        controlPoints,
      );
    });
    _scheduleSettingsSave();
  }

  void _setBlendFogWithShadowTiles(bool value) {
    if (_blendFogWithShadowTiles == value) return;
    setState(() => _blendFogWithShadowTiles = value);
    _scheduleSettingsSave();
  }

  void _setCacheFogTileBitmaps(bool value) {
    if (_cacheFogTileBitmaps == value) return;
    setState(() => _cacheFogTileBitmaps = value);
    _scheduleSettingsSave();
  }

  void _setShowShadowZeroBorders(bool value) {
    if (_showShadowZeroBorders == value) return;
    setState(() => _showShadowZeroBorders = value);
    _scheduleSettingsSave();
  }

  void _setShowLocationImageFlow(bool value) {
    if (_showLocationImageFlow == value) return;
    setState(() => _showLocationImageFlow = value);
    _scheduleSettingsSave();
  }

  void _setLocationImageFlowAngleDegrees(double value) {
    final resolved = value.clamp(0.0, 360.0).toDouble();
    if (_locationImageFlowAngleDegrees == resolved) return;
    setState(() => _locationImageFlowAngleDegrees = resolved);
    _scheduleSettingsSave();
  }

  void _setLocationImageFlowGradientPoints(
    List<TilemapLocationImageFlowGradientPoint> value,
  ) {
    setState(() {
      _locationImageFlowGradientPoints =
          List<TilemapLocationImageFlowGradientPoint>.unmodifiable(value);
    });
    _scheduleSettingsSave();
  }

  void _setLocationImageFlowOpacity(double value) {
    final resolved = value.clamp(0.0, 1.0).toDouble();
    if (_locationImageFlowOpacity == resolved) return;
    setState(() => _locationImageFlowOpacity = resolved);
    _scheduleSettingsSave();
  }

  void _setLocationImageFlowDurationSeconds(double value) {
    final resolved = value
        .clamp(
          tilemapLocationImageFlowDurationSecondsMin,
          tilemapLocationImageFlowDurationSecondsMax,
        )
        .toDouble();
    if (_locationImageFlowDurationSeconds == resolved) return;
    setState(() => _locationImageFlowDurationSeconds = resolved);
    _scheduleSettingsSave();
  }

  void _setLocationImageFlowBlendMode(TilemapLocationImageFlowBlendMode value) {
    if (_locationImageFlowBlendMode == value) return;
    setState(() => _locationImageFlowBlendMode = value);
    _scheduleSettingsSave();
  }

  void _setNearbyLocationDistance(double value) {
    final resolved = value
        .clamp(
          tilemapLocationDistanceThresholdMin,
          _distantLocationDistanceTiles - tilemapLocationDistanceThresholdStep,
        )
        .toDouble();
    if (_nearbyLocationDistanceTiles == resolved) return;
    setState(() {
      _nearbyLocationDistanceTiles = resolved;
      _initialScaleByConfig.clear();
      _loadingCoordinator.invalidateInitialTilePlan();
    });
    _scheduleSettingsSave();
  }

  void _setDistantLocationDistance(double value) {
    final resolved = value
        .clamp(
          _nearbyLocationDistanceTiles + tilemapLocationDistanceThresholdStep,
          tilemapLocationDistanceThresholdMax,
        )
        .toDouble();
    if (_distantLocationDistanceTiles == resolved) return;
    setState(() {
      _distantLocationDistanceTiles = resolved;
      _initialScaleByConfig.clear();
      _loadingCoordinator.invalidateInitialTilePlan();
    });
    _scheduleSettingsSave();
  }

  void _setNearbyLocationInitialScale(double value) {
    final resolved = value
        .roundToDouble()
        .clamp(
          math.max(
            tilemapNearbyLocationInitialScaleMin,
            _distantLocationInitialScale,
          ),
          tilemapNearbyLocationInitialScaleMax,
        )
        .toDouble();
    if (_nearbyLocationInitialScale == resolved) return;
    setState(() {
      _nearbyLocationInitialScale = resolved;
      _initialScaleByConfig.clear();
      _loadingCoordinator.invalidateInitialTilePlan();
    });
    _scheduleSettingsSave();
  }

  void _setDistantLocationInitialScale(double value) {
    final resolved = value
        .roundToDouble()
        .clamp(
          tilemapDistantLocationInitialScaleMin,
          math.min(
            tilemapDistantLocationInitialScaleMax,
            _nearbyLocationInitialScale,
          ),
        )
        .toDouble();
    if (_distantLocationInitialScale == resolved) return;
    setState(() {
      _distantLocationInitialScale = resolved;
      _initialScaleByConfig.clear();
      _loadingCoordinator.invalidateInitialTilePlan();
    });
    _scheduleSettingsSave();
  }

  void _setDragBoundaryPaddingTiles(double value) {
    final resolved = value
        .roundToDouble()
        .clamp(
          tilemapDragBoundaryPaddingTilesMin,
          tilemapDragBoundaryPaddingTilesMax,
        )
        .toDouble();
    if (_dragBoundaryPaddingTiles == resolved) return;
    setState(() => _dragBoundaryPaddingTiles = resolved);
    _scheduleSettingsSave();
  }

  void _toggleSettings() {
    final willClose = _showSettings;
    setState(() => _showSettings = !_showSettings);
    if (willClose) _flushSettingsSave();
  }

  void _closeSettings() {
    if (!_showSettings) return;
    setState(() => _showSettings = false);
    _flushSettingsSave();
  }

  void _handleImageError(String mapId, Object error) {
    if (!_isCurrentMapId(mapId)) return;
    if (_imageError != null) return;
    _finishFirstRenderTrace(mapId: mapId, result: 'failure');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _imageError != null || !_isCurrentMapId(mapId)) return;
      _reportDisplayReadiness(false);
      _reportDisplayError(error);
      setState(() => _imageError = error);
    });
  }

  bool _isCurrentMapId(String mapId) {
    final entityId = widget._entityId.trim();
    return mapId ==
        '${widget._source.name}:$entityId:${_currentLocationId.trim()}';
  }

  Future<void> _loadTileImage(String assetUrl) async {
    final customLoader = widget.tileImageLoader;
    if (customLoader != null) {
      await customLoader(assetUrl);
      return;
    }

    Object? precacheError;
    StackTrace? precacheStackTrace;
    await precacheImage(
      GenesisStaticNetworkImageProvider(imageUrl: assetUrl),
      context,
      onError: (error, stackTrace) {
        precacheError = error;
        precacheStackTrace = stackTrace;
      },
    );
    final error = precacheError;
    if (error != null) {
      Error.throwWithStackTrace(
        error,
        precacheStackTrace ?? StackTrace.current,
      );
    }
  }

  double _initialScaleForConfig(TilemapConfig config) {
    return _initialScaleByConfig.putIfAbsent(
      config,
      () => tilemapAutomaticInitialScaleForTiles(
        tiles: config.tiles,
        nearbyDistanceTiles: _nearbyLocationDistanceTiles,
        distantDistanceTiles: _distantLocationDistanceTiles,
        nearbyScale: _nearbyLocationInitialScale,
        distantScale: _distantLocationInitialScale,
      ),
    );
  }

  TilemapImageLoadPlan _imageLoadPlanForViewport({
    required TilemapConfig config,
    required Size viewportSize,
    required double devicePixelRatio,
  }) {
    final initialScale = _initialScaleForConfig(config);
    return TilemapImageLoadPlan.forConfig(
      config: config,
      displayTilePixelSize:
          tilemapBaseTileExtent *
          initialScale *
          tilemapImageDevicePixelRatio(devicePixelRatio),
      viewportSize: viewportSize,
      initialScale: initialScale,
      dragBoundaryPaddingTiles: _dragBoundaryPaddingTiles,
      locationAvatarsForTile: _locationAvatarsForTile,
      preferredLocationId: _preferredVisibleFocusLocationId(config),
      centerContentInitially: widget.centerContentInitially,
    );
  }

  void _scheduleSilentDrillDownPreload(
    TilemapConfig config, {
    required double displayTilePixelSize,
  }) {
    if (!widget.relatedMapPreloadingEnabled) return;
    final currentInitialScale = _initialScaleForConfig(config);
    final imageDevicePixelRatio =
        displayTilePixelSize / (tilemapBaseTileExtent * currentInitialScale);
    _loadingCoordinator.scheduleSilentDrillDownPreload(
      currentConfig: config,
      locationNodes: widget.locationNodes,
      displayTilePixelSize: displayTilePixelSize,
      displayTilePixelSizeForConfig: (targetConfig) {
        return tilemapBaseTileExtent *
            _initialScaleForConfig(targetConfig) *
            imageDevicePixelRatio;
      },
      loadMap: _preloadMap,
      loadImage: _loadTileImage,
    );
  }

  Widget _buildRenderer(
    TilemapConfig config, {
    required Key rendererKey,
    required bool interactive,
    required VoidCallback? onViewportReady,
    bool foreground = true,
    bool includeLiveContent = true,
    ValueChanged<Object>? backgroundImageError,
  }) {
    final initialScale = _initialScaleForConfig(config);
    return TilemapRenderer(
      key: rendererKey,
      config: config,
      initialTransform: widget.restorationController?._viewportTransform(
        scopeKey: _restorationScopeKey,
        initialLocationId: widget.locationId.trim(),
        mapId: config.id,
      ),
      onTransformChanged: widget.restorationController == null
          ? null
          : (transform) {
              widget.restorationController?._saveViewportTransform(
                scopeKey: _restorationScopeKey,
                initialLocationId: widget.locationId.trim(),
                mapId: config.id,
                transform: transform,
              );
            },
      onTileAction: interactive ? _handleTileAction : null,
      locationNameForTile: _locationNameForTile,
      locationAvatarsForTile: _locationAvatarsForTile,
      showRecentChatForTile: _showRecentChatForTile,
      showEventForTile: _showEventForTile,
      showNewForTile: _showNewForTile,
      preferredFocusLocationId: _preferredVisibleFocusLocationId(config),
      centerContentInitially: widget.centerContentInitially,
      messageBubbles: includeLiveContent
          ? widget.messageBubbles
          : const <WorldMapMessageBubble>[],
      messageBubblePlaybackPaused:
          !interactive ||
          !includeLiveContent ||
          widget.messageBubblePlaybackPaused,
      onMapTap: interactive ? widget.onMapTap : null,
      onImageError:
          backgroundImageError ??
          ((interactive || onViewportReady != null) &&
                  widget.tileImageLoader == null
              ? (error) => _handleImageError(config.id, error)
              : null),
      onViewportReady: onViewportReady,
      waitForVisibleTileImageFrames: widget.tileImageLoader == null,
      isForeground: foreground,
      animationsPaused: widget.animationsPaused,
      locationImageFlowPaused: widget.locationImageFlowPaused,
      visualMode: _visualMode,
      fogControlPoints: _fogControlPoints,
      blendFogWithShadowTiles: _blendFogWithShadowTiles,
      cacheFogTileBitmaps: _cacheFogTileBitmaps,
      showShadowZeroBorders: _showShadowZeroBorders,
      showLocationImageFlow: _showLocationImageFlow,
      locationImageFlowAngleDegrees: _locationImageFlowAngleDegrees,
      locationImageFlowGradientPoints: _locationImageFlowGradientPoints,
      locationImageFlowOpacity: _locationImageFlowOpacity,
      locationImageFlowDurationSeconds: _locationImageFlowDurationSeconds,
      locationImageFlowBlendMode: _locationImageFlowBlendMode,
      initialScale: initialScale,
      dragBoundaryPaddingTiles: _dragBoundaryPaddingTiles,
      zoomControlBottom: widget.zoomControlBottom,
    );
  }

  int _rendererRevisionFor(TilemapConfig config) {
    return _rendererRevisionByMapId[config.id] ?? 0;
  }

  void _bumpCurrentRendererRevision() {
    final mapId = _currentConfig?.id;
    if (mapId != null) _bumpRendererRevisionForMapId(mapId);
  }

  void _bumpRendererRevisionForMapId(String mapId) {
    _rendererRevisionByMapId[mapId] =
        (_rendererRevisionByMapId[mapId] ?? 0) + 1;
    _prerenderController.invalidateMap(mapId);
  }

  String _mapIdForLocation(String rawLocationId) {
    return '${widget._source.name}:'
        '${widget._entityId.trim()}:'
        '${rawLocationId.trim()}';
  }

  List<String> _preferredPrerenderMapIds([TilemapConfig? config]) {
    if (!widget.relatedMapPreloadingEnabled) return const <String>[];
    final currentConfig = config ?? _currentConfig;
    final drillTargetIds = currentConfig == null
        ? const <String>[]
        : tilemapDrillTargetLocationIds(
            config: currentConfig,
            locationNodes: widget.locationNodes,
          ).take(tilemapSilentPreloadMaxPendingTargets).toList(growable: false);
    return <String>[
      if (_locationTrail.isNotEmpty) _mapIdForLocation(_locationTrail.last),
      for (final locationId in drillTargetIds) _mapIdForLocation(locationId),
    ];
  }

  VoidCallback _liveReadyCallbackFor(TilemapConfig config) {
    final environmentGeneration = _prerenderEnvironmentGeneration;
    final key =
        '${config.id}|${_rendererRevisionFor(config)}|$environmentGeneration';
    return _liveViewportReadyCallbacks.putIfAbsent(
      key,
      () =>
          () => _handleLiveViewportReady(config.id, environmentGeneration),
    );
  }

  Widget _buildLiveRendererSurface(
    TilemapConfig config, {
    required bool interactive,
    required bool foreground,
    required bool reportViewportReady,
  }) {
    final revision = _rendererRevisionFor(config);
    return TilemapPrerenderSurface(
      key: ValueKey<String>('tilemap-renderer-surface-${config.id}-$revision'),
      interactive: interactive,
      suspended: widget.animationsPaused,
      child: _buildRenderer(
        config,
        rendererKey: ValueKey<String>(
          'tilemap-live-renderer-${config.id}-$revision',
        ),
        interactive: interactive,
        foreground: foreground,
        includeLiveContent: foreground,
        onViewportReady: reportViewportReady
            ? _liveReadyCallbackFor(config)
            : null,
        backgroundImageError: widget.tileImageLoader != null
            ? null
            : (error) {
                if (_isCurrentMapId(config.id)) {
                  _handleImageError(config.id, error);
                  return;
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _prerenderController.rejectMap(config.id);
                });
              },
      ),
    );
  }

  void _handleLiveViewportReady(String mapId, int environmentGeneration) {
    if (!mounted || environmentGeneration != _prerenderEnvironmentGeneration) {
      return;
    }

    final isCurrentTarget = _currentConfig?.id == mapId;
    if (isCurrentTarget) {
      _requestedPreferredFocusLocationId = '';
      _hasRevealedInitialMap = true;
      final config = _currentConfig;
      final viewportSize = _configuredPrerenderViewportSize;
      final devicePixelRatio = _configuredPrerenderDevicePixelRatio;
      if (config != null && viewportSize != null && devicePixelRatio != null) {
        final plan = _imageLoadPlanForViewport(
          config: config,
          viewportSize: viewportSize,
          devicePixelRatio: devicePixelRatio,
        );
        _finishFirstRenderTrace(
          mapId: config.id,
          result: 'success',
          config: config,
          plan: plan,
        );
        _loadingCoordinator.scheduleBackgroundTilePreload(
          config: config,
          plan: plan,
          loadImage: _loadTileImage,
        );
      }
    }
    _prerenderController.markReady(mapId);
    if (isCurrentTarget && _isCurrentDisplayReady) {
      _reportDisplayReadiness(true);
    }
  }

  bool get _isCurrentDisplayReady {
    return _settingsReady &&
        _currentConfig != null &&
        _hasRevealedInitialMap &&
        (_loadingCoordinator.initialEntryCompleted ||
            _loadingStyle == TilemapLoadingStyle.disabled) &&
        _imageError == null &&
        _mapError == null &&
        _loadingCoordinator.initialLoadError == null;
  }

  void _scheduleCurrentLocationsChanged(TilemapConfig config) {
    if (widget.onCurrentLocationsChanged == null) return;
    final locationIds =
        config.tiles
            .map((tile) => tile.locationId?.trim() ?? '')
            .where((locationId) => locationId.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final signature = '${config.id}\u001f${locationIds.join('\u001e')}';
    if (_reportedCurrentLocationsSignature == signature ||
        _scheduledCurrentLocationsSignature == signature) {
      return;
    }
    _scheduledCurrentLocationsSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scheduledCurrentLocationsSignature != signature) return;
      _scheduledCurrentLocationsSignature = '';
      if (!mounted || !_isCurrentMapId(config.id)) return;
      final callback = widget.onCurrentLocationsChanged;
      if (callback == null) return;
      _reportedCurrentLocationsSignature = signature;
      callback(config.id, Set<String>.unmodifiable(locationIds));
    });
  }

  void _reportDisplayReadiness(bool ready) {
    if (_reportedDisplayReady == ready) return;
    _reportedDisplayReady = ready;
    if (widget.onDisplayReadinessChanged == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reportedDisplayReady != ready) return;
      widget.onDisplayReadinessChanged?.call(ready);
    });
  }

  void _reportDisplayError(Object error) {
    if (widget.onDisplayError == null) return;
    final environmentGeneration = _prerenderEnvironmentGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          environmentGeneration != _prerenderEnvironmentGeneration) {
        return;
      }
      widget.onDisplayError?.call(error);
    });
  }

  int _userAvatarEnvironmentHash(UserAvatar avatar) {
    return Object.hash(
      avatar.id,
      avatar.initials,
      avatar.name,
      avatar.avatarUrl,
      avatar.isPlayerControlledRole,
      avatar.isNew,
    );
  }

  int _worldPointEnvironmentHash(WorldPoint point) {
    return Object.hashAll(<Object?>[
      point.id,
      point.name,
      point.type,
      point.position.dx,
      point.position.dy,
      point.sceneId,
      point.pointId,
      point.iconUrl,
      point.mapImageUrl,
      point.description,
      point.locationDescription,
      point.depth,
      point.isLeafLocation,
      point.isNew,
      Object.hashAll(point.users.map(_userAvatarEnvironmentHash)),
    ]);
  }

  int _locationNodeEnvironmentHash(WorldMapLocationNode node) {
    return Object.hashAll(<Object?>[
      node.id,
      _worldPointEnvironmentHash(node.point),
      node.mapImageUrl,
      node.isRoot,
      node.chatTargetPoint == null
          ? null
          : _worldPointEnvironmentHash(node.chatTargetPoint!),
      Object.hashAll(node.children.map(_locationNodeEnvironmentHash)),
    ]);
  }

  int _messageBubbleEnvironmentHash(WorldMapMessageBubble bubble) {
    return Object.hash(
      bubble.characterId,
      bubble.content,
      bubble.preservePageWidth,
    );
  }

  String _prerenderEnvironmentKey(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final renderSettings = _currentSettings.toJson()..remove('loading_style');
    return <Object?>[
      widget._source.name,
      widget._entityId,
      _cacheGeneration,
      renderSettings,
      widget.centerContentInitially,
      Object.hashAll(widget.locationNodes.map(_locationNodeEnvironmentHash)),
      _requestedPreferredFocusLocationId.isNotEmpty
          ? _requestedPreferredFocusLocationId
          : widget.preferredFocusLocationId,
      Object.hashAll(widget.messageBubbles.map(_messageBubbleEnvironmentHash)),
      widget.messageBubblePlaybackPaused,
      locale,
      textScale,
    ].join('|');
  }

  void _syncPrerenderEnvironment({
    required String environmentKey,
    required Size viewportSize,
    required double devicePixelRatio,
  }) {
    final changed =
        _configuredPrerenderEnvironmentKey != null &&
        (_configuredPrerenderEnvironmentKey != environmentKey ||
            _configuredPrerenderViewportSize != viewportSize ||
            _configuredPrerenderDevicePixelRatio != devicePixelRatio);
    _configuredPrerenderEnvironmentKey = environmentKey;
    _configuredPrerenderViewportSize = viewportSize;
    _configuredPrerenderDevicePixelRatio = devicePixelRatio;
    if (!changed) return;

    _reportDisplayReadiness(false);
    _prerenderEnvironmentGeneration += 1;
    _liveViewportReadyCallbacks.clear();
  }

  Widget _buildMapViewport(BuildContext context, Size viewportSize) {
    if (!_settingsReady) {
      return ColoredBox(
        key: const ValueKey<String>('tilemap-settings-loading-background'),
        color: tilemapVisualStyleFor(_visualMode).backgroundColor,
      );
    }
    if (_imageError != null ||
        _mapError != null ||
        _loadingCoordinator.initialLoadError != null) {
      return _TilemapError(visualMode: _visualMode, onRetry: _retry);
    }

    final config = _currentConfig;
    final showInitialLoading =
        !_loadingCoordinator.initialEntryCompleted &&
        _loadingStyle != TilemapLoadingStyle.disabled;
    final environmentKey = _prerenderEnvironmentKey(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    _syncPrerenderEnvironment(
      environmentKey: environmentKey,
      viewportSize: viewportSize,
      devicePixelRatio: devicePixelRatio,
    );
    _prerenderController.configure(
      environmentKey:
          '$environmentKey|generation=$_prerenderEnvironmentGeneration',
      activeMapId: config?.id,
      preferredMapIds: _preferredPrerenderMapIds(config),
    );

    if (config != null && showInitialLoading) {
      _loadingCoordinator.ensureInitialMapReady(
        config: config,
        plan: _imageLoadPlanForViewport(
          config: config,
          viewportSize: viewportSize,
          devicePixelRatio: devicePixelRatio,
        ),
        loadImage: _loadTileImage,
      );
    }

    final displayMapId = config?.id;
    final liveReady =
        config != null && _hasRevealedInitialMap && !showInitialLoading;
    final children = <Widget>[];

    if (!showInitialLoading) {
      final residentConfigs = _prerenderController.residentConfigs;
      for (final residentConfig in residentConfigs) {
        if (residentConfig.id == displayMapId) continue;
        children.add(
          _buildLiveRendererSurface(
            residentConfig,
            interactive: false,
            foreground: false,
            reportViewportReady: !_prerenderController.isReady(
              residentConfig.id,
            ),
          ),
        );
      }
      for (final residentConfig in residentConfigs) {
        if (residentConfig.id != displayMapId) continue;
        children.add(
          _buildLiveRendererSurface(
            residentConfig,
            interactive: residentConfig.id == displayMapId,
            foreground: true,
            reportViewportReady: !_prerenderController.isReady(
              residentConfig.id,
            ),
          ),
        );
      }
    }

    if (showInitialLoading &&
        !_hasRevealedInitialMap &&
        !_loadingCoordinator.initialEntrySkipped) {
      children.add(
        TilemapLoadingOverlay(
          style: _loadingStyle,
          progress: _loadingCoordinator.initialProgress,
          visualMode: _visualMode,
          backgroundKey: const ValueKey<String>('tilemap-loading-background'),
        ),
      );
    } else if (displayMapId == null) {
      children.add(
        ColoredBox(
          key: ValueKey<String>(
            _hasRevealedInitialMap
                ? 'tilemap-transition-background'
                : 'tilemap-loading-background',
          ),
          color: tilemapVisualStyleFor(_visualMode).backgroundColor,
        ),
      );
    }

    if (liveReady) {
      _scheduleCurrentLocationsChanged(config);
      final displayTilePixelSize =
          tilemapBaseTileExtent *
          _initialScaleForConfig(config) *
          tilemapImageDevicePixelRatio(MediaQuery.devicePixelRatioOf(context));
      _scheduleSilentDrillDownPreload(
        config,
        displayTilePixelSize: displayTilePixelSize,
      );
    }
    return Stack(fit: StackFit.expand, children: children);
  }

  @override
  Widget build(BuildContext context) {
    final exitLocationLabel =
        findWorldMapLocationNode(
          widget.locationNodes,
          _currentLocationId,
        )?.point.name ??
        '';
    final settingsButtonTop =
        widget.visualModeToggleTop ?? MediaQuery.paddingOf(context).top + 6;
    final settingsPanelMaxHeight =
        (MediaQuery.sizeOf(context).height - settingsButtonTop - 58)
            .clamp(220.0, 500.0)
            .toDouble();
    final showSettingsButton =
        widget.showVisualModeToggle &&
        tilemapSettingsButtonVisibility.value &&
        _settingsReady;
    final showSettings = showSettingsButton && _showSettings;
    return TickerMode(
      enabled: !widget.animationsPaused,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mediaSize = MediaQuery.sizeOf(context);
          final viewportSize = Size(
            constraints.hasBoundedWidth
                ? constraints.maxWidth
                : mediaSize.width,
            constraints.hasBoundedHeight
                ? constraints.maxHeight
                : mediaSize.height,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              _buildMapViewport(context, viewportSize),
              if (_locationTrail.isNotEmpty)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: widget.drillExitBottom,
                  child: WorldMapCenteredExitLocationButton(
                    buttonKey: const ValueKey<String>('tilemap-exit-location'),
                    label: exitLocationLabel,
                    maxWidth: widget.drillExitMaxWidth,
                    onPressed: _exitLocation,
                  ),
                ),
              if (showSettings)
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey<String>('tilemap-settings-dismiss'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _closeSettings,
                  ),
                ),
              if (showSettings)
                Positioned(
                  left: 0,
                  right: 0,
                  top: settingsButtonTop + 46,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: settingsPanelMaxHeight,
                    ),
                    child: _TilemapSettingsPanel(
                      visualMode: _visualMode,
                      loadingStyle: _loadingStyle,
                      fogControlPoints: _fogControlPoints,
                      blendFogWithShadowTiles: _blendFogWithShadowTiles,
                      cacheFogTileBitmaps: _cacheFogTileBitmaps,
                      showShadowZeroBorders: _showShadowZeroBorders,
                      showLocationImageFlow: _showLocationImageFlow,
                      locationImageFlowAngleDegrees:
                          _locationImageFlowAngleDegrees,
                      locationImageFlowGradientPoints:
                          _locationImageFlowGradientPoints,
                      locationImageFlowOpacity: _locationImageFlowOpacity,
                      locationImageFlowDurationSeconds:
                          _locationImageFlowDurationSeconds,
                      locationImageFlowBlendMode: _locationImageFlowBlendMode,
                      nearbyLocationDistanceTiles: _nearbyLocationDistanceTiles,
                      distantLocationDistanceTiles:
                          _distantLocationDistanceTiles,
                      nearbyLocationInitialScale: _nearbyLocationInitialScale,
                      distantLocationInitialScale: _distantLocationInitialScale,
                      dragBoundaryPaddingTiles: _dragBoundaryPaddingTiles,
                      onVisualModeChanged: _setVisualMode,
                      onLoadingStyleChanged: _setLoadingStyle,
                      onFogControlPointsChanged: _setFogControlPoints,
                      onBlendFogWithShadowTilesChanged:
                          _setBlendFogWithShadowTiles,
                      onCacheFogTileBitmapsChanged: _setCacheFogTileBitmaps,
                      onShowShadowZeroBordersChanged: _setShowShadowZeroBorders,
                      onShowLocationImageFlowChanged: _setShowLocationImageFlow,
                      onLocationImageFlowAngleDegreesChanged:
                          _setLocationImageFlowAngleDegrees,
                      onLocationImageFlowGradientPointsChanged:
                          _setLocationImageFlowGradientPoints,
                      onLocationImageFlowOpacityChanged:
                          _setLocationImageFlowOpacity,
                      onLocationImageFlowDurationSecondsChanged:
                          _setLocationImageFlowDurationSeconds,
                      onLocationImageFlowBlendModeChanged:
                          _setLocationImageFlowBlendMode,
                      onNearbyLocationDistanceChanged:
                          _setNearbyLocationDistance,
                      onDistantLocationDistanceChanged:
                          _setDistantLocationDistance,
                      onNearbyLocationInitialScaleChanged:
                          _setNearbyLocationInitialScale,
                      onDistantLocationInitialScaleChanged:
                          _setDistantLocationInitialScale,
                      onDragBoundaryPaddingTilesChanged:
                          _setDragBoundaryPaddingTiles,
                      onCopySettings: _copySettingsToClipboard,
                      onResetSettings: _resetSettings,
                      onClose: _closeSettings,
                    ),
                  ),
                ),
              if (showSettingsButton)
                Positioned(
                  right: widget.visualModeToggleRight,
                  top: settingsButtonTop,
                  child: _TilemapSettingsButton(
                    isOpen: showSettings,
                    onPressed: _toggleSettings,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
