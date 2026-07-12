#!/bin/sh
# badge-version.sh — keep the README version badge in lockstep with VERSION (Slice 9k).
#   sh conformance/badge-version.sh            assert the badge == VERSION (CI gate; exit 1 on drift)
#   sh conformance/badge-version.sh --fix      rewrite the badge from VERSION (idempotent)
#   sh conformance/badge-version.sh --selftest fixture: drift fails, --fix syncs, synced passes
# Exit: 0 = ok · 1 = drift · 2 = bad usage. POSIX sh; dash-clean.
set -eu

VERSION_FILE="VERSION"
README="README.md"

read_version() { tr -d '[:space:]' < "$1"; }

# badge_version <readme>: echo the digits inside the first `vX.Y.Z` token, or empty.
badge_version() {
  grep -oE '`v[0-9]+\.[0-9]+\.[0-9]+`' "$1" 2>/dev/null | head -1 | tr -d '`v'
}

# assert_badge <version-file> <readme>: print PASS/FAIL; return 1 on drift.
assert_badge() {
  v=$(read_version "$1"); b=$(badge_version "$2")
  if [ -z "$b" ]; then echo "FAIL: no \`vX.Y.Z\` badge found in $2"; return 1; fi
  if [ "$b" = "$v" ]; then echo "PASS: README badge v$b matches VERSION $v"; return 0; fi
  echo "FAIL: README badge v$b != VERSION $v (run: sh conformance/badge-version.sh --fix)"; return 1
}

# fix_badge <version-file> <readme>: rewrite the first badge token from VERSION (idempotent).
fix_badge() {
  v=$(read_version "$1"); tmp="$2.tmp.$$"
  sed "s/\`v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\`/\`v$v\`/" "$2" > "$tmp" && mv "$tmp" "$2"
  echo "fixed: README badge set to v$v"
}

case "${1:-}" in
  --selftest)
    sfail=0
    d=$(mktemp -d)
    printf '2.34.0\n' > "$d/VERSION"
    printf '# X\n\n`v2.24.0` · Apache-2.0\n' > "$d/README.md"
    if assert_badge "$d/VERSION" "$d/README.md" >/dev/null 2>&1; then
      echo "FAIL: selftest — drift not detected"; sfail=1
    else
      echo "PASS: selftest — drift detected"
    fi
    fix_badge "$d/VERSION" "$d/README.md" >/dev/null 2>&1
    if assert_badge "$d/VERSION" "$d/README.md" >/dev/null 2>&1; then
      echo "PASS: selftest — --fix synced the badge"
    else
      echo "FAIL: selftest — --fix did not sync"; sfail=1
    fi
    [ "$sfail" -eq 0 ] && { echo "OK: badge-version selftest"; exit 0; } || { echo "FAIL: badge-version selftest"; exit 1; }
    ;;
  --fix)
    fix_badge "$VERSION_FILE" "$README"; exit 0
    ;;
  "")
    if assert_badge "$VERSION_FILE" "$README"; then exit 0; else exit 1; fi
    ;;
  *)
    echo "usage: badge-version.sh [--fix|--selftest]" >&2; exit 2
    ;;
esac
