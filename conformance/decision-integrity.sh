#!/bin/sh
# decision-integrity.sh — config-driven anti-bias gate engine for recorded neutrality decisions.
# One engine, four axes (stack #1, deploy-target #2, harness #3, model #4); each *-decision-integrity.sh is a
# 2-line shim into this engine (exec … decision-integrity.sh <axis> "$@"); the model axis has no shim, it is
# a config row here (SWAS-303a) and reads the project's map to decide whether a decision exists. Enforces that a recorded
# decision cites a FIT rationale, not a bias-appeal ("proven/default/what we ran before").
# HONEST CEILING: proves a fit reason is present, non-empty, non-placeholder, and names >=1 fit
# dimension. It CANNOT prove the choice is correct/optimal — that stays the reviewer's / owner's
# Go/No-Go. This gate is a floor/lint, not a semantic judge: it can PASS on an incidental keyword
# co-mention AND can false-FAIL a genuine rationale that uses unlisted jargon — the reviewer/owner
# Go/No-Go is the real correctness control. Skip residual: a wholly-bracketed body that ALSO carries the
# template sentinel is treated as the unfilled example (N/A) — so bias text left inside the still-bracketed
# template block is skipped (visible to any reviewer; caught by the Go/No-Go). The gate does not police a
# half-edited placeholder. Neutrality pattern engine; see DEVELOPMENT-STANDARDS.md.
#   sh conformance/decision-integrity.sh <axis> [<path>]   # verdict for one axis (stack|deploy|harness)
#   sh conformance/decision-integrity.sh <axis> --selftest # one axis's fixtures
#   sh conformance/decision-integrity.sh --selftest [axis] # all axes (or one)
# Exit: 0 = pass or N/A · 1 = violation · 2 = usage. POSIX sh; dash-clean.
set -eu
SELF_ABS="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." 2>/dev/null || true
# MODEL_MAP is a --selftest seam only (the selftest sets it itself). From the environment, CI included, it would let
# a caller grade the model axis against a map of their choosing, so it is refused (S4/R8).
if [ -n "${MODEL_MAP:-}" ]; then
  echo "decision-integrity: MODEL_MAP is a --selftest seam and is not honoured from the environment" >&2; exit 2
fi

