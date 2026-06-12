#!/bin/sh
# privacy-ready.sh — conditional, fail-closed privacy-review check (SP-3).
#
# Trigger: a project that DECLARES it handles Confidential/Restricted personal data
# (a "Data classification:" line in CLAUDE.md or RUNBOOK.md naming Confidential or Restricted,
# not the template placeholder) MUST carry a filled PRIVACY-REVIEW.md (DPIA-lite). Projects with
# only Public/Internal data, an unfilled placeholder, or no declaration are N/A — no personal-data
# review required. A general capability; COPPA is one applicability, not a mandate.
#
# SCOPE: green = a privacy review is RECORDED for the declared sensitive data — NOT that the
# processing is lawful/compliant or that deletion actually works. Those are Manual operator rows.
#
# Usage:
#   sh conformance/privacy-ready.sh [project-dir]   (default: .)
#   sh conformance/privacy-ready.sh --selftest
set -eu

# declares_sensitive <dir>: true if a Data-classification line names Confidential/Restricted
# with a REAL value (not the [Public / Internal / Confidential / Restricted] template placeholder).
declares_sensitive() {
  _d="$1"
  for f in "$_d/CLAUDE.md" "$_d/RUNBOOK.md"; do
    [ -f "$f" ] || continue
    # the classification line, lowercased; skip ONLY if it still holds the unfilled tier-menu
    # placeholder (a bracketed list of the tiers with a '/'). A real value with an unrelated
    # bracket annotation (e.g. "restricted [phi/hipaa]") must NOT be skipped — that would
    # fail-open and drop a sensitive project out of the gate.
    _line=$(grep -i 'data classification:' "$f" 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]') || true
    [ -n "$_line" ] || continue
    printf '%s' "$_line" | grep -Eq '\[[^]]*(public|internal|confidential|restricted)[^]]*/[^]]*\]' && continue
    printf '%s' "$_line" | grep -Eq 'confidential|restricted' && return 0
  done
  return 1
}

check_dir() {
  dir="$1"
  if ! declares_sensitive "$dir"; then
    echo "N/A: $dir declares no Confidential/Restricted data (or none classified) — skipping (no privacy review required)"
    return 0
  fi
  pr="$dir/PRIVACY-REVIEW.md"
  if [ ! -f "$pr" ]; then
    echo "FAIL: $dir handles Confidential/Restricted data but has no PRIVACY-REVIEW.md — record a DPIA-lite (templates/PRIVACY-REVIEW-TEMPLATE.md)"
    return 1
  fi
  if ! grep -Eiq 'lawful basis' "$pr"; then
    echo "FAIL: PRIVACY-REVIEW.md has no 'Lawful basis' — record the basis for processing"
    return 1
  fi
  if grep -Fiq '[lawful basis' "$pr" || grep -Fiq 'basis for processing:** [' "$pr"; then
    echo "FAIL: PRIVACY-REVIEW.md still holds the lawful-basis placeholder — fill the review"
    return 1
  fi
  echo "privacy-ready: OK — a PRIVACY-REVIEW is recorded for the declared sensitive data. NOTE: this does NOT verify the processing is lawful/compliant or that deletion works — those are Manual rows."
  return 0
}

selftest() {
  st_fail=0
  base=$(mktemp -d)

  d1="$base/na_public"; mkdir -p "$d1"; printf '# CLAUDE\n\n- **Data classification:** Internal\n' > "$d1/CLAUDE.md"
  if check_dir "$d1" >/dev/null 2>&1; then echo "selftest PASS: Internal-only -> N/A"; else echo "selftest FAIL: Internal should be N/A"; st_fail=1; fi

  d2="$base/na_placeholder"; mkdir -p "$d2"; printf '# CLAUDE\n\n- **Data classification:** [Public / Internal / Confidential / Restricted]\n' > "$d2/CLAUDE.md"
  if check_dir "$d2" >/dev/null 2>&1; then echo "selftest PASS: unfilled placeholder -> N/A"; else echo "selftest FAIL: placeholder should be N/A"; st_fail=1; fi

  d3="$base/missing"; mkdir -p "$d3"; printf '# CLAUDE\n\n- **Data classification:** Restricted\n' > "$d3/CLAUDE.md"
  if check_dir "$d3" >/dev/null 2>&1; then echo "selftest FAIL: Restricted + no review should FAIL"; st_fail=1; else echo "selftest PASS: Restricted + no review -> FAIL"; fi

  d4="$base/review_placeholder"; mkdir -p "$d4"; printf '# CLAUDE\n\n- **Data classification:** Confidential\n' > "$d4/CLAUDE.md"
  printf '# Privacy Review\n\n- **Lawful basis / basis for processing:** [consent / contract / legitimate interest / legal obligation]\n' > "$d4/PRIVACY-REVIEW.md"
  if check_dir "$d4" >/dev/null 2>&1; then echo "selftest FAIL: review placeholder should FAIL"; st_fail=1; else echo "selftest PASS: review placeholder -> FAIL"; fi

  d5="$base/ok"; mkdir -p "$d5"; printf '# CLAUDE\n\n- **Data classification:** Restricted\n' > "$d5/CLAUDE.md"
  printf '# Privacy Review\n\n- **Lawful basis / basis for processing:** verifiable parental consent (COPPA)\n' > "$d5/PRIVACY-REVIEW.md"
  if check_dir "$d5" >/dev/null 2>&1; then echo "selftest PASS: filled review -> OK"; else echo "selftest FAIL: filled review should pass"; st_fail=1; fi

  if [ "$st_fail" -ne 0 ]; then echo "privacy-ready --selftest: FAIL" >&2; return 1; fi
  echo "privacy-ready --selftest: OK (na/placeholder/missing/review-placeholder/ok all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
