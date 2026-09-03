#!/bin/sh
# Why this gate: docs/architecture/2026-07-26-loop-ceremony-binding-design.md
# ceremony-binding.sh — LOOP-CEREMONY-BINDING Slice 1: the DESIGN GATE backstop.
#
# A Sensitive/Control-plane change-set MUST carry a design artifact that (a) is named by a recorded
# `--gate design` GO SCOPED TO THIS CHANGE, (b) is tracked, not a symlink, and real rather than a stub,
# and (c) is touched by the commit that GO approves. Ordinary change-sets are N-A: nothing is required.
#
# ⚠️ TWO ARMS SINCE 2026-08-15 (C8, GOVERNANCE-RECORD-PR-HAS-NO-DESIGN-BASIS). A PURE
# GOVERNANCE-RECORD change — a meta-control panel sitting plus its bookkeeping — has NO design of its
# own and never will: its artifact IS the panel record. Three shipped PRs (#508, #517, #532) answered
# that gate defect with the same workaround — point `basis:` at a design document the commit happens
# to amend and disclose it in the token — which is green-while-dark in slow motion, so the class is
# closed rather than routinised. Such a change now records `--gate governance` with a
# `CB_GOV_GLOB` (default `docs/architecture/*-meta-control-*.md`) basis, and is adjudicated by THE
# SAME CHAIN with exactly TWO deltas: the basis GLOB, and a GOVERNANCE DIFF-SHAPE GUARD requiring the
# change's cumulative file list to be a SUBSET of the enumerated governance set (_gov_path_in_set).
# The pass is therefore earned by a DERIVED property of the diff, never by an author's declaration.
#   * `scripts/promotion-verify.sh` is UNCHANGED — `--gate` is free text there (prior art: the inert
#     `gate: design-void`), so the new value costs the record tool nothing.
#   * A record carrying BOTH accepted values is DEFECTIVE by DISQUALIFICATION, never dispatched to
#     one arm by matcher order.
#   * The DESIGN arm is byte-unchanged. The live defective record `1d9f0afa` (gate: design + a
#     meta-control basis) therefore STAYS defective — closing the gap does not retro-cure the
#     ledger's evidence of it.
#   * A MIXED PR (a governance record plus routed control-plane cures) still needs a design basis for
#     its payload. That is the gate being RIGHT, not a gap: the fix is to split the cures into their
#     own boarded slices. The narrowing was stated to the owner at the design GO.
#
# ⚠️ THIS GATE MAKES NO ORDERING CLAIM. It does NOT check that the design preceded the work. The
# ordering predicate was WITHDRAWN after being defeated five times in three adversarial rounds — see
# design §4.4 for the catalogue, and CEREMONY-ORDERING-PROOF for the boarded successor.
#
# THIS IS THE BACKSTOP, NOT THE CONTROL. The control is the touch point itself — the human's recorded
# GO at the DESIGN GATE. This check cannot create that moment; it can only refuse a merge that skipped
# it. See docs/architecture/2026-07-26-loop-ceremony-binding-design.md §4.0.
#
# ⚠️ EXIT CONTRACT — CHANGED, and it is a BREAKING change for anyone who wired this script into their
# own CI (docs/architecture/2026-07-28-waiting-gates-render-as-red-design.md §8.3, §9.3, §9.6).
# SCOPE: this is the GATE-RUN contract. `--selftest` is NOT part of it — it returns 1 on a genuine
# suite failure, so routing a selftest rc through the check-run colour map would render a broken test
# suite as the friendly amber. Arg-parse errors (missing --scope value, unknown argument, a
# --scope outside the permitted charset, a universal CB_DESIGN_GLOB) are rc 2, correctly: they are
# anomalies, not waits.
#
#     0  PASS, or N-A (change-class 'ordinary' — nothing is required)
#     1  WAITING — reserved for EXACTLY ONE state: no `--gate design` GO record scoped to this change
#        exists yet. A human has not approved yet. That is a normal stage of healthy work, and CI
#        renders it YELLOW (status: in_progress, no conclusion) — still BLOCKING, but not a red ✗.
#     2  ANOMALY — everything else. EVERY scoped GO that exists is DEFECTIVE (artifact missing,
#        untracked, stubbed, symlinked, traversing, or not a design artifact; approver line malformed
#        or too weak; approved-sha absent, malformed, unresolvable, or not touching the artifact;
#        C8: a record carrying BOTH accepted gate values, a governance record whose basis is not a
#        governance artifact, or a governance record whose change-set ESCAPES the governance set —
#        including the case where that set could not be DERIVED, which fails CLOSED because the
#        diff-shape guard is the governance arm's only anti-laundering leg),
#        OR the gate could not evaluate at all (change-class UNDERIVABLE, no --scope supplied, a
#        universal CB_DESIGN_GLOB or CB_GOV_GLOB). Renders RED, because something is broken and a
#        human must fix it.
#
# ⚠️ EXIT CONTRACT — CHANGED AGAIN (B7 rider, 2026-08-08; the B2-A1 disclosure class). The match
# loop is now COLLECT-AND-ADJUDICATE-ALL in BOTH modes (--scope and --pre-push): every `gate:
# design` record matching the scope key is adjudicated; rc 0 if ANY survives (the verdict names
# the survivor's sha + the examined count); rc 2 ONLY when every matching record is defective
# (each named with its defect). Previously the first match in annotated-SHA order was adjudicated
# ALONE, so a defective record could SHADOW a valid same-key record by sort-order lottery
# (measured on PR #509: `00c0…` < `924e…`). Single-record semantics are unchanged; anyone who
# wired this script into their own CI and depended on "rc 2 = the first matching record is
# defective" now gets "rc 2 = ALL matching records are defective".
#
# ⚠️ SCOPE MATCH — TWO KEYS (BRANCH-SCOPE-END-TO-END, 2026-08-11; owner ruling D11 + D-240811-3).
# A record MATCHES when its `scope:` equals EITHER `PR-<n>` (the caller-supplied CI key) OR
# `branch/<head-branch>` (the key a design GO can carry BEFORE a PR exists). CI supplies the head
# branch as `--head-branch "$HEAD_REF"` (env-bound, never interpolated into a run: script). That
# RETIRES the [S4]#7 interim protocol — the PR-creation RE-RECORD — and with it the record->poster
# race the re-record caused (measured: one decider rerun per gated PR, 4x). Existing `scope: PR-<n>`
# records keep working forever; nothing is migrated. ONE matcher serves BOTH modes and the render.
#   ⚠️ THE BRANCH KEY IS AUTHOR-CONTROLLED, AND ITS RECORDS ARE NOW PERMANENT (no reaping re-record;
#   `promotion-verify.sh record` only overwrites a SAME-SHA note). `D-240811-3` ratifies that ceiling
#   AS NARROWED by three bounds, all of them live in this file:
#     (a) the D11 charset (`_scope_charset_bad`) — a key the record format cannot express is not a
#         key. `github.head_ref` is chosen by whoever opens the PR, so a charset-out name DROPS the
#         branch key and proceeds PR-KEY-ONLY, DISCLOSED on stderr, rc UNCHANGED (a degraded key is
#         not an anomaly: no record could ever have carried that key, so nothing is lost);
#     (b) CONTAINMENT, IN TWO LEGS — the record's `approved-sha` must be (1) an ANCESTOR of the
#         graded head (reachable: the approved commit is in the history being judged) AND (2) NOT an
#         ancestor of merge-base(graded head, base) (new: the approved commit is not already in the
#         base history). Leg 1 alone is NOT enough and that was MEASURED: once a historic branch is
#         MERGED OR REBASED into the base, its approved-sha sits on the MAINLINE, so a new branch
#         reusing the name inherits it reachably — the record satisfied unrelated work, rc 0. Leg 2
#         closes that class. Its base is `--base-ref <name-or-sha>` when CI supplies one, else the
#         locally-resolvable default branch; when NO base resolves — or when the resolved base
#         already CONTAINS the graded head, so it cannot tell historic work from new — leg 2 is
#         SKIPPED with a DISCLOSED one-line degradation and the rc is unchanged (containment is then
#         REACHABLE-ONLY, and the verdict says so). Never a red on a healthy clone shape, never a
#         silent skip;
#     (c) the `--render` block (D-240805-4) putting every matched record verbatim in front of the
#         human before the click.
#   FORK FACE, stated so a green is never over-read: a fork PR can reproduce both the branch NAME and
#   the approved COMMIT (both public), so its design gate CAN match this repo's record. This gate is
#   ONE required context; the merge control is the owner-only ratification approval, which still
#   fails closed on a fork. A green design gate on a hostile fork is not a merge.
#
# WHY IT CHANGED. Before this, rc 1 meant both "waiting on a human" and every one of the ~16 defects
# above, so routing the rc through the check-run colour map would have painted a FORGED OR BROKEN GO
# RECORD as the friendly yellow "just waiting for approval". Red must survive where it belongs, and the
# discriminator is PHASE-AWARE: red means ANOMALOUS, yellow means a normal expected stage of work.
#
# ⚠️ IF YOU ADD A REFUSAL, IT IS rc 2 unless it is a genuine wait on another party. The selftest's
# `_expect_fail` helper DEFAULTS its expected rc to 2, so a new negative leg asserts this for free and a
# defect accidentally left at rc 1 FAILS the suite (leg8b proved it: mutation-tested during T2).
#
# HONEST CEILING (do not overclaim):
#   * GREEN proves: a design artifact EXISTS, is tracked/non-symlink/non-placeholder, is named by a GO
#     record SCOPED TO THIS CHANGE (either key) whose approver carries a derived assurance label, is
#     TOUCHED by the commit that GO approves, and whose approved commit is CONTAINED in the graded
#     head's history AND — when a base resolves — is NOT already in that base's history. That is all.
#   * CONTAINMENT BOUNDS RECORD REUSE, NOT RECORD MINTING. It stops a historic same-name branch's
#     record vouching for a new branch; it says nothing about who wrote the record (`D-240805-3`'s
#     over-cooperation vector is governed by its own controls and is untouched here).
#   * CONTAINMENT IS TWO LEGS, AND ONLY ONE OF THEM IS ALWAYS AVAILABLE. Leg 2 needs a base history;
#     with none resolvable (shallow clone, no default-branch ref, no `--base-ref`) the run is
#     REACHABLE-ONLY and says so on stderr and in its verdict. A green from such a run does not
#     carry the not-already-integrated half — read the verdict's `containment:` state, not the rc.
#   * GOVERNANCE ARM (C8), what its green does and does NOT prove: it proves the change-set is a
#     SUBSET of the enumerated governance set and that a scoped GO names a touched, tracked,
#     substantive meta-control artifact. It does NOT bind that artifact's CONTENT to this change —
#     the same content-binding ceiling the design arm carries, inherited unchanged; the owner's read
#     of the artifact at the sitting is the content control (`D-240805-4`). And the governance set is
#     an ENUMERATION: a legitimate new governance surface REDS until it is added (fail direction
#     chosen deliberately — over-tight is loud, over-wide is green-while-dark). A governance-lane PR
#     can still carry a WRONG panel record — bad judgment in the right shape — and the review seat
#     plus ratification remain the semantic control, exactly as for a design basis.
#   * ⚠️ GOVERNANCE ARM — THE BASE-LADDER ASYMMETRY, disclosed because it bounds the arm in three
#     directions at once. The diff-shape guard's change-set comes from promotion-readiness.sh, whose
#     base ladder is `origin/main` then `main` ONLY; containment leg 2, by contrast, honours a
#     caller-supplied `--base-ref`. So the two legs of this gate can measure against DIFFERENT bases:
#       (a) WRONG SET — a governance PR targeting a non-`main` base is graded against `main`, so the
#           subset judgment is made over a change-set that is not this PR's;
#       (b) LANE UNAVAILABLE TO SOME ADOPTERS — where the default branch is `master`/`trunk`/`develop`
#           and no `origin/main` exists, the derivation NEVER resolves, so the guard fails CLOSED
#           permanently and the governance lane cannot be used at all. The refusal names `fetch-depth:
#           0`, and THAT CURE DOES NOT HELP HERE: the problem is the ladder, not the clone depth. Read
#           the refusal as "no base resolved", not as "fetch more history";
#       (c) A FAIL-OPEN FACE THAT ANOTHER LEG CATCHES — if the graded head is already contained in the
#           resolved base (e.g. a reused branch merged into main), the derived set is EMPTY, an empty
#           set is trivially a subset, and this guard PASSES. What stops that being a bypass is
#           CONTAINMENT LEG 2 (ALREADY-INTEGRATED), which refuses the record outright. So the
#           governance arm's anti-laundering property is NOT self-contained: it depends on leg 2 being
#           evaluable. Where leg 2 is itself skipped (no base resolves) the guard has already failed
#           closed by (b), which is why the two degradations do not compose into a hole — but the
#           dependency is real and is stated here rather than discovered later.
#     Cure boarded as GOVERNANCE-GUARD-BASE-REF-PLUMB (LOW/XS: plumb `--base-ref` through
#     `--changed-files` so both legs measure against the same named base).
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
# THE SAME SINGLE-AUTHORITY RULE GOVERNS THE PRE-PUSH SCOPE KEY (prepush_scope_key, D11), and
# `--print-scope-key` is its ONE SANCTIONED CONSUMER PATH: a read-only print of that function's
# answer for hooks/pre-push, which must never re-derive a branch key of its own.
#
# Usage:
#   sh conformance/ceremony-binding.sh --scope PR-42 [--head-branch feat/x] [--base-ref main]
#                                                      (the CI predicate; two keys — the PR key and,
#                                                       when a head branch is supplied, `branch/feat/x`.
#                                                       --base-ref names the history containment leg 2
#                                                       measures "already integrated" against; without
#                                                       it the locally-resolvable default branch is
#                                                       used, and with neither, leg 2 is skipped and
#                                                       the degradation is disclosed)
#   sh conformance/ceremony-binding.sh --pre-push      (hook mode, B2 Δ1′: the SAME predicate, keyed on
#                                                       the DERIVED scope `branch/<current-branch>`
#                                                       instead of the caller-supplied `PR-<n>`)
#   sh conformance/ceremony-binding.sh --render --scope PR-42 [--head-branch feat/x]
#                                                      (the D-240805-4 visibility block on STDOUT, for
#                                                       $GITHUB_STEP_SUMMARY. THE SINGLE SOURCE of the
#                                                       render: both workflow legs INVOKE this, and the
#                                                       parity lock refuses a leg that regrows a copy.)
#   sh conformance/ceremony-binding.sh --print-scope-key
#                                                      (prints the DERIVED pre-push key
#                                                       `branch/<name>` and grades nothing; rc 1
#                                                       detached HEAD, rc 2 charset-out branch,
#                                                       rc 3 bad usage. hooks/pre-push's only
#                                                       sanctioned way to learn the branch key.)
#   sh conformance/ceremony-binding.sh --selftest
#
# What it changes: nothing — read-only. Reads the working tree, git history, and refs/notes/promotions.
# Guardrails: fails CLOSED on an underivable change-class, an unreadable notes ref, a `basis:` path
# that does not resolve to a tracked file, a placeholder artifact, a `basis:` that is not a design
# artifact (or, on the governance arm, not a governance artifact), an `approved-sha:` that is not a
# hex object name or does not touch the artifact it approves, a record carrying BOTH accepted gate
# values, and — governance arm — a change-set that escapes the governance set or cannot be derived.
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

# ---- THE GOVERNANCE ARM's basis shape (C8, GOVERNANCE-RECORD-PR-HAS-NO-DESIGN-BASIS).
# A PURE governance-record change — a meta-control panel sitting and its bookkeeping — has no design
# of its own and never will: its artifact IS the panel record. Before this arm the only honest options
# were to skip the gate or to point `basis:` at a design document the commit happened to amend, which
# is what three shipped PRs did (#508, #517, #532 — the third was the workaround's last sanctioned
# use). That is a green-while-dark workaround for a gate defect, so the class is closed HERE instead:
# such a change records `--gate governance` with a meta-control artifact as its basis, and earns the
# pass by a DERIVED property (the diff shape, below) rather than by an author's declaration.
CB_GOV_GLOB="${CB_GOV_GLOB:-docs/architecture/*-meta-control-*.md}"
# ITS OWN universal-glob refusal, not a share of CB_DESIGN_GLOB's. Two globs, two refusals: a single
# shared check would have to be written against whichever variable it names, and the OTHER one would
# then be the unguarded off-switch — the exact shape of the defect leg5e exists for. `CB_GOV_GLOB='*'`
# would let ANY substantive tracked file be the "panel artifact", and since the governance arm's diff
# guard admits `skills/*/SKILL.md` and `docs/architecture/*-design.md`, that is the wider hole of the
# two, not the narrower.
case "$CB_GOV_GLOB" in
  ''|'*'|'**'|'*'*'*'|'?*')
    echo "ceremony-binding: CB_GOV_GLOB must not match every path — that disables the governance-artifact" >&2
    echo "  constraint entirely. Narrow it to your meta-control-artifact convention." >&2
    exit 2 ;;
esac

