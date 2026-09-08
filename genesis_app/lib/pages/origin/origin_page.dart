import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/startup/app_startup_coordinator.dart';
import '../../app/telemetry/firebase_performance_operation.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../components/common/list_loading_skeleton.dart';
import '../../components/genesis_logo.dart';
import '../../components/origin/origin_item_card.dart';
import '../../components/page_header.dart';
import '../../components/search_bar.dart';
import '../../network/api_exception.dart';
import '../../network/json_utils.dart';
import '../../platform/session/user_session_store.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_safe_area.dart';
import '../../ui/components/secend_tabs.dart';
import '../../ui/tokens/genesis_origin_card_geometry.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import 'origin_feed_cache_store.dart';

@visibleForTesting
Duration? debugOriginExposureVisibilityUpdateInterval;

class OriginPage extends StatefulWidget {
  const OriginPage({
    super.key,
    this.isInitialPage = false,
    this.onForYouFirstPageReady,
    this.activationListenable,
    this.isActiveListenable,
  });

  final bool isInitialPage;
  final VoidCallback? onForYouFirstPageReady;
  final ValueListenable<int>? activationListenable;
  final ValueListenable<bool>? isActiveListenable;

  @override
  State<OriginPage> createState() => _OriginPageState();
}

class _OriginPageState extends State<OriginPage> with WidgetsBindingObserver {
  static const _tabsHeight = 32.0;
  static const _searchTopSpacing = 12.0;
  static const _scrollToTopDuration = Duration(milliseconds: 240);
  static const _forYouCategory = _OriginCategory(
    name: 'For you',
    scene: 'foryou',
  );

  final _hotTagsCache = const _OriginHotTagsCache();
  final _iosPrimaryScrollController = ScrollController();
  final Map<_OriginCategory, GlobalKey<_OriginFeedState>> _feedKeys = {};
  List<_OriginCategory> _categories = const [_forYouCategory];
  TabController? _categoryTabController;
  var _scrollToTopInProgress = false;
  var _hasSyncedHotTags = false;
  var _hotTagsSyncInFlight = false;
  var _retryHotTagsOnResume = false;
  AppLifecycleState? _lifecycleState;
  bool get _isPageActive => widget.isActiveListenable?.value ?? true;

  @override
  void initState() {
    super.initState();
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.activationListenable?.addListener(_handleMainNavReselected);
    unawaited(_syncHotTags());
    unawaited(_hydrateCachedCategories());
  }

