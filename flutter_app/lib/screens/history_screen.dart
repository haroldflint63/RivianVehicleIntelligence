// ── lib/screens/history_screen.dart ─────────────────────────────────
//
// Open-source integrations applied
// • rivian/ai-sast  (Apache 2.0) — feedback buttons: Confirm / False Positive
//                                   shows confirmed/dismissed badge per alert
// • rivian/odxtools (MIT)        — DTC code badge + VRS score pill on each tile
// • NATS subject routing         — NATS subject label shown in tile metadata

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/agent_decision.dart';
import '../services/websocket_service.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(builder: (_, svc, __) {
      return CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Simulation controls ─────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(child: _SimulationPanel(svc: svc)),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 28)),

          // ── DB stats strip (rivian/ai-sast feedback loop counter) ─
          if (svc.dbStats.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(child: _DbStatsStrip(stats: svc.dbStats)),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],

          // ── Alert history header ────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Row(children: [
                const Icon(Icons.history_rounded,
                    size: 13, color: RivianColors.textTertiary),
                const SizedBox(width: 6),
                Text('ALERT HISTORY',
                    style: RivianText.label.copyWith(
                        color: RivianColors.textTertiary,
                        letterSpacing: 1.4,
                        fontSize: 10)),
                const Spacer(),
                Text('${svc.alertHistory.length} events',
                    style: RivianText.caption),
              ]),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ── Alert log ───────────────────────────────────────────
          if (svc.alertHistory.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(child: _EmptyAlerts()),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _AlertTile(
                    decision: svc.alertHistory[i],
                    svc:      svc,
                  ),
                  childCount: svc.alertHistory.length,
                ),
              ),
            ),
        ],
      );
    });
  }
}

// ── DB stats strip ────────────────────────────────────────────────────
class _DbStatsStrip extends StatelessWidget {
  const _DbStatsStrip({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final total    = stats['total_alerts']   as int? ?? 0;
    final feedback = stats['total_feedback'] as int? ?? 0;
    final confirmed   = stats['confirmed_alerts']  as int? ?? 0;
    final falsePos    = stats['false_positives']   as int? ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: RivianColors.bg1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RivianColors.border, width: 1),
      ),
      child: Row(children: [
        const Icon(Icons.storage_rounded,
            size: 13, color: RivianColors.textTertiary),
        const SizedBox(width: 8),
        Text('SQLite DB',
            style: RivianText.label.copyWith(
                color: RivianColors.textTertiary, fontSize: 9, letterSpacing: 1)),
        const Spacer(),
        _StatPill(label: 'Alerts', value: total, color: RivianColors.info),
        const SizedBox(width: 8),
        _StatPill(label: 'Feedback', value: feedback, color: RivianColors.ice),
        const SizedBox(width: 8),
        _StatPill(label: 'Confirmed', value: confirmed, color: RivianColors.green),
        const SizedBox(width: 8),
        _StatPill(label: 'FP', value: falsePos, color: RivianColors.warning),
      ]),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value, required this.color});
  final String label;
  final int    value;
  final Color  color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$value', style: RivianText.caption.copyWith(
              color: color, fontWeight: FontWeight.w800)),
          const SizedBox(width: 3),
          Text(label, style: RivianText.caption.copyWith(
              color: color.withValues(alpha: 0.7), fontSize: 8)),
        ]),
      );
}

// ── Simulation control panel ──────────────────────────────────────────
class _SimulationPanel extends StatelessWidget {
  const _SimulationPanel({required this.svc});
  final WebSocketService svc;

