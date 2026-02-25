// ── lib/services/websocket_service.dart ─────────────────────────────
//
// Open-source integrations
// • rivian/ai-sast  (Apache 2.0) — sendFeedback() → ALERT_FEEDBACK command
//                                   handles FEEDBACK_RESULT from server
// • rivian/odxtools (MIT)        — alertHistory shows dtcCode + cvssScore

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/agent_decision.dart';
import '../models/telemetry_model.dart';

export '../models/agent_decision.dart' show AlertFeedback;

enum WsState { connecting, connected, disconnected, error }

/// Parsed payload emitted to listeners on each server tick.
class VehiclePayload {
  final TelemetryData telemetry;
  final List<AgentDecision> decisions;
  final double timestamp;
  final Map<String, dynamic> dbStats;

  const VehiclePayload({
    required this.telemetry,
    required this.decisions,
    required this.timestamp,
    this.dbStats = const {},
  });
}

class WebSocketService extends ChangeNotifier {
  WebSocketService(this._url);

  final String _url;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  static const int _maxTelemetryHistory = 60;
  static const int _maxAlertHistory     = 150;

  // ── observable state ─────────────────────────────────────────────
  WsState connectionState = WsState.disconnected;
  VehiclePayload? latestPayload;
  String lastStatusReport = 'Connecting to Vehicle Intelligence Server…';
  String? errorMessage;

  /// Rolling 60-tick telemetry history for sparkline charts.
  final List<TelemetryData> telemetryHistory = [];

  /// Newest-first ordered log of WARNING + CRITICAL decisions.
  final List<AgentDecision> alertHistory = [];

  /// Timestamp of the last PRIORITY_ALERT emitted to the overlay.
  /// Enforces a 2-minute quiet period so alerts don't spam the UI.
  DateTime? _lastAlertEmitted;
  static const _alertCooldown = Duration(minutes: 2);

  /// DB stats received from server (rivian/ai-sast pattern).
  Map<String, dynamic> dbStats = {};

  // ── public streams ────────────────────────────────────────────────
  final _alertCtrl   = StreamController<AgentDecision>.broadcast();
  final _feedbackCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _chatCtrl     = StreamController<Map<String, dynamic>>.broadcast();

  Stream<AgentDecision>      get priorityAlerts  => _alertCtrl.stream;
  /// Emits FEEDBACK_RESULT payload from server.
  Stream<Map<String, dynamic>> get feedbackResults => _feedbackCtrl.stream;
  /// Emits CHAT_RESPONSE payloads from server.
  Stream<Map<String, dynamic>> get chatResponses => _chatCtrl.stream;

  // ── computed properties ───────────────────────────────────────────
  double get estimatedRangeMiles {
    final d = latestPayload?.decisions
        .where((d) => d.agentName == 'RangePredictionAgent')
        .firstOrNull;
    return (d?.metadata['estimated_range_miles'] as num?)?.toDouble() ?? 0.0;
  }

  double get healthScore {
    final d = latestPayload?.decisions
        .where((d) => d.agentName == 'PredictiveMaintenanceAgent')
        .firstOrNull;
    return (d?.metadata['health_score'] as num?)?.toDouble() ?? 100.0;
  }

  String get healthStatus {
    final d = latestPayload?.decisions
        .where((d) => d.agentName == 'PredictiveMaintenanceAgent')
        .firstOrNull;
    return d?.metadata['status'] as String? ?? 'HEALTHY';
  }

  String get healthAction {
    final d = latestPayload?.decisions
        .where((d) => d.agentName == 'PredictiveMaintenanceAgent')
        .firstOrNull;
    return d?.metadata['action'] as String? ?? 'Monitoring systems…';
  }

  // ── connect / disconnect ──────────────────────────────────────────

