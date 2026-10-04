#!/bin/sh
# Why this gate: docs/architecture/2026-07-26-kit-adherence-entry-binding-design.md section 3
# loop-state.sh — KIT-ADHERENCE-ENFORCEMENT Slice B1: the universal refusal floor.
#
# A change must carry an Entry Declaration on the PR HEAD commit. THE REQUIRED SET IS
# PROPORTIONAL TO THE DERIVED CHANGE CLASS (ENTRY-CONTRACT-CLASS-PROPORTIONAL, 2026-08-30):
#
#     ordinary                     ->  Kit-Row, Kit-Class
#     sensitive / control-plane    ->  Kit-Row, Kit-Class, Kit-Stage, Kit-Skill
#     classifier degraded          ->  all four (fail-safe: degradation ESCALATES, never relaxes)
#
# A trailer that is PRESENT is validated regardless of class — exactly-one, charset, stage
# resolution, skill resolution — so the reduced set opens no silent-typo hole. ⚠️ "PRESENT" HERE
# MEANS THE KEY OCCURS, AND THE CHARSET LEG SEPARATELY REQUIRES A NON-EMPTY VALUE: `Kit-Skill:` with
# nothing after it is not "absent", it is a present key with an empty value, and it is REFUSED. The
# verdict line therefore says "neither field carried a value", never "neither was volunteered". Kit-Intent,
# Kit-Ceremony and Kit-Stop stay ADVISORY and are deliberately NOT enforced here — an agent
# authoring its own empty Kit-Stop would otherwise be a self-issued autonomy grant.
#
# WHY THE CUT (do not "restore" the four unconditionally without re-reading this). `D-240805-3`:
# the ledger binds, it does not authenticate. Kit-Row is matched against the board and Kit-Class
# against the classifier — each checked against an authority outside the author. Kit-Stage and
# Kit-Skill are only checked for RESOLVABILITY: nothing establishes that the named stage is the
# real stage or that the named skill was read. Charging ordinary work for a field that returns no
# assurance is ceremony without a control; for sensitive and control-plane work the ceremony is
# the point, so there it is still owed. THE CEILING FOR ORDINARY IS THEREFORE LOWER, AND STATED:
# on an ordinary head this gate no longer asks anything about stage or skill.
#
# THIS GATE MAKES NO ORDERING CLAIM. The declaration may be --amend'ed onto the head commit after
# all the work is done. The ordering predicate was WITHDRAWN after five defeats in three
# adversarial rounds (ceremony-binding.sh:397-414). Do not build one here.
#
# HONEST CEILING (do not overclaim):
#   * GREEN proves a declaration is PRESENT and git-PARSEABLE on the named commit; that Kit-Stage
#     and Kit-Skill RESOLVE against the map (a real skill, appropriate to the stage) WHEN THEY ARE
#     PRESENT — required for sensitive/control-plane, volunteered for ordinary; that Kit-Row
#     MATCHES somewhere on the board — a SUBSTRING match, which is strictly weaker than naming a
#     row (`Kit-Row: a` passes; see BOARD-ROW-IDENTIFIER); and that Kit-Class equals the class
#     derived by `promotion-readiness.sh --class`, which since GUARD-PATH-ENUMERATION-INCOMPLETE S2
#     covers BOTH halves of the merge-time control-plane set — guard-core AND the adapter-declared
#     union — and so no longer under-detects adapter-declared paths (see the derive_class note
#     below for what that does and does not bound).
#   * IT PROVES NOTHING ABOUT ORDER, and nothing about whether the named skill was read or
#     followed — the same un-gateable ceiling skills/using-skills already discloses.
#   * THE RECORD IS PER-PUSH-HEAD, AND DOES NOT SURVIVE THE MERGE. Under a squash merge the commit
#     that lands on the default branch is a NEW commit whose message is composed by the forge, so it
#     carries no Kit-* trailers at all (MEASURED on this repo: PR head commits carry the full
#     declaration; the squashed commits on the default branch carry zero). The attestation lives on the pull
#     request's head commit and in the PR record, never in the merged history — so `git log` on the
#     default branch is the wrong place to audit adherence, and a future check that reads it would be
#     vacuously green. Say "declared at merge time", never "recorded in the history".
#     ↳ WHERE THE ROW DOES SURVIVE (2026-08-30): `scripts/promotion-verify.sh record` now projects
#       the approved commit's Kit-Row into the promotion note, and `promotion-verify.sh trace`
#       recovers it for a trunk commit by matching the note's approved-sha TREE against the trunk
#       commit's tree. That is the audit path — not `git log`. It inherits the GO record's
#       assurance exactly and no more (bind-not-authenticate, `D-240805-3`): a forged note is as
#       forgeable as it ever was. MEASURED 2026-08-30: 0/60 recoverable as a trailer, 28/30
#       recoverable through the note (the 2 misses were merged with no GO record at all).
#   * THE ROW LEG CAN BE N/A'd BY THE CHANGE UNDER TEST. The backend field and the board are read
#     from the PR's own worktree, so flipping the backend or deleting the board in the same commit
#     skips it. Announced on every N/A branch; boarded as LOOP-STATE-NA-SELF-SERVICE.
#   * THIS GATE'S BINDING IS DETECTED, NOT PREVENTED. Which contexts sit in required_status_checks
#     is compared (declared ⊆ live) against REQUIRED-CHECKS.md by branch-protection.sh's live leg on
#     every PR + weekly since 2026-08-28 (required context `branch-protection-live`), so an unbound or
#     renamed context reds the next PR — but an admin can still unbind it (enforce_admins is false), and
#     shrinking the declaration greens it. Never call this gate unbypassable without those two clauses.
#
# ⚠️ THE HEAD DECLARATION DESCRIBES THE PULL REQUEST, NOT JUST THE LAST COMMIT. Kit-Class is
# compared against the class derived from the WHOLE change-set (merge-base HEAD origin/main), so on
# a control-plane PR the head commit must declare `control-plane` even when its own files are
# ordinary — a version bump closing a control-plane slice is the common case, and it caught this
# slice's own final commit. Comparing against the head commit's OWN diff instead would be a forgery
# hole: a control-plane change could hide behind an ordinary last commit. Fail-safe by design.
#
# THE STAGE-TO-SKILL MAP IS NOT IN THIS FILE. It lives in .kit/roster.conf (design section 3.0,
# Security N1): hardcoding it would make this a 14th site enumerating the roster, and an unmapped
# pair would fall through to PASS. The valid Kit-Stage set is DERIVED from that map, so adding a
# stage later (DESIGN-AS-A-STAGE, V2) is a data change rather than a code change here.
#
# Usage:
#   sh conformance/loop-state.sh --head <sha>     (the PR head SHA — NEVER defaults to HEAD)
#   sh conformance/loop-state.sh --selftest
#   sh conformance/loop-state.sh --help           (usage + the roster's stage->skill map; K20)
#
# What it changes: nothing — read-only. Reads git history, .kit/roster.conf and skills/.
# Guardrails: fails CLOSED on a missing or unreadable map, on an empty KIT_STAGES, on a map
# incomplete in any of the three drift directions, and on an unmapped stage — each fixtured.
# ⚠️ derive_class's own fail-closed arm is DISCLOSED-UNPROVEN, not fixtured: review tried to build a
# fixture and REFUTED it — promotion-readiness.sh returns `control-plane` rc 0 for a missing file, an
# empty file, a blank-lines file, a directory and /dev/null, so it never emits an unrecognised token
# and the `*) return 1` arm is unreachable through this interface. Do not invent a fixture for it;
# the arm stays as defense against a future change in that script's contract. Refuses to default to HEAD: on pull_request,
# actions/checkout checks out the ephemeral merge commit, which carries NO trailers.
set -eu
# shellcheck disable=SC1007 # `CDPATH= cd` clears CDPATH so a user's CDPATH cannot redirect the cd.
DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# NOT environment-overridable — and this is load-bearing, not stylistic. An earlier version honoured
# KIT_ROSTER_CONF, which let a caller substitute the stage->skill AUTHORITY wholesale (measured: a
# conf adding a `YOLO` stage with every skill mapped to every stage made the gate pass). It also
# collided with the guard's own KIT_ROSTER_CONF (roster-guard-wired.sh:46), so a developer legitimately
# exporting it for the roster dial silently redirected this gate's map. The selftest sets ROSTER_CONF
# as a plain script variable, so nothing needs an env route.
ROSTER_CONF="$DIR/.kit/roster.conf"

# The repository the declaration is read from. Production is this repo; the selftest points it
# at a throwaway fixture repo IN-PROCESS. Deliberately NOT environment-overridable: the kit has
# banked "use arguments, not env" (OBLIGATION-TESTMODE-ENV-FLAG), and a plain script variable set
# inside selftest() has no external surface at all.
LS_REPO="$DIR"

# The gate-checked fields (design section 3). Kit-Intent / Kit-Ceremony / Kit-Stop are ADVISORY
# and are deliberately absent from this list. This is the FULL set — what a sensitive or
# control-plane head owes. What an ORDINARY head owes is the reduced set ls_required_keys prints.
LS_REQUIRED_KEYS="Kit-Row Kit-Stage Kit-Class Kit-Skill"

# ── THE STAGE-ARTIFACT KEYS (LOOP-STAGE-ARTIFACT-GATE, design 4.2 rule 2) ──────────────────────────
# `Kit-Plan` and `Kit-Review` name the plan file and the review record a PR's head commit is bound to.
# They are ADVISORY HERE, and the split is the whole point: `conformance/review-lane.sh` GRADES them —
# artifact tracked, non-stub, rounds contained, findings disposed, controls resolved, approver
# attestation — and it is a required context of its own. This gate asks ONE question about them:
# is the value SHAPED like a path this repo could carry (charset + prefix + `.md` + no traversal)?
#
# WHY DECLARE THEM HERE AT ALL, rather than let review-lane own them alone. The two gates must not
# DISAGREE ON PARSING (D11's one-derivation rule). review-lane reads these trailers with this file's
# `%(trailers:key=...,valueonly)` idiom precisely because `grep '^Kit-'` matches a line anywhere in a
# message — the severed-block defect this file's own fixture pins. Declaring the keys in the map is
# what makes "the same parser" a fact about the map rather than a claim in a comment. It also closes
# the silent-typo hole the PRESENT-implies-VALIDATED loop closes for the required set: a head carrying
# `Kit-Review: notes/x.txt` would otherwise read as "a record was named" to a human and as nothing at
# all to both gates.
#
# THE CEILING, STATED: shape is not existence. This gate never opens the file; a head naming
# `docs/reviews/does-not-exist.md` passes HERE and is refused by review-lane. Do not describe a
# loop-state green as evidence that a review happened.
LS_ARTIFACT_KEYS="Kit-Plan Kit-Review"
# shellcheck disable=SC2034 # read INDIRECTLY (POSIX sh has no ${!name}) by check_declaration, which
# builds the variable name from the key with `-` mapped to `_`. The keys are a fixed literal list, so
# the indirection cannot reach a name an author chose. shellcheck cannot see through the eval.
LS_ARTIFACT_PREFIX_Kit_Plan="docs/plans/"
# shellcheck disable=SC2034 # same indirection — see the note on LS_ARTIFACT_PREFIX_Kit_Plan.
LS_ARTIFACT_PREFIX_Kit_Review="docs/reviews/"

# ls_required_keys — THE REQUIRED SET IS PROPORTIONAL TO THE DERIVED CLASS
# (ENTRY-CONTRACT-CLASS-PROPORTIONAL, design 2026-08-30 section 4.1a; amends nothing about what a
# green MEANS for the keys that ARE checked).
#
# WHY THE CUT IS Kit-Stage / Kit-Skill AND NOT SOMETHING ELSE. `D-240805-3`: the ledger binds, it
# does not authenticate — an agent-typed value is not a record. Kit-Row is matched against the
# board and Kit-Class against the classifier, so both are checked against an authority OUTSIDE the
# author. Kit-Stage and Kit-Skill are checked only for RESOLVABILITY against a map: nothing
# anywhere establishes that the named stage is the stage the work is in, or that the named skill
# was read. For ordinary work that is ceremony an author pays with no assurance returned, so the
# gate no longer asks for it. It still VALIDATES it when volunteered (see check_declaration) — a
# key that is present is held to its contract regardless of class, so the cut opens no
# silent-typo hole.
#
# ⚠️ ONE DIRECTION ONLY. Anything that is not exactly `ordinary` — sensitive, control-plane, and
# every degraded/unrecognised answer — gets the FULL set. Degradation ESCALATES the requirement;
# it must never be a route to the cheaper contract.
ls_required_keys() {   # $1 = derived class (or a degradation marker)
  case "${1:-}" in
    ordinary) printf 'Kit-Row Kit-Class\n' ;;
    *)        printf '%s\n' "$LS_REQUIRED_KEYS" ;;
  esac
}

# The classifier this gate asks for the class. A plain script variable, NOT an env route (the
# banked OBLIGATION-TESTMODE-ENV-FLAG rule, :61-73): selftest() points it at a stub in-process so
# the degradation arm can be fixtured, and nothing outside this file can reach it.
LS_CLASS_FN="derive_class"

# ls_class_for_required — the class, or the FAIL-SAFED marker, and ALWAYS rc 0.
#
# It always succeeds because its consumer is a required-set SELECTOR, not a verdict: a classifier
# that has broken must still produce a required set, and that set must be the strict one. The
# verdict on a broken classifier is check_class's, which fails closed on the same condition — so a
# degraded run reds there while the declaration leg simultaneously demands all four. Two
# independent refusals, neither depending on the other.
# TAKES NO ARGUMENT, DELIBERATELY. It used to accept an optional fixture listing and forward it to
# the classifier, but nothing ever passed one — run_gate calls it bare and so does the selftest —
# so the parameter was dead code that Linux shellcheck correctly flagged (SC2120). The fixture
# route into the classifier is `derive_class <listing>`, which check_class still uses directly; the
# selftest reaches THIS function's degraded arm by pointing LS_CLASS_FN at a stub instead.
# ⚠️ Do not "restore" the parameter to silence a future warning — a disable comment here would have
# hidden a real dead-argument defect rather than removed it.
ls_class_for_required() {   # [$1 = optional changed-listing path — TBG-TRUSTED-JOB fix-round H-2]
  if _ls_cfr=$("$LS_CLASS_FN" "${1:-}"); then
    printf '%s\n' "$_ls_cfr"
    return 0
  fi
  echo "loop-state: change-class derivation FAILED — fail-safe: control-plane, all four required" >&2
  printf 'FAIL-SAFED\n'
  return 0
}

# ls_safe — strip control characters from any PR-controlled value before it reaches a log.
#
# Applied at EVERY interpolation site, not just the one that was reported. A tracked directory name
# beginning with a newline puts attacker text at the START of an Actions log line, which is enough
# for a workflow command; the sibling sites (backend token, raw Kit-Skill) cannot reach a line start
# because `head -1` truncates, but they can still emit ANSI/CR log corruption. Fixing only the
# reported site would be this repo's named failure — fixing the example, then claiming the class.
#
# ⚠️ promotion-readiness.sh's `_render_safe` is NOT reusable here: its range deliberately preserves
# TAB and LF, so the injected line-start survives it. Measured. The full C0 range plus DEL is what
# works. LC_ALL=C so the byte ranges are not locale-dependent.
ls_safe() { LC_ALL=C printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177'; }

# Read one KEY="value" from the map by PARSING, never by sourcing — sourcing would make a conf
# file executable code reachable from a gate.
conf_val() {   # $1 = key
  sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$ROSTER_CONF" 2>/dev/null | head -1
}

# ls_print_stage_map — the REMEDY SURFACE for every refusal about a stage or a skill (K20).
# A refusal that names neither the stages that exist nor the skills each admits sends the adopter
# hunting for `.kit/roster.conf`, and the plan doc that explains the map is export-ignore'd. This
# prints the map the gate ITSELF just read — one reader, no restated table, so it cannot go stale.
# It is a REMEDY, NOT A CHECK: it reads the conf the gate already trusts and asserts nothing.
# EVERY LINE GOES THROUGH ls_safe. The roster is repo text and a PR may change it, so a stage name
# beginning with a newline would put attacker text at the start of an Actions-log line — the same
# workflow-command surface map_completeness sanitises at :296-305, and the reason leg (k) exists.
# Writes to STDERR, beside the refusal it explains.
ls_print_stage_map() {
  echo "  the stage → skill map (${ROSTER_CONF}):" >&2
  for _ls_pm in $(conf_val KIT_STAGES); do
    echo "    $(ls_safe "$_ls_pm"): $(ls_safe "$(conf_val "STAGE_SKILLS_$_ls_pm")")" >&2
  done
}

# ls_dial_mode "<DIAL_NAME>" — the enforcement-dial reader for THIS gate. Prints exactly `enforce`
# or `observe` and ALWAYS returns 0 (the scope consumer compares the printed word, so a dial can
# never wedge the gate by erroring). A LOCAL copy of the kit_dial_mode precedence
# (.claude/hooks/guard-core.sh:1861): loop-state.sh sources NOTHING and MUST NOT source the
# ~1900-line guard (a `set -eu` gate coupling to code killable by a sparse-excluded `.claude/`), so
# the precedence is re-expressed here — PARSE, DON'T SOURCE, the dial-state.sh:43 precedent. This is
# a THIRD copy by design (guard-core, dial-state, here). The T7c selftest pins THIS reader against the
# shared precedence spec; dial-state.sh's own selftest backstops the committed dial state. No check
# invokes all three readers on one fixture — they share a spec, not a live cross-reader agreement test.
#
# SOURCE: $LS_REPO/.kit/dials.conf — the GRADED tree's conf, NEVER `git rev-parse`/cwd, NEVER an env
# ROOT route (loop-state's banked OBLIGATION-TESTMODE-ENV-FLAG, :61-73). Production (the CI job, the
# pre-push hook via --head) reads the real tree; a selftest fixture ($LS_REPO=throwaway) carries no
# conf and reads observe-by-absence, staying green even though the kit's own tree ships enforce.
# An absent/unreadable/garbage conf, a missing key, a dial NAME outside [A-Z0-9_], or any value that
# is not exactly `enforce` reads OBSERVE (fail-safe toward observe — a dial that cannot be read must
# never refuse a push).
#
# PRECEDENCE IS ASYMMETRIC (the load-bearing rule): the conf value is authoritative; an env var of
# the same name may ESCALATE observe->enforce but may NEVER de-escalate a conf `enforce` — such a
# value LOSES and one loud anomaly line is printed. Env-wins would leave every flip one sticky
# `export` from undone (D-240811-2.1). An unset/empty/equal env var is the normal case, never warned.
ls_dial_mode() {   # $1 = dial name
  _ls_dn=$1
  case "$_ls_dn" in
    ''|*[!A-Z0-9_]*) printf 'observe\n'; return 0 ;;
  esac
  _ls_dconf="$LS_REPO/.kit/dials.conf"
  _ls_dval=''
  if [ -r "$_ls_dconf" ]; then
    _ls_dval=$(grep -E "^[[:space:]]*${_ls_dn}[[:space:]]*=" "$_ls_dconf" 2>/dev/null | tail -n1 \
      | sed -E "s/^[[:space:]]*${_ls_dn}[[:space:]]*=[[:space:]]*//; s/#.*$//; s/[\"']//g; s/[[:space:]].*$//")
  fi
  # The env side, read INDIRECTLY (POSIX sh has no ${!name}); the name is charset-checked above.
  _ls_denv=$(eval "printf '%s' \"\${$_ls_dn:-}\"")
  if [ "$_ls_dval" = enforce ]; then
    if [ -n "$_ls_denv" ] && [ "$_ls_denv" != enforce ]; then
      # SANITIZE BEFORE INTERPOLATING — the value is caller-controlled; strip the full C0 range + DEL
      # via ls_safe (the every-site rule at :90 — CR/LF alone left ESC/ANSI log corruption reachable,
      # F6) and bound length so it cannot forge an extra instruction line on stderr (guard-core SEC M1).
      _ls_dsafe=$(ls_safe "$_ls_denv" | cut -c1-40)
      printf '%s\n' "loop-state: dial $_ls_dn='$_ls_dsafe' in the environment cannot de-escalate the repo-carried enforce in .kit/dials.conf - the conf WINS (env may only escalate observe->enforce). Change the dial through the ratified control-plane ceremony." >&2
    fi
    printf 'enforce\n'; return 0
  fi
  [ "$_ls_denv" = enforce ] && { printf 'enforce\n'; return 0; }
  printf 'observe\n'; return 0
}

# map_completeness — the family-completeness lock (design section 9, Security N1).
# Three FAIL directions, none of which may fall through to PASS:
#   (a) a skill on disk absent from the map
#   (b) a map entry naming no skill on disk
#   (c) a stage in KIT_STAGES with no skill set
map_completeness() {
  [ -f "$ROSTER_CONF" ] || { echo "loop-state: map not found: $ROSTER_CONF" >&2; return 1; }
  _ls_stages=$(conf_val KIT_STAGES)
  [ -n "$_ls_stages" ] || { echo "loop-state: KIT_STAGES missing or empty in $ROSTER_CONF" >&2; return 1; }

  _ls_mapped=""
  for _ls_s in $_ls_stages; do
    _ls_sk=$(conf_val "STAGE_SKILLS_$_ls_s")
    # (c) unmapped stage — FAIL, never fall through
    [ -n "$_ls_sk" ] || {
      echo "loop-state: stage '$(ls_safe "$_ls_s")' has no skill set (unmapped stage) in $ROSTER_CONF" >&2
      return 1; }
    for _ls_k in $_ls_sk; do
      # (b) map entry naming no skill on disk
      [ -f "$DIR/skills/$_ls_k/SKILL.md" ] || {
        echo "loop-state: map entry '$(ls_safe "$_ls_k")' (stage $(ls_safe "$_ls_s")) names no skill on disk — $ROSTER_CONF" >&2
        return 1; }
      _ls_mapped="$_ls_mapped $_ls_k"
    done
  done

  # (a) a skill on disk absent from the map
  for _ls_d in "$DIR"/skills/*/; do
    [ -f "$_ls_d/SKILL.md" ] || continue
    _ls_n=${_ls_d%/}; _ls_n=${_ls_n##*/}
    case " $_ls_mapped " in
      *" $_ls_n "*) ;;
      # NAME THE FILE. --kitself exempts the SELFTEST, not run_gate: map_completeness runs on every
      # PR, so an adopter who adds one project skill reds their gate. Without the path in the
      # message they have no remedy — the plan doc that explains the map is export-ignore'd.
      # SANITISE the directory name before it reaches stderr. A PR can add a tracked directory whose
      # name begins with a newline, which puts attacker text at the START of a line in the Actions
      # log — enough for a workflow command (::stop-commands::, ::add-mask::). Bounded (FAIL path
      # only, contents:read, no secrets, set-env disabled since 2020) but free to close.
      # ⚠️ Reusing promotion-readiness.sh's _render_safe was EXECUTED and REFUTED: its range
      # deliberately preserves TAB and LF, so the injected line-start survives. The full C0 range
      # plus DEL is what actually works — measured.
      *) echo "loop-state: skill '$(ls_safe "$_ls_n")' exists on disk but is absent from the map ($ROSTER_CONF)" >&2
         echo "  Add it to the STAGE_SKILLS_<stage> line(s) it governs in that file." >&2
         return 1 ;;
    esac
  done
  return 0
}

# decl_field — read ONE trailer key off ONE commit, using git's own trailer parser.
#
# NEVER `grep '^Kit-'`. Measured: GitHub's squash-merge appends a dashes separator and a
# Co-authored-by line, which ENDS the trailer paragraph and demotes every Kit-* field above it to
# prose. Zero of the last five commits on this repo's main carry a parseable Kit-* trailer even
# though the text is plainly visible in all of them. A grep implementation would pass those
# commits — including c5d72fb, the commit that shipped the entry contract itself.
decl_field() {   # $1 = sha, $2 = key
  git -C "$LS_REPO" log -1 --format="%(trailers:key=$2,valueonly)" "$1" 2>/dev/null
}

# decl_count — occurrences of one key. Uses `grep -c .`, NEVER `wc -l`: the --format output
# appends a trailing newline, so wc -l reports 2 for a single occurrence and would false-RED
# every valid commit (design section 3.2.1B, measured).
decl_count() {   # $1 = sha, $2 = key
  decl_field "$1" "$2" | grep -c . || true
}

# valid_stage — DERIVED from the map, never a hardcoded list. This is what keeps adding a stage
# (DESIGN-AS-A-STAGE, V2) a data change rather than a code change.
valid_stage() {   # $1 = stage
  case " $(conf_val KIT_STAGES) " in
    *" $1 "*) return 0 ;;
    *)        return 1 ;;
  esac
}

# check_declaration — leg P: presence + parseability + stage resolvability on ONE named commit.
# Base-independent by construction: it reads the SHA it is given and NEVER walks to a parent. A
# declaration present only on an ancestor must FAIL, which is the negative that makes head-only
# scope safe (design section 3.1; the any-ancestor-satisfies defect ceremony-binding closed).
check_declaration() {   # $1 = sha, [$2 = derived class; DEFAULTS TO control-plane = the full set]
  _ls_rc=0
  # THE DEFAULT IS THE STRICT SET, NOT THE CHEAP ONE. A caller that forgets to pass a class gets
  # all four — the omission fails safe. run_gate always passes one.
  _ls_req=$(ls_required_keys "${2:-control-plane}")
  for _ls_k in $_ls_req; do
    # EXACTLY ONE occurrence. More than one is a FAIL, never "take the first" — a commit carrying
    # both `Kit-Class: control-plane` and `Kit-Class: ordinary` yields both lines, and head -1 /
    # tail -1 reach opposite verdicts (design section 3.2, measured decoy).
    _ls_n=$(decl_count "$1" "$_ls_k")
    if [ "$_ls_n" -eq 0 ]; then
      echo "loop-state: $1 carries no parseable '$_ls_k' trailer" >&2
      # K20 — a MISSING Kit-Stage or Kit-Skill is the one refusal where the author cannot write the
      # value without knowing the map. Print it beside the refusal (the stage/skill pair is what
      # carries meaning; a skill is only ever validated AGAINST a stage).
      case "$_ls_k" in
        Kit-Stage|Kit-Skill) ls_print_stage_map ;;
      esac
      _ls_rc=1
      continue
    fi
    if [ "$_ls_n" -ne 1 ]; then
      echo "loop-state: $1 carries $_ls_n occurrences of '$_ls_k' — exactly one is required" >&2
      _ls_rc=1
      continue
    fi
    # CHARSET, REJECT BY DEFAULT, PER FIELD. Trailer values are attacker-influenceable (anyone
    # may open a PR with any trailer). This is the OUTER, per-key charset shared by every Kit-*
    # field; it is deliberately wider than any one field's own grammar, because `Kit-Skill:
    # skills/build` and `Kit-Class: control-plane` must pass it too.
    # ⚠️ THIS COMMENT USED TO SAY `Kit-Row` "flows into a board grep". IT NO LONGER DOES
    # (BOARD-ROW-IDENTIFIER): `check_row` holds the value to `row_id_ok` — the [A-Z0-9][A-Z0-9-]*
    # row-id grammar, one definition in backlog-lib.sh — and then LOOKS IT UP by string equality on
    # a parsed Item cell (`row_count`). No pattern is built from the value anywhere on that path, so
    # the ceremony-binding.sh:124-136 class (a newline turning `grep -F` into an unconditional OR)
    # is unreachable from here by construction rather than by filtering.
    # `#` is included deliberately: it is the canonical row id for the `github` backend, and it is
    # what backlog-presence.sh already matches. Without it an adopter on GitHub Issues cannot
    # declare their row in its native form (`#123`) — measured as a day-one break by review. Note
    # what that buys TODAY, and no more: on a hosted backend `check_row` no longer N/As, it reports
    # NOT ENFORCED (rc-3 arm below), so `#123` is accepted by this charset and then never looked up.
    case "$(decl_field "$1" "$_ls_k")" in
      ''|*[!A-Za-z0-9_.:/#-]*)
        echo "loop-state: '$_ls_k' must be non-empty and may contain only [A-Za-z0-9_.:/#-]" >&2
        echo "  — got a value with a disallowed character (refused at the boundary)." >&2
        _ls_rc=1 ;;
    esac
  done

  # PRESENT ⇒ VALIDATED, REGARDLESS OF CLASS. Every key in the full set that the reduced set did
  # not demand is still held to exactly-one + charset when the author volunteered it. Without this
  # loop, cutting a key from the required set would silently ignore a wrong value — the ordinary
  # head declaring `Kit-Skill: skills/tpd` would read as "the skill was named" to a human and as
  # nothing at all to the gate. Absent is N/A; present is checked.
  for _ls_k in $LS_REQUIRED_KEYS; do
    case " $_ls_req " in *" $_ls_k "*) continue ;; esac
    _ls_n=$(decl_count "$1" "$_ls_k")
    if [ "$_ls_n" -eq 0 ]; then
      continue
    fi
    if [ "$_ls_n" -ne 1 ]; then
      echo "loop-state: $1 carries $_ls_n occurrences of '$_ls_k' — exactly one is required" >&2
      _ls_rc=1
      continue
    fi
    case "$(decl_field "$1" "$_ls_k")" in
      ''|*[!A-Za-z0-9_.:/#-]*)
        echo "loop-state: '$_ls_k' must be non-empty and may contain only [A-Za-z0-9_.:/#-]" >&2
        echo "  — got a value with a disallowed character (refused at the boundary)." >&2
        _ls_rc=1 ;;
    esac
  done
  # THE STAGE-ARTIFACT KEYS — present implies validated, absent is N/A, on EVERY class. Resolvability
  # is PATH SHAPE ONLY (see LS_ARTIFACT_KEYS): charset, the literal prefix, a `.md` suffix and no `..`
  # segment. `Kit-Review` may carry a COMMA-SEPARATED set when a consolidated PR absorbs several
  # slices, and each element is checked independently — a set is only as well-formed as its worst
  # member.
  for _ls_k in $LS_ARTIFACT_KEYS; do
    _ls_n=$(decl_count "$1" "$_ls_k")
    [ "$_ls_n" -eq 0 ] && continue
    if [ "$_ls_n" -ne 1 ]; then
      echo "loop-state: $1 carries $_ls_n occurrences of '$_ls_k' — exactly one is required (a consolidated PR lists several records in ONE comma-separated value)" >&2
      _ls_rc=1; continue
    fi
    _ls_pfx=$(eval "printf '%s' \"\${LS_ARTIFACT_PREFIX_$(printf '%s' "$_ls_k" | tr - _)}\"")
    # ⚠️ THE COMMA SPLIT NEVER TOUCHES $IFS, and that is a blocking-gate constraint, not a style
    # preference: the exported artifact is scanned by semgrep and `bash.lang.security.ifs-tampering`
    # refuses an `IFS=<value>` assignment (it flagged the previous `IFS=','` form four times on PR
    # #644). `IFS= read` is the read builtin's OWN idiom — a per-command prefix that clears splitting
    # for that one read — and the rule does not flag it; aggregate-coverage.sh's census loop is the
    # in-repo precedent for this exact shape and documents it.
    # THE HEREDOC IS LOAD-BEARING: `printf | while` would run the body in a SUBSHELL and every
    # `_ls_rc=1` below would be discarded, so the gate would report zero findings and pass vacuously.
    # A heredoc redirection spawns no subshell, so the assignments persist.
    # AN EMPTY ELEMENT NOW REDS rather than being skipped. The old `for` word-split dropped empties
    # silently, so `Kit-Review: a.md,,b.md` — and even a bare `,` — lost them; here every element
    # reaches the `''` arm of the case below, which is the arm that always intended to refuse it.
    _ls_vals=$(decl_field "$1" "$_ls_k" | head -1 | tr ',' '\n')
    while IFS= read -r _ls_pv; do
      _ls_pv=$(printf '%s' "$_ls_pv" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      case "$_ls_pv" in
        ''|*[!A-Za-z0-9_./-]*|*..*)
          echo "loop-state: '$_ls_k' value '$(ls_safe "$_ls_pv")' is not a usable path (charset [A-Za-z0-9_./-], no '..' segment)" >&2
          _ls_rc=1 ;;
        "$_ls_pfx"*.md) ;;
        *)
          echo "loop-state: '$_ls_k' must name a '$_ls_pfx...md' path — got '$(ls_safe "$_ls_pv")'. The artifact itself is graded by conformance/review-lane.sh; this gate only refuses a value no record could ever live at." >&2
          _ls_rc=1 ;;
      esac
    done <<EOF
$_ls_vals
EOF
  done

  [ "$_ls_rc" -eq 0 ] || return 1

  # STAGE RESOLUTION runs WHEN Kit-Stage IS PRESENT — required for sensitive/control-plane, and
  # volunteered for ordinary. An absent Kit-Stage on an ordinary head has already been accepted by
  # the required-set loop above; running valid_stage on the resulting empty string would refuse it
  # for a reason that is no longer the contract.
  if [ "$(decl_count "$1" Kit-Stage)" -gt 0 ]; then
    _ls_stage=$(decl_field "$1" Kit-Stage | head -1)
    valid_stage "$_ls_stage" || {
      echo "loop-state: Kit-Stage '$_ls_stage' is not a stage in the map ($ROSTER_CONF)" >&2
      return 1; }
  fi
  return 0
}

# derive_class — the class comes from the same authority `ceremony-binding` uses, never re-derived
# here.
#
# ⚠️ SCOPE OF THAT AUTHORITY, STATED HONESTLY (do not call it "the single authority").
#
# ⚠️⚠️ THIS PARAGRAPH CARRIED TWO STALE CITATIONS AND BOTH ARE CORRECTED HERE RATHER THAN LEFT
# STANDING (GUARD-PATH-ENUMERATION-INCOMPLETE S2 M5). What it used to say, and why each was wrong:
#   (1) It named `AGENTS.md` as a MEASURED divergence — "derives ordinary here, rc 1 at
#       agent-boundary". FALSE since 2026-08-16: S1 of this same row graduated `AGENTS.md` into
#       guard-core.sh's curated root set, so both halves had caught it for a day before this comment
#       was read again. A measured-sounding claim that has silently become false is worse than none
#       (the EXTERNAL-PREMISE-EVIDENCE class this repo banks).
#   (2) It cited `ceremony-binding.sh:93-95` as "the identical derivation". DRIFTED: those lines are
#       that file's containment-leg prose, not its class derivation. Cited BY FUNCTION below —
#       `ceremony-binding.sh`'s own `derive_class` — because a line number is a citation that rots.
#
# WHAT IS TRUE NOW. `promotion-readiness.sh --class` consults BOTH halves of the merge-time
# control-plane set: guard-core's hardcoded patterns AND the adapter-declared union
# (`conformance/union-lib.sh`, the same derivation and the same matcher `agent-boundary.sh` uses).
# `GEMINI.md`, `.gemini/*` and `.cursor/rules/*` therefore derive `control-plane` HERE, and a PR
# touching only one of them can no longer declare `ordinary` and pass this gate — the fold
# `LOOP-STATE-CLASS-ADAPTER-UNION` and `CLASS-VS-GATE-ADAPTER-MISMATCH` named. `ceremony-binding.sh`
# inherits the same cure through its own `derive_class`, which calls the same seam.
#
# THE BOUND THAT REMAINS, AND IT IS NOT NOTHING: this agreement holds WHEN THE UNION IS DERIVABLE.
# With adapter manifests present but unreadable (no jq, or a manifest that does not parse) `--class`
# fail-safes to control-plane and discloses on stderr, while `agent-boundary.sh` silently degrades to
# the guard-core floor — so in that state the two gates disagree again, inverted. That is
# agent-boundary's fail posture, boarded as its own row; do not restate this note as "the gates
# always agree".
# Re-implementing the derivation would make a SIXTH derivation site and duplicate the
# control-plane path contract with nothing locking the two together (the CP7R5-KEPTSET-LOCK
# failure). Fails CLOSED: any non-zero exit, empty output or unrecognised token is a DERIVE
# FAILURE, never an implicit `ordinary` — which would be fail-OPEN on the decision this gate
# exists to protect.
#
# $1 is an OPTIONAL fixture listing, and it is reachable ONLY as a function argument from
# selftest(). There is deliberately NO --changed command-line flag — and since A4 removed
# ceremony-binding's (with its env enabler KIT_CB_TEST), NEITHER merge-time gate implements an
# author-facing fixture flag. A gate that never implements the flag cannot accept an
# author-supplied one.
# ★ THE CHILD'S ENVIRONMENT IS SCRUBBED, NOT INHERITED (review REV-I1) — the `env -u` precedent
# conformance/backlog-presence.sh already applies to this exact classifier, extended to the input
# GUARD-PATH-ENUMERATION-INCOMPLETE S2 added. MEASURED: with `KIT_ADAPTERS_DIR` pointing at an empty
# directory, `--class` answers `ordinary` for a `GEMINI.md`-only change-set — so an ambient variable
# would move a governing path out of the control-plane set and let an under-declared `Kit-Class:
# ordinary` trailer pass THIS gate, which is precisely the forgery check_class exists to refuse.
# `KIT_UNION_LIB` is scrubbed in the same breath: it selects the matcher.
# ⚠️ ARGUMENTS, NOT ENV — the same rule phase-gate applies to its own children. Do not "simplify"
# this back to a bare `sh`.
derive_class() {   # [$1 = fixture listing path]
  _ls_out=""
  if [ -n "${1:-}" ]; then
    _ls_out="$(env -u KIT_ADAPTERS_DIR -u KIT_UNION_LIB sh "$DIR/conformance/promotion-readiness.sh" --changed "$1" --class 2>/dev/null | tail -1)" || _ls_out=""
  else
    _ls_out="$(env -u KIT_ADAPTERS_DIR -u KIT_UNION_LIB sh "$DIR/conformance/promotion-readiness.sh" --class 2>/dev/null | tail -1)" || _ls_out=""
  fi
  case "$_ls_out" in
    ordinary|sensitive|control-plane) printf '%s\n' "$_ls_out"; return 0 ;;
    *) return 1 ;;
  esac
}

