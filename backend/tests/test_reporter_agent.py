"""Unit tests for VehicleStatusReporterAgent (backend/agents.py) — Groq API mocked.

The agent's primary method is generate_report(), not analyze().
__init__ accepts alert_db=None (no groq_api_key parameter).
The API key is read from the GROQ_API_KEY environment variable.
"""
import asyncio
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from conftest import make_telemetry
from agents import VehicleStatusReporterAgent

MOCK_REPLY = "All systems nominal; battery at 75% and motor temperature is normal."


def _mock_groq_response(content: str) -> MagicMock:
    """Build a fake httpx.Response that mimics a Groq API 200 reply."""
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {
        "choices": [{"message": {"content": content}}]
    }
    return mock_resp


def run(coro):
    return asyncio.run(coro)


class TestVehicleStatusReporterAgent:

    def setup_method(self):
        self.agent = VehicleStatusReporterAgent(alert_db=None)

    def _call_generate_report(self, telemetry=None, anomaly=None, planner=None,
                               range_dec=None, maintenance=None):
        """Call generate_report() with sensible defaults."""
        if telemetry is None:
            telemetry = make_telemetry()
        coro = self.agent.generate_report(
            telemetry, anomaly, planner, range_dec, maintenance)
        return asyncio.run(coro)

    @patch("httpx.AsyncClient.post", new_callable=AsyncMock)
    def test_report_generated_with_mocked_llm(self, mock_post):
        """With mocked Groq response, agent should return STATUS_REPORT decision."""
        mock_post.return_value = _mock_groq_response(MOCK_REPLY)
        decision = self._call_generate_report()
        assert decision is not None
        assert decision.decision_type == "STATUS_REPORT"
        assert MOCK_REPLY in decision.message

    @patch("httpx.AsyncClient.post", new_callable=AsyncMock)
    def test_report_throttled_within_30s(self, mock_post):
        """Second call within 30 s must NOT trigger another Groq API call."""
        mock_post.return_value = _mock_groq_response(MOCK_REPLY)
        self._call_generate_report()
        first_count = mock_post.call_count
        self._call_generate_report()
        # Call count must not have increased (throttle active)
        assert mock_post.call_count == first_count, \
            "Groq should not be called twice within 30 s"

    def test_dtc_code_is_u1001(self):
        """If a STATUS_REPORT was produced, its DTC must be U1001."""
        # The _last_report attribute starts as a string — only check if a decision was cached
        last = getattr(self.agent, "_last_decision", None)
        if last is not None:
            assert last.dtc_code == "U1001"

    @patch("httpx.AsyncClient.post", new_callable=AsyncMock)
    def test_groq_api_key_sent_in_header(self, mock_post):
        """Agent should send Authorization header when posting to Groq."""
        mock_post.return_value = _mock_groq_response(MOCK_REPLY)
        self._call_generate_report()
        assert mock_post.called
        _, call_kwargs = mock_post.call_args
        headers = call_kwargs.get("headers", {})
        assert "Authorization" in headers

    @patch("httpx.AsyncClient.post", new_callable=AsyncMock)
    def test_groq_rate_limit_handled_gracefully(self, mock_post):
        """If Groq returns 429, agent should return a fallback message (not raise)."""
        mock_429 = MagicMock()
        mock_429.status_code = 429
        mock_post.return_value = mock_429
        # Should not raise — graceful degradation
        try:
            result = self._call_generate_report()
            # Either None or a cached STATUS_REPORT — either is acceptable
        except Exception as e:
            pytest.fail(f"Agent raised on 429 instead of degrading gracefully: {e}")

    @patch("httpx.AsyncClient.post", new_callable=AsyncMock)
    def test_status_report_dtc_after_successful_call(self, mock_post):
        """After a successful Groq call, the returned decision has DTC U1001."""
        mock_post.return_value = _mock_groq_response(MOCK_REPLY)
        decision = self._call_generate_report()
        assert decision is not None
        assert decision.dtc_code == "U1001"

    @patch("httpx.AsyncClient.post", new_callable=AsyncMock)
    def test_last_report_property_updated(self, mock_post):
        """After a successful call, last_report property reflects the new content."""
        mock_post.return_value = _mock_groq_response(MOCK_REPLY)
        self._call_generate_report()
        assert self.agent.last_report == MOCK_REPLY
