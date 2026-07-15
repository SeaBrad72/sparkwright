// Reference LIVE flag provider — a file-config FlagProvider that reflects changes WITHOUT a restart.
// This is the reference implementation of the live slot in the flags.ts seam: it re-reads a JSON flag
// file on every resolution, so rewriting the file flips behaviour in the SAME running process (a live
// runtime flip, not the env floor's restart-to-toggle). A SaaS provider (OpenFeature / Unleash /
// LaunchDarkly) is an adopter-pluggable alternative implementing the same `FlagProvider` — swap it in
// via setProvider() with no change to callers of isEnabled().
//
// TRUST BOUNDARY: `path` is APP-CONFIGURED (an operator-controlled deploy artifact), NOT end-user
// input. The file CONTENT is still treated as untrusted (it can be corrupted/tampered), so resolution
// is fully fail-safe and pollution-safe:
//   - fail-safe: a missing / unreadable / unparseable file, a non-object payload, or a flag absent
//     from the file all fall back to the registry default (FLAGS[name], i.e. OFF). isEnabled never
//     throws and never enables on error.
//   - no prototype pollution: the specific flag key is read via a hasOwnProperty check — the parsed
//     JSON is NEVER spread/merged into a config object — and `__proto__`/`constructor`/`prototype`
//     keys are rejected outright, so a crafted payload cannot poison Object.prototype or enable a flag.
//   - strict coercion: only the boolean `true` enables (mirrors the env floor's strict `=== 'true'`).
//
// PERFORMANCE CAVEAT: this provider does a SYNCHRONOUS `readFileSync` on EVERY `isEnabled` call. That
// is fine for a kill-switch and for the shipped default (the env floor does no FS read at all), but a
// profile/adopter that wires the file provider onto a HOT request path should add an mtime-gated cache
// (stat the file, re-parse only when it changed) so the resolution does not block the event loop.
import { readFileSync } from 'node:fs';
import { FLAGS, type FlagName, type FlagProvider } from './flags.js';

// Names that must never be resolved from file data (prototype-pollution / builtin-shadowing vectors).
const FORBIDDEN_KEYS = new Set(['__proto__', 'constructor', 'prototype']);

export function fileConfigProvider(path: string): FlagProvider {
  return {
    isEnabled(name: FlagName): boolean {
      // Fail-safe default: whatever the registry says (OFF) unless the file explicitly enables.
      // Own-key-only + strict boolean: a name colliding with an inherited Object.prototype member
      // (toString, __proto__, constructor, …) must NOT resolve truthy through the fallback (fail-safe).
      const fallback = Object.prototype.hasOwnProperty.call(FLAGS, name) && (FLAGS as Record<string, unknown>)[name] === true;
      if (FORBIDDEN_KEYS.has(name)) return fallback;
      let parsed: unknown;
      try {
        // Re-read per call: no cache to go stale, so a rewrite of the file is observed immediately
        // (the live flip). Zero-dep (node:fs only); the file is a small operator-owned config.
        parsed = JSON.parse(readFileSync(path, 'utf8'));
      } catch {
        return fallback; // missing / unreadable / unparseable -> OFF, never throw, never enable
      }
      // Only a plain JSON object can carry flags; arrays/null/scalars fall back.
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return fallback;
      // Read the SPECIFIC own key — never spread/merge the untrusted object anywhere.
      if (!Object.prototype.hasOwnProperty.call(parsed, name)) return fallback;
      const value = (parsed as Record<string, unknown>)[name];
      // Strict: only boolean true enables (a "true" string, 1, etc. stay OFF).
      return value === true;
    },
  };
}
