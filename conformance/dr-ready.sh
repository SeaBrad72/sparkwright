#!/bin/sh
# Why this gate: sparkwright explain dr
# dr-ready.sh — conditional, fail-closed, ESCALATE-ONLY DR-readiness DOC check.
#
# Companion to conformance/dr-readiness.md (the DR-readiness gate; DEVELOPMENT-PROCESS.md
# §7 + the Definition of Done for data services). For a project that HANDLES PERSISTENT
# DATA it asserts DR is DOCUMENTED and a restore drill is RECORDED: a BIA artifact exists
# (docs/continuity/BIA.md), the RUNBOOK Disaster-recovery section has RPO/RTO filled (not
# the template placeholder), and a restore-drill date is recorded. No data surface -> N/A.
#
# DIRECTIONAL SAFETY — this check ESCALATES, it never EXEMPTS. Detection is deliberately
# conservative (so stateless tools are not nagged), so a MISS is possible. Therefore the
# N/A path is SELF-INCRIMINATING: if the project handles durable data, an N/A is WRONG and
# the human must apply conformance/dr-readiness.md regardless. The script can only ADD a
# requirement, never remove one. The BIA-at-Inception (a human criticality call) is primary.
#
# SCOPE — a green run proves DR is DOCUMENTED and a drill was RECORDED, NOT that the restore
# succeeded or met RTO/RPO. Those are Manual rows in dr-readiness.md (on-call/operator evidence).
#
# Usage:
#   sh conformance/dr-ready.sh [project-dir]   (default: .)
#   sh conformance/dr-ready.sh --selftest
#
# Run at the DR-readiness gate (DEVELOPMENT-PROCESS.md §7) and as recurring maintenance (§15).
set -eu

# Does $1 (a project dir) handle persistent data? Conservative; a MISS escalates, never exempts.
has_data_surface() {
  _d="$1"
  if [ -f "$_d/.env.example" ] && grep -Eiq 'DATABASE_URL|DB_URL|POSTGRES|MYSQL|MARIADB|MONGO|REDIS_URL|CONNECTION_STRING' "$_d/.env.example"; then
    return 0
  fi
  for _md in prisma migrations db/migrate alembic; do
    if [ -d "$_d/$_md" ]; then return 0; fi
  done
  for _cf in "$_d/compose.yaml" "$_d/compose.yml" "$_d/docker-compose.yml" "$_d/docker-compose.yaml"; do
    [ -f "$_cf" ] || continue
    if grep -Eiq 'image:[[:space:]]*"?(postgres|mysql|mariadb|mongo|redis)' "$_cf"; then return 0; fi
  done
  return 1
}

check_dir() {
  dir="$1"
  fail=0

  if ! has_data_surface "$dir"; then
    echo "N/A: $dir has no persistent-data surface (no DB url in .env.example / migrations dir / compose db) — skipping."
    echo "     WARNING: detection is conservative. If this project handles durable data, this N/A is WRONG —"
    echo "     apply conformance/dr-readiness.md manually. This check escalates (detect -> require); it never exempts."
    return 0
  fi

  rb="$dir/RUNBOOK.md"
  bia="$dir/docs/continuity/BIA.md"

  if [ ! -f "$bia" ]; then
    echo "FAIL: data project has no BIA at docs/continuity/BIA.md (run templates/BIA-TEMPLATE.md) — see conformance/dr-readiness.md"
    fail=1
  fi
  if [ ! -f "$rb" ]; then
    echo "FAIL: data project has no RUNBOOK.md (need a Disaster recovery section with RPO/RTO + a recorded drill)"
    return 1
  fi
  if ! grep -Eiq '^#{1,6}[[:space:]].*disaster recovery' "$rb"; then
    echo "FAIL: RUNBOOK.md has no Disaster recovery section"
    fail=1
  fi
  # Placeholder strings below must stay in sync with templates/RUNBOOK-TEMPLATE.md §6;
  # if that template's RPO/RTO placeholder wording changes, update these greps too.
  if grep -Fq '[< 24h default]' "$rb" || grep -Fq '[< 4h default]' "$rb"; then
    echo "FAIL: RUNBOOK RPO/RTO still hold the template placeholder ([< 24h default] / [< 4h default]) — set real targets"
    fail=1
  fi
  if ! grep -Eiq 'restore verified:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'Restore verified:' line — record a restore-drill date"
    fail=1
  elif grep -Fiq 'restore verified: [date]' "$rb"; then
    echo "FAIL: 'Restore verified:' still holds the [date] placeholder — run a restore drill and record the date"
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "dr-ready: OK — DR is DOCUMENTED and a restore drill is RECORDED. NOTE: this does NOT verify the restore succeeded or met RTO/RPO — those are Manual rows in dr-readiness.md requiring on-call/operator evidence."
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
    echo "selftest PASS: stateless -> N/A (not over-triggered)"
  else
    echo "selftest FAIL: stateless should be N/A"; st_fail=1
  fi

  d3="$base/ok"; mkdir -p "$d3/docs/continuity"
  printf 'DATABASE_URL=postgres://localhost/app\n' > "$d3/.env.example"
  printf '# BIA\ncritical tier: RTO 1h / RPO 15m\n' > "$d3/docs/continuity/BIA.md"
  printf '# RUNBOOK\n\n## Disaster recovery\n- RPO: 1h RTO: 2h\n- Restore verified: 2026-06-01 (passed)\n' > "$d3/RUNBOOK.md"
  if check_dir "$d3" >/dev/null 2>&1; then
    echo "selftest PASS: complete data project -> OK"
  else
    echo "selftest FAIL: complete data project should pass"; st_fail=1
  fi

  d4="$base/placeholder"; mkdir -p "$d4/docs/continuity"
  printf 'DATABASE_URL=postgres://localhost/app\n' > "$d4/.env.example"
  printf '# BIA\n' > "$d4/docs/continuity/BIA.md"
  printf '# RUNBOOK\n\n## Disaster recovery\n- RPO: 1h RTO: 2h\n- Restore verified: [date]\n' > "$d4/RUNBOOK.md"
  if check_dir "$d4" >/dev/null 2>&1; then
    echo "selftest FAIL: [date] placeholder should FAIL"; st_fail=1
  else
    echo "selftest PASS: [date] placeholder -> FAIL as expected"
  fi

  d5="$base/nobia"; mkdir -p "$d5"
  printf 'DATABASE_URL=postgres://localhost/app\n' > "$d5/.env.example"
  printf '# RUNBOOK\n\n## Disaster recovery\n- RPO: 1h RTO: 2h\n- Restore verified: 2026-06-01\n' > "$d5/RUNBOOK.md"
  if check_dir "$d5" >/dev/null 2>&1; then
    echo "selftest FAIL: no-BIA should FAIL"; st_fail=1
  else
    echo "selftest PASS: no-BIA -> FAIL as expected"
  fi

  if [ "$st_fail" -ne 0 ]; then
    echo "dr-ready --selftest: FAIL" >&2
    return 1
  fi
  echo "dr-ready --selftest: OK (na/stateless/ok/placeholder/no-bia all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
