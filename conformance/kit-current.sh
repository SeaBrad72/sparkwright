#!/bin/sh
# kit-current.sh — P1.2/T7 SURFACING: is the kit this project ADOPTED behind the CURRENT release?
#
# THE DEFECT THIS EXISTS FOR (the kit's own recurring failure — its board calls it KW21): a capability
# that is built, conformance-checked, and INVISIBLE IN PRACTICE. P1.2 built an updater. An updater nobody
# is ever PROMPTED to run IS that failure, in its purest form: the adopter does not know they are behind,
# so they never run it, so the release they needed never reaches them. Shipping kit-update WITHOUT this is
# shipping the bug.
#
# So the surfacing is not a nicety bolted onto the updater — it is the half that makes the updater exist.
# This check answers ONE question, at a moment the adopter is already looking:
#
#     "your kit-base is v<OLD>; the current release is v<NEW> — run kit-update to see the delta."
#
# ── WHY THIS IS A DOCTOR/DRIFT CHECK AND NOT A PR GATE ────────────────────────────────────────────────
# The same constraint that shaped release-tagged.sh, board-drift.sh and mirror-current.sh, and it is the
# one that matters most here: BEING BEHIND IS NOT A DEFECT. A project pinned to last month's kit is fine
# — that is a choice, and often the right one. A PR gate that reddened on it would fire on the happy path
# of every adopter every week, and people would learn to ignore it. Then it is worth NOTHING when it
# fires for real. This is ADVISORY, and it is composed into `scripts/doctor.sh` (the adopter's posture
# report — the decision point they already visit) as a WARN-only dimension that can never fail their
# build. It informs a decision; it does not make one.
#
# AND THE OTHER HALF, WHICH IS EQUALLY LOAD-BEARING: an UP-TO-DATE ADOPTER IS NEVER NAGGED. A tool that
# cries wolf destroys the trust it exists to create. `current` prints one quiet OK line and exits 0.
#
#   sh conformance/kit-current.sh [--repo <path>] [--from <git-url|local-path>]
#   sh conformance/kit-current.sh --selftest
#
# Exit:  0 = CURRENT (or AHEAD) — nothing to say, and it says almost nothing
#        1 = BEHIND — the adopter is TOLD: v<OLD> -> v<NEW>, and the command that shows the delta
#        2 = UNVERIFIED — the release source could not be read (offline, unreachable, no release tags,
#            an unresolvable remote). N/A WITH A REASON. Never a pass, and NEVER a false "up to date":
#            absence of evidence is not evidence of currency.
#        3 = N/A — this is not an ADOPTED tree (no `kit-base`): the kit's own repo, a repo that never ran
#            incept, or an adoption that predates the kit-base mechanism. N/A WITH A REASON, never a
#            silent skip. Reached with NO NETWORK ACCESS AT ALL — it is decided before the source is
#            ever touched, so the kit's own CI and any offline tree land here for free.
#
# NOT REGISTERED IN conformance/verify.sh — deliberate, and the same call as mirror-current.sh /
# release-tagged.sh / board-drift.sh. verify.sh is the PR-time control set; a network-touching staleness
# check does not belong there (see "not a PR gate", above). HONEST CONSEQUENCE, named rather than
# glossed: it is therefore NOT reached by the non-vacuity mutation sweep (whose target_set is the
# verify.sh control set). Its teeth are the --selftest battery below (wired into ci.yml) plus HAND
# mutation-testing at authoring time — a weaker guarantee than the sweep, and named as such. The mutant
# witnessed RED at authoring is THE one that matters: a check that always answers "up to date" (the dead
# check) fails the `behind -> rc 1` case below.
#
# ── HONEST CEILING (read before trusting a green) ─────────────────────────────────────────────────────
#   * It compares VERSIONS, not TREES. It reads the version you adopted (kit-base:VERSION) against the
#     newest release TAG at the source. It does NOT fetch that release and does NOT compute the delta —
#     that is kit-update's job, and it is the thing this tells you to go and run. "OK" therefore means
#     "no NEWER RELEASE IS TAGGED at that source". It does not mean your tree is unmodified, and it does
#     not mean the kit's mirror is itself current (that is mirror-current.sh, on the kit's side).
#   * A source that publishes no tags is UNVERIFIED, not current.
#   * BEHIND is a fact, not a verdict. It never fails a build. Whether to move is the adopter's call.
#
# What it changes: nothing — read-only. Reads refs in the repo, and (only when it gets that far) runs
#                  `git ls-remote` against the release source. No clone, no fetch, no write, no forge API.
# Guardrails: ADVISORY — never gates. Fails CLOSED to UNVERIFIED (2) rather than guessing a remote or
#             reading an unreachable source as "current". The N/A path (3) requires no network. POSIX sh;
#             dash-clean.
set -eu
HERE=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)