# THE GOVERNANCE SET — the ENUMERATED file set a `gate: governance` change may touch, and the arm's
# ONLY anti-laundering predicate. Membership is checked against the set that
# conformance/promotion-readiness.sh --changed-files DERIVES (never a local `git diff` — see
# _gov_diff_shape_guard), so class and shape are computed over the SAME paths.
#   ⚠️ IT IS AN ENUMERATION, AND THE FAIL DIRECTION IS DELIBERATE. A legitimate NEW governance surface
#   (some future bookkeeping file) REDS until it is added here. Over-tight is loud and safe — the
#   operator splits the change or records a design GO; over-wide is green-while-dark, which is the
#   whole defect this arm closes. Widening it is a control-plane change with its own ratification, and
#   the family risk is boarded as GOVERNANCE-SET-FAMILY-LOCK.
#   ⚠️ `skills/*/SKILL.md` and `docs/architecture/*-design.md` are the SHARPEST members: they are the
#   measured routed-cure surfaces (a sitting amends a skill; a panel appends to a design's §10 log).
#   Both are CONTROL-PLANE by the kit's own classifier — do not read them as harmless. What makes them
#   admissible is narrower and stated exactly: they carry no MACHINE-EXECUTABLE surface, so a change to
#   one cannot alter what CI or the guard DOES; the control over what they say is the owner's
#   ratification of the PR, not this gate. Both were named to the owner at the design GO.
_gov_path_in_set() {   # <path> -> 0 (true) when the path is INSIDE the governance set
  case "$1" in
    BACKLOG.md|docs/governance/DECISIONS.md|docs/governance/.meta-control-last) return 0 ;;
    docs/governance/meta-control-log.md|docs/kit-internals/meta-control.md) return 0 ;;
    # POSIX `case` globbing does not stop `*` at a '/', so this also admits a nested
    # `skills/a/b/SKILL.md`. Deliberate and harmless: the member is the SKILL.md convention, not a
    # depth rule, and nothing else in the tree is named SKILL.md.
    skills/*/SKILL.md) return 0 ;;
  esac
  # ONE SPELLING for the meta-control family: the SAME glob the basis leg matches. Two spellings would
  # let an adopter narrow the basis convention while the diff guard kept admitting the old shape (or
  # the reverse) — a drift with nothing locking the halves together.
  # shellcheck disable=SC2254 # UNQUOTED ON PURPOSE: these are glob patterns, expanded as such. See
  # the identical disable at the design-artifact leg.
  case "$1" in $CB_GOV_GLOB) return 0 ;; esac
  # shellcheck disable=SC2254 # same reason
  case "$1" in $CB_DESIGN_GLOB) return 0 ;; esac
  return 1
}

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
# ★ THE CHILD'S ENVIRONMENT IS SCRUBBED, NOT INHERITED (review REV-I1) — the `env -u` precedent
# conformance/backlog-presence.sh already applies to this exact classifier, extended to the input
# GUARD-PATH-ENUMERATION-INCOMPLETE S2 added. MEASURED: with `KIT_ADAPTERS_DIR` pointing at an empty
# directory, `--class` answers `ordinary` for a `GEMINI.md`-only change-set, so an ambient variable
# would decide whether this gate's ordinary-class short-circuit applies. `KIT_UNION_LIB` is scrubbed
# in the same breath: it selects the matcher. Arguments, not env.
derive_class() {   # args: [--changed FILE]
  _dc_out=""
  if [ "${1:-}" = "--changed" ] && [ -n "${2:-}" ]; then
    _dc_out="$(env -u KIT_ADAPTERS_DIR -u KIT_UNION_LIB sh "$DIR/conformance/promotion-readiness.sh" --changed "$2" --class 2>/dev/null | tail -1)" || _dc_out=""
  else
    _dc_out="$(env -u KIT_ADAPTERS_DIR -u KIT_UNION_LIB sh "$DIR/conformance/promotion-readiness.sh" --class 2>/dev/null | tail -1)" || _dc_out=""
  fi
  case "$_dc_out" in
    ordinary|sensitive|control-plane) printf '%s\n' "$_dc_out"; return 0 ;;
    *) return 1 ;;
  esac
}

# SCOPE CHARSET — ONE definition, used by the --scope boundary validator AND by the derived pre-push
# key. Widening it here widens both, deliberately: a key the record format cannot express is not a
# key. (promotion-verify.sh applies the same rule to the `branch/` shape at the front door.)
_scope_charset_bad() {   # <candidate> -> 0 (true) when it is empty or holds a disallowed character
  case "$1" in
    ''|*[!A-Za-z0-9_.:/-]*) return 0 ;;
  esac
  return 1
}

# prepush_scope_key — THE derivation of the pre-push scope key (owner ruling D11, 2026-07-28:
# "the GO record gains branch scoping — `scope: branch/<name>` alongside `scope: PR-<n>`", which is
# what lets a design GO bind BEFORE a PR exists).
#
# ⚠️ D11'S OWN TRAP WARNING IS BINDING, AND THIS FUNCTION IS THE ANSWER TO IT: BOTH consumers — this
# predicate and hooks/pre-push — must read the branch key from THIS ONE PLACE. The hook must NEVER
# re-derive it. That is the SIXTH-DERIVATION TRAP the file header already refuses for the CHANGE-SET
# derivation (see "CLASS IS DERIVED BY A SINGLE AUTHORITY" above, and the withdrawn ordering
# predicate's defeat #2, where a second derivation site let `git mv` collapse a control-plane
# change-set to ordinary). A second copy in the hook would be defect-compatible only until the two
# spellings drift — and nothing would lock them together.
#
# Prints `branch/<name>` on stdout. Returns 1 = no branch (detached HEAD) · 2 = the branch name is
# outside the scope charset, so no record could ever carry this key. Both are ANOMALIES for the
# caller (rc 2), never the waiting yellow: the gate evaluated nothing.
prepush_scope_key() {
  _ppk_branch="$(git symbolic-ref -q --short HEAD 2>/dev/null)" || _ppk_branch=""
  [ -n "$_ppk_branch" ] || return 1
  _scope_charset_bad "$_ppk_branch" && return 2
  printf 'branch/%s\n' "$_ppk_branch"
  return 0
}

# print_scope_key_mode — the BODY of the `--print-scope-key` dispatch arm (design §3.1; hoisted here
# by reviewer R3). It lives ABOVE the selftest() marker on purpose: the non-vacuity sweep mutates
# only pre-marker lines, so a mode whose logic sat in the dispatch case at the foot of the file was
# invisible to it — legs P8a-d would have passed against an unmutatable body. Here the rc partition
# is a mutation target like any other check logic.
#
# It EVALUATES NOTHING and grades NOTHING: it relays prepush_scope_key's answer so hooks/pre-push's
# board-presence leg can name the branch without deriving a second key (D11's single-derivation
# rule — see that function's own trap warning). The rc partition IS the contract:
#   0 = `branch/<name>` on stdout · 1 = detached HEAD (NOTHING printed, on either stream) ·
#   2 = the branch name is outside the scope charset (nothing on stdout, one stderr reason) ·
#   3 = bad usage.
# rc 3 rather than this file's usual usage rc 2 is load-bearing: a consumer that cannot tell
# "evaluated: unrepresentable" from "could not evaluate: you called me wrong" would silently N/A a
# broken invocation and stop grading (the presence design's A1-1 HIGH). And the rc-1 path must stay
# SILENT: the hook keys its detached-HEAD N/A on "rc 1 AND no stderr" precisely because a `set -eu`
# preamble failure in this file also exits non-zero, but never quietly (that leg's S1).
print_scope_key_mode() {
  if [ "$#" -ne 1 ]; then
    echo "usage: ceremony-binding.sh --print-scope-key   (takes no other argument)" >&2
    return 3
  fi
  _psk_rc=0; _psk_key="$(prepush_scope_key)" || _psk_rc=$?
  case "$_psk_rc" in
    0) printf '%s\n' "$_psk_key"; return 0 ;;
    1) return 1 ;;
    *) echo "ceremony-binding: the checked-out branch name is outside the scope charset (A-Za-z0-9_.:/-), so no record could ever carry its key" >&2
       return 2 ;;
  esac
}

# containment_base — the BASIS for containment LEG 2 ("the approved commit is not already in the base
# history"). Prints merge-base(base, $1); returns 1 when there is no base to measure against, which the
# caller turns into a DISCLOSED skip, never a refusal.
#
# WHY A SECOND LEG AT ALL (fix round 1, security F1 — measured). Leg 1 (ancestor-of-graded-head) alone
# does NOT close the reused-name class the `D-240811-3` ratification claims closed: under merge/rebase
# integration a historic record's approved-sha lands on the MAINLINE, so a new branch of the same name
# inherits it REACHABLY and the record satisfies unrelated work (reproduced: rc 0). Leg 2 asks the
# question leg 1 cannot: is the approved commit NEW to this change, or already part of the base?
#
# LOCAL READS ONLY — no `git fetch`, no `git remote show`. A merge gate that depends on network
# reachability fails for the network's reasons, not the change's. The candidate ladder is the SHAPE
# `conformance/loop-state.sh`'s scope_base uses (pinned/derived candidates, first resolvable wins,
# unresolvable is a disclosed N/A) — re-derived here rather than imported: loop-state is a different
# gate with its own contract, and a shared helper across two gates is the coupling this file already
# refuses for the class derivation ("CLASS IS DERIVED BY A SINGLE AUTHORITY" — the same argument runs
# the other way for a helper neither gate owns).
containment_base() {   # $1 = graded head sha
  # Locals take the `_cbb_` prefix, NOT `_cb_`: that prefix is the ARGUMENT-PARSE state
  # (_cb_scope/_cb_prepush/_cb_head_branch/_cb_base_ref/_cb_render), and a helper that reused it
  # would be one careless name away from overwriting the caller's mode.
  _cbb_cands=""
  if [ -n "$_cb_base_ref" ]; then
    # AUTHOR-INFLUENCED VALUE (CI passes `github.base_ref`). Treated exactly like --head-branch: a
    # value the record charset cannot express, or one that could be read by git as an OPTION, is not
    # refused — it is UNUSABLE, so it yields the disclosed skip. Refusing would let the choice of base
    # branch paint this gate red, which is a denial of service through an input we cannot use anyway.
    case "$_cb_base_ref" in -*) return 1 ;; esac
    _scope_charset_bad "$_cb_base_ref" && return 1
    # A CI checkout has the base as a REMOTE ref, not a local branch, so all three spellings are
    # tried — in caller-first order, so an explicit sha or local ref always wins.
    _cbb_cands="$_cb_base_ref origin/$_cb_base_ref refs/remotes/origin/$_cb_base_ref"
  else
    # NO BASE SUPPLIED (the --pre-push route, and any adopter CI that has not wired --base-ref):
    # derive the default branch locally. Nothing here is environment-overridable.
    _cbb_dh=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
    _cbb_cands="$_cbb_dh origin/main origin/master main master"
  fi
  # shellcheck disable=SC2086 # deliberate word-split of the candidate list; every element is either a
  # fixed literal or charset-checked above, so it cannot contain whitespace.
  for _cbb_c in $_cbb_cands; do
    [ -n "$_cbb_c" ] || continue
    git rev-parse -q --verify "$_cbb_c^{commit}" >/dev/null 2>&1 || continue
    if _cbb_mb=$(git merge-base "$_cbb_c" "$1" 2>/dev/null) && [ -n "$_cbb_mb" ]; then
      printf '%s\n' "$_cbb_mb"
      return 0
    fi
  done
  # NO FALLBACK from a SUPPLIED base ref to the derived ladder, deliberately: judging containment
  # against a history nobody named would be a different question answered silently. Unresolvable is
  # the disclosed skip, which is the fail-safe direction.
  return 1
}

# _assemble_scope_keys — THE SINGLE DERIVATION of "which scope keys bind a record to this change",
# consumed by the gate loop, by --render, and by the operator guidance. Reads $_cb_prepush /
# $_cb_scope / $_cb_head_branch; sets:
#   $_scope_keys    space-separated key list (every element inside the D11 charset, so word-splitting
#                   it is exact rather than lucky — the charset excludes space and newline)
#   $_record_key    the key to PRINT in "record one like this" guidance — the BRANCH key when there
#                   is one, because after Δ4 that is the key that never needs a re-record
#   $_keys_display  the same list rendered for humans ("PR-7 or branch/feat/x")
# Returns 0 = at least one usable key · 1 = none could be assembled (caller words the refusal) ·
# 2 = the mode could not derive its key at all (this function already printed the diagnosis).
_assemble_scope_keys() {
  _scope_keys=""; _record_key=""; _keys_display=""
  if [ "$_cb_prepush" -eq 1 ]; then
    _ppk_rc=0; _ppk_key="$(prepush_scope_key)" || _ppk_rc=$?
    case "$_ppk_rc" in
      0) _scope_keys="$_ppk_key"; _record_key="$_ppk_key" ;;
      1) echo "FAIL: ceremony-binding --pre-push — HEAD is not on a branch (detached HEAD), so there is no" >&2
         echo "      'branch/<name>' key to match a GO record against. The gate evaluated NOTHING, which is" >&2
         echo "      an anomaly and not a wait (fail closed). Check out the branch you are pushing." >&2
         return 2 ;;
      *) echo "FAIL: ceremony-binding --pre-push — the current branch name may contain only [A-Za-z0-9_.:/-]," >&2
         echo "      and this one does not, so NO GO record could ever carry its 'branch/<name>' key. The" >&2
         echo "      charset is the RECORD FORMAT's (promotion-verify.sh --scope), reused here rather than" >&2
         echo "      widened — a key the ledger cannot express is not a key. Rename the branch." >&2
         return 2 ;;
    esac
  else
    if [ -n "$_cb_scope" ]; then _scope_keys="$_cb_scope"; _record_key="$_cb_scope"; fi
    if [ -n "$_cb_head_branch" ]; then
      if _scope_charset_bad "$_cb_head_branch"; then
        # THE DEGRADED-KEY DISCLOSURE (Δ1). NOT an anomaly and NOT silent: the head branch is
        # author-controlled (a fork PR names its own branch), and a name outside the D11 charset is a
        # name NO record could ever carry — so dropping the key loses nothing, while refusing would
        # hand any PR author an rc-2 red on this gate for free. Disclosed on STDERR (stdout in
        # --render mode IS the step-summary block), rc unchanged.
        echo "ceremony-binding: the supplied --head-branch is outside the record format's charset" >&2
        echo "  ([A-Za-z0-9_.:/-]), so NO GO record could carry its 'branch/<name>' key. DROPPING the" >&2
        echo "  branch key and proceeding on the PR key alone — degraded key, not an anomaly; rc" >&2
        echo "  unchanged. (The charset is promotion-verify.sh's own, reused rather than widened.)" >&2
      else
        _scope_keys="${_scope_keys:+$_scope_keys }branch/$_cb_head_branch"
        _record_key="branch/$_cb_head_branch"
      fi
    fi
  fi
  [ -n "$_scope_keys" ] || return 1
  _keys_display="$(printf '%s\n' "$_scope_keys" | sed 's/ / or /g')"
  return 0
}

# _gov_diff_shape_guard — THE GOVERNANCE ARM's anti-laundering predicate (C8). The graded change's
# CUMULATIVE file list must be a SUBSET of the governance set. Returns 0 = the shape is honest;
# 2 = DEFECTIVE (reason on stderr, in the shape check_design_record's callers already render).
#
# ⚠️ THE FILE LIST HAS ONE DERIVATION AUTHORITY, AND IT IS NOT THIS FILE. It is read from
# `promotion-readiness.sh --changed-files`, the mode added with this arm for exactly this consumer.
# Re-deriving it here with a local `git diff` would be the SIXTH DERIVATION the header already refuses
# for the change-CLASS — and it would be defeated on day one: without `--no-renames`, a
# `git mv .github/workflows/ci.yml docs/architecture/x-meta-control-y.md` emits ONLY the destination,
# the out-of-set SOURCE vanishes from the set, and a workflow DELETION launders through the governance
# lane while the class derivation (which does pass --no-renames) still sees it. Class and guard are
# computed over the SAME set by construction; that is the point of the seam.
#
# ⚠️ FAIL CLOSED ON AN UNDERIVABLE SET, and NOT by the containment-leg-2 precedent. Leg 2 discloses and
# SKIPS when no base resolves, because it is one of two containment legs and the other still bites.
# This guard has no sibling: it is the ONLY thing standing between "I recorded a governance GO" and
# "…so my workflow edit rode along", so a skip greens precisely the property the arm exists for. The
# cure is cheap and named in the refusal (`fetch-depth: 0`), and governance PRs exist only on a repo
# that runs this kit's own CI, which already fetches full history for the gate's job.
_gov_diff_shape_guard() {
  _gds_rc=0
  _gds_list="$( sh "$DIR/conformance/promotion-readiness.sh" --changed-files 2>/dev/null )" || _gds_rc=$?
  if [ "$_gds_rc" -ne 0 ]; then
    echo "FAIL: ceremony-binding — GOVERNANCE DIFF-SHAPE: the change-set could not be DERIVED" >&2
    echo "      (conformance/promotion-readiness.sh --changed-files exited $_gds_rc), so the governance" >&2
    echo "      arm's ONLY anti-laundering predicate could not run. FAIL CLOSED: skipping it would pass" >&2
    echo "      exactly the property this arm exists to prove." >&2
    echo "      CURE: give the checkout a base history — 'fetch-depth: 0' on actions/checkout (the" >&2
    echo "      kit's own gate job already does this), or run where origin/main or main resolves." >&2
    return 2
  fi
  _gds_bad=""; _gds_n=0
  # HEREDOC, NOT A PIPE: the loop must run in THIS shell or the escaping-path list dies with the
  # subshell and the guard reports a clean set for a dirty one (the file's own `while | read` trap).
  while IFS= read -r _gds_p; do
    [ -n "$_gds_p" ] || continue
    if _gov_path_in_set "$_gds_p"; then continue; fi
    _gds_n=$((_gds_n + 1))
    _gds_bad="$_gds_bad
        $_gds_p"
  done <<GOV_SET_EOF
$_gds_list
GOV_SET_EOF
  # `if`, never `[ … ] && return 0`: under `set -e` a false `&&` list is itself a non-zero command and
  # would kill the run before the refusal below could be printed (this file has paid that price).
  # CB_GOV_SUBSET_JUDGED is set ON THIS PATH ONLY — the one place where a real list was really walked.
  # The verdict's "SUBSET of the governance set" line is gated on it, so a guard neutered to `return 0`
  # cannot keep printing the claim: the sentence becomes evidence that the judgment happened, instead
  # of an unconditional label. (Build review LOW-6: a leg must assert only what it measures.)
  if [ "$_gds_n" -eq 0 ]; then CB_GOV_SUBSET_JUDGED=1; return 0; fi
  echo "FAIL: ceremony-binding — GOVERNANCE DIFF-SHAPE: $_gds_n path(s) in this change are OUTSIDE the" >&2
  echo "      governance set, so this is not a PURE governance-record change and a 'gate: governance'" >&2
  echo "      GO cannot carry it:" >&2
  printf '%s\n' "$_gds_bad" >&2
  echo "      The governance set is: BACKLOG.md · $CB_GOV_GLOB · docs/governance/DECISIONS.md ·" >&2
  echo "      docs/governance/.meta-control-last · docs/governance/meta-control-log.md ·" >&2
  echo "      docs/kit-internals/meta-control.md · skills/*/SKILL.md · $CB_DESIGN_GLOB" >&2
  echo "      CURE — SPLIT YOUR CURES: route each payload change to its own boarded, designed slice," >&2
  echo "      or record a '--gate design' GO for the payload and let the DESIGN arm judge it. Mixing" >&2
  echo "      routed control-plane cures into a panel PR is the anti-pattern this arm refuses; the" >&2
  echo "      steward's charter routes findings to rows, it does not apply arbitrary cures in place." >&2
  return 2
}

# _matches_scope <record-body> — THE matcher, and the ONLY one. 0 (true) when the record carries a
# `scope:` line equal to ANY assembled key. Line-anchored + fixed-string (`grep -qF -x`) for the same
# reason the gate line is: a substring or multi-line pattern turns the binding into an OR that every
# design record satisfies by construction (measured, leg13b).
_matches_scope() {
  # shellcheck disable=SC2086 # deliberate word-split of the key list; see _assemble_scope_keys.
  for _msk in $_scope_keys; do
    if printf '%s\n' "$1" | grep -qF -x "scope: $_msk"; then return 0; fi
  done
  return 1
}

# _matched_key <record-body> — which key this record actually matched, for an honest verdict line
# ("matched on branch/feat/x" is a different fact from "matched on PR-7"). Prints the first hit.
_matched_key() {
  # shellcheck disable=SC2086 # deliberate word-split of the key list; see _assemble_scope_keys.
  for _mkk in $_scope_keys; do
    if printf '%s\n' "$1" | grep -qF -x "scope: $_mkk"; then printf '%s\n' "$_mkk"; return 0; fi
  done
  return 1
}

# _record_gate_type <record-body> — THE gate-value classifier, and the ONLY one (C8). Prints
# `design`, `governance`, or `design+governance`; returns 1 when the record carries neither accepted
# value, which is how every consumer skips a `gate: plan` / `gate: merge` / `gate: DoD` record.
#
# Each value is matched LINE-ANCHORED and FIXED-STRING, for the reason the design leg already carries:
# a substring test would accept `gate: design-review`, `gate: redesign` or `gate: governance-void`
# (and the ledger HAS prior art for an inert value minted exactly that way — `gate: design-void`).
#
# ⚠️ A RECORD CARRYING BOTH IS REPORTED AS BOTH, NEVER RESOLVED HERE. Adjudication by DISQUALIFICATION
# is the whole point: the two arms judge different things (a design basis; a governance basis plus the
# diff-shape guard), so dispatching on whichever line a matcher happened to see first would make the
# verdict a lottery on a hand-minted note — the same class as the #509 sort-order wedge, through a
# different door. check_design_record turns `design+governance` into a DEFECT.
_record_gate_type() {
  _rgt=""
  if printf '%s\n' "$1" | grep -qF -x 'gate: design'; then _rgt="design"; fi
  if printf '%s\n' "$1" | grep -qF -x 'gate: governance'; then
    if [ -n "$_rgt" ]; then _rgt="design+governance"; else _rgt="governance"; fi
  fi
  [ -n "$_rgt" ] || return 1
  printf '%s\n' "$_rgt"
  return 0
}

