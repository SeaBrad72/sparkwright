"""App server spine — wires the flags + telemetry modules into a running HTTP server.

The fuller counterpart to ``health.py``: a stdlib-only ``BaseHTTPRequestHandler``
that serves the real endpoints (``/healthz``, ``/metrics``, ``/greeting``, 404),
stamps security headers on every response, and emits per-request telemetry (a
structured log, a bounded-cardinality metric, and an OTel-semantic span). Mirrors
the typescript-node reference ``src/server.ts``.

``health()``'s pure core is imported (not re-implemented); the flag seam and the
telemetry primitives are wired here — the ONE place the profile assembles them.
The handler logic is unit-covered by the integration + e2e suites (the server runs
in-thread in the same process); only the socket-binding boot guard (``serve()`` /
``__main__``) is excluded from coverage, exactly like ``health.py``.
"""

from __future__ import annotations

import json
import os
import re
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

from app.flags import is_enabled, set_provider
from app.health import health
from app.live_provider import file_config_provider
from app.telemetry import build_span, emit_span, log, record_metric, render_metrics

# Stamped on every response — a hardened baseline for a JSON/text API that serves no
# markup: block sniffing/framing, deny all subresources, and leak no referrer.
SECURITY_HEADERS: dict[str, str] = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Content-Security-Policy": "default-src 'none'",
    "Referrer-Policy": "no-referrer",
}

# Honor an inbound X-Request-Id ONLY if it is a safe, bounded token; else mint one.
# Bounding the length + charset rejects malformed/oversized ids defensively.
_REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9._-]{1,128}$")


def _json(payload: dict[str, object]) -> bytes:
    """Compact JSON bytes (no inter-token spaces) — matches the reference server.ts."""
    return json.dumps(payload, separators=(",", ":")).encode("utf-8")


