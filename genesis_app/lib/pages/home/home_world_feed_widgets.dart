part of 'home_page.dart';

class _AnimatedHomeWorldListItem extends StatefulWidget {
  const _AnimatedHomeWorldListItem({
    super.key,
    required this.child,
    required this.isCollapsing,
    required this.bottomSpacing,
    required this.onCollapseCompensationChanged,
    required this.onCollapsed,
  });

  final Widget child;
  final bool isCollapsing;
  final double bottomSpacing;
  final ValueChanged<double> onCollapseCompensationChanged;
  final VoidCallback onCollapsed;

  @override
  State<_AnimatedHomeWorldListItem> createState() =>
      _AnimatedHomeWorldListItemState();
}

class _AnimatedHomeWorldListItemState extends State<_AnimatedHomeWorldListItem>
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
      value: widget.isCollapsing ? 0 : 1,
    )..addListener(_notifyCompensationChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureContentExtent();
      _notifyCompensationChanged();
    });
  }

  @override
  void didUpdateWidget(covariant _AnimatedHomeWorldListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureContentExtent();
      _notifyCompensationChanged();
    });
    if (oldWidget.isCollapsing == widget.isCollapsing) return;
    final revision = ++_animationRevision;
    if (widget.isCollapsing) {
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
    if (!mounted || revision != _animationRevision || !widget.isCollapsing) {
      return;
    }
    widget.onCollapsed();
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
            widget.child,
            if (widget.bottomSpacing > 0)
              SizedBox(height: widget.bottomSpacing),
          ],
        ),
      ),
    );
  }
}

class _MyWorldsEmptyState extends StatelessWidget {
  const _MyWorldsEmptyState({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Align(
      alignment: const Alignment(0, -0.2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Semantics(
          button: true,
          label: 'Open Worldo',
          child: GestureDetector(
            key: const ValueKey<String>('home-my-worlds-empty-action'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    children: const [
                      TextSpan(text: 'Launch a '),
                      TextSpan(
                        text: '#Worldo',
                        style: TextStyle(color: GenesisColors.redSecondary),
                      ),
                      TextSpan(text: ' to generate\n'),
                      TextSpan(text: 'your own World'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    color: GenesisColors.darkTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Worldo is the blueprint. Launch to create a live World you can enter and grow.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: GenesisColors.darkTextSecondary,
                    fontSize: 14,
                    height: 1.25,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorldListPage {
  const _WorldListPage({required this.items, required this.total});

  final List<WorldListItem> items;
  final int total;
}
