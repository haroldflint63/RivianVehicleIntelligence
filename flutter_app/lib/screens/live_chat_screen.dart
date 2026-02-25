// ── lib/screens/live_chat_screen.dart ────────────────────────────────
//
// Rivian Support AI — Live Chat
// Connects to the backend Groq-powered chat agent via WebSocket.
// Vehicle-aware: the AI can see real-time telemetry and give
// contextual advice about the owner's R1T / R1S.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/websocket_service.dart';

// ── Data model ───────────────────────────────────────────────────────

enum _Sender { user, ai, system }

class _ChatMessage {
  final String text;
  final _Sender sender;
  final DateTime time;
  final bool isTyping;

  const _ChatMessage({
    required this.text,
    required this.sender,
    required this.time,
    this.isTyping = false,
  });
}

// ── Screen ───────────────────────────────────────────────────────────

class LiveChatScreen extends StatefulWidget {
  const LiveChatScreen({super.key});

  @override
  State<LiveChatScreen> createState() => _LiveChatScreenState();
}

class _LiveChatScreenState extends State<LiveChatScreen>
    with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  StreamSubscription? _chatSub;
  bool _waitingForReply = false;

  final List<_ChatMessage> _messages = [
    _ChatMessage(
      text: 'Welcome to Rivian Support! I\'m your AI assistant with '
          'real-time access to your vehicle\'s telemetry. Ask me anything '
          'about your R1T — charging, range, service, features, or any '
          'concerns about your vehicle\'s health.',
      sender: _Sender.ai,
      time: DateTime.now(),
    ),
  ];

  // Quick suggestion chips
  static const _suggestions = [
    'What\'s my battery health?',
    'When is my next service due?',
    'How do I maximize range?',
    'Tell me about my warranty',
    'Is my motor temp normal?',
    'How do I use Camp Mode?',
  ];

  @override
  void initState() {
    super.initState();
    final svc = context.read<WebSocketService>();
    _chatSub = svc.chatResponses.listen(_onChatResponse);
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChatResponse(Map<String, dynamic> msg) {
    final reply = msg['message'] as String? ?? '';
    if (reply.isEmpty) return;

    setState(() {
      // Remove typing indicator
      _messages.removeWhere((m) => m.isTyping);
      _messages.add(_ChatMessage(
        text: reply,
        sender: _Sender.ai,
        time: DateTime.now(),
      ));
      _waitingForReply = false;
    });
    _scrollToBottom();
  }

  void _sendMessage([String? override]) {
    final text = (override ?? _controller.text).trim();
    if (text.isEmpty || _waitingForReply) return;

    final svc = context.read<WebSocketService>();

    setState(() {
      _messages.add(_ChatMessage(
        text: text,
        sender: _Sender.user,
        time: DateTime.now(),
      ));
      _messages.add(_ChatMessage(
        text: '',
        sender: _Sender.ai,
        time: DateTime.now(),
        isTyping: true,
      ));
      _waitingForReply = true;
    });

    _controller.clear();
    svc.sendChat(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<WebSocketService>();
    final connected = svc.connectionState == WsState.connected;

    return Scaffold(
      backgroundColor: RivianColors.bg0,
      body: Column(
        children: [
          // ── Header bar ──────────────────────────────────────────
          _ChatHeader(
            connected: connected,
            onBack: () => Navigator.of(context).pop(),
          ),

          // ── Connection warning ──────────────────────────────────
          if (!connected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: RivianColors.warning.withValues(alpha: 0.1),
              child: Row(children: [
                Icon(Icons.wifi_off_rounded,
                    size: 14, color: RivianColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Connecting to Rivian Intelligence Server… '
                    'Chat requires an active connection.',
                    style: RivianText.caption.copyWith(
                        color: RivianColors.warning, fontSize: 10),
                  ),
                ),
              ]),
            ),

          // ── Vehicle context strip ───────────────────────────────
          _VehicleContextStrip(svc: svc),

          // ── Messages ────────────────────────────────────────────
          Expanded(
            child: _messages.length <= 1
                ? _WelcomeView(
                    suggestions: _suggestions,
                    onTap: _sendMessage,
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) =>
                        _MessageBubble(message: _messages[i]),
                  ),
          ),

          // ── Suggestion chips (show when few messages) ───────────
          if (_messages.length <= 3 && !_waitingForReply)
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => _SuggestionChip(
                  label: _suggestions[i],
                  onTap: () => _sendMessage(_suggestions[i]),
                ),
              ),
            ),

          if (_messages.length <= 3 && !_waitingForReply)
            const SizedBox(height: 8),

          // ── Input bar ───────────────────────────────────────────
          _InputBar(
            controller: _controller,
            focusNode: _focusNode,
            enabled: connected && !_waitingForReply,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
//  WIDGETS
// ═════════════════════════════════════════════════════════════════════

// ── Header ───────────────────────────────────────────────────────────

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.connected, required this.onBack});
  final bool connected;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          8, MediaQuery.of(context).padding.top + 8, 16, 12),
      decoration: BoxDecoration(
        color: RivianColors.bg1,
        border:
            Border(bottom: BorderSide(color: RivianColors.border, width: 1)),
      ),
      child: Row(children: [
        // Back button
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_rounded,
              size: 18, color: RivianColors.textPrimary),
          splashRadius: 20,
        ),
        // Avatar
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                RivianColors.green,
                RivianColors.green.withValues(alpha: 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Icon(Icons.support_agent_rounded,
                size: 20, color: RivianColors.bg0),
          ),
        ),
        const SizedBox(width: 12),
        // Title
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rivian Support AI',
                  style: RivianText.headingMd.copyWith(fontSize: 14)),
              const SizedBox(height: 2),
              Row(children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: connected
                        ? RivianColors.green
                        : RivianColors.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  connected
                      ? 'Online · Vehicle-Aware AI'
                      : 'Connecting…',
                  style: RivianText.caption.copyWith(
                    color: connected
                        ? RivianColors.green
                        : RivianColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ]),
            ],
          ),
        ),
        // Phone button — real Rivian number
        _HeaderAction(
          icon: Icons.phone_rounded,
          tooltip: 'Call 1-888-748-4261',
          onTap: () {
            Clipboard.setData(
                const ClipboardData(text: '18887484261'));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Rivian Support: 1-888-748-4261 copied',
                  style: RivianText.bodySm
                      .copyWith(color: RivianColors.textPrimary)),
              backgroundColor: RivianColors.bg2,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ));
          },
        ),
        const SizedBox(width: 4),
        // Info button
        _HeaderAction(
          icon: Icons.info_outline_rounded,
          tooltip: 'Chat info',
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => _ChatInfoDialog(),
            );
          },
        ),
      ]),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction(
      {required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: RivianColors.bg2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: RivianColors.textSecondary),
          ),
        ),
      );
}

