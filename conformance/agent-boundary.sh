#!/bin/sh
# agent-boundary.sh — CI-side, harness-independent enforcement of the DEVELOPMENT-PROCESS.md §13
# agent boundary: a PR diff that touches a CONTROL-PLANE path must carry an explicit HUMAN
# ratification signal (a CODEOWNER (non-author) approval on those paths). This is the
# enforcement floor that holds on EVERY harness — incl. a harness with no inline guard — because CI
# catches an unratified control-plane edit post-hoc, before merge.
#
# Pure decision via boundary_decide(): the CI job computes the inputs (changed-file listing +
# ratified flag) from the PR event and passes them in, so this stays deterministic + --selftest-able.
# Reuses guard-core.sh::is_control_plane_path — the SINGLE SOURCE OF TRUTH for the control-plane set
# (no forked path list; this is another honored consumer of the core).
#
# THREE-STATE: 0 = boundary holds · 1 = violated (unratified control-plane change) · 2 = UNVERIFIED
#   (changed-file listing unavailable). 2 escalates to 1 under CI (CI env) or --require — a gate must
#   be runnable. See conformance/branch-protection.sh for the same contract.
#
#   usage: sh conformance/agent-boundary.sh --changed <listing-file> --ratified <0|1> [--require]
#          sh conformance/agent-boundary.sh --selftest
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
CHANGED=""
RATIFIED="0"
MODE="run"
RC=""
FOR_STATE="NONE"
FOR_CLASS="control-plane"
while [ $# -gt 0 ]; do
  case "$1" in
    --changed) CHANGED="${2:-}"; shift 2 ;;
    --ratified) RATIFIED="${2:-0}"; shift 2 ;;
    --require) REQUIRE=1; shift ;;
    --selftest) MODE="selftest"; shift ;;
    --state) MODE="state"; shift ;;
    # CP-9: the rc -> check-run mapping. `--state` is already a MODE flag (it takes no value), so the
    # mapping's inputs get their own names rather than an ambiguous optional-argument overload.
    --conclusion) MODE="conclusion"; RC="${2:-}"; shift 2 ;;
    --for-state) FOR_STATE="${2:-NONE}"; shift 2 ;;
    --for-class) FOR_CLASS="${2:-control-plane}"; shift 2 ;;
    *) echo "usage: agent-boundary.sh --changed <file> --ratified <0|1> [--require] | --selftest | --state | --conclusion <rc> [--for-state <label>] [--for-class <class>]" >&2; exit 2 ;;
  esac
done

# Resolve + source the deny-matrix core (the control-plane path set lives there).
CORE="${KIT_GUARD_CORE:-$(dirname "$0")/../.claude/hooks/guard-core.sh}"
# adapters/ registry — beyond the kit-standard guard-core set, the gate also protects each harness's
# OWN declared control-plane surface: the union of controlPlanePaths across adapters/*/adapter.json
# (P1 / N5 — turns the manifest's declarative inventory into real enforcement).
ADAPTERS_DIR="${KIT_ADAPTERS_DIR:-$(dirname "$0")/../adapters}"

# adapter_union: echo the union of controlPlanePaths across adapters/*/adapter.json (sorted-unique).
# jq-absent or no adapters/ -> empty union (the hardcoded guard-core floor still applies regardless).
adapter_union() {
  command -v jq >/dev/null 2>&1 || return 0
  [ -d "$ADAPTERS_DIR" ] || return 0
  for _m in "$ADAPTERS_DIR"/*/adapter.json; do
    [ -f "$_m" ] || continue
    jq -r '.controlPlanePaths[]? // empty' "$_m" 2>/dev/null
  done | sort -u
}

# path_in_union <path> <union-list>: 0 if <path> matches a union entry — exact, or a directory-prefix
# entry ending in '/'. Union entries never contain spaces, so word-splitting the list is safe.
path_in_union() {
  _pp=$1; _u=$2
  for _e in $_u; do
    [ "$_pp" = "$_e" ] && return 0
    case "$_e" in */) case "$_pp" in "$_e"*) return 0 ;; esac ;; esac
  done
  return 1
}

unverifiable() {  # <reason>
  if [ "$REQUIRE" = "1" ]; then
    echo "FAIL: agent-boundary could not verify ($1) and verification is required (CI/--require)."
    exit 1
  fi
  echo "UNVERIFIED: $1 — provide --changed <listing> in a PR context. (NOT a pass.)"
  exit 2
}

