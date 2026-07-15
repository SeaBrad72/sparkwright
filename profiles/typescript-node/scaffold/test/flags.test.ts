import { afterEach, describe, expect, it } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { isEnabled, resetProvider, setProvider, type FlagName } from '../src/flags.js';
import { fileConfigProvider } from '../src/live-provider.js';

const ENV = 'FEATURE_NEW_GREETING';
afterEach(() => {
  delete process.env[ENV];
  resetProvider(); // always restore the env floor so the seam tests can't leak into the others
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

  // Fail-safe by NAME (security): a flag name that collides with an inherited Object.prototype member
  // (toString, __proto__, …) must resolve OFF, not truthy. A bare `FLAGS[name]` fallback would return
  // the inherited function/object (truthy) and fail OPEN. Own-key + strict-boolean closes that.
  it.each(['toString', '__proto__', 'constructor', 'valueOf'])(
    'env floor: an inherited-proto name %j resolves OFF, not truthy (no fail-open)',
    (name) => {
      expect(isEnabled(name as FlagName)).toBe(false);
    },
  );
});

// The provider seam: the env floor is the default; a live provider is installable via setProvider().
describe('provider seam — the live flip (the non-vacuity anchor)', () => {
  let dir: string;
  let cfg: string;

  afterEach(() => {
    if (dir) rmSync(dir, { recursive: true, force: true });
  });

  it('flips a flag WITHOUT a restart — the change is OBSERVED, not just present', () => {
    dir = mkdtempSync(join(tmpdir(), 'flags-'));
    cfg = join(dir, 'flags.json');

    // Install the file-config live provider pointed at cfg.
    writeFileSync(cfg, JSON.stringify({ newGreeting: false }));
    setProvider(fileConfigProvider(cfg));
    const before = isEnabled('newGreeting');

    // Rewrite the SAME file — no re-import, no new process, same running module.
    writeFileSync(cfg, JSON.stringify({ newGreeting: true }));
    const after = isEnabled('newGreeting');

    // Assert the OBSERVED transition, not merely the end state (presence != proof).
    expect(before).toBe(false);
    expect(after).toBe(true);
    expect(after).not.toBe(before);
  });

  it('fail-safe: a missing / unreadable file falls back to the registry default (OFF), no throw', () => {
    setProvider(fileConfigProvider('/no/such/flags-file.json'));
    expect(() => isEnabled('newGreeting')).not.toThrow();
    expect(isEnabled('newGreeting')).toBe(false);
  });

  it('fail-safe: an unparseable file falls back to OFF, no throw', () => {
    dir = mkdtempSync(join(tmpdir(), 'flags-'));
    cfg = join(dir, 'flags.json');
    writeFileSync(cfg, 'not json {{{');
    setProvider(fileConfigProvider(cfg));
    expect(() => isEnabled('newGreeting')).not.toThrow();
    expect(isEnabled('newGreeting')).toBe(false);
  });

  it('fail-safe: a flag absent from the file falls back to its registry default (OFF)', () => {
    dir = mkdtempSync(join(tmpdir(), 'flags-'));
    cfg = join(dir, 'flags.json');
    writeFileSync(cfg, JSON.stringify({ someOtherFlag: true }));
    setProvider(fileConfigProvider(cfg));
    expect(isEnabled('newGreeting')).toBe(false);
  });

  it('no prototype pollution: a {"__proto__":{"newGreeting":true}} payload stays OFF', () => {
    dir = mkdtempSync(join(tmpdir(), 'flags-'));
    cfg = join(dir, 'flags.json');
    writeFileSync(cfg, '{"__proto__":{"newGreeting":true}}');
    setProvider(fileConfigProvider(cfg));
    expect(isEnabled('newGreeting')).toBe(false);
    // and the global prototype was not polluted by the read
    expect(({} as Record<string, unknown>).newGreeting).toBeUndefined();
  });

  it('strict coercion: only boolean true enables (a "true" string stays OFF)', () => {
    dir = mkdtempSync(join(tmpdir(), 'flags-'));
    cfg = join(dir, 'flags.json');
    writeFileSync(cfg, JSON.stringify({ newGreeting: 'true' }));
    setProvider(fileConfigProvider(cfg));
    expect(isEnabled('newGreeting')).toBe(false);
  });

  // Fail-safe by NAME (security): the file provider's own fallback must not fail OPEN on a name that
  // collides with an inherited Object.prototype member. With a valid file that does NOT carry the key,
  // the fallback path is exercised; own-key + strict-boolean keeps it OFF (and __proto__/constructor
  // are also rejected outright as forbidden keys).
  it.each(['toString', '__proto__', 'constructor', 'valueOf'])(
    'file provider: an inherited-proto name %j resolves OFF, not truthy (no fail-open)',
    (name) => {
      dir = mkdtempSync(join(tmpdir(), 'flags-'));
      cfg = join(dir, 'flags.json');
      writeFileSync(cfg, JSON.stringify({ newGreeting: false }));
      setProvider(fileConfigProvider(cfg));
      expect(isEnabled(name as FlagName)).toBe(false);
    },
  );
});