# check_class — ANTI-SELF-ASSERTION. Kit-Class must EQUAL the derived class. Not ">=": an
# over-declaration is still a declaration that does not match what the diff says, and the design
# closed class forgery on equality WITHIN the guard-core set. Security review could not forge a
# class downward inside that set; it DID measure that adapter-declared paths fell OUTSIDE it, which
# GUARD-PATH-ENUMERATION-INCOMPLETE S2 closed — the derived class now spans guard-core AND the
# adapter union, so the equality is checked against the same set the required ratification gate uses.
# Still do not restate this as "class forgery is closed" unqualified: the agreement is bounded by the
# union being DERIVABLE, per the derive_class note above.
check_class() {   # $1 = sha, [$2 = fixture listing], [$3 = ALREADY-derived class]
  _ls_declared=$(decl_field "$1" Kit-Class | head -1)
  # $3 EXISTS ONLY TO AVOID A SECOND CLASSIFIER SPAWN (review L5). run_gate has already derived the
  # class to pick the required set; re-deriving here runs promotion-readiness.sh (and its git diff
  # against the trunk) a second time for an answer we hold. The selftest still calls this with a
  # fixture listing and no $3, so the live derivation path keeps its own coverage.
  if [ -n "${3:-}" ]; then
    _ls_derived="$3"
    # FAIL-SAFED is not a class — it is ls_class_for_required's marker that the classifier broke,
    # and it must reach the SAME fail-closed refusal a live derivation failure does. Without this
    # arm the shortcut would compare a trailer against the literal string and refuse for the wrong
    # reason, or worse, pass a commit that declared it.
    if [ "$_ls_derived" = FAIL-SAFED ]; then
      echo "loop-state: change-class derivation FAILED — refusing to assume a class (fail-closed)" >&2
      return 1
    fi
  elif ! _ls_derived=$(derive_class "${2:-}"); then
    echo "loop-state: change-class derivation FAILED — refusing to assume a class (fail-closed)" >&2
    return 1
  fi
  if [ "$_ls_declared" != "$_ls_derived" ]; then
    echo "loop-state: Kit-Class '$_ls_declared' does not equal the derived class '$_ls_derived'." >&2
    echo "  Class is DERIVED, never self-asserted. Update the trailer to match the diff." >&2
    return 1
  fi
  return 0
}

# Board-parser primitives, SOURCED not re-derived. backlog-lib.sh exists precisely so
# backlog-current.sh and backlog-presence.sh consume ONE definition of "the board"; deriving a
# fifth is the trap design section 10.2 names explicitly.
# shellcheck disable=SC1091 # resolved at runtime from $DIR
. "$DIR/conformance/backlog-lib.sh"

# The project root the BOARD is resolved in. Production is this repo; the N/A legs point it at a
# tree with no CLAUDE.md and no board, which is exactly an adopter's first PR.
LS_BOARDROOT="$DIR"

# LOOP-STATE-TRACKER-STEP-ASIDE T1 (design §2): the step-aside's two inputs, by ARGUMENT ONLY
# (RD-3) — never env, never cwd. Both empty means today's behaviour (AC2): no --base-dir/
# --live-contexts pair was given, so bp_tracker_delegated is never called (it fails closed on an
# empty base-dir anyway, but the caller does not even reach it — see check_row below).
LS_BASE_DIR=""
LS_LIVE_CONTEXTS=""

# check_row — Kit-Row resolves to a real board row, WHERE A BOARD APPLIES.
#
# N/A ROUTES (design section 10.2). .gitattributes marks BACKLOG.md export-ignore, so a fresh
# adopter export has NO board and their import commit carries no trailer. A flatly-required row
# check would RED their first PR — the exact failure green-on-clone.sh exists to prevent. Only
# the ROW EXISTENCE leg is N/A'd; Kit-Class and Kit-Skill still apply universally.
# LS_ROW_STATE records what the row leg actually DID, so the success line cannot claim a leg that
# never ran. An N/A that is silent is how a gate ends up asserting more than it verified.
LS_ROW_STATE="unknown"

check_row() {   # $1 = sha
  _ls_row=$(decl_field "$1" Kit-Row | head -1)
  # TBG-SEAM-MD-ARM: the ONLY board access this function performs, on any backend — SEAM_ROOT
  # tracks LS_BOARDROOT (which fixture legs re-point at throwaway trees) so the seam always
  # resolves in the same root this function's other, unrouted board reads (below) already use.
  SEAM_ROOT="$LS_BOARDROOT"
  _ls_backend=$(seam_backend)

  # ⚠️ SELF-SERVICE N/A — DISCLOSED, NOT CLOSED. The backend field and the board are read from the
  # PR's OWN worktree, so a change can grant itself an N/A in the same commit: flip the backend to
  # `GitHub Issues`, or delete BACKLOG.md, and the row leg stops checking. Reading them from the
  # merge base would close it but would break the base-independence `verify.sh` relies on to
  # register the selftest. Announced on every N/A branch below so the escape is at least LOUD, and
  # boarded as LOOP-STATE-NA-SELF-SERVICE.
  case "$_ls_backend" in
    unrecognized:*)
      # FAIL-CLOSED. A mistyped backend must not silently lose the gate — that is the dark-gate
      # class backlog-lib.sh:49-55 closed deliberately, and inheriting its signal keeps one voice.
      echo "loop-state: backlog backend '$(ls_safe "${_ls_backend#unrecognized:}")' is not recognised — refusing" >&2
      LS_ROW_STATE="refused"
      return 1 ;;
    github|jira|ado|linear|gitlab)
      # TBG-RECORD-GATES-BIND (design §2 scope C, §8a H-4): a SET SEAM_RECORD switches this branch
      # to the tracker arm — bind (rc0) or refuse UNVERIFIED (rc2 inside the seam, surfaced here as
      # a plain gate refusal), NEVER waivable, NEVER falling through to not_enforced_notice. An
      # UNSET SEAM_RECORD keeps today's behaviour byte-identical below (rc 3 NOT ENFORCED, waiver
      # ladder preserved) — H-4's "no adopter green->red" rule.
      if seam_tracker_record_set; then
        SEAM_HEAD="$1"
        _ls_tn=$(seam_row_count "$_ls_row") || _ls_tn=""
        case "$_ls_tn" in
          1)
            LS_ROW_STATE="resolved (tracker record)"
            return 0 ;;
          *)
            echo "loop-state: Kit-Row '$(ls_safe "$_ls_row")' did not bind on the tracker record at \$SEAM_RECORD — UNVERIFIED, refusing (never waivable — a set record is never routed through the waiver ladder)" >&2
            LS_ROW_STATE="refused"
            return 1 ;;
        esac
      fi
      # LOOP-STATE-TRACKER-STEP-ASIDE T1 (design §2, AC1/AC4): checked ONLY HERE, strictly AFTER
      # the seam_tracker_record_set block above has already returned — the trusted job (which sets
      # SEAM_RECORD) is never itself excused by its own required-context wiring (RD-2, no
      # self-delegation; proven by delegate/record-wins plus a hoist mutant). Both --base-dir and
      # --live-contexts must have been given (LS_BASE_DIR/LS_LIVE_CONTEXTS non-empty); the shared
      # predicate itself fails closed on anything missing/malformed (backlog-lib.sh::bp_tracker_delegated).
      if [ -n "$LS_BASE_DIR" ] && [ -n "$LS_LIVE_CONTEXTS" ] && bp_tracker_delegated "$LS_BASE_DIR" "$LS_LIVE_CONTEXTS"; then
        LS_ROW_STATE="N/A (delegated to tracker-board-gates — live on the base branch)"
        echo "loop-state: row check $(tracker_delegated_notice)"
        return 0
      fi
      # NOT AN N/A ANY MORE (NON-MD-BACKEND-NEVER-SILENT, D-240903-1 §3). This branch used to say
      # "the row lives in an external tracker" and return 0 — but the kit cannot READ that tracker,
      # so what it actually said was "not checked", in the voice of "checked and fine". The row
      # leg now refuses, with the sentence backlog-lib.sh::not_enforced_notice gives all three
      # board-bound gates, unless a ratified board-governance waiver renders it green WITH the
      # notice. Enforce-vs-observe stays the adopter's LOOP_STATE_MODE dial at the job level; no
      # third knob is added here.
      _ls_ne=0
      # NO `2>&1` (reviewer r3): not_enforced_notice's stderr is its FAIL-CLOSED note — "the
      # validator is not present, treating the waiver as absent". Folding that into the captured
      # stdout would splice a diagnostic into the verdict line the summary prints, and the note
      # belongs on stderr where a reader can tell the two apart.
      # LOOP-STATE-TRACKER-STEP-ASIDE amendment A2: the same cure both gates give, lifted into the
      # one shared helper — an agent reading either gate's refusal gets the same instruction, not
      # loop-state's own generic waiver-only clause (backlog-lib.sh::not_enforced_notice's default).
      _ls_neout=$(not_enforced_notice "$_ls_backend" "$LS_BOARDROOT" "$DIR/conformance/waivers-valid.sh" "$(tracker_delegated_cure)") || _ls_ne=$?
      # STREAM FOLLOWS VERDICT (security S-L3). A waived run is a PASS and its notice is a verdict —
      # stdout. An unwaived run is a REFUSAL and its sentence is the reason — stderr, like every
      # other refusal in this function. That is not cosmetic: hooks/pre-push captures this
      # predicate's STDERR ONLY (`2>&1 >/dev/null`), so with the sentence on stdout the hook refused
      # with "fix the trailer block on the pushed head" — a remedy for a defect the author does not
      # have and cannot fix, on a tree where the trailers are perfect.
      if [ "$_ls_ne" -eq 0 ]; then
        echo "loop-state: row check $_ls_neout"
      else
        echo "loop-state: row check $_ls_neout" >&2
      fi
      if [ "$_ls_ne" -eq 0 ]; then
        LS_ROW_STATE="NOT ENFORCED (backend '$(ls_safe "$_ls_backend")' — waived)"
        return 0
      fi
      LS_ROW_STATE="NOT ENFORCED (backend '$(ls_safe "$_ls_backend")')"
      return 1 ;;
  esac

  # md, or undeclared. Undeclared plus a real in-use board still gets checked — an adopter must
  # not be able to skip row-binding by deleting a field.
  _ls_board="$LS_BOARDROOT/BACKLOG.md"
  if [ ! -f "$_ls_board" ]; then
    LS_ROW_STATE="N/A (no BACKLOG.md — fresh adopter export)"
    echo "loop-state: row check $LS_ROW_STATE"
    return 0
  fi
  if is_pure_template "$_ls_board"; then
    LS_ROW_STATE="N/A (board is still the pristine template)"
    echo "loop-state: row check $LS_ROW_STATE"
    return 0
  fi

  # A ROW LOOKUP, NOT A SUBSTRING MATCH (BOARD-ROW-IDENTIFIER). What stood here was
  # `grep -Fq -- "$_ls_row" "$_ls_board"` over the WHOLE FILE: any byte sequence occurring anywhere
  # in the board satisfied it — `Kit-Row: a` passed, as did a token occurring only in a Links cell
  # (both reproduced by security review, both now legs d and e). The comment that replaced this one
  # said the fix "needs a stable row-ID column on the board". It did not: the board ALREADY carries
  # one, as the FIRST backticked token of the Item cell, and three mechanisms already resolved it
  # (backlog-current's Disposition clause, backlog-presence's inprogress_hints, board-claim's ref
  # name). This was the fourth mechanism, and the only one that disagreed.
  # `row_count` is called, never `row_exists`: EXISTENCE is not enough. A duplicated id means two
  # rows answer to one `Kit-Row`, and a gate that picked either would bind the commit to a row
  # nobody chose.
  # NO REGEX IS BUILT FROM THE VALUE — row_count is string equality on a parsed cell (backlog-lib).
  # `_ls_row` is echoed through ls_safe: it is attacker-influenceable trailer text on its way to a
  # CI log (the C0/DEL lesson at :296-305).
  # THE GRAMMAR IS CHECKED AT THE FRONT DOOR, not merely quoted in a refusal (security S-M2). Until
  # this call existed, a lower-case id on BOTH sides — `| \`kw6-a2\` — … |` on the board and
  # `Kit-Row: kw6-a2` on the commit — RESOLVED, while the refusal below told the reader the grammar
  # was `[A-Z0-9][A-Z0-9-]*`. That is a gate whose message and behaviour disagree, and it also
  # admitted an id `scripts/board-claim.sh` refuses at ITS front door (it becomes a ref name), so
  # the pair could never have been claimed. `row_id_ok` is the ONE definition, in backlog-lib.sh.
  # It is a DISTINCT refusal from "names no row": telling an author their id is malformed sends
  # them to a different edit than telling them their board is missing a row.
  if ! row_id_ok "$_ls_row"; then
    echo "loop-state: Kit-Row '$(ls_safe "$_ls_row")' is not a well-formed row id — it must match [A-Z0-9][A-Z0-9-]* (upper-case letters, digits and hyphens; it becomes a ref name for sh scripts/board-claim.sh claim). Lead your row's Item cell with that backticked id (CLAUDE.md §1 act 3)." >&2
    LS_ROW_STATE="refused"
    return 1
  fi
  _ls_n=$(seam_row_count "$_ls_row") || _ls_n=""
  case "$_ls_n" in
    ''|*[!0-9]*)
      # FAIL-CLOSED. A counter that did not run is never `resolved`.
      echo "loop-state: the row lookup for Kit-Row '$(ls_safe "$_ls_row")' could not be evaluated on $_ls_board — refusing" >&2
      LS_ROW_STATE="refused"
      return 1 ;;
  esac
  if [ "$_ls_n" -eq 0 ]; then
    echo "loop-state: Kit-Row '$(ls_safe "$_ls_row")' names no row on $_ls_board — the id is the first backticked token of a row's Item cell ([A-Z0-9][A-Z0-9-]*); lead your row's Item cell with the backticked id (CLAUDE.md §1 act 3)." >&2
    LS_ROW_STATE="refused"
    return 1
  fi
  if [ "$_ls_n" -gt 1 ]; then
    echo "loop-state: Kit-Row '$(ls_safe "$_ls_row")' is AMBIGUOUS — $_ls_n rows carry it; a row id must be unique across the board." >&2
    LS_ROW_STATE="refused"
    return 1
  fi
  # RESOLVED — and the word is load-bearing. It means the id names EXACTLY ONE row, which is what
  # `matched` never meant. What it still does NOT mean (design §5): that the row is the one the
  # change is ABOUT (a row boarded and closed in the same PR resolves), that the id is unique
  # anywhere but this board, or that the trailer's author is anyone in particular.
  LS_ROW_STATE="resolved"
  return 0
}

# The repo the SKILL path is resolved in. Production is this repo; the path-safety legs point it
# at the throwaway fixture repo so hostile paths (a traversal, an untracked file, a tracked
# symlink) can be built without planting them in the kit's real skills/ tree.
LS_SKILLREPO="$DIR"

# check_skill — Kit-Skill names a real, tracked, non-symlink, stage-appropriate skill.
#
# PATH SAFETY (design section 3.0, Security N2). Kit-Skill is attacker-influenceable text
# interpolated into skills/<value>/SKILL.md. The /SKILL.md suffix blunts naive traversal, but
# that is luck rather than design — a tracked symlink skills/x -> /etc resolves outside the tree,
# reproduced in this repo as ceremony-binding MED-5. The confinement here is stronger than a
# blacklist: the value must be exactly `skills/<name>` where <name> contains NO slash at all, so
# traversal is unreachable rather than filtered.
check_skill() {   # $1 = sha
  # RESET THE DERIVED NAME. sh has no locals: _ls_name is a global, and leaving it set let a
  # neutered form-branch inherit the PREVIOUS invocation's name, skip the single-component case
  # entirely, and die at the file check instead — which made the form leg's fixture vacuous
  # (measured). Production impact today is nil (run_gate calls this once per process); this is test
  # integrity, and removing the stale-global hazard beats working around it.
  _ls_name=""
  _ls_raw=$(decl_field "$1" Kit-Skill | head -1)

  # FORM — exactly `skills/<name>`; anything else is refused before it touches the filesystem.
  case "$_ls_raw" in
    skills/*) _ls_name=${_ls_raw#skills/} ;;
    *) echo "loop-state: Kit-Skill '$(ls_safe "$_ls_raw")' must be of the form skills/<name>" >&2; return 1 ;;
  esac
  # NO slash in the name kills traversal outright (skills/../etc becomes name '../etc').
  # An empty name and any dot-dot are refused with it.
  case "$_ls_name" in
    ''|*/*|*..*) echo "loop-state: Kit-Skill name '$_ls_name' must be a single path component" >&2; return 1 ;;
  esac

  _ls_rel="skills/$_ls_name/SKILL.md"
  # Not a symlink in the directory component, and a regular file at the leaf.
  if [ -L "$LS_SKILLREPO/skills/$_ls_name" ]; then
    echo "loop-state: skills/$_ls_name is a symlink — refused" >&2; return 1
  fi
  if [ ! -f "$LS_SKILLREPO/$_ls_rel" ]; then
    echo "loop-state: Kit-Skill '$(ls_safe "$_ls_raw")' names no skill on disk ($(ls_safe "$_ls_rel"))" >&2; return 1
  fi
  # TRACKED — an untracked file is not part of the ratified tree.
  if ! git -C "$LS_SKILLREPO" ls-files --error-unmatch -- "$_ls_rel" >/dev/null 2>&1; then
    echo "loop-state: $_ls_rel is not tracked — refused" >&2; return 1
  fi
  # git mode 120000 is a symlink even when the working tree looks like a file.
  if [ "$(git -C "$LS_SKILLREPO" ls-files -s -- "$_ls_rel" | cut -d' ' -f1)" = "120000" ]; then
    echo "loop-state: $_ls_rel is recorded as a symlink (mode 120000) — refused" >&2; return 1
  fi

  # STAGE-APPROPRIATENESS — from the map, never a hardcoded pairing. An unmapped stage FAILs
  # rather than falling through (that fall-through is the shape this design has hit three times).
  _ls_stage=$(decl_field "$1" Kit-Stage | head -1)
  _ls_allowed=$(conf_val "STAGE_SKILLS_$_ls_stage")
  [ -n "$_ls_allowed" ] || {
    echo "loop-state: stage '$_ls_stage' has no skill set in the map — refused" >&2; return 1; }
  case " $_ls_allowed " in
    *" $_ls_name "*) return 0 ;;
    *) echo "loop-state: skills/$(ls_safe "$_ls_name") does not govern stage '$(ls_safe "$_ls_stage")' (allowed: $(ls_safe "$_ls_allowed"))" >&2
       ls_print_stage_map                                   # K20 — the whole map, not just this row
       return 1 ;;
  esac
}

# check_skill_if_present — the run_gate-level conditional, extracted so it can be held by a test.
#
# Under the class-proportional set (ls_required_keys) Kit-Skill is only REQUIRED for
# sensitive/control-plane, but it is VALIDATED whenever it appears. Absence is N/A here rather
# than in check_skill itself, because check_skill's own refusals (form, traversal, symlink,
# untracked) must keep their teeth for every commit that does carry the key — and an "empty means
# pass" arm buried inside check_skill would have been reachable by an empty trailer value too.
# The charset leg in check_declaration already refuses an empty value, so this predicate keys off
# OCCURRENCE COUNT, not the string.
check_skill_if_present() {   # $1 = sha
  if [ "$(decl_count "$1" Kit-Skill)" -eq 0 ]; then
    return 0
  fi
  # A VOLUNTEERED SKILL WITH NO STAGE IS REFUSED BY ITS OWN NAME (security M-2). check_skill grades
  # stage-appropriateness, so with Kit-Stage absent it used to reach the map lookup with an empty
  # stage and refuse with "stage '' has no skill set in the map" — a true refusal reported as a map
  # defect, sending the author to .kit/roster.conf to fix a trailer they simply did not write. The
  # pair is what carries meaning: a skill is only ever validated AGAINST a stage.
  if [ "$(decl_count "$1" Kit-Stage)" -eq 0 ]; then
    echo "loop-state: Kit-Skill was volunteered without Kit-Stage — a volunteered skill is validated against the stage; declare both or neither" >&2
    return 1
  fi
  check_skill "$1"
}

# ---------------------------------------------------------------------------
# Kit-Scope — B9 (PHASE-B-SPINE slice 9), design docs/architecture/2026-08-11-b9-process-mechanized-design.md §2.
#
# The OPTIONAL fifth trailer: a space-separated set of path PREFIXES declaring what this pull
# request is allowed to touch. It joins the Kit-* family on the same head commit, is read by the
# same parser (decl_field — never a grep), and is graded against the changed set measured
# merge-base(default branch, head)..head — the same "THE HEAD DECLARATION DESCRIBES THE PULL
# REQUEST" doctrine the class leg already uses (see the header note).
#
# HONEST CEILING — do not overclaim (design §7.1). The declaration is written by the author it
# constrains and lives on an amendable commit, so what this binds is DECLARATION↔DIFF CONSISTENCY
# AT EACH PUSH, never "the declaration preceded the work": an author can widen the line to match
# whatever the diff became, or declare a scope as wide as the tree. No trailer mechanism can bind
# declaration-precedes-work (a frozen-first-commit variant is defeated by rebase). The value is
# (a) LEGIBILITY — one owner-vetoable line on the PR head, where widening it mid-flight is itself
# a visible diff of the declaration — and (b) DRIFT SURFACING: an undeclared path goes loud at the
# push where it first appears. Loud, not impossible (`D3′`: drift control, not an arms race).
#
# ⚠️ WHERE THE OBSERVE-MODE PRINT ACTUALLY LANDS. In observe mode this leg returns 0, and the
# installed pre-push hook's decl leg DISCARDS a PASSING predicate's output (`hooks/pre-push:90-92`
# captures stderr, then `return 0` without printing it). So at the PRE-PUSH surface the loud print
# is visible only when `KIT_SCOPE_MODE=enforce` makes this leg return non-zero; in CI — the bound
# gate that runs at the PR head on every push — the print is in the job log either way. Stated
# rather than assumed; no hook edit is made here (design §2, "zero hook edit").
#
# ⚠️ `Kit-Scope` (a PATH SET) is NOT `D11`'s `scope:` key (a SLICE IDENTITY, ceremony-binding.sh).
# Different objects; the name collision is disclosed so no reviewer conflates them. That whole
# surface (BRANCH-SCOPE-END-TO-END) is deliberately untouched here.

# The ref the scope basis is measured against. Empty = resolve it (production). The selftest pins it
# to a fixture ref — a PLAIN SCRIPT VARIABLE, never an env route (OBLIGATION-TESTMODE-ENV-FLAG; the
# rule LS_REPO / LS_BOARDROOT / LS_SKILLREPO already follow). Without a pinned base the fixture legs
# would resolve the fixture repo's AMBIENT default branch (init.defaultBranch is a user setting —
# `main` on one machine, `master` on another) and grade a base that varies per machine.
LS_SCOPE_BASEREF=""

# LS_SCOPE_STATE records what the scope leg actually DID, so the success line cannot claim a leg
# that never ran — the LS_ROW_STATE discipline. An N/A that is silent is how a gate ends up
# asserting more than it verified.
LS_SCOPE_STATE="unknown"

# scope_base — the merge base of the default branch and $1. Prints it; rc 1 when unresolvable.
# LOCAL READS ONLY (no `git fetch`, no `git remote show`): a merge gate must never depend on network
# reachability. Candidates, in order: the pinned fixture ref → origin/HEAD → origin/main →
# origin/master → main → master. Nothing here is environment-overridable.
# ⚠️ STALE-BASIS NOTE (A4-ii, B9 §10 reviewer-LOW): the local `main`/`master` fallbacks are last on
# purpose — a stale local `main` gives an older merge-base, which can only OVER-report the changed
# set (paths already merged upstream re-appear as "changed"). That grades FAIL-NOISY (the escape
# print is loud, an author widens Kit-Scope or refreshes their base), NEVER fail-open: an outdated
# basis cannot make an escaping path silently pass. CI reads origin/* and never hits this arm.
scope_base() {   # $1 = sha
  if [ -n "$LS_SCOPE_BASEREF" ]; then
    git -C "$LS_REPO" merge-base "$LS_SCOPE_BASEREF" "$1" 2>/dev/null || return 1
    return 0
  fi
  _ls_dh=$(git -C "$LS_REPO" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  for _ls_c in "$_ls_dh" origin/main origin/master main master; do
    [ -n "$_ls_c" ] || continue
    git -C "$LS_REPO" rev-parse --verify --quiet "$_ls_c^{commit}" >/dev/null 2>&1 || continue
    if _ls_mb=$(git -C "$LS_REPO" merge-base "$_ls_c" "$1" 2>/dev/null); then
      printf '%s\n' "$_ls_mb"
      return 0
    fi
  done
  return 1
}

# scope_covers — 0 when any declared token COVERS <path> on a PATH-COMPONENT boundary (A4iv
# tightening, ruling D-240811-2.1; this REVERSES the old plain-prefix contract). Pinned spec:
#   * a token ending `/` covers ONLY paths strictly under it: `foo/` covers `foo/x`, and NEVER the
#     bare name `foo`. This is just the literal prefix match, since the token already carries the `/`.
#   * a token WITHOUT a trailing `/` covers EXACT (`foo` covers `foo`) or `foo/`-prefixed (`foo`
#     covers `foo/x`), but NOT `foobar`. A normalize-`foo/`-to-exact implementation would newly
#     cover the bare file `foo` — a widening (new escape) the spec and the negative fixture forbid.
# The pattern side is a QUOTED expansion, so the token is literal and never a glob — which is exactly
# why the hostile-token refusal above must run first (an unrejected `*` would arrive as a live
# pattern). The nested `case` lives in this function, NOT inline in the diff `$( ... )` — bash 3.2
# mis-parses `case ... esac` inside a command substitution (the :548 note); a function body is fine.
scope_covers() {   # $1 = path, $2 = the declared tokens
  for _ls_cp in $2; do
    case "$_ls_cp" in
      */) case "$1" in "$_ls_cp"*) return 0 ;; esac ;;
      *)  case "$1" in "$_ls_cp"|"$_ls_cp"/*) return 0 ;; esac ;;
    esac
  done
  return 1
}

# scope_leg — the whole ladder. Called ONLY through check_scope, which owns the noglob window.
scope_leg() {   # $1 = sha
  LS_SCOPE_STATE="unknown"
  LS_SCOPE_ESCAPED=""   # the escaping paths, captured for the run_gate scope-only epilogue (A3i)
  _ls_sn=$(decl_count "$1" Kit-Scope)

  # ABSENT → disclosed N/A, never red. The trailer is OPTIONAL and this is first-run-green (the B6
  # precedent). Whether gated/control-plane changes should be REQUIRED to declare a Kit-Scope (the
  # absence arm's drift-control -> containment-boundary question) is the named trigger boarded as
  # SCOPE-ABSENCE-REFUSAL-ON-GATED (ratified as a tracked residue, 2026-08-13, D-240811-2.1) — not
  # decided here, but owned there rather than parked in this comment.
  # (A present-but-EMPTY value lands in this same arm — git emits an empty line and `grep -c .`
  # counts none. That is exactly equivalent to not declaring, so nothing is weakened by it.)
  if [ "$_ls_sn" -eq 0 ]; then
    LS_SCOPE_STATE="N/A (no scope declared)"
    echo "loop-state: scope check $LS_SCOPE_STATE"
    return 0
  fi
  # EXACTLY ONE occurrence, the family's rule: two Kit-Scope lines with different sets yield both,
  # and head -1 / tail -1 reach opposite verdicts. Never "take the first".
  if [ "$_ls_sn" -ne 1 ]; then
    echo "loop-state: $1 carries $_ls_sn occurrences of 'Kit-Scope' — exactly one is required" >&2
    LS_SCOPE_STATE="refused (duplicate Kit-Scope)"
    return 1
  fi
  _ls_scope=$(decl_field "$1" Kit-Scope | head -1)

  # HOSTILE INPUT FIRST — before the value can reach any matching. Each token is interpolated into
  # a `case` PATTERN below, where an unrejected `*` or `?` silently widens the declaration to match
  # anything; the trailer is attacker-influenceable (anyone may open a PR with any trailer), the
  # identical path that forced the charset refusal on Kit-Row (check_declaration above). `..` and a
  # leading `/` are refused with them: a declared prefix is a repo-relative path, never a traversal
  # and never absolute.
  for _ls_p in $_ls_scope; do
    case "$_ls_p" in
      *'*'*|*'?'*|*'['*|*..*|/*)
        echo "loop-state: Kit-Scope token '$(ls_safe "$_ls_p")' is not a plain path token — a glob metacharacter (* ? [), '..' or a leading '/' is refused at the boundary" >&2
        LS_SCOPE_STATE="refused (hostile scope token)"
        return 1 ;;
    esac
  done

  # FAIL-SAFE, DISCLOSED. A shallow clone or an absent default-branch ref has no basis to measure
  # against (the measured B2-Δ2 clone-shape class). A red here would break every healthy fresh
  # clone — the green-on-clone failure class — and a SILENT pass would be worse.
  if ! _ls_base=$(scope_base "$1"); then
    LS_SCOPE_STATE="N/A (scope basis unresolvable)"
    echo "loop-state: scope check $LS_SCOPE_STATE — no merge base against a default branch (shallow clone / absent ref)"
    return 0
  fi

  # --no-renames ON PURPOSE: with rename detection a move OUT of a declared prefix reports only the
  # new path, and a move INTO one hides the deletion at the old path. Both endpoints must be graded.
  # COMPONENT-BOUNDARY MATCH, per the A4iv ruling (D-240811-2.1) — this REVERSED the earlier
  # plain-prefix contract, under which `docs` wrongly covered `docs-old.md`. Now a token is matched
  # on a path-component boundary: `docs` covers `docs` and `docs/…` but NOT `docs-old.md`, and a
  # trailing-slash token (`docs/`) covers strictly-under only. The rule lives in scope_covers.
  # ⚠️ The match lives in scope_covers, NOT inline here: bash 3.2 (macOS /bin/sh, which runs
  # this repo's own hooks) mis-parses a `case` ... `esac` INSIDE a `$( ... )` — "syntax error near
  # unexpected token ';;'", measured, on one line and on several. dash parses it fine, so a
  # linux-only test would never have seen it. Keeping `case` out of the substitution is the fix.
  _ls_esc=$(
    git -C "$LS_REPO" diff --name-only --no-renames "$_ls_base" "$1" 2>/dev/null |
    while IFS= read -r _ls_f; do
      [ -n "$_ls_f" ] || continue
      if scope_covers "$_ls_f" "$_ls_scope"; then continue; fi
      printf '%s\n' "$_ls_f"
    done
  )
  _ls_ec=$(printf '%s' "$_ls_esc" | grep -c . || true)
  if [ "$_ls_ec" -eq 0 ]; then
    # A4-i (B9 §10 reviewer-LOW): STATE THE GRADED-PATH COUNT. A self-referential origin/HEAD clone
    # shape (base == head) yields an EMPTY diff, so "every changed path is under a declared scope token"
    # is vacuously true over ZERO paths — the count makes that visible instead of implying coverage.
    _ls_gc=$(git -C "$LS_REPO" diff --name-only --no-renames "$_ls_base" "$1" 2>/dev/null | grep -c . || true)
    LS_SCOPE_STATE="PASS ($_ls_gc changed path(s) graded; every changed path is under a declared scope token)"
    echo "loop-state: scope check $LS_SCOPE_STATE"
    return 0
  fi

  echo "loop-state: SCOPE LOUD — $_ls_ec changed path(s) fall outside the declared Kit-Scope '$(ls_safe "$_ls_scope")':" >&2
  printf '%s\n' "$_ls_esc" | while IFS= read -r _ls_f; do
    [ -n "$_ls_f" ] || continue
    echo "loop-state:   $(ls_safe "$_ls_f")" >&2
  done
  echo "loop-state:   remedy: widen Kit-Scope on the head commit to cover them, or take the change out of this PR." >&2
  # THE DIAL — read from the repo-carried .kit/dials.conf via ls_dial_mode (DIAL-DELIVERY Δ-B): the
  # conf value is authoritative and env can only ESCALATE (never de-escalate) it. The kit's own tree
  # SHIPS ENFORCE (KIT_SCOPE_MODE=enforce, locked by conformance/dial-state.sh); an adopter export
  # carries no conf and reads OBSERVE. The escaping paths are captured for the run_gate epilogue.
  LS_SCOPE_ESCAPED="$_ls_esc"
  if [ "$(ls_dial_mode KIT_SCOPE_MODE)" = "enforce" ]; then
    LS_SCOPE_STATE="refused ($_ls_ec path(s) outside the declared scope — SCOPE=enforce via .kit/dials.conf)"
    return 1
  fi
  echo "loop-state:   observe mode — rc unchanged; set KIT_SCOPE_MODE=enforce in .kit/dials.conf to refuse instead (or export it to escalate this run only; see docs/adoption/brownfield.md)." >&2
  LS_SCOPE_STATE="observed ($_ls_ec path(s) outside the declared scope — observe mode, rc unchanged)"
  return 0
}

# check_scope — scope_leg inside a NOGLOB window, which is load-bearing, not stylistic.
# `for _ls_p in $_ls_scope` word-splits AND pathname-expands, so a `docs/*` token would EXPAND
# against the current directory before the hostile-token check ever saw it — the check would then
# grade the expansion instead of the declaration. `set -f` closes that; `set +f` restores it for
# every leg that follows (map_completeness globs skills/*/).
check_scope() {   # $1 = sha
  set -f
  _ls_scope_rc=0
  scope_leg "$1" || _ls_scope_rc=$?
  set +f
  return "$_ls_scope_rc"
}