  @override
  void didUpdateWidget(covariant OriginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activationListenable != widget.activationListenable) {
      oldWidget.activationListenable?.removeListener(_handleMainNavReselected);
      widget.activationListenable?.addListener(_handleMainNavReselected);
    }
  }

  @override
  void dispose() {
    widget.activationListenable?.removeListener(_handleMainNavReselected);
    WidgetsBinding.instance.removeObserver(this);
    _iosPrimaryScrollController.dispose();
    super.dispose();
  }

  GlobalKey<_OriginFeedState> _feedKeyFor(_OriginCategory category) {
    return _feedKeys.putIfAbsent(category, () => GlobalKey<_OriginFeedState>());
  }

  void _handleCategoryTap(BuildContext tabContext, int index) {
    final controller = DefaultTabController.of(tabContext);
    _categoryTabController = controller;
    if (controller.index != index || controller.indexIsChanging) return;
    unawaited(_scrollCategoryToTop(index));
  }

  void _handleMainNavReselected() {
    final controller = _categoryTabController;
    if (controller == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleMainNavReselected();
      });
      return;
    }
    if (controller.index != 0) {
      controller.animateTo(
        0,
        duration: _scrollToTopDuration,
        curve: Curves.easeOutCubic,
      );
    }
    unawaited(_scrollCategoryToTop(0));
  }

  Future<void> _scrollCategoryToTop(int index) async {
    if (index < 0 || index >= _categories.length || _scrollToTopInProgress) {
      return;
    }
    _scrollToTopInProgress = true;
    try {
      final feedState = _feedKeyFor(_categories[index]).currentState;
      if (feedState != null) await feedState.scrollToTop();
    } finally {
      _scrollToTopInProgress = false;
    }
  }

  void _scrollCurrentCategoryToTop() {
    if (!_isPageActive) return;
    final controller = _categoryTabController;
    if (controller == null) return;
    unawaited(_scrollCategoryToTop(controller.index));
  }

  @override
  void handleStatusBarTap() {
    if (defaultTargetPlatform != TargetPlatform.iOS || !_isPageActive) return;
    _scrollCurrentCategoryToTop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state != AppLifecycleState.resumed || _hasSyncedHotTags) return;
    if (_hotTagsSyncInFlight) {
      _retryHotTagsOnResume = true;
      return;
    }
    unawaited(_syncHotTags());
  }

  Future<void> _hydrateCachedCategories() async {
    final cachedTags = await _hotTagsCache.load();
    if (!mounted) return;
    if (_hasSyncedHotTags || cachedTags.isEmpty) return;
    setState(() {
      _categories = _categoriesFromTags(cachedTags);
    });
  }

  Future<void> _syncHotTags() async {
    if (_hasSyncedHotTags || _hotTagsSyncInFlight) return;
    _hotTagsSyncInFlight = true;
    try {
      final tags = await AppServicesScope.read(context).api.v1.origin.hotTags();
      final normalizedTags = _normalizeTags(tags);
      await _hotTagsCache.save(normalizedTags);
      if (!mounted) return;
      setState(() {
        _hasSyncedHotTags = true;
        _categories = _categoriesFromTags(normalizedTags);
      });
    } catch (_) {
      // Keep the already rendered For you tab or cached tabs on sync failure.
      // A later foreground transition retries this request after a system
      // network permission sheet or a temporary offline period.
    } finally {
      _hotTagsSyncInFlight = false;
      if (_retryHotTagsOnResume &&
          _lifecycleState == AppLifecycleState.resumed &&
          mounted) {
        _retryHotTagsOnResume = false;
        unawaited(_syncHotTags());
      }
    }
  }

  void _retryHotTagsIfNeeded() {
    if (_hasSyncedHotTags || _hotTagsSyncInFlight || !mounted) return;
    _retryHotTagsOnResume = false;
    unawaited(_syncHotTags());
  }

  static List<_OriginCategory> _categoriesFromTags(List<String> tags) {
    return [
      _forYouCategory,
      for (final tag in _normalizeTags(tags))
        _OriginCategory(name: tag, scene: 'tag'),
    ];
  }

  static List<String> _normalizeTags(List<String> tags) {
    final seen = <String>{};
    final result = <String>[];
    for (final tag in tags) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (key == _forYouCategory.name.toLowerCase()) continue;
      if (!seen.add(key)) continue;
      result.add(trimmed);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final labels = categories.map((item) => item.name).toList();
    final page = DefaultTabController(
      length: categories.length,
      child: Builder(
        builder: (tabContext) {
          _categoryTabController = DefaultTabController.of(tabContext);
          return Column(
            children: [
              Stack(
                children: [
                  GenesisTopSafeArea(
                    backgroundColor: GenesisColors.darkBackground,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        height: kGenesisTopBarHeight + 4,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            height: kGenesisTopBarHeight,
                            child: Transform.translate(
                              offset: const Offset(0, 5),
                              child: Row(
                                children: [
                                  SizedBox(
                                    key: const ValueKey<String>(
                                      'origin-brand-logo',
                                    ),
                                    width: 96,
                                    height: 32,
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: GenesisColors.redPrimary,
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(12),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        child: GenesisLogo(
                                          width: 84,
                                          height: 24,
                                          semanticsLabel: 'Worldo',
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SearchBarPlaceholder(
                                      backgroundColor:
                                          GenesisColors.darkFaintFill,
                                      borderColor: null,
                                      onTap: () {
                                        Navigator.of(
                                          context,
                                        ).pushNamed(RouteNames.search);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (defaultTargetPlatform == TargetPlatform.android)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height:
                          GenesisSafeAreaInsets.top(context) +
                          _searchTopSpacing,
                      child: GestureDetector(
                        key: const ValueKey<String>(
                          'origin-android-scroll-to-top-zone',
                        ),
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: _scrollCurrentCategoryToTop,
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
              SizedBox(
                height: _tabsHeight,
                child: ColoredBox(
                  color: GenesisColors.darkBackground,
                  child: SecendTabs(
                    labels: labels,
                    labelColor: GenesisColors.darkTextPrimary,
                    unselectedLabelColor: GenesisColors.darkTextSecondary,
                    indicatorColor: GenesisColors.redPrimary,
                    verticalPadding: 0,
                    physics: const BouncingScrollPhysics(),
                    onTap: (index) => _handleCategoryTap(tabContext, index),
                  ),
                ),
              ),
              Expanded(
                child: ScrollConfiguration(
                  key: const ValueKey<String>(
                    'origin-tab-pages-scroll-configuration',
                  ),
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(overscroll: false),
                  child: TabBarView(
                    children: [
                      for (final entry in categories.indexed)
                        _OriginFeed(
                          key: _feedKeyFor(entry.$2),
                          index: entry.$1,
                          category: entry.$2,
                          isInitialPage: widget.isInitialPage && entry.$1 == 0,
                          onFirstPageReady: entry.$1 == 0
                              ? widget.onForYouFirstPageReady
                              : null,
                          onInitialLoadCompleted: entry.$1 == 0
                              ? _retryHotTagsIfNeeded
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    final themedPage = GenesisDarkTheme(
      child: ColoredBox(color: GenesisColors.darkBackground, child: page),
    );
    if (defaultTargetPlatform != TargetPlatform.iOS) return themedPage;
    return PrimaryScrollController(
      controller: _iosPrimaryScrollController,
      child: themedPage,
    );
  }
}

class _OriginHotTagsCache {
  const _OriginHotTagsCache();

  static const storageKey = 'origin_hot_tags_v1';

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(storageKey) ?? const <String>[];
  }

  Future<void> save(List<String> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(storageKey, tags);
  }
}

class _OriginCategory {
  const _OriginCategory({required this.name, required this.scene});

  final String name;
  final String scene;

  @override
  bool operator ==(Object other) {
    return other is _OriginCategory &&
        other.name == name &&
        other.scene == scene;
  }

  @override
  int get hashCode => Object.hash(name, scene);
}

class _OriginFeed extends StatefulWidget {
  const _OriginFeed({
    super.key,
    required this.index,
    required this.category,
    this.isInitialPage = false,
    this.onFirstPageReady,
    this.onInitialLoadCompleted,
  });

  final int index;
  final _OriginCategory category;
  final bool isInitialPage;
  final VoidCallback? onFirstPageReady;
  final VoidCallback? onInitialLoadCompleted;

  @override
  State<_OriginFeed> createState() => _OriginFeedState();
}

class _OriginFeedState extends State<_OriginFeed>
    with AutomaticKeepAliveClientMixin<_OriginFeed>, WidgetsBindingObserver {
  static const _pageSize = 20;
  static const _forYouPageSize = 10;
  static const _loadMoreThreshold = 700.0;
  static const _minimumExposureRatio = 0.3;
  static const _minimumExposureDuration = Duration(milliseconds: 1500);
  static const _exposureVisibilityUpdateInterval = Duration(milliseconds: 100);
  static const _exposureBatchCoalescingDuration = Duration(milliseconds: 16);
  static const _maxExposureBatchSize = 100;
  static const _maxExposureAttempts = 3;

  TabController? _tabController;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _exposureViewportKey = GlobalKey(
    debugLabel: 'origin-feed-exposure-viewport',
  );
  final List<OriginListItem> _items = <OriginListItem>[];
  final Map<String, double> _visibleExposureFractions = <String, double>{};
  final Map<String, Timer> _exposureTimers = <String, Timer>{};
  final Map<String, GlobalKey> _exposureCardKeys = <String, GlobalKey>{};
  final Map<String, String> _renderedExposureCovers = <String, String>{};
  final Set<String> _pendingExposureIds = <String>{};
  final Set<String> _inFlightExposureIds = <String>{};
  final Set<String> _reportedExposureIds = <String>{};
  Timer? _exposureQueueFlushTimer;
  Timer? _exposureViewportValidationTimer;
  var _nextPage = 1;
  var _nextScore = 0;
  var _total = 0;
  var _layoutRevision = 0;
  var _hasMore = true;
  var _hasRequested = false;
  var _scrollListenerAttached = false;
  var _isInitialLoading = false;
  var _isLoadingMore = false;
  var _isRefreshing = false;
  var _hasCompletedFirstPageNetworkRequest = false;
  Object? _error;
  var _initialLoadCompleted = false;
  var _initialLoadInFlight = false;
  var _permissionPromptMayBeOpen = false;
  var _retryInitialLoadWhenFinished = false;
  var _hasRetriedInitialStartup = false;
  FirebasePerformanceOperation? _activeFirstScreenRequestOperation;
  FirebasePerformanceOperation? _activeFirstScreenRenderOperation;
  var _firstScreenRequestAttempt = 0;
  var _firstScreenRenderCompleted = false;
  var _launchRenderRevision = 0;
  var _isSendingExposures = false;

  bool get _isForYouFeed => widget.category.scene == 'foryou';

  bool get _usesFirstPageCache => _isForYouFeed;

  bool get _isCurrentTab => _tabController?.index == widget.index;

  bool get _isCurrentTabSettled {
    final controller = _tabController;
    if (controller == null ||
        controller.index != widget.index ||
        controller.indexIsChanging) {
      return false;
    }
    final animationValue = controller.animation?.value;
    return animationValue == null ||
        (animationValue - widget.index).abs() < 0.001;
  }

  @override
  bool get wantKeepAlive => true;

  bool get _isPrimaryFeed =>
      widget.index == 0 && widget.category.scene == 'foryou';

  Future<void> scrollToTop() async {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final minExtent = position.minScrollExtent;
    if (position.pixels <= minExtent) return;
    await position.animateTo(
      minExtent,
      duration: _OriginPageState._scrollToTopDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _trackForYouListLoad({required String type, required int page}) {
    if (!_isPrimaryFeed) return;
    GenesisTelemetry.collectLog(
      actionType: 'event',
      action: 'worldo_list_load',
      object1: type,
      object2: page,
    );
  }

  @override
  void initState() {
    super.initState();
    if (_isForYouFeed) {
      VisibilityDetectorController.instance.updateInterval =
          debugOriginExposureVisibilityUpdateInterval ??
          _exposureVisibilityUpdateInterval;
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _clearExposureCandidates();
    } else if (_isCurrentTab && _items.isNotEmpty) {
      _scheduleVisibilityFlush();
    }

    if (!_isPrimaryFeed || _initialLoadCompleted) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // The iOS wireless-data permission sheet makes the app inactive. Keep
      // the first feed in its loading state until the sheet is dismissed.
      if (_initialLoadInFlight || _isInitialLoading) {
        _permissionPromptMayBeOpen = true;
      }
      return;
    }

    if (state != AppLifecycleState.resumed || !_hasRequested) return;

    // Any first-page failure can be caused by a transient network or system
    // permission transition. Retry once when the app is actually foregrounded.
    _permissionPromptMayBeOpen = false;
    if (_initialLoadInFlight) {
      _retryInitialLoadWhenFinished = true;
      return;
    }
    _hasRetriedInitialStartup = true;
    unawaited(_refreshItems());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = DefaultTabController.of(context);
    if (_tabController != nextController) {
      _tabController?.removeListener(_handleTabChange);
      _tabController = nextController..addListener(_handleTabChange);
    }
    if (!_scrollListenerAttached) {
      _scrollController.addListener(_handleScroll);
      _scrollListenerAttached = true;
    }
    _requestIfCurrentTab();
  }

  @override
  void didUpdateWidget(covariant _OriginFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category ||
        oldWidget.index != widget.index) {
      _resetListState();
      _requestIfCurrentTab();
    }
  }

  @override
  void dispose() {
    if (_activeFirstScreenRequestOperation != null) {
      AppStartupCoordinator.recordLaunchRequestEnd(
        page: 'worldo',
        result: 'cancelled',
      );
    }
    unawaited(_activeFirstScreenRequestOperation?.cancel());
    unawaited(_activeFirstScreenRenderOperation?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _tabController?.removeListener(_handleTabChange);
    _clearExposureCandidates();
    _exposureQueueFlushTimer?.cancel();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _resetListState() {
    _clearExposureCandidates();
    _exposureQueueFlushTimer?.cancel();
    _exposureQueueFlushTimer = null;
    unawaited(_activeFirstScreenRequestOperation?.cancel());
    unawaited(_activeFirstScreenRenderOperation?.cancel());
    _activeFirstScreenRequestOperation = null;
    _activeFirstScreenRenderOperation = null;
    _firstScreenRequestAttempt = 0;
    _firstScreenRenderCompleted = false;
    _launchRenderRevision += 1;
    _items.clear();
    _exposureCardKeys.clear();
    _renderedExposureCovers.clear();
    _layoutRevision += 1;
    _nextPage = 1;
    _nextScore = 0;
    _total = 0;
    _hasMore = true;
    _hasRequested = false;
    _isInitialLoading = false;
    _isLoadingMore = false;
    _isRefreshing = false;
    _hasCompletedFirstPageNetworkRequest = false;
    _error = null;
    _initialLoadCompleted = false;
    _initialLoadInFlight = false;
    _permissionPromptMayBeOpen = false;
    _retryInitialLoadWhenFinished = false;
    _hasRetriedInitialStartup = false;
    _pendingExposureIds.clear();
    _inFlightExposureIds.clear();
    _reportedExposureIds.clear();
  }

  void _scheduleFirstScreenRenderCompletion(
    FirebasePerformanceOperation operation,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(_activeFirstScreenRenderOperation, operation) ||
          !_isPrimaryFeed ||
          _tabController?.index != widget.index) {
        if (identical(_activeFirstScreenRenderOperation, operation)) {
          _activeFirstScreenRenderOperation = null;
        }
        unawaited(operation.cancel());
        return;
      }
      _activeFirstScreenRenderOperation = null;
      _firstScreenRenderCompleted = true;
      unawaited(operation.succeed());
    });
  }

  void _scheduleLaunchRender(
    String result, {
    bool supersedePendingRender = true,
  }) {
    if (!_isPrimaryFeed) return;
    if (supersedePendingRender) _launchRenderRevision += 1;
    final revision = _launchRenderRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isCurrentTab || revision != _launchRenderRevision) {
        return;
      }
      AppStartupCoordinator.recordLaunchRender(page: 'worldo', result: result);
    });
  }

  void _handleTabChange() {
    _requestIfCurrentTab();
    if (_isCurrentTabSettled && _items.isNotEmpty) {
      _scheduleVisibilityFlush();
    } else {
      _clearExposureCandidates();
    }
  }

  void _requestIfCurrentTab() {
    final controller = _tabController;
    if (controller == null ||
        controller.index != widget.index ||
        _hasRequested) {
      return;
    }
    _hasRequested = true;
    if (_usesFirstPageCache) unawaited(_hydrateCachedFirstPage());
    unawaited(_refreshItems());
  }

  void _handleScroll() {
    _scheduleExposureViewportValidation();
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > _loadMoreThreshold) {
      return;
    }
    if (!_hasMore || _isInitialLoading || _isLoadingMore || _isRefreshing) {
      return;
    }
    _trackForYouListLoad(type: 'load_more', page: _nextPage);
    unawaited(_loadNextPage());
  }

  void _scheduleFeedPaginationContinuation() {
    if (!_isForYouFeed || !_hasMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_isCurrentTab ||
          !_hasMore ||
          _isInitialLoading ||
          _isLoadingMore ||
          _isRefreshing) {
        return;
      }

      // Exposure filtering and client-side OID de-duplication can leave a
      // cursor page empty (or too short to move the viewport away from the
      // load-more threshold). No further scroll notification is emitted when
      // that happens, so keep advancing the cursor until the viewport has
      // enough content or the server ends pagination.
      final stillNeedsContent =
          _items.isEmpty ||
          (_scrollController.hasClients &&
              _scrollController.position.extentAfter <= _loadMoreThreshold);
      if (stillNeedsContent) {
        unawaited(_loadNextPage(advanceLogicalPage: false));
      }
    });
  }

  Future<void> _refreshFromPull() {
    _trackForYouListLoad(type: 'refresh', page: 1);
    return _refreshItems();
  }

  Future<_OriginListPage> _fetchPage(int page, {int? startScore}) async {
    if (_isForYouFeed) {
      final data = await AppServicesScope.of(
        context,
      ).api.v1.origin.feed(startScore: startScore ?? 0, rn: _forYouPageSize);
      return _parseOriginFeedPage(data);
    }
    final scene = widget.category.scene;
    final data = await AppServicesScope.of(context).api.v1.origin.list(
      scene: scene,
      tag: scene == 'tag' ? widget.category.name : null,
      pn: page,
      rn: _pageSize,
    );
    return _parseOriginListPage(data);
  }

  Future<OriginFeedCacheStore> _cacheStoreForCurrentOwner() async {
    final services = AppServicesScope.of(context);
    final uid = await services.sessionStore.readLoginUid();
    final ownerUid = uid ?? OriginFeedCacheStore.anonymousOwnerUid;
    return OriginFeedCacheStore(ownerUid: ownerUid);
  }

  Future<void> _hydrateCachedFirstPage() async {
    Map<String, dynamic>? data;
    try {
      final cacheStore = await _cacheStoreForCurrentOwner();
      data = await cacheStore.loadForYouFirstPage();
    } catch (_) {
      return;
    }
    if (!mounted ||
        !_usesFirstPageCache ||
        _hasCompletedFirstPageNetworkRequest ||
        data == null) {
      return;
    }
    late final _OriginListPage page;
    try {
      page = _parseOriginFeedPage(data);
    } catch (_) {
      // Malformed cache data must not affect the parallel network refresh.
      return;
    }
    if (!mounted || _hasCompletedFirstPageNetworkRequest) return;
    setState(() {
      _items
        ..clear()
        ..addAll(page.items);
      _layoutRevision += 1;
      _total = page.total;
      _nextPage = 2;
      _nextScore = page.nextScore ?? 0;
      _hasMore = page.hasMore == true && _nextScore > 0;
      _isInitialLoading = false;
      _error = null;
    });
    _pruneExposureCandidates();
    _scheduleFeedPaginationContinuation();
    widget.onFirstPageReady?.call();
    _scheduleLaunchRender('cache');
  }

  Future<void> _saveFirstPageCache(Map<String, dynamic> data) async {
    try {
      final cacheStore = await _cacheStoreForCurrentOwner();
      await cacheStore.saveForYouFirstPage(data);
    } catch (_) {
      // Cache writes must not affect the visible network result.
    }
  }

  Future<void> _refreshItems() async {
    if (_initialLoadInFlight) return;
    _clearExposureCandidates();
    _initialLoadInFlight = _isPrimaryFeed && !_initialLoadCompleted;
    setState(() {
      _error = null;
      _isInitialLoading = _items.isEmpty;
      _isRefreshing = true;
    });

    FirebasePerformanceOperation? requestOperation;
    final shouldTrackFirstScreen =
        _isPrimaryFeed && !_firstScreenRenderCompleted;
    if (shouldTrackFirstScreen) {
      final attempt = ++_firstScreenRequestAttempt;
      requestOperation = await FirebasePerformanceOperation.start(
        surface: FirebasePerformanceSurface.worldo,
        phase: FirebasePerformancePhase.request,
        attempt: attempt,
      );
      if (!mounted) {
        unawaited(requestOperation.cancel());
        return;
      }
      _activeFirstScreenRequestOperation = requestOperation;
    }

    if (shouldTrackFirstScreen) {
      AppStartupCoordinator.recordLaunchRequestStart(page: 'worldo');
    }
    try {
      final page = await _fetchPage(1, startScore: 0);
      if (!mounted) {
        unawaited(requestOperation?.cancel());
        return;
      }
      if (identical(_activeFirstScreenRequestOperation, requestOperation)) {
        _activeFirstScreenRequestOperation = null;
      }
      unawaited(requestOperation?.succeed());
      AppStartupCoordinator.recordLaunchRequestEnd(
        page: 'worldo',
        result: 'success',
      );
      _hasCompletedFirstPageNetworkRequest = true;
      if (_usesFirstPageCache) {
        unawaited(_saveFirstPageCache(page.rawData));
      }
      FirebasePerformanceOperation? renderOperation;
      if (shouldTrackFirstScreen &&
          _tabController?.index == widget.index &&
          !_firstScreenRenderCompleted) {
        renderOperation = await FirebasePerformanceOperation.start(
          surface: FirebasePerformanceSurface.worldo,
          phase: FirebasePerformancePhase.render,
          attempt: requestOperation?.attempt ?? _firstScreenRequestAttempt,
          timeout: FirebasePerformanceOperation.renderTimeout,
        );
        if (!mounted || _tabController?.index != widget.index) {
          unawaited(renderOperation.cancel());
          renderOperation = null;
        } else {
          _activeFirstScreenRenderOperation = renderOperation;
        }
      }
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _layoutRevision += 1;
        _total = page.total;
        _nextPage = 2;
        _nextScore = page.nextScore ?? 0;
        _hasMore = _isForYouFeed
            ? page.hasMore == true && _nextScore > 0
            : _items.length < _total && page.items.isNotEmpty;
        _isInitialLoading = false;
        _isRefreshing = false;
      });
      _pruneExposureCandidates();
      _scheduleFeedPaginationContinuation();
      _scheduleVisibilityFlush();
      widget.onFirstPageReady?.call();
      _scheduleLaunchRender(page.items.isEmpty ? 'network_empty' : 'network');
      if (renderOperation != null) {
        _scheduleFirstScreenRenderCompletion(renderOperation);
      }
      _initialLoadInFlight = false;
      if (_isPrimaryFeed) {
        _initialLoadCompleted = true;
        widget.onInitialLoadCompleted?.call();
      }
    } catch (error) {
      if (identical(_activeFirstScreenRequestOperation, requestOperation)) {
        _activeFirstScreenRequestOperation = null;
      }
      unawaited(
        requestOperation?.fail(errorType: firebasePerformanceErrorType(error)),
      );
      AppStartupCoordinator.recordLaunchRequestEnd(
        page: 'worldo',
        result: 'failure',
      );
      if (!mounted) return;
      final shouldRetryAfterResume = _retryInitialLoadWhenFinished;
      _retryInitialLoadWhenFinished = false;
      _initialLoadInFlight = false;
      final keepInitialStartupSkeleton =
          _isPrimaryFeed &&
          widget.isInitialPage &&
          !_hasRetriedInitialStartup &&
          !_hasCompletedFirstPageNetworkRequest;
      if (_permissionPromptMayBeOpen || keepInitialStartupSkeleton) {
        setState(() {
          _error = null;
          _isInitialLoading = true;
          _isRefreshing = false;
        });
        return;
      }
      setState(() {
        _error = error;
        _isInitialLoading = false;
        _isRefreshing = false;
      });
      _scheduleLaunchRender('network_error', supersedePendingRender: false);
      if (_items.isNotEmpty) _scheduleVisibilityFlush();
      if (shouldRetryAfterResume && mounted) {
        _hasRetriedInitialStartup = true;
        unawaited(_refreshItems());
      }
    }
  }

  Future<void> _loadNextPage({bool advanceLogicalPage = true}) async {
    if (!_hasMore || _isInitialLoading || _isLoadingMore || _isRefreshing) {
      return;
    }
    setState(() {
      _isLoadingMore = true;
      _error = null;
    });

    try {
      final requestedScore = _nextScore;
      final page = await _fetchPage(
        _nextPage,
        startScore: _isForYouFeed ? requestedScore : null,
      );
      if (!mounted) return;
      setState(() {
        final existingIds = _items.map((item) => item.oid).toSet();
        _items.addAll(page.items.where((item) => existingIds.add(item.oid)));
        _total = page.total;
        if (advanceLogicalPage) _nextPage += 1;
        if (_isForYouFeed) {
          final returnedScore = page.nextScore ?? requestedScore;
          _nextScore = returnedScore;
          _hasMore = page.hasMore == true && returnedScore > requestedScore;
        } else {
          _hasMore = _items.length < _total && page.items.isNotEmpty;
        }
        _isLoadingMore = false;
      });
      _pruneExposureCandidates();
      _scheduleFeedPaginationContinuation();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoadingMore = false;
      });
    }
  }

  void _pruneExposureCandidates() {
    final currentCovers = <String, String>{
      for (final item in _items) item.oid: item.cover,
    };
    final currentIds = currentCovers.keys.toSet();
    _visibleExposureFractions.removeWhere(
      (oid, _) => !currentIds.contains(oid),
    );
    _exposureCardKeys.removeWhere((oid, _) => !currentIds.contains(oid));
    _renderedExposureCovers.removeWhere(
      (oid, cover) => currentCovers[oid] != cover,
    );
    final removedIds = _exposureTimers.keys
        .where((oid) => !currentIds.contains(oid))
        .toList(growable: false);
    for (final oid in removedIds) {
      _exposureTimers.remove(oid)?.cancel();
    }
  }

  void _scheduleVisibilityFlush() {
    if (!_isForYouFeed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isCurrentTabSettled) return;
      VisibilityDetectorController.instance.notifyNow();
      _resampleVisibleExposureCandidates();
    });
  }

  void _resampleVisibleExposureCandidates() {
    if (!_canTrackExposure) return;
    for (final item in _items) {
      final cardContext = _exposureCardKeys[item.oid]?.currentContext;
      if (cardContext == null) continue;
      final visibleFraction = _actualExposureVisibleFraction(item.oid);
      _visibleExposureFractions[item.oid] = visibleFraction;
      _updateExposureCandidate(item.oid, item.cover);
    }
  }

  bool get _canTrackExposure {
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    return _isForYouFeed &&
        _isCurrentTabSettled &&
        !_isInitialLoading &&
        !_isRefreshing &&
        !_permissionPromptMayBeOpen &&
        (lifecycleState == null || lifecycleState == AppLifecycleState.resumed);
  }

  bool _alreadyHandledExposure(String oid) {
    return _reportedExposureIds.contains(oid) ||
        _pendingExposureIds.contains(oid) ||
        _inFlightExposureIds.contains(oid);
  }

  void _clearExposureCandidates() {
    _exposureViewportValidationTimer?.cancel();
    _exposureViewportValidationTimer = null;
    for (final timer in _exposureTimers.values) {
      timer.cancel();
    }
    _exposureTimers.clear();
    _visibleExposureFractions.clear();
  }

  GlobalKey _exposureCardKey(String oid) {
    return _exposureCardKeys.putIfAbsent(
      oid,
      () => GlobalKey(debugLabel: 'origin-feed-card-$oid'),
    );
  }

  double _actualExposureVisibleFraction(String oid) {
    final cardRenderObject = _exposureCardKeys[oid]?.currentContext
        ?.findRenderObject();
    final viewportRenderObject = _exposureViewportKey.currentContext
        ?.findRenderObject();
    if (cardRenderObject is! RenderBox ||
        viewportRenderObject is! RenderBox ||
        !cardRenderObject.attached ||
        !viewportRenderObject.attached ||
        !cardRenderObject.hasSize ||
        !viewportRenderObject.hasSize) {
      return 0;
    }
    final cardRect =
        cardRenderObject.localToGlobal(Offset.zero) & cardRenderObject.size;
    final viewportRect =
        viewportRenderObject.localToGlobal(Offset.zero) &
        viewportRenderObject.size;
    final intersection = cardRect.intersect(viewportRect);
    final cardArea = cardRect.width * cardRect.height;
    if (intersection.isEmpty || cardArea <= 0) return 0;
    return (intersection.width * intersection.height / cardArea)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  bool _qualifiesForExposure(String oid, String cover) {
    return _canTrackExposure &&
        cover.isNotEmpty &&
        _renderedExposureCovers[oid] == cover &&
        (_visibleExposureFractions[oid] ?? 0) >= _minimumExposureRatio &&
        _actualExposureVisibleFraction(oid) >= _minimumExposureRatio &&
        !_alreadyHandledExposure(oid);
  }

  void _updateExposureCandidate(String oid, String cover) {
    if (!_qualifiesForExposure(oid, cover)) {
      _exposureTimers.remove(oid)?.cancel();
      return;
    }
    _exposureTimers.putIfAbsent(
      oid,
      () => Timer(_minimumExposureDuration, () {
        VisibilityDetectorController.instance.notifyNow();
        _exposureTimers.remove(oid);
        if (!mounted || !_qualifiesForExposure(oid, cover)) return;
        _enqueueExposures([oid]);
      }),
    );
  }

  void _handleCoverLoaded(String oid, String cover) {
    if (cover.isEmpty) return;
    _renderedExposureCovers[oid] = cover;
    _updateExposureCandidate(oid, cover);
  }

  void _handleItemVisibilityChanged(
    String oid,
    String cover,
    VisibilityInfo info,
  ) {
    final visibleFraction = info.visibleFraction.clamp(0.0, 1.0).toDouble();
    _visibleExposureFractions[oid] = visibleFraction;
    _updateExposureCandidate(oid, cover);
  }

  void _scheduleExposureViewportValidation() {
    if (!_isForYouFeed || _exposureViewportValidationTimer != null) return;
    _exposureViewportValidationTimer = Timer(
      _exposureVisibilityUpdateInterval,
      () {
        _exposureViewportValidationTimer = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final activeIds = _exposureTimers.keys.toList(growable: false);
          for (final oid in activeIds) {
            final cover = _renderedExposureCovers[oid] ?? '';
            if (!_qualifiesForExposure(oid, cover)) {
              _exposureTimers.remove(oid)?.cancel();
            }
          }
        });
      },
    );
  }

  void _enqueueExposures(Iterable<String> originIds) {
    if (!_isForYouFeed) return;
    for (final oid in originIds) {
      if (oid.isEmpty ||
          _reportedExposureIds.contains(oid) ||
          _pendingExposureIds.contains(oid) ||
          _inFlightExposureIds.contains(oid)) {
        continue;
      }
      _pendingExposureIds.add(oid);
    }
    if (_pendingExposureIds.isNotEmpty) {
      _exposureQueueFlushTimer ??= Timer(_exposureBatchCoalescingDuration, () {
        _exposureQueueFlushTimer = null;
        unawaited(_drainExposureQueue());
      });
    }
  }

  Future<void> _drainExposureQueue() async {
    if (_isSendingExposures || !_isForYouFeed) return;
    _isSendingExposures = true;
    try {
      while (mounted && _pendingExposureIds.isNotEmpty) {
        final batch = _pendingExposureIds
            .take(_maxExposureBatchSize)
            .toList(growable: false);
        _pendingExposureIds.removeAll(batch);
        _inFlightExposureIds.addAll(batch);
        var delivered = false;
        var retainForNextTrigger = false;
        for (var attempt = 1; attempt <= _maxExposureAttempts; attempt += 1) {
          try {
            await AppServicesScope.of(
              context,
            ).api.v1.origin.reportFeedExposure(batch);
            delivered = true;
            break;
          } catch (error) {
            if (!_isRetryableExposureError(error)) break;
            if (attempt >= _maxExposureAttempts) {
              retainForNextTrigger = true;
              break;
            }
            await Future<void>.delayed(Duration(seconds: attempt));
            if (!mounted) {
              retainForNextTrigger = true;
              break;
            }
          }
        }
        _inFlightExposureIds.removeAll(batch);
        if (delivered) {
          _reportedExposureIds.addAll(batch);
        } else if (retainForNextTrigger) {
          _pendingExposureIds.addAll(batch);
          break;
        }
      }
    } finally {
      _isSendingExposures = false;
    }
  }

  bool _isRetryableExposureError(Object error) {
    return error is ApiException && (error.code == 5000 || error.retryable);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scrollKey = PageStorageKey<String>(
      'origin-feed-${widget.category.name}-${widget.category.scene}',
    );
    const physics = BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );

    if (!_hasRequested ||
        _isInitialLoading ||
        (_permissionPromptMayBeOpen && !_initialLoadCompleted)) {
      return const GenesisListLoadingSkeleton.originGrid();
    }

    if (_error != null && _items.isEmpty) {
      return CustomScrollView(
        key: scrollKey,
        primary: true,
        physics: physics,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Load failed',
                    style: TextStyle(color: GenesisColors.darkTextPrimary),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _refreshItems,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      backgroundColor: GenesisColors.darkRaisedBackground,
      color: GenesisColors.darkTextSecondary,
      onRefresh: _refreshFromPull,
      child: _items.isEmpty
          ? CustomScrollView(
              key: scrollKey,
              controller: _scrollController,
              primary: false,
              physics: physics,
              slivers: const [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No data',
                      style: TextStyle(color: GenesisColors.darkTextSecondary),
                    ),
                  ),
                ),
              ],
            )
          : ClipRect(
              key: _exposureViewportKey,
              child: KeyedSubtree(
                key: ValueKey<String>(
                  'origin-feed-layout-${widget.index}-$_layoutRevision',
                ),
                child: CustomScrollView(
                  key: scrollKey,
                  controller: _scrollController,
                  primary: false,
                  scrollCacheExtent: const ScrollCacheExtent.viewport(1),
                  physics: physics,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(2, 5, 2, 0),
                      sliver: SliverLayoutBuilder(
                        builder: (context, constraints) {
                          const crossAxisSpacing = 2.0;
                          final itemWidth =
                              (constraints.crossAxisExtent - crossAxisSpacing) /
                              2;
                          final itemHeight =
                              itemWidth / genesisOriginCoverAspectRatio +
                              genesisOriginCardBottomExtension;
                          return SliverGrid(
                            key: const ValueKey<String>(
                              'origin-feed-virtual-grid',
                            ),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 2,
                                  crossAxisSpacing: crossAxisSpacing,
                                  mainAxisExtent: itemHeight,
                                ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final item = _items[index];
                                final card = GestureDetector(
                                  key: ValueKey<String>(
                                    'origin-feed-item-${item.oid}',
                                  ),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: item.deleted
                                      ? null
                                      : () {
                                          GenesisTelemetry.collectLog(
                                            actionType: 'event',
                                            action: 'worldo_list_click',
                                            object1: item.oid,
                                          );
                                          Navigator.of(context).pushNamed(
                                            RouteNames.originWorld,
                                            arguments: {
                                              'originId': 0,
                                              'oid': item.oid,
                                              'initialName': item.name,
                                              'initialDefinitionVersion':
                                                  item.definitionVersion,
                                              'initialMapLocationId':
                                                  item.defaultMapLocationId,
                                            },
                                          );
                                        },
                                  child: OriginItemCard(
                                    item: item,
                                    onCoverLoaded: _isForYouFeed
                                        ? () => _handleCoverLoaded(
                                            item.oid,
                                            item.cover,
                                          )
                                        : null,
                                  ),
                                );
                                if (!_isForYouFeed) return card;
                                return VisibilityDetector(
                                  key: _exposureCardKey(item.oid),
                                  onVisibilityChanged: (info) =>
                                      _handleItemVisibilityChanged(
                                        item.oid,
                                        item.cover,
                                        info,
                                      ),
                                  child: card,
                                );
                              },
                              childCount: _items.length,
                              addAutomaticKeepAlives: false,
                              addRepaintBoundaries: true,
                            ),
                          );
                        },
                      ),
                    ),
                    if (_isLoadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          key: ValueKey<String>('origin-feed-load-more'),
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Center(
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: GenesisColors.darkTextSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _OriginListPage {
  const _OriginListPage({
    required this.items,
    required this.total,
    required this.rawData,
    this.nextScore,
    this.hasMore,
  });

  final List<OriginListItem> items;
  final int total;
  final Map<String, dynamic> rawData;
  final int? nextScore;
  final bool? hasMore;
}

_OriginListPage _parseOriginFeedPage(Map<String, dynamic> data) {
  final list = data['list'];
  final parsedItems = list is List
      ? list
            .whereType<Map>()
            .map((raw) => OriginListItem.fromJson(asJsonMap(raw)))
            .toList(growable: false)
      : const <OriginListItem>[];
  final seenIds = <String>{};
  final items = parsedItems
      .where((item) => item.oid.isNotEmpty && seenIds.add(item.oid))
      .toList(growable: false);
  return _OriginListPage(
    items: items,
    total: items.length,
    rawData: data,
    nextScore: asInt(data['next_score']),
    hasMore: asBool(data['has_more']),
  );
}

_OriginListPage _parseOriginListPage(Map<String, dynamic> data) {
  final list = data['list'];
  final items = list is List
      ? list
            .whereType<Map>()
            .map((raw) => OriginListItem.fromJson(asJsonMap(raw)))
            .toList(growable: false)
      : const <OriginListItem>[];
  return _OriginListPage(
    items: items,
    total: asInt(data['total']),
    rawData: data,
  );
}
