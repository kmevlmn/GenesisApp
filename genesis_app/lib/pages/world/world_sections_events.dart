// ignore_for_file: use_key_in_widget_constructors

part of 'world_sections_library.dart';

List<Map<String, dynamic>> worldEventTicksAscending(
  List<Map<String, dynamic>> ticks,
) {
  final indexedTicks = ticks.indexed.toList(growable: false);
  indexedTicks.sort((a, b) {
    final tickCompare = worldEventTickNumber(
      a.$2,
    ).compareTo(worldEventTickNumber(b.$2));
    if (tickCompare != 0) return tickCompare;
    final subTickCompare = worldEventSubTickNumber(
      a.$2,
    ).compareTo(worldEventSubTickNumber(b.$2));
    if (subTickCompare != 0) return subTickCompare;
    return a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexedTicks) entry.$2];
}

List<Map<String, dynamic>> worldMergeEventTicksAscending(
  List<Map<String, dynamic>> existing,
  List<Map<String, dynamic>> incoming,
) {
  final keyedTicks = <String, Map<String, dynamic>>{};
  final unkeyedTicks = <Map<String, dynamic>>[];
  for (final tick in [...existing, ...incoming]) {
    final key = worldEventTickIdentity(tick);
    if (key.isEmpty) {
      unkeyedTicks.add(tick);
      continue;
    }
    keyedTicks[key] = tick;
  }
  return worldEventTicksAscending([...keyedTicks.values, ...unkeyedTicks]);
}

String worldEventTickIdentity(Map<String, dynamic> tick) {
  final subTickNo = worldEventSubTickNumber(tick);
  final tickId = worldMapString(tick, const ['tick_id', 'id']);
  if (tickId.isNotEmpty) return 'id:$tickId:sub:$subTickNo';
  final tickNo = worldEventTickNumber(tick);
  if (tickNo > 0) return 'no:$tickNo:sub:$subTickNo';
  return '';
}

int worldEventTickNumber(Map<String, dynamic> tick) {
  final tickNo = worldMapString(tick, const ['tick_no', 'tick_number', 'no']);
  final parsed = int.tryParse(tickNo);
  if (parsed != null) return parsed;

  final id = worldMapString(tick, const ['tick_id', 'id']);
  final suffix = RegExp(r'(\d+)$').firstMatch(id)?.group(1);
  return int.tryParse(suffix ?? '') ?? 0;
}

int worldEventSubTickNumber(Map<String, dynamic> tick) {
  final subTickNo = worldMapString(tick, const [
    'sub_tick_no',
    'sub_tick_number',
  ]);
  return int.tryParse(subTickNo) ?? 0;
}

List<List<Map<String, dynamic>>> worldEventTickPagesAscending(
  List<Map<String, dynamic>> ticks,
) {
  final pages = <List<Map<String, dynamic>>>[];
  for (final tick in worldEventTicksAscending(ticks)) {
    final tickNo = worldEventTickNumber(tick);
    if (pages.isNotEmpty && worldEventTickNumber(pages.last.first) == tickNo) {
      pages.last.add(tick);
    } else {
      pages.add(<Map<String, dynamic>>[tick]);
    }
  }
  return pages;
}

String worldEventTickPageIdentity(List<Map<String, dynamic>> ticks) {
  if (ticks.isEmpty) return '';
  final tickNo = worldEventTickNumber(ticks.first);
  return 'tick:$tickNo';
}

class WorldEventsSection extends StatefulWidget {
  const WorldEventsSection({
    super.key,
    this.scrollController,
    required this.world,
    required this.ticks,
    required this.initialLoading,
    required this.loadingMore,
    required this.hasMore,
    required this.error,
    required this.latestRevision,
    required this.targetTickNumber,
    required this.contentPadding,
    required this.onLoadMore,
  });

  final ScrollController? scrollController;
  final WorldDetail world;
  final List<Map<String, dynamic>> ticks;
  final bool initialLoading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;
  final int latestRevision;
  final int? targetTickNumber;
  final EdgeInsetsGeometry contentPadding;
  final VoidCallback onLoadMore;

  @override
  State<WorldEventsSection> createState() => WorldEventsSectionState();
}

class WorldEventsSectionState extends State<WorldEventsSection> {
  static const int _loadMorePageThreshold = 3;
  static const Duration _pageTurnDuration = Duration(milliseconds: 260);

  late final PageController _pageController = PageController();
  final _tickCardResetRevisions = <String, int>{};
  final _tickCardAlignLatestSubTick = <String, bool>{};
  var _currentPage = 0;
  var _currentTickIdentity = '';
  var _animatingPage = false;
  var _showLatestWhenTicksArrive = true;

