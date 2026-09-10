part of 'origin_world_page.dart';

extension _OriginWorldPageMapShell on _OriginWorldPageState {
  Widget _buildPersistentMapOverlay(double top, {OriginDetail? origin}) {
    return Positioned(
      left: genesisMapBackButtonLeft,
      right: genesisMapTopBarRightInset,
      top: top + genesisMapBackButtonTop,
      child: _OriginWorldNameOverlay(
        worldoName: origin == null
            ? originDisplayName(widget.initialName)
            : originDisplayName(origin.name, fallback: origin.oid),
      ),
    );
  }

  Widget _buildMapOnlyScaffold({
    required double topPadding,
    required Widget mapOverlay,
    required Widget map,
    Widget Function(double minChildSize)? bottomSheetOverlayBuilder,
    Widget? topOverlay,
  }) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _baseStatusBarStyle,
      child: Scaffold(
        backgroundColor: originWorldDetailSheetBackgroundColor,
        resizeToAvoidBottomInset: false,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final viewportHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height;
            final bottomSafeArea = GenesisSafeAreaInsets.bottom(context);
            final sheetTop = originWorldMapHeightFor(
              viewportHeight: viewportHeight,
              bottomSafeArea: bottomSafeArea,
            );
            final mapHeight = originWorldRenderedMapHeightFor(
              viewportHeight: viewportHeight,
              bottomSafeArea: bottomSafeArea,
            );
            final sheetHostHeight = viewportHeight;
            final sheetMinChildSize = sheetHostHeight <= 0
                ? _OriginDetailDraggableSheet.defaultInitialChildSize
                : ((sheetHostHeight - sheetTop) / sheetHostHeight)
                      .clamp(0.08, 1.0)
                      .toDouble();
            return Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    key: const ValueKey<String>('origin-map-viewport'),
                    width: double.infinity,
                    height: mapHeight,
                    child: map,
                  ),
                ),
                mapOverlay,
                if (bottomSheetOverlayBuilder != null)
                  Positioned.fill(
                    child: bottomSheetOverlayBuilder(sheetMinChildSize),
                  ),
                if (topOverlay != null) topOverlay,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildInitialLoadingScaffold(
    double topPadding, {
    OriginDetail? origin,
  }) {
    return _buildMapOnlyScaffold(
      topPadding: topPadding,
      mapOverlay: _buildPersistentMapOverlay(topPadding, origin: origin),
      map:
          _buildInitialTilemapPreview() ??
          ColoredBox(
            key: const ValueKey<String>('origin-map-loading-background'),
            color: _tilemapLoadingBackgroundColor,
          ),
      bottomSheetOverlayBuilder: (minChildSize) => _OriginDetailLoadingSheet(
        minChildSize: minChildSize,
        initiallyExpanded: widget.showOpeningSheetOnEntry,
      ),
    );
  }

  Widget? _buildInitialTilemapPreview() {
    final locationId = widget.initialMapLocationId.trim();
    if (widget.initialDefinitionVersion != 2 || locationId.isEmpty) {
      return null;
    }
    return IgnorePointer(
      key: const ValueKey<String>('origin-initial-tilemap-preview'),
      child: WorldMap.origin(
        definitionVersion: 2,
        originId: widget.oid,
        common: const WorldMapCommonConfig(),
        legacy: const LegacyWorldMapConfig(points: <WorldPoint>[]),
        tilemap: WorldMapTilemapOptions(
          implementationKey: _tilemapImplementationKey,
          locationId: locationId,
          centerContentInitially: true,
          showVisualModeToggle: false,
          restorationController: _tilemapRestorationController,
        ),
      ),
    );
  }
}

class _OriginWorldNameOverlay extends StatelessWidget {
  const _OriginWorldNameOverlay({required this.worldoName});

  final String worldoName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey<String>('origin-top-overlay-bar'),
      height: genesisMapBackButtonDimension,
      child: Row(
        children: [
          GenesisMapGlassBackButton(
            dimension: genesisMapBackButtonDimension,
            onPressed: () => Navigator.of(context).maybePop(),
            glassKey: const ValueKey<String>('origin-top-back-glass'),
            surfaceKey: const ValueKey<String>('origin-top-back-surface'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                worldoName,
                key: const ValueKey<String>('origin-top-worldo-name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                  shadows: [
                    Shadow(
                      color: Color(0x99000000),
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginDetailLoadingSheet extends StatelessWidget {
  const _OriginDetailLoadingSheet({
    required this.minChildSize,
    required this.initiallyExpanded,
  });

  final double minChildSize;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final heightFactor = initiallyExpanded
        ? _originDetailExpandedChildSize(context, minChildSize: minChildSize)
        : minChildSize;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          widthFactor: 1,
          heightFactor: heightFactor,
          child: DecoratedBox(
            key: const ValueKey<String>('origin-detail-loading-sheet'),
            decoration: const BoxDecoration(
              color: originWorldDetailSheetBackgroundColor,
              borderRadius: GenesisRadii.sheet,
            ),
            child: ClipRRect(
              borderRadius: GenesisRadii.sheet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    height: originDetailSheetHeaderHeightForTesting,
                  ),
                  const Expanded(child: _OriginSheetLoadingContent()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OriginSheetLoadingContent extends StatelessWidget {
  const _OriginSheetLoadingContent();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(10, 6, 10, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _OriginLoadingBone(
                key: ValueKey<String>('origin-loading-generic-leading'),
                width: 14,
                height: 14,
                radius: 7,
              ),
              SizedBox(width: originDetailSectionTitleIconGapForTesting),
              _OriginLoadingBone(
                key: ValueKey<String>('origin-loading-generic-title'),
                width: 104,
                height: 14,
              ),
            ],
          ),
          SizedBox(height: 12),
          _OriginLoadingBone(
            key: ValueKey<String>('origin-loading-generic-line-1'),
            widthFactor: 0.86,
            height: 14,
          ),
          SizedBox(height: 8),
          _OriginLoadingBone(
            key: ValueKey<String>('origin-loading-generic-line-2'),
            widthFactor: 0.62,
            height: 14,
          ),
        ],
      ),
    );
  }
}

class _OriginLoadingBone extends StatelessWidget {
  const _OriginLoadingBone({
    super.key,
    this.width,
    this.widthFactor,
    required this.height,
    this.radius = 4,
  });

  final double? width;
  final double? widthFactor;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bone = DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: SizedBox(width: width, height: height),
    );
    final widthFactor = this.widthFactor;
    if (widthFactor == null) return bone;
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: bone,
    );
  }
}