# ls_fail_epilogue — the run_gate failure epilogue, in THREE shapes (A3i, DIAL-DELIVERY Δ-B; I1/F4).
#
# The mode is computed by ls_scope_epilogue_mode (below) from the two facts run_gate already holds —
# NOT from any parse of the formatted LS_SCOPE_STATE string (design-gate LOW-6a):
#   1 = a scope path-ESCAPE was the SOLE failure. The Entry-Declaration trailers are valid and the
#       diff escaped the declared Kit-Scope; name the escaping path(s). Reached ONLY under enforce —
#       an escape returns rc 0 under observe (scope_leg:646-653), so "SCOPE=enforce" is TRUE whenever
#       this mode fires (the I1 fix is precisely that mode 1 is now gated on a captured escape).
#   2 = a scope BOUNDARY refusal (hostile token / duplicate Kit-Scope key) was the SOLE failure. The
#       trailers are valid, so the generic "does not carry a valid Entry Declaration" text is FALSE;
#       and NO path escaped, so the escape epilogue (and its "SCOPE=enforce") would be FALSE too — the
#       I1 defect, doubly wrong under observe, where a hostile token is refused unconditionally at the
#       boundary. scope_leg already printed the precise reason; this epilogue claims neither.
#   0 = anything else — a real Entry-Declaration defect; print the trailer contract (CLAUDE.md §1).
# The named paths go through ls_safe — a pushed filename is attacker-influenceable (the
# every-interpolation rule at ls_safe:79-90).
ls_fail_epilogue() {   # $1 = mode(0|1|2), $2 = sha, $3 = newline-separated escaping paths
  if [ "$1" -eq 1 ]; then
    echo "loop-state: FAIL — $2 declares a Kit-Scope that its own changed paths escape (SCOPE=enforce)." >&2
    echo "  The Entry Declaration trailers are valid; this refusal is the SCOPE leg alone. Escaping path(s):" >&2
    printf '%s\n' "$3" | while IFS= read -r _ls_ep; do
      [ -n "$_ls_ep" ] || continue
      echo "    $(ls_safe "$_ls_ep")" >&2
    done
    echo "  remedy: widen Kit-Scope on the head commit to cover them, or take them out of this change." >&2
    return 0
  fi
  if [ "$1" -eq 2 ]; then
    echo "loop-state: FAIL — $2 was refused by the SCOPE leg alone; the Entry Declaration trailers are valid." >&2
    echo "  No path escaped the declared Kit-Scope — the Kit-Scope declaration itself was rejected at the" >&2
    echo "  boundary (see the reason printed above). Fix the Kit-Scope trailer, not the diff." >&2
    return 0
  fi
  echo "loop-state: FAIL — $2 does not carry a valid Entry Declaration." >&2
  echo "  The contract is CLAUDE.md section 1. Trailers must be the LAST paragraph of the commit" >&2
  echo "  message and CONTIGUOUS: a blank line before Co-Authored-By silently drops every Kit-* field." >&2
  return 0
}

# ls_scope_epilogue_mode — the A3i/I1 discriminant, EXTRACTED from run_gate so it is directly testable
# with controlled inputs. Driving the whole run_gate in the selftest is NOT hermetic: its check_class
# leg derives the class from the AMBIENT working tree (derive_class runs promotion-readiness with no
# fixture listing in the run_gate path — the deliberate "no --changed flag" at :289-293), so the
# non-scope legs cannot be pinned green from a fixture commit. This function is the exact logic that
# mislabelled a boundary refusal as a path escape before I1 — mode is escape(1) ONLY when a real
# escape was captured, never merely because scope was the only failing leg.
#   $1 = nonscope_bad (0|1) — did ANY non-scope leg fail?   $2 = captured escaping paths (maybe empty)
ls_scope_epilogue_mode() {
  [ "$1" -eq 0 ] || { printf 0; return 0; }   # a non-scope leg failed -> the trailer contract
  [ -n "$2" ] && { printf 1; return 0; }       # a REAL escape was captured -> the escape epilogue
  printf 2; return 0                            # scope-only, but NO escape -> a boundary refusal
}

# ---------------------------------------------------------------------------
# Fixture repo. Tiny and trap-cleaned: heavy selftests leaking full-repo temp trees filled the
# work machine twice (banked: conformance-disk-safety). This creates four commits in an empty
# repo — no clone, no checkout of this tree.
# ---------------------------------------------------------------------------
LS_FXDIR=""
ls_fx_cleanup() { [ -n "$LS_FXDIR" ] && [ -d "$LS_FXDIR" ] && rm -rf "$LS_FXDIR"; LS_FXDIR=""; }

