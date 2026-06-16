// Minimal stdlib HTTP server exposing GET /healthz -> 200 JSON via health().
// Kept separate from health.ts (and excluded from coverage in vitest.config.ts) so the
// pure logic is what the coverage gate measures — the socket-binding main guard is not.
import { createServer } from 'node:http';
import { health } from './health.js';

export const server = createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(health()));
    return;
  }
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found' }));
});

// Start only when run directly (not when imported by a test).
if (process.argv[1] && import.meta.url === `file://${process.argv[1]}`) {
  const port = Number(process.env.PORT ?? 3000);
  server.listen(port, () => console.log(`listening on :${port}`));
}
