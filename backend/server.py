"""
╔══════════════════════════════════════════════════════════════════════╗
║           RIVIAN VEHICLE INTELLIGENCE — WEBSOCKET SERVER  v3.0     ║
║                                                                      ║
║  ws://0.0.0.0:8765                                                  ║
║                                                                      ║
║  Commands accepted (JSON):                                           ║
║    SIMULATE_SPIKE   — trigger motor-temp anomaly                    ║
║    SIMULATE_COLD    — trigger cold-weather phase                    ║
║    FORCE_REPORT     — force LLM status report now                   ║
║    ALERT_FEEDBACK   — mark alert confirmed / false-positive         ║
║                       {alert_id, status, comment}                   ║
║    GET_ALERTS       — request recent alert list from DB             ║
║    CHAT             — AI support chat (Groq LLM)                   ║
║                       {message, conversation_id}                   ║
╚══════════════════════════════════════════════════════════════════════╝

Open-source integrations
-------------------------
• rivian/ai-sast  (Apache 2.0) — feedback loop; ALERT_FEEDBACK command
• rivian/odxtools (MIT)        — DTC codes echoed in every payload
• NATS subject routing         — subject field on every broadcast message
"""

import asyncio
import json
import logging
import math
import os
import random
import time

import httpx
import websockets
import websockets.asyncio.server
from dotenv import load_dotenv

from agents import TelemetryData, VehicleIntelligenceOrchestrator

# ── environment ──────────────────────────────────────────────────────
load_dotenv()
GROQ_API_KEY: str = os.environ.get("GROQ_API_KEY", "")
WS_HOST: str      = os.environ.get("WS_HOST", "0.0.0.0")
# Render / Heroku / Fly inject $PORT — fall back to WS_PORT, then 8765
WS_PORT: int      = int(os.environ.get("PORT") or os.environ.get("WS_PORT") or "8765")


# ── HTTP health check (so Render/Fly can hit GET / before WS upgrade) ─
async def _health_check(connection, request):
    """Return HTTP 200 for non-WebSocket requests (e.g. Render health probe)."""
    if request.headers.get("Upgrade", "").lower() == "websocket":
        return None  # let websockets handle the WS upgrade
    return connection.respond(
        200,
        '{"status":"ok","service":"rivian-vehicle-intelligence",'
        '"version":"3.0"}\n',
    )

# ── Live Chat — Groq-powered Rivian Support AI ───────────────────────
GROQ_CHAT_URL  = "https://api.groq.com/openai/v1/chat/completions"
GROQ_CHAT_MODEL = "llama-3.3-70b-versatile"

CHAT_SYSTEM_PROMPT = (
    "You are Rivian Support AI, an intelligent virtual assistant for Rivian electric vehicle owners. "
    "You have deep knowledge of Rivian R1T and R1S vehicles, including their quad-motor drivetrain, "
    "battery systems, charging (Rivian Adventure Network & CCS), software updates (OTA), "
    "Driver+, Camp Mode, Gear Guard, off-road capabilities, and all vehicle features.\n\n"
    "Key Rivian facts you know:\n"
    "- Rivian Customer Service: 1-888-RIVIAN-1 (1-888-748-4261), available 24/7\n"
    "- Rivian Roadside Assistance: 1-888-748-4261 (complimentary, includes flatbed towing)\n"
    "- Service appointments: rivian.com/support or Rivian mobile app\n"
    "- Rivian service centers across the US + mobile service vans\n"
    "- R1T battery: 75 kWh Standard / 135 kWh Large / 180 kWh Max pack\n"
    "- R1S battery: 75 kWh Standard / 135 kWh Large pack\n"
    "- DC fast charging: up to 220 kW (Large pack)\n"
    "- OTA updates delivered regularly with new features\n"
    "- 8-year / 175,000-mile battery & drivetrain warranty\n"
    "- 5-year / 60,000-mile comprehensive warranty\n\n"
    "When the user asks about their vehicle, use the real-time telemetry data provided. "
    "Be helpful, friendly, and technically accurate. Keep responses concise (2-4 sentences max). "
    "If something requires human support, direct them to 1-888-748-4261 or rivian.com/support. "
    "Never make up recall information or safety-critical data."
)

# Per-client conversation history (max 20 messages per client)
_chat_histories: dict[int, list[dict]] = {}
_chat_http_client: httpx.AsyncClient | None = None


async def _get_chat_client() -> httpx.AsyncClient:
    global _chat_http_client
    if _chat_http_client is None or _chat_http_client.is_closed:
        _chat_http_client = httpx.AsyncClient(timeout=15.0)
    return _chat_http_client


