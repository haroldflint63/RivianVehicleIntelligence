import 'package:flutter/material.dart';
import '../main.dart';
import '../models/agent_decision.dart';

class AgentDecisionsPanel extends StatelessWidget {
  const AgentDecisionsPanel({super.key, required this.decisions});
  final List<AgentDecision> decisions;

  @override
  Widget build(BuildContext context) {
    final visible = decisions.where((d) => !d.isStatusReport).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.psychology_rounded,
            size: 13, color: RivianColors.textTertiary),
        const SizedBox(width: 6),
        Text('AGENT DECISIONS',
            style: RivianText.label
                .copyWith(color: RivianColors.textTertiary, letterSpacing: 1.4, fontSize: 10)),
        const Spacer(),
        Text('${visible.length} active',
            style: RivianText.caption
                .copyWith(color: RivianColors.textTertiary)),
      ]),
      const SizedBox(height: 14),
      ...visible.map((d) => _AgentCard(decision: d)),
    ]);
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.decision});
  final AgentDecision decision;

  @override
  Widget build(BuildContext context) {
    final (accentColor, bgColor) = _resolveColors();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: RivianColors.bg1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.2), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        // ── accent bar ────────────────────────────────────────────
        Container(
          height: 3,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accentColor.withValues(alpha: 0.9), accentColor.withValues(alpha: 0.0)],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── header row ─────────────────────────────────────────
            Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(decision.agentIcon, color: accentColor, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(decision.agentLabel,
                        style: RivianText.headingMd
                            .copyWith(color: RivianColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(_decisionTypeLabel(),
                        style: RivianText.caption.copyWith(color: accentColor)),
                  ],
                ),
              ),
              _badge(accentColor),
            ]),

            const SizedBox(height: 14),
            Container(
              height: 1,
              color: RivianColors.border,
            ),
            const SizedBox(height: 14),

            // ── message ────────────────────────────────────────────
            Text(decision.message,
                style: RivianText.bodySm.copyWith(
                    color: RivianColors.textPrimary.withValues(alpha: 0.88),
                    height: 1.6)),

            // ── metadata ───────────────────────────────────────────
            if (decision.metadata.isNotEmpty) ...[
              const SizedBox(height: 14),
              _MetaRow(meta: decision.metadata, color: accentColor),
            ],

            // ── DTC code + VRS score (rivian/odxtools + ai-sast) ──
            if (decision.hasDtc || decision.hasVrs) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (decision.hasDtc)
                  _DtcChip(
                    code: decision.dtcCode,
                    system: decision.dtcSystem,
                    vector: decision.cvssVector,
                    color: accentColor,
                  ),
                if (decision.hasVrs)
                  _VrsBadge(score: decision.cvssScore, color: accentColor),
              ]),
            ],

            // ── warming progress ───────────────────────────────────
            if (decision.isBatteryWarming &&
                decision.metadata['progress_percent'] != null) ...[
              const SizedBox(height: 16),
              _WarmingBar(
                  progress: (decision.metadata['progress_percent'] as num)
                          .toDouble() /
                      100),
            ],
          ]),
        ),
      ]),
    );
  }

  (Color, Color) _resolveColors() {
    if (decision.severity == Severity.critical) {
      return (RivianColors.danger, RivianColors.dangerDim);
    }
    if (decision.severity == Severity.warning) {
      return (RivianColors.warning, RivianColors.warningDim);
    }
    if (decision.isBatteryWarming) {
      return (RivianColors.ice, RivianColors.infoDim);
    }
    return (RivianColors.green, RivianColors.greenDim);
  }

  String _decisionTypeLabel() {
    switch (decision.decisionType) {
      case DecisionType.priorityAlert: return 'Priority Alert';
      case DecisionType.batteryWarming: return 'Battery Conditioning';
      case DecisionType.batteryWarning: return 'Battery Warning';
      default: return 'Normal';
    }
  }

  Widget _badge(Color color) {
    if (decision.isPriorityAlert) return _PulsingBadge(color: color, label: 'ALERT');
    if (decision.isBatteryWarming &&
        decision.metadata['preconditioning_active'] == true) {
      return _PillBadge(color: RivianColors.ice, label: 'WARMING');
    }
    return const SizedBox.shrink();
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.meta, required this.color});
  final Map<String, dynamic> meta;
  final Color color;

  static const _keys = {
    'z_score': 'Z',
    'baseline_mean': 'μ',
    'anomaly_count': 'Alerts',
    'outside_temp': 'Outside',
    'battery_percent': 'Battery',
    'motor_temp': 'Motor',
  };

  @override
  Widget build(BuildContext context) {
    final chips = _keys.entries
        .where((e) => meta.containsKey(e.key) && meta[e.key] != null)
        .toList();
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips.map((e) {
        final raw = meta[e.key];
        final val = raw is double
            ? raw.toStringAsFixed(2)
            : raw.toString();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.18), width: 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${e.value}  ',
                style: RivianText.caption
                    .copyWith(color: color.withValues(alpha: 0.65))),
            Text(val,
                style: RivianText.caption.copyWith(
                    color: color, fontWeight: FontWeight.w700)),
          ]),
        );
      }).toList(),
    );
  }
}

