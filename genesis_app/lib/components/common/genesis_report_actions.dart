import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/bootstrap/app_services_scope.dart';
import 'genesis_content_submission_dialog.dart';

const TextStyle _genesisActionMenuTextStyle = TextStyle(
  fontSize: 12,
  height: 1.2,
  fontWeight: FontWeight.w400,
  color: _genesisActionMenuForegroundColor,
);
const String genesisReportIconAsset =
    'assets/custom-icons/svg/report-svgrepo-com.svg';
const String genesisDeleteIconAsset = 'assets/custom-icons/svg/delete-icon.svg';
const double _genesisActionMenuMinWidth = 96;
const double _genesisActionMenuHorizontalPadding = 14;
const double _genesisActionMenuIconSize = 15;
const double _genesisActionMenuIconGap = 8;
const double _genesisActionMenuRowHeight = 36;
const double _genesisActionMenuArrowWidth = 14;
const double _genesisActionMenuArrowHeight = 8;
const double _genesisActionMenuScreenPadding = 8;
const double _genesisActionMenuTriggerGap = 12;
const double _genesisActionMenuVerticalLift = 4;
const double _genesisActionMenuDownwardScreenRatio = 0.2;
const double _genesisActionMenuShadowPadding = 12;
const double _genesisActionMenuBorderRadius = 8;
const Color _genesisActionMenuBackgroundColor = Color(0xFF666666);
const Color _genesisActionMenuForegroundColor = Colors.white;

enum GenesisActionMenuAppearance { standard, message }

class GenesisActionMenuItem {
  const GenesisActionMenuItem({
    required this.label,
    required this.onSelected,
    this.textStyle,
    this.iconAsset,
    this.iconData,
  });

  final String label;
  final VoidCallback onSelected;
  final TextStyle? textStyle;
  final String? iconAsset;
  final IconData? iconData;
}

class GenesisMoreActionMenuButton extends StatefulWidget {
  const GenesisMoreActionMenuButton({
    super.key,
    required this.items,
    this.iconSize = 18,
    this.appearance = GenesisActionMenuAppearance.standard,
    this.iconColor = Colors.black,
    this.buttonSize = 38,
    this.menuRightInset,
    this.menuVerticalOffset = 0,
    this.visualRightInset,
  });

  final List<GenesisActionMenuItem> items;
  final GenesisActionMenuAppearance appearance;
  final double iconSize;
  final Color iconColor;
  final double buttonSize;
  final double? menuRightInset;
  final double menuVerticalOffset;
  final double? visualRightInset;

  @override
  State<GenesisMoreActionMenuButton> createState() =>
      _GenesisMoreActionMenuButtonState();
}

class _GenesisMoreActionMenuButtonState
    extends State<GenesisMoreActionMenuButton> {
  _GenesisActionMenuHandle? _menuHandle;

  @override
  void dispose() {
    _menuHandle?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: widget.buttonSize,
      height: widget.buttonSize,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(
          width: widget.buttonSize,
          height: widget.buttonSize,
        ),
        icon: Icon(
          Icons.more_horiz_sharp,
          size: widget.iconSize,
          color: widget.iconColor,
        ),
        onPressed: () => _showFromButton(context),
      ),
    );
    final visualRightInset = widget.visualRightInset;
    if (visualRightInset == null) return button;
    final centeredIconTrailingSpace = (widget.buttonSize - widget.iconSize) / 2;
    final trailingPadding = visualRightInset > centeredIconTrailingSpace
        ? visualRightInset - centeredIconTrailingSpace
        : 0.0;
    return SizedBox(
      width: widget.buttonSize + trailingPadding,
      height: widget.buttonSize,
      child: Align(alignment: Alignment.centerLeft, child: button),
    );
  }

  void _showFromButton(BuildContext context) {
    _menuHandle?.close();
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final route = ModalRoute.of(context);
    final topLeft = box.localToGlobal(Offset.zero);
    final buttonCenter = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    _menuHandle = _showGenesisActionMenuAtInternal(
      context: context,
      globalPosition: buttonCenter,
      triggerRect: topLeft & box.size,
      items: widget.items,
      placement: _GenesisActionMenuPlacement.leftOfTrigger,
      appearance: widget.appearance,
      rightInset: widget.menuRightInset,
      verticalOffset: widget.menuVerticalOffset,
    );
    final handle = _menuHandle;
    if (handle != null) {
      unawaited(handle.closed.whenComplete(() => _menuHandle = null));
      if (route != null) {
        unawaited(route.popped.whenComplete(handle.close));
      }
    }
  }
}

