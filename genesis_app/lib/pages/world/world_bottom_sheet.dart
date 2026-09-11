import '../../ui/components/genesis_dark_close_button.dart';
// ignore_for_file: use_key_in_widget_constructors

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_colors.dart';
import '../../ui/tokens/genesis_typography.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/bootstrap/service_registry.dart';
import '../../app/debug/world_new_content_debug_settings.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../components/world_map.dart';
import '../../network/models/location_tree.dart';
import '../../network/models/world.dart';
import '../../ui/components/genesis_edge_swipe_back.dart';
import '../../ui/tokens/genesis_radii.dart';
import '../../ui/components/genesis_map_top_glass_bar.dart';
import 'world_constants.dart';
import 'world_header.dart';
import 'world_map_data.dart';
import 'world_models.dart';
import 'world_sections.dart';

/// The section bar, one button per sheet page. At rest it sits inside Info's
/// glass card; once a sheet is raised it rides on top of it.
class WorldFloatingBubble extends StatelessWidget {
  const WorldFloatingBubble({
    super.key,
    required this.selected,
    required this.onSelected,
    this.eventsUnread = false,
    this.showDetailUnreadDot = false,
  });

  final WorldBottomSheetKind selected;
  final ValueChanged<WorldBottomSheetKind> onSelected;
  final bool eventsUnread;
  final bool showDetailUnreadDot;

