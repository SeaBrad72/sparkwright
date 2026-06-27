#!/bin/sh
# release-tag.sh — forge-neutral auto-tag-on-merge (the FLOOR). Reads VERSION, asserts release
# coherence INLINE, and creates+pushes v<VERSION> on HEAD if that tag doesn't already exist.
# Idempotent: no-op when the tag exists (VERSION unchanged / already released). Pure git — works
# on any forge; the CI trigger + push auth are the per-forge NATIVE binding (GitHub workflow /
# GitLab job / generic). Coherent BY CONSTRUCTION: it tags v<VERSION> on the commit whose VERSION
# file says that value, so a premature/incoherent tag is structurally impossible.
# Exit: 0 = tagged or no-op · 1 = coherence/precondition fail · 2 = bad usage/env.
#   release-tag.sh             # decide + tag + push (run in CI on main)
#   release-tag.sh --dry-run   # decide + print the action; never tags/pushes
#   release-tag.sh --selftest
set -eu
here=$(CDPATH='' cd "$(dirname "$0")" && pwd)
REMOTE="${RELEASE_TAG_REMOTE:-origin}"
COHERENCE="${RELEASE_TAG_COHERENCE:-$here/../conformance/version-tag-coherent.sh}"

# decide -> prints "TAG v<x>" or "NOOP <reason>" on stdout; rc 0 ok, 1 precondition fail, 2 usage.
decide() {
  [ -f VERSION ] || { echo "release-tag: no VERSION file in $(pwd)" >&2; return 2; }
  v=$(tr -d '[:space:]' < VERSION)
  printf '%s' "$v" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "release-tag: VERSION '$v' not semver" >&2; return 2; }
  # coherence backstop INLINE: VERSION must not be behind a reachable tag (don't tag a stale/dup).
  sh "$COHERENCE" . --require >/dev/null 2>&1 || { echo "release-tag: coherence check failed for VERSION $v" >&2; return 1; }
  # idempotency: already tagged? remote first (authoritative), then local.
  if git ls-remote --tags "$REMOTE" "v$v" 2>/dev/null | grep -Fq "refs/tags/v$v" \
     || git tag -l "v$v" 2>/dev/null | grep -qx "v$v"; then
    echo "NOOP v$v already tagged"; return 0
  fi
  echo "TAG v$v"; return 0
}

# on_remote V -> 0 if vV exists on the remote (authoritative), 1 otherwise
on_remote() { git ls-remote --tags "$REMOTE" "$1" 2>/dev/null | grep -Fq "refs/tags/$1"; }

run() {
  out=$(decide) || return $?
  v=${out#TAG }
  case "$out" in
    NOOP*) echo "release-tag: $out"; return 0 ;;
    TAG*) : ;;
    *) echo "release-tag: unexpected decision: $out" >&2; return 2 ;;
  esac
  if [ "${1:-}" = "--dry-run" ]; then
    echo "release-tag: would create + push $v on $(git rev-parse --short HEAD)"; return 0
  fi
  git tag "$v"
  if git push "$REMOTE" "$v"; then
    echo "release-tag: created + pushed $v"; return 0
  fi
  # push failed: a concurrent run may have pushed it (race) — that's fine; otherwise the local
  # tag is a poison pill (a future run would NOOP green with no remote tag), so roll it back + fail.
  git tag -d "$v" >/dev/null 2>&1 || true
  if on_remote "$v"; then
    echo "release-tag: $v already on remote (concurrent run) — ok"; return 0
  fi
  echo "release-tag: push of $v failed and it is NOT on the remote — rolled back local tag" >&2
  return 1
}

selftest() {
  st=0; t=$(mktemp -d)
  # _repo creates a single-commit repo with the given VERSION. Does NOT tag it.
  _repo() { mkdir -p "$1"; printf '%s\n' "$2" > "$1/VERSION"
    ( cd "$1" && git init -q && git -c user.email=c@k -c user.name=c add -A \
      && git -c user.email=c@k -c user.name=c commit -q -m s ) >/dev/null 2>&1; }
  _dry() { ( cd "$1" && sh "$here/release-tag.sh" --dry-run ) 2>/dev/null; }
  # _rc captures the exit code safely under set -eu (nonzero subshell would otherwise
  # trigger set -e exit before "echo $?" runs).
  _rc()  { _x=0; ( cd "$1" && sh "$here/release-tag.sh" --dry-run ) >/dev/null 2>&1 || _x=$?; echo $_x; }
  # A. VERSION ahead of reachable tag, v<VERSION> absent -> TAG
  # Two commits: v1.0.0 tagged on first commit, HEAD is second commit with VERSION=1.1.0.
  # (Single-commit setup fails: tagging v1.0.0 on HEAD with VERSION=1.1.0 violates coherence.)
  d="$t/a"
  ( mkdir -p "$d" && cd "$d" \
    && git init -q \
    && printf '1.0.0\n' > VERSION \
    && git -c user.email=c@k -c user.name=c add -A \
    && git -c user.email=c@k -c user.name=c commit -q -m s1 \
    && git tag v1.0.0 \
    && printf '1.1.0\n' > VERSION \
    && git -c user.email=c@k -c user.name=c add -A \
    && git -c user.email=c@k -c user.name=c commit -q -m s2 ) >/dev/null 2>&1
  case "$(_dry "$d")" in *"would create + push v1.1.0"*) echo "PASS: new version -> TAG";; *) echo "FAIL: A"; st=1;; esac
  # B. v<VERSION> already exists -> NOOP
  d="$t/b"; _repo "$d" "1.0.0"; ( cd "$d" && git tag v1.0.0 ) >/dev/null 2>&1
  case "$(_dry "$d")" in *"NOOP v1.0.0 already tagged"*) echo "PASS: existing tag -> NOOP";; *) echo "FAIL: B"; st=1;; esac
  # C. VERSION BEHIND a reachable tag -> coherence fail (rc 1), no tag
  d="$t/c"; _repo "$d" "1.0.0"; ( cd "$d" && git tag v2.0.0 ) >/dev/null 2>&1
  [ "$(_rc "$d")" = "1" ] && echo "PASS: VERSION behind tag -> rc 1" || { echo "FAIL: C"; st=1; }
  # D. non-semver VERSION -> rc 2
  d="$t/d"; _repo "$d" "not-a-version"
  [ "$(_rc "$d")" = "2" ] && echo "PASS: non-semver -> rc 2" || { echo "FAIL: D"; st=1; }
  rm -rf "$t"
  [ "$st" = 0 ] && { echo "release-tag --selftest: OK"; return 0; } || { echo "release-tag --selftest: FAIL"; return 1; }
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --dry-run)  run --dry-run; exit $? ;;
  "")         run; exit $? ;;
  *)          echo "usage: release-tag.sh [--dry-run|--selftest]" >&2; exit 2 ;;
esac
