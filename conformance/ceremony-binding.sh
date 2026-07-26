#!/bin/sh
# Why this gate: docs/architecture/2026-07-26-loop-ceremony-binding-design.md
# ceremony-binding.sh — LOOP-CEREMONY-BINDING Slice 1: the DESIGN GATE backstop.
#
# A Sensitive/Control-plane change-set MUST carry a design artifact that (a) is named by a recorded
# `--gate design` GO SCOPED TO THIS CHANGE, (b) is tracked, not a symlink, and real rather than a stub,
# and (c) is touched by the commit that GO approves. Ordinary change-sets are N-A: nothing is required.
#
# ⚠️ THIS GATE MAKES NO ORDERING CLAIM. It does NOT check that the design preceded the work. The
# ordering predicate was WITHDRAWN after being defeated five times in three adversarial rounds — see
# design §4.4 for the catalogue, and CEREMONY-ORDERING-PROOF for the boarded successor.
#
# THIS IS THE BACKSTOP, NOT THE CONTROL. The control is the touch point itself — the human's recorded
# GO at the DESIGN GATE. This check cannot create that moment; it can only refuse a merge that skipped
# it. See docs/architecture/2026-07-26-loop-ceremony-binding-design.md §4.0.
#
# HONEST CEILING (do not overclaim):
#   * GREEN proves: a design artifact EXISTS, is tracked/non-symlink/non-placeholder, is named by a GO
#     record SCOPED TO THIS CHANGE whose approver carries a derived assurance label, and is TOUCHED by
#     the commit that GO approves. That is all.
#   * IT PROVES NOTHING ABOUT ORDER. The design may have been written after the work.
#   * `approved-sha` TOUCHES the artifact; it did not necessarily AUTHOR it — a zero-byte create or a
#     whitespace edit satisfies a touch. It binds the record to the artifact, nothing more.
#   * It does NOT prove the design was GOOD, or that anyone read it. That is P2 — explicitly out of
#     scope for this slice and separately boarded. PR #430 would have passed this check.
#   * `refs/notes/*` is OUTSIDE branch protection: anyone with push can add, overwrite or delete the GO
#     ledger with no PR and no review. The storage of this control is weaker than what it gates.
#   * A git NOTE binds, it does not AUTHENTICATE (scripts/promotion-verify.sh carries the same ceiling).
#   * THE SUBSTANCE FLOOR IS THE LOAD-BEARING HALF OF "is the artifact real", not the template signal.
#     obl_is_placeholder's default stub vocabulary is THREAT-MODEL-specific ([summary]/[threat]/[why]/…)
#     and the kit ships no design-doc template, so a design artifact has no stub vocabulary of its own:
#     in practice the `template` signal rarely fires here and >= OBL_MIN_SUBSTANCE_LINES non-blank lines
#     under a heading is what actually stops an empty file satisfying the gate. Measured during T2. Do
#     not read a green as "the design is substantive" — it means "not empty and not a threat-model stub".
#
# CLASS IS DERIVED BY A SINGLE AUTHORITY. This check does NOT re-derive the change-set: it shells out to
# conformance/promotion-readiness.sh --class, the derivation hardened at all five sites in v3.186.0
# (--no-renames + core.quotePath=false + -z + the newline fail-safe). Re-implementing it here would make
# a SIXTH derivation and duplicate the control-plane path contract with nothing locking the two together
# — the CP7R5-KEPTSET-LOCK failure, which is already boarded describing exactly this.
#
# Usage:
#   sh conformance/ceremony-binding.sh                 (derive change-set: merge-base HEAD origin/main)
#   sh conformance/ceremony-binding.sh --changed FILE  (fixture path list; honored ONLY under --selftest)
#   sh conformance/ceremony-binding.sh --selftest
#
# What it changes: nothing — read-only. Reads the working tree, git history, and refs/notes/promotions.
# Guardrails: fails CLOSED on an underivable change-class, an unreadable notes ref, a `basis:` path that
# does not resolve to a tracked file, or a placeholder artifact. A run that grades ZERO implementation
# a `basis:` that is not a design artifact, or an `approved-sha:` that is not a hex object name or does
# not touch the artifact it approves.
set -eu
# shellcheck disable=SC1007 # `CDPATH= cd` clears CDPATH for this one command so a user's CDPATH cannot
# redirect the cd; the empty assignment is intentional, not a mistyped value.
DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

NOTES_REF="${PROMOTION_NOTES_REF:-promotions}"

# The shape a `basis:` artifact must have. Default is the kit's own convention, used by design §8, by
# plan T1, and by every design document in this repo. Overridable for adopters who file designs
# elsewhere — but NOT unconstrained: an unconstrained basis lets any substantive tracked file satisfy
# the DESIGN GATE, which is the whole gate.
CB_DESIGN_GLOB="${CB_DESIGN_GLOB:-docs/architecture/*-design.md}"
# A UNIVERSAL GLOB IS AN OFF-SWITCH, SO REFUSE IT. This value is environment-borne, which the kit has
# already banked as the weaker shape ("use arguments, not env" — OBLIGATION-TESTMODE-ENV-FLAG), and it
# is gate-DEFINING: found by self-attack, `CB_DESIGN_GLOB='*'` reopened the whole defect this constraint
# was added to close (a repo with zero design documents passing by naming README.md). The engine already
# sets the precedent — obligation_gate refuses a glob that matches every path — so the same refusal
# applies here. It does NOT make the env route safe; it removes the one value that silently disables the
# check. An adopter narrowing to their own convention is fine; an adopter widening to everything is not.
case "$CB_DESIGN_GLOB" in
  ''|'*'|'**'|'*'*'*'|'?*')
    echo "ceremony-binding: CB_DESIGN_GLOB must not match every path — that disables the design-artifact" >&2
    echo "  constraint entirely. Narrow it to your design-document convention." >&2
    exit 2 ;;
esac

# Tell the engine it is being SOURCED, so its own --selftest dispatch stays inert here: without this,
# `sh ceremony-binding.sh --selftest` would run the LIB's selftest (the sourced lib sees $1=--selftest)
# instead of this check's legs. Value is 'yes' (NOT '=1') so the non-vacuity sweep — which neuters a
# pre-marker <var>=1 — cannot flip it. Same idiom and same reason as threat-obligation.sh.
# shellcheck disable=SC2034 # read by obligation-lib.sh once sourced, not by this file
OBL_LIB_SOURCED=yes
# shellcheck disable=SC1091 # resolved at runtime from $DIR; shellcheck cannot follow a computed path
. "$DIR/conformance/obligation-lib.sh"

