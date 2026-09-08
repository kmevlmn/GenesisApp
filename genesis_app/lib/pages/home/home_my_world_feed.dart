part of 'home_page.dart';

class _MyWorldFeed extends StatefulWidget {
  const _MyWorldFeed({
    required this.index,
    required this.initialRequestMetricWindow,
    required this.networkRequestsAllowed,
    required this.keepInitialNetworkFailureLoading,
    required this.localRestoreTimeout,
    this.activationListenable,
    this.reselectionListenable,
    this.isActiveListenable,
    this.isFirstPageViewReported,
    this.onFirstPageViewReady,
    this.onOpenWorldo,
    this.initialPageData,
    this.initialPageRenderOperation,
    this.initialPageRequestAttempt = 0,
    this.myWorldsCacheLoader,
  });

  final int index;
  final Duration initialRequestMetricWindow;
  final ValueListenable<bool> networkRequestsAllowed;
  final bool keepInitialNetworkFailureLoading;
  final Duration localRestoreTimeout;
  final ValueListenable<int>? activationListenable;
  final ValueListenable<int>? reselectionListenable;
  final ValueListenable<bool>? isActiveListenable;
  final bool Function(String action)? isFirstPageViewReported;
  final void Function(String action)? onFirstPageViewReady;
  final VoidCallback? onOpenWorldo;
  final Map<String, dynamic>? initialPageData;
  final FirebasePerformanceOperation? initialPageRenderOperation;
  final int initialPageRequestAttempt;
  final HomeMyWorldsCacheLoader? myWorldsCacheLoader;

  @override
  State<_MyWorldFeed> createState() => _MyWorldFeedState();
}

