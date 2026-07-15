"""Pure telemetry primitives — spans, metrics, and structured logs.

The importable core the app server calls per request. Mirrors the typescript-node
reference (src/server.ts): OTel-semantic spans in the exact scripts/otel-trace.sh
schema, bounded-cardinality Prometheus text exposition, and correlated JSON logs.

Deliberately stdlib-only and free of any socket/handler code: pure functions plus
module-level counter state, so the logic is unit-tested here and the I/O surface
(the server) is wired separately. Sinks are chosen by env, exactly like the
reference: spans go to OTEL_TRACE_FILE if set (append) else stdout; logs carry the
SERVICE_NAME (default "reference-app").
"""

from __future__ import annotations

import json
import secrets
from datetime import UTC, datetime
from os import environ

# Bounded label set. An unknown method is bucketed as "other" so a hostile caller
# cannot explode Prometheus series cardinality (path is intentionally NOT a label).
KNOWN_METHODS = frozenset({"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"})

# Module-level counter state (reset via reset_metrics() for test isolation).
_requests_total: dict[tuple[str, int], int] = {}
_duration_seconds_total: float = 0.0


def new_span_ids() -> tuple[str, str]:
    """Return a fresh (trace_id, span_id): 16-byte and 8-byte cryptographic hex."""
    return secrets.token_hex(16), secrets.token_hex(8)


def build_span(
    name: str,
    start_unix_nano: int,
    end_unix_nano: int,
    attributes: dict[str, str],
    status_code: int,
) -> dict[str, object]:
    """Build an OTel-semantic span dict in the reference otel-trace.sh schema.

    `*_unix_nano` are emitted as decimal STRINGS (OTLP/JSON represents them as
    strings — avoids the float precision loss unix nanos, ~1.8e18, would incur).
    `status.code` is ERROR for >= 500, else OK. A fresh trace/span id is minted and
    parent_span_id is None (root span); the server correlates via `attributes`.
    """
    trace_id, span_id = new_span_ids()
    return {
        "trace_id": trace_id,
        "span_id": span_id,
        "parent_span_id": None,
        "name": name,
        "start_unix_nano": str(start_unix_nano),
        "end_unix_nano": str(end_unix_nano),
        "attributes": attributes,
        "status": {"code": "ERROR" if status_code >= 500 else "OK"},
    }


def emit_span(span: dict[str, object]) -> None:
    """Write the span as one JSON line to OTEL_TRACE_FILE (append) if set, else stdout."""
    line = json.dumps(span)
    sink = environ.get("OTEL_TRACE_FILE")
    if sink:
        with open(sink, "a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    else:
        print(line)


def record_metric(method: str | None, status: int, latency_ms: float) -> None:
    """Increment the request counter for (method_label, status) and the duration total.

    method_label is the method when in KNOWN_METHODS, else "other" (bounded cardinality).
    """
    global _duration_seconds_total
    method_label = method if method in KNOWN_METHODS else "other"
    key = (method_label, status)
    _requests_total[key] = _requests_total.get(key, 0) + 1
    _duration_seconds_total += latency_ms / 1000.0


def escape_label_value(value: str) -> str:
    """Escape a Prometheus label value per the text exposition spec (\\, ", \\n).

    method is already normalised to a known set, but escaping is defensive: an
    unusual value can never break a series line or inject a new one.
    """
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def render_metrics() -> str:
    """Render the two counters as Prometheus text exposition (trailing newline)."""
    lines = [
        "# HELP http_requests_total Total number of HTTP requests handled.",
        "# TYPE http_requests_total counter",
    ]
    for (method, status), count in _requests_total.items():
        label = escape_label_value(method)
        lines.append(f'http_requests_total{{method="{label}",status="{status}"}} {count}')
    lines.append(
        "# HELP http_request_duration_seconds_total "
        "Total accumulated request duration in seconds."
    )
    lines.append("# TYPE http_request_duration_seconds_total counter")
    lines.append(f"http_request_duration_seconds_total {_duration_seconds_total}")
    return "\n".join(lines) + "\n"


def reset_metrics() -> None:
    """Clear module-level counter state (lifecycle/test helper)."""
    global _duration_seconds_total
    _requests_total.clear()
    _duration_seconds_total = 0.0


def log(fields: dict[str, object]) -> None:
    """Emit one structured JSON log line to stdout: ts, level, service, merged fields.

    Never pass request bodies, headers, or PII/secrets in `fields`.
    """
    service = environ.get("SERVICE_NAME", "reference-app")
    record: dict[str, object] = {
        "ts": datetime.now(UTC).isoformat(),
        "level": "info",
        "service": service,
        **fields,
    }
    print(json.dumps(record))
