"""Integration: the flag seam + telemetry wiring THROUGH the running server.

Unlike the unit tests (``is_enabled`` in isolation), here the flag registry, the
route handler, and the HTTP layer are exercised together against a real listening
socket in the SAME process — so ``pytest-cov`` measures ``server.py``. Mirrors the
typescript-node reference ``test/integration.test.ts``. The live-flip case is the
load-bearing proof that the provider seam reaches the REAL endpoint with no restart.
"""

from __future__ import annotations

import json
import threading
import time
import urllib.error
import urllib.request
import uuid
from collections.abc import Iterator
from email.message import Message
from http.server import HTTPServer
from pathlib import Path

import pytest

from app.flags import reset_provider, set_provider
from app.live_provider import file_config_provider
from app.server import AppHandler

# The four security headers expected on EVERY response (parity with server.ts).
EXPECTED_SECURITY_HEADERS: dict[str, str] = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Content-Security-Policy": "default-src 'none'",
    "Referrer-Policy": "no-referrer",
}


@pytest.fixture
def base_url() -> Iterator[str]:
    """Run the app server IN-THREAD on an ephemeral port; yield its base URL."""
    httpd = HTTPServer(("127.0.0.1", 0), AppHandler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        port = httpd.server_address[1]
        yield f"http://127.0.0.1:{port}"
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=5)


def _get(base: str, path: str) -> tuple[int, str, str | None]:
    """GET over real HTTP; return (status, body, content-type). Localhost only."""
    req = urllib.request.Request(base + path, method="GET")  # noqa: S310 (trusted localhost test URL)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:  # noqa: S310 (trusted localhost test URL)
            return resp.status, resp.read().decode("utf-8"), resp.getheader("Content-Type")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8"), exc.headers.get("Content-Type")


