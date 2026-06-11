# Slice 11c — Sandbox + scoped-credential references + conformance

**Status:** design approved (brainstorm), pre-plan.
**Arc:** Containment & the Platform Boundary (`docs/ROADMAP-SLICE11.md`). Follows 11a (MCP gate, W3) and 11b (egress, W2-channel). Aimed by [A8 §2.4](../reviews/2026-06-10-A8-mcp-egress-attack-surface.md).
**Version target:** v2.42.0 — **MINOR** (conditional three-state check + reference docs; no new universal required gate).

---

## Problem

11b closed the exfiltration *channel* (default-deny egress). 11c closes **what is reachable to exfiltrate in the first place** — it formalizes the three remaining platform-safety-boundary controls left Org-owned:
- **#2 Separate production credentials** — agents/dev sessions never hold prod write creds; brokered via break-glass + SoD.
- **#3 Sandboxed / read-only filesystem** — the agent workspace is scoped to the work tree and cannot read `~/.aws`, `~/.ssh`, other projects, or host secrets.
- **#4 Scoped, short-lived tokens** — least-privilege, time-boxed credentials; no long-lived broad-scope tokens within agent reach.

This directly defangs the **MCP `secret.read` class** (A8 Part 1, family 6) and the interpreter exfil tail (A8 Part 2) **at the source**: if the FS can't read host secrets and tokens are scoped + short-lived, both lose their payload even if a channel exists.

As with 11a/11b, 11c does **not** enforce these in-process (the kit cannot make a host FS read-only or expire a token). It **ships the reference and verifies the posture is declared + attested** — three-state, UNVERIFIED-honest, never a false PASS.

## Goals

1. Ship a single **`docs/operations/containment.md`** reference with copy-pasteable patterns for all three controls.
2. Add **`conformance/containment-ready.sh`** — one conditional three-state check verifying each of the three sub-aspects independently; overall = weakest aspect.
3. Move crosswalk rows **37/38/39 Org-owned → Kit-assisted** (reference shipped + wiring verified), never Kit-enforced.
4. Preserve the honesty invariant: no green check implies the kit enforced (or verified) read-only FS, token TTL, or prod-cred separation.

## Non-goals

- **No in-process enforcement.** The kit cannot make a host FS read-only, expire a token, or broker prod access. The check verifies declaration + attestation only.
- **No per-profile changes.** The reference is a single canonical doc (the agent-sandbox use case is distinct from the dev-container; a fresh snippet is clearer than retrofitting one profile of ten).
- Honesty restatement / crosswalk-wide tier reconciliation → **11d**. Red-team exit gate → **A9**.

---

## Components

### 1. `docs/operations/containment.md` (the reference)
Pairs with `containment-ready.sh` (as `egress-control.md` pairs with `egress-policy.sh`). Three copy-pasteable patterns + how to attest:
- **Sandbox FS:** a compose/devcontainer snippet — `read_only: true` on the agent service, a `tmpfs` for writable scratch (`/tmp`), and a single scoped bind mount of the work tree; nothing else from the host (so `~/.aws`/`~/.ssh`/other projects are unreachable). Note the agent-sandbox use case is distinct from a developer dev-container.
- **Scoped tokens:** OIDC→role federation (no long-lived secrets), short TTL, least-privilege scope; for CI, the existing push-only `id-token` minimization.
- **Separate prod credentials:** prod creds never in agent/dev reach; access via an audited break-glass/approval workflow (SoD).
- **How to attest:** the three RUNBOOK lines `containment-ready.sh` keys on, and what counts as "wired."
- **The ceiling note:** these patterns only contain anything **if actually applied at the platform** — a repo with the snippet but a host that ignores it is UNVERIFIED, by design.

### 2. `conformance/containment-ready.sh` (the check + `--selftest`)
Conditional, fail-closed, three-state. Reuses the established deploy/integration-surface detection.

**Conditional trigger:** an integration/deploy surface — a `Dockerfile`, any `.github/workflows/`, or a deploy workflow. None → **N/A skip-pass** (a pure-local library/CLI has no agent-reachable secrets or prod to contain).

**Three sub-aspects, each keyed on a RUNBOOK line** (generalized declared+attested, as 11b — the RUNBOOK attestation is the authoritative "wired" signal; an in-repo read-only-mount config is an optional stronger declaration for the FS aspect only):

| Aspect | RUNBOOK line prefix | declared | attested |
|--------|---------------------|----------|----------|
| Sandbox FS | `Sandbox FS:` | read-only-mount config in a compose/devcontainer **or** the line names a mechanism | `enforced: <ISO date>` |
| Scoped tokens | `Scoped tokens:` | line names a mechanism (OIDC→role / short-TTL / least-privilege) | `enforced: <ISO date>` |
| Prod credentials | `Prod credentials:` | line names a mechanism (separate / break-glass / SoD) | `enforced: <ISO date>` |

