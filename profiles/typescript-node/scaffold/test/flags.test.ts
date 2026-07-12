import { afterEach, describe, expect, it } from 'vitest';
import { isEnabled } from '../src/flags.js';

const ENV = 'FEATURE_NEW_GREETING';
afterEach(() => {
  delete process.env[ENV];
});

describe('isEnabled', () => {
  it('defaults OFF when the env is unset (fail-safe kill-switch)', () => {
    delete process.env[ENV];
    expect(isEnabled('newGreeting')).toBe(false);
  });

  it('is ON only for the exact string "true"', () => {
    process.env[ENV] = 'true';
    expect(isEnabled('newGreeting')).toBe(true);
  });

  it.each(['1', 'TRUE', 'yes', '', 'false', ' true '])(
    'stays OFF for non-"true" value %j (strict parse, no accidental enable)',
    (val) => {
      process.env[ENV] = val;
      expect(isEnabled('newGreeting')).toBe(false);
    },
  );

  it('derives the env var name as FEATURE_NEW_GREETING', () => {
    process.env[ENV] = 'true';
    expect(isEnabled('newGreeting')).toBe(true); // would be false if the derived name didn't match
  });
});