def _request(
    base: str,
    path: str,
    method: str = "GET",
    headers: dict[str, str] | None = None,
) -> tuple[int, str, Message]:
    """Any-method HTTP call; return (status, body, response headers). Localhost only.

    Headers are returned as the raw ``http.client.HTTPMessage`` so tests can assert
    on ``get_all`` (duplicate detection), not just presence.
    """
    req = urllib.request.Request(  # noqa: S310 (trusted localhost test URL)
        base + path, method=method, headers=headers or {}
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:  # noqa: S310 (trusted localhost test URL)
            return resp.status, resp.read().decode("utf-8"), resp.headers
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8"), exc.headers


def test_greeting_flag_off_serves_default(
    base_url: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("FEATURE_NEW_GREETING", raising=False)
    reset_provider()
    status, body, ctype = _get(base_url, "/greeting")
    assert status == 200
    assert ctype is not None and "application/json" in ctype
    assert body == '{"greeting":"Hello, world!"}'


def test_greeting_flag_on_serves_new(
    base_url: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    # monkeypatch deletes FEATURE_NEW_GREETING in teardown automatically.
    monkeypatch.setenv("FEATURE_NEW_GREETING", "true")
    reset_provider()
    status, body, _ = _get(base_url, "/greeting")
    assert status == 200
    assert body == '{"greeting":"Hello, world! (new)"}'


def test_healthz_returns_ok(base_url: str) -> None:
    status, body, _ = _get(base_url, "/healthz")
    assert status == 200
    assert body == '{"status":"ok"}'


def test_metrics_exposes_prometheus_counter(base_url: str) -> None:
    _get(base_url, "/greeting")  # generate at least one recorded request
    status, body, _ = _get(base_url, "/metrics")
    assert status == 200
    assert "http_requests_total" in body


def test_greeting_live_flip_on_same_running_server(
    base_url: str, tmp_path: Path
) -> None:
    """★ ENDPOINT-LEVEL LIVE FLIP — the load-bearing wiring proof.

    Install the file-config provider, then rewrite the SAME flag file and observe
    /greeting flip on the SAME running server with NO restart. Proves the seam
    flips the REAL endpoint, not a side process.
    """
    flag_file = tmp_path / "flags.json"
    flag_file.write_text(json.dumps({"new_greeting": False}), encoding="utf-8")
    set_provider(file_config_provider(str(flag_file)))
    try:
        _, body_off, _ = _get(base_url, "/greeting")
        assert body_off == '{"greeting":"Hello, world!"}'

        flag_file.write_text(json.dumps({"new_greeting": True}), encoding="utf-8")
        _, body_on, _ = _get(base_url, "/greeting")
        assert body_on == '{"greeting":"Hello, world! (new)"}'
    finally:
        reset_provider()


def test_get_response_carries_security_headers_and_neutral_server(base_url: str) -> None:
    """Finding 1a/4: a GET carries the four security headers exactly once, no version leak."""
    status, _, headers = _request(base_url, "/healthz")
    assert status == 200
    for name, value in EXPECTED_SECURITY_HEADERS.items():
        assert headers.get_all(name) == [value]  # present AND not duplicated
    assert headers.get("Server") == "reference-app"  # no BaseHTTP/Python version disclosure


@pytest.mark.parametrize("method", ["POST", "PUT", "DELETE", "PATCH", "OPTIONS"])
def test_non_get_returns_json_404_with_security_headers(base_url: str, method: str) -> None:
    """Finding 1b: a non-GET is method-agnostic -> JSON 404 WITH security headers."""
    status, body, headers = _request(base_url, "/greeting", method=method)
    assert status == 404
    assert body == '{"error":"not found"}'
    for name, value in EXPECTED_SECURITY_HEADERS.items():
        assert headers.get_all(name) == [value]
    assert "Python" not in (headers.get("Server") or "")


def test_head_returns_404_headers_without_body(base_url: str) -> None:
    """Finding 1b: HEAD gets a headered 404 with no body (per the reference posture)."""
    status, body, headers = _request(base_url, "/healthz", method="HEAD")
    assert status == 404
    assert body == ""
    for name in EXPECTED_SECURITY_HEADERS:
        assert name in headers


def _last_span_request_id(trace_file: Path, timeout: float = 2.0) -> str:
    """Poll the trace file for the request span, returning its request_id attribute.

    Telemetry is emitted AFTER the response is written (mirroring the reference
    ``res.finish``), so the span can land shortly after ``urlopen`` returns; polling
    also keeps the monkeypatched ``OTEL_TRACE_FILE`` alive until the emit runs.
    """
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if trace_file.exists():
            lines = trace_file.read_text(encoding="utf-8").splitlines()
            if lines:
                return str(json.loads(lines[-1])["attributes"]["request_id"])
        time.sleep(0.01)
    raise AssertionError("no span was emitted to the trace file within the timeout")


def test_valid_inbound_request_id_is_echoed(
    base_url: str, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Finding 5: a safe, bounded inbound X-Request-Id is honored into the span."""
    trace_file = tmp_path / "trace.jsonl"
    monkeypatch.setenv("OTEL_TRACE_FILE", str(trace_file))
    valid_id = "abc-123_valid.ID"
    status, _, _ = _request(base_url, "/healthz", headers={"X-Request-Id": valid_id})
    assert status == 200
    assert _last_span_request_id(trace_file) == valid_id


def test_oversized_inbound_request_id_is_replaced(
    base_url: str, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Finding 5: an oversized (>128) inbound X-Request-Id is rejected and minted fresh."""
    trace_file = tmp_path / "trace.jsonl"
    monkeypatch.setenv("OTEL_TRACE_FILE", str(trace_file))
    bad_id = "x" * 129
    status, _, _ = _request(base_url, "/healthz", headers={"X-Request-Id": bad_id})
    assert status == 200
    minted = _last_span_request_id(trace_file)
    assert minted != bad_id
    uuid.UUID(minted)  # a freshly minted uuid4, not the rejected inbound value
