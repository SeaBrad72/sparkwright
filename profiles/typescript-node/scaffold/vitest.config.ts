import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      // server.ts binds a socket in a main guard — not unit-tested; the pure
      // logic in health.ts is what the gate measures.
      exclude: ['src/server.ts', 'src/healthcheck.ts'],
      thresholds: { lines: 80, functions: 80, branches: 80, statements: 80 },
    },
  },
});
