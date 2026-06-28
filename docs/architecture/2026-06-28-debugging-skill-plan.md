# Implementation plan — skill-spine brick #8: the kit's own `debugging` skill

**Planned by dogfooding `skills/plan/SKILL.md`** (7th self-host use). Source design: `docs/architecture/2026-06-28-debugging-skill-design.md` (owner-approved 2026-06-28).

## Goal
Ship the kit's own `debugging` (systematic-debugging-equivalent) skill — root-cause-first, wired single-seat to the Engineer, with the kit's regression-test tie-in and non-vacuous teeth — as one atomic AMBER `apply.py`. Phase-2 brick #1.

## Architecture
A new FLOOR skill (`skills/debugging/SKILL.md`, invoke-by-read) encodes root-cause-first debugging chained to tdd + verification; the Engineer def (FLOOR + native) gains a debugging reference; the shared verifier `conformance/orchestrator-loop-wired.sh` gains `check_debugging_skill` + two negative selftest cases; the `skill-spine` claim and `orchestration.md` extend to "bricks #1–8". No new gate, no new claim, no guard edit (`skills/*` already control-plane).

## Tech stack
POSIX sh (verifier), Python3 (`apply.py`), Markdown (skill + defs + docs), TSV (claims). No new dependencies.

## Global constraints (verbatim from the design + standing process)
- **FLOOR-only / invoke-by-read** — no formal `skills` adapter dimension; no registry/verify.sh/export/guard edits (confirm `skills/*` glob already covers the new file — **confirm-don't-add**).
- **Single-seat Engineer** — the verifier asserts the Engineer references the skill; no other seat asserted.
- **AMBER** — control-plane. Author under `scratchpad/debugging/`, assemble an idempotent `apply.py`, prove on a **clone dry-run** (`shellcheck` + `verify.sh --require`), hand to the human to apply. The agent never applies/commits-the-applied-diff/pushes/merges/tags ([[merge-tag-authority]]).
- **Version finishing folded into apply.py** — VERSION 3.63.0 → **3.64.0**, README badge, CHANGELOG entry ([[release-finishing-in-apply-py]]).
- **Non-vacuity** — each new selftest case must FAIL a dead/always-pass check (drop-a-marker + omit-the-reference).
- **ASCII-only verifier markers** — `grep -qF`, ASCII. None of the markers begins with `-` (plain `grep -qF` is safe).
- **Dual review** (reviewer + security-reviewer) → **meta-control panel #15** → fold the close INTO the feature PR.

## Build model
**AMBER** — every task below is authored in `scratchpad/debugging/`; nothing lands on a control-plane path as a silent agent commit. The single deliverable is `scratchpad/debugging/apply.py` + its clone-proven dry-run log.

## File map (every path the apply.py creates/modifies)
| Path | Change | Responsibility |
|------|--------|----------------|
| `skills/debugging/SKILL.md` | **create** | Root-cause-first debugging craft (invoke-by-read). Carries the conformance-load-bearing markers + the tdd/verification chain. |
| `agents/engineer.agent.md` | modify | Add a debugging reference alongside the tdd/verification chain. |
| `.claude/agents/engineer.md` | modify | Native mirror of the Engineer reference. |
| `conformance/orchestrator-loop-wired.sh` | modify | `DEBUGGING_SKILL_FILE` var + `check_debugging_skill()` + main-body call + cases 1–17 fixtures gain the skill + Engineer ref + **new cases 18/19**. |
| `conformance/claims.tsv` | modify | Extend the `skill-spine` claim row → debugging + "bricks #1–8". |
| `docs/operations/orchestration.md` | modify | Extend the skill-spine line → the Engineer follows `skills/debugging/SKILL.md`. |
| `VERSION`, `README.md`, `CHANGELOG.md` | modify | Version finishing 3.63.0 → 3.64.0. |

## Tasks (serialized — all touch the shared verifier surface; the parallel-safety rule forbids fan-out)

### Task 1 — Author the skill content (`skills/debugging/SKILL.md`)
Frontmatter `name: debugging` + a conformance-load-bearing HTML comment (mirror `skills/plan/SKILL.md:10-13`, listing the markers). Required content + the EXACT strings the verifier greps (lock now, `grep -qF`, ASCII):
- `## When to use` — any bug, test failure, unexpected behaviour, build/integration failure — BEFORE proposing a fix.
- **The Iron Law** — no fix without `root cause` investigation first; read the actual error/stack trace completely; check recent changes.
- **Reproduce** — verbatim `reproduce`: trigger it reliably; if not reproducible, gather data, don't guess.
- **★ Bug becomes a failing test first** — verbatim `regression test`: reproduce the bug as a regression test that goes red before the fix and green after; chain to `skills/tdd/SKILL.md` (write the failing test) and `skills/verification/SKILL.md` (evidence before claiming fixed). The non-vacuity law applied to bug-fixing.
- **Controlled experiments** — verbatim `one hypothesis`: change one thing at a time; gather evidence before theorizing.
- **Bounded then escalate** — after repeated failed hypotheses, step back / escalate (don't thrash) — ties to the runaway-guard + escalation discipline.
- Red-flags / rationalization table (kept from the proven spine).

**Locked markers (verifier greps all five, `grep -qF`):** `name: debugging` · `root cause` · `reproduce` · `regression test` · `one hypothesis`. (None begins with `-`.)

TDD step: content proven by Task 3's check failing without it. Write to `scratchpad/debugging/SKILL.md`.

### Task 2 — Wire the Engineer (both defs)
- `agents/engineer.agent.md`: in/after the tdd+verification responsibility chain, add "When a test fails or a bug appears, follow the kit's own `skills/debugging/SKILL.md` (read + follow it): find the root cause first; reproduce the bug as a failing regression test before fixing." Must contain literal `skills/debugging/SKILL.md`.
- `.claude/agents/engineer.md`: mirror the reference line.
Author both as full-file copies (or surgical idempotent inserts) under `scratchpad/debugging/`.

### Task 3 — Verifier: the check + non-vacuous teeth (TDD heart)
In a copy of `conformance/orchestrator-loop-wired.sh` under `scratchpad/debugging/`:
1. Add path var: `DEBUGGING_SKILL_FILE="${ORCH_LOOP_DEBUGGING_SKILL:-skills/debugging/SKILL.md}"`.
2. Add `check_debugging_skill()` taking `<skill> <engineer_def>`: assert file exists; `grep -qF` each of the 5 markers; assert `$ENGINEER_DEF` references `skills/debugging/SKILL.md`. Each failure prints a distinct FAIL line + sets miss=1.
3. Main-body call after `check_keystone`: `check_debugging_skill "$DEBUGGING_SKILL_FILE" "$ENGINEER_DEF" || fail=1`.
4. A `_debugging_skill_ok()` emitter (mirror `_vbc_skill_ok`) printing a minimal skill with all 5 markers.
5. Cases 1-17: in EACH, create `$rN/skills/debugging/SKILL.md` via `_debugging_skill_ok`, append `skills/debugging/SKILL.md` to that case's engineer fixture def, and add `ORCH_LOOP_DEBUGGING_SKILL="$rN/skills/debugging/SKILL.md"` to that case's env subshell.
6. **New case 18** (marker teeth): conformant tree, but emit a debugging skill MISSING one marker (drop `regression test`) → assert exit 1.
7. **New case 19** (reference teeth): conformant skill, but the ENGINEER fixture def does NOT reference the skill → assert exit 1.

**Red→green proof (run in scratchpad before assembling apply.py):**
- `sh scratchpad/debugging/orchestrator-loop-wired.sh --selftest` with the skill + all markers + Engineer ref → all 19 cases PASS.
- Mutate case 18 emitter to include all markers → case 18 must FLIP to FAIL ("marker teeth vacuous"). Revert.
- Give case 19 the Engineer ref → case 19 must FLIP to FAIL ("reference teeth vacuous"). Revert.

### Task 4 — Extend the claim + the ops doc (text, no new claim row)
- `conformance/claims.tsv` (the `skill-spine` row): rewrite the description → "… + `debugging` skill (`skills/debugging/SKILL.md`) … referenced by the engineer (TDD + evidence-before-claims **+ debugging**) … bricks **#1–8** …". Keep the same claim id + verifier command (no new row).
- `docs/operations/orchestration.md`: extend the skill-spine sentence → "… and the Engineer follows the kit's own `skills/debugging/SKILL.md` for root-cause debugging — bricks #1–8 …".

### Task 5 — Assemble `scratchpad/debugging/apply.py` (idempotent) + version finishing
One Python3 script (mirror brick #7's apply.py shape, base64-embed the SKILL + verifier): writes `skills/debugging/SKILL.md`; applies the two engineer-def edits (idempotent — skip if reference present); replaces the verifier (idempotent — guard on `check_debugging_skill` presence); edits the claim row + ops line (idempotent string replace, assert old substring present exactly once); bumps VERSION 3.63.0→3.64.0, README badge, prepends a CHANGELOG entry. Every mutation guarded so a re-run is a clean no-op. Print what changed; exit 0.

### Task 6 — Clone dry-run (confabulation-proof gate — itself a use of the verification skill)
`git clone . <unique-dir>` (guard blocks `rm -rf`; use a unique dir) → run `apply.py` → `shellcheck conformance/orchestrator-loop-wired.sh` → `sh conformance/orchestrator-loop-wired.sh --selftest` (19/19 PASS) → `sh conformance/verify.sh --require` (skill-spine PASS, 0 failed) → confirm VERSION==3.64.0 → re-run `apply.py` (idempotent no-op). Capture the log. **Never trust a subagent "done" report — verify on the clone** (`skills/verification/SKILL.md`).

## Self-review (spec coverage — every design requirement → a task)
- Skill content (5 markers + tdd/verification chain) → T1. Engineer wiring (FLOOR+native) → T2. check + cases 18/19 + cases 1–17 fixtures + non-vacuity → T3. Claim + ops doc → T4. AMBER apply.py + version finishing → T5. Clone-proof → T6.
- No guard/registry/verify.sh/export edits → confirmed (confirm-don't-add).
- Single-seat (Engineer only) → T2/T3.
- Placeholder scan: markers are locked literal strings; paths exact; commands carry expected output. No vague steps. ✔
- Build model AMBER stated; human-only ship steps reserved. ✔

## Terminal state / handoff
Hand to the build skill (`skills/tdd/SKILL.md` via the Engineer seat / subagent-driven build): produce `scratchpad/debugging/apply.py` + the Task 6 clone log. Then dual review → panel #15 → human applies + ships. Next Phase-2 brick: #9 `evals`.