  @override
  Widget build(BuildContext context) {
    // No glass of its own: the card or the sheet under it provides the surface.
    return DecoratedBox(
      key: const ValueKey<String>('world-bubble-surface'),
      decoration: BoxDecoration(
        color: worldBubbleFillColor,
        borderRadius: BorderRadius.circular(worldBubbleRadius),
      ),
      child: SizedBox(
        height: worldBubbleHeight,
        child: Padding(
          padding: const EdgeInsets.all(worldBubbleInnerPadding),
          child: Row(
            children: [
              for (final item in worldBottomTagItems)
                Expanded(
                  child: WorldBubbleButton(
                    item: item,
                    selected: item.kind == selected,
                    showUnreadDot:
                        eventsUnread &&
                            item.kind == WorldBottomSheetKind.events ||
                        showDetailUnreadDot &&
                            item.kind == WorldBottomSheetKind.detail,
                    onTap: () => onSelected(item.kind),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorldBubbleButton extends StatelessWidget {
  const WorldBubbleButton({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    this.showUnreadDot = false,
  });

  final WorldBottomTagItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool showUnreadDot;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? GenesisColors.darkTextPrimary
        : GenesisColors.darkTextSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey<String>('world-bubble-${item.label.toLowerCase()}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? const Color(0x1FFFFFFF) : const Color(0x00FFFFFF),
            // Concentric with the bar: its radius less the inner padding.
            borderRadius: BorderRadius.circular(
              worldBubbleRadius - worldBubbleInnerPadding,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildIcon(color),
                  if (showUnreadDot)
                    Positioned(
                      key: item.kind == WorldBottomSheetKind.events
                          ? const ValueKey('world-events-unread-dot')
                          : null,
                      top: -1,
                      right: -3,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: GenesisColors.redPrimary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: GenesisTypography.fontFamily,
                  fontFamilyFallback: GenesisTypography.fontFamilyFallback,
                  color: color,
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(Color color) {
    final asset = item.asset;
    if (asset != null) {
      return SvgPicture.asset(
        asset,
        width: 20,
        height: 20,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return Icon(item.icon, size: 20, color: color);
  }
}

class WorldSingleSectionBottomSheet extends StatefulWidget {
  const WorldSingleSectionBottomSheet({
    super.key,
    required this.selectionListenable,
    required this.services,
    required this.initialWorld,
    required this.worldListenable,
    required this.newUserJoinNoticesListenable,
    required this.eventsCache,
    required this.currentUid,
    required this.recentChatLocationIds,
    required this.onLocationTap,
    this.onDeleteWorld,
    this.bottomReservedHeight = 0,
    required this.infoBuilder,
  });

  final ValueNotifier<WorldBottomSheetSelection> selectionListenable;
  final AppServices services;
  final WorldDetail initialWorld;
  final ValueListenable<WorldDetail?> worldListenable;
  final ValueListenable<List<WorldNewUserJoinNotice>>
  newUserJoinNoticesListenable;
  final WorldSectionsEventsCache eventsCache;
  final String currentUid;
  final Set<String> recentChatLocationIds;
  final ValueChanged<WorldPoint> onLocationTap;
  final Future<void> Function(BuildContext context, WorldDetail world)?
  onDeleteWorld;

  /// Space kept clear under the pages for chrome floating over the sheet.
  final double bottomReservedHeight;

  /// Builds the Info row; the page owns its live action state.
  final Widget Function(BuildContext context, WorldDetail world) infoBuilder;

  @override
  State<WorldSingleSectionBottomSheet> createState() =>
      WorldSingleSectionBottomSheetState();
}

class WorldSingleSectionBottomSheetState
    extends State<WorldSingleSectionBottomSheet> {
  static const int _eventsPageSize = 20;
  static const double _extentUpdateEpsilon = 0.001;
  // Collapse once the sheet's top edge has crossed the middle of the screen.
  static const double _collapseSnapThreshold = 0.5;
  static const double _minimumDownwardFlingVelocity = 650;
  static const double _verticalFlingDirectionRatio = 1.2;
  static const _snapAnimationDuration = Duration(milliseconds: 260);

  late final DraggableScrollableController _sheetController;
  late final PageController _pageController;
  late final List<ScrollController> _previewScrollControllers;
  var _changingPageFromSelection = false;

  /// 0 while the sheet sits at Info's resting card, 1 fully raised.
  final ValueNotifier<double> _raise = ValueNotifier<double>(0);
  var _closing = false;
  var _sheetHostHeight = 1.0;
  var _sheetMinChildSize = 0.08;
  var _sheetMaxChildSize = 1.0;
  VelocityTracker? _sheetPointerVelocityTracker;
  int? _sheetPointer;
  double? _sheetPointerStartExtent;
  WorldLocationListData? _cachedLocationListData;
  ProcessedLocationTree<Map<String, dynamic>>? _cachedProcessedLocationTree;
  List<Map<String, dynamic>>? _cachedLocations;
  List<Map<String, dynamic>>? _cachedCharacterPositions;
  List<Map<String, dynamic>>? _cachedUserPositions;
  String _cachedLocationListCurrentUid = '';

  WorldDetail get _currentWorld =>
      widget.worldListenable.value ?? widget.initialWorld;

  WorldBottomSheetSelection get _selection => widget.selectionListenable.value;

  WorldSectionsEventsCache get _eventsCache => widget.eventsCache;

  @override
  void initState() {
    super.initState();
    _sheetController = DraggableScrollableController();
    _sheetController.addListener(_syncRaise);
    _pageController = PageController(
      initialPage: _pageForKind(_selection.kind),
    );
    _previewScrollControllers = List<ScrollController>.generate(
      worldBottomTagItems.length,
      (_) => ScrollController(),
    );
    widget.worldListenable.addListener(_handleWorldDetailChanged);
    widget.selectionListenable.addListener(_handleSelectionChanged);
    widget.newUserJoinNoticesListenable.addListener(
      _handleNewUserJoinNoticesChanged,
    );
    worldNewContentDebugSettings.listenable.addListener(
      _handleWorldNewContentDebugSettingsChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _riseToFull());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isEventsSheet) {
      _ensureEventsForCurrentWorld(forceFirstPageRefresh: true);
    }
  }

  @override
  void didUpdateWidget(covariant WorldSingleSectionBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.worldListenable != widget.worldListenable) {
      oldWidget.worldListenable.removeListener(_handleWorldDetailChanged);
      widget.worldListenable.addListener(_handleWorldDetailChanged);
    }
    if (oldWidget.selectionListenable != widget.selectionListenable) {
      oldWidget.selectionListenable.removeListener(_handleSelectionChanged);
      widget.selectionListenable.addListener(_handleSelectionChanged);
    }
    if (oldWidget.newUserJoinNoticesListenable !=
        widget.newUserJoinNoticesListenable) {
      oldWidget.newUserJoinNoticesListenable.removeListener(
        _handleNewUserJoinNoticesChanged,
      );
      widget.newUserJoinNoticesListenable.addListener(
        _handleNewUserJoinNoticesChanged,
      );
    }
    if (_isEventsSheet &&
        (oldWidget.eventsCache != widget.eventsCache ||
            oldWidget.selectionListenable.value.kind != _selection.kind)) {
      _ensureEventsForCurrentWorld(forceFirstPageRefresh: true);
    }
  }

  @override
  void dispose() {
    widget.worldListenable.removeListener(_handleWorldDetailChanged);
    widget.selectionListenable.removeListener(_handleSelectionChanged);
    widget.newUserJoinNoticesListenable.removeListener(
      _handleNewUserJoinNoticesChanged,
    );
    worldNewContentDebugSettings.listenable.removeListener(
      _handleWorldNewContentDebugSettingsChanged,
    );
    _sheetController
      ..removeListener(_syncRaise)
      ..dispose();
    _raise.dispose();
    _pageController.dispose();
    for (final controller in _previewScrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _isEventsSheet => _selection.kind == WorldBottomSheetKind.events;

  void _handleWorldDetailChanged() {
    if (_isEventsSheet) {
      _ensureEventsForCurrentWorld();
    }
    if (mounted) setState(() {});
  }

  void _handleWorldNewContentDebugSettingsChanged() {
    _cachedLocationListData = null;
    _cachedProcessedLocationTree = null;
    _cachedLocations = null;
    _cachedCharacterPositions = null;
    _cachedUserPositions = null;
    _cachedLocationListCurrentUid = '';
    if (mounted) setState(() {});
  }

  void _handleNewUserJoinNoticesChanged() {
    if (_selection.kind != WorldBottomSheetKind.detail) return;
    if (mounted) setState(() {});
  }

  void _handleSelectionChanged() {
    if (_isEventsSheet) {
      _ensureEventsForCurrentWorld(forceFirstPageRefresh: true);
    }
    _animateToSelectionPage();
    if (mounted) setState(() {});
  }

  int _pageForKind(WorldBottomSheetKind kind) {
    final index = worldBottomTagItems.indexWhere((item) => item.kind == kind);
    return index < 0 ? 0 : index;
  }

  WorldBottomSheetKind _kindForPage(int page) {
    if (page < 0 || page >= worldBottomTagItems.length) {
      return WorldBottomSheetKind.info;
    }
    return worldBottomTagItems[page].kind;
  }

  void _animateToSelectionPage() {
    if (!_pageController.hasClients) return;
    final targetPage = _pageForKind(_selection.kind);
    final currentPage =
        _pageController.page?.round() ?? _pageController.initialPage;
    if (currentPage == targetPage) return;
    _changingPageFromSelection = true;
    unawaited(
      _pageController
          .animateToPage(
            targetPage,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _changingPageFromSelection = false),
    );
  }

  /// Every opening starts from Info's resting card and grows to full height.
  Future<void> _riseToFull() async {
    if (!mounted || _closing) return;
    await _animateSheetTo(_sheetMaxChildSize);
  }

  void _syncRaise() => _raise.value = _raisedFraction;

  void _handleSheetPageChanged(int page) {
    if (_changingPageFromSelection) return;
    final kind = _kindForPage(page);
    if (_selection.kind == kind) return;
    GenesisTelemetry.collectLog(
      actionType: 'pageview',
      action: worldBottomSheetPageName(kind),
      object1: _currentWorld.worldId,
    );
    widget.selectionListenable.value = WorldBottomSheetSelection(
      kind: kind,
      eventsLatestRevision: _selection.eventsLatestRevision,
    );
  }

  void _ensureEventsForCurrentWorld({bool forceFirstPageRefresh = false}) {
    final worldId = _currentWorld.worldId;
    if (_eventsCache.worldId != worldId) {
      _eventsCache.reset(worldId);
      unawaited(_loadEventsPage(1));
      return;
    }
    if (forceFirstPageRefresh) {
      unawaited(_loadEventsPage(1, force: true));
      return;
    }
    if (_eventsCache.ticks.isEmpty) {
      unawaited(_loadEventsPage(1));
    }
  }

  void _mutateEventsCache(VoidCallback update) {
    if (!mounted) {
      update();
      return;
    }
    setState(update);
  }

  bool get _eventsHasMore {
    if (_eventsCache.total <= 0) return false;
    if (_eventsCache.ticks.length >= _eventsCache.total) return false;
    if (_eventsCache.page <= 0) return true;
    return _eventsCache.page * _eventsPageSize < _eventsCache.total;
  }

  void _loadNextEventsPage() {
    if (!_eventsHasMore ||
        _eventsCache.loadingMore ||
        _eventsCache.initialLoading) {
      return;
    }
    unawaited(_loadEventsPage(_eventsCache.page + 1));
  }

  Future<void> _loadEventsPage(int page, {bool force = false}) async {
    if (page <= 0) return;
    if (page == 1) {
      if (_eventsCache.initialLoading && !force) return;
      _mutateEventsCache(() {
        _eventsCache.initialLoading = true;
        _eventsCache.error = null;
      });
    } else {
      if (_eventsCache.loadingMore || !_eventsHasMore) return;
      _mutateEventsCache(() => _eventsCache.loadingMore = true);
    }

    final worldId = _currentWorld.worldId;
    try {
      final response = await widget.services.api.getWorldTicks(
        wid: worldId,
        limit: _eventsPageSize,
        offset: (page - 1) * _eventsPageSize,
      );
      if (worldId != _eventsCache.worldId) return;
      if (mounted && worldId != _currentWorld.worldId) return;
      final loadedTicks = worldEventTicksAscending(response.data);
      _mutateEventsCache(() {
        _eventsCache.ticks = worldMergeEventTicksAscending(
          _eventsCache.ticks,
          loadedTicks,
        );
        _eventsCache.total = response.total;
        _eventsCache.page = math.max(_eventsCache.page, page);
        _eventsCache.error = null;
      });
    } catch (e) {
      if (worldId != _eventsCache.worldId) return;
      if (mounted && worldId != _currentWorld.worldId) return;
      _mutateEventsCache(() => _eventsCache.error = e);
    } finally {
      if (worldId == _eventsCache.worldId &&
          (!mounted || worldId == _currentWorld.worldId)) {
        _mutateEventsCache(() {
          if (page == 1) {
            _eventsCache.initialLoading = false;
          } else {
            _eventsCache.loadingMore = false;
          }
        });
      }
    }
  }

  Widget _buildEventsSectionPage(ScrollController scrollController) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
      child: WorldEventsSection(
        scrollController: scrollController,
        key: const PageStorageKey<String>('world-events-section-bottom-sheet'),
        world: _currentWorld,
        ticks: _eventsCache.ticks,
        initialLoading: _eventsCache.initialLoading,
        loadingMore: _eventsCache.loadingMore,
        hasMore: _eventsHasMore,
        error: _eventsCache.error,
        latestRevision: _selection.eventsLatestRevision,
        targetTickNumber: _selection.eventsTargetTickNumber,
        contentPadding: const EdgeInsets.fromLTRB(
          12,
          worldSheetVisibleContentTopGap,
          12,
          32,
        ),
        onLoadMore: _loadNextEventsPage,
      ),
    );
  }

  Widget _buildStatusSectionPage(ScrollController scrollController) {
    final world = _currentWorld;
    return WorldCharacterListView(
      storageKey: 'world-status-section-bottom-sheet',
      characters: world.characters,
      currentUid: widget.currentUid,
      emptyText: 'No character status yet.',
      subtitleBuilder: (character) =>
          worldMetricStatusText(world.metric, character),
      subtitleColor: GenesisColors.darkTextSecondary,
      showCharacterDetails: false,
      controller: scrollController,
    );
  }

  Widget _buildCastSectionPage(ScrollController scrollController) {
    final world = _currentWorld;
    return WorldCharacterListView(
      storageKey: 'world-cast-section-bottom-sheet',
      characters: world.characters,
      currentUid: widget.currentUid,
      emptyText: 'No characters yet.',
      subtitleBuilder: worldCharacterDescriptionText,
      subtitleColor: GenesisColors.darkTextSecondary,
      showCharacterDetails: true,
      controller: scrollController,
    );
  }

  Widget _buildLocationsSectionPage(ScrollController scrollController) {
    final locationData = _locationListDataForCurrentWorld();
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
      child: WorldLocationList(
        controller: scrollController,
        points: locationData.points,
        locationNodes: locationData.locationNodes,
        recentChatLocationIds: widget.recentChatLocationIds,
        enableOuterScrollHandoff: false,
        lazyBuildRows: true,
        // Location rows provide their own 5px top inset. Subtract it here so
        // the first visible image/text still starts 15px below the header.
        padding: const EdgeInsets.fromLTRB(
          12,
          worldSheetVisibleContentTopGap - 5,
          12,
          32,
        ),
        onPointTap: (point) {
          final locationId = point.sceneId.trim().isNotEmpty
              ? point.sceneId.trim()
              : (point.pointId.trim().isNotEmpty
                    ? point.pointId.trim()
                    : point.id.trim());
          GenesisTelemetry.collectLog(
            actionType: 'event',
            action: 'world_locations_click',
            object1: _currentWorld.worldId,
            object2: locationId,
          );
          Navigator.of(context).pop();
          widget.onLocationTap(point);
        },
      ),
    );
  }

  WorldLocationListData _locationListDataForCurrentWorld() {
    final world = _currentWorld;
    final cached = _cachedLocationListData;
    if (cached != null &&
        identical(_cachedProcessedLocationTree, world.processedLocationTree) &&
        identical(_cachedLocations, world.locations) &&
        identical(_cachedCharacterPositions, world.characterPositions) &&
        identical(_cachedUserPositions, world.userPositions) &&
        _cachedLocationListCurrentUid == widget.currentUid) {
      return cached;
    }
    final locationData = worldLocationListDataFor(
      world,
      currentUid: widget.currentUid,
    );
    _cachedLocationListData = locationData;
    _cachedProcessedLocationTree = world.processedLocationTree;
    _cachedLocations = world.locations;
    _cachedCharacterPositions = world.characterPositions;
    _cachedUserPositions = world.userPositions;
    _cachedLocationListCurrentUid = widget.currentUid;
    return locationData;
  }

  Widget _buildDetailSectionPage(ScrollController scrollController) {
    final latestDetailJoinNotice = worldLatestPlayerJoinNotice(
      _currentWorld.characters,
    );
    final newUserJoinNotice = _detailNewUserJoinNotice(
      latestDetailJoinNotice,
      widget.newUserJoinNoticesListenable.value,
    );
    return WorldDetailSectionListView(
      storageKey: 'world-detail-section-bottom-sheet',
      world: _currentWorld,
      currentUid: widget.currentUid,
      controller: scrollController,
      newUserJoinNotice: newUserJoinNotice,
      onDeleteWorld: widget.onDeleteWorld,
    );
  }

  WorldNewUserJoinNotice? _detailNewUserJoinNotice(
    WorldNewUserJoinNotice? latestDetailJoinNotice,
    List<WorldNewUserJoinNotice> socketNotices,
  ) {
    if (socketNotices.isNotEmpty) return socketNotices.last;
    return latestDetailJoinNotice;
  }

  Widget _buildInfoSectionPage(ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        worldInfoPageHorizontalPadding,
        0,
        worldInfoPageHorizontalPadding,
        24,
      ),
      children: [
        SizedBox(
          height: worldInfoHeaderHeightFor(_currentWorld),
          child: widget.infoBuilder(context, _currentWorld),
        ),
        const SizedBox(height: 18),
        const _WorldMoreModulesPreview(),
      ],
    );
  }

  Widget _buildSheetPage(
    WorldBottomSheetKind kind,
    ScrollController scrollController,
  ) {
    return switch (kind) {
      WorldBottomSheetKind.info => _buildInfoSectionPage(scrollController),
      WorldBottomSheetKind.detail => _buildDetailSectionPage(scrollController),
      WorldBottomSheetKind.locations => _buildLocationsSectionPage(
        scrollController,
      ),
      WorldBottomSheetKind.events => _buildEventsSectionPage(scrollController),
      WorldBottomSheetKind.status => _buildStatusSectionPage(scrollController),
      WorldBottomSheetKind.cast => _buildCastSectionPage(scrollController),
    };
  }

  Widget _buildSheetContent(ScrollController sheetScrollController) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
      child: PageView.builder(
        controller: _pageController,
        itemCount: worldBottomTagItems.length,
        onPageChanged: _handleSheetPageChanged,
        itemBuilder: (context, index) {
          final kind = _kindForPage(index);
          final scrollController = kind == _selection.kind
              ? sheetScrollController
              : _previewScrollControllers[index];
          final page = _buildSheetPage(kind, scrollController);
          if (kind == WorldBottomSheetKind.info) return page;
          // Section titles ride on their pages; Info keeps its row on top.
          return Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: _handleHeaderDragUpdate,
                child: WorldSingleSectionSheetHeader(
                  item: worldBottomTagItems[index],
                  onClose: _collapseSheet,
                ),
              ),
              Expanded(child: page),
            ],
          );
        },
      ),
    );
  }

  void _handleHeaderDragUpdate(DragUpdateDetails details) {
    if (!_sheetController.isAttached || _sheetHostHeight <= 0) return;
    final nextExtent =
        (_sheetController.size - details.delta.dy / _sheetHostHeight)
            .clamp(_sheetMinChildSize, _sheetMaxChildSize)
            .toDouble();
    _sheetController.jumpTo(nextExtent);
  }

  void _handleSheetPointerDown(PointerDownEvent event) {
    if (_sheetPointer != null) return;
    _sheetPointer = event.pointer;
    _sheetPointerStartExtent = _sheetController.isAttached
        ? _sheetController.size
        : null;
    _sheetPointerVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.localPosition);
  }

  void _handleSheetPointerMove(PointerMoveEvent event) {
    if (_sheetPointer != event.pointer) return;
    _sheetPointerVelocityTracker?.addPosition(
      event.timeStamp,
      event.localPosition,
    );
  }

  void _handleSheetPointerUp(PointerUpEvent event) {
    if (_sheetPointer != event.pointer) return;
    final tracker = _sheetPointerVelocityTracker
      ?..addPosition(event.timeStamp, event.localPosition);
    final velocity = tracker?.getVelocity().pixelsPerSecond ?? Offset.zero;
    final startExtent = _sheetPointerStartExtent;
    final movedSheetDown =
        startExtent != null &&
        _sheetController.isAttached &&
        _sheetController.size < startExtent - _extentUpdateEpsilon;
    final isDownwardFling =
        movedSheetDown &&
        velocity.dy >= _minimumDownwardFlingVelocity &&
        velocity.dy >= velocity.dx.abs() * _verticalFlingDirectionRatio;
    _resetSheetPointerTracking();
    _settleSheetFromCurrentExtent(isDownwardFling: isDownwardFling);
  }

  void _handleSheetPointerCancel(PointerCancelEvent event) {
    if (_sheetPointer != event.pointer) return;
    _resetSheetPointerTracking();
    _settleSheetFromCurrentExtent();
  }

  void _resetSheetPointerTracking() {
    _sheetPointerVelocityTracker = null;
    _sheetPointer = null;
    _sheetPointerStartExtent = null;
  }

  void _settleSheetFromCurrentExtent({bool isDownwardFling = false}) {
    if (!_sheetController.isAttached) return;
    final collapseThreshold = _collapseSnapThreshold
        .clamp(_sheetMinChildSize, _sheetMaxChildSize)
        .toDouble();
    if (isDownwardFling || _sheetController.size <= collapseThreshold) {
      _collapseSheet(curve: Curves.linear);
      return;
    }
    unawaited(_animateSheetTo(_sheetMaxChildSize, curve: Curves.linear));
  }

  void _collapseSheet({Curve curve = Curves.easeOutCubic}) {
    // The scrim, back swipe, settling on Info and the bubble can all ask at
    // once; lay the sheet down and pop only once.
    if (_closing) return;
    _closing = true;
    if (!_sheetController.isAttached) {
      Navigator.of(context).pop();
      return;
    }
    final navigator = Navigator.of(context);
    unawaited(() async {
      final completed = await _animateSheetTo(_sheetMinChildSize, curve: curve);
      if (completed && mounted && navigator.mounted) {
        navigator.pop();
      } else {
        _closing = false;
      }
    }());
  }

  Future<bool> _animateSheetTo(
    double targetExtent, {
    Curve curve = Curves.easeOutCubic,
  }) async {
    if (!_sheetController.isAttached) return false;
    if ((_sheetController.size - targetExtent).abs() <= _extentUpdateEpsilon) {
      return true;
    }
    try {
      await _sheetController.animateTo(
        targetExtent,
        duration: _snapAnimationDuration,
        curve: curve,
      );
      return true;
    } catch (error, stackTrace) {
      if (mounted && kDebugMode) {
        debugPrint(
          '[WorldPage] bottom sheet extent animation interrupted: '
          '$error\n$stackTrace',
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final collapsedHeight = worldCollapsedPanelHeightFor(
          context,
          world: _currentWorld,
        );
        final maxChildSize = availableHeight <= 0
            ? 1.0
            : ((availableHeight - worldDetailSheetExpandedTopOffset) /
                      availableHeight)
                  .clamp(0.08, 1.0)
                  .toDouble();
        final minChildSize = availableHeight <= 0
            ? 0.08
            : (collapsedHeight / availableHeight)
                  .clamp(0.08, maxChildSize)
                  .toDouble();
        _sheetHostHeight = availableHeight;
        _sheetMinChildSize = minChildSize;
        _sheetMaxChildSize = maxChildSize;
        return GenesisEdgeSwipeBack(
          onBack: _collapseSheet,
          child: Stack(
            children: [
              // The route brings no barrier: this scrim darkens the map only as
              // far as the sheet has risen off its rest, and taps lay it down.
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey<String>('world-sheet-scrim'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _collapseSheet,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _raise,
                    builder: (context, raise, _) => ColoredBox(
                      color: Colors.black.withValues(alpha: 0.18 * raise),
                    ),
                  ),
                ),
              ),
              Listener(
                onPointerDown: _handleSheetPointerDown,
                onPointerMove: _handleSheetPointerMove,
                onPointerUp: _handleSheetPointerUp,
                onPointerCancel: _handleSheetPointerCancel,
                child: DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: minChildSize,
                  minChildSize: minChildSize,
                  maxChildSize: maxChildSize,
                  snap: false,
                  shouldCloseOnMinExtent: false,
                  builder: (context, scrollController) {
                    final content = Column(
                      children: [
                        GestureDetector(
                          key: const ValueKey<String>(
                            'world-sheet-header-drag-area',
                          ),
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: _handleHeaderDragUpdate,
                          child: WorldSheetIndicatorStrip(
                            pageController: _pageController,
                            pageCount: worldBottomTagItems.length,
                            raise: _raise,
                          ),
                        ),
                        Expanded(child: _buildSheetContent(scrollController)),
                      ],
                    );
                    return Theme(
                      data: Theme.of(context).copyWith(
                        brightness: Brightness.dark,
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                          brightness: Brightness.dark,
                          surface: GenesisColors.darkBackground,
                          onSurface: GenesisColors.darkTextPrimary,
                        ),
                        dividerColor: GenesisColors.darkFaintFill,
                      ),
                      child: ValueListenableBuilder<double>(
                        valueListenable: _raise,
                        child: content,
                        builder: (context, raise, child) =>
                            _buildMorphingSurface(raise, child!),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// From Info's glass resting card (0) to the opaque full-width sheet (1): the
  /// insets, the lift and the lower corners close up, the glass fills in, and
  /// the room kept for the section bar settles to its raised size.
  Widget _buildMorphingSurface(double raise, Widget child) {
    double lerp(double from, double to) => from + (to - from) * raise;
    final bottomSafeArea =
        widget.bottomReservedHeight - worldBubbleReservedHeight;
    final inset = lerp(worldRestingCardInset, 0);
    final upperRadius = Radius.circular(
      lerp(worldRestingCardRadius, GenesisRadii.sheetTopRadiusValue),
    );
    final lowerRadius = Radius.circular(lerp(worldRestingCardRadius, 0));
    final borderRadius = BorderRadius.only(
      topLeft: upperRadius,
      topRight: upperRadius,
      bottomLeft: lowerRadius,
      bottomRight: lowerRadius,
    );
    final sigma = genesisMapTopGlassBarBlurSigma * (1 - raise);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        inset,
        0,
        inset,
        lerp(bottomSafeArea + worldRestingCardBottomLift, 0),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          enabled: raise < 1,
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: DecoratedBox(
            key: const ValueKey<String>('world-single-section-bottom-sheet'),
            decoration: BoxDecoration(
              color: raise >= 1
                  ? GenesisColors.darkBackground
                  : Color.lerp(
                      worldRestingCardGlassColor,
                      GenesisColors.darkBackground,
                      raise,
                    ),
              borderRadius: borderRadius,
            ),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: lerp(
                  worldRestingCardBubbleArea,
                  widget.bottomReservedHeight,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  double get _raisedFraction {
    if (!_sheetController.isAttached) return 0;
    final span = _sheetMaxChildSize - _sheetMinChildSize;
    if (span <= 0) return 1;
    return ((_sheetController.size - _sheetMinChildSize) / span)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}

/// A section page's title row: icon, name and close. Info has none.
class WorldSingleSectionSheetHeader extends StatelessWidget {
  const WorldSingleSectionSheetHeader({
    required this.item,
    required this.onClose,
  });

  final WorldBottomTagItem item;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        24,
        0,
        24,
        worldSheetTitleToContentGap,
      ),
      child: SizedBox(
        height: worldSheetTitleRowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            WorldSheetHeaderIcon(item: item),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GenesisColors.darkTextPrimary,
                  fontSize: 16,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(width: 12),
            GenesisDarkCloseButton(onPressed: onClose),
          ],
        ),
      ),
    );
  }
}

/// The sheet's top strip: the page indicator alone.
class WorldSheetIndicatorStrip extends StatelessWidget {
  const WorldSheetIndicatorStrip({
    super.key,
    this.pageController,
    required this.pageCount,
    this.raise,
  });

  final PageController? pageController;
  final int pageCount;

  /// 0 at rest, 1 fully raised: the grab handle hands over to the page
  /// indicator as the sheet rises. Null keeps the strip at rest.
  final ValueListenable<double>? raise;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: worldSheetStripHeight,
      child: ValueListenableBuilder<double>(
        valueListenable: raise ?? const AlwaysStoppedAnimation<double>(0),
        builder: (context, raised, _) => Stack(
          children: [
            Positioned(
              top: worldSheetPageIndicatorTopOffset,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topCenter,
                child: Opacity(
                  opacity: 1 - raised,
                  child: const _WorldSheetGrabHandle(),
                ),
              ),
            ),
            // At rest only the handle shows, so the resting card builds no
            // indicator at all.
            if (raise != null)
              Positioned(
                top: worldSheetPageIndicatorTopOffset,
                left: 0,
                right: 0,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Opacity(
                    opacity: raised,
                    child: WorldSheetPageIndicator(
                      pageController: pageController,
                      pageCount: pageCount,
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

class _WorldSheetGrabHandle extends StatelessWidget {
  const _WorldSheetGrabHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('world-sheet-grab-handle'),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: GenesisColors.darkHandleInactive,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Info at rest: a glass card holding the grab handle, the Info row and the
/// section bar. It only pulls up; raised, it turns into the opaque full-width
/// sheet on the Info page.
class WorldInfoRestingSheet extends StatelessWidget {
  const WorldInfoRestingSheet({
    super.key,
    required this.child,
    required this.bubble,
    this.onPullUp,
  });

  final Widget child;
  final Widget bubble;
  final VoidCallback? onPullUp;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(worldRestingCardRadius));
    final card = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: genesisMapTopGlassBarBlurSigma,
          sigmaY: genesisMapTopGlassBarBlurSigma,
        ),
        child: DecoratedBox(
          key: const ValueKey<String>('world-info-resting-sheet'),
          decoration: const BoxDecoration(
            color: worldRestingCardGlassColor,
            borderRadius: radius,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WorldSheetIndicatorStrip(pageCount: worldBottomTagItems.length),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: worldInfoPageHorizontalPadding,
                ),
                child: child,
              ),
              const SizedBox(height: worldInfoToBubbleGap),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: worldRestingCardBubblePadding,
                ),
                child: bubble,
              ),
              const SizedBox(height: worldRestingCardBubblePadding),
            ],
          ),
        ),
      ),
    );
    final pullUp = onPullUp;
    if (pullUp == null) return card;
    return WorldSectionSheetPullGesture(onPullUp: pullUp, child: card);
  }
}

/// Static stand-in for design 9e's module grid under Info when it is raised,
/// until the real modules land.
class _WorldMoreModulesPreview extends StatelessWidget {
  const _WorldMoreModulesPreview();

  static const _tiles = <(IconData, String, String)>[
    (Icons.article_outlined, 'Log', '42 ticks'),
    (Icons.hub_outlined, 'Ties', '5 characters'),
    (Icons.place_outlined, 'Places', '6 total'),
    (Icons.inventory_2_outlined, 'Items', '3 held'),
    (Icons.shield_outlined, 'Rules', 'Tick 2h'),
    (Icons.ios_share, 'Invite', '2 seats left'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('world-info-more-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'More',
          style: TextStyle(
            color: GenesisColors.darkTextPrimary,
            fontSize: 16,
            height: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 10),
          Row(
            children: [
              for (var column = 0; column < 3; column++) ...[
                if (column > 0) const SizedBox(width: 10),
                Expanded(child: _buildTile(_tiles[row * 3 + column])),
              ],
            ],
          ),
        ],
        const SizedBox(height: 14),
        const Text(
          'Anything a world switches on lands here first.',
          style: TextStyle(
            color: GenesisColors.darkTextSecondary,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildTile((IconData, String, String) tile) {
    final (icon, title, meta) = tile;
    return Container(
      height: 96,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: GenesisColors.darkFaintFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: GenesisColors.darkTextPrimary),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: GenesisColors.darkTextPrimary,
              fontSize: 14,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: GenesisColors.darkTextSecondary,
              fontSize: 12,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class WorldSheetPageIndicator extends StatelessWidget {
  const WorldSheetPageIndicator({this.pageController, required this.pageCount});

  static const double _activeWidth = 26;
  static const double _inactiveWidth = 4;
  static const double _segmentGap = 5;
  static const double _height = 4;
  static const Color _activeColor = GenesisColors.darkHandleActive;
  static const Color _inactiveColor = GenesisColors.darkHandleInactive;

  /// Without a controller the indicator rests on the first page, as the resting
  /// Info sheet shows it.
  final PageController? pageController;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final controller = pageController;
    return AnimatedBuilder(
      animation: controller ?? const AlwaysStoppedAnimation<double>(0),
      builder: (context, child) {
        final page = controller == null
            ? 0.0
            : controller.hasClients
            ? controller.page ?? controller.initialPage.toDouble()
            : controller.initialPage.toDouble();
        return SizedBox(
          height: _height,
          child: Row(
            key: const ValueKey<String>('world-sheet-page-indicator'),
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < pageCount; index++) ...[
                _WorldSheetPageIndicatorSegment(
                  index: index,
                  selectionProgress: (1 - (page - index).abs())
                      .clamp(0.0, 1.0)
                      .toDouble(),
                ),
                if (index != pageCount - 1) const SizedBox(width: _segmentGap),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WorldSheetPageIndicatorSegment extends StatelessWidget {
  const _WorldSheetPageIndicatorSegment({
    required this.index,
    required this.selectionProgress,
  });

  final int index;
  final double selectionProgress;

  @override
  Widget build(BuildContext context) {
    final progress = selectionProgress.clamp(0.0, 1.0);
    return Container(
      key: ValueKey<String>('world-sheet-page-segment-$index'),
      width:
          WorldSheetPageIndicator._inactiveWidth +
          (WorldSheetPageIndicator._activeWidth -
                  WorldSheetPageIndicator._inactiveWidth) *
              progress,
      height: WorldSheetPageIndicator._height,
      decoration: BoxDecoration(
        color: Color.lerp(
          WorldSheetPageIndicator._inactiveColor,
          WorldSheetPageIndicator._activeColor,
          progress,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class WorldSheetHeaderIcon extends StatelessWidget {
  const WorldSheetHeaderIcon({required this.item});

  final WorldBottomTagItem item;

  @override
  Widget build(BuildContext context) {
    final asset = item.asset;
    if (asset != null) {
      return SvgPicture.asset(
        asset,
        width: 20,
        height: 20,
        colorFilter: const ColorFilter.mode(
          GenesisColors.darkTextSecondary,
          BlendMode.srcIn,
        ),
      );
    }
    return Icon(item.icon, size: 20, color: GenesisColors.darkTextSecondary);
  }
}

class WorldSectionsEventsCache {
  var worldId = '';
  var ticks = const <Map<String, dynamic>>[];
  var total = 0;
  var page = 0;
  var initialLoading = false;
  var loadingMore = false;
  Object? error;

  void reset(String nextWorldId) {
    worldId = nextWorldId;
    ticks = const <Map<String, dynamic>>[];
    total = 0;
    page = 0;
    initialLoading = false;
    loadingMore = false;
    error = null;
  }

  void clear() {
    reset('');
  }
}
