# Implementation plan — skill-spine brick #9: the kit's own `evals` skill

**Planned by dogfooding `skills/plan/SKILL.md`** (9th self-host use). Source design: `docs/architecture/2026-06-28-evals-skill-design.md` (owner-approved 2026-06-28).

## Goal
Ship the kit's own `evals` (eval-driven-development) skill — the AI-native sibling of `tdd`, a kit-original — wired DUAL-SEAT to the Engineer (build) and Security-reviewer (red-team/safety), both asserted, with the panel-#16 Low-1 keystone count-neutral fold-in — as one atomic AMBER `apply.py`.

## Architecture
A new FLOOR skill (`skills/evals/SKILL.md`, invoke-by-read) encodes the eval-driven-dev craft and points at the kit's existing eval infra; the Engineer def (FLOOR + native) and Security-reviewer def (FLOOR + native) each gain a reference; the shared verifier gains a `SECURITY_DEF` var + `check_evals_skill` (asserts the skill + BOTH refs) + 3 negative cases; the keystone gains the `evals` index row and count-neutral prose (Low-1); the `skill-spine` claim + `orchestration.md` extend. No new gate, no new claim row, no guard edit.

## Tech stack
POSIX sh (verifier), Python3 (`apply.py`), Markdown (skill + defs + keystone + docs), TSV (claims). No new dependencies.

