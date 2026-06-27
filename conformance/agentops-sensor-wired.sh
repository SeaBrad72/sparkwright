#!/bin/sh
# agentops-sensor-wired.sh — behaviour-lock for the E5-thin operate-loop sensor + its golden-path proof.
# Asserts the emit -> adapt -> score -> export vertical is wired end-to-end so it cannot silently rot:
# the four reference scripts pass their own selftests AND are executable, AND the golden-path job that
# proves the loop on REAL emitted data is present + runs the right scripts. This locks the WIRING; the
# BEHAVIOUR (a denied span really moves denial_rate>0) is proven by the golden-path agentops-sensor job
# RUNNING the loop. Distinct from agentops-ready (posture/declaration) — this is behaviour.
# SCOPE: kit-self lock (the golden-path job is the kit's OWN pipeline; carved from the adopter export).
# Usage: sh conformance/agentops-sensor-wired.sh [--selftest]
set -eu

WF="${AGENTOPS_WF:-.github/workflows/golden-path.yml}"
SCRIPTS="scripts/otel-trace.sh scripts/orchestrator-run.sh scripts/otel-to-scorecard.sh scripts/otlp-export.sh"

check_wf() {  # <golden-path.yml> — a job named agentops-sensor runs the emit->adapt->score scripts
  f=$1; miss=0
  # Strip line comments before token-matching so a token that appears only in a comment (or a
  # commented-out step) cannot satisfy the lock — the wiring must be LIVE (the R1 lesson; mirrors
  # feature-flags-wired's comment-strip).
  wf_code=$(sed 's/#.*//' "$f" 2>/dev/null || true)
  printf '%s\n' "$wf_code" | grep -qE '^[[:space:]]*agentops-sensor:[[:space:]]*$' || { echo "FAIL: $f has no agentops-sensor job"; miss=1; }
  for tok in orchestrator-run.sh otel-to-scorecard.sh agent-scorecard.sh; do
    printf '%s\n' "$wf_code" | grep -qF -- "$tok" || { echo "FAIL: $f agentops-sensor proof does not run $tok"; miss=1; }
  done
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  sf=0; d=$(mktemp -d)
  # OK fixture: a live agentops-sensor job that runs all three loop scripts.
  printf 'jobs:\n  agentops-sensor:\n    steps:\n      - run: |\n          sh scripts/orchestrator-run.sh\n          sh scripts/otel-to-scorecard.sh "$t"\n          sh scripts/agent-scorecard.sh --traces d\n' > "$d/wf_ok.yml"
  if check_wf "$d/wf_ok.yml" >/dev/null 2>&1; then echo "selftest PASS: wired golden-path job -> PASS"; else echo "selftest FAIL: wf_ok wrongly failed"; sf=1; fi
  # BAD fixture 1: job present but missing agent-scorecard.sh (loop not closed) -> must FAIL.
  printf 'jobs:\n  agentops-sensor:\n    steps:\n      - run: |\n          sh scripts/orchestrator-run.sh\n          sh scripts/otel-to-scorecard.sh "$t"\n' > "$d/wf_partial.yml"
  if check_wf "$d/wf_partial.yml" >/dev/null 2>&1; then echo "selftest FAIL: missing agent-scorecard NOT caught"; sf=1; else echo "selftest PASS: missing scorecard step -> FAIL"; fi
  # BAD fixture 2: no agentops-sensor job at all -> must FAIL.
  printf 'jobs:\n  other:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$d/wf_nojob.yml"
  if check_wf "$d/wf_nojob.yml" >/dev/null 2>&1; then echo "selftest FAIL: absent job NOT caught"; sf=1; else echo "selftest PASS: absent agentops-sensor job -> FAIL"; fi
  # BAD fixture 3: the loop scripts present ONLY in comments -> must FAIL (comment-strip de-vacuums).
  printf 'jobs:\n  agentops-sensor:\n    steps:\n      - run: |\n          # sh scripts/orchestrator-run.sh\n          # sh scripts/otel-to-scorecard.sh\n          # sh scripts/agent-scorecard.sh\n' > "$d/wf_commented.yml"
  if check_wf "$d/wf_commented.yml" >/dev/null 2>&1; then echo "selftest FAIL: commented-out loop NOT caught"; sf=1; else echo "selftest PASS: commented-out loop -> FAIL"; fi
  [ "$sf" -eq 0 ] && { echo "OK: agentops-sensor-wired selftest"; exit 0; } || { echo "FAIL: agentops-sensor-wired selftest"; exit 1; }
fi

case "${1:-}" in "") : ;; *) echo "usage: agentops-sensor-wired.sh [--selftest]" >&2; exit 2 ;; esac

# Kit-self (mirrors feature-flags-wired's detector): this verifies the kit's OWN operate-loop sensor +
# its golden-path proof. On an adopter tree both kit markers are export-ignored/stripped → nothing to
# verify → N/A. Fail-closed on the kit: ROADMAP-KIT.md remains even if golden-path is deleted, so the
# [ -f "$WF" ] check below still FAILs.
if [ ! -f "docs/ROADMAP-KIT.md" ] && [ ! -f "$WF" ]; then echo "agentops-sensor: N/A — kit-self check (golden-path is the kit's own pipeline; not applicable outside the kit repo)"; exit 0; fi

fail=0
# 1) the four reference scripts pass their own selftests (the sensor logic is non-rotted)
sh scripts/otel-trace.sh --selftest >/dev/null 2>&1            || { echo "FAIL: scripts/otel-trace.sh --selftest"; fail=1; }
sh scripts/orchestrator-run.sh --selftest >/dev/null 2>&1 || { echo "FAIL: scripts/orchestrator-run.sh --selftest"; fail=1; }
sh scripts/otel-to-scorecard.sh --selftest >/dev/null 2>&1     || { echo "FAIL: scripts/otel-to-scorecard.sh --selftest"; fail=1; }
sh scripts/otlp-export.sh --selftest >/dev/null 2>&1           || { echo "FAIL: scripts/otlp-export.sh --selftest"; fail=1; }
# 2) the four scripts exist and are executable
for s in $SCRIPTS; do
  [ -f "$s" ] || { echo "FAIL: missing $s"; fail=1; continue; }
  [ -x "$s" ] || { echo "FAIL: not executable: $s"; fail=1; }
done
# 3) the golden-path job that proves the loop on REAL emitted data is present + runs the loop scripts
[ -f "$WF" ] || { echo "FAIL: golden-path workflow not found: $WF"; fail=1; }
[ "$fail" = 0 ] && { check_wf "$WF" || fail=1; }
[ "$fail" = 0 ] && { echo "OK: operate-loop sensor wired (4 selftests + golden-path agentops-sensor proof)"; exit 0; }
echo "FAIL: agentops-sensor under-wired"; exit 1