# axis_config <axis> — resolve the per-axis config into globals. Values copied verbatim from the
# pre-engine stack/deploy scripts so migrated verdicts + messages are byte-identical (F1).
axis_config() {
  NA_UNLESS_MAP_BOUND=false; PLACEHOLDER_FAILS=false   # axis-specific; reset so a prior axis in one run cannot leak
  case "$1" in
    stack)
      AXIS=stack
      SELF_LABEL="stack-decision-integrity"
      SCRIPTNAME="stack-decision-integrity.sh"
      FIXDIR="conformance/fixtures/stack-decision-integrity"
      DEFAULT_PATH="docs/architecture/ADR-000-stack.md"
      PATHLABEL="<adr-path>"
      HEADING_TEXT="Fit rationale"
      HEADING_MD="##"
      START_RE='^##[[:space:]]+Fit rationale'
      STOP_RE='^##[[:space:]]'
      SENTINEL='why this stack fits'
      ABSENT_NOUN='no stack decision recorded yet'
      FAIL_HINT="reads as bias-appeal; cite workload/ecosystem/team/deploy/data/compliance — 'proven default' is not a fit reason"
      FIT_DIMENSIONS='concurren|cpu-bound|cpu bound|throughput|latency|real-time|real time|memory|ecosystem|librar|team|skill|deploy|serverless|cold.start|data|ml|machine learning|numeric|compliance|regulat|scale|scalab|workload|performance|interop|platform|iteration|full-stack|full stack|pipeline|infrastructure|provision|wasm|embedded|android|windows|azure|gpu|binary|startup|goroutine|green.thread|garbage.collect|garbage'
      HEADING_ABSENT_NA=false
      ;;
    deploy)
      AXIS=deploy
      SELF_LABEL="deploy-decision-integrity"
      SCRIPTNAME="deploy-decision-integrity.sh"
      FIXDIR="conformance/fixtures/deploy-decision-integrity"
      DEFAULT_PATH="RUNBOOK.md"
      PATHLABEL="<runbook-path>"
      HEADING_TEXT="Deploy-target fit rationale"
      HEADING_MD="####"
      START_RE='^####[[:space:]]+Deploy-target fit rationale'
      STOP_RE='^#{2,}[[:space:]]'
      SENTINEL='why this platform fits'
      ABSENT_NOUN='no deploy-target decision recorded yet'
      FAIL_HINT="reads as exercised-appeal; cite statefulness/traffic/latency/ops/compliance/cost — 'proven default' is not a fit reason"
      FIT_DIMENSIONS='stateful|stateless|traffic|spiky|bursty|scale-to-zero|scale to zero|latency|edge|region|residency|compliance|regulat|operational|ops burden|managed|self-host|self-manage|cost|budget|spend|throughput|concurren|cold.start|footprint|team|skill|familiar|uptime|availability|container|orchestrat|serverless|faas|paas|static|geographic|workload'
      HEADING_ABSENT_NA=false
      ;;
    harness)
      AXIS=harness
      SELF_LABEL="harness-decision-integrity"
      SCRIPTNAME="harness-decision-integrity.sh"
      FIXDIR="conformance/fixtures/harness-decision-integrity"
      DEFAULT_PATH="CLAUDE.md"
      PATHLABEL="<claude-md-path>"
      HEADING_TEXT="Harness fit rationale"
      HEADING_MD="####"
      START_RE='^####[[:space:]]+Harness fit rationale'
      STOP_RE='^#{2,}[[:space:]]'
      SENTINEL='why this harness fits'
      ABSENT_NOUN='no harness decision recorded yet'
      FAIL_HINT="reads as bias-appeal; cite fit — IDE/CI/MCP/multi-agent/native-hooks/offline/model-family/team-tooling — 'the default everyone uses' is not a fit reason"
      FIT_DIMENSIONS='ide-native|editor|ci-native|pipeline|mcp|multi-agent|multi agent|subagent|native.hook|pre-exec|pretooluse|interception|offline|air-gap|air gap|self-host|self host|team-tool|team tool|existing tooling|model.family|model provider|cost|budget|availability|enterprise|review-role|branch protection|orchestrat|headless|sandbox'
      HEADING_ABSENT_NA=true
      ;;
    model)
      # SWAS-303a — axis #4 (A3). The rationale lives in the project CLAUDE.md like the harness axis, but whether a
      # model decision EXISTS is read from the project's map: all-`unset` is the honest single-model case (N/A), and a
      # bound map owes a rationale, so a missing heading and an unfilled placeholder are FAILs here, not N/A.
      AXIS=model
      SELF_LABEL="model-decision-integrity"
      SCRIPTNAME="decision-integrity.sh model"
      FIXDIR="conformance/fixtures/model-decision-integrity"
      # An adopter records the rationale in their project CLAUDE.md. The kit's own tree (the docs/ROADMAP-KIT.md marker,
      # export-ignored) records ITS rationale in RUNBOOK.md (export-ignored too), so the kit's CLAUDE.md, which an
      # adopter receives, carries no project-specific section.
      if [ -f docs/ROADMAP-KIT.md ]; then DEFAULT_PATH="RUNBOOK.md"; else DEFAULT_PATH="CLAUDE.md"; fi
      PATHLABEL="<claude-md-path>"
      HEADING_TEXT="Model fit rationale"
      HEADING_MD="####"
      START_RE='^####[[:space:]]+Model fit rationale'
      STOP_RE='^#{2,}[[:space:]]'
      SENTINEL='why these models fit'
      ABSENT_NOUN='a model is bound in .kit/model-map.conf'
      FAIL_HINT="reads as bias-appeal; cite fit - reasoning/long context/tool use/code generation/review depth/cost/latency/availability/a measured A/B - 'the newest model' or 'what everyone uses' is not a fit reason"
      FIT_DIMENSIONS='reasoning|long context|context window|tool use|code generation|review depth|finding rate|latency|throughput|cost|budget|price|a/b|measured|scorecard|evals|availability|residency|self-host|provider|rate limit|first-ci'
      HEADING_ABSENT_NA=false
      NA_UNLESS_MAP_BOUND=true
      PLACEHOLDER_FAILS=true
      ;;
    *) echo "decision-integrity: unknown axis '$1'" >&2; exit 2 ;;
  esac
}

fit_body() { awk -v start="$START_RE" -v stop="$STOP_RE" '$0 ~ start {s=1;next} s && $0 ~ stop {exit} s {print}' "$1"; }

