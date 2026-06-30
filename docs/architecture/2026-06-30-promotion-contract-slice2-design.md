# Design — Proportional Promotion Contract, Slice 2: change-class derivation + promotion-readiness surfacing

**Date:** 2026-06-30
**Epic:** Proportional Promotion Contract (`docs/architecture/2026-06-29-proportional-promotion-contract-design.md`; model `docs/governance/promotion-contract.md`). Slice 1 (model + standards keystone) shipped v3.76.0.
**Status:** Owner-approved design (this slice). Control-plane/governance → AMBER apply, human-ratified.
**Version:** 3.80.0 → 3.81.0 (MINOR — additive new claim + producer).

---

## What this slice is (and is not)

Slice 2 builds the **classifier + the promotion-readiness surfacing** — the thing that *informs* a human GO. It is **advisory only**: it surfaces, it never gates. The proportional *gates* (making CI/keystroke requirements conditional on class×rung) and the `control-plane-ratification` state label are **Slice 3**; relaxing agent-commit is **Slice 4**. Keeping enforcement out of this slice isolates the dangerous capability (a fail-closed gate) in Slice 3, where it gets its own careful review — surface-don't-actuate made literal.

## First-principles fit (why these choices)

- **Single source of truth.** The classifier *sources* `.claude/hooks/guard-core.sh` and calls `is_control_plane_path` — it does not re-implement control-plane detection. (`conformance/guard-core-sourced.sh` already enforces that consumers source the core; this is a new, conforming consumer.)
- **Honest-ceiling / "UNVERIFIED is not a pass."** The surfacing's *proven-vs-attested* field reuses `verify.sh`'s existing `[control]` vs `[doc]` classification — the kit already computes "what's proven vs what's merely documented," and that is the single most decision-relevant fact for a human GO. Surfacing it is the kit being self-consistent, not new machinery.
- **Surface-don't-actuate.** The producer auto-derives *facts* (class, blast-radius, proven-vs-attested) but never the *verdict*. `what-could-regress` and the GO itself stay human-owned. The producer exits `0` always — it cannot block.
- **Right-weight / minimize the change's own blast radius.** Placed in `conformance/` (already guard-immutable via both matchers) so **no `guard-core.sh` edit** is needed — the kit's refactoring lens flags `guard-core.sh` as high-risk "touch only when a cluster forces it." One new script is not a cluster.
- **Fail-safe.** Classification defaults *up* on any uncertainty and is *derived, never self-asserted* — a change cannot relax itself by mislabeling.

## Components

