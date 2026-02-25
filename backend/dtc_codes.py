#!/usr/bin/env python3
"""
Rivian Vehicle Intelligence — DTC Code Mapper
==============================================
Inspired by rivian/odxtools (MIT) — the open-source Python toolkit Rivian
uses to interact with automotive ECU diagnostic descriptions (ODX/UDS/OBD-II).
  https://github.com/rivian/odxtools

Maps agent decision types to standard automotive Diagnostic Trouble Codes
(DTCs) from:
  • SAE J2012 / ISO 15031-6 (OBD-II standardised DTCs)
  • SAE J1939 (heavy-duty vehicle network codes)
  • Manufacturer-specific P1xxx / U1xxx codes (Rivian-inspired)

Also assigns CVSS-style Vehicle Risk Scores (VRS) for each alert type,
following the structured severity model from rivian/ai-sast.
"""

from dataclasses import dataclass
from typing import Dict, Optional


@dataclass(frozen=True)
class DtcEntry:
    """
    Mirrors odxtools ECU service/response structure, adapted for runtime alerts.

    Fields
    ------
    code        SAE/ISO DTC string  (P0xxx | P1xxx | U0xxx | B1xxx | C0xxx)
    description Human-readable fault description
    system      Top-level ECU subsystem (Powertrain | Body | Network | Chassis)
    category    OBD-II semantic (CURRENTDATA | FUNCTION | TESTERPRESENT | …)
    cvss_score  Vehicle Risk Score 0.0-10.0  (ai-sast CVSS-inspired)
    cvss_vector VRS vector string encoding the risk dimensions
    """
    code: str
    description: str
    system: str
    category: str
    cvss_score: float
    cvss_vector: str


# ---------------------------------------------------------------------------
# DTC table — decision_type → DtcEntry
#
# VRS vector format (Vehicle Risk Score, adapted from CVSS 3.1):
#   VRS:1.0/AV:<Motor|Battery|Network|Thermal|Software>/
#          AC:<L|H>/MS:<C|U>/SI:<H|M|L>/CI:<H|M|L>
#   AV  = Attack Vector (which subsystem triggered this)
#   AC  = Alert Confidence (L=Low confidence, H=High confidence)
#   MS  = Mission Safety impact (C=Critical, U=Uncritical)
#   SI  = Safety Integrity (H/M/L)
#   CI  = Component Impact (H/M/L)
# ---------------------------------------------------------------------------

DTC_TABLE: Dict[str, DtcEntry] = {

    # ── Agent 1: Anomaly Detection ────────────────────────────────────
    "PRIORITY_ALERT": DtcEntry(
        code="P0218",
        description="Engine/Motor Overtemperature Condition",
        system="Powertrain",
        category="FUNCTION",
        cvss_score=9.1,
        cvss_vector="VRS:1.0/AV:Motor/AC:H/MS:C/SI:H/CI:H",
    ),

    # ── Agent 2: Context-Aware Planner ───────────────────────────────
    "BATTERY_WARMING": DtcEntry(
        code="P1A00",
        description="High Voltage Battery Pack Temperature Below Optimal Range",
        system="Powertrain",
        category="CURRENTDATA",
        cvss_score=5.3,
        cvss_vector="VRS:1.0/AV:Battery/AC:H/MS:U/SI:M/CI:M",
    ),

    # ── Agent 3: Status Reporter ──────────────────────────────────────
    "STATUS_REPORT": DtcEntry(
        code="U1001",
        description="Vehicle Telematics Status Update",
        system="Network",
        category="TESTERPRESENT",
        cvss_score=0.0,
        cvss_vector="VRS:1.0/AV:Network/AC:L/MS:U/SI:L/CI:L",
    ),

    # ── Agent 4: Range Prediction ─────────────────────────────────────
    "RANGE_ESTIMATE": DtcEntry(
        code="P1A10",
        description="Electric Vehicle Estimated Driving Range Calculation",
        system="Powertrain",
        category="CURRENTDATA",
        cvss_score=0.0,
        cvss_vector="VRS:1.0/AV:Battery/AC:H/MS:U/SI:L/CI:L",
    ),

    # ── Agent 5: Predictive Maintenance ──────────────────────────────
    "MAINTENANCE_STATUS": DtcEntry(
        code="B1090",
        description="Vehicle Health Monitor — Predictive Maintenance Required",
        system="Body",
        category="FUNCTION",
        cvss_score=3.7,
        cvss_vector="VRS:1.0/AV:Thermal/AC:H/MS:U/SI:M/CI:M",
    ),
}

# Severity-adjusted score overrides based on agent severity field
_SEVERITY_MULTIPLIERS: Dict[str, float] = {
    "CRITICAL": 1.0,
    "WARNING":  0.7,
    "INFO":     0.0,
}


def get_dtc(decision_type: str, severity: str = "INFO") -> Optional[DtcEntry]:
    """
    Return the DtcEntry for a given agent decision_type.
    Mirrors odxtools ECU service lookup pattern.
    """
    entry = DTC_TABLE.get(decision_type)
    if entry is None:
        return None

    # Adjust score by severity (CRITICAL keeps full score)
    multiplier = _SEVERITY_MULTIPLIERS.get(severity, 0.0)
    adjusted_score = round(entry.cvss_score * multiplier, 1)

    return DtcEntry(
        code=entry.code,
        description=entry.description,
        system=entry.system,
        category=entry.category,
        cvss_score=adjusted_score,
        cvss_vector=entry.cvss_vector,
    )


def dtc_summary(decision_type: str, severity: str = "INFO") -> Dict:
    """Return a JSON-serialisable dict suitable for WebSocket payloads."""
    entry = get_dtc(decision_type, severity)
    if entry is None:
        return {"dtc_code": "U0001", "cvss_score": 0.0, "cvss_vector": "N/A", "system": "Unknown"}
    return {
        "dtc_code":    entry.code,
        "dtc_desc":    entry.description,
        "system":      entry.system,
        "category":    entry.category,
        "cvss_score":  entry.cvss_score,
        "cvss_vector": entry.cvss_vector,
    }
