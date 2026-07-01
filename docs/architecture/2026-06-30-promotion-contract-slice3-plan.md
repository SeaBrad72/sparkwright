# Plan — Proportional Promotion Contract Slice 3: proportional gates + honest team/solo state label

**Goal:** Make the `control-plane-ratification` gate class-aware and emit a legible, honest team/solo SoD state label, without adding a parallel gate or changing solo behaviour.

**Architecture:** A pure `ratification_state()` derivation + a `--state` seam in `conformance/agent-boundary.sh` (selftest-able, exit-code contract untouched); `.github/workflows/ci.yml` consumes `--state` and Slice 2's `promotion-readiness.sh --class` to render a plain-language, class-aware check-run; a new `proportional-gate` claim/lock proves the wiring + legibility non-vacuously.

**Tech stack:** POSIX sh (dash-clean), GitHub Actions YAML, the kit's conformance/claims registry.

**Global constraints (verbatim from the spec):**
- The gate's pass/fail teeth and exit codes are UNCHANGED (control-plane still requires ratification, fail-closed; three-state 0/1/2 with CI/`--require` escalation intact; all current `agent-boundary --selftest` cases stay green).
- The state label is a PRE-MERGE PROJECTION, not a post-merge audit record. Solo behaviour does not change. No new blocking for Sensitive (`review-lane.md` owns that rigor).
- Stable tokens `RATIFIED-BY-SECOND-REVIEWER` / `SOLO-ADMIN-OVERRIDE-LOGGED` are byte-stable machine identifiers; every human-needed surface pairs the token with plain language (what changed · what it means · honest SoD state · what to do incl. the exact solo command · where to read more).
- Auto-GO is OUT of scope (deferred to a scorecard-live follow-on). Spike×Ordinary no-gate stands.

**Build model: AMBER.** Every file below is control-plane. Author under `scratchpad/promotion-contract-s3/`, assemble one idempotent `apply.py` (version-finishing folded in), clone-prove, hand to the human to apply. No silent agent commit to these paths.

---

## File map (every file, single responsibility)

| File | Control-plane? | Change |
|---|---|---|
| `conformance/agent-boundary.sh` | yes | + `ratification_state()` pure fn, `--state` mode, 3 new selftest cases |
| `.github/workflows/ci.yml` | yes | `control-plane-ratification` step: compute class + state, render legible class-aware check-run |
| `conformance/proportional-gate-wired.sh` | yes (new) | the lock: label behaviour + ci.yml wiring + legibility anchors, non-vacuous |
| `conformance/claims.tsv` | yes | + `proportional-gate` row |
| `conformance/claims-registry.sh` | yes | + `proportional-gate` in `REQUIRED_IDS` (line 17) |
| `conformance/verify.sh` | yes | + `check control proportional-gate …` line |
| `docs/governance/promotion-contract.md` | yes | build-status table: Slice 3 → shipped (version at ship) |
| `DEVELOPMENT-PROCESS.md` | yes | §13: one additive ref line (the gate emits the team/solo state label) |
| `VERSION` · `CHANGELOG.md` · `README.md` | yes | version finishing (folded into apply.py) |

All interlock through one `apply.py`; **serialize** (single engineer) — not parallel (shared files: the lock greps ci.yml that another task edits).

---

## Task 1 — `ratification_state()` + `--state` mode in `agent-boundary.sh`

**TDD:** add the 3 selftest cases first (they fail — no `--state` yet), then implement.

**1a. Add the pure derivation** (insert after `boundary_decide()`, before `run()`):

```sh
# ratification_state <newline-paths> <ratified 0|1> [<union>]: the honest SoD state label for the
# human GO. PURE (no env can force it; the selftest drives it directly). A PRE-MERGE PROJECTION —
# it names the SoD reality the merge will have, it does not observe the future keystroke.
#   control-plane present + ratified=1 -> RATIFIED-BY-SECOND-REVIEWER (team; SoD genuinely exercised)
#   control-plane present + ratified=0 -> SOLO-ADMIN-OVERRIDE-LOGGED  (solo; logged admin-override)
#   no control-plane path              -> NONE (N/A — nothing to ratify)
ratification_state() {
  _list=$1; _rat=$2; _union=${3:-}; _cp=0
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    if is_control_plane_path "$_p" || path_in_union "$_p" "$_union"; then _cp=1; break; fi
  done <<EOF
$_list
EOF
  [ "$_cp" = 1 ] || { echo NONE; return 0; }
  if [ "$_rat" = 1 ]; then echo RATIFIED-BY-SECOND-REVIEWER; else echo SOLO-ADMIN-OVERRIDE-LOGGED; fi
}
```