PUBLISH_SCRIPT="scripts/publish-public.sh"

# ── THE RELEASE SOURCE ────────────────────────────────────────────────────────────────────────────────
# SINGLE SOURCE, exactly as mirror-current.sh does it: the kit's public URL is declared ONCE, in
# publish-public.sh. A second hardcoded copy here would be free to drift, and a staleness check pointed at
# the WRONG remote is worse than none — it would report a confident "up to date" about a repository nobody
# publishes to. So we READ it, and we FAIL CLOSED (UNVERIFIED) if it is not there. Never a guessed default.
# An ARGUMENT, never an env var: an adopter with their own mirror aims it explicitly, and the environment
# does not get to redirect a check at a decoy.
remote_default() {
  _ps="$HERE/$PUBLISH_SCRIPT"
  [ -f "$_ps" ] || { echo "  reason: $PUBLISH_SCRIPT is missing — there is no declaration of where the kit is published, and this refuses to guess one."; return 1; }
  _r=$(grep -E '^PUBLIC_REMOTE_DEFAULT=' "$_ps" | head -1 | sed "s/^[^=]*=//; s/^[\"']//; s/[\"'].*$//")
  case "$_r" in
    https://github.com/*/*.git) printf '%s\n' "$_r" ;;
    *)
      echo "  reason: PUBLIC_REMOTE_DEFAULT in $PUBLISH_SCRIPT is missing or malformed ('$_r'). Refusing to"
      echo "          guess: a staleness check aimed at the wrong repo would report a confident 'up to date'."
      return 1 ;;
  esac
}

# latest_release <src> — the newest release version tagged at <src>, via ls-remote (git protocol, NOT a
# forge API). Strips the peel suffix and the leading 'v'; ignores anything that is not a release tag (the
# adopter's own `kit-base/v*` tags, rc tags, branches). Empty output = nothing usable.
latest_release() {
  git ls-remote --tags -- "$1" 2>/dev/null \
    | sed 's|.*refs/tags/||; s|\^{}$||' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sed 's/^v//' \
    | sort -V | tail -1
}

# newer <a> <b> — is <b> STRICTLY newer than <a>?
newer() {
  [ "$1" != "$2" ] || return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]
}

