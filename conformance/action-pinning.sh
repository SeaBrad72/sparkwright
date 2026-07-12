#!/bin/sh
# action-pinning.sh — assert every `uses:` is SHA-pinned across the kit's OWN workflows AND the
# canonical reference pipeline (Slice 9j; broadened in H4b to the kit's own .github/workflows/).
# The other 9 profiles are adopter-templates (pin at adoption); the contract is enforced on the
# canonical reference AND on the workflows the kit itself runs, so the kit satisfies its own
# "pin to a full commit SHA" rule everywhere it actually executes Actions.
#   sh conformance/action-pinning.sh [--selftest]
# Exit: 0 = all SHA-pinned · 1 = a tag/branch-pinned uses: · 2 = bad usage. POSIX sh; dash-clean.
set -eu

REF="profiles/typescript-node/ci.yml"        # canonical adopter reference
KIT_WORKFLOWS=".github/workflows"             # the workflows the kit itself runs

# has_uses <workflow>: 0 if the file declares at least one real `uses:` step.
has_uses() { grep -Eq '^[[:space:]]*-?[[:space:]]*uses:' "$1"; }

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

# check_target <workflow> <strict>: scan one workflow.
#  strict=1 (canonical reference) — a file with NO uses: is a FAIL (it MUST declare + pin actions).
#  strict=0 (a kit workflow)      — a file with NO uses: is vacuously pinned (OK, nothing to pin).
check_target() {
  _wf=$1; _strict=$2
  if [ ! -f "$_wf" ]; then echo "FAIL: missing $_wf"; return 1; fi
  if ! has_uses "$_wf"; then
    if [ "$_strict" = 1 ]; then echo "FAIL: $_wf declares no uses: (expected the canonical reference to pin actions)"; return 1; fi
    echo "OK: $_wf (no actions to pin)"; return 0
  fi
  echo "Action-pinning ($_wf):"
  if check_pinned "$_wf"; then echo "OK: every uses: in $_wf is SHA-pinned"; return 0; fi
  echo "FAIL: a uses: in $_wf is not SHA-pinned (see above)"; return 1
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
  # broadened scope (H4b): a kit workflow with NO uses: is vacuously OK (strict=0); the canonical
  # reference with no uses: is a FAIL (strict=1).
  nouse=$(mktemp -d)
  printf 'name: x\non: [push]\njobs:\n  y:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n' > "$nouse/wf.yml"
  if check_target "$nouse/wf.yml" 0 >/dev/null 2>&1; then echo "PASS: selftest — no-uses kit workflow is vacuously pinned"; else echo "FAIL: selftest — no-uses kit workflow wrongly failed"; sfail=1; fi
  if check_target "$nouse/wf.yml" 1 >/dev/null 2>&1; then echo "FAIL: selftest — strict reference with no uses not caught"; sfail=1; else echo "PASS: selftest — strict reference with no actions detected"; fi
  [ "$sfail" -eq 0 ] && { echo "OK: action-pinning selftest"; exit 0; } || { echo "FAIL: action-pinning selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: action-pinning.sh [--selftest]" >&2; exit 2 ;;
esac

rc=0
# 1) the canonical adopter reference (strict — it must declare + pin actions)
check_target "$REF" 1 || rc=1
# 2) the kit's OWN workflows (broadened in H4b): every actually-run workflow pins its actions
if [ -d "$KIT_WORKFLOWS" ]; then
  for wf in "$KIT_WORKFLOWS"/*.yml "$KIT_WORKFLOWS"/*.yaml; do
    [ -f "$wf" ] || continue
    check_target "$wf" 0 || rc=1
  done
fi
if [ "$rc" -eq 0 ]; then
  echo "OK: every uses: in the kit's own workflows + the canonical reference is SHA-pinned"
  exit 0
else
  echo "FAIL: a uses: is not SHA-pinned (see above)"
  exit 1
fi
