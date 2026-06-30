# Plan — `prototype`/`team` → `lean` (honest ceremony dial) — T4 item 7

**Design:** `docs/architecture/2026-06-29-mode-dial-lean-design.md` (owner-approved 2026-06-29).

**Goal:** Collapse the false 3-mode dial to honest `lean`/`enterprise`; `prototype`/`team` deprecate to `lean` (warn + map); lock the honest names + alias.

**Architecture:** Rename the ceremony-mode values in `incept.sh` (the producer) + the CLAUDE template field; add a deprecation alias; extend `mode-enforcement-blind.sh` with a static honest-names assertion. The solo-vs-team axis (`enforce_admins`/review-lane) is untouched.

**Build model:** AMBER — `incept.sh` (script) + `conformance/` + template are control-plane. Anchored-edit `apply.py` (per-file buffer per MAINTAINING §3a), idempotent, clone-proven. Version finishing **3.78.0 → 3.79.0**. Artifacts in `scratchpad/t4-item7/` (gitignored).

**Global constraints:** `lean` scaffolds exactly what `prototype|team` did (no behaviour change to scaffolding); `enterprise` unchanged; backward-compatible (old `--mode` values still work via alias); no human-team "team" reference touched; bootstrap CI stays green.

---

## File map

| File | Shipped? | Change |
|---|---|---|
| `scripts/incept.sh` | ✅ apply.py | `PROCESS_MODES`, default, deprecation alias, prompt, help×2, the `prototype|team)`→`lean)` case, the CLAUDE-stamp sed pattern |
| `templates/PROJECT-CLAUDE-TEMPLATE.md` | ✅ apply.py | mode field `[prototype / team / enterprise]` → `[lean / enterprise]` + disambiguation clause |
| `conformance/mode-enforcement-blind.sh` | ✅ apply.py | fixture string `prototype)`→`lean)`; new static honest-names + alias assertion block + selftest negative |
| `VERSION` · `README.md` · `CHANGELOG.md` | ✅ apply.py | version finishing → 3.79.0 |
| `scratchpad/t4-item7/apply.py` · `cloneproof.sh` | ❌ build-time | applier + clone-proof (incl. the behavioural mode matrix) |

---

## Task 1 — author the anchored edits into `apply.py`

`incept.sh`:
1. `PROCESS_MODES="prototype team enterprise"` → `PROCESS_MODES="lean enterprise"`.
2. `[ -n "$MODE" ] || MODE="team"` → `… MODE="lean"`, immediately followed by the alias:
   `case "$MODE" in prototype|team) echo "notice: --mode '$MODE' is deprecated; using 'lean' (ceremony only — solo-vs-team governance is the separate enforce_admins / review-lane.md axis)" >&2; MODE="lean" ;; esac`.
3. prompt line: `Process mode (prototype/team/enterprise) [team]:` → `Process mode (lean/enterprise) [lean]:`.
4. help comment (line 10) + `--help` usage (line 51): `--mode prototype|team|enterprise` → `--mode lean|enterprise`.
5. the curate case `prototype|team)` → `lean)`.
6. the CLAUDE-stamp `sedi` pattern: match `\[lean / enterprise\]` (the new template placeholder).

`templates/PROJECT-CLAUDE-TEMPLATE.md`: replace the mode field line with the `[lean / enterprise]` form + the disambiguation clause.

`conformance/mode-enforcement-blind.sh`: fixture `case "$mode" in prototype)` → `lean)`; add the static assertion block + selftest negative (Task 2).

apply.py uses per-file buffer accumulation (MAINTAINING §3a) since `incept.sh` and the lock each get multiple edits; idempotent; all-or-abort.

## Task 2 — the lock's new static assertion (the teeth)

In `mode-enforcement-blind.sh` `run()`, after the enforcement-blind scan, add (against `$ROOT/scripts/incept.sh`):
- `grep -q 'PROCESS_MODES="lean enterprise"'` else FAIL "incept mode set is not the honest lean/enterprise".
- assert NO canonical `prototype`/`team` in the dial: `PROCESS_MODES` line must not contain `prototype`/`team`.
- assert the alias present: `grep -Eq 'prototype\|team\).*MODE="lean"'` (or a two-line grep) else FAIL "deprecation alias missing — old --mode values would hard-break or dead names could return".
- selftest negative: a fixture `incept.sh` with `PROCESS_MODES="prototype team enterprise"` (or missing the alias) must FAIL.

Keep the existing enforcement-blind assertion + its selftest intact (the new block is additive).

## Task 3 — clone-prove (static + behavioural mode matrix)

`cloneproof.sh`: clone main → run apply.py → commit → assert:
- `mode-enforcement-blind.sh --selftest` OK; real-run PASS.
- `verify.sh --require` RESULT OK; shellcheck lock OK.
- **behavioural mode matrix** — in the clone, run `incept.sh --noninteractive … --mode X` for X in {prototype, team, lean, enterprise, bogus}:
  - prototype/team → exit 0, stamped CLAUDE.md `Process mode … lean`, stderr has the deprecation notice.
  - lean/enterprise → exit 0, stamped accordingly.
  - bogus → exit 2 (rejected).
- `inception-done.sh` passes on a default-mode incept (default now `lean`).
- grep-assert the human-team language is intact: `review-lane.md` still contains "solo" + "team" upgrade language (unchanged).
- apply.py 2nd run idempotent; exactly 7 files change (incept, template, lock, VERSION, README, CHANGELOG — 6; +0).

## Task 4 — dual review + panel #30 + ship
Reviewer (correctness/non-vacuity/standards) + security-reviewer (project-genesis surface: no enforcement weakened, alias not abusable, human-team language intact, mode stays enforcement-blind). Panel #30. Human ships (apply.py → governance-close `3.79.0 GO` → commit → PR → admin-merge → release-tag).

## Honest ceiling
Shipped lock proves honest names + alias present + enforcement-blind. Behavioural deprecation/error proven at build (clone-proof), not a CI gate (incept needs the full tree). Solo-vs-team axis untouched.
