"""Tests for the pure telemetry module (spans, metrics, structured logs).

Mirrors the typescript-node reference helpers in src/server.ts: OTel-semantic
spans, bounded-cardinality Prometheus metrics, and correlated JSON logs — but as
a pure, importable module (no socket/handler code) that the app server calls.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest

from app import telemetry


@pytest.fixture(autouse=True)
def _reset_metrics() -> None:
    """Isolate module-level counter state between tests."""
    telemetry.reset_metrics()


def test_new_span_ids_are_hex_of_the_right_width() -> None:
    trace_id, span_id = telemetry.new_span_ids()
    assert len(trace_id) == 32  # 16 bytes hex
    assert len(span_id) == 16  # 8 bytes hex
    int(trace_id, 16)  # valid hex (raises otherwise)
    int(span_id, 16)


def test_new_span_ids_are_random() -> None:
    assert telemetry.new_span_ids() != telemetry.new_span_ids()


def test_build_span_has_all_required_keys() -> None:
    span = telemetry.build_span(
        name="GET /healthz",
        start_unix_nano=1,
        end_unix_nano=2,
        attributes={"http.request.method": "GET"},
        status_code=200,
    )
    for key in (
        "trace_id",
        "span_id",
        "parent_span_id",
        "name",
        "start_unix_nano",
        "end_unix_nano",
        "attributes",
        "status",
    ):
        assert key in span
    assert span["name"] == "GET /healthz"
    assert span["parent_span_id"] is None
    assert span["attributes"] == {"http.request.method": "GET"}
    trace_id = span["trace_id"]
    span_id = span["span_id"]
    assert isinstance(trace_id, str)
    assert isinstance(span_id, str)
    assert len(trace_id) == 32
    assert len(span_id) == 16


def test_build_span_nanos_are_decimal_strings() -> None:
    span = telemetry.build_span(
        name="x",
        start_unix_nano=1_700_000_000_000_000_000,
        end_unix_nano=1_700_000_000_500_000_000,
        attributes={},
        status_code=200,
    )
    assert span["start_unix_nano"] == "1700000000000000000"
    assert span["end_unix_nano"] == "1700000000500000000"
    assert isinstance(span["start_unix_nano"], str)
    assert isinstance(span["end_unix_nano"], str)


def test_build_span_status_ok_below_500() -> None:
    span = telemetry.build_span(
        name="x", start_unix_nano=1, end_unix_nano=2, attributes={}, status_code=404
    )
    assert span["status"] == {"code": "OK"}


def test_build_span_status_error_at_or_above_500() -> None:
    span = telemetry.build_span(
        name="x", start_unix_nano=1, end_unix_nano=2, attributes={}, status_code=500
    )
    assert span["status"] == {"code": "ERROR"}


def test_emit_span_appends_ndjson_to_otel_trace_file(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    sink = tmp_path / "traces.ndjson"
    monkeypatch.setenv("OTEL_TRACE_FILE", str(sink))
    telemetry.emit_span({"trace_id": "a", "name": "one"})
    telemetry.emit_span({"trace_id": "b", "name": "two"})

    lines = sink.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 2
    assert json.loads(lines[0])["name"] == "one"
    assert json.loads(lines[1])["name"] == "two"


def test_emit_span_writes_ndjson_to_stdout_when_unset(
    capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("OTEL_TRACE_FILE", raising=False)
    telemetry.emit_span({"trace_id": "a", "name": "one"})
    out = capsys.readouterr().out
    assert json.loads(out.strip())["name"] == "one"
    assert out.endswith("\n")


def test_record_metric_increments_the_right_series() -> None:
    telemetry.record_metric("GET", 200, 12.0)
    telemetry.record_metric("GET", 200, 8.0)
    telemetry.record_metric("POST", 201, 5.0)
    out = telemetry.render_metrics()
    assert 'http_requests_total{method="GET",status="200"} 2' in out
    assert 'http_requests_total{method="POST",status="201"} 1' in out


def test_record_metric_buckets_unknown_method_as_other() -> None:
    telemetry.record_metric("BREW", 418, 1.0)
    out = telemetry.render_metrics()
    assert 'http_requests_total{method="other",status="418"} 1' in out
    assert "BREW" not in out


def test_record_metric_buckets_none_method_as_other() -> None:
    telemetry.record_metric(None, 200, 1.0)
    out = telemetry.render_metrics()
    assert 'http_requests_total{method="other",status="200"} 1' in out


def test_render_metrics_accumulates_duration_seconds() -> None:
    telemetry.record_metric("GET", 200, 1500.0)  # 1.5s
    telemetry.record_metric("GET", 200, 500.0)  # 0.5s
    out = telemetry.render_metrics()
    assert "http_request_duration_seconds_total 2.0" in out


def test_render_metrics_emits_help_and_type_lines() -> None:
    telemetry.record_metric("GET", 200, 1.0)
    out = telemetry.render_metrics()
    assert "# HELP http_requests_total" in out
    assert "# TYPE http_requests_total counter" in out
    assert "# HELP http_request_duration_seconds_total" in out
    assert "# TYPE http_request_duration_seconds_total counter" in out
    assert out.endswith("\n")


def test_render_metrics_on_empty_state_is_valid_exposition() -> None:
    out = telemetry.render_metrics()
    assert "# TYPE http_requests_total counter" in out
    assert "http_request_duration_seconds_total 0" in out


def test_escape_label_value_escapes_hostile_input() -> None:
    hostile = 'evil"\\\n} injected 999'
    escaped = telemetry.escape_label_value(hostile)
    assert '"' not in escaped.replace('\\"', "")  # every quote is backslash-escaped
    assert "\n" not in escaped  # newline escaped, cannot break the line
    assert escaped == 'evil\\"\\\\\\n} injected 999'


def test_log_emits_structured_json_line(
    capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("SERVICE_NAME", raising=False)
    telemetry.log({"request_id": "abc", "status": 200})
    out = capsys.readouterr().out
    record: dict[str, Any] = json.loads(out.strip())
    assert record["level"] == "info"
    assert record["service"] == "reference-app"
    assert record["request_id"] == "abc"
    assert record["status"] == 200
    assert "ts" in record


def test_log_uses_service_name_env_when_set(
    capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("SERVICE_NAME", "checkout-svc")
    telemetry.log({"request_id": "abc"})
    record = json.loads(capsys.readouterr().out.strip())
    assert record["service"] == "checkout-svc"
