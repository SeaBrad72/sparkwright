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

# ── CP-10: RELEASE_SHA — the commit being released, resolved ONCE at invocation.
# WHY. `git tag <v>` tags HEAD *implicitly, at the moment it runs* — and ci_gate below polls for up to
# 10 minutes first. If HEAD moves during that poll (a checkout, a commit on another branch), the tag
# lands on whatever HEAD became. This is not hypothetical: on 2026-07-13 it put v3.129.0 on an UNMERGED
# feature branch, because the script was backgrounded for its CI poll while other git work continued.
# A HEAD-reading command that takes minutes to complete is a RACE. So: pin the SHA up front, thread it
# through every downstream step, and NEVER re-read HEAD after this point.
RELEASE_SHA=""

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

# ── CP-10: the on-branch gate. A release tag must point at a RELEASED commit.
#
# The existing ci_gate answers "is this commit GREEN?". It never asks "is this commit SHIPPED?" — and
# those are different questions. version-tag-coherent.sh does not close the gap either: it asserts
# VERSION matches a REACHABLE tag, which stayed GREEN the entire time v3.129.0 sat on an unmerged
# branch. The tag genuinely DID match VERSION. It was simply unreachable from main.
#
# default_branch -> the remote's default branch name (e.g. "main"); empty if unresolvable.
default_branch() {
  _db=$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null || true)
  if [ -n "$_db" ]; then printf '%s' "${_db#"$REMOTE"/}"; return 0; fi
  # Fallback: ask the remote directly (costs a round-trip; only on a clone with no origin/HEAD ref).
  git remote show "$REMOTE" 2>/dev/null | sed -n 's/.*HEAD branch: *//p' | head -1
}

# on_default_branch <sha> -> 0 = sha IS an ancestor of the default branch (released)
#                            1 = sha is NOT (an unmerged commit — refuse to tag it)
#                            2 = the default branch cannot be resolved (caller degrades OPEN)
on_default_branch() {
  _s=$1
  _db=$(default_branch)
  [ -n "$_db" ] || return 2
  _ref="$REMOTE/$_db"
  git rev-parse --verify --quiet "$_ref" >/dev/null 2>&1 || return 2
  git merge-base --is-ancestor "$_s" "$_ref" 2>/dev/null && return 0
  return 1
}

# branch_gate <sha> -> 0 = proceed, 1 = REFUSE. Mirrors ci_gate's posture exactly.
#
# DEGRADE-OPEN on an unresolvable default branch (rc 2), deliberately and out loud: this guard exists to
# catch an HONEST SLIP — the one that actually happened — not to defeat an adversary, who can always
# `git tag` by hand. A forge-neutral kit must not become untaggable on a host it cannot introspect (no
# remote, a detached CI checkout, a fork). The honest ceiling is STATED, never silent: it always says
# which branch it checked, or that it could not check.
branch_gate() {
  _s=$1
  set +e; on_default_branch "$_s"; _rc=$?; set -e
  case "$_rc" in
    0) echo "release-tag: $(git rev-parse --short "$_s") is on $REMOTE/$(default_branch) — released, safe to tag"; return 0 ;;
    1) echo "release-tag: REFUSING to tag $(git rev-parse --short "$_s") — it is NOT an ancestor of $REMOTE/$(default_branch)." >&2
       echo "release-tag: a release tag must point at a RELEASED commit; this one is unmerged. Merge it first." >&2
       return 1 ;;
    *) echo "release-tag: cannot resolve $REMOTE's default branch — SKIPPING the on-branch check (degrade-open)" >&2
       return 0 ;;
  esac
}

