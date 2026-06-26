#!/bin/sh
# version-tag-coherent.sh — release coherence: VERSION must agree with the git tag state.
# (1) VERSION >= highest reachable semver tag; (2) HEAD tagged (semver) => VERSION == that tag.
# Catches a release whose VERSION bump was skipped (e.g. tag v3.49.0 on a VERSION=3.48.18 commit) —
# a gap badge-version (README<->VERSION only) cannot see. Threat model: HUMAN mistake, not agent
# attack (local tags acceptable). Offline (git only). Proves coherence, NOT that the right version was chosen.
# Exit: 0 PASS/NA · 1 FAIL · 2 UNVERIFIED (no git/not a repo) — escalates under CI/--require.
#   sh conformance/version-tag-coherent.sh [project-dir] [--require] | --selftest
set -eu
_here=$(CDPATH='' cd "$(dirname "$0")" && pwd)
. "$_here/version-helpers.sh"
REQUIRE="${REQUIRE:-0}"; [ -n "${CI:-}" ] && REQUIRE=1
DIR=.
for a in "$@"; do
  case "$a" in
    --require) REQUIRE=1 ;;
    --selftest) ;;
    -*) echo "usage: version-tag-coherent.sh [project-dir] [--require] | --selftest" >&2; exit 2 ;;
    *) DIR="$a" ;;
  esac
done
unverified() { printf 'UNVERIFIED: %s\n' "$1" >&2; [ "$REQUIRE" = "1" ] && exit 1; exit 2; }
check() {
  _d="$1"
  [ -f "$_d/VERSION" ] || { echo "version-tag-coherent: N/A — no VERSION file"; return 0; }
  _v=$(ver_norm "$(tr -d '[:space:]' < "$_d/VERSION" 2>/dev/null || true)")
  printf '%s' "$_v" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "version-tag-coherent: N/A — VERSION '$_v' not semver"; return 0; }
  ( cd "$_d" && git rev-parse --git-dir >/dev/null 2>&1 ) || {
    # Non-git tree: an adopter export (pre-adoption) is N/A; the KIT must be a git repo
    # (docs/ROADMAP-KIT.md present, export-ignored) -> escalate. Fail-closed; mirrors
    # feature-flags-wired.sh:49 (same kit-self anchor). Single-marker (ROADMAP-KIT.md only,
    # not the OR-of-two used by file-presence checks) because this check is git-state-scoped:
    # a no-git tree without the kit anchor has no tags to verify regardless.
    # N/A-skip (not carve): the check stays live for an adopter once they git init.
    [ -f "$_d/docs/ROADMAP-KIT.md" ] || { echo "version-tag-coherent: N/A — not a git repo (adopter export / pre-adoption)"; return 0; }
    unverified "not a git repo / git unavailable ($_d)"
  }
  _tags=$( cd "$_d" && git tag --merged HEAD 2>/dev/null | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' || true )
  if [ -z "$_tags" ]; then echo "version-tag-coherent: N/A — no reachable semver tags yet"; return 0; fi
  _hi=$(printf '%s\n' "$_tags" | sort -V | tail -1)
  if ver_gt "$_hi" "$_v"; then
    echo "FAIL: VERSION $_v is BEHIND the highest reachable tag v$_hi — a release tag must not exceed VERSION. Bump VERSION."
    return 1
  fi
  _headtags=$( cd "$_d" && git tag --points-at HEAD 2>/dev/null | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' || true )
  for _t in $_headtags; do
    if [ "$_t" != "$_v" ]; then
      echo "FAIL: HEAD is tagged v$_t but VERSION is $_v — a tagged release commit must declare its own version. Bump VERSION to $_t (or move the tag)."
      return 1
    fi
  done
  echo "version-tag-coherent: OK (VERSION $_v; highest reachable tag v$_hi; HEAD tags coherent)"
  return 0
}
if [ "${1:-}" = "--selftest" ]; then
  sf=0; _t=$(mktemp -d)
  _repo() { # <dir> <VERSION> ; inits a repo with one commit
    mkdir -p "$1"; printf '%s\n' "$2" > "$1/VERSION"
    ( cd "$1" && git init -q && git -c user.email=c@k -c user.name=c add -A \
      && git -c user.email=c@k -c user.name=c commit -q -m s ) >/dev/null 2>&1
  }
  _exp() { if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "version-tag-coherent --selftest: FAIL ($1: want rc $2 got $3)"; sf=1; fi; }
  # A. VERSION==HEAD tag → PASS(0)
  d="$_t/a"; _repo "$d" "1.0.0"; ( cd "$d" && git tag v1.0.0 ) >/dev/null 2>&1
  rc=0; ( REQUIRE=0; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "VERSION==HEAD tag" 0 "$rc"
  # B. seam: VERSION ahead, HEAD untagged, older tag reachable → PASS(0)
  d="$_t/b"; _repo "$d" "1.0.0"; ( cd "$d" && git tag v1.0.0 && printf '1.1.0\n' > VERSION && git -c user.email=c@k -c user.name=c commit -aqm bump ) >/dev/null 2>&1
  rc=0; ( REQUIRE=0; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "seam: VERSION ahead, HEAD untagged" 0 "$rc"
  # C. today's bug: HEAD tagged AHEAD of VERSION → FAIL(1)
  d="$_t/c"; _repo "$d" "3.48.18"; ( cd "$d" && git tag v3.49.0 ) >/dev/null 2>&1
  rc=0; ( REQUIRE=0; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "tag ahead of VERSION (the v3.49.0 bug)" 1 "$rc"
  # D. stale tag at a bumped HEAD: HEAD tagged BEHIND VERSION → FAIL(1)
  d="$_t/d"; _repo "$d" "2.0.0"; ( cd "$d" && git tag v1.0.0 ) >/dev/null 2>&1
  rc=0; ( REQUIRE=0; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "HEAD tagged behind VERSION" 1 "$rc"
  # E. no tags → N/A(0)
  d="$_t/e"; _repo "$d" "1.0.0"
  rc=0; ( REQUIRE=0; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "no tags = N/A" 0 "$rc"
  # F. not a git repo, NO ROADMAP-KIT.md (adopter export) → N/A(0) regardless of --require
  d="$_t/f"; mkdir -p "$d"; printf '1.0.0\n' > "$d/VERSION"
  rc=0; ( REQUIRE=0; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "no git + no ROADMAP (export) = N/A(0)" 0 "$rc"
  rc=0; ( REQUIRE=1; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "no git + no ROADMAP + --require = N/A(0)" 0 "$rc"
  # G. not a git repo but ROADMAP-KIT.md PRESENT (the KIT) → UNVERIFIED(2), escalates to FAIL(1) under --require
  d="$_t/g"; mkdir -p "$d/docs"; printf '1.0.0\n' > "$d/VERSION"; printf 'kit\n' > "$d/docs/ROADMAP-KIT.md"
  rc=0; ( REQUIRE=0; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "no git + ROADMAP (kit) = UNVERIFIED(2)" 2 "$rc"
  rc=0; ( REQUIRE=1; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "no git + ROADMAP + --require = FAIL(1)" 1 "$rc"
  rm -rf "$_t"
  [ "$sf" = 0 ] && { echo "version-tag-coherent --selftest: OK"; exit 0; } || exit 1
fi
check "$DIR"
