"""Unit tests for PredictiveMaintenanceAgent (backend/agents.py).

The agent signature is: analyze(self, telemetry, anomaly=None)
where anomaly is an Optional[AgentDecision] (not an anomaly_count int).
"""
import asyncio
import pytest
from conftest import make_telemetry
from agents import PredictiveMaintenanceAgent


def run(coro):
    return asyncio.run(coro)


class TestPredictiveMaintenanceAgent:

    def setup_method(self):
        self.agent = PredictiveMaintenanceAgent()

    def test_new_vehicle_excellent_health(self):
        """Brand-new agent, one nominal reading → health score should be high."""
        decision = run(self.agent.analyze(make_telemetry(), anomaly=None))
        assert decision is not None
        score = decision.metadata["health_score"]
        assert score >= 70, f"New vehicle should have high health, got {score}"

    def test_sustained_high_stress_degrades_health(self):
        """Repeated high-temp readings should reduce health score over time."""
        initial = run(self.agent.analyze(
            make_telemetry(motor_temp=160.0, vehicle_speed=45.0), anomaly=None))
        for _ in range(30):
            run(self.agent.analyze(
                make_telemetry(motor_temp=240.0, motor_rpm=7000.0, vehicle_speed=90.0),
                anomaly=None))
        final = run(self.agent.analyze(
            make_telemetry(motor_temp=240.0, motor_rpm=7000.0, vehicle_speed=90.0),
            anomaly=None))
        assert initial is not None and final is not None
        assert final.metadata["health_score"] <= initial.metadata["health_score"]

    def test_health_score_never_exceeds_100(self):
        """Health score must be capped at 100."""
        decision = run(self.agent.analyze(make_telemetry(), anomaly=None))
        assert decision is not None
        assert decision.metadata["health_score"] <= 100

    def test_health_score_never_below_0(self):
        """Health score must never go below 0 even after extreme stress."""
        for _ in range(100):
            run(self.agent.analyze(
                make_telemetry(motor_temp=260.0, motor_rpm=9000.0, vehicle_speed=95.0),
                anomaly=None))
        decision = run(self.agent.analyze(
            make_telemetry(motor_temp=260.0, motor_rpm=9000.0, vehicle_speed=95.0),
            anomaly=None))
        assert decision is not None
        assert decision.metadata["health_score"] >= 0

    def test_dtc_code_is_b1090(self):
        """DTC code must be B1090."""
        decision = run(self.agent.analyze(make_telemetry(), anomaly=None))
        assert decision is not None
        assert decision.dtc_code == "B1090"

    def test_decision_type_is_maintenance_status(self):
        """Agent always returns MAINTENANCE_STATUS decision type."""
        decision = run(self.agent.analyze(make_telemetry(), anomaly=None))
        assert decision is not None
        assert decision.decision_type == "MAINTENANCE_STATUS"

    def test_metadata_keys_present(self):
        """Metadata must include health_score, status, action, cumulative_stress."""
        decision = run(self.agent.analyze(make_telemetry(), anomaly=None))
        assert decision is not None
        for key in ("health_score", "status", "action", "cumulative_stress"):
            assert key in decision.metadata, f"Missing metadata key: {key}"

    def test_fixture_scenarios(self, sample_telemetry):
        """Verify agent handles all fixture scenarios without raising."""
        for scenario in sample_telemetry:
            t = make_telemetry(
                motor_temp=scenario["motor_temp"],
                battery_percent=scenario["battery_percent"],
                outside_temp=scenario["outside_temp"],
                cabin_temp=scenario["cabin_temp"],
                vehicle_speed=scenario["vehicle_speed"],
                battery_voltage=scenario["battery_voltage"],
                regen_power=scenario["regen_power"],
                motor_rpm=scenario["motor_rpm"],
            )
            result = run(self.agent.analyze(t))
            assert result is not None
            assert result.decision_type == "MAINTENANCE_STATUS"
            assert 0 <= result.metadata["health_score"] <= 100
