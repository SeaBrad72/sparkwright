#!/bin/sh
# deployable-ready.sh — conditional, fail-closed release-readiness DOC check.
#
# Companion to conformance/definition-of-deployable.md (the Release gate,
# DEVELOPMENT-PROCESS.md §7). For a project WITH a deploy surface — a Dockerfile,
# OR a workflow with an `environment:` key, OR a deploy job/step — it asserts the
# release-safety procedures are DOCUMENTED: RUNBOOK.md has a Deploy section and a
# Rollback section, and a smoke test is referenced. Projects with NO deploy surface
# are N/A (skip-pass) — release-readiness is not forced on libraries/CLIs/batch jobs.
#
# SCOPE — read this before trusting a green run: this verifies release-safety is
# WRITTEN DOWN, NOT that the rollback was tested or that alerts are wired. Those are
# Manual rows in definition-of-deployable.md, signed off by the release manager with
# evidence. A green run here is necessary, not sufficient.
#
# Usage:
#   sh conformance/deployable-ready.sh [project-dir]   (default: .)
#   sh conformance/deployable-ready.sh --selftest      (build fixtures, assert skip/OK/FAIL)
#
# Run at the Release gate (DEVELOPMENT-PROCESS.md §7); also self-tested in kit CI.
set -eu

# shellcheck disable=SC1091  # shared helper, sourced at runtime (sibling of this script)
. "$(dirname "$0")/wf-helpers.sh"   # provides wf_is_deploy() — single source of truth

# Core check over a single project directory. Returns 0 (OK or N/A) / 1 (FAIL).
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
    echo "N/A: $dir has no deploy surface (no Dockerfile / deploy workflow) — skipping (not a deployable service)"
    return 0
  fi

  rb="$dir/RUNBOOK.md"
  if [ ! -f "$rb" ]; then
    echo "FAIL: $dir is deployable but has no RUNBOOK.md (need Deploy + Rollback sections) — see conformance/definition-of-deployable.md"
    return 1
  fi

  if ! grep -Eiq '^#{1,6}[[:space:]].*deploy' "$rb"; then
    echo "FAIL: $rb has no Deploy section (a heading matching 'deploy')"
    fail=1
  fi
  if ! grep -Eiq '^#{1,6}[[:space:]].*rollback' "$rb"; then
    echo "FAIL: $rb has no Rollback section (a heading matching 'rollback')"
    fail=1
  fi

  smoke=0
  if grep -iq 'smoke' "$rb"; then smoke=1; fi
  if [ "$smoke" -eq 0 ] && [ -d "$dir/.github/workflows" ]; then
    for wf in "$dir"/.github/workflows/*.yml "$dir"/.github/workflows/*.yaml; do
      [ -f "$wf" ] || continue
      if grep -iq 'smoke' "$wf"; then smoke=1; break; fi
    done
  fi
  if [ "$smoke" -eq 0 ]; then
    echo "FAIL: no smoke test referenced (in $rb or a workflow)"
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "deployable-ready: OK — release-readiness DOCS present. NOTE: this verifies documentation only, NOT that rollback/alerts/migrations were tested. Those are Manual rows in definition-of-deployable.md requiring release-manager evidence."
  return 0
}

# Build mktemp fixtures and assert each outcome. Fixtures are LEFT in place
# (no rm -rf — avoids tripping the .claude/ runtime guard; see docs/adoption).
selftest() {
  st_fail=0
  base=$(mktemp -d)

  d1="$base/na"; mkdir -p "$d1"
  if check_dir "$d1" >/dev/null 2>&1; then
    echo "selftest PASS: empty dir -> N/A skip"
  else
    echo "selftest FAIL: empty dir should skip-pass"; st_fail=1
  fi

  d2="$base/ok"; mkdir -p "$d2"
  printf 'FROM scratch\n' > "$d2/Dockerfile"
  printf '# RUNBOOK\n\n## Deploy\nrun a smoke test after deploy\n\n## Rollback\nflag-off\n' > "$d2/RUNBOOK.md"
  if check_dir "$d2" >/dev/null 2>&1; then
    echo "selftest PASS: complete deployable -> OK"
  else
    echo "selftest FAIL: complete deployable should pass"; st_fail=1
  fi

  d3="$base/fail"; mkdir -p "$d3"
  printf 'FROM scratch\n' > "$d3/Dockerfile"
  printf '# RUNBOOK\n\n## Deploy\nsmoke test here\n' > "$d3/RUNBOOK.md"
  if check_dir "$d3" >/dev/null 2>&1; then
    echo "selftest FAIL: missing-rollback should FAIL"; st_fail=1
  else
    echo "selftest PASS: missing-rollback -> FAIL as expected"
  fi

  d4="$base/wf"; mkdir -p "$d4/.github/workflows"
  printf 'jobs:\n  deploy:\n    environment: production\n' > "$d4/.github/workflows/deploy.yml"
  printf '# RUNBOOK\n\n## Deploy\nsmoke\n\n## Rollback\nrevert\n' > "$d4/RUNBOOK.md"
  if check_dir "$d4" >/dev/null 2>&1; then
    echo "selftest PASS: workflow-deployable -> OK"
  else
    echo "selftest FAIL: workflow-deployable should pass"; st_fail=1
  fi

  # d5: a "deploy docs" GitHub Pages step name must NOT count as a deploy surface
  # (anti-false-positive — a docs-only workflow shouldn't force release-readiness).
  d5="$base/docsdeploy"; mkdir -p "$d5/.github/workflows"
  printf 'jobs:\n  pages:\n    steps:\n      - name: deploy docs to pages\n        run: echo build\n' > "$d5/.github/workflows/pages.yml"
  if check_dir "$d5" >/dev/null 2>&1; then
    echo "selftest PASS: docs-deploy step -> N/A (not over-triggered)"
  else
    echo "selftest FAIL: docs-deploy step should be N/A, not a deploy surface"; st_fail=1
  fi

  # d6: deployable (Dockerfile) but NO RUNBOOK.md -> FAIL (the early-return path)
  d6="$base/norunbook"; mkdir -p "$d6"
  printf 'FROM scratch\n' > "$d6/Dockerfile"
  if check_dir "$d6" >/dev/null 2>&1; then
    echo "selftest FAIL: deployable without RUNBOOK should FAIL"; st_fail=1
  else
    echo "selftest PASS: deployable without RUNBOOK -> FAIL as expected"
  fi

  if [ "$st_fail" -ne 0 ]; then
    echo "deployable-ready --selftest: FAIL" >&2
    return 1
  fi
  echo "deployable-ready --selftest: OK (skip/OK/FAIL/workflow/docs/no-runbook all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
