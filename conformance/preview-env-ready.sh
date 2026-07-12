#!/bin/sh
# preview-env-ready.sh — conditional, fail-closed preview-environment-record check (Safe Non-Prod, SNP-2).
#
# Companion to conformance/preview-environments-readiness.md. For a project with a DEPLOY SURFACE it
# asserts the preview-environment approach is RECORDED: the RUNBOOK §4 has a "Preview environments:"
# line (not the [approach] placeholder). Non-deployable projects are N/A (skip-pass).
#
# SCOPE — a green run proves the approach is RECORDED, NOT that previews actually spin up, tear down,
# isolate, or exclude prod data. Those are Manual operator rows in preview-environments-readiness.md.
# Recommended, not required — a tiny tool may record "N/A — Dev->Prod" and still pass (it records an
# approach). Necessary, not sufficient.
#
# Usage:
#   sh conformance/preview-env-ready.sh [project-dir]   (default: .)
#   sh conformance/preview-env-ready.sh --selftest
set -eu

# shellcheck disable=SC1091  # shared helper, sourced at runtime (sibling of this script)
. "$(dirname "$0")/wf-helpers.sh"   # provides wf_is_deploy() — single source of truth

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
    echo "N/A: $dir has no deploy surface (no Dockerfile / deploy workflow) — no preview environments to declare"
    return 0
  fi

  rb="$dir/RUNBOOK.md"
  if [ ! -f "$rb" ]; then
    echo "FAIL: $dir is deployable but has no RUNBOOK.md (need a Preview-environments record) — see conformance/preview-environments-readiness.md"
    return 1
  fi
  # Record string must stay in sync with templates/RUNBOOK-TEMPLATE.md §4.
  if ! grep -Eiq 'preview environments:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'Preview environments:' record — declare the per-PR approach (or 'N/A — <reason>')"
    fail=1
  elif grep -Eiq 'preview environments:.*\[approach\]' "$rb"; then
    echo "FAIL: 'Preview environments:' still holds the [approach] placeholder — record a real approach"
    fail=1
  fi
  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "preview-env-ready: OK — preview-environment approach is RECORDED. NOTE: does NOT verify previews actually spin up / tear down / isolate / exclude prod data — those are Manual rows (preview-environments-readiness.md)."
  return 0
}

# mktemp fixtures; outcomes asserted. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st=0
  base=$(mktemp -d)

  d="$base/na"; mkdir -p "$d"; printf '# a library\n' > "$d/README.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: no-deploy-surface -> N/A"; else echo "selftest FAIL: no-surface should be N/A"; st=1; fi

  # recorded fixture mirrors the real RUNBOOK template shape (bold key + parenthetical), filled
  d="$base/ok"; mkdir -p "$d"
  printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n\n## 4. Deploy\n- **Preview environments:** namespace-per-PR via Helm, synthetic data, auto-teardown on close *(scoped creds)*\n' > "$d/RUNBOOK.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: deployable + recorded -> OK"; else echo "selftest FAIL: recorded should pass"; st=1; fi

  d="$base/placeholder"; mkdir -p "$d"
  printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n- **Preview environments:** [approach] *(deployable services — see docs/operations/preview-environments.md)*\n' > "$d/RUNBOOK.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: [approach] placeholder should FAIL"; st=1; else echo "selftest PASS: [approach] placeholder -> FAIL"; fi

  d="$base/missing"; mkdir -p "$d"
  printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n\n## 4. Deploy\n- deploy: kubectl apply\n' > "$d/RUNBOOK.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: missing preview record should FAIL"; st=1; else echo "selftest PASS: missing record -> FAIL"; fi

  if [ "$st" -ne 0 ]; then echo "preview-env-ready --selftest: FAIL" >&2; return 1; fi
  echo "preview-env-ready --selftest: OK (na/recorded/placeholder/missing all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "${1:-.}"; exit $? ;;
esac
