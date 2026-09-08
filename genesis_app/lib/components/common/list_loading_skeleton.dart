import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_image_radii.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/components/genesis_world_list_card_layout.dart';
import '../../ui/tokens/genesis_origin_card_geometry.dart';

enum _GenesisListSkeletonType { world, originGrid }

class GenesisListLoadingSkeleton extends StatelessWidget {
  const GenesisListLoadingSkeleton.worldList({super.key, this.itemCount = 4})
    : _type = _GenesisListSkeletonType.world;

  const GenesisListLoadingSkeleton.originGrid({super.key, this.itemCount = 8})
    : _type = _GenesisListSkeletonType.originGrid;

  final int itemCount;
  final _GenesisListSkeletonType _type;

  @override
  Widget build(BuildContext context) {
    return switch (_type) {
      _GenesisListSkeletonType.world =>
        Theme.of(context).brightness == Brightness.dark
            ? _WorldListSkeleton(itemCount: itemCount)
            : _SkeletonShimmer(child: _WorldListSkeleton(itemCount: itemCount)),
      _GenesisListSkeletonType.originGrid => _OriginGridSkeleton(
        itemCount: itemCount,
      ),
    };
  }
}

class GenesisListLoadingBone extends StatelessWidget {
  const GenesisListLoadingBone({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 4,
  });

  final double? width;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return _SkeletonShimmer(
      child: _SkeletonBone(
        width: width,
        height: height,
        borderRadius: borderRadius,
      ),
    );
  }
}

class GenesisOriginCardLoadingBone extends StatelessWidget {
  const GenesisOriginCardLoadingBone({
    super.key,
    this.borderRadius = GenesisImageRadii.contentValue,
  });

  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8EBF0), Color(0xFFF3F4F6)],
        ),
      ),
    );
  }
}

enum GenesisSearchResultSkeletonType { origin, world, user }

class GenesisSearchResultLoadingSkeleton extends StatelessWidget {
  const GenesisSearchResultLoadingSkeleton.list({
    super.key,
    required this.type,
    this.itemCount = 6,
  });

  final GenesisSearchResultSkeletonType type;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return _SkeletonShimmer(
      child: _SearchResultSkeletonList(type: type, itemCount: itemCount),
    );
  }
}

class _SearchResultSkeletonList extends StatelessWidget {
  const _SearchResultSkeletonList({
    required this.type,
    required this.itemCount,
  });

  final GenesisSearchResultSkeletonType type;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const ValueKey<String>('genesis-search-result-list-skeleton'),
      primary: false,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: _SearchResultSkeletonItem(type: type),
      ),
    );
  }
}

class _SearchResultSkeletonItem extends StatelessWidget {
  const _SearchResultSkeletonItem({required this.type});

  final GenesisSearchResultSkeletonType type;

