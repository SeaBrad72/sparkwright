#!/bin/sh
# mirror-current.sh — P1.2-pre-b DETECT: the released VERSION on main must be PUBLISHED on the
# public mirror.
#
# THE DEFECT. Publication is a purely MANUAL maintainer act (ci.yml runs only
# `publish-public.sh --selftest`). So a release that is merged and tagged but never published is not
# "red" — it is INVISIBLE. On 2026-07-14 the mirror carried ONE commit and ONE tag (v3.122.0) while
# the kit was at 3.134.0: TWELVE releases, including EIGHT guard/control-plane commits (CP-9, CP-10,
# DRIFT-1, DRIFT-2), never published. Nothing reported it; it grew from 9 to 12 unnoticed. The
# staleness was not the defect — the SILENCE was.
#
# WHY THIS IS A CRON CHECK AND NOT A PR GATE — the same constraint that shaped release-tagged.sh:
#   Publication happens AFTER the merge and AFTER the tag. A PR-time gate asking "is this release
#   published?" is RED on EVERY merge until a human publishes. A gate that cries wolf on the happy
#   path is worse than no gate: people learn to ignore it, and then it is worth nothing when it
#   fires for real. This runs weekly in drift-watch.yml.
#
#   usage: sh conformance/mirror-current.sh [--selftest]
#   exit:  0 = the released VERSION is published on the mirror
#          1 = the mirror is BEHIND (or carries no tags at all)
#          2 = UNVERIFIED — the mirror could not be reached. NEVER a pass.
#
# HONEST CEILING (read before trusting a green):
#   - It proves a TAG EXISTS on the mirror. It does NOT prove the mirror's TREE equals the kit's
#     export at that version. That equality is verified by publish-public.sh AT PUBLISH TIME (its
#     own gate + sensitivity scan + gitleaks). This check answers exactly one question:
#     "did the publish ever happen?"
#   - Green means the mirror is CURRENT. It does not mean the mirror is GOOD.
#   - Detection, not automation. Publication stays human-commanded — it is the catastrophic,
#     irreversible act.
set -eu
cd "$(dirname "$0")/.."

PUBLISH_SCRIPT="scripts/publish-public.sh"

# SINGLE SOURCE. The mirror URL is declared exactly once, in publish-public.sh. A second hardcoded
# copy here would be free to drift, and a currency check pointed at the WRONG remote is worse than
# none — it would report a confident green about a repository nobody publishes to. So we READ it,
# and we FAIL CLOSED if it is not there (never fall back to a guessed default).
remote_default() {
  [ -f "$PUBLISH_SCRIPT" ] || { echo "FAIL: $PUBLISH_SCRIPT is missing — cannot resolve the mirror URL"; return 1; }
  # Strip a matched leading/trailing quote and anything after it (a trailing `# comment` or a stray
  # quote must NOT become part of the URL). dual review M2: a malformed value previously degraded to a
  # garbage URL -> ls-remote error -> exit 2 -> laundered to a pass by drift-watch. So VALIDATE the
  # result to an exact github https url and FAIL CLOSED (1) on anything else — never hand a
  # wrong-but-plausible remote downstream, and never a value starting with '-' (a git option).
  _r=$(grep -E '^PUBLIC_REMOTE_DEFAULT=' "$PUBLISH_SCRIPT" | head -1 | sed "s/^[^=]*=//; s/^[\"']//; s/[\"'].*$//")
  case "$_r" in
    https://github.com/*/*.git) printf '%s\n' "$_r" ;;
    *)
      echo "FAIL: PUBLIC_REMOTE_DEFAULT in $PUBLISH_SCRIPT is missing or not a github https .git url ('$_r')."
      echo "      Refusing to guess or trust a malformed remote: a currency check aimed at the wrong repo is"
      echo "      worse than no check — it would report a confident green about a repo nobody publishes to."
      return 1 ;;
  esac
}

