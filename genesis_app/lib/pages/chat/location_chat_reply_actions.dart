import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../components/chat/shared/chat_ui.dart';

/// Visual placeholders only. Reply actions deliberately have no callbacks.
class LocationChatReplyActions extends StatelessWidget {
  const LocationChatReplyActions({super.key, required this.style});

  final ChatUiStyleConfig style;

  static const double buttonSize = 32;
  static const double iconSize = 17;
  static const double centerSpacing = 50;
  // Account for the icon's inset inside its button when spacing the row.
  static const double contentBottomGap = 16 - (buttonSize - iconSize) / 2;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '<     1 / 2     >',
            key: ValueKey('location-chat-reply-page-indicator'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFF4F3F6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(
              left: style.avatarSize + style.avatarBubbleGap,
            ),
            child: Row(
              key: const ValueKey('location-chat-reply-actions-four-icons'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _ReplyActionIcon(
                  key: const ValueKey(_ReplyActionIconType.regenerate),
                  label: 'Regenerate',
                  icon: _ReplyActionIconType.regenerate,
                  style: style,
                ),
                const SizedBox(width: centerSpacing - buttonSize),
                _ReplyActionIcon(
                  key: const ValueKey(_ReplyActionIconType.goOn),
                  label: 'Go on',
                  icon: _ReplyActionIconType.goOn,
                  style: style,
                ),
                const SizedBox(width: centerSpacing - buttonSize),
                _ReplyActionIcon(
                  key: const ValueKey(_ReplyActionIconType.edit),
                  label: 'Edit',
                  icon: _ReplyActionIconType.edit,
                  style: style,
                ),
                const SizedBox(width: centerSpacing - buttonSize),
                _ReplyActionIcon(
                  key: const ValueKey(_ReplyActionIconType.inspiration),
                  label: 'Inspiration',
                  icon: _ReplyActionIconType.inspiration,
                  style: style,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _ReplyActionIconType { regenerate, goOn, edit, inspiration }

class _ReplyActionIcon extends StatelessWidget {
  const _ReplyActionIcon({
    super.key,
    required this.label,
    required this.icon,
    required this.style,
  });

  final String label;
  final _ReplyActionIconType icon;
  final ChatUiStyleConfig style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      enabled: false,
      child: SizedBox.square(
        dimension: LocationChatReplyActions.buttonSize,
        child: Center(
          child: CustomPaint(
            size: const Size.square(LocationChatReplyActions.iconSize),
            painter: _ReplyActionIconPainter(
              icon: icon,
              color: const Color(0xFFF4F3F6),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyActionIconPainter extends CustomPainter {
  const _ReplyActionIconPainter({required this.icon, required this.color});

  final _ReplyActionIconType icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      // Match the send arrow's 1.51 stroke on its 16-unit canvas.
      ..strokeWidth = 3.02
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (icon == _ReplyActionIconType.regenerate) {
      canvas.drawArc(
        const Rect.fromLTWH(3, 3, 26, 26),
        -math.pi / 2 - 0.2,
        -math.pi * 1.73,
        false,
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(23, 10)
          ..lineTo(23.4, 4.5)
          ..lineTo(29, 5),
        paint,
      );
    } else if (icon == _ReplyActionIconType.goOn) {
      canvas.drawPath(
        Path()
          ..moveTo(28.5, 14)
          ..cubicTo(28.5, 7.2, 22.9, 2, 16, 2)
          ..cubicTo(8.8, 2, 3, 7.2, 3, 14)
          ..cubicTo(3, 18.3, 5.5, 22, 9.3, 24.1)
          ..lineTo(9.3, 29)
          ..lineTo(15, 29),
        paint,
      );
      canvas.drawLine(const Offset(24, 20), const Offset(24, 30), paint);
      canvas.drawLine(const Offset(19, 25), const Offset(29, 25), paint);
    } else if (icon == _ReplyActionIconType.edit) {
      // Open rounded square and diagonal pen, matching the Edit reference.
      canvas.drawPath(
        Path()
          ..moveTo(16, 4)
          ..lineTo(8, 4)
          ..quadraticBezierTo(3, 4, 3, 9)
          ..lineTo(3, 24)
          ..quadraticBezierTo(3, 29, 8, 29)
          ..lineTo(23, 29)
          ..quadraticBezierTo(28, 29, 28, 24)
          ..lineTo(28, 16),
        paint,
      );
      canvas.drawLine(const Offset(16, 16), const Offset(27, 5), paint);
    } else {
      final bulb = Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(16, 1)
        ..cubicTo(9.7, 1, 5, 5.8, 5, 12)
        ..cubicTo(5, 16.2, 7.4, 19.2, 10.4, 21.8)
        ..lineTo(11.5, 26)
        ..lineTo(20.5, 26)
        ..lineTo(21.6, 21.8)
        ..cubicTo(24.6, 19.2, 27, 16.2, 27, 12)
        ..cubicTo(27, 5.8, 22.3, 1, 16, 1)
        ..close()
        ..moveTo(16, 6)
        ..lineTo(12, 14)
        ..lineTo(16, 14)
        ..lineTo(14, 22)
        ..lineTo(21, 11)
        ..lineTo(17, 11)
        ..lineTo(20, 6)
        ..close();
      final fill = Paint()..color = color;
      canvas.drawPath(bulb, fill);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(12, 28, 8, 3),
          const Radius.circular(1.5),
        ),
        fill,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ReplyActionIconPainter oldDelegate) =>
      icon != oldDelegate.icon || color != oldDelegate.color;
}
