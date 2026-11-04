#!/bin/sh
# Why this gate: docs/architecture/2026-07-26-kit-adherence-entry-binding-design.md section 3
# loop-state.sh — KIT-ADHERENCE-ENFORCEMENT Slice B1: the universal refusal floor.
#
# A change must carry an Entry Declaration on the PR HEAD commit. EVERY CLASS OWES THE SAME TWO
# TRAILERS (SWAS-614, 2026-11-01; the 2026-08-30 class-proportional set is overturned by the entry
# in docs/governance/DECISIONS.md):
#
#     any class                    ->  Kit-Row, Kit-Class
#     classifier degraded          ->  the same two, and check_class refuses (fail-closed)
#
# EVERY OTHER Kit-* FIELD IS NOT READ HERE, except the stage-artifact keys and Kit-Scope below. A
# Kit-Stage, Kit-Skill, Kit-Intent, Kit-Ceremony or Kit-Stop on the head changes no verdict and is
# never echoed; the pass line says so. "PRESENT" FOR THE TWO REQUIRED KEYS MEANS THE KEY OCCURS,
# AND THE CHARSET LEG SEPARATELY REQUIRES A NON-EMPTY VALUE: `Kit-Row:` with nothing after it is a
# present key with an empty value, and it is REFUSED.
#
# WHY THE CUT (do not "restore" the four without re-reading this). `D-240805-3`: the ledger binds,
# it does not authenticate. Kit-Row is matched against the board and Kit-Class against the
# classifier, each checked against an authority outside the author. Kit-Stage and Kit-Skill were
# only checked for RESOLVABILITY: nothing established that the named stage was the real stage or
# that the named skill was read, and nothing tied a class or a diff to a stage. A field no
# authority checks is ceremony without a control, so it is not asked for and not graded. THE
# CEILING IS STATED: this gate says nothing about which skill governed the work, as it never did.
#
# THIS GATE MAKES NO ORDERING CLAIM. The declaration may be --amend'ed onto the head commit after
# all the work is done. The ordering predicate was WITHDRAWN after five defeats in three
# adversarial rounds (ceremony-binding.sh:397-414). Do not build one here.
#
# HONEST CEILING (do not overclaim):
#   * GREEN proves a declaration is PRESENT and git-PARSEABLE on the named commit; that Kit-Row
#     names exactly one board row (BOARD-ROW-IDENTIFIER); and that Kit-Class equals the class
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
# NO STAGE-TO-SKILL MAP IS READ HERE. It was deleted with the two fields it validated (SWAS-614);
# .kit/roster.conf keeps only MODE and BLOCKLIST, which the guard reads.
#
# Usage:
#   sh conformance/loop-state.sh --head <sha>     (the PR head SHA — NEVER defaults to HEAD)
#   sh conformance/loop-state.sh --selftest
#   sh conformance/loop-state.sh --help           (usage and the two required keys)
#
# What it changes: nothing — read-only. Reads git history and the board.
# Guardrails: fails CLOSED on a classifier that cannot answer (check_class refuses), on an unrecognised
# backend, and on a row that resolves to zero or to more than one board row — each fixtured.
# ⚠️ derive_class's own fail-closed arm is DISCLOSED-UNPROVEN, not fixtured: review tried to build a
# fixture and REFUTED it — promotion-readiness.sh returns `control-plane` rc 0 for a missing file, an
# empty file, a blank-lines file, a directory and /dev/null, so it never emits an unrecognised token
# and the `*) return 1` arm is unreachable through this interface. Do not invent a fixture for it;
# the arm stays as defense against a future change in that script's contract. Refuses to default to HEAD: on pull_request,
# actions/checkout checks out the ephemeral merge commit, which carries NO trailers.
set -eu
# shellcheck disable=SC1007 # `CDPATH= cd` clears CDPATH so a user's CDPATH cannot redirect the cd.
DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# The repository the declaration is read from. Production is this repo; the selftest points it
# at a throwaway fixture repo IN-PROCESS. Deliberately NOT environment-overridable: the kit has
# banked "use arguments, not env" (OBLIGATION-TESTMODE-ENV-FLAG), and a plain script variable set
# inside selftest() has no external surface at all.
LS_REPO="$DIR"

# The gate-checked fields: what a head of ANY class owes. Read directly, no selector.
LS_REQUIRED_KEYS="Kit-Row Kit-Class"

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
# message — the severed-block defect this file's own fixture pins. Declaring the keys in this list is
# what makes "the same parser" a fact about the list rather than a claim in a comment. It also closes
# a silent-typo hole: a head carrying `Kit-Review: notes/x.txt` would otherwise read as "a record was
# named" to a human and as nothing at all to both gates.
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

# The classifier this gate asks for the class. A plain script variable, NOT an env route (the
# banked OBLIGATION-TESTMODE-ENV-FLAG rule, :61-73): selftest() points it at a stub in-process so
# the degradation arm can be fixtured, and nothing outside this file can reach it.
LS_CLASS_FN="derive_class"

# ls_class_for_required — the class, or the FAIL-SAFED marker, and ALWAYS rc 0.
#
# It always succeeds because its consumer is not a verdict: a classifier that has broken must still
# let the other legs run, so the author sees every problem in one round. The verdict on a broken
# classifier is check_class's, which fails closed on the FAIL-SAFED marker (and is the ONE refusal
# left for that state, since the required set no longer depends on the class — SWAS-614).
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
  echo "loop-state: change-class derivation FAILED — the class cannot be assumed; the class check refuses" >&2
  printf 'FAIL-SAFED\n'
  return 0
}

# ls_safe — strip control characters from any PR-controlled value before it reaches a log.
#
# Applied at EVERY interpolation site, not just the one that was reported. A tracked directory name
# beginning with a newline puts attacker text at the START of an Actions log line, which is enough
# for a workflow command; the sibling sites (backend token, artifact-key value) cannot reach a line
# start because `head -1` truncates, but they can still emit ANSI/CR log corruption. Fixing only the
# reported site would be this repo's named failure — fixing the example, then claiming the class.
#
# ⚠️ promotion-readiness.sh's `_render_safe` is NOT reusable here: its range deliberately preserves
# TAB and LF, so the injected line-start survives it. Measured. The full C0 range plus DEL is what
# works. LC_ALL=C so the byte ranges are not locale-dependent.
ls_safe() { LC_ALL=C printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177'; }

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
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) printf 'observe\n'; return 0 ;;
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

