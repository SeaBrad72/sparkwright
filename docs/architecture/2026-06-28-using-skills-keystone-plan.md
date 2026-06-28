# Implementation plan — skill-spine brick #7 (KEYSTONE): the kit's own `using-skills` discovery skill

**Planned by dogfooding `skills/plan/SKILL.md`** (6th self-host use). Source design: `docs/architecture/2026-06-28-using-skills-keystone-design.md` (owner-approved 2026-06-28).

## Goal
Ship the kit's own `using-skills` discovery keystone — the kit's `using-superpowers`-equivalent (discovery discipline + index of the 6 spine skills) — wired single-seat to the Orchestrator, with non-vacuous index + reference teeth, as one atomic AMBER `apply.py`. Completes the spine → unblocks E10.

## Architecture
A new FLOOR skill (`skills/using-skills/SKILL.md`, invoke-by-read) encodes the discovery discipline AND indexes the 6 spine skills; the Orchestrator def (FLOOR + native) gains a "start here" keystone reference; the shared verifier `conformance/orchestrator-loop-wired.sh` gains `check_keystone` (asserts the skill + all-6-index + discipline markers + Orchestrator reference) + two negative selftest cases; the `skill-spine` claim and `orchestration.md` extend to "bricks #1–7". No new gate, no new claim, no guard edit (`skills/*` already control-plane).

## Tech stack
POSIX sh (verifier), Python3 (`apply.py`), Markdown (skill + defs + docs), TSV (claims). No new dependencies.

