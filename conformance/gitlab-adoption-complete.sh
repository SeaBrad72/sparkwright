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
#   KIT_GA_DOC       path to the adoption guide    (default: docs/operations/gitlab-adoption.md)
#   KIT_GA_PROFILE   path to the GitLab CI profile (default: profiles/typescript-node/ci.gitlab-ci.yml)
#   KIT_GA_PROFILES  dir to count profiles/*/ci{,.gitlab-ci}.yml under (default: profiles)
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

# check_coverage <doc> <profiles-dir>: D-240906-1's binding condition. GitLab is a declared
# reference for ONE stack (`typescript-node`), not a claim of parity across the stack matrix — so
# the doc's stated coverage is DERIVED from the real profile counts (profiles/*/ci.gitlab-ci.yml
# vs profiles/*/ci.yml), not hand-typed, and this leg reds the moment they diverge (a new stack
# profile added/removed without updating the doc's headline sentence, or the doc's number drifting
# on its own). Honest ceiling: this proves the STATED NUMBER matches the REAL COUNT — it does not
# judge whether the surrounding prose is otherwise honest (that is doc-markers.tsv's job on the
# specific sentences it pins).
check_coverage() {
  _cd=$1; _cp=$2
  _root=$(dirname "$_cp")
  if [ ! -f "$_root/docs/ROADMAP-KIT.md" ]; then
    echo "N/A -- adoption guide's stated GitLab coverage ('N of M stacks') is a kit-matrix fact (the kit's full stack profile set); it cannot be verified on a pruned/adopter profile tree (no docs/ROADMAP-KIT.md found at $_root) — skipping the count assertion"
    return 0
  fi
  _gl=$(find "$_cp" -mindepth 2 -maxdepth 2 -name 'ci.gitlab-ci.yml' -type f 2>/dev/null | grep -c '')
  _tot=$(find "$_cp" -mindepth 2 -maxdepth 2 -name 'ci.yml' -type f 2>/dev/null | grep -c '')
  if [ ! -f "$_cd" ]; then
    echo "FAIL: coverage check — adoption guide missing ($_cd)"
    return 1
  fi
  if grep -Eq "(^|[^0-9])${_gl} of ${_tot} stacks($|[^0-9])" "$_cd"; then
    echo "PASS: adoption guide states GitLab coverage truthfully ($_gl of $_tot stacks, derived from $_cp)"
    return 0
  fi
  echo "FAIL: adoption guide's stated GitLab coverage does not match the derived count ($_gl of $_tot stacks under $_cp) — update the headline sentence in $_cd"
  return 1
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

  # --- kit marker: coverage fixtures (d)-(f) run on a KIT tree — the count assertion stays live ---
  mkdir -p "$d/docs"
  : > "$d/docs/ROADMAP-KIT.md"

  # --- coverage fixture (d): a 1-gitlab/10-total profile tree whose doc states it truthfully --- MUST PASS
  mkdir -p "$d/profiles/typescript-node" "$d/profiles/go" "$d/profiles/python" \
           "$d/profiles/rust" "$d/profiles/java" "$d/profiles/csharp" \
           "$d/profiles/ruby" "$d/profiles/php" "$d/profiles/kotlin" "$d/profiles/swift"
  : > "$d/profiles/typescript-node/ci.gitlab-ci.yml"
  for _p in typescript-node go python rust java csharp ruby php kotlin swift; do : > "$d/profiles/$_p/ci.yml"; done
  printf 'GitLab is a declared reference for typescript-node only — 1 of 10 stacks ships a GitLab pipeline.\n' > "$d/doc-coverage-true.md"
  if check_coverage "$d/doc-coverage-true.md" "$d/profiles" >/dev/null 2>&1; then
    echo "PASS: selftest — coverage fixture (1 of 10, doc matches) passes"
  else
    echo "FAIL: selftest — truthful coverage fixture wrongly failed"; sfail=1
  fi

  # --- coverage fixture (e): doc states a stale/wrong number --- MUST FAIL (D-240906-1's binding condition)
  printf 'All 8 required CI gates are present and verified on GitLab with zero adoption work.\n' > "$d/doc-coverage-stale.md"
  if check_coverage "$d/doc-coverage-stale.md" "$d/profiles" >/dev/null 2>&1; then
    echo "FAIL: selftest — stale/mismatched coverage claim wrongly passed"; sfail=1
  else
    echo "PASS: selftest — stale GitLab-coverage claim ('zero adoption work', no derived count) detected"
  fi

  # --- coverage fixture (f): profile counts change (a stack gains a GitLab pipeline) but the doc's
  #     number does NOT update --- MUST FAIL (this is the doc-drift the leg exists to catch)
  mkdir -p "$d/profiles2/typescript-node" "$d/profiles2/go" "$d/profiles2/python"
  : > "$d/profiles2/typescript-node/ci.gitlab-ci.yml"
  : > "$d/profiles2/go/ci.gitlab-ci.yml"
  : > "$d/profiles2/typescript-node/ci.yml"
  : > "$d/profiles2/go/ci.yml"
  : > "$d/profiles2/python/ci.yml"
  if check_coverage "$d/doc-coverage-true.md" "$d/profiles2" >/dev/null 2>&1; then
    echo "FAIL: selftest — profile count moved to 2 of 3 but the doc still claiming '1 of 10' wrongly passed"; sfail=1
  else
    echo "PASS: selftest — profile-count drift against a stale doc number detected"
  fi

  # --- coverage fixture (g): a PRUNED/ADOPTER tree — no docs/ROADMAP-KIT.md marker, a single
  #     surviving profile, and a doc still stating the kit's full "1 of 10 stacks" headline ---
  #     MUST PASS as N/A (rc 0), not red — this is the false-adopter-gate class the slice exists
  #     to prevent (CI's cf-export-claims job on the profile-pruned export).
  ad=$(mktemp -d)
  mkdir -p "$ad/profiles/typescript-node"
  : > "$ad/profiles/typescript-node/ci.gitlab-ci.yml"
  : > "$ad/profiles/typescript-node/ci.yml"
  printf 'GitLab is a declared reference for typescript-node only — 1 of 10 stacks ships a GitLab pipeline.\n' > "$ad/doc-coverage-true.md"
  if _out=$(check_coverage "$ad/doc-coverage-true.md" "$ad/profiles" 2>&1) && printf '%s\n' "$_out" | grep -q '^N/A'; then
    echo "PASS: selftest — pruned/adopter tree (no kit marker) renders N/A rc 0, not red"
  else
    echo "FAIL: selftest — pruned/adopter tree wrongly asserted the kit-matrix count (or failed to render N/A)"; sfail=1
  fi
  rm -rf "$ad"

  [ "$sfail" -eq 0 ] && { echo "OK: gitlab-adoption-complete selftest"; exit 0; } || { echo "FAIL: gitlab-adoption-complete selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: gitlab-adoption-complete.sh [--selftest]" >&2; exit 2 ;;
esac

DOC="${KIT_GA_DOC:-$_DOC_DEFAULT}"
PROFILE="${KIT_GA_PROFILE:-$_PROFILE_DEFAULT}"
PROFILES_DIR="${KIT_GA_PROFILES:-profiles}"

echo "GitLab adoption guide completeness ($DOC + $PROFILE):"
if check "$DOC" "$PROFILE" && check_coverage "$DOC" "$PROFILES_DIR"; then
  echo "OK: GitLab adoption guide covers branch-protection + ratification + DORA; profile references it; stated coverage matches the derived profile count"
  exit 0
else
  echo "FAIL: GitLab adoption guide is missing a required section or the profile reference (see above)"
  exit 1
fi