## Global constraints (verbatim from the design + standing process)
- **FLOOR-only / invoke-by-read** — no formal `skills` adapter dimension; no registry/verify.sh/export/guard edits (confirm `skills/*` glob covers the new file — **confirm-don't-add**).
- **DUAL-SEAT both asserted** — Engineer + Security-reviewer both reference the skill; the verifier asserts BOTH (SECURITY_DEF defaults to `agents/security.agent.md`, which the fixtures already create via ROSTER_FILES); each ref-leg gets its own load-bearing negative case.
- **Kit-original** — superpowers has no evals skill; the claim says "#1–8 replace superpowers; `evals` adds the AI-native craft superpowers lacks." Do NOT write "replaces superpowers" for evals.
- **Points at, does not duplicate, the eval infra** — the skill references `EVAL-PLAN-TEMPLATE`, `eval-ready.sh`, the §7 gate, `AI-SYSTEM-CARD`, and `skills/tdd`+`skills/verification`; it does not re-implement them.
- **Keystone structural check (v3.65.0) requires the evals row** — this slice MUST add `skills/evals` to the keystone index or `check_keystone` fails. Fold in Low-1 (count-neutral prose) in the same edit.
- **AMBER** — control-plane. Author under `scratchpad/evals/`, idempotent `apply.py`, clone dry-run (`shellcheck` + `verify.sh --require` + case 21/22/23 flips). Agent never applies/commits/pushes/merges/tags ([[merge-tag-authority]]).
- **Version finishing folded into apply.py** — VERSION 3.65.0 → **3.66.0**, README badge, CHANGELOG entry.
- **ASCII-only markers** — `grep -qF`, ASCII; none begins with `-`.
- **Dual review + panel #17 + fold close into PR.** Ship discipline (incident lessons): `git show --stat HEAD` confirms the keystone + security defs are committed; admin-merge only when `conformance` is GREEN.

## Build model
**AMBER** — authored in `scratchpad/evals/`; the single deliverable is `scratchpad/evals/apply.py` + its clone-proven log.

## File map
| Path | Change | Responsibility |
|------|--------|----------------|
| `skills/evals/SKILL.md` | **create** | The eval-driven-dev craft (invoke-by-read). Carries the markers + the infra/spine chain. |
| `agents/engineer.agent.md` | modify | Engineer evals reference (eval-driven build), alongside tdd/debugging/verification. |
| `.claude/agents/engineer.md` | modify | Native mirror. |
| `agents/security.agent.md` | modify | Security-reviewer evals reference (red-team/safety lens). |
| `.claude/agents/security-reviewer.md` | modify | Native mirror. |
| `conformance/orchestrator-loop-wired.sh` | modify | `EVALS_SKILL_FILE` + `SECURITY_DEF` vars + `check_evals_skill()` (skill + both refs) + main-body call + cases 1–20 fixtures gain the skill + both refs + **new cases 21/22/23**. |
| `skills/using-skills/SKILL.md` | modify | Add `evals` index row + conformance-comment path; **Low-1**: count-neutral prose (lines 3/8/29/42/45/65). |
| `conformance/claims.tsv` | modify | Extend the `skill-spine` claim (kit-original wording). |
| `docs/operations/orchestration.md` | modify | Engineer + Security-reviewer follow `skills/evals/SKILL.md`. |
| `VERSION`, `README.md`, `CHANGELOG.md` | modify | Version finishing 3.65.0 → 3.66.0. |

## Tasks (serialized — shared verifier surface)

### Task 1 — Author the skill (`skills/evals/SKILL.md`)
Frontmatter `name: evals` + conformance-load-bearing HTML comment (mirror `skills/plan/SKILL.md:10-13`, listing the 5 markers). Required content + EXACT marker strings (`grep -qF`, ASCII):
- `## When to use` — any model/prompt-dependent behavior, BEFORE building the prompt/feature.
- **`eval-driven`** — evals are the test suite for AI; the AI sibling of `skills/tdd/SKILL.md`. Probabilistic red→green: write the eval first, watch the unbuilt feature miss the `threshold`, build to the bar. Green = `threshold` (score ≥ bar; no metric drops > N pts), not 0 failures. Calibrate to discriminate (an eval the unbuilt feature already passes proves nothing).
- **`judge`** — pin the judge + judge-independence (no self-grading); pin the SUT model+version.
- **`red-team`** — adversarial prompts, jailbreaks, harmful-output checks before shipping; AI incidents feed the red-team set.
- Runtime guards complement evals (prompt-injection defense, output-schema validation).
- Versioned + grows from production misses + retros; declining score = tech debt.
- Policy: author + wire evals; do NOT run the live provider (human/CI step; the guard speed-bump on live keys).
- Chain to `templates/EVAL-PLAN-TEMPLATE.md`, `conformance/eval-ready.sh`, the §7 Eval gate, `templates/AI-SYSTEM-CARD-TEMPLATE.md`, `skills/tdd/SKILL.md`, `skills/verification/SKILL.md`.
- Red-flags/rationalization table.

**Locked markers (5, `grep -qF`):** `name: evals` · `eval-driven` · `judge` · `red-team` · `threshold`. Write to `scratchpad/evals/SKILL.md`.

### Task 2 — Wire both seats (4 def edits)
- `agents/engineer.agent.md` + `.claude/agents/engineer.md`: add an evals reference — "for any model/prompt-dependent behavior, follow the kit's own `skills/evals/SKILL.md` (eval-driven dev: evals are the test suite; write the eval, watch it miss the bar, build to threshold)." Literal `skills/evals/SKILL.md`.
- `agents/security.agent.md` + `.claude/agents/security-reviewer.md`: add — "for AI features, apply the eval red-team / safety / judge-independence lens via the kit's own `skills/evals/SKILL.md` (the §7 security gate for AI)." Literal `skills/evals/SKILL.md`.
Author as full-file copies or surgical idempotent inserts under `scratchpad/evals/`.

### Task 3 — Verifier: check + dual non-vacuous teeth (TDD heart)
In a copy of `conformance/orchestrator-loop-wired.sh`:
1. Add path vars: `EVALS_SKILL_FILE="${ORCH_LOOP_EVALS_SKILL:-skills/evals/SKILL.md}"` and `SECURITY_DEF="${ORCH_LOOP_SECURITY_DEF:-agents/security.agent.md}"`.
2. `check_evals_skill()` taking `<skill> <engineer_def> <security_def>`: assert file exists; `grep -qF` each of the 5 markers; assert engineer_def references `skills/evals/SKILL.md`; assert security_def references it. Distinct FAIL lines.
3. Main-body call after `check_debugging_skill`: `check_evals_skill "$EVALS_SKILL_FILE" "$ENGINEER_DEF" "$SECURITY_DEF" || fail=1`.
4. A `_evals_skill_ok()` emitter (mirror `_debugging_skill_ok`) with all 5 markers.
5. Cases 1-20: in EACH, create `$rN/skills/evals/SKILL.md` via `_evals_skill_ok`, append `skills/evals/SKILL.md` to BOTH the engineer fixture def AND the security fixture def (`$rN/agents/security.agent.md`, already created via ROSTER_FILES), AND add the `evals` index row to that fixture's keystone (`_keystone_ok` must now emit `skills/evals` too — so the structural check_keystone passes), AND thread `ORCH_LOOP_EVALS_SKILL` + `ORCH_LOOP_SECURITY_DEF` into the env subshell.
6. **Case 21** (marker teeth): emit an evals skill MISSING a marker (drop `red-team`) → exit 1.
7. **Case 22** (Engineer reference teeth): conformant skill + Security ref present, Engineer def does NOT reference → exit 1.
8. **Case 23** (Security reference teeth): conformant skill + Engineer ref present, Security def does NOT reference → exit 1.
Note: `_keystone_ok` now must index `skills/evals` (the structural check enumerates the fixture's skills dirs, which include `evals`); ensure every case's keystone names it or those cases fail for the wrong reason.

**Red→green proof (scratchpad):**
- `sh scratchpad/evals/orchestrator-loop-wired.sh --selftest` → all 23 cases PASS.
- Mutate case 21 (restore `red-team`) → case 21 FLIPs to FAIL. Revert.
- Give case 22 the Engineer ref → case 22 FLIPs to FAIL. Revert.
- Give case 23 the Security ref → case 23 FLIPs to FAIL. Revert.

### Task 4 — Keystone (evals row + Low-1 count-neutral) + claim + ops doc
- `skills/using-skills/SKILL.md`:
  - Add the `evals` index row after the `debugging` row: `| evals | \`skills/evals\` | Eval-driven development for AI features (write the eval, watch it miss the threshold, build to the bar). |`.
  - Add `skills/evals` to the conformance-comment path list.
  - **Low-1 count-neutral swaps:** line 3 "index of the kit's own seven spine skills" → "index of the kit's own spine skills"; line 8 "the single map of the kit's seven spine skills" → "the single map of the kit's spine skills"; line 29 "## The index — the kit's seven spine skills" → "## The index — the kit's spine skills"; line 42 "The index names **all seven** spine skills." → "The index names **every** spine skill on disk."; line 45 "indexes all seven, and the Orchestrator references it" → "indexes every spine skill on disk, and the Orchestrator references it"; line 65 "The seven spine skills are reachable from this one map." → "Every spine skill is reachable from this one map."
- `conformance/claims.tsv` `skill-spine` row: extend → "… + the kit's own `evals` skill (`skills/evals/SKILL.md`), the AI-native eval-driven-dev craft, referenced by the engineer (eval-driven build) and the security-reviewer (red-team/safety) … bricks #1-8 replace superpowers (content + discovery); `evals` adds the AI-native craft superpowers lacks". Same id + verifier command; no new row. Use count-neutral wording (no hard skill count).
- `docs/operations/orchestration.md`: extend → the Engineer and Security-reviewer follow `skills/evals/SKILL.md` for eval-driven dev / AI red-team.

### Task 5 — Assemble `scratchpad/evals/apply.py` (idempotent) + version finishing
Mirror prior apply.py (base64-embed SKILL + verifier): write the skill; 4 def edits (idempotent); replace the verifier; keystone edits (evals row + comment + 6 count-neutral swaps, each idempotent); claim + ops swaps; VERSION 3.65.0→3.66.0, README badge, CHANGELOG prepend. Guard every mutation for clean re-run no-op.

### Task 6 — Clone dry-run (confabulation-proof)
`git clone . <unique>` → `python3 apply.py` → `shellcheck` → selftest (23/23) → `verify.sh --require` (skill-spine PASS, **and** confirm `check_keystone` passes with the evals row indexed, 0 failed) → VERSION 3.66.0 → re-run apply.py (idempotent). Capture the log + the case 21/22/23 flip evidence.

## Self-review (spec coverage)
- Skill (5 markers + infra/spine chain) → T1. Dual-seat wiring (Eng + Security, FLOOR+native) → T2. check + cases 21/22/23 + cases 1–20 fixtures (incl. security ref + keystone evals row) + dual non-vacuity → T3. Keystone evals row + Low-1 + claim + ops → T4. AMBER apply.py + version finishing → T5. Clone-proof incl. structural-keystone-passes → T6.
- No guard/registry/verify.sh/export edits → confirmed.
- Both ref-legs proven independently (22 + 23); kit-original claim wording (no "replaces superpowers" for evals) → T4.
- Placeholder scan: markers + keystone swaps are exact literal strings; commands carry expected output. ✔

## Terminal state / handoff
Hand to the build skill (subagent-driven via the Engineer seat): `scratchpad/evals/apply.py` + the Task 6 clone log incl. the 21/22/23 flips + structural-keystone-passes. Then dual review → panel #17 → human applies + ships (git show --stat + green-conformance discipline). **Next: brick #10 `discovery`.**