**Per-aspect state:** PASS (declared + attested) · UNVERIFIED (declared, not attested — `[date]` placeholder or missing date) · FAIL (line absent where the check applies) · N/A (line records `N/A — <reason>`).

**Overall = weakest aspect:** any FAIL → exit 1; else any UNVERIFIED → exit 2 (escalates to FAIL under CI / `--require`); else (all PASS/N-A) → exit 0. The script prints each aspect's verdict so a partial posture is visible, never hidden behind one label. Containment is only as strong as its leakiest dimension — the aggregate cannot be greener than the weakest real control.

### 3. `conformance/containment-readiness.md` (the checklist)
Mirrors `egress-readiness.md`: **Auto** rows (declared + attested, per aspect) vs **Manual** rows the script cannot prove — *the FS is actually read-only* (an agent process genuinely cannot read `~/.ssh`), *the token actually expires*, *a leaked dev cred genuinely cannot touch prod*. A green run is necessary, not sufficient.

### 4. `templates/RUNBOOK-TEMPLATE.md` (three attestation lines)
Under the deploy/security area, three dated lines the check keys on (record strings stay in sync with the script, same discipline as the §8 resilience / egress lines):
```
Sandbox FS: read-only work-tree mounts ([mechanism]) — enforced: [date]
Scoped tokens: OIDC->role, short TTL ([mechanism]) — enforced: [date]
Prod credentials: separate + break-glass ([mechanism]) — enforced: [date]
```
Each may instead be `<Aspect>: N/A — [reason]`. **Do not** put the literal `N/A` after the aspect prefix inside a comment (the N/A-escape grep is token-anchored per the 11b fix, but keep comments clear of the keyed phrases).

### 5. Enterprise / audit wiring
- Compliance crosswalk **rows 37/38/39** Org-owned → **Kit-assisted**, evidence cells citing `containment-ready.sh` + `containment.md`.
- `conformance/audit-evidence-checklist.md`: add (or update) rows for sandboxed FS / scoped tokens / separate prod creds → **Auto (conditional):** `containment-ready.sh`.
- `platform-safety-boundary.md`: note controls #2/#3/#4 are now reference-shipped + verify-wired — enforcement remains platform-owned (do not weaken the boundary framing).

### 6. Meta / CI
- `.github/workflows/ci.yml` (control-plane → human `cp`): add a `containment-ready.sh --selftest` step.
- `conformance/README.md`: index row.
- `VERSION` → `2.42.0`; `CHANGELOG.md`; `docs/ROADMAP-SLICE11.md` 11c → ✅ shipped.

---

## Honesty boundary (load-bearing)

- The check **verifies declaration + attestation, never enforcement.** PASS = the operator declared and attested the control — **not** that the kit confirmed the FS is read-only, the token expires, or prod creds are unreachable. Those are **Manual** rows.
- **UNVERIFIED is a first-class non-pass** (exit 2), escalating to FAIL under CI / `--require`.
- Crosswalk: **Kit-assisted**, never Kit-enforced. `platform-safety-boundary.md` keeps enforcement platform-owned; 11c only makes the controls declarable + verifiable.

## Testing

`--selftest` fixture battery (wired into kit CI like the other readiness checks):

| Fixture | Expected |
|---------|----------|
| No integration/deploy surface | N/A (skip-pass) |
| Surface present, no containment section | FAIL |
| All three aspects declared + dated | PASS |
| One aspect `[date]` placeholder | UNVERIFIED |
| Sandbox FS via read-only compose config + dated; others dated | PASS (config-declared path) |
| Prod credentials `N/A — no prod env`; other two dated | PASS (per-aspect N/A) |
| Only two of three aspect lines present | FAIL (weakest = absent) |
| Placeholder fixture under `CI=true` | FAIL (escalation) |

Plus: `dash -n` clean; `check-links.sh` resolves new links; bootstrap-into-temp green; fresh RUNBOOK template → UNVERIFIED (not a false PASS); per-fixture `REQUIRE` isolation so the CI-run selftest does not spuriously escalate; full conformance suite + `verify.sh` green.

## Governance

Feature branch → PR → **human ratification** (Bradley merges; agent never self-merges). The `ci.yml` change via the control-plane `cp` (`KIT_GUARD_SELFEDIT=1`). Security-owner-lens review of the honesty framing before the PR. Kit stays generic/anonymized ([[kit-anonymization]]).

## Out of scope / deferred
- In-process enforcement of FS/token/cred controls (impossible-by-construction; not attempted).
- 11d — honesty & assurance restatement (crosswalk-wide tier reconciliation once 11c lands).
- A9 — red-team re-test (the arc's exit gate).
