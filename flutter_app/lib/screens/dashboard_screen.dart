// ── lib/screens/dashboard_screen.dart ───────────────────────────────
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/agent_decision.dart';
import '../services/websocket_service.dart';
import '../widgets/agent_decisions_panel.dart';
import '../widgets/health_score_card.dart';
import '../widgets/range_gauge_card.dart';
import '../widgets/status_report_card.dart';
import '../widgets/telemetry_grid.dart';
import '../widgets/battery_intelligence_card.dart';
import '../widgets/efficiency_score_card.dart';
import '../widgets/predictive_maintenance_card.dart';
import 'analytics_screen.dart';
import 'history_screen.dart';
import 'service_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<AgentDecision>? _alertSub;
  AgentDecision? _latestAlert;
  late AnimationController _headerCtrl;
  late Animation<double> _headerFade;
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _headerFade =
        CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerCtrl.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = context.read<WebSocketService>();
      svc.connect();
      _alertSub = svc.priorityAlerts.listen(_onAlert);
    });
  }

  void _onAlert(AgentDecision d) {
    if (!mounted) return;
    if (d.alertId.isNotEmpty && _latestAlert?.alertId == d.alertId) return;
    setState(() => _latestAlert = d);
  }

  void _dismissAlert() {
    if (!mounted) return;
    setState(() => _latestAlert = null);
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    _headerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RivianColors.bg0,
      body: Stack(children: [
        // ── Premium background ────────────────────────────────────
        const Positioned.fill(child: _PremiumBackground()),

        // ── Main layout ───────────────────────────────────────────
        SafeArea(
          child: Column(children: [
            FadeTransition(
              opacity: _headerFade,
              child: const _RivianHeader(),
            ),

            _ConnectionPill(),
            const SizedBox(height: 12),

            _TabNavBar(
              index: _navIndex,
              onTap: (i) => setState(() => _navIndex = i),
            ),
            const SizedBox(height: 6),

            // Thin green accent line between nav and content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.transparent,
                    RivianColors.green.withValues(alpha: 0.25),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 2),

            // ── Inline alert strip — no popup, no animation ───────────
            if (_latestAlert != null)
              _AlertStrip(
                alert: _latestAlert!,
                onDismiss: _dismissAlert,
              ),

            Expanded(
              child: IndexedStack(
                index: _navIndex,
                children: const [
                  _OverviewTab(),
                  AnalyticsScreen(),
                  HistoryScreen(),
                  ServiceScreen(),
                ],
              ),
            ),
          ]),
        ),

        // ── Demo Mode badge (visible only when backend says demo_mode=true) ──
        const Positioned(top: 12, right: 12, child: _DemoBadge()),
      ]),
    );
  }
}

class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    if (!ws.demoMode) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Clipboard.setData(const ClipboardData(
            text: 'https://github.com/haroldflint63/RivianVehicleIntelligence',
          ));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Repo link copied'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: RivianColors.green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: RivianColors.green.withValues(alpha: 0.55),
              width: 1,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: RivianColors.green,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: RivianColors.green.withValues(alpha: 0.7),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'DEMO MODE · v${ws.serverVersion}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: Colors.white,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Premium dot-grid background with radial aurora glow ──────────────