# check_declaration — leg P: presence + parseability of the two required keys, and the shape of
# the stage-artifact keys, on ONE named commit. The required set does not depend on the class
# (SWAS-614), so there is no class argument and nothing here for a degraded classifier to relax.
# Base-independent by construction: it reads the SHA it is given and NEVER walks to a parent. A
# declaration present only on an ancestor must FAIL, which is the negative that makes head-only
# scope safe (design section 3.1; the any-ancestor-satisfies defect ceremony-binding closed).
check_declaration() {   # $1 = sha
  _ls_rc=0
  for _ls_k in $LS_REQUIRED_KEYS; do
    # EXACTLY ONE occurrence. More than one is a FAIL, never "take the first" — a commit carrying
    # both `Kit-Class: control-plane` and `Kit-Class: ordinary` yields both lines, and head -1 /
    # tail -1 reach opposite verdicts (design section 3.2, measured decoy).
    _ls_n=$(decl_count "$1" "$_ls_k")
    if [ "$_ls_n" -eq 0 ]; then
      echo "loop-state: $1 carries no parseable '$_ls_k' trailer" >&2
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
    # field; it is deliberately wider than any one field's own grammar, because
    # `Kit-Class: control-plane` and `Kit-Row: SWAS-614` must pass it too.
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

  # Kit-Stage, Kit-Skill, Kit-Intent, Kit-Ceremony and Kit-Stop are deliberately NOT READ: a
  # volunteered value changes no verdict (the pass line says so).
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
  # class for the pass line; re-deriving here runs promotion-readiness.sh (and its git diff
  # against the trunk) a second time for an answer we hold. The selftest still calls this with a
  # fixture listing and no $3, so the live derivation path keeps its own coverage.
  if [ -n "${3:-}" ]; then
    _ls_derived="$3"
    # THIS ARM IS NOW THE ONLY REFUSAL LEFT FOR A BROKEN CLASSIFIER (SWAS-614: the required set no
    # longer escalates on it), so degraded/refuses in the selftest is load-bearing.
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
# the ROW EXISTENCE leg is N/A'd; Kit-Class still applies universally.
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
      _ls_neout=$(not_enforced_notice "$_ls_backend" "$LS_BOARDROOT" "$DIR/conformance/waivers-valid.sh" "$(tracker_delegated_cure "$_ls_backend")") || _ls_ne=$?
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
# rule LS_REPO / LS_BOARDROOT already follow). Without a pinned base the fixture legs
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
# every leg that follows.
check_scope() {   # $1 = sha
  set -f
  _ls_scope_rc=0
  scope_leg "$1" || _ls_scope_rc=$?
  set +f
  return "$_ls_scope_rc"
}

# ls_fail_epilogue — the run_gate failure epilogue, in THREE shapes (A3i, DIAL-DELIVERY Δ-B; I1/F4).
#
# The mode is computed by ls_epilogue_mode (below) from the facts run_gate already holds —
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
#   3 = the ROW leg was the SOLE failure (SWAS-204). The other legs passed, so the trailer contract
#       would be false; the row reason printed above names the fix. Scope may ALSO have failed.
#   0 = anything else — a real Entry-Declaration defect; print the trailer contract (CLAUDE.md §1),
#       plus one line when the row leg ALSO refused.
# The named paths go through ls_safe — a pushed filename is attacker-influenceable (the
# every-interpolation rule at ls_safe:79-90).
ls_fail_epilogue() {   # $1 = mode(0|1|2|3), $2 = sha, $3 = escaping paths, $4 = row_bad(0|1), $5 = scope_bad(0|1)
  if [ "$1" -eq 3 ]; then
    echo "loop-state: FAIL — $2 was refused by the ROW leg alone; the other Entry Declaration legs passed." >&2
    echo "  The row reason is printed above. If it says NOT ENFORCED, the backlog backend is one the kit" >&2
    echo "  cannot read, and no commit or trailer edit clears it. Otherwise the row reason above names the" >&2
    echo "  fix (board the row, correct Kit-Row, or fix the board/backend)." >&2
    [ "${5:-0}" -eq 0 ] || echo "  The SCOPE leg also refused (reason above)." >&2
    return 0
  fi
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
  [ "${4:-0}" -eq 0 ] || echo "  The ROW leg ALSO refused (reason above); fixing the trailers alone will not clear it." >&2
  return 0
}

# ls_epilogue_mode — the A3i/I1 + SWAS-204 discriminant, EXTRACTED from run_gate so it is directly
# testable with controlled inputs. Driving the whole run_gate in the selftest is NOT hermetic: its
# check_class leg derives the class from the AMBIENT working tree (derive_class runs promotion-readiness
# with no fixture listing in the run_gate path — the deliberate "no --changed flag" at :289-293), so the
# legs cannot be pinned green from a fixture commit unless they are overridden (T7d L7 does that).
# Mode is escape(1) ONLY when a real escape was captured, never merely because scope was the only
# failing leg.
#   $1 = decl_bad (0|1): did a trailer leg (declaration, class) fail?
#   $2 = row_bad (0|1): did the row leg fail?   $3 = captured escaping paths (maybe empty)
ls_epilogue_mode() {
  [ "$1" -eq 0 ] || { printf 0; return 0; }   # a trailer leg failed -> the trailer contract
  [ "$2" -eq 0 ] || { printf 3; return 0; }   # the ROW leg alone -> the row-only text
  [ -n "$3" ] && { printf 1; return 0; }       # a REAL escape was captured -> the escape epilogue
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
  printf 'conformant fixture\n\nbody\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\n' \
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

  # D — KILL FIXTURE: both fields PRESENT in the message, severed from the trailer paragraph
  # by GitHub's squash separator. git parses NO Kit-* trailers here. A grep implementation passes
  # this commit; the real parser must FAIL it. This is the exact shape of every squash-merge on
  # this repo's main today.
  echo d > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'severed trailer block\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\n\n---------\n\nCo-authored-by: X <x@example.invalid>\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SEVERED=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # F — DUPLICATE KEY: two Kit-Class lines with OPPOSITE values. Measured decoy: `head -1` and
  # `tail -1` reach opposite verdicts, so "take the first" is not a safe reading. Must FAIL.
  echo f > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'duplicate key decoy\n\nKit-Row: DEMO-ROW\nKit-Class: control-plane\nKit-Class: ordinary\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_DUP=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # G — METACHARACTER Kit-Row. The value flows into a board grep (T6), the identical path that
  # forced the charset refusal at ceremony-binding.sh:124-136. Must be refused AT THE BOUNDARY,
  # not matched.
  echo g > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'regex metachar row\n\nKit-Row: DEMO.*ROW\nKit-Class: ordinary\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_META=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # H — SINGLE-KEY POSITIVE for the count logic. Paired with F so an off-by-one (wc -l vs
  # grep -c .) cannot satisfy both: wc -l reports 2 for this one commit and would false-RED it.
  echo h > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'single key positive\n\nKit-Row: DEMO-ROW\nKit-Class: sensitive\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SINGLE=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # H2 — THE STAGE-ARTIFACT KEYS, WELL-FORMED (LOOP-STAGE-ARTIFACT-GATE). Kit-Review carries a
  # consolidated two-record set, so the comma split is exercised by the POSITIVE as well as by H3.
  echo h2 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'stage artifacts named\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Plan: docs/plans/2026-09-04-demo.md\nKit-Review: docs/reviews/2026-09-04-demo.md,docs/reviews/2026-09-04-second.md\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ARTIFACT=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # H3 — Kit-Review OUTSIDE its prefix. The silent-typo hole: `notes/x.md` reads to a human as "a
  # record was named" and to both gates as nothing at all.
  echo h3 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'artifact key outside its prefix\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Review: notes/2026-09-04-demo.md\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ARTIFACT_PFX=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # H3b — an EMPTY ELEMENT in the consolidated set (`a.md,,b.md`). The old IFS word-split dropped
  # empties silently; the heredoc/`IFS= read` split that replaced it (semgrep ifs-tampering) delivers
  # every element to the case, so the `''` arm now refuses it. Without this leg the split could regress
  # to a form that skips empties and nothing would notice.
  echo h3b > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'empty element in the set\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Review: docs/reviews/2026-09-04-demo.md,,docs/reviews/2026-09-04-second.md\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ARTIFACT_EMPTY=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # H4 — a TRAVERSING Kit-Plan. Refused at the boundary, before any consumer resolves it.
  echo h4 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'traversing artifact key\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Plan: docs/plans/../../etc/passwd.md\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ARTIFACT_TRAV=$(git -C "$LS_FXDIR" rev-parse HEAD)

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

  # O — row present on the hermetic board, for the row-resolution positive.
  echo o > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'real board row\n\nKit-Row: FIXTURE-ROW-ALPHA\nKit-Class: ordinary\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_REALROW=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # O2 — SUBSTRING: `Kit-Row: A` (leg d). The design wrote this leg as `Kit-Row: a`; the value is
  # UPPER-CASE here for a reason worth stating, because it is the difference between this leg
  # testing what it claims and testing something else. Since security S-M2, a lower-case id is
  # refused by `row_id_ok` at the front door — so `a` would red on the GRAMMAR and never reach the
  # lookup, leaving the names-no-row path uncovered. `A` is a well-formed id that occurs in the
  # fixture board's TEXT (inside `FIXTURE-ROW-ALPHA`) and names no row, which is exactly the
  # substring the whole-file `grep -Fq` this slice replaces used to accept. The lower-case case has
  # its own leg (board-lower / LS_FX_LOWERROW).
  echo o2 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'single-letter row\n\nKit-Row: A\nKit-Class: ordinary\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SUBSTR=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # O3 — NON-ITEM CELL: the token appears only in another row's Intent/Links cell (leg e). Also
  # accepted by the old whole-file grep; it is not an Item-cell id, so it names no row.
  echo o3 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'links-cell row\n\nKit-Row: LINKS-ONLY-ROW\nKit-Class: ordinary\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_LINKSONLY=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # O4 — a LOWER-CASE Kit-Row (security S-M2). The board-lower fixture carries the matching row, so
  # nothing but the grammar check can refuse this pair.
  echo o4 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'lower-case row id\n\nKit-Row: kw6-a2\nKit-Class: ordinary\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_LOWERROW=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # Q — CONTROL-PLANE POSITIVE: declared == derived == control-plane. The class axis had two
  # negatives and only an `ordinary` positive; this is the class where a false-RED costs most.
  echo q > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'control-plane positive\n\nKit-Row: DEMO-ROW\nKit-Class: control-plane\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_CPOK=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # --- B9 Kit-Scope fixtures --------------------------------------------------------------------
  # The scope leg grades a DIFF, so these need a base and branches off it. The base is PINNED into
  # LS_SCOPE_BASEREF by the legs (never auto-resolved) so nothing here depends on the fixture repo's
  # ambient default-branch name.
  LS_FX_SCOPEBASE=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # S1 — COVERED: the only changed path is under the single declared prefix.
  mkdir -p "$LS_FXDIR/docs"
  echo s1 > "$LS_FXDIR/docs/note.md"; git -C "$LS_FXDIR" add docs/note.md
  printf 'scope covered\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Scope: docs/\n' \
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
  printf 'scope escaped\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Scope: docs/\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_OUT=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # S3/S4/S5 — HOSTILE TOKENS, one face each. ⚠️ NON-VACUITY: every one of them ALSO declares a
  # prefix that covers nothing in the diff, so if the hostile check were removed the leg would fall
  # through to the escape branch and refuse for the WRONG reason — which is exactly what the
  # reason-assertions below (with their forbidden downstream string) measure.
  echo s3 > "$LS_FXDIR/conformance/stray.sh"; git -C "$LS_FXDIR" add conformance/stray.sh
  printf 'scope traversal token\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Scope: docs/../etc\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_DOTDOT=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo s4 > "$LS_FXDIR/conformance/stray.sh"; git -C "$LS_FXDIR" add conformance/stray.sh
  printf 'scope glob token\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Scope: docs/*\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_GLOB=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo s5 > "$LS_FXDIR/conformance/stray.sh"; git -C "$LS_FXDIR" add conformance/stray.sh
  printf 'scope absolute token\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Scope: /etc\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_ABS=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # S6 — DUPLICATE Kit-Scope with OPPOSITE sets: `head -1` and `tail -1` reach opposite verdicts,
  # so "take the first" is not a safe reading here either. Must FAIL on the count, before matching.
  echo s6 > "$LS_FXDIR/conformance/stray.sh"; git -C "$LS_FXDIR" add conformance/stray.sh
  printf 'duplicate scope key\n\nKit-Row: DEMO-ROW\nKit-Class: ordinary\nKit-Scope: docs/\nKit-Scope: conformance/\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_DUP=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # P1/P2/P3 — THE TWO-KEY HEADS (SWAS-614): Kit-Row + Kit-Class and nothing else, one per class.
  # Every class owes exactly this, so the three heads are the positive cells of required/two-keys-
  # every-class. Their Kit-Class matches the listing the selftest classifies each against.
  echo p1 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ordinary two-trailer head\n\nbody\n\nKit-Row: FIXTURE-ROW-ALPHA\nKit-Class: ordinary\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ORD2=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo p2 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'sensitive two-trailer head\n\nbody\n\nKit-Row: FIXTURE-ROW-ALPHA\nKit-Class: sensitive\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SENS2=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo p3 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'control-plane two-trailer head\n\nbody\n\nKit-Row: FIXTURE-ROW-ALPHA\nKit-Class: control-plane\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_CP2=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # P4/P5 — ONE REQUIRED KEY MISSING, each carrying the other, so only the missing one can be named.
  echo p4 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'no row key\n\nbody\n\nKit-Class: ordinary\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_NOROW=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo p5 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'no class key\n\nbody\n\nKit-Row: FIXTURE-ROW-ALPHA\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_NOCLASS=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # I1-I5 — THE FIVE FIELDS THE GATE NO LONGER READS (ignored/*). Each is a two-key ordinary head
  # plus ONE hostile or malformed value the old gate refused: a stage outside any map, a skill that
  # names nothing, a duplicated skill, a shell metacharacter in a skill, and the three advisory
  # fields with empty values. All must PASS and change no verdict.
  echo i1 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ignored bad stage\n\nbody\n\nKit-Row: FIXTURE-ROW-ALPHA\nKit-Class: ordinary\nKit-Stage: Wibble\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_IGN_STAGE=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo i2 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ignored bad skill\n\nbody\n\nKit-Row: FIXTURE-ROW-ALPHA\nKit-Class: ordinary\nKit-Skill: skills/nope\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_IGN_SKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo i3 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ignored duplicate skill\n\nbody\n\nKit-Row: FIXTURE-ROW-ALPHA\nKit-Class: ordinary\nKit-Skill: skills/tdd\nKit-Skill: skills/build\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_IGN_DUPSKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo i4 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ignored metachar skill\n\nbody\n\nKit-Row: FIXTURE-ROW-ALPHA\nKit-Class: ordinary\nKit-Skill: skills/tdd;rm\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_IGN_METASKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo i5 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ignored advisory fields\n\nbody\n\nKit-Row: FIXTURE-ROW-ALPHA\nKit-Class: ordinary\nKit-Intent:\nKit-Ceremony:\nKit-Stop:\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_IGN_ADVISORY=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # E1/E2 — A CONTROL CHARACTER in a PR-controlled value, built at run time from octal so no
  # control byte is stored in this file. E1 rides an IGNORED field (ignored/not-echoed: it must
  # reach no output); E2 rides Kit-Review, a field the gate DOES quote in a refusal, so it is the
  # one hermetic seam where ls_safe is held (safe/artifact-value).
  echo e1 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ignored field with an escape\n\nbody\n\nKit-Row: FIXTURE-ROW-ALPHA\nKit-Class: ordinary\nKit-Skill: bad\033[2Kevil\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_IGN_ESC=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo e2 > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'artifact value with an escape\n\nbody\n\nKit-Row: FIXTURE-ROW-ALPHA\nKit-Class: ordinary\nKit-Review: docs/reviews/bad\033[2Kevil.md\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_ARTIFACT_ESC=$(git -C "$LS_FXDIR" rev-parse HEAD)
  return 0
}

# `--help` — usage and the two required keys. The one moment an agent needs this is while writing
# the very trailers this gate grades, so the gate answers the question itself. A bare invocation
# still exits 2 (it never defaults to HEAD).
print_help() {
  echo "usage: sh conformance/loop-state.sh --head <sha> [--changed <listing>] [--base-dir <dir> --live-contexts <file>]"
  echo "                                                 grade the Entry Declaration on that commit"
  echo "       sh conformance/loop-state.sh --selftest     run this check's own fixtures"
  echo "       sh conformance/loop-state.sh --help         this text"
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
  echo "  Every class               Kit-Row, Kit-Class"
  echo "  also graded when present  Kit-Plan, Kit-Review, Kit-Scope"
  echo "  any other Kit-* field     ignored: it changes no verdict and is never echoed"
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

    # KILL FIXTURE — both fields present in the body but severed by the squash separator.
    # A grep implementation PASSES this. If this leg ever goes green, the gate is matching text
    # instead of parsing structure and the slice has failed.
    check_declaration "$LS_FX_SEVERED" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a SEVERED trailer block must FAIL (grep would pass it)"; st_fail=1; }

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
    check_declaration "$LS_FX_ARTIFACT" >/dev/null 2>&1 \
      || { echo "selftest FAIL: well-formed Kit-Plan/Kit-Review (incl. a comma-separated set) must PASS"; st_fail=1; }

    # NEGATIVE — a Kit-Review outside `docs/reviews/` must FAIL. An always-PASS implementation, and
    # an absent-is-N/A one that forgot PRESENT-implies-VALIDATED, both break THIS leg.
    check_declaration "$LS_FX_ARTIFACT_PFX" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a Kit-Review outside 'docs/reviews/' must FAIL, not read as 'a record was named'"; st_fail=1; }

    # NEGATIVE — an EMPTY element inside the comma set must FAIL. A split that silently drops empties
    # (the IFS word-split this file used before semgrep refused it) passes THIS leg only by accident.
    check_declaration "$LS_FX_ARTIFACT_EMPTY" >/dev/null 2>&1 \
      && { echo "selftest FAIL: an empty element in a comma-separated Kit-Review set must FAIL, not be skipped"; st_fail=1; }

    # NEGATIVE — a traversing Kit-Plan must FAIL at the boundary.
    check_declaration "$LS_FX_ARTIFACT_TRAV" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a traversing Kit-Plan value must FAIL"; st_fail=1; }

    # CHARSET NEGATIVE — a regex-metacharacter Kit-Row must be refused at the boundary before it
    # ever reaches a board grep.
    check_declaration "$LS_FX_META" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a metacharacter Kit-Row must be refused at the boundary"; st_fail=1; }

    # A classifier that answers with a token derive_class does not recognise. Defined here, inside
    # selftest(), so no production path can reach it.
    # shellcheck disable=SC2329 # invoked indirectly through $LS_CLASS_FN
    _st_garbage_class() { printf 'garbage\n'; return 1; }

    # --- T3b: EVERY CLASS OWES THE SAME TWO TRAILERS (SWAS-614) -------------------------------
    _st_fxd="$DIR/conformance/fixtures/loop-state"
    printf 'auth/login.txt\n' > "$LS_FXDIR/changed-sensitive.txt"
    _st_ord_lst="$_st_fxd/changed-ordinary.txt"
    _st_sens_lst="$LS_FXDIR/changed-sensitive.txt"
    _st_cp_lst="$_st_fxd/changed-controlplane.txt"
    _st_board_t3b="$LS_BOARDROOT"
    LS_BOARDROOT="$LS_FXDIR/board"

    # required/two-keys-every-class — the three two-key heads each pass the WHOLE gate (run_gate:
    # declaration, class equality, row) against the listing that derives their class. The old gate
    # refused the sensitive and control-plane heads for the missing Kit-Stage and Kit-Skill.
    _st_twok_ok=1
    _st_twok_cell() {
      _st_twok_out=$(run_gate "$1" "$2" 2>&1) && _st_twok_rc=0 || _st_twok_rc=$?
      case "$_st_twok_out" in
        *"OK: loop-state"*"class:"*"$3"*) [ "$_st_twok_rc" -eq 0 ] || _st_twok_ok=0 ;;
        *) _st_twok_ok=0; echo "selftest: required/two-keys-every-class ($3) got <$_st_twok_out>" ;;
      esac
    }
    _st_twok_cell "$LS_FX_ORD2" "$_st_ord_lst" ordinary
    _st_twok_cell "$LS_FX_SENS2" "$_st_sens_lst" sensitive
    _st_twok_cell "$LS_FX_CP2" "$_st_cp_lst" control-plane
    if [ "$_st_twok_ok" -eq 1 ]; then
      echo "selftest PASS: required/two-keys-every-class — Kit-Row + Kit-Class pass whole-gate on ordinary, sensitive and control-plane"
    else
      echo "selftest FAIL: required/two-keys-every-class — a two-key head must PASS on every class"; st_fail=1
    fi

    # required/missing-row and required/missing-class — REASON-BOUND: each refusal names the key it
    # lacks, and the forbidden half pins that it does not name the key the head DOES carry.
    if ls_assert_reason "required/missing-row" \
         "carries no parseable 'Kit-Row' trailer" "'Kit-Class'" \
         check_declaration "$LS_FX_NOROW"; then
      echo "selftest PASS: required/missing-row"
    else st_fail=1; fi
    if ls_assert_reason "required/missing-class" \
         "carries no parseable 'Kit-Class' trailer" "'Kit-Row'" \
         check_declaration "$LS_FX_NOCLASS"; then
      echo "selftest PASS: required/missing-class"
    else st_fail=1; fi

    # ignored/* — the five fields the gate no longer reads: a malformed value changes no verdict.
    # Each head is graded by the WHOLE gate and must print the pass line (not merely rc 0).
    _st_ign() {   # $1 = cell name, $2 = head
      _sti_out=$(run_gate "$2" "$_st_ord_lst" 2>&1) && _sti_rc=0 || _sti_rc=$?
      case "$_sti_out" in
        *"OK: loop-state"*) [ "$_sti_rc" -eq 0 ] && { echo "selftest PASS: $1"; return 0; } ;;
      esac
      echo "selftest FAIL: $1 — a field the gate does not read must not change the verdict, got rc=$_sti_rc <$_sti_out>"
      st_fail=1
    }
    _st_ign ignored/bad-stage "$LS_FX_IGN_STAGE"
    _st_ign ignored/bad-skill "$LS_FX_IGN_SKILL"
    _st_ign ignored/dup-skill "$LS_FX_IGN_DUPSKILL"
    _st_ign ignored/metachar-skill "$LS_FX_IGN_METASKILL"
    _st_ign ignored/intent-ceremony-stop "$LS_FX_IGN_ADVISORY"
    unset -f _st_ign

    # ignored/not-echoed — an ESC inside an ignored field reaches NO output stream, success line
    # included (stdout and stderr are both captured). The pass line must still be present, so the
    # leg cannot go green on a head that never ran.
    _st_ne_out=$(run_gate "$LS_FX_IGN_ESC" "$_st_ord_lst" 2>&1) && _st_ne_rc=0 || _st_ne_rc=$?
    case "$_st_ne_out" in
      *"$(printf '\033')"*) echo "selftest FAIL: ignored/not-echoed — the bytes of an ignored field reached the output"; st_fail=1 ;;
      *"OK: loop-state"*"other Kit-* fields: not read"*)
        [ "$_st_ne_rc" -eq 0 ] \
          && echo "selftest PASS: ignored/not-echoed — an ESC in Kit-Skill reaches no output, and the pass line says the field was not read" \
          || { echo "selftest FAIL: ignored/not-echoed — rc $_st_ne_rc"; st_fail=1; } ;;
      *) echo "selftest FAIL: ignored/not-echoed — no pass line saying other Kit-* fields were not read, got <$_st_ne_out>"; st_fail=1 ;;
    esac
    LS_BOARDROOT="$_st_board_t3b"

    # degraded/refuses — a classifier that cannot answer still REFUSES a head carrying both valid
    # trailers. The required set no longer escalates on it, so check_class's FAIL-SAFED arm is now
    # the ONLY refusal: the wanted string is that arm's own sentence, and the forbidden one is what
    # the arm's absence would print instead (the mutant that deletes the arm must red here).
    _st_clsfn_saved="$LS_CLASS_FN"
    LS_CLASS_FN=_st_garbage_class
    _st_cls="$(ls_class_for_required 2>/dev/null)"
    [ "$_st_cls" = FAIL-SAFED ] \
      || { echo "selftest FAIL: a degraded classifier must yield FAIL-SAFED, got '$_st_cls'"; st_fail=1; }
    LS_BOARDROOT="$LS_FXDIR/board"
    _st_dg_out=$(run_gate "$LS_FX_ORD2" "$_st_ord_lst" 2>&1 >/dev/null) && _st_dg_rc=0 || _st_dg_rc=$?
    case "$_st_dg_out" in
      *"derivation FAILED"*) : ;;
      *) echo "selftest FAIL: degraded/refuses — the degraded arm must SAY the derivation FAILED, got <$_st_dg_out>"; st_fail=1 ;;
    esac
    if [ "$_st_dg_rc" -eq 1 ] \
       && ls_assert_reason "degraded/refuses" \
            "refusing to assume a class (fail-closed)" "does not equal the derived class" \
            run_gate "$LS_FX_ORD2" "$_st_ord_lst"; then
      echo "selftest PASS: degraded/refuses — a failed classifier refuses a two-valid-trailer head (rc 1)"
    else
      echo "selftest FAIL: degraded/refuses — rc=$_st_dg_rc, a failed classifier must refuse with the fail-closed class sentence"; st_fail=1
    fi
    LS_BOARDROOT="$_st_board_t3b"
    LS_CLASS_FN="$_st_clsfn_saved"

    # degraded/no-classifier — derive_class's own failure arm: a tree that lacks the classifier
    # (an empty directory standing in for $DIR) answers nothing, so it must return 1 and print nothing.
    _st_dir_saved="$DIR"
    mkdir -p "$LS_FXDIR/no-classifier-tree"
    DIR="$LS_FXDIR/no-classifier-tree"
    _st_nc_out=$(derive_class "$_st_ord_lst" 2>/dev/null) && _st_nc_rc=0 || _st_nc_rc=$?
    DIR="$_st_dir_saved"
    if [ "$_st_nc_rc" -eq 1 ] && [ -z "$_st_nc_out" ]; then
      echo "selftest PASS: degraded/no-classifier — derive_class refuses (rc 1, no output) when the classifier is absent"
    else
      echo "selftest FAIL: degraded/no-classifier — derive_class rc=$_st_nc_rc out=<$_st_nc_out>, wanted rc 1 and no output"; st_fail=1
    fi

    # safe/artifact-value — ls_safe coverage, re-homed from the deleted skill leg. An ESC inside a
    # Kit-Review value is quoted by the artifact refusal, and must not survive onto stderr. The
    # identity mutant of ls_safe turns this leg red.
    if ls_assert_reason "safe/artifact-value" \
         "is not a usable path" "$(printf '\033')" \
         check_declaration "$LS_FX_ARTIFACT_ESC"; then
      echo "selftest PASS: safe/artifact-value — ls_safe strips an ESC from a quoted artifact value"
    else st_fail=1; fi

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
    # Kit-Class still reds the WHOLE gate (AC3), driven through run_gate so the declaration and
    # class legs actually run.
    # The class must come from a FIXTURE listing, never from the ambient checkout diff: without
    # $2, ls_class_for_required reads the live git diff against trunk, so this leg's verdict would
    # depend on whatever branch it happens to run on (control-plane on #711's own branch, ordinary
    # on any docs-only PR) rather than on the fixture head under test.
    echo "conformance/loop-state.sh" > "$LS_FXDIR/t1-cp-listing.txt"
    _st_oth_out=$(run_gate "$LS_FX_NOCLASS" "$LS_FXDIR/t1-cp-listing.txt" 2>&1) && _st_oth_rc=0 || _st_oth_rc=$?
    [ "$_st_oth_rc" -eq 1 ] \
      || { echo "selftest FAIL: delegate/other-legs-bind: wanted rc 1 (missing Kit-Class), got rc=$_st_oth_rc; out='$_st_oth_out'"; st_fail=1; }
    case "$_st_oth_out" in
      *"carries no parseable 'Kit-Class' trailer"*) : ;;
      *) echo "selftest FAIL: delegate/other-legs-bind: refusal was not the CLASS sentence (would also pass for a row refusal), got <$_st_oth_out>"; st_fail=1 ;;
    esac
    case "$_st_oth_out" in
      *"N/A: board governance is delegated to the required context 'tracker-board-gates' (live on the base branch)"*)
        echo "selftest PASS: delegate/other-legs-bind: head missing Kit-Class -> rc 1, the CLASS refusal sentence AND the delegated N/A — the step-aside excused the row leg while the declaration leg still refused" ;;
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
    # SWAS-203: the cure follows the backend. This fixture declares github, which has no kit
    # adapter: it is told the waiver or BACKLOG.md, and NEVER to bind a job it cannot have.
    case "$_st_nl_out" in
      *"no kit adapter reads 'github' yet"*"the owner (a human, never an agent) ratifies a board-governance waiver, or move the board to BACKLOG.md"*)
        echo "selftest PASS: delegate/not-live-cure-adapterless: the github refusal names the missing adapter, the waiver and BACKLOG.md (SWAS-203)" ;;
      *)
        echo "selftest FAIL: delegate/not-live-cure-adapterless: missing the adapterless cure, got <$_st_nl_out>"; st_fail=1 ;;
    esac
    case "$_st_nl_out" in
      *"tracker-board-gates"*)
        echo "selftest FAIL: delegate/not-live-cure-adapterless-neg: a github refusal told the author to bind tracker-board-gates, got <$_st_nl_out>"; st_fail=1 ;;
      *)
        echo "selftest PASS: delegate/not-live-cure-adapterless-neg: a github refusal never names tracker-board-gates" ;;
    esac
    # …and a jira tree gets the bind first, the waiver where branch protection cannot be set, and
    # never "no kit adapter". The jira fixture is the head-conf tree (CLAUDE.md declares jira); the
    # live-contexts file still lacks the line, so the step-aside stays off and the row leg refuses.
    _st_c3_root="$LS_BOARDROOT"
    LS_BOARDROOT="$LS_FXDIR/t1-head-conf"
    _st_c3_out=$(check_row "$LS_FX_OK" 2>&1) && _st_c3_rc=0 || _st_c3_rc=$?
    LS_BOARDROOT="$_st_c3_root"
    [ "$_st_c3_rc" -eq 1 ] \
      || { echo "selftest FAIL: delegate/not-live-cure-jira: wanted rc 1 (the verdict is unchanged), got rc=$_st_c3_rc"; st_fail=1; }
    case "$_st_c3_out" in
      *"Cure: bind the trusted job (it needs a valid .kit/tracker.conf on main)"*"--replace"*"a free-plan private repository"*"one person may sign both"*"or move the board to BACKLOG.md"*)
        echo "selftest PASS: delegate/not-live-cure-jira: the jira refusal leads with the bind, then the waiver for a free-plan private repository, then BACKLOG.md (SWAS-203)" ;;
      *)
        echo "selftest FAIL: delegate/not-live-cure-jira: missing the jira cure, got <$_st_c3_out>"; st_fail=1 ;;
    esac
    case "$_st_c3_out" in
      *"no kit adapter"*)
        echo "selftest FAIL: delegate/not-live-cure-jira-neg: a jira refusal said there is no kit adapter, got <$_st_c3_out>"; st_fail=1 ;;
      *)
        echo "selftest PASS: delegate/not-live-cure-jira-neg: a jira refusal is never told there is no kit adapter" ;;
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

    # UNIVERSALITY — on an N/A'd tree the class leg still refuses.
    # ⚠️ HONEST LABEL: this leg is TAUTOLOGICAL as written, and review measured why —
    # check_class contains ZERO references to LS_BOARDROOT, so setting it cannot
    # change its behaviour and this duplicates coverage that already exists above. Kept as a
    # REGRESSION GUARD in case a future change couples the board root into it; it does
    # NOT establish "only the row leg is N/A'd" on its own. Do not cite it as proof of that.
    LS_BOARDROOT="$LS_FXDIR"
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

    # A1 item 5 — a `writer` credential BINDS, with its OWN NOTICE that does not say over-privileged (the distinct word is the point).
    _stn_wr="$LS_FXDIR/tracker-record-writer.txt"
    printf '%s\n' "$_st_good_body" | sed 's/^credential ok/credential writer/' > "$_stn_wr"
    SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stn_wr"; SEAM_HEAD="$_st_trkhead"
    _st_wrout=$(seam_row_count AB-1 2>&1 >/dev/null) && _st_wrrc=0 || _st_wrrc=$?
    [ "$_st_wrrc" -eq 0 ] \
      || { echo "selftest FAIL: a writer credential must BIND (A1 item 5)"; st_fail=1; }
    case "$_st_wrout" in
      *NOTICE*"is a writer"*) : ;;
      *) echo "selftest FAIL: a writer credential must carry its own stderr NOTICE (A1 item 5), got <$_st_wrout>"; st_fail=1 ;;
    esac
    case "$_st_wrout" in
      *"over-privileged"*) echo "selftest FAIL: a writer NOTICE must not say over-privileged (A1 item 5), got <$_st_wrout>"; st_fail=1 ;;
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
      # shellcheck disable=SC2034  # read by seam_row_count via the SEAM_* seam
      { SEAM_ROOT="$_st_trk"; SEAM_RECORD="$_stm6_f"; SEAM_HEAD="$_st_trkhead"; }
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
    # run_gate picks the epilogue via ls_epilogue_mode from the facts it already holds:
    # whether any NON-scope leg failed, and whether check_scope captured a REAL escape. Three modes:
    #   1 = a path ESCAPE was the sole failure  -> name the path(s), each through ls_safe;
    #   2 = a scope BOUNDARY refusal (hostile token / dup key) was the sole failure -> the trailers
    #       are valid AND no path escaped, so NEITHER the trailer contract NOR the escape claim (with
    #       its "SCOPE=enforce") may print. This is the I1 defect: a hostile-token refusal used to
    #       print "changed paths escape (SCOPE=enforce)" over an EMPTY path list, false under enforce
    #       and doubly false under observe (where the boundary refuses unconditionally);
    #   0 = a real Entry-Declaration defect -> the trailer contract.
    # THE DISCRIMINANT IS TESTED DIRECTLY — driving the whole run_gate is not hermetic (its check_class
    # leg derives class from the ambient tree; see ls_epilogue_mode's note). The escape-vs-boundary
    # legs are the I1 mutant kill: the pre-fix logic set the flag purely on "scope was the only failing
    # leg", so it returned the escape mode for BOTH — the `0 '' -> 2` leg is RED before the fix, GREEN after.
    [ "$( ls_epilogue_mode 0 0 'conformance/stray.sh' )" = 1 ] \
      || { echo "selftest FAIL: I1 — a captured escape as the sole failure must be epilogue mode 1"; st_fail=1; }
    [ "$( ls_epilogue_mode 0 0 '' )" = 2 ] \
      || { echo "selftest FAIL: I1 — a scope-only refusal with NO captured escape must be mode 2, not a false escape"; st_fail=1; }
    [ "$( ls_epilogue_mode 1 0 'conformance/stray.sh' )" = 0 ] \
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

    # --- T7d (SWAS-204): a refusal by the ROW leg alone stops blaming valid trailers ------------
    # L1 the defect kill: the pre-fix grouping folded check_row into the trailer flag, so (0,1) gave 0.
    [ "$( ls_epilogue_mode 0 1 '' )" = 3 ] \
      || { echo "selftest FAIL: SWAS-204 L1 — the row leg alone must be epilogue mode 3 (trailer contract blamed valid trailers)"; st_fail=1; }
    # L2 a trailer-leg failure keeps the trailer contract, with or without a row failure.
    [ "$( ls_epilogue_mode 1 0 '' )" = 0 ] && [ "$( ls_epilogue_mode 1 1 '' )" = 0 ] \
      || { echo "selftest FAIL: SWAS-204 L2 — a trailer-leg failure must stay mode 0, with or without a row failure"; st_fail=1; }
    # L3 LOAD-BEARING NEGATIVE: invalid trailers are never given the row-only text.
    for _fe_rb in 0 1; do
      _fe_m0=$( ls_fail_epilogue 0 deadbeef "" "$_fe_rb" 0 2>&1 )
      case "$_fe_m0" in
        *"does not carry a valid Entry Declaration"*"LAST paragraph"*) ;;
        *) echo "selftest FAIL: SWAS-204 L3 — mode 0 (row_bad=$_fe_rb) must print the trailer contract word for word"; st_fail=1 ;;
      esac
      case "$_fe_m0" in
        *"ROW leg alone"*) echo "selftest FAIL: SWAS-204 L3 — mode 0 (row_bad=$_fe_rb) must NEVER print the row-only text"; st_fail=1 ;;
      esac
    done
    # L4 mode 3 names the row leg and never the trailer contract.
    _fe_m3=$( ls_fail_epilogue 3 deadbeef "" 1 0 2>&1 )
    case "$_fe_m3" in
      *"ROW leg alone"*"other Entry Declaration legs passed"*) ;;
      *) echo "selftest FAIL: SWAS-204 L4 — mode 3 must say the ROW leg alone refused and the other legs passed"; st_fail=1 ;;
    esac
    case "$_fe_m3" in
      *"LAST paragraph"*|*"does not carry"*) echo "selftest FAIL: SWAS-204 L4 — mode 3 must NOT print the trailer contract"; st_fail=1 ;;
    esac
    case "$_fe_m3" in
      *"SCOPE leg also refused"*) echo "selftest FAIL: SWAS-204 L4 — mode 3 with scope passing must not claim a scope refusal"; st_fail=1 ;;
    esac
    case "$( ls_fail_epilogue 3 deadbeef "" 1 1 2>&1 )" in
      *"SCOPE leg also refused"*) ;;
      *) echo "selftest FAIL: SWAS-204 L4 — mode 3 with scope ALSO failing must say so"; st_fail=1 ;;
    esac
    # L5 the "ALSO refused" line appears in mode 0 only when the row leg failed too.
    case "$( ls_fail_epilogue 0 deadbeef "" 1 0 2>&1 )" in
      *"ROW leg ALSO refused"*) ;;
      *) echo "selftest FAIL: SWAS-204 L5 — mode 0 with row_bad=1 must say the ROW leg ALSO refused"; st_fail=1 ;;
    esac
    case "$( ls_fail_epilogue 0 deadbeef "" 0 0 2>&1 )" in
      *"ROW leg ALSO refused"*) echo "selftest FAIL: SWAS-204 L5 — mode 0 with row_bad=0 must NOT claim a row refusal"; st_fail=1 ;;
    esac
    # L6 the three I1 rows above are re-pointed to the new signature (row_bad 0); verdicts unchanged.
    # L7 CALL-SITE PIN: run_gate computes the mode on EVERY failure. The leg functions are overridden
    # in a subshell (hermetic); only check_row fails. Pre-fix, a row-only failure kept mode 0.
    # `trap - EXIT`: the subshell inherits ls_fx_cleanup, which would rm the shared fixture dir on exit.
    _fe_rg=$( trap - EXIT INT TERM; LS_REPO="$LS_FXDIR"
      check_declaration() { return 0; }
      check_class() { return 0; }
      check_scope() { return 0; }
      ls_class_for_required() { printf ordinary; }
      check_row() { echo "loop-state: row check NOT ENFORCED: backend 'jira' (fixture)" >&2; return 1; }
      run_gate "$LS_FX_OK" 2>&1 >/dev/null && echo "rc=0" || echo "rc=$?" )
    case "$_fe_rg" in
      *"ROW leg alone"*"rc=1"*) ;;
      *) echo "selftest FAIL: SWAS-204 L7 — run_gate with only check_row failing must print the row-only text and rc 1"; st_fail=1 ;;
    esac
    case "$_fe_rg" in
      *"LAST paragraph"*) echo "selftest FAIL: SWAS-204 L7 — run_gate row-only failure must NOT print the trailer contract"; st_fail=1 ;;
    esac
    # L8 TEXT-CONSUMER INVARIANT: hooks/pre-push and conformance/prepush-lane.sh trim from the
    # "loop-state: FAIL " prefix, so every epilogue's first line must start with it.
    for _fe_c in "0 0" "0 1" "1 0" "2 0" "3 1"; do
      _fe_cm=${_fe_c% *}; _fe_cr=${_fe_c#* }
      _fe_first=$( ls_fail_epilogue "$_fe_cm" deadbeef "conformance/x.sh" "$_fe_cr" 0 2>&1 | head -n 1 )
      case "$_fe_first" in
        "loop-state: FAIL "*) ;;
        *) echo "selftest FAIL: SWAS-204 L8 — epilogue mode $_fe_cm (row_bad=$_fe_cr) first line must start 'loop-state: FAIL '"; st_fail=1 ;;
      esac
    done

    # --- REASON ASSERTIONS ---------------------------------------------------------------------
    # Review's 26-mutant single-mutation sweep measured FIVE legs passing for the WRONG reason: the
    # intended check could be neutered and a DIFFERENT check rejected the fixture, leaving the suite
    # green. An outcome-only leg structurally cannot catch that. These assert the REASON on stderr.
    # Third argument is the DOWNSTREAM reason that must NOT appear — see ls_assert_reason.
    ls_assert_reason "exactly-one occurrence" "occurrences of" "may contain only" \
      check_declaration "$LS_FX_DUP" || st_fail=1

    # --- CONTROL-PLANE POSITIVE ----------------------------------------------------------------
    # declared == derived == control-plane must PASS. This is the class where a false-RED is most
    # expensive and the only one of the three with no positive leg until now.
    check_class "$LS_FX_CPOK" "$_st_fxd/changed-controlplane.txt" >/dev/null 2>&1 \
      || { echo "selftest FAIL: declared control-plane == derived control-plane must PASS"; st_fail=1; }

    LS_REPO="$_st_repo_saved"
    ls_fx_cleanup
  fi

  # --- help/two-keys: --help states the two required keys and no map, and a bare invocation still
  # refuses ------------------------------------------------------------------------------------
  # POSITIVE: rc 0, the two keys named, and neither a stage nor a skill named as owed.
  # NEGATIVE (load-bearing): no arguments must still exit 2 with the existing line, or adding a
  # help arm would have quietly turned "never defaults to HEAD" into a default.
  if _st_help=$(sh "$0" --help 2>&1); then _st_hrc=0; else _st_hrc=$?; fi
  _st_hbad=""
  case "$_st_help" in *"Kit-Row, Kit-Class"*) : ;; *) _st_hbad="$_st_hbad no-two-keys" ;; esac
  case "$_st_help" in *"Kit-Stage"*|*"Kit-Skill"*|*"map"*) _st_hbad="$_st_hbad names-stage-skill-or-map" ;; esac
  if [ "$_st_hrc" -eq 0 ] && [ -z "$_st_hbad" ]; then
    echo "selftest PASS: help/two-keys — --help states Kit-Row + Kit-Class and no stage, skill or map, rc 0"
  else
    echo "selftest FAIL: help/two-keys — --help rc=$_st_hrc, problems:${_st_hbad:- none}"; st_fail=1
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
  echo "  declaration— positives: conformant, single-key, two keys on every class; negatives: no-decl,"
  echo "               ancestor-only, severed-block, duplicate-key, metachar-row, missing row/class"
  echo "  ignored    — five fields (stage, skill, duplicate skill, metachar skill, advisory) change no"
  echo "               verdict; an ESC in an ignored field reaches no output"
  echo "  class      — positives: ordinary, control-plane; negatives: under-declared, over-declared,"
  echo "               classifier failed (refuses with two valid trailers)"
  echo "  safe       — ls_safe strips an ESC from a quoted artifact value"
  echo "  row        — positive; negative; N/A routes: no-board, non-md backend, pristine template;"
  echo "               fail-closed on an unrecognised backend"
  echo "  scope      — positive (covered); negatives: escaping-path under enforce, duplicate key,"
  echo "               hostile tokens (traversal, glob metachar, absolute); observe keeps rc 0 and"
  echo "               NAMES the escaping path; N/A routes: no declaration, unresolvable basis"
  echo "  reasons    — legs assert the refusal REASON (and the absence of the downstream reason),"
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
  _ls_decl_bad=0   # a trailer leg failed (declaration, class): the epilogue discriminant input
  _ls_row_bad=0    # the row leg failed (SWAS-204: split out so a row-only refusal stops blaming trailers)
  git -C "$LS_REPO" cat-file -e "$1^{commit}" 2>/dev/null || {
    echo "loop-state: '$1' is not a commit in this repository" >&2; return 2; }
  # THE CLASSIFIER RUNS FIRST — it needs no trailers, and its answer is held once for check_class
  # and the pass line. A derivation failure yields FAIL-SAFED, which check_class refuses
  # (fail-closed): since the required set no longer depends on the class, that is the one refusal.
  # $2, when supplied, is a caller-built changed-listing (H-2): a BASE-ONLY checkout (the trusted
  # job) has no local diff, so the live git-diff-against-trunk derivation would otherwise read an
  # empty change-set and fail OPEN to `ordinary` rather than FAIL-SAFED.
  _ls_class=$(ls_class_for_required "${2:-}")
  check_declaration "$1" || { _ls_bad=1; _ls_decl_bad=1; }
  check_class       "$1" "" "$_ls_class" || { _ls_bad=1; _ls_decl_bad=1; }
  check_row        "$1" || { _ls_bad=1; _ls_row_bad=1; }
  # B9: the scope leg. It runs inside the existing --head path, so the installed pre-push hook and
  # CI's bound gate both get it with ZERO wiring edits. It cannot change the rc of any commit that
  # carries no Kit-Scope trailer (the N/A arm), which is every PR shape that is green today. Runs
  # LAST so the decl/row flags already reflect every other leg when the epilogue mode is derived.
  _ls_scope_bad=0
  check_scope "$1" || { _ls_bad=1; _ls_scope_bad=1; }
  if [ "$_ls_bad" -ne 0 ]; then
    # I1/F4 + SWAS-204: the mode is computed on EVERY failure, from the facts held here, never parsed
    # from LS_SCOPE_STATE. Scope-ESCAPE (1) only when a REAL escape was captured; a boundary refusal
    # leaves LS_SCOPE_ESCAPED empty and gets mode 2; a row-only refusal gets mode 3.
    _ls_mode=$(ls_epilogue_mode "$_ls_decl_bad" "$_ls_row_bad" "${LS_SCOPE_ESCAPED:-}")
    ls_fail_epilogue "$_ls_mode" "$1" "${LS_SCOPE_ESCAPED:-}" "$_ls_row_bad" "$_ls_scope_bad"
    return 1
  fi
  # The success line states EXACTLY what each leg established — never "all resolve". Security review
  # blocked an earlier version for printing "row, stage, class, skill all resolve" on a change whose
  # row was a single letter, or whose row leg never ran at all. A merge-blocking control that
  # overstates its own result is the failure this whole slice exists to prevent.
  echo "OK: loop-state — $1 carries a valid Entry Declaration."
  # THE PASS LINE SAYS WHAT WAS NOT READ, so a volunteered Kit-Stage or Kit-Skill cannot be taken
  # for a checked field (the same honesty rule as the row leg below).
  echo "  class:         $_ls_class · required: $LS_REQUIRED_KEYS · Kit-Plan, Kit-Review, Kit-Scope: checked when carried · other Kit-* fields: not read"
  echo "  class check:  equals promotion-readiness --class"
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
    # FAIL-SAFED, silently grading a class that may be wrong for what may be a real control-plane
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

# K20: --help states what the Entry Declaration owes, where the trailers are written. It is placed
# BEFORE --head's requirement and changes nothing about it: a BARE invocation still exits 2.
if [ "$_ls_seen_help" -eq 1 ]; then
  print_help; exit 0
fi

# NEVER defaults to HEAD. On pull_request, actions/checkout checks out refs/pull/N/merge —
# GitHub's ephemeral merge commit, whose message carries NO trailers. A gate built on HEAD would
# either false-RED every PR or get "fixed" into walking back until a trailer is found, at which
# point ANY ancestor satisfies it (design section 3.1, Security C2 — CRITICAL).
if [ "$_ls_seen_head" -ne 1 ]; then
  echo "loop-state: --head <sha> or --selftest required (never defaults to HEAD); --help prints usage" >&2
  exit 2
fi

LS_BASE_DIR="$_ls_p_basedir"
LS_LIVE_CONTEXTS="$_ls_p_livecontexts"
run_gate "$_ls_p_head" "$_ls_p_changed"
exit $?
