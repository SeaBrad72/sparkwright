#!/bin/sh
# obligation-lib.sh — the HITL obligation-trigger engine (sourced by per-obligation checks).
# What it changes: nothing at runtime — a sourced library of detector + record-check primitives.
# Detection: an obligation's own sensitive-surface globs over the change-set — NOT the control-plane
# path set. An obligation MAY additionally source guard-core's is_control_plane_path only when ITS
# surface IS the control-plane set; the threat obligation's surface is the secret/auth/payments/
# migrations set, a DIFFERENT set, so it does not (and must not) source guard-core.
# Fail-safe: a derive-FAILURE (no resolvable base / git error) or an uncertain surface -> require the record.
set -eu

# The substance floor for a record to count as "filled" (OBLIGATION-RECORD-FLOOR). CALIBRATED, not
# guessed — and the number that GOVERNS is the BANNER-STRIPPED count, not the template's raw one. A
# record that keeps its `> **Template.**` banner is rejected by Signal 1 by construction, so every
# genuine record is the template MINUS that line. Re-measured 2026-07-24 with the count that actually
# applies (`grep -v '^> \*\*Template\.\*\*' T | grep -c '[^[:space:]]'`): UAT-SIGNOFF 12 non-blank lines
# (the smallest, so the one that governs), A11Y-SIGNOFF 17, THREAT-MODEL 45. The RAW counts are 13/18/46
# and an earlier version of this comment cited those — overstating the true margin by a line. So 8 clears
# the smallest genuine record by 4 lines (no honestly-filled record reds) and sits well ABOVE the 1-3
# line stubs this floor exists to catch. Declared OUTSIDE any function on purpose: an externally-declared
# constant the code cannot satisfy by construction.
# WHAT PROVES WHAT (measured, because the first version of this note claimed more than it could):
#  - the two BOUNDARY legs in obl_selftest derive their fixtures FROM this constant, so they move with a
#    retune and CANNOT see one — at 7, 9 and 12 the whole suite stayed green. What they pin is the
#    COMPARISON (`-lt` vs `-le`), and they do kill that flip.
#  - the CALIBRATION leg is what pins the VALUE: it reds when a retune (or a trimmed template) puts the
#    floor above what a template-derived record can reach.
# (Not `=1`, so the non-vacuity sweep's accumulator mutation cannot flip it.)
OBL_MIN_SUBSTANCE_LINES=8

# The DEFAULT Signal-2 stub vocabulary (OBLIGATION-STUB-PATTERN) — THREAT-MODEL-TEMPLATE.md's own bracket
# tokens, which is where this anchor came from. It was HARDCODED inside obl_is_placeholder, so it was not
# the default but the ONLY option, and every OTHER obligation's template had to be authored to trip Signal 1
# instead. MEASURED on this tree: every one of the 4 distinct bracket tokens in UAT-SIGNOFF-TEMPLATE.md and
# all 9 in A11Y-SIGNOFF-TEMPLATE.md match Signal 1; THREAT-MODEL-TEMPLATE.md carries 17 matches of the
# pattern below.
# That workaround has already failed once. HITL-4 wrote the a11y tool-evidence cell as `[describe:` — with
# a COLON — and Signal 1's `describe ` alternative requires a TRAILING SPACE, so the cell was invisible to
# it (measured: the token does not match). At the time it was a REVIEW ROUND that caught it and no check
# could: one stub is below Signal 2's threshold of 3 and the record still clears the substance floor.
# Reproduced on this tree on the TRUE production path (real repo, KIT_OBL_TEST unset, the real wrapper):
# the shipped A11Y template, banner-stripped with every OTHER cell filled and that one token restored, is
# reported "PASS: a11y surface touched and a filled A11Y-SIGNOFF.md is present".
# TWO CORRECTIONS an earlier version of this note needed, both measured, because the arc "this failed ->
# therefore parameterise" implies more than it earns:
#  (a) THIS PARAMETER WOULD NOT HAVE CAUGHT THAT INSTANCE. On the exact `[describe:` reproduction, the
#      DEFAULT vocabulary and an a11y --stub-pattern BOTH read FILLED — one stub is below the threshold of
#      3 either way. What the parameter removes is the standing obligation to author every future template
#      to Signal 1's vocabulary, and what it catches is the >=3-cell case: with all 10 a11y tokens renamed
#      to `[attach: …]` the record reads FILLED on the default and PLACEHOLDER under an a11y pattern.
#  (b) A CHECK DOES COVER THE SINGLE-CELL CASE NOW — a11y-obligation.sh LEG 8 (per-cell: every stub filled
#      except one, once per stub line). NOT its LEG 7: the banner-delete leg leaves every cell raw, so the
#      other cells still trip Signal 1 and it stays green under single-cell drift (measured — a synthetic
#      template with one cell drifted to `[attach: …]` left LEG 7 green and red-ed LEG 8 on that line).
# Declared OUTSIDE any function alongside OBL_MIN_SUBSTANCE_LINES, and byte-identical to the expression it
# replaces, so making it a parameter cannot change today's verdicts. Callers override it with
# --stub-pattern; obl_selftest's (a) leg is the regression lock that the default still governs.
OBL_DEFAULT_STUB_PATTERN='\[(summary|threat|why|boundary [0-9]|planned/done|data, credentials|users, agents|auth, MFA|risk accepted|tracked items)'

# obl_changeset [--changed FILE]: newline-delimited changed paths. Modelled on promotion-readiness.sh's
# derivation. The two derivations have now CONVERGED — do not re-introduce a divergence without reading
# both notes:
#   (a) the derive-FAILURE-vs-empty-diff split (below) — promotion-readiness.sh adopted it in the T2
#       slice (its no-base branch used to be a WORKTREE-vs-HEAD diff, which one dirty ordinary file made
#       fail-OPEN); it now sets CHANGED_READ_FAIL when no base resolves, exactly as this does;
#   (b) UNQUOTED paths (see PATH QUOTING) — promotion-readiness.sh adopted `core.quotePath=false … -z`
#       in v3.184.0 (PROMOTION-PATH-QUOTING), so the note that used to say it "still uses the bare quoted
#       form" was stale from that release onward and is corrected here;
#   (c) `--no-renames` — this engine gained it in Slice B, promotion-readiness.sh in the T2 slice.
# ⚠️ NOTHING GRADES THESE TWO DERIVATIONS AS A SET. A class-wide scanner was built and withdrawn after it
# was defeated three times over three review rounds (boarded `CHANGESET-DERIVATION-LOCK`), so keeping the
# two convergent is a HUMAN obligation for now: if you change one derivation, change the other, and note
# that an argument reorder (`diff "$base"...HEAD --name-only -z`) silently drops `--no-renames` while
# looking harmless in review. That reorder is one of the measured evasions on the boarded row.
# The derive-FAILURE split:
#  - a valid base RESOLVES (merge-base HEAD origin/main, else HEAD main) and the diff is empty
#    -> empty change-set, OBL_DERIVE_FAIL stays 0 -> 'none'/N-A (correct: nothing changed);
#  - NO base resolves, OR any git step errors -> OBL_DERIVE_FAIL=1 so the caller fails CLOSED
#    (routes to 'uncertain' -> requires the record). We never collapse failure into empty via
#    `|| echo HEAD` / `|| true` (the old fail-open). This is promotion-readiness.sh's CHANGED_READ_FAIL
#    + its `CHANGED_READ_FAIL` fail-safe-to-highest-class (referenced BY NAME, never by line number — an
#    earlier numeric citation here drifted twice), applied to the diff-derivation path.
# shellcheck disable=SC2120 # obl_changeset exposes an optional --changed API that current callers don't
# use (they invoke it bare); the parameter is part of the engine's public surface. This also silences the
# paired SC2119 info at the no-arg call site (obl_changeset > "$cs").
obl_changeset() {
  OBL_DERIVE_FAIL=0
  if [ "${1:-}" = "--changed" ]; then cat "$2"; return 0; fi
  base="$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || true)"
  if [ -z "$base" ]; then OBL_DERIVE_FAIL=1; return 0; fi
  # PATH QUOTING (HITL-4 F1 — a silent fail-open on every obligation). Under git's default
  # core.quotePath=true a path with any non-ASCII byte is emitted WRAPPED IN DOUBLE QUOTES with octal
  # escapes ("web/Caf\303\251.tsx"). The trailing '"' defeats every EXTENSION surface glob (*.tsx,
  # *.html …) while directory globs still match (they are '*'-wrapped both sides), so `Café.tsx` derived
  # N/A where `Cafe.tsx` correctly FAILed — one accented character bypassed the gate. This is MONOTONE:
  # unquoting can only ever ADD matches, so no previously-triggering change-set can stop triggering.
  # WHICH PART IS PROVEN (measured, and an earlier version of this note had it BACKWARDS — see below):
  #   drop `core.quotePath=false` alone -> selftest SURVIVES
  #   drop `-z` alone                   -> selftest SURVIVES  (until the quote leg below; now KILLED)
  #   drop both                         -> KILLED by the non-ASCII leg
  # `-z` is the STRICTLY STRONGER control: NUL output is never quoted at all, whereas
  # `core.quotePath=false` only stops the non-ASCII octal escaping — it still quotes a path containing
  # `"`, `\`, a newline or a control byte. obl_selftest therefore carries TWO assertions: a non-ASCII
  # path (kills the both-dropped mutant) AND a quote-in-name path (kills the `-z`-dropped mutant, which
  # nothing else covers). Keep both, and do not "simplify" `-z` away: it is the half that matters.
  # RENAME DETECTION IS OFF (H1 — a silent fail-open on every obligation, and the bypass this slice exists
  # to close). `git diff --name-only` detects renames BY DEFAULT (diff.renames=true since git 2.9), and a
  # detected rename is reported as ONE entry emitting only the DESTINATION path. So a `git mv` in the same
  # PR removes the SOURCE path — the one carrying the sensitive/regulated token — from the change-set
  # entirely, and a triggering change derives N/A. MEASURED on the true production path before this flag:
  # an identical content edit to `svc2/pii/export.py` reported "FAIL … THREAT-MODEL.md is absent" (rc=1)
  # in place, and the SAME edit with a `git mv` to `svc2/core/export.py` (git scored it R098) reported
  # "N/A: no threat-model surface touched" (rc=0). Reproduced on the sensitive half (`git mv
  # src2/auth/login.js src2/gate/login.js`) and on a11y/uat. A PURE rename needs no content change at all.
  # `--no-renames` (a FLAG, so it also overrides a user's or a host's `diff.renames` config, which
  # `-c diff.renames=false` would not do any better and reads worse) un-collapses that entry back into the
  # `D`+`A` pair, so BOTH paths enter the change-set and a file moved OFF a sensitive path still triggers.
  # MONOTONE, and measured rather than argued — un-collapsing can only ADD the source path, never remove
  # one: across four real base/head pairs (this slice's own diff, and origin/main~40/~120/~400...origin/main
  # -> 16/151/377/997 paths), a sweep of the last 300 commits of this repo's history (the 2 that carry a
  # detected rename went 18->19 and 14->15 paths) and two synthetic rename repos (pure rename, and
  # rename+edit at R098, each 1->2), paths LOST = 0 in EVERY case and the only delta is the collapsed
  # source path being restored. So no previously-triggering change-set can stop triggering.
  # The cost is one extra path per rename in the change-set — the over-trigger direction, which is the
  # ratified fail-safe posture for every obligation this engine serves. obl_selftest's rename leg (with its
  # liveness pair, and its premise — that git collapses the move — PINNED in the fixture repo's own config
  # rather than inherited from the host, so the leg cannot go vacuous) is what holds the flag in place.
  # A temp file, not a pipe: `git … | tr` would make the pipeline's status `tr`'s, silently discarding the
  # derive-FAILURE signal this whole function exists to preserve. POSIX sh has no PIPESTATUS.
  _z="$(mktemp 2>/dev/null)" || { OBL_DERIVE_FAIL=1; return 0; }
  if git -c core.quotePath=false diff --name-only -z --no-renames "$base"...HEAD > "$_z" 2>/dev/null; then
    # NEWLINE-IN-FILENAME -> DERIVE FAILURE (fail-closed), mirroring promotion-readiness.sh. `tr '\0' '\n'`
    # SPLITS a path containing a literal newline into fragments that are then matched separately, so a
    # surface glob can miss both halves (`svc/pii<newline>/export.py` matches no `*pii*` segment rule).
    # POSIX sh cannot PRESERVE such a path, but the NUL stream carries a newline byte only when a filename
    # does — so detect it and require the record rather than silently under-triggering the obligation.
    if [ "$(LC_ALL=C tr -cd '\n' < "$_z" | wc -c | tr -d ' ')" != 0 ]; then
      OBL_DERIVE_FAIL=1
    else
      # tr's status is CAPTURED, not discarded: a bare `tr … < "$_z"` under `set -e` aborts the whole
      # check with no NOTE, no FAIL text and a LEAKED temp file (measured). Fail closed, loudly, and clean up.
      tr '\0' '\n' < "$_z" || OBL_DERIVE_FAIL=1
    fi
  else
    OBL_DERIVE_FAIL=1
  fi
  rm -f "$_z"
  return 0
}

# The alternation separator, held in a VARIABLE rather than written as a literal `|` inside the parameter
# expansions below. That is not style: it is what makes this file PARSEABLE by the SAST gate — see the
# measurement block on _obl_glob_scan. Declared outside any function alongside the other constants.
OBL_GLOB_SEP='|'

# _obl_glob_scan PATH LIST -> 0 iff PATH matches one of LIST's '|'-separated globs.
# THE ENGINE'S ONE SPLITTER. Every place that has to interpret a glob alternation goes through it — the
# surface match, the exclusion match, and obligation_gate's "does this surface define a usable glob at
# all" test — so those three can never drift apart. It also publishes, for the caller that wants the
# LIST's properties rather than a match:
#   OBL_GLOBS_SEEN      the number of NON-BLANK globs examined (incremented BEFORE the match test, so an
#                       early return can never leave it at 0 when a glob did match);
#   OBL_GLOBS_UNIVERSAL 1 if any glob examined matches EVERY path.
# Both are reset on entry. The property caller scans with the EMPTY path, and that is what makes the early
# return safe for OBL_GLOBS_UNIVERSAL: a glob can match the empty string only if it is built entirely from
# '*', and such a glob is universal — so the walk can never stop before a universal glob has been seen.
#
# NO `IFS` AND NO `set -f`. The previous form split with `_oldifs=$IFS; IFS='|'; set -f` … `IFS=$_oldifs;
# set +f`. This rewrite is PREVENTIVE — it fixes no red that exists today — and the reason is a MEASURED
# one, which is NOT the reason first proposed for it. `semgrep --config p/default --error
# conformance/obligation-lib.sh` reported 0 findings before this change, and the honest explanation is
# worse than "the rule tolerates the save/restore form":
#   - the rule does NOT tolerate it. The same function with its one-line `case "$p" in $_g) … ;; esac`
#     merely SPLIT ACROSS LINES scores 3 bash.lang.security.ifs-tampering findings (measured, this build).
#   - the old green was an artifact of the PARSER. semgrep's bash grammar cannot parse a `case` whose
#     first clause starts on the `case … in` line (isolated and measured: the one-line form raises a
#     syntax error, the identical multi-line form parses at 100%). It raised that error at obl_detect and
#     skipped the whole function, so the engine every obligation depends on was never scanned at all —
#     `Parsed lines: ~11.5%` for the file. Any cosmetic reformat of that `case` would have turned the
#     kit's own emitted-artifact SAST gate (`artifact-gate`) red with no semantic change whatsoever.
# Two rules follow from that measurement and both are load-bearing here: every `case` clause starts on its
# own line, and the separator is a variable (`${x%%"$OBL_GLOB_SEP"*}` parses; `${x%%|*}` does not —
# measured, same isolation). After this rewrite the file parses and its 0 findings are a real 0.
# `set -f` has nothing left to protect: the only unquoted expansion remaining is `$_gs_one` as a `case`
# PATTERN, and a case pattern is glob-MATCHED, never pathname-expanded. VERIFIED for this build rather
# than assumed — with `zzz.txt` in the cwd, `_g='*.txt'; case "sub/other.txt" in $_g)` MATCHES under sh,
# dash and bash both with and without `set -f`, while `for w in $_g` in that same cwd yields `zzz.txt`.
# It was the `for` over an unquoted expansion that needed `-f`, and the `for` is gone.
# THE COST, MEASURED AND ACCEPTED — recorded rather than optimised, so a future reader does not have to
# rediscover it. Re-slicing the list string per path is ~13x slower than the retired `IFS`/`set -f`/`for`
# form: 5001 paths against the real 49-glob a11y surface, worst case (no match), measured this build —
# 1.76s vs 0.13s under dash (CI's shell) and 7.43s vs 0.64s under sh. NOT worth reverting for, on two
# grounds: a real PR on this repo is ~11 changed files, which measures 0.01s, so the gate is nowhere near
# this path; and the parseability the rewrite buys is what lets the SAST gate scan this engine AT ALL
# (11.5% -> 100% parsed, see above), which is a correctness property and not a performance trade. If an
# adopter with a very large diff ever does hit it, the optimisation is to split the list ONCE into a
# positional list and reuse it across obl_detect's per-path loop — NOT to bring `IFS` and `set -f` back.
_obl_glob_scan() {
  _gs_p="$1"; _gs_rest="$2"; OBL_GLOBS_SEEN=0; OBL_GLOBS_UNIVERSAL=0
  while [ -n "$_gs_rest" ]; do
    # Split off the head field. When no separator remains the head IS the rest, which is the loop's
    # termination condition. A TRAILING separator does NOT yield a blank final field — an earlier version
    # of this comment said it did, and the behaviour it describes is right for the wrong reason. On `a|`
    # the first iteration takes `a` and sets the remainder to the empty string, so `[ -n "$_gs_rest" ]`
    # ends the loop and a second iteration never runs at all (MEASURED under sh and dash: exactly one
    # iteration, not two). Same outcome either way — no infinite loop and no stray empty glob — but the
    # mechanism is the REMAINDER emptying, not a blank field being produced and then skipped by the
    # blank-field guard below. That guard is for a LEADING or a DOUBLED separator, which do produce one
    # (measured: `a||b` -> 3 fields, the middle blank; `|a` -> 2 fields, the first blank).
    _gs_one="${_gs_rest%%"$OBL_GLOB_SEP"*}"
    if [ "$_gs_one" = "$_gs_rest" ]; then
      _gs_rest=""
    else
      _gs_rest="${_gs_rest#*"$OBL_GLOB_SEP"}"
    fi
    # A BLANK field is not a glob — it is a stray separator or padding. Skipping it is what makes
    # OBL_GLOBS_SEEN a count of USABLE globs, and it keeps an empty pattern out of the `case` below.
    case "$_gs_one" in
      *[![:space:]]*) ;;
      *) continue ;;
    esac
    OBL_GLOBS_SEEN=$((OBL_GLOBS_SEEN + 1))
    # UNIVERSAL-GLOB TEST, exact rather than heuristic: a glob built only from '*' and '?' with at least
    # one '*' matches every string of length >= its number of '?', and a path is never empty. Anything
    # that NAMES a character (every real glob does: *auth*, *.conf.j2) falls into the first clause.
    case "$_gs_one" in
      *[!*?]*) ;;
      *'*'*) OBL_GLOBS_UNIVERSAL=1 ;;
    esac
    # shellcheck disable=SC2254 # the unquoted $_gs_one IS the matching mechanism — each glob (e.g.
    # *auth*) must be used as a case-PATTERN, not matched literally.
    case "$_gs_p" in
      $_gs_one) return 0 ;;
    esac
  done
  return 1
}

