// ── lib/widgets/range_gauge_card.dart ───────────────────────────────
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../main.dart';

class RangeGaugeCard extends StatelessWidget {
  const RangeGaugeCard({
    super.key,
    required this.miles,
    this.maxMiles = 314.0,
  });

  final double miles;
  final double maxMiles;

  @override
  Widget build(BuildContext context) {
    final pct = (miles / maxMiles).clamp(0.0, 1.0);
    final color = pct < 0.15
        ? RivianColors.danger
        : pct < 0.35
            ? RivianColors.warning
            : RivianColors.green;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.07),
            RivianColors.bg1,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
        boxShadow: RivianShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Section label
        Row(children: [
          Icon(Icons.route_rounded, size: 12, color: RivianColors.textTertiary),
          const SizedBox(width: 6),
          Text('EST. RANGE',
              style: RivianText.label.copyWith(
                  color: RivianColors.textTertiary,
                  fontSize: 9,
                  letterSpacing: 1.4)),
        ]),
        const SizedBox(height: 12),

        // Gauge
        Center(
          child: SizedBox(
            width: 150,
            height: 82,
            child: CustomPaint(
              painter: _GaugePainter(progress: pct, color: color),
              child: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          miles > 0 ? '${miles.toStringAsFixed(0)}' : '—',
                          style: RivianText.displayMd.copyWith(
                              color: color,
                              fontSize: 32,
                              letterSpacing: -1.4,
                              height: 1.0),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4, left: 3),
                          child: Text('mi',
                              style: RivianText.caption
                                  .copyWith(color: color.withValues(alpha: 0.7),
                                  fontSize: 10)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Linear percentage bar
        Stack(children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
                color: RivianColors.bg3,
                borderRadius: BorderRadius.circular(3)),
          ),
          FractionallySizedBox(
            widthFactor: pct,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.5), color]),
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 6)
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 6),

        // Labels
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('E',
              style: RivianText.caption.copyWith(
                  color: RivianColors.textTertiary, fontSize: 8)),
          Text(
            '${(pct * 100).toStringAsFixed(0)}% · EPA ${maxMiles.toStringAsFixed(0)} mi',
            style: RivianText.caption
                .copyWith(color: RivianColors.textTertiary, fontSize: 8),
          ),
          Text('F',
              style: RivianText.caption
                  .copyWith(color: RivianColors.textTertiary, fontSize: 8)),
        ]),
      ]),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 4);
    final radius = size.width / 2 - 5;
    const startAngle = math.pi;
    const totalSweep = math.pi;

    // Track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, totalSweep, false,
      Paint()
        ..color = RivianColors.bg3
        ..strokeWidth = 11
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (progress <= 0) return;

    // Gradient fill
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect, startAngle, totalSweep * progress, false,
      Paint()
        ..shader = SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + totalSweep,
          colors: const [
            Color(0xFFFF453A),
            Color(0xFFFFB340),
            Color(0xFF6BE09B),
          ],
          stops: const [0.0, 0.35, 1.0],
        ).createShader(rect)
        ..strokeWidth = 11
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Glowing dot at needle tip
    final angle = startAngle + totalSweep * progress;
    final dotX = center.dx + radius * math.cos(angle);
    final dotY = center.dy + radius * math.sin(angle);
    canvas.drawCircle(
      Offset(dotX, dotY), 12,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(Offset(dotX, dotY), 5, Paint()..color = color);
    canvas.drawCircle(
        Offset(dotX, dotY), 3, Paint()..color = Colors.white.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress || old.color != color;
}