ls_fx_build() {
  LS_FXDIR=$(mktemp -d) || return 1
  trap ls_fx_cleanup EXIT INT TERM
  git -C "$LS_FXDIR" init -q
  git -C "$LS_FXDIR" config user.email fixture@example.invalid
  git -C "$LS_FXDIR" config user.name "loop-state fixture"

  # A — CONFORMANT: contiguous trailer block, nothing after it but another trailer.
  : > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'conformant fixture\n\nbody\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_OK=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # B — BASELINE NEGATIVE: no Kit-* trailers at all.
  echo b > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'no declaration at all\n\njust a body\n' | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_NONE=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # C — ANCESTOR NEGATIVE: this child carries nothing; its PARENT (B... and A) do/does not
  # matter — what matters is that checking THIS sha must not walk back to A and pass.
  echo c > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'child of a declared commit\n\nbody\n' | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_CHILD=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # D — KILL FIXTURE: all four fields PRESENT in the message, severed from the trailer paragraph
  # by GitHub's squash separator. git parses NO Kit-* trailers here. A grep implementation passes
  # this commit; the real parser must FAIL it. This is the exact shape of every squash-merge on
  # this repo's main today.
  echo d > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'severed trailer block\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\n\n---------\n\nCo-authored-by: X <x@example.invalid>\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SEVERED=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # E — BAD STAGE: well-formed block, but Kit-Stage is not in the map.
  echo e > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'stage outside the map\n\nKit-Row: DEMO-ROW\nKit-Stage: Wibble\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_BADSTAGE=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # F — DUPLICATE KEY: two Kit-Class lines with OPPOSITE values. Measured decoy: `head -1` and
  # `tail -1` reach opposite verdicts, so "take the first" is not a safe reading. Must FAIL.
  echo f > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'duplicate key decoy\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: control-plane\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_DUP=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # G — METACHARACTER Kit-Row. The value flows into a board grep (T6), the identical path that
  # forced the charset refusal at ceremony-binding.sh:124-136. Must be refused AT THE BOUNDARY,
  # not matched.
  echo g > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'regex metachar row\n\nKit-Row: DEMO.*ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_META=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # H — SINGLE-KEY POSITIVE for the count logic. Paired with F so an off-by-one (wc -l vs
  # grep -c .) cannot satisfy both: wc -l reports 2 for this one commit and would false-RED it.
  echo h > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'single key positive\n\nKit-Row: DEMO-ROW\nKit-Stage: Review\nKit-Class: sensitive\nKit-Skill: skills/review\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SINGLE=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # H2 — THE STAGE-ARTIFACT KEYS, WELL-FORMED (LOOP-STAGE-ARTIFACT-GATE). Kit-Review carries a
  # consolidated two-record set, so the comma split is exercised by the POSITIVE as well as by H3.
  echo h2 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'stage artifacts named\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/build\nKit-Plan: docs/plans/2026-09-04-demo.md\nKit-Review: docs/reviews/2026-09-04-demo.md,docs/reviews/2026-09-04-second.md\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ARTIFACT=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # H3 — Kit-Review OUTSIDE its prefix. The silent-typo hole: `notes/x.md` reads to a human as "a
  # record was named" and to both gates as nothing at all.
  echo h3 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'artifact key outside its prefix\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/build\nKit-Review: notes/2026-09-04-demo.md\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ARTIFACT_PFX=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # H3b — an EMPTY ELEMENT in the consolidated set (`a.md,,b.md`). The old IFS word-split dropped
  # empties silently; the heredoc/`IFS= read` split that replaced it (semgrep ifs-tampering) delivers
  # every element to the case, so the `''` arm now refuses it. Without this leg the split could regress
  # to a form that skips empties and nothing would notice.
  echo h3b > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'empty element in the set\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/build\nKit-Review: docs/reviews/2026-09-04-demo.md,,docs/reviews/2026-09-04-second.md\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ARTIFACT_EMPTY=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # H4 — a TRAVERSING Kit-Plan. Refused at the boundary, before any consumer resolves it.
  echo h4 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'traversing artifact key\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/build\nKit-Plan: docs/plans/../../etc/passwd.md\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ARTIFACT_TRAV=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # I — STAGE-INAPPROPRIATE: skills/tdd is real, but does not govern Plan.
  echo i > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'stage-inappropriate skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Plan\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_WRONGSKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # J — NONEXISTENT skill.
  echo j > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'nonexistent skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/nosuchskill\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_NOSKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # K — TRAVERSAL: passes the charset (dot and slash are legal characters) so only the form and
  # single-component rules stop it.
  echo k > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'traversal skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/../../etc\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_TRAVERSAL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # L — SYMLINK skill, TRACKED at git mode 120000 inside the fixture repo. Built here rather than
  # in conformance/fixtures/ so no tracked symlink is planted in the kit's real tree (and the
  # guard correctly refuses agent writes there anyway).
  # ⚠️ NON-VACUITY: these hostile skills are named `tdd` and `evals` — both STAGE-APPROPRIATE for
  # Kit-Stage: Build in the real map. If they were named arbitrarily, the stage check would reject
  # them first and these legs would pass for the wrong reason, leaving the path-safety checks
  # untested. Named this way, ONLY the symlink / untracked checks can reject them.
  mkdir -p "$LS_FXDIR/skills/build"
  printf '# fixture skill\n' > "$LS_FXDIR/skills/build/SKILL.md"
  # ⚠️ The symlink targets a directory that REALLY CONTAINS a SKILL.md. An earlier version pointed
  # it at /etc, which made the leg vacuous: it was rejected by the file-does-not-exist check, so
  # disabling symlink refusal entirely left the selftest green. Measured, then fixed.
  ln -s build "$LS_FXDIR/skills/tdd"
  mkdir -p "$LS_FXDIR/skills/evals"
  printf '# present on disk, never added to the index\n' > "$LS_FXDIR/skills/evals/SKILL.md"
  git -C "$LS_FXDIR" add skills/build skills/tdd
  git -C "$LS_FXDIR" commit -q -m "fixture skill tree"

  # L — SYMLINK skill, tracked at git mode 120000, and stage-appropriate by name.
  echo l > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'symlinked skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SYMSKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # M — UNTRACKED skill: present on disk, absent from the index, stage-appropriate by name.
  echo m > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'untracked skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/evals\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_UNTRACKED=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # N — POSITIVE inside the fixture repo: tracked, regular, stage-appropriate.
  echo n > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'good fixture skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/build\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_GOODSKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # ⚠️ HERMETIC BOARD, in its own subdirectory. The row legs used to assert against the KIT's live
  # BACKLOG.md, which made the selftest depend on mutable project data: it died on an adopter tree
  # (BACKLOG.md is export-ignore'd, so the negative leg inverted and green-on-clone went RED) and it
  # would die on the kit's own CI the day KIT-ADHERENCE-ENFORCEMENT is archived to Done.
  # The board lives in $LS_FXDIR/board/ and NOT in $LS_FXDIR itself — putting it at the fixture-repo
  # root would give $LS_FXDIR a BACKLOG.md and silently break the "no board present must be N/A"
  # leg, which is how the reviewer's first attempt at this failed.
  # BOARD-ROW-IDENTIFIER: the Item cell now LEADS with the backticked row id, because that is the
  # grammar CLAUDE.md §1 act 3 tells an adopter to write and the one `row_count` resolves. The
  # second row exists so a token can occur in a NON-Item cell (leg e) — the Links/Intent-cell
  # match that the old whole-file `grep -Fq` accepted.
  mkdir -p "$LS_FXDIR/board"
  printf '# Fixture board\n\n## Ready\n\n| Item | Intent |\n|---|---|\n| `FIXTURE-ROW-ALPHA` — a fixture row | why |\n| `OTHER-ROW` — another row | see LINKS-ONLY-ROW |\n' \
    > "$LS_FXDIR/board/BACKLOG.md"

  # TITLE-ONLY board (leg f): the row is there in prose but carries no backticked id, so it names
  # no row. This is the shape every pre-convention board has, and the refusal must hand the
  # adopter the act-3 remedy rather than "your row does not exist".
  mkdir -p "$LS_FXDIR/board-titleonly"
  printf '# Fixture board\n\n## Ready\n\n| Item | Intent |\n|---|---|\n| FIXTURE-ROW-ALPHA — a fixture row | why |\n' \
    > "$LS_FXDIR/board-titleonly/BACKLOG.md"

  # DUPLICATE board (leg g): one id on two rows. The load-bearing negative for row_count — a
  # `row_exists` implementation cannot tell this board from the good one.
  # LOWERCASE board (security S-M2): a board whose Item cell leads with `kw6-a2` and a commit whose
  # Kit-Row is `kw6-a2` AGREE with each other — and before the grammar was checked at the front
  # door, that pair RESOLVED, while the refusal text three lines below told everyone the grammar was
  # `[A-Z0-9][A-Z0-9-]*`. A gate whose message and behaviour disagree is worse than either.
  mkdir -p "$LS_FXDIR/board-lower"
  printf '# Fixture board\n\n## Ready\n\n| Item | Intent |\n|---|---|\n| `kw6-a2` — a lower-case id | why |\n' \
    > "$LS_FXDIR/board-lower/BACKLOG.md"

  mkdir -p "$LS_FXDIR/board-dup"
  printf '# Fixture board\n\n## Ready\n\n| Item | Intent |\n|---|---|\n| `FIXTURE-ROW-ALPHA` — a fixture row | why |\n\n## In Progress\n\n| Item | Owner |\n|---|---|\n| `FIXTURE-ROW-ALPHA` — the same id again | agent |\n' \
    > "$LS_FXDIR/board-dup/BACKLOG.md"

  # NOT ENFORCED route: a declared non-md backend. resolve_backend reads only <dir>/CLAUDE.md.
  # ⚠️ THIS DIR MUST ALSO CARRY A BOARD, or the leg is VACUOUS — measured: without a BACKLOG.md the
  # no-board branch satisfies it, so deleting the entire backend branch left the suite green. The
  # board's row deliberately does NOT contain the fixture's Kit-Row, so only the backend branch can
  # produce the verdict.
  # ⚠️ THIS COMMENT USED TO SAY "N/A route 2". IT IS NO LONGER AN N/A (NON-MD-BACKEND-NEVER-SILENT):
  # the branch reports NOT ENFORCED and REFUSES, and the two sibling fixtures below carry the
  # ratified waiver and the unfilled incept stamp that separate green-with-notice from red.
  mkdir -p "$LS_FXDIR/backend-github"
  printf '# Fixture charter\n\n- **Backlog backend**: GitHub Issues\n' > "$LS_FXDIR/backend-github/CLAUDE.md"
  printf '# Fixture board\n\n## Ready\n\n| Item | Intent |\n|---|---|\n| OTHER-ROW-PRESENT — not the declared row | why |\n' \
    > "$LS_FXDIR/backend-github/BACKLOG.md"

  # The same tree, plus a RATIFIED board-governance waiver (the §3.5a bridge) and, separately, the
  # UNFILLED stamp `incept` writes — which must buy nothing.
  mkdir -p "$LS_FXDIR/backend-github-waived"
  cp "$LS_FXDIR/backend-github/CLAUDE.md" "$LS_FXDIR/backend-github-waived/CLAUDE.md"
  cp "$LS_FXDIR/backend-github/BACKLOG.md" "$LS_FXDIR/backend-github-waived/BACKLOG.md"
  # TODAY-RELATIVE dates (security S-M1): a future `Opened` is refused, because it makes the 90-day
  # maximum nominal — so the 2099 dates this fixture used to carry would assert the opposite of the
  # rule. LS_FX_WV_EXP is re-read by the waived leg, so the assertion cannot drift from the fixture.
  LS_FX_WV_D0=$(date -u -d "+0 days" +%Y-%m-%d 2>/dev/null || date -u -v+0d +%Y-%m-%d)
  LS_FX_WV_EXP=$(date -u -d "+60 days" +%Y-%m-%d 2>/dev/null || date -u -v+60d +%Y-%m-%d)
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|--|--|--|--|--|--|--|\n| board-governance | the kit reads BACKLOG.md only | @jdoe | %s | %s | adopt TRACKER-BACKED-GOVERNANCE | @sec |\n' "$LS_FX_WV_D0" "$LS_FX_WV_EXP" \
    > "$LS_FXDIR/backend-github-waived/WAIVER-REGISTER.md"
  mkdir -p "$LS_FXDIR/backend-github-stamp"
  cp "$LS_FXDIR/backend-github/CLAUDE.md" "$LS_FXDIR/backend-github-stamp/CLAUDE.md"
  cp "$LS_FXDIR/backend-github/BACKLOG.md" "$LS_FXDIR/backend-github-stamp/BACKLOG.md"
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|--|--|--|--|--|--|--|\n| board-governance | x | [owner] | %s | %s | y | [security-owner] |\n' "$LS_FX_WV_D0" "$LS_FX_WV_EXP" \
    > "$LS_FXDIR/backend-github-stamp/WAIVER-REGISTER.md"

  # N/A route 3: a pristine-template board. is_pure_template wants the `| [title] |` example row
  # AND no other real data row.
  mkdir -p "$LS_FXDIR/board-pristine"
  printf '# Fixture board\n\n## Ready\n\n| Item | Intent |\n|---|---|\n| [title] | [why] |\n' \
    > "$LS_FXDIR/board-pristine/BACKLOG.md"

  # Fail-closed: a mistyped backend. backlog-lib signals this as `unrecognized:<token>` precisely
  # so it does NOT fail open to N/A.
  mkdir -p "$LS_FXDIR/backend-bogus"
  printf '# Fixture charter\n\n- **Backlog backend**: markdow\n' > "$LS_FXDIR/backend-bogus/CLAUDE.md"

  # --- LOOP-STATE-TRACKER-STEP-ASIDE T1 fixtures — the `delegate/*` legs (design §3, modelled on
  # backlog-presence.sh's own `delegate/*` builders) ------------------------------------------------
  # A BASE checkout bp_tracker_delegated can accept: declares jira, ships its OWN copy of the real
  # scripts/tracker-conf.sh (never this process's), and a .kit/tracker.conf that validator accepts.
  mkdir -p "$LS_FXDIR/t1-base/scripts" "$LS_FXDIR/t1-base/.kit"
  cp "$DIR/scripts/tracker-conf.sh" "$LS_FXDIR/t1-base/scripts/tracker-conf.sh"
  printf '# Base\n\n- **Backlog backend** (§6): jira\n' > "$LS_FXDIR/t1-base/CLAUDE.md"
  cat > "$LS_FXDIR/t1-base/.kit/tracker.conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
state.in-progress=In Progress
field.acceptance=description
field.metric=label:metric
field.size=label:size
field.risk=customfield_10088
EOF

  # base-declares-md: the SAME valid tracker conf, but the base's OWN CLAUDE.md declares md — the
  # predicate's condition (i) must fail first (AC5).
  mkdir -p "$LS_FXDIR/t1-base-md/scripts" "$LS_FXDIR/t1-base-md/.kit"
  cp "$LS_FXDIR/t1-base/scripts/tracker-conf.sh" "$LS_FXDIR/t1-base-md/scripts/tracker-conf.sh"
  cp "$LS_FXDIR/t1-base/.kit/tracker.conf" "$LS_FXDIR/t1-base-md/.kit/tracker.conf"
  printf '# Base\n\n- **Backlog backend** (§6): md\n' > "$LS_FXDIR/t1-base-md/CLAUDE.md"

  # bypass-head-conf: LS_BOARDROOT (the head's own dir) plants its own valid tracker.conf, but
  # LS_BASE_DIR stays the md base above — the predicate must never read LS_BOARDROOT's .kit/.
  mkdir -p "$LS_FXDIR/t1-head-conf/scripts" "$LS_FXDIR/t1-head-conf/.kit"
  cp "$LS_FXDIR/t1-base/scripts/tracker-conf.sh" "$LS_FXDIR/t1-head-conf/scripts/tracker-conf.sh"
  cp "$LS_FXDIR/t1-base/.kit/tracker.conf" "$LS_FXDIR/t1-head-conf/.kit/tracker.conf"
  printf '# Head\n\n- **Backlog backend** (§6): jira\n' > "$LS_FXDIR/t1-head-conf/CLAUDE.md"

  # live-contexts files.
  printf 'ci\ntracker-board-gates\nbacklog-presence\n' > "$LS_FXDIR/t1-live.txt"
  printf 'ci\nbacklog-presence\n' > "$LS_FXDIR/t1-live-missing.txt"
  : > "$LS_FXDIR/t1-live-empty.txt"
  printf 'ci\ntracker-board-gates (pull_request_target)\nbacklog-presence\n' > "$LS_FXDIR/t1-live-suffix.txt"

  # Map-completeness drift directions (b) and (c). Plan T1 step 4 required both and neither was
  # fixtured: review measured that gutting either check left the suite GREEN. The code was correct
  # and nothing held it there.
  # (b) a map entry naming no skill on disk.
  printf 'KIT_STAGES="Discover Plan Build Review Release Done Operate"\nSTAGE_SKILLS_Discover="continuous-discovery ghost-skill using-skills"\nSTAGE_SKILLS_Plan="design plan using-skills"\nSTAGE_SKILLS_Build="build tdd debugging worktrees evals using-skills"\nSTAGE_SKILLS_Review="review verification demonstrate using-skills"\nSTAGE_SKILLS_Release="verification demonstrate operating using-skills"\nSTAGE_SKILLS_Done="verification demonstrate using-skills"\nSTAGE_SKILLS_Operate="operating debugging using-skills"\n' \
    > "$LS_FXDIR/roster-ghost-skill.conf"
  # (c) a stage declared in KIT_STAGES with no skill set.
  printf 'KIT_STAGES="Discover Plan Build Review Release Done Operate Ghost"\nSTAGE_SKILLS_Discover="continuous-discovery using-skills"\nSTAGE_SKILLS_Plan="design plan using-skills"\nSTAGE_SKILLS_Build="build tdd debugging worktrees evals using-skills"\nSTAGE_SKILLS_Review="review verification demonstrate using-skills"\nSTAGE_SKILLS_Release="verification demonstrate operating using-skills"\nSTAGE_SKILLS_Done="verification demonstrate using-skills"\nSTAGE_SKILLS_Operate="operating debugging using-skills"\n' \
    > "$LS_FXDIR/roster-unmapped-stage.conf"
  # Fail-closed: an empty KIT_STAGES. (The missing-map case needs no fixture — the legs point
  # ROSTER_CONF at a path that does not exist.)
  printf 'KIT_STAGES=""\n' > "$LS_FXDIR/roster-empty-stages.conf"

  # O — row present on the hermetic board, for the row-resolution positive.
  echo o > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'real board row\n\nKit-Row: FIXTURE-ROW-ALPHA\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_REALROW=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # O1b — a GATED head with Kit-Stage but NO Kit-Skill (leg c). The refusal an adopter meets when
  # they learn the entry contract; it is the surface that must hand them the map.
  echo o1b > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'no skill trailer\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: control-plane\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_NOSKILLKEY=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # A roster whose STAGE NAME carries a C0 byte. The conf is repo text and a PR can change it, so
  # the map print is an injection surface exactly as the skill name at :296-305 was (leg k).
  printf 'KIT_STAGES="Build Rev%siew"\nSTAGE_SKILLS_Build="build tdd"\n' "$(printf '\001')" \
    > "$LS_FXDIR/roster-ctrl-stage.conf"

  # O2 — SUBSTRING: `Kit-Row: A` (leg d). The design wrote this leg as `Kit-Row: a`; the value is
  # UPPER-CASE here for a reason worth stating, because it is the difference between this leg
  # testing what it claims and testing something else. Since security S-M2, a lower-case id is
  # refused by `row_id_ok` at the front door — so `a` would red on the GRAMMAR and never reach the
  # lookup, leaving the names-no-row path uncovered. `A` is a well-formed id that occurs in the
  # fixture board's TEXT (inside `FIXTURE-ROW-ALPHA`) and names no row, which is exactly the
  # substring the whole-file `grep -Fq` this slice replaces used to accept. The lower-case case has
  # its own leg (board-lower / LS_FX_LOWERROW).
  echo o2 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'single-letter row\n\nKit-Row: A\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SUBSTR=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # O3 — NON-ITEM CELL: the token appears only in another row's Intent/Links cell (leg e). Also
  # accepted by the old whole-file grep; it is not an Item-cell id, so it names no row.
  echo o3 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'links-cell row\n\nKit-Row: LINKS-ONLY-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_LINKSONLY=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # O4 — a LOWER-CASE Kit-Row (security S-M2). The board-lower fixture carries the matching row, so
  # nothing but the grammar check can refuse this pair.
  echo o4 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'lower-case row id\n\nKit-Row: kw6-a2\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_LOWERROW=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # P — FORM: a Kit-Skill with no `skills/` prefix. Needed to exercise the form rule in isolation;
  # review measured that gutting it left the suite green because the single-component rule caught
  # the traversal fixture instead.
  echo p > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'skill without the skills prefix\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_BADFORM=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # Q — CONTROL-PLANE POSITIVE: declared == derived == control-plane. The class axis had two
  # negatives and only an `ordinary` positive; this is the class where a false-RED costs most.
  echo q > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'control-plane positive\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: control-plane\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_CPOK=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # R — CONTROL CHARACTER in a PR-controlled value, to fixture ls_safe. The trailer is the usable
  # seam: the skills-directory path has none (map_completeness scans the real tree), so this is the
  # one site where the sanitiser can be held hermetically. check_skill is called DIRECTLY by the leg,
  # which is what lets an ESC through — check_declaration's charset would refuse it first.
  echo r > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ctrl char in Kit-Skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: bad\033[2Kevil\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_CTRL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # --- B9 Kit-Scope fixtures --------------------------------------------------------------------
  # The scope leg grades a DIFF, so these need a base and branches off it. The base is PINNED into
  # LS_SCOPE_BASEREF by the legs (never auto-resolved) so nothing here depends on the fixture repo's
  # ambient default-branch name.
  LS_FX_SCOPEBASE=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # S1 — COVERED: the only changed path is under the single declared prefix.
  mkdir -p "$LS_FXDIR/docs"
  echo s1 > "$LS_FXDIR/docs/note.md"; git -C "$LS_FXDIR" add docs/note.md
  printf 'scope covered\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\nKit-Scope: docs/\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_IN=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # S2 — ESCAPING: branched off the base so its diff is exactly its own two paths, one of which is
  # outside the declared prefix. ⚠️ NON-VACUITY: it also changes a path that IS covered, so a leg
  # that merely notices "something changed" cannot pass for the wrong reason.
  git -C "$LS_FXDIR" checkout -q -b scope-out "$LS_FX_SCOPEBASE"
  mkdir -p "$LS_FXDIR/docs" "$LS_FXDIR/conformance"
  echo s2 > "$LS_FXDIR/docs/note.md"
  echo s2 > "$LS_FXDIR/conformance/stray.sh"
  git -C "$LS_FXDIR" add docs/note.md conformance/stray.sh
  printf 'scope escaped\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\nKit-Scope: docs/\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_OUT=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # S3/S4/S5 — HOSTILE TOKENS, one face each. ⚠️ NON-VACUITY: every one of them ALSO declares a
  # prefix that covers nothing in the diff, so if the hostile check were removed the leg would fall
  # through to the escape branch and refuse for the WRONG reason — which is exactly what the
  # reason-assertions below (with their forbidden downstream string) measure.
  echo s3 > "$LS_FXDIR/conformance/stray.sh"; git -C "$LS_FXDIR" add conformance/stray.sh
  printf 'scope traversal token\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\nKit-Scope: docs/../etc\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_DOTDOT=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo s4 > "$LS_FXDIR/conformance/stray.sh"; git -C "$LS_FXDIR" add conformance/stray.sh
  printf 'scope glob token\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\nKit-Scope: docs/*\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_GLOB=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo s5 > "$LS_FXDIR/conformance/stray.sh"; git -C "$LS_FXDIR" add conformance/stray.sh
  printf 'scope absolute token\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\nKit-Scope: /etc\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_ABS=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # S6 — DUPLICATE Kit-Scope with OPPOSITE sets: `head -1` and `tail -1` reach opposite verdicts,
  # so "take the first" is not a safe reading here either. Must FAIL on the count, before matching.
  echo s6 > "$LS_FXDIR/conformance/stray.sh"; git -C "$LS_FXDIR" add conformance/stray.sh
  printf 'duplicate scope key\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\nKit-Scope: docs/\nKit-Scope: conformance/\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_DUP=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # P1/P2/P3 — CLASS-PROPORTIONAL fixtures (ENTRY-CONTRACT-CLASS-PROPORTIONAL, 2026-08-30).
  # Reduced trailer sets, which is exactly what every fixture above deliberately is NOT: each of
  # them carries all four, so none of them can tell a class-conditional required set from an
  # unconditional one. These three are the discriminant.
  #
  # P1 — ORDINARY, TWO TRAILERS ONLY. The head an ordinary slice now owes.
  echo p1 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ordinary two-trailer head\n\nbody\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ORD2=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # P2 — CONTROL-PLANE, THREE TRAILERS: Kit-Stage is the one missing. ⚠️ NON-VACUITY: it carries
  # Kit-Skill, so a leg that merely counted trailers, or that checked only the two universal keys,
  # would pass it. Only a class-conditional required set refuses it, and it must NAME Kit-Stage.
  echo p2 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'control-plane head missing a stage\n\nbody\n\nKit-Row: DEMO-ROW\nKit-Class: control-plane\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_CP3=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # P3 — ORDINARY + a VOLUNTEERED, BOGUS Kit-Skill. Present ⇒ validated: dropping a key from the
  # required set must not create a silent-typo hole where a wrong value is simply ignored.
  echo p3 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ordinary head volunteering a bogus skill\n\nbody\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Skill: skills/nope\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ORD_BADSKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # P4 — ORDINARY + a volunteered Kit-Stage OUTSIDE the map. Same hole, the stage face.
  echo p4 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ordinary head volunteering a bogus stage\n\nbody\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Stage: Yolo\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ORD_BADSTAGE=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # P5 — ORDINARY + a DUPLICATED optional key. The exactly-one rule must survive the demotion from
  # required to optional: two Kit-Skill lines with opposite values are the same head -1/tail -1
  # decoy the required keys already refuse, and dropping a key from the required set must not drop
  # its arity check with it (review M1).
  echo p5 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ordinary head with two skills\n\nbody\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Stage: Build\nKit-Skill: skills/tdd\nKit-Skill: skills/build\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ORD_DUPSKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # P6 — ORDINARY + an optional key whose value breaks the CHARSET. `;` is the shell-metacharacter
  # face: the value flows to a filesystem path and a map lookup, so the boundary refusal must apply
  # to a volunteered field exactly as it does to a required one (review M1).
  echo p6 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ordinary head with a metachar skill\n\nbody\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Stage: Build\nKit-Skill: skills/tdd;rm\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ORD_METASKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # P7 — ORDINARY + Kit-Skill but NO Kit-Stage. The pair is what carries meaning; refusing this with
  # "stage '' has no skill set in the map" blamed the roster for a missing trailer (security M-2).
  echo p7 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ordinary head with a skill and no stage\n\nbody\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ORD_SKILL_NOSTAGE=$(git -C "$LS_FXDIR" rev-parse HEAD)
  return 0
}

# K20 — `--help`. The stage->skill map lived ONLY in .kit/roster.conf, and the one moment an agent
# needs it is while writing the very trailers this gate grades — so the gate answers the question
# itself. The map is READ from conf_val, never restated: a hard-coded table here would be a second
# copy of the authority and would drift from it silently. Until now a bare invocation printed the
# "--head required" line and this arm did not exist.
print_help() {
  echo "usage: sh conformance/loop-state.sh --head <sha> [--changed <listing>] [--base-dir <dir> --live-contexts <file>]"
  echo "                                                 grade the Entry Declaration on that commit"
  echo "       sh conformance/loop-state.sh --selftest     run this check's own fixtures"
  echo "       sh conformance/loop-state.sh --help         this text, plus the roster's stage->skill map"
  echo
  echo "--changed <listing>        a caller-built changed-paths listing (base..head), for a BASE-ONLY"
  echo "                           checkout with no local diff (trusted-job use)."
  echo "--base-dir / --live-contexts (LOOP-STATE-TRACKER-STEP-ASIDE): must be given TOGETHER. When"
  echo "                           the base at <dir> delegates board governance to the trusted"
  echo "                           'tracker-board-gates' context and <file> proves it is LIVE-required"
  echo "                           on the base branch, the row leg stands aside with an N/A instead of"
  echo "                           NOT ENFORCED. Never fires inside the trusted job itself (no"
  echo "                           self-delegation) and never on the honest md path."
  echo
  echo "The Entry Declaration (CLAUDE.md S1, act 4) is a block of trailers that must be the LAST"
  echo "paragraph of the commit message, and contiguous — a blank line inside it truncates the block,"
  echo "and every field above the blank line is lost."
  echo "  Ordinary                  Kit-Row, Kit-Class"
  echo "  Sensitive / Control-plane Kit-Row, Kit-Class, Kit-Stage, Kit-Skill"
  echo "  also graded when present  Kit-Intent, Kit-Ceremony, Kit-Stop, Kit-Plan, Kit-Review"
  echo
  echo "Stage -> skill map (read live from $ROSTER_CONF — this is the authority, not a copy):"
  _lsh_stages=$(conf_val KIT_STAGES)
  if [ -z "$_lsh_stages" ]; then
    echo "  (none — KIT_STAGES is missing or empty in $ROSTER_CONF)"
    return 0
  fi
  for _lsh_s in $_lsh_stages; do
    printf '  %-10s %s\n' "$_lsh_s" "$(conf_val "STAGE_SKILLS_$_lsh_s")"
  done
  return 0
}

selftest() {
  st_fail=0
  # FIRST: check the checker. Eight legs below depend on ls_assert_reason, and it is structurally
  # invisible to the CI mutation sweep. If it is broken, every one of those legs is broken together
  # and silently — so it is exercised before anything relies on it.
  # ⚠️ THIS CALL IS WHERE THE REGRESS STOPS. Nothing asserts that this line still exists — deleting
  # it restores the un-covered state silently. One level of meta is the standard `verify.sh
  # --selftest` already sets, so stopping here is deliberate; do not "tidy" this call away.
  ls_assert_reason_selfcheck || st_fail=1
  _st_saved="$ROSTER_CONF"

  # POSITIVE LIVENESS ANCHOR — the real, shipped map must pass.
  # An always-FAIL implementation breaks THIS leg.
  ROSTER_CONF="$_st_saved"
  if ! map_completeness >/dev/null 2>&1; then
    echo "selftest FAIL: the shipped .kit/roster.conf map must satisfy map_completeness"
    st_fail=1
  fi

  # LOAD-BEARING NEGATIVE (a) — a skill on disk absent from the map must FAIL.
  # An always-PASS implementation breaks THIS leg.
  ROSTER_CONF="$DIR/conformance/fixtures/loop-state/roster-missing-skill.conf"
  if [ ! -f "$ROSTER_CONF" ]; then
    echo "selftest FAIL: fixture roster-missing-skill.conf is missing"; st_fail=1
  elif map_completeness >/dev/null 2>&1; then
    echo "selftest FAIL: a skill on disk absent from the map must FAIL, not pass"; st_fail=1
  fi

  ROSTER_CONF="$_st_saved"

  # --- T2: declaration read from ONE named commit -------------------------------------------
  _st_repo_saved="$LS_REPO"
  if ! ls_fx_build; then
    echo "selftest FAIL: could not build the fixture repo"; st_fail=1
  else
    LS_REPO="$LS_FXDIR"

    # POSITIVE — a conformant, contiguous declaration passes.
    check_declaration "$LS_FX_OK" >/dev/null 2>&1 \
      || { echo "selftest FAIL: a conformant declaration must PASS"; st_fail=1; }

    # BASELINE NEGATIVE — no Kit-* trailers at all. The simplest and most load-bearing negative.
    check_declaration "$LS_FX_NONE" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a commit with no declaration must FAIL"; st_fail=1; }

    # ANCESTOR NEGATIVE — makes head-only scope safe. If this passes, the gate is walking to a
    # parent and ANY ancestor's trailer satisfies it (the defect ceremony-binding closed).
    check_declaration "$LS_FX_CHILD" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a declaration on an ANCESTOR must not satisfy the head commit"; st_fail=1; }

    # KILL FIXTURE — all four fields present in the body but severed by the squash separator.
    # A grep implementation PASSES this. If this leg ever goes green, the gate is matching text
    # instead of parsing structure and the slice has failed.
    check_declaration "$LS_FX_SEVERED" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a SEVERED trailer block must FAIL (grep would pass it)"; st_fail=1; }

    # STAGE NEGATIVE — a stage outside the map must FAIL, never fall through.
    check_declaration "$LS_FX_BADSTAGE" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a Kit-Stage outside the map must FAIL"; st_fail=1; }

    # --- T3: exactly-one + charset ------------------------------------------------------------
    # SINGLE-KEY POSITIVE — pairs with the duplicate negative below. A wc -l implementation
    # reports 2 for this commit and would false-RED it; grep -c . reports 1.
    check_declaration "$LS_FX_SINGLE" >/dev/null 2>&1 \
      || { echo "selftest FAIL: a single-occurrence declaration must PASS (wc -l off-by-one?)"; st_fail=1; }

    # DUPLICATE NEGATIVE — two Kit-Class lines with opposite values must FAIL, never "take the
    # first". An off-by-one cannot satisfy both this and the single-key positive above.
    check_declaration "$LS_FX_DUP" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a duplicate Kit-Class must FAIL, never take-the-first"; st_fail=1; }

    # --- STAGE-ARTIFACT KEYS (LOOP-STAGE-ARTIFACT-GATE) --------------------------------------
    # POSITIVE — well-formed Kit-Plan + a consolidated two-record Kit-Review must PASS. An
    # over-strict implementation (one that refuses the comma set) breaks THIS leg.
    check_declaration "$LS_FX_ARTIFACT" ordinary >/dev/null 2>&1 \
      || { echo "selftest FAIL: well-formed Kit-Plan/Kit-Review (incl. a comma-separated set) must PASS"; st_fail=1; }

    # NEGATIVE — a Kit-Review outside `docs/reviews/` must FAIL. An always-PASS implementation, and
    # an absent-is-N/A one that forgot PRESENT-implies-VALIDATED, both break THIS leg.
    check_declaration "$LS_FX_ARTIFACT_PFX" ordinary >/dev/null 2>&1 \
      && { echo "selftest FAIL: a Kit-Review outside 'docs/reviews/' must FAIL, not read as 'a record was named'"; st_fail=1; }

    # NEGATIVE — an EMPTY element inside the comma set must FAIL. A split that silently drops empties
    # (the IFS word-split this file used before semgrep refused it) passes THIS leg only by accident.
    check_declaration "$LS_FX_ARTIFACT_EMPTY" ordinary >/dev/null 2>&1 \
      && { echo "selftest FAIL: an empty element in a comma-separated Kit-Review set must FAIL, not be skipped"; st_fail=1; }

    # NEGATIVE — a traversing Kit-Plan must FAIL at the boundary.
    check_declaration "$LS_FX_ARTIFACT_TRAV" ordinary >/dev/null 2>&1 \
      && { echo "selftest FAIL: a traversing Kit-Plan value must FAIL"; st_fail=1; }

    # CHARSET NEGATIVE — a regex-metacharacter Kit-Row must be refused at the boundary before it
    # ever reaches a board grep.
    check_declaration "$LS_FX_META" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a metacharacter Kit-Row must be refused at the boundary"; st_fail=1; }

    # A classifier that answers with a token derive_class does not recognise. Defined here, inside
    # selftest(), so no production path can reach it.
    # shellcheck disable=SC2329 # invoked indirectly through $LS_CLASS_FN
    _st_garbage_class() { printf 'garbage\n'; return 1; }

    # --- T3b: THE REQUIRED SET IS CLASS-PROPORTIONAL ------------------------------------------
    # ENTRY-CONTRACT-CLASS-PROPORTIONAL (design 2026-08-30 section 4.1a). Ordinary pays Kit-Row +
    # Kit-Class; sensitive / control-plane pay all four. Every fixture above carries all four, so
    # these four legs are the only ones that can tell the two required sets apart.

    # ORDINARY + TWO — the head an ordinary slice now owes, and nothing more. Under the old
    # unconditional set this REDS on the missing Kit-Stage; that is the point of the slice.
    check_declaration "$LS_FX_ORD2" ordinary >/dev/null 2>&1 \
      || { echo "selftest FAIL: an ordinary head carrying Kit-Row + Kit-Class must PASS"; st_fail=1; }

    # CONTROL-PLANE MINUS Kit-Stage — must FAIL, and must NAME the key it is missing. The
    # forbidden string pins that it is not refused for some other reason (it carries Kit-Skill).
    ls_assert_reason "class-proportional/cp-missing-stage" \
      "carries no parseable 'Kit-Stage' trailer" "Kit-Skill" \
      check_declaration "$LS_FX_CP3" control-plane || st_fail=1

    # SENSITIVE pays the same four as control-plane — only `ordinary` is reduced.
    check_declaration "$LS_FX_ORD2" sensitive >/dev/null 2>&1 \
      && { echo "selftest FAIL: a sensitive head must still owe all four"; st_fail=1; }

    # PRESENT ⇒ VALIDATED (stage face) — an ordinary head that VOLUNTEERS a stage outside the map
    # must still FAIL. Dropping a key from the required set must not make a wrong value inert.
    check_declaration "$LS_FX_ORD_BADSTAGE" ordinary >/dev/null 2>&1 \
      && { echo "selftest FAIL: a volunteered Kit-Stage outside the map must FAIL even for ordinary"; st_fail=1; }

    # PRESENT ⇒ VALIDATED (skill face) — the run_gate-level predicate, tested directly.
    check_skill_if_present "$LS_FX_ORD2" >/dev/null 2>&1 \
      || { echo "selftest FAIL: an absent Kit-Skill must be N/A for an ordinary head"; st_fail=1; }
    check_skill_if_present "$LS_FX_ORD_BADSKILL" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a volunteered but bogus Kit-Skill must be validated, not ignored"; st_fail=1; }

    # ── THE PRESENT⇒VALIDATED LOOP ITSELF (review M1). The two legs above are graded by check_skill,
    # NOT by the optional-key loop in check_declaration — so with that loop deleted they both still
    # pass and the arity/charset half of "present ⇒ validated" was untested. These two are the
    # loop's own oracle: each names an OPTIONAL key (Kit-Skill, absent from the ordinary required
    # set) and breaks a rule only that loop enforces.
    ls_assert_reason "optional/arity" \
      "carries 2 occurrences of 'Kit-Skill' — exactly one is required" "-" \
      check_declaration "$LS_FX_ORD_DUPSKILL" ordinary || st_fail=1
    ls_assert_reason "optional/charset" \
      "'Kit-Skill' must be non-empty and may contain only" "-" \
      check_declaration "$LS_FX_ORD_METASKILL" ordinary || st_fail=1

    # A VOLUNTEERED SKILL WITH NO STAGE names ITS OWN defect, not the roster's (security M-2). The
    # forbidden string is the old, misleading refusal: if it reappears the message has regressed.
    ls_assert_reason "optional/skill-without-stage" \
      "Kit-Skill was volunteered without Kit-Stage" "has no skill set in the map" \
      check_skill_if_present "$LS_FX_ORD_SKILL_NOSTAGE" || st_fail=1

    # CLASSIFIER DEGRADATION ESCALATES, NEVER RELAXES. A classifier that returns a non-token must
    # fail-safe to control-plane and demand all four — the arm that keeps a broken classifier from
    # becoming a free pass to the reduced set.
    _st_clsfn_saved="$LS_CLASS_FN"
    LS_CLASS_FN=_st_garbage_class
    _st_cls="$(ls_class_for_required 2>/dev/null)"
    [ "$_st_cls" = FAIL-SAFED ] \
      || { echo "selftest FAIL: a degraded classifier must yield FAIL-SAFED, got '$_st_cls'"; st_fail=1; }
    ls_class_for_required 2>&1 >/dev/null | grep -Fq 'fail-safe: control-plane, all four required' \
      || { echo "selftest FAIL: the degraded arm must SAY it fail-safed to control-plane"; st_fail=1; }
    [ "$(ls_required_keys "$_st_cls")" = "$LS_REQUIRED_KEYS" ] \
      || { echo "selftest FAIL: a degraded classifier must require all four keys"; st_fail=1; }
    check_declaration "$LS_FX_ORD2" "$_st_cls" >/dev/null 2>&1 \
      && { echo "selftest FAIL: under a degraded classifier a two-trailer head must FAIL"; st_fail=1; }
    LS_CLASS_FN="$_st_clsfn_saved"

    # …and the healthy path still routes through the same seam.
    [ "$(ls_required_keys ordinary)" = "Kit-Row Kit-Class" ] \
      || { echo "selftest FAIL: ordinary must require exactly Kit-Row + Kit-Class"; st_fail=1; }
    [ "$(ls_required_keys control-plane)" = "$LS_REQUIRED_KEYS" ] \
      || { echo "selftest FAIL: control-plane must require all four"; st_fail=1; }

    # --- T4: Kit-Class must EQUAL the derived class -------------------------------------------
    _st_fxd="$DIR/conformance/fixtures/loop-state"

    # POSITIVE — declared `ordinary`, derived `ordinary`.
    check_class "$LS_FX_OK" "$_st_fxd/changed-ordinary.txt" >/dev/null 2>&1 \
      || { echo "selftest FAIL: declared class equal to derived class must PASS"; st_fail=1; }

    # THE KEY NEGATIVE — declared `ordinary`, derived `control-plane`. An agent under-declaring
    # its way past the ceremony a control-plane change owes is the forgery this leg closes.
    check_class "$LS_FX_OK" "$_st_fxd/changed-controlplane.txt" >/dev/null 2>&1 \
      && { echo "selftest FAIL: declared ordinary vs derived control-plane must FAIL"; st_fail=1; }

    # OVER-DECLARATION NEGATIVE — declared `sensitive`, derived `ordinary`. Also a FAIL: the
    # contract is equality, not ">=". A declaration that does not match the diff is not a
    # conservative choice, it is an inaccurate one.
    check_class "$LS_FX_SINGLE" "$_st_fxd/changed-ordinary.txt" >/dev/null 2>&1 \
      && { echo "selftest FAIL: over-declared class must FAIL (contract is equality)"; st_fail=1; }

    # ── THE ADAPTER-UNION INHERITANCE LEG (GUARD-PATH-ENUMERATION-INCOMPLETE S2).
    # This gate derives through promotion-readiness.sh, and that classifier used to see only the
    # guard-core half of the merge-time control-plane set. So a PR touching ONLY an adapter-declared
    # path — `GEMINI.md` here — derived `ordinary`, this gate PASSED the `Kit-Class: ordinary`
    # trailer, and the required ratification gate (which unions the same manifests) then blocked the
    # merge: a trailer that was gate-approved WRONG. S2 made the classifier union-aware, so this gate
    # inherits the cure with no edit of its own — and THAT is exactly why the leg is asserted rather
    # than reasoned. "It flips by construction once the classifier does" is a derivation, and the
    # sibling row (GUARD-PATH-ENUMERATION-INCOMPLETE S1) exists because a guard/class pair that was
    # supposed to agree by construction did not, for ten days.
    _st_union_cls="$(derive_class "$_st_fxd/changed-union.txt")" || _st_union_cls="<derive failure>"
    if [ "$_st_union_cls" = control-plane ]; then
      echo "selftest PASS: an adapter-declared-only change-set derives control-plane here (union inherited)"
    else
      echo "selftest FAIL: an adapter-declared-only change-set derived '$_st_union_cls', want control-plane — this gate and the required ratification gate disagree again, and a Kit-Class: ordinary trailer would pass here and be blocked there"; st_fail=1
    fi
    # …and end to end through check_class, which is the surface run_gate actually calls: the fixture
    # commit declares `ordinary`, so an adapter-declared-only change-set must now be REFUSED.
    check_class "$LS_FX_OK" "$_st_fxd/changed-union.txt" >/dev/null 2>&1 \
      && { echo "selftest FAIL: declared ordinary vs an adapter-declared-only change-set must FAIL"; st_fail=1; }

    # --- T5: Kit-Skill resolution, stage-appropriateness, path safety -------------------------
    # Legs resolved against the REAL kit tree.
    check_skill "$LS_FX_OK" >/dev/null 2>&1 \
      || { echo "selftest FAIL: a real, stage-appropriate skill must PASS"; st_fail=1; }
    check_skill "$LS_FX_WRONGSKILL" >/dev/null 2>&1 \
      && { echo "selftest FAIL: skills/tdd must not govern Kit-Stage: Plan"; st_fail=1; }
    check_skill "$LS_FX_NOSKILL" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a nonexistent skill must FAIL"; st_fail=1; }
    check_skill "$LS_FX_TRAVERSAL" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a traversal Kit-Skill must FAIL"; st_fail=1; }

    # Path-safety legs resolved against the FIXTURE repo, where the hostile trees live.
    _st_skillrepo_saved="$LS_SKILLREPO"
    LS_SKILLREPO="$LS_FXDIR"
    check_skill "$LS_FX_GOODSKILL" >/dev/null 2>&1 \
      || { echo "selftest FAIL: a tracked regular skill in the fixture repo must PASS"; st_fail=1; }
    check_skill "$LS_FX_SYMSKILL" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a tracked SYMLINK skill (mode 120000) must FAIL"; st_fail=1; }
    check_skill "$LS_FX_UNTRACKED" >/dev/null 2>&1 \
      && { echo "selftest FAIL: an UNTRACKED skill must FAIL"; st_fail=1; }
    LS_SKILLREPO="$_st_skillrepo_saved"

    # --- T6: Kit-Row resolution and the N/A routes --------------------------------------------
    # HERMETIC: every row leg runs against the fixture board, never the kit's live BACKLOG.md.
    _st_board_saved="$LS_BOARDROOT"
    LS_BOARDROOT="$LS_FXDIR/board"

    # POSITIVE (leg a) — an id leading exactly one Item cell RESOLVES, and the state word is
    # `resolved`. The word is asserted, not just the rc: `matched` was the honest label for a
    # substring test and the run line must stop saying it.
    check_row "$LS_FX_REALROW" >/dev/null 2>&1 \
      || { echo "selftest FAIL: a Kit-Row leading an Item cell must RESOLVE"; st_fail=1; }
    [ "$LS_ROW_STATE" = "resolved" ] \
      || { echo "selftest FAIL: the row leg must report 'resolved', got '$LS_ROW_STATE'"; st_fail=1; }

    # NEGATIVE — a row that appears nowhere on the board must FAIL.
    check_row "$LS_FX_OK" >/dev/null 2>&1 \
      && { echo "selftest FAIL: Kit-Row 'DEMO-ROW' appears nowhere on the board and must FAIL"; st_fail=1; }

    # (d) SUBSTRING — `Kit-Row: a` occurs in the board's TEXT and names no row. The mutant is the
    # code this replaces (`grep -Fq -- "$_ls_row" "$_ls_board"`), which accepts it.
    _st_ro=$(check_row "$LS_FX_SUBSTR" 2>&1) && _st_rr=0 || _st_rr=$?
    [ "$_st_rr" -ne 0 ] \
      || { echo "selftest FAIL: Kit-Row 'A' is a substring of the board, not a row — must be REFUSED"; st_fail=1; }
    case "$_st_ro" in
      *"names no row"*) : ;;
      *) echo "selftest FAIL: the substring refusal must say 'names no row', got <$_st_ro>"; st_fail=1 ;;
    esac

    # (e) NON-ITEM CELL — the token occurs only in another row's Intent/Links cell. Same mutant.
    check_row "$LS_FX_LINKSONLY" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a token present only in a non-Item cell must be REFUSED"; st_fail=1; }

    # (f) TITLE-ONLY ROW — the row is on the board in prose but carries no backticked id. The
    # refusal is the adopter's ONLY remedy surface, so it must name act 3 and the grammar.
    LS_BOARDROOT="$LS_FXDIR/board-titleonly"
    _st_ro=$(check_row "$LS_FX_REALROW" 2>&1) && _st_rr=0 || _st_rr=$?
    [ "$_st_rr" -ne 0 ] \
      || { echo "selftest FAIL: a title-only row carries no id and must be REFUSED"; st_fail=1; }
    case "$_st_ro" in
      *"act 3"*) : ;;
      *) echo "selftest FAIL: the names-no-row refusal must cite CLAUDE.md act 3, got <$_st_ro>"; st_fail=1 ;;
    esac
    case "$_st_ro" in
      *'[A-Z0-9][A-Z0-9-]*'*) : ;;
      *) echo "selftest FAIL: the names-no-row refusal must state the id grammar, got <$_st_ro>"; st_fail=1 ;;
    esac

    # (S-M2) THE GRAMMAR IS CHECKED, NOT MERELY QUOTED. A lower-case id on BOTH sides — the board
    # row and the trailer — used to RESOLVE, while the names-no-row refusal three lines away told
    # the reader the grammar was `[A-Z0-9][A-Z0-9-]*`. `board-claim.sh` refuses such an id at its
    # front door (it becomes a ref name), so the pair could never have been claimed either.
    LS_BOARDROOT="$LS_FXDIR/board-lower"
    _st_ro=$(check_row "$LS_FX_LOWERROW" 2>&1) && _st_rr=0 || _st_rr=$?
    [ "$_st_rr" -ne 0 ] \
      || { echo "selftest FAIL: a lower-case Kit-Row must be REFUSED even when the board agrees with it"; st_fail=1; }
    case "$_st_ro" in
      *'[A-Z0-9][A-Z0-9-]*'*) : ;;
      *) echo "selftest FAIL: the grammar refusal must state the charset, got <$_st_ro>"; st_fail=1 ;;
    esac
    case "$_st_ro" in
      *"is not a well-formed row id"*) : ;;
      *) echo "selftest FAIL: the grammar refusal must say the id is ill-formed (not 'names no row'), got <$_st_ro>"; st_fail=1 ;;
    esac
    LS_BOARDROOT="$LS_FXDIR/board"

    # (g) AMBIGUOUS — one id on two rows. THE load-bearing negative for row_count: swap it for
    # row_exists and this board is indistinguishable from the good one.
    LS_BOARDROOT="$LS_FXDIR/board-dup"
    _st_ro=$(check_row "$LS_FX_REALROW" 2>&1) && _st_rr=0 || _st_rr=$?
    [ "$_st_rr" -ne 0 ] \
      || { echo "selftest FAIL: an id carried by TWO rows must be REFUSED, never resolved"; st_fail=1; }
    case "$_st_ro" in
      *"AMBIGUOUS"*"2 rows"*) : ;;
      *) echo "selftest FAIL: the duplicate refusal must say AMBIGUOUS and count the rows, got <$_st_ro>"; st_fail=1 ;;
    esac
    LS_BOARDROOT="$LS_FXDIR/board"

    # N/A ROUTE 1 — no board at all: exactly a fresh adopter export (BACKLOG.md is export-ignore'd).
    # Must be N/A, never RED. This is the green-on-clone failure class.
    LS_BOARDROOT="$LS_FXDIR"
    check_row "$LS_FX_OK" >/dev/null 2>&1 \
      || { echo "selftest FAIL: no board present must be N/A, not a RED first PR"; st_fail=1; }

    # NOT ENFORCED (was N/A ROUTE 2) — a non-BACKLOG.md backend. This leg used to assert that a
    # github backend N/A'd the row leg and returned 0: governance switched off, silently, on a
    # tree the PR itself could declare. Now it REFUSES with the shared sentence
    # (NON-MD-BACKEND-NEVER-SILENT, D-240903-1 §3); observe-vs-enforce is the job's dial, not a
    # third knob here.
    LS_BOARDROOT="$LS_FXDIR/backend-github"
    _st_ro=$(check_row "$LS_FX_OK" 2>&1) && _st_rr=0 || _st_rr=$?
    [ "$_st_rr" -ne 0 ] \
      || { echo "selftest FAIL: a hosted-tracker backend must be NOT ENFORCED (refused), never a silent N/A"; st_fail=1; }
    case "$_st_ro" in
      *"NOT ENFORCED: backend 'github'"*) : ;;
      *) echo "selftest FAIL: the non-md refusal must carry the NOT ENFORCED sentence, got <$_st_ro>"; st_fail=1 ;;
    esac
    # LS_ROW_STATE is what the run's summary line prints, so it must ALSO stop saying N/A. Assert
    # it from a call that is NOT inside a command substitution — a subshell's assignment never
    # reaches this shell, and reading it after the capture above would grade the PREVIOUS leg.
    check_row "$LS_FX_OK" >/dev/null 2>&1 || true
    case "$LS_ROW_STATE" in
      "NOT ENFORCED"*) : ;;
      *) echo "selftest FAIL: LS_ROW_STATE must record NOT ENFORCED, got '$LS_ROW_STATE'"; st_fail=1 ;;
    esac

    # STREAM, not just content (security S-L3). hooks/pre-push captures this predicate's STDERR
    # ONLY (`2>&1 >/dev/null`), and it keys its remedy on the sentence. With the unwaived verdict on
    # STDOUT the hook saw nothing, fell through to the generic branch, and told an author whose
    # trailers were perfect to "fix the trailer block ... git commit --amend". Every other leg here
    # captures 2>&1 and is structurally blind to which stream this is, so it needs its own leg.
    _st_ro=$(check_row "$LS_FX_OK" 2>&1 >/dev/null) || true
    case "$_st_ro" in
      *"NOT ENFORCED: backend 'github'"*) : ;;
      *) echo "selftest FAIL: an UNWAIVED NOT ENFORCED verdict must reach STDERR (hooks/pre-push reads only that), got <$_st_ro>"; st_fail=1 ;;
    esac

    # …and a RATIFIED, filled, unexpired board-governance waiver renders it green WITH the notice.
    LS_BOARDROOT="$LS_FXDIR/backend-github-waived"
    _st_ro=$(check_row "$LS_FX_OK" 2>&1) && _st_rr=0 || _st_rr=$?
    [ "$_st_rr" -eq 0 ] \
      || { echo "selftest FAIL: a ratified board-governance waiver must render the row leg rc 0"; st_fail=1; }
    case "$_st_ro" in
      *"NOT ENFORCED: backend 'github' — waived until $LS_FX_WV_EXP by @jdoe"*) : ;;
      *) echo "selftest FAIL: the waived verdict must still print NOT ENFORCED with owner+expiry, got <$_st_ro>"; st_fail=1 ;;
    esac

    # …and the UNFILLED incept stamp buys nothing.
    LS_BOARDROOT="$LS_FXDIR/backend-github-stamp"
    check_row "$LS_FX_OK" >/dev/null 2>&1 \
      && { echo "selftest FAIL: an unfilled [placeholder] waiver row must NOT render the gate green"; st_fail=1; }

    # N/A ROUTE 3 — a pristine-template board (§11.3, plan T6.2). Also previously unfixtured.
    LS_BOARDROOT="$LS_FXDIR/board-pristine"
    check_row "$LS_FX_OK" >/dev/null 2>&1 \
      || { echo "selftest FAIL: a pristine-template board must N/A the row leg"; st_fail=1; }

    # FAIL-CLOSED — an unrecognised backend must REFUSE, never N/A. backlog-lib closed this
    # dark-gate class deliberately; inheriting the signal is only real if it is held here.
    LS_BOARDROOT="$LS_FXDIR/backend-bogus"
    check_row "$LS_FX_OK" >/dev/null 2>&1 \
      && { echo "selftest FAIL: an unrecognised backend must FAIL-CLOSED, not N/A"; st_fail=1; }

    # --- LOOP-STATE-TRACKER-STEP-ASIDE T1 — the `delegate/*` legs (design §3, plan T1 step 1) ------
    # Every leg below drives check_row DIRECTLY (in-process function calls, not a subprocess) —
    # LS_BASE_DIR/LS_LIVE_CONTEXTS are globals the parser sets (see the parser legs further below
    # for the subprocess-level proof that the flags actually reach them).
    LS_BOARDROOT="$LS_FXDIR/backend-github"

    # (a) delegated: LS_BASE_DIR/LS_LIVE_CONTEXTS point at a delegation-eligible base -> rc 0, the
    # delegated N/A, and LS_ROW_STATE records it (AC1).
    LS_BASE_DIR="$LS_FXDIR/t1-base"; LS_LIVE_CONTEXTS="$LS_FXDIR/t1-live.txt"
    _st_dg_out=$(check_row "$LS_FX_OK" 2>&1) && _st_dg_rc=0 || _st_dg_rc=$?
    [ "$_st_dg_rc" -eq 0 ] \
      || { echo "selftest FAIL: delegate/delegated: wanted rc0, got rc=$_st_dg_rc out='$_st_dg_out'"; st_fail=1; }
    case "$_st_dg_out" in
      *"N/A: board governance is delegated to the required context 'tracker-board-gates' (live on the base branch)"*) : ;;
      *) echo "selftest FAIL: delegate/delegated: missing the delegated N/A sentence, got <$_st_dg_out>"; st_fail=1 ;;
    esac
    # A command-substitution call runs in a SUBSHELL (POSIX): LS_ROW_STATE set inside it never
    # reaches this shell. Re-run directly (output discarded) to read the real assignment, exactly
    # as the pre-existing hosted-backend legs above already do.
    check_row "$LS_FX_OK" >/dev/null 2>&1 || true
    case "$LS_ROW_STATE" in
      "N/A (delegated to tracker-board-gates — live on the base branch)") : ;;
      *) echo "selftest FAIL: delegate/delegated: LS_ROW_STATE wrong, got '$LS_ROW_STATE'"; st_fail=1 ;;
    esac
    echo "selftest PASS: delegate/delegated: base tracker+conf+live-listed -> rc 0, the delegated N/A"

    # (b) other-legs-bind: the step-aside excuses ONLY the row leg — a control-plane head missing
    # Kit-Stage still reds the WHOLE gate (AC3), driven through run_gate so the class/stage/skill
    # legs actually run.
    # The class must come from a FIXTURE listing, never from the ambient checkout diff: without
    # $2, ls_class_for_required reads the live git diff against trunk, so this leg's verdict would
    # depend on whatever branch it happens to run on (control-plane on #711's own branch, ordinary
    # on any docs-only PR) rather than on the fixture head under test.
    echo "conformance/loop-state.sh" > "$LS_FXDIR/t1-cp-listing.txt"
    _st_oth_out=$(run_gate "$LS_FX_CP3" "$LS_FXDIR/t1-cp-listing.txt" 2>&1) && _st_oth_rc=0 || _st_oth_rc=$?
    [ "$_st_oth_rc" -eq 1 ] \
      || { echo "selftest FAIL: delegate/other-legs-bind: wanted rc 1 (missing Kit-Stage), got rc=$_st_oth_rc; out='$_st_oth_out'"; st_fail=1; }
    case "$_st_oth_out" in
      *"carries no parseable 'Kit-Stage' trailer"*) : ;;
      *) echo "selftest FAIL: delegate/other-legs-bind: refusal was not the STAGE sentence (would also pass for a row refusal), got <$_st_oth_out>"; st_fail=1 ;;
    esac
    case "$_st_oth_out" in
      *"N/A: board governance is delegated to the required context 'tracker-board-gates' (live on the base branch)"*)
        echo "selftest PASS: delegate/other-legs-bind: control-plane head missing Kit-Stage -> rc 1, the STAGE refusal sentence AND the delegated N/A — the step-aside excused the row leg while the stage leg still refused" ;;
      *)
        echo "selftest FAIL: delegate/other-legs-bind: missing the delegated N/A sentence (step-aside did not fire), got <$_st_oth_out>"; st_fail=1 ;;
    esac

    # (c) not-live: the live-contexts file exists but lacks the exact line -> rc 1, NOT ENFORCED.
    LS_LIVE_CONTEXTS="$LS_FXDIR/t1-live-missing.txt"
    _st_nl_out=$(check_row "$LS_FX_OK" 2>&1) && _st_nl_rc=0 || _st_nl_rc=$?
    [ "$_st_nl_rc" -eq 1 ] \
      || { echo "selftest FAIL: delegate/not-live: wanted rc 1, got rc=$_st_nl_rc"; st_fail=1; }
    case "$_st_nl_out" in
      *"NOT ENFORCED: backend 'github'"*) : ;;
      *) echo "selftest FAIL: delegate/not-live: wrong sentence, got <$_st_nl_out>"; st_fail=1 ;;
    esac
    case "$_st_nl_out" in
      *"delegated to the required context"*) echo "selftest FAIL: delegate/not-live: wrongly delegated (N/A present), got <$_st_nl_out>"; st_fail=1 ;;
      *) echo "selftest PASS: delegate/not-live: tracker-board-gates absent from the live-contexts file -> rc 1, the NOT ENFORCED sentence, no delegated N/A" ;;
    esac

    # (c2) not-live-cure (amendment A2): the refusal names the real cure — bind tracker-board-gates —
    # not the generic waiver-only clause.
    case "$_st_nl_out" in
      *"Cure: bind the trusted job as a required context: add tracker-board-gates to REQUIRED-CHECKS.md, then run sh scripts/branch-protection-apply.sh --apply — or move the board to BACKLOG.md, or ratify a board-governance waiver"*)
        echo "selftest PASS: delegate/not-live-cure: the refusal stderr names tracker-board-gates + REQUIRED-CHECKS.md (A2)" ;;
      *)
        echo "selftest FAIL: delegate/not-live-cure: missing the real cure, got <$_st_nl_out>"; st_fail=1 ;;
    esac

    # (d) no-live-file: --live-contexts names a file that does not exist -> rc 1, FAIL-CLOSED to
    # TODAY'S PATH (not_enforced_notice), never rc 2 (LS-T2-Q6: rc 2 is reserved for a USAGE
    # anomaly in the PARSER — a missing argument/unknown/dup flag — never for a step-aside input
    # that is merely absent or malformed once both flags WERE given; the A3 md-base wiring passes
    # exactly this shape, a --live-contexts path the conditional fetch step never created).
    LS_LIVE_CONTEXTS="$LS_FXDIR/t1-no-such-file.txt"
    _st_nlf_out=$(check_row "$LS_FX_OK" 2>&1) && _st_nlf_rc=0 || _st_nlf_rc=$?
    [ "$_st_nlf_rc" -eq 1 ] \
      || { echo "selftest FAIL: delegate/no-live-file: wanted rc 1, got rc=$_st_nlf_rc"; st_fail=1; }
    case "$_st_nlf_out" in
      *"NOT ENFORCED: backend 'github'"*) : ;;
      *) echo "selftest FAIL: delegate/no-live-file: wrong sentence, got <$_st_nlf_out>"; st_fail=1 ;;
    esac
    case "$_st_nlf_out" in
      *"delegated to the required context"*) echo "selftest FAIL: delegate/no-live-file: wrongly delegated (N/A present), got <$_st_nlf_out>"; st_fail=1 ;;
      *) echo "selftest PASS: delegate/no-live-file: --live-contexts names a file that does not exist -> rc 1, the NOT ENFORCED sentence, no delegated N/A (fail-closed to today's path, never rc 2)" ;;
    esac

    # (e) empty-live: a present, zero-byte --live-contexts file -> rc 1 (fail-closed), never rc 2.
    LS_LIVE_CONTEXTS="$LS_FXDIR/t1-live-empty.txt"
    _st_el_out=$(check_row "$LS_FX_OK" 2>&1) && _st_el_rc=0 || _st_el_rc=$?
    [ "$_st_el_rc" -eq 1 ] \
      || { echo "selftest FAIL: delegate/empty-live: wanted rc 1, got rc=$_st_el_rc"; st_fail=1; }
    case "$_st_el_out" in
      *"NOT ENFORCED: backend 'github'"*) : ;;
      *) echo "selftest FAIL: delegate/empty-live: wrong sentence, got <$_st_el_out>"; st_fail=1 ;;
    esac
    case "$_st_el_out" in
      *"delegated to the required context"*) echo "selftest FAIL: delegate/empty-live: wrongly delegated (N/A present), got <$_st_el_out>"; st_fail=1 ;;
      *) echo "selftest PASS: delegate/empty-live: an EMPTY --live-contexts file -> rc 1, the NOT ENFORCED sentence, no delegated N/A (never rc 2)" ;;
    esac

    # (f) live-suffix: an event-suffixed spelling must not satisfy the exact-line match -> rc 1.
    LS_LIVE_CONTEXTS="$LS_FXDIR/t1-live-suffix.txt"
    _st_lsx_out=$(check_row "$LS_FX_OK" 2>&1) && _st_ls_rc=0 || _st_ls_rc=$?
    [ "$_st_ls_rc" -eq 1 ] \
      || { echo "selftest FAIL: delegate/live-suffix: wanted rc 1, got rc=$_st_ls_rc"; st_fail=1; }
    case "$_st_lsx_out" in
      *"NOT ENFORCED: backend 'github'"*) : ;;
      *) echo "selftest FAIL: delegate/live-suffix: wrong sentence, got <$_st_lsx_out>"; st_fail=1 ;;
    esac
    case "$_st_lsx_out" in
      *"delegated to the required context"*) echo "selftest FAIL: delegate/live-suffix: wrongly delegated (N/A present), got <$_st_lsx_out>"; st_fail=1 ;;
      *) echo "selftest PASS: delegate/live-suffix: live-contexts holding only the event-suffixed spelling must not satisfy -> rc 1, the NOT ENFORCED sentence, no delegated N/A" ;;
    esac

    # (g) base-declares-md: a valid tracker conf sits under a base whose OWN backend is md ->
    # rc 1, never the delegated N/A (AC5).
    LS_LIVE_CONTEXTS="$LS_FXDIR/t1-live.txt"
    LS_BASE_DIR="$LS_FXDIR/t1-base-md"
    _st_bmd_out=$(check_row "$LS_FX_OK" 2>&1) && _st_bmd_rc=0 || _st_bmd_rc=$?
    [ "$_st_bmd_rc" -eq 1 ] \
      || { echo "selftest FAIL: delegate/base-declares-md: wanted rc 1, got rc=$_st_bmd_rc"; st_fail=1; }
    case "$_st_bmd_out" in
      *"NOT ENFORCED: backend 'github'"*) : ;;
      *) echo "selftest FAIL: delegate/base-declares-md: wrong sentence, got <$_st_bmd_out>"; st_fail=1 ;;
    esac
    case "$_st_bmd_out" in
      *"delegated to the required context"*) echo "selftest FAIL: delegate/base-declares-md: wrongly delegated"; st_fail=1 ;;
      *) echo "selftest PASS: delegate/base-declares-md: base on md, head declares jira + conf -> rc 1, the NOT ENFORCED sentence (AC5)" ;;
    esac

    # (h) bypass-head-conf: LS_BOARDROOT (the head's own dir) plants its own valid tracker.conf,
    # base stays md -> still rc 1 — the predicate never reads LS_BOARDROOT's .kit/ at all.
    LS_BOARDROOT="$LS_FXDIR/t1-head-conf"
    _st_bhc_out=$(check_row "$LS_FX_OK" 2>&1) && _st_bhc_rc=0 || _st_bhc_rc=$?
    [ "$_st_bhc_rc" -eq 1 ] \
      || { echo "selftest FAIL: delegate/bypass-head-conf: wanted rc 1, got rc=$_st_bhc_rc"; st_fail=1; }
    case "$_st_bhc_out" in
      *"NOT ENFORCED: backend 'jira'"*) : ;;
      *) echo "selftest FAIL: delegate/bypass-head-conf: wrong sentence, got <$_st_bhc_out>"; st_fail=1 ;;
    esac
    case "$_st_bhc_out" in
      *"delegated to the required context"*) echo "selftest FAIL: delegate/bypass-head-conf: wrongly delegated"; st_fail=1 ;;
      *) echo "selftest PASS: delegate/bypass-head-conf: head plants its own tracker.conf on an md base -> rc 1, the NOT ENFORCED sentence" ;;
    esac
    LS_BOARDROOT="$LS_FXDIR/backend-github"

    # (i) record-wins (AC4, RD-2): SEAM_RECORD set + a delegation-eligible base+live -> the record
    # arm runs and returns FIRST — the delegated N/A must never print, even though the predicate
    # would otherwise pass. Reuses the TBG-RECORD-GATES-BIND tracked fixture tree so the record's
    # pin matches a real tracker.conf digest.
    # A head whose Kit-Row matches the tracker record's project-id grammar (F-5: `AB-[1-9]...`,
    # the tracked fixture's project=AB) — LS_FX_OK's "DEMO-ROW" cannot be reused here.
    echo t1rw > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
    printf 'delegate/record-wins fixture\n\nbody\n\nKit-Row: AB-1\nKit-Class: ordinary\n' \
      | git -C "$LS_FXDIR" commit -q -F -
    LS_FX_ROWAB1=$(git -C "$LS_FXDIR" rev-parse HEAD)
    _st_rw_trk="$DIR/conformance/fixtures/tbg-record-gates-bind/tracker-jira"
    _st_rw_trkpin=$( { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } < "$_st_rw_trk/.kit/tracker.conf" 2>/dev/null | awk '{print $1}')
    _st_rw_today=$(date -u +%Y-%m-%d)
    _st_rw_rec="$LS_FXDIR/t1-record-wins.txt"
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_st_rw_trkpin"
      echo "head $LS_FX_ROWAB1"
      echo "requested AB-1"
      echo "read-day $_st_rw_today"
      echo "credential ok"
      echo "verdict bound"
      echo "row AB-1 state=in-progress"
    } > "$_st_rw_rec"
    LS_BOARDROOT="$_st_rw_trk"
    LS_BASE_DIR="$LS_FXDIR/t1-base"; LS_LIVE_CONTEXTS="$LS_FXDIR/t1-live.txt"
    SEAM_RECORD="$_st_rw_rec"
    _st_rw_out=$(check_row "$LS_FX_ROWAB1" 2>&1) && _st_rw_rc=0 || _st_rw_rc=$?
    [ "$_st_rw_rc" -eq 0 ] \
      || { echo "selftest FAIL: delegate/record-wins: wanted rc0 (record arm binds), got rc=$_st_rw_rc out='$_st_rw_out'"; st_fail=1; }
    case "$_st_rw_out" in
      *"delegated to the required context"*) echo "selftest FAIL: delegate/record-wins: the record arm never ran — printed the delegated N/A instead"; st_fail=1 ;;
      *) echo "selftest PASS: delegate/record-wins: SEAM_RECORD set + the flags -> the record arm, never the N/A" ;;
    esac
    check_row "$LS_FX_ROWAB1" >/dev/null 2>&1 || true
    SEAM_RECORD=""
    case "$LS_ROW_STATE" in
      "resolved (tracker record)") : ;;
      *) echo "selftest FAIL: delegate/record-wins: LS_ROW_STATE did not record the tracker arm, got '$LS_ROW_STATE'"; st_fail=1 ;;
    esac

    # (j) waiver-unchanged (AC2): no --base-dir/--live-contexts pair given at all -> today's waived
    # NOT ENFORCED path, byte-identical.
    LS_BOARDROOT="$LS_FXDIR/backend-github-waived"
    LS_BASE_DIR=""; LS_LIVE_CONTEXTS=""
    _st_wu_out=$(check_row "$LS_FX_OK" 2>&1) && _st_wu_rc=0 || _st_wu_rc=$?
    [ "$_st_wu_rc" -eq 0 ] \
      || { echo "selftest FAIL: delegate/waiver-unchanged: wanted rc0, got rc=$_st_wu_rc"; st_fail=1; }
    case "$_st_wu_out" in
      *"NOT ENFORCED: backend 'github' — waived until $LS_FX_WV_EXP by @jdoe"*) echo "selftest PASS: delegate/waiver-unchanged: no flags + a ratified waiver -> today's waived verdict" ;;
      *) echo "selftest FAIL: delegate/waiver-unchanged: wrong sentence, got <$_st_wu_out>"; st_fail=1 ;;
    esac

    # Reset before the legs that follow (they read hosted backends without expecting a step-aside).
    LS_BOARDROOT="$LS_FXDIR/backend-github"
    LS_BASE_DIR=""; LS_LIVE_CONTEXTS=""

    # UNIVERSALITY — on an N/A'd tree the class and skill legs still refuse.
    # ⚠️ HONEST LABEL: these two legs are TAUTOLOGICAL as written, and review measured why —
    # check_class and check_skill contain ZERO references to LS_BOARDROOT, so setting it cannot
    # change their behaviour and these duplicate coverage that already exists above. Kept as a
    # REGRESSION GUARD in case a future change couples the board root into either function; they do
    # NOT establish "only the row leg is N/A'd" on their own. Do not cite them as proof of it.
    LS_BOARDROOT="$LS_FXDIR"
    check_skill "$LS_FX_NOSKILL" >/dev/null 2>&1 \
      && { echo "selftest FAIL: Kit-Skill must still apply on an N/A'd board tree"; st_fail=1; }
    check_class "$LS_FX_OK" "$_st_fxd/changed-controlplane.txt" >/dev/null 2>&1 \
      && { echo "selftest FAIL: Kit-Class must still apply on an N/A'd board tree"; st_fail=1; }

    LS_BOARDROOT="$_st_board_saved"

    # --- T6b (TBG-RECORD-GATES-BIND): the tracker arm ------------------------------------------
    # The deliverable fixture tree (design §2 scope D) is the TRACKED half —
    # conformance/fixtures/tbg-record-gates-bind/tracker-jira/{.kit/tracker.conf,CLAUDE.md}, no
    # BACKLOG.md (the treeless proof). The SEAM_RECORD content is generated HERE, at test time —
    # a tracked record file would go stale (L-2 today/yesterday) or drift (M-1 pin digest) the
    # day either side of the tree changed without the other.
    _st_trk="$DIR/conformance/fixtures/tbg-record-gates-bind/tracker-jira"
    _st_trkconf="$_st_trk/.kit/tracker.conf"
    _st_trkpin=$( { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } < "$_st_trkconf" 2>/dev/null | awk '{print $1}')
    _st_trkhead="1111111111111111111111111111111111111111"
    _st_trktoday=$(date -u +%Y-%m-%d)
    _st_trkrec="$LS_FXDIR/tracker-record-good.txt"
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_st_trkpin"
      echo "head $_st_trkhead"
      echo "requested AB-1"
      echo "read-day $_st_trktoday"
      echo "credential ok"
      echo "verdict bound"
      echo "row AB-1 state=in-progress"
    } > "$_st_trkrec"

    # TREELESS POSITIVE — seam_row_count/state BIND on the good record, on a tree with NO
    # BACKLOG.md at all (§3, §6b R2 acceptance).
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_trkrec"; SEAM_HEAD="$_st_trkhead"
    _st_tc=$(seam_row_count AB-1 2>/dev/null) && _st_trc=0 || _st_trc=$?
    [ "$_st_trc" -eq 0 ] && [ "$_st_tc" = "1" ] \
      || { echo "selftest FAIL: tracker seam_row_count must BIND 1 on a good record (treeless — no BACKLOG.md in $_st_trk)"; st_fail=1; }
    _st_ts=$(seam_row_state AB-1 2>/dev/null) && _st_trc=0 || _st_trc=$?
    [ "$_st_trc" -eq 0 ] && [ "$_st_ts" = "in-progress" ] \
      || { echo "selftest FAIL: tracker seam_row_state must BIND 'in-progress' on a good record"; st_fail=1; }

    # H-3/M-5 rewritten for TBG-READER-FLAGS-LIST T7 (was: "both arms UNVERIFIED-by-construction,
    # unconditionally" — now live). pr-bound is the ONE flag answered from a bound record's mere
    # STRUCTURE (§3f: always 'n/a' on a tracker, never a lookup) even here, on the single-row/
    # no-list good record; seam_rows_in_state still refuses (rc2, H-3) on THIS record because
    # $_st_trkrec carries no `list` line at all for any state.
    _st_trpb=$(seam_row_flag AB-1 pr-bound 2>/dev/null) && _st_trpbrc=0 || _st_trpbrc=$?
    [ "$_st_trpbrc" -eq 0 ] && [ "$_st_trpb" = "n/a" ] \
      || { echo "selftest FAIL: tracker seam_row_flag pr-bound must bind 'n/a' (T7), got rc=$_st_trpbrc val=$_st_trpb"; st_fail=1; }
    seam_rows_in_state ready >/dev/null 2>&1 \
      && { echo "selftest FAIL: seam_rows_in_state must refuse (rc2, H-3) when the record carries no list line at all for that state"; st_fail=1; }

    # Each negative below is ONE mutation of the good record, asserted RED against the positive
    # (assert-differs, §8.2/§6). A shared helper keeps each leg to one line.
    _st_trk_neg() {   # $1 = record content, $2 = description
      _stn_f="$LS_FXDIR/tracker-record-neg.txt"
      printf '%s' "$1" > "$_stn_f"
      SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stn_f"; SEAM_HEAD="$_st_trkhead"
      if seam_row_count AB-1 >/dev/null 2>&1; then
        echo "selftest FAIL: tracker negative ($2) must REFUSE, not bind"; st_fail=1
      fi
    }
    _st_good_body=$(cat "$_st_trkrec")

    # H-2 — wrong head.
    _st_trk_neg "$(printf '%s\n' "$_st_good_body" | sed "s/^head .*/head 2222222222222222222222222222222222222222/")" "wrong head (H-2)"

    # M-1 — stale pin (record's pin no longer matches the base conf's actual bytes).
    _st_trk_neg "$(printf '%s\n' "$_st_good_body" | sed 's/^pin sha256:.*/pin sha256:0000000000000000000000000000000000000000000000000000000000000000/')" "stale pin (M-1)"

    # M-6 — unmapped state token (charset-legal, not in the §4.1 vocabulary).
    _st_trk_neg "$(printf '%s\n' "$_st_good_body" | sed 's/state=in-progress/state=frobnicated/')" "unmapped state (M-6)"

    # M-6 — duplicate singleton key (a second verdict line).
    _st_trk_neg "$(printf '%s\nverdict bound\n' "$_st_good_body")" "duplicate verdict key (M-6)"

    # M-6 — row id != requested. AB-2 is an F-5-valid id for this fixture's project (AB) that
    # simply differs from the record's actual row (AB-1) — so this leg's refusal is caused ONLY
    # by the M-6 subject-mismatch rule, never confounded by a coincidental F-5 grammar failure
    # (TBG-FIX-2 was NOT project-AB-shaped, so its label didn't match its true cause).
    _st_trk_neg "$(printf '%s\n' "$_st_good_body" | sed 's/^requested .*/requested AB-2/')" "row id != requested (M-6)"

    # M-6 — verdict bound with no row line.
    _st_trk_neg "$(printf '%s\n' "$_st_good_body" | grep -v '^row ')" "bound without a row line (M-6)"

    # M-6 — hostile charset byte (a literal backtick) smuggled into the row line.
    _st_trk_neg "$(printf '%s\n' "$_st_good_body" | sed 's/state=in-progress/state=in-progress`/')" "hostile charset byte (M-6)"

    # M-3 — credential unverified coexisting with verdict bound.
    _st_trk_neg "$(printf '%s\n' "$_st_good_body" | sed 's/^credential ok/credential unverified/')" "unverified credential + bound verdict (M-3)"

    # M-4 — backend mismatch: the record claims github while the base conf/CLAUDE.md say jira.
    _st_trk_neg "$(printf '%s\n' "$_st_good_body" | sed 's/^backend jira/backend github/')" "backend mismatch (M-4)"

    # L-2 — read-day outside the today/yesterday window.
    _st_trk_neg "$(printf '%s\n' "$_st_good_body" | sed 's/^read-day .*/read-day 2020-01-01/')" "stale read-day (L-2)"

    # N-1 — a duplicate token KEY inside one `row` line must refuse (last-wins is not permitted).
    _st_trk_neg "$(printf '%s\n' "$_st_good_body" | sed 's/state=in-progress/state=in-progress state=done/')" "duplicate state= token in one row line (N-1)"
    _st_trk_neg "$(printf '%s\n' "$_st_good_body" | sed 's/state=in-progress/state=in-progress claimed=yes claimed=no/')" "duplicate claimed= token in one row line (N-1)"

    # N-2 — a NUL byte embedded in the record must refuse (invisible to the per-line charset gate).
    _stn_nul="$LS_FXDIR/tracker-record-nul.txt"
    printf '%s\n' "$_st_good_body" > "$_stn_nul"
    printf '\000' >> "$_stn_nul"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stn_nul"; SEAM_HEAD="$_st_trkhead"
    seam_row_count AB-1 >/dev/null 2>&1 \
      && { echo "selftest FAIL: a NUL byte embedded in the record must be REFUSED (N-2)"; st_fail=1; }

    # N-4 — a base conf carrying a DUPLICATE backend= line must refuse (routed through the one
    # parser, scripts/tracker-conf.sh get, not a second ad hoc `grep '^backend=' | head -1`). The
    # record's own pin is re-digested against THIS conf's actual bytes so the M-1 pin check passes
    # and the leg actually exercises the N-4 backend-compare path, not an unrelated stale-pin refusal.
    _stn_dupconfdir="$LS_FXDIR/tracker-dupbackend"
    mkdir -p "$_stn_dupconfdir/.kit"
    printf '%s\n' "version=1