class _PremiumBackground extends StatelessWidget {
  const _PremiumBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Radial glow from top-center — subtle forest-green aurora
      Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -1.6),
            radius: 1.4,
            colors: [
              Color(0xFF0E2419), // very dark forest
              Color(0xFF060810), // deep space
            ],
            stops: [0.0, 0.65],
          ),
        ),
      ),
      // Fine dot matrix
      Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),
    ]);
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF1E2D40).withValues(alpha: 0.5);
    const step = 28.0;
    for (double x = step / 2; x < size.width; x += step) {
      for (double y = step / 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.0, p);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Tab navigation bar — animated sliding pill ────────────────────────
class _TabNavBar extends StatefulWidget {
  const _TabNavBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _tabs = [
    (Icons.dashboard_rounded, 'Overview'),
    (Icons.show_chart_rounded, 'Analytics'),
    (Icons.history_rounded, 'History'),
    (Icons.build_circle_rounded, 'Service'),
  ];

  @override
  State<_TabNavBar> createState() => _TabNavBarState();
}

class _TabNavBarState extends State<_TabNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
        value: 1.0);
    _from = widget.index.toDouble();
  }

  @override
  void didUpdateWidget(_TabNavBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      // Capture current interpolated position so mid-flight taps feel natural
      final t = Curves.easeInOutCubic.transform(_ctrl.value);
      _from = _from + (old.index - _from) * t;
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(builder: (_, constraints) {
        final tabW = constraints.maxWidth / _TabNavBar._tabs.length;
        return Container(
          height: 50,
          decoration: BoxDecoration(
            color: RivianColors.bg1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: RivianColors.border, width: 1),
          ),
          child: Stack(children: [
            // Sliding pill indicator
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final t = Curves.easeInOutCubic.transform(_ctrl.value);
                final x = _from + (widget.index - _from) * t;
                return Positioned(
                  left: x * tabW + 4,
                  top: 4,
                  width: tabW - 8,
                  height: 42,
                  child: Container(
                    decoration: BoxDecoration(
                      color: RivianColors.bg3,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: RivianColors.green.withValues(alpha: 0.18),
                          width: 1),
                      boxShadow: [
                        BoxShadow(
                            color: RivianColors.green.withValues(alpha: 0.06),
                            blurRadius: 12,
                            spreadRadius: 0),
                      ],
                    ),
                  ),
                );
              },
            ),
            // Tab labels
            Row(
              children: _TabNavBar._tabs.asMap().entries.map((e) {
                final sel = e.key == widget.index;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onTap(e.key),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          e.value.$1,
                          size: 14,
                          color: sel
                              ? RivianColors.green
                              : RivianColors.textTertiary,
                        ),
                        const SizedBox(height: 3),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: RivianText.caption.copyWith(
                            fontSize: 9,
                            letterSpacing: 0.4,
                            color: sel
                                ? RivianColors.textPrimary
                                : RivianColors.textTertiary,
                            fontWeight:
                                sel ? FontWeight.w700 : FontWeight.w500,
                          ),
                          child: Text(e.value.$2),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ]),
        );
      }),
    );
  }
}

// ── Overview tab ──────────────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: const SliverToBoxAdapter(child: _HeroVehicleCapsule()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(child: _LlmReportSection()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          sliver: SliverToBoxAdapter(child: _RangeHealthRow()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(child: _TelemetrySection()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(child: BatteryIntelligenceCard()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(child: EfficiencyScoreCard()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(child: PredictiveMaintenanceCard()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
          sliver: SliverToBoxAdapter(child: _AgentSection()),
        ),
      ],
    );
  }
}

