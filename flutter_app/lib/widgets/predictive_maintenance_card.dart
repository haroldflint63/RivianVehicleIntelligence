// ── lib/widgets/predictive_maintenance_card.dart ─────────────────────
//
// Predictive Component Health Timeline — derives remaining useful life
// for 5 drive-system components from live telemetry signals.
// Motor temp cycles → Drive Unit wear  |  Regen events → Brake life
// Voltage variance → 12V health        |  Cumulative RPM → Bearing life

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/telemetry_model.dart';
import '../services/websocket_service.dart';

// ── Data model ──────────────────────────────────────────────────────
enum _CompStatus { good, monitor, scheduleSoon, serviceNow }

class _Component {
  const _Component({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.healthPct,
    required this.milesRemaining,
    required this.status,
    required this.lastService,
  });
  final String name, subtitle, lastService;
  final IconData icon;
  final double healthPct;
  final int milesRemaining;
  final _CompStatus status;
}

class PredictiveMaintenanceCard extends StatelessWidget {
  const PredictiveMaintenanceCard({super.key});

  // ── Component derivations ────────────────────────────────────────
  static List<_Component> _derive(
      double healthScore, List<TelemetryData> hist) {
    // ─ HV Battery Pack ────────────────────────────────────────────
    // Proxy SoH from agent health score
    final battHealth = (96.0 - (100.0 - healthScore) * 0.32).clamp(72.0, 100.0);
    final battMiles = ((battHealth - 70.0) / 0.014 * 30 * 25).round()
        .clamp(0, 350000); // avg 25 mi/day

    // ─ Drive Unit (motor bearings + seals) ─────────────────────
    // Thermal stress events degrade bearings faster
    final thermalEvents = hist.where((t) => t.motorTemp > 200).length;
    final driveHealth =
        (98.0 - thermalEvents * 0.8 - (100.0 - healthScore) * 0.15)
            .clamp(60.0, 100.0);
    final driveMiles = ((driveHealth / 100.0) * 250000).round();

    // ─ Thermal Management System ─────────────────────────────────
    // Based on cabin-vs-outside delta (HVAC workload)
    final avgHvacLoad = hist.isEmpty
        ? 20.0
        : hist
                .map((t) => (t.cabinTemp - t.outsideTemp).abs())
                .reduce((a, b) => a + b) /
            hist.length;
    final thermalHealth =
        (100.0 - avgHvacLoad * 0.4).clamp(65.0, 100.0);
    final thermalMiles = ((thermalHealth / 100.0) * 120000).round();

    // ─ Regenerative Brake System ─────────────────────────────────
    // More regen = less friction = longer brake life
    final avgRegen = hist.isEmpty
        ? 3.0
        : hist
                .map((t) => t.regenPower)
                .reduce((a, b) => a + b) /
            hist.length;
    final regenBonus = (avgRegen / 8.0 * 15.0).clamp(0.0, 15.0);
    final brakeHealth = (88.0 + regenBonus).clamp(70.0, 100.0);
    final brakeMiles = ((brakeHealth / 100.0) * 60000).round();

    // ─ 12V Auxiliary System ──────────────────────────────────────
    // Based on pack voltage stability (lower variance = healthier aux)
    final voltVariance = hist.length < 2
        ? 1.5
        : () {
            final vols = hist.map((t) => t.batteryVoltage).toList();
            final mean = vols.reduce((a, b) => a + b) / vols.length;
            return vols.map((v) => (v - mean).abs()).reduce((a, b) => a + b) /
                vols.length;
          }();
    final auxHealth = (92.0 - voltVariance * 4.0).clamp(45.0, 95.0);
    final auxMiles = ((auxHealth / 100.0) * 30000).round();

    _CompStatus _status(double h) {
      if (h >= 85) return _CompStatus.good;
      if (h >= 70) return _CompStatus.monitor;
      if (h >= 55) return _CompStatus.scheduleSoon;
      return _CompStatus.serviceNow;
    }

    return [
      _Component(
        name: 'HV Battery Pack',
        subtitle: 'NMC · 135 kWh Large',
        icon: Icons.battery_charging_full_rounded,
        healthPct: battHealth,
        milesRemaining: battMiles,
        status: _status(battHealth),
        lastService: '12 mo ago',
      ),
      _Component(
        name: 'Dual Motor Drive Unit',
        subtitle: 'Front + Rear · Bearings + Seals',
        icon: Icons.settings_rounded,
        healthPct: driveHealth,
        milesRemaining: driveMiles,
        status: _status(driveHealth),
        lastService: '8 mo ago',
      ),
      _Component(
        name: 'Thermal Management',
        subtitle: 'Coolant Loop · Heat Pump · Compressor',
        icon: Icons.thermostat_rounded,
        healthPct: thermalHealth,
        milesRemaining: thermalMiles,
        status: _status(thermalHealth),
        lastService: '6 mo ago',
      ),
      _Component(
        name: 'Regenerative Brakes',
        subtitle: 'Friction pads + Regen blending valve',
        icon: Icons.electric_bolt_rounded,
        healthPct: brakeHealth,
        milesRemaining: brakeMiles,
        status: _status(brakeHealth),
        lastService: '18 mo ago',
      ),
      _Component(
        name: '12V Auxiliary System',
        subtitle: 'LFP aux battery · DC-DC converter',
        icon: Icons.battery_1_bar_rounded,
        healthPct: auxHealth,
        milesRemaining: auxMiles,
        status: _status(auxHealth),
        lastService: '24 mo ago',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(builder: (_, svc, __) {
      final components = _derive(svc.healthScore, svc.telemetryHistory);
      final worstStatus = components
          .map((c) => c.status.index)
          .reduce((a, b) => a > b ? a : b);
      final headerColor = [
        RivianColors.green,
        RivianColors.info,
        RivianColors.warning,
        RivianColors.danger,
      ][worstStatus];

      return Container(
        decoration: BoxDecoration(
          color: RivianColors.bg1,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: headerColor.withValues(alpha: 0.20), width: 1),
          boxShadow: RivianShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Top accent ──────────────────────────────────────────
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                headerColor.withValues(alpha: 0.9),
                headerColor.withValues(alpha: 0.0),
              ]),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    headerColor.withValues(alpha: 0.18),
                    headerColor.withValues(alpha: 0.05),
                  ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                      color: headerColor.withValues(alpha: 0.2), width: 1),
                ),
                child: Icon(Icons.build_circle_rounded,
                    color: headerColor, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child:
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PREDICTIVE MAINTENANCE',
                    style: RivianText.label.copyWith(
                        color: headerColor,
                        letterSpacing: 1.4,
                        fontSize: 9)),
                const SizedBox(height: 2),
                Text('AI-derived component health · service timeline',
                    style: RivianText.caption
                        .copyWith(color: RivianColors.textTertiary)),
              ])),
              _StatusBadge(status: _CompStatus.values[worstStatus]),
            ]),
          ),

          // ── Component list ───────────────────────────────────────
          ...components.map((c) => _ComponentTile(component: c)),

          // ── Footer note ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Text(
              'Estimates based on AI telemetry analysis. Consult Rivian service for '
              'confirmed intervals. Service due = component health < 70%.',
              style: RivianText.caption.copyWith(
                  color: RivianColors.textTertiary,
                  fontSize: 9,
                  height: 1.5),
            ),
          ),
        ]),
      );
    });
  }
}