map_is_bound() {  # the model axis: is any tier key of the project's map set to a real value? (303a keys; 303b: profile.*)
  _mm=${MODEL_MAP:-.kit/model-map.conf}
  [ -f "$_mm" ] || return 1
  grep -E '^(apex|deep|fast|light)=' "$_mm" | sed 's/^[^=]*=//; s/[[:space:]#].*//' | grep -q -v -e '^unset$' -e '^$'
}

# S3: the first map line that is neither a comment, blank, nor canonical key=value. " deep=opus" and "deep =opus"
# are malformed and must never be read as an unbound map.
map_malformed() {
  grep -n -v -E '^([[:space:]]*#.*|[[:space:]]*|[a-z][a-z0-9.-]*=[^[:space:]]*([[:space:]]+#.*)?)$' "${MODEL_MAP:-.kit/model-map.conf}" 2>/dev/null | head -1
}

# The one-release epoch (owner Q3 a, MINOR: nothing reds on upgrade). On the model axis, a map with no decision= line
# (an adopter's pre-303a map) that is bound or malformed turns a FAIL into a WARN, rc 0. A decided map FAILs.
check() {
  if [ "$NA_UNLESS_MAP_BOUND" = true ] && [ -f "${MODEL_MAP:-.kit/model-map.conf}" ] &&
     ! grep -q -E '^decision=D-' "${MODEL_MAP:-.kit/model-map.conf}" && { map_is_bound || [ -n "$(map_malformed)" ]; }; then
    _co=$(_check_core "$1") && _cr=0 || _cr=$?
    if [ "$_cr" = 1 ]; then
      printf '%s\n' "$_co" | sed 's/^FAIL:/WARN:/'
      echo "WARN: the model map has no decision= line (an existing adopter map). This warns for one release and then fails: record the mapping in docs/governance/DECISIONS.md and add decision=, recorded= and revisit-by= to the map."
      return 0
    fi
    printf '%s\n' "$_co"; return "$_cr"
  fi
  _check_core "$1"
}

_check_core() {
  f=$1; rc=0
  if [ "$NA_UNLESS_MAP_BOUND" = true ]; then
    _ml=$(map_malformed)
    if [ -n "$_ml" ]; then echo "FAIL: $f - the model map has a malformed line ($_ml); write keys as key=value at the start of the line"; return 1; fi
    map_is_bound || { echo "N/A: $f - every value in the model map is unset (single-model; no model decision to record)"; return 0; }
    [ -f "$f" ] || { echo "FAIL: $f absent, but a model is bound in the map ($ABSENT_NOUN)"; return 1; }
  fi
  [ -f "$f" ] || { echo "N/A: $f absent ($ABSENT_NOUN)"; return 0; }
  if ! grep -qE "$START_RE" "$f"; then
    # Some axes record their decision in a SHARED file (harness → CLAUDE.md) that always exists but
    # may not carry the section yet (kit principles doc, adopter export, pre-Inception). For those,
    # a missing heading = "not yet decided" = N/A — mirroring how stack/deploy N/A on an ABSENT
    # dedicated artifact. Enforcement kicks in once Inception stamps the heading (then bracket→N/A
    # until filled, then the fit-dimension test). Axes with a dedicated artifact keep FAIL.
    if [ "${HEADING_ABSENT_NA:-false}" = true ]; then
      echo "N/A: $f — no '$HEADING_MD $HEADING_TEXT' recorded ($ABSENT_NOUN)"; return 0
    fi
    echo "FAIL: $f — missing required '$HEADING_MD $HEADING_TEXT' section"; rc=1; return $rc
  fi
  body=$(fit_body "$f"); stripped=$(printf '%s' "$body" | tr -d '[:space:]')
  if [ -z "$stripped" ]; then
    echo "FAIL: $f — '$HEADING_MD $HEADING_TEXT' present but empty"; rc=1; return $rc
  fi
  # Unfilled-example N/A: wholly-bracketed AND carries the shipped template sentinel. A real
  # rationale left in brackets still gets EVALUATED (not skipped); a bracketed non-sentinel body
  # falls through to the fit-dimension test below.
  case "$stripped" in
    '['*']')
      if printf '%s' "$body" | grep -qi "$SENTINEL"; then
        if [ "$PLACEHOLDER_FAILS" = true ]; then
          echo "FAIL: $f — $HEADING_TEXT is still the unfilled example, but a decision is recorded in the map ($ABSENT_NOUN)"; return 1
        fi
        echo "N/A: $f — $HEADING_TEXT is the unfilled example (bracket placeholder)"; return 0
      fi ;;
  esac
  if printf '%s' "$body" | grep -qiE "(^|[^a-zA-Z])($FIT_DIMENSIONS)"; then
    echo "PASS: $f — $HEADING_TEXT cites a fit dimension"; return 0
  fi
  echo "FAIL: $f — $HEADING_TEXT cites no recognized fit dimension ($FAIL_HINT)"; rc=1; return $rc
}