**1b. Add the `--state` CLI mode.** In the arg-parse loop add `--state) MODE="state"; shift ;;`. Add a `state()` function (CI-independent — advisory, never escalates):

```sh
state() {  # advisory label for the CI human-surface; CI-independent, always exit 0
  [ -f "$CORE" ] || { echo NONE; exit 0; }
  # shellcheck disable=SC1090
  . "$CORE"
  { [ -n "$CHANGED" ] && [ -f "$CHANGED" ]; } || { echo NONE; exit 0; }
  ratification_state "$(cat "$CHANGED")" "$RATIFIED" "$(adapter_union)"
  exit 0
}
```

In the terminal `case "$MODE"` add `state) state ;;` before `*) run`.

**1c. Add 3 selftest cases** to `selftest()` (after the existing `dc` block, reusing the sourced core):

```sh
  # slice 3: the honest SoD state label (pure ratification_state, driven in-process)
  rs() {  # expect label paths ratified [union]
    e=$1; p=$2; r=$3; u=${4:-}; g=$(ratification_state "$p" "$r" "$u")
    if [ "$g" = "$e" ]; then echo "selftest PASS: state $e"; else echo "selftest FAIL: state want $e got $g"; st=1; fi
  }
  rs RATIFIED-BY-SECOND-REVIEWER ".github/workflows/ci.yml" 1 ""
  rs SOLO-ADMIN-OVERRIDE-LOGGED  ".github/workflows/ci.yml" 0 ""
  rs NONE                        "src/app.ts" 0 ""
  # load-bearing negative: an always-team mutation flips the solo case above; assert distinction too
  if [ "$(ratification_state '.github/workflows/ci.yml' 0)" = "$(ratification_state '.github/workflows/ci.yml' 1)" ]; then
    echo "selftest FAIL: solo/team labels identical (vacuous)"; st=1; fi
```

**Verify:** `sh conformance/agent-boundary.sh --selftest` ends `agent-boundary --selftest: OK`; `sh conformance/agent-boundary.sh --changed /tmp/cp.txt --ratified 0 --state` prints `SOLO-ADMIN-OVERRIDE-LOGGED`. All pre-existing cases stay green (exit-code path untouched).

**Honest ceiling:** the selftest proves the derivation is correct on fixtures, not that a real PR was ratified.

---

## Task 2 — the lock `conformance/proportional-gate-wired.sh` (new)

Write the full file (note: variable named `WF`, **never `CI`** — `CI` is the env var agent-boundary reads for escalation; shadowing it would break the `--state` calls and the gate):

```sh
#!/bin/sh
# proportional-gate-wired.sh — regression-lock for Proportional Promotion Contract slice 3
# (docs/governance/promotion-contract.md): the control-plane-ratification gate is (a) class-aware
# and (b) emits the honest team/solo SoD state label, surfaced in LEGIBLE plain language for the
# human who must act. Tokens are machine-stable; the gloss is human-required and locked here.
#   sh conformance/proportional-gate-wired.sh [--selftest]
# Exit: 0 = ok · 1 = drift · 2 = usage. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true
AB="conformance/agent-boundary.sh"
WF=".github/workflows/ci.yml"
PR="conformance/promotion-readiness.sh"

label() { sh "$AB" --changed "$1" --ratified "$2" --state 2>/dev/null; }  # -> SoD state label

selftest() {
  st=0; d=$(mktemp -d)
  printf '.github/workflows/ci.yml\n' > "$d/cp.txt"
  printf 'src/util/format.ts\n'       > "$d/ord.txt"
  lk() { _g=$(label "$2" "$3"); if [ "$_g" = "$1" ]; then echo "PASS: $4 -> $_g"; else echo "FAIL: $4 want $1 got $_g"; st=1; fi; }
  lk RATIFIED-BY-SECOND-REVIEWER "$d/cp.txt"  1 "control-plane + ratified -> team label"
  lk SOLO-ADMIN-OVERRIDE-LOGGED  "$d/cp.txt"  0 "control-plane + unratified -> solo label"
  lk NONE                        "$d/ord.txt" 0 "ordinary -> no label (N/A)"
  # load-bearing negative: solo and team labels must differ (always-team mutation -> this FAILs)
  if [ "$(label "$d/cp.txt" 0)" = "$(label "$d/cp.txt" 1)" ]; then
    echo "FAIL: solo and team labels identical (state derivation vacuous)"; st=1; fi
  # ci.yml wiring: class-aware (--class call) + both tokens surfaced
  for tok in '--class' 'RATIFIED-BY-SECOND-REVIEWER' 'SOLO-ADMIN-OVERRIDE-LOGGED'; do
    grep -qF -- "$tok" "$WF" || { echo "FAIL: ci.yml missing '$tok' in the ratification gate"; st=1; }
  done
  # legibility anchors: the human-needed (action_required) summary is plain-language, not jargon
  for a in 'Ratification required' 'NOT a build failure' 'gh pr merge' 'review-lane.md'; do
    grep -qF -- "$a" "$WF" || { echo "FAIL: ci.yml missing legibility anchor '$a'"; st=1; }
  done
  [ "$st" = 0 ] && echo "OK: proportional-gate-wired selftest" || echo "FAIL: proportional-gate-wired selftest"
  return $st
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") for f in "$AB" "$WF" "$PR"; do [ -f "$f" ] || { echo "FAIL: missing $f"; exit 1; }; done
      echo "OK: proportional-gate wiring present"; exit 0 ;;
  *) echo "usage: proportional-gate-wired.sh [--selftest]" >&2; exit 2 ;;
esac
```