# render_records — Δ3, THE SINGLE SOURCE of the D-240805-4 judgment-surface render. Emits the
# matched-record visibility block on STDOUT (the caller appends it to $GITHUB_STEP_SUMMARY); the
# per-run log line goes to stderr so the block stays clean. Reads $_scope_keys and $NOTES_REF.
#
# ⚠️ THIS BEHAVIOUR USED TO EXIST THREE TIMES — here, in .github/workflows/ci.yml, and in
# profiles/adopter-gates.yml (B7 design §1.8, measured). It is single-sourced because Δ1 adds a
# SECOND key: a copy that kept matching on the PR key alone would render NOTHING on exactly the PRs
# the branch key enables, i.e. the gate would pass and the owner would click GO with no record in
# view — a D-240805-4 visibility lie manufactured by the fix. The two workflow legs now INVOKE this,
# and conformance/adopter-gates-parity.sh refuses a leg that drops the invocation or regrows a copy.
#
# Every property the inline copies carried is preserved verbatim and for its original reason:
#   * ALL matches, never the first — the gate passes if ANY match survives adjudication, so showing
#     one record could hide a defective sibling behind the survivor (B7 rider).
#   * VERBATIM bodies inside ONE grown fence, never per-field markdown — a record forged through the
#     front door closed a code span with its own backtick and emitted `<br>`, rendering a SECOND,
#     stronger-looking `approved-by` line (measured, B2 sec H2).
#   * An 8 KB bound that is TOTAL ACROSS RECORDS, with the cut ANNOUNCED — GitHub drops a whole
#     step summary past 1 MiB, and one forged field measured 1,601,670 bytes, so an unbounded render
#     hides the record by VOLUME; a silent truncation hides it just as well (self-review finding 4).
render_records() {
  _rr_nl=$(printf '\nX'); _rr_nl=${_rr_nl%X}   # a literal newline
  _rr_body=''; _rr_matched=0
  if git rev-parse -q --verify "refs/notes/$NOTES_REF" >/dev/null 2>&1; then
    for _rr_obj in $(git notes --ref="$NOTES_REF" list 2>/dev/null | awk '{print $2}'); do
      _rr_b="$(git notes --ref="$NOTES_REF" show "$_rr_obj" 2>/dev/null || true)"
      # BOTH accepted gate values, LABELLED BY TYPE — and the label is derived HERE, inside the single
      # source, never in a workflow (the parity lock refuses a regrown workflow-side matcher, and a
      # copy that learned only `design` would render NOTHING on exactly the PRs the governance arm
      # enables: the gate green, the owner clicking GO with no record in view. That is the
      # D-240805-4 visibility lie the single-sourcing exists to prevent, and it is why the render
      # learns the new value in the SAME change that teaches the gate).
      _rr_type="$(_record_gate_type "$_rr_b")" || _rr_type=""
      [ -n "$_rr_type" ] || continue
      _matches_scope "$_rr_b" || continue
      _rr_matched=$((_rr_matched + 1))
      if [ -z "$_rr_body" ]; then
        _rr_body="--- record $_rr_obj [$_rr_type] ---${_rr_nl}${_rr_b}"
      else
        _rr_body="${_rr_body}${_rr_nl}--- record $_rr_obj [$_rr_type] ---${_rr_nl}${_rr_b}"
      fi
    done
  fi
  if [ -z "$_rr_body" ]; then
    printf '%s\n' 'ceremony-binding: PASS/N-A with no scoped design record (ordinary change-class) — nothing to render.'
    return 0
  fi
  # awk, not `head -c`: `printf | head -c` SIGPIPEs the writer, which under `-o pipefail` aborts the
  # render and drops the record for a THIRD reason. LC_ALL=C so length() counts BYTES (a byte cap).
  _rr_trunc=0
  if [ "$(printf '%s' "$_rr_body" | LC_ALL=C wc -c | tr -d ' ')" -gt 8192 ]; then
    _rr_body=$(printf '%s\n' "$_rr_body" | LC_ALL=C awk -v max=8192 '
      used < max {
        if (used + length($0) + 1 > max) { printf "%s", substr($0, 1, max - used); exit }
        print $0; used += length($0) + 1
      }')
    _rr_trunc=1
  fi
  # FENCE-IN-BODY GUARD, ONE awk pass: the fence must be LONGER than the longest backtick RUN in the
  # body, so no ledger content can close it. The grow-and-rescan loop this replaced forked `grep`
  # once per backtick over author-controlled input (measured 9s on a 2,000-backtick body); a render
  # nobody waits for is not visibility. Fail-safe: an unusable run length yields the LONGEST fence.
  _rr_run=$(printf '%s\n' "$_rr_body" | LC_ALL=C awk '
    { n = 0
      for (i = 1; i <= length($0); i++) {
        if (substr($0, i, 1) == "`") { n++; if (n > m) m = n } else { n = 0 }
      } }
    END { print m + 0 }')
  case "$_rr_run" in ''|*[!0-9]*) _rr_run=8192 ;; esac
  _rr_fence='```'
  while [ "${#_rr_fence}" -le "$_rr_run" ]; do _rr_fence="$_rr_fence"'`'; done
  printf '%s\n' "## ceremony-binding — the design/governance-gate GO record(s) this merge rides on ($_rr_matched matched, rendered up to the 8 KB total bound)" ''
  printf '%s\n' "$_rr_fence" "$_rr_body" "$_rr_fence"
  if [ "$_rr_trunc" = 1 ]; then
    printf '%s\n' '' "**(truncated at 8 KB TOTAL across all $_rr_matched record(s) — read the full ledger: \`git notes --ref=$NOTES_REF show <sha>\`)**"
  fi
  printf '%s\n' '' "_Matched on: $_keys_display (a design or governance GO binds by \`scope: PR-<n>\` OR \`scope: branch/<head-branch>\`; each record above is tagged with the gate value it carries, and a record tagged \`design+governance\` is DEFECTIVE by disqualification, never adjudicated by whichever line was read first). Every record above is reproduced VERBATIM from the ledger, inside one code fence: nothing in it renders as markdown, so a field cannot forge a second one. The gate passes if ANY matching record survives adjudication — a defective sibling is SHOWN here, not hidden behind the survivor, within the 8 KB total bound; past it, the cut is announced and the ledger command shows the rest. Record bodies can contain separator-lookalike text; the header's matched-count is authoritative. A note **binds**, it does not **authenticate** — this render exists so a minted record walks into the owner's field of view before the click (\`D-240805-4\`)._"
  echo "ceremony-binding: $_rr_matched matched record(s) rendered into the step summary." >&2
  return 0
}

run_ceremony_binding() {   # $1 = fixture listing ('' = derive from the ambient tree); rest: --scope ID | none
  # $1 is reachable ONLY as a function parameter: selftest() passes a listing in-process, and the
  # dispatcher at the bottom always passes '' — no command-line flag accepts one. Same shape as
  # loop-state's derive_class fixture parameter, and for the same reason: a gate that never
  # implements the flag cannot accept an author-supplied one.
  # ⚠️ `--changed` WAS that flag and is REMOVED — do not revive it under any spelling or enabling
  # switch. It was argv-borne but enabled by env KIT_CB_TEST=1, and in production it was parsed,
  # validated, and silently DISCARDED while the class derived from the AMBIENT tree (T0-03, measured
  # 2026-08-04: the same command line returned rc 0 or rc 1 flipped solely by the environment).
  # Removal per docs/architecture/2026-08-04-ceremony-binding-fixture-flag-design.md (option ii-b);
  # argv `--changed` now falls to the unknown-arg refusal below, rc 2. The env-borne CLASS lives on
  # in the engine's KIT_OBL_TEST, owned by the boarded OBLIGATION-TESTMODE-ENV-FLAG row.
  # `--base` was removed with the ordering predicate (design §4.4). It existed only to drive the
  # merge-base for the ancestry check; with no ordering there is no base to override.
  _cb_changed="$1"; shift
  _cb_scope=""
  _cb_prepush=0
  _cb_head_branch=""
  _cb_base_ref=""
  _cb_render=0
  # Initialised HERE, not at first use: check_design_record reads both under `set -u`, and a path that
  # reached it with either unset would die with no diagnostic (this file has paid that price twice).
  _mb_base=""; _contain_state="reachable-only (leg 2 not evaluated)"
  # Same reason, C8: the verdict reads it under `set -u`, and an unset value would kill the run with
  # no diagnostic on the one path that is supposed to be a PASS.
  CB_RECORD_TYPE="design"; CB_GOV_SUBSET_JUDGED=0
  while [ $# -gt 0 ]; do
    case "$1" in
      # --pre-push — B2 Δ1′ (docs/architecture/2026-08-07-b2-go-records-prepush-design.md §3a): the
      # git hook's read-only mode. IDENTICAL to the CI predicate in every leg; the ONE difference is
      # WHICH SCOPE KEY binds the record to the change — CI passes `--scope PR-<n>`, this mode
      # DERIVES `branch/<current-branch>` (prepush_scope_key, owner ruling D11). That is what lets a
      # design GO bind BEFORE a PR exists (design S3: prebuild scopes are destroyed at re-record,
      # one sha one note) while still being a predicate that CAN REFUSE.
      # ⚠️ THE SCOPE LEG IS NOT WIDE, AND MUST NOT BE RE-WIDENED. The first build of Δ1 accepted any
      # '^gate: design$' record; on a ledger holding one surviving design record that is PERMANENTLY
      # GREEN (measured: B3's record satisfied a B2 push on the real 107-record ledger) — the same
      # configuration ci.yml describes in the kit's own words, and a leg that cannot refuse fails the
      # 2026-08-02 owner ruling. Withdrawn, with legP1b as its standing regression case.
      # rc contract unchanged: 0 pass/N-A · 1 WAITING (no record for this key) · 2 anomaly.
      # CEILING (bind-not-authenticate, restated where the leg lives): a git note BINDS, it does
      # not AUTHENTICATE (scripts/promotion-verify.sh:38-44) — an agent running under the owner's
      # git identity can mint a front-door record and no local mechanism can distinguish it.
      # PREVENTION IS NOT CLAIMED. The full disposition is: the subagent-brief ledger-write
      # prohibition (process) + the guard's raw-ledger-write deny (the back door) + the record
      # rendered VERBATIM at the CI judgment surface (visibility) — D-240805-3 / D-240805-4.
      --pre-push) _cb_prepush=1; shift ;;
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
        if _scope_charset_bad "$2"; then
          echo "ceremony-binding: --scope must be non-empty and may contain only" >&2
          echo "  [A-Za-z0-9_.:/-] — got a value with a disallowed character (refused)." >&2
          return 2
        fi
        _cb_scope="$2"
        shift 2 ;;
      # `--head-branch` (BRANCH-SCOPE-END-TO-END Δ1) — the SECOND key's raw material, and the ONE
      # argument on this surface whose value is chosen by whoever opens the PR (`github.head_ref`).
      # DELIBERATELY NOT REFUSED AT THE BOUNDARY, unlike --scope: a name outside the record format's
      # charset cannot express a key, so there is nothing to refuse — the key is DROPPED (disclosed)
      # and the run proceeds on the PR key alone. Refusing instead would hand any fork author an rc-2
      # red on our gate by naming a branch `feat/a b`, which is a denial-of-service through an input
      # we already know can carry no record. The charset test itself is the SAME _scope_charset_bad
      # --scope uses, so no new charset hole is opened by the second key.
      --head-branch)
        [ $# -ge 2 ] || { echo "ceremony-binding: --head-branch needs a value" >&2; return 2; }
        _cb_head_branch="$2"
        shift 2 ;;
      # `--base-ref` (BRANCH-SCOPE-END-TO-END Δ2, fix round 1) — the history containment LEG 2 measures
      # "already integrated" against. CI passes `github.base_ref` (the PR's target branch) the same way
      # it passes the head branch: env-bound, argument-borne, never interpolated into a run: line.
      # It selects NO records — it only names a basis — which is why, unlike --head-branch, it is NOT
      # refused alongside --pre-push: the hook simply has a default (the locally-derived branch) and a
      # caller may pin the same thing explicitly. Unusable values are disposed of in containment_base
      # (disclosed skip, rc unchanged), not at this boundary, for --head-branch's reason.
      --base-ref)
        [ $# -ge 2 ] || { echo "ceremony-binding: --base-ref needs a value" >&2; return 2; }
        _cb_base_ref="$2"
        shift 2 ;;
      # `--render` (Δ3) — NOT a gate run: it emits the matched-records visibility block on stdout for
      # $GITHUB_STEP_SUMMARY and makes NO verdict. It exists so the D-240805-4 render has ONE
      # implementation instead of the three copies the B7 design §1.8 measured (this matcher + two
      # inline workflow copies) — teaching the gate a second key without single-sourcing would have
      # made the render silently blind on exactly the PRs the second key enables.
      --render) _cb_render=1; shift ;;
      *) echo "ceremony-binding: unknown arg '$1'" >&2; return 2 ;;
    esac
  done
  # --scope and --pre-push are mutually exclusive, REFUSED rather than reconciled: the pre-push key
  # is DERIVED (D11's single-derivation rule), so honouring a supplied scope would silently run a
  # DIFFERENT predicate than the caller asked --pre-push for, and ignoring it would misrepresent
  # what was checked. rc 2 — an anomaly (a broken wiring), never a wait.
  if [ "$_cb_prepush" -eq 1 ] && [ -n "$_cb_scope" ]; then
    echo "ceremony-binding: --scope cannot be combined with --pre-push — the pre-push scope key is" >&2
    echo "  DERIVED (branch/<current-branch>), never supplied. Run the CI predicate with --scope," >&2
    echo "  or --pre-push alone." >&2
    return 2
  fi
  # SAME RULE, SAME REASON, for the two arguments Δ1/Δ3 add. --pre-push DERIVES its one key from the
  # checked-out branch, so a supplied --head-branch would either be silently ignored (misrepresenting
  # what was checked) or honoured (running a different predicate than --pre-push names). And --render
  # makes no verdict, so pairing it with the hook mode would produce a run that neither renders a
  # CI key nor gates. Both are broken wirings: rc 2, never a wait.
  if [ "$_cb_prepush" -eq 1 ] && [ -n "$_cb_head_branch" ]; then
    echo "ceremony-binding: --head-branch cannot be combined with --pre-push — the pre-push scope key" >&2
    echo "  is DERIVED from the checked-out branch (D11's single-derivation rule), never supplied." >&2
    return 2
  fi
  if [ "$_cb_prepush" -eq 1 ] && [ "$_cb_render" -eq 1 ]; then
    echo "ceremony-binding: --render cannot be combined with --pre-push — the render is the CI" >&2
    echo "  judgment-surface block (D-240805-4) and makes no verdict; --pre-push is a predicate." >&2
    return 2
  fi

  # ---- Δ3 THE RENDER, dispatched BEFORE applicability and deliberately so: it makes no verdict, so
  # it must not inherit the gate's N-A early return (an `ordinary` change would otherwise write
  # "no design artifact required" into $GITHUB_STEP_SUMMARY instead of the render's own honest
  # "nothing to render" line). Its stdout IS the summary block; every diagnostic it emits goes to
  # stderr so the block cannot be polluted by one.
  if [ "$_cb_render" -eq 1 ]; then
    _ask_rc=0; _assemble_scope_keys || _ask_rc=$?
    if [ "$_ask_rc" -ne 0 ]; then
      echo "ceremony-binding --render: no usable scope key (pass --scope and/or an expressible" >&2
      echo "  --head-branch). Refusing to render an unbound set of records." >&2
      return 2
    fi
    render_records
    return 0
  fi

  # ---- Applicability: derive the class via the single hardened authority, fail CLOSED.
  if [ -n "$_cb_changed" ]; then
    _cls="$(derive_class --changed "$_cb_changed")" || _cls=""
  else
    _cls="$(derive_class)" || _cls=""
  fi
  if [ -z "$_cls" ]; then
    echo "FAIL: ceremony-binding — change-class is UNDERIVABLE; refusing to classify (fail closed)." >&2
    # rc 2, not 1 (WAITING-GATES-RENDER-AS-RED, design §8.3/§9.3). The gate evaluated NOTHING here, which
    # is anomalous — rc 1 is reserved for "a human has not recorded the GO yet", the one state that is a
    # normal stage of healthy work. Rendering this as the waiting yellow would tell an operator to go ask
    # for an approval when the real problem is that the classifier could not run.
    return 2
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
  # ancestor of every later commit, so the ordering predicate (WITHDRAWN — see the tombstone below) went
  # vacuously true and ANY future control-plane PR passed with no design and no record of its own. The
  # scope id is what binds record to change; without it this gate stops exactly one merge — its own.
  # Scope is REQUIRED in CI mode only — --pre-push DERIVES its key (D11; prepush_scope_key above).
  # Everything else without a scope stays the rc-2 anomaly it always was.
  if [ "$_cb_prepush" -eq 0 ] && [ -z "$_cb_scope" ] && [ -z "$_cb_head_branch" ]; then
    echo "FAIL: ceremony-binding — no --scope supplied; refusing to match a GO record to this change" >&2
    echo "      by guesswork (fail closed). CI passes the PR number; locally pass --scope <id>." >&2
    # rc 2 (design §9.3, review finding). Left at 1 this renders as normal waiting, which is exactly
    # backwards: with no scope the gate did not evaluate ANYTHING. The live route is a broken CI wiring
    # or an empty PR number yielding the charset-legal scope `PR-`, and that must be investigated, not
    # read as "the owner has not got round to the GO yet".
    return 2
  fi
  # ---- THE SCOPE KEYS (B2 Δ1′, widened by Δ1). ONE assembler, ONE matcher, ONE record search serve
  # BOTH modes AND the render — same loop, same check_design_record, same verdict partition, no fork
  # of the predicate. The mode decides only WHICH KEYS bind record to change.
  _ask_rc=0; _assemble_scope_keys || _ask_rc=$?
  if [ "$_ask_rc" -ne 0 ]; then
    if [ "$_ask_rc" -eq 1 ]; then
      echo "FAIL: ceremony-binding — no --scope supplied, and the --head-branch given cannot express a" >&2
      echo "      scope key, so there is NO key to match a GO record on (fail closed)." >&2
    fi
    return 2
  fi

  # ── B7 RIDER — NO-SHADOWING (the #509 wedge, measured 2026-08-08). The loop below COLLECTS
  # every scope-matching record instead of breaking on the first: the ledger iterates in
  # annotated-SHA order and same-key duplicates exist legitimately (`notes add -f` overwrites only
  # same-SHA re-records; PR-433/PR-439 both carry live same-key pairs), so a first-match break made
  # the verdict a SORT-ORDER LOTTERY — a defective record with a lower annotated sha shadowed a
  # valid same-key record (measured: `00c0…` < `924e…` on #509). Restoring the `break` REDs legR1.
  # NOT FIXED HERE, on purpose: the record→poster race and any new scope key are slice (b)'s job
  # (BRANCH-SCOPE-END-TO-END, owner-ruled split 2026-08-08) — this rider changes ADJUDICATION only.
  _design_note=""; _gate_seen=0; _seen_gov=0; _seen_design=0; _match_count=0; _matches=""
  if git rev-parse -q --verify "refs/notes/$NOTES_REF" >/dev/null 2>&1; then
    for _obj in $(git notes --ref="$NOTES_REF" list 2>/dev/null | awk '{print $2}'); do
      _body="$(git notes --ref="$NOTES_REF" show "$_obj" 2>/dev/null || true)"
      # BOTH conditions on the SAME record, each line-anchored. C8: the gate half now accepts EITHER
      # accepted value through the one classifier — a record carrying both is collected here and
      # DISQUALIFIED downstream, never silently routed to one arm.
      _rec_type="$(_record_gate_type "$_body")" || _rec_type=""
      [ -n "$_rec_type" ] || continue
      _gate_seen=1   # an accepted record exists, but maybe not for THIS scope — report the near-miss
      case "$_rec_type" in
        governance) _seen_gov=1 ;;
        design) _seen_design=1 ;;
        *) _seen_gov=1; _seen_design=1 ;;
      esac
      _matches_scope "$_body" || continue
      _matches="$_matches $_obj"; _match_count=$((_match_count + 1))
    done
  fi
  # THE NEAR-MISS VOCABULARY, derived once for both modes' diagnostics (C8). An operator whose ledger
  # holds only GOVERNANCE records must not be told to record a DESIGN GO — that instruction is how a
  # correct governance-lane change gets "cured" back into the design-basis workaround this arm exists
  # to retire. An error stream is an instruction stream.
  _nm_kind="design"; _nm_gate="design"; _nm_basis="<design-doc-path>"
  if [ "$_seen_gov" -eq 1 ] && [ "$_seen_design" -eq 0 ]; then
    _nm_kind="governance"; _nm_gate="governance"; _nm_basis="<meta-control-artifact-path>"
  fi
  if [ "$_match_count" -eq 0 ] && [ "$_cb_prepush" -eq 1 ]; then
    # The hook mode's WAITING verdict (rc 1): the [S4] family — no design GO recorded for this
    # branch. Same two diagnoses as CI, phrased for the key that actually failed to match.
    if [ "$_gate_seen" -eq 1 ]; then
      echo "FAIL: ceremony-binding --pre-push — a 'gate: $_nm_kind' record exists, but NONE is scoped to this branch" >&2
      echo "      (expected 'scope: $_keys_display'). Another branch's GO does not satisfy this push, and neither" >&2
      echo "      does a 'scope: PR-<n>' record — that is CI's key, not this one. A leg that accepted any design" >&2
      echo "      record went PERMANENTLY GREEN after its own first use (measured); it was withdrawn." >&2
    else
      echo "FAIL: ceremony-binding --pre-push — change-class '$_cls' requires a recorded DESIGN GATE approval," >&2
      echo "      and no '--gate design' record was found in refs/notes/$NOTES_REF." >&2
      echo "      (A PURE governance-record change — a meta-control sitting and its bookkeeping — records" >&2
      echo "      '--gate governance' with a '$CB_GOV_GLOB' basis instead; see docs/enterprise/meta-control.md.)" >&2
    fi
    echo "      Record one: scripts/promotion-verify.sh record --gate $_nm_gate --scope $_record_key \\" >&2
    echo "        --approved-sha <approved-commit> --approved-by <human> --basis $_nm_basis ..." >&2
    echo "      THEN PUBLISH IT: git push origin refs/notes/promotions" >&2
    echo "      THAT ONE RECORD IS ENOUGH: CI matches the SAME branch key (BRANCH-SCOPE-END-TO-END)," >&2
    echo "      so there is NO re-record at PR creation any more — the [S4]#7 interim protocol is" >&2
    echo "      RETIRED (2026-08-11), and with it the record->poster race it caused." >&2
    echo "      STALENESS: this reader never fetches (offline discipline); a stale or partial local" >&2
    echo "      ledger can FALSE-REFUSE — remedy: git fetch origin '+refs/notes/*:refs/notes/*'." >&2
    echo "      It can never weaken CI, which fetches the fresh ledger." >&2
    return 1
  fi
  if [ "$_match_count" -eq 0 ]; then
    # Two distinct causes, reported distinctly. They share a branch but not a diagnosis, and an operator
    # who recorded a GO for the wrong scope needs to be told that rather than "no record found".
    if [ "$_gate_seen" -eq 1 ]; then
      echo "FAIL: ceremony-binding — a 'gate: $_nm_kind' record exists, but NONE is scoped to this change" >&2
      echo "      (expected 'scope: $_keys_display'). A record for another scope does NOT satisfy this gate:" >&2
      echo "      that is what let an unrelated prior design vouch for every later change-set." >&2
    else
      echo "FAIL: ceremony-binding — change-class '$_cls' requires a recorded DESIGN GATE approval," >&2
      echo "      and no '--gate design' record was found in refs/notes/$NOTES_REF." >&2
      echo "      (A PURE governance-record change — a meta-control sitting and its bookkeeping — records" >&2
      echo "      '--gate governance' with a '$CB_GOV_GLOB' basis instead; see docs/enterprise/meta-control.md.)" >&2
    fi
    echo "      Record one: scripts/promotion-verify.sh record --gate $_nm_gate --scope $_record_key \\" >&2
    echo "        --approved-sha <approved-commit> --approved-by <human> --basis $_nm_basis ..." >&2
    echo "      THEN PUBLISH IT: git push origin refs/notes/promotions" >&2
    echo "      Do BOTH BEFORE opening the PR — this gate reads the ledger the moment the PR exists." >&2
    echo "      A BRANCH-scoped record is the one to write: it binds before the PR exists AND is what" >&2
    echo "      CI matches here, so it needs no re-record (the [S4]#7 interim protocol is RETIRED)." >&2
    return 1
  fi

  # The downstream legs are SHARED by both modes (B2 Δ1′: no fork of the predicate), and — B7
  # rider — they now run over EVERY matching record: rc 0 if ANY survives (the survivor is named,
  # with the examined count), rc 2 only when ALL are defective (EACH named with its defect). A
  # defective SCOPED record among only-defective matches is the rc-2 anomaly in BOTH modes —
  # with branch scoping the matched records are bound to THIS change (legP3/leg14/legR3).
  # Pass 1 adjudicates each record in a SUBSHELL (capturing its verdict text without letting a
  # defect print on a passing run); pass 2 re-runs the survivor in THIS shell so
  # CB_DESIGN_DOC/_appr are set for the verdict below — same inputs, same predicate, no fork.
  # ---- Δ2 THE GRADED HEAD, resolved ONCE for the containment leg below. Deliberately AFTER the
  # no-match returns above, so a tree with no record still gets its rc-1 WAITING rather than an
  # rc-2 for a head that could not resolve — the containment leg only ever judges records that exist.
  # CI mode grades the PR head (the deciding job checks it out); --pre-push grades the pushed tip.
  # Both are HEAD in the tree the check runs in, which is why there is one resolution and not two.
  _graded_head="$(git rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)" || _graded_head=""
  if [ -z "$_graded_head" ]; then
    echo "FAIL: ceremony-binding — HEAD does not resolve to a commit, so REACHABILITY CONTAINMENT" >&2
    echo "      cannot be evaluated against the graded head. The gate evaluated NOTHING (fail closed)." >&2
    return 2
  fi
  # ---- Δ2 LEG 2's BASIS, resolved ONCE for every record, with a DISCLOSED disposition ladder.
  # Three outcomes, and none of them is silent:
  #   base resolves and does NOT already contain the head -> leg 2 RUNS (full containment);
  #   base already CONTAINS the graded head -> it cannot discriminate historic work from new (every
  #     commit reachable from the head is in it by definition), so leg 2 would refuse EVERY record on
  #     a healthy shape — a repo with no remote whose default branch IS the checked-out branch, which
  #     is the shape of this file's own fixtures and of a fresh local repo. SKIPPED, disclosed. It is
  #     not a bypass: making it true requires a head the base already contains, i.e. a change-set that
  #     adds nothing to the base;
  #   nothing resolves (shallow clone, no default-branch ref, no --base-ref) -> SKIPPED, disclosed.
  # rc is UNCHANGED in the skip arms and the verdict carries the degraded state, so a green is never
  # read as more containment than was measured (never a red on a healthy clone shape, never a silent
  # skip — the B2-Δ2 clone-shape class and loop-state's scope-basis ladder, same disposition).
  if _mb_try="$(containment_base "$_graded_head")" && [ -n "$_mb_try" ]; then
    if [ "$_mb_try" = "$_graded_head" ]; then
      _contain_state="reachable-only (leg 2 SKIPPED: the resolved base already contains this head)"
      echo "ceremony-binding: CONTAINMENT leg 2 (not-already-integrated) SKIPPED — the resolved base already contains the graded head, so it cannot tell historic work from new; containment is REACHABLE-ONLY for this run, rc unchanged." >&2
    else
      _mb_base="$_mb_try"
      _contain_state="reachable AND not already integrated (base merge-base $_mb_base)"
    fi
  else
    _contain_state="reachable-only (leg 2 SKIPPED: no base history resolved)"
    echo "ceremony-binding: CONTAINMENT leg 2 (not-already-integrated) SKIPPED — no base history resolved (no usable --base-ref, and no local default-branch ref: shallow clone or absent ref); containment is REACHABLE-ONLY for this run, rc unchanged." >&2
  fi
  _survivor=""; _defects=""; _examined=0; _defect_n=0
  for _obj in $_matches; do
    _examined=$((_examined + 1))
    _body="$(git notes --ref="$NOTES_REF" show "$_obj" 2>/dev/null || true)"
    _design_note="$_obj"
    _cdr_rc=0
    _cdr_out="$( check_design_record 2>&1 )" || _cdr_rc=$?
    if [ "$_cdr_rc" -eq 0 ]; then
      [ -n "$_survivor" ] || _survivor="$_obj"
    else
      _defect_n=$((_defect_n + 1))
      # The gate value is APPENDED, never inserted: `record <sha> is DEFECTIVE` stays an intact
      # substring (legR3 and any adopter log-scraper match on it), while a governance defect is no
      # longer indistinguishable from a design one in a mixed-record verdict.
      _dfl="$(_record_gate_type "$_body")" || _dfl="unknown"
      _defects="$_defects
