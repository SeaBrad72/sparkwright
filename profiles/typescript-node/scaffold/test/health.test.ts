import { describe, it, expect } from 'vitest';
import { health } from '../src/health.js';

describe('health', () => {
  it('reports ok', () => {
    expect(health()).toEqual({ status: 'ok' });
  });
});
