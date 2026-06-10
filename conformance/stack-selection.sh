#!/bin/sh
# stack-selection.sh — completeness drift-guard for the stack-decision aid (Slice 9g / R7).
# Asserts: (a) docs/STACK-SELECTION.md exists; (b) every shipped profiles/<stack>.md has a
# "Best for" + "Avoid when" section; (c) the matrix names every shipped profile. Completeness,
# NOT content-equality (a doc aid, not a security control). A new profile must add a matrix
# row + its own section or this fails.
#   sh conformance/stack-selection.sh [--selftest]
# Exit: 0 = complete · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

GUIDE="docs/STACK-SELECTION.md"
PROFILE_DIR="profiles"

# check_tree <guide> <profile-dir>: print PASS/FAIL lines; return 1 if any gap.
check_tree() {
  guide=$1; pdir=$2; f=0
  if [ ! -f "$guide" ]; then echo "FAIL: missing $guide"; return 1; fi
  for p in "$pdir"/*.md; do
    [ -f "$p" ] || continue
    case "$p" in */_TEMPLATE.md) continue ;; esac
    name=$(basename "$p" .md)
    if grep -qi "best for" "$p" && grep -qi "avoid when" "$p"; then
      echo "PASS: $name has Best-for/Avoid-when"
    else
      echo "FAIL: $name profile missing Best-for/Avoid-when"; f=1
    fi
    # name present in the matrix, bounded so 'go' does not match 'good'
    if grep -Eq "(^|[^a-z])$name([^a-z]|\$)" "$guide"; then
      echo "PASS: matrix names $name"
    else
      echo "FAIL: $guide matrix omits $name"; f=1
    fi
  done
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # (1) a tree with a gap must be DETECTED (check returns non-zero)
  g=$(mktemp -d); mkdir -p "$g/profiles"
  printf '# guide\n\n| okstack | x | y |\n' > "$g/guide.md"
  printf '# gap-stack\n## Toolchain\nno section here\n' > "$g/profiles/gap-stack.md"
  if check_tree "$g/guide.md" "$g/profiles" >/dev/null 2>&1; then
    echo "FAIL: selftest — gap not detected"; sfail=1
  else
    echo "PASS: selftest — missing section / matrix row detected"
  fi
  # (2) an all-good tree must PASS
  ok=$(mktemp -d); mkdir -p "$ok/profiles"
  printf '# guide\n\n| okstack | x | y |\n' > "$ok/guide.md"
  printf '# okstack\n## Best for / Avoid when\nBest for: x. Avoid when: y.\n' > "$ok/profiles/okstack.md"
  if check_tree "$ok/guide.md" "$ok/profiles" >/dev/null 2>&1; then
    echo "PASS: selftest — complete tree passes"
  else
    echo "FAIL: selftest — complete tree wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: stack-selection selftest"; exit 0; } || { echo "FAIL: stack-selection selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: stack-selection.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Stack-selection completeness:"
if check_tree "$GUIDE" "$PROFILE_DIR"; then
  echo "OK: stack-decision aid complete (guide + per-profile sections + matrix rows)"
  exit 0
else
  echo "FAIL: stack-decision aid incomplete (see above)"
  exit 1
fi