# boundary_decide <newline-separated-paths> <ratified 0|1>: print verdict; return 0 ok / 1 violation.
# Kept pure so the selftest can exercise it in-process (an env var must never force a pass).
boundary_decide() {
  _list=$1; _rat=$2; _union=${3:-}; _hits=""
  # Read the listing line-by-line in the CURRENT shell (heredoc, not a pipe) so _hits persists.
  # A path is control-plane if guard-core's hardcoded set knows it OR an adapter declared it (union).
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    if is_control_plane_path "$_p" || path_in_union "$_p" "$_union"; then _hits="$_hits $_p"; fi
  done <<EOF
$_list
EOF
  if [ -n "$_hits" ]; then
    if [ "$_rat" = "1" ]; then
      echo "OK: control-plane change present and ratified —$_hits"; return 0
    fi
    echo "FAIL: unratified control-plane change —$_hits"; return 1
  fi
  echo "OK: no control-plane paths in the diff"; return 0
}

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

# conclusion_map <rc> <state> <class>: the rc -> CHECK-RUN mapping, as parseable `key=value` lines
# (status, conclusion, title, summary — each single-line, so `IFS='=' read -r k v` reads them back).
#
# CP-9. Red must mean "something is BROKEN", never "something is WAITING" — a team that sees red for a
# gate working exactly as designed learns to ignore red. The three arms are therefore:
#   rc=0 -> completed/success      green  · nothing to ratify, or ratified
#   rc=1 -> in_progress/(none)     YELLOW · waiting on a human. A required check that is not `success`
#                                           still BLOCKS the merge, so enforcement is preserved with no
#                                           branch-protection change. Witnessed live, not assumed (#305).
#   rc=2 -> completed/failure      RED    · the gate could not evaluate the diff. Genuinely broken.
# The conclusion for rc=1 is EMPTY and must be OMITTED from the API call, not sent as "": a check-run
# carrying any conclusion is `completed`, which is precisely the red we are removing.
#
# PURE: no env, no filesystem, no network. This is the half that can be unit-tested; whether GitHub
# honours the status it is handed is a live question, and only a live probe can answer it.
conclusion_map() {
  _rc=$1; _cm_state=${2:-NONE}; _cm_class=${3:-control-plane}
  case "$_rc" in
    0)
      _status=completed; _concl=success
      if [ "$_cm_state" = RATIFIED-BY-SECOND-REVIEWER ]; then
        _title="Ratified by a second reviewer — control-plane change approved"
        _summary="What changed: a control-plane change (change-class: ${_cm_class}). State: RATIFIED-BY-SECOND-REVIEWER — a non-author reviewer approved this PR, so separation-of-duties is genuinely satisfied. No action needed. More: docs/operations/review-lane.md."
      else
        _title="No control-plane change — nothing to ratify"
        _summary="What changed: change-class ${_cm_class}; no control-plane paths in the diff. This §13 governance gate has nothing to ratify. No action needed."
      fi
      ;;
    1)
      _status=in_progress; _concl=""
      _title="Awaiting ratification — a human must approve before this control-plane change can merge"
      _summary="What changed: a control-plane change (the kit's own guardrails / CI / standards / governance). Change-class: control-plane. Why: control-plane changes must be ratified by a human before merge. This gate is WAITING, not failing — it is a §13 governance merge-gate, NOT a build failure, and no test failed. It will stay yellow (and keep blocking the merge) until a human acts. Current SoD state: SOLO-ADMIN-OVERRIDE-LOGGED — no non-author approval is present yet, so the only merge path is a logged solo admin-override (honestly weaker than a second reviewer). To proceed: (a) get a non-author approval on this PR — this check re-runs on the approval and turns green as RATIFIED-BY-SECOND-REVIEWER; or (b) solo — merge via 'gh pr merge --squash --admin --delete-branch'; GitHub logs the override as the audit trail. More: docs/operations/review-lane.md."
      ;;
    *)
      _status=completed; _concl=failure
      _title="Gate error — could not evaluate the control-plane diff"
      _summary="The control-plane-ratification gate could not evaluate the PR diff (change listing unavailable). This IS a real error — unlike the other states it needs fixing. See conformance/agent-boundary.sh."
      ;;
  esac
  printf 'status=%s\n' "$_status"
  printf 'conclusion=%s\n' "$_concl"
  printf 'title=%s\n' "$_title"
  printf 'summary=%s\n' "$_summary"
}