record $_obj is DEFECTIVE (gate: $_dfl):
$_cdr_out"
    fi
  done
  if [ -z "$_survivor" ]; then
    printf '%s\n' "$_defects" >&2
    echo "FAIL: ceremony-binding — ALL $_examined matching record(s) for 'scope: $_keys_display' are DEFECTIVE" >&2
    echo "      (each named above); no surviving GO record. A defect in EVERY record bound to this" >&2
    echo "      change is broken, not patient (WAITING-GATES-RENDER-AS-RED)." >&2
    return 2
  fi
  _body="$(git notes --ref="$NOTES_REF" show "$_survivor" 2>/dev/null || true)"
  _design_note="$_survivor"
  if ! check_design_record >/dev/null 2>&1; then
    echo "FAIL: ceremony-binding — the surviving record's re-adjudication DIVERGED from its first pass" >&2
    echo "      (record $_survivor). Fail closed: a non-deterministic verdict is an anomaly." >&2
    return 2
  fi

  _survivor_key="$(_matched_key "$_body")" || _survivor_key="$_keys_display"
  # C8 — the verdict NAMES THE ARM. "It passed" and "it passed as a governance-record change, judged
  # by the diff-shape guard" are different facts, and the second is the one an owner reading a green
  # on a panel PR needs (the same rule that makes the verdict name the matched KEY and the containment
  # STATE rather than just saying PASS).
  _gate_word="DESIGN GATE"
  if [ "$CB_RECORD_TYPE" = "governance" ]; then _gate_word="GOVERNANCE GATE"; fi
  if [ "$_cb_prepush" -eq 1 ]; then
    echo "OK: ceremony-binding --pre-push — change-class '$_cls'; $_gate_word recorded (scope $_keys_display)."
    echo "    Survivor: record $_survivor — examined $_examined matching record(s), $_defect_n defective"
    echo "    (a defective sibling cannot shadow a valid record — the #509 wedge; defects render at CI)."
    echo "    Matched on key: $_survivor_key."
    echo "    Artifact: $CB_DESIGN_DOC — tracked, not a symlink, above the substance floor."
    echo "    Approved by: $_appr, in a GO scoped to this branch, whose commit touches that artifact"
    echo "    and is CONTAINED in this head's history — containment: $_contain_state."
    echo "    CI matches this SAME branch key — no re-record at PR creation ([S4]#7 retired 2026-08-11)."
    if [ "$CB_RECORD_TYPE" = "governance" ]; then
      echo "    GOVERNANCE ARM: the change-set is a SUBSET of the governance set (derived by"
      echo "    promotion-readiness.sh --changed-files, the same authority the class comes from)."
    fi
    echo "    NO ORDERING CLAIM: this gate does not check whether the design preceded the work."
    return 0
  fi
  echo "OK: ceremony-binding — change-class '$_cls'; $_gate_word recorded (scope $_keys_display)."
  echo "    Survivor: record $_survivor — examined $_examined matching record(s), $_defect_n defective"
  echo "    (a defective sibling cannot shadow a valid record — the #509 wedge; ALL matches render at CI)."
  echo "    Matched on key: $_survivor_key."
  echo "    Artifact: $CB_DESIGN_DOC — tracked, not a symlink, above the substance floor."
  echo "    Approved by: $_appr, in a GO scoped to this change, whose commit touches that artifact"
  echo "    and is CONTAINED in this head's history — containment: $_contain_state."
  if [ "$CB_RECORD_TYPE" = "governance" ] && [ "$CB_GOV_SUBSET_JUDGED" = 1 ]; then
    echo "    GOVERNANCE ARM: the change-set is a SUBSET of the governance set (derived by"
    echo "    promotion-readiness.sh --changed-files, the same authority the class comes from)."
    echo "    NOT CLAIMED: that the panel artifact's CONTENT is about this change — only that the"
    echo "    record is scope-bound and the artifact is touched by the commit it approves (D-240805-4:"
    echo "    the owner's read of the artifact at the sitting is the content control)."
  fi
  echo "    NO ORDERING CLAIM: this gate does not check whether the design preceded the work."
  return 0
}