Two files (the kit's established producer + lock pattern, e.g. `scripts/sod-check.sh` + `conformance/author-not-approver-wired.sh`):

### `conformance/promotion-readiness.sh` — the producer
Sources `guard-core.sh` (from repo root) to get `is_control_plane_path`. POSIX sh, dash-clean.

**Classification (per path):**
- **control-plane** — `is_control_plane_path "$p"` returns 0.
- **sensitive** — path matches the heuristic set: `auth/`, `*/auth/`, `payments/`, `*/payments/`, `migrations/`, `*/migrations/`, `*secret*`, `*secrets*`, `*/keys/*`, `*.key`, `*.pem`, `.env` and `.env.*` **except** `.env.example|.sample|.template|.dist`. (The DoR threat-model/privacy/eval/compliance sub-flags ride here in a later slice; Slice 2 does the path-derived half.)
- **ordinary** — default.

**Aggregate** = the highest class present, ordered **control-plane > sensitive > ordinary**. **Fail-safe:** an empty change-set, an unreadable `--changed` file, or any token that cannot be read defaults to **control-plane** (the highest) — never silently to ordinary. There is no flag to *declare* a lower class.

**The surfacing (default output):** a structured, human-readable report:
1. **What changed** — the path list, grouped by class.
2. **Change-class** — the aggregate + per-path breakdown.
3. **Blast-radius** — the `class × rung` matrix cell text from `promotion-contract.md` (the disposition for that cell).
4. **Proven-vs-attested** — invokes `conformance/verify.sh`, captures its `Summary: N control-checks · M doc-checks · …` line + the honesty footer, and surfaces them. Degrades gracefully: if `verify.sh` is not runnable, prints `proven-vs-attested: UNAVAILABLE (run conformance/verify.sh)`. Suppressed by `--no-verify`.
5. **DoD + acceptance-criteria** — a static pointer to the Definition of Done (CLAUDE.md); pulls acceptance-criteria from `BACKLOG.md` only if a matching story is trivially present, else a labeled `ACCEPTANCE-CRITERIA: attest at gate` line.
6. **What-could-regress** — a labeled `REGRESSION-SURFACE: human attests` section (a judgment, not a fact — not auto-derived).

**Interface:**
```
conformance/promotion-readiness.sh [--changed FILE] [--rung RUNG] [--class] [--no-verify]
```
(The producer has no `--selftest` of its own; the lock `promotion-readiness-wired.sh --selftest` exercises it — one selftest owner, no duplication.)
- `--changed FILE` — newline-delimited path list (mirrors `agent-boundary.sh --changed`). Default = `git diff --name-only` against the merge-base with the default branch; if git is unavailable, fail-safe to control-plane with a note.
- `--rung RUNG` — `spike|integration|rc|staging|production`. **Default `rc`** (the meaningful go/no-go rung). Unknown value → usage error (exit 2).
- `--class` — **query mode**: print only the aggregate (`ordinary|sensitive|control-plane`) and exit. The stable seam Slice 3 consumes — no JSON contract yet (YAGNI).
- `--no-verify` — skip the proven-vs-attested `verify.sh` invocation (fast classification-only).
- **Exit:** `0` always for producer/query modes (it surfaces, never gates — Slice 3 owns the gate). `2` = usage error.

### `conformance/promotion-readiness-wired.sh` — the lock
A regression-lock with a non-vacuous `--selftest`. Fixtures (each a temp `--changed` file run through the producer in `--class` mode):
- a control-plane path (e.g. `conformance/x.sh`) → `control-plane`.
- a sensitive path (e.g. `src/auth/login.ts`) → `sensitive`.
- an ordinary path (e.g. `src/util/format.ts`) → `ordinary`.
- a **mixed** set (ordinary + sensitive + control-plane) → `control-plane` (highest wins).
- the **fail-safe**: an empty change-set and a non-existent `--changed` file → `control-plane` (defaults up, never ordinary).
- **load-bearing negative:** the selftest also asserts that the control-plane and sensitive fixtures do **not** classify as `ordinary` — so a mutation of the classifier to always-return-`ordinary` makes the selftest FAIL (mislabel-can't-downgrade). Mutation-proven at build time.

## Registration + delivery

- **`conformance/claims.tsv`** — new claim `promotion-readiness`: *"change-class is derived (not self-asserted) and fail-safe, and the promotion-readiness surfacing is produced (conformance/promotion-readiness.sh)"* → `sh conformance/promotion-readiness-wired.sh --selftest`.
- **`conformance/claims-registry.sh`** — add `promotion-readiness` to `REQUIRED_IDS`.
- **`.github/workflows/ci.yml`** — one step running the lock `--selftest` (`sh conformance/promotion-readiness-wired.sh --selftest`). The **lock** owns `--selftest`; the **producer** ships `--class`/`--changed`/`--no-verify` (no `--selftest` of its own). `ci-selftest-coverage` requires any file shipping `--selftest` to be wired into CI — the lock is, so that gate stays green. Neither file is invoked by golden-path, so there is no `golden-path-trigger` (Slice T4-1) interaction.
- **`docs/governance/promotion-contract.md`** — flip the Slice-2 row in the build-status table from `planned` to the shipped version; no model change.
- **AMBER `apply.py`** — installs both files, edits claims.tsv/claims-registry.sh/ci.yml/promotion-contract.md, folds version-finishing (VERSION 3.80.0→3.81.0, README badge, CHANGELOG). Idempotent, all-or-abort, per-file buffered. Clone-proven. Human runs it; governance close separate (M2-S5).

## Testing / verification

- `promotion-readiness-wired.sh --selftest` — all classification + fail-safe + load-bearing-negative cases; mutation-proven (always-ordinary classifier → selftest FAIL).
- Real-run on the kit's own tree: a change-set touching `conformance/` → `control-plane`; a docs-only change → `ordinary`; the surfacing renders all six sections; `--no-verify` suppresses section 4; proven-vs-attested matches `verify.sh`'s footer.
- `claims-registry.sh` green (new claim verifies, coverage intact); `ci-selftest-coverage.sh` green (lock wired); `shellcheck.sh` clean; fresh-clone `verify --require` green.
- Clone-proven idempotent apply.

## Honest ceilings (this slice)

- The classifier is **fail-safe, not omniscient** — path-derivation + safe-default, verified at the (future) gate. A novel sensitive path not in the heuristic set classifies `ordinary` until the gate's reviewer-confirmation (Slice 3) or the heuristic is extended; the fail-safe covers *uncertainty* (unreadable/empty), not *unknown-but-readable* paths. Documented, not hidden.
- The surfacing **informs**, it does not judge — `what-could-regress` and the GO are human-owned.
- Acceptance-criteria pull is BACKLOG.md-only in this slice; full tracker-adapter sourcing (Jira/ADO) is deferred to where the RC gate needs it (Slice 3+).

## Risks

- **Sensitive heuristic false-negatives** (a sensitive path outside the set) → mitigated by fail-safe-up on uncertainty + the gate's reviewer-confirmation later; the heuristic set is documented and extensible.
- **`verify.sh` invocation cost/flakiness** in section 4 → bounded (offline checks, seconds) + `--no-verify` escape + graceful degrade.
- **Producer-in-conformance/ convention smell** → accepted (it is a governance-conformance artifact; auto-immutability + zero guard-core edit outweighs the cosmetic cost).
