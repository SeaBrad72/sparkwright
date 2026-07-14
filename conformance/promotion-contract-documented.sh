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
  # Slice 4 + S1 (KW1 D1): the delegable-execution rule is documented coherently — WITH its load-bearing
  # carve-outs (control-plane GO/judgment stays human; delegation is only AFTER a recorded GO; and if
  # control-plane ACTUATION is delegated it must name its SHA-bound/per-merge qualifier). A doc that
  # documents delegation but drops a carve-out is a fox/henhouse gap and MUST fail.
  require 'delegable-post-go'        'delegable after.*recorded.*GO'
  require 'never-unilateral'         'never unilateral'
  require 'cp-judgment-human'        'control-plane GO stays human'
  # Slice S1 (KW1 D1): if the doc documents control-plane actuation delegation, it MUST name the
  # qualifier — actuation is permitted ONLY on a SHA-bound, per-merge recorded GO. Blanket/inferred
  # control-plane actuation stays banned. (Part C keeps the matrix CELLS human-worded regardless.)
  require 'cp-actuation-qualified'   'SHA-bound.*(per-merge|recorded GO)|actuation is delegable only on a SHA-bound'
  require 'admin-merge-honesty'      'gh pr merge --admin'
  # Slice S2 (KW1 D2): the approve->execute->log actuation protocol for NON-control-plane promotions
  # + the builder != ratifier invariant + never-infer FLOOR + the gateable shipped==approved check.
  # Each marker is isolatable (a per-marker selftest negative below drops ONLY its line and FAILs).
  require 'builder-not-ratifier'     'builder[^a-zA-Z]+ratifier'
  require 'approve-execute-log'      'approve.{0,4}execute.{0,4}log'
  require 'never-infer'              'never[^a-zA-Z]+infer'
  require 'shipped-equals-approved'  'shipped *==? *approved'
  # Slice S4 (KW20): the honest actuation model's three anchors — autonomy as a SECOND modulator
  # (a dial, not a third axis), `lean` as the honest first-class baseline (enterprise = the superset),
  # and the general kill-switch posture (a circuit-breaker, explicitly NOT a validation/review). Each
  # is load-bearing: a per-marker selftest negative below drops ONLY its phrase and FAILs (S1 lesson —
  # no silently-deletable marker). These lock the model against drift; they add NO enforcement.
  require 'autonomy-modulator'         'modulated by.*autonomy|autonomy.*modulator|second modulator'
  require 'lean-first-class'           'lean.*first-class|lean.*honest baseline|enterprise.*superset'
  require 'kill-switch-not-validation' 'kill-switch[^.]*not (a )?(validation|review)'
  # Actuation-division correction (2026-07-07): lock the corrected WHO-ACTUATES division as a single
  # load-bearing marker — on a recorded GO the AGENT actuates the mechanical steps (apply/commit/push/
  # tag/record/check); the human's ONLY control-plane keystroke, solo, is the --admin merge. This locks
  # the correction so a future edit cannot silently restore "hand it to a human to apply." A per-marker
  # selftest negative below drops ONLY this sentence and FAILs (non-vacuity — owner ratified).
  require 'agent-actuates-mechanical'  'agent actuates the mechanical steps.*only control-plane keystroke, solo, is the'

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
    # DRIFT-1 hardening (dual review): the old pattern had NO ratify/approve verb and assumed the
    # relaxing actor is literally called "agent". Both holes were live on main and PROVEN:
    #   "control-plane-ratification rendered by the agent"                    -> passed GREEN
    #   "control-plane-ratification; the orchestrator may ratify unattended"  -> passed GREEN
    # i.e. a cell could say THE AGENT RATIFIES ITSELF and satisfy the lock whose entire job is to
    # grade who ratifies (the CP-9 pwn-request class). Now: any non-human actor (agent/orchestrator/
    # bot/model/llm) bound to any control verb — including ratif/approv/govern — is rejected, as is
    # "unattended" and "by the agent". Validated against all five real cells: zero false positives.
    if printf '%s' "$_cell" | grep -qiE 'no human gate|(agent|orchestrator|bot|model|llm)[ -]?(self|merge|commit|appl|tag|push|actuat|autonom|ratif|approv|govern)|by (the |an |a )?(agent|orchestrator|bot|model|llm)|unattended|self-govern|auto|delegat'; then
      echo "FAIL: Control-plane column relaxed at '$_lab' — cell is '$_cell' (control-plane must stay human-governed)"; fail=1; return 0
    fi
    # Positive: require an EXPLICIT human-actuation disposition. A bare 'human' mention cannot rescue
    # an agent-actuating cell (that gaming path was closed in dual review #27).
    # DRIFT-1: 'AMBER' (the retired hand-off ceremony) dropped from this alternation. NOTHING replaced
    # it — in particular NOT 'dev-clone'. A dev-clone is where the AGENT authors; it is an authoring
    # mechanism, not a human gate. This grep grades WHO RATIFIES, never where the bytes were written.
    # Adding 'dev-clone' here would let a cell satisfy "human-governed" with no human in it.
    if printf '%s' "$_cell" | grep -qiE 'human-authored|control-plane-ratification|human ratif|human-gated|human gate|meta-control|N/A'; then
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
Rigor is also modulated by {trust, autonomy}; autonomy is a second modulator, a dial not a third axis.
lean is genuinely first-class — the honest baseline; enterprise is the superset that adds scaffolding.
The deploy-failsafe is a kill-switch, not a validation — a human circuit-breaker, off by default.
Control-plane is path-derived (is_control_plane_path). Fail-safe: default to the higher class.
Relaxation = deferral, not a waiver. Rigor ratchets at every promotion.
At each promotion the agent emits a promotion-readiness surfacing.
The human renders a GO/NO-GO — a recorded judgment, not a keystroke.
Solo/team: RATIFIED-BY-SECOND-REVIEWER vs SOLO-ADMIN-OVERRIDE-LOGGED.
Execution is delegable after an explicit recorded human GO.
The delegation is never unilateral at a promotion.
Control-plane GO stays human at every rung; actuation is delegable only on a SHA-bound, per-merge recorded GO.
The gh pr merge --admin bypass is a human act.
On a recorded GO the agent actuates the mechanical steps (apply, commit, push, tag, record, check); the human's only control-plane keystroke, solo, is the --admin merge.
Invariant: builder ≠ ratifier — peer to builder ≠ reviewer.
Protocol: approve→execute→log — provide the means, wait, then execute and log after the GO.
The human approves per-gate; approval is never inferred from conversation.
After actuation the agent verifies shipped == approved at merge and at tag.

