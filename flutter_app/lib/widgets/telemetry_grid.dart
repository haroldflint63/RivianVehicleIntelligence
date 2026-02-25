// ── lib/widgets/telemetry_grid.dart ─────────────────────────────────
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/telemetry_model.dart';
import 'sparkline_chart.dart';

class TelemetryGrid extends StatelessWidget {
  const TelemetryGrid({
    super.key,
    required this.telemetry,
    this.history = const [],
  });

  final TelemetryData telemetry;
  final List<TelemetryData> history;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel(label: 'LIVE TELEMETRY', icon: Icons.sensors_rounded),
      const SizedBox(height: 14),

      // Row 1: Hero cards
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: _HeroCard(
            label: 'MOTOR TEMP',
            value: '${telemetry.motorTemp.toStringAsFixed(1)}°',
            unit: 'F',
            color: _motorColor(telemetry.motorTemp),
            status: _motorStatus(telemetry.motorTemp),
            icon: Icons.thermostat_rounded,
            glow: telemetry.motorTemp >= 200,
            sparkData: history.map((t) => t.motorTemp).toList(),
            warningLine: 200,
            dangerLine: 250,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BatteryHeroCard(
            percent: telemetry.batteryPercent,
            sparkData: history.map((t) => t.batteryPercent).toList(),
          ),
        ),
      ]),
      const SizedBox(height: 10),

      // Row 2
      Row(children: [
        Expanded(child: _MetricTile(
          label: 'OUTSIDE TEMP',
          value: '${telemetry.outsideTemp.toStringAsFixed(0)}°F',
          icon: telemetry.outsideTemp < 32
              ? Icons.ac_unit_rounded
              : Icons.wb_sunny_rounded,
          color: _outsideColor(telemetry.outsideTemp),
          tag: telemetry.outsideTemp < 32 ? 'FREEZING' : null,
          tagColor: RivianColors.ice,
        )),
        const SizedBox(width: 10),
        Expanded(child: _MetricTile(
          label: 'SPEED',
          value: '${telemetry.vehicleSpeed.toStringAsFixed(1)}',
          unit: 'mph',
          icon: Icons.speed_rounded,
          color: RivianColors.info,
          tag: telemetry.vehicleSpeed < 1 ? 'PARKED' : null,
          tagColor: RivianColors.textTertiary,
        )),
        const SizedBox(width: 10),
        Expanded(child: _MetricTile(
          label: 'PACK VOLTAGE',
          value: '${telemetry.batteryVoltage.toStringAsFixed(0)}',
          unit: 'V',
          icon: Icons.electric_bolt_rounded,
          color: RivianColors.purple,
        )),
      ]),
      const SizedBox(height: 10),

      // Row 3
      Row(children: [
        Expanded(child: _MetricTile(
          label: 'CABIN TEMP',
          value: '${telemetry.cabinTemp.toStringAsFixed(1)}°F',
          icon: Icons.airline_seat_recline_normal_rounded,
          color: const Color(0xFFFF9A3C),
          tag: telemetry.cabinTemp < 65 ? 'COLD' : null,
          tagColor: RivianColors.ice,
        )),
        const SizedBox(width: 10),
        Expanded(child: _MetricTile(
          label: 'REGEN',
          value: '${telemetry.regenPower.toStringAsFixed(1)}',
          unit: 'kW',
          icon: Icons.bolt_rounded,
          color: RivianColors.ice,
          tag: telemetry.regenPower > 5 ? 'ACTIVE' : null,
          tagColor: RivianColors.ice,
        )),
        const SizedBox(width: 10),
        Expanded(child: _MetricTile(
          label: 'MOTOR RPM',
          value: '${(telemetry.motorRpm / 1000).toStringAsFixed(1)}',
          unit: 'krpm',
          icon: Icons.rotate_right_rounded,
          color: RivianColors.purple,
        )),
      ]),
    ]);
  }

  static Color _motorColor(double t) {
    if (t >= 250) return RivianColors.danger;
    if (t >= 200) return RivianColors.warning;
    return RivianColors.green;
  }

  static String _motorStatus(double t) {
    if (t >= 250) return 'CRITICAL';
    if (t >= 200) return 'ELEVATED';
    return 'NOMINAL';
  }

  static Color _outsideColor(double t) {
    if (t < 32) return RivianColors.ice;
    if (t < 50) return RivianColors.green;
    return RivianColors.warning;
  }
}

// ── Section label ─────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 12, color: RivianColors.textTertiary),
        const SizedBox(width: 6),
        Text(label,
            style: RivianText.label.copyWith(
                color: RivianColors.textTertiary,
                fontSize: 9,
                letterSpacing: 1.4)),
      ]);
}

