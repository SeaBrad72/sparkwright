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
#                  `git ls-remote` against the release source, from `/`, outside any repository (SWAS-680): this
#                  checkout's .git/config does not apply to that read. That authenticates nothing: a global git rule,
#                  an edited kit-base or scripts/publish-public.sh can still forge the answer. The one local read of the
#                  adopted VERSION runs with no network transport (GIT_ALLOW_PROTOCOL=none) and no lazy fetch. If / is itself a
#                  git repository, git -C / reads its config (not guarded here). A credential inside the source URL sits in argv
#                  while the read runs. No clone, no fetch, no write, no forge API.
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
#   The read runs from `/` (no repository, so ./.git/config does not apply: a planted core.sshCommand, url.*.insteadOf or credential helper cannot run or redirect it), with the
#   checkout's GIT_DIR family unset, no ext:: helper, and `--` before the source. It stays a pipeline that ends rc 0 and empty on failure: a `return 1` here would exit the caller's `set -eu` as rc 1, BEHIND.
_kc_git() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR GIT_TERMINAL_PROMPT=0 git -C / -c protocol.ext.allow=never "$@"; }
latest_release() {
  _kc_git ls-remote --tags -- "$1" 2>/dev/null \
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
  # SWAS-680: refs/heads/kit-base, the branch the gate above checked (a TAG named kit-base would win a bare name); GIT_ALLOW_PROTOCOL=none because a git without GIT_NO_LAZY_FETCH (Apple 2.39.5 honours it [M]; which releases lack it is unmeasured) would
  # lazy-fetch this blob of a planted partial clone over the checkout's own transport config (ssh, ext::, include.path); a healthy tree holds the blob locally and reads it.
  _old=$(GIT_ALLOW_PROTOCOL=none GIT_NO_LAZY_FETCH=1 GIT_NO_REPLACE_OBJECTS=1 git -C "$_repo" show refs/heads/kit-base:VERSION 2>/dev/null | tr -d '[:space:]') || _old=''
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
  else
    # A --from is classified before the read: a helper form (or one that starts with `-`) is UNVERIFIED rc 2, never BEHIND (the default URL needs none: remote_default holds it to https://github.com/*/*.git).
    _kind=$(sh "$HERE/scripts/preflight.sh" --url-kind "$_src" 2>/dev/null) || _kind=''
    if [ "$_kind" != remote ] && [ "$_kind" != local ]; then
      echo "kit-current: UNVERIFIED — the release source is not a form this reads (a remote-helper, an option-shaped value, or scripts/preflight.sh is not here to say)."
      echo "  reason: the source is read from outside this checkout and only as a network URL or a local path. Refusing to guess: it is NOT reported as 'up to date'."
      echo "  you adopted v$_old."
      return 2
    fi
    # The read runs from `/`, so a relative local path is made absolute first.
    if [ "$_kind" = local ] && [ -d "$_src" ]; then _src=$(CDPATH='' cd "$_src" && pwd -P) || _src=$2; fi
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
  unset GIT_SSH_COMMAND   # hermetic: an exported ssh command of the developer's shell must not move a cell (the cells that need one set it themselves)
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

  # ── SWAS-680: the release read runs from `/`, so this checkout's own config cannot run or redirect it ──
  # Method: the real check() from inside a planted repository; a plant script that appends to a canary; a POSITIVE CONTROL per cell (plain git fires the plant in that repo,
  # else the cell proves nothing); rc 2 asserted (the read was reached and failed), so a cell that exits early cannot pass on a zero canary. Config is set per cell, in a
  # hermetic HOME with no global or system config. The credential-helper cell is a stand-in (git credential fill), not ls-remote against a 401 listener.
  _kn=$t/canary; : > "$_kn"
  printf '#!/bin/sh\necho x >> "%s"\nexit 1\n' "$_kn" > "$t/plant.sh"; chmod 755 "$t/plant.sh"
  printf '#!/bin/sh\n[ "$1" = -G ] && exit 1\nshift\nPATH="$(git --exec-path):$PATH"; export PATH\nexec sh -c "$*"\n' > "$t/ssh-shim.sh"; chmod 755 "$t/ssh-shim.sh"
  _kh() { env -i PATH="$PATH" HOME="$t" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git "$@"; }
  _kc_n() { if [ -f "$_kn" ]; then wc -l < "$_kn" | tr -d ' '; else echo 0; fi; }
  _kx_env=:
  _kc_in() {  # <cwd> <repo> <src>: check() from <cwd>, hermetic HOME, plus the assignments in $_kx_env; sets _got
    _got=0
    ( cd "$1" && HOME=$t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null && export HOME GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL && eval "$_kx_env" && check "$2" "$3" ) >/dev/null 2>&1 || _got=$?
  }
  _kc_plant() {  # <label> <from> <key> <value> [<key> <value>]: a fresh planted adopter; the control must fire, then check() must not
    _kp_l=$1; _kp_from=$2; shift 2
    mk_adopter "$t/p-$_kp_l" 3.130.0
    while [ $# -ge 2 ]; do _kh -C "$t/p-$_kp_l" config "$1" "$2"; shift 2; done
    : > "$_kn"; ( cd "$t/p-$_kp_l" && _kh ls-remote --tags -- "$_kp_from" ) >/dev/null 2>&1 || true
    if [ "$(_kc_n)" -lt 1 ]; then echo "FAIL: selftest — plant $_kp_l: plain git did not fire the plant (the cell proves nothing)"; st=1; return 0; fi
    : > "$_kn"; _kc_in "$t/p-$_kp_l" "$t/p-$_kp_l" "$_kp_from"
    if [ "$(_kc_n)" = 0 ] && [ "$_got" -eq 2 ]; then echo "PASS: selftest — plant $_kp_l: the release read ran no planted program (canary 0, rc 2)"
    else echo "FAIL: selftest — plant $_kp_l: canary $(_kc_n), rc $_got (wanted canary 0 and rc 2)"; st=1; fi
  }
  _kc_plant sshcommand ssh://127.0.0.1:1/x core.sshCommand "$t/plant.sh"
  _kc_plant gitproxy git://127.0.0.1:1/x core.gitProxy "$t/plant.sh"
  _kc_plant ext "ext::$t/plant.sh" protocol.ext.allow always
  _kc_plant insteadof-ext http://127.0.0.1:1/ "url.ext::$t/plant.sh.insteadOf" http://127.0.0.1:1/ protocol.ext.allow always
  # the decoy rule: the checkout rewrites a closed-port URL to a repository holding the ADOPTED version's tag, so the planted read says "OK, up to date" (SWAS-679 measured rc 0 with the plant, rc 2 without)
  mkdir -p "$t/decoyd"; mk_release "$t/decoyd/k.git" v3.130.0
  mk_adopter "$t/p-decoy" 3.130.0; _kh -C "$t/p-decoy" config "url.$t/decoyd/.insteadOf" http://127.0.0.1:1/
  if [ "$( cd "$t/p-decoy" && _kh ls-remote --tags -- http://127.0.0.1:1/k.git 2>/dev/null | grep -c 'refs/tags/v3.130.0' )" -ge 1 ]; then
    _kc_in "$t/p-decoy" "$t/p-decoy" http://127.0.0.1:1/k.git
    if [ "$_got" -eq 2 ]; then echo "PASS: selftest — a url.*.insteadOf decoy in the checkout cannot yield 'OK, up to date' (rc 2)"
    else echo "FAIL: selftest — the decoy rule moved the verdict (rc $_got, wanted 2)"; st=1; fi
  else echo "FAIL: selftest — the decoy rule did not redirect plain git (the decoy cell proves nothing)"; st=1; fi
  # no-network: the real default URL, rewritten by plain git in a planted repo, comes back untouched through the shared helper
  _kc_real=$(remote_default 2>/dev/null) || _kc_real=https://github.com/a/b.git
  mk_adopter "$t/p-url" 3.130.0; _kh -C "$t/p-url" config "url.$t/decoyd/.insteadOf" "$_kc_real"
  _kc_ctl=$( cd "$t/p-url" && _kh ls-remote --get-url "$_kc_real" 2>/dev/null ) || _kc_ctl=''
  _kc_got=$( cd "$t/p-url" && HOME=$t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null && export HOME GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL && _kc_git ls-remote --get-url "$_kc_real" 2>/dev/null ) || _kc_got=''
  if [ "$_kc_ctl" = "$t/decoyd/" ] && [ "$_kc_got" = "$_kc_real" ]; then echo "PASS: selftest — a rule on the default URL rewrites it for plain git and not for the release read (no network)"
  else echo "FAIL: selftest — default-URL rewrite: control '$_kc_ctl', helper '$_kc_got'"; st=1; fi
  # a person's own GIT_DIR pointing at a planted repository is ignored by the read
  : > "$_kn"
  ( cd "$t" && HOME=$t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_DIR=$t/p-sshcommand/.git && export HOME GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_DIR && git ls-remote --tags -- ssh://127.0.0.1:1/x ) >/dev/null 2>&1 || true
  _kc_ctl=$(_kc_n); : > "$_kn"
  _kx_env="export GIT_DIR=$t/p-sshcommand/.git"; _kc_in "$t" "$t/p-sshcommand" ssh://127.0.0.1:1/x; _kx_env=:
  if [ "$_kc_ctl" -ge 1 ] && [ "$(_kc_n)" = 0 ] && [ "$_got" -eq 2 ]; then echo "PASS: selftest — a GIT_DIR in the environment does not send the release read into that repository"
  else echo "FAIL: selftest — GIT_DIR: control $_kc_ctl, canary $(_kc_n), rc $_got"; st=1; fi
  # the environment still applies: an ssh shim through GIT_SSH_COMMAND, and a GIT_CONFIG_COUNT rule (the sandbox's route), each read the release source
  _kx_env="export GIT_SSH_COMMAND=$t/ssh-shim.sh"; _kc_in "$t" "$t/behind" "ssh://fixture$t/rel"
  if [ "$_got" -eq 1 ]; then echo "PASS: selftest — GIT_SSH_COMMAND still applies (the read answered over ssh: BEHIND rc 1)"; else echo "FAIL: selftest — the ssh shim read gave rc $_got, wanted 1"; st=1; fi
  _kx_env="export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=url.$t/rel.insteadOf GIT_CONFIG_VALUE_0=http://127.0.0.1:1/x"; _kc_in "$t" "$t/behind" http://127.0.0.1:1/x; _kx_env=:
  if [ "$_got" -eq 1 ]; then echo "PASS: selftest — a GIT_CONFIG_COUNT rule still applies (BEHIND rc 1)"; else echo "FAIL: selftest — the GIT_CONFIG_COUNT read gave rc $_got, wanted 1"; st=1; fi
  # --from is classified first: a helper form or an option-shaped value is UNVERIFIED rc 2 (never BEHIND rc 1), and runs nothing
  : > "$_kn"
  _case "a remote-helper --from -> rc 2, not BEHIND" 2 "$t/behind" "ext::$t/plant.sh"
  _case "an option-shaped --from (--upload-pack) -> rc 2, not BEHIND" 2 "$t/behind" "--upload-pack=$t/plant.sh;:y"
  [ "$(_kc_n)" = 0 ] && echo "PASS: selftest — an option-shaped --from ran nothing (canary 0)" || { echo "FAIL: selftest — an option-shaped --from ran the plant"; st=1; }
  if [ "$(sh "$HERE/scripts/preflight.sh" --url-kind "--upload-pack=x;:y" 2>/dev/null)" = helper ] && [ "$(sh "$HERE/scripts/preflight.sh" --url-kind https://github.com/a/b.git 2>/dev/null)" = remote ]; then
    echo "PASS: selftest — preflight --url-kind says helper for a leading '-' and remote for https"; else echo "FAIL: selftest — preflight --url-kind"; st=1; fi
  _got=0; ( HERE="$t/nopub"; check "$t/behind" "$t/rel" >/dev/null 2>&1 ) || _got=$?
  if [ "$_got" -eq 2 ]; then echo "PASS: selftest — no scripts/preflight.sh to classify with -> rc 2 UNVERIFIED, not a read"; else echo "FAIL: selftest — a missing classifier gave rc $_got, wanted 2"; st=1; fi
  # a relative local --from is made absolute (the read runs from `/`)
  _got=0; ( cd "$t" && check "$t/behind" rel >/dev/null 2>&1 ) || _got=$?
  if [ "$_got" -eq 1 ]; then echo "PASS: selftest — a relative local --from still reads (BEHIND rc 1)"; else echo "FAIL: selftest — a relative --from gave rc $_got, wanted 1"; st=1; fi
  # the plants are LIVE through the real script: with the `-C /` cut from the shared read (a rewritten copy), the ssh plant fires and the decoy yields rc 0
  mkdir -p "$t/mut/conformance" "$t/mut/scripts"
  sed 's#git -C / -c#git -c#' "$0" > "$t/mut/conformance/kit-current.sh"
  if [ -f "$HERE/scripts/preflight.sh" ] && ! cmp -s "$0" "$t/mut/conformance/kit-current.sh"; then
    cp "$HERE/scripts/preflight.sh" "$t/mut/scripts/preflight.sh"
    : > "$_kn"; ( cd "$t/p-sshcommand" && HOME=$t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null && export HOME GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL && sh "$t/mut/conformance/kit-current.sh" --repo "$t/p-sshcommand" --from ssh://127.0.0.1:1/x ) >/dev/null 2>&1 || true
    if [ "$(_kc_n)" -ge 1 ]; then echo "PASS: selftest — mutant (read inside the checkout) fires the ssh plant: the plant is live"; else echo "FAIL: selftest — the mutant did not fire the ssh plant (the sshcommand cell is vacuous)"; st=1; fi
    _got=0; ( cd "$t/p-decoy" && HOME=$t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null && export HOME GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL && sh "$t/mut/conformance/kit-current.sh" --repo "$t/p-decoy" --from http://127.0.0.1:1/k.git ) >/dev/null 2>&1 || _got=$?
    if [ "$_got" -eq 0 ]; then echo "PASS: selftest — mutant (read inside the checkout) yields 'OK, up to date' from the decoy: the decoy is live"; else echo "FAIL: selftest — the mutant gave rc $_got on the decoy, wanted 0"; st=1; fi
  else echo "FAIL: selftest — the SWAS-680 mutant did not apply (no preflight here, or the sed matched nothing)"; st=1; fi

  # ── the local read of the adopted VERSION (round 1 of the review): no transport, no lazy fetch, no replace refs, and the BRANCH kit-base ──
  _kc_mut() {  # <name> <sed expr>: a rewritten COPY of this script (with the real preflight beside it) at $t/mut-<name>; rc 1 when the edit changed nothing
    mkdir -p "$t/mut-$1/conformance" "$t/mut-$1/scripts"; sed "$2" "$0" > "$t/mut-$1/conformance/kit-current.sh"
    cp "$HERE/scripts/preflight.sh" "$t/mut-$1/scripts/preflight.sh" 2>/dev/null || return 1
    ! cmp -s "$0" "$t/mut-$1/conformance/kit-current.sh"
  }
  _kc_runmut() {  # <name> <repo> <PATH or empty> [<--from src>]: the copy, in <repo>, hermetic; its rc in _got
    _got=0
    ( cd "$2" && HOME=$t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null && export HOME GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL && if [ -n "$3" ]; then PATH=$3; export PATH; fi && sh "$t/mut-$1/conformance/kit-current.sh" --repo "$2" ${4:+--from "$4"} ) >/dev/null 2>&1 || _got=$?
  }
  mkdir -p "$t/oldbin"; _kc_real=$(command -v git)
  printf '#!/bin/sh\nunset GIT_NO_LAZY_FETCH\nexec %s "$@"\n' "$_kc_real" > "$t/oldbin/git"; chmod 755 "$t/oldbin/git"
  _kc_oldpath="$t/oldbin:$(dirname "$_kc_real"):/usr/bin:/bin"
  # F1: a planted partial clone whose adopted-VERSION blob is absent locally. A read of it lazy-fetches over the checkout's own transport config (ext:: here) unless GIT_NO_LAZY_FETCH holds. A stand-in git
  # drops the variable (a git without it); a real /usr/bin/git row follows, gated on its own measured control. Apple 2.39.5 honours the variable [M]; which releases lack it is unmeasured.
  mk_adopter "$t/p-pc" 3.130.0
  _kc_oid=$(_kh -C "$t/p-pc" rev-parse refs/heads/kit-base:VERSION)
  rm -f "$t/p-pc/.git/objects/$(printf '%s' "$_kc_oid" | cut -c1-2)/$(printf '%s' "$_kc_oid" | cut -c3-)"
  _kh -C "$t/p-pc" config core.repositoryformatversion 1; _kh -C "$t/p-pc" config extensions.partialClone pl; _kh -C "$t/p-pc" config remote.pl.url "ext::$t/plant.sh"
  _kh -C "$t/p-pc" config remote.pl.promisor true; _kh -C "$t/p-pc" config remote.pl.partialclonefilter blob:none; _kh -C "$t/p-pc" config protocol.ext.allow always
  : > "$_kn"; ( cd "$t/p-pc" && _kh show refs/heads/kit-base:VERSION ) >/dev/null 2>&1 || true
  if [ "$(_kc_n)" -ge 1 ]; then
    : > "$_kn"; _kc_in "$t/p-pc" "$t/p-pc" ""; _kc_a=$_got; _kc_an=$(_kc_n)
    : > "$_kn"; _kx_env="export PATH=$_kc_oldpath"; _kc_in "$t/p-pc" "$t/p-pc" ""; _kx_env=:; _kc_b=$_got; _kc_bn=$(_kc_n)
    if [ "$_kc_an" = 0 ] && [ "$_kc_bn" = 0 ] && [ "$_kc_a" -eq 2 ] && [ "$_kc_b" -eq 2 ]; then echo "PASS: selftest — a planted partial clone with the VERSION blob absent fires nothing, on this git and on a stand-in git without GIT_NO_LAZY_FETCH (canary 0, rc 2)"
    else echo "FAIL: selftest — partial clone: canary $_kc_an/$_kc_bn, rc $_kc_a/$_kc_b (wanted 0/0 and 2/2)"; st=1; fi
    if _kc_mut noproto '/^  _old=/s/GIT_ALLOW_PROTOCOL=none //'; then
      : > "$_kn"; _kc_runmut noproto "$t/p-pc" "$_kc_oldpath"
      if [ "$(_kc_n)" -ge 1 ]; then echo "PASS: selftest — mutant (no GIT_ALLOW_PROTOCOL) on a stand-in git without the lazy-fetch belt fires the plant: the protocol belt is load-bearing"; else echo "FAIL: selftest — the no-protocol mutant did not fire the plant"; st=1; fi
    else echo "FAIL: selftest — the no-protocol mutant did not apply"; st=1; fi
    if _kc_mut nobelts '/^  _old=/s/GIT_ALLOW_PROTOCOL=none GIT_NO_LAZY_FETCH=1 //'; then
      : > "$_kn"; _kc_runmut nobelts "$t/p-pc" ""
      if [ "$(_kc_n)" -ge 1 ]; then echo "PASS: selftest — mutant (neither belt) fires the plant on this git: the plant is live through kit-current"; else echo "FAIL: selftest — the no-belt mutant did not fire the plant"; st=1; fi
    else echo "FAIL: selftest — the no-belt mutant did not apply"; st=1; fi
    # the REAL /usr/bin/git, when it is another git than the one above and runnable (a Mac without command-line tools gets a stub that opens an installer: not touched). Gated on the measured control, not a version.
    if [ "$_kc_real" != /usr/bin/git ] && [ -x /usr/bin/git ] && { [ "$(uname -s)" != Darwin ] || xcode-select -p >/dev/null 2>&1; }; then
      _kr='/usr/bin:/bin'; _krv=$(/usr/bin/git --version 2>/dev/null) || _krv=''
      : > "$_kn"; ( cd "$t/p-pc" && env -i PATH="$_kr" HOME="$t" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git show refs/heads/kit-base:VERSION ) >/dev/null 2>&1 || true; _kr0=$(_kc_n)
      : > "$_kn"; ( cd "$t/p-pc" && env -i PATH="$_kr" HOME="$t" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_LAZY_FETCH=1 git show refs/heads/kit-base:VERSION ) >/dev/null 2>&1 || true; _krb=$(_kc_n)
      if [ "$_kr0" -ge 1 ]; then
        : > "$_kn"; _kx_env="export PATH=$_kr"; _kc_in "$t/p-pc" "$t/p-pc" ""; _kx_env=:
        if [ "$(_kc_n)" = 0 ] && [ "$_got" -eq 2 ]; then echo "PASS: selftest — real /usr/bin/git ($_krv): a planted partial clone with the VERSION blob absent fires nothing (canary 0, rc 2)"; else echo "FAIL: selftest — real /usr/bin/git: canary $(_kc_n), rc $_got (wanted 0 and 2)"; st=1; fi
        : > "$_kn"; _kc_runmut noproto "$t/p-pc" "$_kr"
        if [ "$_krb" -ge 1 ]; then
          if [ "$(_kc_n)" -ge 1 ]; then echo "PASS: selftest — real /usr/bin/git ignores GIT_NO_LAZY_FETCH: the no-protocol mutant fires the plant (the protocol belt is load-bearing there)"; else echo "FAIL: selftest — real /usr/bin/git ignores the variable, yet the no-protocol mutant did not fire"; st=1; fi
        else
          if [ "$(_kc_n)" = 0 ]; then echo "PASS: selftest — real /usr/bin/git honours GIT_NO_LAZY_FETCH [M]: the no-protocol mutant fires nothing (the lazy-fetch belt holds there)"; else echo "FAIL: selftest — real /usr/bin/git honours the variable, yet the no-protocol mutant fired"; st=1; fi
        fi
        : > "$_kn"; _kc_runmut nobelts "$t/p-pc" "$_kr"
        if [ "$(_kc_n)" -ge 1 ]; then echo "PASS: selftest — real /usr/bin/git: the mutant with neither belt fires the plant (the plant is live on this git)"; else echo "FAIL: selftest — real /usr/bin/git: the no-belt mutant did not fire"; st=1; fi
      else echo "NOTE: selftest — real /usr/bin/git ($_krv): the plain read did not lazy-fetch, so its row is unrun"; fi
    else echo "NOTE: selftest — no separate runnable /usr/bin/git: the real-git row is unrun"; fi
  else echo "FAIL: selftest — plain git did not lazy-fetch the absent VERSION blob (the partial-clone cell proves nothing)"; st=1; fi
  # F3: a TAG named kit-base beats the bare name kit-base:VERSION; the gate above checks the branch, so the read must too
  mk_adopter "$t/p-tag" 3.130.0; mk_adopter "$t/tagsrc" 9.9.9
  _kh -C "$t/p-tag" fetch -q "$t/tagsrc" refs/heads/kit-base:refs/tags/kit-base >/dev/null 2>&1 || true
  if [ "$(_kh -C "$t/p-tag" show kit-base:VERSION 2>/dev/null | tr -d '[:space:]')" = 9.9.9 ]; then
    _kc_in "$t" "$t/p-tag" "$t/rel"
    if [ "$_got" -eq 1 ]; then echo "PASS: selftest — a tag named kit-base does not replace the branch's VERSION (BEHIND rc 1, not AHEAD)"; else echo "FAIL: selftest — a kit-base tag moved the verdict (rc $_got, wanted 1)"; st=1; fi
    if _kc_mut tagwins '/^  _old=/s#refs/heads/kit-base:VERSION#kit-base:VERSION#'; then
      _kc_runmut tagwins "$t/p-tag" "" "$t/rel"
      if [ "$_got" -eq 0 ]; then echo "PASS: selftest — mutant (bare kit-base name) lets the tag win: AHEAD rc 0, so the cell is live"; else echo "FAIL: selftest — the bare-name mutant gave rc $_got, wanted 0"; st=1; fi
    else echo "FAIL: selftest — the bare-name mutant did not apply"; st=1; fi
  else echo "FAIL: selftest — the fixture tag did not shadow the branch for plain git (the tag cell proves nothing)"; st=1; fi
  # F4: a replace ref on the VERSION blob must not change the adopted version
  mk_adopter "$t/p-rep" 3.130.0
  _kc_oid=$(_kh -C "$t/p-rep" rev-parse refs/heads/kit-base:VERSION); _kc_new=$(printf '9.9.9\n' | _kh -C "$t/p-rep" hash-object -w --stdin)
  _kh -C "$t/p-rep" replace "$_kc_oid" "$_kc_new" >/dev/null 2>&1 || true
  if [ "$(_kh -C "$t/p-rep" show refs/heads/kit-base:VERSION 2>/dev/null | tr -d '[:space:]')" = 9.9.9 ]; then
    _kc_in "$t" "$t/p-rep" "$t/rel"
    if [ "$_got" -eq 1 ]; then echo "PASS: selftest — a replace ref on the VERSION blob is not honoured (BEHIND rc 1)"; else echo "FAIL: selftest — a replace ref moved the verdict (rc $_got, wanted 1)"; st=1; fi
    if _kc_mut norepl '/^  _old=/s/GIT_NO_REPLACE_OBJECTS=1 //'; then
      _kc_runmut norepl "$t/p-rep" "" "$t/rel"
      if [ "$_got" -eq 0 ]; then echo "PASS: selftest — mutant (no GIT_NO_REPLACE_OBJECTS) honours the replace ref: AHEAD rc 0, so the cell is live"; else echo "FAIL: selftest — the replace mutant gave rc $_got, wanted 0"; st=1; fi
    else echo "FAIL: selftest — the replace mutant did not apply"; st=1; fi
  else echo "FAIL: selftest — the fixture replace ref did not change plain git's VERSION (the replace cell proves nothing)"; st=1; fi
  # the credential helper: a stand-in for the 401 a real ls-remote would meet (no listener here), `git credential fill` with no prompt. Plain git in the planted repo runs the helper; the release read's own git (from `/`) does not.
  mk_adopter "$t/p-cred" 3.130.0; _kh -C "$t/p-cred" config credential.helper "!$t/plant.sh"
  : > "$_kn"; ( cd "$t/p-cred" && printf 'protocol=https\nhost=x\n\n' | env -i PATH="$PATH" HOME="$t" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 git credential fill ) >/dev/null 2>&1 || true
  _kc_ctl=$(_kc_n); : > "$_kn"
  ( cd "$t/p-cred" && HOME=$t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null && export HOME GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL && printf 'protocol=https\nhost=x\n\n' | _kc_git credential fill ) >/dev/null 2>&1 || true
  if [ "$_kc_ctl" -ge 1 ] && [ "$(_kc_n)" = 0 ]; then echo "PASS: selftest — a planted credential.helper runs for plain git in the checkout and not through the release read's git (a stand-in for ls-remote, which needs a 401 listener)"
  else echo "FAIL: selftest — credential helper: control $_kc_ctl, through the helper git $(_kc_n)"; st=1; fi

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