// ── Component tile ───────────────────────────────────────────────────
class _ComponentTile extends StatelessWidget {
  const _ComponentTile({required this.component});
  final _Component component;

  Color get _healthColor {
    if (component.healthPct >= 85) return RivianColors.green;
    if (component.healthPct >= 70) return RivianColors.info;
    if (component.healthPct >= 55) return RivianColors.warning;
    return RivianColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final color = _healthColor;
    final mileFmt = component.milesRemaining >= 1000
        ? '${(component.milesRemaining / 1000).toStringAsFixed(0)}k mi'
        : '${component.milesRemaining} mi';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RivianColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Icon(component.icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(component.name,
                style: RivianText.bodySm.copyWith(
                    color: RivianColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
            Text(component.subtitle,
                style: RivianText.caption
                    .copyWith(color: RivianColors.textTertiary, fontSize: 9)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${component.healthPct.toStringAsFixed(1)}%',
                style: RivianText.headingMd.copyWith(
                    color: color, fontSize: 14, letterSpacing: -0.3)),
            Text('health', style: RivianText.caption.copyWith(fontSize: 8)),
          ]),
        ]),

        const SizedBox(height: 10),

        // Health bar
        Stack(children: [
          Container(
              height: 6,
              decoration: BoxDecoration(
                  color: RivianColors.bg3,
                  borderRadius: BorderRadius.circular(3))),
          FractionallySizedBox(
            widthFactor: component.healthPct / 100,
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                gradient:
                    LinearGradient(colors: [color.withValues(alpha: 0.45), color]),
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                      color: color.withValues(alpha: 0.3), blurRadius: 4)
                ],
              ),
            ),
          ),
        ]),

        const SizedBox(height: 8),

        // Footer
        Row(children: [
          _StatusBadge(status: component.status),
          const Spacer(),
          Icon(Icons.timer_outlined,
              size: 9, color: RivianColors.textTertiary),
          const SizedBox(width: 3),
          Text('$mileFmt until service',
              style: RivianText.caption.copyWith(
                  color: RivianColors.textTertiary, fontSize: 9)),
          const SizedBox(width: 8),
          Icon(Icons.history_rounded,
              size: 9, color: RivianColors.textTertiary),
          const SizedBox(width: 3),
          Text(component.lastService,
              style: RivianText.caption.copyWith(
                  color: RivianColors.textTertiary, fontSize: 9)),
        ]),
      ]),
    );
  }
}

// ── Status badge ────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final _CompStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      _CompStatus.good => ('GOOD', RivianColors.green),
      _CompStatus.monitor => ('MONITOR', RivianColors.info),
      _CompStatus.scheduleSoon => ('SCHEDULE', RivianColors.warning),
      _CompStatus.serviceNow => ('SERVICE NOW', RivianColors.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Text(label,
          style: RivianText.caption.copyWith(
              color: color, fontWeight: FontWeight.w800, fontSize: 8)),
    );
  }
}