async def handle_chat(
    ws: "websockets.asyncio.server.ServerConnection",
    user_message: str,
    conversation_id: str,
    telemetry_context: str,
) -> None:
    """Process a chat message through Groq and send response back."""
    client_id = id(ws)

    # Initialize or retrieve conversation history
    if client_id not in _chat_histories:
        _chat_histories[client_id] = []

    history = _chat_histories[client_id]

    # Add user message
    history.append({"role": "user", "content": user_message})

    # Keep only last 20 messages to stay within token limits
    if len(history) > 20:
        history[:] = history[-20:]

    # Build messages array with system prompt + telemetry context
    system_msg = CHAT_SYSTEM_PROMPT
    if telemetry_context:
        system_msg += f"\n\nCurrent vehicle telemetry:\n{telemetry_context}"

    messages = [{"role": "system", "content": system_msg}] + history

    try:
        http_client = await _get_chat_client()
        resp = await http_client.post(
            GROQ_CHAT_URL,
            headers={
                "Authorization": f"Bearer {GROQ_API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "model": GROQ_CHAT_MODEL,
                "messages": messages,
                "max_tokens": 300,
                "temperature": 0.6,
            },
        )

        if resp.status_code == 200:
            data = resp.json()
            reply = data["choices"][0]["message"]["content"].strip()
            history.append({"role": "assistant", "content": reply})
            log.info("[Chat] Reply: %s", reply[:80])
        elif resp.status_code == 429:
            reply = ("I'm currently experiencing high demand. Please try again in a moment, "
                     "or call Rivian Support directly at 1-888-748-4261.")
            log.warning("[Chat] Groq rate-limited (429)")
        else:
            reply = ("I'm having trouble connecting right now. For immediate help, "
                     "please call Rivian at 1-888-748-4261 or visit rivian.com/support.")
            log.error("[Chat] Groq %d: %s", resp.status_code, resp.text[:200])

    except Exception as exc:
        reply = ("Sorry, I'm temporarily unavailable. Please reach Rivian Support "
                 "at 1-888-748-4261 for immediate assistance.")
        log.error("[Chat] Exception: %s", exc)

    # Send response back to the requesting client
    response = json.dumps({
        "type": "CHAT_RESPONSE",
        "subject": "vehicle.chat.response",
        "message": reply,
        "conversation_id": conversation_id,
        "timestamp": time.time(),
    })

    if ws in CLIENTS:
        try:
            await ws.send(response)
        except Exception:
            pass

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("server")

# ── connected-client registry ────────────────────────────────────────
CLIENTS: set[websockets.asyncio.server.ServerConnection] = set()
COMMAND_QUEUE: asyncio.Queue = asyncio.Queue()


async def broadcast(message: str) -> None:
    if not CLIENTS:
        return
    results = await asyncio.gather(
        *[client.send(message) for client in list(CLIENTS)],
        return_exceptions=True,
    )
    for r in results:
        if isinstance(r, Exception):
            log.debug("Broadcast exception (client disconnected): %s", r)


# ── Telemetry Simulator ──────────────────────────────────────────────

