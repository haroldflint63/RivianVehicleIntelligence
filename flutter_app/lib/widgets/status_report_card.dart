// ── lib/widgets/status_report_card.dart ──────────────────────────────
import 'package:flutter/material.dart';
import '../main.dart';

class StatusReportCard extends StatefulWidget {
  const StatusReportCard(
      {super.key, required this.report, required this.isLoading});
  final String report;
  final bool isLoading;

  @override
  State<StatusReportCard> createState() => _StatusReportCardState();
}

class _StatusReportCardState extends State<StatusReportCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimCtrl;
  late Animation<double> _shim;
  String _displayed = '';

  @override
  void initState() {
    super.initState();
    _shimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
    _shim = Tween(begin: -1.5, end: 1.5)
        .animate(CurvedAnimation(parent: _shimCtrl, curve: Curves.easeInOut));
    _displayed = widget.report;
  }

  @override
  void didUpdateWidget(StatusReportCard old) {
    super.didUpdateWidget(old);
    if (old.report != widget.report) _displayed = widget.report;
  }

  @override
  void dispose() {
    _shimCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: RivianColors.bg1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RivianColors.borderBright, width: 1),
        boxShadow: RivianShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Top accent bar — gradient from info to transparent
        Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              RivianColors.info.withValues(alpha: 0.9),
              RivianColors.info.withValues(alpha: 0.0),
            ]),
          ),
        ),

        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                RivianColors.infoDim.withValues(alpha: 0.6),
                Colors.transparent,
              ],
            ),
            border: Border(
              bottom: BorderSide(color: RivianColors.border, width: 1),
            ),
          ),
          child: Row(children: [
            // AI icon badge
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    RivianColors.info.withValues(alpha: 0.18),
                    RivianColors.infoDim,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                    color: RivianColors.info.withValues(alpha: 0.2), width: 1),
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  color: RivianColors.info, size: 16),
            ),
            const SizedBox(width: 14),

            // Labels
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI STATUS REPORT',
                        style: RivianText.label.copyWith(
                            color: RivianColors.info,
                            letterSpacing: 1.4,
                            fontSize: 9)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Container(
                        width: 5, height: 5,
                        decoration: const BoxDecoration(
                          color: Color(0xFFBF5AF2),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text('Groq · llama-3.3-70b-versatile',
                          style: RivianText.caption
                              .copyWith(color: RivianColors.textTertiary)),
                    ]),
                  ]),
            ),

            // Pulse status dot
            _PulseDot(
                color: widget.isLoading
                    ? RivianColors.warning
                    : RivianColors.green),
          ]),
        ),

        // Body
        Padding(
          padding: const EdgeInsets.all(20),
          child: widget.isLoading
              ? _Shimmer(animation: _shim)
              : _FadeText(text: _displayed),
        ),
      ]),
    );
  }
}

class _FadeText extends StatefulWidget {
  const _FadeText({required this.text});
  final String text;
  @override
  State<_FadeText> createState() => _FadeTextState();
}

class _FadeTextState extends State<_FadeText>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _f;
  String _t = '';

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _f = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    _t = widget.text;
    _c.forward();
  }

  @override
  void didUpdateWidget(_FadeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _c.reset();
      _t = widget.text;
      _c.forward();
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _f,
        child: Text(_t,
            style: RivianText.bodyLg.copyWith(
                height: 1.7,
                color: RivianColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w400)),
      );
}

class _Shimmer extends StatelessWidget {
  const _Shimmer({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [0, 1, 2].map((i) {
            final widths = [1.0, 0.82, 0.58];
            return Container(
              margin: EdgeInsets.only(bottom: i < 2 ? 10 : 0),
              height: 13,
              width: double.infinity,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: widths[i],
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      begin: Alignment(animation.value - 1, 0),
                      end: Alignment(animation.value, 0),
                      colors: const [
                        Color(0xFF111827),
                        Color(0xFF1C2535),
                        Color(0xFF111827),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});
  final Color color;
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
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _a = Tween(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, __) => Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: widget.color.withValues(alpha: _a.value * 0.75),
                  blurRadius: 8)
            ],
          ),
        ),
      );
}
