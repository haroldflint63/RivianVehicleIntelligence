"""
Multi-Agent AI Vehicle Telemetry — Agent Definitions  v3.0
===========================================================
5 agents: AnomalyDetection, ContextAwarePlanner, VehicleStatusReporter,
          RangePrediction, PredictiveMaintenance
+ VehicleIntelligenceOrchestrator (coordinates all 5 agents)

Open-source integrations applied
---------------------------------
• rivian/ai-sast  (Apache 2.0) — SQLite feedback loop + CVSS-style scoring
  https://github.com/rivian/ai-sast
• rivian/odxtools  (MIT)       — OBD-II / UDS DTC code mapping
  https://github.com/rivian/odxtools
• NATS subject routing         — subject-prefixed WebSocket message structure
  https://github.com/rivian/nats-server
"""

import json
import logging
import os
import time
from dataclasses import asdict, dataclass, field
from typing import Callable, Dict, List, Optional

import httpx
import numpy as np
from dotenv import load_dotenv

from alert_db import AlertDatabase
from dtc_codes import dtc_summary

load_dotenv()

# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------

@dataclass
class TelemetryData:
    motor_temp:       float = 0.0
    battery_percent:  float = 100.0
    outside_temp:     float = 72.0
    vehicle_speed:    float = 0.0
    battery_voltage:  float = 355.0
    cabin_temp:       float = 72.0
    regen_power:      float = 0.0
    motor_rpm:        float = 0.0


@dataclass
class AgentDecision:
    agent_name:    str
    decision_type: str
    message:       str
    severity:      str   = "INFO"
    metadata:      dict  = field(default_factory=dict)
    timestamp:     float = field(default_factory=time.time)
    # OBD-II DTC fields (rivian/odxtools inspired)
    dtc_code:      str   = ""
    cvss_score:    float = 0.0
    cvss_vector:   str   = ""
    alert_id:      str   = ""


# ---------------------------------------------------------------------------
# Agent 1 — Anomaly Detection (rolling Z-Score)
# ---------------------------------------------------------------------------

class AnomalyDetectionAgent:
    WINDOW    = 20
    THRESHOLD = 2.5
    COOLDOWN  = 15.0

    def __init__(self) -> None:
        self._log = logging.getLogger(self.__class__.__name__)
        self._history: List[float] = []
        self._last_alert: float = 0.0

    async def analyze(self, telemetry: TelemetryData) -> Optional[AgentDecision]:
        self._history.append(telemetry.motor_temp)
        if len(self._history) > self.WINDOW:
            self._history.pop(0)
        if len(self._history) < 5:
            return None

        arr  = np.array(self._history)
        mean = arr.mean()
        std  = arr.std()
        if std < 0.01:
            return None

        z   = abs((telemetry.motor_temp - mean) / std)
        now = time.time()
        if z >= self.THRESHOLD and (now - self._last_alert) >= self.COOLDOWN:
            self._last_alert = now
            self._log.warning("Anomaly Z=%.2f  temp=%.1f", z, telemetry.motor_temp)
            dtc = dtc_summary("PRIORITY_ALERT", "CRITICAL")
            return AgentDecision(
                agent_name="AnomalyDetectionAgent",
                decision_type="PRIORITY_ALERT",
                message=(
                    "Motor temp anomaly detected (Z={:.2f}). "
                    "Current: {:.1f} F. Immediate inspection recommended.".format(
                        z, telemetry.motor_temp)
                ),
                severity="CRITICAL",
                metadata={
                    "z_score":    round(z, 3),
                    "motor_temp": telemetry.motor_temp,
                    "mean":       round(float(mean), 2),
                    "std":        round(float(std), 2),
                },
                dtc_code=dtc["dtc_code"],
                cvss_score=dtc["cvss_score"],
                cvss_vector=dtc["cvss_vector"],
            )
        return None


# ---------------------------------------------------------------------------
# Agent 2 — Context-Aware Planner
# ---------------------------------------------------------------------------