class _WarmingBar extends StatelessWidget {
  const _WarmingBar({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('BATTERY WARM-UP',
            style: RivianText.caption
                .copyWith(color: RivianColors.ice, letterSpacing: 1.2)),
        Text('${(progress * 100).toStringAsFixed(0)}%',
            style: RivianText.caption.copyWith(
                color: RivianColors.ice, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 8),
      Stack(children: [
        Container(
            height: 6,
            decoration: BoxDecoration(
                color: RivianColors.bg3,
                borderRadius: BorderRadius.circular(6))),
        FractionallySizedBox(
          widthFactor: progress,
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF4DA6FF), Color(0xFF7DD4F8)]),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(color: Color(0x557DD4F8), blurRadius: 8)
              ],
            ),
          ),
        ),
      ]),
    ]);
  }
}

// ── DTC + VRS widgets (rivian/odxtools + ai-sast patterns) ──────────

/// OBD-II DTC code chip with tooltip showing the VRS vector string.
class _DtcChip extends StatelessWidget {
  const _DtcChip({
    required this.code,
    required this.system,
    required this.vector,
    required this.color,
  });
  final String code, system, vector;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$system\n$vector',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.car_repair_rounded, size: 10, color: color.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Text(code,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  fontFamily: 'monospace')),
        ]),
      ),
    );
  }
}

/// Vehicle Risk Score badge — colour shifts by severity level.
class _VrsBadge extends StatelessWidget {
  const _VrsBadge({required this.score, required this.color});
  final double score;
  final Color  color;

  static Color _scoreColor(double s) {
    if (s >= 7.0) return const Color(0xFFFF4D4D);   // CRITICAL — red
    if (s >= 4.0) return const Color(0xFFFF9A3C);   // WARNING  — amber
    if (s >= 0.1) return const Color(0xFF4DA6FF);   // INFO     — blue
    return const Color(0xFF4CAF50);                  // SAFE     — green
  }

  @override
  Widget build(BuildContext context) {
    final c = _scoreColor(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('VRS',
            style: TextStyle(
                color: c.withValues(alpha: 0.65),
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0)),
        const SizedBox(width: 4),
        Text(score.toStringAsFixed(1),
            style: TextStyle(
                color: c,
                fontSize: 11,
                fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

// ── Badge widgets ─────────────────────────────────────────────────────
class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(label,
          style: RivianText.caption.copyWith(
              color: color, fontWeight: FontWeight.w800, fontSize: 9)),
    );
  }
}

class _PulsingBadge extends StatefulWidget {
  const _PulsingBadge({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  State<_PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<_PulsingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _a = Tween(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, __) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _a.value * 0.15),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
                color: widget.color.withValues(alpha: _a.value * 0.7), width: 1),
          ),
          child: Text(widget.label,
              style: RivianText.caption.copyWith(
                  color: widget.color.withValues(alpha: _a.value),
                  fontWeight: FontWeight.w800,
                  fontSize: 9)),
        ),
      );
}