backend=jira
backend=jira
base_url=https://example.atlassian.net
project=AB" > "$_stn_dupconfdir/.kit/tracker.conf"
    cp "$_st_trk/CLAUDE.md" "$_stn_dupconfdir/CLAUDE.md"
    _stn_dupdigest=$( { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } < "$_stn_dupconfdir/.kit/tracker.conf" | awk '{print $1}')
    _stn_dupback="$LS_FXDIR/tracker-record-dupback.txt"
    printf '%s\n' "$_st_good_body" | sed "s/^pin sha256:.*/pin sha256:$_stn_dupdigest/" > "$_stn_dupback"
    SEAM_ROOT="$_stn_dupconfdir"; SEAM_RECORD="$_stn_dupback"; SEAM_HEAD="$_st_trkhead"
    seam_row_count AB-1 >/dev/null 2>&1 \
      && { echo "selftest FAIL: a base conf with a duplicate backend= line must be REFUSED (N-4)"; st_fail=1; }

    # L-a — an unbounded unknown-key length must not be echoed unbounded onto stderr.
    _stn_longkey=$(awk 'BEGIN{s="a"; for(i=0;i<12;i++) s=s s; print s}')
    _stn_longrec="$LS_FXDIR/tracker-record-longkey.txt"
    printf 'kit-tracker-read 1\n%s value\n' "$_stn_longkey" > "$_stn_longrec"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stn_longrec"; SEAM_HEAD="$_st_trkhead"
    _stn_longout=$(seam_row_count AB-1 2>&1 >/dev/null) || true
    if [ "${#_stn_longout}" -gt 90 ]; then
      echo "selftest FAIL: an unknown-key refusal must be BOUNDED (L-a), got ${#_stn_longout} bytes: <$_stn_longout>"; st_fail=1
    fi
    case "$_stn_longout" in
      *"key"*) : ;;
      *) echo "selftest FAIL: a bounded unknown-key refusal must still name 'key' (L-a), got <$_stn_longout>"; st_fail=1 ;;
    esac

    # L-b — `verdict unverified` on an otherwise-sound record must refuse with a NAMED sentence.
    _stn_unvrec="$LS_FXDIR/tracker-record-unverified.txt"
    printf '%s\n' "$_st_good_body" | sed 's/^verdict bound/verdict unverified/' | grep -v '^row ' > "$_stn_unvrec"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stn_unvrec"; SEAM_HEAD="$_st_trkhead"
    _stn_unvout=$(seam_row_count AB-1 2>&1 >/dev/null) || true
    case "$_stn_unvout" in
      *"unverified"*) : ;;
      *) echo "selftest FAIL: 'verdict unverified' must refuse with a NAMED sentence (L-b), got <$_stn_unvout>"; st_fail=1 ;;
    esac

    # L-c — a malformed dor-* token key (empty metric name, or a second `=` folded into the value)
    # must refuse.
    _st_trk_neg "$(printf '%s\n' "$_st_good_body" | sed 's/state=in-progress/state=in-progress dor-=yes/')" "empty dor- metric name (L-c)"
    _st_trk_neg "$(printf '%s\n' "$_st_good_body" | sed 's/state=in-progress/state=in-progress dor-metric=yes=no/')" "second = folded into a dor- value (L-c)"

    # missing 512-line cap positive leg — a 513-line record must refuse (M-2's cap, previously
    # untested in this direction).
    _stn_513="$LS_FXDIR/tracker-record-513.txt"
    {
      echo "kit-tracker-read 1"
      _st_i=1
      while [ "$_st_i" -le 512 ]; do
        printf 'requested AB-1\n'
        _st_i=$((_st_i + 1))
      done
    } > "$_stn_513"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stn_513"; SEAM_HEAD="$_st_trkhead"
    seam_row_count AB-1 >/dev/null 2>&1 \
      && { echo "selftest FAIL: a 513-line record must be REFUSED (the 512-line cap, M-2)"; st_fail=1; }

    # M-2 — a symlinked record path.
    _stn_sym="$LS_FXDIR/tracker-record-sym.txt"
    ln -sf "$_st_trkrec" "$_stn_sym"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stn_sym"; SEAM_HEAD="$_st_trkhead"
    seam_row_count AB-1 >/dev/null 2>&1 \
      && { echo "selftest FAIL: a symlinked record path must be REFUSED (M-2)"; st_fail=1; }

    # M-2 — an oversized record (>64 KiB).
    _stn_big="$LS_FXDIR/tracker-record-big.txt"
    { printf '%s\n' "$_st_good_body"; awk 'BEGIN{for(i=0;i<70000;i++) printf "x"}'; } > "$_stn_big"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stn_big"; SEAM_HEAD="$_st_trkhead"
    seam_row_count AB-1 >/dev/null 2>&1 \
      && { echo "selftest FAIL: an oversized record must be REFUSED (M-2)"; st_fail=1; }

    # M-3 — over-privileged BINDS, with a stderr NOTICE (never a refusal).
    _stn_ovp="$LS_FXDIR/tracker-record-ovp.txt"
    printf '%s\n' "$_st_good_body" | sed 's/^credential ok/credential over-privileged/' > "$_stn_ovp"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stn_ovp"; SEAM_HEAD="$_st_trkhead"
    _st_ovpout=$(seam_row_count AB-1 2>&1 >/dev/null) && _st_ovprc=0 || _st_ovprc=$?
    [ "$_st_ovprc" -eq 0 ] \
      || { echo "selftest FAIL: an over-privileged credential must still BIND (M-3)"; st_fail=1; }
    case "$_st_ovpout" in
      *NOTICE*"over-privileged"*) : ;;
      *) echo "selftest FAIL: an over-privileged credential must carry a stderr NOTICE (M-3), got <$_st_ovpout>"; st_fail=1 ;;
    esac

    # L-1 — sentence hygiene: the hostile-byte leg's refusal must never echo the hostile byte itself.
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$LS_FXDIR/tracker-record-neg.txt"
    printf '%s\n' "$_st_good_body" | sed 's/state=in-progress/state=in-progress`whoami`/' > "$SEAM_RECORD"
    SEAM_HEAD="$_st_trkhead"
    _st_hostout=$(seam_row_count AB-1 2>&1 >/dev/null) || true
    case "$_st_hostout" in
      *'`whoami`'*) echo "selftest FAIL: a refusal must NEVER echo the hostile record bytes (L-1), got <$_st_hostout>"; st_fail=1 ;;
      *) : ;;
    esac

    unset -f _st_trk_neg

    # --- T6a (TBG-READER-FLAGS-LIST T6a): multi-`row`/multi-`list` capture, closed dor- names, two
    # new tokens (bijection itself is T6b — not tested here). Design §3b's example record, on the
    # SAME fixture tree/conf as the T6b section above (project=AB in $_st_trkconf, so AB-* ids are
    # in-grammar) — read-day/head/pin built the same way the existing good-record builder does.
    _st_mr_rec="$LS_FXDIR/tracker-record-multirow.txt"
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_st_trkpin"
      echo "head $_st_trkhead"
      echo "requested AB-7"
      echo "read-day $_st_trktoday"
      echo "credential ok"
      echo "verdict bound"
      echo "row AB-7 state=in-progress claimed=yes"
      echo "row AB-12 state=ready dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes"
      echo "row AB-31 state=ready dor-acceptance=yes dor-metric=no dor-size=yes dor-risk=yes"
      echo "list ready AB-12 AB-31"
      echo "list in-progress AB-7"
    } > "$_st_mr_rec"

    # Leg 1 — the good multi-row/multi-list record BINDS (seam_row_count on the subject = 1).
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_rec"; SEAM_HEAD="$_st_trkhead"
    _st_mrc=$(seam_row_count AB-7 2>/dev/null) && _st_mrrc=0 || _st_mrrc=$?
    [ "$_st_mrrc" -eq 0 ] && [ "$_st_mrc" = "1" ] \
      || { echo "selftest FAIL: T6a leg1 — a good multi-row/multi-list record must BIND seam_row_count=1 for the subject, got rc=$_st_mrrc val=$_st_mrc"; st_fail=1; }
    # F-1(a): also assert the resolved STATE is the subject's own (AB-7 -> in-progress), never a
    # non-subject row's (AB-12/AB-31 -> ready) — a mutant that takes `state=` from the LAST row
    # scanned rather than the MATCHING row would still bind (count=1) but return the wrong value.
    _st_mrs=$(seam_row_state AB-7 2>/dev/null) && _st_mrsrc=0 || _st_mrsrc=$?
    [ "$_st_mrsrc" -eq 0 ] && [ "$_st_mrs" = "in-progress" ] \
      || { echo "selftest FAIL: T6a leg1 — seam_row_state AB-7 must be in-progress (the subject's own row), got rc=$_st_mrsrc val=$_st_mrs"; st_fail=1; }

    # Leg 1b (F-1(b)) — the SUBJECT row LAST, after rows in OTHER states (single-spaced, lists
    # consistent). Leg 1 alone leaves the subject-first shape as the only one exercised; a mutant
    # that resolves `state=` from the LAST row _seam_rows_state_of scans (MA), rather than the
    # one whose id actually matches, would still pass leg1 (subject first == last row happens to be
    # a non-subject `ready` row there too, but leg1 doesn't probe that) — this leg pins the case
    # where "last scanned" and "the subject" are provably different rows.
    _st_mrlast_rec="$LS_FXDIR/tracker-record-multirow-last.txt"
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_st_trkpin"
      echo "head $_st_trkhead"
      echo "requested AB-7"
      echo "read-day $_st_trktoday"
      echo "credential ok"
      echo "verdict bound"
      echo "row AB-12 state=ready"
      echo "row AB-31 state=done"
      echo "row AB-7 state=in-progress"
      echo "list ready AB-12"
      echo "list done AB-31"
      echo "list in-progress AB-7"
    } > "$_st_mrlast_rec"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mrlast_rec"; SEAM_HEAD="$_st_trkhead"
    _st_mrlc=$(seam_row_count AB-7 2>/dev/null) && _st_mrlrc=0 || _st_mrlrc=$?
    [ "$_st_mrlrc" -eq 0 ] && [ "$_st_mrlc" = "1" ] \
      || { echo "selftest FAIL: T6a leg1b — subject-row-last must still BIND seam_row_count=1, got rc=$_st_mrlrc val=$_st_mrlc"; st_fail=1; }
    _st_mrls=$(seam_row_state AB-7 2>/dev/null) && _st_mrlrc=0 || _st_mrlrc=$?
    [ "$_st_mrlrc" -eq 0 ] && [ "$_st_mrls" = "in-progress" ] \
      || { echo "selftest FAIL: T6a leg1b — subject-row-last must resolve seam_row_state=in-progress (not a non-subject row's state), got rc=$_st_mrlrc val=$_st_mrls"; st_fail=1; }

    # Leg 2 — _SRV_ROWS holds EXACTLY all three rows (newline-joined, in file order, one trailing
    # newline per T6a's append convention) and _SRV_LISTS EXACTLY both lists, asserted with WHOLE-
    # STRING equality (F-1(c): a substring `case` match cannot tell "newline-joined" from
    # "space-joined" apart — MB drops the newline separator and every substring is still present,
    # just glued onto one line — so this leg pins the SEPARATOR, not merely the content). Also
    # asserts _seam_record_load itself returned 0 (a PLAIN call, never `$(...)`, so the globals it
    # sets land in THIS shell — same convention LS_ROW_STATE's assertion above already relies on;
    # captured via the `cmd && rc=0 || rc=$?` idiom so a future non-zero can't abort the whole
    # selftest under `set -e` before its own FAIL: line prints).
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_rec"; SEAM_HEAD="$_st_trkhead"
    _seam_record_load >/dev/null 2>&1 && _st_t6a_l2rc=0 || _st_t6a_l2rc=$?
    [ "$_st_t6a_l2rc" -eq 0 ] \
      || { echo "selftest FAIL: T6a leg2 — _seam_record_load must return 0 on the good multi-row/multi-list record, got rc=$_st_t6a_l2rc"; st_fail=1; }
    _st_t6a_want_rows="AB-7 state=in-progress claimed=yes
AB-12 state=ready dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes
AB-31 state=ready dor-acceptance=yes dor-metric=no dor-size=yes dor-risk=yes
"
    _st_t6a_want_lists="ready AB-12 AB-31
in-progress AB-7
"
    [ "$_SRV_ROWS" = "$_st_t6a_want_rows" ] \
      || { echo "selftest FAIL: T6a leg2 — _SRV_ROWS must equal the three newline-joined rows exactly, got <$_SRV_ROWS>"; st_fail=1; }
    [ "$_SRV_LISTS" = "$_st_t6a_want_lists" ] \
      || { echo "selftest FAIL: T6a leg2 — _SRV_LISTS must equal the two newline-joined lists exactly, got <$_SRV_LISTS>"; st_fail=1; }

    _st_mr_body=$(cat "$_st_mr_rec")
    _st_mr_neg() {   # $1 = record content, $2 = description — one mutation of the T6a good
      # multi-row/multi-list record, asserted RED against it (assert-differs, mirrors _st_trk_neg).
      _stmrn_f="$LS_FXDIR/tracker-record-mr-neg.txt"
      printf '%s' "$1" > "$_stmrn_f"
      SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stmrn_f"; SEAM_HEAD="$_st_trkhead"
      if seam_row_count AB-7 >/dev/null 2>&1; then
        echo "selftest FAIL: T6a negative ($2) must REFUSE, not bind"; st_fail=1
      fi
    }

    # Leg 3 — a duplicate `row` id on two lines must refuse.
    _st_mr_neg "$(printf '%s\n' "$_st_mr_body"; printf 'row AB-12 state=ready dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes\n')" "duplicate row id on two lines (leg3)"

    # Leg 4 — two `list ready` lines must refuse (a duplicate LIST STATE, not a duplicate id).
    _st_mr_neg "$(printf '%s\n' "$_st_mr_body"; printf 'list ready AB-12\n')" "two list ready lines (leg4)"

    # Leg 5 — a duplicate id WITHIN one `list` line must refuse.
    _st_mr_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/^list ready AB-12 AB-31$/list ready AB-12 AB-12 AB-31/')" "duplicate id within one list line (leg5)"

    # Leg 6 — a `dor-bogus=yes` token on a row must refuse (the P-2 closed dor- name set).
    _st_mr_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/dor-risk=yes$/dor-risk=yes dor-bogus=yes/')" "dor-bogus on a row (leg6)"

    # Leg 7 — `outcome-recorded=yes` and `blocked-by-open=no` on a row are ACCEPTED (booleans, F-9
    # forward-compat: the reader does not emit them yet, but the parser must not refuse them).
    _st_mr_pos_f="$LS_FXDIR/tracker-record-mr-pos.txt"
    printf '%s\n' "$_st_mr_body" | sed 's/^row AB-7 state=in-progress claimed=yes$/row AB-7 state=in-progress claimed=yes outcome-recorded=yes blocked-by-open=no/' > "$_st_mr_pos_f"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_pos_f"; SEAM_HEAD="$_st_trkhead"
    _st_mrp_c=$(seam_row_count AB-7 2>/dev/null) && _st_mrp_rc=0 || _st_mrp_rc=$?
    [ "$_st_mrp_rc" -eq 0 ] && [ "$_st_mrp_c" = "1" ] \
      || { echo "selftest FAIL: T6a leg7 — outcome-recorded=yes/blocked-by-open=no on a row must be ACCEPTED (binds), got rc=$_st_mrp_rc val=$_st_mrp_c"; st_fail=1; }
    # F-1(a): also assert the resolved STATE is still the subject's own (in-progress), not a
    # non-subject row's (ready) — same MA mutant coverage as leg1, on a record shape leg1 doesn't
    # cover (the subject row carries the two new forward-compat tokens).
    _st_mrps=$(seam_row_state AB-7 2>/dev/null) && _st_mrpsrc=0 || _st_mrpsrc=$?
    [ "$_st_mrpsrc" -eq 0 ] && [ "$_st_mrps" = "in-progress" ] \
      || { echo "selftest FAIL: T6a leg7 — seam_row_state AB-7 must be in-progress (the subject's own row), got rc=$_st_mrpsrc val=$_st_mrps"; st_fail=1; }

    # Leg 8 — the two new booleans are BOOLEANS ONLY: `blocked-by-open=maybe` and
    # `outcome-recorded=n/a` must each refuse (never a silent pass, mirrors dor-*'s M-5 rule).
    _st_mr_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/^row AB-7 state=in-progress claimed=yes$/row AB-7 state=in-progress claimed=yes blocked-by-open=maybe/')" "blocked-by-open=maybe (leg8)"
    _st_mr_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/^row AB-7 state=in-progress claimed=yes$/row AB-7 state=in-progress claimed=yes outcome-recorded=n\/a/')" "outcome-recorded=n/a (leg8)"

    unset -f _st_mr_neg

    # F-2 (fix round 1, Minor) — _SRV_ROWS/_SRV_LISTS must be CLEARED on every rc-2 refusal, never
    # a stale partially-parsed capture surviving past a refused record. The duplicate-row-id record
    # (same mutation as leg3) is refused AFTER its first row has already been appended to
    # _SRV_ROWS — the load-bearing shape a leak here would actually carry real row data past a
    # refusal. A PLAIN call (never `$(...)`), so the globals _seam_record_load sets land in THIS
    # shell and can be inspected afterward.
    _st_f2_f="$LS_FXDIR/tracker-record-f2-dup.txt"
    { printf '%s\n' "$_st_mr_body"; printf 'row AB-12 state=ready dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes\n'; } > "$_st_f2_f"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_f2_f"; SEAM_HEAD="$_st_trkhead"
    _seam_record_load >/dev/null 2>&1 && _st_f2rc=0 || _st_f2rc=$?
    [ "$_st_f2rc" -eq 2 ] \
      || { echo "selftest FAIL: F-2 — a duplicate-row-id record must return rc=2, got rc=$_st_f2rc"; st_fail=1; }
    [ -z "$_SRV_ROWS" ] \
      || { echo "selftest FAIL: F-2 — _SRV_ROWS must be cleared on refusal, got <$_SRV_ROWS>"; st_fail=1; }
    # T6b Step 0b (re-review Minor): the F-2 leg above asserted only _SRV_ROWS was cleared — a
    # mutant that cleared _SRV_ROWS but left _SRV_LISTS alone would survive it. This fixture's
    # record carries a `list` line too (part of $_st_mr_body), so _SRV_LISTS is non-empty mid-parse
    # by the time the duplicate-row-id refusal fires; assert it is ALSO cleared.
    [ -z "$_SRV_LISTS" ] \
      || { echo "selftest FAIL: F-2 — _SRV_LISTS must ALSO be cleared on refusal, got <$_SRV_LISTS>"; st_fail=1; }

    # T6b Step 0b item 2 — the LATE-refusal leg: a good multi-row/multi-list record whose
    # SEAM_HEAD is wrong is refused AFTER the row/list scan already populated _SRV_ROWS/_SRV_LISTS
    # (H-2's head compare runs near the END of _seam_record_load_parse, well after the row/list
    # loop) — both captures must STILL come back empty (F-2's clear-on-refusal must cover every
    # refusal site, not just the mid-scan one the F-2 leg above already pins).
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_rec"; SEAM_HEAD="2222222222222222222222222222222222222222"
    _seam_record_load >/dev/null 2>&1 && _st_lr_rc=0 || _st_lr_rc=$?
    [ "$_st_lr_rc" -eq 2 ] \
      || { echo "selftest FAIL: T6b Step 0b — a wrong-SEAM_HEAD refusal on a good multi-row record must return rc=2, got rc=$_st_lr_rc"; st_fail=1; }
    [ -z "$_SRV_ROWS" ] \
      || { echo "selftest FAIL: T6b Step 0b — _SRV_ROWS must be cleared on a LATE (post-row-scan) refusal, got <$_SRV_ROWS>"; st_fail=1; }
    [ -z "$_SRV_LISTS" ] \
      || { echo "selftest FAIL: T6b Step 0b — _SRV_LISTS must be cleared on a LATE (post-row-scan) refusal, got <$_SRV_LISTS>"; st_fail=1; }
    # T6b Step 0b item 3 (hardening) — _SRV_ROWID/_SRV_ROWSTATE are set by the subject-match step,
    # which runs BEFORE the H-2 head compare, so a LATE refusal like this one leaves them set by
    # _seam_record_load_parse; the wrapper must clear these two too, not just _SRV_ROWS/_SRV_LISTS.
    [ -z "$_SRV_ROWID" ] \
      || { echo "selftest FAIL: T6b Step 0b — _SRV_ROWID must be cleared on a LATE refusal too, got <$_SRV_ROWID>"; st_fail=1; }
    [ -z "$_SRV_ROWSTATE" ] \
      || { echo "selftest FAIL: T6b Step 0b — _SRV_ROWSTATE must be cleared on a LATE refusal too, got <$_SRV_ROWSTATE>"; st_fail=1; }
    # T6b-fix1 Minor 3 — the wrapper must clear EVERY _SRV_* global on refusal (step 0b said "every";
    # only 4 of the 11 were, before this fix). Same LATE-refusal fixture as above.
    [ -z "$_SRV_REQUESTED" ] \
      || { echo "selftest FAIL: T6b-fix1 Minor 3 — _SRV_REQUESTED must be cleared on a LATE refusal too, got <$_SRV_REQUESTED>"; st_fail=1; }
    [ -z "$_SRV_VERDICT" ] \
      || { echo "selftest FAIL: T6b-fix1 Minor 3 — _SRV_VERDICT must be cleared on a LATE refusal too, got <$_SRV_VERDICT>"; st_fail=1; }
    [ -z "$_SRV_SUBJ_STATE" ] \
      || { echo "selftest FAIL: T6b-fix1 Minor 3 — _SRV_SUBJ_STATE must be cleared on a LATE refusal too, got <$_SRV_SUBJ_STATE>"; st_fail=1; }
    SEAM_HEAD="$_st_trkhead"

    # Leg 9 (lens 7: `loop-state` unaffected) — today's shape, one `row` line, no flags, no `list`
    # at all, still binds — the ORIGINAL $_st_trkrec built earlier in this section, re-asserted
    # here explicitly (not just relying on its earlier use above) as the N=1 regression guard for
    # everything T6a changed.
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_trkrec"; SEAM_HEAD="$_st_trkhead"
    _st_l9c=$(seam_row_count AB-1 2>/dev/null) && _st_l9rc=0 || _st_l9rc=$?
    [ "$_st_l9rc" -eq 0 ] && [ "$_st_l9c" = "1" ] \
      || { echo "selftest FAIL: T6a leg9 — today's shape (one row line, no flags, no list) must still BIND, got rc=$_st_l9rc val=$_st_l9c"; st_fail=1; }
    _st_l9s=$(seam_row_state AB-1 2>/dev/null) && _st_l9rc=0 || _st_l9rc=$?
    [ "$_st_l9rc" -eq 0 ] && [ "$_st_l9s" = "in-progress" ] \
      || { echo "selftest FAIL: T6a leg9 — today's shape must still resolve seam_row_state=in-progress, got rc=$_st_l9rc val=$_st_l9s"; st_fail=1; }

    # --- T6b (TBG-READER-FLAGS-LIST T6b): the §3b bijection rules, the F-5 project-id check, and
    # M-6's one-space rule (design §3b/§3c, plan task T6 "Re-slicing" row T6b). Built on the SAME
    # $_st_mr_rec / $_st_mr_body multi-row/multi-list good record T6a already established (project
    # AB, subject AB-7 state=in-progress, non-subject AB-12/AB-31 state=ready, `list ready AB-12
    # AB-31` / `list in-progress AB-7`). ------------------------------------------------------------

    # Leg 0 (T6a review, M-6) — FIRST, before any bijection code reads the captures: exactly ONE
    # ASCII space between tokens on every line. Two spaces on a `row` line, two spaces on a `list`
    # line, and a trailing space must each refuse (rc2) — `list done` and `list done  ` would
    # otherwise capture differently, and a reader treating "present list, zero ids" as a real
    # answer (H-3) would read the trailing-space form as non-empty.
    _st_t6b_neg() {   # $1 = record content, $2 = description — one mutation of $_st_mr_body,
      # asserted RED against it (assert-differs, mirrors T6a's _st_mr_neg).
      _stn6b_f="$LS_FXDIR/tracker-record-t6b-neg.txt"
      printf '%s' "$1" > "$_stn6b_f"
      SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stn6b_f"; SEAM_HEAD="$_st_trkhead"
      if seam_row_count AB-7 >/dev/null 2>&1; then
        echo "selftest FAIL: T6b negative ($2) must REFUSE, not bind"; st_fail=1
      fi
    }
    _st_t6b_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/^row AB-7 state=in-progress claimed=yes$/row AB-7  state=in-progress claimed=yes/')" "two spaces on a row line (leg0/M-6)"
    _st_t6b_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/^list ready AB-12 AB-31$/list ready  AB-12 AB-31/')" "two spaces on a list line (leg0/M-6)"
    _st_t6b_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/^list in-progress AB-7$/list in-progress AB-7 /')" "trailing space on a list line (leg0/M-6)"

    # Leg 1 — a listed id with no `row` line at all -> rc2 (§3b bijection).
    _st_t6b_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/^list ready AB-12 AB-31$/list ready AB-12 AB-31 AB-99/')" "listed id AB-99 names no row line (leg1)"

    # Leg 2 — a `row` whose state= differs from the list it appears in -> rc2 (§3b bijection).
    _st_t6b_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/^row AB-12 state=ready dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes$/row AB-12 state=in-progress dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes/')" "row AB-12 state disagrees with the list ready it is under (leg2)"

    # Leg 3 — a non-subject `row` that appears in no list -> rc2 (§3b bijection). AB-31 keeps its
    # row line but is dropped from the ready list.
    _st_t6b_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/^list ready AB-12 AB-31$/list ready AB-12/')" "non-subject row AB-31 appears in no list (leg3)"

    # Leg 4 — one id in two DIFFERENT lists -> rc2 (§3b bijection). AB-12 (ready) is ALSO added to
    # the in-progress list.
    _st_t6b_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/^list in-progress AB-7$/list in-progress AB-7 AB-12/')" "AB-12 listed under two different states (leg4)"

    # Leg 5 — the subject id in ANOTHER state's list -> rc2 (§3b bijection). AB-7 (state=
    # in-progress) is listed under `ready` instead of `in-progress`.
    _st_t6b_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/^list ready AB-12 AB-31$/list ready AB-12 AB-31 AB-7/