# ══ THE CHECK ════════════════════════════════════════════════════════════════════════════════════════
# check <repo> <src-or-empty>
check() {
  _repo=$1; _src=${2:-}

  git -C "$_repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "kit-current: N/A — '$_repo' is not a git repository."
    echo "  reason: the version a project adopted is recorded as a git ref (the vendored 'kit-base'). With"
    echo "          no repository there is no record, and nothing to compare. Not a skip: there is no question."
    return 3
  }

  # ── THE N/A GATE — DECIDED FIRST, AND WITHOUT TOUCHING THE NETWORK ──────────────────────────────────
  # No kit-base = this is not an ADOPTED tree, and the question "are you behind?" is not merely
  # unanswerable, it is not even well-posed: there is no "the version you adopted". This is the path the
  # KIT'S OWN REPO takes (it was never incepted), and it is the path an offline/odd tree takes. It is
  # STATED, with the reason and the consequence — never a silent skip, and never a green that pretends
  # the check ran.
  if ! git -C "$_repo" rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1; then
    if [ -f "$_repo/ENGINEERING-PRINCIPLES.md" ]; then
      echo "kit-current: N/A — this project has NO 'kit-base' branch."
      echo "  reason: it is an incepted tree (ENGINEERING-PRINCIPLES.md is present), but it carries no record"
      echo "          of the tree it was adopted from — it was adopted BEFORE the kit-base mechanism, or the"
      echo "          branch was deleted. Staleness is therefore UNKNOWABLE here, and it is not assumed."
      echo "  consequence: kit-update cannot run either (it needs that merge base). See docs/operations/kit-base.md."
    else
      echo "kit-current: N/A — not an adopted tree (no 'kit-base' branch)."
      echo "  reason: this is the KIT ITSELF, or a repo that never ran incept. 'Which kit release did you"
      echo "          adopt?' has no answer here — the kit does not adopt itself. Nothing is checked, and"
      echo "          nothing is claimed."
    fi
    return 3
  fi

  # The version this project ADOPTED. It is a FACT, recorded at inception — never inferred.
  _old=$(git -C "$_repo" show kit-base:VERSION 2>/dev/null | tr -d '[:space:]') || _old=''
  if [ -z "$_old" ]; then
    echo "kit-current: UNVERIFIED — 'kit-base' exists but carries no readable VERSION."
    echo "  reason: the base cannot say which release it is. Refusing to guess: a wrong OLD would produce a"
    echo "          wrong verdict in EITHER direction — a false 'up to date', or a nag to move you nowhere."
    return 2
  fi

  # ── THE SOURCE — only NOW, after N/A is ruled out, is the network touched at all ─────────────────────
  if [ -z "$_src" ]; then
    _src=$(remote_default) || {
      echo "kit-current: UNVERIFIED — cannot resolve where the kit is published (see the reason above)."
      echo "  you adopted v$_old. Whether a newer release exists is UNKNOWN — it is NOT reported as 'up to date'."
      return 2
    }
  fi

  _new=$(latest_release "$_src")
  if [ -z "$_new" ]; then
    echo "kit-current: UNVERIFIED — could not read a release tag from the kit source."
    echo "    source: $_src"
    echo "  reason: it is unreachable (offline? no access?) or it publishes no release tags. Either way the"
    echo "          current release is UNKNOWN. Absence of evidence is NOT evidence of currency, so this is"
    echo "          NOT reported as 'up to date' — you adopted v$_old, and that is all that is known."
    return 2
  fi

  # ── THE ANSWER ──────────────────────────────────────────────────────────────────────────────────────
  if newer "$_old" "$_new"; then
    # THE SURFACING. Everything above exists to make these five lines trustworthy.
    echo "kit-current: BEHIND — your kit-base is v$_old; the current release is v$_new."
    echo "    source: $_src"
    echo "  This is NOT a failure and it does not gate anything: staying on v$_old is a legitimate choice."
    echo "  It is a fact you were owed, at a moment you were already looking."
    echo "  To SEE what moving would cost — the kit changes that apply cleanly, the ones that conflict with"
    echo "  your edits, and the files it will not touch — run kit-update. It REPORTS; it writes nothing:"
    echo "      sh scripts/kit-update.sh --from $_src"
    return 1
  fi

  # NOT BEHIND. Say it once, quietly, and get out of the way. (AHEAD is called out only because a silent
  # 'OK' there would be hiding something real — an adopter ahead of the published mirror is either the kit
  # maintainer or someone whose source is stale.)
  if newer "$_new" "$_old"; then
    echo "kit-current: OK — your kit-base is v$_old, AHEAD of the newest release at the source (v$_new). Nothing to offer."
  else
    echo "kit-current: OK — up to date (kit-base v$_old == the current release v$_new)."
  fi
  return 0
}