# obl_detect GLOBS CHANGED_FILE [FORCE] [EXCLUDE_GLOBS] -> prints triggered|none|uncertain
# The uncertain band + fail-safe: --force-uncertain (a real derive-failure, or a simulated ambiguous
# surface) routes straight to 'uncertain', which the gate treats as "require the record". It is tested
# FIRST, so no list can talk the engine out of the fail-safe.
# ARITY (a contract-shape change — every caller was re-grepped, not just the one being edited):
# EXCLUDE_GLOBS is a FOURTH positional, APPENDED rather than inserted, so every existing 2- and 3-argument
# call keeps its meaning. FORCE is '--force-uncertain' or the empty string.
# EXCLUSIONS ARE EVALUATED FIRST (OBLIGATION-CONFIG-TEMPLATE-EXT). An obligation that detects by markup
# EXTENSION cannot distinguish a view template from a CONFIG template borrowing the same extension —
# Ansible/Chef write roles/nginx/templates/nginx.conf.j2 and app.conf.erb — so a11y demanded a WCAG
# sign-off for an nginx config. Skipping an excluded path BEFORE any surface glob is tested makes an
# exclusion a statement about the PATH ("this is not a UI file"), never a hole in the surface.
# THE TWO DIRECTIONS ARE DELIBERATELY ASYMMETRIC, because an exclusion list is an OFF-SWITCH:
#  - an EMPTY or blank-only exclusion list excludes NOTHING. That is the stricter direction, so it needs
#    no refusal — unlike an empty --surface-globs, which reads as a blanket N/A.
#  - a glob that matches EVERY path would switch the whole surface off, so obligation_gate refuses one
#    before this function is ever reached.
obl_detect() {
  _globs="$1"; _changed="$2"; _force="${3:-}"; _excl="${4:-}"
  [ "$_force" = "--force-uncertain" ] && { echo uncertain; return; }
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    _obl_glob_scan "$p" "$_excl" && continue
    _obl_glob_scan "$p" "$_globs" && { echo triggered; return; }
  done < "$_changed"
  echo none
}

# _obl_ignored FLAG: announce that a gate-defining argument was DISCARDED. First-wins and the `--` sentinel
# both invert POSIX's last-wins convention, and doing so silently means a caller who typed `--record X`
# cannot tell that X did nothing. Goes to stderr so it never contaminates the verdict line on stdout.
# THE FLAG NAME ONLY, NEVER THE VALUE — a gate verdict must never render caller-supplied text (the rule
# a11y-obligation.sh LEG 8 applies to template-controlled text); obl_selftest asserts both halves.
_obl_ignored() {
  printf 'NOTE: %s is gate-defining and is fixed by this check — the value supplied after it was ignored\n' "$1" >&2
}

# _obl_need_value FLAG REMAINING -> 0 iff a VALUE follows FLAG (M-4/L2). REMAINING is the caller's `$#`,
# which COUNTS THE FLAG ITSELF, so `-ge 2` is "there is a value after it".
# Every two-argument branch of obligation_gate's parser ends in `shift 2`, and `shift 2` with only the flag
# left FAILS. The consequence depends on the caller and both halves are wrong:
#  - production entrypoint (a simple command under `set -e`): the check ABORTS. Measured —
#    `sh conformance/threat-obligation.sh --record` returned rc=1 carrying only the stderr NOTE and no
#    `FAIL:` line; `--changed`/`--root` returned rc=1 and no output at all. Fail-CLOSED, so not a bypass,
#    but a check that dies mid-parse cannot be told from one that ran and passed its parse.
#  - a caller wrapping the gate in a CONDITION or a command substitution (obl_selftest, every wrapper
#    selftest): POSIX suppresses errexit for that whole subtree, `$#` never decreases and the parse loop
#    SPINS FOREVER. Measured — killed by SIGXCPU under `ulimit -t 15`, 0 bytes emitted.
# So the arity is tested BEFORE the branch reads `$2` or shifts. Rendering the flag NAME is safe: the
# `case` patterns it is called from are exact literals, so the argument is this file's own text, never the
# caller's (the rule _obl_ignored states). The missing value is not rendered because there isn't one.
# On stdout, not stderr, and worded as a `FAIL:`: this is a VERDICT — the whole point is that the gate
# reaches one — where _obl_ignored's NOTE is an aside about a call that still reached a verdict of its own.
_obl_need_value() {
  [ "$2" -ge 2 ] && return 0
  echo "FAIL: the gate-defining argument $1 was supplied with no value — it takes one, and a check that cannot finish parsing its own arguments must refuse rather than die mid-parse"
  return 1
}

# obligation_gate --name N --surface-globs G --record R --template-marker T [--stub-pattern P]
#                 [--exclude-globs X] -- [--changed F|--root D|--force-uncertain]
# The bracketed fixture flags (--changed/--root/--force-uncertain) are honored ONLY under KIT_OBL_TEST=1
# (set by --selftest). The production entrypoint (verify.sh: no args) parses-but-ignores them, so an
# ARGUMENT alone cannot redirect the gate at /dev/null or a dummy record dir (M1).
# THE PRECISE SCOPE OF THAT CLAIM, corrected — an earlier version of this line said "a caller cannot", full
# stop, which is true only of a caller supplying ARGUMENTS. KIT_OBL_TEST is read from the ENVIRONMENT, so a
# caller who controls the environment reopens every fixture flag. MEASURED non-vacuously on a throwaway repo
# whose real diff is `src/auth/login.js` with no record present: the bare wrapper FAILs; the same wrapper
# with `--changed /dev/null` appended still FAILs (the flag is correctly ignored); and
# `KIT_OBL_TEST=1 … --changed /dev/null` reads "N/A: no threat-model surface touched", rc=0. The control
# matters — probing this on the kit's own tree returns N/A either way, which looks like a bypass and proves
# nothing. So the guarantee this parser provides is ARGUMENT-borne, not environment-borne, and the honest
# statement of it is: a caller who can set the environment of the gate can already switch it off, exactly as
# one who can edit the check could. Replacing the env flag with an argument-borne token is BOARDED
# (`OBLIGATION-TESTMODE-ENV-FLAG`) — this repo already banked "use arguments, not env" as a security ruling.
obligation_gate() {
  name=""; globs=""; record=""; tmpl=""; stubpat=""; excl=""; changed=""; root="."; force=""
  # TWO RULES guard the six GATE-DEFINING arguments (--name/--surface-globs/--record/--template-marker/
  # --stub-pattern/--exclude-globs). Each wrapper (threat-/uat-/a11y-obligation.sh) writes its own
  # definition, then emits `--`, then forwards "$@".
  #  1. THE `--` SENTINEL. Everything after it is a CALLER's argument, so the six are no longer accepted.
  #  2. FIRST ASSIGNMENT WINS. The wrapper's values are always the first assignment, so anything a caller
  #     appends is a second one and is dropped.
  # Rule 2 alone was not enough, and shipping the gap would have contradicted this slice's own thesis: it
  # can only defend an argument the wrapper SETS, and no wrapper sets --stub-pattern, so a caller-supplied
  # one was the FIRST assignment and was honored. Measured on the true production path before the sentinel:
  # `sh conformance/threat-obligation.sh` FAILed while the same command with `--stub-pattern '\[zzz'`
  # appended PASSed — on all three wrappers. Rule 1 closes that and is strictly stronger; rule 2 is kept as
  # defence in depth (it also covers a direct obligation_gate caller that emits no sentinel, which is how
  # obl_selftest exercises it). They cannot conflict: a wrapper's own values are both pre-sentinel and first.
  # Together they close `sh conformance/a11y-obligation.sh --record README.md` (redirect the gate at a
  # benign file), `--surface-globs '*nothing*'` (blanket N/A), `--stub-pattern …` (disable Signal 2) and
  # `--exclude-globs '*'` (skip every file before the surface is tested — the same blanket N/A, and the
  # reason the newest gate-defining argument shipped fenced rather than being fenced later).
  # UNCONDITIONAL — deliberately NOT gated behind $_testmode, unlike the fixture flags. Two reasons:
  #  (a) the property is then the same in test and production, so obl_selftest can prove it directly
  #      instead of needing a production-mode probe that cannot use --changed/--root; and
  #  (b) the condition has one form instead of two, and a two-form condition here is easy to write
  #      backwards. No caller sets any of these twice, so nothing legitimate loses.
  # An explicit seen-flag, not `[ -z "$var" ]`: emptiness is not the same predicate as first-assignment
  # (a wrapper that legitimately passed an empty value would otherwise be overridable).
  # The sentinel fences ONLY these six. `--changed`/`--root`/`--force-uncertain` MUST survive it — every
  # wrapper forwards "$@" after its own `--`, so ending argument parsing there would kill every fixture
  # flag and red LEG 1 of all three wrapper selftests.
  _seen_name=0; _seen_globs=0; _seen_record=0; _seen_tmpl=0; _seen_stub=0; _seen_excl=0
  _defs_done=0   # flipped by the `--` sentinel: past it, the six above are a caller's, not the check's
  _bad_arg=""    # a gate-defining argument that DISABLES what it defines -> refuse (see the FAIL below)
  _bad_why=""    # …and why, in the author's terms; set together with _bad_arg, never separately
  _testmode=0; [ "${KIT_OBL_TEST:-}" = 1 ] && _testmode=1
  while [ $# -gt 0 ]; do case "$1" in
    --) _defs_done=1; shift;;
    # EVERY two-argument branch below opens with the SAME arity guard, and it is tested BEFORE anything
    # else in the branch — before `$2` is read, before the seen-flag, before the shift. See
    # _obl_need_value for what a missing value costs (an abort at the production entrypoint, an INFINITE
    # parse loop from any caller that wraps the gate in a condition). The guard is written out per branch
    # rather than hoisted into one pre-loop test against a list of flag names, because a second copy of
    # the flag list is exactly the kind of thing that drifts away from the `case` it is meant to mirror.
    --name)            _obl_need_value --name $# || return 1
                       if [ "$_defs_done" = 0 ] && [ "$_seen_name"   = 0 ]; then name="$2";  _seen_name=1
                       else _obl_ignored --name; fi; shift 2;;
    # (--surface-globs needs no emptiness test HERE: an empty surface is indistinguishable from an unset
    # one — both are fail-open — so ONE post-loop check below covers both routes. --stub-pattern is the
    # opposite case and is tested in its own branch; see there.)
    --surface-globs)   _obl_need_value --surface-globs $# || return 1
                       if [ "$_defs_done" = 0 ] && [ "$_seen_globs"  = 0 ]; then globs="$2"; _seen_globs=1
                       else _obl_ignored --surface-globs; fi; shift 2;;
    --record)          _obl_need_value --record $# || return 1
                       if [ "$_defs_done" = 0 ] && [ "$_seen_record" = 0 ]; then record="$2"; _seen_record=1
                       else _obl_ignored --record; fi; shift 2;;
    --template-marker) _obl_need_value --template-marker $# || return 1
                       if [ "$_defs_done" = 0 ] && [ "$_seen_tmpl"   = 0 ]; then tmpl="$2";  _seen_tmpl=1
                       else _obl_ignored --template-marker; fi; shift 2;;
    # An EMPTY value is REFUSED, not defaulted. obl_is_placeholder's `${2:-…}` cannot tell empty from
    # unset, so an empty pattern silently fell back to the DEFAULT (threat) vocabulary while the seen-flag
    # recorded that a pattern HAD been supplied: a wrapper writing `--stub-pattern "$SOME_VAR"` with an
    # unset var got another obligation's stub set and no warning (measured: verdict-identical to omitting
    # the flag). Only an ACCEPTED value is checked — a post-sentinel empty one is a caller's and is merely
    # ignored, which is already the right answer. Tested IN THE BRANCH, unlike --surface-globs, because
    # empty and unset are DIFFERENT here: unset is the legitimate, overwhelmingly common case (it selects
    # the default vocabulary), so only the seen-flag can tell the two apart.
    --stub-pattern)    _obl_need_value --stub-pattern $# || return 1
                       if [ "$_defs_done" = 0 ] && [ "$_seen_stub"   = 0 ]; then stubpat="$2"; _seen_stub=1
                         [ -n "$stubpat" ] || { _bad_arg=--stub-pattern
                           _bad_why="was supplied empty — a blank stub vocabulary does not mean 'no vocabulary', it silently falls back to another obligation's" ; }
                       else _obl_ignored --stub-pattern; fi; shift 2;;
    # --exclude-globs is the SIXTH gate-defining argument and the most dangerous of them, because it is an
    # OFF-SWITCH rather than a definition: honouring a caller's turns any triggering change-set into an
    # N/A. T3 measured that the reachable shape is exactly this — an argument NO wrapper is obliged to set,
    # so a caller's is the FIRST assignment and first-wins cannot defend it. It therefore ships fenced by
    # the `--` sentinel from day one rather than by first-wins alone.
    # An EMPTY value is NOT refused here, unlike --surface-globs and --stub-pattern: excluding nothing is
    # precisely what omitting the flag does and it is the STRICTER direction. The refusal this argument
    # needs is at the OTHER end — a glob that matches every path — and it is checked after the loop.
    --exclude-globs)   _obl_need_value --exclude-globs $# || return 1
                       if [ "$_defs_done" = 0 ] && [ "$_seen_excl"   = 0 ]; then excl="$2"; _seen_excl=1
                       else _obl_ignored --exclude-globs; fi; shift 2;;
    # The two FIXTURE flags take a value and `shift 2` exactly like the six above, and in PRODUCTION mode
    # they parse-but-ignore and then shift anyway — so a value-less one dies or spins identically
    # (measured: `sh conformance/threat-obligation.sh --changed` -> rc=1 with no output whatsoever). They
    # get the same guard; the refusal is UNCONDITIONAL rather than test-mode-gated, because a parse that
    # cannot complete is a parse that cannot complete in either mode.
    --changed) _obl_need_value --changed $# || return 1
               if [ "$_testmode" = 1 ]; then changed="$2"; fi; shift 2;;
    --root) _obl_need_value --root $# || return 1
            if [ "$_testmode" = 1 ]; then root="$2"; fi; shift 2;;
    --force-uncertain) if [ "$_testmode" = 1 ]; then force="--force-uncertain"; fi; shift;;
    *) shift;; esac; done
  # A SURFACE THAT DEFINES NO GLOB IS THE MOST COMPLETE FAIL-OPEN THIS ENGINE HAS: it matches nothing, so
  # obl_detect reads 'none' and EVERY change-set is a blanket N/A with no record ever required. MEASURED
  # before this check existed: a TRIGGERING change-set with the record ABSENT returned rc=0.
  # THE PREDICATE IS "AT LEAST ONE USABLE GLOB", NOT "NON-EMPTY". The first version of this line tested
  # `[ -n "$globs" ]`, which is strictly weaker, and an earlier comment claimed one check covered every
  # route when it did not: MEASURED on that version, record absent and a change-set triggering '*auth*',
  # `--surface-globs '|'` -> N/A, `'||'` -> N/A, `' '` -> N/A, control `'*auth*'` -> FAIL. Walking the
  # SAME splitter obl_detect matches on is what makes the two agree by construction — a separately
  # maintained emptiness test is how they came apart in the first place.
  # `|| true` because a no-match return is not an error here; only the published count is being read.
  _obl_glob_scan '' "$globs" || true
  if [ "${OBL_GLOBS_SEEN:-0}" -lt 1 ]; then
    _bad_arg=--surface-globs
    _bad_why="defines no usable glob — it was supplied empty, never supplied at all (a '--' placed first defines nothing), or contains nothing but separators and whitespace; a surface that matches nothing turns every change-set into a blanket N/A with no record ever required"
  fi
  # …and the mirror-image refusal for the OFF-SWITCH. One exclusion glob that matches every path makes
  # obl_detect skip every file, so the gate reads that same blanket N/A by another route. Only exclusions
  # get this rule: a universal SURFACE glob makes everything trigger, which is the fail-CLOSED direction
  # and merely noisy. See _obl_glob_scan for why the test is exact rather than a heuristic, and for why
  # scanning with the EMPTY path cannot truncate the walk before a universal glob is seen.
  if [ -z "$_bad_arg" ]; then
    _obl_glob_scan '' "$excl" || true
    if [ "${OBL_GLOBS_UNIVERSAL:-0}" = 1 ]; then
      _bad_arg=--exclude-globs
      _bad_why="contains a glob that matches EVERY path — an exclusion that broad skips every file before the surface is ever tested, which is the blanket N/A the surface rule above exists to prevent"
    fi
  fi
  # Refuse BEFORE deriving anything: a misconfigured gate must not be able to reach a verdict at all, not
  # even an N/A. $_bad_arg is one of this file's own literal flag names and $_bad_why one of its own
  # literal sentences, never caller-supplied text, so rendering them is safe — the offending VALUE is
  # never echoed anywhere (see _obl_ignored).
  if [ -n "$_bad_arg" ]; then
    # The template marker is appended only when there IS one. On the never-supplied route (`--` first) it
    # is empty, and the old unconditional "($tmpl)" rendered as a bare "()" — an author reading the one
    # verdict that is meant to point them somewhere was pointed at nothing.
    _tm=""; [ -n "$tmpl" ] && _tm=" ($tmpl)"
    echo "FAIL: the gate-defining argument $_bad_arg $_bad_why, so it is refused rather than defaulted$_tm"
    return 1
  fi

  # Derive the change-set into a temp file and detect the surface INSIDE a subshell whose EXIT trap removes
  # the mktemp'd file even on a set -e abort (L3) WITHOUT clobbering a caller's trap (e.g. the selftest's).
  # The subshell emits "<derive_fail> <state>"; a derive-FAILURE forces the uncertain band (fail CLOSED).
  _out="$(
    cs="$(mktemp)"; trap 'rm -f "$cs"' EXIT
    OBL_DERIVE_FAIL=0
    if [ -n "$changed" ]; then cat "$changed" > "$cs"; else obl_changeset > "$cs"; fi
    _f="$force"; [ "${OBL_DERIVE_FAIL:-0}" = 1 ] && _f="--force-uncertain"
    printf '%s %s\n' "${OBL_DERIVE_FAIL:-0}" "$(obl_detect "$globs" "$cs" "$_f" "$excl")"
  )"
  derive_fail="${_out%% *}"; s="${_out#* }"
  case "$s" in
    none)      echo "N/A: no $name surface touched by this change-set — no record required"; return 0 ;;
    uncertain)
      if [ "$derive_fail" = 1 ]; then
        echo "NOTE: could not derive the $name change-set (no resolvable base / git error) — fail-safe requires the record"
      else
        echo "NOTE: ambiguous $name surface — fail-safe requires the record"
      fi ;;  # fall through -> record required
  esac
  rec="$root/$record"
  if [ ! -f "$rec" ]; then
    echo "FAIL: change touches a $name surface but $rec is absent — record it ($tmpl)"; return 1
  fi
  # present + filled: reject the unfilled template placeholder (privacy-ready.sh:21-35 idiom).
  # The message is keyed to the SIGNAL that fired, not one text for all three. "still the unfilled
  # template — fill it" is true for Signals 1-2 and false (and unactionable) for a record the author
  # hand-wrote and considers complete: it names a template they never used and offers no route to a fix.
  if obl_is_placeholder "$rec" "$stubpat"; then
    case "${OBL_PLACEHOLDER_REASON:-template}" in
      unreadable)
        # ($tmpl) here too (R2-5): this was the only one of the three rejections that did not point at the
        # template, and it is the one an author is least likely to be able to act on unaided.
        echo "FAIL: $rec exists but is not readable — a record that cannot be read cannot count as filled (fail-closed) ($tmpl)" ;;
      floor)
        echo "FAIL: $rec ${OBL_PLACEHOLDER_DETAIL:-is below the substance floor} — a record needs >=$OBL_MIN_SUBSTANCE_LINES non-blank lines under at least one markdown heading ('# …' or a setext underline) ($tmpl)" ;;
      pattern)
        # A FOURTH cause, and a CONFIGURATION fault rather than a record fault — so it gets its own text
        # and is checked BEFORE the record signals, which would otherwise mask it and blame the author for
        # a wrapper's typo. The offending pattern is deliberately NOT quoted back into the verdict.
        echo "FAIL: the --stub-pattern this gate was given is not a valid ERE — Signal 2 cannot compile it, so no record can be judged filled (fail-closed) ($tmpl)" ;;
      *)
        echo "FAIL: $rec is still the unfilled template — fill it ($tmpl)" ;;
    esac
    return 1
  fi
  echo "PASS: $name surface touched and a filled $record is present"; return 0
}