| Rung | Ordinary | Sensitive | Control-plane |
|---|---|---|---|
| **Spike** | Agent autonomous (L3) | Human-gated | Human-authored |
| **Integration** | Automated gates | Human GO | Dev-clone authoring + control-plane-ratification |
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
  sed 's/Dev-clone authoring + control-plane-ratification/Agent autonomous (L3)/' "$good" > "$relaxed"
  if check_file "$relaxed" >/dev/null 2>&1; then echo "selftest FAIL: relaxed control-plane column should FAIL (non-vacuity broken!)"; st=1; else echo "selftest PASS: relaxed control-plane -> FAIL"; fi

  # Anti-gaming: cell reverted to autonomous but a prose line elsewhere says control-plane stays human.
  mask="$base/prose-mask.md"
  {
    echo 'Note: the Control-plane column stays human-authored at every rung in our intent.'
    sed 's/| Dev-clone authoring + control-plane-ratification |/| Agent autonomous |/' "$good"
  } > "$mask"
  if check_file "$mask" >/dev/null 2>&1; then echo "selftest FAIL: prose-mask should not rescue a relaxed cell"; st=1; else echo "selftest PASS: prose-mask -> FAIL (final cell wins)"; fi

  # NEW (S1): control-plane actuation delegation documented WITHOUT its qualifier -> MUST FAIL.
  # A doc that says the agent may actuate the control-plane but omits the SHA-bound/per-merge
  # carve-out is documenting BLANKET delegation (the fox/henhouse hole). Non-vacuity for D1.
  blanket="$base/cp-blanket.md"
  sed 's/Control-plane GO stays human at every rung; actuation is delegable only on a SHA-bound, per-merge recorded GO./The agent may actuate the control-plane after a GO./' "$good" > "$blanket"
  if check_file "$blanket" >/dev/null 2>&1; then echo "selftest FAIL: blanket CP actuation should FAIL (non-vacuity broken!)"; st=1; else echo "selftest PASS: blanket CP actuation -> FAIL"; fi

  # Euphemism evasion (dual-review #27): a Control-plane cell that relaxes to agent actuation in
  # natural language — NOT the canonical "agent autonomous" — must STILL FAIL.
  euph="$base/euphemism.md"
  sed 's/Dev-clone authoring + control-plane-ratification/agent merges after GO; human notified/' "$good" > "$euph"
  if check_file "$euph" >/dev/null 2>&1; then echo "selftest FAIL: euphemistic relaxation should FAIL (teeth gap!)"; st=1; else echo "selftest PASS: euphemistic relaxation -> FAIL"; fi

  # And the bare-'human' rescue must not save an auto-merge cell.
  bare="$base/bare-human.md"
  sed 's/Dev-clone authoring + control-plane-ratification/auto-merge on green; human informed/' "$good" > "$bare"
  if check_file "$bare" >/dev/null 2>&1; then echo "selftest FAIL: auto-merge+human should FAIL"; st=1; else echo "selftest PASS: auto-merge+human -> FAIL (bare 'human' cannot rescue)"; fi

  # SELF-RATIFICATION (DRIFT-1 dual review): a cell that keeps the ratification marker but hands the
  # RATIFYING to the agent must FAIL. Both of these passed GREEN on main — the lock graded the words,
  # not the actor. This is the CP-9 pwn-request class: an agent ratifying its own control-plane change.
  selfratify="$base/self-ratify.md"
  sed 's/Dev-clone authoring + control-plane-ratification/Dev-clone authoring + control-plane-ratification rendered by the agent/' "$good" > "$selfratify"
  if check_file "$selfratify" >/dev/null 2>&1; then echo "selftest FAIL: agent-rendered ratification should FAIL (self-ratification hole open!)"; st=1; else echo "selftest PASS: agent-rendered ratification -> FAIL"; fi

  unattended="$base/unattended.md"
  sed 's/Dev-clone authoring + control-plane-ratification/Dev-clone authoring + control-plane-ratification; the orchestrator may ratify unattended/' "$good" > "$unattended"
  if check_file "$unattended" >/dev/null 2>&1; then echo "selftest FAIL: unattended orchestrator ratification should FAIL"; st=1; else echo "selftest PASS: unattended orchestrator ratification -> FAIL"; fi

  # Slice 4 load-bearing negatives: documenting delegation but DROPPING a carve-out must FAIL.
  nocp="$base/no-cp-carveout.md"
  grep -v 'Control-plane GO stays human' "$good" > "$nocp"
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

  # NEW (S2): each approve->execute->log marker is load-bearing — dropping ONLY its line MUST FAIL.
  nbr="$base/no-builder-ratifier.md"
  grep -v 'builder ≠ ratifier' "$good" > "$nbr"
  if check_file "$nbr" >/dev/null 2>&1; then echo "selftest FAIL: dropped builder-not-ratifier should FAIL"; st=1; else echo "selftest PASS: dropped builder-not-ratifier -> FAIL"; fi

  nael="$base/no-approve-execute-log.md"
  grep -v 'approve→execute→log' "$good" > "$nael"
  if check_file "$nael" >/dev/null 2>&1; then echo "selftest FAIL: dropped approve-execute-log should FAIL"; st=1; else echo "selftest PASS: dropped approve-execute-log -> FAIL"; fi

  nni="$base/no-never-infer.md"
  grep -v 'never inferred' "$good" > "$nni"
  if check_file "$nni" >/dev/null 2>&1; then echo "selftest FAIL: dropped never-infer should FAIL"; st=1; else echo "selftest PASS: dropped never-infer -> FAIL"; fi

  nsea="$base/no-shipped-approved.md"
  grep -v 'shipped == approved' "$good" > "$nsea"
  if check_file "$nsea" >/dev/null 2>&1; then echo "selftest FAIL: dropped shipped-equals-approved should FAIL"; st=1; else echo "selftest PASS: dropped shipped-equals-approved -> FAIL"; fi

  # NEW (S4): each honest-actuation-model marker is load-bearing — dropping ONLY its phrase MUST FAIL.
  nam="$base/no-autonomy-modulator.md"
  grep -v 'second modulator' "$good" > "$nam"
  if check_file "$nam" >/dev/null 2>&1; then echo "selftest FAIL: dropped autonomy-modulator should FAIL"; st=1; else echo "selftest PASS: dropped autonomy-modulator -> FAIL"; fi

  nlfc="$base/no-lean-first-class.md"
  grep -v 'first-class' "$good" > "$nlfc"
  if check_file "$nlfc" >/dev/null 2>&1; then echo "selftest FAIL: dropped lean-first-class should FAIL"; st=1; else echo "selftest PASS: dropped lean-first-class -> FAIL"; fi

  nksv="$base/no-kill-switch.md"
  grep -v 'not a validation' "$good" > "$nksv"
  if check_file "$nksv" >/dev/null 2>&1; then echo "selftest FAIL: dropped kill-switch-not-validation should FAIL"; st=1; else echo "selftest PASS: dropped kill-switch-not-validation -> FAIL"; fi

  # NEW (actuation-division correction): the corrected who-actuates division marker is load-bearing —
  # dropping ONLY that sentence must make the lock FAIL. This is the regression teeth: a future edit
  # that silently restores "hand it to a human to apply" (deleting the sentence) is caught here.
  nact="$base/no-agent-actuates.md"
  grep -v 'agent actuates the mechanical steps' "$good" > "$nact"
  if check_file "$nact" >/dev/null 2>&1; then echo "selftest FAIL: dropped agent-actuates-mechanical should FAIL (regression teeth broken!)"; st=1; else echo "selftest PASS: dropped agent-actuates-mechanical -> FAIL"; fi

  if [ "$st" -ne 0 ]; then echo "promotion-contract-documented --selftest: FAIL" >&2; return 1; fi
  echo "promotion-contract-documented --selftest: OK (complete/missing/relaxed/prose-mask/cp-blanket/euphemism/bare-human/no-cp-carveout/no-after-go/no-never-unilateral/no-admin-honesty/no-builder-ratifier/no-approve-execute-log/no-never-infer/no-shipped-approved/no-autonomy-modulator/no-lean-first-class/no-kill-switch/no-agent-actuates all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *) check_file "${1:-docs/governance/promotion-contract.md}"; exit $? ;;
esac