class TelemetrySimulator:
    """
    Generates realistic Rivian R1T sensor readings with scripted scenarios.

    Auto scenarios:
      Tick 60, 120, …  → Motor-temp spike (+85-120 F for 5 ticks)
      Tick 0-89        → Warm outside (50-75 F)
      Tick 90-179      → Cold outside (10-28 F) → triggers Agent 2
    Battery drains ~0.045%/tick.

    On-demand triggers:
      trigger_spike()          → immediate motor-temp spike
      trigger_cold(n_ticks)    → cold-weather phase for n ticks
    """

    NORMAL_MOTOR_TEMP  = 155.0
    SPIKE_TICKS        = 5
    _CABIN_HVAC_TARGET = 72.0

    def __init__(self) -> None:
        self._tick              = 0
        self._spike_remaining   = 0
        self._cold_override_ticks = 0
        self._battery_start     = 82.0
        self._cabin_temp        = 72.0

    def trigger_spike(self) -> None:
        self._spike_remaining = max(self._spike_remaining, self.SPIKE_TICKS)
        log.info("[Simulator] Motor spike triggered on-demand")

    def trigger_cold(self, duration_ticks: int = 45) -> None:
        self._cold_override_ticks = max(self._cold_override_ticks, duration_ticks)
        log.info("[Simulator] Cold-weather override triggered (%d ticks)", duration_ticks)

    def next(self) -> TelemetryData:
        self._tick += 1
        t = self._tick

        # motor temperature
        if t % 60 == 0:
            self._spike_remaining = self.SPIKE_TICKS
        if self._spike_remaining > 0:
            motor_temp = self.NORMAL_MOTOR_TEMP + random.uniform(85, 120)
            self._spike_remaining -= 1
        else:
            motor_temp = (
                self.NORMAL_MOTOR_TEMP
                + math.sin(t * 0.12) * 8.0
                + random.gauss(0, 3.5)
            )

        # outside temperature
        if self._cold_override_ticks > 0:
            outside_temp = random.uniform(10.0, 28.0)
            self._cold_override_ticks -= 1
        else:
            phase = (t // 90) % 2
            outside_temp = (
                random.uniform(10.0, 28.0)
                if phase == 1
                else random.uniform(50.0, 75.0)
            )

        # cabin temp (HVAC settling toward target)
        target = self._CABIN_HVAC_TARGET
        if outside_temp < 32:
            target = 68.0 + random.gauss(0, 0.5)
        self._cabin_temp = (
            self._cabin_temp * 0.98 + target * 0.02 + random.gauss(0, 0.2)
        )

        # battery state
        battery_pct = max(
            10.0,
            self._battery_start - t * 0.045 + random.gauss(0, 0.4),
        )

        # speed
        speed = abs(math.sin(t * 0.04)) * 72.0 + random.gauss(0, 2.0)
        speed = max(0.0, speed)

        # regen power (0-50 kW)
        regen_raw   = math.sin(t * 0.08 + 1.5) * 28.0 + math.sin(t * 0.13) * 18.0
        regen_power = max(0.0, regen_raw)

        # motor RPM  (~8.2:1 ratio, r=0.37 m)
        motor_rpm = (speed * 60.0 / (2 * math.pi * 0.37) * 8.2) if speed > 0.5 else 0.0

        # battery voltage (355 V nominal ± noise)
        voltage = 355.0 + random.gauss(0, 4.0)

        return TelemetryData(
            motor_temp=round(motor_temp, 2),
            battery_percent=round(battery_pct, 2),
            outside_temp=round(outside_temp, 2),
            vehicle_speed=round(speed, 2),
            battery_voltage=round(voltage, 2),
            cabin_temp=round(self._cabin_temp, 2),
            regen_power=round(regen_power, 2),
            motor_rpm=round(motor_rpm, 1),
        )


# ── WebSocket handler ────────────────────────────────────────────────

async def ws_handler(
    websocket: websockets.asyncio.server.ServerConnection,
) -> None:
    CLIENTS.add(websocket)
    addr = websocket.remote_address
    log.info("Client connected: %s  (total: %d)", addr, len(CLIENTS))

    await websocket.send(json.dumps({
        "type":    "HANDSHAKE",
        "subject": "vehicle.server.handshake",
        "message": "Connected to Rivian Vehicle Intelligence Server",
        "agents":  [
            "AnomalyDetectionAgent",
            "ContextAwarePlannerAgent",
            "VehicleStatusReporterAgent",
            "RangePredictionAgent",
            "PredictiveMaintenanceAgent",
        ],
        "features": [
            "dtc_codes",
            "vrs_scoring",
            "sqlite_feedback_loop",
            "nats_subjects",
        ],
        "version":   "3.0",
        "timestamp": time.time(),
    }))

    try:
        async for raw in websocket:
            try:
                cmd      = json.loads(raw)
                cmd_type = cmd.get("type", "")
                log.info("Command received: %s", cmd_type)
                await COMMAND_QUEUE.put({"cmd": cmd, "ws": websocket})
                await websocket.send(json.dumps({"type": "ACK", "command": cmd_type}))
            except json.JSONDecodeError:
                pass
    except websockets.exceptions.ConnectionClosedOK:
        pass
    except (
        websockets.exceptions.ConnectionClosedError,
        websockets.exceptions.ConnectionClosed,
    ) as exc:
        log.debug("Connection closed: %s", exc)
    finally:
        CLIENTS.discard(websocket)
        _chat_histories.pop(id(websocket), None)
        log.info("Client disconnected: %s  (total: %d)", addr, len(CLIENTS))


# ── Main telemetry loop ──────────────────────────────────────────────

async def telemetry_loop(orchestrator: VehicleIntelligenceOrchestrator) -> None:
    simulator = TelemetrySimulator()

    while True:
        # Drain command queue
        while not COMMAND_QUEUE.empty():
            try:
                item     = COMMAND_QUEUE.get_nowait()
                cmd      = item["cmd"]
                ws_src   = item.get("ws")
                cmd_type = cmd.get("type", "")

                if cmd_type == "SIMULATE_SPIKE":
                    simulator.trigger_spike()

                elif cmd_type == "SIMULATE_COLD":
                    simulator.trigger_cold(cmd.get("duration_ticks", 45))

                elif cmd_type == "FORCE_REPORT":
                    orchestrator.reporter_agent.force_report()

                elif cmd_type == "ALERT_FEEDBACK":
                    # rivian/ai-sast pattern — operator marks alert as
                    # confirmed_alert or false_positive to feed into LLM
                    alert_id = cmd.get("alert_id", "")
                    status   = cmd.get("status", "")   # confirmed_alert / false_positive
                    comment  = cmd.get("comment", "")
                    ok = orchestrator.record_feedback(alert_id, status, comment)
                    result_msg = json.dumps({
                        "type":      "FEEDBACK_RESULT",
                        "subject":   "vehicle.feedback.result",
                        "alert_id":  alert_id,
                        "status":    status,
                        "accepted":  ok,
                        "timestamp": time.time(),
                    })
                    if ws_src and ws_src in CLIENTS:
                        try:
                            await ws_src.send(result_msg)
                        except Exception:
                            pass
                    log.info(
                        "Feedback %s for alert %s → %s",
                        status, alert_id, "OK" if ok else "NOT FOUND",
                    )

                elif cmd_type == "CHAT":
                    user_msg = cmd.get("message", "")
                    conv_id  = cmd.get("conversation_id", "default")
                    # Build telemetry context from latest readings
                    tel_ctx = ""
                    try:
                        tel = simulator.next()
                        tel_ctx = (
                            f"Motor Temp: {tel.motor_temp:.1f}°F, "
                            f"Battery: {tel.battery_percent:.1f}%, "
                            f"Voltage: {tel.battery_voltage:.0f}V, "
                            f"Speed: {tel.vehicle_speed:.1f} mph, "
                            f"Outside: {tel.outside_temp:.1f}°F, "
                            f"Cabin: {tel.cabin_temp:.1f}°F, "
                            f"Regen: {tel.regen_power:.1f} kW"
                        )
                    except Exception:
                        pass
                    if user_msg and ws_src:
                        asyncio.create_task(
                            handle_chat(ws_src, user_msg, conv_id, tel_ctx)
                        )

                elif cmd_type == "GET_ALERTS":
                    # Send recent SQLite alerts to requesting client
                    limit  = min(int(cmd.get("limit", 50)), 200)
                    alerts = orchestrator.alert_db.get_recent_alerts(limit=limit)
                    msg = json.dumps({
                        "type":      "ALERTS_LIST",
                        "subject":   "vehicle.alerts.history",
                        "alerts":    alerts,
                        "count":     len(alerts),
                        "timestamp": time.time(),
                    })
                    if ws_src and ws_src in CLIENTS:
                        try:
                            await ws_src.send(msg)
                        except Exception:
                            pass

            except asyncio.QueueEmpty:
                break

        telemetry = simulator.next()
        decisions = await orchestrator.process(telemetry)
        payload   = orchestrator.to_json(decisions, telemetry)
        await broadcast(payload)
        await asyncio.sleep(1.0)


# ── Entry point ──────────────────────────────────────────────────────

async def main() -> None:
    if not GROQ_API_KEY:
        log.warning(
            "GROQ_API_KEY not set — LLM reports will error. "
            "Add to backend/.env  (GROQ_API_KEY=gsk_…)"
        )

    orchestrator = VehicleIntelligenceOrchestrator(
        groq_api_key=GROQ_API_KEY,
        broadcast_callback=broadcast,
    )

    log.info(
        "Rivian Vehicle Intelligence Server v3.0  →  ws://%s:%d",
        WS_HOST, WS_PORT,
    )
    log.info(
        "Agents: AnomalyDetection | ContextPlanner | RangePrediction "
        "| PredictiveMaintenance | LLMReporter"
    )
    log.info(
        "Open-source integrations: rivian/ai-sast (SQLite feedback) "
        "| rivian/odxtools (OBD-II DTC) | NATS subject routing"
    )

    try:
        async with websockets.serve(
            ws_handler, WS_HOST, WS_PORT,
            process_request=_health_check,
        ):
            await telemetry_loop(orchestrator)
    except asyncio.CancelledError:
        pass
    finally:
        await orchestrator.shutdown()
        log.info("Server stopped.")


if __name__ == "__main__":
    asyncio.run(main())
