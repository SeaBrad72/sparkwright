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

## The provider seam — floor vs live

`src/flags.ts` is a **provider seam**, not a hard-wired env read. A `FlagProvider` interface has one
method (`isEnabled(name)`); `isEnabled()` delegates to whichever provider is active, and
`setProvider()` swaps it. Two providers ship:

| Provider | Source | Toggle mechanism | Shipped |
|----------|--------|------------------|---------|
| `envProvider` (the **floor**, default) | environment variable, strict `=== 'true'` | **restart-to-toggle** (dark-launch + kill-switch) | yes |
| `fileConfigProvider(path)` (`src/live-provider.ts`) | a JSON flag file, re-read per resolution | **live flip — no restart** | yes (reference) |

A SaaS provider (OpenFeature / Unleash / LaunchDarkly) is an **adopter-pluggable** alternative: implement
the same `FlagProvider` and install it with `setProvider()` — no change to any caller of `isEnabled()`.

## Honesty note — what is and is not shipped

- **Env floor** — toggles at **process restart**, not live. Dark-launch + restart-to-toggle: a real
  kill-switch (restart-to-disable beats a rollback deploy) and a real merge/release decouple. This is
  what the reference **HTTP server** reads **by default** (`GET /greeting`, `FLAG_FILE` unset).
- **Live flip — now shipped on the reference** via `fileConfigProvider`: rewriting the JSON flag file
  changes behaviour **without a restart**. `server.ts` opts into it at boot when `FLAG_FILE` is set
  (unset → the env floor, unchanged): `if (process.env.FLAG_FILE) setProvider(fileConfigProvider(...))`.
  Proven end-to-end by the `live-flip` job in the `golden-path` workflow — it boots the image once with
  `FLAG_FILE` + a bind-mounted `flags.json`, GETs `/greeting` (OFF), rewrites the mounted file, and GETs
  `/greeting` again (ON): the **endpoint of the same running server flips with no restart** — and by the
  `test/flags.test.ts` observed-flip test. It is **fail-safe** (a missing / unreadable / unparseable
  file, or an absent flag, or a name that collides with an inherited `Object.prototype` member, all fall
  back to the registry default OFF — never throws, never enables on error) and **pollution-safe** (reads
  the specific own flag key; never spreads untrusted JSON; rejects `__proto__`/`constructor`/`prototype`).
  It re-reads the file **synchronously per resolution**; a profile/adopter wiring it onto a hot request
  path should add an mtime-gated cache (see the caveat in `src/live-provider.ts`).
- **Not mandated per profile.** The seam + a reference live provider ship for `typescript-node`; other
  profiles are not required to ship their own live provider (the env floor is the DoD floor). Targeting,
  gradual rollout, and managed evaluation remain a SaaS provider's job behind the same interface.

## Next steps (beyond the reference live provider)

- **Targeting / gradual rollout / managed evaluation** — adopt a vendor-neutral provider
  ([OpenFeature](https://openfeature.dev/)) or a managed service (Unleash, LaunchDarkly) behind `FlagProvider`.
- **Expand-contract migrations** behind a flag (safe schema change: add → backfill → contract).
- **Canary / blue-green** flag-driven staged rollout (see [progressive-delivery.md](progressive-delivery.md)).