# Derive the change-class via the SINGLE hardened authority. Fails CLOSED: any non-zero exit, empty
# output, or unrecognised token from promotion-readiness.sh is a DERIVE FAILURE, never an implicit
# `ordinary` (which would be fail-OPEN on the decision this whole gate exists to protect).
derive_class() {   # args: [--changed FILE]
  _dc_out=""
  if [ "${1:-}" = "--changed" ] && [ -n "${2:-}" ]; then
    _dc_out="$(sh "$DIR/conformance/promotion-readiness.sh" --changed "$2" --class 2>/dev/null | tail -1)" || _dc_out=""
  else
    _dc_out="$(sh "$DIR/conformance/promotion-readiness.sh" --class 2>/dev/null | tail -1)" || _dc_out=""
  fi
  case "$_dc_out" in
    ordinary|sensitive|control-plane) printf '%s\n' "$_dc_out"; return 0 ;;
    *) return 1 ;;
  esac
}

run_ceremony_binding() {   # args: forwarded (--changed FILE | --scope ID | none)
  # `--base` was removed with the ordering predicate (design §4.4). It existed only to drive the
  # merge-base for the ancestry check; with no ordering there is no base to override.
  _cb_changed=""; _cb_scope=""
  while [ $# -gt 0 ]; do
    case "$1" in
      # `--changed` is a FIXTURE flag, honored only when KIT_CB_TEST=1 (set by selftest). The VALUE is
      # argument-borne, so a caller who controls only the environment cannot redirect the gate — the
      # fixture path must also arrive on argv, which in CI means editing the `run:` line.
      # ⚠️ HONEST CORRECTION: the enabling half IS environment-borne, exactly like the engine's
      # KIT_OBL_TEST. An earlier version of this comment claimed "argument-borne, not
      # environment-borne", which review measured as false. This inherits OBLIGATION-TESTMODE-ENV-FLAG's
      # limitation rather than escaping it; that boarded row governs both.
      --changed)
        [ $# -ge 2 ] || { echo "ceremony-binding: --changed needs a value" >&2; return 2; }
        [ "${KIT_CB_TEST:-}" = "1" ] && _cb_changed="$2"
        shift 2 ;;
      # `--scope` is a PRODUCTION argument, not a fixture flag: it is what BINDS the GO record to THIS
      # change. CI supplies the PR number. Argument-borne per the banked "arguments, not env" ruling.
      --scope)
        [ $# -ge 2 ] || { echo "ceremony-binding: --scope needs a value" >&2; return 2; }
        # VALIDATE AT THE BOUNDARY. `grep -F` treats a NEWLINE in the pattern string as a pattern
        # SEPARATOR, so a multi-line scope becomes an OR — and since every design record carries
        # `gate: design` by construction, `--scope "$(printf 'PR-9\ngate: design')"` matched
        # unconditionally and bypassed the binding entirely (reproduced by security review).
        # Not reachable from this repo's CI (a PR number is an integer), but `--scope` is a PRODUCTION
        # argument in a check adopters copy into their own CI, where it may be wired from a ticket id or
        # a PR title. Reject-by-default, the same rule promotion-verify.sh applies to the same field.
        case "$2" in
          ''|*[!A-Za-z0-9_.:/-]*)
            echo "ceremony-binding: --scope must be non-empty and may contain only" >&2
            echo "  [A-Za-z0-9_.:/-] — got a value with a disallowed character (refused)." >&2
            return 2 ;;
        esac
        _cb_scope="$2"
        shift 2 ;;
      *) echo "ceremony-binding: unknown arg '$1'" >&2; return 2 ;;
    esac
  done

  # ---- Applicability: derive the class via the single hardened authority, fail CLOSED.
  if [ -n "$_cb_changed" ]; then
    _cls="$(derive_class --changed "$_cb_changed")" || _cls=""
  else
    _cls="$(derive_class)" || _cls=""
  fi
  if [ -z "$_cls" ]; then
    echo "FAIL: ceremony-binding — change-class is UNDERIVABLE; refusing to classify (fail closed)." >&2
    return 1
  fi
  if [ "$_cls" = "ordinary" ]; then
    echo "N-A: ceremony-binding — change-class 'ordinary'; no design artifact required."
    return 0
  fi

  # ---- The DESIGN GATE record: a `--gate design` GO must exist in refs/notes/promotions.
  # Matched LINE-ANCHORED (`^gate: design$`), never as a substring: a substring test would accept
  # `gate: design-review` or `gate: redesign` and let an unrelated record satisfy this gate. Same
  # discipline as promotion-verify.sh rejecting a mid-string `[signed: gpg]` decoy.
  # THE RECORD MUST BE BOUND TO **THIS** CHANGE (amendment §4.3, security HIGH-1). Selecting the first
  # `gate: design` record in the ledger was a full bypass: an unrelated design doc merged to trunk is an
  # ancestor of every later commit, so the ordering predicate below went vacuously true and ANY future
  # control-plane PR passed with no design and no record of its own. The scope id is what binds record
  # to change; without it this gate stops exactly one merge — its own.
  if [ -z "$_cb_scope" ]; then
    echo "FAIL: ceremony-binding — no --scope supplied; refusing to match a GO record to this change" >&2
    echo "      by guesswork (fail closed). CI passes the PR number; locally pass --scope <id>." >&2
    return 1
  fi
  _design_note=""; _gate_seen=0
  if git rev-parse -q --verify "refs/notes/$NOTES_REF" >/dev/null 2>&1; then
    for _obj in $(git notes --ref="$NOTES_REF" list 2>/dev/null | awk '{print $2}'); do
      _body="$(git notes --ref="$NOTES_REF" show "$_obj" 2>/dev/null || true)"
      # BOTH conditions on the SAME record, each line-anchored.
      printf '%s\n' "$_body" | grep -q '^gate: design$' || continue
      _gate_seen=1   # a design record exists, but maybe not for THIS scope — report the near-miss
      printf '%s\n' "$_body" | grep -qF -x "scope: $_cb_scope" || continue
      _design_note="$_obj"; break
    done
  fi
  if [ -z "$_design_note" ]; then
    # Two distinct causes, reported distinctly. They share a branch but not a diagnosis, and an operator
    # who recorded a GO for the wrong scope needs to be told that rather than "no record found".
    if [ "$_gate_seen" -eq 1 ]; then
      echo "FAIL: ceremony-binding — a 'gate: design' record exists, but NONE is scoped to this change" >&2
      echo "      (expected 'scope: $_cb_scope'). A record for another scope does NOT satisfy this gate:" >&2
      echo "      that is what let an unrelated prior design vouch for every later change-set." >&2
    else
      echo "FAIL: ceremony-binding — change-class '$_cls' requires a recorded DESIGN GATE approval," >&2
      echo "      and no '--gate design' record was found in refs/notes/$NOTES_REF." >&2
    fi
    echo "      Record one: scripts/promotion-verify.sh record --gate design --scope $_cb_scope \\" >&2
    echo "        --approved-sha <design-commit> --approved-by <human> --basis <design-doc-path> ..." >&2
    echo "      THEN PUBLISH IT: git push origin refs/notes/promotions" >&2
    echo "      Do BOTH BEFORE opening the PR. CI fetches the ledger seconds after the PR is created," >&2
    echo "      so a record pushed afterwards loses the race and this gate reds on a compliant change" >&2
    echo "      until the job re-runs. Measured on this check's own PR: run started 13:41:37Z, the" >&2
    echo "      notes landed 13:41:48Z, and the fetch at +7s saw an empty ledger." >&2
    return 1
  fi

  # THE RECORD MUST NAME AN APPROVER (amendment §4.3, security HIGH-2). Before this the check read only
  # `gate:` and `basis:`, so a hand-written note with NO approver line passed and three shipped claims
  # about "a named human's recorded GO" were false. The label is the DERIVED assurance token that
  # promotion-verify.sh computes from the commit's own evidence — it is never accepted from input there,
  # so requiring it forces the record through the tool rather than a bare `git notes add`.
  _appr="$(printf '%s\n' "$_body" | sed -n 's/^approved-by: //p' | head -1)"
  case "$_appr" in
    ?*\ \[*\]) : ;;
    *) echo "FAIL: ceremony-binding — the GO record carries no valid 'approved-by: <id> [<label>]' line." >&2
       echo "      Record it through scripts/promotion-verify.sh record, which derives the label." >&2
       return 1 ;;
  esac
  # ESCAPE THE BRACKET. `${_appr##*[}` has an UNESCAPED `[`, which starts a bracket expression in
  # POSIX pattern syntax. bash tolerates an unterminated one as a literal; DASH DOES NOT MATCH AT ALL
  # and returns the whole string. `/bin/sh` on ubuntu-latest IS dash, and every invocation of this
  # check is literal `sh` — the selftest inside the REQUIRED `conformance` job, the PR-context gate,
  # conformance/verify.sh, and the non-vacuity sweep. Measured: 16 of 25 legs FAIL under dash, and a
  # fully compliant branch is REJECTED on the production path. conformance/shellcheck.sh is green over
  # it, so nothing else in the fleet catches it.
  _label="${_appr##*\[}"; _label="${_label%]}"
  # EXACTLY ONE bracket group, and the id carries none. Found by self-attack: `##*[` is GREEDY, so
  # `approved-by: X [self-asserted] [committer]` extracted `committer` and a self-asserted record with an
  # appended decoy passed the control-plane tier. promotion-verify.sh already rejects '[' and ']'
  # ANYWHERE in --approved-by for the same reason (a mid-string decoy fooling a substring grep), so a
  # tool-written record can never have two groups — mirroring that rule here keeps the requirement
  # meaningful instead of decorative. (The claim that this "forces the record through the tool" was
  # RETRACTED — see below; it does not, and this file's own fixtures prove it.)
  # ⚠️ DO NOT RESTATE THE CLAIM THAT WAS HERE. It said requiring the label "forces the record through
  # the tool rather than a bare `git notes add`". THIS FILE'S OWN FIXTURES DISPROVE IT — _mkfix/_mkord/
  # _mklink all write `approved-by: … [committer]` with a bare `git notes add`, and legs 9/16/17 PASS on
  # them. Requiring the label makes a record SHAPED like a tool-written one; it does not authenticate
  # it. The true statement is the header's: a note BINDS, it does not AUTHENTICATE.
  _id="${_appr%% \[*}"
  case "$_id" in
    *'['*|*']'*|'')
      echo "FAIL: ceremony-binding — the approver id must not contain '[' or ']' (the assurance label is" >&2
      echo "      derived, never supplied). Got: $_appr" >&2
      return 1 ;;
  esac
  if [ "$_appr" != "$_id [$_label]" ]; then
    echo "FAIL: ceremony-binding — 'approved-by:' must be exactly '<id> [<label>]'; a trailing decoy" >&2
    echo "      label would otherwise override a weaker one. Got: $_appr" >&2
    return 1
  fi
  case "$_label" in
    # `authenticated:` is NOT a wildcard — promotion-verify.sh only ever derives `authenticated:
    # <forge>-review`, so `[authenticated: nonsense]` must not pass. Found by self-attack.
    "signed: gpg"|committer|"authenticated: "*-review) : ;;
    "self-asserted")
      # Solo-compatible by design: the owner IS the committer of the design commit, so [committer] is
      # reached at no cost. `approver != author` is deliberately NOT imposed — unusable solo, theatre here.
      if [ "$_cls" = "control-plane" ]; then
        echo "FAIL: ceremony-binding — a control-plane DESIGN GATE needs an assurance stronger than" >&2
        echo "      [self-asserted]. Record with --approved-by matching the design commit's committer" >&2
        echo "      identity (yields [committer]) or sign the commit (yields [signed: gpg])." >&2
        return 1
      fi ;;
    *) echo "FAIL: ceremony-binding — unrecognised assurance label '[$_label]' on the GO record." >&2
       return 1 ;;
  esac

  # ---- Identification: the GO record NAMES the artifact, in its `basis:` field.
  # Without an explicit pointer the ancestry assertion below would have to accept ANY design doc in
  # history — and every one of them is an ancestor of everything, so the ordering proof would be
  # VACUOUSLY GREEN. The pointer is what makes the ordering claim non-trivial.
  _basis="$(git notes --ref="$NOTES_REF" show "$_design_note" 2>/dev/null \
            | sed -n 's/^basis: //p' | head -1)"
  if [ -z "$_basis" ] || [ "$_basis" = "(none recorded)" ]; then
    echo "FAIL: ceremony-binding — the '--gate design' record on $_design_note names no artifact." >&2
    echo "      Re-record it with --basis <path-to-the-design-doc>." >&2
    return 1
  fi

  # PATH SAFETY. `basis:` is free text written by a human at GO time, so it is untrusted input to this
  # check. Reject an absolute path or any `..` segment BEFORE touching the filesystem, then require the
  # path to be a TRACKED file — `git ls-files --error-unmatch` also confines it to the repository, so a
  # symlink pointing outside the tree cannot satisfy the gate.
  case "$_basis" in
    /*|*..*)
      echo "FAIL: ceremony-binding — refusing a basis path that is absolute or contains '..'." >&2
      return 1 ;;
  esac
  # IT MUST BE A DESIGN ARTIFACT. Without this the chain validated traversal -> tracked -> non-symlink
  # -> non-placeholder and never asked WHAT the file is, so pointing `basis:` at any substantive
  # markdown the payload commit already touched satisfied the DESIGN GATE. Both reviewers reproduced it
  # independently on repos containing ZERO design documents (`basis: README.md`, `basis: CHANGELOG.md`).
  # Evade cost: zero — cheaper than all five defeats that got the ordering predicate withdrawn, and it
  # defeated the gate's entire remaining claim. It also made five shipped surfaces false, every one of
  # which says "design artifact".
  # The pattern is the kit's OWN convention (design §8, plan T1, and every design doc in this repo), so
  # this constrains the check to what the surfaces already promised rather than inventing a rule.
  # Adopters who keep designs elsewhere change CB_DESIGN_GLOB; the default is the kit convention.
  # shellcheck disable=SC2254 # UNQUOTED ON PURPOSE: CB_DESIGN_GLOB is a glob pattern and must be
  # expanded as one. Quoting it would match the literal string `docs/architecture/*-design.md`, which no
  # real path equals — the constraint would silently never match and every basis would be refused.
  case "$_basis" in
    $CB_DESIGN_GLOB) : ;;
    *)
      echo "FAIL: ceremony-binding — basis '$_basis' is not a design artifact." >&2
      echo "      Expected $CB_DESIGN_GLOB (the kit convention, e.g." >&2
      echo "      docs/architecture/2026-07-26-my-slice-design.md)." >&2
      echo "      A GO naming an arbitrary tracked file is not a recorded DESIGN decision." >&2
      return 1 ;;
  esac
  if ! git ls-files --error-unmatch -- "$_basis" >/dev/null 2>&1; then
    echo "FAIL: ceremony-binding — the design artifact named by the GO record is not a tracked file:" >&2
    echo "      $_basis" >&2
    return 1
  fi
  # REFUSE A SYMLINK (git mode 120000). `ls-files --error-unmatch` proves the LINK is tracked; it does
  # NOT confine the target — obl_is_placeholder's `[ -r ]` and greps then FOLLOW it to content outside
  # the repository that appears in no diff. Reproduced by security review (MED-5) with a tracked
  # `docs/architecture/x-design.md -> ../../../outside/notes.md`. The header previously CLAIMED this was
  # closed by ls-files, which was false; now it is closed here and the claim is true.
  if [ "$(git ls-files -s -- "$_basis" 2>/dev/null | awk '{print $1}')" = "120000" ]; then
    echo "FAIL: ceremony-binding — the design artifact is a SYMLINK; its content is not in this tree:" >&2
    echo "      $_basis" >&2
    return 1
  fi

  # ---- Is the artifact REAL, or a stub? Reuse the engine's placeholder detector rather than
  # re-implementing stub vocabulary: it already defeats "eight lines of prose under a heading", already
  # fails closed on an unreadable record, and already refuses a malformed pattern.
  if obl_is_placeholder "$_basis"; then
    echo "FAIL: ceremony-binding — the design artifact is a PLACEHOLDER (${OBL_PLACEHOLDER_REASON:-template}):" >&2
    echo "      $_basis" >&2
    return 1
  fi

  # shellcheck disable=SC2034 # consumed by T3's ancestry predicate, which resolves the commit that
  # introduced this artifact and asserts it precedes every implementation commit on the branch.
  # ---- Bind the GO to the ARTIFACT, and use it as the ordering anchor (round 3, owner-ratified).
  # The scope binding tied the RECORD to this change; the ARTIFACT stayed unbound, so a scoped GO could
  # name any pre-existing design doc whose first add is an ancestor of everything — and security
  # reproduced a brand-new branch with ZERO design authored passing on the production path.
  # `approved-sha:` is the field that closes it: promotion-verify.sh requires it, validates it resolves,
  # and derives the assurance label FROM it, so it is the one field already bound to real evidence.
  # It ALSO replaces the previous anchor. That was `git log --diff-filter=A … | tail -1` — the OLDEST
  # add of the path — which security defeated by writing the design after the payload at a path that had
  # existed and been deleted earlier in history: the stale add won and the ordering went vacuous.
  _asha="$(printf '%s\n' "$_body" | sed -n 's/^approved-sha: //p' | head -1)"
  case "$_asha" in
    ''|-*)
      # NO temp-file cleanup here: this validation now runs BEFORE $_trig/$_pcache exist, and under
      # `set -u` referencing them would abort the whole run — which is exactly what it did, killing the
      # selftest mid-list with no diagnostic at all.
      echo "FAIL: ceremony-binding — the GO record carries no usable 'approved-sha:' line." >&2
      return 1 ;;
  esac
  # NORMALISE FIRST. `git rev-list` always prints 40-hex, but promotion-verify.sh stores
  # `approved-sha:` VERBATIM as typed — it only checks resolvability, it never canonicalises. Measured
  # on this repo's real ledger: 34 of 61 records are 40-char, 24 are 7-char, 3 are 8-char. Comparing
  # the raw string against rev-list's output therefore FALSE-REDs 27 of 61 real records on a fully
  # compliant branch, with a message accusing the operator of the one thing they did correctly.
  # Reproduced before this fix. An uppercase 40-char SHA is the same class (rev-parse accepts it,
  # rev-list emits lowercase).
  # SHAPE FIRST, THEN NORMALISE. Normalising with `rev-parse` alone widened the field from an object
  # NAME to ANY git revision expression: `approved-sha: HEAD` and `approved-sha: <branch>` both began
  # to pass, and each RE-RESOLVES on every run to whatever the tip is at check time. That is not a
  # binding at all — it is the opposite of one, and it landed squarely on the single claim this slice
  # retained after the ordering withdrawal. Introduced by my own normalisation fix; caught in review.
  # `${#var}` is POSIX and dash-safe.
  _asha_raw="$_asha"
  case "$_asha" in
    ''|*[!0-9a-fA-F]*)
      echo "FAIL: ceremony-binding — approved-sha must be a hex object name, not a revision" >&2
      echo "      expression (a name like HEAD or a branch re-resolves at check time and binds" >&2
      echo "      nothing). Got: $_asha_raw" >&2
      return 1 ;;
  esac
  if [ "${#_asha}" -lt 7 ] || [ "${#_asha}" -gt 40 ]; then
    echo "FAIL: ceremony-binding — approved-sha must be 7-40 hex characters. Got: $_asha_raw" >&2
    return 1
  fi
  _asha="$(git rev-parse -q --verify "${_asha}^{commit}" 2>/dev/null)" || _asha=""
  if [ -z "$_asha" ]; then
    echo "FAIL: ceremony-binding — approved-sha '$_asha_raw' does not resolve to a commit in this repo." >&2
    return 1
  fi
  # THE BINDING ITSELF: the approved commit must actually TOUCH the artifact it approves. Without this a
  # GO could name design doc A while approving commit B, and neither would constrain the other.
  # $_basis, not $CB_DESIGN_DOC: this validation now runs BEFORE that assignment, and under `set -u`
  # naming it here aborts the run with no diagnostic — which is precisely how it failed.
  if [ "$(git rev-list -1 "$_asha" -- "$_basis" 2>/dev/null)" != "$_asha" ]; then
    echo "FAIL: ceremony-binding — the approved commit does not touch the artifact it approves." >&2
    echo "      approved-sha: $_asha" >&2
    echo "      basis:        $_basis" >&2
    echo "      A GO must approve a commit that touches the design it names." >&2
    return 1
  fi

  CB_DESIGN_DOC="$_basis"

  # ---- ORDERING IS WITHDRAWN (design §4.4, owner-ratified 2026-07-26 after round 3).
  # FIVE defeats across three adversarial rounds, every one of them in the ordering predicate and
  # every one costing an attacker nothing:
  #   1. `--is-ancestor` is reflexive           -> design + work in one commit   (`git commit --amend`)
  #   2. a SIXTH derivation site                -> rename collapses to ordinary  (`git mv`)
  #   3. the anchor was a TOUCH test            -> zero-byte create, one blank line, or a mode change
  #   4. the stale anchor was merely RELOCATED  -> path created+deleted pre-base, design re-authored
  #   5. abbreviated approved-sha               -> false RED on 27 of this repo's 61 real records
  # Each fix relocated the defect instead of closing the class. Every OTHER component held across all
  # three rounds and appears on both reviewers' "tried and could not break" lists.
  # §4.0 already said the control is the TOUCH POINT, not the check — ordering was the backstop's
  # backstop. Withdrawing it costs the claim "and the design preceded the work", which has been
  # demonstrably false five times and demonstrably true never, and costs nothing else.
  # REMOVED WITH IT, and none of it may return piecemeal: the merge-base resolution, the per-path
  # commit partition (with its two mktemp files), the strict-ancestor check, the graded-commit count
  # and its anti-vacuity backstop, and the in-branch-vs-predates disclosure.
  # Boarded as CEREMONY-ORDERING-PROOF — a sound ordering proof needs its own design pass with the
  # five-defeat catalogue above as required input, the way CHANGESET-DERIVATION-LOCK carries its own.
  echo "OK: ceremony-binding — change-class '$_cls'; DESIGN GATE recorded (scope $_cb_scope)."
  echo "    Artifact: $CB_DESIGN_DOC — tracked, not a symlink, above the substance floor."
  echo "    Approved by: $_appr, in a GO scoped to this change, whose commit touches that artifact."
  echo "    NO ORDERING CLAIM: this gate does not check whether the design preceded the work."
  return 0
}

# ---- selftest() marker: the non-vacuity sweep mutates ONLY lines ABOVE here ----
selftest() {
  _tmp="$(mktemp -d "${TMPDIR:-/tmp}/ceremony-st.XXXXXX")"
  trap 'rm -rf "$_tmp"' EXIT INT TERM
  export KIT_CB_TEST=1   # honor the --changed fixture flag only in-test
  # PIN THE NOTES REF. Every fixture helper writes `git notes --ref=promotions`, but NOTES_REF is
  # resolved from PROMOTION_NOTES_REF at file scope, so a developer or adopter with that variable
  # exported got 13 red legs — and since this selftest is registered in conformance/verify.sh, a red
  # PRIMARY AGGREGATE. Same shape as the ambient-tree defect (C2), through the environment instead.
  # Setting only the env var is insufficient: NOTES_REF is already resolved by now, so pin both.
  NOTES_REF=promotions; PROMOTION_NOTES_REF=promotions; export PROMOTION_NOTES_REF
  # PIN THE DESIGN GLOB TOO, same reason. Every fixture files its design at
  # docs/architecture/d-design.md, so an adopter who legitimately narrows CB_DESIGN_GLOB to their own
  # convention would get a RED selftest — and it is registered in conformance/verify.sh, so that is a
  # red PRIMARY AGGREGATE for doing something the check explicitly invites. Measured:
  # `CB_DESIGN_GLOB='design/*.md' … --selftest` -> rc 1 before this pin. Identical class to the
  # PROMOTION_NOTES_REF defect, found the same way.
  CB_DESIGN_GLOB='docs/architecture/*-design.md'
  _fails=0; _legs=0

  # LEG 1 (liveness) — an ORDINARY change-set requires nothing: N-A, rc 0.
  _legs=$((_legs+1))   # leg1
  printf 'docs/x.md\n' > "$_tmp/changed-ordinary"
  if run_ceremony_binding --changed "$_tmp/changed-ordinary" --scope PR-1 >/dev/null 2>&1; then
    echo "PASS leg1: ordinary change-set -> N-A rc 0"
  else
    echo "FAIL leg1: ordinary change-set should be N-A rc 0"; _fails=$((_fails+1))
  fi

  # LEG 2 (LOAD-BEARING NEGATIVE for applicability) — a CONTROL-PLANE change-set with no recorded
  # `--gate design` GO must FAIL. Without this leg a check that N-A'd everything would pass leg 1 and
  # look healthy: leg 1 alone cannot distinguish "correctly exempts ordinary" from "exempts everything".
  # ⚠️ THIS LEG MUST RUN IN ITS OWN FIXTURE, NOT THE AMBIENT REPOSITORY.
  # It originally ran against whatever repo the selftest was invoked in, so "no GO record" held only
  # while that repo had never used the feature. Reviewer reproduced the consequence: record this slice's
  # own DESIGN GATE GO — the step the plan mandates before merge — and leg 2 FAILED. Because the selftest
  # is registered in conformance/verify.sh, that reddened the PRIMARY AGGREGATE for every developer and
  # every adopter while CI stayed green (only the PR-context job fetches refs/notes/*). A self-defeating
  # check: using the feature broke its own test. Now hermetic, and asserting verdict text like every
  # other negative leg — leg 2 was the last one checking rc alone, against this file's own stated rule.
  printf 'conformance/x.sh\n' > "$_tmp/changed-cp"
  _mkbare "$_tmp/f2"
  _expect_fail leg2 "$_tmp/f2" "no '--gate design' record was found" "control-plane with no GO record"

  # LEG 3 (fail-closed) — an UNDERIVABLE change-class must FAIL, never fall through to `ordinary`.
  #
  # ⚠️ THIS LEG WAS MIS-SPECIFIED ON FIRST WRITE AND THE CORRECTION IS THE POINT. The obvious fixture —
  # `--changed <nonexistent-file>` — does NOT produce an underivable class: promotion-readiness.sh
  # fail-safes an unreadable change-set to `control-plane` (measured: rc 0, output `control-plane`).
  # So that fixture would have FAILed for LEG 2's reason (no GO record) while claiming to prove
  # fail-closed derivation — a TAUTOLOGICAL DUPLICATE of leg 2 that leaves derive_class's `return 1`
  # branch dead and unproven. The real branch is only reachable when the AUTHORITY ITSELF is
  # unavailable, so that is what this leg builds, and it asserts the SPECIFIC verdict text rather than
  # a bare non-zero rc — going through the exit code alone is exactly what made it confusable.
  _legs=$((_legs+1))   # leg3
  _nodir="$_tmp/no-authority"
  mkdir -p "$_nodir/conformance"
  _leg3_out="$( DIR="$_nodir" run_ceremony_binding --changed "$_tmp/changed-cp" --scope PR-1 2>&1 || true )"
  case "$_leg3_out" in
    *UNDERIVABLE*) echo "PASS leg3: authority unavailable -> FAIL closed, verdict names UNDERIVABLE" ;;
    *) echo "FAIL leg3: expected an UNDERIVABLE fail-closed verdict, got: $_leg3_out"; _fails=$((_fails+1)) ;;
  esac

  # ---- T2 legs: the GO record must NAME a real, tracked, non-placeholder artifact.
  # Fixture repos are real git repos with real notes — a mocked note would prove nothing about the
  # parsing this check actually does in production.

  # (The identification-only liveness leg that lived here was REMOVED when T3 landed, not repaired.
  # Once ordering was enforced it began failing correctly — a single-commit fixture has no merge base,
  # so the check fails closed — and propping it up with a synthetic base would have made it assert a
  # state production never reaches. LEG 9 is the liveness anchor: it passes through applicability,
  # identification AND ordering end to end, so identification's PASS path stays proven.)

  # LEGS 5-8 assert the SPECIFIC VERDICT TEXT, never a bare non-zero rc.
  # ⚠️ THE REASON IS MEASURED, NOT STYLISTIC. Two legs in this file were caught failing for a DIFFERENT
  # reason than the one they named (leg 3's fixture, and leg 5's `none` fixture which had no commit and
  # therefore no record at all). Both would have shipped GREEN and proven nothing. An rc-only assertion
  # cannot tell "refused because the basis is untracked" from "refused because there is no record" —
  # so every negative leg below names the verdict it expects.
  _mkfix "$_tmp/f5" design "docs/architecture/absent-design.md" none
  _expect_fail leg5 "$_tmp/f5" "not a tracked file" "basis names an untracked path"

  _mkfix "$_tmp/f6" design "docs/architecture/d-design.md" stub
  _expect_fail leg6 "$_tmp/f6" "PLACEHOLDER (template)" "basis names a template stub"

  # Distinct signal from leg 6: that one fires `template`, this one fires `floor`. Discovered during T2
  # when a 5-line fixture read PLACEHOLDER(floor) — without this leg the floor half of the detector
  # would be relied on in production and proven by nothing here.
  _mkfix "$_tmp/f6b" design "docs/architecture/d-design.md" thin
  _expect_fail leg6b "$_tmp/f6b" "PLACEHOLDER (floor)" "artifact below the substance floor"

  # The line-anchoring proof: `gate: plan` must not match `^gate: design$`.
  _mkfix "$_tmp/f7" plan "docs/architecture/d-design.md" real
  _expect_fail leg7 "$_tmp/f7" "no '--gate design' record was found" "wrong-gate record"

  # LEG 13 (HIGH-1, THE LOAD-BEARING NEGATIVE FOR RECORD BINDING) — a perfectly valid design record
  # scoped to a DIFFERENT change must NOT satisfy this one. Before the scope binding, the first
  # `gate: design` note in the ledger satisfied every future control-plane PR, so the gate went
  # permanently green after its own first use.
  _scope=PR-999 _mkfix "$_tmp/f13" design "docs/architecture/d-design.md" real
  _expect_fail leg13 "$_tmp/f13" "NONE is scoped to this change" "GO record scoped to a different change"

  # LEG 14 (HIGH-2) — a record with NO approved-by line must FAIL. A hand-written `git notes add` that
  # never went through promotion-verify.sh has no derived assurance label, and before this the check
  # read only gate: and basis:, so an approver-free note passed while three shipped claims said a named
  # human had approved.
  _label=NONE _mkfix "$_tmp/f14" design "docs/architecture/d-design.md" real
  _expect_fail leg14 "$_tmp/f14" "no valid 'approved-by:" "GO record with no approver line"

  # LEG 15 (HIGH-2, control-plane tier) — [self-asserted] is rejected at control-plane. Solo-compatible:
  # the owner IS the committer of the design commit, so [committer] is reached at no cost.
  _label="self-asserted" _mkfix "$_tmp/f15" design "docs/architecture/d-design.md" real
  _expect_fail leg15 "$_tmp/f15" "stronger than" "self-asserted assurance at control-plane"

  # LEG 15b (self-attack) — a DECOY second label must not override a weaker first one. `##*[` is greedy,
  # so `X [self-asserted] [committer]` extracted `committer` and passed the control-plane tier.
  _label="self-asserted] [committer" _mkfix "$_tmp/f15b" design "docs/architecture/d-design.md" real
  _expect_fail leg15b "$_tmp/f15b" "trailing decoy" "decoy second assurance label"

  # LEG 15c (self-attack) — `authenticated:` is not a wildcard; only `authenticated: <forge>-review` is
  # a label promotion-verify.sh can derive. `[authenticated: nonsense]` used to pass.
  _label="authenticated: nonsense" _mkfix "$_tmp/f15c" design "docs/architecture/d-design.md" real
  _expect_fail leg15c "$_tmp/f15c" "unrecognised assurance label" "fabricated authenticated label"

  # LEG 5c (IMP-6) — `(none recorded)` is promotion-verify.sh's DEFAULT basis when --basis is omitted,
  # which makes it the most reachable of the fail-closed branches: 46 of this repo's 61 real records
  # carry exactly that literal.
  _mkfix "$_tmp/f5c" design "(none recorded)" real
  _expect_fail leg5c "$_tmp/f5c" "names no artifact" "GO record with the default empty basis"

  # LEG 13b (security MED-2) — a multi-line --scope must be REFUSED at the boundary. `grep -F` treats a
  # newline as a pattern separator, so `PR-9\ngate: design` became an OR that every design record
  # satisfies by construction, bypassing the binding entirely.
  # ⚠️ THIS LEG WAS VACUOUS AND MUTATION IS THE ONLY REASON I KNOW. It asserted rc alone, and
  # MUTANT-H (neuter the --scope charset check) left it PASSING — a multi-line scope then matched
  # `gate: design` as an OR, proceeded, and died later on `basis:`, so rc was non-zero for a wholly
  # unrelated reason. It was also the ONLY negative leg checking rc alone, which made this file's own
  # rule at the top of this section false, and made the shipped claim "every negative asserts its
  # specific verdict text" false in CHANGELOG.md and conformance/README.md. Fifth vacuous leg in this
  # slice; the other four were caught the same way.
  _legs=$((_legs+1))   # leg13b
  _out13b="$( run_ceremony_binding --changed "$_tmp/changed-cp" \
                --scope "$(printf 'PR-9\ngate: design')" 2>&1 || true )"
  case "$_out13b" in
    *"may contain only"*) echo "PASS leg13b: multi-line --scope -> refused at the boundary" ;;
    *) echo "FAIL leg13b: expected a boundary refusal naming the charset, got: $_out13b"
       _fails=$((_fails+1)) ;;
  esac

  # LEG 18 (security HIGH-1 residual, round 3) — a GO whose approved-sha does NOT touch the artifact it
  # names must FAIL. This is the artifact binding: without it a scoped GO could name design doc A while
  # approving commit B, and security reproduced a brand-new branch with ZERO design authored passing on
  # the production path by pointing `basis:` at a pre-existing doc.
  _asha_override=BASE _mkfix "$_tmp/f18" design "docs/architecture/d-design.md" real
  _expect_fail leg18 "$_tmp/f18" "does not touch the artifact" "GO approving a commit that never touched the artifact"

  # LEG 19 — a GO with no approved-sha at all must FAIL (the field promotion-verify.sh already mandates).
  _asha_override=NONE _mkfix "$_tmp/f19" design "docs/architecture/d-design.md" real
  _expect_fail leg19 "$_tmp/f19" "no usable 'approved-sha:'" "GO record with no approved-sha"

  # LEG 19b (liveness, security HIGH-2) — an ABBREVIATED approved-sha must PASS. 27 of this repo's 61
  # real GO records carry one, so an un-normalised comparison merge-blocks a compliant branch. This is
  # a LIVENESS leg: the negative direction is already covered by leg18/leg19, and what needed proving
  # is that the normalisation does not merely widen the check into accepting anything.
  _legs=$((_legs+1))   # leg19b
  # LEG 19c (reviewer I-A) — a SYMBOLIC approved-sha must FAIL. The normalisation that fixed the
  # abbreviated-SHA false RED also let `HEAD` and branch names through, and those re-resolve on every
  # run, so the record would bind to whatever the tip happens to be. Regression from my own fix.
  _asha_override=SYMBOLIC _mkfix "$_tmp/f19c" design "docs/architecture/d-design.md" real
  _expect_fail leg19c "$_tmp/f19c" "must be a hex object name" "symbolic approved-sha (HEAD)"

  _asha_override=SHORT _mkfix "$_tmp/f19b" design "docs/architecture/d-design.md" real
  if ( cd "$_tmp/f19b" && run_ceremony_binding --changed "$_tmp/changed-cp" --scope PR-1 ) >/dev/null 2>&1; then
    echo "PASS leg19b: abbreviated approved-sha -> PASS (normalised before comparison)"
  else
    echo "FAIL leg19b: an abbreviated approved-sha must not false-RED a compliant record"
    _fails=$((_fails+1))
  fi

  # LEG 5d (reviewer C-A / security HIGH-2, THE LOAD-BEARING NEGATIVE FOR THE ARTIFACT) — a GO naming
  # an ordinary tracked file must FAIL. Both reviewers independently reproduced a repo with ZERO design
  # documents passing the DESIGN GATE by pointing `basis:` at README.md / CHANGELOG.md — substantive
  # markdown the payload commit already touched. Evade cost was ZERO, cheaper than all five defeats
  # that got the ordering predicate withdrawn, and it defeated the gate's entire remaining claim.
  _mkfix "$_tmp/f5d" design "README.md" real
  _expect_fail leg5d "$_tmp/f5d" "not a design artifact" "GO naming an ordinary file as the design"

  # LEG 5e (self-attack) — a UNIVERSAL CB_DESIGN_GLOB must be REFUSED, not honoured. Found by
  # self-attacking my own C-A fix: `CB_DESIGN_GLOB='*'` reopened the entire defect the constraint was
  # added to close. The value is environment-borne (the weaker shape the kit has already banked) AND
  # gate-defining, so the one value that silently disables the check must not be accepted. Same
  # precedent as obligation_gate refusing a glob that matches every path.
  _legs=$((_legs+1))   # leg5e
  if ( CB_DESIGN_GLOB='*' sh "$0" --selftest ) >/dev/null 2>&1; then
    echo "FAIL leg5e: a universal CB_DESIGN_GLOB must be refused"; _fails=$((_fails+1))
  else
    echo "PASS leg5e: universal CB_DESIGN_GLOB -> refused"
  fi

  _mkfix "$_tmp/f8" design "../../../etc/passwd" real
  _expect_fail leg8 "$_tmp/f8" "absolute or contains" "traversal basis path"

  # LEG 8b (MED-5) — a TRACKED SYMLINK whose target lies outside the tree must FAIL. `ls-files` proves
  # the link is tracked but does not confine the target; the header used to claim otherwise.
  _mklink "$_tmp/f8b"
  _expect_fail leg8b "$_tmp/f8b" "is a SYMLINK" "basis is a tracked symlink escaping the tree"

  # (The ordering legs that lived here — 9, 10, 10b, 11, 16, 17 — were REMOVED with the ordering
  # predicate itself, design §4.4. They tested strict ancestry, the commit partition, the
  # anti-vacuity commit count and the derivation hardening, none of which exist any more.
  # They are NOT commented out and must not be revived piecemeal: a leg for a predicate the
  # check no longer has is the vacuous-green class this file has already produced five times.
  # LEG 12 — proves the deadlock the plan worried about CANNOT occur, so no exemption is needed.
  # A change-set of ceremony + version-finishing paths only derives `ordinary` (measured: every one of
  # VERSION/CHANGELOG.md/README.md/BACKLOG.md/docs/architecture/*/docs/plans/* is ordinary), so it
  # returns N-A long before the anti-vacuity backstop can see it.
  _legs=$((_legs+1))   # leg12
  printf '%s\n' 'docs/architecture/x-design.md' 'docs/plans/x-plan.md' VERSION CHANGELOG.md README.md \
    BACKLOG.md > "$_tmp/changed-ceremony"
  if run_ceremony_binding --changed "$_tmp/changed-ceremony" --scope PR-1 >/dev/null 2>&1; then
    echo "PASS leg12: ceremony + version-finishing only -> N-A (no deadlock, no exemption needed)"
  else
    echo "FAIL leg12: a ceremony-only change-set should be N-A"; _fails=$((_fails+1))
  fi

  if [ "$_fails" -eq 0 ]; then
    # COUNT IS COMPUTED, NEVER HARDCODED. It drifted twice — 17->18 unnoticed, then 25 while 20 ran
    # after the ordering legs were deleted — and a hardcoded total is a claim the file makes about
    # itself that nothing checks. Now it cannot disagree with reality.
    echo "OK: ceremony-binding --selftest ($_legs legs)"; return 0
  fi
  echo "FAIL: ceremony-binding --selftest — $_fails leg(s) failed"; return 1
}

# _expect_fail <leg-name> <fixture-dir> <expected-substring> <description>
# The kill assertion for every negative leg: the run must FAIL *and* its verdict must contain the
# expected text. A leg that only checks rc cannot distinguish its own failure mode from any other, which
# is how two vacuous legs got written in this very file before this helper existed.
_expect_fail() {
  _ln="$1"; _fd="$2"; _exp="$3"; _desc="$4"; _legs=$((_legs+1))
  _out="$( cd "$_fd" && run_ceremony_binding --changed "$_tmp/changed-cp" --scope PR-1 2>&1 || true )"
  if ( cd "$_fd" && run_ceremony_binding --changed "$_tmp/changed-cp" --scope PR-1 ) >/dev/null 2>&1; then
    echo "FAIL $_ln: $_desc should FAIL but PASSed"; _fails=$((_fails+1)); return 0
  fi
  case "$_out" in
    *"$_exp"*) echo "PASS $_ln: $_desc -> FAIL naming '$_exp'" ;;
    *) echo "FAIL $_ln: FAILed for the WRONG reason — expected '$_exp', got: $_out"
       _fails=$((_fails+1)) ;;
  esac
}

# ---- selftest helpers. BELOW the marker DELIBERATELY: the CI non-vacuity sweep mutates only lines
# ABOVE the selftest() marker, so a kill-assertion helper placed above it would be neutered along with
# the code it is meant to police, and the selftest would go vacuous. (writing-conformance-check-selftests)
#
# _mkbare <dir> — a repo with one commit and NO notes ref at all (leg 2's shape). Hermetic: its verdict
# cannot be changed by whatever the surrounding repository's GO ledger happens to contain.
_mkbare() {
  mkdir -p "$1"
  (
    cd "$1" || exit 1
    git init -q 2>/dev/null
    git config user.email fixture@example.invalid; git config user.name Fixture
    printf 'fixture repo\n' > README.md
    git add -A 2>/dev/null; git commit -q -m fixture >/dev/null 2>&1
  )
}

# _mklink <dir> — a fixture whose basis is a TRACKED SYMLINK pointing outside the repository.
_mklink() {
  # `docs/architecture`, not `docs` — the basis must satisfy CB_DESIGN_GLOB, and if this mkdir is wrong
  # the `ln -s` below fails, which under `set -e` aborts the ENTIRE selftest with no diagnostic at all
  # (third time that failure mode has bitten in this file; it presents as a short run, not an error).
  _d="$1"; mkdir -p "$_d/docs/architecture" "$_d/../outside-$$"
  printf '%s\n' '# Outside' 'content that lives outside the repository and appears in no diff' \
    > "$_d/../outside-$$/notes.md"
  (
    cd "$_d" || exit 1
    git init -q 2>/dev/null
    git config user.email fixture@example.invalid; git config user.name Fixture
    printf 'fixture repo\n' > README.md
    ln -s "../../../outside-$$/notes.md" docs/architecture/d-design.md 2>/dev/null
    git add -A 2>/dev/null; git commit -q -m fixture >/dev/null 2>&1
    printf '%s\n' "record: promotion GO (approve->execute->log)" "gate: design" \
      "scope: PR-1" "approved-by: Fixture Human [committer]" "approved-sha: $(git rev-parse HEAD)" \
      "change-class: control-plane" "basis: docs/architecture/d-design.md" \
      | git notes --ref=promotions add -f -F - HEAD 2>/dev/null
  )
}



# _mkfix <dir> <gate> <basis> <doc-kind>
#   doc-kind: real = a filled design doc . stub = an unfilled template . none = no doc at all
_mkfix() {
  _d="$1"; _gate="$2"; _basis="$3"; _kind="$4"
  _sc="${_scope:-PR-1}"; _lb="${_label:-committer}"; _ao="${_asha_override:-}"
  # _label=NONE builds a record with NO approved-by line at all (leg 14's shape).
  if [ "$_lb" = NONE ]; then _apline="change-class: control-plane"
  else _apline="approved-by: Fixture Human [$_lb]"; fi
  mkdir -p "$_d/docs/architecture"
  (
    cd "$_d" || exit 1
    git init -q 2>/dev/null
    git config user.email fixture@example.invalid
    git config user.name Fixture
    # `real` must clear obl_is_placeholder's SUBSTANCE FLOOR: >= OBL_MIN_SUBSTANCE_LINES (8) non-blank
    # lines under at least one markdown heading. Measured during T2 — a 5-line fixture read
    # PLACEHOLDER(floor), which is the detector working correctly, not a defect. Keep this >= 8 or leg 4
    # silently stops proving the PASS path.
    case "$_kind" in
      real) printf '%s\n' \
              '# Design — fixture' '' '## Approach' \
              'The gate derives the change class from the single hardened authority and refuses to' \
              'classify a change-set it cannot read. The trade-off is that a stricter refusal costs' \
              'an operator an explicit re-record when the base is unreachable, which is the fail-safe' \
              'direction and the one this kit takes everywhere else.' \
              'Identification rides on the GO record rather than a registry, so the ordering claim' \
              'below is non-trivial instead of vacuously true of every document in history.' \
              '## Honest ceiling' \
              'Proves existence and commit-graph order only; it does not prove the design is sound,' \
              'and a rebase can manufacture the ordering it checks.' \
              > docs/architecture/d-design.md ;;
    # `stub` must CLEAR the substance floor and still be caught by the template signal — otherwise it
    # fires `floor` and becomes a duplicate of the `thin` fixture, testing one signal twice while
    # leaving the other unproven. That is exactly what happened on first write (measured: leg 6 fired
    # PLACEHOLDER(floor)), and it is why every negative leg asserts its verdict text. Needs >= 8
    # non-blank lines under a heading AND >= 3 stub markers (Signal 2's threshold).
    # Stub markers use OBL_DEFAULT_STUB_PATTERN's ACTUAL vocabulary ([summary]/[threat]/[why]), not an
    # invented one. Measured on first write: `[attach]` is NOT in the default pattern, so a fixture full
    # of it read FILLED and leg 6 passed while claiming to prove stub rejection — the third tautology
    # this file produced. >= 3 markers (Signal 2's threshold) and >= 8 non-blank lines (the floor), so
    # the TEMPLATE signal is the one under test and not the floor.
      stub) printf '%s\n' \
              '# Design' '' '## Approach' \
              '[summary]' '[threat]' '[why]' \
              'Filler prose so the record clears the substance floor and the template signal is the' \
              'one under test here, rather than the floor signal the thin fixture exercises.' \
              'This line and the next exist only to put the record above the eight-line minimum.' \
              '## Honest ceiling' '[summary]' \
              > docs/architecture/d-design.md ;;
      thin) printf '%s\n' '# Design' '' '## Approach' 'One real sentence, no stub vocabulary at all.' \
              > docs/architecture/d-design.md ;;
    esac
    # ALWAYS produce a commit, even for `none`. Without this the `none` fixture had nothing to commit,
    # so it had no HEAD, so `git notes add` failed, so there was no GO record at all — and leg 5 then
    # FAILed for LEG 2's reason ("no record") while claiming to prove "basis names an untracked path".
    # Second instance of the tautological-leg class in this file (see leg 3); a leg must fail for the
    # reason it names, so the fixture has to differ from the passing case in exactly ONE respect.
    printf 'fixture repo\n' > README.md
    git add -A 2>/dev/null
    git commit -q -m "fixture" >/dev/null 2>&1
    # approved-sha shapes: default = the commit that authored the basis (HEAD);
    # BASE = an empty commit that touches nothing (leg18); NONE = omit the line (leg19).
    case "$_ao" in
      BASE) git commit -q --allow-empty -m "unrelated" >/dev/null 2>&1
            _ashaline="approved-sha: $(git rev-parse HEAD)" ;;
      SHORT) _ashaline="approved-sha: $(git rev-parse --short HEAD)" ;;
      SYMBOLIC) _ashaline="approved-sha: HEAD" ;;
      NONE) _ashaline="change-class: control-plane" ;;
      *)    _ashaline="approved-sha: $(git rev-parse HEAD)" ;;
    esac
    printf '%s\n' "record: promotion GO (approve->execute->log)" \
      "gate: $_gate" "scope: $_sc" "$_apline" "$_ashaline" \
      "change-class: control-plane" "basis: $_basis" \
      | git notes --ref=promotions add -f -F - HEAD 2>/dev/null
  )
}

case "${1:-}" in
  --selftest) selftest ;;
  *) run_ceremony_binding "$@" ;;
esac