# ---- the oracle region (everything from selftest() on is graded verbatim by conformance/non-vacuity.sh) ----
# selftest() sits ABOVE the helpers that record a verdict (_expect/_expect_warn set st to one) on purpose: non-vacuity.sh
# neuters every accumulator set to one BEFORE the first selftest() marker, so a helper above it had its own flag flipped and a check
# that could no longer FAIL still passed its own selftest (SWAS-303a pre-push fix; SURVIVED, accumulator-flip).
selftest() {  # runs the configured axis's fixtures; prints its block; returns rc (does not exit)
  st=0
  axis_selftest_cases
  if [ "$st" = 0 ]; then echo "OK: $SELF_LABEL selftest"; return 0; else echo "FAIL: $SELF_LABEL selftest"; return 1; fi
}

_expect() {  # <fixture> <expected-rc> <label>  — uses $FIXDIR / check(); sets $st on mismatch
  if check "$FIXDIR/$1" >/dev/null 2>&1; then _rc=0; else _rc=$?; fi
  if [ "$_rc" = "$2" ]; then echo "PASS: selftest — $3 (rc $_rc)"; else echo "FAIL: selftest — $3 expected $2 got $_rc"; st=1; fi
}

_expect_warn() {  # <fixture> <label> — rc 0 AND a WARN line (the one-release epoch), never a silent PASS or a FAIL
  _wo=$(check "$FIXDIR/$1" 2>&1) && _rc=0 || _rc=$?
  case $_wo in *WARN:*) _w=1 ;; *) _w=0 ;; esac
  if [ "$_rc" = 0 ] && [ "$_w" = 1 ]; then echo "PASS: selftest — $2 (rc 0, WARN)"; else echo "FAIL: selftest — $2 expected rc 0 + WARN, got rc $_rc: $_wo"; st=1; fi
}

