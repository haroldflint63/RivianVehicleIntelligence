import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/agent_decision.dart';

/// Quiet bottom-toast alert — slides up from below, auto-dismisses after 6 s.
/// No pulsing, no full-screen takeover. Tap the X or wait for it to fade.
class PriorityAlertOverlay extends StatefulWidget {
  const PriorityAlertOverlay({
    super.key,
    required this.alert,
    this.duration = const Duration(seconds: 6),
    this.onDismiss,
  });
  final AgentDecision alert;
  final Duration duration;
  final VoidCallback? onDismiss;

  @override
  State<PriorityAlertOverlay> createState() => _PriorityAlertOverlayState();
}

class _PriorityAlertOverlayState extends State<PriorityAlertOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    // Slide up from below rather than dropping from top
    _slide = Tween(begin: const Offset(0, 1.5), end: Offset.zero).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _ctrl.reverse().then((_) => widget.onDismiss?.call());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCrit = widget.alert.severity == Severity.critical;
    final color = isCrit ? RivianColors.danger : RivianColors.warning;

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          decoration: BoxDecoration(
            color: RivianColors.bg1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
            boxShadow: [
              BoxShadow(
                color: RivianColors.bg0.withValues(alpha: 0.8),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              // Compact icon
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  isCrit
                      ? Icons.local_fire_department_rounded
                      : Icons.warning_amber_rounded,
                  color: color,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              // Text
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    isCrit ? 'Critical Alert' : 'Priority Alert',
                    style: RivianText.label.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 0.4),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.alert.message,
                    style: RivianText.caption.copyWith(
                        color: RivianColors.textSecondary,
                        height: 1.4,
                        fontSize: 10),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              // Dismiss
              GestureDetector(
                onTap: _dismiss,
                child: Icon(Icons.close_rounded,
                    color: RivianColors.textTertiary, size: 16),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
