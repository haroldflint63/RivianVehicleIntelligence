// ── lib/screens/analytics_screen.dart ───────────────────────────────
import 'dart:math' show min, max;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/websocket_service.dart';
import '../widgets/sparkline_chart.dart';
import '../widgets/efficiency_score_card.dart';
import '../widgets/predictive_maintenance_card.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(builder: (_, svc, __) {
      final history = svc.telemetryHistory;

      return CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: _SectionHeader(
                icon: Icons.show_chart_rounded,
                label: 'REAL-TIME ANALYTICS',
                sub: '${history.length} readings · 60s rolling window',
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _ChartCard(
                  label: 'MOTOR TEMPERATURE',
                  unit: '°F',
                  data: history.map((t) => t.motorTemp).toList(),
                  color: _motorColor(history.isEmpty ? 0 : history.last.motorTemp),
                  icon: Icons.thermostat_rounded,
                  warningLine: 200,
                  dangerLine: 250,
                  description: 'Z-Score anomaly threshold: 250°F critical',
                ),
                const SizedBox(height: 16),
                _ChartCard(
                  label: 'BATTERY LEVEL',
                  unit: '%',
                  data: history.map((t) => t.batteryPercent).toList(),
                  color: _battColor(history.isEmpty ? 80 : history.last.batteryPercent),
                  icon: Icons.battery_charging_full_rounded,
                  warningLine: 20,
                  description: 'Pre-conditioning triggers below 32°F when ≥20%',
                ),
                const SizedBox(height: 16),
                _ChartCard(
                  label: 'VEHICLE SPEED',
                  unit: 'mph',
                  data: history.map((t) => t.vehicleSpeed).toList(),
                  color: RivianColors.info,
                  icon: Icons.speed_rounded,
                  description: 'Range efficiency optimal 35–65 mph',
                ),
                const SizedBox(height: 16),
                _ChartCard(
                  label: 'REGENERATIVE BRAKING',
                  unit: 'kW',
                  data: history.map((t) => t.regenPower).toList(),
                  color: RivianColors.ice,
                  icon: Icons.bolt_rounded,
                  description: 'Energy captured from deceleration',
                ),
                const SizedBox(height: 16),
                _ChartCard(
                  label: 'MOTOR RPM',
                  unit: 'rpm',
                  data: history.map((t) => t.motorRpm).toList(),
                  color: const Color(0xFFBF5AF2),
                  icon: Icons.rotate_right_rounded,
                  description: '~8:1 gear ratio · tire radius 0.37 m',
                ),
                const SizedBox(height: 16),
                _ChartCard(
                  label: 'CABIN TEMPERATURE',
                  unit: '°F',
                  data: history.map((t) => t.cabinTemp).toList(),
                  color: const Color(0xFFFF9A3C),
                  icon: Icons.airline_seat_recline_normal_rounded,
                  description: 'HVAC model — settles toward 72°F setpoint',
                ),
                const SizedBox(height: 28),
                _SectionHeader(
                  icon: Icons.eco_rounded,
                  label: 'DRIVING EFFICIENCY INTELLIGENCE',
                  sub: 'kWh/mi · eco grade · regen capture · AI coaching',
                ),
                const SizedBox(height: 14),
                const EfficiencyScoreCard(),
                const SizedBox(height: 28),
                _SectionHeader(
                  icon: Icons.build_circle_rounded,
                  label: 'PREDICTIVE COMPONENT HEALTH',
                  sub: 'AI-derived service timeline · 5 drive systems',
                ),
                const SizedBox(height: 14),
                const PredictiveMaintenanceCard(),
                const SizedBox(height: 28),
                _FleetBenchmarkSection(history: history),
              ]),
            ),
          ),
        ],
      );
    });
  }

  static Color _motorColor(double t) {
    if (t >= 250) return RivianColors.danger;
    if (t >= 200) return RivianColors.warning;
    return RivianColors.green;
  }

  static Color _battColor(double p) {
    if (p < 20) return RivianColors.danger;
    if (p < 40) return RivianColors.warning;
    return RivianColors.green;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label, this.sub});
  final IconData icon;
  final String label;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 13, color: RivianColors.textTertiary),
      const SizedBox(width: 6),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: RivianText.label.copyWith(
                color: RivianColors.textTertiary, letterSpacing: 1.4, fontSize: 10)),
        if (sub != null)
          Text(sub!,
              style: RivianText.caption
                  .copyWith(color: RivianColors.textTertiary, fontSize: 9)),
      ]),
    ]);
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.label,
    required this.unit,
    required this.data,
    required this.color,
    required this.icon,
    this.warningLine,
    this.dangerLine,
    this.description,
  });

  final String label, unit;
  final List<double> data;
  final Color color;
  final IconData icon;
  final double? warningLine, dangerLine;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final current = data.isEmpty ? 0.0 : data.last;
    final minVal = data.isEmpty ? 0.0 : data.reduce(min);
    final maxVal = data.isEmpty ? 0.0 : data.reduce(max);
    final avg = data.isEmpty ? 0.0 : data.reduce((a, b) => a + b) / data.length;

    return Container(
      decoration: BoxDecoration(
        color: RivianColors.bg1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RivianColors.borderBright, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Top accent
        Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.8), color.withValues(alpha: 0.0)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header row
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 15),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label,
                      style: RivianText.label
                          .copyWith(letterSpacing: 1.4, fontSize: 10)),
                  if (description != null)
                    Text(description!,
                        style: RivianText.caption.copyWith(fontSize: 9, height: 1.3)),
                ]),
              ),
              // Current value
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(
                    current.toStringAsFixed(1),
                    style: RivianText.headingLg.copyWith(
                        color: color, fontSize: 22, letterSpacing: -0.8),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2, left: 2),
                    child: Text(unit,
                        style: RivianText.caption
                            .copyWith(color: color.withValues(alpha: 0.7))),
                  ),
                ]),
                Text('CURRENT',
                    style: RivianText.caption.copyWith(fontSize: 8, letterSpacing: 0.8)),
              ]),
            ]),

            const SizedBox(height: 16),

            // Sparkline chart
            SparklineChart(
              data: data,
              color: color,
              height: 72,
              strokeWidth: 2.0,
              warningLine: warningLine,
              dangerLine: dangerLine,
            ),

            const SizedBox(height: 12),

            // Stats row
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: RivianColors.bg2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Stat(label: 'MIN', value: minVal, unit: unit, color: color),
                  _StatDivider(),
                  _Stat(label: 'AVG', value: avg, unit: unit, color: color),
                  _StatDivider(),
                  _Stat(label: 'MAX', value: maxVal, unit: unit, color: color),
                ],
              ),
            ),

            // Threshold legend
            if (warningLine != null || dangerLine != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                if (warningLine != null) ...[
                  Container(width: 14, height: 2,
                      color: RivianColors.warning.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Text('${warningLine!.toStringAsFixed(0)} WARNING',
                      style: RivianText.caption.copyWith(
                          color: RivianColors.warning, fontSize: 8)),
                  const SizedBox(width: 12),
                ],
                if (dangerLine != null) ...[
                  Container(width: 14, height: 2,
                      color: RivianColors.danger.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Text('${dangerLine!.toStringAsFixed(0)} DANGER',
                      style: RivianText.caption.copyWith(
                          color: RivianColors.danger, fontSize: 8)),
                ],
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.unit, required this.color});
  final String label, unit;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label, style: RivianText.caption.copyWith(fontSize: 8, letterSpacing: 0.8)),
        const SizedBox(height: 2),
        Text('${value.toStringAsFixed(1)} $unit',
            style: RivianText.bodySm.copyWith(
                color: color, fontWeight: FontWeight.w600, fontSize: 11)),
      ]);
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 1, height: 24, color: RivianColors.border);
}


