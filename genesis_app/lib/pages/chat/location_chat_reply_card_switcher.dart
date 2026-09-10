import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../components/chat/shared/chat_ui.dart';

const replyCardSwitchDuration = Duration(milliseconds: 240);

class LocationChatReplyCard {
  const LocationChatReplyCard({
    required this.id,
    required this.messages,
    this.status,
  });
  final int id;
  final List<ChatMessageVm> messages;
  final Widget? status;
}

/// Owns only the transient gesture. The owner commits business state on settle.
class LocationChatReplyCardSwitcher extends StatefulWidget {
  const LocationChatReplyCardSwitcher({
    super.key,
    required this.identity,
    required this.cards,
    required this.currentCardId,
    required this.cardBuilder,
    required this.onCommit,
    required this.onBusyChanged,
    required this.onWillChangeLayout,
    this.enabled = true,
  });
  final String identity;
  final List<LocationChatReplyCard> cards;
  final int currentCardId;
  final Widget Function(LocationChatReplyCard card) cardBuilder;
  final bool Function(int cardId) onCommit;
  final ValueChanged<bool> onBusyChanged;
  final VoidCallback onWillChangeLayout;
  final bool enabled;

  @override
  State<LocationChatReplyCardSwitcher> createState() =>
      LocationChatReplyCardSwitcherState();
}

