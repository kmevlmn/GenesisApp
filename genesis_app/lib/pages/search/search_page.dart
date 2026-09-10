import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../components/common/copyable_id_label.dart';
import '../../components/common/list_loading_skeleton.dart';
import '../../components/origin/stat_item.dart';
import '../../components/page_header.dart';
import '../../components/search_bar.dart';
import '../../icons/custom_icon_assets.dart';
import '../../network/json_utils.dart';
import '../../network/models/search_v2.dart';
import '../../platform/session/session_revision_subscription.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_avatar.dart';
import '../../ui/components/genesis_refresh_indicator.dart';
import '../../ui/components/genesis_safe_area.dart';
import '../../ui/system/genesis_system_ui.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import '../../ui/components/genesis_list_image.dart';
import '../../ui/components/genesis_origin_list_card_layout.dart';
import '../../ui/components/genesis_world_list_card_layout.dart';
import '../../ui/components/secend_tabs.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/tokens/genesis_typography.dart';
import '../../ui/tokens/genesis_origin_card_geometry.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/entity_deleted.dart';
import '../../utils/stat_count_formatter.dart';
import '../world/world_page_result.dart';
import 'search_history_store.dart';

part 'search_history_panel.dart';
part 'search_result_list.dart';
part 'search_result_tiles.dart';
part 'search_result_models.dart';
part 'search_tab_label.dart';

enum _SearchTab {
  origin('origin', 'Worldo'),
  world('world', 'World'),
  user('user', 'User');

  const _SearchTab(this.apiType, this.label);

  final String apiType;
  final String label;
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  static const Duration _debounceDuration = Duration(
    milliseconds: 600,
  ); // API rate limit is 1 request per second, so 600ms is a good balance between responsiveness and reducing unnecessary requests.
  static const int _pageSize = 20;
  static const int _minSearchLength = 3;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final TabController _tabController;
  late final Map<_SearchTab, _SearchTabResults> _results;
  late final SessionRevisionSubscription _sessionRevision;
  final Map<_SearchTab, int> _tabTotals = <_SearchTab, int>{};

