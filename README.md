# Rivian On-Vehicle Intelligence — Multi-Agent AI System

A production-grade **Multi-Agent AI** telemetry system for Rivian EVs built with:

| Layer | Tech |
|---|---|
| **Backend Agents** | Python · `asyncio` · `numpy` · `websockets` |
| **Free LLM** | [Groq Cloud](https://console.groq.com) — `llama-3.3-70b-versatile` (no credit card) |
| **Flutter UI** | Flutter 3 · Provider · `web_socket_channel` |
| **Persistence** | SQLite · alert feedback loop (inspired by [rivian/ai-sast](https://github.com/rivian/ai-sast)) |
| **Diagnostics** | OBD-II DTC codes · CVSS-style Vehicle Risk Scores (inspired by [rivian/odxtools](https://github.com/rivian/odxtools)) |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                 VehicleIntelligenceOrchestrator                  │
│                                                                  │
│  TelemetrySimulator ──► TelemetryData (every 1 s)                │
│                              │                                   │
│        ┌─────────────────────┼──────────────────────┐            │
│        ▼                     ▼                      ▼            │
│  AnomalyDetection   ContextAwarePlanner      RangePrediction     │
│  Agent (Z-Score)    Agent (cold/battery)     Agent (EPA model)   │
│        │                     │                      │            │
│        ▼                     ▼                      ▼            │
│  PredictiveMaintenance                      StatusReporter       │
│  Agent (EWM stress)                         Agent (Groq LLM)    │
│        │                     │                      │            │
│        └─────────────────────┴──────────────────────┘            │
│                              │                                   │
│             SQLite (alert_db) ◄── operator feedback              │
│                              │                                   │
│                    WebSocket broadcast                            │
│                    ws://0.0.0.0:8765                              │
└──────────────────────────────────────────────────────────────────┘
                              │
                    Flutter Dashboard UI
                  (telemetry + agent decisions
                   + priority alerts + LLM report
                   + AI support chat)
```

---

## Agent Details

### 1 · Anomaly Detection Agent  (`AnomalyDetectionAgent`)

Uses a **rolling Z-Score** over the last 20 motor temperature readings:

$$Z = \frac{|x - \mu|}{\sigma}$$

| Z-Score | Action |
|---|---|
| `< 2.5` | `NORMAL` — nominal |
| `≥ 2.5` | `PRIORITY_ALERT (WARNING)` |
| temp `≥ 250 °F` | `PRIORITY_ALERT (CRITICAL)` regardless of Z |

- 15-second cooldown prevents alert spam  
- All alert metadata (Z, μ, σ) surfaced to UI  
- DTC code: **P0218** (Motor Overtemperature) · VRS: 9.1

---

### 2 · Context-Aware Planner Agent  (`ContextAwarePlannerAgent`)

Inputs: **Battery %** + **Outside Temperature (°F)**

```
outside_temp < 32 °F  AND  battery ≥ 20 %
    → BATTERY_WARMING INITIATED
    → Flutter UI shows "Battery Warming" progress bar

preconditioning active + battery < 20 %
    → BATTERY_WARNING — halt to conserve energy

after 10 min (simulated)
    → BATTERY_WARMING COMPLETE
```

- DTC code: **P1A00** (Battery Pack Temperature Below Optimal) · VRS: 5.3

---

### 3 · Vehicle Status Reporter Agent  (`VehicleStatusReporterAgent`)

Calls **Groq Cloud's FREE API** every **30 seconds**:

- **Model:** `llama-3.3-70b-versatile`  
- **Free tier:** 30 req/min · 6 000 tok/min (no credit card required)  
- **Output:** One driver-friendly sentence summarising all sensor data + agent states  
- Injects historical alert feedback from SQLite as LLM context for improved accuracy  
- Displayed with fade-in animation on the Flutter dashboard  
- DTC code: **U1001** (Vehicle Telematics Status Update)

---

### 4 · Range Prediction Agent  (`RangePredictionAgent`)

Estimates remaining range based on real-time conditions:

| Factor | Description |
|---|---|
| **Temperature** | 70% efficiency below 32 °F · 85% below 50 °F · 95% below 68 °F |
| **Speed drag** | Penalises speeds above 55 mph using a square-root drag model |
| **Motor RPM** | Applies efficiency derating above 6 000 rpm |
| **Regen credit** | Adds up to 5% range credit from regenerative braking power |

- Base: **314-mile EPA range** for the Rivian R1T  
- DTC code: **P1A10** (EV Estimated Driving Range Calculation)

---

### 5 · Predictive Maintenance Agent  (`PredictiveMaintenanceAgent`)

Tracks cumulative drivetrain stress using an **Exponentially Weighted Mean (EWM)**:

```
health = 100 − (cumulative_stress × 10) − (anomaly_count × 2)
```

| Health Score | Status | Action |
|---|---|---|
| 85 – 100 | EXCELLENT | No maintenance required |
| 70 – 84 | GOOD | Routine inspection within 90 days |
| 50 – 69 | FAIR | Service appointment within 30 days |
| 30 – 49 | POOR | Immediate service recommended |
| < 30 | CRITICAL | Stop vehicle · contact Rivian service |

- DTC code: **B1090** (Vehicle Health Monitor — Predictive Maintenance Required) · VRS: 3.7

---

## Quick Start

### Backend

```bash
cd backend

# 1. Install dependencies
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 2. Add your free Groq API key
cp .env.example .env
# → edit .env and set GROQ_API_KEY=gsk_...
#   Get yours free at: https://console.groq.com

# 3. Start the server
python server.py
# 🚗  Rivian Vehicle Intelligence Server v3.0  →  ws://0.0.0.0:8765
```

### Flutter App

```bash
cd flutter_app
flutter pub get
flutter run
```

> **Note:** For a physical device, change `localhost` in `lib/main.dart` to your machine's LAN IP.  
> Example: `ws://192.168.1.42:8765`

---

## WebSocket Message Schema

### Server → Client: Telemetry Update

Every tick the server broadcasts:

```json
{
  "type": "TELEMETRY_UPDATE",
  "subject": "vehicle.broadcast",
  "telemetry": {
    "motor_temp": 158.3,
    "battery_percent": 74.2,
    "outside_temp": 22.4,
    "cabin_temp": 71.8,
    "vehicle_speed": 45.1,
    "battery_voltage": 354.6,
    "regen_power": 12.4,
    "motor_rpm": 3210.0
  },
  "decisions": [
    {
      "subject": "vehicle.agents.anomaly",
      "agent_name": "AnomalyDetectionAgent",
      "decision_type": "PRIORITY_ALERT",
      "message": "Motor temp anomaly detected (Z=3.87). Current: 268.7 F. Immediate inspection recommended.",
      "severity": "CRITICAL",
      "metadata": { "z_score": 3.87, "motor_temp": 268.7, "mean": 155.2, "std": 29.3 },
      "dtc_code": "P0218",
      "cvss_score": 9.1,
      "cvss_vector": "VRS:1.0/AV:Motor/AC:H/MS:C/SI:H/CI:H",
      "alert_id": "a3f8c201",
      "timestamp": 1740412800.0
    },
    {
      "subject": "vehicle.agents.range",
      "agent_name": "RangePredictionAgent",
      "decision_type": "RANGE_ESTIMATE",
      "message": "Estimated range: 218 mi (69% of EPA).",
      "severity": "INFO",
      "metadata": { "estimated_range_miles": 218.0, "epa_base_miles": 314.0, "temp_factor": 0.85 },
      "dtc_code": "P1A10",
      "cvss_score": 0.0,
      "cvss_vector": "VRS:1.0/AV:Battery/AC:H/MS:U/SI:L/CI:L",
      "alert_id": "7d2e9b44",
      "timestamp": 1740412800.0
    },
    {
      "subject": "vehicle.agents.maintenance",
      "agent_name": "PredictiveMaintenanceAgent",
      "decision_type": "MAINTENANCE_STATUS",
      "message": "Vehicle health: 91/100 (EXCELLENT). No maintenance required.",
      "severity": "INFO",
      "metadata": { "health_score": 91.0, "status": "EXCELLENT", "cumulative_stress": 0.92 },
      "dtc_code": "B1090",
      "cvss_score": 0.0,
      "cvss_vector": "VRS:1.0/AV:Thermal/AC:H/MS:U/SI:M/CI:M",
      "alert_id": "c9a1f037",
      "timestamp": 1740412800.0
    },
    {
      "subject": "vehicle.agents.reporter",
      "agent_name": "VehicleStatusReporterAgent",
      "decision_type": "STATUS_REPORT",
      "message": "All systems nominal; battery warming active due to 22°F outside temperature.",
      "severity": "INFO",
      "metadata": { "model": "llama-3.3-70b-versatile", "battery_percent": 74.2 },
      "dtc_code": "U1001",
      "cvss_score": 0.0,
      "alert_id": "e5b20f18",
      "timestamp": 1740412800.0
    }
  ],
  "db_stats": {
    "total_alerts": 142,
    "total_feedback": 5,
    "false_positives": 2,
    "confirmed_alerts": 3
  },
  "timestamp": 1740412800.0
}
```

### Server → Client: Handshake

Sent once on connection:

```json
{
  "type": "HANDSHAKE",
  "subject": "vehicle.server.handshake",
  "message": "Connected to Rivian Vehicle Intelligence Server",
  "agents": [
    "AnomalyDetectionAgent",
    "ContextAwarePlannerAgent",
    "VehicleStatusReporterAgent",
    "RangePredictionAgent",
    "PredictiveMaintenanceAgent"
  ],
  "features": ["dtc_codes", "vrs_scoring", "sqlite_feedback_loop", "nats_subjects"],
  "version": "3.0",
  "timestamp": 1740412800.0
}
```

### Server → Client: Chat Response

```json
{
  "type": "CHAT_RESPONSE",
  "subject": "vehicle.chat.response",
  "message": "Your battery is at 74% and the motor temperature is normal at 158°F — all systems look good.",
  "conversation_id": "user-session-1",
  "timestamp": 1740412800.0
}
```

---

## WebSocket Commands (Client → Server)

Send JSON commands to the server to trigger scenarios or request data:

| Command | Description | Extra fields |
|---|---|---|
| `SIMULATE_SPIKE` | Trigger a motor-temperature spike for 5 ticks | — |
| `SIMULATE_COLD` | Trigger a cold-weather phase | `duration_ticks` (default 45) |
| `FORCE_REPORT` | Force an immediate LLM status report | — |
| `ALERT_FEEDBACK` | Mark an alert as confirmed or false-positive | `alert_id`, `status` (`confirmed_alert` \| `false_positive`), `comment` |
| `GET_ALERTS` | Request recent alert history from SQLite | `limit` (default 50, max 200) |
| `CHAT` | Send a message to the Rivian Support AI | `message`, `conversation_id` |

**Example — trigger a spike:**
```json
{ "type": "SIMULATE_SPIKE" }
```

**Example — mark an alert as a false positive:**
```json
{
  "type": "ALERT_FEEDBACK",
  "alert_id": "a3f8c201",
  "status": "false_positive",
  "comment": "Sensor noise during tunnel transit"
}
```

---

## Flutter UI — Agent Decision Display

| Decision Type | Visual Treatment |
|---|---|
| `PRIORITY_ALERT` | Slide-in banner from top · pulsing red border · auto-dismiss 8 s |
| `BATTERY_WARMING` | Cyan progress bar in agent card · "WARMING" badge |
| `BATTERY_WARNING` | Orange bordered card |
| `RANGE_ESTIMATE` | Range card with estimated miles and efficiency factors |
| `MAINTENANCE_STATUS` | Health score card with status badge and action prompt |
| `STATUS_REPORT` | Dedicated LLM card with fade-in animation · green live dot |
| `NORMAL` | Subtle green-bordered agent card |

---

## Open-Source Integrations

| Integration | License | What it contributes |
|---|---|---|
| [rivian/ai-sast](https://github.com/rivian/ai-sast) | Apache 2.0 | SQLite feedback loop · CVSS-style Vehicle Risk Scores · alert ID pattern |
| [rivian/odxtools](https://github.com/rivian/odxtools) | MIT | OBD-II / UDS DTC code mapping (P0xxx, P1xxx, U1xxx, B1xxx) |
| [rivian/nats-server](https://github.com/rivian/nats-server) | Apache 2.0 | NATS-style `subject` field on every WebSocket message for future routing |

---

## Free LLM Cost

| Provider | Model | Free Tier | Sign-up |
|---|---|---|---|
| **Groq** | `llama-3.3-70b-versatile` | 30 req/min · 6 000 tok/min | [console.groq.com](https://console.groq.com) |
| **HuggingFace** | `Mistral-7B-Instruct` | ~1 000 req/day | [huggingface.co](https://huggingface.co) |
| **Cohere** | `command-r` | 1 000 req/month | [cohere.com](https://cohere.com) |

This project uses **Groq** because it is the fastest (< 500 ms) and most generous free tier.