// ── Hero vehicle capsule — Rivian HMI-inspired glass card -------------
class _HeroVehicleCapsule extends StatelessWidget {
  const _HeroVehicleCapsule();

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(builder: (_, svc, __) {
      final t = svc.latestPayload?.telemetry;
      final range = svc.estimatedRangeMiles;
      final soc = (t?.batteryPercent ?? 0).clamp(0, 100).toDouble();
      final motor = t?.motorTemp ?? 0;
      final outside = t?.outsideTemp ?? 0;
      final cabin = t?.cabinTemp ?? 0;
      final health = svc.healthStatus;

      return Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF101828), Color(0xFF0A1913)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: RivianColors.borderBright, width: 1),
          boxShadow: RivianShadows.card,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Header row
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: RivianColors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: RivianColors.green.withValues(alpha: 0.35), width: 1),
                    ),
                    child: Row(children: [
                      const Icon(Icons.directions_car_filled_rounded,
                          color: RivianColors.green, size: 14),
                      const SizedBox(width: 6),
                      Text('R1T · AWD',
                          style: RivianText.caption
                              .copyWith(color: RivianColors.green, fontSize: 9)),
                    ]),
                  ),
                  const Spacer(),
                  _Pill(label: health.isEmpty ? 'Monitoring' : health, color: RivianColors.info),
                ]),

                const SizedBox(height: 14),

                // Range + SOC row
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${range.toStringAsFixed(0)} mi',
                          style: RivianText.displayMd.copyWith(letterSpacing: -1.5)),
                      const SizedBox(height: 2),
                      Row(children: [
                        Icon(Icons.bolt_rounded,
                            color: RivianColors.green, size: 14),
                        const SizedBox(width: 6),
                        Text('Battery ${soc.toStringAsFixed(0)}% · Spring Green mode',
                            style: RivianText.caption
                                .copyWith(color: RivianColors.textSecondary, fontSize: 9)),
                      ]),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [RivianColors.green.withValues(alpha: 0.4), RivianColors.greenDim],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: RivianColors.borderBright, width: 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Drive',
                          style: RivianText.caption
                              .copyWith(color: RivianColors.textTertiary, fontSize: 8)),
                      const SizedBox(height: 4),
                      Text('All-Purpose',
                          style: RivianText.headingMd.copyWith(fontSize: 12)),
                      Text('Regen: Standard',
                          style: RivianText.caption
                              .copyWith(color: RivianColors.textSecondary, fontSize: 9)),
                    ]),
                  )
                ]),

                const SizedBox(height: 14),

                // Quick action bar
                Row(children: [
                  _ActionButton(icon: Icons.lock_outline, label: 'Lock'),
                  const SizedBox(width: 10),
                  _ActionButton(icon: Icons.light_mode_outlined, label: 'Flash'),
                  const SizedBox(width: 10),
                  _ActionButton(icon: Icons.campaign_outlined, label: 'Honk'),
                  const SizedBox(width: 10),
                  _ActionButton(icon: Icons.bedtime_outlined, label: 'Camp'),
                  const Spacer(),
                  _Pill(label: 'Route Optimized', color: RivianColors.green),
                ]),

                const SizedBox(height: 12),

                // Environmental + thermal chips
                Wrap(spacing: 10, runSpacing: 8, children: [
                  _MiniChip(icon: Icons.thermostat_rounded, label: 'Motor',
                      value: '${motor.toStringAsFixed(0)}°F', color: _motorColor(motor)),
                  _MiniChip(icon: Icons.ac_unit_rounded, label: 'Outside',
                      value: '${outside.toStringAsFixed(0)}°F', color: RivianColors.ice),
                  _MiniChip(icon: Icons.air_rounded, label: 'Cabin',
                      value: '${cabin.toStringAsFixed(0)}°F', color: RivianColors.info),
                  _MiniChip(icon: Icons.shield_rounded, label: 'Health',
                      value: svc.healthScore.toStringAsFixed(0), color: RivianColors.green),
                ]),
              ]),
            ),
          ),
        ),
      );
    });
  }

  static Color _motorColor(double t) {
    if (t >= 230) return RivianColors.danger;
    if (t >= 200) return RivianColors.warning;
    return RivianColors.green;
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: RivianColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RivianColors.borderBright, width: 1),
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: RivianColors.textSecondary),
        const SizedBox(width: 6),
        Text(label,
            style: RivianText.caption
                .copyWith(color: RivianColors.textSecondary, fontSize: 9)),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Text(label,
          style: RivianText.caption.copyWith(color: color, fontSize: 9)),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: RivianColors.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RivianColors.border, width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: RivianText.caption
                .copyWith(color: RivianColors.textTertiary, fontSize: 9)),
        const SizedBox(width: 6),
        Text(value,
            style: RivianText.caption.copyWith(color: color, fontSize: 9)),
      ]),
    );
  }
}

