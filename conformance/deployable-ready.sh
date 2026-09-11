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

# _section_body FILE HEADING-ERE — print the lines between the first line matching
# HEADING-ERE (case-insensitive, via tolower) and the NEXT markdown heading (or EOF).
# Content predicate helper for the Deploy/Rollback placeholder check below — presence
# of the heading is not enough; we need to look at what is UNDER it.
_section_body() {
  awk -v start="$2" '
    tolower($0) ~ start { s=1; next }
    s && /^#{1,6}[[:space:]]/ { exit }
    s { print }
  ' "$1"
}

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

  # A template that ships the Deploy/Rollback HEADINGS verbatim (templates/RUNBOOK-TEMPLATE.md
  # lines 27, 60) is presence, not content: an adopter who copies it and fills in nothing
  # (bodies still `[deploy command(s)]` / `[rollback command]`) must NOT pass green. Read the
  # section BODY, not just the heading; also reject the un-removed guidance banner, which by
  # itself signals "this runbook has not been customized."
  # The un-removed guidance banner is its OWN signal (the runbook was copied but not customized),
  # reported distinctly so a diligent adopter with real bodies is never pointed at a placeholder
  # that isn't there (reviewer M1).
  if grep -qF '> **Template.**' "$rb"; then
    echo "FAIL: $rb still carries the un-removed '> **Template.**' banner — remove it once the runbook is customized (see templates/RUNBOOK-TEMPLATE.md)"
    fail=1
  fi

  if ! grep -Eiq '^#{1,6}[[:space:]].*deploy' "$rb"; then
    echo "FAIL: $rb has no Deploy section (a heading matching 'deploy')"
    fail=1
  else
    deploy_body=$(_section_body "$rb" '^#{1,6}[[:space:]].*deploy')
    if printf '%s\n' "$deploy_body" | grep -qF '[deploy command(s)]'; then
      echo "FAIL: $rb Deploy section is still the unfilled template placeholder ([deploy command(s)]) — fill in real deploy steps (see templates/RUNBOOK-TEMPLATE.md)"
      fail=1
    fi
  fi
  if ! grep -Eiq '^#{1,6}[[:space:]].*rollback' "$rb"; then
    echo "FAIL: $rb has no Rollback section (a heading matching 'rollback')"
    fail=1
  else
    rollback_body=$(_section_body "$rb" '^#{1,6}[[:space:]].*rollback')
    if printf '%s\n' "$rollback_body" | grep -qF '[rollback command]'; then
      echo "FAIL: $rb Rollback section is still the unfilled template placeholder ([rollback command]) — fill in a real rollback command (see templates/RUNBOOK-TEMPLATE.md)"
      fail=1
    fi
  fi

  # Smoke reference: a mention of "smoke" that is ONLY the template's own unfilled
  # `[smoke test command]` sentinel is not a real reference — strip lines that carry just that
  # sentinel before deciding whether a genuine smoke reference remains.
  smoke=0
  if grep -iq 'smoke' "$rb" && grep -i 'smoke' "$rb" | grep -vF '[smoke test command]' | grep -iq 'smoke'; then
    smoke=1
  fi
  if [ "$smoke" -eq 0 ] && [ -d "$dir/.github/workflows" ]; then
    for wf in "$dir"/.github/workflows/*.yml "$dir"/.github/workflows/*.yaml; do
      [ -f "$wf" ] || continue
      if grep -iq 'smoke' "$wf"; then smoke=1; break; fi
    done
  fi
  if [ "$smoke" -eq 0 ]; then
    echo "FAIL: no smoke test referenced (in $rb or a workflow) — the template's own [smoke test command] placeholder does not count (see templates/RUNBOOK-TEMPLATE.md)"
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

  # d7: deployable (Dockerfile) + RUNBOOK.md with the Deploy/Rollback HEADINGS present but bodies
  # still the template's unfilled sentinels, plus the template's own [smoke test command] line —
  # a presence-only check would pass this green (measured before the fix). Content check -> FAIL.
  d7="$base/placeholder"; mkdir -p "$d7"
  printf 'FROM scratch\n' > "$d7/Dockerfile"
  printf '# RUNBOOK\n\n## Deploy\n[deploy command(s)]\n\n## Rollback\n[rollback command]\n\nSmoke test: after each deploy run the post-deploy smoke test ([smoke test command]) and record the result before declaring the release live\n' > "$d7/RUNBOOK.md"
  if check_dir "$d7" >/dev/null 2>&1; then
    echo "selftest FAIL: placeholder-body RUNBOOK (headings only, unfilled sentinels) should FAIL, not pass green"; st_fail=1
  else
    echo "selftest PASS: placeholder-body RUNBOOK -> FAIL as expected"
  fi

  # d8: the reviewer-M1 case — the un-removed '> **Template.**' banner but REAL Deploy/Rollback
  # bodies. Must FAIL on the banner-specific message, NOT be misdirected to the placeholder message.
  d8="$base/banner"; mkdir -p "$d8"
  printf 'FROM scratch\n' > "$d8/Dockerfile"
  printf '# RUNBOOK\n\n> **Template.**\n\n## Deploy\nrun ./scripts/deploy.sh then verify with a smoke test\n\n## Rollback\ngit revert and redeploy the prior tag\n' > "$d8/RUNBOOK.md"
  d8_out=$(check_dir "$d8" 2>&1) || true  # expected non-zero (banner FAIL); neutralize for set -e (dash aborts a failing assignment)
  if printf '%s\n' "$d8_out" | grep -qF 'un-removed' && ! printf '%s\n' "$d8_out" | grep -qF 'still the unfilled template placeholder'; then
    echo "selftest PASS: banner + real bodies -> FAILs on the banner message, not misdirected to the placeholder (M1)"
  else
    echo "selftest FAIL: banner-with-real-bodies should FAIL on the banner, not the placeholder message"; st_fail=1
  fi

  if [ "$st_fail" -ne 0 ]; then
    echo "deployable-ready --selftest: FAIL" >&2
    return 1
  fi
  echo "deployable-ready --selftest: OK (skip/OK/FAIL/workflow/docs/no-runbook/placeholder/banner all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