  @override
  Widget build(BuildContext context) {
    final connected = svc.connectionState == WsState.connected;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.science_outlined,
            size: 13, color: RivianColors.textTertiary),
        const SizedBox(width: 6),
        Text('SIMULATION CONTROLS',
            style: RivianText.label.copyWith(
                color: RivianColors.textTertiary,
                letterSpacing: 1.4,
                fontSize: 10)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (connected ? RivianColors.green : RivianColors.danger)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            connected ? 'CONNECTED' : 'OFFLINE',
            style: RivianText.caption.copyWith(
              color: connected ? RivianColors.green : RivianColors.danger,
              fontWeight: FontWeight.w700,
              fontSize: 9,
            ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: RivianColors.bg1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: RivianColors.border, width: 1),
        ),
        child: Column(children: [
          _CmdButton(
            label: 'Simulate Motor Spike',
            description: 'Triggers a +85–120°F anomaly spike for 5 ticks',
            icon: Icons.local_fire_department_rounded,
            color: RivianColors.danger,
            disabled: !connected,
            onTap: () => svc.sendCommand('SIMULATE_SPIKE'),
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: RivianColors.border),
          const SizedBox(height: 10),
          _CmdButton(
            label: 'Simulate Cold Weather',
            description: 'Forces 45 ticks of sub-32°F outside temperature',
            icon: Icons.ac_unit_rounded,
            color: RivianColors.ice,
            disabled: !connected,
            onTap: () => svc.sendCommand('SIMULATE_COLD'),
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: RivianColors.border),
          const SizedBox(height: 10),
          _CmdButton(
            label: 'Force AI Status Report',
            description: 'Immediately calls Groq LLM regardless of 10s interval',
            icon: Icons.smart_toy_rounded,
            color: RivianColors.info,
            disabled: !connected,
            onTap: () => svc.sendCommand('FORCE_REPORT'),
          ),
        ]),
      ),
    ]);
  }
}

class _CmdButton extends StatefulWidget {
  const _CmdButton({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.disabled,
    required this.onTap,
  });
  final String label, description;
  final IconData icon;
  final Color color;
  final bool disabled;
  final VoidCallback onTap;
  @override
  State<_CmdButton> createState() => _CmdButtonState();
}

class _CmdButtonState extends State<_CmdButton> {
  bool _fired = false;

  void _tap() {
    if (widget.disabled || _fired) return;
    widget.onTap();
    setState(() => _fired = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _fired = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.disabled
        ? RivianColors.textTertiary
        : _fired
            ? RivianColors.green
            : widget.color;

    return GestureDetector(
      onTap: _tap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _fired ? Icons.check_rounded : widget.icon,
              color: color,
              size: 17,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fired ? 'Command sent!' : widget.label,
                    style: RivianText.headingMd.copyWith(color: color)),
                const SizedBox(height: 2),
                Text(widget.description,
                    style: RivianText.caption.copyWith(height: 1.3)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              color: color.withValues(alpha: 0.5), size: 18),
        ]),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────
class _EmptyAlerts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: RivianColors.bg1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RivianColors.border, width: 1),
      ),
      child: Column(children: [
        Icon(Icons.verified_rounded, color: RivianColors.green, size: 36),
        const SizedBox(height: 12),
        Text('All Systems Nominal',
            style: RivianText.headingMd.copyWith(color: RivianColors.green)),
        const SizedBox(height: 6),
        Text('No alerts have fired this session.', style: RivianText.bodySm),
      ]),
    );
  }
}

