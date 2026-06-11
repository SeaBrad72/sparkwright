#!/bin/sh
# test-data-ready.sh — conditional, fail-closed test-data-record check (Safe Non-Prod, SNP-1).
#
# Companion to conformance/test-data-readiness.md. For a project with a DATA SURFACE it asserts the
# test-data approach is RECORDED: the RUNBOOK has a "Test data:" line (not the [approach] placeholder).
# Projects with no data surface are N/A (skip-pass) — a pure-compute CLI/library has no test data to manage.
#
# SCOPE — a green run proves the approach is RECORDED, NOT that the data is actually synthetic/masked
# or that no prod data leaked into non-prod. Those are Manual rows in test-data-readiness.md. Necessary,
# not sufficient.
#
# Usage:
#   sh conformance/test-data-ready.sh [project-dir]   (default: .)
#   sh conformance/test-data-ready.sh --selftest
set -eu

# Does $1 have a persistent-data surface? (same signals as dr-ready.sh)
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
    echo "N/A: $dir has no persistent-data surface (no DB url in .env.example / migrations dir / compose db) — no test data to manage"
    return 0
  fi
  rb="$dir/RUNBOOK.md"
  if [ ! -f "$rb" ]; then
    echo "FAIL: $dir handles data but has no RUNBOOK.md (need a Test-data record) — see conformance/test-data-readiness.md"
    return 1
  fi
  # Record string must stay in sync with templates/RUNBOOK-TEMPLATE.md §2.
  if ! grep -Eiq 'test data:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'Test data:' record — declare the non-prod data approach (synthetic / masked / never raw prod)"
    fail=1
  elif grep -Eiq 'test data:.*\[approach\]' "$rb"; then
    echo "FAIL: 'Test data:' still holds the [approach] placeholder — record a real approach"
    fail=1
  fi
  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "test-data-ready: OK — test-data approach is RECORDED. NOTE: does NOT verify the data is actually synthetic/masked or that no prod data leaked — those are Manual rows (test-data-readiness.md)."
  return 0
}

# mktemp fixtures; outcomes asserted. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st=0
  base=$(mktemp -d)

  d="$base/no-data"; mkdir -p "$d"; printf '# a stateless CLI\n' > "$d/README.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: no-data -> N/A"; else echo "selftest FAIL: no-data should be N/A"; st=1; fi

  # data-ok fixture mirrors the real RUNBOOK template shape (bold key + parenthetical), filled.
  d="$base/data-ok"; mkdir -p "$d"
  printf 'DATABASE_URL=postgres://localhost/app\n' > "$d/.env.example"
  printf '# RUNBOOK\n\n## 2. Test / build\n- **Test data:** synthetic via faker; seeded fixtures *(never raw prod)*\n' > "$d/RUNBOOK.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: data + recorded -> OK"; else echo "selftest FAIL: recorded should pass"; st=1; fi

  # placeholder fixture mirrors the unfilled template line verbatim.
  d="$base/data-placeholder"; mkdir -p "$d"
  printf 'DATABASE_URL=postgres://localhost/app\n' > "$d/.env.example"
  printf '# RUNBOOK\n- **Test data:** [approach] *(data-handling projects — see docs/operations/test-data-management.md)*\n' > "$d/RUNBOOK.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: [approach] placeholder should FAIL"; st=1; else echo "selftest PASS: [approach] placeholder -> FAIL"; fi

  d="$base/data-missing"; mkdir -p "$d"
  printf 'DATABASE_URL=postgres://localhost/app\n' > "$d/.env.example"
  printf '# RUNBOOK\n\n## 2. Test / build\n- build: make\n' > "$d/RUNBOOK.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: missing test-data record should FAIL"; st=1; else echo "selftest PASS: missing record -> FAIL"; fi

  if [ "$st" -ne 0 ]; then echo "test-data-ready --selftest: FAIL" >&2; return 1; fi
  echo "test-data-ready --selftest: OK (no-data/recorded/placeholder/missing all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "${1:-.}"; exit $? ;;
esac