class LocationChatReplyCardSwitcherState
    extends State<LocationChatReplyCardSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late int _displayedId;
  int? _targetId;
  int _delta = 0, _generation = 0;
  double _progress = 0, _dragDistance = 0, _width = 1;
  bool _busy = false, _dragging = false;
  double _from = 0, _to = 0;

  LocationChatReplyCard? _card(int? id) =>
      widget.cards.where((card) => card.id == id).firstOrNull;
  int get _index => widget.cards.indexWhere((card) => card.id == _displayedId);
  LocationChatReplyCard? _neighbor(int delta) {
    final index = _index + delta;
    return _index >= 0 && index >= 0 && index < widget.cards.length
        ? widget.cards[index]
        : null;
  }

  @override
  void initState() {
    super.initState();
    _displayedId = widget.currentCardId;
    _animation =
        AnimationController(
          vsync: this,
          duration: replyCardSwitchDuration,
        )..addListener(() {
          widget.onWillChangeLayout();
          setState(
            () => _progress =
                _from +
                (_to - _from) * Curves.easeOutCubic.transform(_animation.value),
          );
        });
  }

  @override
  void didUpdateWidget(LocationChatReplyCardSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.identity != oldWidget.identity ||
        widget.currentCardId != oldWidget.currentCardId ||
        !widget.enabled ||
        (_targetId != null && _card(_targetId) == null)) {
      _reset(deferred: true);
      _displayedId = widget.currentCardId;
    }
  }

  void _setBusy(bool value, {bool deferred = false}) {
    if (_busy == value) return;
    _busy = value;
    final callback = widget.onBusyChanged;
    if (deferred) {
      scheduleMicrotask(() => callback(value));
    } else {
      callback(value);
    }
  }

  void _reset({bool deferred = false}) {
    _generation++;
    _animation.stop();
    _dragging = false;
    _progress = 0;
    _targetId = null;
    _delta = 0;
    _setBusy(false, deferred: deferred);
  }

  void switchBy(int delta) {
    if (!widget.enabled || _busy || _neighbor(delta) == null) return;
    _delta = delta;
    _targetId = _neighbor(delta)!.id;
    _setBusy(true);
    unawaited(_settle(commit: true));
  }

  Future<void> _settle({required bool commit}) async {
    final generation = ++_generation;
    final target = _targetId;
    _dragging = false;
    _from = _progress;
    _to = commit ? 1 : 0;
    if (!MediaQuery.disableAnimationsOf(context)) {
      try {
        await _animation.forward(from: 0).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || generation != _generation || !widget.enabled) return;
    widget.onWillChangeLayout();
    if (commit &&
        target != null &&
        _card(target) != null &&
        widget.onCommit(target)) {
      _displayedId = target;
    }
    setState(_reset);
  }

  void _startDrag(DragStartDetails details) {
    if (_busy || !widget.enabled) return;
    _dragging = true;
    _dragDistance = 0;
    _setBusy(true);
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!_dragging) return;
    _dragDistance = (_dragDistance + details.delta.dx).clamp(-_width, _width);
    final delta = _dragDistance < 0 ? 1 : -1;
    final neighbor = _neighbor(delta);
    widget.onWillChangeLayout();
    setState(() {
      _delta = delta;
      _targetId = neighbor?.id;
      final distance = _dragDistance.abs() / _width;
      _progress = neighbor == null ? math.min(0.12, distance * 0.25) : distance;
    });
  }

  void _endDrag(DragEndDetails details) {
    if (!_dragging) return;
    final velocity = details.primaryVelocity ?? 0;
    final fast = velocity * -_delta >= 650;
    unawaited(
      _settle(commit: _targetId != null && (_progress >= 0.25 || fast)),
    );
  }

  @override
  void dispose() {
    _generation++;
    _animation.dispose();
    _setBusy(false, deferred: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _card(_displayedId);
    if (current == null) return const SizedBox.shrink();
    final target = _card(_targetId);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = math.max(1, constraints.maxWidth);
        return Listener(
          onPointerCancel: (_) {
            if (_dragging) unawaited(_settle(commit: false));
          },
          child: GestureDetector(
            key: const ValueKey('reply-card-gesture'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: widget.enabled ? _startDrag : null,
            onHorizontalDragUpdate: widget.enabled ? _updateDrag : null,
            onHorizontalDragEnd: widget.enabled ? _endDrag : null,
            onHorizontalDragCancel: widget.enabled
                ? () {
                    if (_dragging) unawaited(_settle(commit: false));
                  }
                : null,
            child: ClipRect(
              child: _SlidingCardLayout(
                progress: _progress,
                delta: _delta,
                children: [
                  IgnorePointer(
                    key: ValueKey('reply-card-page-${current.id}'),
                    ignoring: _busy,
                    child: widget.cardBuilder(current),
                  ),
                  if (target != null)
                    ExcludeSemantics(
                      key: ValueKey('reply-card-page-${target.id}'),
                      child: IgnorePointer(child: widget.cardBuilder(target)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SlidingCardLayout extends MultiChildRenderObjectWidget {
  const _SlidingCardLayout({
    required this.progress,
    required this.delta,
    required super.children,
  });
  final double progress;
  final int delta;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSlidingCards(progress, delta);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSlidingCards renderObject,
  ) {
    renderObject.update(progress, delta);
  }
}

class _CardParentData extends ContainerBoxParentData<RenderBox> {}

/// Measures both variable-height pages in one layout pass; no post-frame jump.
class _RenderSlidingCards extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CardParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CardParentData> {
  _RenderSlidingCards(this.progress, this.delta);
  double progress;
  int delta;
  void update(double nextProgress, int nextDelta) {
    if (progress == nextProgress && delta == nextDelta) return;
    progress = nextProgress;
    delta = nextDelta;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CardParentData) {
      child.parentData = _CardParentData();
    }
  }

  @override
  void performLayout() {
    final first = firstChild!;
    final second = childAfter(first);
    final childConstraints = BoxConstraints.tightFor(
      width: constraints.maxWidth,
    );
    first.layout(childConstraints, parentUsesSize: true);
    second?.layout(childConstraints, parentUsesSize: true);
    final height =
        first.size.height +
        ((second?.size.height ?? first.size.height) - first.size.height) *
            progress;
    size = constraints.constrain(Size(constraints.maxWidth, height));
    (first.parentData! as _CardParentData).offset = Offset(
      -delta * progress * size.width,
      size.height - first.size.height,
    );
    if (second != null) {
      (second.parentData! as _CardParentData).offset = Offset(
        delta * (1 - progress) * size.width,
        size.height - second.size.height,
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = (child.parentData! as _CardParentData).offset;
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }
}