class ContextAwarePlannerAgent:
    COLD_THRESHOLD      = 32.0
    MIN_BATTERY         = 20.0
    PRECONDITION_MINUTES = 10

    def __init__(self) -> None:
        self._log = logging.getLogger(self.__class__.__name__)
        self._last_decision: float = 0.0

    async def analyze(self, telemetry: TelemetryData) -> Optional[AgentDecision]:
        if (telemetry.outside_temp < self.COLD_THRESHOLD
                and telemetry.battery_percent >= self.MIN_BATTERY):
            now = time.time()
            if (now - self._last_decision) >= 600:
                self._last_decision = now
                self._log.info("Cold weather plan: %.1f F", telemetry.outside_temp)
                dtc = dtc_summary("BATTERY_WARMING", "WARNING")
                return AgentDecision(
                    agent_name="ContextAwarePlannerAgent",
                    decision_type="BATTERY_WARMING",
                    message=(
                        "Cold weather detected ({:.1f} F). "
                        "Initiating {}-min battery preconditioning.".format(
                            telemetry.outside_temp, self.PRECONDITION_MINUTES)
                    ),
                    severity="WARNING",
                    metadata={
                        "outside_temp":          telemetry.outside_temp,
                        "battery_percent":        telemetry.battery_percent,
                        "precondition_minutes":   self.PRECONDITION_MINUTES,
                    },
                    dtc_code=dtc["dtc_code"],
                    cvss_score=dtc["cvss_score"],
                    cvss_vector=dtc["cvss_vector"],
                )
        return None


# ---------------------------------------------------------------------------
# Agent 3 — Vehicle Status Reporter  (Groq LLM)
#            Uses historical feedback context from rivian/ai-sast SQLite loop
# ---------------------------------------------------------------------------