# check <remote> <version>: is v<version> published on <remote>?
check() {
  _remote=$1; _version=$2; _tag="v$_version"

  # ls-remote against an unreachable/nonexistent remote must NOT read as "current". Absence of
  # evidence is not evidence of currency — surface it as UNVERIFIED (2), never as a pass.
  # `--` guards against a remote value that begins with '-' being parsed as a git option.
  if ! _tags=$(git ls-remote --tags -- "$_remote" 2>/dev/null); then
    echo "UNVERIFIED: could not reach the mirror ($_remote) — this is NOT a pass."
    return 2
  fi

  # A remote that answers with ZERO tags is not "current" — and this also catches an ls-remote that
  # exits 0 while returning nothing (the vacuous-green path).
  if [ -z "$_tags" ]; then
    echo "FAIL: the mirror ($_remote) carries NO tags at all — nothing has ever been published."
    return 1
  fi

  # FIXED-STRING match (dual review m1): $_tag is interpolated from VERSION and the dots are regex
  # wildcards under grep -E, so v3X135X0 would false-green a check built for v3.135.0. Strip the
  # peel-suffix (^{}) and the refs/tags/ prefix, then compare LITERALLY.
  if printf '%s\n' "$_tags" | sed 's|.*refs/tags/||; s|\^{}$||' | grep -qxF "$_tag"; then
    echo "mirror-current: OK — $_tag is published on the mirror"
    return 0
  fi

  _latest=$(printf '%s\n' "$_tags" | sed 's|.*refs/tags/||; s|\^{}$||' | sort -V | tail -1)
  echo "FAIL: the kit released $_tag but the mirror's latest published tag is '${_latest:-none}'."
  echo "      A tagged-but-unpublished release is invisible to every adopter. Publish it:"
  echo "        sh $PUBLISH_SCRIPT"
  return 1
}

