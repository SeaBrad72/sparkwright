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
# What it changes: Creates and pushes the git tag v<VERSION> on HEAD; --dry-run decides and prints only (never tags/pushes).
# Guardrails: Idempotent no-op when the tag already exists; refuses a non-semver VERSION and a failed coherence check (won't tag a stale/dup); RELEASE_TAG_CI_PROBE is eval'd via `sh -c` — set it only from trusted CI config, never repo/PR input.
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

# ci_probe -> prints "<status>\t<conclusion>" for HEAD's main CI run; empty if unknown.
# Default: GitHub via gh. Overridable via RELEASE_TAG_CI_PROBE (a command) for tests / non-GitHub forges.
# SECURITY: RELEASE_TAG_CI_PROBE is eval'd via 'sh -c' - set it only from trusted CI config, never repo/PR input.
ci_probe() {
  if [ -n "${RELEASE_TAG_CI_PROBE:-}" ]; then
    sh -c "$RELEASE_TAG_CI_PROBE" 2>/dev/null || true
    return 0
  fi
  command -v gh >/dev/null 2>&1 || return 0
  _sha=$(git rev-parse HEAD 2>/dev/null) || return 0
  gh run list --commit "$_sha" --workflow CI --json status,conclusion \
    --jq '.[0] | .status + "\t" + (.conclusion // "")' 2>/dev/null || true
}

# ci_gate -> 0 = proceed (success OR degrade-open), 1 = refuse (definitive CI failure).
# Bounded poll: the tag fires while CI may still be in-progress, so wait (bounded) for a conclusion;
# refuse only on a definitive failure; degrade OPEN (warn + proceed) on no-signal / timeout (forge-neutral).
ci_gate() {
  _timeout=${RELEASE_TAG_CI_TIMEOUT:-600}
  _interval=${RELEASE_TAG_CI_INTERVAL:-15}
  if [ "$_interval" -lt 1 ]; then _interval=1; fi   # floor: never busy-loop on a 0 interval
  _elapsed=0
  while :; do
    _out=$(ci_probe)
    _status=$(printf '%s' "$_out" | cut -f1)
    _concl=$(printf '%s' "$_out" | cut -f2)
    if [ -z "$_out" ] || [ -z "$_status" ]; then
      echo "release-tag: CI status unavailable for HEAD (no gh / not GitHub / no run) - proceeding (degrade-open)" >&2
      return 0
    fi
    if [ "$_status" = "completed" ]; then
      case "$_concl" in
        success) return 0 ;;
        failure|cancelled|timed_out|startup_failure)
          echo "release-tag: main CI concluded '$_concl' for HEAD - refusing to tag a red commit" >&2
          return 1 ;;
        *) echo "release-tag: CI conclusion '$_concl' is not a clear pass - proceeding (degrade-open)" >&2
           return 0 ;;
      esac
    fi
    if [ "$_elapsed" -ge "$_timeout" ]; then
      echo "release-tag: main CI still '$_status' after ${_timeout}s - proceeding (degrade-open); re-run after CI concludes for the gate to bite" >&2
      return 0
    fi
    sleep "$_interval"
    _elapsed=$((_elapsed + _interval))
  done
}

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
  ci_gate || return 1
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
  # --- tag-time CI gate (injected probe, no network) ---
  _gate_rc() { _x=0; ( RELEASE_TAG_CI_PROBE="$1" RELEASE_TAG_CI_TIMEOUT="${2:-0}" RELEASE_TAG_CI_INTERVAL=1; ci_gate ) >/dev/null 2>&1 || _x=$?; echo $_x; }
  # E (teeth): definitive failure -> refuse (rc 1)
  [ "$(_gate_rc 'printf "completed\tfailure\n"')" = "1" ] && echo "PASS: CI failure -> refuse tag" || { echo "FAIL: E (CI-gate failure not refused)"; st=1; }
  # F: success -> proceed (rc 0)
  [ "$(_gate_rc 'printf "completed\tsuccess\n"')" = "0" ] && echo "PASS: CI success -> proceed" || { echo "FAIL: F"; st=1; }
  # G: in-progress + timeout 0 -> degrade-open proceed (rc 0)
  [ "$(_gate_rc 'printf "in_progress\t\n"' 0)" = "0" ] && echo "PASS: CI in-progress timeout -> proceed (degrade-open)" || { echo "FAIL: G"; st=1; }
  # H: no CI signal (empty probe) -> degrade-open proceed (rc 0)
  [ "$(_gate_rc 'true')" = "0" ] && echo "PASS: no CI signal -> proceed (degrade-open)" || { echo "FAIL: H"; st=1; }
  rm -rf "$t"
  [ "$st" = 0 ] && { echo "release-tag --selftest: OK"; return 0; } || { echo "release-tag --selftest: FAIL"; return 1; }
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --dry-run)  run --dry-run; exit $? ;;
  "")         run; exit $? ;;
  *)          echo "usage: release-tag.sh [--dry-run|--selftest]" >&2; exit 2 ;;
esac
