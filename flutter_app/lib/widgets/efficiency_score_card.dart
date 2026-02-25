// ── lib/widgets/efficiency_score_card.dart ──────────────────────────
//
// Real-time driving efficiency coach — computes Eco Score (A+–F) and
// kWh/mi from live telemetry history. Benchmarks against R1T EPA rating.
// Surfaces actionable tips based on current driving conditions.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/telemetry_model.dart';
import '../services/websocket_service.dart';

class EfficiencyScoreCard extends StatelessWidget {
  const EfficiencyScoreCard({super.key});

  // ── Eco score 0–100 ────────────────────────────────────────────────
  // Weighted from: speed profile, regen harvest, HVAC load, motor temp
  static double _ecoScore(TelemetryData t, List<TelemetryData> hist) {
    double s = 65.0;

    // Speed — optimal band is 30–65 mph
    if (t.vehicleSpeed >= 30 && t.vehicleSpeed <= 65) {
      s += 18;
    } else if (t.vehicleSpeed < 30 && t.vehicleSpeed > 3) {
      s += 8; // city driving — ok
    } else if (t.vehicleSpeed <= 75) {
      s += 6;
    } else {
      s -= 12; // highway blast
    }

    // Regen harvest — higher is better
    final avgRegen = hist.isEmpty
        ? t.regenPower
        : hist.map((h) => h.regenPower).reduce((a, b) => a + b) /
            hist.length;
    s += (avgRegen / 8.0 * 20.0).clamp(0.0, 20.0);

    // HVAC penalty — delta between cabin and outside temps
    final hvacDelta = (t.cabinTemp - t.outsideTemp).abs();
    if (hvacDelta > 45) s -= 18;
    else if (hvacDelta > 30) s -= 10;
    else if (hvacDelta > 18) s -= 4;

    // Motor temp — cooler = more efficient
    if (t.motorTemp < 130) s += 5;
    else if (t.motorTemp > 230) s -= 12;
    else if (t.motorTemp > 190) s -= 5;

    return s.clamp(0.0, 100.0);
  }

  // ── kWh/mi from live drain vs distance ────────────────────────────
  // R1T Large Pack = 135 kWh  ·  readings every 5 s
  static double? _kwhPerMile(List<TelemetryData> hist) {
    final moving = hist.where((t) => t.vehicleSpeed > 5).toList();
    if (moving.length < 8) return null;

    final pctDrain = moving.first.batteryPercent - moving.last.batteryPercent;
    if (pctDrain <= 0.01) return null; // charging or idle

    final kwhUsed = pctDrain / 100.0 * 135.0;
    final avgSpeedMph =
        moving.map((t) => t.vehicleSpeed).reduce((a, b) => a + b) /
            moving.length;
    final hours = moving.length * 5.0 / 3600.0;
    final miles = avgSpeedMph * hours;
    if (miles < 0.02) return null;

    return kwhUsed / miles;
  }

  // ── Letter grade ───────────────────────────────────────────────────
  static String _grade(double s) {
    if (s >= 95) return 'A+';
    if (s >= 88) return 'A';
    if (s >= 80) return 'A−';
    if (s >= 72) return 'B+';
    if (s >= 64) return 'B';
    if (s >= 56) return 'B−';
    if (s >= 48) return 'C+';
    if (s >= 40) return 'C';
    if (s >= 32) return 'D';
    return 'F';
  }

  static Color _gradeColor(double s) {
    if (s >= 72) return RivianColors.green;
    if (s >= 48) return RivianColors.warning;
    return RivianColors.danger;
  }