enum _GenesisActionMenuPlacement { anchoredBubble, leftOfTrigger }

class _GenesisActionMenuPosition {
  const _GenesisActionMenuPosition({
    required this.left,
    required this.top,
    required this.expandsDown,
    required this.arrowCenterX,
    required this.width,
    required this.showArrow,
  });

  final double left;
  final double top;
  final bool expandsDown;
  final double arrowCenterX;
  final double width;
  final bool showArrow;
}

_GenesisActionMenuPosition _genesisActionMenuPosition({
  required Offset globalPosition,
  required Size overlaySize,
  required int itemCount,
  required double menuWidth,
}) {
  final menuHeight = itemCount * _genesisActionMenuRowHeight;
  final totalHeight = menuHeight + _genesisActionMenuArrowHeight;
  final minArrowCenterX = _genesisActionMenuArrowWidth / 2;
  final maxArrowCenterX = menuWidth - _genesisActionMenuArrowWidth / 2;
  final desiredLeft = globalPosition.dx - menuWidth / 2;
  final maxLeft =
      overlaySize.width - menuWidth - _genesisActionMenuScreenPadding;
  final maxTop =
      overlaySize.height - totalHeight - _genesisActionMenuScreenPadding;
  final expandsDown =
      globalPosition.dy <=
      overlaySize.height * _genesisActionMenuDownwardScreenRatio;
  final desiredTop = expandsDown
      ? globalPosition.dy +
            _genesisActionMenuTriggerGap -
            _genesisActionMenuVerticalLift
      : globalPosition.dy -
            _genesisActionMenuTriggerGap -
            totalHeight -
            _genesisActionMenuVerticalLift;
  final left = desiredLeft
      .clamp(
        _genesisActionMenuScreenPadding,
        maxLeft < _genesisActionMenuScreenPadding
            ? _genesisActionMenuScreenPadding
            : maxLeft,
      )
      .toDouble();
  final top = desiredTop
      .clamp(
        _genesisActionMenuScreenPadding,
        maxTop < _genesisActionMenuScreenPadding
            ? _genesisActionMenuScreenPadding
            : maxTop,
      )
      .toDouble();
  final arrowCenterX = (globalPosition.dx - left)
      .clamp(minArrowCenterX, maxArrowCenterX)
      .toDouble();

  return _GenesisActionMenuPosition(
    left: left,
    top: top,
    expandsDown: expandsDown,
    arrowCenterX: arrowCenterX,
    width: menuWidth,
    showArrow: true,
  );
}

_GenesisActionMenuPosition _genesisActionMenuLeftPosition({
  required Rect triggerRect,
  required Size overlaySize,
  required int itemCount,
  required double menuWidth,
  double? rightInset,
  double verticalOffset = 0,
}) {
  final menuHeight = itemCount * _genesisActionMenuRowHeight;
  final maxLeft =
      overlaySize.width - menuWidth - _genesisActionMenuScreenPadding;
  final desiredLeft = rightInset == null
      ? triggerRect.left - menuWidth
      : overlaySize.width - rightInset - menuWidth;
  final maxTop =
      overlaySize.height - menuHeight - _genesisActionMenuScreenPadding;
  // Keep the first action row aligned with the trigger. Additional rows then
  // expand below it, so a two-item profile menu keeps Block below Report.
  final desiredTop =
      triggerRect.center.dy - _genesisActionMenuRowHeight / 2 + verticalOffset;
  return _GenesisActionMenuPosition(
    left: desiredLeft
        .clamp(
          _genesisActionMenuScreenPadding,
          maxLeft < _genesisActionMenuScreenPadding
              ? _genesisActionMenuScreenPadding
              : maxLeft,
        )
        .toDouble(),
    top: desiredTop
        .clamp(
          _genesisActionMenuScreenPadding,
          maxTop < _genesisActionMenuScreenPadding
              ? _genesisActionMenuScreenPadding
              : maxTop,
        )
        .toDouble(),
    expandsDown: true,
    arrowCenterX: 0,
    width: menuWidth,
    showArrow: false,
  );
}

class _GenesisActionMenuLayout {
  _GenesisActionMenuLayout({
    required this.appearance,
    required this.textScaler,
    required List<GenesisActionMenuItem> items,
  }) {
    rowCount = isHorizontal ? 1 : items.length;
    width = _widthFor(items);
  }

  final GenesisActionMenuAppearance appearance;
  final TextScaler textScaler;
  late final int rowCount;
  late final double width;

  bool get isHorizontal => appearance == GenesisActionMenuAppearance.message;

