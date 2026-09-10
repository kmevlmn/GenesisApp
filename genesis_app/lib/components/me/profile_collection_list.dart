import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/genesis_ui.dart';
import '../../ui/components/genesis_deleted_list_item_transition.dart';

class ProfileCollectionList extends StatefulWidget {
  const ProfileCollectionList({
    super.key,
    required this.items,
    required this.emptyText,
    this.isLoading = false,
    this.loadingKey,
    this.onRefresh,
    this.refreshKey,
    this.sliverMode = false,
    this.injectNestedOverlap = false,
    this.alwaysScrollable = false,
    this.topPadding = 12,
    this.itemSpacing = 24,
  });

  static const double minSystemNavigationBottomPadding = 56;

  final List<GenesisProfileCollectionItemData> items;
  final String emptyText;
  final bool isLoading;
  final Key? loadingKey;
  final Future<void> Function()? onRefresh;
  final Key? refreshKey;
  final bool sliverMode;
  final bool injectNestedOverlap;
  final bool alwaysScrollable;
  final double topPadding;
  final double itemSpacing;

  @override
  State<ProfileCollectionList> createState() => _ProfileCollectionListState();
}

class _ProfileCollectionListState extends State<ProfileCollectionList> {
  final Map<Object, double> _collapseBottomCompensation = <Object, double>{};

  @override
  void didUpdateWidget(covariant ProfileCollectionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveKeys = <Object>{
      for (var index = 0; index < widget.items.length; index += 1)
        widget.items[index].animationKey ?? index,
    };
    _collapseBottomCompensation.removeWhere(
      (key, _) => !liveKeys.contains(key),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = [
      mediaQuery.padding.bottom,
      mediaQuery.viewPadding.bottom,
      ProfileCollectionList.minSystemNavigationBottomPadding,
    ].reduce((a, b) => a > b ? a : b);
    final listPadding = EdgeInsets.only(
      top: widget.topPadding,
      bottom: 16 + bottomInset + _collapseCompensation,
    );

    if (widget.items.isEmpty && widget.isLoading) {
      final loading = SizedBox(
        key: widget.loadingKey,
        width: 24,
        height: 24,
        child: const GenesisLoadingIndicator(),
      );
      return _buildPlaceholder(context, loading);
    }

    if (widget.items.isEmpty) {
      final empty = Text(
        widget.emptyText,
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(context).brightness == Brightness.dark
              ? GenesisColors.darkTextSecondary
              : const Color(0xFF8A8A8A),
          fontWeight: FontWeight.w400,
        ),
        textAlign: TextAlign.center,
      );
      return _buildPlaceholder(context, empty);
    }

    if (widget.sliverMode) {
      return SliverPadding(
        padding: listPadding,
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            _buildItem,
            childCount: widget.items.length,
          ),
        ),
      );
    }

    final physics = widget.onRefresh != null || widget.alwaysScrollable
        ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
        : const BouncingScrollPhysics();
    final list = widget.injectNestedOverlap
        ? CustomScrollView(
            physics: physics,
            clipBehavior: Clip.hardEdge,
            slivers: [
              SliverOverlapInjector(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
              ),
              SliverPadding(
                padding: listPadding,
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    _buildItem,
                    childCount: widget.items.length,
                  ),
                ),
              ),
            ],
          )
        : ListView.builder(
            itemCount: widget.items.length,
            physics: physics,
            clipBehavior: Clip.hardEdge,
            padding: listPadding,
            itemBuilder: _buildItem,
          );
    return _wrapRefreshIndicator(list);
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = widget.items[index];
    final animationKey = item.animationKey ?? index;
    return _AnimatedProfileCollectionListItem(
      key: ValueKey<Object>(animationKey),
      item: item,
      bottomSpacing: index == widget.items.length - 1 ? 0 : widget.itemSpacing,
      onCollapseCompensationChanged: (value) =>
          _setCollapseCompensation(animationKey, value),
    );
  }

  double get _collapseCompensation {
    return _collapseBottomCompensation.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
  }

  void _setCollapseCompensation(Object key, double value) {
    final normalized = value <= 0.5 ? 0.0 : value;
    final current = _collapseBottomCompensation[key] ?? 0;
    if ((current - normalized).abs() <= 0.5) return;
    if (!mounted) return;
    setState(() {
      if (normalized == 0) {
        _collapseBottomCompensation.remove(key);
      } else {
        _collapseBottomCompensation[key] = normalized;
      }
    });
  }

  Widget _buildPlaceholder(BuildContext context, Widget child) {
    if (widget.sliverMode) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: child),
      );
    }
    if (widget.onRefresh == null && !widget.alwaysScrollable) {
      return Center(child: child);
    }

    const physics = BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
    final placeholder = SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.45,
      child: Center(child: child),
    );
    final list = widget.injectNestedOverlap
        ? CustomScrollView(
            physics: physics,
            slivers: [
              SliverOverlapInjector(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
              ),
              SliverToBoxAdapter(child: placeholder),
            ],
          )
        : ListView(physics: physics, children: [placeholder]);
    return widget.onRefresh == null ? list : _wrapRefreshIndicator(list);
  }

  Widget _wrapRefreshIndicator(Widget child) {
    final refresh = widget.onRefresh;
    if (refresh == null) return child;
    return GenesisRefreshIndicator(
      key: widget.refreshKey,
      onRefresh: refresh,
      child: child,
    );
  }
}