axis_selftest_cases() {  # the per-axis fixture expectations (copied verbatim from the pre-engine scripts)
  case "$AXIS" in
    stack)
      _expect good-adr.md 0 "good ADR passes"
      _expect missing-rationale-adr.md 1 "missing rationale FAILs (load-bearing +ve)"
      _expect bias-only-adr.md 1 "bias-only FAILs (load-bearing -ve)"
      _expect placeholder-adr.md 0 "unfilled placeholder is N/A"
      _expect bracket-bias-adr.md 1 "bracketed bias without sentinel FAILs (M1 close)"
      _expect substring-bias-adr.md 1 "substring-only bias FAILs (ml-in-html false-PASS closed)"
      ;;
    deploy)
      _expect good.md 0 "good RUNBOOK passes"
      _expect missing-rationale.md 1 "missing rationale FAILs (load-bearing +ve)"
      _expect exercised-bias.md 1 "exercised-bias FAILs (load-bearing -ve)"
      _expect placeholder.md 0 "unfilled placeholder is N/A"
      _expect bracket-bias.md 1 "bracketed bias without sentinel FAILs (M1 close)"
      _expect acknowledge-bias.md 1 "exercised-appeal with 'acknowledge' FAILs (edge left-anchored via generic wrap, no false-PASS)"
      ;;
    harness)
      _expect good.md 0 "good CLAUDE.md passes"
      _expect missing.md 0 "missing heading is N/A (shared file, no harness decision recorded yet)"
      _expect bias-only.md 1 "bias-only FAILs (load-bearing -ve)"
      _expect placeholder.md 0 "unfilled placeholder is N/A"
      ;;
    model)
      # SWAS-303a: the fourth axis. The project's map decides whether a model decision exists at all: all-unset
      # is the honest single-model case (N/A), and a bound map owes a fit rationale (missing/bias-only/placeholder = FAIL).
      MODEL_MAP="$FIXDIR/map-bound.conf"; export MODEL_MAP
      _expect good.md 0 "good CLAUDE.md passes under a bound map"
      _expect missing.md 1 "missing rationale FAILs under a bound map (load-bearing +ve)"
      _expect bias-only.md 1 "bias-only FAILs under a bound map (load-bearing -ve)"
      _expect placeholder.md 1 "an unfilled placeholder FAILs under a bound map (decided, not recorded)"
      MODEL_MAP="$FIXDIR/map-unset.conf"; export MODEL_MAP
      _expect missing.md 0 "missing rationale is N/A under an all-unset map"
      _expect bias-only.md 0 "bias-only is N/A under an all-unset map (nothing decided)"
      _expect placeholder.md 0 "placeholder is N/A under an all-unset map"
      MODEL_MAP="$FIXDIR/map-absent.conf"; export MODEL_MAP
      _expect missing.md 0 "no map at all is N/A"
      # Owner Q3 a (MINOR): a bound map with NO decision= line (an adopter's pre-303a map) WARNs for one release, rc 0.
      MODEL_MAP="$FIXDIR/map-nodecision.conf"; export MODEL_MAP
      _expect_warn missing.md "a hand-edited bound map with no decision= line WARNs on a missing rationale, rc 0"
      _expect_warn bias-only.md "...and on a bias-only rationale"
      _expect_warn placeholder.md "...and on an unfilled placeholder"
      _expect good.md 0 "...and a good rationale still passes"
      # decision=none records nothing: a template map that binds a model is still in the epoch
      MODEL_MAP="$FIXDIR/map-none-bound.conf"; export MODEL_MAP
      _expect_warn missing.md "a decision=none template map that binds a model WARNs on a missing rationale, rc 0"
      # S3: a line that is not a comment or canonical key=value is malformed, never read as an unbound map.
      MODEL_MAP="$FIXDIR/map-malformed.conf"; export MODEL_MAP
      _expect good.md 1 "a malformed map line (leading space) on a decided tree FAILs even with a good rationale"
      MODEL_MAP="$FIXDIR/map-malformed-nodecision.conf"; export MODEL_MAP
      _expect_warn good.md "a malformed map line in the one-release epoch WARNs, rc 0"
      # S4/R8: MODEL_MAP is a selftest seam only; supplied from outside (CI included) the engine refuses it.
      if ( MODEL_MAP="$FIXDIR/map-unset.conf" sh "$SELF_ABS" model ) >/dev/null 2>&1; then _er=0; else _er=$?; fi
      if [ "$_er" = 2 ]; then echo "PASS: selftest — MODEL_MAP supplied from outside is refused (rc 2)"; else echo "FAIL: selftest — MODEL_MAP supplied from outside must be refused with rc 2, got $_er"; st=1; fi
      # the kit's own rationale lives in an export-ignored file, and the kit tree reads it
      if [ -f docs/ROADMAP-KIT.md ]; then
        axis_config model
        MODEL_MAP="$FIXDIR/map-bound.conf"; export MODEL_MAP
        if [ "$DEFAULT_PATH" = RUNBOOK.md ] && check RUNBOOK.md >/dev/null 2>&1; then echo "PASS: selftest — the kit tree reads its own model-fit rationale from RUNBOOK.md"
        else echo "FAIL: selftest — the kit tree must read RUNBOOK.md (DEFAULT_PATH=$DEFAULT_PATH) and it must carry a fit rationale"; st=1; fi
      fi
      ;;
  esac
}

# ---- dispatch ----
case "${1:-}" in
  --selftest)
    # engine-direct: --selftest [axis]  — one axis, or all three
    if [ -n "${2:-}" ]; then
      axis_config "$2"; selftest; exit $?
    fi
    all_rc=0
    for _a in stack deploy harness model; do
      axis_config "$_a"; selftest || all_rc=1
    done
    exit $all_rc
    ;;
  stack|deploy|harness|model)
    axis_config "$1"; shift
    case "${1:-}" in
      --selftest) selftest; exit $? ;;
      "")
        # Real-path verdict. For shared-file axes (harness → CLAUDE.md) a missing heading N/As inside
        # check() via HEADING_ABSENT_NA — so the kit principles doc, the adopter export, and a
        # pre-Inception adopter all N/A uniformly (no reliance on export-ignored markers). Enforcement
        # begins once the heading is present.
        check "$DEFAULT_PATH"; exit $? ;;
      *) if [ -f "$1" ]; then check "$1"; exit $?; else echo "usage: $SCRIPTNAME [$PATHLABEL|--selftest]" >&2; exit 2; fi ;;
    esac
    ;;
  *) echo "usage: decision-integrity.sh <stack|deploy|harness|model> [<path>|--selftest] | --selftest [axis]" >&2; exit 2 ;;
esac