class VehicleStatusReporterAgent:
    GROQ_API_URL   = "https://api.groq.com/openai/v1/chat/completions"
    MODEL          = "llama-3.3-70b-versatile"
    MAX_TOKENS     = 80
    REPORT_INTERVAL = 30   # seconds — conservative to stay within Groq TPD limit

    _SYSTEM_PROMPT = (
        "You are a concise AI vehicle status reporter for a Rivian R1T electric truck. "
        "Respond with exactly one sentence summarizing vehicle health and key metrics. "
        "Be specific about numbers. Never use bullet points. Maximum 35 words."
    )

    def __init__(self, alert_db: Optional["AlertDatabase"] = None) -> None:
        self._log      = logging.getLogger(self.__class__.__name__)
        self._api_key  = os.getenv("GROQ_API_KEY", "")
        self._client   = httpx.AsyncClient(timeout=12.0)
        self._last_ts: float = 0.0
        self._last_report    = "Initializing vehicle status reporter..."
        self._force_next     = False
        self._alert_db       = alert_db   # rivian/ai-sast feedback loop

    def force_report(self) -> None:
        self._force_next = True

    async def generate_report(
        self,
        telemetry: TelemetryData,
        anomaly:     Optional[AgentDecision],
        planner:     Optional[AgentDecision],
        range_dec:   Optional[AgentDecision] = None,
        maintenance: Optional[AgentDecision] = None,
    ) -> Optional[AgentDecision]:
        now = time.time()
        if not self._force_next and (now - self._last_ts) < self.REPORT_INTERVAL:
            return None
        self._last_ts    = now
        self._force_next = False

        # ── optional context lines ────────────────────────────────────
        range_info = ""
        if range_dec and range_dec.metadata.get("estimated_range_miles"):
            range_info = "  - Est. Range: {:.0f} mi\n".format(
                range_dec.metadata["estimated_range_miles"])

        health_info = ""
        if maintenance and maintenance.metadata.get("health_score"):
            health_info = "  - Health Score: {:.0f}/100 ({})\n".format(
                maintenance.metadata["health_score"],
                maintenance.metadata.get("status", "HEALTHY"))

        anomaly_msg = anomaly.message   if anomaly  else "No active alert"
        planner_msg = planner.message   if planner  else "Normal"

        # ── rivian/ai-sast feedback loop: inject historical context ───
        historical_context = ""
        if self._alert_db:
            historical_context = self._alert_db.format_context_for_llm()

        user_prompt = (
            "Vehicle sensor snapshot:\n"
            "  - Motor Temp: {:.1f} F\n"
            "  - Battery: {:.1f}%  ({:.0f} V)\n"
            "  - Outside Temp: {:.1f} F  |  Cabin: {:.1f} F\n"
            "  - Speed: {:.1f} mph\n"
            "  - Regen Power: {:.1f} kW\n"
            "  - Motor RPM: {:.0f} rpm\n"
            "{}{}"
            "  - Anomaly Agent: {}\n"
            "  - Planner Agent: {}\n"
            "{}"
            "Write the one-sentence Vehicle Status Report now:"
        ).format(
            telemetry.motor_temp,
            telemetry.battery_percent, telemetry.battery_voltage,
            telemetry.outside_temp, telemetry.cabin_temp,
            telemetry.vehicle_speed,
            telemetry.regen_power,
            telemetry.motor_rpm,
            range_info,
            health_info,
            anomaly_msg,
            planner_msg,
            ("\n## Alert History Context\n" + historical_context + "\n") if historical_context else "",
        )

        try:
            resp = await self._client.post(
                self.GROQ_API_URL,
                headers={
                    "Authorization": "Bearer " + self._api_key,
                    "Content-Type":  "application/json",
                },
                json={
                    "model":       self.MODEL,
                    "messages": [
                        {"role": "system", "content": self._SYSTEM_PROMPT},
                        {"role": "user",   "content": user_prompt},
                    ],
                    "max_tokens":  self.MAX_TOKENS,
                    "temperature": 0.3,
                },
            )
            if resp.status_code == 200:
                data   = resp.json()
                report = data["choices"][0]["message"]["content"].strip()
                self._last_report = report
                self._log.info("LLM report: %s", report)
                dtc = dtc_summary("STATUS_REPORT", "INFO")
                return AgentDecision(
                    agent_name="VehicleStatusReporterAgent",
                    decision_type="STATUS_REPORT",
                    message=report,
                    severity="INFO",
                    metadata={
                        "model":             self.MODEL,
                        "motor_temp":        telemetry.motor_temp,
                        "battery_percent":   telemetry.battery_percent,
                        "prompt_tokens":     data.get("usage", {}).get("prompt_tokens"),
                        "completion_tokens": data.get("usage", {}).get("completion_tokens"),
                        "historical_alerts": len(self._alert_db.get_confirmed_alerts()) if self._alert_db else 0,
                    },
                    dtc_code=dtc["dtc_code"],
                    cvss_score=dtc["cvss_score"],
                    cvss_vector=dtc["cvss_vector"],
                )
            elif resp.status_code == 429:
                # Rate-limited — back off 60 s and return last cached report
                self._log.warning("Groq rate-limited (429). Backing off 60s.")
                self._last_ts += 60
                if self._last_report:
                    dtc = dtc_summary("STATUS_REPORT", "INFO")
                    return AgentDecision(
                        agent_name="VehicleStatusReporterAgent",
                        decision_type="STATUS_REPORT",
                        message=self._last_report,
                        severity="INFO",
                        metadata={"cached": True, "rate_limited": True},
                        dtc_code=dtc["dtc_code"],
                        cvss_score=dtc["cvss_score"],
                        cvss_vector=dtc["cvss_vector"],
                    )
                return None
            else:
                self._log.error("Groq %d: %s", resp.status_code, resp.text[:200])
                return None

        except Exception as exc:
            self._log.error("Reporter exception: %s", exc)
            return None

    @property
    def last_report(self) -> str:
        return self._last_report

    async def close(self) -> None:
        await self._client.aclose()


# ---------------------------------------------------------------------------
# Agent 4 — Range Prediction
# ---------------------------------------------------------------------------

