import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_colors.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/bootstrap/service_registry.dart';
import '../../app/debug/location_chat_debug_slice.dart';
import '../../app/debug/world_new_content_debug_settings.dart';
import '../../app/recent_chat/recent_world_chat_store.dart';
import '../../app/telemetry/firebase_performance_operation.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../components/auth/login_guard.dart';
import '../../components/chat/chatroom_failure_toast.dart';
import '../../components/chat/shared/chat_ui.dart';
import '../../components/common/genesis_action_box.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../components/common/genesis_generation_wait_overlay.dart';
import '../../components/common/genesis_modal_routes.dart';
import '../../components/gems/gem_balance_prompt.dart';
import '../../components/origin/origin_role_launch_sheet.dart';
import '../../components/tilemap/tilemap_renderer.dart';
import '../../components/tilemap/tilemap_settings_store.dart';
import '../../components/world_details_shell.dart';
import '../../components/world_map.dart';
import '../../components/world_tick1_wait_dialog.dart';
import '../../network/api_client.dart';
import '../../network/chatroom/chatroom_connection_controller.dart';
import '../../network/chatroom/chatroom_models.dart';
import '../../network/chatroom/world_chatroom_service.dart';
import '../../network/api_exception.dart';
import '../../network/models/location_tree.dart';
import '../../network/models/world.dart';
import '../../ui/components/genesis_safe_area.dart';
import '../../ui/components/genesis_static_network_image.dart';
import '../../utils/api_error_message.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/genesis_image_resource.dart';
import 'world_bottom_sheet.dart';
import 'world_constants.dart';
import 'world_header.dart';
import 'world_location_chat_host.dart';
import 'world_detail_map_activity_locations.dart';
import 'world_map_bubble_candidates.dart';
import 'world_map_data.dart';
import 'world_models.dart';
import 'world_page_result.dart';
import 'world_sections.dart';
import 'world_update_push_banner.dart';
import 'world_update_push_target.dart';
import 'world_value_helpers.dart';

part 'world_page_tabs.dart';
part 'world_page_chatroom_session.dart';
part 'world_page_detail_sync.dart';
part 'world_page_tick_flow.dart';
part 'world_page_location_chat.dart';
part 'world_page_sheets.dart';
part 'world_page_layout.dart';

class WorldPage extends StatefulWidget {
  const WorldPage({
    super.key,
    required this.wid,
    this.waitForTick1 = false,
    this.initialWorldDetail,
    this.initiallyLaunched = false,
    this.initialName = '',
    this.initialLocationId = '',
    this.initialMessageToSend = '',
    this.initialMentionCatalog,
    this.initialDefinitionVersion = 0,
    this.initialMapLocationId = '',
  });

  final String wid;
  final bool waitForTick1;
  final WorldDetail? initialWorldDetail;
  final bool initiallyLaunched;
  final String initialName;
  final String initialLocationId;
  final String initialMessageToSend;
  final ChatMentionCatalog? initialMentionCatalog;
  final int initialDefinitionVersion;
  final String initialMapLocationId;

  @override
  State<WorldPage> createState() => _WorldPageState();
}

enum _WorldPageRenderStage { framework, detailShell, content }

