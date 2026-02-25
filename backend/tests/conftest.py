"""Shared pytest fixtures for Rivian Vehicle Intelligence tests."""
import json
import pathlib
import pytest
from agents import TelemetryData

FIXTURES_DIR = pathlib.Path(__file__).parent / "fixtures"


@pytest.fixture
def sample_telemetry():
    """Load all sample telemetry scenarios from JSON fixture."""
    with open(FIXTURES_DIR / "sample_telemetry.json") as f:
        return json.load(f)


def make_telemetry(
    motor_temp=158.0,
    battery_percent=75.0,
    outside_temp=65.0,
    cabin_temp=72.0,
    vehicle_speed=45.0,
    battery_voltage=354.0,
    regen_power=2.0,
    motor_rpm=3200.0,
) -> TelemetryData:
    """Helper to construct a TelemetryData with sensible defaults."""
    return TelemetryData(
        motor_temp=motor_temp,
        battery_percent=battery_percent,
        outside_temp=outside_temp,
        cabin_temp=cabin_temp,
        vehicle_speed=vehicle_speed,
        battery_voltage=battery_voltage,
        regen_power=regen_power,
        motor_rpm=motor_rpm,
    )