s/^list in-progress AB-7$/list in-progress/')" "subject AB-7 listed under another state (leg5)"

    # T6b-fix1 Important 1 (a) — the "iff" half of §3b: the subject's OWN state (ready) IS listed
    # (list ready AB-12 AB-31 is present), but the subject (now state=ready) is absent from it ->
    # rc2. The `list in-progress AB-7` line is dropped entirely (rather than left stale) so rule B
    # (row/list state agreement) cannot fire first — the ONLY defect left is the "iff" gap.
    _st_t6b_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/^row AB-7 state=in-progress claimed=yes$/row AB-7 state=ready claimed=yes/
/^list in-progress AB-7$/d')" "subject AB-7 (now state=ready) absent from the listed ready state (fix1-important1a)"

    # T6b-fix1 Important 1 (b) — the subject's own state (in-progress) IS listed, but with ZERO
    # ids (an empty `list in-progress` line) -> rc2. Distinct from Leg 7's positive control (NO
    # list line at all for that state).
    _st_t6b_neg "$(printf '%s\n' "$_st_mr_body" | sed 's/^list in-progress AB-7$/list in-progress/')" "subject AB-7's own state listed but EMPTY (fix1-important1b)"

    unset -f _st_t6b_neg

    # Leg 6 — the subject row in its OWN state's list -> binds (positive). This is exactly
    # $_st_mr_rec's own shape (AB-7 state=in-progress, `list in-progress AB-7`) — re-asserted here
    # explicitly as the T6b positive control now that the bijection pass (Legs 1-3) is fully wired.
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_rec"; SEAM_HEAD="$_st_trkhead"
    _st_t6b_l6c=$(seam_row_count AB-7 2>/dev/null) && _st_t6b_l6rc=0 || _st_t6b_l6rc=$?
    [ "$_st_t6b_l6rc" -eq 0 ] && [ "$_st_t6b_l6c" = "1" ] \
      || { echo "selftest FAIL: T6b leg6 — the subject listed under its OWN state must still BIND, got rc=$_st_t6b_l6rc val=$_st_t6b_l6c"; st_fail=1; }

    # Leg 7 — the subject row in NO list at all -> binds (positive, presence-only read). AB-7 keeps
    # its row (state=in-progress) but there is no `list in-progress` line at all; AB-12 keeps its
    # own single `list ready` membership so rule (c) (every non-subject row lists exactly once)
    # still holds for it — a genuinely different shape from T6a leg9's "one row, no list at all".
    _st_t6b_l7_rec="$LS_FXDIR/tracker-record-t6b-leg7.txt"
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_st_trkpin"
      echo "head $_st_trkhead"
      echo "requested AB-7"
      echo "read-day $_st_trktoday"
      echo "credential ok"
      echo "verdict bound"
      echo "row AB-7 state=in-progress claimed=yes"
      echo "row AB-12 state=ready dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes"
      echo "list ready AB-12"
    } > "$_st_t6b_l7_rec"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_t6b_l7_rec"; SEAM_HEAD="$_st_trkhead"
    _st_t6b_l7c=$(seam_row_count AB-7 2>/dev/null) && _st_t6b_l7rc=0 || _st_t6b_l7rc=$?
    [ "$_st_t6b_l7rc" -eq 0 ] && [ "$_st_t6b_l7c" = "1" ] \
      || { echo "selftest FAIL: T6b leg7 — the subject listed under NO state (presence-only read) must still BIND, got rc=$_st_t6b_l7rc val=$_st_t6b_l7c"; st_fail=1; }

    # Leg 8 — `verdict bound` with no row equal to `requested` -> rc2. Already covered by the
    # pre-T6a "row id != requested (M-6)" negative (single-row shape) and by the pre-existing
    # _seam_rows_state_of check itself (unchanged by this slice) — pinned HERE too, on the
    # MULTI-row good record (requested renamed to an id no row carries), per the brief's own
    # "if T6a already covers it, pin it here with a mutant instead and say so."
    _st_t6b_neg2() {
      _stn6b2_f="$LS_FXDIR/tracker-record-t6b-neg2.txt"
      printf '%s' "$1" > "$_stn6b2_f"
      SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stn6b2_f"; SEAM_HEAD="$_st_trkhead"
      if seam_row_count AB-99 >/dev/null 2>&1; then
        echo "selftest FAIL: T6b negative ($2) must REFUSE, not bind"; st_fail=1
      fi
    }
    _st_t6b_neg2 "$(printf '%s\n' "$_st_mr_body" | sed 's/^requested AB-7$/requested AB-99/')" "verdict bound but no row equals requested (leg8, multi-row pin)"
    unset -f _st_t6b_neg2

    # Leg 9 (F-5) — an id not matching ^<conf project>-[1-9][0-9]*$ in a `row` -> rc2; in a `list`
    # -> rc2. Leading zeros refused (AB-07 must not alias AB-7). Project is "AB" ($_st_trkconf).
    # Each mutation renames BOTH the row AND its list occurrence consistently, so F-5's grammar
    # check is the ONLY defect exercised (never confounded with the bijection rules above).
    _st_t6b_neg3() {
      _stn6b3_f="$LS_FXDIR/tracker-record-t6b-neg3.txt"
      printf '%s' "$1" > "$_stn6b3_f"
      SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stn6b3_f"; SEAM_HEAD="$_st_trkhead"
      if seam_row_count AB-7 >/dev/null 2>&1; then
        echo "selftest FAIL: T6b negative ($2) must REFUSE, not bind"; st_fail=1
      fi
    }
    # T6b-fix1 Important 2 (step 3 rework): this "row" sub-case renames BOTH the row AND its list
    # occurrence together, so its refusal today comes from the LIST-side check (a listed id failing
    # F-5), not independently from the row-side check — re-labelled to say so honestly. The row-side
    # check is independently, load-bearingly exercised by the LONE-SUBJECT legs below (no `list` line
    # at all), added fresh for this fix.
    _st_t6b_neg3 "$(printf '%s\n' "$_st_mr_body" | sed 's/^row AB-12 state=ready dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes$/row AB-07 state=ready dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes/
s/^list ready AB-12 AB-31$/list ready AB-07 AB-31/')" "row+list id AB-07 fails the project grammar, leading zero (leg9/F-5, confounded with the list-side check — row isolation is fix1-important2)"
    _st_t6b_neg3 "$(printf '%s\n' "$_st_mr_body" | sed 's/^row AB-31 state=ready dor-acceptance=yes dor-metric=no dor-size=yes dor-risk=yes$/row CD-31 state=ready dor-acceptance=yes dor-metric=no dor-size=yes dor-risk=yes/
s/^list ready AB-12 AB-31$/list ready AB-12 CD-31/')" "list id CD-31 fails the project grammar, wrong project (leg9/F-5, list)"
    unset -f _st_t6b_neg3

    # T6b-fix1 Important 2 (step 2) — F-5 must cover the SUBJECT id too (today it is skipped by a
    # `continue` in the row-loop's F-5 call, leaving that call dead: leg9 above only ever exercises
    # NON-subject ids, and always alongside a matching list-side mutation, so the row-side call's own
    # contribution is never independently proven — the reviewer's mutant MR, replacing the row-loop's
    # `_seam_id_matches_project "$_srb_rid"` call with an unconditional success, survives every
    # existing leg). These two legs use the LONE-SUBJECT single-row fixture ($_st_good_body, project
    # AB, NO `list` line at all) so the row-side check is the ONLY code path that can catch a bad
    # subject id — renaming `requested` and its `row` consistently (they must still agree, M-6).
    _st_t6bfix1_neg4() {
      _stn6bf1_f="$LS_FXDIR/tracker-record-t6bfix1-neg.txt"
      printf '%s' "$1" > "$_stn6bf1_f"
      SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stn6bf1_f"; SEAM_HEAD="$_st_trkhead"
      if seam_row_count "$2" >/dev/null 2>&1; then
        echo "selftest FAIL: T6b-fix1 negative ($3) must REFUSE, not bind"; st_fail=1
      fi
    }
    _st_t6bfix1_neg4 "$(printf '%s\n' "$_st_good_body" | sed 's/^requested AB-1$/requested AB-07/
s/^row AB-1 /row AB-07 /')" "AB-07" "lone subject id AB-07 fails the project grammar, leading zero, no list at all (fix1-important2)"
    _st_t6bfix1_neg4 "$(printf '%s\n' "$_st_good_body" | sed 's/^requested AB-1$/requested ZZ-9/
s/^row AB-1 /row ZZ-9 /')" "ZZ-9" "lone subject id ZZ-9 fails the project grammar, wrong project, no list at all (fix1-important2)"
    unset -f _st_t6bfix1_neg4

    # --- WB-FIX-A A1: the two seam-answer legs moved OUT of scripts/tracker-read.sh's own selftest
    # (Q2 / T5d leg 6) — a public seam call from that file made board-parser-drift clause (c) treat
    # it as a seam-routed board consumer, and it names curl (D-240919-4: curl is POSITIVELY scoped,
    # never file-allowlisted). The reader keeps its own emit + exact-line grep + _seam_record_load
    # parse; the ANSWER half lives here, on the SAME record shapes those legs still byte-grep, built
    # from this section's own tracker-record helpers ($_st_trk/$_st_trkpin/$_st_trkhead/$_st_trktoday).

    # WB-FIX-A Q2: a legal-empty `list ready` line (no ids) still binds, and seam_rows_in_state
    # answers rc 0 empty — the same shape tracker-read.sh's own Q2 leg byte-greps
    # (`grep -q '^list ready$'`).
    _st_wbA_q2rec="$LS_FXDIR/tracker-record-wbA-q2.txt"
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_st_trkpin"
      echo "head $_st_trkhead"
      echo "requested AB-1"
      echo "read-day $_st_trktoday"
      echo "credential ok"
      echo "verdict bound"
      echo "row AB-1 state=in-progress"
      echo "list ready"
    } > "$_st_wbA_q2rec"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_wbA_q2rec"; SEAM_HEAD="$_st_trkhead"
    _st_wbA_q2out=$(seam_rows_in_state ready 2>/dev/null) && _st_wbA_q2rc=0 || _st_wbA_q2rc=$?
    [ "$_st_wbA_q2rc" -eq 0 ] && [ -z "$_st_wbA_q2out" ] \
      || { echo "selftest FAIL: WB-FIX-A Q2 — seam_rows_in_state ready on a legal-empty 'list ready' record must bind rc0 empty, got rc=$_st_wbA_q2rc val=<$_st_wbA_q2out>"; st_fail=1; }

    # WB-FIX-A T5d leg6: the all-four-dor-*=yes subject row — the same shape tracker-read.sh's own
    # T5d leg 6 byte-greps (`grep -q '^row AB-1 state=ready claimed=yes dor-acceptance=yes
    # dor-metric=yes dor-size=yes dor-risk=yes$'`); seam_row_flag answers dor-risk and
    # dor-acceptance 'yes' rc0 via the same unmodified tracker arm T7 leg2/leg4 below already exercise.
    _st_wbA_l6rec="$LS_FXDIR/tracker-record-wbA-t5dleg6.txt"
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_st_trkpin"
      echo "head $_st_trkhead"
      echo "requested AB-1"
      echo "read-day $_st_trktoday"
      echo "credential ok"
      echo "verdict bound"
      echo "row AB-1 state=ready claimed=yes dor-acceptance=yes dor-metric=yes dor-size=yes dor-risk=yes"
      # WB-FIX-2 item 4: mirror the reader's own T5d leg 6 record exactly — its `state.ready=Selected`
      # + `list-in-states` fixture also emits a `list ready AB-1` line for this exact subject/state.
      echo "list ready AB-1"
    } > "$_st_wbA_l6rec"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_wbA_l6rec"; SEAM_HEAD="$_st_trkhead"
    _st_wbA_risk=$(seam_row_flag AB-1 dor-risk 2>/dev/null) && _st_wbA_riskrc=0 || _st_wbA_riskrc=$?
    _st_wbA_acc=$(seam_row_flag AB-1 dor-acceptance 2>/dev/null) && _st_wbA_accrc=0 || _st_wbA_accrc=$?
    [ "$_st_wbA_riskrc" -eq 0 ] && [ "$_st_wbA_risk" = yes ] && [ "$_st_wbA_accrc" -eq 0 ] && [ "$_st_wbA_acc" = yes ] \
      || { echo "selftest FAIL: WB-FIX-A T5d leg6 — seam_row_flag dor-risk/dor-acceptance must bind 'yes' rc0 on the all-four-yes record, got risk-rc=$_st_wbA_riskrc risk=$_st_wbA_risk acc-rc=$_st_wbA_accrc acc=$_st_wbA_acc"; st_fail=1; }

    # T7 Step 0 — the ISOLATING leg (re-review carryover, Minor). The subject's F-5 project-id
    # grammar is today checked TWICE for the same value whenever a `row` line exists — once at
    # _seam_record_bijection's `requested`-id check, once again inside the row loop when the
    # scanned row id happens to equal `requested` — so a mutant defeating EITHER check ALONE
    # still refuses (the other one catches it) and neither call is independently proven. A record
    # with ZERO `row` lines removes the row loop from the picture entirely (it never executes,
    # empty or not), isolating the sole remaining source of refusal to the `requested`-id check.
    _st_iso_rec="$LS_FXDIR/tracker-record-iso-f5.txt"
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_st_trkpin"
      echo "head $_st_trkhead"
      echo "requested ZZ-9"
      echo "read-day $_st_trktoday"
      echo "credential ok"
      echo "verdict unverified"
    } > "$_st_iso_rec"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_iso_rec"; SEAM_HEAD="$_st_trkhead"
    _seam_record_load >/dev/null 2>&1 && _st_iso_rc=0 || _st_iso_rc=$?
    [ "$_st_iso_rc" -eq 2 ] \
      || { echo "selftest FAIL: T7 Step0 isolating leg — a zero-row record with a bad-grammar requested id (ZZ-9) must refuse rc=2, got rc=$_st_iso_rc"; st_fail=1; }

    # --- H-4 (loop-state binding: unset SEAM_RECORD -> rc3 byte-identical; set-but-missing -> rc2,
    # NEVER waivable even under an active waiver) ------------------------------------------------
    unset SEAM_RECORD
    LS_BOARDROOT="$LS_FXDIR/backend-github"
    _st_h4out=$(check_row "$LS_FX_OK" 2>&1) && _st_h4rc=0 || _st_h4rc=$?
    [ "$_st_h4rc" -ne 0 ] || { echo "selftest FAIL: jira/github + SEAM_RECORD unset must stay the H-4 rc3 NOT ENFORCED path"; st_fail=1; }
    case "$_st_h4out" in
      *"NOT ENFORCED: backend 'github'"*) : ;;
      *) echo "selftest FAIL: unset SEAM_RECORD must print today's NOT ENFORCED sentence verbatim (H-4), got <$_st_h4out>"; st_fail=1 ;;
    esac

    SEAM_RECORD="$LS_FXDIR/does-not-exist.txt"
    LS_BOARDROOT="$LS_FXDIR/backend-github-waived"
    _st_h4rc2=0
    check_row "$LS_FX_OK" >/dev/null 2>&1 || _st_h4rc2=$?
    [ "$_st_h4rc2" -ne 0 ] \
      || { echo "selftest FAIL: SEAM_RECORD SET-BUT-MISSING must REFUSE even under an active board-governance waiver (H-4, never waivable)"; st_fail=1; }
    LS_BOARDROOT="$_st_board_saved"
    SEAM_RECORD=""

    # --- H-1: THE ROUND-TRIP LEG — tracker-read.sh's OWN production code writes a REAL record;
    # the seam binds against it, never a hand-authored fixture (anti-drift, "verify the real API"). --
    (
      _rt_tmp=$(mktemp -d) || exit 1
      trap 'rm -rf "$_rt_tmp"' EXIT
      mkdir -p "$_rt_tmp/scripts" "$_rt_tmp/.kit"
      cp "$DIR/scripts/tracker-read.sh" "$_rt_tmp/scripts/tracker-read.sh"
      cp "$DIR/scripts/tracker-conf.sh" "$_rt_tmp/scripts/tracker-conf.sh"
      # A fake `jira` adapter under the THROWAWAY root — TR_ROOT resolves from $0's own dirname, so
      # invoking the COPIED tracker-read.sh (never the real one) dispatches to THIS file, never the
      # real scripts/tracker-jira.sh (J1 neutrality — no network reachable from here).
      cat > "$_rt_tmp/scripts/tracker-jira.sh" <<'EOF'
#!/bin/sh
case "$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t3\n'; printf 'status-name\tIn Progress\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
esac
EOF
      chmod +x "$_rt_tmp/scripts/tracker-jira.sh"
      cat > "$_rt_tmp/.kit/tracker.conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
state.in-progress=In Progress
EOF
      printf '# Fixture\n\n- **Backlog backend**: Jira\n' > "$_rt_tmp/CLAUDE.md"
      # H-2/F-11 (TBG-READER-FLAGS-LIST T4): the head is a CALLER ASSERTION passed as tracker-read.sh's
      # 5th positional arg — there is no internal `git rev-parse HEAD` fallback any more (the internal
      # derivation was the H-2 replay hole; a base checkout cannot derive the subject's head).
      # This is a fixed, valid, non-zero sha the trusted job would have fetched, asserted verbatim.
      _rt_head="1111111111111111111111111111111111111111"
      _rt_rc=0
      KIT_TRACKER_USER="user@example.com" KIT_TRACKER_TOKEN="s3cr3t" \
        sh "$_rt_tmp/scripts/tracker-read.sh" "$_rt_tmp/.kit/tracker.conf" - "$_rt_tmp/record.txt" AB-1 "$_rt_head" >/dev/null 2>&1 || _rt_rc=$?
      [ "$_rt_rc" -eq 0 ] && grep -q '^verdict bound$' "$_rt_tmp/record.txt" 2>/dev/null \
        || { echo "selftest FAIL: H-1 round-trip — the real tracker-read.sh writer did not produce a bound record (rc=$_rt_rc)"; exit 1; }
      grep -q "^head $_rt_head\$" "$_rt_tmp/record.txt" 2>/dev/null \
        || { echo "selftest FAIL: H-1 round-trip — expected the caller-asserted head verbatim, got: $(cat "$_rt_tmp/record.txt")"; exit 1; }
      SEAM_ROOT="$_rt_tmp"; SEAM_RECORD="$_rt_tmp/record.txt"; SEAM_HEAD="$_rt_head"
      _rt_c=$(seam_row_count AB-1 2>/dev/null) || { echo "selftest FAIL: H-1 round-trip — seam_row_count did not bind on the real writer's output"; exit 1; }
      [ "$_rt_c" = "1" ] || { echo "selftest FAIL: H-1 round-trip — seam_row_count returned '$_rt_c', want 1"; exit 1; }
      _rt_s=$(seam_row_state AB-1 2>/dev/null) || { echo "selftest FAIL: H-1 round-trip — seam_row_state did not bind"; exit 1; }
      [ "$_rt_s" = "in-progress" ] || { echo "selftest FAIL: H-1 round-trip — seam_row_state returned '$_rt_s', want in-progress"; exit 1; }
      exit 0
    ) || st_fail=1

    # --- TBG-READER-FLAGS-LIST T7: the seam's live tracker answers ------------------------------
    # seam_row_flag / seam_rows_in_state, on the SAME good multi-row/multi-list record T6a/T6b
    # already established ($_st_mr_rec / $_st_mr_body: project AB, subject AB-7 state=in-progress
    # claimed=yes, AB-12/AB-31 state=ready with dor-*, `list ready AB-12 AB-31` / `list in-progress
    # AB-7`).

    # Leg 1 — a NON-subject id's flag (AB-12's dor-size=no) binds. Proves this arm carries no
    # subject check at all (§3d: the flag/list arms never get the relaxed subject check the
    # subject-keyed arms carry) — a mutant enforcing requested==id here would refuse this leg.
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_rec"; SEAM_HEAD="$_st_trkhead"
    _st_t7_v=$(seam_row_flag AB-12 dor-size 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 0 ] && [ "$_st_t7_v" = "no" ] \
      || { echo "selftest FAIL: T7 leg1 — seam_row_flag AB-12 dor-size must bind 'no' (non-subject id), got rc=$_st_t7_rc val=$_st_t7_v"; st_fail=1; }

    # Leg 2 — the subject's own flag (AB-7 claimed=yes) binds.
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_rec"; SEAM_HEAD="$_st_trkhead"
    _st_t7_v=$(seam_row_flag AB-7 claimed 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 0 ] && [ "$_st_t7_v" = "yes" ] \
      || { echo "selftest FAIL: T7 leg2 — seam_row_flag AB-7 claimed must bind 'yes', got rc=$_st_t7_rc val=$_st_t7_v"; st_fail=1; }

    # Leg 3 — a flag the row does not carry at all (AB-7's row has no dor-risk token) -> rc2,
    # empty stdout (M-5: never `n/a` for an ABSENT flag — `n/a` is reserved for a literal value).
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_rec"; SEAM_HEAD="$_st_trkhead"
    _st_t7_v=$(seam_row_flag AB-7 dor-risk 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 2 ] && [ -z "$_st_t7_v" ] \
      || { echo "selftest FAIL: T7 leg3 — seam_row_flag AB-7 dor-risk (absent flag) must rc2 empty (M-5), got rc=$_st_t7_rc val=$_st_t7_v"; st_fail=1; }

    # Leg 4 — a LITERAL `dor-risk=n/a` on a row binds 'n/a' (the parser accepts the literal per
    # §4.3's grammar; the answer is honest — never confused with leg3's ABSENT-flag rc2).
    _st_t7_narec="$LS_FXDIR/tracker-record-t7-na.txt"
    printf '%s\n' "$_st_mr_body" | sed 's/^row AB-12 state=ready dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes$/row AB-12 state=ready dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=n\/a/' > "$_st_t7_narec"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_t7_narec"; SEAM_HEAD="$_st_trkhead"
    _st_t7_v=$(seam_row_flag AB-12 dor-risk 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 0 ] && [ "$_st_t7_v" = "n/a" ] \
      || { echo "selftest FAIL: T7 leg4 — seam_row_flag AB-12 dor-risk with a literal =n/a must bind 'n/a', got rc=$_st_t7_rc val=$_st_t7_v"; st_fail=1; }

    # Leg 5 (fix1 R1) — an id not in the record at all -> rc2 UNVERIFIED, empty stdout. A tracker
    # record is a partial read (the subject + the listed ids), so an absent id means "not read" —
    # rc1 stays reserved for grammar/mapping refusals (leg6's unknown flag name, leg9c's unknown
    # state), never for "not read".
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_rec"; SEAM_HEAD="$_st_trkhead"
    _st_t7_v=$(seam_row_flag AB-999 claimed 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 2 ] && [ -z "$_st_t7_v" ] \
      || { echo "selftest FAIL: T7-fix1 leg5 (R1) — seam_row_flag AB-999 claimed (id absent) must rc2 empty, got rc=$_st_t7_rc val=$_st_t7_v"; st_fail=1; }

    # Leg 5b (fix1 F-1/R1, Important 1) — pr-bound on an id not in the record at all -> rc2 empty
    # too, never the old n/a-regardless-of-id answer: the absent-id check must run BEFORE the
    # pr-bound special case, so pr-bound is not exempt from R1 either (applies to EVERY flag).
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_rec"; SEAM_HEAD="$_st_trkhead"
    _st_t7_v=$(seam_row_flag AB-999 pr-bound 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 2 ] && [ -z "$_st_t7_v" ] \
      || { echo "selftest FAIL: T7-fix1 leg5b (R1) — seam_row_flag AB-999 pr-bound (id absent) must rc2 empty, got rc=$_st_t7_rc val=$_st_t7_v"; st_fail=1; }

    # Leg 6 — a flag name outside the closed §4.2 set -> rc1 (never a lookup at all).
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_rec"; SEAM_HEAD="$_st_trkhead"
    _st_t7_v=$(seam_row_flag AB-7 bogus 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 1 ] && [ -z "$_st_t7_v" ] \
      || { echo "selftest FAIL: T7 leg6 — seam_row_flag AB-7 bogus (unknown flag name) must rc1 empty, got rc=$_st_t7_rc val=$_st_t7_v"; st_fail=1; }

    # Leg 7 — pr-bound on a tracker record -> n/a, rc0 (§4.2: always answered from the Kit-Row
    # trailer on a tracker, never a record lookup — backlog-presence uses state+claimed instead).
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_rec"; SEAM_HEAD="$_st_trkhead"
    _st_t7_v=$(seam_row_flag AB-7 pr-bound 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 0 ] && [ "$_st_t7_v" = "n/a" ] \
      || { echo "selftest FAIL: T7 leg7 — seam_row_flag AB-7 pr-bound must bind 'n/a' on a tracker, got rc=$_st_t7_rc val=$_st_t7_v"; st_fail=1; }

    # Leg 7b (fix1 F-2/R2) — `mine` on a tracker always refuses (rc2), explicit, fail-closed:
    # §4.2 "local only — CI never knows who 'me' is" — a gate reading `n/a` on an ownership check
    # could pass open, so `mine` is never folded into the generic per-row lookup. The refusal must
    # name "local only" on stderr (captured separately, `2>&1 >/dev/null` per the kit's own
    # stderr-only capture idiom).
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_rec"; SEAM_HEAD="$_st_trkhead"
    _st_t7_v=$(seam_row_flag AB-7 mine 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 2 ] && [ -z "$_st_t7_v" ] \
      || { echo "selftest FAIL: T7-fix1 leg7b (R2) — seam_row_flag AB-7 mine must rc2 empty, got rc=$_st_t7_rc val=$_st_t7_v"; st_fail=1; }
    seam_row_flag AB-7 mine 2>&1 >/dev/null | grep -Fq 'local only' \
      || { echo "selftest FAIL: T7-fix1 leg7b (R2) — seam_row_flag AB-7 mine's refusal must name 'local only' on stderr"; st_fail=1; }

    # Leg 8 — seam_rows_in_state ready -> the listed ids, one per line, IN LIST ORDER, rc0.
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_mr_rec"; SEAM_HEAD="$_st_trkhead"
    _st_t7_ris=$(seam_rows_in_state ready 2>/dev/null) && _st_t7_risrc=0 || _st_t7_risrc=$?
    [ "$_st_t7_risrc" -eq 0 ] && [ "$_st_t7_ris" = "AB-12
AB-31" ] \
      || { echo "selftest FAIL: T7 leg8 — seam_rows_in_state ready must list AB-12 then AB-31 in order, got rc=$_st_t7_risrc val=<$_st_t7_ris>"; st_fail=1; }

    # Leg 9a — a PRESENT list with ZERO ids ('list in-review' with no trailing ids) -> empty
    # stdout, rc0 (the one legal empty, §4.2).
    _st_t7_zerorec="$LS_FXDIR/tracker-record-t7-zerolist.txt"
    { printf '%s\n' "$_st_mr_body"; printf 'list in-review\n'; } > "$_st_t7_zerorec"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_t7_zerorec"; SEAM_HEAD="$_st_trkhead"
    _st_t7_z=$(seam_rows_in_state in-review 2>/dev/null) && _st_t7_zrc=0 || _st_t7_zrc=$?
    [ "$_st_t7_zrc" -eq 0 ] && [ -z "$_st_t7_z" ] \
      || { echo "selftest FAIL: T7 leg9a — seam_rows_in_state in-review (present, zero ids) must be empty rc0, got rc=$_st_t7_zrc val=<$_st_t7_z>"; st_fail=1; }

    # Leg 9b — a state with NO list line at all (done, on the SAME record) -> rc2 (H-3: never
    # folded into the same empty-rc0 answer as 9a — presence, not mere absence-of-ids, is what
    # legalises the empty).
    _st_t7_v=$(seam_rows_in_state "done" 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 2 ] && [ -z "$_st_t7_v" ] \
      || { echo "selftest FAIL: T7 leg9b — seam_rows_in_state done (no list line at all) must rc2 empty (H-3), got rc=$_st_t7_rc val=<$_st_t7_v>"; st_fail=1; }

    # Leg 9c — a state outside the closed §4.1 set -> rc1, whatever the record says.
    _st_t7_v=$(seam_rows_in_state bogus 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 1 ] && [ -z "$_st_t7_v" ] \
      || { echo "selftest FAIL: T7 leg9c — seam_rows_in_state bogus (outside §4.1) must rc1 empty, got rc=$_st_t7_rc val=<$_st_t7_v>"; st_fail=1; }

    # T89s leg1 (item 1, T7 seat L-2) — the state gate was a SUBSTRING membership over " $tokens ",
    # so a caller-supplied argument spanning two adjacent tokens (`ready in-progress`, one quoted
    # arg) read as a literal match and bypassed the vocabulary gate straight into a real record
    # load — same class tr_valid_state (tracker-read.sh F-2) already closed on the adapter twin.
    # Both examples must refuse rc1, exactly like leg9c's plain "bogus": a concatenation of two
    # valid tokens, and "in" (a substring shared by in-progress/in-review — never itself a token).
    _st_t7_v=$(seam_rows_in_state "ready in-progress" 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 1 ] && [ -z "$_st_t7_v" ] \
      || { echo "selftest FAIL: T89s leg1a — seam_rows_in_state 'ready in-progress' (concatenation) must rc1 empty, got rc=$_st_t7_rc val=<$_st_t7_v>"; st_fail=1; }
    _st_t7_v=$(seam_rows_in_state "in" 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 1 ] && [ -z "$_st_t7_v" ] \
      || { echo "selftest FAIL: T89s leg1b — seam_rows_in_state 'in' (substring of two tokens) must rc1 empty, got rc=$_st_t7_rc val=<$_st_t7_v>"; st_fail=1; }

    # Leg 10 — `verdict unverified` on an otherwise-sound/consistent record -> BOTH arms rc2, empty
    # stdout (neither ever answers on an unbound read, whatever the record structurally contains).
    _st_t7_unvrec="$LS_FXDIR/tracker-record-t7-unverified.txt"
    printf '%s\n' "$_st_mr_body" | sed 's/^verdict bound$/verdict unverified/' > "$_st_t7_unvrec"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_t7_unvrec"; SEAM_HEAD="$_st_trkhead"
    _st_t7_v=$(seam_row_flag AB-7 claimed 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 2 ] && [ -z "$_st_t7_v" ] \
      || { echo "selftest FAIL: T7 leg10 — seam_row_flag on verdict-unverified must rc2 empty, got rc=$_st_t7_rc val=<$_st_t7_v>"; st_fail=1; }
    _st_t7_v=$(seam_rows_in_state ready 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 2 ] && [ -z "$_st_t7_v" ] \
      || { echo "selftest FAIL: T7 leg10 — seam_rows_in_state on verdict-unverified must rc2 empty, got rc=$_st_t7_rc val=<$_st_t7_v>"; st_fail=1; }

    # Leg 11 — a record the PARSER ITSELF refuses (a duplicate row id, the §3b bijection's own
    # refusal — the same shape T6a leg3 already proves red) -> BOTH arms rc2, empty stdout.
    _st_t7_refrec="$LS_FXDIR/tracker-record-t7-refused.txt"
    { printf '%s\n' "$_st_mr_body"; printf 'row AB-12 state=ready dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes\n'; } > "$_st_t7_refrec"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_t7_refrec"; SEAM_HEAD="$_st_trkhead"
    _st_t7_v=$(seam_row_flag AB-7 claimed 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 2 ] && [ -z "$_st_t7_v" ] \
      || { echo "selftest FAIL: T7 leg11 — seam_row_flag on a parser-refused record must rc2 empty, got rc=$_st_t7_rc val=<$_st_t7_v>"; st_fail=1; }
    _st_t7_v=$(seam_rows_in_state ready 2>/dev/null) && _st_t7_rc=0 || _st_t7_rc=$?
    [ "$_st_t7_rc" -eq 2 ] && [ -z "$_st_t7_v" ] \
      || { echo "selftest FAIL: T7 leg11 — seam_rows_in_state on a parser-refused record must rc2 empty, got rc=$_st_t7_rc val=<$_st_t7_v>"; st_fail=1; }

    # T89s leg2 (item 2, T4 seat M-1, the seam twin) — the pin/head hex checks use `[0-9a-f]`
    # bracket ranges; measured (T2a's pattern) that under LC_ALL=en_US.UTF-8 macOS `sh`/`bash`
    # collate the range to ALSO match uppercase, so a head ending in uppercase 'A' is wrongly
    # ACCEPTED as hex — a caller-locale-dependent verdict on a security-relevant grammar gate.
    # A fresh sh/dash/bash process, via `<interp> -c CODE "$DIR/conformance/loop-state.sh" …` so
    # $0 still resolves the kit root the way backlog-lib.sh's own pin check needs (mirrors
    # tracker-read.sh's 0a locale-leg pattern, generalised for a sourced library's $0 dependency).
    _st_t89s_lchead="111111111111111111111111111111111111111A"
    _st_t89s_lcrec="$LS_FXDIR/tracker-record-t89s-locale.txt"
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_st_trkpin"
      echo "head $_st_t89s_lchead"
      echo "requested AB-1"
      echo "read-day $_st_trktoday"
      echo "credential ok"
      echo "verdict bound"
      echo "row AB-1 state=in-progress"
    } > "$_st_t89s_lcrec"
    _st_t89s_lccode='. "$1"; SEAM_ROOT="$2"; SEAM_RECORD="$3"; SEAM_HEAD="$4"; seam_row_count AB-1 >/dev/null 2>&1; exit $?'
    _st_t89s_lc_rc=0
    LC_ALL=en_US.UTF-8 sh -c "$_st_t89s_lccode" "$DIR/conformance/loop-state.sh" "$DIR/conformance/backlog-lib.sh" "$_st_trk" "$_st_t89s_lcrec" "$_st_t89s_lchead" >/dev/null 2>&1 || _st_t89s_lc_rc=$?
    _st_t89s_lc_sh_ok=0; [ "$_st_t89s_lc_rc" -ne 0 ] && _st_t89s_lc_sh_ok=1
    _st_t89s_lc_dash_note=""
    if command -v dash >/dev/null 2>&1; then
      _st_t89s_lc_rc=0
      LC_ALL=en_US.UTF-8 dash -c "$_st_t89s_lccode" "$DIR/conformance/loop-state.sh" "$DIR/conformance/backlog-lib.sh" "$_st_trk" "$_st_t89s_lcrec" "$_st_t89s_lchead" >/dev/null 2>&1 || _st_t89s_lc_rc=$?
      _st_t89s_lc_dash_ok=0; [ "$_st_t89s_lc_rc" -ne 0 ] && _st_t89s_lc_dash_ok=1
    else
      _st_t89s_lc_dash_ok=1; _st_t89s_lc_dash_note=" (dash arm SKIPPED — UNVERIFIED: no dash on PATH)"
    fi
    _st_t89s_lc_bash_note=""
    if command -v bash >/dev/null 2>&1; then
      _st_t89s_lc_rc=0
      LC_ALL=en_US.UTF-8 bash -c "$_st_t89s_lccode" "$DIR/conformance/loop-state.sh" "$DIR/conformance/backlog-lib.sh" "$_st_trk" "$_st_t89s_lcrec" "$_st_t89s_lchead" >/dev/null 2>&1 || _st_t89s_lc_rc=$?
      _st_t89s_lc_bash_ok=0; [ "$_st_t89s_lc_rc" -ne 0 ] && _st_t89s_lc_bash_ok=1
    else
      _st_t89s_lc_bash_ok=1; _st_t89s_lc_bash_note=" (bash arm SKIPPED — UNVERIFIED: no bash on PATH)"
    fi
    _st_t89s_lc_locale_note=""
    if ! command -v locale >/dev/null 2>&1 || ! locale -a 2>/dev/null | grep -qi '^en_us\.utf-\?8$'; then
      _st_t89s_lc_locale_note=" (locale UNVERIFIED — en_US.UTF-8 not in \`locale -a\`)"
    fi
    if [ "$_st_t89s_lc_sh_ok" -eq 1 ] && [ "$_st_t89s_lc_dash_ok" -eq 1 ] && [ "$_st_t89s_lc_bash_ok" -eq 1 ]; then
      echo "selftest PASS: T89s leg2 — a record head ending in uppercase 'A' refuses under LC_ALL=en_US.UTF-8 on a fresh sh AND dash AND bash process${_st_t89s_lc_dash_note}${_st_t89s_lc_bash_note}${_st_t89s_lc_locale_note}"
    else
      echo "selftest FAIL: T89s leg2 — the uppercase-A head was not refused under LC_ALL=en_US.UTF-8 (sh_ok=$_st_t89s_lc_sh_ok dash_ok=$_st_t89s_lc_dash_ok bash_ok=$_st_t89s_lc_bash_ok)"; st_fail=1
    fi

    # T89s leg4 (item 4, T7 seat M-1) — the parse memo: `_seam_record_load` must skip the re-parse
    # ONLY when SEAM_RECORD/SEAM_ROOT/SEAM_HEAD and the record file's own sha256 all still match
    # the last rc-0 load; ANY change forces a reload, and a failed load is never itself cached.
    # EVERY call below asserts `_seam_record_load` DIRECTLY, PLAIN (`cmd && rc=0 || rc=$?`, T6a
    # leg2's own idiom) — never through a wrapper's stdout, and never `$(...)`, which forks a
    # subshell whose memo-global writes are discarded the instant it exits (the file's own
    # :484-494 dead end); going through `seam_row_state` would also let its OWN downstream
    # `_SRV_REQUESTED`/verdict checks mask a memo bug that still leaves `_seam_record_load` wrongly
    # rc0 (measured: exactly this happened when leg4c first went through the wrapper).
    _SRV_MEMO_OK=0
    _st_t89s_memorec="$LS_FXDIR/tracker-record-t89s-memo.txt"
    _st_t89s_memohead="2222222222222222222222222222222222222222"
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_st_trkpin"
      echo "head $_st_t89s_memohead"
      echo "requested AB-1"
      echo "read-day $_st_trktoday"
      echo "credential ok"
      echo "verdict bound"
      echo "row AB-1 state=in-progress"
    } > "$_st_t89s_memorec"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_t89s_memorec"; SEAM_HEAD="$_st_t89s_memohead"
    _seam_record_load >/dev/null 2>&1 && _st_t89s_rc=0 || _st_t89s_rc=$?
    [ "$_st_t89s_rc" -eq 0 ] && [ "$_SRV_ROWSTATE" = "in-progress" ] \
      || { echo "selftest FAIL: T89s leg4 setup — the first load must BIND in-progress, got rc=$_st_t89s_rc val=<$_SRV_ROWSTATE>"; st_fail=1; }

    # leg4a — rewrite the SAME path's bytes (path/root/head all unchanged); the second call must
    # see the NEW content, never a stale memo hit keyed only on the unchanged path/root/head.
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_st_trkpin"
      echo "head $_st_t89s_memohead"
      echo "requested AB-1"
      echo "read-day $_st_trktoday"
      echo "credential ok"
      echo "verdict bound"
      echo "row AB-1 state=done"
    } > "$_st_t89s_memorec"
    _seam_record_load >/dev/null 2>&1 && _st_t89s_rc=0 || _st_t89s_rc=$?
    [ "$_st_t89s_rc" -eq 0 ] && [ "$_SRV_ROWSTATE" = "done" ] \
      || { echo "selftest FAIL: T89s leg4a — a record rewritten between calls must be re-read (new state), got rc=$_st_t89s_rc val=<$_SRV_ROWSTATE>"; st_fail=1; }

    # leg4b — SEAM_HEAD changed between calls (bytes unchanged) forces a reload; the record's own
    # `head` line no longer matches SEAM_HEAD, so the reload must now refuse.
    SEAM_HEAD="3333333333333333333333333333333333333333"
    _seam_record_load >/dev/null 2>&1 && _st_t89s_rc=0 || _st_t89s_rc=$?
    [ "$_st_t89s_rc" -eq 2 ] && [ -z "$_SRV_ROWSTATE" ] \
      || { echo "selftest FAIL: T89s leg4b — a changed SEAM_HEAD must force a reload and refuse (mismatched head), got rc=$_st_t89s_rc val=<$_SRV_ROWSTATE>"; st_fail=1; }

    # leg4c — a failed load is NEVER cached: repeating the SAME still-wrong SEAM_HEAD unchanged
    # must refuse again (rc2, and the globals cleared), not take a memo shortcut that turns the
    # prior failure into a bare rc0 success.
    _seam_record_load >/dev/null 2>&1 && _st_t89s_rc=0 || _st_t89s_rc=$?
    [ "$_st_t89s_rc" -eq 2 ] && [ -z "$_SRV_ROWSTATE" ] \
      || { echo "selftest FAIL: T89s leg4c — a repeated still-failing call must not read a cached success, got rc=$_st_t89s_rc val=<$_SRV_ROWSTATE>"; st_fail=1; }

    # leg4d — restore the matching SEAM_HEAD (memo currently invalid from leg4c's refusal), reset
    # the test-only load counter, then call N times on one unchanged record: exactly ONE real
    # parse (the first, arming the memo), the rest are memo hits.
    SEAM_HEAD="$_st_t89s_memohead"
    SEAM_TEST_LOAD_COUNT=0
    _st_t89s_i=0
    while [ "$_st_t89s_i" -lt 5 ]; do
      _seam_record_load >/dev/null 2>&1
      _st_t89s_i=$((_st_t89s_i + 1))
    done
    [ "$SEAM_TEST_LOAD_COUNT" -eq 1 ] \
      || { echo "selftest FAIL: T89s leg4d — 5 calls on one unchanged record must parse exactly once, got $SEAM_TEST_LOAD_COUNT"; st_fail=1; }

    # T89s leg5 (item 5, T7 seat M-1) — the single-pass bijection scan: EVERY existing T6b/T7
    # bijection leg above (Leg0-9, T6b-fix1 Important 1/2, T7 Step 0's isolating leg) already
    # re-runs unchanged against the new _seam_bijection_scan and stays green (same accept/refuse
    # set) — this leg adds the ONE thing they don't cover: a timing bound at scale. A record with
    # 480 rows and 480 listed ids (measured: the old O(listed*rows) nested scan took ~2000ms for
    # this shape on this machine, the new O(listed+rows) awk pass ~6ms) must still load well under
    # a generous bound here, so the leg never flakes on a slower CI box.
    _st_t89s_bigrec="$LS_FXDIR/tracker-record-t89s-480.txt"
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_st_trkpin"
      echo "head $_st_trkhead"
      echo "requested AB-1"
      echo "read-day $_st_trktoday"
      echo "credential ok"
      echo "verdict bound"
      _st_t89s_bigi=1
      _st_t89s_bigids=""
      while [ "$_st_t89s_bigi" -le 480 ]; do
        echo "row AB-$_st_t89s_bigi state=ready"
        _st_t89s_bigids="$_st_t89s_bigids AB-$_st_t89s_bigi"
        _st_t89s_bigi=$((_st_t89s_bigi + 1))
      done
      _st_t89s_bigids=${_st_t89s_bigids# }
      echo "list ready $_st_t89s_bigids"
    } > "$_st_t89s_bigrec"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_t89s_bigrec"; SEAM_HEAD="$_st_trkhead"
    _st_t89s_bigt0=$(date -u +%s)
    _st_t89s_v=$(seam_row_count AB-1 2>/dev/null) && _st_t89s_rc=0 || _st_t89s_rc=$?
    _st_t89s_bigt1=$(date -u +%s)
    _st_t89s_bigelapsed=$((_st_t89s_bigt1 - _st_t89s_bigt0))
    [ "$_st_t89s_rc" -eq 0 ] && [ "$_st_t89s_v" = "1" ] && [ "$_st_t89s_bigelapsed" -le 10 ] \
      || { echo "selftest FAIL: T89s leg5 — 480 rows/480 listed ids must BIND under 10s (generous bound), got rc=$_st_t89s_rc val=<$_st_t89s_v> elapsed=${_st_t89s_bigelapsed}s"; st_fail=1; }

    # T89s-fix1 H1 (security HIGH) — the memo/answer globals are read before this process ever
    # sets them, so an env var exported before the library is sourced (GITHUB_ENV, a poisoned
    # profile) could pre-arm the memo and a parser-refused record would still answer bound. A
    # fresh sh/dash process exports the five memo vars + verdict=bound/requested/rowstate, THEN
    # sources the library and asks it about a garbage record via the real seam_row_state surface.
    _st_h1_garbage="$LS_FXDIR/tracker-record-t89s-fix1-h1-garbage.txt"
    printf 'not a real record\n' > "$_st_h1_garbage"
    _st_h1_sha=$( { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } < "$_st_h1_garbage" 2>/dev/null | awk '{print $1}')
    _st_h1_code='
