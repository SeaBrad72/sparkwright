import { describe, expect, it } from 'vitest';
import type { AddressInfo } from 'node:net';
import { server } from '../src/server.js';

// E2E: a full user journey against the assembled service — liveness, the greeting feature, and the
// not-found path — proving end-to-end behaviour in-suite. DISTINCT from post-deploy smoke (which
// proves the deployed container is alive); this is the runnable oracle E3 executes per branch.
describe('e2e: service journey', () => {
  it('is live, serves a greeting, and 404s an unknown route', async () => {
    await new Promise<void>((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, resolve);
    });
    const { port } = server.address() as AddressInfo;
    const base = `http://127.0.0.1:${port}`;
    try {
      const health = await fetch(`${base}/healthz`);
      expect(health.status).toBe(200);
      expect(await health.json()).toEqual({ status: 'ok' });

      const greeting = await fetch(`${base}/greeting`);
      expect(greeting.status).toBe(200);
      expect((await greeting.json() as { greeting: string }).greeting).toMatch(/^Hello, world!/);

      const missing = await fetch(`${base}/nope`);
      expect(missing.status).toBe(404);
      expect(await missing.json()).toEqual({ error: 'not found' });
    } finally {
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }
  });
});