class _AnimatedProfileCollectionListItem extends StatefulWidget {
  const _AnimatedProfileCollectionListItem({
    super.key,
    required this.item,
    required this.bottomSpacing,
    required this.onCollapseCompensationChanged,
  });

  final GenesisProfileCollectionItemData item;
  final double bottomSpacing;
  final ValueChanged<double> onCollapseCompensationChanged;

  @override
  State<_AnimatedProfileCollectionListItem> createState() =>
      _AnimatedProfileCollectionListItemState();
}

class _AnimatedProfileCollectionListItemState
    extends State<_AnimatedProfileCollectionListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final GlobalKey _contentKey = GlobalKey();
  double _contentExtent = 0;
  int _animationRevision = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
      value: widget.item.isCollapsing ? 0 : 1,
    )..addListener(_notifyCompensationChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureContentExtent();
      _notifyCompensationChanged();
    });
  }

  @override
  void didUpdateWidget(covariant _AnimatedProfileCollectionListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureContentExtent();
      _notifyCompensationChanged();
    });
    if (oldWidget.item.isCollapsing == widget.item.isCollapsing) return;
    final revision = ++_animationRevision;
    if (widget.item.isCollapsing) {
      unawaited(_collapse(revision));
    } else {
      _controller.animateTo(1, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_notifyCompensationChanged);
    widget.onCollapseCompensationChanged(0);
    _controller.dispose();
    super.dispose();
  }

  void _measureContentExtent() {
    final renderObject = _contentKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    _contentExtent = renderObject.size.height;
  }

  void _notifyCompensationChanged() {
    if (_contentExtent <= 0) return;
    final progress = 1 - _controller.value;
    widget.onCollapseCompensationChanged(
      _contentExtent *
          (1 -
              GenesisDeletedListItemTransition.heightFactorForProgress(
                progress,
              )),
    );
  }

  Future<void> _collapse(int revision) async {
    await _controller.animateTo(0, curve: Curves.linear);
    if (!mounted ||
        revision != _animationRevision ||
        !widget.item.isCollapsing) {
      return;
    }
    widget.item.onCollapsed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return GenesisDeletedListItemTransition(
          progress: 1 - _controller.value,
          child: child!,
        );
      },
      child: RepaintBoundary(
        child: Column(
          key: _contentKey,
          mainAxisSize: MainAxisSize.min,
          children: [
            GenesisProfileCollectionListItem(item: widget.item),
            if (widget.bottomSpacing > 0)
              SizedBox(height: widget.bottomSpacing),
          ],
        ),
      ),
    );
  }
}