class RangePredictionAgent:
    EPA_BASE_MILES = 314.0
    SPEED_OPTIMAL  = 55.0

    def __init__(self) -> None:
        self._log = logging.getLogger(self.__class__.__name__)

    async def analyze(self, telemetry: TelemetryData) -> AgentDecision:
        # Temperature efficiency
        if   telemetry.outside_temp < 32:  temp_factor = 0.70
        elif telemetry.outside_temp < 50:  temp_factor = 0.85
        elif telemetry.outside_temp < 68:  temp_factor = 0.95
        else:                              temp_factor = 1.0

        # Speed drag
        speed = max(telemetry.vehicle_speed, 1.0)
        speed_factor = min(1.0, (self.SPEED_OPTIMAL / speed) ** 0.5) if speed > self.SPEED_OPTIMAL else 1.0

        # Motor efficiency
        if   telemetry.motor_rpm > 8000: motor_factor = 0.92
        elif telemetry.motor_rpm > 6000: motor_factor = 0.96
        else:                            motor_factor = 1.0

        regen_credit = min(0.05, telemetry.regen_power / 1000.0)
        soc_factor   = telemetry.battery_percent / 100.0

        est = (
            self.EPA_BASE_MILES * soc_factor * temp_factor * speed_factor * motor_factor
            + self.EPA_BASE_MILES * regen_credit
        )
        est = max(0.0, min(est, self.EPA_BASE_MILES))
        pct = (est / self.EPA_BASE_MILES) * 100.0

        if   est < 20: severity, msg = "CRITICAL", "Critical range warning: {:.0f} mi. Charge immediately.".format(est)
        elif est < 50: severity, msg = "WARNING",  "Low range: {:.0f} mi. Plan charging stop soon.".format(est)
        else:          severity, msg = "INFO",     "Estimated range: {:.0f} mi ({:.0f}% of EPA).".format(est, pct)

        dtc = dtc_summary("RANGE_ESTIMATE", severity)
        return AgentDecision(
            agent_name="RangePredictionAgent",
            decision_type="RANGE_ESTIMATE",
            message=msg,
            severity=severity,
            metadata={
                "estimated_range_miles": round(est, 1),
                "epa_base_miles":        self.EPA_BASE_MILES,
                "temp_factor":           round(temp_factor, 3),
                "speed_factor":          round(speed_factor, 3),
                "motor_factor":          round(motor_factor, 3),
                "regen_credit":          round(regen_credit, 4),
                "soc":                   round(soc_factor, 3),
            },
            dtc_code=dtc["dtc_code"],
            cvss_score=dtc["cvss_score"],
            cvss_vector=dtc["cvss_vector"],
        )


# ---------------------------------------------------------------------------
# Agent 5 — Predictive Maintenance  (EWM stress model)
# ---------------------------------------------------------------------------

class PredictiveMaintenanceAgent:
    EWM_ALPHA = 0.05

    def __init__(self) -> None:
        self._log = logging.getLogger(self.__class__.__name__)
        self._ewm_temp:        float = 150.0
        self._ewm_rpm:         float = 2000.0
        self._cumulative_stress: float = 0.0
        self._tick:            int   = 0
        self._anomaly_count:   int   = 0

    async def analyze(
        self,
        telemetry: TelemetryData,
        anomaly: Optional[AgentDecision] = None,
    ) -> AgentDecision:
        self._tick += 1
        if anomaly and anomaly.decision_type == "PRIORITY_ALERT":
            self._anomaly_count += 1

        self._ewm_temp = self.EWM_ALPHA * telemetry.motor_temp  + (1 - self.EWM_ALPHA) * self._ewm_temp
        self._ewm_rpm  = self.EWM_ALPHA * telemetry.motor_rpm   + (1 - self.EWM_ALPHA) * self._ewm_rpm

        temp_stress = max(0.0, (self._ewm_temp - 180.0) / 40.0)
        rpm_stress  = max(0.0, (self._ewm_rpm  - 5000.0) / 5000.0)
        tick_stress = (temp_stress * 0.6 + rpm_stress * 0.4) * 0.01
        self._cumulative_stress = min(100.0, self._cumulative_stress + tick_stress)

        health = max(0.0, 100.0 - self._cumulative_stress * 10.0 - self._anomaly_count * 2.0)

        if   health >= 85: status, severity, action = "EXCELLENT", "INFO",     "No maintenance required."
        elif health >= 70: status, severity, action = "GOOD",      "INFO",     "Schedule routine inspection within 90 days."
        elif health >= 50: status, severity, action = "FAIR",      "WARNING",  "Schedule service appointment within 30 days."
        elif health >= 30: status, severity, action = "POOR",      "WARNING",  "Immediate service recommended."
        else:              status, severity, action = "CRITICAL",  "CRITICAL", "Stop vehicle and contact Rivian service immediately."

        anomaly_rate = (self._anomaly_count / max(1, self._tick)) * 3600.0
        msg = "Vehicle health: {:.0f}/100 ({}). {}".format(health, status, action)

        dtc = dtc_summary("MAINTENANCE_STATUS", severity)
        return AgentDecision(
            agent_name="PredictiveMaintenanceAgent",
            decision_type="MAINTENANCE_STATUS",
            message=msg,
            severity=severity,
            metadata={
                "health_score":           round(health, 1),
                "status":                 status,
                "action":                 action,
                "cumulative_stress":      round(self._cumulative_stress, 4),
                "anomaly_count":          self._anomaly_count,
                "anomaly_rate_per_hour":  round(anomaly_rate, 2),
                "ewm_temp":               round(self._ewm_temp, 2),
                "ewm_rpm":                round(self._ewm_rpm, 2),
            },
            dtc_code=dtc["dtc_code"],
            cvss_score=dtc["cvss_score"],
            cvss_vector=dtc["cvss_vector"],
        )