# obl_is_placeholder FILE [STUB_PATTERN]: true (returns 0) if the record is still the blank template (unfilled), or is
# present-but-unreadable (L2 — fail CLOSED, never pass on a read error). What marks "unfilled":
#  1. the template's self-identifying "> **Template.**" guidance banner, or a generic unfilled bracket
#     token (fill/todo/replace/your/describe) — mirrors privacy-ready.sh's placeholder-skip idiom; or
#  2. (L1) a threshold (>=3) of residual TEMPLATE STUBS still present — anchored on THREAT-MODEL-TEMPLATE.md's
#     OWN bracket vocabulary ([summary]/[threat]/[why]/[boundary N …]/[planned/done]/[data, credentials …]/
#     [users, agents …]/[auth, MFA …]/[risk accepted …]/[tracked items …]), a stable subset that will NOT
#     appear in ordinary prose. This catches a record with the banner deleted but every section left as the
#     template stub, WITHOUT false-positiving on a filled record's markdown links / citations ([STRIDE],
#     [design doc](…), [1], [OWASP A01]) — the pre-fix arbitrary-`[...]` count wrongly FAILed those. Coarse
#     by design (honest ceiling stays "present + filled"). The vocabulary is now the SECOND ARGUMENT
#     (OBLIGATION-STUB-PATTERN), defaulting to $OBL_DEFAULT_STUB_PATTERN — that threat set — so an
#     obligation with a stub vocabulary of its own no longer has to author its template to trip Signal 1.
#  3. (OBLIGATION-RECORD-FLOOR) below the minimum SUBSTANCE floor: fewer than OBL_MIN_SUBSTANCE_LINES
#     non-blank lines, or no markdown heading at all (ATX `# …` or a setext underline). Signals 1-2 both
#     look for something PRESENT, so a record with nothing in it matched neither and
#     `touch THREAT-MODEL.md` satisfied every obligation.
# Absent all signals on a readable file -> treat as filled (a real record passes).
# WHICH signal fired is published in OBL_PLACEHOLDER_REASON (template|floor|unreadable|pattern) plus, for
# the floor, OBL_PLACEHOLDER_DETAIL — so obligation_gate can tell the author what is actually wrong instead
# of accusing every rejected record of being an unfilled template. Set on EVERY path, reset on entry.
# `pattern` is the odd one out and deliberately so: it is a fault in the CALLER's configuration, not in the
# record, so it is tested BEFORE any record signal (a record signal firing first would blame the author for
# a wrapper's typo) and it returns 0 — "cannot be judged filled" is the fail-CLOSED answer, because a
# vocabulary that will not compile means Signal 2 cannot run at all.
# HONEST CEILING (do not read the floor as more than it is): it closes the empty/stub bypass and nothing
# more. EIGHT LINES OF PROSE UNDER A HEADING STILL PASSES. AND A SYMLINK PASSES TOO: obligation_gate's
# presence test is `[ -f "$rec" ]`, which FOLLOWS symlinks, so `ln -s README.md THREAT-MODEL.md` is read as
# a filled record whenever the target clears the floor (MEASURED on the production path: PASS; a DANGLING
# symlink correctly FAILs, so the direction is fail-closed). It is worth naming because it is the ONLY
# trivial pass that leaves NO CONTENT IN THE DIFF — every other route (banner, stubs, floor) forces the
# author to write something a reviewer can read. Disclosed rather than closed: a symlinked record is
# conspicuous in a diff, and review is the backstop the whole ceiling already rests on.
# The floor measures STRUCTURE, never QUALITY —
# whether the threat analysis is sound, the a11y verdicts truthful, or the record FRESH for this change
# are all review's job, not this engine's. Same ceiling every obligation's own header already states.
# KNOWN FALSE POSITIVE of the heading half, disclosed rather than discovered: a record written as a bare
# markdown TABLE — no `#` line and no setext underline — reds as unfilled. Every shipped template opens
# with a heading, so a template-derived record always clears it; a hand-rolled table-only record does not.
# Accepted — the remedy is one line the author adds — but it is a real cost of the structure half, not a
# free check. A SETEXT-underlined title is NOT in this class: it is CommonMark-legal, it reds-ed in the
# first cut of this floor, and it is now accepted (with a selftest leg holding it accepted).

# _obl_strip_code_markup FILE -> FILE's text with markdown CODE MARKUP removed: fenced code blocks
# (``` and ~~~, the fence line and its whole body) and inline backtick spans. Used by Signal 1 ONLY.
#
# WHY, and what this is NOT. Signal 1's vocabulary is ordinary English (`fill`, `todo`, `replace`,
# `your `, `describe `) plus the `**Template.**` banner, so a document that WRITES ABOUT the engine is
# indistinguishable from a record that still CARRIES the stubs. Measured on this repository: four of its
# own design/plan documents are denied for quoting the vocabulary while discussing it.
# TWO OTHER SEPARATORS WERE RULED AND THEN VETOED BY MEASUREMENT. Neither may be reintroduced:
#  - a HIT COUNT (">=2 hits before Signal 1 may deny"). Vetoed: eleven live records are caught by a
#    SINGLE hit (a11y-obligation.sh's ten per-cell LEG-8 fixtures, each an otherwise-complete sign-off
#    with one unfilled cell, plus this file's own BANNER.md), and nineteen shipped templates fire exactly
#    once — on the banner, which is a single-occurrence marker by construction. A threshold of 2 makes an
#    unsigned a11y sign-off and a wholly unedited template both read FILLED.
#  - excluding BLOCKQUOTE lines. Vetoed twice over: the four false positives are not in blockquotes (they
#    are in inline code spans), and `> **Template.**` IS a blockquote line — so the rule would delete the
#    hit that catches all nineteen templates while fixing nothing. Blockquotes are deliberately NOT
#    stripped here, and obl_selftest leg (m6) reds if that changes.
# CODE MARKUP is the separator that measured clean in BOTH directions on the real corpus: all four false
# positives sit inside it; all eleven true stubs and all nineteen template banners sit outside it.
# COARSE BY DESIGN, and the coarseness is in the SAFE direction for the fence rule (an unterminated fence
# swallows the rest of the file, which can only LOSE a hit — so the fence test insists on a closing line
# of the SAME fence character, and an inline span must be CLOSED on its own line to be stripped). What is
# left is what markdown itself leaves: a record whose author wraps a real unfilled stub in backticks is
# not detected. That is a deliberate trade — a stub inside a code span is being displayed, not filled in,
# and the alternative is the manufactured denial this rule exists to remove.
# awk, not sed: the fence state is a LINE-SPANNING mode, and a sed range (`/```/,/```/d`) cannot tell a
# closing ``` from a ~~~ nor stop at an unterminated one. Every `case` clause in this file starts on its
# own line for the SAST parser's sake (see _obl_glob_scan); this function introduces no `case` at all.
_obl_strip_code_markup() {
  awk '
    {
      _line = $0
      if (_fence == "") {
        if (match(_line, /^[ \t]*(```+|~~~+)/)) {
          _m = substr(_line, RSTART, RLENGTH)
          sub(/^[ \t]*/, "", _m)
          _fence = substr(_m, 1, 1)
          next
        }
      } else {
        if (match(_line, /^[ \t]*(```+|~~~+)[ \t]*$/)) {
          _m = substr(_line, RSTART, RLENGTH)
          sub(/^[ \t]*/, "", _m)
          if (substr(_m, 1, 1) == _fence) { _fence = "" }
        }
        next
      }
      # INLINE SPANS, by the CommonMark RUN-LENGTH rule rather than by a naive gsub. An opening run of N
      # backticks is closed by a run of EXACTLY N, which is why a `gsub(/`[^`]*`/,"")` is wrong and was
      # measured wrong: on `` > **Template.** `` it pairs the two halves of the OPENING run with each
      # other, deletes them, and leaves the quoted banner behind as bare text — the false positive intact.
      # An UNCLOSED run is left in place, so an odd stray backtick can only ever leave MORE text for
      # Signal 1 to see, never less.
      _out = ""; _rest = _line
      while (match(_rest, /`+/)) {
        _pre = substr(_rest, 1, RSTART - 1)
        _open = substr(_rest, RSTART, RLENGTH)
        _n = RLENGTH
        _after = substr(_rest, RSTART + RLENGTH)
        # Walk the remainder for a run of exactly _n. RSTART/RLENGTH belong to the INNER match from here
        # on, which is why _pre/_open/_n/_after are all captured BEFORE the walk starts.
        _close = 0; _scan = _after; _off = 0
        while (match(_scan, /`+/)) {
          if (RLENGTH == _n) { _close = _off + RSTART; break }
          _off = _off + RSTART + RLENGTH - 1
          _scan = substr(_scan, RSTART + RLENGTH)
        }
        if (_close > 0) { _out = _out _pre; _rest = substr(_after, _close + _n) }
        else { _out = _out _pre _open; _rest = _after }
      }
      print _out _rest
    }
  ' "$1" 2>/dev/null
}