  Timer? _debounceTimer;
  int _requestToken = 0;
  String _activeQuery = '';
  bool _hasInput = false;
  bool _isSelectingDefaultTab = false;
  List<String> _searchHistory = <String>[];
  var _sessionListGeneration = 0;
  var _didLoadSessionData = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _SearchTab.values.length,
      vsync: this,
    )..addListener(_handleTabChanged);
    _results = {for (final tab in _SearchTab.values) tab: _SearchTabResults()};
    _sessionRevision = SessionRevisionSubscription(_handleSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sessionRevision.bind(AppServicesScope.of(context).sessionRevision);
    if (_didLoadSessionData) return;
    _didLoadSessionData = true;
    unawaited(_loadSearchHistory());
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    _controller.dispose();
    _focusNode.dispose();
    _sessionRevision.dispose();
    super.dispose();
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    _debounceTimer?.cancel();
    final query = _controller.text.trim();
    final searchable = _isSearchableQuery(query);
    final token = ++_requestToken;
    setState(() {
      _sessionListGeneration += 1;
      _searchHistory = <String>[];
      _activeQuery = searchable ? query : '';
      _hasInput = searchable;
      _resetAllTabs();
      if (searchable) _markAllTabsStale();
    });
    unawaited(_loadSearchHistory());
    if (searchable) {
      unawaited(_refreshTab(_selectedTab, token: token));
    }
  }

  Future<void> _loadSearchHistory() async {
    final revision = _sessionRevision.value;
    final history = await (await _historyStore()).load();
    if (!mounted || !_sessionRevision.matches(revision)) return;
    setState(() {
      _searchHistory = history;
    });
  }

  Future<void> _recordActiveSearchQuery() async {
    final query = _activeQuery.trim();
    if (query.isEmpty) return;
    final revision = _sessionRevision.value;
    final history = await (await _historyStore()).add(query);
    if (!mounted || !_sessionRevision.matches(revision)) return;
    setState(() {
      _searchHistory = history;
    });
  }

  Future<SearchHistoryStore> _historyStore() async {
    final uid =
        (await AppServicesScope.read(context).sessionStore.readUid())?.trim() ??
        '';
    return SearchHistoryStore(ownerUid: uid);
  }

  void _onQueryChanged(String raw) {
    _debounceTimer?.cancel();
    _requestToken += 1;
    final token = _requestToken;
    final query = raw.trim();

    if (!_isSearchableQuery(query)) {
      setState(() {
        _activeQuery = '';
        _hasInput = false;
        _resetAllTabs();
      });
      return;
    }

    setState(() {
      _hasInput = true;
      _isSelectingDefaultTab = true;
      _tabController.index = _defaultSearchTab(query).index;
      _isSelectingDefaultTab = false;
    });

    _debounceTimer = Timer(_debounceDuration, () {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _activeQuery = query;
        _markAllTabsStale();
      });
      unawaited(_refreshTab(_selectedTab, token: token));
    });
  }

  void _resetAllTabs() {
    _tabTotals.clear();
    for (final state in _results.values) {
      state.reset();
    }
  }

  void _markAllTabsStale() {
    _tabTotals.clear();
    for (final state in _results.values) {
      state.hasRequested = false;
      state.hasSuccessfulResponse = false;
      state.isInitialLoading = false;
      state.isLoadingMore = false;
      state.error = null;
      state.requestToken = 0;
    }
  }

  bool get _hasRenderedResults {
    return _results.values.any((state) => state.items.isNotEmpty);
  }

  _SearchTab get _selectedTab => _SearchTab.values[_tabController.index];

  void _handleTabChanged() {
    if (_isSelectingDefaultTab) return;
    final tab = _selectedTab;
    final state = _results[tab]!;
    if (_activeQuery.isEmpty || state.hasRequested) return;
    unawaited(_refreshTab(tab, token: _requestToken));
  }

  Future<void> _refreshTab(_SearchTab tab, {required int token}) async {
    final query = _activeQuery;
    if (query.isEmpty) return;
    final state = _results[tab]!;
    setState(() {
      state
        ..hasRequested = true
        ..hasSuccessfulResponse = false
        ..isInitialLoading = state.items.isEmpty
        ..isLoadingMore = false
        ..error = null
        ..requestToken = token;
    });

    try {
      final page = await _fetchPage(tab, query: query, pageNumber: 1);
      if (kDebugMode) {
        debugPrint(
          '[SearchPage] search query="$query" type=${tab.apiType} pn=1 '
          'items=${page.items.length} total=${page.total}',
        );
      }
      if (!_acceptsResult(token, query)) return;
      setState(() {
        state
          ..items.clear()
          ..items.addAll(page.items)
          ..total = page.total
          ..nextPage = 2
          ..hasMore = page.hasMore
          ..hasSuccessfulResponse = true
          ..isInitialLoading = false
          ..error = null;
        _tabTotals.addAll(page.tabTotals);
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[SearchPage] search failed query="$query" type=${tab.apiType}: '
          '$error',
        );
      }
      if (!_acceptsResult(token, query)) return;
      setState(() {
        state
          ..hasSuccessfulResponse = false
          ..isInitialLoading = false
          ..error = state.items.isEmpty ? error : null;
      });
    }
  }

  Future<void> _loadNextPage(_SearchTab tab) async {
    final state = _results[tab]!;
    final query = _activeQuery;
    final token = _requestToken;
    if (query.isEmpty ||
        !state.hasMore ||
        state.isInitialLoading ||
        state.isLoadingMore) {
      return;
    }

    setState(() {
      state
        ..isLoadingMore = true
        ..error = null
        ..requestToken = token;
    });

    try {
      final page = await _fetchPage(
        tab,
        query: query,
        pageNumber: state.nextPage,
      );
      if (kDebugMode) {
        debugPrint(
          '[SearchPage] search load more query="$query" type=${tab.apiType} '
          'pn=${state.nextPage} items=${page.items.length} total=${page.total}',
        );
      }
      if (!_acceptsResult(token, query)) return;
      setState(() {
        state
          ..items.addAll(page.items)
          ..total = page.total
          ..nextPage += 1
          ..hasMore = page.hasMore
          ..isLoadingMore = false
          ..error = null;
        _tabTotals.addAll(page.tabTotals);
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[SearchPage] search load more failed query="$query" '
          'type=${tab.apiType}: $error',
        );
      }
      if (!_acceptsResult(token, query)) return;
      setState(() {
        state
          ..isLoadingMore = false
          ..error = error;
      });
    }
  }

  bool _acceptsResult(int token, String query) {
    return mounted && token == _requestToken && query == _activeQuery;
  }

  Future<_SearchPageResult> _fetchPage(
    _SearchTab tab, {
    required String query,
    required int pageNumber,
  }) async {
    final response = await AppServicesScope.of(context).api.v1.search.search(
      query: query,
      type: tab.apiType,
      pn: pageNumber,
      rn: _pageSize,
    );
    final tabTotals = <_SearchTab, int>{
      _SearchTab.origin: response.origins.total,
      _SearchTab.world: response.worlds.total,
      _SearchTab.user: response.users.total,
    };
    return switch (tab) {
      _SearchTab.origin => _SearchPageResult(
        items: response.origins.items
            .map(
              (item) =>
                  _SearchResultItem.fromV2Origin(item, searchQuery: query),
            )
            .toList(growable: false),
        total: response.origins.total,
        hasMore: response.origins.hasMore,
        tabTotals: tabTotals,
      ),
      _SearchTab.world => _SearchPageResult(
        items: response.worlds.items
            .map(
              (item) => _SearchResultItem.fromV2World(item, searchQuery: query),
            )
            .toList(growable: false),
        total: response.worlds.total,
        hasMore: response.worlds.hasMore,
        tabTotals: tabTotals,
      ),
      _SearchTab.user => _SearchPageResult(
        items: response.users.items
            .map(
              (item) => _SearchResultItem.fromV2User(item, searchQuery: query),
            )
            .toList(growable: false),
        total: response.users.total,
        hasMore: response.users.hasMore,
        tabTotals: tabTotals,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return GenesisDarkTheme(
      child: GenesisBottomSystemBarStyleScope(
        style: const GenesisBottomSystemBarStyle(
          color: GenesisColors.darkBackground,
        ),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: kGenesisLightSystemUiOverlayStyle,
          child: Scaffold(
            backgroundColor: GenesisColors.darkBackground,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: kGenesisTopBarHeight,
                      child: Transform.translate(
                        offset: const Offset(0, 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: SearchBarPlaceholder(
                                backgroundColor: GenesisColors.darkFaintFill,
                                borderColor: null,
                                controller: _controller,
                                focusNode: _focusNode,
                                onChanged: _onQueryChanged,
                                onClear: () {
                                  _controller.clear();
                                  _onQueryChanged('');
                                  setState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 14),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => Navigator.of(context).pop(),
                              child: const SizedBox(
                                height: 28,
                                child: Center(
                                  child: Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: GenesisColors.darkTextPrimary,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_hasInput)
                    SecendTabs(
                      labelColor: GenesisColors.darkTextPrimary,
                      unselectedLabelColor: GenesisColors.darkTextSecondary,
                      indicatorColor: GenesisColors.redPrimary,
                      controller: _tabController,
                      labels: [for (final tab in _SearchTab.values) tab.label],
                      labelWidgets: [
                        for (final tab in _SearchTab.values)
                          _SearchTabLabel(
                            key: ValueKey<String>('search-tab-${tab.name}'),
                            tab: tab,
                            total: _tabTotals[tab],
                          ),
                      ],
                      horizontalPadding: 16,
                      labelPadding: const EdgeInsets.only(right: 42),
                      verticalPadding: 0,
                    ),
                  Expanded(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (_) => _dismissKeyboard(),
                      child: _buildBody(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_hasInput) {
      return _SearchHistoryPanel(
        queries: _searchHistory,
        onSelect: _searchFromHistory,
      );
    }

    if (_activeQuery.isEmpty && !_hasRenderedResults) {
      return const SizedBox.shrink();
    }

    return TabBarView(
      controller: _tabController,
      children: [
        for (final tab in _SearchTab.values)
          _SearchResultList(
            key: PageStorageKey<String>(
              'search-results-$_sessionListGeneration-${tab.apiType}',
            ),
            tab: tab,
            state: _results[tab]!,
            onRetry: () => _refreshTab(tab, token: _requestToken),
            onLoadMore: () => _loadNextPage(tab),
            onOpen: _openResult,
            onDismissKeyboard: _dismissKeyboard,
          ),
      ],
    );
  }

  void _searchFromHistory(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _onQueryChanged(query);
    _focusNode.requestFocus();
  }

  Future<void> _openResult(_SearchResultItem item) async {
    if (item.deleted) return;
    _dismissKeyboard();
    unawaited(_recordActiveSearchQuery());
    GenesisTelemetry.collectLog(
      actionType: 'event',
      action: 'search_click',
      object1: _activeQuery,
      object2: item.entityId,
    );
    switch (item.tab) {
      case _SearchTab.origin:
        Navigator.of(context).pushNamed(
          RouteNames.originWorld,
          arguments: {
            'originId': 0,
            'oid': item.entityId,
            'initialName': item.title,
          },
        );
      case _SearchTab.world:
        final result = await Navigator.of(context).pushNamed<WorldPageResult>(
          RouteNames.world,
          arguments: {'wid': item.entityId, 'initialName': item.title},
        );
        if (!mounted || result == null) return;
        _removeDeletedWorld(result.deletedWorldId);
      case _SearchTab.user:
        Navigator.of(
          context,
        ).pushNamed(RouteNames.userInfo, arguments: {'uid': item.entityId});
    }
  }

  void _removeDeletedWorld(String rawWorldId) {
    final worldId = rawWorldId.trim();
    if (worldId.isEmpty) return;
    setState(() {
      var removedAny = false;
      for (final state in _results.values) {
        final previousLength = state.items.length;
        state.items.removeWhere(
          (item) =>
              item.tab == _SearchTab.world && item.entityId.trim() == worldId,
        );
        final removedCount = previousLength - state.items.length;
        if (removedCount == 0) continue;
        removedAny = true;

        state.total = state.total > removedCount
            ? state.total - removedCount
            : 0;
        state.hasMore = state.items.length < state.total;
      }
      if (removedAny) {
        final worldTotal = _tabTotals[_SearchTab.world];
        if (worldTotal != null) {
          _tabTotals[_SearchTab.world] = worldTotal > 0 ? worldTotal - 1 : 0;
        }
      }
    });
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }
}

_SearchTab _defaultSearchTab(String query) {
  return _entityIdSearchTab(query) ?? _SearchTab.origin;
}

bool _isSearchableQuery(String query) {
  return _entityIdSearchTab(query) != null ||
      _searchableCharacterCount(query) >= _SearchPageState._minSearchLength;
}

_SearchTab? _entityIdSearchTab(String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.length != 8 || normalized[1] != '_') return null;
  if (!normalized.substring(2).runes.every(_isAsciiLetterOrDigit)) return null;

  return switch (normalized[0]) {
    'u' => _SearchTab.user,
    'w' => _SearchTab.world,
    _ => null,
  };
}

int _searchableCharacterCount(String query) {
  var count = 0;
  for (final rune in query.runes) {
    if (_isAsciiLetter(rune) || _isCjkIdeograph(rune)) count += 1;
  }
  return count;
}

bool _isAsciiLetter(int rune) {
  return (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);
}

bool _isAsciiLetterOrDigit(int rune) {
  return _isAsciiLetter(rune) || (rune >= 0x30 && rune <= 0x39);
}

bool _isCjkIdeograph(int rune) {
  return (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0x20000 && rune <= 0x2A6DF) ||
      (rune >= 0x2A700 && rune <= 0x2B73F) ||
      (rune >= 0x2B740 && rune <= 0x2B81F) ||
      (rune >= 0x2B820 && rune <= 0x2CEAF);
}
