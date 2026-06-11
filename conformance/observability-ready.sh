#!/bin/sh
# observability-ready.sh — conditional, fail-closed observability-record check (gate parity, Slice 2).
#
# Companion to conformance/observability-readiness.md (the Observability/SLO readiness;
# DEVELOPMENT-PROCESS.md §7). For a project with a DEPLOY SURFACE it asserts the observability
# posture is RECORDED: the RUNBOOK §8 has an "SLOs:" target and a "Telemetry wired:" signal set
# (not the template [target]/[signals] placeholders). Projects with no deploy surface are N/A
# (skip-pass) — a library/CLI has no running service to set SLOs on or emit telemetry from.
#
# SCOPE — a green run proves the posture was RECORDED, NOT that the system is actually observable:
# that the signals actually emit in prod, the alerts actually fire, or the SLO/error-budget is
# actually tracked. Those are Manual rows in observability-readiness.md (operator evidence). A
# green run is necessary, not sufficient.
#
# Usage:
#   sh conformance/observability-ready.sh [project-dir]   (default: .)
#   sh conformance/observability-ready.sh --selftest
#
# Run at the Observability readiness gate (DEVELOPMENT-PROCESS.md §7); also self-tested in kit CI.
set -eu

# Does $1 (a workflow file) indicate a deploy surface? (Same structural signals as
# resilience-ready.sh: a GitHub `environment:` key or a deploy-ish job key.)
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
    echo "N/A: $dir has no deploy surface (no Dockerfile / deploy workflow) — skipping (no running service to set SLOs on or emit telemetry from)"
    return 0
  fi

  rb="$dir/RUNBOOK.md"
  if [ ! -f "$rb" ]; then
    echo "FAIL: $dir is deployable but has no RUNBOOK.md (need §8 observability records) — see conformance/observability-readiness.md"
    return 1
  fi

  # Record strings below must stay in sync with templates/RUNBOOK-TEMPLATE.md §8.
  if ! grep -Eiq 'slos:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'SLOs:' record — declare the service-level objective (availability/latency/error budget)"
    fail=1
  elif grep -Fiq 'slos: [target]' "$rb"; then
    echo "FAIL: 'SLOs:' still holds the [target] placeholder — record a real SLO target"
    fail=1
  fi
  if ! grep -Eiq 'telemetry wired:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'Telemetry wired:' record — locate the metrics + traces + health signals (Factor 14)"
    fail=1
  elif grep -Fiq 'telemetry wired: [signals]' "$rb"; then
    echo "FAIL: 'Telemetry wired:' still holds the [signals] placeholder — record the real signal set"
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "observability-ready: OK — observability posture is RECORDED (SLOs declared, telemetry located). NOTE: this does NOT verify the system is actually observable (signals emit in prod, alerts fire, SLO/error-budget tracked) — those are Manual rows in observability-readiness.md requiring operator evidence."
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
  printf '# RUNBOOK\n\n## Monitoring & alerting\n- Observability: SLOs: 99.9%% avail, p95 < 200ms · Telemetry wired: Prometheus + OTel traces + /healthz\n' > "$d3/RUNBOOK.md"
  if check_dir "$d3" >/dev/null 2>&1; then
    echo "selftest PASS: complete deployable -> OK"
  else
    echo "selftest FAIL: complete deployable should pass"; st_fail=1
  fi

  d4="$base/placeholder"; mkdir -p "$d4"
  printf 'FROM scratch\n' > "$d4/Dockerfile"
  printf '# RUNBOOK\n\n## Monitoring & alerting\n- Observability: SLOs: [target] · Telemetry wired: Prometheus + OTel\n' > "$d4/RUNBOOK.md"
  if check_dir "$d4" >/dev/null 2>&1; then
    echo "selftest FAIL: [target] placeholder should FAIL"; st_fail=1
  else
    echo "selftest PASS: SLOs [target] placeholder -> FAIL as expected"
  fi

  d5="$base/missing"; mkdir -p "$d5"
  printf 'FROM scratch\n' > "$d5/Dockerfile"
  printf '# RUNBOOK\n\n## Monitoring & alerting\n- Observability: SLOs: 99.9%% avail\n' > "$d5/RUNBOOK.md"
  if check_dir "$d5" >/dev/null 2>&1; then
    echo "selftest FAIL: missing telemetry record should FAIL"; st_fail=1
  else
    echo "selftest PASS: missing telemetry record -> FAIL as expected"
  fi

  if [ "$st_fail" -ne 0 ]; then
    echo "observability-ready --selftest: FAIL" >&2
    return 1
  fi
  echo "observability-ready --selftest: OK (na/no-surface/ok/placeholder/missing all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