// ── Vehicle context strip ────────────────────────────────────────────

class _VehicleContextStrip extends StatelessWidget {
  const _VehicleContextStrip({required this.svc});
  final WebSocketService svc;

  @override
  Widget build(BuildContext context) {
    final tel = svc.latestPayload?.telemetry;
    if (tel == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: RivianColors.green.withValues(alpha: 0.04),
      child: Row(children: [
        Icon(Icons.electric_car_rounded,
            size: 13, color: RivianColors.green.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        _CtxChip(
            icon: Icons.battery_charging_full_rounded,
            value: '${tel.batteryPercent.toStringAsFixed(0)}%'),
        const SizedBox(width: 12),
        _CtxChip(
            icon: Icons.thermostat_rounded,
            value: '${tel.motorTemp.toStringAsFixed(0)}°F'),
        const SizedBox(width: 12),
        _CtxChip(
            icon: Icons.speed_rounded,
            value: '${tel.vehicleSpeed.toStringAsFixed(0)} mph'),
        const SizedBox(width: 12),
        _CtxChip(
            icon: Icons.route_rounded,
            value: '${svc.estimatedRangeMiles.toStringAsFixed(0)} mi'),
        const Spacer(),
        Text('LIVE',
            style: RivianText.caption.copyWith(
                color: RivianColors.green,
                fontSize: 8,
                fontWeight: FontWeight.w800)),
        const SizedBox(width: 4),
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: RivianColors.green,
            shape: BoxShape.circle,
          ),
        ),
      ]),
    );
  }
}

