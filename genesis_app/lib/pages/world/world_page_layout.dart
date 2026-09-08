part of 'world_page.dart';

extension _WorldPageLayout on _WorldPageState {
  void _handleTilemapDisplayReadinessChanged(bool ready) {
    if (!mounted || _tilemapDisplayReady == ready) return;
    _setWorldPageState(() {
      _tilemapDisplayReady = ready;
      if (ready) {
        _tilemapDisplayError = null;
        _coverTilemapAfterInitialChat = false;
      }
    });
  }

  void _handleTilemapDisplayError(Object error) {
    if (!mounted) return;
    _setWorldPageState(() {
      _tilemapDisplayReady = false;
      _tilemapDisplayError = error;
      _coverTilemapAfterInitialChat = false;
    });
  }

  Widget _buildInitialLoadingScaffold(
    double topPadding, {
    WorldDetail? world,
    bool assumeLaunched = false,
  }) {
    final collapsedPanelHeight = worldCollapsedPanelHeightFor(
      context,
      world: world,
      assumeLaunched: true,
    );
    const infoHeaderHeight = worldLaunchedInfoHeaderHeight;
    return Stack(
      children: [
        WorldDetailsPageScaffold(
          backgroundColor: _tilemapLoadingBackgroundColor,
          panelBackgroundColor: GenesisColors.darkBackground,
          panelTopGap: 50,
          panelCollapsedHeightOffset: 120,
          scrollPhysics: const NeverScrollableScrollPhysics(),
          persistentTopOverlay: _buildPersistentMapOverlay(
            topPadding,
            world: world,
            initialName: widget.initialName,
            worldTime: world?.currentTime ?? '',
            tickIndex: world?.tickCount ?? -1,
            subTickNo: world?.subTickNo ?? 0,
          ),
          map:
              _buildInitialTilemapPreview() ??
              ColoredBox(
                key: const ValueKey<String>('world-map-loading-background'),
                color: _tilemapLoadingBackgroundColor,
              ),
          fixedCollapsedPanelHeight: collapsedPanelHeight,
          fixedCollapsedPanelHeightIncludesBottomSafeArea: true,
          contentBottomPaddingOverride: 0,
          slivers: [
            WorldDetailsLoadingContent(
              infoHeaderHeight: infoHeaderHeight,
              useCompactAction: true,
            ),
          ],
        ),
        _buildWorldBottomTagsOverlay(
          collapsedPanelHeight: collapsedPanelHeight,
          interactive: false,
        ),
      ],
    );
  }

  Widget? _buildInitialTilemapPreview() {
    final locationId = widget.initialMapLocationId.trim();
    if (widget.initialDefinitionVersion != 2 || locationId.isEmpty) {
      return null;
    }
    return IgnorePointer(
      key: const ValueKey<String>('world-initial-tilemap-preview'),
      child: WorldMap.world(
        definitionVersion: 2,
        worldId: widget.wid,
        common: const WorldMapCommonConfig(),
        legacy: const LegacyWorldMapConfig(points: <WorldPoint>[]),
        tilemap: WorldMapTilemapOptions(
          implementationKey: _tilemapImplementationKey,
          locationId: locationId,
          centerContentInitially: true,
          showVisualModeToggle: false,
          restorationController: _tilemapRestorationController,
          onDisplayReadinessChanged: _handleTilemapDisplayReadinessChanged,
          onDisplayError: _handleTilemapDisplayError,
        ),
      ),
    );
  }

  Widget _buildWorldBottomTagsOverlay({
    required double collapsedPanelHeight,
    required bool interactive,
  }) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: collapsedPanelHeight - worldMainTabsHeight,
      height: worldMainTabsHeight,
      child: IgnorePointer(
        key: const ValueKey<String>('world-bottom-tags-overlay'),
        ignoring: !interactive,
        child: WorldBottomTags(
          eventsUnread: _eventsUnread,
          showDetailUnreadDot: _hasUnreadNewUserJoin,
          onTap: _openWorldBottomSheet,
        ),
      ),
    );
  }

  Widget _buildPersistentMapOverlay(
    double top, {
    WorldDetail? world,
    String initialName = '',
    String worldTime = '',
    int tickIndex = -1,
    int subTickNo = 0,
  }) {
    final title = world == null
        ? initialName.trim()
        : (world.name.trim().isEmpty ? world.worldId : world.name.trim());
    final resolvedWorldTimeLabel = worldTimeLabel(
      tickIndex: tickIndex,
      subTickNo: subTickNo,
      worldTime: worldTime,
    );
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sideReservedWidth =
              worldMapBackButtonLeft +
              worldMapTabsHeight +
              worldMapIdentityHorizontalGap;
          final maxIdentityWidth =
              (constraints.maxWidth -
                      sideReservedWidth -
                      worldMapBackButtonLeft)
                  .clamp(worldTimePillMinWidth, constraints.maxWidth)
                  .toDouble();
          return Stack(
            children: [
              if (_worldMainTabIndex == 0)
                Positioned(
                  left: worldMapBackButtonLeft,
                  right: worldMapBackButtonLeft,
                  top: top + 8,
                  child: AnimatedBuilder(
                    animation:
                        _mainTabController.animation ?? _mainTabController,
                    builder: (context, _) {
                      if (_worldMainTabIndex != 0) {
                        return const SizedBox.shrink();
                      }
                      return WorldMapTopBar(
                        title: title,
                        timeText: resolvedWorldTimeLabel,
                        maxIdentityWidth: maxIdentityWidth,
                        onBackPressed: () => Navigator.of(context).maybePop(),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