  // ── Context-aware driving tips ─────────────────────────────────────
  static List<String> _tips(TelemetryData t, List<TelemetryData> hist) {
    final tips = <String>[];
    if (t.vehicleSpeed > 75) {
      tips.add('Speed above 75 mph — slowing to 65 recovers ~15% range');
    }
    if (t.outsideTemp < 32) {
      tips.add('Sub-freezing temp detected — pre-condition while plugged in');
    }
    if (t.regenPower < 1.5 && t.vehicleSpeed > 20) {
      tips.add('Enable One-Pedal Driving to maximise regenerative braking');
    }
    final hvacDelta = (t.cabinTemp - t.outsideTemp).abs();
    if (hvacDelta > 30) {
      tips.add('Heavy HVAC load — seat heating uses ~60% less energy');
    }
    if (t.motorTemp > 200) {
      tips.add('Motor running hot — reduce load to improve efficiency');
    }
    if (tips.isEmpty) {
      tips.add('Excellent driving conditions — maintain current profile');
    }
    return tips.take(2).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(builder: (_, svc, __) {
      final t = svc.latestPayload?.telemetry;
      final hist = svc.telemetryHistory;

      if (t == null) return const _PlaceholderStrip();

      final score = _ecoScore(t, hist);
      final grade = _grade(score);
      final color = _gradeColor(score);
      final kwhPerMi = _kwhPerMile(hist);
      final epaRating = 0.370; // R1T Large Pack EPA: ~3.1 mi/kWh = 0.37 kWh/mi
      final tips = _tips(t, hist);

      // Regen capture %: regen power / estimated total power
      final estDriveKw = (t.batteryVoltage * t.motorRpm / 1000.0 / 60.0)
          .clamp(0.1, 250.0);
      final regenPct =
          ((t.regenPower / (estDriveKw + t.regenPower)) * 100).clamp(0.0, 40.0);

      return Container(
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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Header
            Row(children: [
              Icon(Icons.eco_rounded,
                  size: 12, color: RivianColors.textTertiary),
              const SizedBox(width: 6),
              Text('DRIVING EFFICIENCY',
                  style: RivianText.label.copyWith(
                      color: RivianColors.textTertiary,
                      letterSpacing: 1.4,
                      fontSize: 9)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: color.withValues(alpha: 0.2), width: 1),
                ),
                child: Text('LIVE SCORE',
                    style: RivianText.caption.copyWith(
                        color: color, fontWeight: FontWeight.w700)),
              ),
            ]),

            const SizedBox(height: 16),

            // Main metrics row
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // ── Grade letter ────────────────────────────────────
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      color.withValues(alpha: 0.15),
                      color.withValues(alpha: 0.0),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: color.withValues(alpha: 0.25), width: 1),
                ),
                child: Center(
                  child: Text(grade,
                      style: TextStyle(
                          color: color,
                          fontSize: grade.length > 1 ? 34 : 40,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2.0,
                          height: 1.0)),
                ),
              ),
              const SizedBox(width: 16),

              // ── Metrics column ──────────────────────────────────
              Expanded(
                child: Column(children: [
                  // kWh/mi row
                  _MetricRow(
                    label: 'EFFICIENCY',
                    value: kwhPerMi != null
                        ? '${kwhPerMi.toStringAsFixed(2)} kWh/mi'
                        : '— kWh/mi',
                    sub: 'R1T EPA: ${epaRating.toStringAsFixed(2)} kWh/mi',
                    color: color,
                    showBar: kwhPerMi != null,
                    barFraction: kwhPerMi != null
                        ? (epaRating / kwhPerMi).clamp(0.0, 1.0)
                        : 0,
                    barColor: kwhPerMi != null && kwhPerMi <= epaRating
                        ? RivianColors.green
                        : RivianColors.warning,
                    barLabel: kwhPerMi != null
                        ? kwhPerMi <= epaRating
                            ? '↑ ${((epaRating - kwhPerMi) / epaRating * 100).toStringAsFixed(0)}% better than EPA'
                            : '↓ ${((kwhPerMi - epaRating) / epaRating * 100).toStringAsFixed(0)}% above EPA'
                        : 'Gathering data…',
                  ),
                  const SizedBox(height: 10),

                  // Regen row
                  _MetricRow(
                    label: 'REGEN CAPTURE',
                    value: '${regenPct.toStringAsFixed(1)}%',
                    sub: '${t.regenPower.toStringAsFixed(1)} kW recovered',
                    color: RivianColors.ice,
                    showBar: true,
                    barFraction: (regenPct / 35.0).clamp(0.0, 1.0),
                    barColor: RivianColors.ice,
                    barLabel: regenPct > 15
                        ? 'Strong regen — great one-pedal use'
                        : 'Increase regen with One-Pedal mode',
                  ),
                ]),
              ),
            ]),

            // ── Tips ──────────────────────────────────────────────
            if (tips.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: RivianColors.bg2,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: RivianColors.border, width: 1),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI COACHING',
                          style: RivianText.caption.copyWith(
                              color: RivianColors.textTertiary,
                              letterSpacing: 1.2,
                              fontSize: 8)),
                      const SizedBox(height: 6),
                      ...tips.map((tip) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.arrow_right_rounded,
                                      size: 13, color: color),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(tip,
                                        style: RivianText.caption.copyWith(
                                            color:
                                                RivianColors.textSecondary,
                                            height: 1.4,
                                            fontSize: 10)),
                                  ),
                                ]),
                          )),
                    ]),
              ),
            ],
          ]),
        ),
      );
    });
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.showBar,
    required this.barFraction,
    required this.barColor,
    required this.barLabel,
  });
  final String label, value, sub, barLabel;
  final Color color, barColor;
  final bool showBar;
  final double barFraction;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label,
            style: RivianText.caption.copyWith(
                color: RivianColors.textTertiary,
                fontSize: 8,
                letterSpacing: 1.0)),
        const Spacer(),
        Text(value,
            style: RivianText.headingMd.copyWith(
                color: color, fontSize: 13, letterSpacing: -0.3)),
      ]),
      if (showBar) ...[
        const SizedBox(height: 5),
        Stack(children: [
          Container(
              height: 4,
              decoration: BoxDecoration(
                  color: RivianColors.bg3,
                  borderRadius: BorderRadius.circular(2))),
          FractionallySizedBox(
            widthFactor: barFraction.clamp(0.0, 1.0),
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [barColor.withValues(alpha: 0.5), barColor]),
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                      color: barColor.withValues(alpha: 0.35),
                      blurRadius: 4)
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 3),
        Text(barLabel,
            style: RivianText.caption.copyWith(
                color: barColor.withValues(alpha: 0.8), fontSize: 8)),
      ] else ...[
        const SizedBox(height: 2),
        Text(sub,
            style: RivianText.caption.copyWith(
                color: RivianColors.textTertiary, fontSize: 9)),
      ],
    ]);
  }
}

// ── Placeholder while no telemetry ────────────────────────────────────
class _PlaceholderStrip extends StatelessWidget {
  const _PlaceholderStrip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: RivianColors.bg1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: RivianColors.border, width: 1),
        ),
        child: Row(children: [
          const Icon(Icons.eco_rounded,
              size: 20, color: RivianColors.textTertiary),
          const SizedBox(width: 14),
          Text('Awaiting telemetry — start the backend to compute efficiency',
              style: RivianText.bodySm),
        ]),
      );
}
