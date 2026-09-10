part of 'tilemap_library.dart';

class _FogCurveEditor extends StatefulWidget {
  const _FogCurveEditor({
    required this.points,
    required this.foregroundColor,
    required this.secondaryColor,
    required this.onChanged,
  });

  final List<TilemapFogControlPoint> points;
  final Color foregroundColor;
  final Color secondaryColor;
  final ValueChanged<List<TilemapFogControlPoint>> onChanged;

  @override
  State<_FogCurveEditor> createState() => _FogCurveEditorState();
}

class _FogCurveEditorState extends State<_FogCurveEditor> {
  static const _plotPadding = EdgeInsets.fromLTRB(34, 12, 14, 24);

  int? _activePointIndex;

  Rect _plotRect(Size size) {
    return Rect.fromLTRB(
      _plotPadding.left,
      _plotPadding.top,
      size.width - _plotPadding.right,
      size.height - _plotPadding.bottom,
    );
  }

  Offset _offsetForPoint(TilemapFogControlPoint point, Rect plotRect) {
    return Offset(
      plotRect.left + plotRect.width * point.position,
      plotRect.bottom - plotRect.height * point.opacity,
    );
  }

  int? _closestPoint(Offset localPosition, Rect plotRect) {
    if (widget.points.isEmpty) return null;
    var closestIndex = 0;
    var closestDistance = double.infinity;
    for (var index = 0; index < widget.points.length; index += 1) {
      final distance =
          (_offsetForPoint(widget.points[index], plotRect) - localPosition)
              .distanceSquared;
      if (distance >= closestDistance) continue;
      closestIndex = index;
      closestDistance = distance;
    }
    return closestIndex;
  }

  void _startDrag(DragStartDetails details, Size size) {
    final index = _closestPoint(details.localPosition, _plotRect(size));
    setState(() => _activePointIndex = index);
    _updateDrag(details.localPosition, size);
  }

  void _updateDrag(Offset localPosition, Size size) {
    final index = _activePointIndex;
    if (index == null) return;
    final plotRect = _plotRect(size);
    final rawPosition = ((localPosition.dx - plotRect.left) / plotRect.width)
        .clamp(0.0, 1.0);
    final minPosition = index == 0
        ? 0.0
        : widget.points[index - 1].position + 0.01;
    final maxPosition = index == widget.points.length - 1
        ? 1.0
        : widget.points[index + 1].position - 0.01;
    final opacity = (1 - (localPosition.dy - plotRect.top) / plotRect.height)
        .clamp(0.0, 1.0);
    final updatedPoints = widget.points.toList(growable: false);
    updatedPoints[index] = updatedPoints[index].copyWith(
      position: rawPosition.clamp(minPosition, maxPosition).toDouble(),
      opacity: opacity.toDouble(),
    );
    widget.onChanged(updatedPoints);
  }