class _MyWorldFeedState extends State<_MyWorldFeed>
    with AutomaticKeepAliveClientMixin<_MyWorldFeed>, WidgetsBindingObserver {
  static const _pageViewAction = 'home_my_worlds';
  static const _pageSize = 10;
  static const _loadMoreThreshold = 700.0;
  static const _scrollToTopDuration = Duration(milliseconds: 240);

  TabController? _tabController;
  final ScrollController _scrollController = ScrollController();
  final List<WorldListItem> _items = <WorldListItem>[];
  final Set<String> _deletingWorldIds = <String>{};
  final Set<String> _collapsingWorldIds = <String>{};
  final Set<String> _locallyDeletedWorldIds = <String>{};
  final Map<String, double> _collapseBottomCompensation = <String, double>{};
  Timer? _startupInitialRetryTimer;
  Future<bool>? _cacheLoadFuture;
  var _nextPage = 1;
  var _total = 0;
  var _hasMore = true;
  var _hasRequested = false;
  var _initialRequestInFlight = false;
  var _hasAttemptedCachePreload = false;
  var _hasLoadedCachedPage = false;
  var _hasCompletedInitialNetworkRefresh = false;
  var _initialContentReady = false;
  var _firstPageViewReportedFallback = false;
  var _hasResolvedLocalSession = false;
  var _scrollListenerAttached = false;
  var _isInitialLoading = false;
  var _isLoadingMore = false;
  var _isRefreshing = false;
  var _isSignedOut = false;
  Object? _error;
  FirebasePerformanceOperation? _activeFirstScreenRequestOperation;
  FirebasePerformanceOperation? _activeFirstScreenRenderOperation;
  var _firstScreenRequestAttempt = 0;
  var _firstScreenRenderCompleted = false;
  var _launchRenderRevision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firstScreenRequestAttempt = widget.initialPageRequestAttempt;
    _activeFirstScreenRenderOperation = widget.initialPageRenderOperation;
    _hydrateInitialPageDataIfAvailable();
    _scheduleInitialPageRenderCompletionIfNeeded();
    widget.activationListenable?.addListener(_handlePageActivated);
    widget.reselectionListenable?.addListener(_handleMainNavReselected);
    widget.networkRequestsAllowed.addListener(_handleNetworkRequestsAllowed);
    worldDeletionEvents.addListener(_handleExternalWorldDeleted);
  }

  @override
  bool get wantKeepAlive => true;

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
    _preloadCachedItemsIfNeeded();
    _requestIfCurrentTab();
    _tryRecordFirstPageView();
  }

  @override
  void didUpdateWidget(covariant _MyWorldFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activationListenable != widget.activationListenable) {
      oldWidget.activationListenable?.removeListener(_handlePageActivated);
      widget.activationListenable?.addListener(_handlePageActivated);
    }
    if (oldWidget.reselectionListenable != widget.reselectionListenable) {
      oldWidget.reselectionListenable?.removeListener(_handleMainNavReselected);
      widget.reselectionListenable?.addListener(_handleMainNavReselected);
    }
    if (oldWidget.networkRequestsAllowed != widget.networkRequestsAllowed) {
      oldWidget.networkRequestsAllowed.removeListener(
        _handleNetworkRequestsAllowed,
      );
      widget.networkRequestsAllowed.addListener(_handleNetworkRequestsAllowed);
    }
    if (oldWidget.index != widget.index) {
      _resetListState();
      _requestIfCurrentTab();
      _tryRecordFirstPageView();
    }
  }

  @override
  void dispose() {
    _startupInitialRetryTimer?.cancel();
    if (_activeFirstScreenRequestOperation != null) {
      AppStartupCoordinator.recordLaunchRequestEnd(
        page: 'home',
        result: 'cancelled',
      );
    }
    unawaited(_activeFirstScreenRequestOperation?.cancel());
    unawaited(_activeFirstScreenRenderOperation?.cancel());
    worldDeletionEvents.removeListener(_handleExternalWorldDeleted);
    WidgetsBinding.instance.removeObserver(this);
    widget.activationListenable?.removeListener(_handlePageActivated);
    widget.reselectionListenable?.removeListener(_handleMainNavReselected);
    widget.networkRequestsAllowed.removeListener(_handleNetworkRequestsAllowed);
    _tabController?.removeListener(_handleTabChange);
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  void handleStatusBarTap() {
    if (defaultTargetPlatform != TargetPlatform.iOS || !_isPageActive) return;
    unawaited(_scrollToTop());
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final minExtent = position.minScrollExtent;
    if (position.pixels <= minExtent) return;
    await position.animateTo(
      minExtent,
      duration: _scrollToTopDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _handleMainNavReselected() {
    if (!_isPageActive) return;
    unawaited(_scrollToTop());
  }

  void _handleExternalWorldDeleted() {
    final event = worldDeletionEvents.value;
    if (event == null) return;
    _beginWorldDeletion(event.worldId);
  }

  void _resetListState() {
    _startupInitialRetryTimer?.cancel();
    unawaited(_activeFirstScreenRequestOperation?.cancel());
    unawaited(_activeFirstScreenRenderOperation?.cancel());
    _activeFirstScreenRequestOperation = null;
    _activeFirstScreenRenderOperation = null;
    _firstScreenRequestAttempt = 0;
    _firstScreenRenderCompleted = false;
    _launchRenderRevision += 1;
    _startupInitialRetryTimer = null;
    _items.clear();
    _deletingWorldIds.clear();
    _collapsingWorldIds.clear();
    _locallyDeletedWorldIds.clear();
    _collapseBottomCompensation.clear();
    _nextPage = 1;
    _total = 0;
    _cacheLoadFuture = null;
    _hasMore = true;
    _hasRequested = false;
    _initialRequestInFlight = false;
    _hasAttemptedCachePreload = false;
    _hasLoadedCachedPage = false;
    _hasCompletedInitialNetworkRefresh = false;
    _initialContentReady = false;
    _hasResolvedLocalSession = false;
    _isInitialLoading = false;
    _isLoadingMore = false;
    _isRefreshing = false;
    _isSignedOut = false;
    _error = null;
  }

  void _scheduleInitialPageRenderCompletionIfNeeded() {
    final operation = _activeFirstScreenRenderOperation;
    if (operation == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(_activeFirstScreenRenderOperation, operation) ||
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

  void _scheduleFirstScreenRenderCompletion(
    FirebasePerformanceOperation operation,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(_activeFirstScreenRenderOperation, operation) ||
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

  void _hydrateInitialPageDataIfAvailable() {
    final data = widget.initialPageData;
    if (data == null) return;
    final page = _parseWorldListPage(data);
    _items
      ..clear()
      ..addAll(page.items);
    _total = page.total;
    _nextPage = 2;
    _hasMore = _items.length < _total && page.items.isNotEmpty;
    _hasRequested = true;
    _hasAttemptedCachePreload = true;
    _hasLoadedCachedPage = true;
    _hasCompletedInitialNetworkRefresh = true;
    _initialContentReady = true;
    _hasResolvedLocalSession = true;
    _isSignedOut = false;
    _isInitialLoading = false;
    _isLoadingMore = false;
    _isRefreshing = false;
    _cacheLoadFuture = Future<bool>.value(true);
  }

  void _clearDeleteState() {
    _deletingWorldIds.clear();
    _collapsingWorldIds.clear();
    _locallyDeletedWorldIds.clear();
    _collapseBottomCompensation.clear();
  }

  void _pruneDeleteStateForCurrentItems() {
    final liveIds = _items.map((item) => item.wid.trim()).toSet();
    _deletingWorldIds.removeWhere((wid) => !liveIds.contains(wid));
    _collapsingWorldIds.removeWhere((wid) => !liveIds.contains(wid));
    _collapseBottomCompensation.removeWhere((wid, _) => !liveIds.contains(wid));
  }

  void _handleTabChange() {
    _requestIfCurrentTab();
    _tryRecordFirstPageView();
  }

  void _handleNetworkRequestsAllowed() {
    if (widget.networkRequestsAllowed.value) {
      _requestIfCurrentTab();
      _tryRecordFirstPageView();
    }
  }

  void _handlePageActivated() {
    final controller = _tabController;
    if (controller == null || controller.index != widget.index) return;
    if (!_hasRequested) {
      _requestIfCurrentTab();
      return;
    }
    if (widget.networkRequestsAllowed.value) {
      if (_hasReportedFirstPageView) {
        _recordPageView();
      } else {
        _tryRecordFirstPageView();
      }
      unawaited(
        _refreshItems(onlyIfFirstPageChanged: true, scrollToTopOnUpdate: true),
      );
    }
  }

  void _requestIfCurrentTab() {
    final controller = _tabController;
    if (controller == null ||
        controller.index != widget.index ||
        _hasRequested ||
        _initialRequestInFlight ||
        !widget.networkRequestsAllowed.value) {
      return;
    }
    _hasRequested = true;
    _initialRequestInFlight = true;
    if (_hasReportedFirstPageView) _recordPageView();
    unawaited(_requestInitialItems());
  }

  bool get _hasReportedFirstPageView =>
      widget.isFirstPageViewReported?.call(_pageViewAction) ??
      _firstPageViewReportedFallback;

  bool get _isPageActive {
    final controller = _tabController;
    return (widget.isActiveListenable?.value ?? true) &&
        controller != null &&
        controller.index == widget.index;
  }

  void _recordPageView() {
    GenesisTelemetry.collectLog(
      actionType: 'pageview',
      action: _pageViewAction,
    );
  }

  void _tryRecordFirstPageView() {
    if (!_hasRequested ||
        !_initialContentReady ||
        !_isPageActive ||
        _hasReportedFirstPageView) {
      return;
    }
    final callback = widget.onFirstPageViewReady;
    if (callback != null) {
      callback(_pageViewAction);
      return;
    }
    _firstPageViewReportedFallback = true;
    _recordPageView();
  }

  void _markInitialContentReady() {
    _initialContentReady = true;
    _tryRecordFirstPageView();
  }

  void _scheduleLaunchRender(String result) {
    final revision = ++_launchRenderRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isPageActive || revision != _launchRenderRevision) {
        return;
      }
      AppStartupCoordinator.recordLaunchRender(page: 'home', result: result);
    });
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > _loadMoreThreshold) {
      return;
    }
    _loadNextPage();
  }

  void _preloadCachedItemsIfNeeded() {
    if (_hasAttemptedCachePreload) return;
    _hasAttemptedCachePreload = true;
    unawaited(_preloadCachedItemsForSignedInSession());
  }

  Future<void> _preloadCachedItemsForSignedInSession() async {
    final hasSession = await _readLocalLoginSessionBestEffort();
    if (!mounted) return;
    if (hasSession == null) return;
    if (!hasSession) {
      setState(() {
        _items.clear();
        _clearDeleteState();
        _nextPage = 1;
        _total = 0;
        _hasMore = false;
        _error = null;
        _isInitialLoading = false;
        _isLoadingMore = false;
        _isRefreshing = false;
        _isSignedOut = true;
        _hasResolvedLocalSession = true;
      });
      return;
    }
    if (_isSignedOut || !_hasResolvedLocalSession) {
      setState(() {
        _isSignedOut = false;
        _hasResolvedLocalSession = true;
      });
    }
    await _loadCachedItemsOnce();
  }

  Future<void> _requestInitialItems() async {
    try {
      final hasSession = await _readLocalLoginSessionBestEffort();
      if (!mounted) return;
      if (hasSession == false) {
        setState(() {
          _items.clear();
          _clearDeleteState();
          _nextPage = 1;
          _total = 0;
          _hasMore = false;
          _error = null;
          _isInitialLoading = false;
          _isLoadingMore = false;
          _isRefreshing = false;
          _isSignedOut = true;
          _hasResolvedLocalSession = true;
        });
        return;
      }
      if (_items.isEmpty || _isSignedOut || !_hasResolvedLocalSession) {
        setState(() {
          if (hasSession == true) _hasResolvedLocalSession = true;
          _isSignedOut = false;
          _isInitialLoading = _items.isEmpty;
        });
      }
      // Cache restoration and the first network refresh intentionally race.
      // A fast cache can provide the first frame, while a slow or stuck cache
      // must never delay /world/list. The network completion guard in
      // _loadCachedItemsIfAvailable prevents a late cache from replacing
      // fresher network data.
      unawaited(_loadCachedItemsOnce());
      await _waitHomeInitialRequestMetricWindow(
        widget.initialRequestMetricWindow,
      );
      if (!mounted) return;
      await _refreshItems(force: true, hasConfirmedSession: hasSession == true);
    } catch (_) {
      _hasRequested = false;
      _cacheLoadFuture = null;
      _scheduleInitialRequestRetry();
    } finally {
      _initialRequestInFlight = false;
    }
  }

  Future<bool> _loadCachedItemsOnce() {
    return _cacheLoadFuture ??= _loadCachedItemsBestEffort();
  }

  Future<bool> _loadCachedItemsBestEffort() async {
    try {
      return await _loadCachedItemsIfAvailable().timeout(
        widget.localRestoreTimeout,
      );
    } catch (_) {
      _cacheLoadFuture = null;
      return false;
    }
  }

  Future<bool> _loadCachedItemsIfAvailable() async {
    final services = AppServicesScope.of(context);
    final uid = await services.sessionStore.readLoginUid();
    if (uid == null) return false;
    final loader = widget.myWorldsCacheLoader;
    final data = loader != null
        ? await loader(uid)
        : await HomeFeedCacheStore(
            ownerUid: uid,
          ).load(HomeFeedCacheKind.myWorlds);
    if (!mounted || _hasCompletedInitialNetworkRefresh) return false;
    if (data == null) {
      if (!_hasRequested) {
        setState(() {
          _isInitialLoading = false;
        });
      }
      return false;
    }

    final page = _parseWorldListPage(data);
    _startupInitialRetryTimer?.cancel();
    _startupInitialRetryTimer = null;
    setState(() {
      _items
        ..clear()
        ..addAll(page.items);
      _pruneDeleteStateForCurrentItems();
      _total = page.total;
      _nextPage = 2;
      _hasMore = _items.length < _total && page.items.isNotEmpty;
      _hasLoadedCachedPage = true;
      _error = null;
      _isInitialLoading = false;
      _isLoadingMore = false;
      _isRefreshing = false;
      _isSignedOut = false;
    });
    _markInitialContentReady();
    _scheduleLaunchRender('cache');
    return true;
  }

  Future<_WorldListPage> _fetchPage(int page) async {
    final services = AppServicesScope.of(context);
    final data = await services.api.v1.world.list(
      scene: 'mine',
      pn: page,
      rn: _pageSize,
    );
    if (page == 1) {
      _ignoreHomeFeedCacheWrite(_saveFirstPageToCache(data));
    }
    return _parseWorldListPage(data);
  }

  Future<void> _saveFirstPageToCache(Map<String, dynamic> data) async {
    final services = AppServicesScope.read(context);
    try {
      final uid =
          (await services.sessionStore.readUid().timeout(
            widget.localRestoreTimeout,
          ))?.trim() ??
          '';
      if (uid.isEmpty) return;
      await HomeFeedCacheStore(
        ownerUid: uid,
      ).save(HomeFeedCacheKind.myWorlds, data);
    } catch (_) {
      // Cache persistence is best-effort and must never delay page delivery.
    }
  }

  _WorldListPage _parseWorldListPage(Map<String, dynamic> data) {
    return _parseHomeWorldListPage(
      data,
      locallyDeletedWorldIds: _locallyDeletedWorldIds,
    );
  }

  Future<void> _refreshItems({
    bool force = false,
    bool onlyIfFirstPageChanged = false,
    bool scrollToTopOnUpdate = false,
    bool hasConfirmedSession = false,
  }) async {
    if (!widget.networkRequestsAllowed.value) return;
    if ((!force && _isInitialLoading) || _isRefreshing) return;
    if (!hasConfirmedSession) {
      final hasSession = await _readLocalLoginSessionBestEffort();
      if (hasSession == false) {
        if (!mounted) return;
        setState(() {
          _items.clear();
          _clearDeleteState();
          _nextPage = 1;
          _total = 0;
          _hasMore = false;
          _error = null;
          _isInitialLoading = false;
          _isLoadingMore = false;
          _isRefreshing = false;
          _isSignedOut = true;
          _hasResolvedLocalSession = true;
        });
        return;
      }
    }

    setState(() {
      _error = null;
      _isSignedOut = false;
      _hasResolvedLocalSession = true;
      _isInitialLoading = _items.isEmpty && !_hasLoadedCachedPage;
      _isRefreshing = true;
    });

    FirebasePerformanceOperation? requestOperation;
    final shouldTrackFirstScreen = !_firstScreenRenderCompleted;
    if (shouldTrackFirstScreen) {
      final attempt = ++_firstScreenRequestAttempt;
      requestOperation = await FirebasePerformanceOperation.start(
        surface: FirebasePerformanceSurface.myWorlds,
        phase: FirebasePerformancePhase.request,
        attempt: attempt,
      );
      if (!mounted) {
        unawaited(requestOperation.cancel());
        return;
      }
      _activeFirstScreenRequestOperation = requestOperation;
      AppStartupCoordinator.recordLaunchRequestStart(page: 'home');
    }

    try {
      final page = await _fetchPage(1);
      _hasCompletedInitialNetworkRefresh = true;
      if (!mounted) {
        unawaited(requestOperation?.cancel());
        return;
      }
      if (identical(_activeFirstScreenRequestOperation, requestOperation)) {
        _activeFirstScreenRequestOperation = null;
      }
      unawaited(requestOperation?.succeed());
      if (shouldTrackFirstScreen) {
        AppStartupCoordinator.recordLaunchRequestEnd(
          page: 'home',
          result: 'success',
        );
      }
      _startupInitialRetryTimer?.cancel();
      _startupInitialRetryTimer = null;
      if (onlyIfFirstPageChanged && !_firstPageWorldOrderChanged(page)) {
        setState(() {
          _isInitialLoading = false;
          _isRefreshing = false;
        });
        return;
      }
      final shouldReplaceItems = !_worldPageMatchesCurrent(page);
      FirebasePerformanceOperation? renderOperation;
      if (shouldTrackFirstScreen &&
          _tabController?.index == widget.index &&
          !_firstScreenRenderCompleted) {
        renderOperation = await FirebasePerformanceOperation.start(
          surface: FirebasePerformanceSurface.myWorlds,
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
        if (shouldReplaceItems) {
          _items
            ..clear()
            ..addAll(page.items);
          _pruneDeleteStateForCurrentItems();
        }
        _total = page.total;
        _nextPage = 2;
        _hasMore = _items.length < _total && page.items.isNotEmpty;
        _isInitialLoading = false;
        _isRefreshing = false;
      });
      _markInitialContentReady();
      if (shouldTrackFirstScreen) {
        _scheduleLaunchRender(page.items.isEmpty ? 'network_empty' : 'network');
      }
      if (renderOperation != null) {
        _scheduleFirstScreenRenderCompletion(renderOperation);
      }
      if (scrollToTopOnUpdate) {
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) await _scrollToTop();
      }
    } catch (error) {
      if (identical(_activeFirstScreenRequestOperation, requestOperation)) {
        _activeFirstScreenRequestOperation = null;
      }
      unawaited(
        requestOperation?.fail(errorType: firebasePerformanceErrorType(error)),
      );
      if (shouldTrackFirstScreen) {
        AppStartupCoordinator.recordLaunchRequestEnd(
          page: 'home',
          result: 'failure',
        );
      }
      if (!mounted) return;
      if (_shouldKeepInitialNetworkFailureLoading(error)) {
        setState(() {
          _error = null;
          _isInitialLoading = true;
          _isRefreshing = false;
        });
        _scheduleStartupInitialRetry();
        return;
      }
      setState(() {
        _error = error;
        _isInitialLoading = false;
        _isRefreshing = false;
      });
      if (shouldTrackFirstScreen && _items.isEmpty) {
        _scheduleLaunchRender('network_error');
      }
    }
  }

  bool _worldPageMatchesCurrent(_WorldListPage page) {
    if (_total != page.total || _items.length != page.items.length) {
      return false;
    }
    for (var index = 0; index < _items.length; index += 1) {
      if (_worldItemSignature(_items[index]) !=
          _worldItemSignature(page.items[index])) {
        return false;
      }
    }
    return true;
  }

  bool _firstPageWorldOrderChanged(_WorldListPage page) {
    final currentFirstPageLength = _items.length < _pageSize
        ? _items.length
        : _pageSize;
    if (page.items.length != currentFirstPageLength) return true;
    for (var index = 0; index < page.items.length; index += 1) {
      if (page.items[index].wid.trim() != _items[index].wid.trim()) return true;
    }
    return false;
  }

  String _worldItemSignature(WorldListItem item) {
    return <Object?>[
      item.oid,
      item.originVersionNum,
      item.originVersionCreateAt,
      item.wid,
      item.status,
      item.name,
      item.deleted,
      item.cover,
      item.displaySubtitle,
      item.createdUid,
      item.createdUserName,
      item.ownerUid,
      item.ownerName,
      item.createdAt,
      item.lastActiveAt,
      item.updatedAt,
      item.lastProgressAt,
      item.lastProgressSummary,
      item.lastProgressTickNo,
      item.lastProgressSubTickNo,
      item.lastProgressCurrentTime,
      item.previewImages.join('\n'),
      item.tags.join('\n'),
      item.tickCnt,
      item.connectCnt,
      item.aiCharacterCnt,
      item.playerCnt,
      item.locationCnt,
    ].join('\u001F');
  }

  bool _shouldKeepInitialNetworkFailureLoading(Object error) {
    return widget.keepInitialNetworkFailureLoading &&
        _items.isEmpty &&
        !_hasLoadedCachedPage &&
        !_isSignedOut &&
        _isNetworkLikeHomeError(error);
  }

  void _scheduleStartupInitialRetry() {
    if (_startupInitialRetryTimer?.isActive ?? false) return;
    _startupInitialRetryTimer = Timer(_homeInitialNetworkRetryDelay, () {
      _startupInitialRetryTimer = null;
      if (!mounted || !widget.networkRequestsAllowed.value) return;
      final controller = _tabController;
      if (controller == null || controller.index != widget.index) return;
      unawaited(_refreshItems(force: true));
    });
  }

  void _scheduleInitialRequestRetry() {
    if (_startupInitialRetryTimer?.isActive ?? false) return;
    _startupInitialRetryTimer = Timer(_homeInitialNetworkRetryDelay, () {
      _startupInitialRetryTimer = null;
      if (!mounted || !widget.networkRequestsAllowed.value) return;
      _requestIfCurrentTab();
    });
  }

  Future<bool?> _readLocalLoginSessionBestEffort() async {
    try {
      return await _hasLocalLoginSession().timeout(widget.localRestoreTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _hasLocalLoginSession() async {
    final services = AppServicesScope.read(context);
    return await services.sessionStore.readLoginUid() != null;
  }

  Future<void> _loadNextPage() async {
    if (!widget.networkRequestsAllowed.value ||
        !_hasMore ||
        _isInitialLoading ||
        _isLoadingMore ||
        _isRefreshing) {
      return;
    }
    setState(() {
      _isLoadingMore = true;
      _error = null;
    });

    try {
      final page = await _fetchPage(_nextPage);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _pruneDeleteStateForCurrentItems();
        _total = page.total;
        _nextPage += 1;
        _hasMore = _items.length < _total && page.items.isNotEmpty;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoadingMore = false;
      });
    }
  }

  double get _collapseCompensation {
    return _collapseBottomCompensation.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
  }

  void _setCollapseCompensation(String worldId, double value) {
    if (worldId.isEmpty) return;
    final normalized = value <= 0.5 ? 0.0 : value;
    final current = _collapseBottomCompensation[worldId] ?? 0;
    if ((current - normalized).abs() <= 0.5) return;
    if (!mounted) return;
    setState(() {
      if (normalized == 0) {
        _collapseBottomCompensation.remove(worldId);
      } else {
        _collapseBottomCompensation[worldId] = normalized;
      }
    });
  }

  void _handleWorldCollapseCompleted(String worldId) {
    if (worldId.isEmpty || !mounted) return;
    setState(() {
      _items.removeWhere((item) => item.wid.trim() == worldId);
      _deletingWorldIds.remove(worldId);
      _collapsingWorldIds.remove(worldId);
      _collapseBottomCompensation.remove(worldId);
      if (_total > 0) {
        _total -= 1;
      }
      _hasMore = _items.length < _total && _items.isNotEmpty;
    });
  }

  Future<void> _openWorld(WorldListItem item) async {
    GenesisTelemetry.collectLog(
      actionType: 'event',
      action: 'home_my_worlds_click',
      object1: item.wid,
    );
    final result = await Navigator.of(context).pushNamed<WorldPageResult>(
      RouteNames.world,
      arguments: {
        'wid': item.wid,
        'initialName': item.name,
        'initiallyLaunched': true,
        'initialDefinitionVersion': item.definitionVersion,
        'initialMapLocationId': item.defaultMapLocationId,
      },
    );
    if (!mounted || result == null) return;
    _beginWorldDeletion(result.deletedWorldId);
  }

  void _beginWorldDeletion(String rawWorldId) {
    final deletedWorldId = rawWorldId.trim();
    if (!mounted ||
        deletedWorldId.isEmpty ||
        _collapsingWorldIds.contains(deletedWorldId)) {
      return;
    }
    final hasVisibleItem = _items.any(
      (item) => item.wid.trim() == deletedWorldId,
    );
    setState(() {
      _locallyDeletedWorldIds.add(deletedWorldId);
      _deletingWorldIds.remove(deletedWorldId);
      if (hasVisibleItem) {
        _collapsingWorldIds.add(deletedWorldId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final waitingForStartupNetwork = !widget.networkRequestsAllowed.value;
    if (!waitingForStartupNetwork &&
        _hasResolvedLocalSession &&
        !_isSignedOut &&
        (_isInitialLoading ||
            (!_hasRequested && !_hasLoadedCachedPage && _items.isEmpty))) {
      return const GenesisListLoadingSkeleton.worldList();
    }

    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Load failed',
              style: TextStyle(color: GenesisColors.darkTextPrimary),
            ),
            const SizedBox(height: 10),
            FilledButton(onPressed: _refreshItems, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_items.isEmpty && !_hasResolvedLocalSession) {
      return ListView(
        key: const PageStorageKey<String>('home-feed-my-world-pending'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: MediaQuery.sizeOf(context).height * 0.62)],
      );
    }

    final emptyListView = ListView(
      key: const PageStorageKey<String>('home-feed-my-world'),
      physics: _isSignedOut
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: _MyWorldsEmptyState(onTap: widget.onOpenWorldo),
        ),
      ],
    );

    if (_items.isEmpty && _isSignedOut) {
      return emptyListView;
    }

    return RefreshIndicator(
      backgroundColor: GenesisColors.darkRaisedBackground,
      color: GenesisColors.darkTextSecondary,
      onRefresh: _refreshItems,
      child: _items.isEmpty
          ? emptyListView
          : ListView.builder(
              key: const PageStorageKey<String>('home-feed-my-world'),
              controller: _scrollController,
              primary: false,
              scrollCacheExtent: const ScrollCacheExtent.pixels(900),
              padding: EdgeInsets.only(
                top: 10,
                bottom: 36 + _collapseCompensation,
              ),
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              itemCount: _items.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _items.length) {
                  return const Padding(
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
                  );
                }
                final vm = _items[index];
                final worldId = vm.wid.trim();
                final isDeleting = _deletingWorldIds.contains(worldId);
                final isCollapsing = _collapsingWorldIds.contains(worldId);
                final canInteract = !vm.deleted && !isDeleting && !isCollapsing;
                return _AnimatedHomeWorldListItem(
                  key: ValueKey<String>('home-my-world-$worldId'),
                  isCollapsing: isCollapsing,
                  bottomSpacing: index == _items.length - 1 && !_isLoadingMore
                      ? 0
                      : 30,
                  onCollapseCompensationChanged: (value) =>
                      _setCollapseCompensation(worldId, value),
                  onCollapsed: () => _handleWorldCollapseCompleted(worldId),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: canInteract ? () => unawaited(_openWorld(vm)) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: WorldItemCard(item: vm),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
