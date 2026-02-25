// ── lib/widgets/battery_intelligence_card.dart ──────────────────────
//
// Rivian BMS-proxy dashboard — State of Health, degradation tracking,
// warranty cliff visualisation, and adaptive charge coaching.
// Data derived from AI health score + pack voltage (closest available
// proxy for BMS cell capacity without direct BMS socket access).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/websocket_service.dart';

class BatteryIntelligenceCard extends StatelessWidget {
  const BatteryIntelligenceCard({super.key});

  // ── SoH proxy ──────────────────────────────────────────────────────
  // Real BMS measures cell capacity vs factory baseline.
  // We derive from: AI health score (composite agent signal) +
  // pack voltage deviation from nominal (403 V at 100% for NMC 811).
  static double _computeSoH(double healthScore, double packVoltage) {
    const nominalV = 403.0;
    final voltFactor = (packVoltage / nominalV).clamp(0.92, 1.04);
    return ((96.5 - (100.0 - healthScore) * 0.28) * voltFactor)
        .clamp(70.0, 99.9);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(builder: (_, svc, __) {
      final t = svc.latestPayload?.telemetry;
      final soc = t?.batteryPercent ?? 80.0;
      final voltage = t?.batteryVoltage ?? 403.0;

      final soH = _computeSoH(svc.healthScore, voltage);

      // Degradation modelling
      const degPerMonth = 0.014; // %/mo — typical NMC cell chemistry
      final monthsToWarranty = (soH - 70.0) / degPerMonth;
      final yearsRemaining = (monthsToWarranty / 12.0).clamp(0.0, 20.0);

      // Charge cycle estimate: each 0.003% SoH lost ≈ 1 cycle
      final cycles = ((100.0 - soH) / 0.003).round().clamp(0, 2000);

      // Capacity used vs total
      final kwhRemaining = soc / 100.0 * 135.0;

      final soHColor = soH >= 90
          ? RivianColors.green
          : soH >= 80
              ? RivianColors.warning
              : RivianColors.danger;

      // Charge coaching
      final (coachMsg, coachIcon, coachColor) = soc > 85
          ? ('Above 85% daily limit. Charge to 80% for long-term cell health.',
              Icons.warning_amber_rounded,
              RivianColors.warning)
          : soc < 20
              ? ('Below 20%. Charge soon. Pre-condition before DC fast charging.',
                  Icons.bolt_rounded,
                  RivianColors.danger)
              : ('Optimal charge window. Target 80% for daily use.',
                  Icons.check_circle_rounded,
                  RivianColors.green);

      return Container(
        decoration: BoxDecoration(
          color: RivianColors.bg1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: soHColor.withValues(alpha: 0.2), width: 1),
          boxShadow: RivianShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          // Top accent stripe
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                soHColor,
                soHColor.withValues(alpha: 0.0),
              ]),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Header ──────────────────────────────────────────
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        soHColor.withValues(alpha: 0.18),
                        soHColor.withValues(alpha: 0.04),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                        color: soHColor.withValues(alpha: 0.2), width: 1),
                  ),
                  child: Icon(Icons.battery_full_rounded,
                      color: soHColor, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BATTERY INTELLIGENCE',
                            style: RivianText.label.copyWith(
                                color: soHColor,
                                letterSpacing: 1.4,
                                fontSize: 9)),
                        const SizedBox(height: 2),
                        Text('R1T · 135 kWh Large Pack · NMC 811 cells',
                            style: RivianText.caption
                                .copyWith(color: RivianColors.textTertiary)),
                      ]),
                ),
                // kWh remaining pill
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: RivianColors.bg2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: RivianColors.border, width: 1),
                  ),
                  child: Column(children: [
                    Text(kwhRemaining.toStringAsFixed(1),
                        style: RivianText.headingMd.copyWith(
                            color: soHColor,
                            fontSize: 14,
                            letterSpacing: -0.5)),
                    Text('kWh left',
                        style: RivianText.caption.copyWith(fontSize: 7)),
                  ]),
                ),
              ]),

              const SizedBox(height: 20),

              // ── SoH big number row ───────────────────────────────
              Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('STATE OF HEALTH',
                      style: RivianText.caption.copyWith(
                          color: RivianColors.textTertiary,
                          letterSpacing: 1.2,
                          fontSize: 8)),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(soH.toStringAsFixed(1),
                          style: RivianText.displayMd.copyWith(
                              color: soHColor,
                              fontSize: 38,
                              letterSpacing: -2.0,
                              height: 1.0)),
                      Text('%',
                          style: RivianText.headingMd.copyWith(
                              color: soHColor.withValues(alpha: 0.6),
                              fontSize: 16)),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: soHColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: soHColor.withValues(alpha: 0.2),
                              width: 1),
                        ),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.trending_down_rounded,
                                  size: 10, color: soHColor),
                              const SizedBox(width: 3),
                              Text(
                                  '-${degPerMonth.toStringAsFixed(3)}%/mo',
                                  style: RivianText.caption.copyWith(
                                      color: soHColor,
                                      fontWeight: FontWeight.w700)),
                            ]),
                      ),
                    ],
                  ),
                ]),
                const Spacer(),
                // Cycles + warranty years
                Row(children: [
                  _StatColumn(
                      label: 'CYCLES',
                      value: '$cycles',
                      sub: '/ ~2,000',
                      color: RivianColors.info),
                  const SizedBox(width: 16),
                  _StatColumn(
                      label: 'WARRANTY',
                      value: '${yearsRemaining.toStringAsFixed(1)}yr',
                      sub: 'remaining',
                      color: soHColor),
                ]),
              ]),

              const SizedBox(height: 16),

              // ── Capacity retention bar ───────────────────────────
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('CAPACITY RETENTION',
                          style: RivianText.caption.copyWith(
                              color: RivianColors.textTertiary,
                              letterSpacing: 1.2,
                              fontSize: 8)),
                      Text('8yr / 175,000 mi warranty ≥70%',
                          style: RivianText.caption.copyWith(
                              color: RivianColors.textTertiary,
                              fontSize: 8)),
                    ]),
                const SizedBox(height: 8),
                LayoutBuilder(builder: (_, c) {
                  final fillFrac = soH / 100.0;
                  final threshFrac = 0.70;
                  return SizedBox(
                    height: 12,
                    child: Stack(children: [
                      // Track
                      Container(
                          decoration: BoxDecoration(
                              color: RivianColors.bg3,
                              borderRadius: BorderRadius.circular(6))),
                      // Fill
                      FractionallySizedBox(
                        widthFactor: fillFrac,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              soHColor.withValues(alpha: 0.5),
                              soHColor
                            ]),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                  color: soHColor.withValues(alpha: 0.3),
                                  blurRadius: 6)
                            ],
                          ),
                        ),
                      ),
                      // Warranty threshold marker
                      Align(
                        alignment:
                            Alignment(threshFrac * 2 - 1, 0),
                        child: Container(
                            width: 2,
                            height: 12,
                            decoration: BoxDecoration(
                              color: RivianColors.warning,
                              boxShadow: [
                                BoxShadow(
                                    color: RivianColors.warning
                                        .withValues(alpha: 0.5),
                                    blurRadius: 4)
                              ],
                            )),
                      ),
                    ]),
                  );
                }),
                const SizedBox(height: 6),
                Row(children: [
                  Container(
                      width: 14,
                      height: 2,
                      color: RivianColors.warning),
                  const SizedBox(width: 4),
                  Text('70% warranty floor',
                      style: RivianText.caption
                          .copyWith(color: RivianColors.warning, fontSize: 8)),
                  const Spacer(),
                  Text(
                      '${((soH - 70) / degPerMonth / 12).toStringAsFixed(1)} yrs to threshold',
                      style: RivianText.caption.copyWith(
                          color: RivianColors.textTertiary, fontSize: 8)),
                ]),
              ]),

              const SizedBox(height: 14),

              // ── Charge coaching banner ───────────────────────────
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: coachColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: coachColor.withValues(alpha: 0.2), width: 1),
                ),
                child: Row(children: [
                  Icon(coachIcon, color: coachColor, size: 15),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(coachMsg,
                        style: RivianText.caption.copyWith(
                            color: RivianColors.textSecondary,
                            height: 1.45,
                            fontSize: 10)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        coachColor.withValues(alpha: 0.2),
                        coachColor.withValues(alpha: 0.05),
                      ]),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${soc.toStringAsFixed(0)}%\nSOC',
                        textAlign: TextAlign.center,
                        style: RivianText.caption.copyWith(
                            color: coachColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            height: 1.3)),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      );
    });
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });
  final String label, value, sub;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              style: RivianText.caption.copyWith(
                  color: RivianColors.textTertiary,
                  fontSize: 8,
                  letterSpacing: 1.0)),
          const SizedBox(height: 2),
          Text(value,
              style: RivianText.headingLg.copyWith(
                  color: color, fontSize: 18, letterSpacing: -0.5)),
          Text(sub,
              style: RivianText.caption
                  .copyWith(color: RivianColors.textTertiary, fontSize: 8)),
        ],
      );
}