selftest() {
  st=0
  base=$(mktemp -d)

  # Local git repos work as remotes for ls-remote — no network, no creds.
  mk_remote() {  # <dir> <tag-or-empty>
    mkdir -p "$1"
    ( cd "$1" && git init --quiet && git config user.email t@t && git config user.name t \
      && echo x > f && git add f && git commit --quiet -m x \
      && { [ -z "${2:-}" ] || git tag "$2"; } ) >/dev/null 2>&1
  }

  mk_remote "$base/current" v9.9.9
  mk_remote "$base/behind"  v0.0.1
  mk_remote "$base/notags"  ""

  if check "$base/current" 9.9.9 >/dev/null 2>&1; then
    echo "OK: mirror carrying the released tag -> GREEN"
  else
    echo "FAIL: selftest — a current mirror wrongly reddened"; st=1
  fi

  # LOAD-BEARING NEGATIVE: a mirror behind the kit MUST go RED. This is the whole point.
  if check "$base/behind" 9.9.9 >/dev/null 2>&1; then
    echo "FAIL: selftest — a mirror 1 release BEHIND passed (the check is dead)"; st=1
  else
    echo "OK: mirror behind the released VERSION -> RED"
  fi

  # A tagless mirror is not "current" — and must not pass vacuously.
  if check "$base/notags" 9.9.9 >/dev/null 2>&1; then
    echo "FAIL: selftest — a mirror with ZERO tags passed (vacuous green)"; st=1
  else
    echo "OK: mirror with no tags at all -> RED (no vacuous green)"
  fi

  # UNREACHABLE -> exit 2 (UNVERIFIED), NOT 0 and NOT 1. A network blip must never read as
  # "the mirror is current", and must be distinguishable from a real FAIL.
  check "$base/no-such-repo-$$" 9.9.9 >/dev/null 2>&1 && _rc=0 || _rc=$?
  if [ "$_rc" = 2 ]; then
    echo "OK: unreachable mirror -> exit 2 UNVERIFIED (never a pass)"
  else
    echo "FAIL: selftest — unreachable mirror returned $_rc, want 2 (absence of evidence != currency)"; st=1
  fi

  # SINGLE-SOURCE DRIFT: strip PUBLIC_REMOTE_DEFAULT and the resolver must FAIL CLOSED, never guess.
  _fake="$base/fake-publish.sh"
  printf '#!/bin/sh\necho no remote here\n' > "$_fake"
  if ( PUBLISH_SCRIPT="$_fake"; remote_default >/dev/null 2>&1 ); then
    echo "FAIL: selftest — remote_default invented a URL when the single source was missing"; st=1
  else
    echo "OK: missing PUBLIC_REMOTE_DEFAULT -> FAIL closed (no guessed remote)"
  fi

  # A well-quoted value with a trailing comment extracts CLEANLY (the sed stops at the closing quote):
  # it is a valid URL and must PASS resolution. This documents the boundary — only genuinely malformed
  # values fail, not benign trailing comments.
  _cmt="$base/cmt-publish.sh"
  printf 'PUBLIC_REMOTE_DEFAULT="https://github.com/a/b.git"  # the mirror\n' > "$_cmt"
  if ( PUBLISH_SCRIPT="$_cmt"; remote_default >/dev/null 2>&1 ); then
    echo "OK: quoted URL + trailing comment -> resolves cleanly (valid)"
  else
    echo "FAIL: selftest — a well-quoted URL with a trailing comment was wrongly rejected"; st=1
  fi

  # GARBAGE that survives extraction must FAIL CLOSED (rc 1), NOT degrade to a broken remote that
  # ls-remote errors on -> exit 2 -> laundered to a pass by drift-watch (dual review M2). An UNQUOTED
  # value with trailing junk is the real hazard: the strict https-*.git `case` is the backstop.
  _bad="$base/bad-publish.sh"
  printf 'PUBLIC_REMOTE_DEFAULT=https://github.com/a/b.git and more junk\n' > "$_bad"
  ( PUBLISH_SCRIPT="$_bad"; remote_default >/dev/null 2>&1 ) && _rc=0 || _rc=$?
  if [ "$_rc" = 1 ]; then
    echo "OK: garbage-tail PUBLIC_REMOTE_DEFAULT -> FAIL closed rc 1 (no laundered exit 2)"
  else
    echo "FAIL: selftest — garbage-tail remote returned $_rc, want 1 (structural fail, no broken URL)"; st=1
  fi

  # An SSH-form URL is not our https mirror form -> FAIL closed (mirror_slug parity; dual review m2).
  _ssh="$base/ssh-publish.sh"
  printf 'PUBLIC_REMOTE_DEFAULT="git@github.com:a/b.git"\n' > "$_ssh"
  if ( PUBLISH_SCRIPT="$_ssh"; remote_default >/dev/null 2>&1 ); then
    echo "FAIL: selftest — an ssh-form URL was accepted (should fail closed to https form)"; st=1
  else
    echo "OK: ssh-form URL -> FAIL closed (only the https mirror form is trusted)"
  fi

  if [ "$st" = 0 ]; then echo "mirror-current --selftest: OK (fixtures in $base)"; else echo "mirror-current --selftest: FAIL"; fi
  return "$st"
}

case "${1:-}" in
  --selftest) selftest ;;
  '')
    # KIT-ONLY (dual review finding 7): this checks the KIT OWNER's mirror. On an incepted adopter
    # tree it would network-probe a repo the adopter does not own and red on the owner's staleness.
    # Detected by the kit's own invariant (incept renames CLAUDE.md -> ENGINEERING-PRINCIPLES.md).
    if [ -f ENGINEERING-PRINCIPLES.md ]; then
      echo "mirror-current: N/A — incepted tree (this checks the KIT's own public mirror)"; exit 0
    fi
    _r=$(remote_default) || exit 1
    check "$_r" "$(cat VERSION)"
    ;;
  *) echo "usage: mirror-current.sh [--selftest]" >&2; exit 2 ;;
esac
