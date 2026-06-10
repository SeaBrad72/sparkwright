#!/bin/sh
# action-pinning.sh — assert the canonical reference pipeline SHA-pins every `uses:` (Slice 9j).
# The other 9 profiles are adopter-templates (pin at adoption); the contract is enforced on the
# canonical reference so the kit satisfies its own "pin to a full commit SHA" rule.
#   sh conformance/action-pinning.sh [--selftest]
# Exit: 0 = all SHA-pinned · 1 = a tag-pinned uses: · 2 = bad usage. POSIX sh; dash-clean.
set -eu

REF="profiles/typescript-node/ci.yml"

# check_pinned <workflow>: print PASS/FAIL per `uses:`; return 1 if any is not a 40-hex SHA.
# Extraction is comment-safe: only lines whose YAML key is `uses:` (optionally after `- `) count,
# so a "# pin uses: to a SHA" guidance COMMENT is never mistaken for a real action ref. Trailing
# `# vX` comments are stripped before reading the ref (awk's last field).
check_pinned() {
  wf=$1; f=0
  if [ ! -f "$wf" ]; then echo "FAIL: missing $wf"; return 1; fi
  refs=$(grep -E '^[[:space:]]*-?[[:space:]]*uses:' "$wf" | sed 's/#.*//' | awk '{print $NF}')
  if [ -z "$refs" ]; then echo "FAIL: no uses: found in $wf"; return 1; fi
  for r in $refs; do
    case "$r" in
      *@*) : ;;
      *) echo "FAIL: $r has no @ref"; f=1; continue ;;
    esac
    sha=${r#*@}
    case "$sha" in
      *[!0-9a-f]*) echo "FAIL: $r is not SHA-pinned (tag/branch)"; f=1 ;;
      *) if [ "${#sha}" -eq 40 ]; then echo "PASS: $r"; else echo "FAIL: $r is not a 40-char SHA"; f=1; fi ;;
    esac
  done
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # gap tree: a tag-pinned uses: must be detected (incl. a guidance comment that must be ignored)
  g=$(mktemp -d)
  printf '# pin every `uses:` to a SHA\njobs:\n  x:\n    steps:\n      - uses: actions/checkout@v4\n' > "$g/wf.yml"
  if check_pinned "$g/wf.yml" >/dev/null 2>&1; then
    echo "FAIL: selftest — tag-pin not detected"; sfail=1
  else
    echo "PASS: selftest — tag-pin detected (and comment ignored)"
  fi
  # complete tree: a 40-hex SHA-pinned uses: with a trailing # vX comment must pass
  ok=$(mktemp -d)
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@1111111111111111111111111111111111111111  # v4\n' > "$ok/wf.yml"
  if check_pinned "$ok/wf.yml" >/dev/null 2>&1; then
    echo "PASS: selftest — SHA-pin passes"
  else
    echo "FAIL: selftest — SHA-pin wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: action-pinning selftest"; exit 0; } || { echo "FAIL: action-pinning selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: action-pinning.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Action-pinning ($REF):"
if check_pinned "$REF"; then
  echo "OK: every uses: in the canonical reference is SHA-pinned"
  exit 0
else
  echo "FAIL: a uses: in the canonical reference is not SHA-pinned (see above)"
  exit 1
fi
