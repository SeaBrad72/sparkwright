#!/bin/sh
# promotion-contract-documented.sh — doc-coherence guard for the Proportional Promotion Contract
# (Slice 1, design 2026-06-29-proportional-promotion-contract-design.md). Asserts the canonical
# model doc STATES each load-bearing invariant of the contract AND — the teeth — that the matrix's
# Control-plane column is human-governed at every rung and is NEVER relaxed to an "agent autonomous"
# disposition. This verifies the model is DOCUMENTED COHERENTLY (documentation drift), NOT that the
# running gates enforce it — enforcement is slices 2-4 (control-plane-ratification / agent-boundary
# remain the live boundary, unchanged here). Judgment quality stays un-gateable (honest ceiling).
#
#   sh conformance/promotion-contract-documented.sh [model-doc-path]   (default: docs/governance/promotion-contract.md)
#   sh conformance/promotion-contract-documented.sh --selftest
# Exit: 0 = model documented coherently · 1 = a marker missing or the control-plane column relaxed.
# POSIX sh; dash-clean. Modeled on conformance/assurance-tiers.sh (match the row, compare the cell
# exactly — never a substring anywhere — so prose elsewhere can't mask a revert).
set -eu

check_file() {
  doc="$1"
  if [ ! -f "$doc" ]; then echo "FAIL: model doc not found ($doc)"; return 1; fi
  fail=0

  # --- Part A: load-bearing prose markers (each must be present) -------------------------
  # require <label> <regex> — case-insensitive presence anywhere in the doc.
  require() {
    _lab="$1"; _re="$2"
    if grep -qiE "$_re" "$doc"; then
      echo "PASS: marker $_lab"
    else
      echo "FAIL: marker $_lab missing (/$_re/)"; fail=1
    fi
  }
  require 'model-sentence'      'rigor[^a-z]*=[^a-z]*f\(.*rung.*change-class'
  require 'fail-safe-derivation' 'default to the higher class'
  require 'change-class-derived' 'is_control_plane_path'
  require 'deferral-not-waiver' 'deferral[,[:space:]].*not.*waiver'
  require 'ratchet'             'ratchet.* at every promotion'
  require 'promotion-readiness' 'promotion-readiness'
  require 'go-nogo-judgment'    'GO/NO-GO'
  require 'judgment-not-keystroke' 'judgment,? *not.*keystroke'
  require 'state-label-team'    'RATIFIED-BY-SECOND-REVIEWER'
  require 'state-label-solo'    'SOLO-ADMIN-OVERRIDE-LOGGED'
  # Slice 4: the delegable-execution rule is documented coherently — WITH its two load-bearing
  # carve-outs (control-plane execution stays human; delegation is only AFTER a recorded GO). A doc
  # that documents delegation but drops either carve-out is a fox/henhouse gap and MUST fail.
  require 'delegable-post-go'        'delegable after.*recorded.*GO'
  require 'never-unilateral'         'never unilateral'
  require 'cp-execution-human'       'control-plane execution stays human'
  require 'admin-merge-honesty'      'gh pr merge --admin'

  # --- Part B: the matrix header names all three change-classes -------------------------
  if grep -E '^\|' "$doc" | grep -qiE 'Ordinary' \
     && grep -E '^\|' "$doc" | grep -qiE 'Sensitive' \
     && grep -E '^\|' "$doc" | grep -qiE 'Control-plane'; then
    echo "PASS: matrix names Ordinary/Sensitive/Control-plane"
  else
    echo "FAIL: matrix must name all three change-classes (Ordinary/Sensitive/Control-plane)"; fail=1
  fi

  # --- Part C: THE TEETH — the Control-plane column (LAST matrix cell) is human-governed at
  # every rung and never relaxed to an autonomous disposition. Match only a TABLE ROW whose FIRST
  # cell is the rung label, then read the LAST cell exactly (the Control-plane column). A stale
  # word in the row's prose or a line above the table cannot mask a reverted final cell.
  assert_cp_cell() {
    _lab="$1"
    _row=$(grep -iE "^\|[^|]*$_lab" "$doc" | head -1 || true)
    if [ -z "$_row" ]; then
      echo "FAIL: no matrix rung-row for '$_lab'"; fail=1; return 0
    fi
    _cell=$(printf '%s' "$_row" | sed 's/.*|\([^|]*\)|[[:space:]]*$/\1/; s/^[[:space:]]*//; s/[[:space:]]*$//')
    # Negative: reject ANY agent-actuation / autonomy disposition, not just the canonical
    # "agent autonomous" phrasing — a future cell must not relax the control-plane by euphemism
    # ("agent merges; human notified", "auto-merge on green", "delegated to agent"). Dual-review
    # hardening (#27). 'auto' also covers autonomous/automated/auto-{merge,apply}. POSIX-portable (no \b).
    if printf '%s' "$_cell" | grep -qiE 'no human gate|agent[ -]?(self|merge|commit|appl|tag|push|actuat|autonom)|self-govern|auto|delegat'; then
      echo "FAIL: Control-plane column relaxed at '$_lab' — cell is '$_cell' (control-plane must stay human-governed)"; fail=1; return 0
    fi
    # Positive: require an EXPLICIT human-actuation disposition. A bare 'human' mention cannot rescue
    # an agent-actuating cell (that gaming path was closed in dual review #27).
    if printf '%s' "$_cell" | grep -qiE 'human-authored|control-plane-ratification|human ratif|human-gated|human gate|AMBER|meta-control|N/A'; then
      echo "PASS: Control-plane@$_lab human-governed -> '$_cell'"
    else
      echo "FAIL: Control-plane@$_lab cell '$_cell' is not a recognized human-governed disposition"; fail=1
    fi
  }
  assert_cp_cell 'Spike'
  assert_cp_cell 'Integration'
  assert_cp_cell 'Release candidate'
  assert_cp_cell 'Staging/UAT'
  assert_cp_cell 'Production'

  if [ "$fail" -ne 0 ]; then echo "promotion-contract-documented: FAIL ($doc)"; return 1; fi
  echo "promotion-contract-documented: OK — contract documented coherently, control-plane column human-governed ($doc)"
  return 0
}

