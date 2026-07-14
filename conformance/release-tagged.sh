#!/bin/sh
# release-tagged.sh — CP-10 DETECT: the VERSION on the default branch must carry a matching, REACHABLE tag.
#
# THE DEFECT. Nothing forces a tag. `release-coherence.yml` only fires ON TAG PUSH — so an untagged
# release is not "red", it is INVISIBLE. v3.119.2 shipped untagged and was found only because a human went
# looking. The mirror failure is just as silent: on 2026-07-13, v3.129.0 was tagged on an UNMERGED feature
# branch — the tag existed, matched VERSION, and was unreachable from main.
#
# WHY THIS IS A CRON CHECK AND NOT A PR GATE — the constraint that shapes it:
#   A PR-time gate CANNOT enforce "this release is tagged", because THE TAG IS CREATED AFTER THE MERGE.
#   Any push-to-main check asking that question is RED on every merge until a human tags. A gate that
#   cries wolf on the happy path is worse than no gate: people learn to ignore it, and then it is
#   decorative. CP-10's own board row named this — "a gate that can only run once the behaviour it guards
#   has already happened."
#   => It belongs in drift-watch (the weekly cron), where the question is answerable and the answer means
#      something. Honest ceiling: up to 7 days to notice. Owner-accepted, and stated rather than hidden.
#
# Both directions are one query: does tag v<VERSION> exist AND point at a commit REACHABLE from the
# default branch? A missing tag fails; an unreachable tag fails. `version-tag-coherent.sh` catches
# NEITHER — it asserts VERSION matches a REACHABLE tag, which stayed green the whole time v3.129.0 sat on
# an unmerged branch, because the tag genuinely did match VERSION.
#
# What it changes: nothing (read-only). Guardrails: none needed.
#
# Usage:
#   sh conformance/release-tagged.sh [<dir>]   # 0 = tagged+reachable · 1 = DRIFT · 2 = cannot determine
#   sh conformance/release-tagged.sh --selftest
#
# NOT registered in conformance/verify.sh, deliberately: that battery is PORTABLE (adopters run it, and
# artifact-gate runs it on the INCEPTED export, which has no remote and no release history), so this would
# fire there for reasons that are not drift. Same call as verify-enforced-wired.sh and non-vacuity-wired.sh.
# CONSEQUENCE, stated honestly rather than glossed: it is therefore NOT reached by the non-vacuity mutation
# sweep (whose target_set is the verify.sh control set). Its teeth come from --selftest below, which is
# mutation-tested by hand at authoring time — a weaker guarantee than the sweep, and named as such.
set -eu

REMOTE="${RELEASE_TAGGED_REMOTE:-origin}"

# default_branch <dir> -> the remote's default branch name; empty if unresolvable.
default_branch() {
  _d=$1
  _db=$( cd "$_d" && git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null || true )
  if [ -n "$_db" ]; then printf '%s' "${_db#"$REMOTE"/}"; return 0; fi
  ( cd "$_d" && git remote show "$REMOTE" 2>/dev/null | sed -n 's/.*HEAD branch: *//p' | head -1 )
}

# check <dir> -> 0 OK · 1 DRIFT · 2 cannot determine.
#
# Exit 2 ("cannot determine") is NOT a pass. drift-watch treats any non-zero as red, deliberately: in the
# kit's OWN weekly cron, "I could not tell whether the release is tagged" is itself a finding. Never
# collapse it into a silent 0 — that is the green-while-dark failure this kit exists to prevent.
check() {
  _d=${1:-.}
  [ -d "$_d/.git" ] || { echo "UNVERIFIED: $_d is not a git repo" >&2; return 2; }
  [ -f "$_d/VERSION" ] || { echo "UNVERIFIED: no VERSION file in $_d" >&2; return 2; }

  _v=$( tr -d '[:space:]' < "$_d/VERSION" )
  printf '%s' "$_v" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || { echo "UNVERIFIED: VERSION '$_v' is not semver" >&2; return 2; }

  _db=$(default_branch "$_d")
  [ -n "$_db" ] || { echo "UNVERIFIED: cannot resolve $REMOTE's default branch" >&2; return 2; }
  _ref="$REMOTE/$_db"
  ( cd "$_d" && git rev-parse --verify --quiet "$_ref" >/dev/null 2>&1 ) \
    || { echo "UNVERIFIED: $_ref does not exist locally (did the checkout fetch it?)" >&2; return 2; }

  # The VERSION we judge is the one ON THE DEFAULT BRANCH — not the working tree's. A dirty local VERSION
  # (mid-slice) must not make the cron red, and a released VERSION must not be hidden by a local revert.
  _rv=$( cd "$_d" && git show "$_ref:VERSION" 2>/dev/null | tr -d '[:space:]' || true )
  [ -n "$_rv" ] || { echo "UNVERIFIED: cannot read VERSION from $_ref" >&2; return 2; }
  printf '%s' "$_rv" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || { echo "UNVERIFIED: VERSION '$_rv' on $_ref is not semver" >&2; return 2; }

  _tag="v$_rv"

  # (a) does the tag exist at all?  -> the v3.119.2 failure (shipped untagged)
  if ! ( cd "$_d" && git rev-parse --verify --quiet "refs/tags/$_tag" >/dev/null 2>&1 ); then
    echo "FAIL: $_ref declares VERSION $_rv but $_tag DOES NOT EXIST — the release was never tagged." >&2
    echo "      (release-coherence only fires on tag push, so an untagged release is invisible, not red.)" >&2
    return 1
  fi

  # (b) is the tag REACHABLE from the default branch?  -> the v3.129.0 failure (tagged off-main)
  _tsha=$( cd "$_d" && git rev-list -n1 "$_tag" 2>/dev/null || true )
  [ -n "$_tsha" ] || { echo "UNVERIFIED: cannot resolve $_tag to a commit" >&2; return 2; }
  if ! ( cd "$_d" && git merge-base --is-ancestor "$_tsha" "$_ref" 2>/dev/null ); then
    echo "FAIL: $_tag exists but is NOT reachable from $_ref — it is tagged on an UNMERGED commit." >&2
    echo "      (version-tag-coherent stays GREEN here: the tag does match VERSION. It is just unreleased.)" >&2
    return 1
  fi

  echo "OK: $_ref VERSION $_rv is tagged $_tag and reachable ($(cd "$_d" && git rev-parse --short "$_tsha"))"
  return 0
}

