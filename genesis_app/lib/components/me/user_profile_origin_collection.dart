part of 'user_profile_library.dart';

class _OriginProfileCollectionList extends StatelessWidget {
  const _OriginProfileCollectionList({
    required this.items,
    required this.emptyText,
    required this.isLoading,
    required this.listenable,
    required this.onRefresh,
    required this.sliverMode,
    required this.injectNestedOverlap,
    this.alwaysScrollable = false,
    required this.canEditOrigins,
  });

  final List<UserProfileOriginItem> items;
  final String emptyText;
  final bool isLoading;
  final ValueListenable<UserProfileCollectionState<UserProfileOriginItem>>?
  listenable;
  final Future<void> Function()? onRefresh;
  final bool sliverMode;
  final bool injectNestedOverlap;
  final bool alwaysScrollable;
  final bool canEditOrigins;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable == null) {
      return _buildOriginList(context, items, isLoading);
    }
    return ValueListenableBuilder<
      UserProfileCollectionState<UserProfileOriginItem>
    >(
      valueListenable: listenable,
      builder: (context, state, _) {
        return _buildOriginList(context, state.items, state.isLoading);
      },
    );
  }

  Widget _buildOriginList(
    BuildContext context,
    List<UserProfileOriginItem> items,
    bool isLoading,
  ) {
    return ProfileCollectionList(
      items: items
          .map(
            (item) => GenesisProfileCollectionItemData(
              animationKey: item.oid,
              imageUrl: item.imageUrl,
              title: originDisplayName(item.title),
              subtitle: item.subtitle,
              useOriginCardLayout: true,
              showPressedBackground: false,
              stats: [
                GenesisProfileCollectionStat(
                  iconAsset: copyStatIconAsset,
                  value: item.copyCount,
                ),
                GenesisProfileCollectionStat(
                  iconAsset: connectStatIconAsset,
                  value: item.interactCount,
                ),
                GenesisProfileCollectionStat(
                  iconAsset: characterStatIconAsset,
                  value: item.characterCount,
                ),
              ],
              onTap: item.deleted
                  ? null
                  : () {
                      GenesisTelemetry.collectLog(
                        actionType: 'event',
                        action: 'me_click',
                        object1: item.oid,
                      );
                      Navigator.of(context)
                          .pushNamed(
                            RouteNames.originWorld,
                            arguments: {
                              'originId': item.originId,
                              'oid': item.oid,
                              'initialName': item.title,
                              'initialDefinitionVersion':
                                  item.definitionVersion,
                              'initialMapLocationId': item.defaultMapLocationId,
                            },
                          )
                          .then((_) {
                            if (!context.mounted) return;
                            onRefresh?.call();
                          });
                    },
              onEdit: !canEditOrigins || item.deleted
                  ? null
                  : () async {
                      final originId = item.oid.trim().isNotEmpty
                          ? item.oid.trim()
                          : '${item.originId}';
                      await Navigator.of(context).pushNamed(
                        RouteNames.edit,
                        arguments: {'origin_id': originId},
                      );
                      if (!context.mounted) return;
                      await onRefresh?.call();
                    },
            ),
          )
          .toList(growable: false),
      emptyText: emptyText,
      isLoading: isLoading,
      loadingKey: const ValueKey('profile-origin-list-loading'),
      onRefresh: onRefresh,
      refreshKey: const ValueKey('profile-origin-list-refresh'),
      sliverMode: sliverMode,
      injectNestedOverlap: injectNestedOverlap,
      alwaysScrollable: alwaysScrollable,
      topPadding: 10,
      itemSpacing: 30,
    );
  }
}