class _WorldPageState extends State<WorldPage> with TickerProviderStateMixin {
  static const double _progressWaitAvatarSize = 88;
  static const String _progressWaitTitle = 'Progressing the World';
  static const String _progressWaitMessage =
      'Compressing recent memories\n'
      'Advancing the world timeline\n'
      'Generating the next story beat\n'
      'Updating character locations';
  static const double _worldMainSwipeSystemGestureEdgeWidth = 24;
  static const double _worldMainSwipeMinDistance = 48;
  static const double _worldMainSwipeDirectionRatio = 1.25;
  late final TabController _mainTabController;
  WorldDetail? _world;
  Object? _initialLoadError;
  _WorldPageRenderStage _renderStage = _WorldPageRenderStage.framework;
  bool _contentMountScheduled = false;
  FirebasePerformanceOperation? _initialRequestPerformanceOperation;
  FirebasePerformanceOperation? _initialRenderPerformanceOperation;
  FirebasePerformanceDataSource _initialRenderDataSource =
      FirebasePerformanceDataSource.network;
  var _initialRequestPerformanceAttempt = 0;
  var _initialContentRenderCompleted = false;
  WorldChatroomService? _worldChatroom;
  StreamSubscription<WorldChatroomState>? _worldChatroomSub;
  StreamSubscription? _worldChatroomFailureSub;
  StreamSubscription<GemBalanceAlert>? _worldChatroomBalanceSub;
  Future<void>? _worldChatroomAuthRecovery;
  Map<String, WorldLocationChatPanelDescriptor> _locationChatDescriptors =
      <String, WorldLocationChatPanelDescriptor>{};
  final _locationChatPageCache = WorldLocationChatPageCache();
  final _tilemapRestorationController = TilemapRestorationController();
  final GlobalKey _tilemapImplementationKey = GlobalKey(
    debugLabel: 'world-detail-tilemap',
  );
  TilemapVisualMode _tilemapVisualMode = tilemapVisualModeController.value;
  late final Future<void> _tilemapVisualModeLoad;
  bool _tilemapVisualModeReady = false;
  final Set<String> _preloadedLocationMessageIds = <String>{};
  final Map<String, Future<void>> _preloadingLocationMessageFutures =
      <String, Future<void>>{};
  String _activeChatLocationId = '';
  String _pendingLocationChatLeaveId = '';
  late String _pendingInitialLocationId;
  late bool _initialLocationChatEntry;
  late bool _locationChatTransitionsEnabled;
  bool _tilemapDisplayReady = false;
  Object? _tilemapDisplayError;
  bool _coverTilemapAfterInitialChat = false;
  bool _pollInFlight = false;
  bool _worldActionRunning = false;
  bool _worldTickInProgress = false;
  int _worldTickProgressFailureRevision = 0;
  bool _worldTickWaitOverlayRequested = false;
  bool _openEventsAfterTickDone = false;
  bool _eventsUnread = false;
  bool _worldBottomSheetOpen = false;
  bool _hasUnreadNewUserJoin = false;
  bool _openEventsAfterCurrentBottomSheetClosed = false;
  int? _eventsAfterCurrentBottomSheetClosedTargetTickNumber;
  BuildContext? _worldBottomSheetContext;
  int _worldMainTabIndex = 0;
  int? _worldMainSwipePointer;
  Offset? _worldMainSwipeStartPosition;
  bool _worldMainSwipeStartCanMapScrollLeft = false;
  bool _worldMainSwipeStartCanMapScrollRight = false;
  bool _worldMapCanScrollLeft = false;
  bool _worldMapCanScrollRight = false;
  bool _mapBubbleMessagesReady = false;
  int _eventsLatestRevision = 0;
  int? _eventsTargetTickNumber;
  int _lastAppliedNewUserJoinRevision = 0;
  int _lastAppliedMapUpdatedRevision = 0;
  int _lastAppliedContentUpdateNoticeRevision = 0;
  int _tilemapReloadRevision = 0;
  List<WorldContentUpdateNotice> _contentUpdateNotices =
      const <WorldContentUpdateNotice>[];
  WorldNewUserJoinNotice? _pendingNewUserJoinNotice;
  bool _tick1WaitDialogStarted = false;
  bool? _lastChatroomInputBlocked;
  bool _worldTickDoneHandling = false;
  bool _worldTickLockPollInFlight = false;
  int _worldTickLockPollingGeneration = 0;
  Timer? _worldTickLockPollingTimer;
  int _lastAppliedChatroomWorldProgressRevision = 0;
  WorldChatroomState? _deferredBottomSheetMapChatroomState;
  List<WorldMapBubbleCandidate> _mapBubbleCandidates =
      const <WorldMapBubbleCandidate>[];
  int? _pendingProgressTickCount;
  var _currentUid = '';
  var _currentUidRequested = false;
  Future<void>? _currentUidLoad;
  Set<String> _recentChatLocationIds = const <String>{};
  Set<String> _recentChatLocationPathIds = const <String>{};
  bool _recentChatInitializedFromDetail = false;
  bool _recentChatStoreUpdatesEnabled = false;
  bool _hasRecentChatSessionOverride = false;
  Set<String> _currentTickEventLocationPathIds = const <String>{};
  var _locationChatDescriptorSignature = '';
  late final ValueNotifier<WorldDetail?> _sectionsWorldNotifier =
      ValueNotifier<WorldDetail?>(_world);
  late final ValueNotifier<WorldBottomSheetSelection>
  _worldBottomSheetSelection = ValueNotifier<WorldBottomSheetSelection>(
    const WorldBottomSheetSelection(
      kind: WorldBottomSheetKind.detail,
      eventsLatestRevision: 0,
    ),
  );
  final ValueNotifier<List<WorldNewUserJoinNotice>>
  _newUserJoinNoticesNotifier = ValueNotifier<List<WorldNewUserJoinNotice>>(
    const <WorldNewUserJoinNotice>[],
  );
  final _sectionsEventsCache = WorldSectionsEventsCache();
  static const _worldTickLockPollInterval = Duration(seconds: 10);

