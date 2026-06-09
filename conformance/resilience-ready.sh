#!/bin/sh
# resilience-ready.sh — conditional, fail-closed resilience-record check.
#
# Companion to conformance/resilience-readiness.md (the Resilience-readiness gate;
# DEVELOPMENT-PROCESS.md §7). For a project with a DEPLOY SURFACE it asserts the
# resilience drills are RECORDED: the RUNBOOK §8 has a "Load/soak tested:" date and a
# "Fault-injection drill:" date (not the template [date] placeholder). Projects with no
# deploy surface are N/A (skip-pass) — a library/CLI has no dependencies to circuit-break
# or load to soak.
#
# SCOPE — a green run proves the drills were RECORDED, NOT that the system is actually
# resilient (breaker tripped, degraded gracefully, survived soak). Those are Manual rows
# in resilience-readiness.md (on-call/operator evidence). A green run is necessary, not
# sufficient.
#
# Usage:
#   sh conformance/resilience-ready.sh [project-dir]   (default: .)
#   sh conformance/resilience-ready.sh --selftest
#
# Run at the Resilience-readiness gate (DEVELOPMENT-PROCESS.md §7); also self-tested in kit CI.
set -eu

# Does $1 (a workflow file) indicate a deploy surface? (Same structural signals as
# deployable-ready.sh: a GitHub `environment:` key or a deploy-ish job key.)
wf_is_deploy() {
  _wf="$1"
  if grep -Eq '^[[:space:]]*environment:' "$_wf"; then return 0; fi
  if grep -Eq '^[[:space:]]+deploy[A-Za-z0-9_-]*:[[:space:]]*$' "$_wf"; then return 0; fi
  return 1
}

check_dir() {
  dir="$1"
  fail=0

  deployable=0
  if [ -f "$dir/Dockerfile" ]; then deployable=1; fi
  if [ "$deployable" -eq 0 ] && [ -d "$dir/.github/workflows" ]; then
    for wf in "$dir"/.github/workflows/*.yml "$dir"/.github/workflows/*.yaml; do
      [ -f "$wf" ] || continue
      if wf_is_deploy "$wf"; then deployable=1; break; fi
    done
  fi

  if [ "$deployable" -eq 0 ]; then
    echo "N/A: $dir has no deploy surface (no Dockerfile / deploy workflow) — skipping (no dependencies to circuit-break or load to soak)"
    return 0
  fi

  rb="$dir/RUNBOOK.md"
  if [ ! -f "$rb" ]; then
    echo "FAIL: $dir is deployable but has no RUNBOOK.md (need §8 resilience records) — see conformance/resilience-readiness.md"
    return 1
  fi

  # Record strings below must stay in sync with templates/RUNBOOK-TEMPLATE.md §8.
  if ! grep -Eiq 'load/soak tested:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'Load/soak tested:' record — run a load/soak test and record the date (docs/operations/resilience-verification.md)"
    fail=1
  elif grep -Fiq 'load/soak tested: [date]' "$rb"; then
    echo "FAIL: 'Load/soak tested:' still holds the [date] placeholder — run the test and record the date"
    fail=1
  fi
  if ! grep -Eiq 'fault-injection drill:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'Fault-injection drill:' record — run a fault-injection drill and record the date"
    fail=1
  elif grep -Fiq 'fault-injection drill: [date]' "$rb"; then
    echo "FAIL: 'Fault-injection drill:' still holds the [date] placeholder — run the drill and record the date"
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "resilience-ready: OK — resilience drills are RECORDED. NOTE: this does NOT verify the system is actually resilient (breaker tripped, degraded gracefully, survived soak) — those are Manual rows in resilience-readiness.md requiring on-call/operator evidence."
  return 0
}

# Build mktemp fixtures and assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st_fail=0
  base=$(mktemp -d)

  d1="$base/na"; mkdir -p "$d1"
  if check_dir "$d1" >/dev/null 2>&1; then
    echo "selftest PASS: empty -> N/A"
  else
    echo "selftest FAIL: empty should be N/A"; st_fail=1
  fi

  d2="$base/stateless"; mkdir -p "$d2"; printf '# a stateless CLI tool\n' > "$d2/README.md"
  if check_dir "$d2" >/dev/null 2>&1; then
    echo "selftest PASS: no-deploy-surface -> N/A (not over-triggered)"
  else
    echo "selftest FAIL: no-deploy-surface should be N/A"; st_fail=1
  fi

  d3="$base/ok"; mkdir -p "$d3"
  printf 'FROM scratch\n' > "$d3/Dockerfile"
  printf '# RUNBOOK\n\n## Monitoring & alerting\n- Resilience verification: Load/soak tested: 2026-06-01 · Fault-injection drill: 2026-06-02\n' > "$d3/RUNBOOK.md"
  if check_dir "$d3" >/dev/null 2>&1; then
    echo "selftest PASS: complete deployable -> OK"
  else
    echo "selftest FAIL: complete deployable should pass"; st_fail=1
  fi

  d4="$base/placeholder"; mkdir -p "$d4"
  printf 'FROM scratch\n' > "$d4/Dockerfile"
  printf '# RUNBOOK\n\n## Monitoring & alerting\n- Load/soak tested: [date] · Fault-injection drill: 2026-06-02\n' > "$d4/RUNBOOK.md"
  if check_dir "$d4" >/dev/null 2>&1; then
    echo "selftest FAIL: [date] placeholder should FAIL"; st_fail=1
  else
    echo "selftest PASS: load/soak [date] placeholder -> FAIL as expected"
  fi

  d5="$base/missing"; mkdir -p "$d5"
  printf 'FROM scratch\n' > "$d5/Dockerfile"
  printf '# RUNBOOK\n\n## Monitoring & alerting\n- Load/soak tested: 2026-06-01\n' > "$d5/RUNBOOK.md"
  if check_dir "$d5" >/dev/null 2>&1; then
    echo "selftest FAIL: missing fault-injection record should FAIL"; st_fail=1
  else
    echo "selftest PASS: missing fault-injection record -> FAIL as expected"
  fi

  if [ "$st_fail" -ne 0 ]; then
    echo "resilience-ready --selftest: FAIL" >&2
    return 1
  fi
  echo "resilience-ready --selftest: OK (na/no-surface/ok/placeholder/missing all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
