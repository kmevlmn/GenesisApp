part of 'user_profile_library.dart';

class _WorldProfileCollectionList extends StatefulWidget {
  const _WorldProfileCollectionList({
    required this.items,
    required this.emptyText,
    required this.isLoading,
    required this.listenable,
    required this.onRefresh,
    required this.sliverMode,
    required this.injectNestedOverlap,
    this.alwaysScrollable = false,
    required this.canDeleteWorlds,
    required this.onWorldDeleted,
  });

  final List<UserProfileWorldItem> items;
  final String emptyText;
  final bool isLoading;
  final ValueListenable<UserProfileCollectionState<UserProfileWorldItem>>?
  listenable;
  final Future<void> Function()? onRefresh;
  final bool sliverMode;
  final bool injectNestedOverlap;
  final bool alwaysScrollable;
  final bool canDeleteWorlds;
  final ValueChanged<UserProfileWorldItem>? onWorldDeleted;

  @override
  State<_WorldProfileCollectionList> createState() =>
      _WorldProfileCollectionListState();
}

class _WorldProfileCollectionListState
    extends State<_WorldProfileCollectionList> {
  final Set<String> _deletingWorldIds = <String>{};
  final Set<String> _collapsingWorldIds = <String>{};
  final Set<String> _locallyDeletedWorldIds = <String>{};

  @override
  void didUpdateWidget(covariant _WorldProfileCollectionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveIds = <String>{
      for (final item in widget.items) item.wid,
      if (widget.listenable != null)
        for (final item in widget.listenable!.value.items) item.wid,
    };
    _deletingWorldIds.removeWhere((wid) => !liveIds.contains(wid));
    _collapsingWorldIds.removeWhere((wid) => !liveIds.contains(wid));
  }

  @override
  Widget build(BuildContext context) {
    final listenable = widget.listenable;
    if (listenable == null) {
      return _buildWorldList(context, widget.items, widget.isLoading);
    }
    return ValueListenableBuilder<
      UserProfileCollectionState<UserProfileWorldItem>
    >(
      valueListenable: listenable,
      builder: (context, state, _) {
        return _buildWorldList(context, state.items, state.isLoading);
      },
    );
  }

  Widget _buildWorldList(
    BuildContext context,
    List<UserProfileWorldItem> items,
    bool isLoading,
  ) {
    final visibleItems = items
        .where((item) => !_locallyDeletedWorldIds.contains(item.wid.trim()))
        .toList(growable: false);
    return ProfileCollectionList(
      items: visibleItems
          .map(
            (item) => GenesisProfileCollectionItemData(
              animationKey: item.wid,
              imageUrl: item.imageUrl,
              title: item.title,
              subtitle: item.subtitle,
              statsText: formatWorldStatsLabel(
                tickNo: item.progressCount,
                subTickNo: item.subTickNo,
                messageCount: item.interactCount,
                playerCount: item.playerCount,
              ),
              useWorldCardLayout: true,
              isCollapsing: _collapsingWorldIds.contains(item.wid),
              showPressedBackground: false,
              enableFeedback: false,
              onTap:
                  item.deleted ||
                      _deletingWorldIds.contains(item.wid) ||
                      _collapsingWorldIds.contains(item.wid)
                  ? null
                  : () => unawaited(_openWorld(item)),
              onCollapsed: () => _handleWorldCollapseCompleted(item),
            ),
          )
          .toList(growable: false),
      emptyText: widget.emptyText,
      isLoading: isLoading,
      loadingKey: const ValueKey('profile-world-list-loading'),
      onRefresh: widget.onRefresh,
      refreshKey: const ValueKey('profile-world-list-refresh'),
      sliverMode: widget.sliverMode,
      injectNestedOverlap: widget.injectNestedOverlap,
      alwaysScrollable: widget.alwaysScrollable,
      topPadding: 10,
      itemSpacing: 30,
    );
  }

  Future<void> _openWorld(UserProfileWorldItem item) async {
    GenesisTelemetry.collectLog(
      actionType: 'event',
      action: 'me_click',
      object1: item.wid,
    );
    final result = await Navigator.of(context).pushNamed<WorldPageResult>(
      RouteNames.world,
      arguments: {
        'wid': item.wid,
        'initialName': item.title,
        'initialDefinitionVersion': item.definitionVersion,
        'initialMapLocationId': item.defaultMapLocationId,
      },
    );
    if (!mounted || result == null) return;
    final deletedWorldId = result.deletedWorldId.trim();
    if (deletedWorldId.isEmpty ||
        deletedWorldId != item.wid.trim() ||
        _collapsingWorldIds.contains(deletedWorldId)) {
      return;
    }
    setState(() {
      _deletingWorldIds.remove(deletedWorldId);
      _collapsingWorldIds.add(deletedWorldId);
    });
  }

  void _handleWorldCollapseCompleted(UserProfileWorldItem item) {
    final worldId = item.wid.trim();
    if (!mounted || worldId.isEmpty || !_collapsingWorldIds.contains(worldId)) {
      return;
    }
    setState(() {
      _locallyDeletedWorldIds.add(worldId);
      _deletingWorldIds.remove(worldId);
      _collapsingWorldIds.remove(worldId);
    });
    widget.onWorldDeleted?.call(item);
  }
}

class UserProfileOriginItem {
  const UserProfileOriginItem({
    required this.originId,
    required this.oid,
    required this.title,
    this.definitionVersion = 0,
    this.defaultMapLocationId = '',
    required this.subtitle,
    this.deleted = false,
    required this.imageUrl,
    required this.copyCount,
    required this.interactCount,
    required this.characterCount,
  });

  final int originId;
  final String oid;
  final String title;
  final int definitionVersion;
  final String defaultMapLocationId;
  final String subtitle;
  final bool deleted;
  final String imageUrl;
  final int copyCount;
  final int interactCount;
  final int characterCount;
}

class UserProfileWorldItem {
  const UserProfileWorldItem({
    required this.wid,
    required this.title,
    this.definitionVersion = 0,
    this.defaultMapLocationId = '',
    required this.subtitle,
    this.deleted = false,
    required this.imageUrl,
    required this.progressCount,
    this.subTickNo = 0,
    required this.interactCount,
    required this.characterCount,
    required this.playerCount,
    required this.ownerName,
  });

  final String wid;
  final String title;
  final int definitionVersion;
  final String defaultMapLocationId;
  final String subtitle;
  final bool deleted;
  final String imageUrl;
  final int progressCount;
  final int subTickNo;
  final int interactCount;
  final int characterCount;
  final int playerCount;
  final String ownerName;
}