// ── Alert tile ────────────────────────────────────────────────────────
class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.decision, required this.svc});
  final AgentDecision  decision;
  final WebSocketService svc;

  @override
  Widget build(BuildContext context) {
    final color = decision.severity == Severity.critical
        ? RivianColors.danger
        : RivianColors.warning;

    final feedbackColor = switch (decision.feedback) {
      AlertFeedback.confirmed     => RivianColors.green,
      AlertFeedback.falsePositive => RivianColors.textTertiary,
      AlertFeedback.none          => null,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: RivianColors.bg1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: feedbackColor?.withValues(alpha: 0.35) ??
              color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Main row ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Severity dot
              Container(
                width: 8, height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: feedbackColor ?? color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(decision.agentLabel,
                            style: RivianText.label.copyWith(
                                color: RivianColors.textSecondary,
                                fontSize: 9,
                                letterSpacing: 0.8)),
                      ),
                      Text(_timeAgo(decision.timestamp), style: RivianText.caption),
                    ]),
                    const SizedBox(height: 4),
                    Text(decision.message,
                        style: RivianText.bodySm.copyWith(
                            color: RivianColors.textPrimary.withValues(alpha: 0.88),
                            fontSize: 12)),
                    const SizedBox(height: 8),

                    // ── Chips row ──────────────────────────────
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      // OBD-II DTC code chip (rivian/odxtools)
                      if (decision.hasDtc)
                        _Chip(
                          label: decision.dtcCode,
                          tooltip: '${decision.dtcSystem} — ${decision.cvssVector}',
                          color: color,
                          icon: Icons.car_repair_rounded,
                        ),
                      // VRS score chip
                      if (decision.hasVrs)
                        _Chip(
                          label: 'VRS ${decision.cvssScore.toStringAsFixed(1)}',
                          tooltip: decision.cvssVector,
                          color: _vrsColor(decision.cvssScore),
                        ),
                      // Z-score chip (anomaly agent)
                      if (decision.metadata['z_score'] != null)
                        _Chip(
                          label: 'Z = ${(decision.metadata['z_score'] as num).toStringAsFixed(2)}',
                          color: color,
                        ),
                      // Motor temp chip
                      if (decision.metadata['motor_temp'] != null)
                        _Chip(
                          label: '${(decision.metadata['motor_temp'] as num).toStringAsFixed(1)}°F',
                          color: color,
                        ),
                      // Feedback badge
                      if (decision.feedback != AlertFeedback.none)
                        _Chip(
                          label: decision.feedback == AlertFeedback.confirmed
                              ? '✓ Confirmed'
                              : '✗ False Positive',
                          color: feedbackColor!,
                        ),
                    ]),
                  ],
                ),
              ),
            ]),
          ),

          // ── Feedback buttons (rivian/ai-sast pattern) ──────────
          if (decision.alertId.isNotEmpty &&
              decision.feedback == AlertFeedback.none) ...[
            Divider(height: 1, color: RivianColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(children: [
                Text('Mark:',
                    style: RivianText.caption.copyWith(
                        color: RivianColors.textTertiary, fontSize: 9)),
                const SizedBox(width: 10),
                _FeedbackBtn(
                  label: '✅  Confirm',
                  color: RivianColors.green,
                  onTap: () => svc.sendFeedback(
                      alertId: decision.alertId,
                      status:  'confirmed_alert'),
                ),
                const SizedBox(width: 8),
                _FeedbackBtn(
                  label: '❌  False Positive',
                  color: RivianColors.textTertiary,
                  onTap: () => svc.sendFeedback(
                      alertId: decision.alertId,
                      status:  'false_positive'),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  static Color _vrsColor(double score) {
    if (score >= 7.0) return RivianColors.danger;
    if (score >= 4.0) return RivianColors.warning;
    if (score >= 0.1) return RivianColors.info;
    return RivianColors.textTertiary;
  }

  static String _timeAgo(double ts) {
    final dt   = DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${dt.hour.toString().padLeft(2, "0")}:'
        '${dt.minute.toString().padLeft(2, "0")}';
  }
}

// ── Chip widget ───────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.tooltip, this.icon});
  final String  label;
  final Color   color;
  final String? tooltip;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 3),
        ],
        Text(label,
            style: RivianText.caption.copyWith(
                color: color, fontWeight: FontWeight.w700, fontSize: 9)),
      ]),
    );
    if (tooltip != null) {
      chip = Tooltip(message: tooltip!, child: chip);
    }
    return chip;
  }
}

// ── Feedback button ───────────────────────────────────────────────────
class _FeedbackBtn extends StatefulWidget {
  const _FeedbackBtn({required this.label, required this.color, required this.onTap});
  final String label;
  final Color  color;
  final VoidCallback onTap;
  @override
  State<_FeedbackBtn> createState() => _FeedbackBtnState();
}

class _FeedbackBtnState extends State<_FeedbackBtn> {
  bool _sent = false;

  void _tap() {
    if (_sent) return;
    widget.onTap();
    setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _tap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: (_sent ? RivianColors.green : widget.color).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: (_sent ? RivianColors.green : widget.color).withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Text(
          _sent ? 'Sent ✓' : widget.label,
          style: RivianText.caption.copyWith(
            color: _sent ? RivianColors.green : widget.color,
            fontWeight: FontWeight.w700,
            fontSize: 9,
          ),
        ),
      ),
    );
  }
}

