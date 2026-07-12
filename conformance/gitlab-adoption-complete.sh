#!/bin/sh
# gitlab-adoption-complete.sh — drift-guard: docs/operations/gitlab-adoption.md covers all three
# governance areas AND the TypeScript-Node GitLab profile references it (H4a honest-scoping lock).
# The check fails CI if the adopter guide loses a required section or the profile stops pointing at it.
#
#   sh conformance/gitlab-adoption-complete.sh [--selftest]
#
# Exit: 0 = complete · 1 = a required section or reference missing · 2 = usage.
# POSIX sh; dash-clean.
#
# Env overrides (for --selftest fixtures and dry-run):
#   KIT_GA_DOC      path to the adoption guide   (default: docs/operations/gitlab-adoption.md)
#   KIT_GA_PROFILE  path to the GitLab CI profile (default: profiles/typescript-node/ci.gitlab-ci.yml)
set -eu

_DOC_DEFAULT="docs/operations/gitlab-adoption.md"
_PROFILE_DEFAULT="profiles/typescript-node/ci.gitlab-ci.yml"

# The three governance-area headings that MUST be present.
HEADING_1="## Branch protection"
HEADING_2="## Control-plane ratification"
HEADING_3="## DORA"

# check <doc> <profile>: assert the doc exists, has all three headings, and the profile references it.
# Returns 1 on any failure (accumulates all failures so every gap is visible in one run).
check() {
  _doc=$1; _prof=$2; _rc=0

  if [ ! -f "$_doc" ]; then
    echo "FAIL: adoption guide missing ($_doc)"
    return 1
  fi
  echo "PASS: adoption guide exists ($_doc)"

  for _h in "$HEADING_1" "$HEADING_2" "$HEADING_3"; do
    if grep -qF "$_h" "$_doc"; then
      echo "PASS: heading present — $_h"
    else
      echo "FAIL: heading missing from $_doc — $_h"
      _rc=1
    fi
  done

  if [ ! -f "$_prof" ]; then
    echo "FAIL: GitLab profile missing ($_prof)"
    _rc=1
  elif grep -qF "gitlab-adoption.md" "$_prof"; then
    echo "PASS: profile references gitlab-adoption.md ($_prof)"
  else
    echo "FAIL: profile does not reference gitlab-adoption.md ($_prof)"
    _rc=1
  fi

  return $_rc
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  d=$(mktemp -d)

  # --- fixture (a): complete — doc has all 3 headings, profile references the doc --- MUST PASS
  cat > "$d/doc-complete.md" <<'EOF'
## Branch protection

Branch-protection details.

## Control-plane ratification

Ratification details.

## DORA

DORA metrics details.
EOF
  printf '# GitLab CI profile\n# see docs/operations/gitlab-adoption.md\n' > "$d/profile-ok.yml"

  if check "$d/doc-complete.md" "$d/profile-ok.yml" >/dev/null 2>&1; then
    echo "PASS: selftest — complete fixture passes"
  else
    echo "FAIL: selftest — complete fixture wrongly failed"; sfail=1
  fi

  # --- fixture (b): missing "## Control-plane ratification" --- MUST FAIL (exit 1)
  cat > "$d/doc-missing-section.md" <<'EOF'
## Branch protection

Branch-protection details.

## DORA

DORA metrics details.
EOF

  if check "$d/doc-missing-section.md" "$d/profile-ok.yml" >/dev/null 2>&1; then
    echo "FAIL: selftest — missing-section fixture wrongly passed"; sfail=1
  else
    echo "PASS: selftest — missing Control-plane ratification heading detected"
  fi

  # --- fixture (c): profile omits gitlab-adoption.md reference --- MUST FAIL (exit 1)
  printf '# GitLab CI profile\n# no reference to the adoption guide here\n' > "$d/profile-no-ref.yml"

  if check "$d/doc-complete.md" "$d/profile-no-ref.yml" >/dev/null 2>&1; then
    echo "FAIL: selftest — missing-profile-ref fixture wrongly passed"; sfail=1
  else
    echo "PASS: selftest — missing gitlab-adoption.md profile reference detected"
  fi

  [ "$sfail" -eq 0 ] && { echo "OK: gitlab-adoption-complete selftest"; exit 0; } || { echo "FAIL: gitlab-adoption-complete selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: gitlab-adoption-complete.sh [--selftest]" >&2; exit 2 ;;
esac

DOC="${KIT_GA_DOC:-$_DOC_DEFAULT}"
PROFILE="${KIT_GA_PROFILE:-$_PROFILE_DEFAULT}"

echo "GitLab adoption guide completeness ($DOC + $PROFILE):"
if check "$DOC" "$PROFILE"; then
  echo "OK: GitLab adoption guide covers branch-protection + ratification + DORA; profile references it"
  exit 0
else
  echo "FAIL: GitLab adoption guide is missing a required section or the profile reference (see above)"
  exit 1
fi
