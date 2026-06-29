# Pre-E10 hardening — guard two-matcher symmetry + tag-time CI gate

**Date:** 2026-06-28
**Epic / slice:** banked hardening promoted ahead of **E10** — a single combined control-plane slice. Closes two banked items from meta-control panels #16–#18.
**Status:** Design converged — **designed by dogfooding `skills/design/SKILL.md`** (11th self-host), owner-ratified 2026-06-28 (one combined slice; tag-gate = bounded-poll + degrade-open). Ready for the implementation plan.
**Tracked here** because both touch control-plane integrity and must be resumable cold.

**Reads-first for a cold resume:** [[reprioritized-backlog]] (the two banked items + the brick-#8 incident that promoted the tag-gate), `.claude/hooks/guard-core.sh` (the guard being hardened), `scripts/release-tag.sh` (the release script being gated), the brick-#10 design (`docs/architecture/2026-06-28-continuous-discovery-skill-design.md`, the slice convention this mirrors).

## 0. Why this slice (the decision trail)
Two small control-plane hardening items have been banked across panels #16–#18, both sharpened by things that happened in the brick-#10 ship session:
1. **Guard two-matcher asymmetry for `conformance/`** — the verifiers (the kit's *gates*) live in `conformance/`. They are protected on the Write/Edit + path-extraction route (`is_control_plane_path`, `guard-core.sh:23` lists `conformance/*`), but **not** on the raw-shell command-pattern route (`guard_check_command`, the mention regex `:82` and the redirect regex `:85` do **not** list `conformance/`). The exploitable gap is the **redirect form** — `echo … > conformance/foo.sh` / `sed -i … conformance/foo.sh` — which can slip the path-extraction route but should be denied by `:85`. An agent that silently rewrites a verifier to always-pass defeats every gate; this is exactly what the command matcher exists to stop.
2. **Tag-time CI gate** — the brick-#8 incident shipped a RED-`conformance` commit to `main` and then `release-tag.sh` tagged it, because `--admin` merge bypassed branch-protection's `conformance` gate and `release-tag.sh` only checks VERSION/tag coherence, never CI. The ship-session UX reinforced it: `conformance` runs ~5 min and shows as `pending (0s)`, so the human eyeballing it is a fragile control. A mechanical backstop is warranted.

Owner-ratified (2026-06-28): **one combined "pre-E10 hardening" slice** (both are small control-plane fixes; one design/apply.py/review/panel/ship), and the tag-gate is **bounded-poll + degrade-open**.

## 1. What this slice is
Two changes, one AMBER `apply.py`:
- **A. Guard:** add `conformance/` to the two `guard_check_command` shell regexes (`guard-core.sh:82` mention + `:85` redirect), closing the redirect-form gap with two-matcher symmetry. Prove with an agent-autonomy fixture (redirect + `sed -i` against `conformance/` denied).
- **B. Tag-gate:** add a CI-conclusion backstop to `scripts/release-tag.sh` — before tagging, bounded-poll the head commit's main CI; **refuse on definitive `failure`**, **degrade open** (warn + proceed) on timeout / no `gh` / non-GitHub / no run. Forge-neutral; the CI probe is injectable so the `--selftest` proves it without network.

## 2. Part A — guard two-matcher symmetry (the precise fix)
- **Add `conformance/[^[:space:]]*`** to the `:82` control-plane *mention* regex and the `:85` *redirect-target* regex, mirroring how `skills/[^[:space:]]*` is listed in both. After the fix, `> conformance/x.sh` and `sed -i conformance/x.sh` are denied by the command matcher (not only the path route).
- **Scope decision:** the `:82`/`:85` regexes are a curated *subset* of `is_control_plane_path` (the highest-risk shell-mutation targets: guard, CI, governance, agent defs, release/escalate scripts, skills). `conformance/` belongs in that set (it holds the gates). `adapters/*` shares the identical gap (listed beside `conformance/*` at `:23`) — **flagged for the reviewer**: add it in the same edit for full symmetry, or leave scoped to the ratified `conformance/` item. Recommendation: add `adapters/` too (zero extra cost, same class).
- **Non-vacuity:** extend the agent-autonomy fixture with a redirect-deny + `sed -i`-deny case against a `conformance/*.sh` path, and (load-bearing negative) confirm the *pre-fix* regex would have ALLOWED the redirect form — i.e., the new alternative is what flips it to denied.
- **Honest ceiling:** the guard is a SPEED BUMP, not a boundary (`guard-core.sh:7`); this closes one shell-form gap, it does not make `conformance/` tamper-proof (an interpreter `python -c` bypasses the shell path — documented, unchanged).

## 3. Part B — tag-time CI gate (bounded-poll, degrade-open, forge-neutral)
- **Where:** in `run()` (`release-tag.sh`), after `decide()` yields `TAG v<x>` and before `git tag` — gate only the real tag action (not `--dry-run`, not `NOOP`).
- **Behavior matrix** (head commit = `git rev-parse HEAD`):
  - definitive **`failure`/`cancelled`/`timed_out`** → **REFUSE** (rc 1, message names the red run).
  - **`success`** → proceed to tag.
  - **no `gh` / not a GitHub remote / no run found / poll timeout (still in-progress)** → **WARN + proceed** (degrade open — preserves pure-git forge-neutrality + never hard-blocks a legit release on a slow/absent CI).
- **Bounded poll:** loop `ci_conclusion()` until terminal or `RELEASE_TAG_CI_TIMEOUT` (default 600s), sleeping `RELEASE_TAG_CI_INTERVAL` (default 15s). Needed because the tag fires while CI is still `in_progress` (observed: conformance concluded at 5m15s) — without the poll the gate has no teeth for the exact flow it guards.
- **Forge-neutrality / injectable testing (the key buildability move):** the CI lookup is a single function `ci_conclusion()` whose default implementation shells `gh` (`gh run list --commit <sha> --workflow CI --json conclusion,status …`), but is **overridable via `RELEASE_TAG_CI_PROBE`** (a command that prints `status<TAB>conclusion`). The `--selftest` injects a stub probe → tests the matrix with **no network**: failure→rc1, success→proceed, in-progress-then-timeout→proceed-with-warn, probe-absent→proceed-with-warn. Mirrors the existing injectable `RELEASE_TAG_COHERENCE`.
- **Default on, self-disabling:** the gate is active by default but auto-skips (degrade open) when `gh` is absent / remote isn't GitHub — so adopters on other forges are unaffected and the FLOOR stays pure-git.
- **Honest ceiling:** this REDUCES the brick-#8 risk (tag-on-red), it does not eliminate it — a CI slower than the poll window, or a forge without the probe, degrades open by design. Named in the script header + the claim. The hard control remains branch protection + the human; this is a mechanical backstop.

## 4. Conformance (right-weighted)
- **Guard:** extend the existing agent-autonomy fixture (`scripts/fixtures/…`/`conformance/agent-autonomy.sh` — confirm path at plan time) with the redirect + `sed -i` deny cases for `conformance/`; the existing `runtime-security` / guard lock already runs it. No new gate.
- **Tag-gate:** extend `release-tag.sh --selftest` with the 4 injected-probe cases (the script is already locked by `version-tag-coherent` / the release lock — confirm which conformance check runs `release-tag.sh --selftest`, extend its expectations). No new gate/claim if an existing lock covers `release-tag.sh`; if not, the selftest is self-proving and CI runs it.
- **Both** proven on a fresh clone (shellcheck + selftests + `verify --require` 31/0).

## 5. Honest ceiling & scope (named, not built)
- Guard: speed-bump not boundary; closes the redirect-form shell gap for `conformance/` (+ `adapters/` if accepted), not interpreter bypass.
- Tag-gate: backstop not hard gate; degrades open by design (forge-neutrality + no-false-block win over absolute teeth). The pure-git release path is unchanged when `gh` is absent.
- No new seat, no new skill, no new claim row (extend existing locks). FLOOR.

## 6. Build approach
Control-plane slice (`.claude/hooks/guard-core.sh` [+ `conformance/`/`adapters/` in `:82`+`:85`]; `scripts/release-tag.sh` [+ `ci_conclusion()` + gate in `run()` + 4 selftest cases]; the agent-autonomy fixture [+ redirect/`sed -i` deny cases]; possibly a conformance expectation doc; version finishing **3.67.0 → 3.68.0**) → **AMBER `apply.py`**, clone dry-run (shellcheck + guard fixture + `release-tag.sh --selftest` + `verify --require` 31/0 + the load-bearing negatives) → **dual review** (reviewer: correctness + non-vacuity + degrade-open honesty; security: the guard regex is correct + doesn't over/under-block, the gate can't be tricked, forge-neutral degrade is safe) → **panel #19** → fold close into the PR. The human applies/ships (`git show --stat` + green-conformance discipline).

## 7. Convergence record (owner-ratified 2026-06-28)
Designed by dogfooding `skills/design/SKILL.md` (11th self-host). One combined pre-E10 hardening slice. Part A: close the guard's redirect-form gap for `conformance/` (+ `adapters/` flagged) — two-matcher symmetry, agent-autonomy fixture proves it. Part B: tag-time CI gate in `release-tag.sh` — bounded-poll, refuse-on-definitive-failure, **degrade open** (forge-neutral; injectable `ci_conclusion()` probe makes `--selftest` network-free). Both honest-ceiling'd (speed-bump / backstop, not absolutes). Right-weighted: extend existing locks, no new gate/claim/seat. VERSION → 3.68.0. **Next: the implementation plan, then E10.**
