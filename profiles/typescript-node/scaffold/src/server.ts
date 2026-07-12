// Minimal stdlib HTTP server exposing GET /healthz -> 200 JSON via health().
// Kept separate from health.ts (and excluded from coverage in vitest.config.ts) so the
// pure logic is what the coverage gate measures — the socket-binding main guard is not.
import { createServer } from 'node:http';
import { randomUUID, randomBytes } from 'node:crypto';
import { appendFileSync } from 'node:fs';
import { health } from './health.js';
import { isEnabled } from './flags.js';

const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Content-Security-Policy': "default-src 'none'",
  'Referrer-Policy': 'no-referrer',
} as const;

const SERVICE = process.env.SERVICE_NAME ?? 'reference-app';

// Structured JSON logging to stdout — one machine-parseable line per event
// (DEVELOPMENT-STANDARDS.md §3: every entry carries ts, level, fields, request/correlation id, service).
// Never log request bodies, headers, or any PII/secret — only routing + timing metadata. NOTE: `path`
// below is the full req.url INCLUDING any query string; an adopter whose query params can carry
// secrets/tokens must redact `path` before logging (the reference app's routes carry none).
function log(fields: Record<string, unknown>): void {
  console.log(JSON.stringify({ ts: new Date().toISOString(), level: 'info', service: SERVICE, ...fields }));
}

// E5-trace — emit one OTel-semantic span per request in the exact scripts/otel-trace.sh schema, so
// scripts/otlp-export.sh converts it to OTLP/JSON. Zero-dep (node:crypto + node:fs). Sink: OTEL_TRACE_FILE
// if set, else stdout (mirrors otel-trace.sh). The span correlates to the structured log line via the
// request_id attribute. `name` strips the query string (span cardinality + secret hygiene).
function emitSpan(span: Record<string, unknown>): void {
  const line = JSON.stringify(span);
  const sink = process.env.OTEL_TRACE_FILE;
  if (sink) appendFileSync(sink, line + '\n');
  else console.log(line);
}

// E5-metrics — zero-dep Prometheus text exposition (DEVELOPMENT-STANDARDS.md Factor 14: telemetry =
// metrics + traces + health, not just logs). Two counters keyed by BOUNDED labels (method, status —
// NOT path; cardinality + secret hygiene). An unknown method is bucketed as "other" so an attacker
// cannot explode series cardinality. Updated on res.finish; scraped at GET /metrics.
const KNOWN_METHODS = new Set(['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS']);
const requestsTotal = new Map<string, number>(); // key: `${methodLabel}|${status}`
let durationSecondsTotal = 0;

function recordMetric(method: string | undefined, status: number, latencyMs: number): void {
  const m = method && KNOWN_METHODS.has(method) ? method : 'other';
  const key = `${m}|${status}`;
  requestsTotal.set(key, (requestsTotal.get(key) ?? 0) + 1);
  durationSecondsTotal += latencyMs / 1000;
}

// Render Prometheus text exposition. Label values are escaped per the spec (\\, \", \n) so an unusual
// label can never break a series line — though method is already normalised to a known set above.
function renderMetrics(): string {
  const esc = (v: string) => v.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n');
  const lines = [
    '# HELP http_requests_total Total number of HTTP requests handled.',
    '# TYPE http_requests_total counter',
  ];
  for (const [key, count] of requestsTotal) {
    const [method, status] = key.split('|');
    lines.push(`http_requests_total{method="${esc(method)}",status="${esc(status)}"} ${count}`);
  }
  lines.push(
    '# HELP http_request_duration_seconds_total Total accumulated request duration in seconds.',
    '# TYPE http_request_duration_seconds_total counter',
    `http_request_duration_seconds_total ${durationSecondsTotal}`,
  );
  return lines.join('\n') + '\n';
}

export const server = createServer((req, res) => {
  const startMono = process.hrtime.bigint();
  const startNano = BigInt(Date.now()) * 1_000_000n; // wall-clock unix nanos at request start
  // Honor an inbound correlation id (seeds distributed tracing later) ONLY if it is a safe, bounded
  // token; otherwise mint one. JSON.stringify already escapes the value (no log-line injection), but
  // validating bounds the length and rejects malformed ids defensively.
  const headerId = req.headers['x-request-id'];
  const raw = Array.isArray(headerId) ? headerId[0] : headerId;
  const requestId = raw && /^[A-Za-z0-9._-]{1,128}$/.test(raw) ? raw : randomUUID();

  res.on('finish', () => {
    const endMono = process.hrtime.bigint();
    const latencyMs = Math.round((Number(endMono - startMono) / 1e6) * 1000) / 1000;
    log({ requestId, method: req.method, path: req.url, status: res.statusCode, latencyMs });
    recordMetric(req.method, res.statusCode, latencyMs);
    // OTel-semantic request span (real duration: wall-clock anchor + monotonic delta).
    const endNano = startNano + (endMono - startMono);
    const spanName = `${req.method} ${(req.url ?? '').split('?')[0]}`;
    emitSpan({
      trace_id: randomBytes(16).toString('hex'),
      span_id: randomBytes(8).toString('hex'),
      parent_span_id: null,
      name: spanName,
      // Exact decimal strings (OTLP/JSON represents *_unix_nano as strings) — avoids the IEEE-754
      // precision loss a JS Number incurs past ~9e15 (unix nanos are ~1.8e18).
      start_unix_nano: startNano.toString(),
      end_unix_nano: endNano.toString(),
      attributes: {
        'http.request.method': req.method,
        'http.response.status_code': String(res.statusCode),
        request_id: requestId,
      },
      status: { code: res.statusCode >= 500 ? 'ERROR' : 'OK' },
    });
  });

  if (req.method === 'GET' && req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json', ...SECURITY_HEADERS });
    res.end(JSON.stringify(health()));
    return;
  }
  if (req.method === 'GET' && req.url === '/metrics') {
    res.writeHead(200, { 'Content-Type': 'text/plain; version=0.0.4', ...SECURITY_HEADERS });
    res.end(renderMetrics());
    return;
  }
  if (req.method === 'GET' && req.url === '/greeting') {
    const greeting = isEnabled('newGreeting') ? 'Hello, world! (new)' : 'Hello, world!';
    res.writeHead(200, { 'Content-Type': 'application/json', ...SECURITY_HEADERS });
    res.end(JSON.stringify({ greeting }));
    return;
  }
  res.writeHead(404, { 'Content-Type': 'application/json', ...SECURITY_HEADERS });
  res.end(JSON.stringify({ error: 'not found' }));
});

// Start only when run directly (not when imported by a test).
if (process.argv[1] && import.meta.url === `file://${process.argv[1]}`) {
  const port = Number(process.env.PORT ?? 3000);
  server.listen(port, () => console.log(`listening on :${port}`));
}