  @override
  Widget build(BuildContext context) {
    final isOrigin = type == GenesisSearchResultSkeletonType.origin;
    final isUser = type == GenesisSearchResultSkeletonType.user;
    return Row(
      key: const ValueKey<String>('genesis-search-result-item-skeleton'),
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        _SkeletonBone(
          key: ValueKey<String>(
            'genesis-search-result-${type.name}-thumbnail-skeleton',
          ),
          width: 60,
          height: isOrigin ? 90 : 60,
          borderRadius: isUser ? 30 : GenesisImageRadii.contentValue,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SkeletonBone(
                widthFactor: 0.56,
                height: 14,
                borderRadius: 4,
              ),
              SizedBox(height: isUser ? 7 : 5),
              _SkeletonBone(
                widthFactor: isUser ? 0.42 : 0.76,
                height: 12,
                borderRadius: 4,
              ),
              if (isOrigin) ...[
                const SizedBox(height: 5),
                const _SkeletonBone(
                  widthFactor: 0.88,
                  height: 12,
                  borderRadius: 4,
                ),
                const SizedBox(height: 5),
                const _SkeletonBone(
                  widthFactor: 0.62,
                  height: 12,
                  borderRadius: 4,
                ),
              ],
              if (!isUser) ...[
                const SizedBox(height: 8),
                const _SkeletonLineRow(widths: [30, 34, 32, 30], height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WorldListSkeleton extends StatelessWidget {
  const _WorldListSkeleton({required this.itemCount});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListView.separated(
      key: const ValueKey<String>('genesis-world-list-skeleton'),
      primary: false,
      padding: dark
          ? const EdgeInsets.only(top: 10, bottom: 36)
          : EdgeInsets.zero,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: itemCount,
      separatorBuilder: (context, index) => dark
          ? const SizedBox(height: 30)
          : const Divider(height: 25, thickness: 1, color: Color(0xFFEFEFEF)),
      itemBuilder: (context, index) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _WorldSkeletonItem(),
        );
      },
    );
  }
}

class _WorldSkeletonItem extends StatelessWidget {
  const _WorldSkeletonItem();

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBone(
            key: ValueKey<String>('genesis-world-list-thumbnail-skeleton'),
            width: GenesisWorldListCardLayout.coverWidth,
            height: GenesisWorldListCardLayout.coverHeight,
            borderRadius: GenesisImageRadii.contentValue,
          ),
          SizedBox(width: GenesisWorldListCardLayout.contentGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBone(widthFactor: 0.65, height: 14),
                SizedBox(height: 6),
                _SkeletonBone(widthFactor: 0.78, height: 12),
                SizedBox(height: 6),
                _SkeletonBone(widthFactor: 0.95, height: 12),
                SizedBox(height: 5),
                _SkeletonBone(widthFactor: 0.7, height: 12),
                SizedBox(height: 6),
                Row(
                  children: [
                    _SkeletonBone(width: 25, height: 25, borderRadius: 8),
                    SizedBox(width: 6),
                    _SkeletonBone(width: 90, height: 12),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonBone(
              key: ValueKey<String>('genesis-world-list-thumbnail-skeleton'),
              width: 60,
              height: 60,
              borderRadius: GenesisImageRadii.contentValue,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBone(widthFactor: 0.44, height: 14, borderRadius: 4),
                  SizedBox(height: 7),
                  _SkeletonLineRow(widths: [74, 86], height: 12),
                  SizedBox(height: 10),
                  _SkeletonLineRow(widths: [34, 42, 36, 38], height: 12),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        _SkeletonProgressHeader(titleWidth: 104, trailingWidth: 58),
        SizedBox(height: 10),
        _SkeletonBone(widthFactor: 0.96, height: 10, borderRadius: 4),
        SizedBox(height: 7),
        _SkeletonBone(widthFactor: 0.9, height: 10, borderRadius: 4),
        SizedBox(height: 7),
        _SkeletonBone(widthFactor: 0.72, height: 10, borderRadius: 4),
      ],
    );
  }
}

class _SkeletonProgressHeader extends StatelessWidget {
  const _SkeletonProgressHeader({required this.titleWidth, this.trailingWidth});

  final double titleWidth;
  final double? trailingWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _SkeletonBone(width: 14, height: 14, borderRadius: 7),
        const SizedBox(width: 5),
        _SkeletonBone(width: titleWidth, height: 14, borderRadius: 4),
        if (trailingWidth case final width?) ...[
          const Spacer(),
          _SkeletonBone(width: width, height: 12, borderRadius: 4),
        ],
      ],
    );
  }
}

class _OriginGridSkeleton extends StatelessWidget {
  const _OriginGridSkeleton({required this.itemCount});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const ValueKey<String>('genesis-origin-grid-skeleton'),
      primary: true,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(2, 5, 2, 0),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              const crossAxisSpacing = 2.0;
              final itemWidth =
                  (constraints.crossAxisExtent - crossAxisSpacing) / 2;
              final itemHeight =
                  itemWidth / genesisOriginCoverAspectRatio +
                  genesisOriginCardBottomExtension;
              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: crossAxisSpacing,
                  mainAxisExtent: itemHeight,
                ),
                itemCount: itemCount,
                itemBuilder: (context, index) =>
                    const _OriginGridSkeletonItem(),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OriginGridSkeletonItem extends StatelessWidget {
  const _OriginGridSkeletonItem();

  @override
  Widget build(BuildContext context) {
    return const GenesisOriginCardLoadingBone(
      key: ValueKey<String>('genesis-origin-grid-item-skeleton'),
    );
  }
}

class _SkeletonLineRow extends StatelessWidget {
  const _SkeletonLineRow({required this.widths, required this.height});

  final List<double> widths;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in widths.indexed) ...[
          _SkeletonBone(width: entry.$2, height: height, borderRadius: 4),
          if (entry.$1 != widths.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _SkeletonShimmer extends StatefulWidget {
  const _SkeletonShimmer({required this.child});

  final Widget child;

  @override
  State<_SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<_SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SkeletonAnimation(animation: _controller, child: widget.child);
  }
}

class _SkeletonAnimation extends InheritedWidget {
  const _SkeletonAnimation({required this.animation, required super.child});

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_SkeletonAnimation>()
        ?.animation;
  }

  @override
  bool updateShouldNotify(covariant _SkeletonAnimation oldWidget) {
    return animation != oldWidget.animation;
  }
}

class _SkeletonBone extends StatelessWidget {
  const _SkeletonBone({
    super.key,
    this.width,
    this.widthFactor,
    this.height,
    this.borderRadius = 4,
  }) : assert(width == null || widthFactor == null);

  final double? width;
  final double? widthFactor;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final animation = _SkeletonAnimation.maybeOf(context);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    Widget child = SizedBox(
      width: width,
      height: height,
      child: Theme.of(context).brightness == Brightness.dark
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: GenesisColors.darkFaintFill,
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            )
          : animation == null || disableAnimations
          ? _buildDecoratedBox(0)
          : AnimatedBuilder(
              animation: animation,
              builder: (context, child) => _buildDecoratedBox(animation.value),
            ),
    );

    if (widthFactor case final factor?) {
      child = FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: factor,
        child: child,
      );
    }
    return child;
  }

  Widget _buildDecoratedBox(double animationValue) {
    final offset = -1.4 + (animationValue * 2.8);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment(offset - 0.8, 0),
          end: Alignment(offset + 0.8, 0),
          colors: const [
            Color(0xFFE8EBF0),
            Color(0xFFF6F7F9),
            Color(0xFFE8EBF0),
          ],
          stops: const [0.25, 0.5, 0.75],
        ),
      ),
    );
  }
}