# ── selftest : the check must be LOAD-BEARING in BOTH directions. A detector that never fires certifies
#    the hole; a detector that always fires gets muted. Every fixture below is a real failure or a real
#    happy path.
selftest() {
  st=0; t=$(mktemp -d)

  # _fx <dir> <version> : a work repo with a real bare remote and a default branch.
  _fx() {
    ( git init -q --bare "$1/o.git"
      git clone -q "$1/o.git" "$1/w"
      cd "$1/w"
      printf '%s\n' "$2" > VERSION
      git -c user.email=c@k -c user.name=c add -A
      git -c user.email=c@k -c user.name=c commit -q -m rel
      git push -q origin HEAD:main
      git remote set-head origin main ) >/dev/null 2>&1
  }
  _rc() { _x=0; check "$1" >/dev/null 2>&1 || _x=$?; echo $_x; }

  # A (LIVENESS anchor): VERSION tagged AND reachable -> OK. Without this, a check that always FAILs
  # would pass every negative below and be worthless.
  d="$t/a"; mkdir -p "$d"; _fx "$d" "1.0.0"
  ( cd "$d/w" && git tag v1.0.0 && git push -q origin v1.0.0 ) >/dev/null 2>&1
  [ "$(_rc "$d/w")" = "0" ] && echo "PASS: tagged + reachable -> OK" \
    || { echo "FAIL: A — a correctly-tagged release was reported as drift"; st=1; }

  # B (TEETH — the v3.119.2 defect): VERSION on main, NO TAG -> DRIFT (rc 1).
  d="$t/b"; mkdir -p "$d"; _fx "$d" "1.0.0"
  [ "$(_rc "$d/w")" = "1" ] && echo "PASS: VERSION on main with NO TAG -> DRIFT (the v3.119.2 defect)" \
    || { echo "FAIL: B — an untagged release went undetected"; st=1; }

  # C (TEETH — the v3.129.0 defect): the tag EXISTS but is NOT reachable from main -> DRIFT (rc 1).
  # This is the one version-tag-coherent cannot see: the tag genuinely matches VERSION.
  d="$t/c"; mkdir -p "$d"; _fx "$d" "1.0.0"
  ( cd "$d/w" && git checkout -q -b unmerged \
    && git -c user.email=c@k -c user.name=c commit -q --allow-empty -m off-main \
    && git tag v1.0.0 ) >/dev/null 2>&1
  [ "$(_rc "$d/w")" = "1" ] && echo "PASS: tag on an UNMERGED commit -> DRIFT (the v3.129.0 defect)" \
    || { echo "FAIL: C — a tag on an unmerged commit went undetected"; st=1; }

  # D: judge the VERSION on the DEFAULT BRANCH, not the working tree. A dirty local bump mid-slice must
  # NOT make the cron red — main is still correctly tagged.
  d="$t/d"; mkdir -p "$d"; _fx "$d" "1.0.0"
  ( cd "$d/w" && git tag v1.0.0 && git push -q origin v1.0.0 && printf '9.9.9\n' > VERSION ) >/dev/null 2>&1
  [ "$(_rc "$d/w")" = "0" ] && echo "PASS: a dirty local VERSION does not fire (main is judged, not the worktree)" \
    || { echo "FAIL: D — an uncommitted local bump made the cron red"; st=1; }

  # E: no remote -> UNVERIFIED (rc 2). NOT a pass — "cannot determine" must never read as "fine".
  d="$t/e"; mkdir -p "$d/w"
  ( cd "$d/w" && git init -q && printf '1.0.0\n' > VERSION \
    && git -c user.email=c@k -c user.name=c add -A \
    && git -c user.email=c@k -c user.name=c commit -q -m s ) >/dev/null 2>&1
  [ "$(_rc "$d/w")" = "2" ] && echo "PASS: unresolvable default branch -> UNVERIFIED (rc 2), never a silent pass" \
    || { echo "FAIL: E — an undeterminable state was reported as OK (green-while-dark)"; st=1; }

  rm -rf "$t"
  [ "$st" = 0 ] && echo "release-tagged --selftest: OK" || { echo "release-tagged --selftest: FAIL" >&2; return 1; }
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check "${1:-.}"; exit $? ;;
esac
