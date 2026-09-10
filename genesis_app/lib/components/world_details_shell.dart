import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/components/genesis_safe_area.dart';
import '../ui/system/genesis_system_ui.dart';
import 'world_map_interaction_notification.dart';

@immutable
class WorldDetailsStatusBarPresentation {
  const WorldDetailsStatusBarPresentation({
    required this.style,
    required this.backgroundColor,
  });

  final SystemUiOverlayStyle style;
  final Color backgroundColor;
}

class WorldDetailsStatusBarOverride {
  WorldDetailsStatusBarOverride._();

  static final ValueNotifier<WorldDetailsStatusBarPresentation?> _presentation =
      ValueNotifier<WorldDetailsStatusBarPresentation?>(null);

  static ValueListenable<WorldDetailsStatusBarPresentation?> get listenable =>
      _presentation;

  static void setStyle(
    SystemUiOverlayStyle style, {
    Color backgroundColor = Colors.transparent,
  }) {
    _presentation.value = WorldDetailsStatusBarPresentation(
      style: style,
      backgroundColor: backgroundColor,
    );
  }

  static void clearStyle() {
    _presentation.value = null;
  }

  static Future<T> runWithStyle<T>(
    SystemUiOverlayStyle style,
    Future<T> Function() action, {
    Color? backgroundColor,
  }) async {
    final previousPresentation = _presentation.value;
    _presentation.value = WorldDetailsStatusBarPresentation(
      style: style,
      backgroundColor:
          backgroundColor ??
          previousPresentation?.backgroundColor ??
          Colors.transparent,
    );
    try {
      return await action();
    } finally {
      _presentation.value = previousPresentation;
    }
  }
}

class WorldDetailsPageScaffold extends StatefulWidget {
  const WorldDetailsPageScaffold({
    super.key,
    required this.map,
    required this.slivers,
    this.panelTopGap = defaultPanelTopGap,
    this.panelCollapsedHeightOffset = defaultPanelCollapsedHeightOffset,
    this.panelTopRadius = defaultPanelTopRadius,
    this.panelTopOverlap = 0,
    this.scrollPhysics,
    this.bottomBar,
    this.fixedCollapsedPanelHeight,
    this.fixedCollapsedPanelHeightIncludesBottomSafeArea = false,
    this.contentBottomPaddingOverride,
    this.includeBottomSafeAreaInContentPadding = true,
    this.topOverlay,
    this.persistentTopOverlay,
    this.onPanelTopPullUp,
    this.backgroundColor,
    this.panelBackgroundColor = Colors.white,
  });

  static const double defaultPanelTopGap = 30;
  static const double defaultPanelCollapsedHeightOffset = 50;
  static const double defaultPanelTopRadius = 8;
  static const double contentHorizontalPadding = 12;
  static const double inlineContentTopPadding = 14;
  static const double contentBottomPadding = 20;
  static const double contentBottomPaddingWithBottomBar = 126;

  final Widget map;
  final List<Widget> slivers;
  final double panelTopGap;
  final double panelCollapsedHeightOffset;
  final double panelTopRadius;
  final double panelTopOverlap;
  final ScrollPhysics? scrollPhysics;
  final Widget? bottomBar;
  final double? fixedCollapsedPanelHeight;
  final bool fixedCollapsedPanelHeightIncludesBottomSafeArea;
  final double? contentBottomPaddingOverride;
  final bool includeBottomSafeAreaInContentPadding;
  final Widget? topOverlay;
  final Widget? persistentTopOverlay;
  final VoidCallback? onPanelTopPullUp;
  final Color? backgroundColor;
  final Color panelBackgroundColor;

  @override
  State<WorldDetailsPageScaffold> createState() =>
      _WorldDetailsPageScaffoldState();
}

class _WorldDetailsPageScaffoldState extends State<WorldDetailsPageScaffold> {
  late final ScrollController _scrollController = ScrollController();
  bool _mapInteractionActive = false;