# mktemp fixtures; assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard convention).
selftest() {
  st=0
  base=$(mktemp -d)

  # A complete, correct fixture: every marker + a matrix whose Control-plane column is human-governed.
  good="$base/good.md"
  cat > "$good" <<'EOF'
# The Proportional Promotion Contract (model)
rigor = f(rung × change-class), modulated by trust.
Control-plane is path-derived (is_control_plane_path). Fail-safe: default to the higher class.
Relaxation = deferral, not a waiver. Rigor ratchets at every promotion.
At each promotion the agent emits a promotion-readiness surfacing.
The human renders a GO/NO-GO — a recorded judgment, not a keystroke.
Solo/team: RATIFIED-BY-SECOND-REVIEWER vs SOLO-ADMIN-OVERRIDE-LOGGED.
Execution is delegable after an explicit recorded human GO.
The delegation is never unilateral at a promotion.
Control-plane execution stays human at every rung.
The gh pr merge --admin bypass is a human act.

| Rung | Ordinary | Sensitive | Control-plane |
|---|---|---|---|
| **Spike** | Agent autonomous (L3) | Human-gated | Human-authored |
| **Integration** | Automated gates | Human GO | AMBER apply + control-plane-ratification |
| **Release candidate** | Human GO | Dual review + GO | human ratify + meta-control |
| **Staging/UAT** | smoke + sign-off | + threat re-check | N/A |
| **Production** | human-commanded | human-commanded | N/A |
EOF
  if check_file "$good" >/dev/null 2>&1; then echo "selftest PASS: complete+human-governed -> OK"; else echo "selftest FAIL: complete fixture should pass"; st=1; fi

  # Missing a marker (drop the deferral-not-waiver line) -> FAIL.
  miss="$base/missing.md"
  grep -v 'deferral' "$good" > "$miss"
  if check_file "$miss" >/dev/null 2>&1; then echo "selftest FAIL: missing marker should FAIL"; st=1; else echo "selftest PASS: missing marker -> FAIL"; fi

  # THE LOAD-BEARING NEGATIVE: Control-plane@Integration relaxed to 'Agent autonomous' -> MUST FAIL.
  relaxed="$base/cp-relaxed.md"
  sed 's/AMBER apply + control-plane-ratification/Agent autonomous (L3)/' "$good" > "$relaxed"
  if check_file "$relaxed" >/dev/null 2>&1; then echo "selftest FAIL: relaxed control-plane column should FAIL (non-vacuity broken!)"; st=1; else echo "selftest PASS: relaxed control-plane -> FAIL"; fi

  # Anti-gaming: cell reverted to autonomous but a prose line elsewhere says control-plane stays human.
  mask="$base/prose-mask.md"
  {
    echo 'Note: the Control-plane column stays human-authored at every rung in our intent.'
    sed 's/| AMBER apply + control-plane-ratification |/| Agent autonomous |/' "$good"
  } > "$mask"
  if check_file "$mask" >/dev/null 2>&1; then echo "selftest FAIL: prose-mask should not rescue a relaxed cell"; st=1; else echo "selftest PASS: prose-mask -> FAIL (final cell wins)"; fi

  # Euphemism evasion (dual-review #27): a Control-plane cell that relaxes to agent actuation in
  # natural language — NOT the canonical "agent autonomous" — must STILL FAIL.
  euph="$base/euphemism.md"
  sed 's/AMBER apply + control-plane-ratification/agent merges after GO; human notified/' "$good" > "$euph"
  if check_file "$euph" >/dev/null 2>&1; then echo "selftest FAIL: euphemistic relaxation should FAIL (teeth gap!)"; st=1; else echo "selftest PASS: euphemistic relaxation -> FAIL"; fi

  # And the bare-'human' rescue must not save an auto-merge cell.
  bare="$base/bare-human.md"
  sed 's/AMBER apply + control-plane-ratification/auto-merge on green; human informed/' "$good" > "$bare"
  if check_file "$bare" >/dev/null 2>&1; then echo "selftest FAIL: auto-merge+human should FAIL"; st=1; else echo "selftest PASS: auto-merge+human -> FAIL (bare 'human' cannot rescue)"; fi

  # Slice 4 load-bearing negatives: documenting delegation but DROPPING a carve-out must FAIL.
  nocp="$base/no-cp-carveout.md"
  grep -v 'Control-plane execution stays human' "$good" > "$nocp"
  if check_file "$nocp" >/dev/null 2>&1; then echo "selftest FAIL: dropped control-plane carve-out should FAIL (fox/henhouse gap!)"; st=1; else echo "selftest PASS: dropped control-plane carve-out -> FAIL"; fi

  nogo="$base/no-after-go.md"
  grep -v 'delegable after an explicit recorded human GO' "$good" > "$nogo"
  if check_file "$nogo" >/dev/null 2>&1; then echo "selftest FAIL: dropped after-GO precondition should FAIL"; st=1; else echo "selftest PASS: dropped after-GO precondition -> FAIL"; fi

  nunil="$base/no-never-unilateral.md"
  grep -v 'never unilateral at a promotion' "$good" > "$nunil"
  if check_file "$nunil" >/dev/null 2>&1; then echo "selftest FAIL: dropped never-unilateral should FAIL"; st=1; else echo "selftest PASS: dropped never-unilateral -> FAIL"; fi

  nadmin="$base/no-admin-honesty.md"
  grep -v 'gh pr merge --admin' "$good" > "$nadmin"
  if check_file "$nadmin" >/dev/null 2>&1; then echo "selftest FAIL: dropped admin-honesty should FAIL"; st=1; else echo "selftest PASS: dropped admin-honesty -> FAIL"; fi

  if [ "$st" -ne 0 ]; then echo "promotion-contract-documented --selftest: FAIL" >&2; return 1; fi
  echo "promotion-contract-documented --selftest: OK (complete/missing/relaxed/prose-mask/euphemism/bare-human/no-cp-carveout/no-after-go/no-never-unilateral/no-admin-honesty all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *) check_file "${1:-docs/governance/promotion-contract.md}"; exit $? ;;
esac
