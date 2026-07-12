#!/bin/sh
# security-policy.sh — conditional, fail-closed SECURITY.md presence/disclosure check (SP-2).
#
# Trigger: a governed repo (a CLAUDE.md is present) MUST ship a SECURITY.md with a real
# security contact (not the [security-contact] template placeholder). A bare scratch dir
# (no CLAUDE.md) is N/A — nothing to disclose against. Mirrors observability-ready.sh.
#
# SCOPE: a green run proves a disclosure policy is RECORDED with a real contact — NOT that the
# process actually works (acknowledgement SLAs met, triage happens). Those are operator rows.
#
# Usage:
#   sh conformance/security-policy.sh [project-dir]   (default: .)
#   sh conformance/security-policy.sh --selftest
set -eu

check_dir() {
  dir="$1"
  if [ ! -f "$dir/CLAUDE.md" ]; then
    echo "N/A: $dir is not a governed repo (no CLAUDE.md) — skipping (no disclosure policy required)"
    return 0
  fi
  sec="$dir/SECURITY.md"
  if [ ! -f "$sec" ]; then
    echo "FAIL: $dir has a CLAUDE.md but no SECURITY.md — ship a coordinated-disclosure policy (templates/SECURITY-TEMPLATE.md)"
    return 1
  fi
  # Record string stays in sync with templates/SECURITY-TEMPLATE.md.
  if ! grep -Eiq 'security contact:' "$sec"; then
    echo "FAIL: SECURITY.md has no 'Security contact:' line — name a real reporting channel"
    return 1
  fi
  if grep -Fiq '[security-contact]' "$sec"; then
    echo "FAIL: SECURITY.md still holds the [security-contact] placeholder — record a real contact"
    return 1
  fi
  echo "security-policy: OK — SECURITY.md present with a real security contact. NOTE: this does NOT verify the disclosure process works (SLAs met, triage happens) — those are operator rows."
  return 0
}

selftest() {
  st_fail=0
  base=$(mktemp -d)

  d1="$base/na"; mkdir -p "$d1"; printf '# scratch\n' > "$d1/README.md"
  if check_dir "$d1" >/dev/null 2>&1; then echo "selftest PASS: no CLAUDE.md -> N/A"; else echo "selftest FAIL: should be N/A"; st_fail=1; fi

  d2="$base/missing"; mkdir -p "$d2"; printf '# CLAUDE\n' > "$d2/CLAUDE.md"
  if check_dir "$d2" >/dev/null 2>&1; then echo "selftest FAIL: CLAUDE.md without SECURITY.md should FAIL"; st_fail=1; else echo "selftest PASS: governed + no SECURITY.md -> FAIL"; fi

  d3="$base/placeholder"; mkdir -p "$d3"; printf '# CLAUDE\n' > "$d3/CLAUDE.md"
  printf '# Security Policy\n\n**Security contact:** [security-contact]\n' > "$d3/SECURITY.md"
  if check_dir "$d3" >/dev/null 2>&1; then echo "selftest FAIL: [security-contact] placeholder should FAIL"; st_fail=1; else echo "selftest PASS: placeholder -> FAIL"; fi

  d4="$base/ok"; mkdir -p "$d4"; printf '# CLAUDE\n' > "$d4/CLAUDE.md"
  printf '# Security Policy\n\n**Security contact:** GitHub private vulnerability reporting\n' > "$d4/SECURITY.md"
  if check_dir "$d4" >/dev/null 2>&1; then echo "selftest PASS: filled contact -> OK"; else echo "selftest FAIL: filled should pass"; st_fail=1; fi

  if [ "$st_fail" -ne 0 ]; then echo "security-policy --selftest: FAIL" >&2; return 1; fi
  echo "security-policy --selftest: OK (na/missing/placeholder/ok all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