  void _endDrag() {
    if (_activePointIndex == null) return;
    setState(() => _activePointIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey<String>('tilemap-settings-fog-curve'),
      height: 160,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _FogCurveDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<_FogCurveDragRecognizer>(
                    _FogCurveDragRecognizer.new,
                    (recognizer) {
                      recognizer.onStart = (details) {
                        _startDrag(details, size);
                      };
                      recognizer.onUpdate = (details) {
                        _updateDrag(details.localPosition, size);
                      };
                      recognizer.onEnd = (_) {
                        _endDrag();
                      };
                      recognizer.onCancel = _endDrag;
                    },
                  ),
            },
            child: CustomPaint(
              key: const ValueKey<String>('tilemap-settings-fog-curve-paint'),
              painter: _FogCurvePainter(
                points: widget.points,
                plotRect: _plotRect(size),
                foregroundColor: widget.foregroundColor,
                secondaryColor: widget.secondaryColor,
                activePointIndex: _activePointIndex,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FogCurveDragRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _FogCurvePainter extends CustomPainter {
  const _FogCurvePainter({
    required this.points,
    required this.plotRect,
    required this.foregroundColor,
    required this.secondaryColor,
    required this.activePointIndex,
  });

  final List<TilemapFogControlPoint> points;
  final Rect plotRect;
  final Color foregroundColor;
  final Color secondaryColor;
  final int? activePointIndex;

  Offset _offsetForPoint(TilemapFogControlPoint point) {
    return Offset(
      plotRect.left + plotRect.width * point.position,
      plotRect.bottom - plotRect.height * point.opacity,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = secondaryColor.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var step = 0; step <= 4; step += 1) {
      final fraction = step / 4;
      final x = plotRect.left + plotRect.width * fraction;
      final y = plotRect.top + plotRect.height * fraction;
      canvas
        ..drawLine(
          Offset(x, plotRect.top),
          Offset(x, plotRect.bottom),
          gridPaint,
        )
        ..drawLine(
          Offset(plotRect.left, y),
          Offset(plotRect.right, y),
          gridPaint,
        );
    }

    for (final label in const [
      (value: '100%', fraction: 0.0),
      (value: '0%', fraction: 1.0),
    ]) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: label.value,
          style: TextStyle(
            fontFamily: GenesisTypography.fontFamily,
            fontFamilyFallback: GenesisTypography.fontFamilyFallback,
            color: secondaryColor,
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          plotRect.left - textPainter.width - 5,
          plotRect.top +
              plotRect.height * label.fraction -
              textPainter.height / 2,
        ),
      );
    }

    if (points.isEmpty) return;
    const accentColor = Color(0xFF7C6CF2);
    final offsets = points.map(_offsetForPoint).toList(growable: false);
    final curvePath = Path()
      ..moveTo(plotRect.left, offsets.first.dy)
      ..lineTo(offsets.first.dx, offsets.first.dy);
    for (final offset in offsets.skip(1)) {
      curvePath.lineTo(offset.dx, offset.dy);
    }
    curvePath.lineTo(plotRect.right, offsets.last.dy);

    final fillPath = Path.from(curvePath)
      ..lineTo(plotRect.right, plotRect.bottom)
      ..lineTo(plotRect.left, plotRect.bottom)
      ..close();
    canvas
      ..drawPath(fillPath, Paint()..color = accentColor.withValues(alpha: 0.12))
      ..drawPath(
        curvePath,
        Paint()
          ..color = accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );

    for (var index = 0; index < offsets.length; index += 1) {
      final offset = offsets[index];
      final isActive = activePointIndex == index;
      canvas
        ..drawCircle(
          offset,
          isActive ? 8 : 6,
          Paint()..color = accentColor.withValues(alpha: 0.22),
        )
        ..drawCircle(offset, isActive ? 5 : 4, Paint()..color = accentColor);
      final positionLabel = TextPainter(
        text: TextSpan(
          text: '${(points[index].position * 100).round()}%',
          style: TextStyle(
            fontFamily: GenesisTypography.fontFamily,
            fontFamilyFallback: GenesisTypography.fontFamilyFallback,
            color: foregroundColor,
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelLeft = (offset.dx - positionLabel.width / 2).clamp(
        0.0,
        size.width - positionLabel.width,
      );
      positionLabel.paint(
        canvas,
        Offset(labelLeft.toDouble(), plotRect.bottom + 5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FogCurvePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.plotRect != plotRect ||
        oldDelegate.foregroundColor != foregroundColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.activePointIndex != activePointIndex;
  }
}

class _FogOpacityEditor extends StatelessWidget {
  const _FogOpacityEditor({
    required this.index,
    required this.points,
    required this.foregroundColor,
    required this.secondaryColor,
    required this.onChanged,
  });

  final int index;
  final List<TilemapFogControlPoint> points;
  final Color foregroundColor;
  final Color secondaryColor;
  final ValueChanged<List<TilemapFogControlPoint>> onChanged;

  @override
  Widget build(BuildContext context) {
    final point = points[index];

    void updatePoint(TilemapFogControlPoint updatedPoint) {
      final updatedPoints = points.toList(growable: false);
      updatedPoints[index] = updatedPoint;
      onChanged(updatedPoints);
    }

    return _TilemapSettingsSlider(
      label: 'P${index + 1} · ${(point.position * 100).round()}%',
      value: point.opacity,
      min: 0,
      max: 1,
      valueLabel: '${(point.opacity * 100).round()}%',
      sliderKey: ValueKey<String>('tilemap-settings-fog-opacity-$index'),
      foregroundColor: foregroundColor,
      secondaryColor: secondaryColor,
      onChanged: (value) => updatePoint(point.copyWith(opacity: value)),
    );
  }
}