  Color get backgroundColor => _genesisActionMenuBackgroundColor;

  Color get foregroundColor => _genesisActionMenuForegroundColor;

  TextStyle get defaultTextStyle =>
      appearance == GenesisActionMenuAppearance.message
      ? const TextStyle(
          fontSize: 12,
          height: 1.2,
          fontWeight: FontWeight.w400,
          color: _genesisActionMenuForegroundColor,
        )
      : _genesisActionMenuTextStyle.copyWith(color: foregroundColor);

  ColorFilter get iconColorFilter =>
      ColorFilter.mode(foregroundColor, BlendMode.srcIn);

  double _widthFor(List<GenesisActionMenuItem> items) {
    if (isHorizontal) {
      final total = items.fold<double>(0, (sum, item) => sum + itemWidth(item));
      return total < _genesisActionMenuMinWidth
          ? _genesisActionMenuMinWidth
          : total;
    }
    var width = _genesisActionMenuMinWidth;
    for (final item in items) {
      final itemWidth = this.itemWidth(item);
      if (itemWidth > width) width = itemWidth;
    }
    return width;
  }

  double itemWidth(GenesisActionMenuItem item) {
    final painter = TextPainter(
      text: TextSpan(
        text: item.label,
        style: item.textStyle ?? defaultTextStyle,
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final hasIcon = item.iconAsset != null || item.iconData != null;
    final iconWidth = !hasIcon
        ? 0
        : _genesisActionMenuIconSize + _genesisActionMenuIconGap;
    return (_genesisActionMenuHorizontalPadding * 2 + iconWidth + painter.width)
            .ceilToDouble() +
        2;
  }
}

class _GenesisActionMenuHandle {
  _GenesisActionMenuHandle({
    required OverlayEntry entry,
    required Completer<void> completer,
    required Rect menuBounds,
  }) : _entry = entry,
       _completer = completer,
       _menuBounds = menuBounds {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
  }

  static _GenesisActionMenuHandle? _active;

  final OverlayEntry _entry;
  final Completer<void> _completer;
  final Rect _menuBounds;

  Future<void> get closed => _completer.future;

  void activate() {
    if (_active == this) return;
    _active?.close();
    _active = this;
  }

  void close() {
    if (_completer.isCompleted) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handlePointerEvent,
    );
    if (_active == this) _active = null;
    _entry.remove();
    _completer.complete();
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event is! PointerDownEvent) return;
    if (_menuBounds.contains(event.position)) return;
    close();
  }
}

Future<void> showGenesisActionMenuAt({
  required BuildContext context,
  required Offset globalPosition,
  required List<GenesisActionMenuItem> items,
  GenesisActionMenuAppearance appearance = GenesisActionMenuAppearance.standard,
}) async {
  final handle = _showGenesisActionMenuAtInternal(
    context: context,
    globalPosition: globalPosition,
    items: items,
    placement: _GenesisActionMenuPlacement.anchoredBubble,
    appearance: appearance,
  );
  if (handle == null) return;
  return handle.closed;
}