class _CtxChip extends StatelessWidget {
  const _CtxChip({required this.icon, required this.value});
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 10, color: RivianColors.textTertiary),
        const SizedBox(width: 3),
        Text(value,
            style: RivianText.caption.copyWith(
                color: RivianColors.textSecondary, fontSize: 9)),
      ]);
}

// ── Message bubble ───────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isTyping) return _TypingIndicator();

    final isUser = message.sender == _Sender.user;
    final isSystem = message.sender == _Sender.system;

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: RivianColors.bg2,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(message.text,
                style: RivianText.caption
                    .copyWith(color: RivianColors.textTertiary, fontSize: 9)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            // AI avatar
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: BoxDecoration(
                color: RivianColors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(Icons.support_agent_rounded,
                    size: 14, color: RivianColors.green),
              ),
            ),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? RivianColors.green.withValues(alpha: 0.15)
                    : RivianColors.bg1,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: Border.all(
                  color: isUser
                      ? RivianColors.green.withValues(alpha: 0.25)
                      : RivianColors.border,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message.text,
                    style: RivianText.bodySm.copyWith(
                      color: RivianColors.textPrimary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.time),
                    style: RivianText.caption.copyWith(
                      color: RivianColors.textTertiary,
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(left: 8, bottom: 2),
              decoration: BoxDecoration(
                color: RivianColors.info.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(Icons.person_rounded,
                    size: 14, color: RivianColors.info),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $ampm';
  }
}

// ── Typing indicator ─────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: RivianColors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Icon(Icons.support_agent_rounded,
                  size: 14, color: RivianColors.green),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: RivianColors.bg1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: RivianColors.border, width: 1),
            ),
            child: AnimatedBuilder(
              animation: _anim,
              builder: (ctx, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final delay = i * 0.25;
                  final t = ((_anim.value - delay) % 1.0).clamp(0.0, 1.0);
                  final y = -4.0 * (t < 0.5 ? t * 2 : (1 - t) * 2);
                  return Transform.translate(
                    offset: Offset(0, y),
                    child: Container(
                      width: 7,
                      height: 7,
                      margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                      decoration: BoxDecoration(
                        color: RivianColors.green
                            .withValues(alpha: 0.3 + 0.5 * (1 - t)),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('Rivian AI is thinking…',
              style: RivianText.caption.copyWith(
                  color: RivianColors.textTertiary, fontSize: 9)),
        ],
      ),
    );
  }
}

// ── Welcome view (initial state) ─────────────────────────────────────