# ---------------------------------------------------------------------------
# Orchestrator  — coordinates all 5 agents + SQLite persistence
# ---------------------------------------------------------------------------

class VehicleIntelligenceOrchestrator:
    """
    Runs all 5 agents each telemetry tick, attaches DTC codes + VRS scores,
    persists to SQLite (rivian/ai-sast pattern), and serialises results.

    NATS-style subject routing (rivian/nats-server pattern):
      vehicle.telemetry           — raw sensor snapshot
      vehicle.agents.<type>       — individual agent decision
      vehicle.broadcast           — full combined payload (default)
    """

    def __init__(
        self,
        groq_api_key: str = "",
        broadcast_callback: Optional[Callable] = None,
    ) -> None:
        self._log = logging.getLogger(self.__class__.__name__)
        self._db  = AlertDatabase()   # rivian/ai-sast SQLite layer

        # Agent instances
        self.anomaly_agent     = AnomalyDetectionAgent()
        self.planner_agent     = ContextAwarePlannerAgent()
        self.reporter_agent    = VehicleStatusReporterAgent(alert_db=self._db)
        self.range_agent       = RangePredictionAgent()
        self.maintenance_agent = PredictiveMaintenanceAgent()

        self._broadcast = broadcast_callback

        # Latest decisions cache
        self._last_anomaly:     Optional[AgentDecision] = None
        self._last_planner:     Optional[AgentDecision] = None
        self._last_report:      Optional[AgentDecision] = None
        self._last_range:       Optional[AgentDecision] = None
        self._last_maintenance: Optional[AgentDecision] = None

        self._log.info(
            "Orchestrator initialised — DB: %s | Agents: 5", self._db.db_path
        )

    # ------------------------------------------------------------------
    # Alert ID helpers  (rivian/ai-sast SHA-1 ID pattern)
    # ------------------------------------------------------------------

    @staticmethod
    def _assign_alert_id(decision: AgentDecision) -> AgentDecision:
        """Stamp each decision with an 8-char alert_id."""
        decision.alert_id = AlertDatabase.make_alert_id(
            decision.agent_name, decision.message, decision.timestamp
        )
        return decision

    # ------------------------------------------------------------------
    # Main per-tick processing
    # ------------------------------------------------------------------

    async def process(self, telemetry: TelemetryData) -> List[AgentDecision]:
        decisions: List[AgentDecision] = []

        # Agent 1 — Anomaly Detection
        anomaly = await self.anomaly_agent.analyze(telemetry)
        if anomaly:
            self._assign_alert_id(anomaly)
            self._last_anomaly = anomaly
            self._persist(anomaly)
            decisions.append(anomaly)

        # Agent 2 — Context-Aware Planner
        planner = await self.planner_agent.analyze(telemetry)
        if planner:
            self._assign_alert_id(planner)
            self._last_planner = planner
            self._persist(planner)
            decisions.append(planner)

        # Agent 4 — Range Prediction (run before reporter)
        range_dec = await self.range_agent.analyze(telemetry)
        self._assign_alert_id(range_dec)
        self._last_range = range_dec
        if range_dec.severity in ("CRITICAL", "WARNING"):
            self._persist(range_dec)
        decisions.append(range_dec)

        # Agent 5 — Predictive Maintenance
        maint = await self.maintenance_agent.analyze(telemetry, anomaly)
        self._assign_alert_id(maint)
        self._last_maintenance = maint
        if maint.severity in ("CRITICAL", "WARNING"):
            self._persist(maint)
        decisions.append(maint)

        # Agent 3 — LLM Status Reporter  (uses feedback context from DB)
        report = await self.reporter_agent.generate_report(
            telemetry, anomaly, planner, range_dec, maint
        )
        if report:
            self._assign_alert_id(report)
            self._last_report = report
            decisions.append(report)

        return decisions

    def _persist(self, decision: AgentDecision) -> None:
        """Store critical/warning alerts in SQLite (rivian/ai-sast pattern)."""
        try:
            self._db.store_alert(
                alert_id=decision.alert_id,
                agent_name=decision.agent_name,
                decision_type=decision.decision_type,
                severity=decision.severity,
                message=decision.message,
                dtc_code=decision.dtc_code or None,
                cvss_score=decision.cvss_score or None,
                cvss_vector=decision.cvss_vector or None,
                metadata=decision.metadata,
            )
        except Exception as exc:
            self._log.debug("Persist skipped: %s", exc)

    def record_feedback(
        self,
        alert_id: str,
        status: str,
        comment: str = "",
    ) -> bool:
        """
        Operator marks an alert as confirmed_alert or false_positive.
        Mirrors rivian/ai-sast store_feedback() — feeds back into LLM context.
        """
        # Find the alert in DB
        rows = self._db.get_recent_alerts(limit=200)
        target = next((r for r in rows if r["alert_id"] == alert_id), None)
        if target is None:
            self._log.warning("Feedback for unknown alert_id: %s", alert_id)
            return False
        return self._db.store_feedback(
            alert_id=alert_id,
            agent_name=target["agent_name"],
            decision_type=target["decision_type"],
            severity=target["severity"],
            message=target["message"],
            dtc_code=target.get("dtc_code"),
            status=status,
            comment=comment,
        )

    # ------------------------------------------------------------------
    # Serialisation  — NATS-style subject field added (rivian/nats pattern)
    # ------------------------------------------------------------------

    def to_json(
        self,
        decisions: List[AgentDecision],
        telemetry: TelemetryData,
    ) -> str:
        """
        Produce the full broadcast payload.
        Each decision carries a NATS-style subject string for future routing:
          vehicle.agents.anomaly | vehicle.agents.planner | etc.
        """
        subject_map = {
            "PRIORITY_ALERT":    "vehicle.agents.anomaly",
            "BATTERY_WARMING":   "vehicle.agents.planner",
            "STATUS_REPORT":     "vehicle.agents.reporter",
            "RANGE_ESTIMATE":    "vehicle.agents.range",
            "MAINTENANCE_STATUS":"vehicle.agents.maintenance",
        }

        def _serialise(d: AgentDecision) -> Dict:
            return {
                "subject":       subject_map.get(d.decision_type, "vehicle.agents.unknown"),
                "agent_name":    d.agent_name,
                "decision_type": d.decision_type,
                "message":       d.message,
                "severity":      d.severity,
                "timestamp":     d.timestamp,
                "metadata":      d.metadata,
                # OBD-II / DTC fields (rivian/odxtools)
                "dtc_code":      d.dtc_code,
                "cvss_score":    d.cvss_score,
                "cvss_vector":   d.cvss_vector,
                # rivian/ai-sast alert id
                "alert_id":      d.alert_id,
            }

        db_stats = self._db.get_statistics()

        return json.dumps({
            "type":       "TELEMETRY_UPDATE",
            "subject":    "vehicle.broadcast",   # NATS-style top-level subject
            "telemetry":  asdict(telemetry),
            "decisions":  [_serialise(d) for d in decisions],
            "db_stats":   db_stats,
            "timestamp":  time.time(),
        })

    # ------------------------------------------------------------------
    # Properties
    # ------------------------------------------------------------------

    @property
    def last_report(self) -> str:
        return self.reporter_agent.last_report

    @property
    def alert_db(self) -> AlertDatabase:
        return self._db

    async def shutdown(self) -> None:
        await self.reporter_agent.close()
        self._log.info("Orchestrator shut down cleanly.")
