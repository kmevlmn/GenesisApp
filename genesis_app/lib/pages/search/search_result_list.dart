part of 'search_page.dart';

class _SearchResultList extends StatefulWidget {
  const _SearchResultList({
    super.key,
    required this.tab,
    required this.state,
    required this.onRetry,
    required this.onLoadMore,
    required this.onOpen,
    required this.onDismissKeyboard,
  });

  final _SearchTab tab;
  final _SearchTabResults state;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final ValueChanged<_SearchResultItem> onOpen;
  final VoidCallback onDismissKeyboard;

  @override
  State<_SearchResultList> createState() => _SearchResultListState();
}

class _SearchResultListState extends State<_SearchResultList>
    with AutomaticKeepAliveClientMixin<_SearchResultList> {
  static const _loadMoreThreshold = 700.0;

  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    widget.onDismissKeyboard();
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > _loadMoreThreshold) {
      return;
    }
    widget.onLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = widget.state;

    if (state.isInitialLoading) {
      return GenesisSearchResultLoadingSkeleton.list(
        type: _searchSkeletonType(widget.tab),
      );
    }

    if (state.error != null && state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Search failed',
              style: TextStyle(color: GenesisColors.darkTextSecondary),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: widget.onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: GenesisColors.redPrimary,
                foregroundColor: GenesisColors.darkTextPrimary,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!state.hasSuccessfulResponse) {
      return const SizedBox.shrink();
    }

    if (state.items.isEmpty) {
      return const Center(
        child: Text(
          'No results.',
          style: TextStyle(
            fontSize: 14,
            color: GenesisColors.darkTextSecondary,
            fontWeight: FontWeight.w400,
          ),
        ),
      );
    }

    final itemCount = state.items.length + (state.isLoadingMore ? 1 : 0);
    return ListView.builder(
      controller: _scrollController,
      primary: false,
      cacheExtent: 900,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= state.items.length) {
          return const Padding(
            key: ValueKey<String>('search-result-load-more'),
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: GenesisLoadingIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final item = state.items[index];
        return Padding(
          padding: EdgeInsets.only(
            bottom: widget.tab == _SearchTab.user ? 22 : 30,
          ),
          child: _SearchResultTile(
            item: item,
            onTap: item.deleted ? null : () => widget.onOpen(item),
          ),
        );
      },
    );
  }
}

GenesisSearchResultSkeletonType _searchSkeletonType(_SearchTab tab) {
  return switch (tab) {
    _SearchTab.origin => GenesisSearchResultSkeletonType.origin,
    _SearchTab.world => GenesisSearchResultSkeletonType.world,
    _SearchTab.user => GenesisSearchResultSkeletonType.user,
  };
}

// The following classes are adapted from WorldDetailsPanel and WorldDetailsShell to be used in the search page result details.
