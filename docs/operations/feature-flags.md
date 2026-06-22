# Feature flags — the kill-switch floor

Feature flags **decouple code-merge from release**: you merge a feature "dark" (behind an
OFF flag), then enable it later — and disable it instantly if it misbehaves. That instant-off is
the **kill-switch**, the lowest-blast-radius rollback (see
[progressive-delivery.md](progressive-delivery.md) and `DEVELOPMENT-STANDARDS.md §10`: the rollback
preference order is **flag-off → redeploy previous → revert + redeploy**).

## The reference flag (typescript-node)

`src/flags.ts` is a typed registry; every flag **defaults OFF** (fail-safe — an unset, unknown, or
malformed value can never silently enable a feature). It resolves from an environment variable with
a strict `=== 'true'` parse:

| Flag (registry)  | Env var                 | Default |
|------------------|-------------------------|---------|
| `newGreeting`    | `FEATURE_NEW_GREETING`  | OFF     |

`GET /greeting` returns a different body depending on the flag. `scripts/smoke.sh` asserts the
endpoint honours the configured flag, and the `golden-path` workflow boots the image twice — once
OFF (kill-switch greeting), once ON — to **prove both branches end-to-end**.

## Flag lifecycle

1. **Add** — a new entry in `FLAGS`, default `false`. One place enumerates every live flag.
2. **Dark-launch** — merge the feature behind the OFF flag; `main` stays releasable.
3. **Enable** — set the env var to `true` and restart (see the honesty note below).
4. **Retire** — once the feature is permanently on (or abandoned), delete the flag entry **and**
   the now-dead OFF branch together. Because the registry is the single list of live flags,
   retirement is a known checklist, not a code hunt. Stale flags are tech debt — retire promptly.

## Honesty note — what this floor does and does not do

An env-driven flag toggles at **process restart**, not live. This is **dark-launch +
restart-to-toggle**: a real kill-switch (restart-to-disable beats a rollback deploy) and a real
merge/release decouple — but **NOT a live runtime flip**. A live flip (change behaviour without a
restart) needs a dynamic flag source: a config file watched at runtime, a control endpoint, or a
managed provider.

## Next steps (not shipped in the floor)

- **Live runtime flips / targeting / gradual rollout** — adopt a vendor-neutral provider
  ([OpenFeature](https://openfeature.dev/)) or a managed service (Unleash, LaunchDarkly).
- **Expand-contract migrations** behind a flag (safe schema change: add → backfill → contract).
- **Canary / blue-green** flag-driven staged rollout (see [progressive-delivery.md](progressive-delivery.md)).
