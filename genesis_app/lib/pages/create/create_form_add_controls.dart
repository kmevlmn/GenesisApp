part of 'create_form_library.dart';

class CreateAddButton extends StatelessWidget {
  const CreateAddButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 58,
  });

  final String label;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: CustomPaint(
          painter: CreateDashedRRectPainter(
            color: createFormDash,
            radius: 8,
            strokeWidth: 1.2,
          ),
          child: SizedBox(
            width: double.infinity,
            height: height,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: GenesisColors.createAdd,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CreateInlineAddButton extends StatelessWidget {
  const CreateInlineAddButton({
    super.key,
    required this.label,
    required this.onTap,
    this.supportingText,
    this.fontSize = 14,
    this.centered = false,
    this.verticalPadding = 8,
    this.contentPadding,
  });

  final String label;
  final VoidCallback onTap;
  final String? supportingText;
  final double fontSize;
  final bool centered;
  final double verticalPadding;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final supporting = supportingText?.trim() ?? '';
    final labelText = Text.rich(
      TextSpan(
        text: label,
        children: [
          if (supporting.isNotEmpty)
            TextSpan(
              text: ' $supporting',
              style: const TextStyle(
                color: Color(0xFFA8A8AD),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
      style: TextStyle(
        color: CreateFormTheme.colorOf(
          context,
          GenesisColors.createAdd,
          GenesisColors.redSecondary,
        ),
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding:
            contentPadding ?? EdgeInsets.symmetric(vertical: verticalPadding),
        child: centered
            ? Align(alignment: Alignment.center, child: labelText)
            : labelText,
      ),
    );
  }
}

class CreateDashedRRectPainter extends CustomPainter {
  CreateDashedRRectPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 1,
  });

  final Color color;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    const double dashWidth = 8;
    const double dashSpace = 7;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CreateDashedRRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