# check_design_record — the DOWNSTREAM legs, shared VERBATIM by both modes (B2: refactor-in-place,
# no fork of the predicate — CI and --pre-push run these exact lines). Reads $_body, $_design_note
# $_cls and $_graded_head (set by the caller's record search) plus NOTES_REF / CB_DESIGN_GLOB /
# CB_GOV_GLOB; on success sets CB_DESIGN_DOC, CB_RECORD_TYPE and $_appr for the caller's verdict text. Returns 0 = the record survives every
# leg; 2 = the record is DEFECTIVE, reason on stderr. The rc-2-everywhere rule is inherited
# (WAITING-GATES-RENDER-AS-RED): every refusal below is an anomaly, never a wait.
check_design_record() {
  # ---- C8: WHICH ARM IS JUDGING THIS RECORD. Derived from the record itself through the ONE
  # classifier, before any leg runs, because two legs below differ by arm (the basis GLOB, and the
  # governance-only diff-shape guard) and everything else is shared VERBATIM — the same
  # refactor-in-place discipline B2 applied to --pre-push, and for the same reason: a forked
  # predicate is two predicates that drift.
  # Reset per record: pass 2 re-adjudicates the survivor in THIS shell, so a flag left set by an
  # earlier record would let one record's judgment vouch for another's verdict line.
  CB_GOV_SUBSET_JUDGED=0
  _rt="$(_record_gate_type "$_body")" || _rt=""
  if [ "$_rt" = "design+governance" ]; then
    echo "FAIL: ceremony-binding — the GO record carries BOTH 'gate: design' and 'gate: governance'." >&2
    echo "      A record matching more than one accepted gate value is DEFECTIVE BY DISQUALIFICATION." >&2
    echo "      The two arms judge DIFFERENT things — a design basis, versus a governance basis plus" >&2
    echo "      the diff-shape guard — so dispatching on whichever line a matcher saw first would make" >&2
    echo "      the verdict a lottery on a hand-minted note (the #509 sort-order class, new door)." >&2
    echo "      Record ONE gate per GO: split it into two records, or drop the value that does not" >&2
    echo "      describe this change." >&2
    return 2
  fi
  if [ -z "$_rt" ]; then
    # Unreachable from the collect loop (which skips a record carrying neither value) — asserted here
    # anyway because check_design_record is called through TWO paths (pass 1 and the survivor's
    # re-adjudication) and an arm that silently defaulted would be the fail-open direction.
    echo "FAIL: ceremony-binding — the GO record carries no accepted gate value ('gate: design' or" >&2
    echo "      'gate: governance'); it cannot be adjudicated by either arm (fail closed)." >&2
    return 2
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
       # ── rc 2 FROM HERE DOWN (WAITING-GATES-RENDER-AS-RED, design §8.3/§9.3). ──────────────────────
       # A scoped GO record EXISTS; it is DEFECTIVE. That is an anomaly, and anomalies are RED.
       # rc 1 is reserved, above, for the single state that is a normal stage of healthy work: no scoped
       # GO recorded yet. Everything past that point — a malformed approver line, a basis that is
       # missing, untracked, symlinked, traversing, or not a design artifact, a bad approved-sha — is a
       # defect a human must fix, and rendering it as the waiting yellow is how a broken record comes to
       # look like patience. If you add a new refusal below, it is rc 2 unless it is a genuine wait.
       return 2 ;;
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
      return 2 ;;
  esac
  if [ "$_appr" != "$_id [$_label]" ]; then
    echo "FAIL: ceremony-binding — 'approved-by:' must be exactly '<id> [<label>]'; a trailing decoy" >&2
    echo "      label would otherwise override a weaker one. Got: $_appr" >&2
    return 2
  fi
  case "$_label" in
    # `authenticated:` is NOT a wildcard — promotion-verify.sh only ever derives `authenticated:
    # <forge>-review`, so `[authenticated: nonsense]` must not pass. Found by self-attack.
    "signed: gpg"|committer|"authenticated: "*-review) : ;;
    "self-asserted")
      # Solo-compatible by design: for a design commit ON THIS BRANCH the owner IS its committer, so
      # [committer] is reached at no cost. `approver != author` is deliberately NOT imposed — unusable
      # solo, theatre here.
      # ⚠️ NOT TRUE OF AN ALREADY-MERGED DESIGN. Squash-merge replaces the committer with the forge —
      # measured 2026-07-29: 140 of 140 commits on `main` touching docs/architecture/*-design.md have
      # committer `GitHub <noreply@github.com>`, ZERO have the owner. So for an inherited design
      # [committer] is unreachable BY A HUMAN APPROVER — and this refusal is the one an inheriting
      # successor actually hits (it returns before the basis/touch checks below).
      # ⚠️⚠️ IT IS NOT UNREACHABLE, IT IS FORGEABLE. derive_assurance compares the caller-supplied
      # --approved-by string against %cn/%ce, so `--approved-by GitHub` on a squash-merged design
      # commit DERIVES [committer] and clears this bar. Measured end-to-end 2026-07-29 (security
      # re-review, then reproduced on this repo's own d347fd4). That makes the derivation an OPEN
      # HOLE, not a usability gap: the fix is to make the forge identity an UNACCEPTABLE APPROVER.
      # Boarded as ASSURANCE-FORGE-IDENTITY-ACCEPTED-AS-APPROVER. Do NOT read the message below as
      # "the weak path is impossible" — it is illegitimate, which prose cannot enforce.
      if [ "$_cls" = "control-plane" ]; then
        echo "FAIL: ceremony-binding — a control-plane DESIGN GATE needs an assurance stronger than" >&2
        echo "      [self-asserted]. Record with --approved-by matching the design commit's committer" >&2
        echo "      identity (yields [committer]) or sign the commit (yields [signed: gpg])." >&2
        echo "      ⚠️ INHERITING an already-merged design? The committer of a squash-merged commit is" >&2
        echo "      the FORGE, not a human. A GO naming the forge as approver is NOT a human approval" >&2
        echo "      and must not be recorded. Write THIS slice's own design artifact instead, which" >&2
        echo "      may CONFIRM the design you inherit rather than originate one. It records what" >&2
        echo "      it confirms, scope coverage, whether the inherited sizing still holds, deltas," >&2
        echo "      and inherited obligations. See skills/design ('Design provenance')." >&2
        echo "      THEN RE-RECORD the GO with --basis <the new artifact> and --approved-sha <the" >&2
        echo "      commit that touches it>. The label derives from approved-sha, so a new artifact" >&2
        echo "      with the old record still fails here." >&2
        return 2
      fi ;;
    *) echo "FAIL: ceremony-binding — unrecognised assurance label '[$_label]' on the GO record." >&2
       return 2 ;;
  esac

  # ---- Identification: the GO record NAMES the artifact, in its `basis:` field.
  # The pointer originally stopped the WITHDRAWN ordering predicate accepting ANY design doc in history
  # (every one is an ancestor of everything, so it would have gone VACUOUSLY GREEN). Ordering is gone —
  # see the tombstone below — so the pointer now does one job: bind the GO to the artifact. NO ordering claim.
  _basis="$(git notes --ref="$NOTES_REF" show "$_design_note" 2>/dev/null \
            | sed -n 's/^basis: //p' | head -1)"
  if [ -z "$_basis" ] || [ "$_basis" = "(none recorded)" ]; then
    echo "FAIL: ceremony-binding — the '--gate design' record on $_design_note names no artifact." >&2
    echo "      Re-record it with --basis <path-to-the-design-doc>." >&2
    return 2
  fi

  # PATH SAFETY. `basis:` is free text written by a human at GO time, so it is untrusted input to this
  # check. Reject an absolute path or any `..` segment BEFORE touching the filesystem, then require the
  # path to be a TRACKED file — `git ls-files --error-unmatch` also confines it to the repository, so a
  # symlink pointing outside the tree cannot satisfy the gate.
  case "$_basis" in
    /*|*..*)
      echo "FAIL: ceremony-binding — refusing a basis path that is absolute or contains '..'." >&2
      return 2 ;;
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
  # C8 — DELTA (i) OF TWO: the GLOB is the arm's, and ONLY the glob. The governance arm asks the same
  # question ("is the basis the kind of artifact this gate names?") against the kind of artifact a
  # governance GO actually rides on — the meta-control panel record. The design arm is BYTE-UNCHANGED,
  # which is why the live defective record `1d9f0afa` (gate: design + a meta-control basis) STAYS
  # defective: the ledger's honesty about the gap is not retro-cured by closing the gap.
  if [ "$_rt" = "governance" ]; then
    # shellcheck disable=SC2254 # UNQUOTED ON PURPOSE: CB_GOV_GLOB is a glob pattern — see below.
    case "$_basis" in
      $CB_GOV_GLOB) : ;;
      *)
        echo "FAIL: ceremony-binding — basis '$_basis' is not a governance artifact." >&2
        echo "      Expected $CB_GOV_GLOB (the kit convention, e.g." >&2
        echo "      docs/architecture/2026-08-11-meta-control-39.md)." >&2
        echo "      A 'gate: governance' GO names the meta-control artifact of the sitting it records." >&2
        echo "      A design document is the DESIGN arm's basis, not this one — pointing a governance" >&2
        echo "      GO at one is the very workaround this arm exists to retire." >&2
        return 2 ;;
    esac
  else
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
      return 2 ;;
  esac
  fi
  if ! git ls-files --error-unmatch -- "$_basis" >/dev/null 2>&1; then
    echo "FAIL: ceremony-binding — the design artifact named by the GO record is not a tracked file:" >&2
    echo "      $_basis" >&2
    return 2
  fi
  # REFUSE A SYMLINK (git mode 120000). `ls-files --error-unmatch` proves the LINK is tracked; it does
  # NOT confine the target — obl_is_placeholder's `[ -r ]` and greps then FOLLOW it to content outside
  # the repository that appears in no diff. Reproduced by security review (MED-5) with a tracked
  # `docs/architecture/x-design.md -> ../../../outside/notes.md`. The header previously CLAIMED this was
  # closed by ls-files, which was false; now it is closed here and the claim is true.
  if [ "$(git ls-files -s -- "$_basis" 2>/dev/null | awk '{print $1}')" = "120000" ]; then
    echo "FAIL: ceremony-binding — the design artifact is a SYMLINK; its content is not in this tree:" >&2
    echo "      $_basis" >&2
    return 2
  fi

  # ---- Is the artifact REAL, or a stub? Reuse the engine's placeholder detector rather than
  # re-implementing stub vocabulary: it already defeats "eight lines of prose under a heading", already
  # fails closed on an unreadable record, and already refuses a malformed pattern.
  if obl_is_placeholder "$_basis"; then
    echo "FAIL: ceremony-binding — the design artifact is a PLACEHOLDER (${OBL_PLACEHOLDER_REASON:-template}):" >&2
    echo "      $_basis" >&2
    return 2
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
      return 2 ;;
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
      return 2 ;;
  esac
  if [ "${#_asha}" -lt 7 ] || [ "${#_asha}" -gt 40 ]; then
    echo "FAIL: ceremony-binding — approved-sha must be 7-40 hex characters. Got: $_asha_raw" >&2
    return 2
  fi
  _asha="$(git rev-parse -q --verify "${_asha}^{commit}" 2>/dev/null)" || _asha=""
  if [ -z "$_asha" ]; then
    echo "FAIL: ceremony-binding — approved-sha '$_asha_raw' does not resolve to a commit in this repo." >&2
    return 2
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
    # SIGNPOST THE ESCAPE, DO NOT RELAX THE CHECK. This refusal is correct — it is the DESIGN STAGE
    # being enforced against a change-set with no design artifact of its own. Restating the rule was
    # not enough: a whole session was spent rediscovering the compliant path and then proposing to
    # delete this predicate twice. The ONE compliant satisfier is named here, and the artifact-to-scope
    # hole is warned against — an earlier draft offered it as "option 2" and security review measured
    # that as an endorsed bypass on a bound required context. So the next reader does
    # not repeat that. See docs/architecture/2026-07-29-ceremony-binding-inherits-d12-design.md.
    echo "      The compliant way to satisfy this:" >&2
    echo "        Write THIS slice's own design artifact and approve a commit that touches it." >&2
    echo "        It may ORIGINATE a design, or CONFIRM one you inherit (from the owner, a" >&2
    echo "        previous slice, or a backlog story's design link). A confirming design is a" >&2
    echo "        full design artifact: it records what it confirms, scope coverage, whether the" >&2
    echo "        inherited sizing still holds, deltas, and inherited obligations. See" >&2
    echo "        skills/design ('Design provenance')." >&2
    echo "      Do NOT instead point approved-sha at some older design's own commit to make this" >&2
    echo "      pass: NOTHING here binds the artifact's CONTENT to this change (only the RECORD is" >&2
    echo "      scope-bound), so that satisfies the gate with no design for the work at hand." >&2
    return 2
  fi

  # ---- Δ2 REACHABILITY CONTAINMENT (BRANCH-SCOPE-END-TO-END, 2026-08-11) — the approved commit must
  # be an ANCESTOR of the graded head. THIS IS NOT AN ORDERING CLAIM AND MUST NEVER BE READ AS ONE
  # (see the withdrawal tombstone below): it says the approved commit is IN THIS HISTORY, not that it
  # came first — `git commit --amend` defeats ordering and this check is indifferent to that.
  #
  # WHY IT EXISTS. Retiring the re-record makes branch-scoped records PERMANENT, and branch NAMES are
  # author-REUSABLE: without this, a record left behind by a historic `feat/x` would be inherited by
  # any future branch named `feat/x`. Containment cures the CLASS — a historic record's approved-sha
  # is not in the new branch's history, so the record is inert. Applied to the PR key too, for
  # symmetry: a record's own approved commit not being in the graded head is anomalous on any key.
  # The existing commit-touches-basis leg above is unchanged; this ADDS containment, it replaces
  # nothing. Fail-shape is DEFECTIVE-with-a-named-reason, so the adjudicate-all rider renders it and
  # a valid sibling still carries the gate (B7 rider semantics preserved exactly).
  #
  # `set -eu` DISCIPLINE: `--is-ancestor` reports its VERDICT in the exit status (1 = not an
  # ancestor), so the rc is captured with `|| _mb_rc=$?` — a bare call would abort the whole run
  # under `set -e` and turn a legitimate refusal into a silent death mid-adjudication.
  _mb_rc=0
  git merge-base --is-ancestor "$_asha" "$_graded_head" >/dev/null 2>&1 || _mb_rc=$?
  if [ "$_mb_rc" -ne 0 ]; then
    if [ "$_mb_rc" -eq 1 ]; then
      echo "FAIL: ceremony-binding — CONTAINMENT: the approved commit is NOT an ancestor of the graded head," >&2
      echo "      so this GO approves a commit that is not in the history being judged." >&2
      echo "      approved-sha: $_asha" >&2
      echo "      graded head:  $_graded_head" >&2
      echo "      A branch name can be REUSED, so a record from a historic branch of the same name must" >&2
      echo "      not vouch for this one. Record a GO for THIS change (the branch key needs no" >&2
      echo "      re-record), or rebase so the approved commit is genuinely contained." >&2
    else
      echo "FAIL: ceremony-binding — CONTAINMENT could not be evaluated (git merge-base --is-ancestor" >&2
      echo "      exited $_mb_rc for approved-sha $_asha against graded head $_graded_head). Fail closed:" >&2
      echo "      an unevaluable containment check is an anomaly, not a pass." >&2
    fi
    return 2
  fi

  # ---- Δ2 CONTAINMENT, LEG 2: NOT ALREADY INTEGRATED (fix round 1, security F1).
  # Leg 1 above proves the approved commit is IN this history. It does NOT prove the record is about
  # THIS work, and the difference is the whole reused-name class: once a historic same-named branch is
  # MERGED OR REBASED into the base, its approved-sha lives on the MAINLINE — so every later branch
  # inherits it reachably and its record satisfies unrelated work. MEASURED as rc 0 on exactly that
  # shape, which is the class `D-240811-3` was ratified believing closed. Leg 2 closes it: the approved
  # commit must NOT be an ancestor of merge-base(graded head, base) — i.e. it must be NEW relative to
  # the base, not already integrated into it.
  # $_mb_base is EMPTY when no base could be resolved (or the resolved base already contains the head);
  # the caller has already DISCLOSED that degradation and $_contain_state carries it into the verdict.
  # Skipping here is deliberate and fail-safe: a red for a clone SHAPE would break every shallow
  # checkout and every fresh local repo, which is the green-on-clone failure class in reverse.
  if [ -n "$_mb_base" ]; then
    _mb2_rc=0
    git merge-base --is-ancestor "$_asha" "$_mb_base" >/dev/null 2>&1 || _mb2_rc=$?
    if [ "$_mb2_rc" -eq 0 ]; then
      echo "FAIL: ceremony-binding — CONTAINMENT: ALREADY-INTEGRATED: the approved commit is in the base" >&2
      echo "      history — a historic record cannot approve new work; record a fresh GO." >&2
      echo "      This also catches a GO recorded at the FORK POINT (approved-sha == the merge-base):" >&2
      echo "      that record approves a commit the base already has, so it says nothing about this" >&2
      echo "      branch's work — the remedy is the same, a fresh GO on a commit of this change." >&2
      echo "      approved-sha:     $_asha" >&2
      echo "      base merge-base:  $_mb_base" >&2
      echo "      graded head:      $_graded_head" >&2
      return 2
    fi
    if [ "$_mb2_rc" -ne 1 ]; then
      echo "FAIL: ceremony-binding — CONTAINMENT leg 2 could not be evaluated (git merge-base" >&2
      echo "      --is-ancestor exited $_mb2_rc for approved-sha $_asha against base merge-base" >&2
      echo "      $_mb_base). Fail closed: an unevaluable containment check is an anomaly, not a pass." >&2
      return 2
    fi
  fi

  # ---- C8 — DELTA (ii) OF TWO, and the arm's THESIS: the GOVERNANCE DIFF-SHAPE GUARD. Deliberately
  # LAST, after every shared hygiene leg: a governance record that is malformed in a way BOTH arms
  # care about should be told THAT, not handed a diff-shape lecture. Runs for the governance arm
  # ONLY — the design arm imposes no diff constraint and gains none here (byte-unchanged behaviour).
  if [ "$_rt" = "governance" ]; then
    _gov_diff_shape_guard || return 2
  fi

  CB_DESIGN_DOC="$_basis"
  # The arm that judged this record, for the caller's verdict line. Set only on SUCCESS, next to
  # CB_DESIGN_DOC and for its reason: a verdict must never name an arm for a record that did not pass.
  CB_RECORD_TYPE="$_rt"

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
  return 0
}

# ---- selftest() marker: the non-vacuity sweep mutates ONLY lines ABOVE here ----
selftest() {
  _tmp="$(mktemp -d "${TMPDIR:-/tmp}/ceremony-st.XXXXXX")"
  trap 'rm -rf "$_tmp"' EXIT INT TERM
  # (The `export KIT_CB_TEST=1` that lived here died with the `--changed` flag it enabled — fixtures
  # now arrive as run_ceremony_binding's first function parameter, which has no external surface.)
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
  # PIN THE GOVERNANCE GLOB TOO (C8), for the identical reason: every governance fixture files its
  # panel artifact at docs/architecture/<date>-meta-control-<n>.md, so an adopter who legitimately
  # narrows CB_GOV_GLOB to their own convention would get a RED selftest — and this selftest is
  # registered in conformance/verify.sh, so that is a red PRIMARY AGGREGATE for doing exactly what
  # the check invites. Note the glob is ALSO a member of the governance set, so an unpinned value
  # would move the diff-shape guard's set underneath the fixtures as well.
  CB_GOV_GLOB='docs/architecture/*-meta-control-*.md'
  _fails=0; _legs=0

  # LEG 1 (liveness) — an ORDINARY change-set requires nothing: N-A, rc 0.
  _legs=$((_legs+1))   # leg1
  printf 'docs/x.md\n' > "$_tmp/changed-ordinary"
  if run_ceremony_binding "$_tmp/changed-ordinary" --scope PR-1 >/dev/null 2>&1; then
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
  # rc 1 EXPLICITLY. There is ONE waiting STATE (no scoped GO recorded yet), reported with TWO
  # diagnoses (no record at all / a record scoped elsewhere) from ONE code path, and covered by THREE
  # legs. The header says "exactly one state" and means the state; this means the legs.
  # which is a normal stage of healthy work, not a broken build.
  _expect_fail leg2 "$_tmp/f2" "no '--gate design' record was found" "control-plane with no GO record" 1

  # LEG 2b (A4 LOAD-BEARING NEGATIVE #1, T0-03) — the PRODUCTION surface must REFUSE `--changed`.
  # The flag used to be parsed, validated, and silently DISCARDED unless env KIT_CB_TEST=1: an
  # identical command line derived its class from the AMBIENT tree and waved a disagreeing listing
  # through green (measured 2026-08-04). Now no code path reads the flag — argv `--changed` falls to
  # the unknown-arg refusal, rc 2. Asserts rc AND the named refusal AND that the message advertises
  # no bypass and no test switch: an error stream is an instruction stream.
  _legs=$((_legs+1))   # leg2b
  _out2b="$( sh "$0" --changed "$_tmp/changed-cp" --scope PR-1 2>&1 )" && _rc2b=0 || _rc2b=$?
  case "$_rc2b:$_out2b" in
    2:*"unknown arg '--changed'"*)
      case "$_out2b" in
        *KIT_CB_TEST*|*selftest*)
          echo "FAIL leg2b: the refusal must advertise no bypass or test switch, got: $_out2b"
          _fails=$((_fails+1)) ;;
        *) echo "PASS leg2b: production --changed -> rc 2 named refusal, advertising nothing" ;;
      esac ;;
    *) echo "FAIL leg2b: production --changed must be REFUSED rc 2 naming the arg, got rc=$_rc2b: $_out2b"
       _fails=$((_fails+1)) ;;
  esac

  # LEG 2c (A4 LOAD-BEARING NEGATIVE #2) — KIT_CB_TEST in the environment is DEAD, not dormant: the
  # SAME command line must produce the IDENTICAL verdict (rc and text) with and without it. Under
  # the removed machinery the env var alone flipped the verdict — fixture honored versus silently
  # discarded — which is the env-borne shape the kit has banked as the weaker one
  # (OBLIGATION-TESTMODE-ENV-FLAG). That row still owns the engine's KIT_OBL_TEST; this leg pins
  # ceremony-binding's own instance shut.
  _legs=$((_legs+1))   # leg2c
  _out2c_off="$( KIT_CB_TEST='' sh "$0" --changed "$_tmp/changed-cp" --scope PR-1 2>&1 )" \
    && _rc2c_off=0 || _rc2c_off=$?
  _out2c_on="$( KIT_CB_TEST=1 sh "$0" --changed "$_tmp/changed-cp" --scope PR-1 2>&1 )" \
    && _rc2c_on=0 || _rc2c_on=$?
  if [ "$_rc2c_off" = "$_rc2c_on" ] && [ "$_out2c_off" = "$_out2c_on" ]; then
    echo "PASS leg2c: KIT_CB_TEST=1 changes no verdict (env var dead: rc $_rc2c_on both ways)"
  else
    echo "FAIL leg2c: KIT_CB_TEST=1 CHANGED the verdict (rc $_rc2c_off -> $_rc2c_on) — the env var is alive"
    _fails=$((_fails+1))
  fi

  # LEG 3 (fail-closed) — an UNDERIVABLE change-class must FAIL, never fall through to `ordinary`.
  #
  # ⚠️ THIS LEG WAS MIS-SPECIFIED ON FIRST WRITE AND THE CORRECTION IS THE POINT. The obvious fixture —
  # a listing path that does not exist — does NOT produce an underivable class: promotion-readiness.sh
  # fail-safes an unreadable change-set to `control-plane` (measured: rc 0, output `control-plane`).
  # So that fixture would have FAILed for LEG 2's reason (no GO record) while claiming to prove
  # fail-closed derivation — a TAUTOLOGICAL DUPLICATE of leg 2 that leaves derive_class's `return 1`
  # branch dead and unproven. The real branch is only reachable when the AUTHORITY ITSELF is
  # unavailable, so that is what this leg builds, and it asserts the SPECIFIC verdict text rather than
  # a bare non-zero rc — going through the exit code alone is exactly what made it confusable.
  _legs=$((_legs+1))   # leg3
  _nodir="$_tmp/no-authority"
  mkdir -p "$_nodir/conformance"
  _leg3_out="$( DIR="$_nodir" run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 2>&1 || true )"
  # ★ rc ASSERTED TOO (WAITING-GATES-RENDER-AS-RED). This is the ONE negative leg that does not route
  # through _expect_fail, so it was the ONE defect path the partition's rc default did not cover —
  # review mutated this branch 2 -> 1 and the whole suite stayed GREEN, which would have rendered an
  # UNDERIVABLE change-class (a gate that evaluated NOTHING) as the friendly waiting yellow. §8.1's
  # table rules that state RED. Text alone could not see it; text AND rc can.
  ( DIR="$_nodir" run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 ) >/dev/null 2>&1 \
    && _rc3=0 || _rc3=$?
  case "$_rc3:$_leg3_out" in
    2:*UNDERIVABLE*) echo "PASS leg3: authority unavailable -> rc 2 (anomaly), verdict names UNDERIVABLE" ;;
    1:*) echo "FAIL leg3: UNDERIVABLE returned rc 1 — a gate that evaluated NOTHING would render as the normal waiting yellow"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL leg3: expected rc 2 with an UNDERIVABLE verdict, got rc=$_rc3: $_leg3_out"; _fails=$((_fails+1)) ;;
  esac

  # LEG 3d (GUARD-PATH-ENUMERATION-INCOMPLETE S2) — THE ADAPTER-UNION INHERITANCE.
  # This gate derives its change-class through promotion-readiness.sh, and that classifier used to
  # see only the GUARD-CORE half of the merge-time control-plane set. So a change-set touching only
  # an adapter-declared path (`GEMINI.md`, `.gemini/*`, `.cursor/rules/*`) derived `ordinary`, this
  # gate's ordinary-class short-circuit let it through, and the required ratification gate — which
  # unions the SAME manifests — then blocked the merge. S2 made the classifier union-aware, so this
  # gate inherits the cure with no edit of its own.
  # ⚠️ ASSERTED, NOT INHERITED. "It flips by construction once the classifier does" is a derivation,
  # not a measurement, and the sibling row exists precisely because a pair that was supposed to agree
  # by construction diverged for ten days. Driven through derive_class — this file's own authority
  # seam — so a future re-fork of that function reds here.
  _legs=$((_legs+1))   # leg3d
  printf 'GEMINI.md\n' > "$_tmp/changed-union"
  _l3d="$( derive_class --changed "$_tmp/changed-union" )" || _l3d="<derive failure>"
  if [ "$_l3d" = control-plane ]; then
    echo "PASS leg3d: an adapter-declared-only change-set derives control-plane (adapter union inherited)"
  else
    echo "FAIL leg3d: an adapter-declared-only change-set derived '$_l3d', want control-plane — this gate and the required ratification gate classify the same diff differently again"
    _fails=$((_fails+1))
  fi

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
  _expect_fail leg7 "$_tmp/f7" "no '--gate design' record was found" "wrong-gate record" 1

  # LEG 13 (HIGH-1, THE LOAD-BEARING NEGATIVE FOR RECORD BINDING) — a perfectly valid design record
  # scoped to a DIFFERENT change must NOT satisfy this one. Before the scope binding, the first
  # `gate: design` note in the ledger satisfied every future control-plane PR, so the gate went
  # permanently green after its own first use.
  _scope=PR-999 _mkfix "$_tmp/f13" design "docs/architecture/d-design.md" real
  _expect_fail leg13 "$_tmp/f13" "NONE is scoped to this change" "GO record scoped to a different change" 1

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
  _out13b="$( run_ceremony_binding "$_tmp/changed-cp" \
                --scope "$(printf 'PR-9\ngate: design')" 2>&1 || true )"
  case "$_out13b" in
    *"may contain only"*) echo "PASS leg13b: multi-line --scope -> refused at the boundary" ;;
    *) echo "FAIL leg13b: expected a boundary refusal naming the charset, got: $_out13b"
       _fails=$((_fails+1)) ;;
  esac

  # LEG 13c (WAITING-GATES-RENDER-AS-RED) — NO --scope at all must be rc 2, the ANOMALY code, never rc 1.
  # This path had ZERO legs before this slice: every other invocation in this selftest supplies --scope,
  # so the partition's "no other path returns 1" claim was unprovable exactly here. It matters because
  # the live route is not a hand-typed command — it is a broken CI wiring, or an empty PR number
  # yielding the charset-LEGAL scope `PR-`. Left at rc 1 that renders as the normal yellow "the owner
  # has not recorded the GO yet", so an operator waits patiently for a gate that evaluated nothing.
  # Asserts rc AND verdict text together: rc alone cannot tell this refusal from any other.
  _legs=$((_legs+1))   # leg13c
  _out13c="$( cd "$_tmp/f2" && run_ceremony_binding "$_tmp/changed-cp" 2>&1 || true )"
  ( cd "$_tmp/f2" && run_ceremony_binding "$_tmp/changed-cp" ) >/dev/null 2>&1 \
    && _rc13c=0 || _rc13c=$?
  case "$_rc13c:$_out13c" in
    2:*"no --scope supplied"*) echo "PASS leg13c: absent --scope -> rc 2 (anomaly), naming the refusal" ;;
    1:*) echo "FAIL leg13c: absent --scope returned rc 1 — a gate that evaluated NOTHING would render as the normal waiting yellow"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL leg13c: expected rc 2 naming 'no --scope supplied', got rc=$_rc13c: $_out13c"
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
  if ( cd "$_tmp/f19b" && run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 ) >/dev/null 2>&1; then
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
  if run_ceremony_binding "$_tmp/changed-ceremony" --scope PR-1 >/dev/null 2>&1; then
    echo "PASS leg12: ceremony + version-finishing only -> N-A (no deadlock, no exemption needed)"
  else
    echo "FAIL leg12: a ceremony-only change-set should be N-A"; _fails=$((_fails+1))
  fi

  # ---- B2 legs: the --pre-push mode (Δ1′ — owner ruling D11, 2026-07-28). SAME script, SAME record
  # search, SAME downstream legs. The ONE difference is WHICH SCOPE KEY binds the record to the
  # change: CI passes `--scope PR-<n>`; the hook mode derives `branch/<current-branch>` from
  # prepush_scope_key(). That makes it a predicate that CAN REFUSE (the 2026-08-02 owner ruling),
  # with no PR number and no heuristic.
  # ⚠️ TOMBSTONE — the WITHDRAWN wide leg. Δ1 as first built accepted ANY '^gate: design$' record.
  # On any ledger holding one surviving design record that leg is PERMANENTLY GREEN (measured on
  # this repo's real 107-record ledger: B3's record satisfied a B2 push). legP1b is that defect's
  # standing regression case; do not re-widen the scope leg under any spelling.

  # LEG P1 (liveness) — a GO scoped to THIS branch PASSES, and the verdict names the key it matched.
  _legs=$((_legs+1))   # legP1
  _scope=branch/b2-pp _mkfix "$_tmp/fpp1" design "docs/architecture/d-design.md" real
  ( cd "$_tmp/fpp1" && git checkout -q -b b2-pp )
  _outP1="$( cd "$_tmp/fpp1" && run_ceremony_binding "$_tmp/changed-cp" --pre-push 2>&1 )" \
    && _rcP1=0 || _rcP1=$?
  case "$_rcP1:$_outP1" in
    0:*"scope branch/b2-pp"*)
      echo "PASS legP1: --pre-push passes on a GO scoped to THIS branch, naming the key" ;;
    *) echo "FAIL legP1: expected rc 0 naming 'scope branch/b2-pp', got rc=$_rcP1: $_outP1"
       _fails=$((_fails+1)) ;;
  esac

  # LEG P1b (THE REGRESSION CASE for the withdrawn wide leg) — a FULLY VALID design GO scoped to
  # ANOTHER BRANCH must NOT satisfy this push. This exact fixture PASSED under Δ1 as first built.
  # rc 1 (a wait: the operator must record their own GO), and the near-miss is DIAGNOSED rather
  # than reported as "no record" — an operator who recorded a GO on the wrong branch needs to be
  # told that. Mirrors leg13, which pins the same property on the CI key.
  _legs=$((_legs+1))   # legP1b
  _scope=branch/some-other-branch _mkfix "$_tmp/fpp1b" design "docs/architecture/d-design.md" real
  ( cd "$_tmp/fpp1b" && git checkout -q -b b2-pp )
  _outP1b="$( cd "$_tmp/fpp1b" && run_ceremony_binding "$_tmp/changed-cp" --pre-push 2>&1 )" \
    && _rcP1b=0 || _rcP1b=$?
  case "$_rcP1b:$_outP1b" in
    1:*"NONE is scoped to this branch"*)
      echo "PASS legP1b: --pre-push REFUSES a GO scoped to another branch (the wide-leg defect dies)" ;;
    0:*) echo "FAIL legP1b: another branch's GO SATISFIED this push — the withdrawn wide leg is back"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legP1b: expected rc 1 naming the branch near-miss, got rc=$_rcP1b: $_outP1b"
       _fails=$((_fails+1)) ;;
  esac

  # LEG P1c — a PR-SCOPED record alone does not satisfy pre-push. `scope: PR-<n>` is CI's key, not
  # this one; a record back-filled at PR creation cannot retroactively vouch for a local push.
  _legs=$((_legs+1))   # legP1c
  _scope=PR-777 _mkfix "$_tmp/fpp1c" design "docs/architecture/d-design.md" real
  ( cd "$_tmp/fpp1c" && git checkout -q -b b2-pp )
  _outP1c="$( cd "$_tmp/fpp1c" && run_ceremony_binding "$_tmp/changed-cp" --pre-push 2>&1 )" \
    && _rcP1c=0 || _rcP1c=$?
  case "$_rcP1c:$_outP1c" in
    1:*"NONE is scoped to this branch"*)
      echo "PASS legP1c: --pre-push is not satisfied by a PR-scoped record (CI's key, not ours)" ;;
    *) echo "FAIL legP1c: expected rc 1 naming the branch near-miss, got rc=$_rcP1c: $_outP1c"
       _fails=$((_fails+1)) ;;
  esac

  # LEG P2 (LOAD-BEARING NEGATIVE) — NO design record at all: the WAITING verdict, rc 1, naming the
  # record command WITH the branch scope the operator must use. This is the [S4]-family failure
  # class the pre-push leg exists to catch.
  _legs=$((_legs+1))   # legP2
  _mkbare "$_tmp/fpp2"
  ( cd "$_tmp/fpp2" && git checkout -q -b b2-pp )
  _outP2="$( cd "$_tmp/fpp2" && run_ceremony_binding "$_tmp/changed-cp" --pre-push 2>&1 )" \
    && _rcP2=0 || _rcP2=$?
  case "$_rcP2:$_outP2" in
    1:*"--scope branch/b2-pp"*)
      echo "PASS legP2: --pre-push with no design record -> rc 1 WAITING, naming the branch-scoped record command" ;;
    *) echo "FAIL legP2: expected rc 1 naming '--scope branch/b2-pp', got rc=$_rcP2: $_outP2"
       _fails=$((_fails+1)) ;;
  esac

  # LEG P3 (the downstream legs still bite, and the verdict PARTITION holds) — a record scoped to
  # THIS branch that is DEFECTIVE (no approver line) is the rc-2 ANOMALY, exactly as in CI mode
  # (leg14 pins the CI half of the same property).
  # ⚠️ THIS LEG CHANGED WITH Δ1′, deliberately. Under the withdrawn wide leg it was rc 1, on the
  # reasoning that "an old defective record elsewhere in the ledger is not an anomaly OF THIS PUSH".
  # With branch scoping the matched record IS bound to this change, so that reasoning is gone: a
  # defective record for THIS branch is broken, and broken renders red (WAITING-GATES-RENDER-AS-RED).
  _legs=$((_legs+1))   # legP3
  _label=NONE _scope=branch/b2-pp _mkfix "$_tmp/fpp3" design "docs/architecture/d-design.md" real
  ( cd "$_tmp/fpp3" && git checkout -q -b b2-pp )
  _outP3="$( cd "$_tmp/fpp3" && run_ceremony_binding "$_tmp/changed-cp" --pre-push 2>&1 )" \
    && _rcP3=0 || _rcP3=$?
  case "$_rcP3:$_outP3" in
    2:*"no valid 'approved-by:"*)
      echo "PASS legP3: --pre-push with a DEFECTIVE branch-scoped record -> rc 2 anomaly, named" ;;
    1:*) echo "FAIL legP3: a defective record bound to THIS branch must be the anomaly (rc 2), got rc 1: $_outP3"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legP3: expected rc 2 naming the approver defect, got rc=$_rcP3: $_outP3"
       _fails=$((_fails+1)) ;;
  esac

  # LEG P4 — an ORDINARY change-set is N-A rc 0 in --pre-push mode too (applicability unchanged).
  _legs=$((_legs+1))   # legP4
  if run_ceremony_binding "$_tmp/changed-ordinary" --pre-push >/dev/null 2>&1; then
    echo "PASS legP4: --pre-push + ordinary change-set -> N-A rc 0"
  else
    echo "FAIL legP4: --pre-push + ordinary change-set should be N-A rc 0"; _fails=$((_fails+1))
  fi

  # LEG P5 — --pre-push and --scope together are REFUSED (rc 2, anomaly): the pre-push key is
  # DERIVED (D11's single-derivation rule), so honouring a supplied scope would run a different
  # predicate than the caller asked for, and ignoring it would misrepresent what was checked.
  _legs=$((_legs+1))   # legP5
  _outP5="$( cd "$_tmp/fpp1" && run_ceremony_binding "$_tmp/changed-cp" --pre-push --scope PR-1 2>&1 )" \
    && _rcP5=0 || _rcP5=$?
  case "$_rcP5:$_outP5" in
    2:*"--scope"*) echo "PASS legP5: --pre-push with --scope -> rc 2 refusal naming the conflict" ;;
    *) echo "FAIL legP5: expected rc 2 naming --scope, got rc=$_rcP5: $_outP5"
       _fails=$((_fails+1)) ;;
  esac

  # LEG P5b / P5c — THE OTHER TWO MODE CONFLICTS, pinned by legP5's shape (reviewer LOW-2: both
  # refusals shipped with NO leg, so deleting either left the whole suite green while the run either
  # misrepresented what it checked or made no verdict at all).
  #   --head-branch: the pre-push key is DERIVED (D11's single-derivation rule), so honouring a
  #     supplied one runs a DIFFERENT predicate than --pre-push names, and ignoring it misrepresents
  #     what was checked. Deleting the refusal REDs this leg at rc 0/1, not rc 2 (demonstrated).
  #   --render: the render makes NO verdict, so pairing it with the hook mode yields a run that
  #     neither renders a CI key nor gates. Deleting the refusal REDs this leg at rc 0.
  # (--base-ref is deliberately NOT in this family — it selects no records, only the containment
  # basis, and --pre-push has a derived default for it. See its arg-parse comment.)
  _legs=$((_legs+1))   # legP5b
  _outP5b="$( cd "$_tmp/fpp1" && run_ceremony_binding "$_tmp/changed-cp" --pre-push --head-branch b2-pp 2>&1 )" \
    && _rcP5b=0 || _rcP5b=$?
  case "$_rcP5b:$_outP5b" in
    2:*"--head-branch cannot be combined with --pre-push"*)
      echo "PASS legP5b: --pre-push with --head-branch -> rc 2 refusal naming the conflict" ;;
    *) echo "FAIL legP5b: expected rc 2 naming the --head-branch conflict, got rc=$_rcP5b: $_outP5b"
       _fails=$((_fails+1)) ;;
  esac

  _legs=$((_legs+1))   # legP5c
  _outP5c="$( cd "$_tmp/fpp1" && run_ceremony_binding "$_tmp/changed-cp" --pre-push --render 2>&1 )" \
    && _rcP5c=0 || _rcP5c=$?
  case "$_rcP5c:$_outP5c" in
    2:*"--render cannot be combined with --pre-push"*)
      echo "PASS legP5c: --pre-push with --render -> rc 2 refusal naming the conflict" ;;
    *) echo "FAIL legP5c: expected rc 2 naming the --render conflict, got rc=$_rcP5c: $_outP5c"
       _fails=$((_fails+1)) ;;
  esac

  # LEG P6 — a DETACHED HEAD has no branch key to derive. FAIL CLOSED, rc 2 (the gate evaluated
  # nothing — that is an anomaly, never the waiting yellow), naming the state.
  _legs=$((_legs+1))   # legP6
  ( cd "$_tmp/fpp1" && git checkout -q --detach HEAD )
  _outP6="$( cd "$_tmp/fpp1" && run_ceremony_binding "$_tmp/changed-cp" --pre-push 2>&1 )" \
    && _rcP6=0 || _rcP6=$?
  case "$_rcP6:$_outP6" in
    2:*"detached HEAD"*) echo "PASS legP6: --pre-push on a detached HEAD -> rc 2, naming the state" ;;
    *) echo "FAIL legP6: expected rc 2 naming 'detached HEAD', got rc=$_rcP6: $_outP6"
       _fails=$((_fails+1)) ;;
  esac
  ( cd "$_tmp/fpp1" && git checkout -q b2-pp )

  # LEG P7 — a branch name the RECORD FORMAT CANNOT EXPRESS is rc 2, not a silent non-match. The
  # scope charset is promotion-verify.sh's (and CI's) — reused here rather than widened, so no new
  # charset hole is opened by the derived key. A '+' is legal in a git refname and illegal in a
  # scope; without this the key would simply never match and the operator would be told to record
  # a GO they cannot record.
  _legs=$((_legs+1))   # legP7
  ( cd "$_tmp/fpp1" && git checkout -q -b 'feat+plus' )
  _outP7="$( cd "$_tmp/fpp1" && run_ceremony_binding "$_tmp/changed-cp" --pre-push 2>&1 )" \
    && _rcP7=0 || _rcP7=$?
  case "$_rcP7:$_outP7" in
    2:*"may contain only"*) echo "PASS legP7: an unrepresentable branch name -> rc 2 naming the charset" ;;
    *) echo "FAIL legP7: expected rc 2 naming the charset, got rc=$_rcP7: $_outP7"
       _fails=$((_fails+1)) ;;
  esac
  ( cd "$_tmp/fpp1" && git checkout -q b2-pp )

  # ── LEGS P8a-d: `--print-scope-key`, the ONE sanctioned exit of prepush_scope_key to another
  # process (PRE-PUSH-RUNS-BACKLOG-PRESENCE design §3.1). hooks/pre-push's presence leg needs the
  # branch key and D11 forbids it deriving one, so this mode relays THIS function's answer and
  # nothing else. The rc partition is the contract the hook reads, and it must be UNAMBIGUOUS:
  # rc 0 + `branch/<name>` on stdout · rc 1 detached (the hook's ONLY N/A) · rc 2 charset · rc 3
  # BAD USAGE. Sharing rc 2 between "evaluated: unrepresentable" and "could not evaluate: bad
  # usage" is the A1-1 HIGH — the hook would N/A a broken invocation and the leg would silently
  # stop grading. Each leg re-invokes the script as a CHILD PROCESS (not the in-process function),
  # because the process boundary IS the thing under test.
  case "$0" in /*) _psk_self="$0" ;; *) _psk_self="$PWD/$0" ;; esac
  _legs=$((_legs+1))   # legP8a
  _outP8a="$( cd "$_tmp/fpp1" && sh "$_psk_self" --print-scope-key 2>/dev/null )" \
    && _rcP8a=0 || _rcP8a=$?
  if [ "$_rcP8a" = 0 ] && [ "$_outP8a" = "branch/b2-pp" ]; then
    echo "PASS legP8a: --print-scope-key prints 'branch/b2-pp' rc 0"
  else
    echo "FAIL legP8a: expected rc 0 + 'branch/b2-pp', got rc=$_rcP8a: '$_outP8a'"; _fails=$((_fails+1))
  fi

  # legP8b — detached HEAD: rc 1 with NOTHING on EITHER stream. The empty STDERR is as load-bearing
  # as the rc (security S1): hooks/pre-push treats "rc 1 and silent" as its only N/A, because this
  # file is `set -eu` and a preamble or source failure ALSO exits non-zero — with a reason. If this
  # path ever gained a diagnostic, the hook would start refusing legitimate detached pushes; if the
  # hook keyed on the rc alone, a broken predicate would be waved through as "detached". One of the
  # two must pin the stderr, and this is the cheaper side.
  _legs=$((_legs+1))   # legP8b
  ( cd "$_tmp/fpp1" && git checkout -q --detach HEAD )
  _errP8b="$_tmp/p8b.err"
  _outP8b="$( cd "$_tmp/fpp1" && sh "$_psk_self" --print-scope-key 2>"$_errP8b" )" \
    && _rcP8b=0 || _rcP8b=$?
  if [ "$_rcP8b" = 1 ] && [ -z "$_outP8b" ] && [ ! -s "$_errP8b" ]; then
    echo "PASS legP8b: --print-scope-key on a detached HEAD -> rc 1, silent on BOTH streams"
  else
    echo "FAIL legP8b: expected rc 1 + empty stdout + EMPTY stderr, got rc=$_rcP8b: '$_outP8b' err='$(cat "$_errP8b" 2>/dev/null)'"
    _fails=$((_fails+1))
  fi
  ( cd "$_tmp/fpp1" && git checkout -q b2-pp )

  _legs=$((_legs+1))   # legP8c
  # -B, not -b: legP7 above already created this branch in the same fixture, and under `set -e` a
  # second `-b` would abort the whole selftest rather than fail a leg (measured on first write).
  ( cd "$_tmp/fpp1" && git checkout -q -B 'feat+plus' )
  _errP8c="$_tmp/p8c.err"
  _outP8c="$( cd "$_tmp/fpp1" && sh "$_psk_self" --print-scope-key 2>"$_errP8c" )" \
    && _rcP8c=0 || _rcP8c=$?
  if [ "$_rcP8c" = 2 ] && [ -z "$_outP8c" ] && [ -s "$_errP8c" ]; then
    echo "PASS legP8c: a charset-out branch -> rc 2, empty stdout, one stderr reason"
  else
    echo "FAIL legP8c: expected rc 2 + empty stdout + a stderr reason, got rc=$_rcP8c: '$_outP8c' err='$(cat "$_errP8c" 2>/dev/null)'"
    _fails=$((_fails+1))
  fi
  ( cd "$_tmp/fpp1" && git checkout -q b2-pp )

  # legP8d — BAD USAGE IS ITS OWN RC (A1-1). Folding it into rc 2 would make the hook read a
  # broken invocation as an evaluated charset answer; folding it into rc 1 would make the hook
  # N/A the leg entirely. Deleting the `[ $# -ne 1 ]` refusal reds this leg at rc 0.
  _legs=$((_legs+1))   # legP8d
  _errP8d="$_tmp/p8d.err"
  _outP8d="$( cd "$_tmp/fpp1" && sh "$_psk_self" --print-scope-key --scope PR-1 2>"$_errP8d" )" \
    && _rcP8d=0 || _rcP8d=$?
  if [ "$_rcP8d" = 3 ] && [ -z "$_outP8d" ] && grep -q 'usage' "$_errP8d" 2>/dev/null; then
    echo "PASS legP8d: --print-scope-key with an extra argument -> rc 3 + usage on stderr"
  else
    echo "FAIL legP8d: expected rc 3 + usage on stderr, got rc=$_rcP8d: '$_outP8d' err='$(cat "$_errP8d" 2>/dev/null)'"
    _fails=$((_fails+1))
  fi

  # ── B7 RIDER legs: NO-SHADOWING (the #509 wedge, measured). The ledger iterates in
  # annotated-SHA order and the old match loop broke on FIRST scope-match, so a DEFECTIVE record
  # shadowed a VALID same-key record by sort-order lottery. The rider collects and adjudicates
  # ALL matching records: rc 0 if ANY survives, rc 2 only when EVERY one is defective.
  # BOTH sort orders are built (defective-on-lower = the measured #509 shape, iterated FIRST; and
  # the reverse), so a re-introduced `break` cannot hide behind a lucky ordering.

  # LEG R1 — defective on the LOWER sha + valid on the higher, same scope key: rc 0, the verdict
  # names the SURVIVOR's sha and the examined count. Under first-match-break this exact fixture
  # was the rc-2 wedge.
  _legs=$((_legs+1))   # legR1
  _mkfix2 "$_tmp/fR1" lower
  _outR1="$( cd "$_tmp/fR1" && run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 2>&1 )" \
    && _rcR1=0 || _rcR1=$?
  _valR1=$(cat "$_tmp/fR1/.valid-sha" 2>/dev/null || echo MISSING)
  case "$_rcR1:$_outR1" in
    0:*"Survivor: record $_valR1"*)
      case "$_outR1" in
        (*"examined 2"*) echo "PASS legR1: defective(lower)+valid same key -> rc 0 naming survivor + examined count" ;;
        (*) echo "FAIL legR1: survivor named but the examined count is missing: $_outR1"; _fails=$((_fails+1)) ;;
      esac ;;
    *) echo "FAIL legR1: expected rc 0 naming 'Survivor: record $_valR1', got rc=$_rcR1: $_outR1"
       _fails=$((_fails+1)) ;;
  esac

  # LEG R2 — the REVERSE sort order (defective on the HIGHER sha): same verdict. A fix that only
  # works when the valid record happens to iterate first is the same lottery with a new winner.
  _legs=$((_legs+1))   # legR2
  _mkfix2 "$_tmp/fR2" higher
  _outR2="$( cd "$_tmp/fR2" && run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 2>&1 )" \
    && _rcR2=0 || _rcR2=$?
  _valR2=$(cat "$_tmp/fR2/.valid-sha" 2>/dev/null || echo MISSING)
  case "$_rcR2:$_outR2" in
    0:*"Survivor: record $_valR2"*)
      echo "PASS legR2: defective(higher)+valid same key -> rc 0 naming the survivor (reverse order)" ;;
    *) echo "FAIL legR2: expected rc 0 naming 'Survivor: record $_valR2', got rc=$_rcR2: $_outR2"
       _fails=$((_fails+1)) ;;
  esac

  # LEG R3 — ALL matching records defective -> rc 2, EACH named with its defect (a single
  # anonymous FAIL would hide how many broken records carry this key).
  _legs=$((_legs+1))   # legR3
  _mkfix2 "$_tmp/fR3" both
  _outR3="$( cd "$_tmp/fR3" && run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 2>&1 || true )"
  ( cd "$_tmp/fR3" && run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 ) >/dev/null 2>&1 \
    && _rcR3=0 || _rcR3=$?
  _d3a=$(sed -n 1p "$_tmp/fR3/.defective-shas" 2>/dev/null || echo MISSING)
  _d3b=$(sed -n 2p "$_tmp/fR3/.defective-shas" 2>/dev/null || echo MISSING)
  if [ "$_rcR3" = 2 ] && printf '%s' "$_outR3" | grep -qF "record $_d3a is DEFECTIVE" \
     && printf '%s' "$_outR3" | grep -qF "record $_d3b is DEFECTIVE" \
     && printf '%s' "$_outR3" | grep -qF "ALL 2 matching"; then
    echo "PASS legR3: two defective same-key records -> rc 2 naming EACH"
  else
    echo "FAIL legR3: expected rc 2 naming both defective records + 'ALL 2 matching', got rc=$_rcR3: $_outR3"
    _fails=$((_fails+1))
  fi

  # ── BRANCH-SCOPE-END-TO-END legs (Δ1 two-key match · Δ2 containment · Δ3 the render single-source).
  # The design's §7 list, in order. Every negative below was demonstrated RED FIRST against a
  # hand-built mutant of the production code (the standing discipline), never written green-first.

  # LEG B1 (Δ1 LIVENESS, and the whole point of the slice) — a record carrying ONLY the branch key
  # PASSES its PR. Before Δ1 this exact fixture was the rc-1 WAITING that forced the [S4]#7
  # re-record; the verdict must NAME the key it matched, or "it passed" and "it passed for the
  # reason we think" are indistinguishable.
  _legs=$((_legs+1))   # legB1
  _scope=branch/b2-pp _mkfix "$_tmp/fB1" design "docs/architecture/d-design.md" real
  _outB1="$( cd "$_tmp/fB1" && run_ceremony_binding "$_tmp/changed-cp" \
               --scope PR-1 --head-branch b2-pp 2>&1 )" && _rcB1=0 || _rcB1=$?
  case "$_rcB1:$_outB1" in
    0:*"Matched on key: branch/b2-pp"*)
      echo "PASS legB1: a branch-key-only record PASSES its PR, and the verdict names the key" ;;
    1:*) echo "FAIL legB1: a branch-key-only record still WAITS — the two-key match is not live: $_outB1"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legB1: expected rc 0 naming 'Matched on key: branch/b2-pp', got rc=$_rcB1: $_outB1"
       _fails=$((_fails+1)) ;;
  esac

  # LEG B2 (THE LOAD-BEARING NEGATIVE for Δ1) — the SAME record must REFUSE a DIFFERENT branch's PR.
  # A second key that matched any branch would be the withdrawn wide leg with a new spelling: on a
  # ledger holding one surviving design record it goes permanently green (measured, legP1b's
  # tombstone). rc 1 (a genuine wait — the operator has not recorded a GO for THIS change).
  _legs=$((_legs+1))   # legB2
  _outB2="$( cd "$_tmp/fB1" && run_ceremony_binding "$_tmp/changed-cp" \
               --scope PR-1 --head-branch some-other-branch 2>&1 )" && _rcB2=0 || _rcB2=$?
  case "$_rcB2:$_outB2" in
    1:*"NONE is scoped to this change"*)
      echo "PASS legB2: the same record REFUSES a different branch's PR (the second key is not wide)" ;;
    0:*) echo "FAIL legB2: another branch's GO SATISFIED this PR — the branch key matches anything"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legB2: expected rc 1 naming the scope near-miss, got rc=$_rcB2: $_outB2"
       _fails=$((_fails+1)) ;;
  esac

  # LEG B3 (THE LOAD-BEARING NEGATIVE for Δ2, the ratified ceiling's narrowing) — a record whose
  # NAME key matches but whose approved-sha is NOT an ancestor of the graded head is DEFECTIVE with
  # a NAMED containment reason. This is the permanence hazard made inert: branch names are
  # author-reusable and branch records no longer get reaped, so without this leg a historic
  # `feat/x` record would vouch for every future `feat/x`. rc 2 (a defect, not a wait).
  _legs=$((_legs+1))   # legB3
  _mkcontain "$_tmp/fB3" branch/b2-pp
  _outB3="$( cd "$_tmp/fB3" && run_ceremony_binding "$_tmp/changed-cp" \
               --scope PR-1 --head-branch b2-pp 2>&1 || true )"
  ( cd "$_tmp/fB3" && run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 --head-branch b2-pp ) \
    >/dev/null 2>&1 && _rcB3=0 || _rcB3=$?
  case "$_rcB3:$_outB3" in
    2:*CONTAINMENT*"NOT an ancestor"*)
      echo "PASS legB3: a name-matching record outside the graded head's history -> rc 2, CONTAINMENT named" ;;
    0:*) echo "FAIL legB3: a record whose approved commit is NOT in this history SATISFIED the gate — a reused branch name inherits its predecessor's GO"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legB3: expected rc 2 naming CONTAINMENT, got rc=$_rcB3: $_outB3"
       _fails=$((_fails+1)) ;;
  esac

  # LEG B4 (Δ1 REGRESSION) — an existing PR-scoped record still passes, WITH a head branch supplied
  # that no record carries. Nothing is migrated and no adopter's ledger is invalidated: the PR key
  # is not deprecated, it is joined. Without this leg the second key could have REPLACED the first.
  _legs=$((_legs+1))   # legB4
  _scope=PR-1 _mkfix "$_tmp/fB4" design "docs/architecture/d-design.md" real
  _outB4="$( cd "$_tmp/fB4" && run_ceremony_binding "$_tmp/changed-cp" \
               --scope PR-1 --head-branch a-branch-with-no-record 2>&1 )" && _rcB4=0 || _rcB4=$?
  case "$_rcB4:$_outB4" in
    0:*"Matched on key: PR-1"*)
      echo "PASS legB4: a PR-scoped record still passes when a second key is in play (no migration)" ;;
    *) echo "FAIL legB4: expected rc 0 naming 'Matched on key: PR-1', got rc=$_rcB4: $_outB4"
       _fails=$((_fails+1)) ;;
  esac

  # LEG B5 (THE HOSTILE-INPUT DISPOSAL) — `github.head_ref` is chosen by whoever opens the PR, so a
  # name outside the record format's charset must DROP the branch key, DISCLOSE that it did, and
  # leave the rc alone. Two failure modes this leg pins shut, in both directions: refusing (rc 2)
  # would hand any fork author a red on this gate for free, and dropping SILENTLY would make the
  # verdict "PASS on the PR key" indistinguishable from "PASS on a branch key we never used".
  # The PR-scoped record of fB4 still carries the run, so the rc is UNCHANGED at 0.
  _legs=$((_legs+1))   # legB5
  _outB5="$( cd "$_tmp/fB4" && run_ceremony_binding "$_tmp/changed-cp" \
               --scope PR-1 --head-branch 'feat/a b;rm -rf' 2>&1 )" && _rcB5=0 || _rcB5=$?
  case "$_rcB5:$_outB5" in
    0:*"outside the record format's charset"*"DROPPING the"*)
      case "$_outB5" in
        *"Matched on key: PR-1"*)
          echo "PASS legB5: a hostile head-branch name -> PR-key-only, disclosed, rc UNCHANGED (0)" ;;
        *) echo "FAIL legB5: the run passed but not on the PR key — the dropped key leaked into the match: $_outB5"
           _fails=$((_fails+1)) ;;
      esac ;;
    2:*) echo "FAIL legB5: a charset-out head branch REFUSED (rc 2) — an author-chosen name must not red this gate: $_outB5"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legB5: expected rc 0 with a disclosed key drop, got rc=$_rcB5: $_outB5"
       _fails=$((_fails+1)) ;;
  esac

  # LEG B6 (Δ3 — THE RENDER IS THIS SCRIPT'S, and it follows the same two keys). The D-240805-4
  # block used to be inlined in ci.yml AND profiles/adopter-gates.yml; a copy left matching the PR
  # key alone would render NOTHING on exactly the PRs Δ1 enables — the gate green, the owner
  # clicking GO with no record in view. Here: the render finds a BRANCH-keyed record verbatim,
  # inside a fence, and honestly renders nothing when no key matches. (The other half of the
  # single-source claim — that BOTH workflow legs INVOKE this rather than carrying a copy — is
  # conformance/adopter-gates-parity.sh's assert_render_single_sourced + cases 2h/2i/9.)
  _legs=$((_legs+1))   # legB6
  _outB6="$( cd "$_tmp/fB1" && run_ceremony_binding '' --render --scope PR-1 --head-branch b2-pp 2>/dev/null )" \
    && _rcB6=0 || _rcB6=$?
  _outB6b="$( cd "$_tmp/fB1" && run_ceremony_binding '' --render --scope PR-1 --head-branch nope 2>/dev/null )" \
    && _rcB6b=0 || _rcB6b=$?
  if [ "$_rcB6" = 0 ] && printf '%s\n' "$_outB6" | grep -qF 'scope: branch/b2-pp' \
     && printf '%s\n' "$_outB6" | grep -qF '(1 matched' \
     && printf '%s\n' "$_outB6" | grep -q '^```' \
     && [ "$_rcB6b" = 0 ] && printf '%s\n' "$_outB6b" | grep -qF 'nothing to render'; then
    echo "PASS legB6: --render is the single-sourced block — branch-keyed record verbatim in a fence, honest empty otherwise"
  else
    echo "FAIL legB6: --render did not emit the matched record block (rc=$_rcB6/$_rcB6b): $_outB6"
    _fails=$((_fails+1))
  fi

  # LEG B7 (Δ3 BOUND) — the render's 8 KB TOTAL bound and its ANNOUNCED cut move with the code, or
  # single-sourcing would have quietly dropped B2's measured volume defence (one forged field
  # emitted 1,601,670 bytes; GitHub DROPS a step summary past 1 MiB, so an unbounded render hides
  # the record by volume just as effectively as omitting it).
  _legs=$((_legs+1))   # legB7
  _mkbigrec "$_tmp/fB7" branch/b2-pp
  _outB7="$( cd "$_tmp/fB7" && run_ceremony_binding '' --render --scope PR-1 --head-branch b2-pp 2>/dev/null )" \
    && _rcB7=0 || _rcB7=$?
  _bytesB7=$(printf '%s' "$_outB7" | LC_ALL=C wc -c | tr -d ' ')
  if [ "$_rcB7" = 0 ] && [ "$_bytesB7" -le 65536 ] \
     && printf '%s\n' "$_outB7" | grep -qF 'truncated at 8 KB TOTAL' \
     && printf '%s\n' "$_outB7" | grep -qF 'gate: design'; then
    echo "PASS legB7: --render bounds an oversized record at 8 KB TOTAL ($_bytesB7 bytes) and ANNOUNCES the cut"
  else
    echo "FAIL legB7: expected a bounded, announced render (rc=$_rcB7, $_bytesB7 bytes)"
    _fails=$((_fails+1))
  fi

  # ── Δ2 CONTAINMENT LEG 2 — "not already integrated" (fix round 1, security F1). legB3 above pins
  # leg 1; these four pin the leg that actually closes the reused-name CLASS, plus its disclosed
  # degradation. Every negative was demonstrated RED FIRST against a hand-built mutant with leg 2
  # removed (the standing discipline), and under that mutant legB8/legB11 return rc 0 — which IS the
  # measured defect: a historic record satisfying unrelated work.

  # LEG B8 (THE CLASS KILLER) — the shape leg 1 CANNOT see: the historic branch's approved commit was
  # MERGED/REBASED into the base, so it sits on the MAINLINE; a NEW branch reusing the name inherits
  # it reachably and carries NO fresh record. Under leg 1 alone this is rc 0 (measured) — the record
  # from an unrelated, already-integrated slice vouches for this change. rc 2, ALREADY-INTEGRATED.
  # Exercises the EXPLICIT CI route (--base-ref, the way the workflows pass $GITHUB_BASE_REF).
  _legs=$((_legs+1))   # legB8
  _mkbase "$_tmp/fB8" integrated branch/feat/reused
  _outB8="$( cd "$_tmp/fB8" && run_ceremony_binding "$_tmp/changed-cp" \
               --scope PR-1 --head-branch feat/reused --base-ref main 2>&1 || true )"
  ( cd "$_tmp/fB8" && run_ceremony_binding "$_tmp/changed-cp" \
      --scope PR-1 --head-branch feat/reused --base-ref main ) >/dev/null 2>&1 && _rcB8=0 || _rcB8=$?
  case "$_rcB8:$_outB8" in
    2:*ALREADY-INTEGRATED*)
      echo "PASS legB8: an already-integrated record on a REUSED branch name -> rc 2, ALREADY-INTEGRATED named" ;;
    0:*) echo "FAIL legB8: a record whose approved commit is ALREADY IN THE BASE satisfied a new branch of the same name — the reused-name class D-240811-3 claims closed is OPEN: $_outB8"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legB8: expected rc 2 naming ALREADY-INTEGRATED, got rc=$_rcB8: $_outB8"
       _fails=$((_fails+1)) ;;
  esac

  # LEG B9 (THE LIVENESS HALF, and the false-red guard) — OUR OWN FLOW: the design commit lives ON the
  # branch, not in the base. BOTH legs must pass and the verdict must SAY so, or leg 2 would refuse
  # every compliant slice in this repo. Uses the DERIVED base ladder (no --base-ref), because that is
  # the route the pre-push hook and any un-wired adopter CI take.
  _legs=$((_legs+1))   # legB9
  _mkbase "$_tmp/fB9" onbranch branch/feat/new
  _outB9="$( cd "$_tmp/fB9" && run_ceremony_binding "$_tmp/changed-cp" \
               --scope PR-1 --head-branch feat/new 2>&1 )" && _rcB9=0 || _rcB9=$?
  case "$_rcB9:$_outB9" in
    0:*"not already integrated"*)
      echo "PASS legB9: a design commit ON the branch passes BOTH containment legs, and the verdict names the state" ;;
    0:*) echo "FAIL legB9: the run passed but the verdict does not claim leg 2 — a skipped leg is being read as a full containment: $_outB9"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legB9: our own compliant shape must PASS with both legs, got rc=$_rcB9: $_outB9"
       _fails=$((_fails+1)) ;;
  esac

  # LEG B10 (THE DISCLOSED DEGRADATION) — with NO base resolvable (no --base-ref, no origin, no
  # main/master), leg 2 is SKIPPED: rc UNCHANGED, the skip DISCLOSED, and the verdict downgraded to
  # reachable-only. Two failure modes pinned in both directions — a red here would break every shallow
  # clone and every fresh local repo (the green-on-clone class in reverse), and a SILENT skip would let
  # a reachable-only green be read as the full containment the ratified ceiling claims.
  _legs=$((_legs+1))   # legB10
  _mkbase "$_tmp/fB10" nobase branch/feat/nobase
  _outB10="$( cd "$_tmp/fB10" && run_ceremony_binding "$_tmp/changed-cp" \
                --scope PR-1 --head-branch feat/nobase 2>&1 )" && _rcB10=0 || _rcB10=$?
  case "$_rcB10:$_outB10" in
    0:*"no base history resolved"*"reachable-only"*)
      echo "PASS legB10: an unresolvable base -> leg 2 SKIPPED, disclosed, rc UNCHANGED (0), verdict downgraded" ;;
    2:*) echo "FAIL legB10: an unresolvable base REDDENED the gate — a clone SHAPE must never be an anomaly: $_outB10"
         _fails=$((_fails+1)) ;;
    0:*) echo "FAIL legB10: leg 2 was skipped SILENTLY or the verdict still claims full containment: $_outB10"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legB10: expected rc 0 with a disclosed degradation, got rc=$_rcB10: $_outB10"
       _fails=$((_fails+1)) ;;
  esac

  # LEG B11 (THE NAMED EDGE) — a GO recorded at the FORK POINT (approved-sha == merge-base) is
  # DEFECTIVE, and deliberately so: that commit is already in the base, so the record says nothing
  # about this branch's work. Named in the refusal's second sentence with its remedy (a fresh GO), and
  # pinned here so the edge is a DECISION rather than an accident of the predicate. Derived base route.
  _legs=$((_legs+1))   # legB11
  _mkbase "$_tmp/fB11" forkpoint branch/feat/fork
  _outB11="$( cd "$_tmp/fB11" && run_ceremony_binding "$_tmp/changed-cp" \
                --scope PR-1 --head-branch feat/fork 2>&1 || true )"
  ( cd "$_tmp/fB11" && run_ceremony_binding "$_tmp/changed-cp" \
      --scope PR-1 --head-branch feat/fork ) >/dev/null 2>&1 && _rcB11=0 || _rcB11=$?
  case "$_rcB11:$_outB11" in
    2:*ALREADY-INTEGRATED*"FORK POINT"*)
      echo "PASS legB11: a GO recorded at the fork point -> rc 2, ALREADY-INTEGRATED, the edge NAMED with its remedy" ;;
    2:*) echo "FAIL legB11: refused, but the fork-point edge is not NAMED — the operator is told to record a GO without being told why this one failed: $_outB11"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legB11: expected rc 2 naming ALREADY-INTEGRATED + the fork point, got rc=$_rcB11: $_outB11"
       _fails=$((_fails+1)) ;;
  esac

  # ── C8 GOVERNANCE-ARM legs (GOVERNANCE-RECORD-PR-HAS-NO-DESIGN-BASIS). Every one of them asserts a
  # GOVERNANCE-SPECIFIC string — the arm label `(gate: governance)` via _expect_fail_gov, or a message
  # only the governance arm can print — so none can go green on a design-arm refusal. The two
  # load-bearing negatives (legG6, legG7) run on TWO-BRANCH fixtures and exercise the REAL derivation
  # through the real authority; a fixture-listing shortcut would have proven the fixture, not the
  # production path.

  # LEG G1 (THE POSITIVE ANCHOR) — a governance GO on a PURE governance-record change PASSES and the
  # verdict NAMES the arm. Two properties, each measured rather than asserted:
  #   * the fixture touches EVERY member of the governance set, so DELETING a member from
  #     _gov_path_in_set REDs this leg (mutation-measured: dropping `skills/*/SKILL.md` -> rc 2). The
  #     enumeration cannot rot silently.
  #   * the "SUBSET of the governance set" sentence is emitted ONLY when the guard actually walked a
  #     derived list (CB_GOV_SUBSET_JUDGED), so asserting it here also kills a guard neutered to
  #     `return 0` — which, before build-review LOW-6, printed the claim unconditionally and left this
  #     leg green while the arm's only predicate was inert.
  _legs=$((_legs+1))   # legG1
  _mkgov "$_tmp/fG1" conforming
  _outG1="$( cd "$_tmp/fG1" && DIR="$_tmp/fG1" run_ceremony_binding "$_tmp/changed-cp" \
               --scope PR-1 2>&1 )" && _rcG1=0 || _rcG1=$?
  case "$_rcG1:$_outG1" in
    0:*"GOVERNANCE GATE recorded"*)
      case "$_outG1" in
        *"SUBSET of the governance set"*)
          echo "PASS legG1: a pure governance-record change PASSES on a governance GO, verdict names the arm + the subset judgment" ;;
        *) echo "FAIL legG1: passed but the verdict does not claim the diff-shape judgment — a green would be read as more than was measured: $_outG1"
           _fails=$((_fails+1)) ;;
      esac ;;
    1:*) echo "FAIL legG1: a valid governance GO still WAITS — the governance gate value is not matched: $_outG1"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legG1: expected rc 0 naming 'GOVERNANCE GATE recorded', got rc=$_rcG1: $_outG1"
       _fails=$((_fails+1)) ;;
  esac

  # LEG G2 — a governance GO whose basis is an ORDINARY file. The design arm's leg5d, in the
  # governance arm's words: without the glob, any substantive tracked file would be a "panel record".
  _mkfix "$_tmp/fG2" governance "README.md" real
  _expect_fail_gov legG2 "$_tmp/fG2" "not a governance artifact" "governance GO naming an ordinary file as the panel artifact"

  # LEG G3 — a governance GO naming a panel artifact that does not exist. Asserts a SHARED-chain
  # message, which is exactly why _expect_fail_gov also pins the arm: the same words would appear if
  # this record had fallen through to the design arm.
  _mkfix "$_tmp/fG3" governance "docs/architecture/2026-08-15-meta-control-99.md" none
  _expect_fail_gov legG3 "$_tmp/fG3" "not a tracked file" "governance GO naming an absent panel artifact"

  # LEG G4 (THE DURABLE PIN FOR THE LIVE DEFECT) — the ledger's `1d9f0afa` body, replayed
  # byte-faithfully: `gate: design` + a meta-control basis. It must STAY defective. This is the
  # regression that stops a future "fix" from widening CB_DESIGN_GLOB to admit panel artifacts, which
  # would erase the design/governance distinction inside one glob (design §5, approach B — rejected).
  _legs=$((_legs+1))   # legG4
  _mkreplay "$_tmp/fG4"
  _outG4="$( cd "$_tmp/fG4" && DIR="$_tmp/fG4" run_ceremony_binding "$_tmp/changed-cp" \
               --scope PR-517 2>&1 || true )"
  ( cd "$_tmp/fG4" && DIR="$_tmp/fG4" run_ceremony_binding "$_tmp/changed-cp" --scope PR-517 ) \
    >/dev/null 2>&1 && _rcG4=0 || _rcG4=$?
  case "$_rcG4:$_outG4" in
    2:*"is not a design artifact"*)
      case "$_outG4" in
        *"(gate: design)"*)
          echo "PASS legG4: the replayed live record (design gate + meta-control basis) stays DEFECTIVE on the DESIGN arm" ;;
        *) echo "FAIL legG4: refused, but the record was not adjudicated as a design record: $_outG4"
           _fails=$((_fails+1)) ;;
      esac ;;
    0:*) echo "FAIL legG4: the live defective record now PASSES — the governance arm has leaked into the design arm and the ledger's evidence of the gap is retro-cured"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legG4: expected rc 2 naming 'is not a design artifact', got rc=$_rcG4: $_outG4"
       _fails=$((_fails+1)) ;;
  esac

  # LEG G5 (ADJUDICATION BY DISQUALIFICATION) — a record carrying BOTH accepted gate values is
  # DEFECTIVE. The alternative is a dispatch lottery on a hand-minted note: whichever matcher ran
  # first would decide whether the diff-shape guard applies at all. Same class as the #509 wedge.
  # The gate parameter carries a literal newline, so _mkfix writes TWO `gate:` lines.
  _mkfix "$_tmp/fG5" "$(printf 'design\ngate: governance')" "docs/architecture/d-design.md" real
  _expect_fail legG5 "$_tmp/fG5" "BOTH 'gate: design' and 'gate: governance'" \
    "a record carrying two accepted gate values" 2 "$_tmp/fG5"

  # LEG G6 (THE SLICE'S THESIS, AND ITS LOAD-BEARING NEGATIVE) — a VALID governance record whose
  # change-set carries a control-plane payload is DEFECTIVE, and the escaping path is NAMED. Every
  # other leg of the chain passes on this fixture; the diff shape is the only thing that can refuse.
  # TWO-BRANCH: the file list comes from the real authority walking the real merge-base.
  _legs=$((_legs+1))   # legG6
  _mkgov "$_tmp/fG6" escapes
  _outG6="$( cd "$_tmp/fG6" && DIR="$_tmp/fG6" run_ceremony_binding "$_tmp/changed-cp" \
               --scope PR-1 2>&1 || true )"
  ( cd "$_tmp/fG6" && DIR="$_tmp/fG6" run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 ) \
    >/dev/null 2>&1 && _rcG6=0 || _rcG6=$?
  case "$_rcG6:$_outG6" in
    2:*"OUTSIDE the"*"governance set"*)
      case "$_outG6" in
        *conformance/x.sh*)
          case "$_outG6" in
            *"SPLIT YOUR CURES"*)
              echo "PASS legG6: a governance GO carrying a control-plane payload -> rc 2, the escaping path NAMED with the split-your-cures cure" ;;
            *) echo "FAIL legG6: refused and named the path, but the operator is not told the cure: $_outG6"
               _fails=$((_fails+1)) ;;
          esac ;;
        *) echo "FAIL legG6: refused without NAMING the escaping path — an operator cannot act on 'something escaped': $_outG6"
           _fails=$((_fails+1)) ;;
      esac ;;
    0:*) echo "FAIL legG6: a control-plane payload RODE ALONG on a governance record — the arm's only anti-laundering predicate is inert: $_outG6"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legG6: expected rc 2 naming the escaping path, got rc=$_rcG6: $_outG6"
       _fails=$((_fails+1)) ;;
  esac

  # LEG G7 (THE RENAME LEG — vet HIGH-1) — `git mv` of an out-of-set file ONTO an in-set name. With
  # git's default rename detection the derivation emits the DESTINATION ALONE and the workflow
  # DELETION vanishes from the change-set; only the authority's `--no-renames` keeps the source
  # visible. This is why the guard reads promotion-readiness.sh instead of running its own git diff.
  _legs=$((_legs+1))   # legG7
  _mkgov "$_tmp/fG7" rename
  # PREMISE, ASSERTED NOT ASSUMED: the leg is meaningless unless a rename-detecting derivation really
  # would have hidden the source. FAIL, never skip — a skipped premise is an unproven leg.
  _g7def="$( cd "$_tmp/fG7" && git diff --name-only main...HEAD 2>/dev/null || true )"
  if printf '%s\n' "$_g7def" | grep -qF '.github/workflows/ci.yml'; then
    echo "FAIL legG7: premise — the DEFAULT (rename-detecting) derivation still shows the source path, so this fixture cannot demonstrate the collapse and the leg proves NOTHING"
    _fails=$((_fails+1))
  else
    echo "PASS legG7-premise: the default rename-detecting derivation HIDES the moved-away source"
  fi
  _outG7="$( cd "$_tmp/fG7" && DIR="$_tmp/fG7" run_ceremony_binding "$_tmp/changed-cp" \
               --scope PR-1 2>&1 || true )"
  ( cd "$_tmp/fG7" && DIR="$_tmp/fG7" run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 ) \
    >/dev/null 2>&1 && _rcG7=0 || _rcG7=$?
  case "$_rcG7:$_outG7" in
    2:*".github/workflows/ci.yml"*)
      echo "PASS legG7: a git mv of a workflow ONTO an in-set name -> rc 2, the SOURCE path named (--no-renames is inherited from the single authority)" ;;
    0:*) echo "FAIL legG7: a workflow DELETION laundered through the governance lane — the guard is deriving the change-set with rename detection on: $_outG7"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legG7: expected rc 2 naming the renamed-away source, got rc=$_rcG7: $_outG7"
       _fails=$((_fails+1)) ;;
  esac

  # LEG G8 (THE COMPOSITION LEG — vet Q4) — a defective design record and a governance record on the
  # SAME key, over a change-set that escapes the set. The B7 adjudicate-all rider passes if ANY record
  # survives, so this pins that two records cannot launder each other: each is defective on its own
  # arm, and the verdict names BOTH with the arm that judged each.
  _legs=$((_legs+1))   # legG8
  _mkgov "$_tmp/fG8" composition
  _outG8="$( cd "$_tmp/fG8" && DIR="$_tmp/fG8" run_ceremony_binding "$_tmp/changed-cp" \
               --scope PR-1 2>&1 || true )"
  ( cd "$_tmp/fG8" && DIR="$_tmp/fG8" run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 ) \
    >/dev/null 2>&1 && _rcG8=0 || _rcG8=$?
  if [ "$_rcG8" = 2 ] && printf '%s' "$_outG8" | grep -qF '(gate: governance)' \
     && printf '%s' "$_outG8" | grep -qF '(gate: design)' \
     && printf '%s' "$_outG8" | grep -qF 'ALL 2 matching'; then
    echo "PASS legG8: a defective design record + a governance record over an escaping diff -> rc 2, each named with its arm (no laundering through the rider)"
  else
    echo "FAIL legG8: expected rc 2 naming BOTH arms and 'ALL 2 matching', got rc=$_rcG8: $_outG8"
    _fails=$((_fails+1))
  fi

  # LEG G9 (FAIL-CLOSED — vet MED-1) — with NO base resolvable the change-set is UNDERIVABLE, and the
  # governance arm must RED rather than skip. The containment-leg-2 disclosed-skip precedent does NOT
  # transfer: leg 2 has a sibling that still bites, this guard is the arm's only anti-laundering leg,
  # so a skip would green exactly the property the arm exists for. The refusal names the cure.
  _legs=$((_legs+1))   # legG9
  _mkgov "$_tmp/fG9" nobase
  _outG9="$( cd "$_tmp/fG9" && DIR="$_tmp/fG9" run_ceremony_binding "$_tmp/changed-cp" \
               --scope PR-1 2>&1 || true )"
  ( cd "$_tmp/fG9" && DIR="$_tmp/fG9" run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 ) \
    >/dev/null 2>&1 && _rcG9=0 || _rcG9=$?
  case "$_rcG9:$_outG9" in
    2:*"could not be DERIVED"*"fetch-depth: 0"*)
      echo "PASS legG9: an underivable change-set -> rc 2 FAIL CLOSED, naming the fetch-depth cure" ;;
    0:*) echo "FAIL legG9: an underivable change-set PASSED — the guard skipped the only leg the governance arm has: $_outG9"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legG9: expected rc 2 naming the derive failure + its cure, got rc=$_rcG9: $_outG9"
       _fails=$((_fails+1)) ;;
  esac

  # LEG G10 (THE COLOUR LEG) — a governance-SHAPED change with NO record at all is the WAITING yellow
  # (rc 1), not red. The diff-shape guard must never fire on a PR that has no governance record to
  # judge: a change waiting for its GO is a normal stage of healthy work, and painting it red is how
  # a wait comes to look like a break. The guidance also has to MENTION the governance lane, or an
  # operator on a panel PR is instructed straight back into the design-basis workaround.
  _legs=$((_legs+1))   # legG10
  _mkgov "$_tmp/fG10" conforming
  ( cd "$_tmp/fG10" && git update-ref -d refs/notes/promotions 2>/dev/null || true )
  _outG10="$( cd "$_tmp/fG10" && DIR="$_tmp/fG10" run_ceremony_binding "$_tmp/changed-cp" \
                --scope PR-1 2>&1 || true )"
  ( cd "$_tmp/fG10" && DIR="$_tmp/fG10" run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 ) \
    >/dev/null 2>&1 && _rcG10=0 || _rcG10=$?
  case "$_rcG10:$_outG10" in
    1:*"--gate governance"*)
      echo "PASS legG10: a governance-shaped change with no record -> rc 1 WAITING (yellow), and the guidance names the governance lane" ;;
    2:*) echo "FAIL legG10: a change with NO record RED-ed — the diff-shape guard fired with nothing to judge, turning a normal wait into a break: $_outG10"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legG10: expected rc 1 with governance-aware guidance, got rc=$_rcG10: $_outG10"
       _fails=$((_fails+1)) ;;
  esac

  # LEG G11 (TYPE-AWARE NEAR-MISS — vet LOW-2) — when the ledger holds ONLY governance records and
  # none is scoped here, the near-miss must say so and hand back the GOVERNANCE record form. Telling
  # that operator to record a DESIGN GO is how a correct governance change gets "cured" back into the
  # workaround. rc 1: still a wait.
  _legs=$((_legs+1))   # legG11
  _outG11="$( cd "$_tmp/fG1" && DIR="$_tmp/fG1" run_ceremony_binding "$_tmp/changed-cp" \
                --scope PR-42 2>&1 || true )"
  ( cd "$_tmp/fG1" && DIR="$_tmp/fG1" run_ceremony_binding "$_tmp/changed-cp" --scope PR-42 ) \
    >/dev/null 2>&1 && _rcG11=0 || _rcG11=$?
  case "$_rcG11:$_outG11" in
    1:*"a 'gate: governance' record exists"*"--gate governance"*)
      echo "PASS legG11: a governance-only ledger near-miss -> rc 1 naming the GOVERNANCE record form, never the design one" ;;
    1:*) echo "FAIL legG11: rc 1, but the near-miss diagnosis or the record-one guidance still speaks of a DESIGN GO: $_outG11"
         _fails=$((_fails+1)) ;;
    *) echo "FAIL legG11: expected rc 1 with a governance near-miss, got rc=$_rcG11: $_outG11"
       _fails=$((_fails+1)) ;;
  esac

  # LEG G12 (THE RENDER LEARNS THE VALUE — design §2.9, the D-240805-4 half) — a ledger with one
  # design and one governance record on the same key renders BOTH, each TAGGED with its gate value. A
  # render that matched `design` alone would show NOTHING on exactly the PRs this arm enables: the
  # gate green and the owner clicking GO with no record in view — a visibility lie manufactured by
  # the fix. (The other half of single-sourcing — that both workflow legs INVOKE this — is
  # adopter-gates-parity.sh's job.)
  _legs=$((_legs+1))   # legG12
  _outG12="$( cd "$_tmp/fG8" && DIR="$_tmp/fG8" run_ceremony_binding '' --render --scope PR-1 2>/dev/null )" \
    && _rcG12=0 || _rcG12=$?
  if [ "$_rcG12" = 0 ] && printf '%s\n' "$_outG12" | grep -qF '[governance] ---' \
     && printf '%s\n' "$_outG12" | grep -qF '[design] ---' \
     && printf '%s\n' "$_outG12" | grep -qF 'gate: governance' \
     && printf '%s\n' "$_outG12" | grep -qF '(2 matched'; then
    echo "PASS legG12: --render shows BOTH a design and a governance record, each tagged with its gate value"
  else
    echo "FAIL legG12: the render did not show both records tagged by type (rc=$_rcG12): $_outG12"
    _fails=$((_fails+1))
  fi

  # LEG G13 (SELF-ATTACK, mirroring leg5e) — a UNIVERSAL CB_GOV_GLOB must be REFUSED. It is the wider
  # of the two off-switches: with `CB_GOV_GLOB='*'` any tracked file becomes a "panel artifact" AND
  # the governance set's meta-control member admits every path, so the diff-shape guard dies with it.
  _legs=$((_legs+1))   # legG13
  if ( CB_GOV_GLOB='*' sh "$0" --selftest ) >/dev/null 2>&1; then
    echo "FAIL legG13: a universal CB_GOV_GLOB must be refused"; _fails=$((_fails+1))
  else
    echo "PASS legG13: universal CB_GOV_GLOB -> refused"
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
# <dir-override> (6th, C8) is the fixture's own $DIR: it makes the run consult the AUTHORITY COPY
# inside the fixture instead of the kit's, so the governance diff-shape guard derives the FIXTURE's
# change-set. Without it a governance leg would grade the kit's own working branch — non-hermetic,
# and green or red for reasons that have nothing to do with the fixture (the ambient-tree defect this
# file already paid for once, leg 2). POSITIONAL, not an inherited `_var=x` prefix: a prefix
# assignment on a FUNCTION call persists in some shells and not others, so the next leg would inherit
# it silently. Defaults to the real $DIR, so all 51 existing call sites are byte-unchanged in effect.
_expect_fail() {
  _ln="$1"; _fd="$2"; _exp="$3"; _desc="$4"; _exp_rc="${5:-2}"; _ef_dir="${6:-$DIR}"; _legs=$((_legs+1))
  _out="$( cd "$_fd" && DIR="$_ef_dir" run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 2>&1 || true )"
  # Capture the rc, guarded: a bare call would abort the whole selftest under `set -e`. The
  # `&& x=0 || x=$?` form is the file's existing idiom for this.
  ( cd "$_fd" && DIR="$_ef_dir" run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 ) >/dev/null 2>&1 \
    && _got_rc=0 || _got_rc=$?
  if [ "$_got_rc" = 0 ]; then
    echo "FAIL $_ln: $_desc should FAIL but PASSed"; _fails=$((_fails+1)); return 0
  fi
  # ★ THE PARTITION ASSERTION (WAITING-GATES-RENDER-AS-RED). Defaulting to 2 is what makes this cheap
  # AND complete: every one of the 17 existing negative legs gains the check with its call site
  # UNEDITED, and only the three genuine waiting states opt in to 1. Before this the helper accepted
  # ANY non-zero rc, so a defect path left at rc 1 — rendering a broken GO record as the normal yellow
  # "waiting on a human" — would have passed all 17 legs unnoticed. A new negative leg must now
  # deliberately declare itself a wait; silence means anomaly.
  if [ "$_got_rc" != "$_exp_rc" ]; then
    echo "FAIL $_ln: $_desc exited rc=$_got_rc, expected rc=$_exp_rc (1 = WAITING/yellow, 2 = anomaly/red)"
    _fails=$((_fails+1))
  fi
  case "$_out" in
    *"$_exp"*) echo "PASS $_ln: $_desc -> FAIL naming '$_exp'" ;;
    *) echo "FAIL $_ln: FAILed for the WRONG reason — expected '$_exp', got: $_out"
       _fails=$((_fails+1)) ;;
  esac
}

# _expect_fail_gov <leg> <fixture-dir> <expected-substring> <description> [expected-rc]
# The C8 kill assertion for a GOVERNANCE leg. Everything _expect_fail does, plus TWO things it cannot:
#   (1) it runs with the FIXTURE as $DIR, so the diff-shape guard derives the fixture's own change-set
#       through the real authority (never the kit's working tree);
#   (2) it requires the verdict to identify the record as `(gate: governance)` IN ADDITION to the
#       expected text. Several legs below assert a SHARED-chain message ("not a tracked file"), and a
#       shared message proves nothing about WHICH arm ran — a governance leg that silently fell
#       through to the design arm would print exactly the same words. Pinning the arm is what stops a
#       governance leg going green on a design-arm message (the vet's Q7 condition).
_expect_fail_gov() {
  _gln="$1"; _gfd="$2"; _gexp="$3"; _gdesc="$4"; _gexp_rc="${5:-2}"; _legs=$((_legs+1))
  _gout="$( cd "$_gfd" && DIR="$_gfd" run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 2>&1 || true )"
  ( cd "$_gfd" && DIR="$_gfd" run_ceremony_binding "$_tmp/changed-cp" --scope PR-1 ) >/dev/null 2>&1 \
    && _ggot_rc=0 || _ggot_rc=$?
  if [ "$_ggot_rc" = 0 ]; then
    echo "FAIL $_gln: $_gdesc should FAIL but PASSed"; _fails=$((_fails+1)); return 0
  fi
  if [ "$_ggot_rc" != "$_gexp_rc" ]; then
    echo "FAIL $_gln: $_gdesc exited rc=$_ggot_rc, expected rc=$_gexp_rc (1 = WAITING/yellow, 2 = anomaly/red)"
    _fails=$((_fails+1))
  fi
  case "$_gout" in
    *"$_gexp"*)
      case "$_gout" in
        *"(gate: governance)"*) echo "PASS $_gln: $_gdesc -> FAIL naming '$_gexp', adjudicated by the GOVERNANCE arm" ;;
        *) echo "FAIL $_gln: the verdict names '$_gexp' but NOT '(gate: governance)' — the leg cannot tell which arm refused, so it would pass on a design-arm message: $_gout"
           _fails=$((_fails+1)) ;;
      esac ;;
    *) echo "FAIL $_gln: FAILed for the WRONG reason — expected '$_gexp', got: $_gout"
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



# _mkfix2 <dir> <defective:lower|higher|both> — TWO commits, EACH carrying a 'gate: design' record
# with the SAME scope key (PR-1): the #509 wedge shape. `git notes list` iterates in annotated-SHA
# order (measured 2026-08-08, insertion-order-independent), so 'lower' plants the DEFECTIVE record
# where the old first-match break examined it FIRST and the valid record was shadowed; 'higher' is
# the reverse; 'both' makes every match defective. The defective shape is leg14's (no approved-by
# line). Writes .valid-sha / .defective-sha(s) files for the legs' assertions — those are written
# AFTER the commits, so they stay untracked and cannot disturb the fixture's diff.
_mkfix2() {
  _d2="$1"; _w2="$2"
  mkdir -p "$_d2/docs/architecture"
  (
    cd "$_d2" || exit 1
    git init -q 2>/dev/null
    git config user.email fixture@example.invalid
    git config user.name Fixture
    # Same substance shape as _mkfix's `real` (>= 8 non-blank lines under a heading) — the valid
    # record must clear obl_is_placeholder, or these legs silently test the floor instead.
    printf '%s\n' \
      '# Design — fixture' '' '## Approach' \
      'The gate derives the change class from the single hardened authority and refuses to' \
      'classify a change-set it cannot read. The trade-off is that a stricter refusal costs' \
      'an operator an explicit re-record when the base is unreachable, which is the fail-safe' \
      'direction and the one this kit takes everywhere else.' \
      'Identification rides on the GO record rather than a registry, so the binding claim' \
      'here is non-trivial instead of vacuously true of every document in history.' \
      '## Honest ceiling' \
      'Proves existence and record binding only; it does not prove the design is sound.' \
      > docs/architecture/d-design.md
    printf 'fixture repo\n' > README.md
    git add -A 2>/dev/null
    git -c user.email=fixture@example.invalid -c user.name=Fixture commit -q -m fixture >/dev/null 2>&1
    _c1=$(git rev-parse HEAD)
    printf 'Amended: a second commit touching the artifact.\n' >> docs/architecture/d-design.md
    git add -A 2>/dev/null
    git -c user.email=fixture@example.invalid -c user.name=Fixture commit -q -m fixture2 >/dev/null 2>&1
    _c2=$(git rev-parse HEAD)
    # POSIX-portable lexicographic order (SC3012: `\<` in [ ] is undefined in POSIX sh —
    # CI's shellcheck flags it; a newer local one did not. LC_ALL=C pins the collation.)
    _lo=$(printf '%s\n%s\n' "$_c1" "$_c2" | LC_ALL=C sort | head -n 1)
    if [ "$_lo" = "$_c1" ]; then _hi="$_c2"; else _hi="$_c1"; fi
    _note2() { # <commit> <defective:1|0> — both commits touch the basis, so approved-sha binds
      if [ "$2" = 1 ]; then _ap2="change-class: control-plane"; else _ap2="approved-by: Fixture Human [committer]"; fi
      printf '%s\n' "record: promotion GO (approve->execute->log)" \
        "gate: design" "scope: PR-1" "$_ap2" "approved-sha: $1" \
        "change-class: control-plane" "basis: docs/architecture/d-design.md" \
        | git notes --ref=promotions add -f -F - "$1" 2>/dev/null
    }
    case "$_w2" in
      (lower)  _note2 "$_lo" 1; _note2 "$_hi" 0
               printf '%s\n' "$_lo" > .defective-sha; printf '%s\n' "$_hi" > .valid-sha ;;
      (higher) _note2 "$_hi" 1; _note2 "$_lo" 0
               printf '%s\n' "$_hi" > .defective-sha; printf '%s\n' "$_lo" > .valid-sha ;;
      (both)   _note2 "$_c1" 1; _note2 "$_c2" 1
               printf '%s\n%s\n' "$_c1" "$_c2" > .defective-shas ;;
    esac
  )
}

# _mkcontain <dir> <scope> — the Δ2 CONTAINMENT fixture: a record whose scope key MATCHES and whose
# approved-sha TOUCHES the basis, but whose approved commit is NOT in the graded head's history.
# Shape: c1 authors the design doc; a side branch adds c2, which also touches it; HEAD is then
# detached back at c1 and the note is written on c2. So every other leg of check_design_record
# passes and CONTAINMENT is the ONLY thing that can refuse — the fixture differs from the passing
# case in exactly one respect, which is this file's own hard-won rule (leg 3 / leg 5's tautologies).
# This is the reused-branch-name hazard in miniature: the record is real, it is simply not ours.
_mkcontain() {
  _dc="$1"; _scc="$2"
  mkdir -p "$_dc/docs/architecture"
  (
    cd "$_dc" || exit 1
    git init -q 2>/dev/null
    git config user.email fixture@example.invalid; git config user.name Fixture
    # >= 8 non-blank lines under a heading, or obl_is_placeholder fires the FLOOR signal and this
    # leg silently tests the substance floor instead of containment.
    printf '%s\n' \
      '# Design — fixture' '' '## Approach' \
      'The gate derives the change class from the single hardened authority and refuses to' \
      'classify a change-set it cannot read. The trade-off is that a stricter refusal costs' \
      'an operator an explicit correction when the base is unreachable, which is the fail-safe' \
      'direction and the one this kit takes everywhere else.' \
      'Identification rides on the GO record rather than a registry, so the binding claim' \
      'here is non-trivial instead of vacuously true of every document in history.' \
      '## Honest ceiling' \
      'Proves existence and record binding only; it does not prove the design is sound.' \
      > docs/architecture/d-design.md
    printf 'fixture repo\n' > README.md
    git add -A 2>/dev/null; git commit -q -m fixture >/dev/null 2>&1
    _cc1=$(git rev-parse HEAD)
    printf 'A second commit on the OTHER branch, touching the artifact.\n' >> docs/architecture/d-design.md
    git add -A 2>/dev/null; git commit -q -m fixture-elsewhere >/dev/null 2>&1
    _cc2=$(git rev-parse HEAD)
    printf '%s\n' "record: promotion GO (approve->execute->log)" "gate: design" \
      "scope: $_scc" "approved-by: Fixture Human [committer]" "approved-sha: $_cc2" \
      "change-class: control-plane" "basis: docs/architecture/d-design.md" \
      | git notes --ref=promotions add -f -F - "$_cc2" 2>/dev/null
    # Graded head goes BACK to c1, which does not contain c2.
    git checkout -q --detach "$_cc1"
  )
}

# _mkbase <dir> <shape> <scope> — the Δ2 LEG 2 fixtures ("not already integrated"). Each shape differs
# from the PASSING one (`onbranch`) in exactly ONE respect — WHERE the approved commit sits relative to
# the base — so a leg can only fail for the reason it names (this file's hard-won rule; see leg 3/leg 5).
#   integrated  the historic branch was MERGED/REBASED into the base, so its approved commit is on the
#               MAINLINE; a NEW branch REUSES the name and carries no fresh record. THE MEASURED CLASS.
#   onbranch    our own compliant flow: the approved commit is on the branch, not in the base.
#   forkpoint   the GO was recorded at the merge-base itself (branched, then recorded at the fork point).
#   nobase      no base is resolvable at all: no remote, and the sole branch is named neither
#               main nor master, so the derived ladder finds nothing.
# ⚠️ THE DEFAULT BRANCH NAME IS SET EXPLICITLY, BEFORE THE FIRST COMMIT. `git init` honours the user's
# init.defaultBranch, so a developer configured to `master` (or anything else) would otherwise build a
# DIFFERENT fixture than CI does — and these legs turn on precisely whether that ref resolves. Same
# class as the PROMOTION_NOTES_REF / CB_DESIGN_GLOB pins at the top of selftest().
_mkbase() {
  _dz="$1"; _shz="$2"; _scz="$3"
  mkdir -p "$_dz/docs/architecture"
  (
    cd "$_dz" || exit 1
    git init -q 2>/dev/null
    git config user.email fixture@example.invalid; git config user.name Fixture
    case "$_shz" in
      nobase) git symbolic-ref HEAD refs/heads/sole ;;
      *)      git symbolic-ref HEAD refs/heads/main ;;
    esac
    # >= 8 non-blank lines under a heading, or obl_is_placeholder fires the FLOOR signal and these
    # legs silently test the substance floor instead of containment.
    _mkbase_doc() {
      printf '%s\n' \
        '# Design — fixture' '' '## Approach' \
        'The gate derives the change class from the single hardened authority and refuses to' \
        'classify a change-set it cannot read. The trade-off is that a stricter refusal costs' \
        'an operator an explicit correction when the base is unreachable, which is the fail-safe' \
        'direction and the one this kit takes everywhere else.' \
        'Identification rides on the GO record rather than a registry, so the binding claim' \
        'here is non-trivial instead of vacuously true of every document in history.' \
        '## Honest ceiling' \
        'Proves existence and record binding only; it does not prove the design is sound.' \
        > docs/architecture/d-design.md
    }
    _mkbase_note() {   # <approved-sha>
      printf '%s\n' "record: promotion GO (approve->execute->log)" "gate: design" \
        "scope: $_scz" "approved-by: Fixture Human [committer]" "approved-sha: $1" \
        "change-class: control-plane" "basis: docs/architecture/d-design.md" \
        | git notes --ref=promotions add -f -F - "$1" 2>/dev/null
    }
    printf 'fixture repo\n' > README.md
    case "$_shz" in
      integrated)
        git add -A 2>/dev/null; git commit -q -m base >/dev/null 2>&1
        # The APPROVED commit, landing on the MAINLINE — a historic branch's design commit after its
        # merge/rebase into the base, which is what makes it reachable from every later branch.
        _mkbase_doc
        git add -A 2>/dev/null; git commit -q -m "historic design, integrated into the base" >/dev/null 2>&1
        _bz_a=$(git rev-parse HEAD)
        git checkout -q -b feat/reused
        printf 'unrelated new work\n' > work.txt
        git add -A 2>/dev/null; git commit -q -m "new work on the REUSED branch name" >/dev/null 2>&1
        _mkbase_note "$_bz_a" ;;
      onbranch)
        git add -A 2>/dev/null; git commit -q -m base >/dev/null 2>&1
        git checkout -q -b feat/new
        _mkbase_doc
        git add -A 2>/dev/null; git commit -q -m "this slice's design, ON the branch" >/dev/null 2>&1
        _mkbase_note "$(git rev-parse HEAD)" ;;
      forkpoint)
        _mkbase_doc
        git add -A 2>/dev/null; git commit -q -m "base, touching the artifact" >/dev/null 2>&1
        _bz_f=$(git rev-parse HEAD)
        git checkout -q -b feat/fork
        printf 'work after the fork\n' > work.txt
        git add -A 2>/dev/null; git commit -q -m "work" >/dev/null 2>&1
        _mkbase_note "$_bz_f" ;;
      nobase)
        git add -A 2>/dev/null; git commit -q -m base >/dev/null 2>&1
        _mkbase_doc
        git add -A 2>/dev/null; git commit -q -m "design on the sole branch" >/dev/null 2>&1
        _mkbase_note "$(git rev-parse HEAD)" ;;
    esac
  )
}

# _mkbigrec <dir> <scope> — a single scope-matching record whose body is far past the render's 8 KB
# total bound (B2's measured volume attack in miniature: the real one emitted 1,601,670 bytes).
_mkbigrec() {
  _db="$1"; _scb="$2"
  mkdir -p "$_db"
  (
    cd "$_db" || exit 1
    git init -q 2>/dev/null
    git config user.email fixture@example.invalid; git config user.name Fixture
    git commit -q --allow-empty -m fixture >/dev/null 2>&1
    { printf '%s\n' "gate: design" "scope: $_scb"
      awk 'BEGIN { s = ""; for (i = 0; i < 1000; i++) s = s "A"; for (j = 0; j < 40; j++) print s }'
    } | git notes --ref=promotions add -f -F - HEAD 2>/dev/null
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
    # ⚠️ PIN THE DEFAULT BRANCH BEFORE THE FIRST COMMIT (C8; _mkbase already does this, for its own
    # reason). `git init` honours the user's init.defaultBranch, so this fixture is born on `main`
    # locally and `master` on a stock CI runner — and promotion-readiness.sh resolves its base as
    # `origin/main` then `main` ONLY. On `master` the base is UNRESOLVABLE, so any leg that reaches
    # the governance diff-shape guard would red for the RUNNER's configuration instead of the
    # fixture's shape. Behaviourally inert for the 51 pre-C8 legs (their class comes from a listing,
    # and the containment ladder resolves `main` here exactly as it resolved `master` before).
    git symbolic-ref HEAD refs/heads/main 2>/dev/null || true
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
  # THE AUTHORITY COPY (C8), written AFTER the commit so it stays UNTRACKED and therefore never
  # appears in the fixture's own change-set. It exists so a leg may run with this fixture as $DIR —
  # then `promotion-readiness.sh` (which cd's to its own ../) derives THIS repo rather than the kit's
  # working tree. Copied unconditionally, defensively: a governance leg that fell through to the
  # guard without it would silently grade the kit's branch and its verdict would be an artifact of
  # whatever the builder happened to have staged.
  mkdir -p "$_d/conformance" "$_d/.claude/hooks"
  cp "$DIR/conformance/promotion-readiness.sh" "$_d/conformance/promotion-readiness.sh"
  # `if`, never `[ … ] && cp`: a false test makes the whole && list non-zero, and under `set -e` that
  # kills the selftest mid-list with no diagnostic (this file's third-most-expensive failure mode).
  if [ -f "$DIR/.claude/hooks/guard-core.sh" ]; then
    cp "$DIR/.claude/hooks/guard-core.sh" "$_d/.claude/hooks/guard-core.sh"
  fi
  return 0
}

# ---- C8 GOVERNANCE FIXTURES ---------------------------------------------------------------------
#
# _mkgov <dir> <shape> — the governance-arm fixtures. TWO-BRANCH BY CONSTRUCTION (the legB11
# fork-shape precedent), and that is the load-bearing property, not a convenience: the diff-shape
# guard's whole claim is about the REAL derivation, so a fixture that handed the leg a listing would
# prove the listing, not the production path (vet HIGH-2 — the C7 vacuity class aimed at this very
# design's core leg). Each fixture therefore carries its own COMMITTED copy of the derivation
# authority + the guard core, is born on `main`, forks to `gov`, and lets
# `promotion-readiness.sh --changed-files` walk merge-base(main, HEAD)...HEAD for real.
#
# Shapes — each differs from the PASSING one in exactly ONE respect, so a leg can only fail for the
# reason it names (this file's hard-won rule; see leg 3 / leg 5):
#   conforming   the branch touches EVERY member of the governance set and nothing else. The positive
#                anchor — and because it exercises all eight members, DELETING a member from
#                _gov_path_in_set REDs it, which is what keeps the enumeration honest.
#   escapes      conforming + `conformance/x.sh`. THE SLICE'S THESIS: a valid governance record must
#                not carry a control-plane payload.
#   rename       `git mv .github/workflows/ci.yml docs/kit-internals/meta-control.md` — the destination is
#                IN the set and the source is not. With rename detection on (pinned in the fixture's
#                own config) the default derivation emits the destination ALONE and the workflow
#                deletion vanishes; only the authority's `--no-renames` keeps the source visible.
#   composition  escapes + a SECOND, defective design record on the same scope key: the B7
#                adjudicate-all rider must not let a governance record and a design record launder
#                each other into a pass.
#   nobase       no `main`, no origin: the change-set is UNDERIVABLE, which must fail CLOSED.
_mkgov() {
  _dv="$1"; _shv="$2"
  mkdir -p "$_dv/conformance" "$_dv/.claude/hooks" "$_dv/docs/architecture" "$_dv/docs/governance" \
           "$_dv/docs/kit-internals" "$_dv/skills/design" "$_dv/.github/workflows"
  cp "$DIR/conformance/promotion-readiness.sh" "$_dv/conformance/promotion-readiness.sh"
  if [ -f "$DIR/.claude/hooks/guard-core.sh" ]; then
    cp "$DIR/.claude/hooks/guard-core.sh" "$_dv/.claude/hooks/guard-core.sh"
  fi
  (
    cd "$_dv" || exit 1
    git init -q 2>/dev/null
    # `nobase` is the ONE shape whose branch name matters: neither `main` nor `master` exists, and
    # there is no remote, so promotion-readiness's base ladder finds nothing at all.
    case "$_shv" in
      nobase) git symbolic-ref HEAD refs/heads/sole ;;
      *)      git symbolic-ref HEAD refs/heads/main ;;
    esac
    git config user.email fixture@example.invalid; git config user.name Fixture
    # PIN RENAME DETECTION ON in the fixture's OWN config (local outranks global), or the `rename`
    # leg's premise evaporates on a host configured with diff.renames=false: the unfixed derivation
    # would emit both paths anyway and the leg would pass while proving nothing. Same pin, same
    # reason, as promotion-readiness-wired.sh's mkrepo_mv.
    git config diff.renames true
    _gov_art() {   # >= 8 non-blank lines under a heading, or obl_is_placeholder fires FLOOR and the
                   # leg silently tests the substance floor instead of the arm it names
      printf '%s\n' \
        '# Meta-control panel 41 — the sitting record' '' '## Verdict' \
        'GO-WITH-CONDITIONS. The panel adjudicated the cadence, the two ledgers and the routing of' \
        'every finding to a boarded row, and recorded the rulings the owner gave in the sitting.' \
        'Ledger 1 (verified-as-quality) and Ledger 2 (fix-forward) are both reproduced below, ranked,' \
        'with the workstream each finding was routed to and the row that now carries it.' \
        'The freshness marker and the verdict log are updated in the same change, which is what makes' \
        'this a governance-record change rather than a design one.' \
        '## Honest ceiling' \
        'A panel record binds the sitting, not the quality of the judgments made in it.' \
        > docs/architecture/2026-08-15-meta-control-41.md
    }
    printf 'fixture repo\n' > README.md
    printf 'name: ci\non: [push]\njobs: {}\n' > .github/workflows/ci.yml
    git add -A 2>/dev/null; git commit -q -m base >/dev/null 2>&1
    case "$_shv" in
      nobase) : ;;                       # stay on `sole`: there is no base to fork from
      *)      git checkout -q -b gov ;;
    esac
    _gov_art
    case "$_shv" in
      rename)
        # ONE escaping path and one in-set destination: the source must NOT be re-created, or the
        # derivation would see a modify instead of the delete this leg is about.
        git mv .github/workflows/ci.yml docs/kit-internals/meta-control.md ;;
      *)
        # EVERY member of the governance set except the two globs (the artifact above is one of
        # them), so the positive anchor proves the whole enumeration rather than one lucky member.
        printf '%s\n' '- [x] GOVERNANCE-ROW — boarded by the panel' >> BACKLOG.md
        printf '%s\n' '- D-240815-1 — a ruling recorded at the sitting' >> docs/governance/DECISIONS.md
        printf '%s\n' 'v3.220.0 GO-WITH-CONDITIONS' > docs/governance/.meta-control-last
        printf '%s\n' '2026-08-15 · v3.220.0 · cadence · full · GO-WITH-CONDITIONS · panel 41' \
          >> docs/governance/meta-control-log.md
        printf '%s\n' '# Meta-control' 'The panel ceremony, amended at the sitting.' \
          > docs/kit-internals/meta-control.md
        printf '%s\n' '# Skill — design' 'Amended at the sitting: a governance GO names its panel artifact.' \
          > skills/design/SKILL.md ;;
    esac
    case "$_shv" in
      escapes|composition)
        # THE PAYLOAD THAT MUST NOT RIDE: a control-plane file, outside the set.
        printf '#!/bin/sh\necho "a routed cure that belongs in its own slice"\n' > conformance/x.sh ;;
    esac
    git add -A 2>/dev/null; git commit -q -m "governance sitting" >/dev/null 2>&1
    _gv_a=$(git rev-parse HEAD)
    printf '%s\n' "record: promotion GO (approve->execute->log)" "gate: governance" \
      "scope: PR-1" "approved-by: Fixture Human [committer]" "approved-sha: $_gv_a" \
      "change-class: control-plane" "basis: docs/architecture/2026-08-15-meta-control-41.md" \
      | git notes --ref=promotions add -f -F - "$_gv_a" 2>/dev/null
    if [ "$_shv" = composition ]; then
      # A SECOND commit (one note per commit) touching the artifact, carrying a DEFECTIVE design
      # record on the SAME scope key: leg14's shape (no approved-by line).
      printf 'The sitting record, amended.\n' >> docs/architecture/2026-08-15-meta-control-41.md
      git add -A 2>/dev/null; git commit -q -m "sitting amendment" >/dev/null 2>&1
      _gv_b=$(git rev-parse HEAD)
      printf '%s\n' "record: promotion GO (approve->execute->log)" "gate: design" \
        "scope: PR-1" "change-class: control-plane" "approved-sha: $_gv_b" \
        "basis: docs/architecture/2026-08-15-meta-control-41.md" \
        | git notes --ref=promotions add -f -F - "$_gv_b" 2>/dev/null
    fi
  )
}

# _mkreplay <dir> — the DURABLE PIN for the live defect (vet MED-3). The record body below is the
# ledger's `1d9f0afa` REPLAYED BYTE-FAITHFULLY (10 lines, 536 bytes, read from the note blob
# 2f2f392c on refs/notes/promotions): a `gate: design` GO whose basis is a meta-control artifact —
# the exact workaround shape this arm retires. It must STAY defective forever, which is why the
# durable evidence is this fixture and not a one-time run against the live ledger.
# The approved-sha is the real one and does NOT resolve here, deliberately: the basis-glob leg fires
# BEFORE the sha is resolved, so the leg asserts the defect it names and the body stays unedited.
_mkreplay() {
  _dr="$1"
  mkdir -p "$_dr/docs/architecture" "$_dr/conformance" "$_dr/.claude/hooks"
  # The authority copy (as _mkfix and _mkgov carry): this leg runs with the fixture as $DIR, so the
  # CLASS derivation must resolve here too — without it the run dies at "change-class is UNDERIVABLE"
  # and the leg would assert the wrong refusal (measured on first write, exactly as leg 3 warns).
  cp "$DIR/conformance/promotion-readiness.sh" "$_dr/conformance/promotion-readiness.sh"
  if [ -f "$DIR/.claude/hooks/guard-core.sh" ]; then
    cp "$DIR/.claude/hooks/guard-core.sh" "$_dr/.claude/hooks/guard-core.sh"
  fi
  (
    cd "$_dr" || exit 1
    git init -q 2>/dev/null
    git symbolic-ref HEAD refs/heads/main 2>/dev/null || true
    git config user.email fixture@example.invalid; git config user.name Fixture
    printf 'fixture repo\n' > README.md
    git add -A 2>/dev/null; git commit -q -m fixture >/dev/null 2>&1
    printf '%s\n' \
      'record: promotion GO (approve->execute->log)' \
      'approved-sha: 1d9f0afaf756c8d51cbf118d6f97665fbaf2be5a' \
      'approved-by: Bradley James [committer]' \
      'gate: design' \
      'rung: integration' \
      'change-class: control-plane' \
      'scope: PR-517' \
      'approval-token: "GO on the panel-39 sitting record — the five D-240811-2 rulings were given by the owner in-session 2026-08-11 (three as owner-lens revisions) and the owner has approved PR 517; orchestrator-recorded per D-240805-4."' \
      'basis: docs/architecture/2026-08-11-meta-control-39.md' \
      'recorded-at: 2026-08-11T21:48:47Z' \
      | git notes --ref=promotions add -f -F - HEAD 2>/dev/null
  )
}

case "${1:-}" in
  --selftest) selftest ;;
  # --print-scope-key — the ONE sanctioned exit of prepush_scope_key to another process (design
  # docs/architecture/2026-09-02-prepush-presence-design.md §3.1). It EVALUATES NOTHING and grades
  # NOTHING: it relays this file's derivation so hooks/pre-push's board-presence leg can name the
  # branch without deriving a second key (D11's single-derivation rule — see prepush_scope_key's
  # own trap warning). The rc partition IS the contract, and bad usage gets its OWN rc:
  #   0 = `branch/<name>` on stdout · 1 = detached HEAD (nothing printed) · 2 = the branch name is
  #   outside the scope charset (nothing printed, one stderr reason) · 3 = bad usage.
  # rc 3 rather than the file's usual usage rc 2 is load-bearing: a consumer that cannot tell
  # "evaluated: unrepresentable" from "could not evaluate: you called me wrong" would silently N/A
  # a broken invocation and stop grading (the presence design's A1-1 HIGH).
  --print-scope-key) print_scope_key_mode "$@"; exit $? ;;
  # The literal '' is the fixture parameter: production NEVER supplies a listing — the class always
  # derives from the ambient tree. Only selftest()'s in-process calls pass a real path.
  *) run_ceremony_binding '' "$@" ;;
esac