# ══ ORACLE — below the ^selftest() marker, so the mutation harness never neuters it. ══════════════════
selftest() {
  st=0
  t=$(mktemp -d) || return 2

  # A RELEASE SOURCE: a local git repo carrying release tags. `git ls-remote` reads a local path exactly
  # as it reads a URL — so the whole battery runs with NO NETWORK and NO CREDENTIALS.
  # NB: called with ZERO tags for the no-tags fixture. Do NOT "simplify" this to `for _tg in "$@"` with an
  # empty "" argument — `git tag ''` exits 128, and under `set -eu` that kills the whole selftest BEFORE it
  # prints a single line: rc 128, no output, and a CI step that fails for a reason nobody can see. (Found
  # the hard way, authoring this.)
  mk_release() {  # <dir> [tag...]
    _d=$1; shift
    mkdir -p "$_d"
    ( cd "$_d" && git init -q . && echo x > f && git add f \
        && git -c user.email=t@t -c user.name=t commit -qm r \
        && for _tg in "$@"; do git tag "$_tg" || exit 1; done ) >/dev/null 2>&1
  }
  # AN ADOPTER: a repo carrying the vendored ORPHAN kit-base with the VERSION it was adopted at — the same
  # shape conformance/kit-base.sh proves incept produces.
  mk_adopter() {  # <dir> <basever|__NOVERSION__>
    _d=$1; _v=$2
    mkdir -p "$_d"
    ( cd "$_d" && git init -q . && echo app > app.txt && git add app.txt \
        && git -c user.email=t@t -c user.name=t commit -qm head ) >/dev/null 2>&1
    _s=$(mktemp -d)
    if [ "$_v" = "__NOVERSION__" ]; then printf 'x\n' > "$_s/other"; else printf '%s\n' "$_v" > "$_s/VERSION"; fi
    _idx=$(mktemp) && rm -f "$_idx"
    _gd="$_d/.git"
    # -Af: force past any core.excludesFile on the runner, so the fixture is environment-independent.
    ( cd "$_s" && GIT_DIR="$_gd" GIT_INDEX_FILE="$_idx" GIT_WORK_TREE="$_s" git add -Af . ) >/dev/null 2>&1
    _tr=$(GIT_DIR="$_gd" GIT_INDEX_FILE="$_idx" git write-tree)
    _cm=$(GIT_DIR="$_gd" git -c user.email=t@t -c user.name=t commit-tree "$_tr" -m base)
    GIT_DIR="$_gd" git update-ref refs/heads/kit-base "$_cm"
    rm -f "$_idx"; rm -rf "$_s"
  }
  _case() {  # <label> <expected-rc> <repo> [src]
    check "$3" "${4:-}" >/dev/null 2>&1 && _got=0 || _got=$?
    if [ "$_got" -eq "$2" ]; then echo "PASS: selftest — $1 (rc $_got)"
    else echo "FAIL: selftest — $1 expected rc $2, got $_got"; st=1; fi
  }

  mk_release "$t/rel" v3.130.0 v3.135.0
  mk_release "$t/notags"
  mk_adopter "$t/behind"  3.130.0
  mk_adopter "$t/current" 3.135.0
  mk_adopter "$t/ahead"   3.140.0
  mk_adopter "$t/nover"   __NOVERSION__
  mkdir -p "$t/nobase" && ( cd "$t/nobase" && git init -q . ) >/dev/null 2>&1

  # ── THE LOAD-BEARING NEGATIVE. THE WHOLE POINT. An adopter behind the current release MUST be TOLD.
  # This is the case a DEAD CHECK — one that always answers "up to date" — cannot satisfy. If this ever
  # stops being rc 1, the updater is invisible again and KW21 has recurred.
  _case "adopter BEHIND the current release -> rc 1, TOLD (the anti-vacuity anchor)" 1 "$t/behind" "$t/rel"

  # ...and it must SAY BOTH VERSIONS AND NAME THE TOOL. A bare rc 1 is not a surfacing: the adopter has to
  # be able to act. (A check that reddened without saying WHAT to do would pass the rc assertion above.)
  _out=$(check "$t/behind" "$t/rel" 2>&1) || :
  if printf '%s' "$_out" | grep -q 'v3\.130\.0' && printf '%s' "$_out" | grep -q 'v3\.135\.0' \
     && printf '%s' "$_out" | grep -q 'kit-update.sh --from'; then
    echo "PASS: selftest — the BEHIND message names v<OLD>, v<NEW> and the exact kit-update command"
  else
    echo "FAIL: selftest — BEHIND reddened but did not tell the adopter the versions + what to run"; st=1
  fi

  # ── EQUALLY LOAD-BEARING: NO FALSE ALARM. A tool that cries wolf destroys the trust it exists to
  # create. An up-to-date adopter gets rc 0 and no scary word anywhere in the output.
  _case "adopter already at the current release -> rc 0, NOT nagged" 0 "$t/current" "$t/rel"
  _out=$(check "$t/current" "$t/rel" 2>&1) || :
  if printf '%s' "$_out" | grep -qi 'behind'; then
    echo "FAIL: selftest — an UP-TO-DATE adopter was told it was 'behind' (the check cries wolf)"; st=1
  else
    echo "PASS: selftest — an up-to-date adopter sees no 'behind' anywhere in the output (no wolf-crying)"
  fi

  # AHEAD (the maintainer, or a stale source) is not behind — and must not nag either.
  _case "adopter AHEAD of the source -> rc 0, no nag" 0 "$t/ahead" "$t/rel"

  # ── N/A WITH A REASON, never a silent skip and never a false green ──────────────────────────────────
  _case "no kit-base (the KIT'S OWN repo / never incepted) -> rc 3 N/A" 3 "$t/nobase" "$t/rel"
  _case "not a git repo at all -> rc 3 N/A" 3 "$t/definitely-not-a-repo-$$" "$t/rel"

  # ...and the N/A must be REASONED. An unexplained skip is indistinguishable from a check that quietly
  # did nothing — which is precisely the failure mode this whole slice exists to kill.
  _out=$(check "$t/nobase" "$t/rel" 2>&1) || :
  if printf '%s' "$_out" | grep -q 'N/A' && printf '%s' "$_out" | grep -q 'reason:'; then
    echo "PASS: selftest — the N/A states a REASON (not a silent skip)"
  else
    echo "FAIL: selftest — N/A was returned with no stated reason (a silent skip)"; st=1
  fi

  # THE REAL TREE, not a fixture: THIS repo (the kit itself) has no kit-base, so it MUST be N/A — and it
  # must get there WITHOUT A NETWORK. The src is a path that does not exist: if anything touched the
  # source before deciding N/A, this would come back 2, not 3. (Guards the ordering, which is the whole
  # reason the kit's own CI can run this offline.)
  _case "the KIT'S OWN repo + an unreachable source -> rc 3 N/A, decided with NO network" 3 "$HERE" "$t/nope"

  # ── UNVERIFIED, never a false 'up to date' ──────────────────────────────────────────────────────────
  # Absence of evidence is not evidence of currency. An adopter who cannot reach the source must NOT be
  # told they are current — that is the quiet lie that would make the whole tool worthless.
  _case "unreachable source (offline) -> rc 2 UNVERIFIED, NOT 0" 2 "$t/behind" "$t/no-such-repo"
  # Assert on the AFFIRMATIVE VERDICT SENTINEL ('kit-current: OK'), never on the loose phrase 'up to date'
  # — the UNVERIFIED message itself contains that phrase, in the sentence promising NOT to say it. Grepping
  # the phrase made this assertion fire on the correct behaviour (a false FAIL, found authoring this). The
  # lesson generalizes: match the verdict a check EMITS, not prose that happens to quote it.
  _out=$(check "$t/behind" "$t/no-such-repo" 2>&1) || :
  if printf '%s' "$_out" | grep -q 'kit-current: OK'; then
    echo "FAIL: selftest — an UNREACHABLE source emitted an OK verdict (a false green)"; st=1
  else
    echo "PASS: selftest — an unreachable source never emits an OK verdict"
  fi

  _case "source that publishes NO release tags -> rc 2 UNVERIFIED, not 'current'" 2 "$t/behind" "$t/notags"
  _case "kit-base with no readable VERSION -> rc 2 UNVERIFIED (refuses to guess OLD)" 2 "$t/nover" "$t/rel"

  # ── THE SINGLE-SOURCE RESOLVER — fail CLOSED, never a guessed remote ────────────────────────────────
  # (Run from a temp HERE whose publish-public.sh is missing/malformed: the resolver must refuse, and the
  # refusal must surface as UNVERIFIED — never as a default URL nobody publishes to.)
  mkdir -p "$t/nopub/scripts"
  if ( HERE="$t/nopub"; remote_default >/dev/null 2>&1 ); then
    echo "FAIL: selftest — the resolver INVENTED a remote when the single source was missing"; st=1
  else
    echo "PASS: selftest — missing PUBLIC_REMOTE_DEFAULT -> FAIL closed (no guessed remote)"
  fi
  mkdir -p "$t/badpub/scripts"
  printf 'PUBLIC_REMOTE_DEFAULT=https://github.com/a/b.git and junk\n' > "$t/badpub/scripts/publish-public.sh"
  if ( HERE="$t/badpub"; remote_default >/dev/null 2>&1 ); then
    echo "FAIL: selftest — the resolver accepted a MALFORMED remote (it would check the wrong repo)"; st=1
  else
    echo "PASS: selftest — malformed PUBLIC_REMOTE_DEFAULT -> FAIL closed"
  fi
  # ...and a WELL-FORMED one resolves (the liveness anchor for the resolver: if this fails, the two
  # negatives above are passing vacuously — everything would 'fail closed', including the good case).
  mkdir -p "$t/goodpub/scripts"
  printf 'PUBLIC_REMOTE_DEFAULT="https://github.com/a/b.git"  # the mirror\n' > "$t/goodpub/scripts/publish-public.sh"
  if [ "$( HERE="$t/goodpub"; remote_default 2>/dev/null )" = "https://github.com/a/b.git" ]; then
    echo "PASS: selftest — a well-formed PUBLIC_REMOTE_DEFAULT resolves (resolver liveness anchor)"
  else
    echo "FAIL: selftest — the resolver rejected a VALID remote (the negatives above are vacuous)"; st=1
  fi

  rm -rf "$t" 2>/dev/null || true
  if [ "$st" = 0 ]; then echo "kit-current --selftest: OK"; else echo "kit-current --selftest: FAIL" >&2; fi
  return "$st"
}

REPO=""; SRC=""
case "${1:-}" in
  --selftest) selftest; exit $? ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] && [ -n "$2" ] || { echo "kit-current: --repo requires a path" >&2; exit 2; }; REPO=$2; shift 2 ;;
    --from) [ $# -ge 2 ] && [ -n "$2" ] || { echo "kit-current: --from requires a git url or a local path" >&2; exit 2; }; SRC=$2; shift 2 ;;
    -h|--help) echo "usage: kit-current.sh [--repo <path>] [--from <git-url|local-path>] | --selftest"; exit 0 ;;
    *) echo "usage: kit-current.sh [--repo <path>] [--from <git-url|local-path>] | --selftest" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] || REPO=$PWD
check "$REPO" "$SRC"
