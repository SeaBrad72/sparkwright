#!/bin/sh
# action-pinning.sh — assert every `uses:` is SHA-pinned across the kit's OWN workflows AND the
# WHOLE profile fleet (Slice 9j; broadened in H4b to the kit's own .github/workflows/; broadened
# in CP-7/K14 to every profiles/<stack>/ci.yml — not just typescript-node). K14 proved a
# single-profile check was a mask: the emitted SAST scans all 10 shipped ci.yml files, so an
# unpinned non-typescript profile reddened the adopter's first CI while this gate stayed green.
# Fail-closed: an empty fleet enumeration (no profiles found) is a FAIL, never a vacuous pass.
#   sh conformance/action-pinning.sh [--selftest]
# Exit: 0 = all SHA-pinned · 1 = a tag/branch-pinned uses: · 2 = bad usage. POSIX sh; dash-clean.
# INVARIANT: every profiles/<dir> is a pinnable profile shipping a ci.yml — a subdir without one FAILs
# by design (forces a new profile to ship a pinned CI). Shared/helper files live at profiles/<file>,
# NOT profiles/<dir>/ (e.g. profiles/ratification.yml, profiles/_TEMPLATE.md).
set -eu

REF_RATIFICATION="profiles/ratification.yml"  # CP-9 §13 gate; RATIFY-PARITY: the single stack-neutral source
KIT_WORKFLOWS=".github/workflows"                         # the workflows the kit itself runs

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

# check_fleet <root>: enumerate every <root>/<dir>/ci.yml (each a profile) and check it strictly
# (strict=1 — every profile MUST declare + pin actions; missing/unpinned = FAIL). Fail-closed:
# if the enumeration finds ZERO profile dirs, that is itself a FAIL ("no profiles found — cannot
# verify fleet pinning"), never a silent/vacuous pass. `find`, not a glob, so this stays correct
# under `set -eu` (no nullglob) and matches the sibling gates' enumeration convention.
check_fleet() {
  _root=$1; _ffail=0
  _profiles=$(find "$_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if [ -z "$_profiles" ]; then
    echo "FAIL: no profiles found under $_root — cannot verify fleet pinning"
    return 1
  fi
  for _p in $_profiles; do
    check_target "$_p/ci.yml" 1 || _ffail=1
  done
  return $_ffail
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

  # (a) fleet liveness anchor: >=2 profile-shaped dirs, each ci.yml fully SHA-pinned -> PASS.
  fa=$(mktemp -d)
  mkdir -p "$fa/alpha-lang" "$fa/beta-lang"
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@1111111111111111111111111111111111111111\n' > "$fa/alpha-lang/ci.yml"
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@2222222222222222222222222222222222222222\n' > "$fa/beta-lang/ci.yml"
  if check_fleet "$fa" >/dev/null 2>&1; then
    echo "PASS: selftest — fleet (a) liveness anchor: all-pinned fleet passes"
  else
    echo "FAIL: selftest — fleet (a) liveness anchor wrongly failed"; sfail=1
  fi

  # (b) THE load-bearing negative (beyond-typescript): same-shaped fleet, with a pinned
  # "typescript-node" dir alongside a non-typescript profile ("python") that carries a tag-pin.
  # Must FAIL, and the output must name that profile (its ci.yml path), proving the enumeration
  # reaches past typescript-node — exactly the K14 mask this closes.
  fb=$(mktemp -d)
  mkdir -p "$fb/typescript-node" "$fb/python"
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@3333333333333333333333333333333333333333\n' > "$fb/typescript-node/ci.yml"
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@v4\n' > "$fb/python/ci.yml"
  fb_out=$(check_fleet "$fb" 2>&1) && fb_rc=0 || fb_rc=1
  if [ "$fb_rc" -ne 0 ] && printf '%s' "$fb_out" | grep -q "python/ci.yml"; then
    echo "PASS: selftest — fleet (b) beyond-typescript negative: non-ts tag-pin caught and named"
  else
    echo "FAIL: selftest — fleet (b) beyond-typescript negative did not fire as designed"; sfail=1
  fi

  # (c) completeness negative (fail-closed): an empty fleet dir (no profile subdirs) must FAIL
  # with a "no profiles found" style message — never a silent pass.
  fc=$(mktemp -d)
  fc_out=$(check_fleet "$fc" 2>&1) && fc_rc=0 || fc_rc=1
  if [ "$fc_rc" -ne 0 ] && printf '%s' "$fc_out" | grep -q "no profiles found"; then
    echo "PASS: selftest — fleet (c) completeness negative: empty fleet fails closed"
  else
    echo "FAIL: selftest — fleet (c) completeness negative did not fail closed"; sfail=1
  fi

  [ "$sfail" -eq 0 ] && { echo "OK: action-pinning selftest"; exit 0; } || { echo "FAIL: action-pinning selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: action-pinning.sh [--selftest]" >&2; exit 2 ;;
esac

rc=0
# 1) the WHOLE profile fleet (K14 — strict: every profiles/<stack>/ci.yml must declare + pin
# actions; typescript-node is just one enumerated member, not special-cased). Fail-closed: zero
# profiles found is itself a FAIL (see check_fleet).
check_fleet "profiles" || rc=1
# 1b) CP-9: the ratification gate, which ships as its own workflow (it alone re-runs on
# pull_request_review). Strict: the adopter installs it verbatim, and it is the file that carries
# a `checks: write` token, so an unpinned action here is the worst place to have one.
check_target "$REF_RATIFICATION" 1 || rc=1
# 2) the kit's OWN workflows (broadened in H4b): every actually-run workflow pins its actions
if [ -d "$KIT_WORKFLOWS" ]; then
  for wf in "$KIT_WORKFLOWS"/*.yml "$KIT_WORKFLOWS"/*.yaml; do
    [ -f "$wf" ] || continue
    check_target "$wf" 0 || rc=1
  done
fi
if [ "$rc" -eq 0 ]; then
  echo "OK: every uses: in the kit's own workflows + the whole profile fleet is SHA-pinned"
  exit 0
else
  echo "FAIL: a uses: is not SHA-pinned (see above)"
  exit 1
fi