`chmod 0755`. **Non-vacuity proof (build-time, by hand):** (i) mutate `ratification_state` to always echo `RATIFIED-BY-SECOND-REVIEWER` → the solo `lk` case + the identical-labels negative FAIL; (ii) delete the `--class` call from ci.yml → the `--class` grep FAILs; (iii) strip one legibility sentence → the matching anchor FAILs. Record all three flips in the build report.

---

## Task 3 — legible, class-aware check-run in `ci.yml`

In the `gate-agent-boundary` job, after the existing `Compute ratification signal` step and the run that computes `rc`, **replace** the `case "$rc"` conclusion block + the `gh api` post with the class+state-aware version. Add, inside the same `run: |`:

```sh
          state=$(CI= sh conformance/agent-boundary.sh --changed /tmp/changed.txt \
                    --ratified "${{ steps.ratify.outputs.ratified }}" --state 2>/dev/null || echo NONE)
          class=$(sh conformance/promotion-readiness.sh --class --no-verify \
                    --changed /tmp/changed.txt 2>/dev/null || echo control-plane)
          case "$rc" in
            0)
              if [ "$state" = RATIFIED-BY-SECOND-REVIEWER ]; then
                concl=success
                title="Ratified by a second reviewer — control-plane change approved"
                summary="What changed: a control-plane change (change-class: ${class}). State: RATIFIED-BY-SECOND-REVIEWER — a non-author reviewer approved this PR, so separation-of-duties is genuinely satisfied. No action needed. More: docs/operations/review-lane.md."
              else
                concl=success
                title="No control-plane change — nothing to ratify"
                summary="What changed: change-class ${class}; no control-plane paths in the diff. This §13 governance gate has nothing to ratify. No action needed."
              fi
              ;;
            1)
              concl=action_required
              title="Ratification required — a control-plane change is awaiting a human"
              summary="What changed: a control-plane change (the kit's own guardrails / CI / standards / governance). Change-class: ${class}. Why: control-plane changes must be ratified by a human before merge. This is a §13 governance merge-gate, NOT a build failure — no test failed. Current SoD state: SOLO-ADMIN-OVERRIDE-LOGGED — no non-author approval is present yet, so the only merge path is a logged solo admin-override (honestly weaker than a second reviewer). To proceed: (a) get a non-author approval on this PR -> becomes RATIFIED-BY-SECOND-REVIEWER; or (b) solo -- merge via 'gh pr merge --squash --admin --delete-branch'; GitHub logs the override as the audit trail. More: docs/operations/review-lane.md."
              ;;
            *)
              concl=failure
              title="Gate error — could not evaluate the control-plane diff"
              summary="The control-plane-ratification gate could not evaluate the PR diff (change listing unavailable). This IS a real error — unlike the other states it needs fixing. See conformance/agent-boundary.sh."
              ;;
          esac
          gh api -X POST "repos/${{ github.repository }}/check-runs" \
            -f name='control-plane-ratification' \
            -f head_sha="$SHA" \
            -f status='completed' \
            -f conclusion="$concl" \
            -f 'output[title]'="$title" \
            -f 'output[summary]'="$summary"
          echo "control-plane-ratification => $concl (rc=$rc, class=$class, state=$state)"
```