obl_is_placeholder() {
  _rec="$1"
  # Signal 2's stub vocabulary, PARAMETERISED (OBLIGATION-STUB-PATTERN). Omitted or empty -> the shipped
  # THREAT-MODEL vocabulary, so every existing caller keeps today's verdicts unchanged. A supplied pattern
  # REPLACES the default rather than adding to it: an obligation whose filled records legitimately contain
  # threat-vocabulary brackets must be able to NARROW, not only widen. The cost of that choice is that a
  # pattern is a way to WEAKEN Signal 2 — which is why obligation_gate treats --stub-pattern as
  # gate-defining and ignores any second one (see its parser).
  _pat="${2:-$OBL_DEFAULT_STUB_PATTERN}"
  # Which signal fired, for the caller's diagnostic. Reset on every call so a previous verdict can never
  # leak into this one. `template` keeps the historical wording (those records ARE unfilled templates);
  # `floor` and `unreadable` get their own text — see obligation_gate.
  OBL_PLACEHOLDER_REASON=template; OBL_PLACEHOLDER_DETAIL=""
  # L2: an existing-but-unreadable record must NOT pass — treat as unfilled (fail-closed).
  if [ ! -r "$_rec" ]; then OBL_PLACEHOLDER_REASON=unreadable; return 0; fi
  # MALFORMED PATTERN -> fail CLOSED. This is the SECOND route into Signal 2's swallowed `2>/dev/null`, and
  # the likelier of the two: a malformed ERE exits 2 exactly as an unknown option does, so the redirect eats
  # the diagnostic, `_n` is 0 and Signal 2 is SILENTLY OFF. The trigger is not an attacker but the next
  # wrapper author — the intended shape is `\[(a|b|c)` and a dropped closing paren is a one-character typo
  # that ships an inert detector, green through CI. MEASURED on the 3-stub fixture before this check:
  # `\[(attach|evidence owner|rollout window` , `\[(attach` and `[` each read FILLED (raw grep rc=2);
  # only the well-formed pattern read PLACEHOLDER. Every other unreadable/underivable condition in this
  # engine fails closed; this was the one place caller-authored input could turn a signal off silently.
  # Validated ONCE here, against EMPTY input, so this is a pure pattern-COMPILE probe: independent of the
  # record, of the filesystem, and cheap. `|| _perr=$?` and not `$?` after an `if`: measured under sh, dash
  # and bash, the brief's `if …; then :; else [ $? -ge 2 ]` shape reads correctly ONLY while nothing
  # intervenes — insert a single `true` before it and `$?` is 0 (measured, all three shells). The OR-list
  # form captures the status in the very next word and is errexit-safe (POSIX exempts every command of an
  # AND-OR list but the last), so it is also safe for a future BARE caller.
  # The pattern is NOT echoed anywhere: a gate verdict must never render caller-supplied text.
  # `-ge 2` AND NOT `-ge 1`, and the boundary is one apart: against empty input a WELL-FORMED pattern exits
  # 1 (no match) and only a compile failure exits 2 (measured for both, under sh, dash and bash). So the
  # false-POSITIVE direction of this comparison is not theoretical — `-ge 1` would reject every valid
  # pattern including the default, and obl_selftest's leg (a) (no --stub-pattern -> PASS) is what reds on it.
  _perr=0; printf '' | grep -qE -e "$_pat" 2>/dev/null || _perr=$?
  if [ "$_perr" -ge 2 ]; then OBL_PLACEHOLDER_REASON=pattern; return 0; fi
  # Signal 1: the "> **Template.**" banner, or a generic unfilled bracket token — read from the record with
  # its markdown CODE MARKUP removed (OBLIGATION-SIGNAL1-CODE-MARKUP). See _obl_strip_code_markup for what
  # is stripped, why the two rejected alternatives were rejected, and the corpus this was measured on.
  # THE FALLBACK IS THE FAIL-CLOSED HALF and it is not decoration: the stripper is the only external
  # dependency this function grew, and a stripper that dies silently would take Signal 1 with it — the
  # fail-OPEN class every other guard in this file exists to close. On a non-zero status the raw record is
  # appended, so the input degrades to TODAY's text (a superset of the stripped text) and detection can only
  # get STRICTER, never weaker. obl_selftest leg (m8) shadows awk with a failing stub and holds this.
  if { _obl_strip_code_markup "$_rec" || cat "$_rec" 2>/dev/null; } \
       | grep -Eiq '(\*\*template\.\*\*|\[(fill|todo|replace|your |describe ))'; then
    return 0
  fi
  # Signal 2 (L1): residual template stubs. Anchor on the template's stub words — NOT arbitrary `[...]` —
  # so bracketed prose (markdown links, citations) is not mistaken for an unfilled stub. A bare `[STRIDE]`
  # citation defeats a pure link-strip, so the stub-vocabulary anchor (not a link-strip) is load-bearing.
  # `-e` before the pattern (POSIX's way to introduce a pattern that may begin with `-`): the pattern now
  # arrives in a VARIABLE, and a value starting with `-` is otherwise read as an OPTION. That is not
  # cosmetic — it is a silent FAIL-OPEN, because the `2>/dev/null` here swallows grep's usage error and the
  # empty output makes _n zero, switching Signal 2 OFF for that record. MEASURED without the `-e`: a usage
  # error, exit 2, no matches. (The error TEXT is implementation-specific — GNU grep, BSD grep and a
  # `grep`-aliased ugrep each word it differently and prefix it with their own name — so it is not quoted
  # here. Only the exit status is portable, and the exit status is what the fix keys on.)
  # `-e` covers ONE of the two routes into that swallowed redirect — the OPTION-PARSING route, and nothing
  # else. The other is a malformed ERE, which exits 2 identically; that one is closed by the pattern-COMPILE
  # probe near the top of this function, not here. obl_selftest carries a leg for each.
  # Nothing else about the match changes — the default is byte-identical to the literal that used to sit
  # here (the two strings were compared byte-for-byte during the build).
  _n=$(grep -oE -e "$_pat" "$_rec" 2>/dev/null | wc -l | tr -d ' ')
  # `if`, not `[ … ] && return 0` — SYMMETRY with Signal 3 below, not a fix. A leading `[ … ]` that fails
  # inside an AND-list does NOT trip errexit even for a bare caller: POSIX exempts every command of an
  # AND-OR list except the last. MEASURED under sh, dash and bash — the function runs on past the failed
  # test in all three. The `|| true`s below are a DIFFERENT case (a bare `$(grep -c …)` genuinely does
  # abort) and are the ones a future bare caller needs; do not merge the two rationales.
  if [ "${_n:-0}" -ge 3 ]; then return 0; fi
  # Signal 3 (RECORD-FLOOR): without it, `touch A11Y-SIGNOFF.md` satisfies every obligation gate — a
  # cheaper bypass than the banner-delete the template tightening already closes, and open on all three
  # obligations at once. STRUCTURAL ONLY: >=1 markdown heading AND >= OBL_MIN_SUBSTANCE_LINES non-blank
  # lines. Deliberately NOT keyed on a per-record heading STRING, which would re-introduce the record-
  # vocabulary coupling this engine is shedding — any heading counts.
  # HEADING TEST — ATX (`# …`) *or* SETEXT (a title underlined with `===` / `---`). Setext is
  # CommonMark-legal and the first cut of this floor RED-ed on it (measured), which is the failure mode
  # this kit deletes gates for: a gate that reds on compliant behavior. The selftest's setext leg locks
  # the acceptance in, so "simplifying" back to `^#` cannot ship green.
  # DISCLOSED, not discovered: `^[-]{3,}` also matches a thematic break and a YAML front-matter fence, so
  # a record using either is credited with a heading it does not have. That is a false NEGATIVE on the
  # structure half only — the line-count half still applies — and the alternative (parsing CommonMark in
  # POSIX sh to tell a setext underline from a thematic break) buys precision this coarse check does not
  # claim. The remaining false POSITIVE is unchanged and still real: a record written as a bare markdown
  # table with neither an ATX heading nor an underline reds as unfilled.
  # `|| true` on both counts: `grep -c` exits 1 on zero matches (a legitimate count here — an empty record
  # has zero of both). Today's ONLY caller is obligation_gate's `if obl_is_placeholder "$rec"; then` —
  # named, not line-numbered, because the number this comment first carried had already drifted — and
  # POSIX suppresses errexit for the whole subtree of an `if` CONDITION. So with both `|| true` stripped
  # nothing aborts, `_hd` still gets `0`, and the entire suite stays green (measured, under sh AND dash;
  # an earlier version of this comment claimed the opposite, which is what put this file back in review).
  # What they actually defend is a FUTURE BARE caller: `obl_is_placeholder "$f"`
  # outside a condition DOES abort silently at this line under `set -e` (measured — the script died
  # between two echoes, exit 1, no FAIL text). No test can observe that, because adding one would mean
  # adding the bare caller. Do not delete these on the strength of a green selftest.
  # The `${_hd:-0}` defaults cover the other direction: a grep ERROR prints nothing.
  _hd=$(grep -cE '^#|^[=-]{3,}[[:space:]]*$' "$_rec" 2>/dev/null || true)
  _nb=$(grep -c '[^[:space:]]' "$_rec" 2>/dev/null || true)
  if [ "${_hd:-0}" -lt 1 ] || [ "${_nb:-0}" -lt "$OBL_MIN_SUBSTANCE_LINES" ]; then
    OBL_PLACEHOLDER_REASON=floor
    OBL_PLACEHOLDER_DETAIL="has ${_nb:-0} non-blank line(s)"
    if [ "${_hd:-0}" -lt 1 ]; then OBL_PLACEHOLDER_DETAIL="$OBL_PLACEHOLDER_DETAIL and no markdown heading"; fi
    return 0
  fi
  return 1
}

# ---- selftest() marker: the non-vacuity sweep mutates ONLY lines ABOVE here; everything below (the
# engine's own oracle) is emitted verbatim. Named selftest() per non-vacuity.sh's first_marker
# convention so the sweep recognizes this oracle region and mutates the engine FAIL paths above;
# obl_selftest (just below) is the substantive test it delegates to.
selftest() { obl_selftest; }