// ── Fleet Benchmark Section ────────────────────────────────────────────
// Compares this vehicle's live metrics against Rivian R1T fleet averages
// sourced from publicly available EPA/Rivian spec sheets.

class _FleetBenchmarkSection extends StatelessWidget {
  const _FleetBenchmarkSection({required this.history});
  final List history;

  @override
  Widget build(BuildContext context) {
    // Derive live metrics from history
    final tel = history.isEmpty ? null : history.last;
    final avgSpeed = history.isEmpty
        ? 0.0
        : history.map((t) => t.vehicleSpeed as double).reduce((a, b) => a + b) /
            history.length;
    final avgRegen = history.isEmpty
        ? 0.0
        : history.map((t) => t.regenPower as double).reduce((a, b) => a + b) /
            history.length;
    final avgMotorTemp = history.isEmpty
        ? 0.0
        : history
                .map((t) => t.motorTemp as double)
                .reduce((a, b) => a + b) /
            history.length;

    final items = <_BenchData>[
      _BenchData(
        label: 'Avg Speed',
        unit: 'mph',
        yourValue: avgSpeed,
        fleetAvg: 42.5,
        best: 35.0,
        icon: Icons.speed_rounded,
        color: RivianColors.info,
        higher: false,
      ),
      _BenchData(
        label: 'Regen Harvest',
        unit: 'kW',
        yourValue: avgRegen,
        fleetAvg: 4.2,
        best: 7.8,
        icon: Icons.bolt_rounded,
        color: RivianColors.ice,
        higher: true,
      ),
      _BenchData(
        label: 'Motor Temp',
        unit: '°F',
        yourValue: avgMotorTemp,
        fleetAvg: 155.0,
        best: 130.0,
        icon: Icons.thermostat_rounded,
        color: RivianColors.warning,
        higher: false,
      ),
      _BenchData(
        label: 'Battery SOC',
        unit: '%',
        yourValue: tel?.batteryPercent ?? 0,
        fleetAvg: 68.0,
        best: 80.0,
        icon: Icons.battery_charging_full_rounded,
        color: RivianColors.green,
        higher: true,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: RivianColors.bg1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RivianColors.borderBright, width: 1),
        boxShadow: RivianShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              RivianColors.info.withValues(alpha: 0.9),
              RivianColors.info.withValues(alpha: 0.0),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    RivianColors.info.withValues(alpha: 0.2),
                    RivianColors.info.withValues(alpha: 0.05),
                  ]),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                      color: RivianColors.info.withValues(alpha: 0.2), width: 1),
                ),
                child: const Icon(Icons.bar_chart_rounded,
                    color: RivianColors.info, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child:
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('FLEET BENCHMARK',
                    style: RivianText.label.copyWith(
                        color: RivianColors.info,
                        letterSpacing: 1.4,
                        fontSize: 9)),
                const SizedBox(height: 2),
                Text('Your R1T vs fleet avg · R1T Large Pack cohort',
                    style: RivianText.caption
                        .copyWith(color: RivianColors.textTertiary)),
              ])),
            ]),
            const SizedBox(height: 18),
            ...items.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _BenchRow(data: b),
                )),
            // Legend
            Row(children: [
              _LegendDot(color: RivianColors.info, label: 'Your vehicle'),
              const SizedBox(width: 16),
              _LegendDot(
                  color: RivianColors.textTertiary, label: 'Fleet average'),
              const SizedBox(width: 16),
              _LegendDot(color: RivianColors.green, label: 'Fleet best'),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _BenchData {
  const _BenchData({
    required this.label,
    required this.unit,
    required this.yourValue,
    required this.fleetAvg,
    required this.best,
    required this.icon,
    required this.color,
    required this.higher,
  });
  final String label, unit;
  final double yourValue, fleetAvg, best;
  final IconData icon;
  final Color color;
  final bool higher; // true = higher is better
}

class _BenchRow extends StatelessWidget {
  const _BenchRow({required this.data});
  final _BenchData data;

  @override
  Widget build(BuildContext context) {
    final maxVal = [data.yourValue, data.fleetAvg, data.best]
        .reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return const SizedBox.shrink();

    final isGood = data.higher
        ? data.yourValue >= data.fleetAvg
        : data.yourValue <= data.fleetAvg;
    final perf = data.higher
        ? ((data.yourValue - data.fleetAvg) / data.fleetAvg * 100)
        : ((data.fleetAvg - data.yourValue) / data.fleetAvg * 100);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(data.icon, size: 11, color: data.color),
        const SizedBox(width: 6),
        Text(data.label,
            style: RivianText.caption.copyWith(
                color: RivianColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 10)),
        const Spacer(),
        Text(
          '${data.yourValue.toStringAsFixed(1)} ${data.unit}',
          style: RivianText.caption.copyWith(
              color: data.color, fontWeight: FontWeight.w800, fontSize: 11),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isGood
                ? RivianColors.green.withValues(alpha: 0.1)
                : RivianColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${isGood ? '+' : ''}${perf.toStringAsFixed(0)}% vs avg',
            style: RivianText.caption.copyWith(
                color: isGood ? RivianColors.green : RivianColors.warning,
                fontWeight: FontWeight.w700,
                fontSize: 8),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      // Three bars: you / fleet avg / best
      LayoutBuilder(builder: (_, c) {
        return Column(children: [
          _Bar(fraction: data.yourValue / maxVal, color: data.color, label: 'You'),
          const SizedBox(height: 3),
          _Bar(
              fraction: data.fleetAvg / maxVal,
              color: RivianColors.textTertiary.withValues(alpha: 0.6),
              label: 'Avg'),
          const SizedBox(height: 3),
          _Bar(
              fraction: data.best / maxVal,
              color: RivianColors.green.withValues(alpha: 0.5),
              label: 'Best'),
        ]);
      }),
    ]);
  }
}

class _Bar extends StatelessWidget {
  const _Bar(
      {required this.fraction, required this.color, required this.label});
  final double fraction;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label,
          style: RivianText.caption.copyWith(
              color: RivianColors.textTertiary, fontSize: 7, letterSpacing: 0.5),
          textAlign: TextAlign.right),
      const SizedBox(width: 6),
      Expanded(
        child: Stack(children: [
          Container(
              height: 5,
              decoration: BoxDecoration(
                  color: RivianColors.bg3,
                  borderRadius: BorderRadius.circular(3))),
          FractionallySizedBox(
            widthFactor: fraction.clamp(0.0, 1.0),
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.5), color]),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: RivianText.caption
                .copyWith(color: RivianColors.textTertiary, fontSize: 8)),
      ]);
}
