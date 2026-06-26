import { afterEach, describe, expect, it } from 'vitest';
import type { AddressInfo } from 'node:net';
import { server } from '../src/server.js';

// Integration: the feature flag wires THROUGH the running server to the /greeting response.
// Unlike the unit tests (isEnabled() in isolation), here the flag registry + route handler + HTTP
// layer are exercised together against a real listening socket. Zero deps: server.listen(0) + fetch.
const ENV = 'FEATURE_NEW_GREETING';

describe('integration: flag -> /greeting', () => {
  afterEach(() => { delete process.env[ENV]; });

  it('serves the default greeting with the flag OFF and the new one with it ON', async () => {
    await new Promise<void>((resolve) => server.listen(0, resolve));
    const { port } = server.address() as AddressInfo;
    const base = `http://127.0.0.1:${port}`;
    try {
      delete process.env[ENV];
      const off = await fetch(`${base}/greeting`);
      expect(off.status).toBe(200);
      expect(off.headers.get('content-type')).toContain('application/json');
      expect(await off.json()).toEqual({ greeting: 'Hello, world!' });

      process.env[ENV] = 'true';
      const on = await fetch(`${base}/greeting`);
      expect(await on.json()).toEqual({ greeting: 'Hello, world! (new)' });
    } finally {
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }
  });
});
