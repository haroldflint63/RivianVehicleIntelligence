// ── lib/widgets/health_score_card.dart ──────────────────────────────
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../main.dart';

class HealthScoreCard extends StatefulWidget {
  const HealthScoreCard({
    super.key,
    required this.score,
    required this.status,
    required this.action,
    this.anomalyRatePerHour = 0.0,
  });

  final double score;
  final String status;
  final String action;
  final double anomalyRatePerHour;

  @override
  State<HealthScoreCard> createState() => _HealthScoreCardState();
}

class _HealthScoreCardState extends State<HealthScoreCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _prev = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _prev = 0;
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(HealthScoreCard old) {
    super.didUpdateWidget(old);
    if (old.score != widget.score) {
      _prev = old.score;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final score = _prev + (widget.score - _prev) * _anim.value;
        final color = score >= 90
            ? RivianColors.green
            : score >= 75
                ? RivianColors.warning
                : RivianColors.danger;

        return Container(
          padding: const EdgeInsets.all(20),
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
              Icon(Icons.monitor_heart_rounded,
                  size: 12, color: RivianColors.textTertiary),
              const SizedBox(width: 6),
              Text('HEALTH SCORE',
                  style: RivianText.label.copyWith(
                      color: RivianColors.textTertiary,
                      letterSpacing: 1.4,
                      fontSize: 9)),
            ]),
            const SizedBox(height: 16),

            // Arc + details row
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // 270° arc ring
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(fit: StackFit.expand, children: [
                  CustomPaint(
                    painter: _ArcPainter(
                      progress: (score / 100).clamp(0.0, 1.0),
                      color: color,
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(score.toStringAsFixed(0),
                            style: RivianText.displayMd.copyWith(
                                color: color,
                                fontSize: 26,
                                letterSpacing: -1.5,
                                height: 1.0)),
                        const SizedBox(height: 1),
                        Text('/100',
                            style: RivianText.caption.copyWith(
                                color: RivianColors.textTertiary,
                                fontSize: 8)),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 16),

              // Status + action
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: color.withValues(alpha: 0.25), width: 1),
                        ),
                        child: Text(widget.status,
                            style: RivianText.caption.copyWith(
                                color: color, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 9),
                      Text(widget.action,
                          style: RivianText.caption.copyWith(
                              color: RivianColors.textSecondary,
                              height: 1.5,
                              fontSize: 10)),
                      if (widget.anomalyRatePerHour > 0) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: RivianColors.warningDim,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 10, color: RivianColors.warning),
                            const SizedBox(width: 5),
                            Text(
                                '${widget.anomalyRatePerHour.toStringAsFixed(1)}/hr',
                                style: RivianText.caption.copyWith(
                                    color: RivianColors.warning,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ],
                    ]),
              ),
            ]),
          ]),
        );
      },
    );
  }
}

// ── Custom 270° arc painter ──────────────────────────────────────────
class _ArcPainter extends CustomPainter {
  const _ArcPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  // Arc spans 270° starting at bottom-left (135°) going clockwise
  static const _start = math.pi * 0.75;   // 135°
  static const _sweep = math.pi * 1.5;    // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 9;

    // Background track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _start, _sweep, false,
      Paint()
        ..color = RivianColors.bg3
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (progress <= 0) return;

    // Coloured progress arc with gradient
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect, _start, _sweep * progress, false,
      Paint()
        ..shader = SweepGradient(
          startAngle: _start,
          endAngle: _start + _sweep,
          colors: [color.withValues(alpha: 0.25), color],
          stops: const [0.0, 1.0],
        ).createShader(rect)
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Glowing end-cap dot
    final endAngle = _start + _sweep * progress;
    final dx = center.dx + radius * math.cos(endAngle);
    final dy = center.dy + radius * math.sin(endAngle);
    // Outer glow
    canvas.drawCircle(
      Offset(dx, dy), 11,
      Paint()
        ..color = color.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    // Core dot
    canvas.drawCircle(Offset(dx, dy), 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress || old.color != color;
}