# ci_probe -> prints "<status>\t<conclusion>" for HEAD's main CI run; empty if unknown.
# Default: GitHub via gh. Overridable via RELEASE_TAG_CI_PROBE (a command) for tests / non-GitHub forges.
# SECURITY: RELEASE_TAG_CI_PROBE is eval'd via 'sh -c' - set it only from trusted CI config, never repo/PR input.
ci_probe() {
  if [ -n "${RELEASE_TAG_CI_PROBE:-}" ]; then
    sh -c "$RELEASE_TAG_CI_PROBE" 2>/dev/null || true
    return 0
  fi
  command -v gh >/dev/null 2>&1 || return 0
  # CP-10: probe the PINNED release sha, not a fresh HEAD read. Re-reading HEAD here would ask CI about
  # a commit we are not tagging — the same race, one level down. Fall back to HEAD only when unpinned
  # (a direct ci_probe call from a test).
  _sha=${RELEASE_SHA:-$(git rev-parse HEAD 2>/dev/null)} || return 0
  [ -n "$_sha" ] || return 0
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
  # PIN THE RELEASE COMMIT, ONCE, BEFORE ANYTHING SLOW RUNS. Every downstream step uses $RELEASE_SHA;
  # none re-reads HEAD. This is what makes the ceremony safe to run in the background: HEAD may move,
  # the release cannot.
  RELEASE_SHA=$(git rev-parse HEAD 2>/dev/null) || { echo "release-tag: cannot resolve HEAD" >&2; return 2; }

  out=$(decide) || return $?
  v=${out#TAG }
  case "$out" in
    NOOP*) echo "release-tag: $out"; return 0 ;;
    TAG*) : ;;
    *) echo "release-tag: unexpected decision: $out" >&2; return 2 ;;
  esac
  if [ "${1:-}" = "--dry-run" ]; then
    echo "release-tag: would create + push $v on $(git rev-parse --short "$RELEASE_SHA")"; return 0
  fi
  # CP-10: is it SHIPPED? (branch_gate)  ...then: is it GREEN? (ci_gate)
  # Ordered cheap-first on purpose: refusing an unmerged commit costs one local merge-base, so we do not
  # spend a 10-minute CI poll only to reject the commit afterwards.
  branch_gate "$RELEASE_SHA" || return 1
  ci_gate || return 1
  # Tag the PINNED sha explicitly — never a bare `git tag "$v"`, which re-reads HEAD at this instant.
  git tag "$v" "$RELEASE_SHA"
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

  # ===== CP-10 — the on-branch gate (a release tag must point at a RELEASED commit) ==========
  # ci_gate asks "is it GREEN?". branch_gate asks "is it SHIPPED?". Those are different questions, and
  # nothing asked the second one until v3.129.0 landed on an unmerged branch.
  #
  # _wt <dir>: a work repo with a real bare remote, main checked out, origin/HEAD set.
  _wt() {
    ( git init -q --bare "$1/origin.git"
      git clone -q "$1/origin.git" "$1/w"
      cd "$1/w"
      printf '1.0.0\n' > VERSION
      git -c user.email=c@k -c user.name=c add -A
      git -c user.email=c@k -c user.name=c commit -q -m s1
      git tag v1.0.0
      printf '1.1.0\n' > VERSION
      git -c user.email=c@k -c user.name=c add -A
      git -c user.email=c@k -c user.name=c commit -q -m s2
      git push -q origin HEAD:main
      git push -q origin v1.0.0
      git remote set-head origin main ) >/dev/null 2>&1
  }
  _bg_rc() { _x=0; ( cd "$1" && RELEASE_SHA=$(git rev-parse "$2"); branch_gate "$RELEASE_SHA" ) >/dev/null 2>&1 || _x=$?; echo $_x; }

  # I (TEETH — the whole point): a commit NOT on the default branch must be REFUSED, and NO TAG WRITTEN.
  #
  # ★ THIS TEST DRIVES THE REAL SCRIPT END-TO-END, NOT branch_gate DIRECTLY — and that distinction is
  # load-bearing. An earlier draft called branch_gate() directly. It proved the FUNCTION worked but not
  # that run() CALLED it: deleting the `branch_gate "$RELEASE_SHA"` line from run() left the selftest
  # GREEN. A vacuous test — it verified the artifact I wrote, not the property I wanted. Caught by
  # mutation. Assert on the OBSERVABLE OUTCOME (rc != 0 AND no tag exists), which no wiring bug survives.
  d="$t/i"; mkdir -p "$d"; _wt "$d"
  ( cd "$d/w" && git checkout -q -b feature/unmerged \
    && printf 'x\n' > f.txt \
    && git -c user.email=c@k -c user.name=c add -A \
    && git -c user.email=c@k -c user.name=c commit -q -m unmerged \
    && printf '1.2.0\n' > VERSION \
    && git -c user.email=c@k -c user.name=c add -A \
    && git -c user.email=c@k -c user.name=c commit -q -m bump ) >/dev/null 2>&1
  _irc=0
  ( cd "$d/w" && RELEASE_TAG_CI_PROBE='printf "completed\tsuccess\n"' sh "$here/release-tag.sh" ) >/dev/null 2>&1 || _irc=$?
  _itag=$( cd "$d/w" && git tag -l v1.2.0 )
  if [ "$_irc" != "0" ] && [ -z "$_itag" ]; then
    echo "PASS: an UNMERGED commit -> REFUSED, no tag written (the v3.129.0 defect)"
  else
    echo "FAIL: I — an unmerged commit was tagged (rc=$_irc tag='$_itag')"; st=1
  fi

  # J (LIVENESS — the anchor): a commit ON the default branch must be ACCEPTED, and the tag WRITTEN.
  # Without this, a gate that refuses EVERYTHING would pass test I and be worse than useless.
  # Also end-to-end, for the same reason.
  d="$t/j"; mkdir -p "$d"; _wt "$d"
  _jrc=0
  ( cd "$d/w" && RELEASE_TAG_CI_PROBE='printf "completed\tsuccess\n"' sh "$here/release-tag.sh" ) >/dev/null 2>&1 || _jrc=$?
  _jtag=$( cd "$d/w" && git tag -l v1.1.0 )
  if [ "$_jrc" = "0" ] && [ -n "$_jtag" ]; then
    echo "PASS: a RELEASED commit (on origin/main) -> tagged"
  else
    echo "FAIL: J — a released commit was refused (rc=$_jrc tag='$_jtag') — the gate refuses everything"; st=1
  fi

  # K: no resolvable default branch -> DEGRADE OPEN (rc 0), loudly. A forge-neutral kit must not become
  # untaggable on a host it cannot introspect. The ceiling is stated, not silent.
  d="$t/k"; _repo "$d" "1.1.0"     # a plain repo: no remote at all
  [ "$(_bg_rc "$d" HEAD)" = "0" ] \
    && echo "PASS: unresolvable default branch -> degrade-open (forge-neutral)" \
    || { echo "FAIL: K — degraded CLOSED; the kit is untaggable without a resolvable remote"; st=1; }

  # ===== CP-10 — the HEAD race (the mechanism that caused the defect) =======================
  # L (TEETH): HEAD moving DURING the CI poll must not change which commit gets tagged.
  # We reproduce the real bug: the CI probe (which runs inside ci_gate, mid-poll) commits a new commit,
  # moving HEAD — precisely what an unrelated `checkout -b` + `commit` did on 2026-07-13. The tag MUST
  # still land on the sha pinned at invocation. Before the fix, `git tag "$v"` tagged the NEW HEAD.
  d="$t/l"; mkdir -p "$d"; _wt "$d"
  _orig=$( cd "$d/w" && git rev-parse HEAD )
  _probe='printf "completed\tsuccess\n"; git -c user.email=c@k -c user.name=c commit -q --allow-empty -m "HEAD MOVED mid-poll" >/dev/null 2>&1'
  ( cd "$d/w" && RELEASE_TAG_CI_PROBE="$_probe" sh "$here/release-tag.sh" ) >/dev/null 2>&1 || true
  _tagged=$( cd "$d/w" && git rev-list -n1 v1.1.0 2>/dev/null || true )
  _now=$( cd "$d/w" && git rev-parse HEAD )
  if [ "$_tagged" = "$_orig" ] && [ "$_orig" != "$_now" ]; then
    echo "PASS: HEAD moved mid-poll; the tag stayed on the PINNED sha (race closed)"
  else
    echo "FAIL: L — the tag followed a moving HEAD (tagged=$_tagged orig=$_orig head=$_now)"; st=1
  fi

  rm -rf "$t"
  [ "$st" = 0 ] && { echo "release-tag --selftest: OK"; return 0; } || { echo "release-tag --selftest: FAIL"; return 1; }
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --dry-run)  run --dry-run; exit $? ;;
  "")         run; exit $? ;;
  *)          echo "usage: release-tag.sh [--dry-run|--selftest]" >&2; exit 2 ;;
esac