# obl_selftest: the engine's OWN mutation-tested oracle. The per-obligation wrappers (threat-obligation.sh)
# are thin — run_threat_obligation carries no mutable FAIL idiom of its own, so mutating that file yields
# UNCOVERED(no-idiom) and cannot prove the engine's teeth. So the engine tests ITSELF here: non-vacuity.sh
# mutates obl_changeset/obl_detect/obligation_gate's FAIL legs ABOVE the marker and this oracle KILLS them.
# Covers: obl_detect none/triggered/uncertain; obligation_gate absent-record FAIL, placeholder FAIL, real
# derive-failure -> uncertain -> require FAIL, filled -> PASS, non-triggering -> N/A PASS.
obl_selftest() {
  _t="$(mktemp -d "${TMPDIR:-/tmp}/obl-st.XXXXXX")"; trap 'rm -rf "$_t"' EXIT INT TERM
  export KIT_OBL_TEST=1   # honor the fixture flags (--changed/--root/--force-uncertain) only in-test (M1)
  rc=0

  # obl_detect — the three bands.
  printf 'docs/README.md\n' > "$_t/none"
  [ "$(obl_detect '*secret*|*auth*' "$_t/none")" = none ] \
    || { echo "OBL SELFTEST FAIL: non-matching change-set should detect 'none'"; rc=1; }
  printf 'src/auth/login.js\n' > "$_t/hit"
  [ "$(obl_detect '*secret*|*auth*' "$_t/hit")" = triggered ] \
    || { echo "OBL SELFTEST FAIL: matching change-set should detect 'triggered'"; rc=1; }
  [ "$(obl_detect '*secret*|*auth*' "$_t/hit" --force-uncertain)" = uncertain ] \
    || { echo "OBL SELFTEST FAIL: --force-uncertain should detect 'uncertain'"; rc=1; }

  # obl_detect — EXCLUSIONS (OBLIGATION-CONFIG-TEMPLATE-EXT), the FOURTH positional. An obligation that
  # detects by markup EXTENSION cannot tell a view template from a CONFIG template that borrows the same
  # extension: Ansible/Chef write `roles/nginx/templates/nginx.conf.j2` and `app.conf.erb`, so a11y demanded
  # a WCAG sign-off for an nginx config. The exclusion list is evaluated BEFORE any surface glob, so an
  # exclusion is a statement about the PATH ("this is not a UI file"), never a hole in the surface.
  # EVERY leg here is PAIRED with its liveness run — the same path with NO exclusion list must still
  # trigger — because an "excluded -> none" assertion is green for free if the path never matched at all.
  printf 'roles/nginx/templates/nginx.conf.j2\n' > "$_t/cfgtpl"
  [ "$(obl_detect '*.j2' "$_t/cfgtpl")" = triggered ] \
    || { echo "OBL SELFTEST FAIL: a config template is not matched by the surface at all — every exclusion leg below would be vacuous"; rc=1; }
  [ "$(obl_detect '*.j2' "$_t/cfgtpl" '' '*.conf.j2')" = none ] \
    || { echo "OBL SELFTEST FAIL: an EXCLUDED path still triggered — exclusions must be evaluated before the surface globs"; rc=1; }
  # THE EXCLUSION MUST NOT BE WIDENABLE INTO AN OFF-SWITCH. A real view template carrying the SAME
  # extension must still trigger: that is what makes the exclusion a COMPOUND SUFFIX (*.conf.j2) rather
  # than the bare extension (*.j2), which would disable the surface outright.
  printf 'app/templates/index.j2\n' > "$_t/viewtpl"
  [ "$(obl_detect '*.j2' "$_t/viewtpl" '' '*.conf.j2')" = triggered ] \
    || { echo "OBL SELFTEST FAIL: a REAL view template with the excluded extension stopped triggering — the exclusion has widened into a surface off-switch"; rc=1; }
  # …and the exclusion is PER PATH, not per change-set: one excluded config template in the diff must not
  # suppress a genuine view template sitting beside it.
  printf 'roles/nginx/templates/nginx.conf.j2\napp/templates/index.j2\n' > "$_t/mixedtpl"
  [ "$(obl_detect '*.j2' "$_t/mixedtpl" '' '*.conf.j2')" = triggered ] \
    || { echo "OBL SELFTEST FAIL: an excluded path suppressed the WHOLE change-set — exclusion is per path"; rc=1; }
  # A DEGENERATE exclusion list excludes NOTHING. This is the deliberately asymmetric half: an empty or
  # separators-only exclusion is the STRICTER direction (everything still triggers), so unlike an empty
  # --surface-globs it needs no refusal. Locking it here stops a future "tidy-up" turning a blank field
  # into a match-everything glob.
  [ "$(obl_detect '*.j2' "$_t/viewtpl" '' '')" = triggered ] \
    || { echo "OBL SELFTEST FAIL: an EMPTY exclusion list excluded something — an empty off-switch must exclude nothing"; rc=1; }
  [ "$(obl_detect '*.j2' "$_t/viewtpl" '' '|  |')" = triggered ] \
    || { echo "OBL SELFTEST FAIL: a separators-and-whitespace-only exclusion list excluded something — a blank field is not a glob"; rc=1; }
  # …and the fail-safe still outranks both lists: --force-uncertain wins over an exclusion that would
  # otherwise have produced a comfortable 'none'.
  [ "$(obl_detect '*.j2' "$_t/cfgtpl" --force-uncertain '*.conf.j2')" = uncertain ] \
    || { echo "OBL SELFTEST FAIL: an exclusion overrode the uncertain fail-safe — --force-uncertain must win"; rc=1; }

  # obligation_gate — absent record on a triggered surface -> FAIL. Kills obligation_gate's absent-record
  # `return 1` (neutered to `return 0`, this leg would see a wrong PASS).
  printf 'src/auth/login.js\n' > "$_t/changed"
  if obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: triggered surface with no record did not FAIL"; rc=1
  fi
  # placeholder (unfilled template) record -> FAIL. Kills the placeholder-branch `return 1`.
  printf '> **Template.**\n' > "$_t/R.md"
  if obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: unfilled template record did not FAIL"; rc=1
  fi
  # filled record -> PASS. REBUILT FROM THE SHIPPED TEMPLATE (banner stripped, every bracketed stub
  # substituted with a generic pattern) rather than hand-written. Two reasons, both learned the hard way:
  #  (a) the old fixture was a heading plus ONE prose line — 2 non-blank lines. The RECORD-FLOOR below
  #      correctly reds that, so this leg HAD to change; that is an intended regression, not breakage.
  #  (b) a hand-written fixture cannot COUPLE the check to the artifact. That exact gap is why an inert
  #      `[describe:` stub shipped green through HITL-4's first review round. Built from the template,
  #      a future template edit that the engine can no longer accept reds HERE.
  # The trailing prose is the L1 FALSE-POSITIVE guard, kept alongside threat-obligation.sh LEG 5's copy
  # because Signal 2 lives HERE: a genuinely-filled record whose only brackets are markdown links and
  # citations ([STRIDE], [design doc](…), [1]) must read as FILLED. It is APPENDED after the substitution
  # so those brackets survive it — the pre-fix arbitrary-`[...]` >= 3 count wrongly FAILed such a record.
  # shellcheck disable=SC1007 # `CDPATH= cd` clears CDPATH for this one command so a user's CDPATH cannot
  # redirect it; the empty assignment is intentional. $0-relative (not cwd-relative) so it also resolves
  # for the non-vacuity sweep's renamed .nv-mut-/.nv-ctl- copy, which runs from this same directory.
  _root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
  _tpl="$_root/templates/THREAT-MODEL-TEMPLATE.md"
  if [ ! -f "$_tpl" ] || [ ! -s "$_tpl" ]; then
    echo "OBL SELFTEST FAIL: templates/THREAT-MODEL-TEMPLATE.md is missing or empty — the filled-record leg cannot run"; rc=1
  else
    { grep -v '^> \*\*Template\.\*\*' "$_tpl" \
        | sed 's/\[[^]]*\]/analyzed: spoofing mitigated by MFA, Jane Roe 2026-07-24/g'
      printf '\nAssets analyzed per [STRIDE]; rationale in the [design doc](https://x/y); see ref [1].\n'
    } > "$_t/R.md"
    if ! obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
         --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
      echo "OBL SELFTEST FAIL: triggered surface with a filled record (the SHIPPED template, banner-stripped and fully filled) did not PASS"; rc=1
    fi
  fi
  # non-triggering change -> N/A PASS.
  if ! obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/none" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: non-triggering change did not PASS (N/A)"; rc=1
  fi
  # REAL derive-failure (no resolvable base) -> uncertain -> require the record -> FAIL. Kills
  # obl_changeset's `OBL_DERIVE_FAIL=1` (neutered to =0, failure collapses into an empty change-set ->
  # 'none' -> a wrong N/A PASS). Throwaway repo with neither origin/main nor a 'main' branch.
  _dr="$_t/derive"; mkdir -p "$_dr"
  git -C "$_dr" init -q >/dev/null 2>&1
  git -C "$_dr" config user.email obl@test.local
  git -C "$_dr" config user.name obl-test
  : > "$_dr/f.txt"; git -C "$_dr" add f.txt; git -C "$_dr" commit -qm init >/dev/null 2>&1
  git -C "$_dr" branch -m obl-st-nobase >/dev/null 2>&1
  if ( cd "$_dr" && obligation_gate --name t --surface-globs '*auth*' \
         --record R.md --template-marker T --root "$_dr" ) >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: underivable change-set did not FAIL (derive fail-open)"; rc=1
  fi
  # LIVENESS ONLY — this leg kills NO quoting mutant, and saying otherwise was a round-3 defect.
  # Its change-set is {web/Cafe.tsx, web/Café.tsx}; the ASCII twin matches *.tsx however the accented one
  # is rendered, so the gate fires under every derivation and this assertion is permanently green. It is
  # kept because it does kill a "detection totally broken" mutant, and because the twin makes the NEXT
  # leg's setup explicit — but it is NOT one of the two path-quoting assertions. Those are the
  # accented-ALONE leg and the quote-in-name leg below, each of which is the sole triggering path in its
  # own change-set. A fail-open assertion sharing a change-set with any other triggering path proves nothing.
  _qr="$_t/quote"; mkdir -p "$_qr"
  git -C "$_qr" init -q >/dev/null 2>&1
  git -C "$_qr" config user.email obl@test.local
  git -C "$_qr" config user.name obl-test
  : > "$_qr/seed.txt"; git -C "$_qr" add seed.txt; git -C "$_qr" commit -qm seed >/dev/null 2>&1
  git -C "$_qr" branch -M main >/dev/null 2>&1        # a resolvable base for merge-base HEAD main
  git -C "$_qr" checkout -q -b feat >/dev/null 2>&1
  mkdir -p "$_qr/web"
  _acc="$(printf 'web/Caf\303\251.tsx')"              # UTF-8 'Café.tsx', written by byte so the
  : > "$_qr/$_acc"                                    # selftest does not depend on this file's encoding
  : > "$_qr/web/Cafe.tsx"
  git -C "$_qr" add -A >/dev/null 2>&1; git -C "$_qr" commit -qm ui >/dev/null 2>&1
  if ( cd "$_qr" && obligation_gate --name t --surface-globs '*.tsx' \
         --record R.md --template-marker T --root "$_qr" ) >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a change-set containing plain ASCII UI files was wrongly N/A — detection is broken outright"; rc=1
  fi
  # …and the accented file ALONE must still trigger. This is the assertion that actually bites: with the
  # ASCII twin present, the twin triggers and masks the bug, so the leg above cannot prove equivalence on
  # its own (verified — under the both-dropped mutant only THIS assertion fires).
  git -C "$_qr" rm -q --cached web/Cafe.tsx >/dev/null 2>&1
  rm -f "$_qr/web/Cafe.tsx"
  git -C "$_qr" commit -qm ascii-gone >/dev/null 2>&1
  if ( cd "$_qr" && obligation_gate --name t --surface-globs '*.tsx' \
         --record R.md --template-marker T --root "$_qr" ) >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a change-set whose ONLY UI file has a non-ASCII name was wrongly N/A"; rc=1
  fi
  # QUOTE-IN-NAME (kills the `-z`-dropped mutant, which the non-ASCII legs above CANNOT — git quotes a
  # path containing `"` regardless of core.quotePath, so only `-z` unquotes it). Without this leg the
  # engine's strongest half ships untested and a maintainer can "simplify" it away on a false attestation.
  # The accented file is REMOVED first: with core.quotePath=false it emits raw, triggers, and MASKS this
  # assertion (measured — the mutant survived until this line existed). Every fail-open leg here must be
  # the ONLY triggering path in its change-set, or it proves nothing.
  git -C "$_qr" rm -q --cached "$_acc" >/dev/null 2>&1
  rm -f "$_qr/$_acc"
  _qn="$(printf 'web/qu\42ote.tsx')"        # web/qu"ote.tsx, written by byte
  : > "$_qr/$_qn"
  git -C "$_qr" add -A >/dev/null 2>&1; git -C "$_qr" commit -qm quoted >/dev/null 2>&1
  if ( cd "$_qr" && obligation_gate --name t --surface-globs '*.tsx' \
         --record R.md --template-marker T --root "$_qr" ) >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a UI path containing a double-quote was wrongly N/A — git quotes it whatever core.quotePath says, so the derivation must use -z"; rc=1
  fi
  # RENAME DETECTION (H1) — a `git mv` in the same PR silently converted a triggering change into an N/A.
  # `git diff --name-only` has rename detection ON BY DEFAULT (diff.renames=true since git 2.9), and a
  # DETECTED rename emits ONLY the DESTINATION path — so the SOURCE path, the one carrying the sensitive or
  # regulated token, never enters the change-set at all. MEASURED on the TRUE production path before
  # `--no-renames`: an identical content edit to `svc2/pii/export.py` reported
  # "FAIL … THREAT-MODEL.md is absent" (rc=1) in place, and the SAME edit with a `git mv` to
  # `svc2/core/export.py` (git scored it R098) reported "N/A: no threat-model surface touched" (rc=0).
  # A PURE rename needs no content change at all and is detected R100 whatever the file's size. Reproduced
  # on the sensitive half (`git mv src2/auth/login.js src2/gate/login.js` -> N/A) and on a11y/uat.
  # That is the fail-OPEN direction on a fail-safe gate, so the derivation switches rename detection off.
  # `--no-renames` is MONOTONE: all it does is un-collapse an `R` entry back into the (source, destination)
  # pair git would otherwise have reported as `D`+`A`, so it can only ever ADD the source path — no
  # previously-triggering change-set can stop triggering. Measured across five base/head pairs, including
  # this slice's own diff and two rename-carrying synthetic ones: paths LOST = 0 in every case.
  # PAIRED with its liveness run, because "the rename still FAILs" is green for free if the DESTINATION
  # happens to sit on the surface too: the destination path ALONE must read N/A, so the FAIL below is
  # attributable to the SOURCE path re-entering the change-set and to nothing else.
  # PRECONDITION, PINNED rather than assumed (the same reason the malformed-pattern legs probe each shape):
  # this leg's premise is "git collapses this move into a rename". A host whose EFFECTIVE config carries
  # `diff.renames=false` does not collapse it — it emits both paths anyway, so the derivation triggers with
  # or without `--no-renames` and the leg proves nothing while the banner still credits it. MEASURED on this
  # build with `GIT_CONFIG_GLOBAL` pointing at a `diff.renames=false` file: a copy of this file with
  # `--no-renames` deleted from the derivation ran rc=0 — the mutant SURVIVED — while the same mutant under
  # the default config ran rc=1. Skipping the leg with a NOTE did not repair that: the OK banner still
  # asserted "derivation follows a rename". So the fixture repo pins `diff.renames=true` in its OWN config.
  # LOCAL config outranks global and system, and it is read by BOTH the probe below AND the gate's
  # derivation (which runs with cwd inside this fixture) — so the leg is live whatever the host is set to.
  # With the pin in place the premise-not-met branch is a FAIL, not a skip: the only remaining way it can
  # fire is a git that cannot detect an exact-content rename at all (or a caller forcing the value back off
  # through `GIT_CONFIG_PARAMETERS`, which outranks even local config), and that is a broken premise rather
  # than a legitimate host setting — red is the honest verdict, because the assertion ran on nothing.
  _mv="$_t/renamed"; mkdir -p "$_mv/src/auth"
  git -C "$_mv" init -q >/dev/null 2>&1
  git -C "$_mv" config user.email obl@test.local
  git -C "$_mv" config user.name obl-test
  git -C "$_mv" config diff.renames true            # pin the leg's premise; local beats a host global
  printf 'export function login(u, p) {\n  return check(u, p);\n}\n' > "$_mv/src/auth/login.js"
  git -C "$_mv" add -A >/dev/null 2>&1; git -C "$_mv" commit -qm seed >/dev/null 2>&1
  git -C "$_mv" branch -M main >/dev/null 2>&1      # a resolvable base for merge-base HEAD main
  git -C "$_mv" checkout -q -b feat >/dev/null 2>&1
  mkdir -p "$_mv/src/gate"
  git -C "$_mv" mv src/auth/login.js src/gate/login.js >/dev/null 2>&1
  git -C "$_mv" commit -qm rename >/dev/null 2>&1
  # LIVENESS: the DESTINATION path is NOT on the surface, so a change-set containing only it reads N/A.
  # Without this the assertion below could be green because `src/gate/login.js` matched `*auth*`.
  printf 'src/gate/login.js\n' > "$_t/mvdest"
  if ! obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/mvdest" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: the rename DESTINATION is itself on the surface — the rename leg below would be green for free"; rc=1
  fi
  _mvbase="$(git -C "$_mv" merge-base HEAD main 2>/dev/null || true)"
  # DO NOT "FIX" THE MISSING --no-renames ON THE NEXT LINE. It deliberately omits the flag because it
  # MEASURES collapse: it is the premise assertion proving the fixture WOULD collapse without the fix.
  # Adding the flag would make this selftest's own premise vacuous and the assertion below would then run
  # on nothing while the OK banner still credited it.
  _mvdefault="$(git -C "$_mv" diff --name-only "$_mvbase"...HEAD 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${_mvdefault:-0}" != 1 ]; then
    echo "OBL SELFTEST FAIL: the fixture move did not collapse into a rename (it lists ${_mvdefault:-0} paths, not 1) even with diff.renames pinned true in the fixture repo — the assertion below would have run on nothing while the OK banner still credited it"; rc=1
  elif ( cd "$_mv" && obligation_gate --name t --surface-globs '*auth*' \
           --record R.md --template-marker T --root "$_mv" ) >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a change-set whose ONLY change is a git mv OFF a sensitive path was wrongly N/A — rename detection is ON by default and emits the destination only, so the derivation must pass --no-renames"; rc=1
  fi

  # ---- NEWLINE-IN-FILENAME derive failure. `tr '\0' '\n'` SPLITS a path whose NAME contains a literal
  # newline, and each fragment is then matched against the surface globs separately — so a path that
  # WOULD trigger can be split into fragments that match nothing, silently under-triggering the
  # obligation. obl_changeset now treats a newline byte in the `-z` stream as a DERIVE FAILURE, which
  # routes to `--force-uncertain` and REQUIRES the record. This leg is the load-bearing negative for that
  # detector: without it, the detector is behaviourally correct but observed by NOTHING (found in review —
  # the sibling check `ratification-parity.sh` had the identical gap, fixed at the same time).
  _nlr="$_t/nlrepo"
  mkdir -p "$_nlr/docs"
  ( cd "$_nlr" && git init -q && git config user.email t@t && git config user.name t \
      && printf 'x\n' > docs/base.md && git add -A && git commit -q -m base && git branch -M main \
      && git checkout -q -b feat ) >/dev/null 2>&1
  # NOTE: the crafted commit MUST land on a BRANCH, not on main. Committing it on main makes
  # `main...HEAD` EMPTY, the derivation succeeds with a null change-set, and the leg then passes without
  # ever exercising the detector — measured (the mutant survived). Same class as the untracked-file
  # fixture error in promotion-readiness-wired.sh's no-base leg.
  # A name whose fragments match NOTHING on the surface: pre-detector this derived N/A and the obligation
  # was silently skipped; post-detector the derive failure requires the record.
  _nlname=$(printf 'docs/a\nb.md')
  if ( cd "$_nlr" && printf 'y\n' > "$_nlname" && git add -A && git commit -q -m crafted ) >/dev/null 2>&1; then
    # PREMISE: the fixture must really carry a newline, else the leg proves nothing.
    _nlbytes=$( ( cd "$_nlr" && git diff --name-only -z --no-renames main...HEAD 2>/dev/null | LC_ALL=C tr -cd '\n' | wc -c | tr -d ' ' ) )
    # Assert the FLAG directly, in-process. Going through obligation_gate's exit code is too indirect: a
    # non-zero can mean "obligation required" OR any other refusal, so the mutant survived that form
    # (measured twice). `OBL_DERIVE_FAIL` is the exact state the detector sets and the caller reads.
    _nlflag=$( cd "$_nlr" && OBL_DERIVE_FAIL=0; obl_changeset >/dev/null 2>&1 || true; printf '%s' "${OBL_DERIVE_FAIL:-0}" )
    _nlset=$( cd "$_nlr" && OBL_DERIVE_FAIL=0; obl_changeset 2>/dev/null | tr '\n' '|' )
    if [ "${_nlbytes:-0}" -lt 1 ]; then
      echo "OBL SELFTEST FAIL: the newline fixture carries NO newline byte in its derived stream — the derive-failure leg below proves nothing"; rc=1
    elif [ "$_nlflag" != 1 ]; then
      echo "OBL SELFTEST FAIL: a change-set carrying a NEWLINE in a path name did NOT set OBL_DERIVE_FAIL (got '$_nlflag'); tr splits such a path into fragments that can match no surface glob, so it must fail CLOSED and require the record. Derived: [$_nlset]"; rc=1
    fi
  else
    echo "OBL SELFTEST FAIL: could not build a newline-in-filename fixture — the derive-failure leg did not run (do NOT read this as a pass)"; rc=1
  fi

  # ---- RECORD-FLOOR (OBLIGATION-RECORD-FLOOR). Before the floor, obl_is_placeholder treated ANY readable
  # file carrying no placeholder signal as filled — so `touch THREAT-MODEL.md` satisfied every obligation
  # gate. That is a CHEAPER bypass than the banner-delete the template tightening has twice been built to
  # close, and it applied to all three obligations at once. The floor is STRUCTURAL only (>=1 markdown
  # heading AND >= OBL_MIN_SUBSTANCE_LINES non-blank lines); eight lines of prose still passes, so this
  # measures substance, never quality — review backstops that, and the check header says so.
  # The two BOUNDARY legs are the point of this test: both are DERIVED from $OBL_MIN_SUBSTANCE_LINES,
  # never hardcoded, so retuning the constant moves BOTH sides with it and a `-lt`/`-le` flip in the
  # implementation is killed by one of them. A fixture landing merely NEAR the floor proves nothing.
  printf 'src/auth/login.js\n' > "$_t/changed"
  : > "$_t/R.md"                                   # zero-byte record
  if obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: an EMPTY record was accepted as filled (the \`touch\` bypass is open)"; rc=1
  fi
  printf '# Threat Model\n' > "$_t/R.md"           # one-line record: a heading and nothing else
  if obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a ONE-LINE record was accepted as filled"; rc=1
  fi
  # BOUNDARY (below): exactly OBL_MIN_SUBSTANCE_LINES-1 non-blank lines, WITH a heading -> must RED.
  # The fixture's own line count is asserted first: an off-by-one in the GENERATOR would otherwise let
  # this leg claim a boundary it never lands on (the exact defect a "near the floor" fixture hides).
  { echo '# Threat Model'
    _i=2; while [ "$_i" -lt "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "line $_i"; _i=$((_i+1)); done; } > "$_t/R.md"
  _fx=$(grep -c '[^[:space:]]' "$_t/R.md" || true)
  [ "${_fx:-0}" = "$((OBL_MIN_SUBSTANCE_LINES - 1))" ] \
    || { echo "OBL SELFTEST FAIL: the floor-1 fixture has $_fx non-blank lines, not $((OBL_MIN_SUBSTANCE_LINES - 1)) — it does not land ON the boundary"; rc=1; }
  if obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a record at floor-1 non-blank lines was accepted as filled"; rc=1
  fi
  # BOUNDARY (on): exactly OBL_MIN_SUBSTANCE_LINES non-blank lines, WITH a heading -> must PASS. This is
  # the false-positive half, and what it kills is the COMPARISON DIRECTION: flip `-lt` to `-le` in the
  # implementation and this leg reds (measured). It does NOT protect the constant's VALUE — an earlier
  # version of this comment claimed "without it the floor could be raised arbitrarily and nothing would
  # notice", which is false in both directions: WITH it, 8->7, 8->9 and 8->12 all left the entire suite
  # green (measured), because both boundary fixtures derive from the constant and move with it. The
  # CALIBRATION leg further down is what pins the value.
  { echo '# Threat Model'
    _i=2; while [ "$_i" -le "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "line $_i"; _i=$((_i+1)); done; } > "$_t/R.md"
  _fx=$(grep -c '[^[:space:]]' "$_t/R.md" || true)
  [ "${_fx:-0}" = "$OBL_MIN_SUBSTANCE_LINES" ] \
    || { echo "OBL SELFTEST FAIL: the on-floor fixture has $_fx non-blank lines, not $OBL_MIN_SUBSTANCE_LINES — it does not land ON the boundary"; rc=1; }
  if ! obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a record exactly AT the floor was wrongly rejected as a placeholder"; rc=1
  fi
  # Substance without STRUCTURE: enough non-blank lines but no markdown heading -> must RED. Kills a
  # line-count-only implementation. Deliberately NOT keyed on a per-record heading STRING (e.g.
  # '# Threat Model') — that would re-introduce the record-vocabulary coupling the engine is shedding.
  { _i=1; while [ "$_i" -le "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "prose line $_i"; _i=$((_i+1)); done; } > "$_t/R.md"
  if obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a heading-less record was accepted as filled"; rc=1
  fi
  # SETEXT HEADING: a title underlined with `===` is a CommonMark-legal heading, and the first version of
  # this floor RED-ed on it (measured). A gate that reds on compliant behavior is a gate that gets deleted,
  # so the heading test accepts the setext form too and THIS leg locks that in — without it, "simplifying"
  # the pattern back to `^#` would silently re-break every setext-authored record.
  { echo 'A11y Sign-off'
    echo '============='
    _i=3; while [ "$_i" -le "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "line $_i"; _i=$((_i+1)); done; } > "$_t/R.md"
  _fx=$(grep -c '[^[:space:]]' "$_t/R.md" || true)
  [ "${_fx:-0}" = "$OBL_MIN_SUBSTANCE_LINES" ] \
    || { echo "OBL SELFTEST FAIL: the setext fixture has $_fx non-blank lines, not $OBL_MIN_SUBSTANCE_LINES — it does not sit at the floor, so a PASS here would not be attributable to the heading"; rc=1; }
  if grep -q '^#' "$_t/R.md"; then
    echo "OBL SELFTEST FAIL: the setext fixture carries an ATX '#' heading — it does not probe the setext path at all"; rc=1
  fi
  if ! obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a record whose heading is a setext underline (CommonMark-legal) was rejected as a placeholder"; rc=1
  fi

  # ---- DIAGNOSTIC ATTRIBUTION. Every Signal-3 rejection used to print "is still the unfilled template —
  # fill it". For a record the author hand-wrote and considers complete that text is false AND offers no
  # route to a fix: it names a template they never used. These legs assert the FAIL text matches the signal
  # that actually fired. They also make the diagnostic a tested surface, so a later reword cannot quietly
  # regress it back to one message for every cause.
  printf '# A11y Sign-off\nAll checks pass.\n' > "$_t/R.md"     # heading, but only 2 non-blank lines
  _msg="$(obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
            --changed "$_t/changed" --root "$_t" 2>&1 || true)"
  case "$_msg" in
    *"non-blank line"*) ;;
    *) echo "OBL SELFTEST FAIL: a FLOOR rejection did not report the line count that caused it — it said: $_msg"; rc=1 ;;
  esac
  case "$_msg" in
    *"unfilled template"*) echo "OBL SELFTEST FAIL: a FLOOR rejection was reported as an unfilled template — the author never used a template: $_msg"; rc=1 ;;
  esac
  { _i=1; while [ "$_i" -le "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "prose line $_i"; _i=$((_i+1)); done; } > "$_t/R.md"
  _msg="$(obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
            --changed "$_t/changed" --root "$_t" 2>&1 || true)"
  case "$_msg" in
    *"no markdown heading"*) ;;
    *) echo "OBL SELFTEST FAIL: a heading-less rejection did not say the heading was what was missing — it said: $_msg"; rc=1 ;;
  esac
  # …and the converse: Signals 1-2 MUST keep the template wording. Those records genuinely ARE the
  # unfilled template, and "fill it" is the correct instruction. Without this leg the fix above could
  # over-reach and describe every rejection as a floor miss.
  printf '> **Template.**\n' > "$_t/R.md"
  _msg="$(obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
            --changed "$_t/changed" --root "$_t" 2>&1 || true)"
  case "$_msg" in
    *"unfilled template"*) ;;
    *) echo "OBL SELFTEST FAIL: an unfilled-TEMPLATE record lost the template wording — it said: $_msg"; rc=1 ;;
  esac
  # The L2 (present-but-unreadable) path is a THIRD cause and was also printing the template text. It is
  # permission-dependent: a uid that bypasses file permissions (root, some containers) can still read a
  # 0000 file, so the fixture is CHECKED before it is trusted and the leg says so out loud rather than
  # passing vacuously — a leg that cannot run must not look like a leg that ran.
  printf '# R\nunreadable fixture\n' > "$_t/R.md"; chmod 000 "$_t/R.md"
  if [ -r "$_t/R.md" ]; then
    echo "OBL SELFTEST NOTE: uid $(id -u) bypasses file permissions — the unreadable-record diagnostic leg could NOT run here"
  else
    _msg="$(obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
              --changed "$_t/changed" --root "$_t" 2>&1 || true)"
    case "$_msg" in
      *"not readable"*) ;;
      *) echo "OBL SELFTEST FAIL: an unreadable record was not reported as unreadable — it said: $_msg"; rc=1 ;;
    esac
    # R2-5: the unreadable text was the ONLY one of the three that omitted the ($tmpl) template-marker
    # suffix, so the one rejection an author is least likely to understand was also the one that did not
    # point at the template. Asserted here rather than in its own leg because this is the only place the
    # unreadable path can be reached, and that makes the assertion PERMISSION-DEPENDENT: on a uid that
    # bypasses file permissions it does not run at all (the branch above says so out loud).
    case "$_msg" in
      *"(T)"*) ;;
      *) echo "OBL SELFTEST FAIL: the unreadable-record FAIL did not name the template marker, unlike the other two — it said: $_msg"; rc=1 ;;
    esac
  fi
  chmod 644 "$_t/R.md"

  # ---- SIGNAL-2 VOCABULARY (OBLIGATION-STUB-PATTERN). Signal 2 used to be HARDCODED to THREAT-MODEL's
  # bracket vocabulary, so every OTHER obligation's template had to be authored to trip Signal 1 instead.
  # That workaround has already failed once: the a11y template reached review carrying `[describe:` (colon),
  # and Signal 1's `describe ` alternative needs a TRAILING SPACE, so that cell was inert. A REVIEW ROUND
  # caught it — at the time no check could. MEASURED on this tree, on the TRUE production path (real repo,
  # KIT_OBL_TEST unset, the real wrapper): the shipped A11Y-SIGNOFF template, banner-stripped with every
  # cell filled EXCEPT a single `[describe: …]`, is reported
  # "PASS: a11y surface touched and a filled A11Y-SIGNOFF.md is present". One stub is below Signal 2's
  # threshold of 3 and invisible to Signal 1, and the record clears the floor — so nothing caught it.
  # DO NOT read that arc as "the parameter would have caught it" — measured, it would NOT (one stub is
  # under the threshold of 3 whatever the vocabulary). The parameter's actual value is the >=3-cell case
  # and retiring the author-to-Signal-1 obligation; the SINGLE-cell case is covered by a different
  # mechanism, a11y-obligation.sh LEG 8 (per-cell), not by this. Both claims are laid out at
  # $OBL_DEFAULT_STUB_PATTERN's declaration above.
  # Every fixture below is DERIVED from $OBL_MIN_SUBSTANCE_LINES, so a retune moves it rather than
  # invalidating it. CUSTOM.md's non-blank count is asserted outright; the other three (CUSTOM2, THREAT,
  # DECOY) each have a leg REQUIRING them to PASS, which they cannot do unless they clear the floor. So a
  # RED anywhere in this section is attributable to Signal 2 and never to the floor.
  printf 'src/auth/login.js\n' > "$_t/changed"
  _cvp='\[(attach|evidence owner|rollout window)'   # a vocabulary NO shipped template uses
  _noop='\[zzz-no-such-stub-token'                  # a vocabulary nothing in these fixtures can match
  # EXACTLY 3 custom stubs — Signal 2's threshold, so the fixture lands ON the boundary, not near it.
  { echo '# Deployment Record'
    echo '| Diagram | [attach: architecture diagram] |'
    echo '| Owner   | [evidence owner: name] |'
    echo '| Window  | [rollout window: date] |'
    _i=5; while [ "$_i" -le "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "line $_i"; _i=$((_i+1)); done; } > "$_t/CUSTOM.md"
  _fx=$(grep -c '[^[:space:]]' "$_t/CUSTOM.md" || true)
  [ "${_fx:-0}" = "$OBL_MIN_SUBSTANCE_LINES" ] \
    || { echo "OBL SELFTEST FAIL: the custom-vocabulary fixture has $_fx non-blank lines, not $OBL_MIN_SUBSTANCE_LINES — it does not sit at the floor, so a verdict on it would not be attributable to Signal 2"; rc=1; }
  # (a) DEFAULT UNCHANGED — the regression lock, and the leg that makes (b) attributable. With NO
  # --stub-pattern this record must PASS: it trips neither Signal 1 (no fill/todo/replace/`your `/`describe `
  # token) nor the DEFAULT threat vocabulary, and it sits ON the floor. If any other signal fired here,
  # (b)'s RED would prove nothing about the parameter.
  if ! obligation_gate --name t --surface-globs '*auth*' --record CUSTOM.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a record using its OWN bracket vocabulary was rejected with no --stub-pattern — the parameter's default is not today's behaviour"; rc=1
  fi
  # (b) …and the SAME record, with ONLY --stub-pattern added, must be caught.
  if obligation_gate --name t --surface-globs '*auth*' --record CUSTOM.md --template-marker T \
       --stub-pattern "$_cvp" --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: --stub-pattern named the record's OWN stub vocabulary and the unfilled record still PASSed"; rc=1
  fi
  # (c) THRESHOLD FROM BELOW: two custom stubs is under Signal 2's >=3, so the same vocabulary must PASS.
  # Pins the comparison on the parameterised path exactly as the floor's boundary legs pin theirs — without
  # it, a `-ge 3` widened to `-ge 1` would ship green.
  { echo '# Deployment Record'
    echo '| Diagram | [attach: architecture diagram] |'
    echo '| Owner   | [evidence owner: name] |'
    _i=4; while [ "$_i" -le "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "line $_i"; _i=$((_i+1)); done; } > "$_t/CUSTOM2.md"
  if ! obligation_gate --name t --surface-globs '*auth*' --record CUSTOM2.md --template-marker T \
       --stub-pattern "$_cvp" --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: two custom stubs — BELOW Signal 2's threshold of 3 — were treated as unfilled"; rc=1
  fi
  # (c2) A pattern BEGINNING WITH `-`. Now that the vocabulary is a variable, an unguarded
  # `grep -oE "$_pat"` reads it as an OPTION, grep exits 2, the `2>/dev/null` swallows the usage error and
  # the empty output makes the stub count zero — Signal 2 silently OFF. A fail-OPEN introduced by the very
  # parameter this task adds, so it gets its own leg. `-*\[(…)` is ERE-equivalent to `\[(…)` (`-*` matches
  # zero or more dashes) but starts with a dash, so it probes the parsing and not the matching: this record
  # must still be caught. Strip the `-e` from the implementation and this leg reds.
  if obligation_gate --name t --surface-globs '*auth*' --record CUSTOM.md --template-marker T \
       --stub-pattern '-*\[(attach|evidence owner|rollout window)' --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a --stub-pattern beginning with '-' was swallowed as a grep option — Signal 2 silently switched OFF (fail-open)"; rc=1
  fi
  # (c3) A MALFORMED ERE — the SECOND route into the same swallowed `2>/dev/null`, and by far the likelier
  # one. The intended shape is `\[(a|b|c)`; drop the closing paren and grep exits 2 exactly as it does for
  # an unknown option, the redirect eats the diagnostic, `_n` is 0 and Signal 2 is SILENTLY OFF. The trigger
  # is not an attacker but the NEXT wrapper author: a one-character typo shipping an inert detector, green
  # through CI — precisely the defect class the parameter exists to prevent. MEASURED before the fix, on the
  # 3-stub CUSTOM.md fixture below: `\[(attach|evidence owner|rollout window` , `\[(attach` and `[` each
  # made it read FILLED (raw grep rc=2 for all three); the well-formed pattern read PLACEHOLDER.
  # PRECONDITION, asserted per shape rather than assumed: this leg's premise is "grep rejects this pattern",
  # so a platform whose grep COMPILES one is not probing what the leg claims. It says so out loud and skips
  # that shape — and the counter below reds if EVERY shape was skipped, so the leg cannot go silently vacuous.
  _mal_ran=0
  for _mal in '\[(attach|evidence owner|rollout window' '\[(attach' '['; do
    _mrc=0; printf '' | grep -qE -e "$_mal" 2>/dev/null || _mrc=$?
    if [ "$_mrc" -lt 2 ]; then
      echo "OBL SELFTEST NOTE: this platform's grep compiles a pattern this leg expects to be invalid (exit $_mrc) — that shape could not be probed here"
      continue
    fi
    _mal_ran=$((_mal_ran + 1))
    if obligation_gate --name t --surface-globs '*auth*' --record CUSTOM.md --template-marker T \
         --stub-pattern "$_mal" --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
      echo "OBL SELFTEST FAIL: a MALFORMED --stub-pattern PASSed — grep's exit 2 was swallowed by the 2>/dev/null and Signal 2 switched silently OFF (fail-open)"; rc=1
    fi
  done
  [ "$_mal_ran" -ge 1 ] \
    || { echo "OBL SELFTEST FAIL: no malformed-pattern shape could be probed on this platform — the fail-closed assertion ran on nothing"; rc=1; }
  # …and the rejection says WHAT is wrong (a bad pattern, not an unfilled record) WITHOUT echoing the
  # pattern back. A gate verdict must never render caller-supplied text — the same rule a11y-obligation.sh
  # LEG 8 applies to template-controlled text, applied here to an argument.
  _msg="$(obligation_gate --name t --surface-globs '*auth*' --record CUSTOM.md --template-marker T \
            --stub-pattern '\[(attach' --changed "$_t/changed" --root "$_t" 2>&1 || true)"
  case "$_msg" in
    *"not a valid"*) ;;
    *) echo "OBL SELFTEST FAIL: a malformed --stub-pattern was not reported as a bad pattern — it said: $_msg"; rc=1 ;;
  esac
  case "$_msg" in
    *'[(attach'*) echo "OBL SELFTEST FAIL: the malformed pattern was echoed back into the verdict — a gate verdict must never render caller-supplied text: $_msg"; rc=1 ;;
  esac
  # (c3b) THE ORDER of the compile probe — a SURVIVING MUTANT until this leg existed. obl_is_placeholder
  # runs the probe BEFORE every record signal, and the reason is stated in prose right above it: otherwise
  # a WRAPPER's malformed-pattern typo is reported as THE AUTHOR's unfilled template, sending them to fix a
  # record that is not the problem. That ordering was asserted in prose and proven by NOTHING: moving the
  # probe from before Signal 1 to after Signal 2 SURVIVED the entire suite, because every malformed-pattern
  # leg above uses CUSTOM.md — a record that trips no OTHER signal, so it cannot observe the order at all.
  # This fixture is the one that can: it carries the `> **Template.**` banner (Signal 1 fires) AND clears
  # the substance floor (so Signal 3 cannot be the cause of anything here). Under the shipped order the
  # verdict is the pattern one; under ANY reordering that puts the probe after a record signal it becomes
  # "unfilled template". Re-verified by mutation during this build: probe moved after Signal 2 -> this leg
  # reds and nothing else in the suite does.
  { echo '> **Template.**'
    echo '# Deployment Record'
    _i=3; while [ "$_i" -le "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "line $_i"; _i=$((_i+1)); done; } > "$_t/BANNER.md"
  _fx=$(grep -c '[^[:space:]]' "$_t/BANNER.md" || true)
  [ "${_fx:-0}" = "$OBL_MIN_SUBSTANCE_LINES" ] \
    || { echo "OBL SELFTEST FAIL: the banner fixture has $_fx non-blank lines, not $OBL_MIN_SUBSTANCE_LINES — it does not clear the floor, so a verdict on it would not be attributable to the signal ORDER"; rc=1; }
  # LIVENESS: with NO --stub-pattern this record really IS reported as an unfilled template, so the
  # assertion below is caused by the ORDER and not by a fixture that fails to trip Signal 1 at all.
  _msg="$(obligation_gate --name t --surface-globs '*auth*' --record BANNER.md --template-marker T \
            --changed "$_t/changed" --root "$_t" 2>&1 || true)"
  case "$_msg" in
    *"unfilled template"*) ;;
    *) echo "OBL SELFTEST FAIL: the banner-carrying fixture is not reported as an unfilled template — the probe-ordering leg below would be vacuous: $_msg"; rc=1 ;;
  esac
  # PRECONDITION, asserted rather than assumed (the same reason (c3) probes each shape): this leg's premise
  # is "grep rejects this pattern", so a platform whose grep compiles it is not probing what the leg claims.
  _mrc=0; printf '' | grep -qE -e '\[(attach' 2>/dev/null || _mrc=$?
  if [ "$_mrc" -lt 2 ]; then
    echo "OBL SELFTEST NOTE: this platform's grep compiles the pattern this leg expects to be invalid (exit $_mrc) — the probe-ordering leg could NOT run here"
  else
    _msg="$(obligation_gate --name t --surface-globs '*auth*' --record BANNER.md --template-marker T \
              --stub-pattern '\[(attach' --changed "$_t/changed" --root "$_t" 2>&1 || true)"
    case "$_msg" in
      *"not a valid"*) ;;
      *) echo "OBL SELFTEST FAIL: a malformed --stub-pattern on a record that ALSO trips Signal 1 was not reported as a bad pattern — the compile probe has moved BELOW the record signals: $_msg"; rc=1 ;;
    esac
    case "$_msg" in
      *"unfilled template"*) echo "OBL SELFTEST FAIL: a CONFIGURATION fault (a malformed --stub-pattern) was blamed on the record's author as an unfilled template — the compile probe must run BEFORE every record signal: $_msg"; rc=1 ;;
    esac
  fi
  # (c4) An EMPTY --stub-pattern. `${2:-…}` treats empty as unset, so an empty value fell back to the
  # DEFAULT (threat) vocabulary WHILE the seen-flag recorded that a pattern had been supplied: a wrapper
  # writing `--stub-pattern "$SOME_VAR"` with an unset var silently got another obligation's stub set.
  # MEASURED before the fix: verdict-identical to omitting the flag. Refused, never defaulted. Leg (a) above
  # is the liveness pair — the SAME record PASSes with the flag omitted, so this RED is attributable to the
  # empty VALUE and not to the record.
  if obligation_gate --name t --surface-globs '*auth*' --record CUSTOM.md --template-marker T \
       --stub-pattern '' --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: an EMPTY --stub-pattern was silently defaulted to another obligation's vocabulary instead of being refused"; rc=1
  fi
  _msg="$(obligation_gate --name t --surface-globs '*auth*' --record CUSTOM.md --template-marker T \
            --stub-pattern '' --changed "$_t/changed" --root "$_t" 2>&1 || true)"
  case "$_msg" in
    *"--stub-pattern"*"empty"*) ;;
    *) echo "OBL SELFTEST FAIL: an empty --stub-pattern was not named as the cause — it said: $_msg"; rc=1 ;;
  esac
  # (d) The SHIPPED threat vocabulary must still fire through the DEFAULT path…
  { echo '# Threat Model'
    echo '| Summary  | [summary] |'
    echo '| Threat   | [threat] |'
    echo '| Boundary | [boundary 1] |'
    _i=5; while [ "$_i" -le "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "line $_i"; _i=$((_i+1)); done; } > "$_t/THREAT.md"
  if obligation_gate --name t --surface-globs '*auth*' --record THREAT.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a record left as THREAT-MODEL stubs PASSed on the default path — the shipped Signal-2 vocabulary is gone"; rc=1
  fi
  # (e) …and that RED is attributable to the PATTERN, not to Signal 1 or the floor: point --stub-pattern at
  # a vocabulary the record does not use and the same file must PASS. This is also the assertion that pins
  # REPLACE semantics — an implementation that OR-ed the parameter with the default would red here.
  if ! obligation_gate --name t --surface-globs '*auth*' --record THREAT.md --template-marker T \
       --stub-pattern "$_noop" --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: --stub-pattern did not REPLACE the default vocabulary — the threat stubs still fired under a pattern that cannot match them"; rc=1
  fi

  # ---- GATE-DEFINING ARGUMENTS: FIRST ASSIGNMENT WINS. The wrapper (threat-/uat-/a11y-obligation.sh)
  # supplies --name/--surface-globs/--record/--template-marker and then forwards "$@", so the wrapper's
  # values are ALWAYS the first assignment and anything a caller appends is a SECOND one. Ignoring the
  # second means `sh conformance/a11y-obligation.sh --record README.md` can no longer redirect the gate at
  # a benign file, and `--surface-globs '*nothing*'` can no longer turn it into a blanket N/A.
  # EVERY leg below is PAIRED with a LIVENESS run proving the decoy value WOULD have changed the verdict
  # had it been honoured. Without that pair a "still FAILs" assertion can be green because the decoy was
  # inert, which is the exact shape of test that proves nothing.
  { echo '# Decoy record'
    _i=2; while [ "$_i" -le "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "decoy line $_i"; _i=$((_i+1)); done; } > "$_t/DECOY.md"
  rm -f "$_t/R.md"                                   # the wrapper's own record is ABSENT -> the gate FAILs
  # --record, liveness: the decoy IS accepted as a filled record when it is the FIRST --record…
  if ! obligation_gate --name t --surface-globs '*auth*' --record DECOY.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: the decoy record is not itself accepted as filled — the --record hardening leg below would be vacuous"; rc=1
  fi
  # …and is IGNORED as a SECOND one. Under last-wins parsing this PASSes: that is the bypass being closed,
  # and this is the leg that bites. Mutating the parser back to last-wins reds HERE and nowhere else.
  if obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --record DECOY.md --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a SECOND --record redirected the gate to a decoy record — first assignment must win"; rc=1
  fi
  # --surface-globs, liveness: a non-matching surface really does read N/A…
  if ! obligation_gate --name t --surface-globs '*no-such-surface*' --record R.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a non-matching surface did not read N/A — the --surface-globs hardening leg below would be vacuous"; rc=1
  fi
  # …so a SECOND --surface-globs would widen the gate to N/A for every change-set. It must be ignored.
  if obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --surface-globs '*no-such-surface*' --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a SECOND --surface-globs widened the gate to N/A — first assignment must win"; rc=1
  fi
  # --stub-pattern, liveness: an unmatchable vocabulary really does disable Signal 2 for this record…
  if ! obligation_gate --name t --surface-globs '*auth*' --record CUSTOM.md --template-marker T \
       --stub-pattern "$_noop" --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: an unmatchable --stub-pattern did not disable Signal 2 — the hardening leg below would be vacuous"; rc=1
  fi
  # …so a SECOND --stub-pattern would silently disable Signal 2 for a wrapper that sets one. It is ignored.
  if obligation_gate --name t --surface-globs '*auth*' --record CUSTOM.md --template-marker T \
       --stub-pattern "$_cvp" --stub-pattern "$_noop" --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a SECOND --stub-pattern disabled Signal 2 — first assignment must win"; rc=1
  fi
  # --name / --template-marker are DIAGNOSTIC rather than gate-deciding, so they are proved on the FAIL
  # TEXT: a second value must not reach the message an author reads (a mislabelled gate sends them to the
  # wrong template). Same first-wins rule, cheapest possible observation of it.
  _msg="$(obligation_gate --name t --name evil --surface-globs '*auth*' --record R.md \
            --template-marker T --template-marker EVIL --changed "$_t/changed" --root "$_t" 2>&1 || true)"
  case "$_msg" in
    *"touches a t surface"*) ;;
    *) echo "OBL SELFTEST FAIL: a SECOND --name reached the FAIL text — it said: $_msg"; rc=1 ;;
  esac
  case "$_msg" in
    *"(T)"*) ;;
    *) echo "OBL SELFTEST FAIL: a SECOND --template-marker displaced the wrapper's marker — it said: $_msg"; rc=1 ;;
  esac
  case "$_msg" in
    *evil*|*EVIL*) echo "OBL SELFTEST FAIL: a caller-appended value leaked into the FAIL text — it said: $_msg"; rc=1 ;;
  esac
  # A DISCARD MUST BE ANNOUNCED. First-wins (and the sentinel below) invert POSIX's last-wins convention:
  # silently, a caller who typed --record X cannot tell that X did nothing. The NOTE goes to stderr and
  # names the FLAG ONLY — never the value, because several legs here capture stderr with 2>&1 and, more to
  # the point, a gate verdict must never render caller-supplied text. Both halves are asserted.
  _msg="$(obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
            --record DECOY.md --changed "$_t/changed" --root "$_t" 2>&1 || true)"
  case "$_msg" in
    *"NOTE:"*"--record"*) ;;
    *) echo "OBL SELFTEST FAIL: a discarded gate-defining argument was dropped SILENTLY — no NOTE: $_msg"; rc=1 ;;
  esac
  case "$_msg" in
    *DECOY*) echo "OBL SELFTEST FAIL: the discard NOTE echoed the caller's VALUE — a verdict must never render caller-supplied text: $_msg"; rc=1 ;;
  esac

  # ---- A VALUE-LESS FLAG MUST STILL PRODUCE A VERDICT (M-4/L2). Every two-argument branch of the parser
  # ends in `shift 2`, and `shift 2` with only the flag left FAILS. What that cost depends on the CALLER,
  # and both outcomes are wrong — the second one measurably worse than the review that found this recorded:
  #  - from the PRODUCTION entrypoint (`run_threat_obligation "$@"`, a simple command under `set -e`) the
  #    whole check aborts. MEASURED: `sh conformance/threat-obligation.sh --record` -> rc=1 carrying only
  #    the stderr NOTE and NO `FAIL:` line, on all six gate-defining flags; `--changed` and `--root` ->
  #    rc=1 and NO output at all. Fail-CLOSED, so never a bypass — but a check that dies mid-parse is
  #    indistinguishable from one that ran, and every verdict this kit records rests on that distinction.
  #  - from ANY caller that wraps the gate in a CONDITION or a command substitution — which is how
  #    obl_selftest, all three wrapper selftests and this leg itself call it — POSIX suppresses errexit for
  #    the whole subtree, so the failed `shift 2` leaves `$#` UNCHANGED and the parse loop SPINS FOREVER.
  #    MEASURED: `_msg="$(obligation_gate … --record 2>&1 || true)"` never returns; under `ulimit -t 15`
  #    the shell is killed by SIGXCPU (exit 152) having produced 0 bytes. A hung gate is not a fail-closed
  #    verdict, it is a gate that never reaches one — and in CI it burns the job's whole time budget.
  # So the arity is checked FIRST in each two-argument branch, before it touches `$2` or shifts, and the
  # gate returns a REFUSAL in the same shape as the other gate-defining refusals. The flag NAME is safe to
  # render — the `case` patterns are exact literals, so `$1` is this file's own text and never the
  # caller's (the rule _obl_ignored states) — and the missing value cannot be rendered, there isn't one.
  # ALL EIGHT two-argument flags are covered, the two FIXTURE flags included: they take a value and shift
  # by two exactly like the other six, and in production mode they parse-but-ignore and then shift anyway.
  # The liveness pair for this whole leg is the entire suite above: every one of those calls supplies its
  # values and reaches a real verdict, so a RED here cannot be a parser that refuses everything.
  # BOTH HALVES are asserted — the verdict TEXT and the exit STATUS — because they fail to different
  # mutants. Neutering _obl_need_value's `return 1` to `return 0` still emits the message (so a text-only
  # assertion survives it) while letting the branch fall through to the very `shift 2` this guard exists to
  # prevent. `|| _vrc=$?` and not `$?` after the assignment: the OR-list captures the status in the very
  # next word, and POSIX exempts every command of an AND-OR list but the last from errexit.
  for _vl in --name --surface-globs --record --template-marker --stub-pattern --exclude-globs \
             --changed --root; do
    _vrc=0
    _msg="$(obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
              --changed "$_t/changed" --root "$_t" "$_vl" 2>&1)" || _vrc=$?
    case "$_msg" in
      *"FAIL:"*"$_vl"*value*) ;;
      *) printf 'OBL SELFTEST FAIL: the gate-defining flag %s supplied with NO value did not produce a verdict naming it — the parse died (or span) instead. It said: [%s]\n' "$_vl" "$_msg"; rc=1 ;;
    esac
    [ "$_vrc" -ne 0 ] \
      || { printf 'OBL SELFTEST FAIL: %s with NO value was ANNOUNCED but not REFUSED (rc=0) — the guard printed its verdict and let the branch fall through to the shift it exists to prevent\n' "$_vl"; rc=1; }
  done

  # ---- THE '--' SENTINEL. First-assignment-wins can only defend an argument the WRAPPER SETS. No shipped
  # wrapper passes --stub-pattern, so a caller-supplied one WAS the first assignment and was honoured —
  # measured on the true production path, `sh conformance/threat-obligation.sh` FAILed and the same command
  # with `--stub-pattern '\[zzz'` appended PASSed, on all three wrappers. Shipping a new bypass in a
  # hardening slice contradicts the slice's own thesis, so each wrapper now emits `--` after its own
  # definition and the six gate-defining arguments are honoured only BEFORE it. Strictly stronger than
  # first-wins: it also defends arguments a wrapper does not set. Both rules are kept (defence in depth) —
  # they cannot conflict, because a wrapper's own values are always pre-sentinel AND always first.
  # obl_selftest calls obligation_gate DIRECTLY (no sentinel), which is why the first-wins legs above still
  # exercise the first-wins rule; the legs below add the `--` explicitly.
  # The decoy here is --stub-pattern SPECIFICALLY: it is the one argument first-wins does NOT already
  # defend in these fixtures, so a RED here is attributable to the sentinel alone. THREAT.md is the record
  # because legs (d)/(e) above already prove the pair this needs — it FAILs on the default vocabulary and
  # PASSes under $_noop — so $_noop is a decoy with proven potency, not an inert one.
  if obligation_gate --name t --surface-globs '*auth*' --record THREAT.md --template-marker T \
       -- --stub-pattern "$_noop" --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a --stub-pattern supplied AFTER the '--' sentinel disabled Signal 2 — post-sentinel gate-defining arguments must be ignored"; rc=1
  fi
  # …and the sentinel fences ONLY those six. Every wrapper forwards "$@" after its own `--`, so if `--`
  # ended argument parsing outright, the fixture flags would die with it and LEG 1 of all three wrapper
  # selftests would red. Proven here directly, with its liveness pair: a post-sentinel --changed pointing
  # at a NON-triggering change-set must still be honoured (-> N/A PASS) for a record that does not exist…
  if ! obligation_gate --name t --surface-globs '*auth*' --record NO-SUCH-RECORD.md --template-marker T \
       --changed "$_t/changed" -- --changed "$_t/none" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: --changed after the '--' sentinel was dropped — the sentinel must fence only the six gate-defining arguments"; rc=1
  fi
  # …and WITHOUT that post-sentinel override the very same call FAILs, so the PASS above is caused by the
  # forwarded flag and not by the record or the surface.
  if obligation_gate --name t --surface-globs '*auth*' --record NO-SUCH-RECORD.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a triggered change-set with an absent record PASSed — the post-sentinel --changed leg above would be vacuous"; rc=1
  fi

  # ---- A GATE WITH NO SURFACE IS REFUSED, not silently disabled. Same class as the empty --stub-pattern
  # at (c4) and found by asking the same question of the other five gate-defining arguments: an empty
  # --surface-globs matches nothing, so obl_detect returns 'none' and EVERY change-set reads N/A — a
  # blanket PASS with no record ever required, which is the most complete fail-OPEN this engine has.
  # MEASURED before this guard: `obligation_gate --surface-globs '' --record NOPE.md` on a TRIGGERING
  # change-set with the record ABSENT returned rc=0 (N/A). Not reachable from the three shipped wrappers —
  # all three pass a literal string — but a11y-obligation.sh already holds its surface in a VARIABLE
  # ($A11Y_SURFACE_GLOBS), so it is one bad edit away, and that is exactly the shape M-3 describes for
  # --stub-pattern. Applied symmetrically rather than left to be discovered.
  # The other four need no such rule and deliberately do not get one: an empty --record reds as absent
  # (measured), --name/--template-marker are diagnostic only, and an empty --exclude-globs excludes
  # NOTHING — the stricter direction, so refusing it would buy nothing (its refusal is at the other end,
  # a glob matching every path; see its own leg below).
  # The liveness pair is the leg immediately above — the same call with a real surface FAILs — so a PASS
  # here is caused by the empty surface and not by the fixture.
  if obligation_gate --name t --surface-globs '' --record NO-SUCH-RECORD.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: an EMPTY --surface-globs turned a triggering change-set into a blanket N/A — a gate with no surface must be refused, not silently disabled"; rc=1
  fi
  # …and the same refusal when the surface is never DEFINED at all, which a sentinel placed first produces.
  if obligation_gate -- --name t --surface-globs '*auth*' --record NO-SUCH-RECORD.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a gate whose surface was never defined (a '--' sentinel placed first) read N/A instead of being refused"; rc=1
  fi
  # …and the same refusal for a surface that is NON-EMPTY but defines no glob. `[ -n "$globs" ]` is a
  # WEAKER predicate than "defines at least one usable glob", and the gap is the same blanket-N/A fail-open
  # the two legs above close, reached by a different route. MEASURED on the previous implementation, record
  # absent and a change-set that triggers '*auth*': `--surface-globs '|'` -> N/A, `'||'` -> N/A, `' '` ->
  # N/A, while the control `'*auth*'` correctly FAILed. Narrow (the realistic trigger, an unset variable,
  # was already closed) but free now that the emptiness test walks the same split obl_detect matches on.
  for _degen in '|' '||' ' ' '|  |'; do
    if obligation_gate --name t --surface-globs "$_degen" --record NO-SUCH-RECORD.md --template-marker T \
         --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
      printf 'OBL SELFTEST FAIL: --surface-globs [%s] is non-empty but defines no glob, and it was accepted and read as a blanket N/A\n' "$_degen"; rc=1
    fi
  done
  # …and the converse, so the rule above cannot over-reach into rejecting real surfaces: a list carrying a
  # blank field ALONGSIDE a real glob is still a usable surface, and it still gates.
  if obligation_gate --name t --surface-globs '|*auth*|' --record NO-SUCH-RECORD.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a surface with stray separators around a REAL glob was refused or read N/A — the non-blank-glob rule has over-reached"; rc=1
  fi

  # ---- --exclude-globs (OBLIGATION-CONFIG-TEMPLATE-EXT) IS AN OFF-SWITCH, so it ships fenced by BOTH
  # rules from day one. T3's finding was that a caller-supplied off-switch on a VARIABLE-held argument is
  # the reachable shape (no wrapper set --stub-pattern, so a caller's was the FIRST assignment and was
  # honoured); an exclusion list is the most dangerous possible instance of that shape, because honouring
  # one turns any triggering change-set into an N/A. It is therefore the SIXTH gate-defining argument.
  printf 'app/templates/index.j2\n' > "$_t/j2"
  # LIVENESS: the decoy exclusion really would flip this verdict when it is the gate's OWN first one.
  # Record absent + a triggering path, so without the exclusion a FAIL is certain.
  if ! obligation_gate --name t --surface-globs '*.j2' --exclude-globs '*index*' \
       --record NO-SUCH-RECORD.md --template-marker T --changed "$_t/j2" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: the decoy exclusion does not itself produce an N/A — every --exclude-globs hardening leg below would be vacuous"; rc=1
  fi
  if obligation_gate --name t --surface-globs '*.j2' \
       --record NO-SUCH-RECORD.md --template-marker T --changed "$_t/j2" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a triggering path with an absent record PASSed with no exclusion at all — the liveness pair above proves nothing"; rc=1
  fi
  # FIRST ASSIGNMENT WINS — a caller appending a second --exclude-globs must not widen the gate.
  if obligation_gate --name t --surface-globs '*.j2' --exclude-globs '*no-such-exclusion*' \
       --record NO-SUCH-RECORD.md --template-marker T --exclude-globs '*index*' \
       --changed "$_t/j2" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a SECOND --exclude-globs widened the gate to N/A — first assignment must win"; rc=1
  fi
  # THE '--' SENTINEL — and this is the rule that actually matters here, because no wrapper is obliged to
  # set --exclude-globs at all (threat-obligation.sh and uat-obligation.sh do not), so without the sentinel
  # a caller's would be the FIRST assignment and would be honoured. Exactly the T3 shape.
  if obligation_gate --name t --surface-globs '*.j2' \
       --record NO-SUCH-RECORD.md --template-marker T \
       -- --exclude-globs '*index*' --changed "$_t/j2" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: an --exclude-globs supplied AFTER the '--' sentinel switched the surface off — post-sentinel gate-defining arguments must be ignored"; rc=1
  fi
  # …and the discard is ANNOUNCED, naming the flag and never the value (the same two halves the other five
  # are held to).
  _msg="$(obligation_gate --name t --surface-globs '*.j2' --exclude-globs '*no-such-exclusion*' \
            --record NO-SUCH-RECORD.md --template-marker T --exclude-globs '*index*' \
            --changed "$_t/j2" --root "$_t" 2>&1 || true)"
  case "$_msg" in
    *"NOTE:"*"--exclude-globs"*) ;;
    *) echo "OBL SELFTEST FAIL: a discarded --exclude-globs was dropped SILENTLY — no NOTE: $_msg"; rc=1 ;;
  esac
  case "$_msg" in
    *index*) echo "OBL SELFTEST FAIL: the discard NOTE echoed the caller's exclusion VALUE — a verdict must never render caller-supplied text: $_msg"; rc=1 ;;
  esac
  # A UNIVERSAL exclusion is REFUSED, not honoured. One glob that matches every path makes obl_detect skip
  # every file, so the gate reads a blanket N/A with no record ever required — the identical fail-open the
  # empty-surface refusal closes, arriving through the new argument. The rule is EXACT rather than a
  # heuristic: a glob built only from '*' and '?' with at least one '*' matches every string of length >=
  # the number of '?', and a path is never empty. The last shape below puts the universal glob SECOND, so a
  # scan that stops at the first glob cannot pass this leg.
  for _uni in '*' '**' '*?' '?*' '*.conf.j2|*'; do
    _msg="$(obligation_gate --name t --surface-globs '*.j2' --exclude-globs "$_uni" \
              --record NO-SUCH-RECORD.md --template-marker T --changed "$_t/j2" --root "$_t" 2>&1 || true)"
    case "$_msg" in
      *"FAIL:"*"--exclude-globs"*) ;;
      *) printf 'OBL SELFTEST FAIL: an exclusion glob that matches EVERY path was honoured instead of refused — it said: %s\n' "$_msg"; rc=1 ;;
    esac
  done
  # …and the refusal must not over-reach onto the real thing: every exclusion this engine ships BEGINS with
  # '*', so the shape test has to be about what the glob NAMES, not about its first character. Asserted on
  # the MESSAGE, because a refusal and a correct absent-record FAIL are both rc=1 and a bare `if` cannot
  # tell them apart — which is precisely how an over-reaching refusal would ship green.
  _msg="$(obligation_gate --name t --surface-globs '*.j2' --exclude-globs '*.conf.j2|templates/_*.tpl' \
            --record NO-SUCH-RECORD.md --template-marker T --changed "$_t/j2" --root "$_t" 2>&1 || true)"
  case "$_msg" in
    *"is absent — record it"*) ;;
    *) echo "OBL SELFTEST FAIL: a legitimate compound-suffix exclusion list was refused or swallowed a path it does not match — it said: $_msg"; rc=1 ;;
  esac

  # ---- SIGNAL 1 IGNORES CODE MARKUP (OBLIGATION-SIGNAL1-CODE-MARKUP). Signal 1's vocabulary is made of
  # ordinary English words, so a document that DISCUSSES the vocabulary is indistinguishable from a record
  # that still CARRIES it — measured, four of this repository's own design/plan documents were denied for
  # quoting `[replace: …]` and `> **Template.**` while writing ABOUT the engine. The separator that works is
  # not a hit COUNT (measured and vetoed: eleven live records are caught by a single hit, and nineteen
  # shipped templates fire exactly once on the banner) and it is not BLOCKQUOTES (measured and vetoed: the
  # banner IS a blockquote line, so excluding them deletes the hit that catches every template). It is CODE
  # MARKUP: the quoting documents write the tokens inside backticks and fenced blocks, the records write
  # them bare.
  # EVERY leg below is PAIRED with its bare-token liveness run on the SAME token, because "the backticked
  # form PASSes" is green for free if the token never denied in the first place. Fixtures are derived from
  # $OBL_MIN_SUBSTANCE_LINES so a floor retune moves them instead of invalidating them, and each clears the
  # floor, so every verdict here is attributable to Signal 1 and never to Signal 3.
  _cm_pad() { _i=$1; while [ "$_i" -le "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "line $_i"; _i=$((_i+1)); done; }
  # (m1) BARE token -> DENY. The liveness anchor for (m2)-(m4): this is the shape a real unfilled a11y cell
  # has, and it is the behaviour that must NOT be weakened.
  { echo '# A11y Sign-off'; echo '| Decision | [replace: **pass** / fail] |'; _cm_pad 3; } > "$_t/CM-bare.md"
  if ! obl_is_placeholder "$_t/CM-bare.md"; then
    echo "OBL SELFTEST FAIL: a BARE '[replace: …]' cell was read as filled — Signal 1 no longer catches an unfilled cell, and every code-markup leg below is vacuous"; rc=1
  fi
  # (m2) the SAME token inside a single-backtick inline span -> PASS.
  # shellcheck disable=SC2016 # the SINGLE quotes are the point: the backticks must reach the fixture as
  # literal markdown, not be executed as a command substitution. Same for (m3) below.
  { echo '# The a11y obligation, explained'; echo 'The template writes `[replace: **pass** / fail]` in that cell.'; _cm_pad 3; } > "$_t/CM-span.md"
  if obl_is_placeholder "$_t/CM-span.md"; then
    echo "OBL SELFTEST FAIL: a Signal-1 token inside an inline code span was read as an unfilled stub — a document DISCUSSING the vocabulary is denied for quoting it"; rc=1
  fi
  # (m3) …and inside a DOUBLE-backtick span, which is the shape the real design document uses (it has to
  # be, because the quoted text itself contains no backtick but the surrounding prose does).
  # shellcheck disable=SC2016 # literal backticks again — see (m2).
  { echo '# The a11y obligation, explained'; echo 'The banner reads `` > **Template.** `` at line 3.'; _cm_pad 3; } > "$_t/CM-span2.md"
  if obl_is_placeholder "$_t/CM-span2.md"; then
    echo "OBL SELFTEST FAIL: a Signal-1 token inside a DOUBLE-backtick inline code span was read as an unfilled stub"; rc=1
  fi
  # (m4) …and inside a FENCED block, with the token BARE on its own line inside the fence — so this leg
  # cannot be satisfied by the inline-span rule alone.
  { echo '# The a11y obligation, explained'; echo 'The template ships:'; echo '```'
    echo '| Decision | [replace: **pass** / fail] |'; echo '```'; _cm_pad 5; } > "$_t/CM-fence.md"
  if obl_is_placeholder "$_t/CM-fence.md"; then
    echo "OBL SELFTEST FAIL: a Signal-1 token inside a FENCED code block was read as an unfilled stub — the fence half of the rule is missing"; rc=1
  fi
  # (m5) …and a TILDE fence, which CommonMark treats identically and which a backtick-only implementation
  # silently misses.
  { echo '# The a11y obligation, explained'; echo 'The template ships:'; echo '~~~'
    echo '| Decision | [replace: **pass** / fail] |'; echo '~~~'; _cm_pad 5; } > "$_t/CM-tilde.md"
  if obl_is_placeholder "$_t/CM-tilde.md"; then
    echo "OBL SELFTEST FAIL: a Signal-1 token inside a TILDE-fenced code block was read as an unfilled stub"; rc=1
  fi
  # (m6) BLOCKQUOTES ARE NOT EXCLUDED — the half that vetoed the withdrawn replacement rule. `> **Template.**`
  # IS a blockquote line, so a rule that skipped blockquotes would delete the single hit that catches all
  # nineteen shipped templates. This leg is what stops that rule being reintroduced as a "simplification".
  { echo '> **Template.** Delete the guidance; fill the sections.'; echo '# Deployment Record'; _cm_pad 3; } > "$_t/CM-quote.md"
  if ! obl_is_placeholder "$_t/CM-quote.md"; then
    echo "OBL SELFTEST FAIL: the '> **Template.**' banner in a plain BLOCKQUOTE was read as filled — blockquotes must NOT be excluded, or every shipped template reads as a filled record"; rc=1
  fi
  # (m7) …and the same banner INSIDE a fence is code markup, so it must not deny. Paired with (m6) on the
  # identical line, which makes the pair attributable to the MARKUP and to nothing else about the text.
  { echo '# The banner, explained'; echo 'Line 3 of every template reads:'; echo '```markdown'
    echo '> **Template.** Delete the guidance; fill the sections.'; echo '```'; _cm_pad 5; } > "$_t/CM-qfence.md"
  if obl_is_placeholder "$_t/CM-qfence.md"; then
    echo "OBL SELFTEST FAIL: the banner QUOTED inside a fenced block was read as an unfilled template"; rc=1
  fi
  # (m8) FAIL-CLOSED WHEN THE STRIPPER CANNOT RUN. The stripper is the one new external dependency in this
  # function, and a silently-failing one would switch Signal 1 OFF — the exact fail-open class this file
  # closes everywhere else (see the -e and compile-probe legs). The implementation falls back to the RAW
  # record, which is strictly stricter, and this leg proves it by shadowing the stripper's binary with a
  # failing stub on PATH. The fixture is (m4)'s, whose token is visible ONLY in the raw text.
  mkdir -p "$_t/nobin"
  printf '#!/bin/sh\nexit 127\n' > "$_t/nobin/awk"; chmod 755 "$_t/nobin/awk"
  # shellcheck disable=SC2030,SC2031 # the PATH change being LOCAL TO THE SUBSHELL is exactly what is
  # wanted — the shadow must not leak into the rest of the suite. Both legs open their own subshell.
  if ! ( PATH="$_t/nobin:$PATH"; export PATH; obl_is_placeholder "$_t/CM-fence.md" ); then
    echo "OBL SELFTEST FAIL: with the code-markup stripper unavailable, Signal 1 went SILENTLY OFF instead of falling back to the raw record — a weakening that fails open"; rc=1
  fi
  # …and the shadow really is potent (the stub is on PATH and really does break the stripper), or (m8) is
  # green for free on a shell that resolved the real binary anyway.
  # shellcheck disable=SC2031 # deliberately subshell-local, as in the leg above.
  if ( PATH="$_t/nobin:$PATH"; export PATH; awk 'BEGIN{exit 0}' >/dev/null 2>&1 ); then
    echo "OBL SELFTEST FAIL: the failing-stripper stub on PATH was not used — leg (m8) proved nothing"; rc=1
  fi
  # (m9) THE SHIPPED-TEMPLATE FAMILY LOCK. The legs above are synthetic; this one couples the rule to the
  # artifacts a weakening would actually cost. Every template NAMED here must still read as unfilled, and
  # the COUNT of shipped templates that do must equal the list — a named set alone cannot see a template
  # SUBSTITUTED for another, and a count alone cannot see WHICH one was lost.
  # The five templates deliberately absent (AI-ARTIFACT-LINEAGE, OPPORTUNITY-BRIEF, REVIEW-RECORD,
  # SHAPING-DOC, WAIVER-REGISTER) carry no Signal-1 token at all and read FILLED today — an existing,
  # separate gap, unchanged by this rule and not this leg's business.
  _cm_named='A11Y-SIGNOFF AI-POLICY AI-SYSTEM-CARD AI-TRANSPARENCY-SIGNOFF BACKLOG BIA EVAL-PLAN
FEATURE-REQUEST FIELD-REPORT JIRA-SETUP KIT-FEEDBACK POSTMORTEM PRIVACY-REVIEW PROJECT-CLAUDE
RUNBOOK SECURITY TASK-CONTEXT-CONTRACT TEST-PLAN THREAT-MODEL TRACKER-SETUP UAT-SIGNOFF'
  _cm_want=0
  for _cm_n in $_cm_named; do
    _cm_want=$((_cm_want + 1))
    _cm_f="$_root/templates/$_cm_n-TEMPLATE.md"
    if [ ! -f "$_cm_f" ]; then
      echo "OBL SELFTEST FAIL: templates/$_cm_n-TEMPLATE.md is named by the Signal-1 family lock but is not present — the lock cannot be evaluated against it"; rc=1
      continue
    fi
    if ! obl_is_placeholder "$_cm_f"; then
      echo "OBL SELFTEST FAIL: the shipped templates/$_cm_n-TEMPLATE.md reads as a FILLED record — an unedited template now satisfies its obligation"; rc=1
    fi
  done
  _cm_got=0
  # `if`, never `obl_is_placeholder … && _cm_got=…`: an AND-list whose LAST command fails DOES trip
  # errexit, and this suite runs under `set -e`, so the && form aborts the whole selftest on the first
  # template that reads filled — silently turning the count lock into an abort with no FAIL text.
  for _cm_f in "$_root"/templates/*.md; do
    if obl_is_placeholder "$_cm_f"; then _cm_got=$((_cm_got + 1)); fi
  done
  [ "$_cm_got" = "$_cm_want" ] \
    || { echo "OBL SELFTEST FAIL: $_cm_got shipped templates read as unfilled, but the family lock names $_cm_want — a template gained or lost its placeholder signal without the lock being updated"; rc=1; }

  # ---- CALIBRATION: the leg that pins the constant's VALUE. Everything above derives its fixtures FROM
  # $OBL_MIN_SUBSTANCE_LINES, so a retune moves the proof with it and nothing notices — measured: at 7, 9
  # and 12 every selftest in this suite stayed green. What governs in production is the SHIPPED TEMPLATES:
  # a genuine record is one of them, banner-stripped (Signal 1 rejects the banner by construction), so the
  # floor is calibrated iff every template still clears it banner-stripped. `-ge`, not a padded margin:
  # this leg reds EXACTLY when a template-derived record would red, so it asserts behaviour, not taste.
  # It bites in BOTH directions of drift — the floor retuned UP past the smallest template (12, UAT), or a
  # template TRIMMED down below the floor. Verified by mutation: at 13 it reds naming UAT-SIGNOFF.
  # (One incidental catch exists today — uat-obligation.sh LEG 5's hand-written fixture happens to be 12
  # non-blank lines, so it also reds at 13. It is an accident of that fixture, it names nothing about
  # calibration, and it lives in the file OBLIGATION-UAT-FIXTURE is routed to rewrite. Not a substitute.)
  for _rt in UAT-SIGNOFF A11Y-SIGNOFF THREAT-MODEL; do
    _rtf="$_root/templates/$_rt-TEMPLATE.md"
    if [ ! -f "$_rtf" ]; then
      echo "OBL SELFTEST FAIL: templates/$_rt-TEMPLATE.md is missing — the floor's calibration cannot be checked against it"; rc=1
      continue
    fi
    _c=$(grep -v '^> \*\*Template\.\*\*' "$_rtf" | grep -c '[^[:space:]]' || true)
    [ "${_c:-0}" -ge "$OBL_MIN_SUBSTANCE_LINES" ] \
      || { echo "OBL SELFTEST FAIL: $_rt-TEMPLATE.md is $_c non-blank lines banner-stripped — a record filled from it cannot clear the floor of $OBL_MIN_SUBSTANCE_LINES"; rc=1; }
  done

  [ "$rc" = 0 ] && echo "OK (obligation-lib engine: detect none/triggered/uncertain; exclusions before inclusions, per-path, real-view-template-still-triggers, degenerate-list-excludes-nothing, fail-safe outranks both; gate absent/placeholder/filled/none/derive-fail; derivation follows a rename (a git mv OFF a sensitive path still triggers) and every value-less two-argument flag is refused with a verdict rather than dying mid-parse; record-floor empty/one-line/floor-1/on-floor/heading-less/setext; diagnostic attribution floor/heading/template/unreadable+marker/bad-pattern, the pattern probe proven to run BEFORE every record signal; floor calibrated against the shipped templates; stub-pattern default-unchanged/custom-vocabulary/below-threshold/dash-leading/malformed-ERE-fail-closed/empty-refused/replaces-not-ors; gate-defining args first-wins AND '--'-sentinel-fenced for record/surface-globs/stub-pattern/exclude-globs/name/template-marker, each with its liveness pair, each discard announced without echoing the value; a surface defining no usable glob and an exclusion matching every path both refused rather than read as a blanket N/A; Signal 1 ignores CODE MARKUP — bare token denies, the same token in a single- and a double-backtick span and in a backtick- and a tilde-fenced block does not, blockquotes are NOT excluded so the banner still fires, the stripper falls back to the raw record when it cannot run, and all 21 shipped templates that carry a placeholder signal still read unfilled under a named-set + count lock)"
  return $rc
}

# Dispatch the engine selftest ONLY when this lib is executed directly, NEVER when sourced. A consumer
# (threat-obligation.sh) sets OBL_LIB_SOURCED before sourcing us, so this stays inert there; a directly-
# run copy — INCLUDING the non-vacuity harness's renamed .nv-mut-/.nv-ctl- copies, which a $0-basename
# guard could NOT recognize — has it unset, so the selftest runs and the sweep can mutate + kill the
# engine's FAIL paths. Flag-based (not $0-based) precisely because the sweep renames the copy it runs.
if [ -z "${OBL_LIB_SOURCED:-}" ] && [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
