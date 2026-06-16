"""Health surface.

`health()` is the pure, testable core. A minimal stdlib HTTP server exposes it
at GET /healthz, but only when this module is run as a script — importing it
(for tests) binds no port.
"""

from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, HTTPServer


def health() -> dict[str, str]:
    """Return the liveness payload."""
    return {"status": "ok"}


class HealthHandler(BaseHTTPRequestHandler):  # pragma: no cover
    """Serve GET /healthz -> 200 JSON; everything else -> 404.

    Excluded from coverage (like serve()/__main__): the I/O surface is not unit-tested;
    the pure health() core is. Swap for a tested framework handler as you grow.
    """

    def do_GET(self) -> None:  # noqa: N802  (stdlib-mandated method name)
        if self.path != "/healthz":
            self.send_response(404)
            self.end_headers()
            return
        body = json.dumps(health()).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def serve(host: str = "127.0.0.1", port: int = 8000) -> None:  # pragma: no cover
    """Start the blocking health server (script entry point only)."""
    HTTPServer((host, port), HealthHandler).serve_forever()


if __name__ == "__main__":  # pragma: no cover
    serve()