Keep the surrounding `set +e/-e` around the `rc` computation and the job's `exit 0` semantics. **Verify:** `actionlint .github/workflows/ci.yml` clean (watch the [[release-finishing]] lesson — colons live only inside the `run: |` literal scalar, never in a step `name:`); `grep -F` for each token/anchor the lock checks succeeds.

---

## Task 4 — registry wiring (3 coordinated edits — miss one and conformance goes RED)

1. **`conformance/claims.tsv`** — append (tab-separated):
   `proportional-gate␉the control-plane-ratification gate is class-aware (consumes promotion-readiness --class) and emits the honest team/solo SoD state label (RATIFIED-BY-SECOND-REVIEWER / SOLO-ADMIN-OVERRIDE-LOGGED), surfaced in legible plain language for the human who must act; pre-merge projection, solo behaviour unchanged␉sh conformance/proportional-gate-wired.sh --selftest`
2. **`conformance/claims-registry.sh` line 17** — append ` proportional-gate` to the end of the `REQUIRED_IDS` string (inside the quotes).
3. **`conformance/verify.sh`** — add after the `escalation-seam` line: `check control proportional-gate sh conformance/proportional-gate-wired.sh --selftest`.

**Verify:** `sh conformance/claims-registry.sh` → `PASS: proportional-gate` + `coverage intact`; `sh conformance/verify.sh --require` → `RESULT: OK`, control-count +1.

---

## Task 5 — docs + version finishing

- **`docs/governance/promotion-contract.md`** build-status table: change the Slice 3 row Status from `planned` to the ship version (set at apply time, e.g. `v3.82.0`) and the build-status §"Build status" table likewise. Tighten the lead-paragraph note that enforcement "lands in slices 3–4" → "slice 4" once 3 ships.
- **`DEVELOPMENT-PROCESS.md` §13** — one additive sentence: the `control-plane-ratification` gate now emits the honest team/solo SoD state label (`RATIFIED-BY-SECOND-REVIEWER` / `SOLO-ADMIN-OVERRIDE-LOGGED`) and is class-aware; respect the doc-budget ratchet (if the §13 bucket is at cap, raise it one bucket in the same apply.py, mirroring Slice 1).
- **Version finishing folded into apply.py:** bump `VERSION` (minor: `3.81.0` → `3.82.0`), add the `README.md` version badge bump, prepend a `CHANGELOG.md` entry under a new version heading.

---

## Task 6 — assemble `apply.py` + clone-prove

Idempotent `scratchpad/promotion-contract-s3/apply.py` applying every edit above (per-file in-memory buffer when a file gets ≥2 edits — MAINTAINING §3a; `set -f` noglob discipline in any shell the build runs). **Clone-prove on a throwaway clone:**
1. `shellcheck` clean on the two changed/added `conformance/*.sh`.
2. `actionlint` clean on `ci.yml`.
3. `sh conformance/agent-boundary.sh --selftest` OK (old + 3 new cases).
4. `sh conformance/proportional-gate-wired.sh --selftest` OK + the 3 non-vacuity flips recorded.
5. `sh conformance/claims-registry.sh` OK (coverage intact).
6. `sh conformance/verify.sh --require` → `RESULT: OK`.
7. apply.py re-run = no-op (idempotent).
8. `git show --stat` after a dry-run commit lists ALL nine files (keystone-coupling lesson — no half-land).

---

## Dual review (builder ≠ reviewer)

- **`reviewer`** (correctness): exit-code contract preserved; the `rc`→conclusion mapping; idempotency; registry coverage; no placeholder.
- **`security-reviewer`** (the SoD/honesty lens): can the label ever over-claim a protection not exercised? Is the projection tense honest? Can `--state` be coerced (env) to emit team when solo? Does the class call leak anything on its stdout into the check-run? Control-plane completeness (no NEW control-plane path created → no guard-matcher gap, but confirm).

## Ship (human; standing flow)
apply.py → governance close (separate `governance-close.py`: marker `3.82.0 GO` + meta-control-log row) → commit (`git show --stat` confirms all nine) → push → PR → green conformance → `gh pr merge --squash --admin --delete-branch` (solo control-plane PR is red on `control-plane-ratification` by design) → `git checkout main && git pull && sh scripts/release-tag.sh`.

## Spec coverage check
AC1 → Task 1 + Task 2 selftest. AC2 (incl. legibility) → Task 3 + Task 2 anchors. AC3 → Task 2 non-vacuity. AC4 → Task 1 (exit-code untouched) + clone-prove step 3. AC5 → Task 4 + Task 5 + clone-prove steps 5-6.
