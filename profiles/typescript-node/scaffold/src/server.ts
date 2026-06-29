// Minimal stdlib HTTP server exposing GET /healthz -> 200 JSON via health().
// Kept separate from health.ts (and excluded from coverage in vitest.config.ts) so the
// pure logic is what the coverage gate measures — the socket-binding main guard is not.
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
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

export const server = createServer((req, res) => {
  const start = process.hrtime.bigint();
  // Honor an inbound correlation id (seeds distributed tracing later) ONLY if it is a safe, bounded
  // token; otherwise mint one. JSON.stringify already escapes the value (no log-line injection), but
  // validating bounds the length and rejects malformed ids defensively.
  const headerId = req.headers['x-request-id'];
  const raw = Array.isArray(headerId) ? headerId[0] : headerId;
  const requestId = raw && /^[A-Za-z0-9._-]{1,128}$/.test(raw) ? raw : randomUUID();

  res.on('finish', () => {
    const latencyMs = Math.round((Number(process.hrtime.bigint() - start) / 1e6) * 1000) / 1000;
    log({ requestId, method: req.method, path: req.url, status: res.statusCode, latencyMs });
  });

  if (req.method === 'GET' && req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json', ...SECURITY_HEADERS });
    res.end(JSON.stringify(health()));
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