lib="$1"; root="$2"; rec="$3"; head="$4"; sha="$5"
export _SRV_MEMO_OK=1 _SRV_MEMO_RECORD="$rec" _SRV_MEMO_ROOT="$root" _SRV_MEMO_HEAD="$head" _SRV_MEMO_SHA="$sha"
export _SRV_VERDICT=bound _SRV_REQUESTED=AB-1 _SRV_ROWSTATE=done
. "$lib"
SEAM_ROOT="$root"; SEAM_RECORD="$rec"; SEAM_HEAD="$head"
seam_row_state AB-1
exit $?
'
    _st_h1_out=$(sh -c "$_st_h1_code" "$DIR/conformance/loop-state.sh" "$DIR/conformance/backlog-lib.sh" "$_st_trk" "$_st_h1_garbage" "$_st_trkhead" "$_st_h1_sha" 2>/dev/null) && _st_h1_sh_rc=0 || _st_h1_sh_rc=$?
    [ "$_st_h1_sh_rc" -eq 2 ] && [ -z "$_st_h1_out" ] \
      || { echo "selftest FAIL: T89s-fix1 H1 (sh) — a pre-seeded memo + verdict=bound must not survive the file-scope reset, got rc=$_st_h1_sh_rc val=<$_st_h1_out>"; st_fail=1; }
    if command -v dash >/dev/null 2>&1; then
      _st_h1_out=$(dash -c "$_st_h1_code" "$DIR/conformance/loop-state.sh" "$DIR/conformance/backlog-lib.sh" "$_st_trk" "$_st_h1_garbage" "$_st_trkhead" "$_st_h1_sha" 2>/dev/null) && _st_h1_dash_rc=0 || _st_h1_dash_rc=$?
      [ "$_st_h1_dash_rc" -eq 2 ] && [ -z "$_st_h1_out" ] \
        || { echo "selftest FAIL: T89s-fix1 H1 (dash) — a pre-seeded memo must not survive the file-scope reset, got rc=$_st_h1_dash_rc val=<$_st_h1_out>"; st_fail=1; }
    fi

    # T89s-fix1 Q2 (quality blocking 2) — SEAM_ROOT and SEAM_RECORD are BOTH still part of the
    # memo key, but removing either comparison alone leaves the rest of the suite green; pin both.
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_t89s_memorec"; SEAM_HEAD="$_st_t89s_memohead"
    _seam_record_load >/dev/null 2>&1 && _st_t89s_rc=0 || _st_t89s_rc=$?
    [ "$_st_t89s_rc" -eq 0 ] \
      || { echo "selftest FAIL: T89s-fix1 Q2 setup — arming the memo on the known-good record must bind, got rc=$_st_t89s_rc"; st_fail=1; }

    # Q2a — switch SEAM_ROOT to a root whose tracker.conf pin cannot match this record (record
    # bytes/head unchanged): must reparse and refuse, never a stale hit keyed on the old root.
    _st_q2_altroot="$LS_FXDIR/tbg-fix1-q2-altroot"
    mkdir -p "$_st_q2_altroot/.kit"
    { cat "$_st_trkconf"; echo "# q2 differs"; } > "$_st_q2_altroot/.kit/tracker.conf"
    SEAM_ROOT="$_st_q2_altroot"
    _seam_record_load >/dev/null 2>&1 && _st_t89s_rc=0 || _st_t89s_rc=$?
    [ "$_st_t89s_rc" -eq 2 ] \
      || { echo "selftest FAIL: T89s-fix1 Q2a — a SEAM_ROOT switch to a pin-mismatched root must refuse (SEAM_ROOT pinned in the memo key), got rc=$_st_t89s_rc"; st_fail=1; }

    # Q2b — re-arm the memo, then point SEAM_RECORD at a byte-identical COPY under a NEW path: the
    # load counter must still increment (a real reparse), never a hit keyed on content alone.
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_t89s_memorec"; SEAM_HEAD="$_st_t89s_memohead"
    _seam_record_load >/dev/null 2>&1 && _st_t89s_rc=0 || _st_t89s_rc=$?
    [ "$_st_t89s_rc" -eq 0 ] \
      || { echo "selftest FAIL: T89s-fix1 Q2b setup — re-arming the memo must bind, got rc=$_st_t89s_rc"; st_fail=1; }
    _st_q2_copy="$LS_FXDIR/tracker-record-t89s-fix1-q2-copy.txt"
    cp "$_st_t89s_memorec" "$_st_q2_copy"
    SEAM_TEST_LOAD_COUNT=0
    SEAM_RECORD="$_st_q2_copy"
    _seam_record_load >/dev/null 2>&1 && _st_t89s_rc=0 || _st_t89s_rc=$?
    [ "$SEAM_TEST_LOAD_COUNT" -eq 1 ] \
      || { echo "selftest FAIL: T89s-fix1 Q2b — a byte-identical copy at a NEW path must still reparse (SEAM_RECORD pinned in the memo key), got count=$SEAM_TEST_LOAD_COUNT"; st_fail=1; }

    # T89s-fix1 H3 (security Low, hash-vs-parse window) — a COLD symlinked SEAM_RECORD is already
    # refused by the parser's own [ -L ] check, so that leg alone would be vacuous (green with or
    # without this fix). The real gap: memo state armed on a REGULAR file, then the SAME path is
    # swapped to a symlink pointing at a byte-identical file — a memo hit (matching sha, never
    # re-checking [ -L ]) would skip the parser's check entirely. Establish a real bind, THEN swap.
    _st_h3_path="$LS_FXDIR/tracker-record-t89s-fix1-h3.txt"
    cp "$_st_trkrec" "$_st_h3_path"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_st_h3_path"; SEAM_HEAD="$_st_trkhead"
    _seam_record_load >/dev/null 2>&1 && _st_t89s_rc=0 || _st_t89s_rc=$?
    [ "$_st_t89s_rc" -eq 0 ] \
      || { echo "selftest FAIL: T89s-fix1 H3 setup — the initial regular-file bind must succeed, got rc=$_st_t89s_rc"; st_fail=1; }
    _st_h3_real2="$LS_FXDIR/tracker-record-t89s-fix1-h3-real2.txt"
    cp "$_st_h3_path" "$_st_h3_real2"
    rm -f "$_st_h3_path"
    ln -s "$_st_h3_real2" "$_st_h3_path"
    _seam_record_load >/dev/null 2>&1 && _st_t89s_rc=0 || _st_t89s_rc=$?
    [ "$_st_t89s_rc" -eq 2 ] \
      || { echo "selftest FAIL: T89s-fix1 H3 — swapping the SAME path to a symlink over byte-identical content must refuse (a stale sha-only memo hit must not skip the parser's [ -L ] check), got rc=$_st_t89s_rc"; st_fail=1; }

    # T89s-fix1 L2 (security Medium, the locale class at the other sites) — the whole-line charset
    # gate and the backend grammar used bracket RANGES, which collate a Unicode letter (whole-line)
    # or an uppercase letter (backend, same class item2 already closed for pin/head) as "inside"
    # the range under LC_ALL=en_US.UTF-8; spelling both out closes it. Asserted by the STDERR
    # MESSAGE, not rc alone — either bug still refuses the whole record eventually (a later check
    # catches the fallout), but only the FIXED code names the right rule.
    _st_l2_code='
lib="$1"; root="$2"; rec="$3"; head="$4"
. "$lib"
SEAM_ROOT="$root"; SEAM_RECORD="$rec"; SEAM_HEAD="$head"
_seam_record_load 2>&1 1>/dev/null
'
    _st_l2_uline="$LS_FXDIR/tracker-record-t89s-fix1-l2-unicode.txt"
    printf 'kit-tracker-read 1\nbackend\303\251 jira\n' > "$_st_l2_uline"
    _st_l2_msg=$(LC_ALL=en_US.UTF-8 sh -c "$_st_l2_code" "$DIR/conformance/loop-state.sh" "$DIR/conformance/backlog-lib.sh" "$_st_trk" "$_st_l2_uline" "$_st_trkhead") || true
    _st_l2_sh_ok=0
    printf '%s' "$_st_l2_msg" | grep -Fq 'outside the closed charset' && _st_l2_sh_ok=1
    _st_l2_bash_note=""
    if command -v bash >/dev/null 2>&1; then
      _st_l2_msg=$(LC_ALL=en_US.UTF-8 bash -c "$_st_l2_code" "$DIR/conformance/loop-state.sh" "$DIR/conformance/backlog-lib.sh" "$_st_trk" "$_st_l2_uline" "$_st_trkhead") || true
      _st_l2_bash_ok=0
      printf '%s' "$_st_l2_msg" | grep -Fq 'outside the closed charset' && _st_l2_bash_ok=1
    else
      _st_l2_bash_ok=1; _st_l2_bash_note=" (bash arm SKIPPED — UNVERIFIED: no bash on PATH)"
    fi
    [ "$_st_l2_sh_ok" -eq 1 ] && [ "$_st_l2_bash_ok" -eq 1 ] \
      || { echo "selftest FAIL: T89s-fix1 L2a — a record key carrying a Unicode letter (é) must refuse via the whole-line charset gate under LC_ALL=en_US.UTF-8 on sh AND bash${_st_l2_bash_note}"; st_fail=1; }

    _st_l2_urec="$LS_FXDIR/tracker-record-t89s-fix1-l2-upper.txt"
    {
      echo "kit-tracker-read 1"
      echo "backend JIRA"
      echo "pin sha256:$_st_trkpin"
      echo "head $_st_trkhead"
      echo "requested AB-1"
      echo "read-day $_st_trktoday"
      echo "credential ok"
      echo "verdict bound"
      echo "row AB-1 state=in-progress"
    } > "$_st_l2_urec"
    _st_l2_msg=$(LC_ALL=en_US.UTF-8 sh -c "$_st_l2_code" "$DIR/conformance/loop-state.sh" "$DIR/conformance/backlog-lib.sh" "$_st_trk" "$_st_l2_urec" "$_st_trkhead") || true
    _st_l2_sh_ok=0
    printf '%s' "$_st_l2_msg" | grep -Fq 'key backend refused (malformed token)' && _st_l2_sh_ok=1
    _st_l2_bash_note=""
    if command -v bash >/dev/null 2>&1; then
      _st_l2_msg=$(LC_ALL=en_US.UTF-8 bash -c "$_st_l2_code" "$DIR/conformance/loop-state.sh" "$DIR/conformance/backlog-lib.sh" "$_st_trk" "$_st_l2_urec" "$_st_trkhead") || true
      _st_l2_bash_ok=0
      printf '%s' "$_st_l2_msg" | grep -Fq 'key backend refused (malformed token)' && _st_l2_bash_ok=1
    else
      _st_l2_bash_ok=1; _st_l2_bash_note=" (bash arm SKIPPED — UNVERIFIED: no bash on PATH)"
    fi
    [ "$_st_l2_sh_ok" -eq 1 ] && [ "$_st_l2_bash_ok" -eq 1 ] \
      || { echo "selftest FAIL: T89s-fix1 L2b — an uppercase backend value must refuse via the backend grammar under LC_ALL=en_US.UTF-8 on sh AND bash${_st_l2_bash_note}"; st_fail=1; }

    # T89s-fix1 M6 (quality minor, keep the reasons) — the single-pass bijection scan used to
    # collapse every rule to ONE generic sentence; each mutation below is the SAME fixture T6b's
    # own legs 1/2/3/Important-1a already construct, re-asserted here on the STDERR MESSAGE so an
    # operator can tell WHICH rule refused.
    _st_m6_msg() {   # $1 = record content, $2 = expected fixed-text substring, $3 = description
      _stm6_f="$LS_FXDIR/tracker-record-t89s-fix1-m6.txt"
      printf '%s' "$1" > "$_stm6_f"
      SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stm6_f"; SEAM_HEAD="$_st_trkhead"
      _stm6_msg=$(seam_row_count AB-7 2>&1 1>/dev/null) || true
      printf '%s' "$_stm6_msg" | grep -Fq "$2" \
        || { echo "selftest FAIL: T89s-fix1 M6 ($3) — expected the fixed sentence naming <$2>, got <$_stm6_msg>"; st_fail=1; }
    }
    _st_m6_msg "$(printf '%s\n' "$_st_mr_body" | sed 's/^list ready AB-12 AB-31$/list ready AB-12 AB-31 AB-99/')" \
      "a listed id names no row line" "norow, leg1's own fixture"
    _st_m6_msg "$(printf '%s\n' "$_st_mr_body" | sed 's/^row AB-12 state=ready dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes$/row AB-12 state=in-progress dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes/')" \
      "a row's state disagrees with the list it is listed under" "statemismatch, leg2's own fixture"
    _st_m6_msg "$(printf '%s\n' "$_st_mr_body" | sed 's/^list ready AB-12 AB-31$/list ready AB-12/')" \
      "a non-subject row appears in no list" "unlisted, leg3's own fixture"
    _st_m6_msg "$(printf '%s\n' "$_st_mr_body" | sed 's/^row AB-7 state=in-progress claimed=yes$/row AB-7 state=ready claimed=yes/
