# Rivian On-Vehicle Intelligence — Multi-Agent AI System

A production-grade **Multi-Agent AI** telemetry system for Rivian EVs built with:

| Layer | Tech |
|---|---|
| **Backend Agents** | Python · `asyncio` · `numpy` · `websockets` |
| **Free LLM** | [Groq Cloud](https://console.groq.com) — `llama-3.3-70b-versatile` (no credit card) |
| **Flutter UI** | Flutter 3 · Provider · `web_socket_channel` |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│               VehicleIntelligenceOrchestrator                │
│                                                              │
│  TelemetrySimulator ──► TelemetryData (every 1 s)            │
│                              │                               │
│           ┌──────────────────┼──────────────────┐            │
│           ▼                  ▼                  ▼            │
│  AnomalyDetection  ContextAwarePlanner  StatusReporter       │
│  Agent (Z-Score)   Agent (cold/battery)  Agent (Groq LLM)   │
│           │                  │                  │            │
│           └──────────────────┴──────────────────┘            │
│                              │                               │
│                    WebSocket broadcast                        │
│                    ws://0.0.0.0:8765                          │
└──────────────────────────────────────────────────────────────┘
                              │
                    Flutter Dashboard UI
                  (telemetry + agent decisions
                   + priority alerts + LLM report)
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
- All alert metadata (Z, μ, σ, anomaly count) surfaced to UI

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

---

### 3 · Vehicle Status Reporter Agent  (`VehicleStatusReporterAgent`)

Calls **Groq Cloud's FREE API** every **10 seconds**:

- **Model:** `llama-3.3-70b-versatile`  
- **Free tier:** 30 req/min · 6 000 tok/min (no credit card required)  
- **Output:** One driver-friendly sentence summarising all sensor data + agent states  
- Displayed with fade-in animation on the Flutter dashboard

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
# 🚗  Rivian Vehicle Intelligence Server  →  ws://0.0.0.0:8765
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

Every tick the server sends:

```json
{
  "type": "TELEMETRY_UPDATE",
  "telemetry": {
    "motor_temp": 158.3,
    "battery_percent": 74.2,
    "outside_temp": 22.4,
    "vehicle_speed": 45.1,
    "battery_voltage": 354.6,
    "timestamp": 1740412800.0
  },
  "agent_decisions": [
    {
      "agent_name": "AnomalyDetectionAgent",
      "decision_type": "NORMAL",
      "message": "Motor temp nominal: 158.3°F  (Z = 0.42)",
      "severity": "INFO",
      "metadata": { "motor_temp": 158.3, "z_score": 0.42 }
    },
    {
      "agent_name": "ContextAwarePlannerAgent",
      "decision_type": "BATTERY_WARMING",
      "message": "🔋 BATTERY WARMING INITIATED ...",
      "severity": "WARNING",
      "metadata": { "preconditioning_active": true, "progress_percent": 12.5 }
    },
    {
      "agent_name": "VehicleStatusReporterAgent",
      "decision_type": "STATUS_REPORT",
      "message": "All systems nominal; battery warming active due to 22°F outside temperature.",
      "severity": "INFO",
      "metadata": { "model": "llama-3.3-70b-versatile" }
    }
  ]
}
```

On anomaly: an additional `PRIORITY_ALERT` message fires immediately:

```json
{
  "type": "PRIORITY_ALERT",
  "payload": {
    "agent_name": "AnomalyDetectionAgent",
    "decision_type": "PRIORITY_ALERT",
    "message": "⚠️ Motor Temperature Anomaly Detected! Current: 268.7°F | Z-Score: 4.21",
    "severity": "CRITICAL",
    "metadata": { "z_score": 4.21, "baseline_mean": 155.2, "anomaly_count": 3 }
  }
}
```

---

## Flutter UI — Agent Decision Display

| Decision Type | Visual Treatment |
|---|---|
| `PRIORITY_ALERT` | Slide-in banner from top · pulsing red border · auto-dismiss 8 s |
| `BATTERY_WARMING` | Cyan progress bar in agent card · "WARMING" badge |
| `BATTERY_WARNING` | Orange bordered card |
| `STATUS_REPORT` | Dedicated LLM card with fade-in animation · green live dot |
| `NORMAL` | Subtle green-bordered agent card |

---

## Free LLM Cost

| Provider | Model | Free Tier | Sign-up |
|---|---|---|---|
| **Groq** | `llama-3.3-70b-versatile` | 30 req/min · 6 000 tok/min | [console.groq.com](https://console.groq.com) |
| **HuggingFace** | `Mistral-7B-Instruct` | ~1 000 req/day | [huggingface.co](https://huggingface.co) |
| **Cohere** | `command-r` | 1 000 req/month | [cohere.com](https://cohere.com) |

This project uses **Groq** because it is the fastest (< 500 ms) and most generous free tier.
