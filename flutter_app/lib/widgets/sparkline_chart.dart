// ── lib/widgets/sparkline_chart.dart ────────────────────────────────
import 'dart:math' show min, max;
import 'package:flutter/material.dart';
import '../main.dart';

/// A compact bezier line chart with filled gradient area.
/// Draws the last N data points as a smooth glowing curve.
class SparklineChart extends StatelessWidget {
  const SparklineChart({
    super.key,
    required this.data,
    required this.color,
    this.height = 56,
    this.showCurrentDot = true,
    this.fillGradient = true,
    this.strokeWidth = 1.8,
    this.warningLine,
    this.dangerLine,
  });

  final List<double> data;
  final Color color;
  final double height;
  final bool showCurrentDot;
  final bool fillGradient;
  final double strokeWidth;
  final double? warningLine;
  final double? dangerLine;

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('Collecting data…',
              style: RivianText.caption.copyWith(color: RivianColors.textTertiary)),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          data: data,
          color: color,
          showDot: showCurrentDot,
          fillGradient: fillGradient,
          strokeWidth: strokeWidth,
          warningLine: warningLine,
          dangerLine: dangerLine,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.data,
    required this.color,
    required this.showDot,
    required this.fillGradient,
    required this.strokeWidth,
    this.warningLine,
    this.dangerLine,
  });

  final List<double> data;
  final Color color;
  final bool showDot;
  final bool fillGradient;
  final double strokeWidth;
  final double? warningLine;
  final double? dangerLine;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    // Compute range, extend a bit for padding
    final minVal = data.reduce(min);
    final maxVal = data.reduce(max);
    final range = (maxVal - minVal).abs();
    final eff = range < 0.01 ? 1.0 : range * 1.15;
    final baseMin = minVal - eff * 0.05;

    Offset toOffset(int i, double v) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((v - baseMin) / eff) * size.height;
      return Offset(x, y.clamp(0.0, size.height));
    }

    // Build smooth bezier path
    final path = Path();
    path.moveTo(0, toOffset(0, data[0]).dy);
    for (int i = 1; i < data.length; i++) {
      final prev = toOffset(i - 1, data[i - 1]);
      final curr = toOffset(i, data[i]);
      final cp1 = Offset((prev.dx + curr.dx) / 2, prev.dy);
      final cp2 = Offset((prev.dx + curr.dx) / 2, curr.dy);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, curr.dx, curr.dy);
    }

    // Filled gradient area
    if (fillGradient) {
      final fill = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    // Glow
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.22)
        ..strokeWidth = strokeWidth + 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Main line
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Threshold lines
    void drawThreshold(double val, Color c) {
      final y = size.height - ((val - baseMin) / eff) * size.height;
      if (y < 0 || y > size.height) return;
      canvas.drawLine(
        Offset(0, y), Offset(size.width, y),
        Paint()
          ..color = c.withValues(alpha: 0.5)
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke,
      );
    }
    if (warningLine != null) drawThreshold(warningLine!, RivianColors.warning);
    if (dangerLine != null)  drawThreshold(dangerLine!,  RivianColors.danger);

    // Current value dot
    if (showDot && data.isNotEmpty) {
      final dot = toOffset(data.length - 1, data.last);
      canvas.drawCircle(dot, 3.5, Paint()..color = color);
      canvas.drawCircle(
        dot, 7,
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.data != data || old.color != color;
}
