#!/usr/bin/env python3
"""
Rivian Vehicle Intelligence — Alert Persistence Database
=========================================================
Inspired by rivian/ai-sast (Apache 2.0) SQLite feedback pattern.
  https://github.com/rivian/ai-sast/blob/main/src/integrations/scan_database.py

Stores all agent decisions + operator feedback (confirmed / false-positive)
so the VehicleStatusReporter can include historical context in its LLM prompts,
improving accuracy over time — the same loop used in Rivian's ai-sast tool.

Schema
------
alerts   — every AgentDecision broadcast to clients
feedback — operator marks alert as confirmed_alert or false_positive
"""

import hashlib
import json
import logging
import os
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)

_DEFAULT_DB = Path.home() / ".rivian-vi" / "alerts.db"


class AlertDatabase:
    """
    Local SQLite store for vehicle intelligence alerts and operator feedback.

    Mirrors the ScanDatabase pattern from rivian/ai-sast:
      • store_alert()           ← equivalent to store_scan_result()
      • store_feedback()        ← equivalent to store_feedback()
      • get_confirmed_alerts()  ← equivalent to get_confirmed_vulnerabilities()
      • get_false_positives()   ← equivalent to get_false_positives()
      • format_context()        ← equivalent to format_feedback_for_context()
    """

    def __init__(self, db_path: Optional[str] = None) -> None:
        self.db_path = str(db_path or _DEFAULT_DB)
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        self._init_db()
        logger.info("AlertDatabase ready at %s", self.db_path)

    # ------------------------------------------------------------------
    # Schema setup
    # ------------------------------------------------------------------

    def _init_db(self) -> None:
        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()

        # All agent decisions
        cur.execute("""
            CREATE TABLE IF NOT EXISTS alerts (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                alert_id     TEXT NOT NULL,
                timestamp    TEXT NOT NULL,
                agent_name   TEXT NOT NULL,
                decision_type TEXT NOT NULL,
                severity     TEXT NOT NULL,
                message      TEXT NOT NULL,
                dtc_code     TEXT,
                cvss_score   REAL,
                cvss_vector  TEXT,
                metadata_json TEXT,
                created_at   TEXT NOT NULL,
                UNIQUE(alert_id)
            )
        """)

        # Operator feedback (true-positive / false-positive)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS feedback (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                alert_id     TEXT NOT NULL,
                timestamp    TEXT NOT NULL,
                agent_name   TEXT NOT NULL,
                decision_type TEXT NOT NULL,
                severity     TEXT NOT NULL,
                message      TEXT NOT NULL,
                dtc_code     TEXT,
                status       TEXT NOT NULL,
                comment      TEXT,
                created_at   TEXT NOT NULL,
                UNIQUE(alert_id, status)
            )
        """)

        # Indices (mirrors ai-sast index strategy)
        for stmt in [
            "CREATE INDEX IF NOT EXISTS idx_alerts_agent   ON alerts(agent_name)",
            "CREATE INDEX IF NOT EXISTS idx_alerts_ts      ON alerts(timestamp)",
            "CREATE INDEX IF NOT EXISTS idx_alerts_sev     ON alerts(severity)",
            "CREATE INDEX IF NOT EXISTS idx_feedback_agent ON feedback(agent_name)",
            "CREATE INDEX IF NOT EXISTS idx_feedback_status ON feedback(status)",
        ]:
            cur.execute(stmt)

        conn.commit()
        conn.close()

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def make_alert_id(agent_name: str, message: str, ts: float) -> str:
        """Deterministic 8-char hex ID — same SHA-1 approach as ai-sast."""
        raw = f"{agent_name}:{message[:80]}:{ts:.0f}"
        return hashlib.sha1(raw.encode()).hexdigest()[:8]

    # ------------------------------------------------------------------
    # Write operations
    # ------------------------------------------------------------------

    def store_alert(
        self,
        alert_id: str,
        agent_name: str,
        decision_type: str,
        severity: str,
        message: str,
        dtc_code: Optional[str] = None,
        cvss_score: Optional[float] = None,
        cvss_vector: Optional[str] = None,
        metadata: Optional[Dict] = None,
    ) -> bool:
        """Persist a single agent decision."""
        try:
            ts = datetime.now().isoformat()
            conn = sqlite3.connect(self.db_path)
            conn.execute("""
                INSERT OR IGNORE INTO alerts
                (alert_id, timestamp, agent_name, decision_type, severity,
                 message, dtc_code, cvss_score, cvss_vector, metadata_json, created_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """, (
                alert_id, ts, agent_name, decision_type, severity,
                message, dtc_code, cvss_score, cvss_vector,
                json.dumps(metadata or {}), ts,
            ))
            conn.commit()
            conn.close()
            return True
        except Exception as exc:
            logger.error("store_alert error: %s", exc)
            return False

    def store_feedback(
        self,
        alert_id: str,
        agent_name: str,
        decision_type: str,
        severity: str,
        message: str,
        status: str,          # "confirmed_alert" | "false_positive"
        dtc_code: Optional[str] = None,
        comment: Optional[str] = None,
    ) -> bool:
        """Record operator feedback on a specific alert."""
        try:
            ts = datetime.now().isoformat()
            conn = sqlite3.connect(self.db_path)
            conn.execute("""
                INSERT OR REPLACE INTO feedback
                (alert_id, timestamp, agent_name, decision_type, severity,
                 message, dtc_code, status, comment, created_at)
                VALUES (?,?,?,?,?,?,?,?,?,?)
            """, (
                alert_id, ts, agent_name, decision_type, severity,
                message, dtc_code, status, comment or "", ts,
            ))
            conn.commit()
            conn.close()
            logger.info("Feedback stored: %s → %s", alert_id, status)
            return True
        except Exception as exc:
            logger.error("store_feedback error: %s", exc)
            return False

    # ------------------------------------------------------------------
    # Read operations  (mirrors rivian/ai-sast get_false_positives /
    #                   get_confirmed_vulnerabilities)
    # ------------------------------------------------------------------

    def get_false_positives(
        self,
        days_back: int = 90,
        limit: int = 50,
    ) -> List[Dict]:
        return self._query_feedback("false_positive", days_back, limit)

    def get_confirmed_alerts(
        self,
        days_back: int = 90,
        limit: int = 50,
    ) -> List[Dict]:
        return self._query_feedback("confirmed_alert", days_back, limit)

    def _query_feedback(self, status: str, days_back: int, limit: int) -> List[Dict]:
        try:
            cutoff = (datetime.now() - timedelta(days=days_back)).isoformat()
            conn = sqlite3.connect(self.db_path)
            conn.row_factory = sqlite3.Row
            rows = conn.execute("""
                SELECT alert_id, agent_name, decision_type, severity,
                       message, dtc_code, comment, timestamp
                FROM   feedback
                WHERE  status = ? AND timestamp >= ?
                ORDER  BY timestamp DESC
                LIMIT  ?
            """, (status, cutoff, limit)).fetchall()
            conn.close()
            return [dict(r) for r in rows]
        except Exception as exc:
            logger.error("_query_feedback error: %s", exc)
            return []

    def get_recent_alerts(self, limit: int = 20) -> List[Dict]:
        """Fetch the most recent alerts for the overview panel."""
        try:
            conn = sqlite3.connect(self.db_path)
            conn.row_factory = sqlite3.Row
            rows = conn.execute("""
                SELECT alert_id, agent_name, decision_type, severity,
                       message, dtc_code, cvss_score, cvss_vector, timestamp
                FROM   alerts
                ORDER  BY timestamp DESC
                LIMIT  ?
            """, (limit,)).fetchall()
            conn.close()
            return [dict(r) for r in rows]
        except Exception as exc:
            logger.error("get_recent_alerts error: %s", exc)
            return []

    # ------------------------------------------------------------------
    # Context formatting  (rivian/ai-sast format_feedback_for_context)
    # ------------------------------------------------------------------

    def format_context_for_llm(self) -> str:
        """
        Build historical-context text to inject into the LLM prompt —
        the same technique used in rivian/ai-sast to improve AI accuracy
        over time by feeding past true/false-positive feedback back in.
        """
        false_positives  = self.get_false_positives(days_back=30, limit=10)
        confirmed_alerts = self.get_confirmed_alerts(days_back=30, limit=10)

        parts: List[str] = []

        if false_positives:
            parts.append("\n## Historical False Positive Alerts\nAvoid over-weighting these patterns:\n")
            for i, fp in enumerate(false_positives, 1):
                parts.append(
                    f"{i}. **Agent**: {fp['agent_name']} | "
                    f"**Issue**: {fp['message'][:60]} | "
                    f"**DTC**: {fp.get('dtc_code','N/A')} | "
                    f"**Severity**: {fp['severity']}"
                )
                if fp.get("comment"):
                    parts.append(f"   Reason: {fp['comment']}")

        if confirmed_alerts:
            parts.append("\n## Confirmed Alerts (Pay Attention)\nBe vigilant about similar patterns:\n")
            for i, ca in enumerate(confirmed_alerts, 1):
                parts.append(
                    f"{i}. **Agent**: {ca['agent_name']} | "
                    f"**Issue**: {ca['message'][:60]} | "
                    f"**DTC**: {ca.get('dtc_code','N/A')} | "
                    f"**Severity**: {ca['severity']}"
                )

        return "\n".join(parts)

    # ------------------------------------------------------------------
    # Statistics
    # ------------------------------------------------------------------

    def get_statistics(self) -> Dict:
        try:
            conn = sqlite3.connect(self.db_path)
            total_alerts = conn.execute("SELECT COUNT(*) FROM alerts").fetchone()[0]
            total_feedback = conn.execute("SELECT COUNT(*) FROM feedback").fetchone()[0]
            false_positives = conn.execute(
                "SELECT COUNT(*) FROM feedback WHERE status='false_positive'"
            ).fetchone()[0]
            confirmed = conn.execute(
                "SELECT COUNT(*) FROM feedback WHERE status='confirmed_alert'"
            ).fetchone()[0]
            conn.close()
            return {
                "total_alerts": total_alerts,
                "total_feedback": total_feedback,
                "false_positives": false_positives,
                "confirmed_alerts": confirmed,
            }
        except Exception as exc:
            logger.error("get_statistics error: %s", exc)
            return {}
