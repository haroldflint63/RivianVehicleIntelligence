"""Unit tests for AnomalyDetectionAgent (backend/agents.py)."""
import asyncio
import pytest
from conftest import make_telemetry
from agents import AnomalyDetectionAgent


def run(coro):
    return asyncio.run(coro)


class TestAnomalyDetectionAgent:

    def setup_method(self):
        self.agent = AnomalyDetectionAgent()

    def _warm_up(self, n=20, base_temp=158.0):
        """Feed n readings with alternating slight variance to populate the window
        with a non-zero std, so subsequent anomaly checks work correctly."""
        for i in range(n):
            # Alternate slightly above/below to create natural variance
            temp = base_temp + (1.5 if i % 2 == 0 else -1.5)
            run(self.agent.analyze(make_telemetry(motor_temp=temp)))

    # ------------------------------------------------------------------

    def test_returns_none_before_window_fills(self):
        """Fewer than 5 readings → agent returns None (insufficient data)."""
        for _ in range(4):
            result = run(self.agent.analyze(make_telemetry(motor_temp=158.0)))
        assert result is None

    def test_normal_temps_no_alert(self):
        """20 readings with slight variance followed by a similar reading → no alert."""
        self._warm_up(20, base_temp=158.0)
        # 159.5 is close to the mean (~158.0) → z-score should be low
        decision = run(self.agent.analyze(make_telemetry(motor_temp=159.5)))
        # Either None (no decision) or not a PRIORITY_ALERT for a normal reading
        if decision is not None:
            assert decision.decision_type != "PRIORITY_ALERT"

    def test_high_z_score_triggers_alert(self):
        """19 readings with slight variance + spike to 228°F → PRIORITY_ALERT."""
        self._warm_up(19, base_temp=158.0)
        decision = run(self.agent.analyze(make_telemetry(motor_temp=228.0)))
        assert decision is not None
        assert decision.decision_type == "PRIORITY_ALERT"

    def test_critical_temp_triggers_critical(self):
        """Motor temp spike to 260°F → PRIORITY_ALERT CRITICAL with DTC P0218."""
        self._warm_up(19, base_temp=158.0)
        decision = run(self.agent.analyze(make_telemetry(motor_temp=260.0)))
        assert decision is not None
        assert decision.decision_type == "PRIORITY_ALERT"
        assert decision.severity == "CRITICAL"
        assert decision.dtc_code == "P0218"

    def test_cooldown_suppresses_second_alert(self):
        """Second spike within COOLDOWN window (15 s) must be suppressed."""
        self._warm_up(19, base_temp=158.0)
        first = run(self.agent.analyze(make_telemetry(motor_temp=260.0)))
        assert first is not None and first.decision_type == "PRIORITY_ALERT"
        # Fire immediately again (< 15 s elapsed)
        second = run(self.agent.analyze(make_telemetry(motor_temp=260.0)))
        # Should be suppressed: None (cooldown active)
        assert second is None

    def test_metadata_has_z_score_mean_std(self):
        """PRIORITY_ALERT metadata must include z_score, mean, std."""
        self._warm_up(19, base_temp=158.0)
        decision = run(self.agent.analyze(make_telemetry(motor_temp=260.0)))
        assert decision is not None
        assert "z_score" in decision.metadata
        assert "mean" in decision.metadata
        assert "std" in decision.metadata
        assert decision.metadata["z_score"] >= AnomalyDetectionAgent.THRESHOLD

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
            # Should not raise; result is None or AgentDecision
            assert result is None or result.decision_type in ("PRIORITY_ALERT",)