/^list in-progress AB-7$/d')" \
      "the subject's own state was listed but the subject id is absent from it" "iff, fix1-important1a's own fixture"
    unset -f _st_m6_msg

    # --- T7 (B9): Kit-Scope — the declared path set vs the measured changed set ----------------
    # Every leg runs against the fixture repo with the base PINNED, so none of them can be
    # satisfied (or falsified) by this tree's own branch topology.
    _st_scopebase_saved="$LS_SCOPE_BASEREF"
    LS_SCOPE_BASEREF="$LS_FX_SCOPEBASE"

    # POSITIVE — every changed path under the declared prefix passes.
    # ⚠️ rc IS NOT ENOUGH HERE, and that is measured: in observe mode (the default) an
    # always-UNCOVERED implementation also returns 0, so an rc-only positive would stay green while
    # the matcher never matched anything. The leg asserts the PASS DISCLOSURE, which only a real
    # match produces. An always-FAIL implementation breaks it from the other side.
    _st_scopeok=""
    _st_scopeok=$(check_scope "$LS_FX_SCOPE_IN" 2>&1) \
      || { echo "selftest FAIL: a change entirely inside the declared Kit-Scope must PASS"; st_fail=1; }
    case "$_st_scopeok" in
      *"changed path(s) graded; every changed path is under a declared scope token"*) ;;
      *) echo "selftest FAIL: a covered change must report the scope PASS with a graded-path count (got: $_st_scopeok)"; st_fail=1 ;;
    esac

    # DIAL LIVENESS — the same covered change under enforce must still pass. Without this, an
    # enforce arm that refuses EVERYTHING would satisfy the negative below and be worse than useless.
    # shellcheck disable=SC2034  # KIT_SCOPE_MODE is read indirectly (ls_dial_mode -> eval), so shellcheck cannot see the use
    ( KIT_SCOPE_MODE=enforce; check_scope "$LS_FX_SCOPE_IN" ) >/dev/null 2>&1 \
      || { echo "selftest FAIL: a covered change must pass even under KIT_SCOPE_MODE=enforce"; st_fail=1; }

    # THE LOAD-BEARING NEGATIVE — an escaping path under the enforce dial must FAIL.
    # ⚠️ The dial is set in a SUBSHELL, never as `VAR=x check_scope ...`: a variable assignment on a
    # FUNCTION call PERSISTS after the call in dash/POSIX sh, which would silently leak `enforce`
    # into every leg below and invert the observe leg's meaning.
    # shellcheck disable=SC2034  # KIT_SCOPE_MODE is read indirectly (ls_dial_mode -> eval), so shellcheck cannot see the use
    ( KIT_SCOPE_MODE=enforce; check_scope "$LS_FX_SCOPE_OUT" ) >/dev/null 2>&1 \
      && { echo "selftest FAIL: an escaping path under KIT_SCOPE_MODE=enforce must FAIL"; st_fail=1; }

    # OBSERVE (the shipped default) — the SAME fixture must keep rc 0 AND name the escaping path.
    # Both halves matter: rc-only would pass for an implementation that never detected anything,
    # and print-only would pass for one that refused. This is the leg that pins observe-first.
    _st_scoperc=0
    _st_scopeout=$( ( unset KIT_SCOPE_MODE; check_scope "$LS_FX_SCOPE_OUT" ) 2>&1 >/dev/null ) || _st_scoperc=$?
    if [ "$_st_scoperc" -ne 0 ]; then
      echo "selftest FAIL: an escaping path in OBSERVE mode must not change rc (observe-first)"; st_fail=1
    fi
    case "$_st_scopeout" in
      *"conformance/stray.sh"*) ;;
      *) echo "selftest FAIL: OBSERVE mode must NAME each escaping path (got: $_st_scopeout)"; st_fail=1 ;;
    esac

    # ABSENT trailer — N/A, never red, and the N/A is ANNOUNCED. A silent N/A is how a gate ends up
    # asserting more than it verified.
    _st_scopena=""
    _st_scopena=$(check_scope "$LS_FX_OK" 2>&1) \
      || { echo "selftest FAIL: an absent Kit-Scope must be N/A, never a RED"; st_fail=1; }
    case "$_st_scopena" in
      *"N/A (no scope declared)"*) ;;
      *) echo "selftest FAIL: an absent Kit-Scope must DISCLOSE its N/A"; st_fail=1 ;;
    esac

    # UNRESOLVABLE BASIS — a base ref that does not exist yields the disclosed N/A, rc 0 (the
    # shallow-clone / fresh-adopter shape), never a red and never a silent pass.
    LS_SCOPE_BASEREF="refs/heads/no-such-base-ref"
    _st_scopena=$(check_scope "$LS_FX_SCOPE_OUT" 2>&1) \
      || { echo "selftest FAIL: an unresolvable scope basis must be N/A, never a RED"; st_fail=1; }
    case "$_st_scopena" in
      *"N/A (scope basis unresolvable)"*) ;;
      *) echo "selftest FAIL: an unresolvable scope basis must DISCLOSE its N/A"; st_fail=1 ;;
    esac
    LS_SCOPE_BASEREF="$LS_FX_SCOPEBASE"

    # HOSTILE TOKENS + the duplicate key — REASON-BOUND, not outcome-only: these must be the ONLY
    # refusals on the boundary side of the ladder, so the forbidden string is the escape-branch
    # message. MEASURED, so the claim is not overstated: with the hostile arm neutered these three
    # fixtures do not merely refuse for the wrong reason, they stop refusing at all (the escape
    # branch keeps rc 0 in observe mode) — the helper catches that as "expected a refusal, but the
    # check PASSED". The forbidden half is the guard for the day the dial flips to enforce.
    ls_assert_reason "scope token: traversal" "is not a plain path token" "fall outside the declared" \
      check_scope "$LS_FX_SCOPE_DOTDOT" || st_fail=1
    ls_assert_reason "scope token: glob metacharacter" "is not a plain path token" "fall outside the declared" \
      check_scope "$LS_FX_SCOPE_GLOB" || st_fail=1
    ls_assert_reason "scope token: absolute path" "is not a plain path token" "fall outside the declared" \
      check_scope "$LS_FX_SCOPE_ABS" || st_fail=1
    ls_assert_reason "scope duplicate key" "occurrences of 'Kit-Scope'" "is not a plain path token" \
      check_scope "$LS_FX_SCOPE_DUP" || st_fail=1

    LS_SCOPE_BASEREF="$_st_scopebase_saved"

    # --- T7b (A4iv): scope_covers component-boundary match -------------------------------------
    # The tightening (ruling D-240811-2.1, B9 §10-A4iv): a declared token is a PATH-COMPONENT
    # boundary, not a raw string prefix. Pinned spec (design MEDIUM-4):
    #   * a token ending `/` covers ONLY paths strictly under it (`foo/` covers `foo/x`, NEVER the
    #     bare name `foo` — the one new-ESCAPE risk a normalize-to-exact mutant would open);
    #   * a token without `/` covers EXACT or `foo/`-prefixed (`foo` covers `foo` and `foo/x`) but
    #     NOT `foobar` (the false-cover the old plain-prefix permitted).
    # Each leg is a mutant kill: revert-to-plain-prefix re-covers `foobar`; normalize-`foo/`-to-exact
    # re-covers bare `foo`. Called under `set -f` to match check_scope's production noglob window.
    ( set -f; scope_covers "foo/x"  "foo/" ) || { echo "selftest FAIL: A4iv — 'foo/' must cover 'foo/x'"; st_fail=1; }
    ( set -f; scope_covers "foo"    "foo/" ) && { echo "selftest FAIL: A4iv — 'foo/' must NOT cover bare 'foo' (new-escape guard)"; st_fail=1; }
    ( set -f; scope_covers "foo"    "foo"  ) || { echo "selftest FAIL: A4iv — 'foo' must cover exact 'foo'"; st_fail=1; }
    ( set -f; scope_covers "foo/x"  "foo"  ) || { echo "selftest FAIL: A4iv — 'foo' must cover 'foo/x'"; st_fail=1; }
    ( set -f; scope_covers "foobar" "foo"  ) && { echo "selftest FAIL: A4iv — 'foo' must NOT cover 'foobar' (the tightening)"; st_fail=1; }

    # --- T7c (MEDIUM-2): ls_dial_mode precedence contract --------------------------------------
    # ls_dial_mode is a THIRD copy of the dial precedence (guard-core.sh:1861 kit_dial_mode and
    # dial-state.sh:43 dial_value are the siblings a gate MUST NOT source). This pins THIS copy
    # against the shared spec (it does NOT invoke the siblings — a spec-conformance test, not a live
    # cross-reader agreement leg): the conf value under $LS_REPO/.kit/dials.conf is
    # authoritative; env may ESCALATE observe->enforce but NEVER de-escalate a conf `enforce` (it
    # LOSES + one loud anomaly line); absent/garbage/missing-key => observe (fail-safe).
    # ⚠️ Every case drives the env in a SUBSHELL, never `VAR=x ls_dial_mode ...`: a var assignment
    # on a FUNCTION call PERSISTS in POSIX sh (the :1041 note) and would leak into the legs below.
    _st_drepo_saved="$LS_REPO"
    mkdir -p "$LS_FXDIR/dm-enforce/.kit" "$LS_FXDIR/dm-garbage/.kit" "$LS_FXDIR/dm-absent"
    printf 'KIT_SCOPE_MODE=enforce\n' > "$LS_FXDIR/dm-enforce/.kit/dials.conf"
    printf 'KIT_SCOPE_MODE=banana\n'  > "$LS_FXDIR/dm-garbage/.kit/dials.conf"

    LS_REPO="$LS_FXDIR/dm-enforce"
    [ "$( unset KIT_SCOPE_MODE; ls_dial_mode KIT_SCOPE_MODE 2>/dev/null )" = enforce ] \
      || { echo "selftest FAIL: dial — conf enforce (env unset) must read enforce"; st_fail=1; }
    # shellcheck disable=SC2034  # KIT_SCOPE_MODE is read indirectly (ls_dial_mode -> eval), so shellcheck cannot see the use
    [ "$( KIT_SCOPE_MODE=observe; ls_dial_mode KIT_SCOPE_MODE 2>/dev/null )" = enforce ] \
      || { echo "selftest FAIL: dial — env observe must NOT de-escalate a conf enforce"; st_fail=1; }
    # shellcheck disable=SC2034  # KIT_SCOPE_MODE is read indirectly (ls_dial_mode -> eval), so shellcheck cannot see the use
    _dm_out=$( KIT_SCOPE_MODE=observe; ls_dial_mode KIT_SCOPE_MODE 2>&1 >/dev/null )
    case "$_dm_out" in
      *"cannot de-escalate"*) ;;
      *) echo "selftest FAIL: dial — a de-escalation attempt must print one loud anomaly line"; st_fail=1 ;;
    esac
    # shellcheck disable=SC2034  # KIT_SCOPE_MODE is read indirectly (ls_dial_mode -> eval), so shellcheck cannot see the use
    _dm_out=$( KIT_SCOPE_MODE=enforce; ls_dial_mode KIT_SCOPE_MODE 2>&1 >/dev/null )
    case "$_dm_out" in
      *"cannot de-escalate"*) echo "selftest FAIL: dial — an equal env value must NOT warn"; st_fail=1 ;;
    esac

    LS_REPO="$LS_FXDIR/dm-absent"
    [ "$( unset KIT_SCOPE_MODE; ls_dial_mode KIT_SCOPE_MODE 2>/dev/null )" = observe ] \
      || { echo "selftest FAIL: dial — an absent conf must fail-safe to observe"; st_fail=1; }
    # shellcheck disable=SC2034  # KIT_SCOPE_MODE is read indirectly (ls_dial_mode -> eval), so shellcheck cannot see the use
    [ "$( KIT_SCOPE_MODE=enforce; ls_dial_mode KIT_SCOPE_MODE 2>/dev/null )" = enforce ] \
      || { echo "selftest FAIL: dial — env enforce must escalate observe->enforce"; st_fail=1; }

    LS_REPO="$LS_FXDIR/dm-garbage"
    [ "$( unset KIT_SCOPE_MODE; ls_dial_mode KIT_SCOPE_MODE 2>/dev/null )" = observe ] \
      || { echo "selftest FAIL: dial — a garbage conf value must read observe"; st_fail=1; }
    LS_REPO="$_st_drepo_saved"

    # --- T7d (A3i; I1/F4): the run_gate failure epilogue is scope-aware ------------------------
    # run_gate picks the epilogue via ls_scope_epilogue_mode from the two facts it already holds:
    # whether any NON-scope leg failed, and whether check_scope captured a REAL escape. Three modes:
    #   1 = a path ESCAPE was the sole failure  -> name the path(s), each through ls_safe;
    #   2 = a scope BOUNDARY refusal (hostile token / dup key) was the sole failure -> the trailers
    #       are valid AND no path escaped, so NEITHER the trailer contract NOR the escape claim (with
    #       its "SCOPE=enforce") may print. This is the I1 defect: a hostile-token refusal used to
    #       print "changed paths escape (SCOPE=enforce)" over an EMPTY path list, false under enforce
    #       and doubly false under observe (where the boundary refuses unconditionally);
    #   0 = a real Entry-Declaration defect -> the trailer contract.
    # THE DISCRIMINANT IS TESTED DIRECTLY — driving the whole run_gate is not hermetic (its check_class
    # leg derives class from the ambient tree; see ls_scope_epilogue_mode's note). The escape-vs-boundary
    # legs are the I1 mutant kill: the pre-fix logic set the flag purely on "scope was the only failing
    # leg", so it returned the escape mode for BOTH — the `0 '' -> 2` leg is RED before the fix, GREEN after.
    [ "$( ls_scope_epilogue_mode 0 'conformance/stray.sh' )" = 1 ] \
      || { echo "selftest FAIL: I1 — a captured escape as the sole failure must be epilogue mode 1"; st_fail=1; }
    [ "$( ls_scope_epilogue_mode 0 '' )" = 2 ] \
      || { echo "selftest FAIL: I1 — a scope-only refusal with NO captured escape must be mode 2, not a false escape"; st_fail=1; }
    [ "$( ls_scope_epilogue_mode 1 'conformance/stray.sh' )" = 0 ] \
      || { echo "selftest FAIL: I1 — a non-scope leg failure must be the trailer-contract mode 0"; st_fail=1; }

    # mode 1 — names the escaping path, does NOT print the trailer contract.
    _fe_scope=$( ls_fail_epilogue 1 deadbeef "conformance/stray.sh" 2>&1 )
    case "$_fe_scope" in
      *"conformance/stray.sh"*) ;;
      *) echo "selftest FAIL: A3i — a scope escape epilogue must NAME the escaping path"; st_fail=1 ;;
    esac
    case "$_fe_scope" in
      *"LAST paragraph"*) echo "selftest FAIL: A3i — a scope escape epilogue must NOT print the trailer contract"; st_fail=1 ;;
    esac

    # mode 2 — a boundary refusal: neither the false escape claim ("changed paths escape") nor its
    # false "SCOPE=enforce", and NOT the trailer contract (the trailers are valid). This is the leg
    # that catches the I1 mislabel end-to-end at the epilogue.
    _fe_bnd=$( ls_fail_epilogue 2 deadbeef "" 2>&1 )
    case "$_fe_bnd" in
      *"changed paths escape"*) echo "selftest FAIL: I1 — a boundary refusal must NOT claim the paths escaped the scope"; st_fail=1 ;;
    esac
    case "$_fe_bnd" in
      *"SCOPE=enforce"*) echo "selftest FAIL: I1 — a boundary refusal must NOT assert enforce mode (an export reads observe)"; st_fail=1 ;;
    esac
    case "$_fe_bnd" in
      *"LAST paragraph"*) echo "selftest FAIL: I1 — a boundary refusal must NOT print the trailer contract (trailers are valid)"; st_fail=1 ;;
    esac
    case "$_fe_bnd" in
      *"refused by the SCOPE leg"*) ;;
      *) echo "selftest FAIL: I1 — a boundary refusal must state it is the scope leg alone"; st_fail=1 ;;
    esac

    # mode 0 — the trailer contract, and NOT the scope escape epilogue.
    _fe_decl=$( ls_fail_epilogue 0 deadbeef "" 2>&1 )
    case "$_fe_decl" in
      *"LAST paragraph"*) ;;
      *) echo "selftest FAIL: A3i — a declaration failure must print the trailer contract"; st_fail=1 ;;
    esac
    case "$_fe_decl" in
      *"declares a Kit-Scope"*) echo "selftest FAIL: A3i — a declaration failure must NOT print the scope epilogue"; st_fail=1 ;;
    esac

    # --- MAP COMPLETENESS, drift directions (b) and (c) ---------------------------------------
    # Plan T1 step 4 required these and they were missing; review measured that gutting either
    # check left the suite GREEN. The code was right and nothing held it there.
    _st_conf_saved="$ROSTER_CONF"
    ROSTER_CONF="$LS_FXDIR/roster-ghost-skill.conf"
    map_completeness >/dev/null 2>&1 \
      && { echo "selftest FAIL: a map entry naming no skill on disk must FAIL"; st_fail=1; }
    ROSTER_CONF="$LS_FXDIR/roster-unmapped-stage.conf"
    map_completeness >/dev/null 2>&1 \
      && { echo "selftest FAIL: a stage in KIT_STAGES with no skill set must FAIL"; st_fail=1; }
    ROSTER_CONF="$_st_conf_saved"

    # --- REASON ASSERTIONS ---------------------------------------------------------------------
    # Review's 26-mutant single-mutation sweep measured FIVE legs passing for the WRONG reason: the
    # intended check could be neutered and a DIFFERENT check rejected the fixture, leaving the suite
    # green. An outcome-only leg structurally cannot catch that. These assert the REASON on stderr.
    # Third argument is the DOWNSTREAM reason that must NOT appear — see ls_assert_reason.
    ls_assert_reason "form rule (no skills/ prefix)" "must be of the form" "single path component" \
      check_skill "$LS_FX_BADFORM" || st_fail=1
    # ls_safe COVERAGE. The forbidden half is exactly the right instrument here: the ESC must not
    # survive into stderr. Replacing ls_safe with the identity function turns this leg RED — without
    # it the sanitiser was a security control with zero coverage.
    ls_assert_reason "form-error sanitises control chars" "must be of the form" "$(printf '\033')" \
      check_skill "$LS_FX_CTRL" || st_fail=1
    ls_assert_reason "single-component rule (traversal)" "single path component" "names no skill on disk" \
      check_skill "$LS_FX_TRAVERSAL" || st_fail=1
    ls_assert_reason "skill missing on disk" "names no skill on disk" "is not tracked" \
      check_skill "$LS_FX_NOSKILL" || st_fail=1
    ls_assert_reason "exactly-one occurrence" "occurrences of" "may contain only" \
      check_declaration "$LS_FX_DUP" || st_fail=1

    _st_skillrepo_saved2="$LS_SKILLREPO"
    LS_SKILLREPO="$LS_FXDIR"
    ls_assert_reason "symlink refusal (-L, not 'not tracked')" "is a symlink" "is not tracked" \
      check_skill "$LS_FX_SYMSKILL" || st_fail=1
    ls_assert_reason "untracked refusal" "is not tracked" "-" \
      check_skill "$LS_FX_UNTRACKED" || st_fail=1
    LS_SKILLREPO="$_st_skillrepo_saved2"

    # --- MAP FAIL-CLOSED (N2) ------------------------------------------------------------------
    # The header asserts "fails CLOSED on a missing or unreadable map" and nothing held it: review
    # measured both mutants surviving.
    # REASON-BOUND, not outcome-only. As first written these two were outcome-only and BOTH
    # survived their own mutants: neutering the empty-KIT_STAGES guard let drift-(a) reject the
    # fixture instead, and neutering the missing-map guard let the empty-KIT_STAGES guard reject it
    # — the exact "passed because a LATER check rejected the fixture" class, in legs added by the
    # same commit that introduced ls_assert_reason to close it.
    _st_conf_saved2="$ROSTER_CONF"
    ROSTER_CONF="$LS_FXDIR/roster-empty-stages.conf"
    ls_assert_reason "empty KIT_STAGES fails closed" "KIT_STAGES missing or empty" "absent from the map" \
      map_completeness || st_fail=1
    ROSTER_CONF="$LS_FXDIR/no-such-map.conf"
    ls_assert_reason "missing map fails closed" "map not found" "KIT_STAGES missing or empty" \
      map_completeness || st_fail=1
    ROSTER_CONF="$_st_conf_saved2"

    # --- K20: THE CONTROL-PLANE REFUSAL PRINTS THE STAGE->SKILL MAP ---------------------------
    # (c) A gated head missing Kit-Skill is refused. The refusal is the adopter's whole remedy
    # surface: without the map they must find .kit/roster.conf themselves, and the plan doc that
    # explains it is export-ignore'd. Assert EVERY stage name in KIT_STAGES reaches stderr — an
    # oracle over the whole map, not one sampled stage (a per-site leg would survive a truncation).
    _st_cpo=$(check_declaration "$LS_FX_NOSKILLKEY" control-plane 2>&1) && _st_cpr=0 || _st_cpr=$?
    [ "$_st_cpr" -ne 0 ] \
      || { echo "selftest FAIL: a control-plane head with no Kit-Skill must be REFUSED"; st_fail=1; }
    for _st_stg in $(conf_val KIT_STAGES); do
      case "$_st_cpo" in
        *"$_st_stg"*) : ;;
        *) echo "selftest FAIL: the missing-key refusal must print stage '$_st_stg' from the map"; st_fail=1 ;;
      esac
    done

    # (k) SANITISED. A roster stage name carrying a C0 byte must not put that byte on stderr —
    # stderr is the Actions log, where a line-start is a workflow command. Mutant: print without
    # ls_safe and this leg reds.
    _st_conf_saved3="$ROSTER_CONF"
    ROSTER_CONF="$LS_FXDIR/roster-ctrl-stage.conf"
    _st_cpo=$(check_declaration "$LS_FX_NOSKILLKEY" control-plane 2>&1) && _st_cpr=0 || _st_cpr=$?
    case "$_st_cpo" in
      *"Rev$(printf '\001')iew"*)
        echo "selftest FAIL: the stage-map print leaked a C0 byte from the roster to stderr"; st_fail=1 ;;
    esac
    case "$_st_cpo" in
      *"Review"*) : ;;                # `Rev\001iew` with the byte stripped — still readable
      *) echo "selftest FAIL: the stage-map print dropped the C0-bearing stage entirely"; st_fail=1 ;;
    esac
    ROSTER_CONF="$_st_conf_saved3"

    # --- CONTROL-PLANE POSITIVE ----------------------------------------------------------------
    # declared == derived == control-plane must PASS. This is the class where a false-RED is most
    # expensive and the only one of the three with no positive leg until now.
    check_class "$LS_FX_CPOK" "$_st_fxd/changed-controlplane.txt" >/dev/null 2>&1 \
      || { echo "selftest FAIL: declared control-plane == derived control-plane must PASS"; st_fail=1; }

    LS_REPO="$_st_repo_saved"
    ls_fx_cleanup
  fi

  # --- K20: --help prints the stage->skill map, and a bare invocation still refuses ---------------
  # POSITIVE: every token of the LIVE KIT_STAGES appears in the --help output and rc is 0 — keyed
  # on conf_val, so a --help that stopped reading the roster (or restated a stale copy) reds here.
  # NEGATIVE (load-bearing): no arguments must still exit 2 with the existing line, or adding a
  # help arm would have quietly turned "never defaults to HEAD" into a default.
  if _st_help=$(sh "$0" --help 2>&1); then _st_hrc=0; else _st_hrc=$?; fi
  _st_hmiss=""
  for _st_hs in $(conf_val KIT_STAGES); do
    printf '%s\n' "$_st_help" | grep -qF -- "$_st_hs" || _st_hmiss="$_st_hmiss $_st_hs"
  done
  if [ "$_st_hrc" -eq 0 ] && [ -z "$_st_hmiss" ] \
     && printf '%s\n' "$_st_help" | grep -qF -- "Stage -> skill map"; then
    echo "selftest PASS: --help prints the stage->skill map (every KIT_STAGES token present), rc 0"
  else
    echo "selftest FAIL: --help rc=$_st_hrc, stage(s) missing from the map output:${_st_hmiss:- none}"; st_fail=1
  fi
  if sh "$0" >/dev/null 2>&1; then
    echo "selftest FAIL: a bare invocation must exit 2, never default to HEAD"; st_fail=1
  else
    _st_brc=$?
    if [ "$_st_brc" -eq 2 ]; then
      echo "selftest PASS: a bare invocation still exits 2 (never defaults to HEAD)"
    else
      echo "selftest FAIL: a bare invocation exited $_st_brc, expected 2"; st_fail=1
    fi
  fi

  # --- LOOP-STATE-TRACKER-STEP-ASIDE T1 — the parser legs (design §2 RD-3, amendment A1 LS-D3) ---
  # T1-Q1 fix round 1: no selftest may write objects into $DIR's real repo (the prior `commit-tree`
  # block did, and aborted under a hermetic/unconfigured git identity — rc 128 "no email was
  # given").
  # T1 fix round 2 (BLOCKER): a bare `sh "$0" --head 0000...` subprocess makes rc 2 AMBIGUOUS —
  # run_gate ALSO returns rc 2 for a non-commit SHA ("is not a commit in this repository"), so
  # dropping the pair check, skipping the unknown-flag branch, or letting a repeated --head
  # silently overwrite would all still read as "rc 2" and the leg would pass for the WRONG reason.
  # Graded IN-PROCESS instead (as delegate/changed-after-flags already does): each leg calls
  # ls_parse_args directly in a subshell, exactly as a real invocation would reach it (before any
  # commit is ever read), and asserts BOTH the function's own rc AND its own stderr sentence — so
  # a sibling fault that happens to share the same rc cannot pass this leg.
  _st_pf_head="0000000000000000000000000000000000000000"

  # (half-args) only ONE of the pair -> rc 2, "must be given together", both directions.
  _st_ha1_err=$(ls_parse_args --head "$_st_pf_head" --base-dir /tmp/does-not-matter 2>&1 >/dev/null) && _st_ha1=0 || _st_ha1=$?
  if [ "$_st_ha1" -eq 2 ] && case "$_st_ha1_err" in *"must be given together"*) true ;; *) false ;; esac; then
    echo "selftest PASS: delegate/half-args: --base-dir alone -> rc 2, 'must be given together'"
  else
    echo "selftest FAIL: delegate/half-args: --base-dir alone rc=$_st_ha1 out='$_st_ha1_err', wanted rc 2 + 'must be given together'"; st_fail=1
  fi
  _st_ha2_err=$(ls_parse_args --head "$_st_pf_head" --live-contexts /tmp/does-not-matter 2>&1 >/dev/null) && _st_ha2=0 || _st_ha2=$?
  if [ "$_st_ha2" -eq 2 ] && case "$_st_ha2_err" in *"must be given together"*) true ;; *) false ;; esac; then
    echo "selftest PASS: delegate/half-args: --live-contexts alone -> rc 2, 'must be given together'"
  else
    echo "selftest FAIL: delegate/half-args: --live-contexts alone rc=$_st_ha2 out='$_st_ha2_err', wanted rc 2 + 'must be given together'"; st_fail=1
  fi

  # (unknown-flag) LS-D3: an unrecognised flag must refuse, never be silently dropped -> rc 2,
  # "unknown argument".
  _st_uf_err=$(ls_parse_args --head "$_st_pf_head" --frobnicate 2>&1 >/dev/null) && _st_uf=0 || _st_uf=$?
  if [ "$_st_uf" -eq 2 ] && case "$_st_uf_err" in *"unknown argument"*) true ;; *) false ;; esac; then
    echo "selftest PASS: delegate/unknown-flag: an unknown flag -> rc 2, 'unknown argument' (LS-D3)"
  else
    echo "selftest FAIL: delegate/unknown-flag: rc=$_st_uf out='$_st_uf_err', wanted rc 2 + 'unknown argument'"; st_fail=1
  fi

  # (dup-flag) each flag at most once -> rc 2, "given more than once".
  _st_df_err=$(ls_parse_args --head "$_st_pf_head" --head "$_st_pf_head" 2>&1 >/dev/null) && _st_df=0 || _st_df=$?
  if [ "$_st_df" -eq 2 ] && case "$_st_df_err" in *"given more than once"*) true ;; *) false ;; esac; then
    echo "selftest PASS: delegate/dup-flag: a repeated flag -> rc 2, 'given more than once'"
  else
    echo "selftest FAIL: delegate/dup-flag: rc=$_st_df out='$_st_df_err', wanted rc 2 + 'given more than once'"; st_fail=1
  fi

  # (changed-after-flags) LS-D3, T1-Q1(d)/Q2: `--changed` must reach the classifier no matter
  # where it falls among the other flags. Graded IN-PROCESS against `ls_parse_args` directly (no
  # subprocess, no repo object writes) — each order runs in a subshell so the parsed globals from
  # one order never leak into the next, and each asserts the parsed --changed/--base-dir/
  # --live-contexts globals equal the literal inputs given.
  _st_caf_c="/tmp/does-not-exist-changed-C"
  _st_caf_b="/tmp/does-not-exist-base-B"
  _st_caf_l="/tmp/does-not-exist-live-L"
  _st_caf_x="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

  _st_caf_check_order() {
    # runs in a subshell (command substitution below) so globals never leak between orders
    ls_parse_args "$@" || return 1
    [ "$_ls_p_changed" = "$_st_caf_c" ] || { echo "changed mismatch: got '$_ls_p_changed'"; return 1; }
    [ "$_ls_p_basedir" = "$_st_caf_b" ] || { echo "base-dir mismatch: got '$_ls_p_basedir'"; return 1; }
    [ "$_ls_p_livecontexts" = "$_st_caf_l" ] || { echo "live-contexts mismatch: got '$_ls_p_livecontexts'"; return 1; }
    return 0
  }

  _st_caf_err=$(_st_caf_check_order --head "$_st_caf_x" --changed "$_st_caf_c" --base-dir "$_st_caf_b" --live-contexts "$_st_caf_l" 2>&1)
  if [ $? -eq 0 ]; then
    echo "selftest PASS: delegate/changed-after-flags: order 1 (--head --changed --base-dir --live-contexts) parses all globals"
  else
    echo "selftest FAIL: delegate/changed-after-flags: order 1 failed: $_st_caf_err"; st_fail=1
  fi

  _st_caf_err=$(_st_caf_check_order --base-dir "$_st_caf_b" --live-contexts "$_st_caf_l" --head "$_st_caf_x" --changed "$_st_caf_c" 2>&1)
  if [ $? -eq 0 ]; then
    echo "selftest PASS: delegate/changed-after-flags: order 2 (--base-dir --live-contexts --head --changed) parses all globals"
  else
    echo "selftest FAIL: delegate/changed-after-flags: order 2 failed: $_st_caf_err"; st_fail=1
  fi

  _st_caf_err=$(_st_caf_check_order --changed "$_st_caf_c" --head "$_st_caf_x" --live-contexts "$_st_caf_l" --base-dir "$_st_caf_b" 2>&1)
  if [ $? -eq 0 ]; then
    echo "selftest PASS: delegate/changed-after-flags: order 3 (--changed --head --live-contexts --base-dir) parses all globals"
  else
    echo "selftest FAIL: delegate/changed-after-flags: order 3 failed: $_st_caf_err"; st_fail=1
  fi

  if [ "$st_fail" -ne 0 ]; then echo "loop-state --selftest: FAIL" >&2; return 1; fi
  echo "loop-state --selftest: OK"
  echo "  map        — positive; drift (a) skill-absent, (b) entry-with-no-skill, (c) unmapped-stage;"
  echo "               fail-closed on an empty KIT_STAGES and on a missing map"
  echo "  declaration— positives: conformant, single-key; negatives: no-decl, ancestor-only,"
  echo "               severed-block, bad-stage, duplicate-key, metachar-row"
  echo "  class      — positives: ordinary, control-plane; negatives: under-declared, over-declared"
  echo "  skill      — positives: real tree, fixture tree; negatives: stage-inappropriate,"
  echo "               nonexistent, traversal, tracked-symlink, untracked"
  echo "  row        — positive; negative; N/A routes: no-board, non-md backend, pristine template;"
  echo "               fail-closed on an unrecognised backend"
  echo "  scope      — positive (covered); negatives: escaping-path under enforce, duplicate key,"
  echo "               hostile tokens (traversal, glob metachar, absolute); observe keeps rc 0 and"
  echo "               NAMES the escaping path; N/A routes: no declaration, unresolvable basis"
  echo "  reasons    — 12 legs assert the refusal REASON (and the absence of the downstream reason),"
  echo "               so a leg cannot pass because a LATER check rejected the fixture"
  echo "  meta       — the reason-assertion helper is itself checked against 5 synthetic subjects,"
  echo "               because it is structurally invisible to the CI mutation sweep"
  return 0
}

# ls_assert_reason — assert a check FAILS *for the stated reason*, not merely that it fails.
#
# Defined BELOW the selftest() marker on purpose: the CI non-vacuity sweep mutates only lines
# BEFORE that marker, so a kill-assertion helper defined above it could itself be neutered and the
# whole suite would go vacuously green. (Banked: writing-conformance-check-selftests.)
ls_assert_reason() {   # $1 = label, $2 = expected substring, $3 = forbidden substring (or -), $4... = cmd
  _lar_label="$1"; _lar_pat="$2"; _lar_not="$3"; shift 3
  if _lar_err=$("$@" 2>&1 >/dev/null); then
    echo "selftest FAIL: $_lar_label — expected a refusal, but the check PASSED"
    return 1
  fi
  case "$_lar_err" in
    *"$_lar_pat"*) ;;
    *) echo "selftest FAIL: $_lar_label — refused for the WRONG reason."
       echo "  wanted stderr containing: $_lar_pat"
       echo "  got: $_lar_err"
       return 1 ;;
  esac
  # THE FORBIDDEN HALF closes a measured gaming vector: keep a branch's `echo` but drop its
  # `return 1`, and the refusal comes from a LATER check while the wanted string still appears —
  # the suite goes green with the named branch inert. A correct implementation returns at its own
  # branch, so the downstream reason NEVER appears; the mutant emits both.
  # ⚠️ NOT TAUTOLOGICAL — a mutant in which the forbidden string IS present was measured before
  # this assertion was written (the DRIFT-2b trap: a green `assert_lacks` can be vacuous).
  [ "$_lar_not" = "-" ] && return 0
  case "$_lar_err" in
    *"$_lar_not"*)
      echo "selftest FAIL: $_lar_label — the named branch did not cause the refusal."
      echo "  stderr also contains the DOWNSTREAM reason: $_lar_not"
      echo "  got: $_lar_err"
      return 1 ;;
  esac
  return 0
}

# ls_assert_reason_selfcheck — COVERAGE FOR THE COVERAGE MECHANISM.
#
# EIGHT legs depend on ls_assert_reason. Measured: it can be broken three ways and the entire suite
# still goes GREEN — make it always return 0, drop the forbidden half, or change `2>&1 >/dev/null`
# to `2>&1` so stdout is silently credited. That is a single point of failure with ZERO coverage,
# and the cause is structural: the helper sits below the selftest() marker so `non-vacuity.sh` will
# not neuter it — which also means the CI sweep cannot CHECK it.
#
# So the helper is exercised against synthetic commands whose behaviour is known. This passes on the
# as-shipped helper (every one of the five behaviours verified correct today) — it is a REGRESSION
# guard, not a fix for a live defect.
ls_assert_reason_selfcheck() {
  _lsc_fail=0
  # Synthetic subjects. Deliberately trivial so the only thing under test is the helper.
  # shellcheck disable=SC2329 # invoked indirectly — passed to ls_assert_reason and run as "$@"
  _sc_right()    { echo "the wanted reason" >&2; return 1; }
  # shellcheck disable=SC2329
  _sc_norefuse() { echo "the wanted reason" >&2; return 0; }
  # shellcheck disable=SC2329
  _sc_wrong()    { echo "some other reason" >&2; return 1; }
  # shellcheck disable=SC2329
  _sc_forbidden(){ echo "the wanted reason" >&2; echo "the downstream reason" >&2; return 1; }
  # shellcheck disable=SC2329
  _sc_stdout()   { echo "the wanted reason";     return 1; }

  ls_assert_reason "meta/right" "the wanted reason" "the downstream reason" _sc_right >/dev/null 2>&1 \
    || { echo "selftest FAIL: meta — a correct refusal must PASS the helper"; _lsc_fail=1; }
  ls_assert_reason "meta/norefuse" "the wanted reason" "-" _sc_norefuse >/dev/null 2>&1 \
    && { echo "selftest FAIL: meta — rc=0 must FAIL the helper (helper always-pass?)"; _lsc_fail=1; }
  ls_assert_reason "meta/wrong" "the wanted reason" "-" _sc_wrong >/dev/null 2>&1 \
    && { echo "selftest FAIL: meta — a WRONG reason must FAIL the helper"; _lsc_fail=1; }
  ls_assert_reason "meta/forbidden" "the wanted reason" "the downstream reason" _sc_forbidden >/dev/null 2>&1 \
    && { echo "selftest FAIL: meta — a present FORBIDDEN reason must FAIL (forbidden half dropped?)"; _lsc_fail=1; }
  # The subtle one: if the redirect order is flipped, stdout gets credited as a reason.
  ls_assert_reason "meta/stdout" "the wanted reason" "-" _sc_stdout >/dev/null 2>&1 \
    && { echo "selftest FAIL: meta — a reason on STDOUT must NOT be credited (2>&1 >/dev/null flipped?)"; _lsc_fail=1; }
  return "$_lsc_fail"
}

# run_gate — the whole floor against ONE commit. Every leg runs so the author sees every problem
# in one CI round rather than peeling them off one per push.
run_gate() {   # $1 = sha, [$2 = optional changed-listing path — TBG-TRUSTED-JOB fix-round H-2]
  # M-2 hygiene: KIT_TRACKER_RECORD maps to SEAM_RECORD ONLY here, on the local/hygiene path (no
  # distinct trusted job exists yet — that wiring is a later JOIN slice, design §8 honest ceiling).
  # backlog-lib.sh's tracker arm NEVER reads ${KIT_TRACKER_RECORD} itself — only $SEAM_RECORD, set
  # once, at this ONE call site, exactly as SEAM_ROOT already tracks LS_BOARDROOT.
  SEAM_RECORD="${KIT_TRACKER_RECORD:-}"
  _ls_bad=0
  _ls_nonscope_bad=0   # tracks whether ANY leg other than scope failed (the A3i discriminant input)
  git -C "$LS_REPO" cat-file -e "$1^{commit}" 2>/dev/null || {
    echo "loop-state: '$1' is not a commit in this repository" >&2; return 2; }
  map_completeness   || { _ls_bad=1; _ls_nonscope_bad=1; }
  # THE CLASSIFIER RUNS FIRST — it needs no trailers, so it can be hoisted ahead of the
  # declaration leg, and the declaration leg needs its answer to know what to require. A
  # derivation failure yields FAIL-SAFED, which ls_required_keys maps to the FULL set; check_class
  # independently reds on the same condition (fail-closed), so degradation never buys anything.
  # $2, when supplied, is a caller-built changed-listing (H-2): a BASE-ONLY checkout (the trusted
  # job) has no local diff, so the live git-diff-against-trunk derivation would otherwise read an
  # empty change-set and fail OPEN to `ordinary` rather than FAIL-SAFED.
  _ls_class=$(ls_class_for_required "${2:-}")
  check_declaration "$1" "$_ls_class" || { _ls_bad=1; _ls_nonscope_bad=1; }
  check_class       "$1" "" "$_ls_class" || { _ls_bad=1; _ls_nonscope_bad=1; }
  check_skill_if_present "$1" || { _ls_bad=1; _ls_nonscope_bad=1; }
  check_row         "$1" || { _ls_bad=1; _ls_nonscope_bad=1; }
  # B9: the scope leg. It runs inside the existing --head path, so the installed pre-push hook and
  # CI's bound gate both get it with ZERO wiring edits. It cannot change the rc of any commit that
  # carries no Kit-Scope trailer (the N/A arm), which is every PR shape that is green today. Runs
  # LAST so _ls_nonscope_bad already reflects every other leg when the scope-only flag is derived.
  _ls_scope_mode=0
  if ! check_scope "$1"; then
    _ls_bad=1
    # I1/F4: the epilogue mode is scope-ESCAPE (1) ONLY when a REAL escape was captured. A boundary
    # refusal (hostile token / duplicate Kit-Scope key) leaves LS_SCOPE_ESCAPED empty and gets mode 2
    # — NOT the false "changed paths escape (SCOPE=enforce)" with an empty path list (doubly false
    # under observe). Derived from the discriminant inputs, never parsed from LS_SCOPE_STATE.
    _ls_scope_mode=$(ls_scope_epilogue_mode "$_ls_nonscope_bad" "${LS_SCOPE_ESCAPED:-}")
  fi
  if [ "$_ls_bad" -ne 0 ]; then
    ls_fail_epilogue "$_ls_scope_mode" "$1" "${LS_SCOPE_ESCAPED:-}"
    return 1
  fi
  # The success line states EXACTLY what each leg established — never "all resolve". Security review
  # blocked an earlier version for printing "row, stage, class, skill all resolve" on a change whose
  # row was a single letter, or whose row leg never ran at all. A merge-blocking control that
  # overstates its own result is the failure this whole slice exists to prevent.
  echo "OK: loop-state — $1 carries a valid Entry Declaration."
  # THE REQUIRED SET IS PART OF THE VERDICT. An ordinary head is not asked for stage or skill, so
  # printing "stage + skill: resolved against the map" on one would claim a leg that never ran —
  # the exact overstatement security review blocked for the row leg (see below).
  echo "  class:         $_ls_class · required set: $(ls_required_keys "$_ls_class")"
  if [ "$(decl_count "$1" Kit-Stage)" -gt 0 ] || [ "$(decl_count "$1" Kit-Skill)" -gt 0 ]; then
    echo "  stage + skill: resolved against the map (for the fields present on this commit)"
  else
    echo "  stage + skill: NOT ASKED — ordinary class, and neither field carried a value"
  fi
  echo "  class check:   equals promotion-readiness --class"
  # ⚠️ THIS LINE IS PART OF THE VERDICT AND IT WENT STALE ONCE ALREADY. It used to read
  # "(guard-core scope; the adapter union is enforced by ratification.yml)", which stopped being true
  # the moment GUARD-PATH-ENUMERATION-INCOMPLETE S2 made `--class` union-aware — a merge-blocking
  # control describing its own scope wrongly, on the surface a human reads at the click. Keep it
  # honest in BOTH directions: what the equality now covers, and the one state where it does not.
  echo "                 (guard-core AND the adapter-declared union, when the union is derivable;"
  echo "                  with manifests present but unreadable the class fail-safes and says so)"
  echo "  row:           $LS_ROW_STATE"
  echo "  scope:         $LS_SCOPE_STATE"
  echo "                 (declaration<->diff consistency at THIS push; no ordering claim)"
  return 0
}

# --- dispatch ---
# LOOP-STATE-TRACKER-STEP-ASIDE T1 (design §2 RD-3, amendment A1 LS-D3): a REAL parser, a
# `while [ $# -gt 0 ]` loop, order-independent — today's dispatch (a single `case "${1:-}"` on the
# first token only) silently dropped an unknown argument placed after `--head SHA`, and losing the
# trusted job's own `--changed` that way hands the classifier an empty diff (the H-2 hazard this
# gate exists to avoid). Each flag is accepted AT MOST ONCE (a repeat is a usage anomaly, rc 2);
# an unrecognised flag is rc 2; `--base-dir` and `--live-contexts` must arrive as a PAIR.
# T1-Q1(c): the dispatch loop lives in a function, `ls_parse_args`, so the selftest can grade it
# either as a real subprocess (`sh "$0" ...`) or in-process (a direct call, in a subshell) without
# duplicating the parsing logic. No behaviour change: it sets the same globals it always did.
ls_parse_args() {
_ls_seen_selftest=0; _ls_seen_help=0; _ls_seen_head=0; _ls_seen_changed=0
_ls_seen_basedir=0; _ls_seen_livecontexts=0
_ls_p_head=""; _ls_p_changed=""; _ls_p_basedir=""; _ls_p_livecontexts=""
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest)
      if [ "$_ls_seen_selftest" -ne 0 ]; then
        echo "loop-state: --selftest given more than once" >&2
        exit 2
      fi
      _ls_seen_selftest=1
      shift
      ;;
    -h|--help)
      if [ "$_ls_seen_help" -ne 0 ]; then
        echo "loop-state: --help given more than once" >&2
        exit 2
      fi
      _ls_seen_help=1
      shift
      ;;
    --head)
      if [ "$_ls_seen_head" -ne 0 ]; then
        echo "loop-state: --head given more than once" >&2
        exit 2
      fi
      [ $# -ge 2 ] || { echo "loop-state: --head needs a SHA" >&2; exit 2; }
      _ls_seen_head=1
      _ls_p_head=$2
      shift 2
      ;;
    # --changed is OPTIONAL, trusted-job-only in practice (TBG-TRUSTED-JOB fix-round H-2): a
    # caller whose checkout is BASE ONLY (never the PR head/merge commit) has no local diff for
    # the class classifier to see, and promotion-readiness.sh's live git-diff-against-trunk
    # derivation over that tree reads as an EMPTY change-set — which fails OPEN to `ordinary`, not
    # FAIL-SAFED, silently under-requiring the trailer set for what may be a real control-plane
    # PR. This is NOT a general author-facing fixture flag (the file's own header above still
    # forbids that): the listing here is built by the CALLER from forge metadata (a base..head
    # compare), never author-supplied text.
    --changed)
      if [ "$_ls_seen_changed" -ne 0 ]; then
        echo "loop-state: --changed given more than once" >&2
        exit 2
      fi
      [ $# -ge 2 ] || { echo "loop-state: --changed needs a listing path" >&2; exit 2; }
      _ls_seen_changed=1
      _ls_p_changed=$2
      shift 2
      ;;
    --base-dir)
      if [ "$_ls_seen_basedir" -ne 0 ]; then
        echo "loop-state: --base-dir given more than once" >&2
        exit 2
      fi
      [ $# -ge 2 ] || { echo "loop-state: --base-dir needs a directory" >&2; exit 2; }
      _ls_seen_basedir=1
      _ls_p_basedir=$2
      shift 2
      ;;
    --live-contexts)
      if [ "$_ls_seen_livecontexts" -ne 0 ]; then
        echo "loop-state: --live-contexts given more than once" >&2
        exit 2
      fi
      [ $# -ge 2 ] || { echo "loop-state: --live-contexts needs a file" >&2; exit 2; }
      _ls_seen_livecontexts=1
      _ls_p_livecontexts=$2
      shift 2
      ;;
    *)
      echo "loop-state: unknown argument '$1' (--head <sha> or --selftest required; --help prints usage)" >&2
      exit 2
      ;;
  esac
done

# --base-dir / --live-contexts must be given TOGETHER (LOOP-STATE-TRACKER-STEP-ASIDE design §2,
# RD-3): exactly one of the two is a usage anomaly, never a silent partial step-aside. Checked
# HERE, inside ls_parse_args itself (T1 fix round 2), so the in-process grading path
# (delegate/half-args, called the same way delegate/changed-after-flags already is) can assert
# this function's OWN rc AND its own stderr sentence, instead of trusting a bare rc 2 that a
# sibling fault (e.g. run_gate's "not a commit" path) could equally have produced.
if [ "$_ls_seen_basedir" -ne "$_ls_seen_livecontexts" ]; then
  echo "loop-state: --base-dir and --live-contexts must be given together" >&2
  exit 2
fi
}

ls_parse_args "$@"

if [ "$_ls_seen_selftest" -eq 1 ]; then
  selftest; exit $?
fi

# K20: --help answers the stage->skill question where the trailers are written. It is placed
# BEFORE --head's requirement and changes nothing about it: a BARE invocation still exits 2.
if [ "$_ls_seen_help" -eq 1 ]; then
  print_help; exit 0
fi

# NEVER defaults to HEAD. On pull_request, actions/checkout checks out refs/pull/N/merge —
# GitHub's ephemeral merge commit, whose message carries NO trailers. A gate built on HEAD would
# either false-RED every PR or get "fixed" into walking back until a trailer is found, at which
# point ANY ancestor satisfies it (design section 3.1, Security C2 — CRITICAL).
if [ "$_ls_seen_head" -ne 1 ]; then
  echo "loop-state: --head <sha> or --selftest required (never defaults to HEAD); --help prints the stage->skill map" >&2
  exit 2
fi

LS_BASE_DIR="$_ls_p_basedir"
LS_LIVE_CONTEXTS="$_ls_p_livecontexts"
run_gate "$_ls_p_head" "$_ls_p_changed"
exit $?
