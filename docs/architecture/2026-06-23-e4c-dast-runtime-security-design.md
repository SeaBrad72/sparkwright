# E4c — DAST / runtime-security: proven security-header floor + documented DAST reference

**Status:** Design approved 2026-06-23 (owner-ratified). Closes the last named gap-assessment blind spot.
**Tracked here** (not `docs/superpowers/specs/`) per the C7 lesson.

---

## 0. Context

E4 (containment). The E3 §10 contract (#7) puts **DAST / runtime-security** in scope ("a parallel
fleet widens the attack surface"); the gap-assessment lists "no DAST / runtime security / fuzzing"
as a blind spot. `docs/operations/security-scanning.md` ships SAST (`gate-sast`, Semgrep) + license,
both **static** — nothing exercises the *running* app.

The reference app is a deliberately trivial zero-dependency Node stdlib server
(`profiles/typescript-node/scaffold/src/server.ts`: GET `/healthz`, GET `/greeting`, 404) that sets
only `Content-Type` — **no security headers**. A full ZAP scan of a toy API mostly surfaces missing
headers, so "run a real DAST tool in CI" risks a thin/contrived proof (the E4d trap). E4c instead
ships a **proven runtime-security floor** (security headers, asserted on the booted app) + a
**documented DAST reference** (OWASP ZAP baseline) for adopters with real attack surface.

**Honest boundary:** the kit *proves* the runtime-security headers on its reference; full DAST
against real routes / auth / inputs is the *documented pattern* for real apps (the reference is
intentionally minimal). Stated in the docs + the gate comment so it's not read as "the app was
pentested."

---

## 1. Owner-ratified decisions

1. **Shape:** harden the reference app with security headers + a proven runtime-security check; DAST (ZAP) is a documented reference, not a forced gate.
2. **DAST scope:** documented OWASP ZAP baseline pattern (copy-paste ci.yml snippet in `security-scanning.md`), **not** a required §14 conditional gate — no heavy ZAP forced on every web service.
3. **Conformance:** a new claim `runtime-security` (claims **27 → 28**), dedicated `conformance/runtime-security.sh`, `--selftest`, wired into `verify.sh` + `ci.yml`.

---

## 2. Harden the reference app (agent-editable)

`profiles/typescript-node/scaffold/src/server.ts` — a shared `SECURITY_HEADERS` const merged into
**every** response (the `/healthz` 200, the `/greeting` 200, and the 404), zero-dependency (no
helmet — it's a stdlib server). For a JSON API:

```ts
const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Content-Security-Policy': "default-src 'none'",
  'Referrer-Policy': 'no-referrer',
} as const;
// each: res.writeHead(<status>, { 'Content-Type': 'application/json', ...SECURITY_HEADERS })
```

Rationale: `nosniff` (MIME-sniffing), `DENY` (clickjacking), `default-src 'none'` (a JSON API serves
no resources — strictest correct CSP), `no-referrer` (referrer leakage). Bodies are unchanged, so the
existing smoke + tests still pass.

**No new unit test (recon-driven adjustment).** The scaffold has no server-handler test —
`server.ts` is deliberately **coverage-excluded** (the socket-binding main guard; see its header
comment + `vitest.config.ts`); only the pure `flags()`/`health()` logic is unit-tested. Adding a
handler test would cross that intentional boundary. The header hardening is instead proven two ways,
both red-green: **static** (§3 `runtime-security.sh` greps the header set in `server.ts`) and
**behavioural** (§3 golden-path curls the booted app). This matches how the kit already treats
`server.ts`.

---

## 3. Proven behavioural + conformance

### 3.1 golden-path runtime-security assertion (control-plane)
The `golden-path` job already boots the `gp` container and polls `/healthz`. Add a step that, on the
booted container, asserts each security header is present on the response:

```sh
hdrs=$(curl -sS -D - -o /dev/null http://localhost:3000/healthz)
for h in 'x-content-type-options: nosniff' 'x-frame-options: DENY' "content-security-policy: default-src 'none'" 'referrer-policy: no-referrer'; do
  printf '%s\n' "$hdrs" | grep -iqF -- "$h" || { echo "runtime-security: MISSING header: $h"; docker logs gp || true; docker rm -f gp >/dev/null 2>&1 || true; exit 1; }
done
echo "runtime-security: OK — all security headers present on the booted app"
```
Reuses the already-booted container (no new boot). Deterministic, non-vacuous: RED before the §2
hardening → GREEN after.

### 3.2 `conformance/runtime-security.sh` (new, control-plane)
Kit-self lock (static; no docker — runs in the `verify.sh` aggregate). Asserts:
- `profiles/typescript-node/scaffold/src/server.ts` defines all four security headers.
- `.github/workflows/golden-path.yml` carries the runtime-security assertion (the load-bearing
  tokens: the curl + each header / the `runtime-security: OK` marker) — so the proof can't silently
  rot.
- `--selftest` fixtures: a server.ts with all four headers + a golden-path with the assertion → PASS;
  a server.ts missing a header → FAIL; a golden-path missing the assertion → FAIL.
- Claim `runtime-security` in `claims.tsv` (verifier `sh conformance/runtime-security.sh`); id added
  to `REQUIRED_IDS` → claims **27 → 28**; wired into `verify.sh` + a `ci.yml` `--selftest` step.

### 3.3 Export carve
`runtime-security.sh` reads the export-ignored `golden-path.yml` (a kit-self lock), so its claim is
**carved from the adopter export — both loops in `scripts/adopter-export.sh`** (mirroring
`containment-audit` / `feature-flags-wired`). The hardened `server.ts` **ships** to adopters (they
get a hardened reference); only the kit-self lock's claim is carved. (Verified in the plan's
clone+export dry-run.)

---

## 4. DAST documented reference (not forced)

`docs/operations/security-scanning.md` — a new **DAST — dynamic application security testing**
section:
- The OWASP **ZAP baseline** pattern: a copy-paste ci.yml snippet (`zaproxy/action-baseline`,
  SHA-pinned when adopted) scanning the deployed / preview URL.
- **When it applies:** a real web attack surface (routes, forms, auth, user input) — not a
  health-only service.
- **How it fits:** SAST (`gate-sast`, static, first-party code) + dependency/image scans (`gate-dep-scan`,
  `gate-image-vuln`) + the **runtime-security headers** (the proven floor here) + **DAST** (dynamic,
  the running app). Honest note: the kit proves the runtime-security floor on its trivial reference;
  full DAST is the adopter's to wire against their real surface.
- **Not** a required §14 conditional gate — forcing a heavy ZAP run (large image, minutes, network)
  on every web service is the false-universality the §14 framework warns against. Opt-in.

---

## 5. Footprint & verification

- **Control-plane → AMBER mechanic** (flat `/tmp/e4c_scratch/` → human-run `apply.py` →
  **security-review-of-scratch MANDATORY**): `conformance/runtime-security.sh`, `claims.tsv`,
  `claims-registry.sh`, `verify.sh`, `ci.yml`, `.github/workflows/golden-path.yml`,
  `scripts/adopter-export.sh` (carve).
- **Agent-editable on-branch:** `profiles/typescript-node/scaffold/src/server.ts`,
  `docs/operations/security-scanning.md`, VERSION 3.45.0, CHANGELOG, README badge, `docs/ROADMAP-KIT.md`.
- **Proof model (G2/E4a/E4b):** local docker red-green (boot the hardened container, curl, headers
  present; revert → assertion fails); **golden-path job GREEN on PR + main = canonical**.
- **apply.py invariants:** explicit ROOT, idempotent, atomic, fail-loud anchors, mode-preserve 0755.
- **DoD:** `runtime-security.sh --selftest` green + real-tree green; golden-path runtime-security step
  GREEN on PR + main; claims 28; export carve verified; `verify --require` OK; `doctor` PASS;
  builder ≠ reviewer + security-review-of-scratch APPROVE; merge landed verified.

---

## 6. E4 decomposition (updated)

| Slice | Status |
|---|---|
| E4a — boot+probe sandbox (FS/egress/caps) | ✅ v3.42.0 |
| E4b — image-vuln CVE gate | ✅ v3.43.0 |
| E4a′ — token-scope static gate | ✅ v3.44.0 |
| **E4c — DAST/runtime-security (this)** | **building** — closes the last named blind spot |
| E4e — R2 bot-identity ratification gate | next candidates |
| E4f — G8 per-segment guard | (delicate; deliberate standalone session) |
| /work-mount reference fix | |
| E4d — cost/runaway kill-switch | deferred to land with E3 |

E3 (orchestration) builds after E4. Order: E2 ✓ → E4 → E3 → E1/E5/E6.