  static const _transparentStatusBarColor = Color(0x00FFFFFF);
  static const _whiteStatusBarColor = Color(0xFFFFFFFF);
  static const _initialStatusBarStyle =
      kGenesisLightStatusIconsSystemUiOverlayStyle;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double _statusBarProgress(double mapHeight, double statusBarHeight) {
    if (!_scrollController.hasClients) return 0;
    final scrollDistance = (mapHeight - statusBarHeight).clamp(
      1.0,
      double.infinity,
    );
    return (_scrollController.offset / scrollDistance).clamp(0.0, 1.0);
  }

  SystemUiOverlayStyle _statusBarStyle(double progress) {
    if (progress <= 0) return _initialStatusBarStyle;
    final useDarkIcons = progress >= 0.55;
    return useDarkIcons
        ? kGenesisDefaultSystemUiOverlayStyle
        : kGenesisLightStatusIconsSystemUiOverlayStyle;
  }

  @override
  Widget build(BuildContext context) {
    final bottomBar = widget.bottomBar;
    final topOverlay = widget.topOverlay;
    return Scaffold(
      backgroundColor: widget.backgroundColor,
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewportHeight = constraints.maxHeight;
          final bottomSafeArea = _bottomSafeAreaOf(context);
          final fixedCollapsedPanelHeight = widget.fixedCollapsedPanelHeight;
          final mapBottomOffset =
              bottomBar == null &&
                  !widget.fixedCollapsedPanelHeightIncludesBottomSafeArea
              ? bottomSafeArea
              : 0.0;
          final maxMapHeight =
              (viewportHeight - widget.panelTopGap - mapBottomOffset)
                  .clamp(0.0, viewportHeight)
                  .toDouble();
          final mapHeight =
              (fixedCollapsedPanelHeight == null
                      ? viewportHeight *
                                (1 -
                                    WorldDetailsPanel.defaultExposedChildSize) +
                            widget.panelCollapsedHeightOffset -
                            mapBottomOffset
                      : viewportHeight -
                            fixedCollapsedPanelHeight -
                            mapBottomOffset)
                  .clamp(0.0, maxMapHeight)
                  .toDouble();
          final panelTopOverlap = widget.panelTopOverlap
              .clamp(0.0, mapHeight)
              .toDouble();
          final bottomPadding = bottomBar == null
              ? widget.contentBottomPaddingOverride ??
                    WorldDetailsPageScaffold.contentBottomPadding
              : WorldDetailsPageScaffold.contentBottomPaddingWithBottomBar;
          final contentBottomSafeArea =
              widget.includeBottomSafeAreaInContentPadding
              ? bottomSafeArea
              : 0.0;
          final statusBarHeight = GenesisSafeAreaInsets.top(context);

          return AnimatedBuilder(
            animation: Listenable.merge([
              _scrollController,
              WorldDetailsStatusBarOverride.listenable,
            ]),
            builder: (context, child) {
              final statusBarProgress = _statusBarProgress(
                mapHeight,
                statusBarHeight,
              );
              final overridePresentation =
                  WorldDetailsStatusBarOverride.listenable.value;
              final statusBarColor =
                  overridePresentation?.backgroundColor ??
                  Color.lerp(
                    _transparentStatusBarColor,
                    _whiteStatusBarColor,
                    statusBarProgress,
                  )!;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value:
                    overridePresentation?.style ??
                    _statusBarStyle(statusBarProgress),
                child: _buildPanelShell(
                  mapHeight: mapHeight,
                  panelTopOverlap: panelTopOverlap,
                  bottomPadding: bottomPadding,
                  contentBottomSafeArea: contentBottomSafeArea,
                  statusBarHeight: statusBarHeight,
                  statusBarColor: statusBarColor,
                  bottomBar: bottomBar,
                  topOverlay: topOverlay,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAlignedMapLayer(double mapHeight) {
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(height: mapHeight, child: widget.map),
    );
  }

  Widget _buildPanelShell({
    required double mapHeight,
    required double panelTopOverlap,
    required double bottomPadding,
    required double contentBottomSafeArea,
    required double statusBarHeight,
    required Color statusBarColor,
    required Widget? bottomBar,
    required Widget? topOverlay,
  }) {
    final scrollView = MediaQuery.removePadding(
      context: context,
      removeBottom: true,
      child: CustomScrollView(
        controller: _scrollController,
        hitTestBehavior: HitTestBehavior.deferToChild,
        physics: _mapInteractionActive
            ? const NeverScrollableScrollPhysics()
            : widget.scrollPhysics,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: mapHeight)),
          DecoratedSliver(
            key: const ValueKey<String>('world-details-content-background'),
            decoration: BoxDecoration(color: widget.panelBackgroundColor),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: WorldDetailsPageScaffold.inlineContentTopPadding,
                    child: _buildPanelTopBand(panelTopOverlap),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal:
                        WorldDetailsPageScaffold.contentHorizontalPadding,
                  ),
                  sliver: SliverMainAxisGroup(slivers: widget.slivers),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: bottomPadding + contentBottomSafeArea,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final stack = Stack(
      children: [
        _buildAlignedMapLayer(mapHeight),
        scrollView,
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          height: statusBarHeight,
          child: IgnorePointer(child: ColoredBox(color: statusBarColor)),
        ),
        if (bottomBar != null)
          Positioned(left: 0, right: 0, bottom: 0, child: bottomBar),
        if (widget.persistentTopOverlay != null) widget.persistentTopOverlay!,
        if (topOverlay != null) topOverlay,
      ],
    );
    final shell = NotificationListener<WorldMapInteractionNotification>(
      onNotification: (notification) {
        if (_mapInteractionActive != notification.active) {
          setState(() => _mapInteractionActive = notification.active);
        }
        return false;
      },
      child: stack,
    );

    return WorldDetailsPanelScrollControllerScope(
      controller: _scrollController,
      mapHeight: mapHeight,
      child: shell,
    );
  }

  Widget _buildPanelTopBand(double panelTopOverlap) {
    return OverflowBox(
      minHeight:
          WorldDetailsPageScaffold.inlineContentTopPadding + panelTopOverlap,
      maxHeight:
          WorldDetailsPageScaffold.inlineContentTopPadding + panelTopOverlap,
      alignment: Alignment.bottomCenter,
      child: _WorldDetailsPanelTopPullGesture(
        onPullUp: widget.onPanelTopPullUp,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.panelBackgroundColor,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(widget.panelTopRadius),
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class WorldDetailsPanel extends StatelessWidget {
  const WorldDetailsPanel({
    super.key,
    required this.slivers,
    this.exposedChildSize = defaultExposedChildSize,
    this.topGap = 0,
    this.collapsedHeightOffset = 15,
    this.horizontalPadding = 16,
    this.bottomPadding = 0,
  });

  static const double defaultExposedChildSize = 0.31;
  static const double contentTopPadding = 20;

  final double exposedChildSize;
  final List<Widget> slivers;
  final double topGap;
  final double collapsedHeightOffset;
  final double horizontalPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = this.bottomPadding;
    final bottomSafeArea = _bottomSafeAreaOf(context);
    return WorldDetailsShell(
      topGap: topGap,
      minChildSize: exposedChildSize,
      initialChildSize: exposedChildSize,
      collapsedHeightOffset: collapsedHeightOffset,
      contentPadding: EdgeInsets.only(
        top: contentTopPadding,
        left: horizontalPadding,
        right: horizontalPadding,
      ),
      contentBuilder: (scrollController) => WorldDetailsScrollContent(
        controller: scrollController,
        slivers: [
          ...slivers,
          if (bottomPadding > 0)
            SliverToBoxAdapter(
              child: SizedBox(height: bottomPadding + bottomSafeArea),
            ),
        ],
      ),
    );
  }
}

double _bottomSafeAreaOf(BuildContext context) {
  return GenesisSafeAreaInsets.bottom(context);
}

class WorldDetailsPanelScrollControllerScope extends InheritedWidget {
  const WorldDetailsPanelScrollControllerScope({
    super.key,
    required this.controller,
    this.mapHeight,
    required super.child,
  });

  final ScrollController controller;
  final double? mapHeight;

  static ScrollController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<
          WorldDetailsPanelScrollControllerScope
        >()
        ?.controller;
  }

  static double? maybeMapHeightOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<
          WorldDetailsPanelScrollControllerScope
        >()
        ?.mapHeight;
  }

  @override
  bool updateShouldNotify(WorldDetailsPanelScrollControllerScope oldWidget) {
    return oldWidget.controller != controller ||
        oldWidget.mapHeight != mapHeight;
  }
}

class WorldDetailsShell extends StatelessWidget {
  const WorldDetailsShell({
    super.key,
    required this.contentBuilder,
    this.minChildSize = 0.25,
    this.initialChildSize = 0.25,
    this.topGap = 60,
    this.collapsedHeightOffset = 0,
    this.contentPadding = const EdgeInsets.only(top: 8, left: 16, right: 16),
  });

  static const double dragHandleTitleGap = 10;
  static const double dragHandleWidth = 55;
  static const double dragHandleHeight = 4;

  final Widget Function(ScrollController) contentBuilder;
  final double minChildSize;
  final double initialChildSize;
  final double topGap;
  final double collapsedHeightOffset;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final resolvedPadding = contentPadding.resolve(Directionality.of(context));
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxChildSize =
            (constraints.maxHeight - topGap) / constraints.maxHeight;
        final minSize = _adjustedChildSize(minChildSize, constraints.maxHeight);
        final initialSize = _adjustedChildSize(
          initialChildSize,
          constraints.maxHeight,
        ).clamp(minSize, maxChildSize).toDouble();
        return DraggableScrollableSheet(
          minChildSize: minSize,
          initialChildSize: initialSize,
          maxChildSize: maxChildSize,
          snap: true,
          snapSizes: [minSize, maxChildSize],
          builder: (context, scrollController) {
            return Material(
              color: Colors.transparent,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  resolvedPadding.left,
                  0,
                  resolvedPadding.right,
                  resolvedPadding.bottom,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: resolvedPadding.top,
                      child: const Center(child: WorldDetailsDragHandle()),
                    ),
                    const SizedBox(
                      height: WorldDetailsShell.dragHandleTitleGap,
                    ),
                    Expanded(
                      child: WorldDetailsPanelScrollControllerScope(
                        controller: scrollController,
                        child: contentBuilder(scrollController),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  double _adjustedChildSize(double size, double height) {
    if (collapsedHeightOffset <= 0 || height <= 0) return size;
    final adjustedHeight = size * height - collapsedHeightOffset;
    return (adjustedHeight / height).clamp(0.0, 1.0).toDouble();
  }
}

class _WorldDetailsPanelTopPullGesture extends StatefulWidget {
  const _WorldDetailsPanelTopPullGesture({
    required this.child,
    required this.onPullUp,
  });

  final Widget child;
  final VoidCallback? onPullUp;

  @override
  State<_WorldDetailsPanelTopPullGesture> createState() =>
      _WorldDetailsPanelTopPullGestureState();
}

class _WorldDetailsPanelTopPullGestureState
    extends State<_WorldDetailsPanelTopPullGesture> {
  static const double _triggerDistance = 36;
  static const double _triggerVelocity = 520;

  var _dragDy = 0.0;

  @override
  Widget build(BuildContext context) {
    final onPullUp = widget.onPullUp;
    if (onPullUp == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) {
        _dragDy = 0;
      },
      onVerticalDragUpdate: (details) {
        _dragDy += details.delta.dy;
      },
      onVerticalDragEnd: (details) {
        final upwardVelocity = -(details.primaryVelocity ?? 0);
        if (_dragDy <= -_triggerDistance ||
            upwardVelocity >= _triggerVelocity) {
          onPullUp();
        }
        _dragDy = 0;
      },
      onVerticalDragCancel: () {
        _dragDy = 0;
      },
      child: widget.child,
    );
  }
}

class WorldDetailsDragHandle extends StatelessWidget {
  const WorldDetailsDragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: WorldDetailsShell.dragHandleWidth,
      height: WorldDetailsShell.dragHandleHeight,
      decoration: const BoxDecoration(
        color: Color(0xFFD9D9D9),
        borderRadius: BorderRadius.all(
          Radius.circular(WorldDetailsShell.dragHandleHeight / 2),
        ),
      ),
    );
  }
}

class WorldDetailsScrollContent extends StatelessWidget {
  const WorldDetailsScrollContent({
    super.key,
    required this.controller,
    required this.slivers,
  });

  final ScrollController controller;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: CustomScrollView(controller: controller, slivers: slivers),
    );
  }
}
