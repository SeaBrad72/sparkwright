// Container HEALTHCHECK probe (referenced by the Dockerfile: `node dist/healthcheck.js`).
// GETs /healthz and exits 0 on 200, non-zero otherwise — no deps (node:http). Kept separate
// from server.ts and excluded from coverage (it's an entrypoint, not unit-tested logic).
import { get } from 'node:http';

const port = Number(process.env.PORT ?? 3000);
get(`http://127.0.0.1:${port}/healthz`, (res) => {
  process.exit(res.statusCode === 200 ? 0 : 1);
}).on('error', () => process.exit(1));