_GenesisActionMenuHandle? _showGenesisActionMenuAtInternal({
  required BuildContext context,
  required Offset globalPosition,
  required List<GenesisActionMenuItem> items,
  required _GenesisActionMenuPlacement placement,
  required GenesisActionMenuAppearance appearance,
  Rect? triggerRect,
  double? rightInset,
  double verticalOffset = 0,
}) {
  if (items.isEmpty) return null;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  final overlayBox = overlay.context.findRenderObject();
  if (overlayBox is! RenderBox) return null;
  final completer = Completer<void>();
  late OverlayEntry entry;
  void close() {
    if (completer.isCompleted) return;
    entry.remove();
    completer.complete();
  }

  final layout = _GenesisActionMenuLayout(
    appearance: appearance,
    textScaler: MediaQuery.textScalerOf(context),
    items: items,
  );
  final menuWidth = layout.width;
  final rowCount = layout.rowCount;
  final position =
      placement == _GenesisActionMenuPlacement.leftOfTrigger &&
          triggerRect != null
      ? _genesisActionMenuLeftPosition(
          triggerRect: triggerRect,
          overlaySize: overlayBox.size,
          itemCount: rowCount,
          menuWidth: menuWidth,
          rightInset: rightInset,
          verticalOffset: verticalOffset,
        )
      : _genesisActionMenuPosition(
          globalPosition: globalPosition,
          overlaySize: overlayBox.size,
          itemCount: rowCount,
          menuWidth: menuWidth,
        );
  final totalMenuHeight =
      rowCount * _genesisActionMenuRowHeight +
      (position.showArrow ? _genesisActionMenuArrowHeight : 0);
  final menuBounds = Rect.fromLTWH(
    position.left - _genesisActionMenuShadowPadding,
    position.top - _genesisActionMenuShadowPadding,
    position.width + _genesisActionMenuShadowPadding * 2,
    totalMenuHeight + _genesisActionMenuShadowPadding * 2,
  );
  entry = OverlayEntry(
    builder: (context) {
      return Stack(
        children: [
          Positioned(
            left: position.left - _genesisActionMenuShadowPadding,
            top: position.top - _genesisActionMenuShadowPadding,
            width: position.width + _genesisActionMenuShadowPadding * 2,
            child: Padding(
              padding: const EdgeInsets.all(_genesisActionMenuShadowPadding),
              child: _GenesisActionBubble(
                items: items,
                layout: layout,
                width: position.width,
                expandsDown: position.expandsDown,
                showArrow: position.showArrow,
                arrowCenterX: position.arrowCenterX,
                onDismiss: close,
              ),
            ),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
  final handle = _GenesisActionMenuHandle(
    entry: entry,
    completer: completer,
    menuBounds: menuBounds,
  );
  handle.activate();
  return handle;
}

class _GenesisActionBubble extends StatelessWidget {
  const _GenesisActionBubble({
    required this.items,
    required this.layout,
    required this.width,
    required this.expandsDown,
    required this.showArrow,
    required this.arrowCenterX,
    required this.onDismiss,
  });

  final List<GenesisActionMenuItem> items;
  final _GenesisActionMenuLayout layout;
  final double width;
  final bool expandsDown;
  final bool showArrow;
  final double arrowCenterX;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final arrow = _GenesisActionBubbleArrow(
      width: width,
      pointsUp: expandsDown,
      centerX: arrowCenterX,
      color: layout.backgroundColor,
    );
    final body = _GenesisActionBubbleBody(
      items: items,
      layout: layout,
      width: width,
      onDismiss: onDismiss,
    );
    return Material(
      color: Colors.transparent,
      child: CustomPaint(
        painter: _GenesisActionBubbleShadowPainter(
          itemCount: layout.rowCount,
          width: width,
          showArrow: showArrow,
          expandsDown: expandsDown,
          arrowCenterX: arrowCenterX,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: showArrow
              ? (expandsDown ? [arrow, body] : [body, arrow])
              : [body],
        ),
      ),
    );
  }
}

class _GenesisActionBubbleShadowPainter extends CustomPainter {
  const _GenesisActionBubbleShadowPainter({
    required this.itemCount,
    required this.width,
    required this.showArrow,
    required this.expandsDown,
    required this.arrowCenterX,
  });

  final int itemCount;
  final double width;
  final bool showArrow;
  final bool expandsDown;
  final double arrowCenterX;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _genesisActionBubblePath(
      itemCount: itemCount,
      width: width,
      showArrow: showArrow,
      expandsDown: expandsDown,
      arrowCenterX: arrowCenterX,
    );
    final shadow = const BoxShadow(
      color: Color(0x24000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    );
    canvas.save();
    canvas.translate(shadow.offset.dx, shadow.offset.dy);
    canvas.drawPath(path, shadow.toPaint());
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GenesisActionBubbleShadowPainter oldDelegate) {
    return oldDelegate.itemCount != itemCount ||
        oldDelegate.width != width ||
        oldDelegate.showArrow != showArrow ||
        oldDelegate.expandsDown != expandsDown ||
        oldDelegate.arrowCenterX != arrowCenterX;
  }
}

Path _genesisActionBubblePath({
  required int itemCount,
  required double width,
  required bool showArrow,
  required bool expandsDown,
  required double arrowCenterX,
}) {
  final bodyHeight = itemCount * _genesisActionMenuRowHeight;
  final bodyTop = showArrow && expandsDown
      ? _genesisActionMenuArrowHeight
      : 0.0;
  final bodyRect = Rect.fromLTWH(0, bodyTop, width, bodyHeight);
  final path = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        bodyRect,
        const Radius.circular(_genesisActionMenuBorderRadius),
      ),
    );
  if (!showArrow) return path;
  if (expandsDown) {
    path
      ..moveTo(arrowCenterX, 0)
      ..lineTo(
        arrowCenterX + _genesisActionMenuArrowWidth / 2,
        _genesisActionMenuArrowHeight,
      )
      ..lineTo(
        arrowCenterX - _genesisActionMenuArrowWidth / 2,
        _genesisActionMenuArrowHeight,
      )
      ..close();
  } else {
    final arrowTop = bodyHeight;
    path
      ..moveTo(arrowCenterX - _genesisActionMenuArrowWidth / 2, arrowTop)
      ..lineTo(arrowCenterX + _genesisActionMenuArrowWidth / 2, arrowTop)
      ..lineTo(arrowCenterX, arrowTop + _genesisActionMenuArrowHeight)
      ..close();
  }
  return path;
}

class _GenesisActionBubbleBody extends StatelessWidget {
  const _GenesisActionBubbleBody({
    required this.items,
    required this.layout,
    required this.width,
    required this.onDismiss,
  });

  final List<GenesisActionMenuItem> items;
  final _GenesisActionMenuLayout layout;
  final double width;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: layout.backgroundColor,
        borderRadius: BorderRadius.circular(_genesisActionMenuBorderRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_genesisActionMenuBorderRadius),
        child: layout.isHorizontal
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items)
                    _GenesisActionBubbleRow(
                      item: item,
                      layout: layout,
                      width: layout.itemWidth(item),
                      onTap: () {
                        onDismiss();
                        item.onSelected();
                      },
                    ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    _GenesisActionBubbleRow(
                      item: items[index],
                      layout: layout,
                      width: width,
                      onTap: () {
                        onDismiss();
                        items[index].onSelected();
                      },
                    ),
                    if (index != items.length - 1)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0x33FFFFFF),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _GenesisActionBubbleRow extends StatelessWidget {
  const _GenesisActionBubbleRow({
    required this.item,
    required this.layout,
    required this.width,
    required this.onTap,
  });

  final GenesisActionMenuItem item;
  final _GenesisActionMenuLayout layout;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final itemColor = item.textStyle?.color ?? layout.foregroundColor;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _genesisActionMenuRowHeight,
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _genesisActionMenuHorizontalPadding,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.iconAsset case final iconAsset?) ...[
                SvgPicture.asset(
                  iconAsset,
                  width: _genesisActionMenuIconSize,
                  height: _genesisActionMenuIconSize,
                  colorFilter: ColorFilter.mode(itemColor, BlendMode.srcIn),
                ),
                const SizedBox(width: _genesisActionMenuIconGap),
              ] else if (item.iconData case final iconData?) ...[
                Icon(
                  iconData,
                  size: _genesisActionMenuIconSize,
                  color: itemColor,
                ),
                const SizedBox(width: _genesisActionMenuIconGap),
              ],
              Text(
                item.label,
                maxLines: 1,
                style: item.textStyle ?? layout.defaultTextStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenesisActionBubbleArrow extends StatelessWidget {
  const _GenesisActionBubbleArrow({
    required this.width,
    required this.pointsUp,
    required this.centerX,
    required this.color,
  });

  final double width;
  final bool pointsUp;
  final double centerX;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _genesisActionMenuArrowHeight,
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: centerX - _genesisActionMenuArrowWidth / 2,
            top: 0,
            child: CustomPaint(
              size: const Size(
                _genesisActionMenuArrowWidth,
                _genesisActionMenuArrowHeight,
              ),
              painter: _GenesisActionBubbleArrowPainter(
                pointsUp: pointsUp,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GenesisActionBubbleArrowPainter extends CustomPainter {
  const _GenesisActionBubbleArrowPainter({
    required this.pointsUp,
    required this.color,
  });

  final bool pointsUp;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointsUp) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _GenesisActionBubbleArrowPainter oldDelegate) {
    return oldDelegate.pointsUp != pointsUp || oldDelegate.color != color;
  }
}

GenesisActionMenuItem genesisReportMenuItem({
  required BuildContext context,
  required String targetType,
  required String targetId,
}) {
  return GenesisActionMenuItem(
    label: 'Report',
    iconAsset: genesisReportIconAsset,
    onSelected: () {
      showGenesisReportDialog(
        context: context,
        targetType: targetType,
        targetId: targetId,
      );
    },
  );
}

Future<bool> showGenesisReportDialog({
  required BuildContext context,
  required String targetType,
  required String targetId,
}) async {
  if (!context.mounted) return false;
  final api = AppServicesScope.read(context).api;
  return showGenesisContentSubmissionDialog(
    context: context,
    title: 'Report',
    contentInputKey: const ValueKey<String>('genesis-report-content-input'),
    successMessage: 'Report submitted',
    failureMessage: 'Report failed',
    onSubmit: (content) {
      return api.v1.report.create(
        targetType: targetType,
        targetId: targetId,
        content: content,
      );
    },
  );
}