  Future<void> connect() async {
    if (connectionState == WsState.connected) return;
    _updateState(WsState.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_url));
      await _channel!.ready;
      _updateState(WsState.connected);
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
    } catch (e) {
      errorMessage = e.toString();
      _updateState(WsState.error);
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _sub?.cancel();
    _channel?.sink.close();
    _updateState(WsState.disconnected);
  }

  /// Send any typed command to the server.
  void sendCommand(String type, [Map<String, dynamic>? data]) {
    if (connectionState != WsState.connected) return;
    final payload = <String, dynamic>{'type': type, ...?data};
    _channel?.sink.add(jsonEncode(payload));
    debugPrint('[WS] Command sent: $type');
  }

  /// Send operator feedback for an alert (rivian/ai-sast pattern).
  /// [status] is 'confirmed_alert' or 'false_positive'.
  void sendFeedback({
    required String alertId,
    required String status,
    String comment = '',
  }) {
    sendCommand('ALERT_FEEDBACK', {
      'alert_id': alertId,
      'status':   status,
      'comment':  comment,
    });
    debugPrint('[WS] Feedback sent: $alertId → $status');
  }

  /// Send a chat message to the Rivian Support AI.
  void sendChat(String message, {String conversationId = 'default'}) {
    sendCommand('CHAT', {
      'message': message,
      'conversation_id': conversationId,
    });
    debugPrint('[WS] Chat sent: ${message.length > 50 ? message.substring(0, 50) : message}');
  }

  /// Mark alert in local [alertHistory] with operator feedback.
  void _applyLocalFeedback(String alertId, AlertFeedback fb) {
    final idx = alertHistory.indexWhere((a) => a.alertId == alertId);
    if (idx >= 0) {
      alertHistory[idx] = alertHistory[idx].withFeedback(fb);
    }
  }

  // ── private message handling ──────────────────────────────────────

  void _onMessage(dynamic raw) {
    try {
      final Map<String, dynamic> msg = jsonDecode(raw as String);
      final type = msg['type'] as String?;

      switch (type) {
        case 'HANDSHAKE':
          debugPrint('[WS] Handshake v${msg['version']}: ${msg['message']}');
          final features = (msg['features'] as List?)?.cast<String>() ?? [];
          debugPrint('[WS] Server features: ${features.join(', ')}');

        case 'TELEMETRY_UPDATE':
          final telemetry =
              TelemetryData.fromJson(msg['telemetry'] as Map<String, dynamic>);

          // Server now sends key "decisions" (not "agent_decisions").
          final rawDecisions = msg['decisions'] as List<dynamic>? ?? [];
          final decisions = rawDecisions
              .map((d) => AgentDecision.fromJson(d as Map<String, dynamic>))
              .toList();

          // Update telemetry sparkline buffer.
          telemetryHistory.add(telemetry);
          if (telemetryHistory.length > _maxTelemetryHistory) {
            telemetryHistory.removeAt(0);
          }

          // Extract LLM status report.
          final reportDecision = decisions.firstWhere(
            (d) => d.isStatusReport,
            orElse: () => AgentDecision(
              agentName:    'VehicleStatusReporterAgent',
              decisionType: DecisionType.statusReport,
              message:      lastStatusReport,
              severity:     Severity.info,
              timestamp:    DateTime.now().millisecondsSinceEpoch / 1000,
              metadata:     const {},
            ),
          );
          lastStatusReport = reportDecision.message;

          // Add WARNING/CRITICAL decisions to alert history.
          for (final d in decisions) {
            if (d.severity != Severity.info && d.alertId.isNotEmpty) {
              // Avoid duplicates by alertId.
              if (!alertHistory.any((a) => a.alertId == d.alertId)) {
                alertHistory.insert(0, d);
                if (alertHistory.length > _maxAlertHistory) {
                  alertHistory.removeLast();
                }
                // Emit stream event for CRITICAL alerts.
                if (d.severity == Severity.critical) {
                  _alertCtrl.add(d);
                }
              }
            }
          }

          // Store DB stats (rivian/ai-sast feedback loop counter).
          if (msg['db_stats'] is Map) {
            dbStats = Map<String, dynamic>.from(msg['db_stats'] as Map);
          }

          latestPayload = VehiclePayload(
            telemetry: telemetry,
            decisions: decisions,
            timestamp: (msg['timestamp'] as num?)?.toDouble() ?? 0.0,
            dbStats:   dbStats,
          );
          notifyListeners();

        case 'FEEDBACK_RESULT':
          // rivian/ai-sast pattern: server confirms feedback was recorded.
          final alertId = msg['alert_id'] as String? ?? '';
          final status  = msg['status']   as String? ?? '';
          final accepted = msg['accepted'] as bool? ?? false;

          if (accepted && alertId.isNotEmpty) {
            final fb = status == 'confirmed_alert'
                ? AlertFeedback.confirmed
                : AlertFeedback.falsePositive;
            _applyLocalFeedback(alertId, fb);
          }
          _feedbackCtrl.add(msg);
          notifyListeners();
          debugPrint('[WS] Feedback result: $alertId=$status accepted=$accepted');

        case 'ALERTS_LIST':
          // Response to GET_ALERTS: update alert history from DB snapshot.
          final rawList = msg['alerts'] as List<dynamic>? ?? [];
          for (final raw in rawList) {
            final d = AgentDecision.fromJson(raw as Map<String, dynamic>);
            if (!alertHistory.any((a) => a.alertId == d.alertId)) {
              alertHistory.add(d);
            }
          }
          alertHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          if (alertHistory.length > _maxAlertHistory) {
            alertHistory.removeRange(_maxAlertHistory, alertHistory.length);
          }
          notifyListeners();

        case 'PRIORITY_ALERT':
          // Only emit if this alertId hasn't been seen before.
          final decision =
              AgentDecision.fromJson(msg['payload'] as Map<String, dynamic>);
          if (!alertHistory.any((a) => a.alertId == decision.alertId)) {
            alertHistory.insert(0, decision);
            if (alertHistory.length > _maxAlertHistory) alertHistory.removeLast();
            // Only show the overlay if the cooldown has expired.
            final now = DateTime.now();
            if (_lastAlertEmitted == null ||
                now.difference(_lastAlertEmitted!) >= _alertCooldown) {
              _lastAlertEmitted = now;
              _alertCtrl.add(decision);
            }
          }
          notifyListeners();

        case 'CHAT_RESPONSE':
          _chatCtrl.add(msg);
          debugPrint('[WS] Chat response received');

        case 'ACK':
          debugPrint('[WS] ACK: ${msg['command']}');
      }
    } catch (e, st) {
      debugPrint('[WS] Parse error: $e\n$st');
    }
  }

  void _onError(Object err) {
    errorMessage = err.toString();
    _updateState(WsState.error);
    _scheduleReconnect();
  }

  void _onDone() {
    _updateState(WsState.disconnected);
    _scheduleReconnect();
  }

  void _updateState(WsState s) {
    connectionState = s;
    notifyListeners();
  }

  void _scheduleReconnect() {
    Future.delayed(const Duration(seconds: 3), () {
      if (connectionState != WsState.connected) connect();
    });
  }

  @override
  void dispose() {
    disconnect();
    _alertCtrl.close();
    _feedbackCtrl.close();
    _chatCtrl.close();
    super.dispose();
  }
}