// ── Hero card ─────────────────────────────────────────────────────────
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.status,
    required this.icon,
    this.glow = false,
    this.sparkData = const [],
    this.warningLine,
    this.dangerLine,
  });
  final String label, value, unit, status;
  final Color color;
  final IconData icon;
  final bool glow;
  final List<double> sparkData;
  final double? warningLine, dangerLine;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: glow ? 0.12 : 0.06),
            RivianColors.bg1,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: color.withValues(alpha: glow ? 0.35 : 0.2), width: 1),
        boxShadow: glow
            ? [
                BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 24,
                    spreadRadius: 0),
                ...RivianShadows.card,
              ]
            : RivianShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Icon badge
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.2),
                  color.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: color.withValues(alpha: 0.15), width: 1),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const Spacer(),
          _StatusPill(label: status, color: color),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(value,
              style: RivianText.displayMd
                  .copyWith(color: color, fontSize: 30, letterSpacing: -1.4)),
          Padding(
            padding: const EdgeInsets.only(bottom: 3, left: 3),
            child: Text(unit,
                style: RivianText.bodySm
                    .copyWith(color: color.withValues(alpha: 0.65))),
          ),
        ]),
        const SizedBox(height: 3),
        Text(label, style: RivianText.caption),
        if (sparkData.length >= 2) ...[
          const SizedBox(height: 12),
          SparklineChart(
            data: sparkData,
            color: color,
            height: 36,
            strokeWidth: 1.5,
            warningLine: warningLine,
            dangerLine: dangerLine,
          ),
        ],
      ]),
    );
  }
}

// ── Battery hero card ─────────────────────────────────────────────────
class _BatteryHeroCard extends StatelessWidget {
  const _BatteryHeroCard({required this.percent, this.sparkData = const []});
  final double percent;
  final List<double> sparkData;

  @override
  Widget build(BuildContext context) {
    final color = percent < 20
        ? RivianColors.danger
        : percent < 40
            ? RivianColors.warning
            : RivianColors.green;
    final label = percent < 20 ? 'LOW' : percent < 40 ? 'OK' : 'GOOD';

    return Container(
      padding: const EdgeInsets.all(18),
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
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.2),
                  color.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: color.withValues(alpha: 0.15), width: 1),
            ),
            child: Icon(Icons.battery_charging_full_rounded,
                color: color, size: 15),
          ),
          const Spacer(),
          _StatusPill(label: label, color: color),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(percent.toStringAsFixed(1),
              style: RivianText.displayMd
                  .copyWith(color: color, fontSize: 30, letterSpacing: -1.4)),
          Padding(
            padding: const EdgeInsets.only(bottom: 3, left: 2),
            child: Text('%',
                style: RivianText.bodySm
                    .copyWith(color: color.withValues(alpha: 0.65))),
          ),
        ]),
        const SizedBox(height: 3),
        Text('BATTERY', style: RivianText.caption),
        const SizedBox(height: 10),

        // Battery fill bar
        Stack(children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
                color: RivianColors.bg3,
                borderRadius: BorderRadius.circular(4)),
          ),
          FractionallySizedBox(
            widthFactor: (percent / 100).clamp(0.0, 1.0),
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.6), color]),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                      color: color.withValues(alpha: 0.4), blurRadius: 6)
                ],
              ),
            ),
          ),
        ]),

        if (sparkData.length >= 2) ...[
          const SizedBox(height: 10),
          SparklineChart(
            data: sparkData,
            color: color,
            height: 30,
            strokeWidth: 1.5,
            warningLine: 20,
          ),
        ],
      ]),
    );
  }
}

// ── Secondary metric tile ─────────────────────────────────────────────
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.unit,
    this.tag,
    this.tagColor,
  });
  final String label, value;
  final String? unit, tag;
  final IconData icon;
  final Color color;
  final Color? tagColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.04),
            RivianColors.bg1,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: color.withValues(alpha: 0.15), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Coloured icon
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 13),
        ),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(
            child: Text(value,
                style: RivianText.headingLg.copyWith(
                    color: color, fontSize: 17, letterSpacing: -0.6)),
          ),
          if (unit != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 1, left: 2),
              child: Text(unit!,
                  style: RivianText.caption.copyWith(
                      color: color.withValues(alpha: 0.6), fontSize: 9)),
            ),
        ]),
        const SizedBox(height: 4),
        if (tag != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: (tagColor ?? color).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(tag!,
                style: RivianText.caption.copyWith(
                    color: tagColor ?? color,
                    fontWeight: FontWeight.w700,
                    fontSize: 8)),
          )
        else
          Text(label,
              style: RivianText.caption.copyWith(fontSize: 9)),
      ]),
    );
  }
}

// ── Status pill ───────────────────────────────────────────────────────
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
        ),
        child: Text(label,
            style: RivianText.caption.copyWith(
                color: color, fontWeight: FontWeight.w700, fontSize: 8)),
      );
}
