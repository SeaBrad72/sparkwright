#!/bin/sh
# decision-integrity.sh — config-driven anti-bias gate engine for recorded neutrality decisions.
# One engine, three axes (stack #1, deploy-target #2, harness #3); each *-decision-integrity.sh is a
# 2-line shim into this engine (exec … decision-integrity.sh <axis> "$@"). Enforces that a recorded
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
cd "$(dirname "$0")/.." 2>/dev/null || true

# axis_config <axis> — resolve the per-axis config into globals. Values copied verbatim from the
# pre-engine stack/deploy scripts so migrated verdicts + messages are byte-identical (F1).
axis_config() {
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
    *) echo "decision-integrity: unknown axis '$1'" >&2; exit 2 ;;
  esac
}

fit_body() { awk -v start="$START_RE" -v stop="$STOP_RE" '$0 ~ start {s=1;next} s && $0 ~ stop {exit} s {print}' "$1"; }

check() {
  f=$1; rc=0
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
        echo "N/A: $f — $HEADING_TEXT is the unfilled example (bracket placeholder)"; return 0
      fi ;;
  esac
  if printf '%s' "$body" | grep -qiE "(^|[^a-zA-Z])($FIT_DIMENSIONS)"; then
    echo "PASS: $f — $HEADING_TEXT cites a fit dimension"; return 0
  fi
  echo "FAIL: $f — $HEADING_TEXT cites no recognized fit dimension ($FAIL_HINT)"; rc=1; return $rc
}

_expect() {  # <fixture> <expected-rc> <label>  — uses $FIXDIR / check(); sets $st on mismatch
  if check "$FIXDIR/$1" >/dev/null 2>&1; then _rc=0; else _rc=$?; fi
  if [ "$_rc" = "$2" ]; then echo "PASS: selftest — $3 (rc $_rc)"; else echo "FAIL: selftest — $3 expected $2 got $_rc"; st=1; fi
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
  esac
}

selftest() {  # runs the configured axis's fixtures; prints its block; returns rc (does not exit)
  st=0
  axis_selftest_cases
  if [ "$st" = 0 ]; then echo "OK: $SELF_LABEL selftest"; return 0; else echo "FAIL: $SELF_LABEL selftest"; return 1; fi
}

# ---- dispatch ----
case "${1:-}" in
  --selftest)
    # engine-direct: --selftest [axis]  — one axis, or all three
    if [ -n "${2:-}" ]; then
      axis_config "$2"; selftest; exit $?
    fi
    all_rc=0
    for _a in stack deploy harness; do
      axis_config "$_a"; selftest || all_rc=1
    done
    exit $all_rc
    ;;
  stack|deploy|harness)
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
  *) echo "usage: decision-integrity.sh <stack|deploy|harness> [<path>|--selftest] | --selftest [axis]" >&2; exit 2 ;;
esac