## Global constraints (verbatim from the design + standing process)
- **FLOOR-only / invoke-by-read** — no formal `skills` adapter dimension; no registry/verify.sh/export/guard edits (confirm `skills/*` glob already covers the new file — **confirm-don't-add**).
- **Single-seat Orchestrator** — the verifier asserts the Orchestrator references the keystone; no other seat is asserted.
- **Index coupling** — the keystone names all 6 spine skills; the verifier greps each. Exhaustive by design.
- **AMBER** — control-plane. Author under `scratchpad/keystone/`, assemble an idempotent `apply.py`, prove on a **clone dry-run** (`shellcheck` + `verify.sh --require`), hand to the human to apply. The agent never applies/commits-the-applied-diff/pushes/merges/tags ([[merge-tag-authority]]).
- **Version finishing folded into apply.py** — VERSION 3.62.0 → **3.63.0**, README badge, CHANGELOG entry ([[release-finishing-in-apply-py]]).
- **Non-vacuity** — each new selftest case must FAIL a dead/always-pass check (drop-an-index-name + omit-the-reference).
- **ASCII-only verifier markers** — `grep -qF`, ASCII. The index greps are path strings (`skills/design` … `skills/verification`); none begins with `-`, so plain `grep -qF` is safe.
- **Honest ceiling** — the entry-point is a documented convention, not enforced auto-load; state it in SKILL.md + orchestration.md.
- **Dual review** (reviewer + security-reviewer) → **meta-control panel #14** → fold the close INTO the feature PR.

## Build model
**AMBER** — every task below is authored in `scratchpad/keystone/`; nothing lands on a control-plane path as a silent agent commit. The single deliverable is `scratchpad/keystone/apply.py` + its clone-proven dry-run log.

## File map (every path the apply.py creates/modifies)
| Path | Change | Responsibility |
|------|--------|----------------|
| `skills/using-skills/SKILL.md` | **create** | The discovery discipline + the index of the 6 spine skills. Carries the conformance-load-bearing markers + the 6 skill-path names. |
| `agents/orchestrator.agent.md` | modify | Add a "start here" discovery reference → `skills/using-skills/SKILL.md`. |
| `.claude/agents/orchestrator.md` | modify | Native mirror of the discovery reference. |
| `conformance/orchestrator-loop-wired.sh` | modify | `KEYSTONE_FILE` var + `check_keystone()` + main-body call + cases 1–15 fixtures gain the keystone + Orchestrator ref + **new cases 16/17**. |
| `conformance/claims.tsv` | modify | Extend the `skill-spine` claim row → keystone + "bricks #1–7 … content + discovery". |
| `docs/operations/orchestration.md` | modify | Extend the skill-spine line + add the entry-point convention note. |
| `VERSION`, `README.md`, `CHANGELOG.md` | modify | Version finishing 3.62.0 → 3.63.0. |

## Tasks (serialized — all touch the shared verifier surface; the parallel-safety rule forbids fan-out)

### Task 1 — Author the keystone content (`skills/using-skills/SKILL.md`)
Frontmatter `name: using-skills` + a conformance-load-bearing HTML comment (mirror `skills/plan/SKILL.md:10-13`, listing the markers + the 6 indexed paths). Required content + the EXACT strings the verifier greps (lock now, `grep -qF`, ASCII):
- `## When to use` — at the start of any task, before any response/action, even a 1% chance a skill applies.
- **Discovery discipline** — verbatim **`invoke by reading`** (read `skills/<name>/SKILL.md` and follow it — the harness-neutral FLOOR); check for a relevant skill verbatim **`before acting`**; rigid skills are followed exactly; process-skills before implementation-skills.
- **Instruction priority** — verbatim **`user instructions`** (skills override defaults, but explicit user instructions always win).
- **The index — names ALL 6 spine skills as paths** (each must appear verbatim for the index teeth): `skills/design` (idea → owner-approved spec), `skills/plan` (spec → build-ready plan), `skills/tdd` (build a slice test-first), `skills/review` (judge a diff before merge), `skills/worktrees` (isolate parallel fan-out), `skills/verification` (evidence before any "done" claim).
- **Entry-point honesty** — a short note that on the FLOOR this is a convention the conductor follows (auto-load is harness-local).
- Red-flags / rationalization table (kept from the proven spine).

**Locked markers (verifier greps, `grep -qF`):** discipline → `name: using-skills` · `invoke by reading` · `before acting` · `user instructions`; index → `skills/design` · `skills/plan` · `skills/tdd` · `skills/review` · `skills/worktrees` · `skills/verification`. (None begins with `-`.)

TDD step: content proven by Task 3's check failing without it. Write to `scratchpad/keystone/SKILL.md`.

### Task 2 — Wire the Orchestrator (both defs)
- `agents/orchestrator.agent.md`: add a discovery "start here" reference — when convening the cast per phase, consult the kit's own discovery keystone `skills/using-skills/SKILL.md` to find the right skill (the kit's `using-superpowers`-equivalent; invoke-by-read). Literal `skills/using-skills/SKILL.md` must appear.
- `.claude/agents/orchestrator.md`: mirror the reference line.
Author both as full-file copies under `scratchpad/keystone/`.

### Task 3 — Verifier: the check + index/reference teeth (TDD heart)
In a copy of `conformance/orchestrator-loop-wired.sh` under `scratchpad/keystone/`:
1. Add path var: `KEYSTONE_FILE="${ORCH_LOOP_KEYSTONE:-skills/using-skills/SKILL.md}"`.
2. Add `check_keystone()` taking `<keystone> <orch_def>`: assert file exists; `grep -qF` each discipline marker (`name: using-skills`, `invoke by reading`, `before acting`, `user instructions`); `grep -qF` each of the 6 index paths (`skills/design`…`skills/verification`); assert `$ORCH_DEF` references `skills/using-skills/SKILL.md`. Each failure prints a distinct FAIL line + sets miss=1.
3. Main-body call after `check_vbc_skill`: `check_keystone "$KEYSTONE_FILE" "$ORCH_DEF" || fail=1`.
4. A `_keystone_ok()` emitter (mirror `_vbc_skill_ok`) printing a minimal keystone with all 4 discipline markers + all 6 index paths.
5. Cases 1-15: in EACH, create `$rN/skills/using-skills/SKILL.md` via `_keystone_ok`, append `skills/using-skills/SKILL.md` to that case's orchestrator fixture def, and add `ORCH_LOOP_KEYSTONE="$rN/skills/using-skills/SKILL.md"` to that case's env subshell.
6. **New case 16** (index teeth): conformant tree, but emit a keystone MISSING one index path (drop `skills/verification`) → assert exit 1.
7. **New case 17** (reference teeth): conformant keystone, but the Orchestrator fixture def does NOT reference the keystone → assert exit 1.