  int? get _requestedTickNumber {
    final target = widget.targetTickNumber;
    return target == null || target <= 0 ? null : target;
  }

  @override
  void initState() {
    super.initState();
    if (_setCurrentPageToRequestedTargetOrLatestIfAvailable()) {
      _jumpToCurrentPage();
    }
  }

  @override
  void didUpdateWidget(covariant WorldEventsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final worldChanged = oldWidget.world.worldId != widget.world.worldId;
    if (worldChanged) {
      _currentPage = 0;
      _currentTickIdentity = '';
      _showLatestWhenTicksArrive = true;
      if (_setCurrentPageToRequestedTargetOrLatestIfAvailable()) {
        _jumpToCurrentPage();
      }
      return;
    }

    if (oldWidget.latestRevision != widget.latestRevision ||
        oldWidget.targetTickNumber != widget.targetTickNumber) {
      _showLatestWhenTicksArrive = true;
      if (_setCurrentPageToRequestedTargetOrLatestIfAvailable()) {
        _jumpToCurrentPage();
        _maybeLoadPendingTarget();
      }
      return;
    }

    if (_currentTickIdentity.isEmpty) {
      if (_setCurrentPageToRequestedTargetOrLatestIfAvailable()) {
        _jumpToCurrentPage();
        _maybeLoadMoreForPage(_currentPage);
      }
      return;
    }

    final nextIndex = _findPageByIdentity(_currentTickIdentity);
    if (_isPendingTargetIdentity(_currentTickIdentity)) {
      _maybeLoadPendingTarget();
    }
    if (nextIndex < 0) {
      if (_isPendingTargetIdentity(_currentTickIdentity) &&
          _setCurrentPageToRequestedTargetOrLatestIfAvailable()) {
        _jumpToCurrentPage();
        _maybeLoadMoreForPage(_currentPage);
        _maybeLoadPendingTarget();
        return;
      }
      _currentPage = _currentPage.clamp(0, _maxRenderedPage).toInt();
      _currentTickIdentity = _pageIdentityAt(_currentPage);
      _bumpTickCardResetRevisionAt(_currentPage);
      _jumpToCurrentPage();
      return;
    }
    if (nextIndex != _currentPage) {
      _currentPage = nextIndex;
      _bumpTickCardResetRevisionAt(_currentPage);
      _jumpToCurrentPage();
      _maybeLoadMoreForPage(_currentPage);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<List<Map<String, dynamic>>> get _visibleTickPages {
    return worldEventTickPagesAscending(widget.ticks);
  }

  int get _maxRenderedPage => math.max(0, _pageCount - 1);

  int get _pageCount {
    final pendingTargetPage = _pendingTargetPage;
    if (pendingTargetPage == null) return _visibleTickPages.length;
    return _visibleTickPages.length + 1;
  }

  int? get _pendingTargetPage {
    final target = _requestedTickNumber;
    if (target == null || _pageIndexForTickNumber(target) != null) {
      return null;
    }
    if (!widget.initialLoading && !widget.loadingMore && !widget.hasMore) {
      return null;
    }
    return _insertionPageForTickNumber(target);
  }

  bool _setCurrentPageToRequestedTargetOrLatestIfAvailable() {
    final visibleTickPages = _visibleTickPages;
    final requestedTickNumber = _requestedTickNumber;
    if (requestedTickNumber != null) {
      final resolvedTargetPage = _pageIndexForTickNumber(requestedTickNumber);
      final pendingTargetPage = _pendingTargetPage;
      if (resolvedTargetPage != null || pendingTargetPage != null) {
        final targetPage = resolvedTargetPage ?? pendingTargetPage!;
        _currentPage = targetPage.clamp(0, _maxRenderedPage).toInt();
        _currentTickIdentity = _pageIdentityAt(_currentPage);
        _showLatestWhenTicksArrive = false;
        _bumpTickCardResetRevisionAt(_currentPage, alignLatestSubTick: true);
        return _pageCount > 0;
      }
    }
    if (visibleTickPages.isEmpty) return false;
    final target = _showLatestWhenTicksArrive ? _maxRenderedPage : _currentPage;
    _currentPage = target.clamp(0, _maxRenderedPage).toInt();
    _currentTickIdentity = _pageIdentityAt(_currentPage);
    _showLatestWhenTicksArrive = false;
    _bumpTickCardResetRevisionAt(_currentPage, alignLatestSubTick: true);
    return true;
  }

  void _jumpToCurrentPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_pageController.hasClients) {
        _jumpToCurrentPage();
        return;
      }
      final target = _currentPage.clamp(0, _maxRenderedPage).toInt();
      _pageController.jumpToPage(target);
    });
  }

  void _handlePageChanged(int page) {
    final nextPage = page.clamp(0, _maxRenderedPage).toInt();
    _currentPage = nextPage;
    _currentTickIdentity = _pageIdentityAt(_currentPage);
    if (widget.scrollController != null) setState(() {});
    _maybeLoadMoreForPage(_currentPage);
  }

  void _maybeLoadMoreForPage(int page) {
    if (!widget.hasMore || widget.loadingMore || widget.initialLoading) return;
    if (page <= _loadMorePageThreshold) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !widget.hasMore ||
            widget.loadingMore ||
            widget.initialLoading) {
          return;
        }
        widget.onLoadMore();
      });
    }
  }

  void _maybeLoadPendingTarget() {
    if (_requestedTickNumber == null ||
        _pendingTargetPage == null ||
        !widget.hasMore ||
        widget.loadingMore ||
        widget.initialLoading) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _requestedTickNumber == null ||
          _pendingTargetPage == null ||
          !widget.hasMore ||
          widget.loadingMore ||
          widget.initialLoading) {
        return;
      }
      widget.onLoadMore();
    });
  }

  void _bumpTickCardResetRevisionAt(
    int page, {
    bool alignLatestSubTick = false,
  }) {
    final identity = _pageIdentityAt(page);
    if (identity.isEmpty) return;
    _tickCardResetRevisions[identity] =
        (_tickCardResetRevisions[identity] ?? 0) + 1;
    _tickCardAlignLatestSubTick[identity] = alignLatestSubTick;
  }

  void _turnPage(int delta) {
    if (_animatingPage || !_pageController.hasClients) return;
    final target = (_currentPage + delta).clamp(0, _maxRenderedPage).toInt();
    if (target == _currentPage) {
      _maybeLoadMoreForPage(_currentPage);
      return;
    }
    _animatingPage = true;
    setState(
      () => _bumpTickCardResetRevisionAt(target, alignLatestSubTick: delta < 0),
    );
    unawaited(
      _pageController
          .animateToPage(
            target,
            duration: _pageTurnDuration,
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (!mounted) return;
            _animatingPage = false;
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingTargetPage = _pendingTargetPage;
    final hasPendingTargetPage = pendingTargetPage != null;
    if (widget.ticks.isEmpty &&
        widget.initialLoading &&
        !hasPendingTargetPage) {
      return ListView(
        controller: widget.scrollController,
        physics: const ClampingScrollPhysics(),
        padding: widget.contentPadding,
        children: const [WorldEventLoadingSkeleton()],
      );
    }
    if (widget.ticks.isEmpty && !hasPendingTargetPage) {
      return ListView(
        controller: widget.scrollController,
        physics: const ClampingScrollPhysics(),
        padding: widget.contentPadding,
        children: [
          WorldEmptySection(
            text: widget.error == null
                ? 'No events yet.'
                : 'Load events failed.',
            fontSize: 14,
          ),
        ],
      );
    }

    final locationsById = <String, Map<String, dynamic>>{
      for (final location in widget.world.locations)
        worldMapString(location, const ['location_id', 'id']): location,
    }..remove('');
    final charactersById = <String, Map<String, dynamic>>{
      for (final character in widget.world.characters)
        worldMapString(character, const ['char_id', 'character_id', 'id']):
            character,
    }..remove('');
    final fallbackBody = worldEventBody(widget.world);
    final metricUnit = worldMapString(widget.world.metric, const ['unit']);
    final visibleTickPages = _visibleTickPages;

    return Stack(
      children: [
        PageView.builder(
          key: const ValueKey<String>('world-events-tick-pager'),
          controller: _pageController,
          scrollDirection: Axis.vertical,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _pageCount,
          onPageChanged: _handlePageChanged,
          itemBuilder: (context, index) {
            if (index == pendingTargetPage) {
              final tickNumber = _requestedTickNumber ?? widget.world.tickCount;
              return WorldTickEventCardPage(
                key: ValueKey<String>('world-event-tick-pending-$tickNumber'),
                scrollController: index == _currentPage
                    ? widget.scrollController
                    : null,
                resetRevision:
                    _tickCardResetRevisions['pending_tick:$tickNumber'] ?? 0,
                hasTopEdgePage: index > 0,
                hasBottomEdgePage: index < _pageCount - 1,
                padding: widget.contentPadding,
                onTurnPage: _turnPage,
                child: WorldTickPendingEventPage(tickNumber: tickNumber),
              );
            }
            final tickPageIndex = _tickPageIndexForPage(index);
            if (tickPageIndex == null) return const SizedBox.shrink();
            final ticks = visibleTickPages[tickPageIndex];
            final pageIdentity = worldEventTickPageIdentity(ticks);
            final tickNumber = worldTickEventNumber(
              ticks.first,
              fallback: tickPageIndex + 1,
            );
            final showsAiDisclaimer = tickPageIndex == 0 && !widget.hasMore;
            return WorldTickEventCardPage(
              key: ValueKey<String>('world-event-tick-$pageIdentity'),
              scrollController: index == _currentPage
                  ? widget.scrollController
                  : null,
              resetRevision: _tickCardResetRevisions[pageIdentity] ?? 0,
              alignLastItemToTop:
                  _tickCardAlignLatestSubTick[pageIdentity] ?? false,
              hasTopEdgePage: index > 0,
              hasBottomEdgePage: index < _pageCount - 1,
              padding: widget.contentPadding,
              onTurnPage: _turnPage,
              itemCount: ticks.length + (showsAiDisclaimer ? 1 : 0),
              itemBuilder: (context, itemIndex) {
                if (showsAiDisclaimer && itemIndex == 0) {
                  return const AiContentDisclaimer(
                    textColor: GenesisColors.darkTextTertiary,
                    padding: EdgeInsets.fromLTRB(10, 0, 10, 18),
                    textAlign: TextAlign.left,
                  );
                }
                final subTickIndex = itemIndex - (showsAiDisclaimer ? 1 : 0);
                final tick = ticks[subTickIndex];
                return WorldTickEventItem(
                  key: ValueKey<String>(
                    'world-event-tick-item-${worldEventTickIdentity(tick)}',
                  ),
                  tick: tick,
                  useChatEventStyle: true,
                  tickNumber: tickNumber,
                  subTickNumber: worldEventSubTickNumber(tick),
                  fallbackBody: fallbackBody,
                  locationsById: locationsById,
                  charactersById: charactersById,
                  dateLabel: worldTickParagraphTimestamp(tick),
                  stackedContent: true,
                  contentLabelStyle: _worldEventContentLabelStyle,
                  contentTextStyle: _worldEventContentTextStyle,
                  contentTimestampStyle: _worldEventContentTimestampStyle,
                  metricUnit: metricUnit,
                  showParagraphClue: true,
                  isLast: subTickIndex == ticks.length - 1,
                );
              },
            );
          },
        ),
        if (widget.loadingMore)
          const IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: WorldEventsLoadingMoreIndicator(),
            ),
          ),
      ],
    );
  }

  int? _tickPageIndexForPage(int page) {
    final pendingTargetPage = _pendingTargetPage;
    final tickPageIndex = pendingTargetPage != null && page > pendingTargetPage
        ? page - 1
        : page;
    if (tickPageIndex < 0 || tickPageIndex >= _visibleTickPages.length) {
      return null;
    }
    return tickPageIndex;
  }

  String _pageIdentityAt(int page) {
    final pendingTargetPage = _pendingTargetPage;
    if (pendingTargetPage != null && page == pendingTargetPage) {
      return 'pending_tick:${_requestedTickNumber ?? 0}';
    }
    final tickPageIndex = _tickPageIndexForPage(page);
    if (tickPageIndex == null) return '';
    return worldEventTickPageIdentity(_visibleTickPages[tickPageIndex]);
  }

  int _findPageByIdentity(String identity) {
    for (var page = 0; page < _pageCount; page += 1) {
      if (_pageIdentityAt(page) == identity) return page;
    }
    return -1;
  }

  bool _isPendingTargetIdentity(String identity) {
    final target = _requestedTickNumber;
    return target != null && identity == 'pending_tick:$target';
  }

  int? _pageIndexForTickNumber(int targetTickNumber) {
    final tickPageIndex = _visibleTickPages.indexWhere(
      (ticks) => worldTickEventNumber(ticks.first) == targetTickNumber,
    );
    if (tickPageIndex < 0) return null;
    return tickPageIndex;
  }

  int _insertionPageForTickNumber(int targetTickNumber) {
    final visibleTickPages = _visibleTickPages;
    for (var index = 0; index < visibleTickPages.length; index += 1) {
      final tickNumber = worldTickEventNumber(visibleTickPages[index].first);
      if (tickNumber >= targetTickNumber) return index;
    }
    return visibleTickPages.length;
  }
}
