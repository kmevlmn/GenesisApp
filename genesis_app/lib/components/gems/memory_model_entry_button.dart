import 'dart:ui';

import '../../ui/tokens/genesis_blur.dart';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const double kMemoryModelEntryMinWidth = 82;
const double kMemoryModelEntryMaxWidth = 96;
const double kMemoryModelRoomHeaderMinWidth = 62;

enum MemoryModelEntryButtonVariant { standard, roomHeader }

class MemoryModelEntryButton extends StatelessWidget {
  const MemoryModelEntryButton({
    super.key,
    required this.modelLabel,
    required this.onTap,
    this.darkHeader = false,
    this.compact = false,
    this.variant = MemoryModelEntryButtonVariant.standard,
  });

  final String modelLabel;
  final VoidCallback onTap;
  final bool darkHeader;
  final bool compact;
  final MemoryModelEntryButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    if (variant == MemoryModelEntryButtonVariant.roomHeader) {
      return _buildRoomHeaderButton();
    }

    final foreground = darkHeader ? Colors.white : Colors.black;
    final background = darkHeader
        ? Colors.transparent
        : Colors.white.withValues(alpha: 0.9);
    final borderRadius = compact ? 11.5 : 19.0;
    final iconSize = compact ? 16.0 : 18.0;
    final labelStyle = TextStyle(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w400,
      color: foreground,
    );
    final labelPainter = TextPainter(
      text: TextSpan(text: modelLabel, style: labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final buttonWidth = (20 + iconSize + 5 + labelPainter.width)
        .clamp(kMemoryModelEntryMinWidth, kMemoryModelEntryMaxWidth)
        .toDouble();
    return Material(
      key: const ValueKey('memory-model-entry'),
      color: background,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: SizedBox(
          width: buttonWidth,
          height: compact ? 23 : 38,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  'assets/custom-icons/svg/arrow-change-svgrepo-com.svg',
                  width: iconSize,
                  height: iconSize,
                  colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    modelLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomHeaderButton() {
    const foreground = Colors.white;
    const labelColor = Color(0xFFF4F3F6);
    const borderRadius = BorderRadius.all(Radius.circular(9));
    const labelStyle = TextStyle(
      color: labelColor,
      fontSize: 11,
      height: 1,
      fontWeight: FontWeight.w600,
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GenesisBlur.strong,
          sigmaY: GenesisBlur.strong,
        ),
        child: Material(
          key: const ValueKey('memory-model-entry'),
          color: foreground.withValues(alpha: 0.13),
          shape: const RoundedRectangleBorder(borderRadius: borderRadius)
              .copyWith(
                side: BorderSide(color: foreground.withValues(alpha: 0.18)),
              ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStatePropertyAll<Color>(
              foreground.withValues(alpha: 0.08),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: kMemoryModelRoomHeaderMinWidth,
                minHeight: 28,
                maxHeight: 28,
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomPaint(
                      key: const ValueKey('memory-model-entry-icon'),
                      size: const Size.square(12),
                      painter: const _MemoryModelSlidersIconPainter(
                        color: labelColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      modelLabel,
                      maxLines: 1,
                      softWrap: false,
                      style: labelStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoryModelSlidersIconPainter extends CustomPainter {
  const _MemoryModelSlidersIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rail = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final knob = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final left = size.width * 0.12;
    final right = size.width * 0.88;
    final topY = size.height * 0.32;
    final bottomY = size.height * 0.72;
    canvas.drawLine(Offset(left, topY), Offset(right, topY), rail);
    canvas.drawLine(Offset(left, bottomY), Offset(right, bottomY), rail);
    canvas.drawCircle(Offset(size.width * 0.36, topY), 1.7, knob);
    canvas.drawCircle(Offset(size.width * 0.68, bottomY), 1.7, knob);
  }

  @override
  bool shouldRepaint(covariant _MemoryModelSlidersIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