class _RangeHealthRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(builder: (_, svc, __) {
      final maint = svc.latestPayload?.decisions
          .where((d) => d.agentName == 'PredictiveMaintenanceAgent')
          .firstOrNull;
      final anomalyRate =
          (maint?.metadata['anomaly_rate_per_hour'] as num?)?.toDouble() ?? 0.0;
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: RangeGaugeCard(miles: svc.estimatedRangeMiles)),
        const SizedBox(width: 12),
        Expanded(
          child: HealthScoreCard(
            score: svc.healthScore,
            status: svc.healthStatus,
            action: svc.healthAction,
            anomalyRatePerHour: anomalyRate,
          ),
        ),
      ]);
    });
  }
}

class _LlmReportSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(builder: (_, svc, __) {
      final loading = svc.connectionState != WsState.connected ||
          svc.latestPayload == null;
      return StatusReportCard(report: svc.lastStatusReport, isLoading: loading);
    });
  }
}

class _TelemetrySection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(builder: (_, svc, __) {
      final p = svc.latestPayload;
      if (p == null) return const _SkeletonGrid();
      return TelemetryGrid(telemetry: p.telemetry, history: svc.telemetryHistory);
    });
  }
}

class _AgentSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(builder: (_, svc, __) {
      final p = svc.latestPayload;
      if (p == null) return const SizedBox.shrink();
      return AgentDecisionsPanel(decisions: p.decisions);
    });
  }
}

// ── Rivian header ─────────────────────────────────────────────────────
class _RivianHeader extends StatelessWidget {
  const _RivianHeader();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Logo mark with glow
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6BE09B), Color(0xFF3AA868)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x906BE09B),
                    blurRadius: 22,
                    spreadRadius: -4,
                    offset: Offset(0, 6)),
              ],
            ),
            child: const Center(
              child: Text('R',
                  style: TextStyle(
                      color: Color(0xFF030D07),
                      fontWeight: FontWeight.w900,
                      fontSize: 23,
                      letterSpacing: -1.0)),
            ),
          ),
          const SizedBox(width: 14),

          // Brand title
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RIVIAN',
                      style: RivianText.label.copyWith(
                          color: RivianColors.green,
                          letterSpacing: 3.8,
                          fontSize: 10,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text('Vehicle Intelligence',
                      style:
                          RivianText.headingLg.copyWith(letterSpacing: -0.4)),
                  const SizedBox(height: 2),
                  Text('5-AGENT AI PLATFORM',
                      style: RivianText.caption.copyWith(
                          color: RivianColors.textTertiary,
                          letterSpacing: 1.8)),
                ]),
          ),

          // Live clock
          const _LiveClock(),
        ]),
      ),

      // Gradient separator line — signature Rivian accent
      Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              RivianColors.green.withValues(alpha: 0.55),
              RivianColors.green.withValues(alpha: 0.55),
              Colors.transparent,
            ],
            stops: const [0.0, 0.35, 0.65, 1.0],
          ),
        ),
      ),
      const SizedBox(height: 10),
    ]);
  }
}

// ── Live clock with date ──────────────────────────────────────────────
class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late Timer _t;
  String _hhmm = '', _ss = '', _date = '';

  static const _wd = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  static const _mo = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  @override
  void initState() {
    super.initState();
    _tick();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final n = DateTime.now();
    setState(() {
      _hhmm = '${n.hour.toString().padLeft(2, "0")}:'
          '${n.minute.toString().padLeft(2, "0")}';
      _ss = ':${n.second.toString().padLeft(2, "0")}';
      _date = '${_wd[n.weekday - 1]}  ${n.day}  ${_mo[n.month - 1]}';
    });
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(_hhmm,
            style: RivianText.headingMd.copyWith(
                fontSize: 17,
                letterSpacing: -0.5,
                fontFeatures: [const FontFeature.tabularFigures()])),
        Text(_ss,
            style: RivianText.headingMd.copyWith(
                fontSize: 12,
                letterSpacing: -0.3,
                color: RivianColors.textTertiary,
                fontFeatures: [const FontFeature.tabularFigures()])),
      ]),
      const SizedBox(height: 2),
      Text(_date,
          style: RivianText.caption
              .copyWith(color: RivianColors.textTertiary, letterSpacing: 1.5)),
    ]);
  }
}