**Red→green proof (run in scratchpad before assembling apply.py):**
- `sh scratchpad/keystone/orchestrator-loop-wired.sh --selftest` with keystone present + all markers/index + ref → all 17 cases PASS.
- Mutate case 16 emitter to include all 6 index paths → case 16 must FLIP to FAIL ("index teeth vacuous"). Revert.
- Give case 17 the Orchestrator ref → case 17 must FLIP to FAIL ("keystone reference teeth vacuous"). Revert.

### Task 4 — Extend the claim + the ops doc (text, no new claim row)
- `conformance/claims.tsv` (the `skill-spine` row): rewrite the description → "… + the `using-skills` discovery keystone (`skills/using-skills/SKILL.md`) indexing the 6 spine skills, referenced by the orchestrator (discovery) … bricks **#1–7** — the kit's own skill spine replacing superpowers (content + discovery)". Keep the same claim id + verifier command (no new row).
- `docs/operations/orchestration.md`: extend the skill-spine sentence + add the entry-point convention note (the Orchestrator/session consults `skills/using-skills/SKILL.md` first; on the FLOOR this is convention, NATIVE can auto-surface) — bricks #1–7.

### Task 5 — Assemble `scratchpad/keystone/apply.py` (idempotent) + version finishing
One Python3 script (mirror brick #6's apply.py shape, base64-embed the SKILL + verifier): writes `skills/using-skills/SKILL.md`; applies the two orchestrator-def edits (idempotent — skip if reference present); replaces the verifier (idempotent — guard on `check_keystone` presence); edits the claim row + ops line (idempotent string replace, assert old substring present exactly once); bumps VERSION 3.62.0→3.63.0, README badge, prepends a CHANGELOG entry. Every mutation guarded so a re-run is a clean no-op. Print what changed; exit 0.

### Task 6 — Clone dry-run (confabulation-proof gate — itself a use of the verification skill)
`git clone . <unique-dir>` (guard blocks `rm -rf`; use a unique dir) → run `apply.py` → `shellcheck conformance/orchestrator-loop-wired.sh` → `sh conformance/orchestrator-loop-wired.sh --selftest` (17/17 PASS) → `sh conformance/verify.sh --require` (skill-spine PASS, 0 failed) → confirm VERSION==3.63.0 → re-run `apply.py` (idempotent no-op). Capture the log. **Never trust a subagent "done" report — verify on the clone** (`skills/verification/SKILL.md`).

## Self-review (spec coverage — every design requirement → a task)
- Keystone content (discipline + index, 4 markers + 6 paths) → T1. Orchestrator wiring (FLOOR+native) → T2. check + cases 16/17 + cases 1–15 fixtures + index/reference non-vacuity → T3. Claim + ops doc + entry-point note → T4. AMBER apply.py + version finishing → T5. Clone-proof → T6.
- No guard/registry/verify.sh/export edits → confirmed (confirm-don't-add).
- Single-seat (Orchestrator only) → T2/T3. Index names all 6 + index-teeth proven (case 16) → T1/T3.
- Honest ceiling (entry-point convention) → T1 + T4.
- Placeholder scan: markers + index paths are locked literal strings; paths exact; commands carry expected output. No vague steps. ✔
- Build model AMBER stated; human-only ship steps reserved. ✔

## Terminal state / handoff
Hand to the build skill (`skills/tdd/SKILL.md` via the Engineer seat / subagent-driven build): produce `scratchpad/keystone/apply.py` + the Task 6 clone log. Then dual review → panel #14 → human applies + ships. **This completes the skill spine; the next epic is E10 (zero-superpowers acceptance).**
