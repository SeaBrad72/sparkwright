"""E2E: a full user journey against the assembled service.

Liveness -> the greeting feature -> a not-found route, proving end-to-end behaviour
in-suite. DISTINCT from post-deploy ``scripts/smoke.sh`` (which proves a deployed
container is alive); this is the runnable in-process oracle. Mirrors the reference
``test/e2e.test.ts``.
"""

from __future__ import annotations

import threading
import urllib.error
import urllib.request
from collections.abc import Iterator
from http.server import HTTPServer

import pytest

from app.server import AppHandler


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


def _get(base: str, path: str) -> tuple[int, str]:
    """GET over real HTTP; return (status, body). Localhost only."""
    req = urllib.request.Request(base + path, method="GET")  # noqa: S310 (trusted localhost test URL)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:  # noqa: S310 (trusted localhost test URL)
            return resp.status, resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8")


def test_service_journey_live_greeting_then_404(base_url: str) -> None:
    status, body = _get(base_url, "/healthz")
    assert status == 200
    assert body == '{"status":"ok"}'

    status, body = _get(base_url, "/greeting")
    assert status == 200
    assert body.startswith('{"greeting":"Hello, world!')

    status, body = _get(base_url, "/nope")
    assert status == 404
    assert body == '{"error":"not found"}'