class _WelcomeView extends StatelessWidget {
  const _WelcomeView({required this.suggestions, required this.onTap});
  final List<String> suggestions;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 20),
        // AI message (first message)
        _MessageBubble(
          message: _ChatMessage(
            text: 'Welcome to Rivian Support! I\'m your AI assistant with '
                'real-time access to your vehicle\'s telemetry. Ask me anything '
                'about your R1T — charging, range, service, features, or any '
                'concerns about your vehicle\'s health.',
            sender: _Sender.ai,
            time: DateTime.now(),
          ),
        ),
        const SizedBox(height: 24),
        // Quick actions grid
        Text('SUGGESTED QUESTIONS',
            style: RivianText.label.copyWith(
                color: RivianColors.textTertiary,
                letterSpacing: 1.4,
                fontSize: 9)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestions.map((s) => _QuickActionCard(
            label: s,
            onTap: () => onTap(s),
          )).toList(),
        ),
        const SizedBox(height: 30),
        // Info footer
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: RivianColors.bg1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: RivianColors.border, width: 1),
          ),
          child: Row(children: [
            Icon(Icons.verified_user_rounded,
                size: 14, color: RivianColors.green.withValues(alpha: 0.6)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'This AI has access to your vehicle\'s live telemetry and can '
                'provide personalized insights. For safety-critical issues, '
                'always contact Rivian at 1-888-748-4261.',
                style: RivianText.caption.copyWith(
                    color: RivianColors.textTertiary,
                    fontSize: 9,
                    height: 1.5),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _QuickActionCard extends StatefulWidget {
  const _QuickActionCard({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered
                ? RivianColors.green.withValues(alpha: 0.08)
                : RivianColors.bg1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? RivianColors.green.withValues(alpha: 0.3)
                  : RivianColors.border,
              width: 1,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 12,
                color: _hovered
                    ? RivianColors.green
                    : RivianColors.textTertiary),
            const SizedBox(width: 8),
            Text(widget.label,
                style: RivianText.bodySm.copyWith(
                    color: _hovered
                        ? RivianColors.green
                        : RivianColors.textSecondary,
                    fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}

// ── Suggestion chip ──────────────────────────────────────────────────

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: RivianColors.bg1,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: RivianColors.border, width: 1),
          ),
          child: Text(label,
              style: RivianText.caption.copyWith(
                  color: RivianColors.textSecondary, fontSize: 10)),
        ),
      );
}

// ── Input bar ────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSend,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final void Function([String?]) onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 12, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: RivianColors.bg1,
        border:
            Border(top: BorderSide(color: RivianColors.border, width: 1)),
      ),
      child: Row(children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: RivianColors.bg0,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                  color: RivianColors.border.withValues(alpha: 0.5), width: 1),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              style: RivianText.bodySm.copyWith(
                  color: RivianColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: enabled
                    ? 'Ask Rivian Support AI…'
                    : 'Waiting for response…',
                hintStyle: RivianText.bodySm.copyWith(
                    color: RivianColors.textTertiary, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                isDense: true,
              ),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: enabled ? () => onSend() : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: enabled
                  ? RivianColors.green
                  : RivianColors.green.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Icon(Icons.arrow_upward_rounded,
                  size: 20, color: RivianColors.bg0),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Chat info dialog ─────────────────────────────────────────────────

class _ChatInfoDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: RivianColors.bg1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: RivianColors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Icon(Icons.support_agent_rounded,
                  size: 24, color: RivianColors.green),
            ),
          ),
          const SizedBox(height: 16),
          Text('Rivian Support AI',
              style: RivianText.headingLg.copyWith(fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            'Powered by AI with real-time vehicle telemetry access. '
            'This assistant can help with questions about your Rivian, '
            'interpret vehicle data, and provide maintenance guidance.',
            style: RivianText.bodySm
                .copyWith(color: RivianColors.textSecondary, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          _InfoRow(
              icon: Icons.phone_rounded,
              label: 'Rivian Support',
              value: '1-888-RIVIAN-1 (1-888-748-4261)'),
          const SizedBox(height: 10),
          _InfoRow(
              icon: Icons.language_rounded,
              label: 'Online Support',
              value: 'rivian.com/support'),
          const SizedBox(height: 10),
          _InfoRow(
              icon: Icons.access_time_rounded,
              label: 'Availability',
              value: '24/7 Roadside & Support'),
          const SizedBox(height: 10),
          _InfoRow(
              icon: Icons.shield_rounded,
              label: 'Battery Warranty',
              value: '8 yr / 175,000 mi'),
          const SizedBox(height: 10),
          _InfoRow(
              icon: Icons.verified_rounded,
              label: 'Comprehensive',
              value: '5 yr / 60,000 mi'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: RivianColors.green.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text('Got it',
                  style: RivianText.headingMd
                      .copyWith(color: RivianColors.green, fontSize: 13)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 14, color: RivianColors.textTertiary),
        const SizedBox(width: 10),
        Text('$label  ',
            style: RivianText.caption.copyWith(
                color: RivianColors.textTertiary, fontSize: 10)),
        Expanded(
          child: Text(value,
              style: RivianText.bodySm.copyWith(
                  color: RivianColors.textPrimary, fontSize: 11),
              textAlign: TextAlign.right),
        ),
      ]);
}