run() {
  [ -f "$CORE" ] || unverifiable "deny-matrix core not found at $CORE (set KIT_GUARD_CORE)"
  # shellcheck disable=SC1090  # core path is resolved at runtime, intentionally dynamic
  . "$CORE"
  [ -n "$CHANGED" ] || unverifiable "no --changed listing supplied"
  [ -f "$CHANGED" ] || unverifiable "--changed listing not found: $CHANGED"
  _paths=$(cat "$CHANGED")
  _union=$(adapter_union)
  if boundary_decide "$_paths" "$RATIFIED" "$_union"; then exit 0; else exit 1; fi
}

selftest() {
  st=0
  # source the core so is_control_plane_path is available to boundary_decide in-process
  [ -f "$CORE" ] || { echo "selftest FAIL: core not found at $CORE"; return 1; }
  # shellcheck disable=SC1090
  . "$CORE"
  dc() {  # expect_rc paths ratified label [union]
    e=$1; p=$2; r=$3; lbl=$4; u=${5:-}
    ( boundary_decide "$p" "$r" "$u" ) >/dev/null && g=0 || g=$?
    if [ "$g" = "$e" ]; then echo "selftest PASS: $lbl -> rc $g"; else echo "selftest FAIL: $lbl want $e got $g"; st=1; fi
  }
  dc 0 "src/app.ts
README.md" 0 "ordinary diff, unratified -> PASS"
  dc 1 "src/app.ts
.github/workflows/ci.yml" 0 "workflow change, unratified -> FAIL"
  dc 0 "src/app.ts
.github/workflows/ci.yml" 1 "workflow change, ratified -> PASS"
  dc 1 "CODEOWNERS" 0 "CODEOWNERS change, unratified -> FAIL"
  dc 0 "" 0 "empty diff -> PASS"
  dc 1 "conformance/agent-boundary.sh" 0 "conformance change, unratified -> FAIL"
  dc 0 "conformance/agent-boundary.sh" 1 "conformance change, ratified -> PASS"
  dc 1 "DEVELOPMENT-STANDARDS.md" 0 "standards doc change, unratified -> FAIL"
  dc 1 "CLAUDE.md" 0 "CLAUDE.md change, unratified -> FAIL"
  dc 1 "adapters/generic/adapter.json" 0 "adapter manifest change, unratified -> FAIL"
  dc 0 "scripts/deploy.sh" 0 "adopter own script (not kit) -> PASS"

  # N5 union: a path declared ONLY in an adapter manifest's controlPlanePaths (NOT in guard-core's
  # hardcoded set) is now caught — proving the gate enforces what adapters declare, per harness.
  dc 1 ".cursor/rules" 0 "adapter-union path, unratified -> FAIL" ".cursor/rules .github/workflows/"
  dc 0 ".cursor/rules" 1 "adapter-union path, ratified -> PASS" ".cursor/rules .github/workflows/"
  dc 0 "src/app.ts" 0 "non-union ordinary path -> PASS" ".cursor/rules"
  dc 1 ".cursor/rules/foo.md" 0 "dir-prefix union entry -> FAIL" ".cursor/rules/"

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

  # CP-9: the rc -> check-run (status, conclusion) mapping. Lives HERE, not in inline CI YAML, because
  # inline YAML cannot be unit-tested — and this mapping is the whole slice: a WAITING gate must not
  # render as a BROKEN one. Driven in-process (pure), so no env can force a verdict.
  cn() {  # <label> <key> <want> <rc> [state] [class]
    _lbl=$1; _k=$2; _want=$3; _rc=$4; _st=${5:-NONE}; _cl=${6:-control-plane}
    # `|| true`: grep returns 1 on no-match, and an unmatched key must read as an EMPTY value (a real
    # FAIL below), not abort the whole selftest under set -e.
    _line=$(conclusion_map "$_rc" "$_st" "$_cl" | grep "^${_k}=" || true)
    _got=${_line#*=}
    if [ "$_got" = "$_want" ]; then echo "selftest PASS: $_lbl ($_k='$_got')"
    else echo "selftest FAIL: $_lbl want $_k='$_want' got '$_got'"; st=1; fi
  }
  cn "rc=0 ratified -> completed"      status     completed   0 RATIFIED-BY-SECOND-REVIEWER
  cn "rc=0 ratified -> success"        conclusion success     0 RATIFIED-BY-SECOND-REVIEWER
  cn "rc=0 no-cp -> success"           conclusion success     0 NONE ordinary
  # ★ THE LOAD-BEARING PAIR: waiting is YELLOW (in_progress) and carries NO conclusion. An empty
  # conclusion is not cosmetic — a check-run with a conclusion is COMPLETED, and a completed non-success
  # check is what renders red. Omitting it is what keeps the gate blocking-but-not-broken.
  cn "rc=1 waiting -> in_progress"     status     in_progress 1 SOLO-ADMIN-OVERRIDE-LOGGED
  # Asserted as an EXACT LINE, not as an empty value: `want ''` would also be satisfied by a mapping
  # that emits no conclusion key at all (it passed against an unimplemented conclusion_map — vacuous).
  # The contract is "the key is present and deliberately empty", so the test must say exactly that.
  if conclusion_map 1 SOLO-ADMIN-OVERRIDE-LOGGED control-plane | grep -qx 'conclusion='; then
    echo "selftest PASS: rc=1 waiting -> conclusion= (present, empty)"
  else echo "selftest FAIL: rc=1 must emit an empty 'conclusion=' line"; st=1; fi
  cn "rc=2 gate error -> completed"    status     completed   2 NONE
  cn "rc=2 gate error -> failure"      conclusion failure     2 NONE
  # red is RESERVED for a genuine error: only rc=2 may ever produce a failing conclusion.
  for _r in 0 1; do
    if conclusion_map "$_r" SOLO-ADMIN-OVERRIDE-LOGGED control-plane | grep -q '^conclusion=failure$'; then
      echo "selftest FAIL: rc=$_r produced conclusion=failure (red is reserved for rc=2)"; st=1
    fi
  done
  # legibility: the waiting title says WAITING, and still tells the human how to proceed.
  _w=$(conclusion_map 1 SOLO-ADMIN-OVERRIDE-LOGGED control-plane)
  # 'To proceed:' is anchored deliberately: without it the summary can keep every other token and
  # still stop TELLING THE HUMAN WHAT TO DO. A mutation that gutted the instruction framing survived
  # the other four anchors — legibility is the point of the yellow state, so it gets its own anchor.
  for _a in 'Awaiting ratification' 'NOT a build failure' 'To proceed:' 'gh pr merge' 'review-lane.md'; do
    case "$_w" in *"$_a"*) echo "selftest PASS: waiting text carries '$_a'" ;;
      *) echo "selftest FAIL: waiting text missing '$_a'"; st=1 ;; esac
  done
  # non-vacuity: the three arms must not collapse into one another.
  if [ "$(conclusion_map 1 X control-plane | grep '^status=')" = "$(conclusion_map 2 X control-plane | grep '^status=')" ]; then
    echo "selftest FAIL: rc=1 and rc=2 statuses identical (mapping vacuous)"; st=1; fi
  # the CLI surface, not just the function (the CI job calls the CLI).
  _cli=$(sh "$0" --conclusion 1 --for-state SOLO-ADMIN-OVERRIDE-LOGGED --for-class control-plane)
  case "$_cli" in *"status=in_progress"*) echo "selftest PASS: --conclusion CLI -> in_progress" ;;
    *) echo "selftest FAIL: --conclusion CLI did not emit status=in_progress"; st=1 ;; esac
  if printf '%s\n' "$_cli" | grep -q '^conclusion=.'; then
    echo "selftest FAIL: --conclusion CLI emitted a non-empty conclusion for rc=1"; st=1
  else echo "selftest PASS: --conclusion CLI rc=1 conclusion is empty"; fi
  # the class the caller passes is what the human reads back.
  case "$(conclusion_map 0 NONE sensitive)" in *'change-class sensitive'*) echo "selftest PASS: class interpolated" ;;
    *) echo "selftest FAIL: class not interpolated into the summary"; st=1 ;; esac

  # three-state CLI: no --changed is UNVERIFIED (exit 2) locally, FAIL (exit 1) under CI/--require.
  miss=$(mktemp -d)  # fixtures left in place (no rm; 7e guard)
  printf '.github/workflows/ci.yml\n' > "$miss/cp.txt"
  printf 'src/app.ts\n' > "$miss/clean.txt"
  # shellcheck disable=SC1007  # CI= intentionally clears the var for the subprocess
  CI= REQUIRE=0 sh "$0" --ratified 0 >/dev/null && r=0 || r=$?
  if [ "$r" = "2" ]; then echo "selftest PASS: no --changed local -> exit 2 (UNVERIFIED)"; else echo "selftest FAIL: no --changed local want 2 got $r"; st=1; fi
  CI=true sh "$0" --ratified 0 >/dev/null && r=0 || r=$?
  if [ "$r" = "1" ]; then echo "selftest PASS: no --changed + CI -> exit 1 (escalation)"; else echo "selftest FAIL: no --changed + CI want 1 got $r"; st=1; fi
  # end-to-end CLI over a real listing file
  sh "$0" --changed "$miss/cp.txt" --ratified 0 >/dev/null && r=0 || r=$?
  if [ "$r" = "1" ]; then echo "selftest PASS: cli unratified control-plane -> exit 1"; else echo "selftest FAIL: cli cp unratified want 1 got $r"; st=1; fi
  sh "$0" --changed "$miss/cp.txt" --ratified 1 >/dev/null && r=0 || r=$?
  if [ "$r" = "0" ]; then echo "selftest PASS: cli ratified control-plane -> exit 0"; else echo "selftest FAIL: cli cp ratified want 0 got $r"; st=1; fi
  sh "$0" --changed "$miss/clean.txt" --ratified 0 >/dev/null && r=0 || r=$?
  if [ "$r" = "0" ]; then echo "selftest PASS: cli clean diff -> exit 0"; else echo "selftest FAIL: cli clean want 0 got $r"; st=1; fi

  # N5 integration: drive the FULL run() path (real adapter_union from this repo's adapters/) over a
  # path that ONLY the union protects (AGENTS.md, declared by the generic adapter, not in guard-core).
  printf 'AGENTS.md\n' > "$miss/agents.txt"
  if command -v jq >/dev/null 2>&1 && [ -d "$ADAPTERS_DIR" ]; then
    sh "$0" --changed "$miss/agents.txt" --ratified 0 >/dev/null && r=0 || r=$?
    if [ "$r" = "1" ]; then echo "selftest PASS: cli AGENTS.md via real adapter union, unratified -> exit 1"; else echo "selftest FAIL: cli AGENTS.md union want 1 got $r"; st=1; fi
    sh "$0" --changed "$miss/agents.txt" --ratified 1 >/dev/null && r=0 || r=$?
    if [ "$r" = "0" ]; then echo "selftest PASS: cli AGENTS.md via real adapter union, ratified -> exit 0"; else echo "selftest FAIL: cli AGENTS.md union ratified want 0 got $r"; st=1; fi
  else
    echo "selftest SKIP: real adapter-union integration (jq or adapters/ absent)"
  fi

  [ "$st" = "0" ] && echo "agent-boundary --selftest: OK"
  return "$st"
}

state() {  # advisory label for the CI human-surface; CI-independent, always exit 0
  [ -f "$CORE" ] || { echo NONE; exit 0; }
  # shellcheck disable=SC1090
  . "$CORE"
  { [ -n "$CHANGED" ] && [ -f "$CHANGED" ]; } || { echo NONE; exit 0; }
  ratification_state "$(cat "$CHANGED")" "$RATIFIED" "$(adapter_union)"
  exit 0
}

conclusion() {  # emit the check-run mapping for <rc>; no core, no filesystem — pure. Always exit 0.
  case "$RC" in
    0|1|2) ;;
    *) echo "usage: agent-boundary.sh --conclusion <0|1|2> [--for-state <label>] [--for-class <class>]" >&2; exit 2 ;;
  esac
  conclusion_map "$RC" "$FOR_STATE" "$FOR_CLASS"
  exit 0
}

case "$MODE" in
  selftest) selftest; exit $? ;;
  state) state ;;
  conclusion) conclusion ;;
  *) run ;;
esac