// ── Connection pill ───────────────────────────────────────────────────
class _ConnectionPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(builder: (_, svc, __) {
      final (color, icon, label) = switch (svc.connectionState) {
        WsState.connected =>
          (RivianColors.green, Icons.radio_button_checked, 'Live'),
        WsState.connecting =>
          (RivianColors.warning, Icons.sync_rounded, 'Connecting'),
        WsState.error =>
          (RivianColors.danger, Icons.wifi_off_rounded, 'Error'),
        WsState.disconnected =>
          (RivianColors.textTertiary, Icons.circle_outlined, 'Offline'),
      };

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(100),
              border:
                  Border.all(color: color.withValues(alpha: 0.25), width: 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _PulseDot(color: color, active: svc.connectionState == WsState.connected),
              const SizedBox(width: 7),
              Text(label,
                  style: RivianText.caption.copyWith(
                      color: color, fontWeight: FontWeight.w700, fontSize: 9)),
              if (svc.connectionState == WsState.connected) ...[
                const SizedBox(width: 8),
                Container(
                    width: 1,
                    height: 10,
                    color: color.withValues(alpha: 0.25)),
                const SizedBox(width: 8),
                Text('ws://localhost:8765',
                    style: RivianText.caption
                        .copyWith(color: color.withValues(alpha: 0.55))),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          if (svc.connectionState == WsState.connected)
            Text('${svc.latestPayload?.decisions.length ?? 0} signals',
                style: RivianText.caption
                    .copyWith(color: RivianColors.textTertiary)),
        ]),
      );
    });
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, this.active = true});
  final Color color;
  final bool active;
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _a = Tween(begin: 0.35, end: 1.0)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Container(width: 6, height: 6,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle));
    }
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) => Container(
        width: 6, height: 6,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: widget.color.withValues(alpha: _a.value * 0.7),
                blurRadius: 6)
          ],
        ),
      ),
    );
  }
}

// ── Skeleton loading grid ─────────────────────────────────────────────
class _SkeletonGrid extends StatefulWidget {
  const _SkeletonGrid();
  @override
  State<_SkeletonGrid> createState() => _SkeletonGridState();
}

class _SkeletonGridState extends State<_SkeletonGrid>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _a = Tween(begin: -1.5, end: 1.5)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
        children: List.generate(4, (_) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment(_a.value - 1, 0),
              end: Alignment(_a.value, 0),
              colors: const [
                Color(0xFF0C1018),
                Color(0xFF1C2535),
                Color(0xFF0C1018),
              ],
            ),
          ),
        )),
      ),
    );
  }
}

// ── Inline alert strip — replaces the old floating popup ─────────────
// Sits in the layout between the nav bar and content.
// Static, no pulse, no animation. Tap X to dismiss.
class _AlertStrip extends StatelessWidget {
  const _AlertStrip({required this.alert, required this.onDismiss});
  final AgentDecision alert;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isCrit = alert.severity == Severity.critical;
    final color = isCrit ? RivianColors.danger : RivianColors.warning;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(children: [
        Icon(
          isCrit
              ? Icons.local_fire_department_rounded
              : Icons.warning_amber_rounded,
          color: color,
          size: 14,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            alert.message,
            style: RivianText.caption.copyWith(
                color: RivianColors.textSecondary, height: 1.3, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onDismiss,
          child: Icon(Icons.close_rounded,
              color: RivianColors.textTertiary, size: 14),
        ),
      ]),
    );
  }
}