  void _setWorldPageState(VoidCallback callback) {
    setState(callback);
  }

  Widget _buildWorldLocationChatHost() {
    return WorldLocationChatRouterHost(
      worldId: widget.wid,
      chatroom: _worldChatroom,
      worldTickInProgress: _worldTickInProgress,
      worldTickProgressFailureRevision: _worldTickProgressFailureRevision,
      cache: _locationChatPageCache,
      onBack: _closeCachedLocationChat,
      onOverlayDismissed: _completePendingLocationChatLeave,
      onCharactersMovedLocationTap: (movement) =>
          unawaited(_openCharactersMovedTargetLocation(movement)),
      animateTransitions: _locationChatTransitionsEnabled,
      isMessageQueueInitializationCovered: (locationId) {
        final resolvedLocationId = locationId.trim();
        return _preloadedLocationMessageIds.contains(resolvedLocationId) ||
            _preloadingLocationMessageFutures.containsKey(resolvedLocationId);
      },
      onPanelReady: (locationId) {
        final becameReady = _locationChatPageCache.markReady(locationId);
        _recordWorldLocationChatDebug(
          action: 'panelReady',
          locationId: locationId,
        );
        if (mounted && becameReady) setState(() {});
      },
    );
  }

  Widget _buildInitialLocationChatPage({Widget? background}) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleWorldPopBlocked();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handleWorldMainSwipePointerDown,
        onPointerUp: _handleWorldMainSwipePointerUp,
        onPointerCancel: _handleWorldMainSwipePointerCancel,
        child: Stack(
          children: [
            Positioned.fill(
              child:
                  background ??
                  ColoredBox(color: _tilemapLoadingBackgroundColor),
            ),
            Positioned.fill(
              key: const ValueKey<String>('world-location-chat-host-layer'),
              child: _buildWorldLocationChatHost(),
            ),
          ],
        ),
      ),
    );
  }

  Color get _tilemapLoadingBackgroundColor =>
      tilemapVisualStyleFor(_tilemapVisualMode).backgroundColor;

  Future<void> _loadTilemapVisualMode() async {
    try {
      await const TilemapSettingsStore().load().timeout(
        const Duration(seconds: 2),
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[WorldPage] tilemap settings load failed: $error');
      }
    } finally {
      _tilemapVisualModeReady = true;
    }
  }

  void _handleTilemapVisualModeChanged() {
    final visualMode = tilemapVisualModeController.value;
    if (!mounted || _tilemapVisualMode == visualMode) return;
    setState(() => _tilemapVisualMode = visualMode);
  }

  void _scheduleInitialWorldLoadAfterFrameworkFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initialWorld = widget.initialWorldDetail;
      if (initialWorld != null) {
        _initialRenderDataSource = FirebasePerformanceDataSource.prefetched;
        _applyWorldDetail(initialWorld, clearInitialLoadError: true);
        _maybeShowTick1WaitDialog();
        return;
      }
      unawaited(
        _fetchWorld(isInitial: true).then((_) {
          if (mounted) _maybeShowTick1WaitDialog();
        }),
      );
    });
  }

  void _scheduleContentMountAfterDetailShellFrame() {
    if (_renderStage != _WorldPageRenderStage.detailShell ||
        _contentMountScheduled) {
      return;
    }
    _contentMountScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _world == null ||
          _renderStage != _WorldPageRenderStage.detailShell) {
        _contentMountScheduled = false;
        return;
      }
      if (_world?.definitionVersion != 2 ||
          _tilemapVisualModeReady ||
          tilemapVisualModeController.isHydrated) {
        unawaited(_mountContentAfterDetailShell());
        return;
      }
      unawaited(_mountContentAfterTilemapVisualModeLoad());
    });
  }

  Future<void> _mountContentAfterTilemapVisualModeLoad() async {
    if (_world?.definitionVersion == 2) {
      await _tilemapVisualModeLoad;
    }
    await _mountContentAfterDetailShell();
  }

  Future<void> _mountContentAfterDetailShell() async {
    if (!mounted ||
        _world == null ||
        _renderStage != _WorldPageRenderStage.detailShell) {
      _contentMountScheduled = false;
      return;
    }
    final world = _world!;
    await _currentUidLoad;
    if (!mounted ||
        !identical(_world, world) ||
        _renderStage != _WorldPageRenderStage.detailShell) {
      _contentMountScheduled = false;
      return;
    }
    await _precacheCurrentWorldFooterAvatar(world);
    if (!mounted ||
        !identical(_world, world) ||
        _renderStage != _WorldPageRenderStage.detailShell) {
      _contentMountScheduled = false;
      return;
    }
    FirebasePerformanceOperation? renderOperation;
    if (!_initialContentRenderCompleted &&
        _initialRenderPerformanceOperation == null) {
      renderOperation = await FirebasePerformanceOperation.start(
        surface: FirebasePerformanceSurface.worldPage,
        phase: FirebasePerformancePhase.render,
        attempt: _initialRequestPerformanceAttempt == 0
            ? 1
            : _initialRequestPerformanceAttempt,
        dataSource: _initialRenderDataSource,
        timeout: FirebasePerformanceOperation.renderTimeout,
      );
      if (!mounted ||
          !identical(_world, world) ||
          _renderStage != _WorldPageRenderStage.detailShell) {
        unawaited(renderOperation.cancel());
        _contentMountScheduled = false;
        return;
      }
      _initialRenderPerformanceOperation = renderOperation;
    }
    setState(() {
      _contentMountScheduled = false;
      _renderStage = _WorldPageRenderStage.content;
    });
    if (renderOperation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !identical(_initialRenderPerformanceOperation, renderOperation) ||
            !identical(_world, world) ||
            _renderStage != _WorldPageRenderStage.content) {
          if (identical(_initialRenderPerformanceOperation, renderOperation)) {
            _initialRenderPerformanceOperation = null;
          }
          unawaited(renderOperation?.cancel());
          return;
        }
        _initialRenderPerformanceOperation = null;
        _initialContentRenderCompleted = true;
        unawaited(renderOperation?.succeed());
      });
    }
  }

  @override
  void initState() {
    super.initState();
    recentWorldChatStore.listenable.addListener(
      _handleRecentWorldChatStoreChanged,
    );
    worldNewContentDebugSettings.listenable.addListener(
      _handleWorldNewContentDebugSettingsChanged,
    );
    tilemapVisualModeController.addListener(_handleTilemapVisualModeChanged);
    _tilemapVisualModeLoad = _loadTilemapVisualMode();
    _pendingInitialLocationId = widget.initialLocationId.trim();
    _locationChatPageCache.queueInitialMessageToSend(
      _pendingInitialLocationId,
      widget.initialMessageToSend,
      mentionCatalog: widget.initialMentionCatalog,
    );
    _initialLocationChatEntry = _pendingInitialLocationId.isNotEmpty;
    _locationChatTransitionsEnabled = !_initialLocationChatEntry;
    _mainTabController = TabController(length: worldMainPageCount, vsync: this);
    _mainTabController.addListener(_handleWorldMainTabChanged);
    _worldBottomSheetSelection.addListener(
      _handleWorldBottomSheetSelectionChanged,
    );
    _syncWorldStatusBarForMainTab();
    if (_initialLocationChatEntry) {
      final descriptor = WorldLocationChatPanelDescriptor(
        locationId: _pendingInitialLocationId,
        locationName: 'Location',
        backgroundImageUrl: '',
        backgroundPreviewImageUrl: '',
        isLeafLocation: true,
        localMessageLocationIds: <String>[_pendingInitialLocationId],
        recentChatLocationPathIds: <String>[_pendingInitialLocationId],
      );
      _locationChatDescriptors = <String, WorldLocationChatPanelDescriptor>{
        descriptor.locationId: descriptor,
      };
      _locationChatPageCache.syncDescriptors(_locationChatDescriptors);
      _locationChatPageCache.activate(descriptor);
      _locationChatPageCache.markReady(descriptor.locationId);
      _activeChatLocationId = descriptor.locationId;
      _startWorldChatroom();
      WorldDetailsStatusBarOverride.setStyle(
        kChatDarkHeaderSystemUiOverlayStyle,
      );
    }
    _scheduleInitialWorldLoadAfterFrameworkFrame();
  }

  @override
  void reassemble() {
    super.reassemble();
    unawaited(_fetchWorld());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_currentUidRequested) {
      _currentUidRequested = true;
      final currentUidLoad = _loadCurrentUid();
      _currentUidLoad = currentUidLoad;
      unawaited(currentUidLoad);
    }
  }

  @override
  void dispose() {
    unawaited(_initialRequestPerformanceOperation?.cancel());
    unawaited(_initialRenderPerformanceOperation?.cancel());
    _stopWorldTickLockPolling();
    worldNewContentDebugSettings.listenable.removeListener(
      _handleWorldNewContentDebugSettingsChanged,
    );
    tilemapVisualModeController.removeListener(_handleTilemapVisualModeChanged);
    recentWorldChatStore.listenable.removeListener(
      _handleRecentWorldChatStoreChanged,
    );
    _mainTabController.removeListener(_handleWorldMainTabChanged);
    _worldBottomSheetSelection.removeListener(
      _handleWorldBottomSheetSelectionChanged,
    );
    WorldDetailsStatusBarOverride.clearStyle();
    unawaited(_worldChatroomSub?.cancel());
    unawaited(_worldChatroomFailureSub?.cancel());
    unawaited(_worldChatroomBalanceSub?.cancel());
    final chatroom = _worldChatroom;
    _worldChatroom = null;
    if (chatroom != null) {
      unawaited(_disposeWorldChatroom(chatroom));
    }
    _mainTabController.dispose();
    _sectionsEventsCache.clear();
    _locationChatPageCache.dispose();
    _tilemapRestorationController.dispose();
    _sectionsWorldNotifier.dispose();
    _worldBottomSheetSelection.removeListener(
      _handleWorldBottomSheetSelectionChanged,
    );
    _worldBottomSheetSelection.dispose();
    _newUserJoinNoticesNotifier.dispose();
    super.dispose();
  }

  void _handleWorldNewContentDebugSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = GenesisSafeAreaInsets.top(context);
    final world = _world;
    if (world == null) {
      if (_initialLocationChatEntry) {
        return _buildInitialLocationChatPage();
      }
      if (_initialLoadError != null) {
        return Scaffold(
          backgroundColor: GenesisColors.darkBackground,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Load failed',
                  style: TextStyle(color: GenesisColors.darkTextSecondary),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () => _fetchWorld(isInitial: true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      }
      return _buildInitialLoadingScaffold(
        topPadding,
        world: widget.initialWorldDetail,
        assumeLaunched: widget.initiallyLaunched,
      );
    }
    if (_renderStage != _WorldPageRenderStage.content) {
      _scheduleContentMountAfterDetailShellFrame();
      final loadingScaffold = _buildInitialLoadingScaffold(
        topPadding,
        world: world,
      );
      if (_activeChatLocationId.isNotEmpty) {
        return _buildInitialLocationChatPage(background: loadingScaffold);
      }
      return loadingScaffold;
    }

    final avatarsByLocation = worldAvatarsByLocationFromCharacterPositions(
      world.characterPositions,
      currentUid: _currentUid,
    );
    final processedLocationTree = world.processedLocationTree;
    final preferredInitialMapLocationId =
        world.definitionVersion == 2 &&
            widget.initialDefinitionVersion == world.definitionVersion
        ? widget.initialMapLocationId
        : '';
    final initialTilemapLocationId = processedLocationTree
        .initialTilemapLocationId(
          syntheticRootId: worldSyntheticRootLocationId,
          preferredLocationId: preferredInitialMapLocationId,
        );
    final rootLocationNodes = processedLocationTree.initialMapDisplayRoots;
    final rootMapImageUrl = _rootMapImageUrlForWorld(world);
    final renderLocationNodes = processedLocationTree.initialMapRenderRoots;
    final allLocationNodes = processedLocationTree.flattened;
    final locationNodes = worldMapLocationNodes(
      rootLocationNodes,
      avatarsByLocation,
      processedLocationTree,
    );
    final listLocationNodes = worldMapLocationNodes(
      processedLocationTree.mapRoots,
      avatarsByLocation,
      processedLocationTree,
    );
    WorldPoint? contentUpdatePushTarget(WorldContentUpdateNotice notice) {
      return resolveWorldUpdatePushChatTarget(
        notice: notice,
        world: world,
        locationNodes: listLocationNodes,
      );
    }

    final points = renderLocationNodes.isNotEmpty
        ? worldPointsFromLocationNodes(
            renderLocationNodes,
            avatarsByLocation,
            processedLocationTree,
          )
        : world.locations.isNotEmpty
        ? worldPointsFromLocations(
            worldRootWorldLocations(world.locations),
            avatarsByLocation,
          )
        : worldPointsFromLocationIds(
            world.characterPositions
                .map((e) => e['location_id'])
                .followedBy(world.userPositions.map((e) => e['location_id']))
                .toList(growable: false),
            avatarsByLocation,
          );
    final listPoints = allLocationNodes.isNotEmpty
        ? worldPointsFromLocationNodes(
            allLocationNodes,
            avatarsByLocation,
            processedLocationTree,
          )
        : world.locations.isNotEmpty
        ? worldPointsFromLocations(world.locations, avatarsByLocation)
        : points;
    final recentMapLocationIds = _recentChatLocationPathIds;
    final eventMapLocationIds = _currentTickEventLocationPathIds;
    final collapsedPanelHeight = worldCollapsedPanelHeightFor(
      context,
      world: world,
    );
    Widget buildWorldMapPage(int tabIndex, {required bool pointMode}) {
      final preparingInitialTilemap =
          _initialLocationChatEntry && _activeChatLocationId.isNotEmpty;
      final mapPausedForLocationChat =
          _activeChatLocationId.isNotEmpty && !preparingInitialTilemap;
      final Widget map = WorldMap.world(
        definitionVersion: world.definitionVersion,
        worldId: widget.wid,
        common: WorldMapCommonConfig(
          locationNodes: locationNodes,
          messageBubbles:
              (_activeChatLocationId.isEmpty || preparingInitialTilemap) &&
                  _mapBubbleMessagesReady
              ? _mapMessageBubbles
              : const <WorldMapMessageBubble>[],
          messageBubblePlaybackPaused: mapPausedForLocationChat,
          onDrillIntoLocation: _showMapTab,
          onMapTap: _recordWorldMapClick,
          onPointTap: _openChatForPoint,
          drillExitBottom: collapsedPanelHeight + 12,
        ),
        legacy: LegacyWorldMapConfig(
          implementationKey: PageStorageKey<String>('world-map-tab-$tabIndex'),
          points: points,
          listPoints: listPoints,
          listLocationNodes: listLocationNodes,
          mapImageUrl: rootMapImageUrl,
          dimmed: pointMode,
          showPointsList: pointMode,
          recentChatLocationIds: _recentChatLocationIds,
          recentChatMapLocationIds: recentMapLocationIds,
          eventMapLocationIds: eventMapLocationIds,
          initialZoomScale: pointMode ? 1 : 1.2,
          zoomControlBottom: collapsedPanelHeight + 12,
          pointsListOuterScrollHandoff: false,
          overlayTop:
              topPadding +
              8 +
              (pointMode ? worldMapTabsHeight + 8 : worldMapContentTopOffset),
          drillExitMaxWidth: worldSecondaryMapControlWidth,
          onHorizontalPanStateChanged: tabIndex == 0
              ? _handleWorldMapHorizontalPanStateChanged
              : null,
        ),
        tilemap: WorldMapTilemapOptions(
          implementationKey: _tilemapImplementationKey,
          locationId: initialTilemapLocationId,
          locationNodes: listLocationNodes,
          centerContentInitially: true,
          recentChatLocationIds: recentMapLocationIds,
          eventLocationIds: eventMapLocationIds,
          animationsPaused: _worldBottomSheetOpen || mapPausedForLocationChat,
          reloadRevision: _tilemapReloadRevision,
          visualModeToggleTop:
              topPadding + worldMapBackButtonTop + worldMapTabsHeight + 8,
          visualModeToggleRight: worldMapTopBarRightInset,
          // Clear of the floating Info card and bubble.
          zoomControlBottom: collapsedPanelHeight + 12,
          restorationController: _tilemapRestorationController,
          onMapTap: _recordWorldTilemapClick,
          onDisplayReadinessChanged: _handleTilemapDisplayReadinessChanged,
          onDisplayError: _handleTilemapDisplayError,
          onCurrentLocationsChanged: _handleCurrentTilemapLocationsChanged,
        ),
      );
      return WorldKeepAlivePage(
        child: Stack(
          fit: StackFit.expand,
          children: [
            map,
            if (_coverTilemapAfterInitialChat &&
                !_tilemapDisplayReady &&
                _tilemapDisplayError == null)
              ColoredBox(
                key: const ValueKey<String>(
                  'world-initial-tilemap-static-cover',
                ),
                color: _tilemapLoadingBackgroundColor,
              ),
          ],
        ),
      );
    }

    final canShowWorldTickProgress =
        _worldChatroom != null ||
        shouldConnectWorldChatroom(world.relationStatus);
    return PopScope(
      canPop: _activeChatLocationId.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleWorldPopBlocked();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handleWorldMainSwipePointerDown,
        onPointerUp: _handleWorldMainSwipePointerUp,
        onPointerCancel: _handleWorldMainSwipePointerCancel,
        child: Stack(
          children: [
            // The map runs to the bottom edge; the Info card and the bubble
            // float over it instead of sitting in a panel below.
            WorldDetailsPageScaffold(
              backgroundColor: _tilemapLoadingBackgroundColor,
              panelBackgroundColor: GenesisColors.darkBackground,
              panelTopGap: 0,
              scrollPhysics: const NeverScrollableScrollPhysics(),
              persistentTopOverlay: _buildPersistentMapOverlay(
                topPadding,
                world: world,
                worldTime: world.currentTime,
                tickIndex: world.tickCount,
                subTickNo: world.subTickNo,
              ),
              map: buildWorldMapPage(0, pointMode: false),
              fixedCollapsedPanelHeight: 0,
              fixedCollapsedPanelHeightIncludesBottomSafeArea: true,
              contentBottomPaddingOverride: 0,
              slivers: const <Widget>[],
            ),
            if (_worldMainTabIndex != 0)
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: topPadding,
                child: const ColoredBox(color: GenesisColors.darkBackground),
              ),
            if (_worldMainTabIndex != 0)
              Positioned(
                left: worldMapBackButtonLeft,
                top: topPadding + worldMapBackButtonTop,
                child: WorldMapBackButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            _buildWorldFloatingOverlay(
              card: WorldFeedContent(
                world: world,
                currentUid: _currentUid,
                worldActionRunning: _worldActionRunning,
                onWorldAction: _runWorldAction,
                onPullUp: () =>
                    _openWorldBottomSheet(WorldBottomSheetKind.info),
              ),
              interactive: true,
            ),
            Positioned.fill(
              key: const ValueKey<String>('world-location-chat-host-layer'),
              child: _buildWorldLocationChatHost(),
            ),
            if (canShowWorldTickProgress &&
                _worldTickInProgress &&
                _worldTickWaitOverlayRequested &&
                _activeChatLocationId.isEmpty &&
                _locationChatPageCache.activeLocationId.isEmpty)
              Positioned.fill(
                child: GenesisGenerationWaitOverlay(
                  title: _progressWaitTitle,
                  message: _progressWaitMessage,
                  brightness: Brightness.dark,
                  characterAvatars: _progressWaitAvatarsFromWorld(_world),
                  onBackPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            WorldUpdatePushBannerQueue(
              top: topPadding + 8,
              revision: _lastAppliedContentUpdateNoticeRevision,
              notices: _contentUpdateNotices,
              canShowNotice: (notice) =>
                  contentUpdatePushTarget(notice) != null,
              onNoticeTap: (notice) {
                final target = contentUpdatePushTarget(notice);
                if (target == null) return;
                unawaited(_openChatForPoint(target));
              },
            ),
          ],
        ),
      ),
    );
  }
}