class AppHandler(BaseHTTPRequestHandler):
    """Serve routes with security headers + per-request telemetry on EVERY method.

    Single-connection posture: ``HTTPServer`` handles one connection at a time and
    ``timeout`` bounds each socket read, so a client that opens a socket and sends
    nothing is dropped rather than hanging the server (slowloris/idle-connection
    defense). An adopter expecting real concurrency/load should front this with a
    threaded/async server (e.g. ``ThreadingHTTPServer``).
    """

    # Drop a stalled/idle connection after this many seconds of silence.
    timeout = 10

    def version_string(self) -> str:
        """Neutralize the ``Server`` header — no interpreter/library version disclosure."""
        return "reference-app"

    def log_message(self, format: str, *args: object) -> None:  # noqa: A002 (stdlib signature)
        """Silence the default stderr access log — telemetry.log() is the record."""

    def end_headers(self) -> None:
        """Stamp the security baseline on EVERY response before finalizing headers.

        Overriding here (not in ``_respond``) means even stdlib ``send_error`` output
        — e.g. an unhandled method — carries the security headers, keeping the
        docstring's "security headers on every response" true.
        """
        for name, value in SECURITY_HEADERS.items():
            self.send_header(name, value)
        super().end_headers()

    def _dispatch(self) -> tuple[int, str, bytes]:
        """Route the request path (query stripped) -> (status, content_type, body)."""
        path = self.path.split("?", 1)[0]
        if path == "/healthz":
            return 200, "application/json", _json(dict(health()))
        if path == "/metrics":
            return 200, "text/plain; version=0.0.4", render_metrics().encode("utf-8")
        if path == "/greeting":
            greeting = "Hello, world! (new)" if is_enabled("new_greeting") else "Hello, world!"
            return 200, "application/json", _json({"greeting": greeting})
        return 404, "application/json", _json({"error": "not found"})

    def _respond(
        self, status: int, content_type: str, body: bytes, *, with_body: bool = True
    ) -> None:
        """Write status line, headers, and (unless a HEAD) the body.

        Security headers are added by ``end_headers`` (every response), so they are
        NOT stamped here — avoiding duplicate header emission.
        """
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body) if with_body else 0))
        self.end_headers()
        if with_body:
            self.wfile.write(body)

    def _request_id(self) -> str:
        """Return a validated inbound X-Request-Id, or a freshly minted one."""
        raw = self.headers.get("X-Request-Id")
        if raw is not None and _REQUEST_ID_RE.match(raw):
            return raw
        return str(uuid.uuid4())

    def _handle(self, method: str) -> None:
        """Dispatch + write, then emit per-request telemetry — for ANY method.

        BaseHTTPRequestHandler exposes no finish callback, so timing + telemetry are
        done inline around the dispatch: a monotonic clock measures latency, a
        wall-clock anchor dates the span, and the query string is stripped from the
        span name (cardinality + secret hygiene). Only GET is routed; every other
        method falls through to a hardened JSON 404 (method-agnostic, mirroring the
        typescript-node reference) so it too carries security headers + telemetry.
        """
        start_mono = time.monotonic_ns()
        start_nano = time.time_ns()
        request_id = self._request_id()

        if method == "GET":
            status, content_type, body = self._dispatch()
        else:
            status, content_type, body = 404, "application/json", _json({"error": "not found"})
        self._respond(status, content_type, body, with_body=method != "HEAD")

        end_mono = time.monotonic_ns()
        latency_ms = (end_mono - start_mono) / 1_000_000
        span_name = f"{method} {self.path.split('?', 1)[0]}"
        # NOTE: `path` is the full request path INCLUDING any query string. The reference
        # app's routes carry no secrets, but an adopter whose query params can carry
        # tokens/secrets MUST redact `path` here before logging (the span name above
        # already strips the query string).
        log(
            {
                "request_id": request_id,
                "method": method,
                "path": self.path,
                "status": status,
                "latency_ms": latency_ms,
            }
        )
        record_metric(method, status, latency_ms)
        emit_span(
            build_span(
                name=span_name,
                start_unix_nano=start_nano,
                end_unix_nano=start_nano + (end_mono - start_mono),
                attributes={
                    "http.request.method": method,
                    "http.response.status_code": str(status),
                    "request_id": request_id,
                },
                status_code=status,
            )
        )

    def do_GET(self) -> None:  # noqa: N802 (stdlib-mandated method name)
        """Serve the GET routes (the only routed method)."""
        self._handle("GET")

    def do_POST(self) -> None:  # noqa: N802 (stdlib-mandated method name)
        """Non-routed method -> hardened JSON 404 with headers + telemetry."""
        self._handle("POST")

    def do_PUT(self) -> None:  # noqa: N802 (stdlib-mandated method name)
        """Non-routed method -> hardened JSON 404 with headers + telemetry."""
        self._handle("PUT")

    def do_DELETE(self) -> None:  # noqa: N802 (stdlib-mandated method name)
        """Non-routed method -> hardened JSON 404 with headers + telemetry."""
        self._handle("DELETE")

    def do_PATCH(self) -> None:  # noqa: N802 (stdlib-mandated method name)
        """Non-routed method -> hardened JSON 404 with headers + telemetry."""
        self._handle("PATCH")

    def do_OPTIONS(self) -> None:  # noqa: N802 (stdlib-mandated method name)
        """Non-routed method -> hardened JSON 404 with headers + telemetry."""
        self._handle("OPTIONS")

    def do_HEAD(self) -> None:  # noqa: N802 (stdlib-mandated method name)
        """Non-routed method -> headered JSON 404 status, no body (HEAD semantics)."""
        self._handle("HEAD")


def serve(host: str = "127.0.0.1", port: int | None = None) -> None:  # pragma: no cover
    """Start the blocking app server (script entry point only).

    FLAG_FILE boot gate (the load-bearing wiring): when ``FLAG_FILE`` is set, install
    the file-config live provider BEFORE listening, so the running server's /greeting
    reflects live file flips with no restart. Unset -> the env floor (default).
    """
    flag_file = os.environ.get("FLAG_FILE")
    if flag_file:
        set_provider(file_config_provider(flag_file))
    if port is None:
        port = int(os.environ.get("PORT", "8000"))
    HTTPServer((host, port), AppHandler).serve_forever()


if __name__ == "__main__":  # pragma: no cover
    serve()
