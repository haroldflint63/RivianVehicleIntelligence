"""Unit tests for RangePredictionAgent (backend/agents.py)."""
import asyncio
import pytest
from conftest import make_telemetry
from agents import RangePredictionAgent

EPA_BASE = 314.0


def run(coro):
    return asyncio.run(coro)


class TestRangePredictionAgent:

    def setup_method(self):
        self.agent = RangePredictionAgent()

    def test_warm_full_battery_close_to_epa(self):
        """72°F, 100% battery, 45 mph, no regen → estimated range should be > 280 mi."""
        t = make_telemetry(outside_temp=72.0, battery_percent=100.0,
                           vehicle_speed=45.0, regen_power=0.0)
        decision = run(self.agent.analyze(t))
        assert decision is not None
        miles = decision.metadata["estimated_range_miles"]
        assert miles > 280, f"Expected >280 mi in warm weather with full battery, got {miles}"

    def test_cold_weather_reduces_range(self):
        """22°F outside → range should be ≤ 80% of EPA base (cold penalty)."""
        t = make_telemetry(outside_temp=22.0, battery_percent=100.0,
                           vehicle_speed=45.0, regen_power=0.0)
        decision = run(self.agent.analyze(t))
        assert decision is not None
        miles = decision.metadata["estimated_range_miles"]
        assert miles <= EPA_BASE * 0.80, \
            f"Cold weather range should be reduced, got {miles}"

    def test_high_speed_reduces_range_vs_moderate(self):
        """85 mph should yield less range than 45 mph (drag model)."""
        moderate = run(self.agent.analyze(
            make_telemetry(vehicle_speed=45.0, outside_temp=72.0, regen_power=0.0)))
        fast = run(self.agent.analyze(
            make_telemetry(vehicle_speed=85.0, outside_temp=72.0, regen_power=0.0)))
        assert moderate is not None and fast is not None
        assert fast.metadata["estimated_range_miles"] < moderate.metadata["estimated_range_miles"]

    def test_regen_credit_increases_range(self):
        """High regen_power (18 kW) should give >= range vs zero regen."""
        no_regen = run(self.agent.analyze(
            make_telemetry(regen_power=0.0, outside_temp=72.0)))
        with_regen = run(self.agent.analyze(
            make_telemetry(regen_power=18.0, outside_temp=72.0)))
        assert no_regen is not None and with_regen is not None
        assert with_regen.metadata["estimated_range_miles"] >= no_regen.metadata["estimated_range_miles"]

    def test_decision_type_is_range_estimate(self):
        """Agent always returns RANGE_ESTIMATE decision type."""
        decision = run(self.agent.analyze(make_telemetry()))
        assert decision is not None
        assert decision.decision_type == "RANGE_ESTIMATE"

    def test_dtc_code_is_p1a10(self):
        """DTC code for range estimates must be P1A10."""
        decision = run(self.agent.analyze(make_telemetry()))
        assert decision is not None
        assert decision.dtc_code == "P1A10"

    def test_metadata_contains_epa_base(self):
        """Metadata should expose epa_base_miles equal to EPA_BASE."""
        decision = run(self.agent.analyze(make_telemetry()))
        assert decision is not None
        assert "epa_base_miles" in decision.metadata
        assert decision.metadata["epa_base_miles"] == EPA_BASE

    def test_low_battery_reduces_range_proportionally(self):
        """50% battery → estimated range roughly half of 100% battery range."""
        full = run(self.agent.analyze(
            make_telemetry(battery_percent=100.0, outside_temp=72.0, regen_power=0.0)))
        half = run(self.agent.analyze(
            make_telemetry(battery_percent=50.0, outside_temp=72.0, regen_power=0.0)))
        assert full is not None and half is not None
        assert half.metadata["estimated_range_miles"] < full.metadata["estimated_range_miles"]

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
            assert result.decision_type == "RANGE_ESTIMATE"
            assert result.metadata["estimated_range_miles"] >= 0.0
