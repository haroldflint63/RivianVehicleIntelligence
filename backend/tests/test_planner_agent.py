"""Unit tests for ContextAwarePlannerAgent (backend/agents.py).

The agent returns BATTERY_WARMING when outside_temp < 32°F and battery >= 20%.
It has a 600-second cooldown between decisions; when battery < 20% in cold
weather, it returns None (no BATTERY_WARNING — that case is not implemented).
"""
import asyncio
import pytest
from conftest import make_telemetry
from agents import ContextAwarePlannerAgent


def run(coro):
    return asyncio.run(coro)


class TestContextAwarePlannerAgent:

    def setup_method(self):
        self.agent = ContextAwarePlannerAgent()

    def test_warm_weather_no_warming(self):
        """70°F outside, 80% battery → no BATTERY_WARMING (temp above threshold)."""
        decision = run(self.agent.analyze(
            make_telemetry(outside_temp=70.0, battery_percent=80.0)))
        assert decision is None

    def test_cold_weather_initiates_warming(self):
        """22°F outside, 50% battery → BATTERY_WARMING initiated."""
        decision = run(self.agent.analyze(
            make_telemetry(outside_temp=22.0, battery_percent=50.0)))
        assert decision is not None
        assert decision.decision_type == "BATTERY_WARMING"

    def test_cold_low_battery_returns_none(self):
        """22°F outside, battery < 20% → returns None (insufficient battery for warming)."""
        decision = run(self.agent.analyze(
            make_telemetry(outside_temp=22.0, battery_percent=15.0)))
        assert decision is None

    def test_cooldown_suppresses_repeat_warming(self):
        """Second cold-weather call within 600-second cooldown → suppressed (None)."""
        first = run(self.agent.analyze(
            make_telemetry(outside_temp=22.0, battery_percent=50.0)))
        assert first is not None and first.decision_type == "BATTERY_WARMING"
        # Immediately call again (< 600 s elapsed)
        second = run(self.agent.analyze(
            make_telemetry(outside_temp=22.0, battery_percent=50.0)))
        assert second is None

    def test_dtc_code_is_p1a00(self):
        """DTC code for battery warming must be P1A00."""
        decision = run(self.agent.analyze(
            make_telemetry(outside_temp=22.0, battery_percent=50.0)))
        assert decision is not None
        assert decision.dtc_code == "P1A00"

    def test_metadata_contains_outside_temp(self):
        """Metadata should expose outside_temp and battery_percent."""
        decision = run(self.agent.analyze(
            make_telemetry(outside_temp=22.0, battery_percent=50.0)))
        assert decision is not None
        assert "outside_temp" in decision.metadata
        assert "battery_percent" in decision.metadata

    def test_borderline_temp_exactly_at_threshold(self):
        """Exactly 32°F outside → NOT cold (threshold is strictly less than 32)."""
        decision = run(self.agent.analyze(
            make_telemetry(outside_temp=32.0, battery_percent=80.0)))
        assert decision is None

    def test_fixture_scenarios(self, sample_telemetry):
        """Verify agent handles all fixture scenarios without raising."""
        agent = ContextAwarePlannerAgent()  # fresh agent per fixture run
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
            result = run(agent.analyze(t))
            assert result is None or result.decision_type == "BATTERY_WARMING"
