// Feature-flag registry + resolver SEAM — the kit's kill-switch (E2). A typed, zero-dependency flag
// whose default is OFF, so an unset / unknown / malformed value can never silently enable a feature
// (fail-safe). This module is a PROVIDER SEAM (the shape the whole profile fan-out replicates):
//   - the FLOOR provider (`envProvider`) is env-driven and restart-to-toggle — dark-launch + a real
//     kill-switch, but NOT a live runtime flip;
//   - a pluggable live slot (`setProvider`) accepts any `FlagProvider` — e.g. the reference
//     file-config live provider (src/live-provider.ts, flips WITHOUT a restart) or an adopter's SaaS
//     provider (OpenFeature/Unleash/LaunchDarkly) implementing the same interface.
// The public API stays `isEnabled(name)` and delegates to whichever provider is active. See
// docs/operations/feature-flags.md. Adding a flag = one entry in FLAGS (the single place to
// enumerate live flags, so retiring one is a known list, not a code hunt).
export const FLAGS = { newGreeting: false } as const;
export type FlagName = keyof typeof FLAGS;

// camelCase flag -> SCREAMING_SNAKE env with a FEATURE_ prefix. newGreeting -> FEATURE_NEW_GREETING.
export function envName(name: FlagName): string {
  return `FEATURE_${name.replace(/[A-Z]/g, (c) => `_${c}`).toUpperCase()}`;
}

// The seam contract every provider (env floor, file-config live provider, or a SaaS provider) implements.
export interface FlagProvider {
  isEnabled(name: FlagName): boolean;
}

// The FLOOR provider: env-driven, restart-to-toggle, fail-safe OFF. (The original inline behaviour,
// extracted.) True ONLY when the env var is exactly "true"; otherwise the registry default (OFF).
export const envProvider: FlagProvider = {
  isEnabled(name) {
    const raw = process.env[envName(name)];
    // Own-key-only, strict-boolean fallback: a name that collides with an inherited Object.prototype
    // member (toString, __proto__, constructor, …) must NOT resolve truthy — fail-safe OFF, not open.
    return raw === undefined
      ? Object.prototype.hasOwnProperty.call(FLAGS, name) && (FLAGS as Record<string, unknown>)[name] === true
      : raw === 'true';
  },
};

// The pluggable seam. Default = the env floor; a live provider is installed by setProvider().
let activeProvider: FlagProvider = envProvider;
export function setProvider(p: FlagProvider): void {
  activeProvider = p;
}
export function resetProvider(): void {
  activeProvider = envProvider;
}

// Public API unchanged — delegates to the active provider.
export function isEnabled(name: FlagName): boolean {
  return activeProvider.isEnabled(name);
}
