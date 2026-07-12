// Feature-flag registry + resolver — the kit's kill-switch FLOOR (E2). A typed, zero-dependency
// flag whose default is OFF, so an unset / unknown / malformed value can never silently enable a
// feature (fail-safe). Toggled by environment variable: a dark-launch + restart-to-toggle
// mechanism, NOT a live runtime flip. Live flips need a dynamic provider — see
// docs/operations/feature-flags.md. Adding a flag = one entry here (the single place to enumerate
// live flags, so retiring one is a known list, not a code hunt).
export const FLAGS = { newGreeting: false } as const;
export type FlagName = keyof typeof FLAGS;

// camelCase flag -> SCREAMING_SNAKE env with a FEATURE_ prefix. newGreeting -> FEATURE_NEW_GREETING.
function envName(name: FlagName): string {
  return `FEATURE_${name.replace(/[A-Z]/g, (c) => `_${c}`).toUpperCase()}`;
}

// True ONLY when the env var is exactly "true"; otherwise the registry default (fail-safe OFF).
export function isEnabled(name: FlagName): boolean {
  const raw = process.env[envName(name)];
  return raw === undefined ? FLAGS[name] : raw === 'true';
}
