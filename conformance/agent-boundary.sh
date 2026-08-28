#!/bin/sh
# agent-boundary.sh — CI-side, harness-independent enforcement of the DEVELOPMENT-PROCESS.md §13
# agent boundary: a PR diff that touches a CONTROL-PLANE path must carry an explicit HUMAN
# ratification signal (a CODEOWNER (non-author) approval on those paths). This is the
# enforcement floor that holds on EVERY harness — incl. a harness with no inline guard — because CI
# catches an unratified control-plane edit post-hoc, before merge.
#
# Pure decision via boundary_decide(): the CI job computes the inputs (changed-file listing +
# ratified flag) from the PR event and passes them in, so this stays deterministic + --selftest-able.
# Reuses guard-core.sh::is_control_plane_path — the SINGLE SOURCE OF TRUTH for the control-plane set
# (no forked path list; this is another honored consumer of the core).
#
# THREE-STATE: 0 = boundary holds · 1 = violated (unratified control-plane change) · 2 = UNVERIFIED
#   (changed-file listing unavailable). 2 escalates to 1 under CI (CI env) or --require — a gate must
#   be runnable. See conformance/branch-protection.sh for the same contract.
#
#   usage: sh conformance/agent-boundary.sh --changed <listing-file> --ratified <0|1> [--require]
#          sh conformance/agent-boundary.sh --selftest
#          sh conformance/agent-boundary.sh --check-complete --changed <listing-file>
#
# --check-complete EXIT SPACE IS 0 or 2, NEVER 1 (A4). `1` above means "unratified control-plane
# change" — a state one human approval clears. A listing truncated at the API cap is NOT ratifiable,
# so it must never render as "awaiting a human"; it is a gate error (2).
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
CHANGED=""
RATIFIED="0"
MODE="run"
RC=""
FOR_STATE="NONE"
FOR_CLASS="control-plane"
FOR_GATE="control-plane-ratification"
# --render-exit inputs. EMPTY BY DEFAULT, never 0: an omitted input must reach the error arm rather
# than silently defaulting to the value that renders green (see render_exit's validation).
RE_RC=""
RE_APPROVALS=""
RE_READABLE=""
RE_FAILSAFE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --changed) CHANGED="${2:-}"; shift 2 ;;
    --ratified) RATIFIED="${2:-0}"; shift 2 ;;
    --require) REQUIRE=1; shift ;;
    --selftest) MODE="selftest"; shift ;;
    --state) MODE="state"; shift ;;
    # A4: change-set completeness. Takes no value — the entry count is derived from --changed, never
    # supplied, so no caller can hand in a stale or forged figure.
    --check-complete) MODE="complete"; shift ;;
    # CP-9: the rc -> check-run mapping. `--state` is already a MODE flag (it takes no value), so the
    # mapping's inputs get their own names rather than an ambiguous optional-argument overload.
    --conclusion) MODE="conclusion"; RC="${2:-}"; shift 2 ;;
    --for-state) FOR_STATE="${2:-NONE}"; shift 2 ;;
    --for-class) FOR_CLASS="${2:-control-plane}"; shift 2 ;;
    # WAITING-GATES-RENDER-AS-RED: which GATE's prose to render. DEFAULTED, deliberately — the default
    # reproduces the pre-existing ratification wording byte-for-byte, so ratification.yml and its profile
    # copy need no edit and no ratification-parity wiring token moves.
    --for-gate) FOR_GATE="${2:-control-plane-ratification}"; shift 2 ;;
    # RATIFICATION-WAITING-IS-GREEN: the rc -> (exit, arm) DECISION. Deliberately its own mode with its
    # own inputs — the workflow must not be able to reach the decision by any other spelling.
    --render-exit) MODE="render-exit"; shift ;;
    --rc) RE_RC="${2:-}"; shift 2 ;;
    --approvals-seen) RE_APPROVALS="${2:-}"; shift 2 ;;
    --reviews-readable) RE_READABLE="${2:-}"; shift 2 ;;
    --failsafe) RE_FAILSAFE="${2:-}"; shift 2 ;;
    *) echo "usage: agent-boundary.sh --changed <file> --ratified <0|1> [--require] | --selftest | --state | --conclusion <rc> [--for-state <label>] [--for-class <class>] [--for-gate <gate>] | --check-complete --changed <file> | --render-exit --rc <0|1|2> --approvals-seen <n> --reviews-readable <0|1> --failsafe <0|1>" >&2; exit 2 ;;
  esac
done

# Resolve + source the deny-matrix core (the control-plane path set lives there).
CORE="${KIT_GUARD_CORE:-$(dirname "$0")/../.claude/hooks/guard-core.sh}"
# adapters/ registry — beyond the kit-standard guard-core set, the gate also protects each harness's
# OWN declared control-plane surface: the union of controlPlanePaths across adapters/*/adapter.json
# (P1 / N5 — turns the manifest's declarative inventory into real enforcement).
ADAPTERS_DIR="${KIT_ADAPTERS_DIR:-$(dirname "$0")/../adapters}"

# ★ THE UNION AUTHORITY IS SHARED, NOT LOCAL (GUARD-PATH-ENUMERATION-INCOMPLETE S2). Both the
# derivation and the MATCHER moved to conformance/union-lib.sh, because the OTHER merge-time gate —
# promotion-readiness.sh's `--class`, which loop-state and ceremony-binding both derive through — now
# consults the same union. Two copies of a matcher IS the divergence this row exists to close: a
# re-implemented matcher there would have gated `.Cursor/rules/x` here while deriving `ordinary`
# there. Do not re-inline either function.
UNION_LIB="${KIT_UNION_LIB:-$(dirname "$0")/union-lib.sh}"
# shellcheck source=/dev/null  # resolved at runtime from $0, not statically followable
[ -f "$UNION_LIB" ] && . "$UNION_LIB"

# union_lib_ok: 0 iff the SHARED union unit is loaded and defines BOTH primitives this gate needs.
# ⚠️⚠️ THE EXTRACTION CREATED A NEW PRECONDITION AND IT MUST FAIL CLOSED — this is a REQUIRED gate.
# MEASURED, on a tree with the manifests intact and only conformance/union-lib.sh absent: `path_in_union`
# called `kit_path_in_union`, which does not exist, so the command-not-found went to the discarded
# stderr, the `if` read it as "no match", and a `GEMINI.md` diff answered rc 0 / state NONE — the gate
# announcing "no control-plane paths in the diff" for a path it is the sole enforcement of. Deleting one
# unregistered file silently disarmed the adapter half. An earlier revision of this comment claimed the
# posture was "unchanged by the extraction, byte-for-byte"; that was true of the DERIVATION and false of
# the DEPENDENCY, and the honest statement is the one below.
union_lib_ok() {
  command -v kit_union_derive >/dev/null 2>&1 && command -v kit_path_in_union >/dev/null 2>&1
}

# adapter_union: echo the union of controlPlanePaths across adapters/*/adapter.json (sorted-unique).
# jq-absent or no adapters/ -> empty union (the hardcoded guard-core floor still applies regardless).
#
# ⚠️ THIS GATE'S DEGRADED-MECHANISM POSTURE IS UNCHANGED BY THE EXTRACTION, DELIBERATELY, AND THE
# SCOPE OF THAT WORD MATTERS. kit_union_derive prints what it could parse in EVERY state and reports
# the state as its rc; this wrapper still IGNORES that rc and consumes the partial union, exactly as
# the inline copy did. So a jq-less runner still degrades this required gate to the guard-core floor
# SILENTLY, while `--class` fail-safes to control-plane — the two gates disagree again, inverted.
# That asymmetry is named in the S2 design (§3, vet M-B) and is boarded as its own row: changing a
# REQUIRED gate's fail posture is its own ruling, not a side effect of an extraction. Non-strict on
# purpose for the same reason.
# ⚠️ WHAT IS **NOT** INHERITED FROM THE INLINE COPY: a MISSING SHARED UNIT. The inline copy could not
# be missing — it was in this file. Its absence is a broken installation, not a degraded input, and it
# is refused at the call sites below rather than absorbed here.
adapter_union() {
  union_lib_ok || return 0
  kit_union_derive "$ADAPTERS_DIR" 2>/dev/null || return 0
}

# path_in_union <path> <union-list>: 0 if <path> matches a union entry — exact, a glob, or a
# directory-prefix entry ending in '/'. A THIN ALIAS onto the shared matcher (see above); the
# semantics — glob implementation, case folding of BOTH sides, the trailing-slash prefix rule — live
# in conformance/union-lib.sh and are documented there. Kept as a name because this file's selftest,
# its callers and its commentary all refer to it.
path_in_union() {
  kit_path_in_union "$@"
}

unverifiable() {  # <reason>
  if [ "$REQUIRE" = "1" ]; then
    echo "FAIL: agent-boundary could not verify ($1) and verification is required (CI/--require)."
    exit 1
  fi
  echo "UNVERIFIED: $1 — provide --changed <listing> in a PR context. (NOT a pass.)"
  exit 2
}

# boundary_decide <newline-separated-paths> <ratified 0|1>: print verdict; return 0 ok / 1 violation.
# Kept pure so the selftest can exercise it in-process (an env var must never force a pass).
boundary_decide() {
  _list=$1; _rat=$2; _union=${3:-}; _hits=""
  # Read the listing line-by-line in the CURRENT shell (heredoc, not a pipe) so _hits persists.
  # A path is control-plane if guard-core's hardcoded set knows it OR an adapter declared it (union).
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    if is_control_plane_path "$_p" || path_in_union "$_p" "$_union"; then _hits="$_hits $_p"; fi
  done <<EOF
$_list
EOF
  if [ -n "$_hits" ]; then
    if [ "$_rat" = "1" ]; then
      echo "OK: control-plane change present and ratified —$_hits"; return 0
    fi
    echo "FAIL: unratified control-plane change —$_hits"; return 1
  fi
  echo "OK: no control-plane paths in the diff"; return 0
}

# ratification_state <newline-paths> <ratified 0|1> [<union>]: the honest SoD state label for the
# human GO. PURE (no env can force it; the selftest drives it directly). A PRE-MERGE PROJECTION —
# it names the SoD reality the merge will have, it does not observe the future keystroke.
#   control-plane present + ratified=1 -> RATIFIED-BY-SECOND-REVIEWER (team; SoD genuinely exercised)
#   control-plane present + ratified=0 -> SOLO-ADMIN-OVERRIDE-LOGGED  (solo; logged admin-override)
#   no control-plane path              -> NONE (N/A — nothing to ratify)
ratification_state() {
  _list=$1; _rat=$2; _union=${3:-}; _cp=0
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    if is_control_plane_path "$_p" || path_in_union "$_p" "$_union"; then _cp=1; break; fi
  done <<EOF
$_list
EOF
  [ "$_cp" = 1 ] || { echo NONE; return 0; }
  if [ "$_rat" = 1 ]; then echo RATIFIED-BY-SECOND-REVIEWER; else echo SOLO-ADMIN-OVERRIDE-LOGGED; fi
}

# conclusion_map <rc> <state> <class>: the rc -> CHECK-RUN mapping, as parseable `key=value` lines
# (status, conclusion, title, summary — each single-line, so `IFS='=' read -r k v` reads them back).
#
# CP-9. Red must mean "something is BROKEN", never "something is WAITING" — a team that sees red for a
# gate working exactly as designed learns to ignore red. The three arms are therefore:
#   rc=0 -> completed/success      green  · nothing to ratify, or ratified
#   rc=1 -> in_progress/(none)     YELLOW · waiting on a human. A required check that is not `success`
#                                           still BLOCKS the merge, so enforcement is preserved with no
#                                           branch-protection change. Witnessed live, not assumed (#305).
#   rc=2 -> completed/failure      RED    · the gate could not evaluate the diff. Genuinely broken.
# The conclusion for rc=1 is EMPTY and must be OMITTED from the API call, not sent as "": a check-run
# carrying any conclusion is `completed`, which is precisely the red we are removing.
#
# ⚠️ `status=` AND `conclusion=` ARE INERT SINCE 2026-08-27 (REQUIRED-CHECK-POSTED-VIA-API-NOT-MATCHED).
# No caller posts a check-run any more — GitHub branch protection stopped MATCHING posted runs, so every
# required context became a real JOB whose own conclusion is the verdict. The workflows now consume ONLY
# `title=` and `summary=` from this mapping.
#
# ⚠️ AND THE COLOUR NOW DIFFERS BY GATE — do not read the sentence that used to sit here ("a WAITING
# state renders RED like any other non-green job") as still covering all of them:
#   `backlog-presence` / `ceremony-binding` — WAITING still renders RED, and this prose is the whole
#      compensation: it is the only thing telling a human that the red means "nobody has recorded the
#      GO yet" rather than "the build is broken".
#   `control-plane-ratification` — WAITING renders GREEN with a notice since 2026-08-28
#      (RATIFICATION-WAITING-IS-GREEN): the merge is blocked by branch protection's review
#      requirement, so the check explains rather than duplicates. Its rc 1 prose below says so, and
#      the (exit, arm) decision behind it is render_exit's, not this mapping's.
# The two keys are
# kept (not deleted) because they are the tested record of the colour contract and cost nothing; treat
# them as documentation, and never re-wire a poster to them without re-reading why the last one died.
#
# PURE: no env, no filesystem, no network. This is the half that can be unit-tested; whether GitHub
# honours the status it is handed is a live question, and only a live probe can answer it.
# WAITING-GATES-RENDER-AS-RED (design §9.2). THE DECLARED GATE SET — the family-completeness source.
# A hardcoded list inside the selftest would be a PRESENCE CHECK, and a presence check cannot see a
# SUBSTITUTION: a third gate added later with its own divergent colour arm would pass unnoticed. Declaring
# the set here and ITERATING it in the selftest makes both drift directions FAIL — an arm with no token,
# and a token with no arm. An unknown token returns non-zero and emits NOTHING, so the caller cannot post
# a check-run it could not characterise (ratification.yml's `[ -z "$status" ]` refusal is the precedent).
CONCLUSION_GATES="control-plane-ratification ceremony-binding"

conclusion_map() {
  _rc=$1; _cm_state=${2:-NONE}; _cm_class=${3:-control-plane}; _cm_gate=${4:-control-plane-ratification}
  _cm_known=0
  for _cm_g in $CONCLUSION_GATES; do
    if [ "$_cm_g" = "$_cm_gate" ]; then _cm_known=1; fi
  done
  if [ "$_cm_known" != 1 ]; then return 3; fi
  # ★ VALIDATE THE CLASS. This block used to be a COMMENT asserting "_cm_class is a closed token set"
  # while nothing enforced it — and dual review reproduced the consequence end to end: a class carrying
  # a NEWLINE injects its own `status=`/`conclusion=` lines into this function's key=value output, and
  # the consumer's `while IFS='=' read -r k v` loop is LAST-WINS, so an rc=1 WAITING gate renders as
  # completed/success. A forged green. Unreachable from either shipped call site (both pass a derived or
  # literal token), but conformance/ is NOT export-ignored and the usage line advertises --for-class, so
  # an adopter wiring this into their own pipeline inherits the hole. The claim is now the code.
  case "$_cm_class" in
    ordinary|sensitive|control-plane) ;;
    *) return 3 ;;
  esac
  # ── THE ONE COLOUR DERIVATION. §4.1's constraint lives HERE and nowhere else. rc -> (status,
  # conclusion) is computed ONCE, before any gate branching, so the gate dimension is STRUCTURALLY
  # incapable of changing a colour — it can only change words. A second derivation is the sixth-derivation
  # trap ceremony-binding.sh already refused once, and the selftest asserts this pair is identical for
  # every declared token.
  case "$_rc" in
    0) _status=completed;   _concl=success ;;
    1) _status=in_progress; _concl=""      ;;
    *) _status=completed;   _concl=failure ;;
  esac
  # ── PROSE ONLY, from here down. ⚠️ STATIC TEXT: no runtime value (a `basis:` path, a --scope id, a
  # branch name) may be interpolated into a title or summary. This output is parsed back by
  # `while IFS='=' read -r k v`, so one newline inside an interpolated value would inject its own
  # `status=`/`conclusion=` lines and forge the verdict. `_cm_class` is a closed token set, and is the
  # only interpolation permitted. A caller that wants the gate's own verdict text in the check-run appends
  # it at the API call site, where it never passes through this parser.
  case "$_cm_gate" in
  ceremony-binding)
  case "$_rc" in
    # ⚠️ LANE-NEUTRAL / LANE-AWARE SINCE C8. The gate has TWO arms (design, governance), and this prose
    # is what the owner actually reads at the click. Design-lane-only wording here was measured as an
    # ACTIVE HAZARD, not a cosmetic gap: the waiting text instructed `--gate design --basis
    # <design-doc-path>`, which routes a governance-record PR (a meta-control panel sitting) straight
    # back into the very workaround C8 retired — the check-run telling the operator to do the thing the
    # gate exists to stop. rc 0's old text also asserted a `--gate design` record EXISTS, which is
    # simply false on a governance-arm pass. Neutral where the arms agree, explicit where they differ.
    0)
      _title="GATE satisfied — a scoped, gate-appropriate GO record is recorded for this change"
      _summary="What changed: a ${_cm_class} change. A GO record scoped to this pull request exists in refs/notes/promotions, names an approver, and cites a substantive basis artifact appropriate to its lane: a design artifact for a '--gate design' record, or a meta-control artifact for a '--gate governance' record (on that lane the change-set is additionally judged to be a PURE governance-record change — nothing outside the governance file set). No action needed. More: docs/governance/promotion-contract.md."
      ;;
    1)
      _title="Awaiting the DESIGN GATE (or the GOVERNANCE GATE, for a governance-record change) — a human must record the GO before this change can merge"
      _summary="What changed: a ${_cm_class} change, which may not enter merge without a recorded gate approval. This gate is WAITING, not failing — it is a governance merge-gate, NOT a build failure, and no test failed. Nothing is broken: no GO record scoped to this pull request exists yet, which is the normal state of a change that has not been approved yet. It shows RED (and keeps blocking the merge) until a human acts — red here means WAITING, not broken. To proceed: CHOOSE THE LANE THAT DESCRIBES THIS CHANGE. Feature-shaped work (the usual case) takes the DESIGN lane: (1) record the GO with 'sh scripts/promotion-verify.sh record --gate design --scope PR-<n> --approved-sha <design-commit> --approved-by <human> --basis <design-doc-path>'. A PURE governance-record change — a meta-control panel sitting and its bookkeeping, which has no design of its own — takes the GOVERNANCE lane instead: record '--gate governance' with '--basis <the meta-control artifact>', per the copyable form in docs/operations/meta-control.md; that lane also requires the change-set to touch nothing outside the governance file set, so routed cures belong in their own slices. Do NOT point a design GO at a document this change merely amends — that is the retired workaround. Then, either lane: (2) publish it with 'git push origin refs/notes/promotions' — the gate reads the published ledger, so an unpublished record leaves this check red; (3) RE-RUN THIS CHECK. Steps 1 and 2 trigger no workflow on their own — recording and pushing notes does not re-run CI — so re-run the job or push a commit, or this check stays red forever while you wait for it. More: docs/governance/promotion-contract.md."
      ;;
    *)
      _title="GATE error — the recorded GO is defective, or the gate could not evaluate"
      _summary="This is NOT the waiting state. Either the gate could not evaluate this change at all, or a GO record exists and is defective — a missing, untracked, stubbed, or symlinked basis artifact; an unauthenticated approver line; a malformed approved-sha; or a change-class that would not derive. On the GOVERNANCE lane there are three further defect classes: a record carrying BOTH gate values (defective by disqualification), a basis that is not a meta-control artifact, and a change-set that escapes the governance file set or could not be derived at all (that one fails CLOSED). This IS a real error and needs fixing. The gate's own verdict names which; read it in the gate job's log, linked below. More: docs/governance/promotion-contract.md."
      ;;
  esac
  ;;
  *)
  case "$_rc" in
    0)
      if [ "$_cm_state" = RATIFIED-BY-SECOND-REVIEWER ]; then
        _title="Ratified by a second reviewer — control-plane change approved"
        _summary="What changed: a control-plane change (change-class: ${_cm_class}). State: RATIFIED-BY-SECOND-REVIEWER — a non-author reviewer approved this PR, so separation-of-duties is genuinely satisfied. No action needed. More: docs/operations/review-lane.md."
      else
        _title="No control-plane change — nothing to ratify"
        _summary="What changed: change-class ${_cm_class}; no control-plane paths in the diff. This §13 governance gate has nothing to ratify. No action needed."
      fi
      ;;
    1)
      _title="Awaiting ratification — a human must approve before this control-plane change can merge"
      _summary="What changed: a control-plane change (the kit's own guardrails / CI / standards / governance). Change-class: control-plane. Why: control-plane changes must be ratified by a human before merge. This gate is WAITING, not failing — it is a §13 governance merge-gate, NOT a build failure, and no test failed. This check is GREEN while waiting (since 2026-08-28): what blocks the merge is the branch protection review requirement, which does not clear until a human approves; on that approval this gate re-runs and confirms the ratification as RATIFIED-BY-SECOND-REVIEWER. Current SoD state: SOLO-ADMIN-OVERRIDE-LOGGED — no non-author approval is present yet, so the only merge path is a logged solo admin-override (honestly weaker than a second reviewer). To proceed: (a) get a non-author approval on this PR; or (b) solo — merge via 'gh pr merge --squash --admin --delete-branch'; GitHub logs the override as the audit trail. More: docs/operations/review-lane.md."
      ;;
    *)
      _title="Gate error — could not evaluate the control-plane diff"
      _summary="The control-plane-ratification gate could not evaluate the PR diff (change listing unavailable). This IS a real error — unlike the other states it needs fixing. See conformance/agent-boundary.sh."
      ;;
  esac
  ;;
  esac
  printf 'status=%s\n' "$_status"
  printf 'conclusion=%s\n' "$_concl"
  printf 'title=%s\n' "$_title"
  printf 'summary=%s\n' "$_summary"
}

# ── A4: change-set completeness. THE CAP IS THE SIGNAL. ──────────────────────────────────────────
# GitHub's *List pull request files* API returns a bounded number of entries and `--paginate` then
# simply STOPS — a SUCCESS, not an error — so neither `set -e` nor ratification.yml's empty-listing
# escalation (:173) sees it. The required §13 gate then classifies on a change-set missing paths it
# cannot enumerate, and posts GREEN "nothing to ratify".
#
# WHY NOT A COUNT COMPARISON. The obvious design — reconcile the emitted count against the PR event's
# `changed_files` — was built and WITHDRAWN after dual review measured two defects:
#   (1) the listing emits `filename` AND `previous_filename` while `changed_files` counts a rename
#       ONCE, so emitted = min(entries,CAP) + renames. 3000 renames + one hidden `skills/` path
#       reconciles as "complete" — blind in exactly its target case.
#   (2) `changed_files` is ABSENT from `pull_request_review` payloads, and ratification.yml fires on
#       that trigger precisely so the check re-runs when a human approves — so the comparison would
#       have reddened the gate at the moment of ratification.
# Hitting the cap is itself sufficient evidence that the listing cannot be trusted. No arithmetic, no
# payload field, no premise about how `changed_files` counts anything.
#
# ⚠️ UNVERIFIED PREMISE (EXTERNAL-PREMISE-EVIDENCE): the cap's VALUE is documented-by-GitHub, not
# measured here. Failure directions are asymmetric and worth knowing:
#   - real cap HIGHER than KIT_PR_FILES_CAP -> we fail closed early. Conservative, SAFE.
#   - real cap LOWER  than KIT_PR_FILES_CAP -> a truncated listing sits below our threshold and PASSES.
#     UNSAFE, and the only direction that matters.
# Settle it with: a scratch repo, a branch adding CAP+1 files, then
#   gh api repos/O/R/pulls/N/files --paginate -q '.[].filename' | wc -l
# and record the number here.
#
# ⚠️ A PLAIN CONSTANT, DELIBERATELY NOT AN ENV OVERRIDE. An earlier draft read
# `${KIT_PR_FILES_CAP:-3000}` and advertised it as "overridable so an adopter on a different forge can
# correct it without editing a control-plane file". That INVERTED the security argument. On a
# `pull_request` event GitHub runs the WORKFLOW from the PR, so a PR could add
# `env: KIT_PR_FILES_CAP: 999999999` to the ratification job and silently disable this tripwire — and
# unlike DELETING the call, neutering it that way passes BOTH wiring anchors, which grep only for the
# literal call string. Meanwhile this file is checked out from the BASE tree, which is precisely what a
# PR cannot reach: a constant here is strictly safer than a knob.
# An adopter on another forge edits this line — a control-plane change, ratified once, visible in a diff.
KIT_PR_FILES_CAP=3000

# changeset_at_api_cap <entry_count> -> 0 below the cap (trustworthy) · 1 at/over it · 2 unusable input.
# NOTE the empty case is deliberately 0 here, not an error: an EMPTY listing is already escalated by
# ratification.yml:173 as its own fail-safe, and duplicating it here would misattribute a failed
# checkout to the API cap.
changeset_at_api_cap() {
  _ca_n=${1:-}
  # Bound the LENGTH before any arithmetic: an all-digit value past the shell's integer range makes
  # `[` error out, and inside an &&/|| guard `set -e` is suppressed, so control would fall through to
  # a PASS — a fail-OPEN inside a fail-closed function. Measured under dash.
  case "$_ca_n" in
    ''|*[!0-9]*) return 2 ;;
    ??????????*) return 2 ;;
  esac
  # VALIDATE THE CAP TOO — it is the RIGHT operand and it comes from the environment. Guarding only the
  # left one left a measured fail-OPEN: with KIT_PR_FILES_CAP="3,000" (or `abc`, `0x10`, " ") `[` errors
  # out, the &&-list suppresses `set -e`, control falls through to `return 0`, and a 3500-entry listing
  # is announced "complete". The header below ADVERTISES this override for other forges, so the invited
  # path was the exploit path — a GitLab adopter setting "1,000" silently disabled the tripwire.
  case "$KIT_PR_FILES_CAP" in
    ''|*[!0-9]*) return 2 ;;
    ??????????*) return 2 ;;
  esac
  [ "$KIT_PR_FILES_CAP" -lt 1 ] && return 2
  [ "$_ca_n" -ge "$KIT_PR_FILES_CAP" ] && return 1
  return 0
}

# complete — the CLI face, called by the ratification workflows right after they build the listing.
# Counts entries itself so a caller cannot hand in a stale figure.
#
# EXIT SPACE IS 0 or 2 — NEVER 1. `1` in this file means "unratified control-plane change", which
# conclusion_map renders as "Awaiting ratification — a human must approve" (which the ratification job
# shows GREEN-with-a-notice while no approval exists, and RED once an approval is present that still
# does not ratify — RATIFICATION-WAITING-IS-GREEN, 2026-08-28) and whose summary
# tells the human to `gh pr merge --squash --admin`. A truncated change-set is NOT ratifiable: nobody,
# human or agent, knows what is in it. Returning 1 here would be a fail-OPEN dressed as fail-closed.
# NOTE the name: `complete` is a bash builtin and undefined in POSIX sh, so shellcheck SC3044 flags a
# function of that name in a `#!/bin/sh` script. Named `check_completeness` to stay dash-clean.
check_completeness() {
  [ -n "$CHANGED" ] || { echo "agent-boundary --check-complete: no --changed listing supplied" >&2; exit 2; }
  [ -f "$CHANGED" ] || { echo "agent-boundary --check-complete: --changed listing not found: $CHANGED" >&2; exit 2; }
  # awk NR, not `wc -l`: a listing whose final line lacks a trailing newline undercounts by one under
  # wc, which would misreport as "below cap" (or, in the old design, as a spurious truncation).
  _c_n=$(awk 'END{print NR}' < "$CHANGED")
  # Guard the call — `set -e` aborts on a non-zero simple command, so capturing $? on the NEXT
  # statement never runs and the verdict message is silently lost (measured in the withdrawn build).
  changeset_at_api_cap "$_c_n" && _c_rc=0 || _c_rc=$?
  case "$_c_rc" in
    0) echo "change-set listing complete: $_c_n entr(y|ies), below the $KIT_PR_FILES_CAP API cap."; exit 0 ;;
    1) echo "LISTING NOT VERIFIABLE: the changed-file listing emitted $_c_n line(s), at or over the $KIT_PR_FILES_CAP cap. NOTE this counts EMITTED LINES, and a rename contributes TWO (filename + previous_filename), so this fires at files+renames >= cap — meaning EITHER the forge truncated the listing at its API cap OR the change-set is genuinely that large. Both are treated the same and both fail closed: a class derived from a listing this gate cannot vouch for is untrustworthy, and an unverifiable change-set is not ratifiable — nobody can approve what cannot be enumerated. If this is a legitimate very large change-set, split it or raise KIT_PR_FILES_CAP deliberately." >&2; exit 2 ;;
    *) # Name WHICH operand is unusable. An earlier draft always blamed the entry count, so an operator
       # debugging a malformed cap would inspect the listing and find nothing wrong with it.
       if ! changeset_at_api_cap 1 >/dev/null 2>&1; then
         echo "agent-boundary --check-complete: unusable CAP '$KIT_PR_FILES_CAP' (non-numeric, zero, or absurd) — the entry count '$_c_n' is fine. This is a gate ERROR. Fail-closed." >&2
       else
         echo "agent-boundary --check-complete: unusable entry count '$_c_n' (non-numeric or absurd). This is a gate ERROR, not an absence of changes. Fail-closed." >&2
       fi
       exit 2 ;;
  esac
}

run() {
  [ -f "$CORE" ] || unverifiable "deny-matrix core not found at $CORE (set KIT_GUARD_CORE)"
  # shellcheck disable=SC1090  # core path is resolved at runtime, intentionally dynamic
  . "$CORE"
  # ★ REFUSE, NEVER DEGRADE, WHEN THE SHARED UNION UNIT IS ABSENT (see union_lib_ok). The guard-core
  # half being unavailable is already `unverifiable` above; the adapter half deserves the same
  # treatment, and without this line it got the opposite — a silent rc 0. `unverifiable` is the
  # right refusal: rc 2 locally, escalated to rc 1 under CI/--require, and the ratification workflow
  # renders rc 2 as a RED check-run, which blocks. Fail-closed by the same route every other
  # can't-evaluate state here takes.
  union_lib_ok || unverifiable "conformance/union-lib.sh missing or defines no kit_path_in_union — the adapter-declared half of the control-plane set cannot be evaluated (looked for '$UNION_LIB'; set KIT_UNION_LIB)"
  [ -n "$CHANGED" ] || unverifiable "no --changed listing supplied"
  [ -f "$CHANGED" ] || unverifiable "--changed listing not found: $CHANGED"
  _paths=$(cat "$CHANGED")
  _union=$(adapter_union)
  if boundary_decide "$_paths" "$RATIFIED" "$_union"; then exit 0; else exit 1; fi
}

# ── render_exit: THE RATIFICATION JOB'S rc -> (exit, arm) DECISION, SINGLE-SOURCED ──────────────────
# (RATIFICATION-WAITING-IS-GREEN, owner ruling 2026-08-28; review round 1, finding 3.)
# WHY HERE AND NOT IN THE YAML. The first build wrote it inline in both workflows under TEXT anchors,
# and the reviewer inverted it twice without touching one anchored literal (`_exit=1` inside the
# waiting arm; the condition widened with `|| [ 1 = 1 ]`). A policy in un-unit-testable YAML can only
# be locked by its spelling — so it lives in a `--selftest`-driven function that the workflows CALL.
# THE CONTRACT (stdout, one line): `exit=<0|1> arm=<ratified|waiting|defective|error>`
#   ratified  0 — rc 0: ratified, or no control-plane path in the diff.
#   waiting   0 — rc 1, NO approval seen, review list READABLE. The healthy state; green because
#                 branch protection's `required_approving_review_count >= 1` blocks server-side.
#   defective 1 — an approval is present that does not ratify · the review list was UNREADABLE ·
#                 the change-class FAIL-SAFED instead of being derived.
#   error     1 — rc 2, or an input this function cannot trust.
# ⚠️ `reviews_readable` IS SEPARATE FROM THE COUNT (round 1, BLOCKER). A failed reviews read leaves the
# approver list EMPTY, so the count is 0 — indistinguishable from "nobody has approved yet", the GREEN
# arm — while the forge's review requirement may ALREADY be satisfied, merging with the non-author /
# seat property never evaluated. "No one approved" and "we could not find out" cannot share an answer.
# ⚠️ `failsafe` REDS REGARDLESS OF rc AND COUNT (round 1, finding 4): a fail-safed class is gate
# DEGRADATION, not a slow human, and its colour must not depend on an unrelated human act.
render_exit() {  # <rc> <approvals_seen> <reviews_readable> <failsafe> -> prints the contract line
  _re_rc=$1; _re_ap=$2; _re_rd=$3; _re_fs=$4
  # VALIDATE FIRST, AND ROUTE A BAD INPUT TO `error`, NEVER TO A DEFAULT: a caller's `${VAR:-0}` would
  # make an UNSET count read as "no approvals" — the green arm, the same fail-open one layer down.
  case "$_re_rc" in 0|1|2) ;; *) echo "exit=1 arm=error"; return 0 ;; esac
  case "$_re_rd" in 0|1) ;; *) echo "exit=1 arm=error"; return 0 ;; esac
  case "$_re_fs" in 0|1) ;; *) echo "exit=1 arm=error"; return 0 ;; esac
  # A count is a run of digits and nothing else: '', ' ', '1x', '-1' and 'x' all reach `error`.
  case "$_re_ap" in ''|*[!0-9]*) echo "exit=1 arm=error"; return 0 ;; esac
  [ "$_re_rc" = 2 ]  && { echo "exit=1 arm=error";     return 0; }
  [ "$_re_fs" = 1 ]  && { echo "exit=1 arm=defective"; return 0; }
  [ "$_re_rc" = 0 ]  && { echo "exit=0 arm=ratified";  return 0; }
  if [ "$_re_ap" = 0 ] && [ "$_re_rd" = 1 ]; then
    echo "exit=0 arm=waiting"; return 0
  fi
  echo "exit=1 arm=defective"
}

selftest() {
  st=0
  # source the core so is_control_plane_path is available to boundary_decide in-process
  [ -f "$CORE" ] || { echo "selftest FAIL: core not found at $CORE"; return 1; }
  # shellcheck disable=SC1090
  . "$CORE"
  dc() {  # expect_rc paths ratified label [union]
    e=$1; p=$2; r=$3; lbl=$4; u=${5:-}
    ( boundary_decide "$p" "$r" "$u" ) >/dev/null && g=0 || g=$?
    if [ "$g" = "$e" ]; then echo "selftest PASS: $lbl -> rc $g"; else echo "selftest FAIL: $lbl want $e got $g"; st=1; fi
  }
  dc 0 "src/app.ts
README.md" 0 "ordinary diff, unratified -> PASS"
  dc 1 "src/app.ts
.github/workflows/ci.yml" 0 "workflow change, unratified -> FAIL"
  dc 0 "src/app.ts
.github/workflows/ci.yml" 1 "workflow change, ratified -> PASS"
  dc 1 "CODEOWNERS" 0 "CODEOWNERS change, unratified -> FAIL"
  dc 0 "" 0 "empty diff -> PASS"
  dc 1 "conformance/agent-boundary.sh" 0 "conformance change, unratified -> FAIL"
  dc 0 "conformance/agent-boundary.sh" 1 "conformance change, ratified -> PASS"
  dc 1 "DEVELOPMENT-STANDARDS.md" 0 "standards doc change, unratified -> FAIL"
  dc 1 "CLAUDE.md" 0 "CLAUDE.md change, unratified -> FAIL"
  dc 1 "adapters/generic/adapter.json" 0 "adapter manifest change, unratified -> FAIL"
  # ⚠️ FIXTURE CHANGED 2026-08-16 (GUARD-PATH-ENUMERATION-INCOMPLETE S1), and the change is disclosed
  # in that design's consequences rather than worked around. `scripts/deploy.sh` used to prove "an
  # adopter's own script is not kit machinery"; `scripts/` is a FAMILY now — protecting it per-file let
  # a real governing script (scripts/branch-protection-apply.sh) sit writable and mergeable as ordinary
  # for ten days — so every path under a `scripts/` SEGMENT is control-plane, adopter scripts included.
  # The property this row actually guards (the boundary is not "anything that looks kit-ish") is kept
  # by re-pointing it at a directory that merely ENDS in the family name: the family is SEGMENT-
  # anchored, so `myscripts/` is ordinary and this row still fails if the family ever becomes a
  # substring match. The old spelling is asserted from the other side, as a control-plane row.
  dc 0 "myscripts/deploy.sh" 0 "adopter dir merely ENDING in a family name -> PASS"
  dc 1 "scripts/deploy.sh" 0 "adopter script under a scripts/ SEGMENT is family control-plane -> FAIL"
  # ⚠️ THE SECOND MERGE-SIDE FACE OF THE HOME-INSTRUMENTATION RELIEF, PINNED HERE BECAUSE A COMMENT
  # CANNOT GO RED (GUARD-CLAUDE-HOME-INSTRUMENTATION-FP, design §4 vet M2). That relief exists to
  # unbreak the harness's OWN `~/.claude/projects|plans/` workspace, but it is by subtree NAME rather
  # than by location, so it relaxes TWO merge-side surfaces, not one: `promotion-readiness --class`
  # derives `ordinary` (pinned in promotion-readiness-wired.sh) AND this gate answers "no
  # control-plane paths" for a repo-tracked path under a relieved name — measured, and the first cut
  # of the slice pinned only the first half. Accepted (no harness reads repo-side copies of these
  # subtrees) and asserted, so a future slice that location-scopes the relief reds BOTH halves rather
  # than silently leaving one behind. The paired row below is the load-bearing negative: a
  # NON-relieved sibling inside the very same directory must still demand ratification, or this row
  # would pass just as happily against a relief widened to the whole `.claude/` family.
  dc 0 ".claude/projects/evil.md" 0 "relieved workspace subtree (accepted M2 face) -> PASS"
  dc 1 ".claude/commands/evil.md" 0 "NON-relieved sibling in the same directory -> FAIL"

  # N5 union: a path declared ONLY in an adapter manifest's controlPlanePaths (NOT in guard-core's
  # hardcoded set) is now caught — proving the gate enforces what adapters declare, per harness.
  dc 1 ".cursor/rules" 0 "adapter-union path, unratified -> FAIL" ".cursor/rules .github/workflows/"
  dc 0 ".cursor/rules" 1 "adapter-union path, ratified -> PASS" ".cursor/rules .github/workflows/"
  # A2 (case) on the UNION half. is_control_plane_path folds case, but the adapter-declared surface is
  # a separate matcher — before the fold `.Cursor/rules` classified ordinary and the union half of this
  # gate stayed evadable by one capital letter. Both directions, since manifests are author-written.
  dc 1 ".Cursor/rules" 0 "adapter-union CASE VARIANT, unratified -> FAIL" ".cursor/rules .github/workflows/"
  dc 1 ".cursor/rules" 0 "adapter-union path vs UPPERCASE manifest entry -> FAIL" ".Cursor/rules .github/workflows/"
  # GLOB-BEARING union entries. Unlocked until now: the entire glob branch could be DELETED and this
  # selftest stayed green, because every union leg above uses a glob-free entry. A behaviour whose
  # removal ships green is not a control (the kit's own non-vacuity law), and this one guards an
  # authorization predicate fed by author-controlled adapter manifests.
  dc 1 "docs/CAPABILITIES.md"   0 "glob union entry MATCHES its subtree -> FAIL" "docs/*"
  dc 0 "src/App.tsx"            0 "glob union entry does NOT match outside it -> PASS" "docs/*"
  dc 0 "README.md"              0 "glob union entry does NOT match an unrelated root file -> PASS" "docs/*"
  dc 1 "docs/deep/nested.md"    0 "glob union entry matches a NESTED path -> FAIL" "docs/*"
  # The trailing-'/' prefix rule must still work alongside globbing, with set -f in force.
  dc 1 "conformance/newfile.sh" 0 "prefix union entry matches a NEW file -> FAIL" "conformance/"

  # ── A4: CHANGE-SET COMPLETENESS — THE CAP IS THE SIGNAL.
  #    An earlier design compared the emitted line count against the PR event's `changed_files`. Dual
  #    review measured it BLIND in its own target case: the listing emits `filename` AND
  #    `previous_filename` while `changed_files` counts a rename ONCE, so `emitted = min(entries,3000) +
  #    renames` and 3000 renames + one hidden `skills/` path passes as "complete". `changed_files` is
  #    also ABSENT on `pull_request_review` payloads, so that wiring would have reddened the gate at the
  #    exact moment a human ratifies. Both withdrawn: if the listing came back AT the cap it is
  #    untrustworthy, full stop — no arithmetic, no payload dependency, no unverified premise.
  cap() {  # expect_rc entries label
    e=$1; n=$2; lbl=$3
    ( changeset_at_api_cap "$n" ) >/dev/null 2>&1 && g=0 || g=$?
    if [ "$g" = "$e" ]; then echo "selftest PASS: $lbl -> rc $g"; else echo "selftest FAIL: $lbl want $e got $g"; st=1; fi
  }
  cap 0 0    "0 entries -> below cap (the EMPTY case is ratification.yml:173's, not ours)"
  cap 0 1    "1 entry -> below cap"
  cap 0 2999 "2999 entries -> below cap, trustworthy"
  cap 1 3000 "3000 entries -> AT the API cap, untrustworthy"
  cap 1 3001 "3001 entries -> over the cap, untrustworthy"
  cap 2 ""   "entry count absent -> gate error"
  cap 2 "x"  "entry count non-numeric -> gate error"
  # Overflow: an all-digit value past the shell's integer range makes `[` error out; inside an &&/||
  # guard `set -e` is suppressed and control would fall through to a PASS (a fail-OPEN in a
  # fail-closed function). Bound the length before any arithmetic.
  cap 2 "99999999999999999999" "absurd entry count -> gate error, never a silent pass"
  # The CAP is the other operand and comes from the environment. Guarding only the entry count left a
  # measured fail-OPEN (a thousands separator made `[` error out and control fell through to a PASS on
  # a listing well over the cap). These legs make the cap's validation load-bearing.
  _cap_saved=$KIT_PR_FILES_CAP
  for _bad in "3,000" "abc" "0x10" " " "" "0" "99999999999999999999"; do
    KIT_PR_FILES_CAP=$_bad
    ( changeset_at_api_cap 3500 ) >/dev/null 2>&1 && _g=0 || _g=$?
    if [ "$_g" = 2 ]; then echo "selftest PASS: malformed cap '$_bad' -> gate error (rc 2), never a silent pass"
    else echo "selftest FAIL: malformed cap '$_bad' want rc 2 got $_g — a 3500-entry listing was judged against an unusable cap"; st=1; fi
  done
  KIT_PR_FILES_CAP=$_cap_saved
  # And a VALID override must still work — the escape hatch has to survive its own validation.
  KIT_PR_FILES_CAP=1000
  ( changeset_at_api_cap 1500 ) >/dev/null 2>&1 && _g=0 || _g=$?
  if [ "$_g" = 1 ]; then echo "selftest PASS: valid override cap=1000 -> 1500 entries is AT/over cap"
  else echo "selftest FAIL: valid override cap=1000 with 1500 entries want rc 1 got $_g"; st=1; fi
  KIT_PR_FILES_CAP=$_cap_saved

  # ── CLI-level legs for --check-complete. The in-process `cap` legs above exercise the PURE function
  #    only. The withdrawn build had NO CLI leg, and both defects it shipped — an unbound DECLARED
  #    under `set -u`, and `set -e` swallowing the verdict before $? was captured — were invisible to
  #    a fully green selftest. Assert the VERDICT TEXT as well as rc: a leg checking rc alone cannot
  #    tell its own failure from a neighbour's.
  _cbd=$(mktemp -d 2>/dev/null) || _cbd=""
  if [ -n "$_cbd" ]; then
    awk -v n="$KIT_PR_FILES_CAP" 'BEGIN{for(i=0;i<n;i++)printf "f%d.txt\n", i}' > "$_cbd/atcap.txt"
    awk -v n="$KIT_PR_FILES_CAP" 'BEGIN{for(i=0;i<n-1;i++)printf "f%d.txt\n", i}' > "$_cbd/under.txt"
    printf 'a.txt\nb.txt' > "$_cbd/nonl.txt"   # deliberately NO trailing newline
    cli() {  # expect_rc expect_text label [args...]
      e=$1; t=$2; lbl=$3; shift 3
      o=$( sh "$0" --check-complete "$@" 2>&1 ) && g=0 || g=$?
      if [ "$g" != "$e" ]; then echo "selftest FAIL: $lbl want rc $e got $g"; st=1; return; fi
      case "$o" in *"$t"*) echo "selftest PASS: $lbl -> rc $g, verdict names '$t'" ;;
        *) echo "selftest FAIL: $lbl rc $g correct but verdict lacks '$t': $o"; st=1 ;; esac
    }
    cli 0 "below the"        "CLI: under the cap -> rc 0"                --changed "$_cbd/under.txt"
    cli 2 "NOT VERIFIABLE"   "CLI: AT the cap -> rc 2 (never 1)"         --changed "$_cbd/atcap.txt"
    cli 2 "no --changed"     "CLI: --changed omitted -> rc 2"
    cli 2 "not found"        "CLI: --changed points at nothing -> rc 2"  --changed "$_cbd/nope.txt"
    # awk NR vs wc -l: `wc -l` reports 1 for this 2-entry file, which would undercount a listing
    # whose last line lacks a newline. rc 0 either way here; the leg pins the COUNTING METHOD.
    cli 0 "2 entr"           "CLI: no trailing newline counts 2, not 1"  --changed "$_cbd/nonl.txt"
    [ -n "$_cbd" ] && rm -rf "$_cbd"
  else
    echo "selftest FAIL: could not mktemp for the --check-complete CLI legs"; st=1
  fi
  dc 0 "src/app.ts" 0 "non-union ordinary path -> PASS" ".cursor/rules"
  dc 1 ".cursor/rules/foo.md" 0 "dir-prefix union entry -> FAIL" ".cursor/rules/"

  # slice 3: the honest SoD state label (pure ratification_state, driven in-process)
  rs() {  # expect label paths ratified [union]
    e=$1; p=$2; r=$3; u=${4:-}; g=$(ratification_state "$p" "$r" "$u")
    if [ "$g" = "$e" ]; then echo "selftest PASS: state $e"; else echo "selftest FAIL: state want $e got $g"; st=1; fi
  }
  rs RATIFIED-BY-SECOND-REVIEWER ".github/workflows/ci.yml" 1 ""
  rs SOLO-ADMIN-OVERRIDE-LOGGED  ".github/workflows/ci.yml" 0 ""
  rs NONE                        "src/app.ts" 0 ""
  # load-bearing negative: an always-team mutation flips the solo case above; assert distinction too
  if [ "$(ratification_state '.github/workflows/ci.yml' 0)" = "$(ratification_state '.github/workflows/ci.yml' 1)" ]; then
    echo "selftest FAIL: solo/team labels identical (vacuous)"; st=1; fi

  # CP-9: the rc -> check-run (status, conclusion) mapping. Lives HERE, not in inline CI YAML, because
  # inline YAML cannot be unit-tested — and this mapping is the whole slice: a WAITING gate must not
  # render as a BROKEN one. Driven in-process (pure), so no env can force a verdict.
  cn() {  # <label> <key> <want> <rc> [state] [class]
    _lbl=$1; _k=$2; _want=$3; _rc=$4; _st=${5:-NONE}; _cl=${6:-control-plane}
    # `|| true`: grep returns 1 on no-match, and an unmatched key must read as an EMPTY value (a real
    # FAIL below), not abort the whole selftest under set -e.
    _line=$(conclusion_map "$_rc" "$_st" "$_cl" | grep "^${_k}=" || true)
    _got=${_line#*=}
    if [ "$_got" = "$_want" ]; then echo "selftest PASS: $_lbl ($_k='$_got')"
    else echo "selftest FAIL: $_lbl want $_k='$_want' got '$_got'"; st=1; fi
  }
  cn "rc=0 ratified -> completed"      status     completed   0 RATIFIED-BY-SECOND-REVIEWER
  cn "rc=0 ratified -> success"        conclusion success     0 RATIFIED-BY-SECOND-REVIEWER
  cn "rc=0 no-cp -> success"           conclusion success     0 NONE ordinary
  # ★ THE LOAD-BEARING PAIR: waiting is YELLOW (in_progress) and carries NO conclusion. An empty
  # conclusion is not cosmetic — a check-run with a conclusion is COMPLETED, and a completed non-success
  # check is what renders red. Omitting it is what keeps the gate blocking-but-not-broken.
  cn "rc=1 waiting -> in_progress"     status     in_progress 1 SOLO-ADMIN-OVERRIDE-LOGGED
  # Asserted as an EXACT LINE, not as an empty value: `want ''` would also be satisfied by a mapping
  # that emits no conclusion key at all (it passed against an unimplemented conclusion_map — vacuous).
  # The contract is "the key is present and deliberately empty", so the test must say exactly that.
  if conclusion_map 1 SOLO-ADMIN-OVERRIDE-LOGGED control-plane | grep -qx 'conclusion='; then
    echo "selftest PASS: rc=1 waiting -> conclusion= (present, empty)"
  else echo "selftest FAIL: rc=1 must emit an empty 'conclusion=' line"; st=1; fi
  cn "rc=2 gate error -> completed"    status     completed   2 NONE
  cn "rc=2 gate error -> failure"      conclusion failure     2 NONE
  # red is RESERVED for a genuine error: only rc=2 may ever produce a failing conclusion.
  for _r in 0 1; do
    if conclusion_map "$_r" SOLO-ADMIN-OVERRIDE-LOGGED control-plane | grep -q '^conclusion=failure$'; then
      echo "selftest FAIL: rc=$_r produced conclusion=failure (red is reserved for rc=2)"; st=1
    fi
  done
  # legibility: the waiting title says WAITING, and still tells the human how to proceed.
  _w=$(conclusion_map 1 SOLO-ADMIN-OVERRIDE-LOGGED control-plane)
  # 'To proceed:' is anchored deliberately: without it the summary can keep every other token and
  # still stop TELLING THE HUMAN WHAT TO DO. A mutation that gutted the instruction framing survived
  # the other four anchors — legibility is the point of the yellow state, so it gets its own anchor.
  for _a in 'Awaiting ratification' 'NOT a build failure' 'To proceed:' 'gh pr merge' 'review-lane.md'; do
    case "$_w" in *"$_a"*) echo "selftest PASS: waiting text carries '$_a'" ;;
      *) echo "selftest FAIL: waiting text missing '$_a'"; st=1 ;; esac
  done
  # non-vacuity: the three arms must not collapse into one another.
  if [ "$(conclusion_map 1 X control-plane | grep '^status=')" = "$(conclusion_map 2 X control-plane | grep '^status=')" ]; then
    echo "selftest FAIL: rc=1 and rc=2 statuses identical (mapping vacuous)"; st=1; fi
  # the CLI surface, not just the function (the CI job calls the CLI).
  _cli=$(sh "$0" --conclusion 1 --for-state SOLO-ADMIN-OVERRIDE-LOGGED --for-class control-plane)
  case "$_cli" in *"status=in_progress"*) echo "selftest PASS: --conclusion CLI -> in_progress" ;;
    *) echo "selftest FAIL: --conclusion CLI did not emit status=in_progress"; st=1 ;; esac
  if printf '%s\n' "$_cli" | grep -q '^conclusion=.'; then
    echo "selftest FAIL: --conclusion CLI emitted a non-empty conclusion for rc=1"; st=1
  else echo "selftest PASS: --conclusion CLI rc=1 conclusion is empty"; fi
  # the class the caller passes is what the human reads back.
  case "$(conclusion_map 0 NONE sensitive)" in *'change-class sensitive'*) echo "selftest PASS: class interpolated" ;;
    *) echo "selftest FAIL: class not interpolated into the summary"; st=1 ;; esac

  # ── WAITING-GATES-RENDER-AS-RED: the gate dimension (design §9.2). ────────────────────────────────
  # ★ THE LOAD-BEARING LOCK. The gate dimension may change WORDS, never COLOUR. Iterating the declared
  # set (rather than naming two tokens here) is what makes this family-complete: a third gate added with
  # its own divergent arm is caught, which a presence check cannot do. This is the leg that fails the
  # moment someone splits the one rc->colour derivation in two.
  for _cg in $CONCLUSION_GATES; do
    _ref=$(conclusion_map 1 NONE control-plane control-plane-ratification | grep '^status=\|^conclusion=')
    _cmp=$(conclusion_map 1 NONE control-plane "$_cg" | grep '^status=\|^conclusion=')
    if [ "$_ref" = "$_cmp" ]; then echo "selftest PASS: gate '$_cg' rc=1 colour identical to the one derivation"
    else echo "selftest FAIL: gate '$_cg' rc=1 DERIVED ITS OWN COLOUR ($_cmp vs $_ref)"; st=1; fi
    for _cr in 0 2; do
      _ref=$(conclusion_map "$_cr" NONE control-plane control-plane-ratification | grep '^status=\|^conclusion=')
      _cmp=$(conclusion_map "$_cr" NONE control-plane "$_cg" | grep '^status=\|^conclusion=')
      if [ "$_ref" != "$_cmp" ]; then
        echo "selftest FAIL: gate '$_cg' rc=$_cr DERIVED ITS OWN COLOUR ($_cmp vs $_ref)"; st=1; fi
    done
  done
  # ★ THE SUBSTITUTION CATCH. A declared token with NO prose arm falls through to the ratification `*)`
  # branch and silently renders ratification wording — green, and wrong: it would tell a ceremony-binding
  # author to go get a non-author approval. Asserting the ABSENCE of ratification-specific anchors at
  # EVERY rc is what detects that, and it is why §9.2 rules all three arms rather than only the waiting
  # one: the rc re-partition makes rc=2 the MAJORITY arm for ceremony-binding.
  for _cg in $CONCLUSION_GATES; do
    [ "$_cg" = control-plane-ratification ] && continue
    for _cr in 0 1 2; do
      _txt=$(conclusion_map "$_cr" NONE control-plane "$_cg")
      for _anchor in 'Awaiting ratification' 'nothing to ratify' 'control-plane diff' 'review-lane.md'; do
        case "$_txt" in
          *"$_anchor"*) echo "selftest FAIL: gate '$_cg' rc=$_cr leaked ratification prose '$_anchor'"; st=1 ;;
        esac
      done
    done
    echo "selftest PASS: gate '$_cg' carries no ratification prose at any rc"
  done
  # legibility for the new gate: the waiting text says WAITING and names the EXACT next command. Same
  # anchor discipline as the ratification arm above — a mutation that keeps every other token while
  # gutting the instruction is the one that survived four anchors last time.
  _cb=$(conclusion_map 1 NONE control-plane ceremony-binding)
  # 'RE-RUN THIS CHECK' is anchored deliberately. Review measured that an operator following the earlier
  # wording exactly — record, then push notes — would watch this check stay yellow forever, because
  # neither action triggers a workflow. The instruction that actually clears the gate was the one missing.
  for _a in 'Awaiting the DESIGN GATE' 'NOT a build failure' 'To proceed:' 'promotion-verify.sh record' 'git push origin refs/notes/promotions' 'RE-RUN THIS CHECK' 'promotion-contract.md'; do
    case "$_cb" in *"$_a"*) echo "selftest PASS: ceremony-binding waiting text carries '$_a'" ;;
      *) echo "selftest FAIL: ceremony-binding waiting text missing '$_a'"; st=1 ;; esac
  done
  # ★ C8 — THE SECOND LANE MUST BE OFFERED, AND THE RETIRED WORKAROUND MUST BE NAMED AS RETIRED.
  # Same anchor discipline, one class further on: the earlier text was not merely incomplete, it
  # INSTRUCTED the governance-record author to do the thing the gate now refuses. An anchor per
  # element of that instruction, because a reworded summary that keeps 'design' and drops the
  # governance lane is exactly the regression this leg exists to catch.
  for _a in '--gate governance' 'meta-control artifact' 'docs/operations/meta-control.md' 'governance file set' 'retired workaround'; do
    case "$_cb" in *"$_a"*) echo "selftest PASS: ceremony-binding waiting text offers the governance lane ('$_a')" ;;
      *) echo "selftest FAIL: ceremony-binding waiting text missing '$_a' — a governance-record PR would be routed back into the retired design-basis workaround"; st=1 ;; esac
  done
  # rc=0 MUST NOT ASSERT A DESIGN RECORD. On a governance-arm pass no '--gate design' record exists,
  # so the old wording was an overclaim the owner reads as fact at the click. Asserted from BOTH
  # directions: the neutral phrasing is present, and the false assertion is absent.
  _cb0=$(conclusion_map 0 NONE control-plane ceremony-binding)
  case "$_cb0" in
    *"A '--gate design' GO record scoped to this pull request exists"*)
      echo "selftest FAIL: ceremony-binding rc=0 asserts a DESIGN record exists — false on a governance-arm pass"; st=1 ;;
    *"gate-appropriate GO record"*)
      echo "selftest PASS: ceremony-binding rc=0 states a gate-appropriate record exists (lane-neutral)" ;;
    *) echo "selftest FAIL: ceremony-binding rc=0 wording is neither the neutral form nor the old overclaim: $_cb0"; st=1 ;;
  esac
  # rc=2 must ENUMERATE the governance defect classes, or the arm's three new refusals are invisible
  # to the human reading the red.
  _cb2=$(conclusion_map 2 NONE control-plane ceremony-binding)
  for _a in 'BOTH gate values' 'not a meta-control artifact' 'escapes the governance file set'; do
    case "$_cb2" in *"$_a"*) echo "selftest PASS: ceremony-binding rc=2 names the governance defect class '$_a'" ;;
      *) echo "selftest FAIL: ceremony-binding rc=2 omits the governance defect class '$_a'"; st=1 ;; esac
  done
  # rc=2 must NOT read as the waiting state — it is the arm the re-partition fills with real defects.
  case "$(conclusion_map 2 NONE control-plane ceremony-binding)" in
    *'This is NOT the waiting state'*) echo "selftest PASS: ceremony-binding rc=2 disclaims the waiting state" ;;
    *) echo "selftest FAIL: ceremony-binding rc=2 does not distinguish itself from waiting"; st=1 ;; esac
  # an UNDECLARED token emits NOTHING and returns non-zero — never a silent ratification fall-back.
  if _bogus=$(conclusion_map 1 NONE control-plane not-a-real-gate 2>/dev/null); then
    echo "selftest FAIL: an undeclared --for-gate returned success"; st=1
  elif [ -n "$_bogus" ]; then
    echo "selftest FAIL: an undeclared --for-gate emitted output: $_bogus"; st=1
  else echo "selftest PASS: undeclared gate -> non-zero, no output"; fi
  # ★ A CLASS CARRYING A NEWLINE MUST BE REFUSED. Without the guard this forges a GREEN: the injected
  # lines are parsed by the consumer's last-wins key=value loop and override the real verdict. Asserts
  # the refusal AND that no second status= line escapes, because emitting output at all is the defect.
  _inj=$(printf 'control-plane\nstatus=completed\nconclusion=success')
  if _poison=$(conclusion_map 1 NONE "$_inj" ceremony-binding 2>/dev/null); then
    echo "selftest FAIL: a newline-bearing --for-class was ACCEPTED — it forges a completed/success verdict through the caller's key=value parser"; st=1
  elif [ -n "$_poison" ]; then
    echo "selftest FAIL: a refused --for-class still emitted output: $_poison"; st=1
  else echo "selftest PASS: newline-bearing class -> refused, no output"; fi
  # ...and the CLI surface refuses it too, since that is what an adopter's pipeline calls.
  if sh "$0" --conclusion 1 --for-gate ceremony-binding --for-class "$_inj" >/dev/null 2>&1; then
    echo "selftest FAIL: --for-class CLI accepted a newline-bearing class"; st=1
  else echo "selftest PASS: --for-class CLI rejects a newline-bearing class"; fi
  # ★ FAMILY COMPLETENESS, THE OTHER DIRECTION. The token-with-no-arm case is covered by the prose
  # leak legs above. This covers ARM-WITH-NO-TOKEN, which review measured as NOT locked: an arm added
  # as `ceremony-binding|orphan-gate)` was unreachable-but-undetected, so the claim made in this file,
  # the plan, the design and the CHANGELOG was half false. Read the arm labels out of the prose case
  # and require every one to be declared.
  _arms=$(sed -n '/^  case "\$_cm_gate" in$/,/^  esac$/p' "$0" \
          | grep -oE '^  [a-z][a-z0-9|-]*\)' | tr -d ' )' | tr '|' '\n' | grep -v '^\*$' || true)
  for _arm in $_arms; do
    case " $CONCLUSION_GATES " in
      *" $_arm "*) ;;
      *) echo "selftest FAIL: conclusion_map has a prose arm '$_arm' that is NOT in CONCLUSION_GATES — an undeclared arm is unreachable, so its wording is never rendered and never tested"; st=1 ;;
    esac
  done
  echo "selftest PASS: every conclusion_map prose arm is a declared gate ($(printf '%s' "$_arms" | tr '\n' ' '))"
  # and the CLI surface turns that into exit 2, which is what makes the caller refuse to post.
  if sh "$0" --conclusion 1 --for-gate not-a-real-gate >/dev/null 2>&1; then
    echo "selftest FAIL: --for-gate CLI accepted an undeclared gate"; st=1
  else echo "selftest PASS: --for-gate CLI rejects an undeclared gate"; fi

  # three-state CLI: no --changed is UNVERIFIED (exit 2) locally, FAIL (exit 1) under CI/--require.
  miss=$(mktemp -d)  # fixtures left in place (no rm; 7e guard)
  printf '.github/workflows/ci.yml\n' > "$miss/cp.txt"
  printf 'src/app.ts\n' > "$miss/clean.txt"
  # shellcheck disable=SC1007  # CI= intentionally clears the var for the subprocess
  CI= REQUIRE=0 sh "$0" --ratified 0 >/dev/null && r=0 || r=$?
  if [ "$r" = "2" ]; then echo "selftest PASS: no --changed local -> exit 2 (UNVERIFIED)"; else echo "selftest FAIL: no --changed local want 2 got $r"; st=1; fi
  CI=true sh "$0" --ratified 0 >/dev/null && r=0 || r=$?
  if [ "$r" = "1" ]; then echo "selftest PASS: no --changed + CI -> exit 1 (escalation)"; else echo "selftest FAIL: no --changed + CI want 1 got $r"; st=1; fi
  # end-to-end CLI over a real listing file
  sh "$0" --changed "$miss/cp.txt" --ratified 0 >/dev/null && r=0 || r=$?
  if [ "$r" = "1" ]; then echo "selftest PASS: cli unratified control-plane -> exit 1"; else echo "selftest FAIL: cli cp unratified want 1 got $r"; st=1; fi
  sh "$0" --changed "$miss/cp.txt" --ratified 1 >/dev/null && r=0 || r=$?
  if [ "$r" = "0" ]; then echo "selftest PASS: cli ratified control-plane -> exit 0"; else echo "selftest FAIL: cli cp ratified want 0 got $r"; st=1; fi
  sh "$0" --changed "$miss/clean.txt" --ratified 0 >/dev/null && r=0 || r=$?
  if [ "$r" = "0" ]; then echo "selftest PASS: cli clean diff -> exit 0"; else echo "selftest FAIL: cli clean want 0 got $r"; st=1; fi

  # N5 integration: drive the FULL run() path (real adapter_union from this repo's adapters/) over a
  # path that ONLY the union protects (AGENTS.md, declared by the generic adapter, not in guard-core).
  printf 'AGENTS.md\n' > "$miss/agents.txt"
  if command -v jq >/dev/null 2>&1 && [ -d "$ADAPTERS_DIR" ]; then
    sh "$0" --changed "$miss/agents.txt" --ratified 0 >/dev/null && r=0 || r=$?
    if [ "$r" = "1" ]; then echo "selftest PASS: cli AGENTS.md via real adapter union, unratified -> exit 1"; else echo "selftest FAIL: cli AGENTS.md union want 1 got $r"; st=1; fi
    sh "$0" --changed "$miss/agents.txt" --ratified 1 >/dev/null && r=0 || r=$?
    if [ "$r" = "0" ]; then echo "selftest PASS: cli AGENTS.md via real adapter union, ratified -> exit 0"; else echo "selftest FAIL: cli AGENTS.md union ratified want 0 got $r"; st=1; fi
  else
    echo "selftest SKIP: real adapter-union integration (jq or adapters/ absent)"
  fi

  # ── ★★★ THE SHARED-UNIT PRECONDITION MUST FAIL CLOSED (S2 fix round, review REV-C2).
  # REGRESSION LEG for a MEASURED fail-open: with conformance/union-lib.sh absent and the manifests
  # intact, `path_in_union` called an undefined `kit_path_in_union`, the command-not-found went to
  # discarded stderr, and a GEMINI.md diff answered rc 0 / state NONE — this REQUIRED gate reporting
  # "no control-plane paths in the diff" for a path it is the sole enforcement of. Driven END TO END
  # through a hermetic tree, because the defect lived in the CLI's real resolution of $0, and driven
  # in BOTH directions so the leg cannot pass by breaking the fixture instead of the mechanism.
  _ul=$(mktemp -d 2>/dev/null) || _ul=""
  if [ -n "$_ul" ]; then
    mkdir -p "$_ul/conformance" "$_ul/.claude/hooks" "$_ul/adapters/gemini"
    cp "$0" "$_ul/conformance/agent-boundary.sh"
    cp "$CORE" "$_ul/.claude/hooks/guard-core.sh" 2>/dev/null || :
    # A manifest declaring a UNION-ONLY path: guard-core does not carry GEMINI.md, so only the
    # adapter half can catch it. That is what makes this fixture able to see the hole at all.
    printf '{"controlPlanePaths":["GEMINI.md"]}\n' > "$_ul/adapters/gemini/adapter.json"
    printf 'GEMINI.md\n' > "$_ul/changed.txt"
    # (a) WITH the shared unit present the union half must CATCH it -> rc 1. This is the premise: if
    #     this half fails, the fixture proves nothing and (b) below would pass for free.
    cp "$UNION_LIB" "$_ul/conformance/union-lib.sh" 2>/dev/null || :
    # shellcheck disable=SC1007  # CI= / REQUIRE= intentionally CLEAR the vars for the subprocess (the
    # three-state contract needs them empty); same idiom, same justification, as the CLI legs above.
    ( cd "$_ul" && CI= REQUIRE=0 sh conformance/agent-boundary.sh --changed changed.txt --ratified 0 ) >/dev/null 2>&1 && _ulr=0 || _ulr=$?
    if [ "$_ulr" = 1 ]; then echo "selftest PASS: premise — with union-lib.sh present, a union-only path is caught (rc 1)"
    else echo "selftest FAIL: premise — with union-lib.sh present the union-only fixture answered rc $_ulr, not 1; the missing-lib leg below would prove nothing"; st=1; fi
    # (b) REMOVE the shared unit. The gate must REFUSE (rc 2 locally), never answer rc 0.
    rm -f "$_ul/conformance/union-lib.sh"
    # shellcheck disable=SC1007  # as above: the empty assignments are the point.
    ( cd "$_ul" && CI= REQUIRE=0 sh conformance/agent-boundary.sh --changed changed.txt --ratified 0 ) >/dev/null 2>&1 && _ulr=0 || _ulr=$?
    if [ "$_ulr" = 2 ]; then echo "selftest PASS: union-lib.sh ABSENT -> rc 2 (refused), never a silent rc 0"
    elif [ "$_ulr" = 0 ]; then echo "selftest FAIL: union-lib.sh ABSENT -> rc 0 — the gate announced 'no control-plane paths' for a union-only path; deleting one file silently disarms the adapter half"; st=1
    else echo "selftest FAIL: union-lib.sh ABSENT -> rc $_ulr, want 2 (unverifiable/refused)"; st=1; fi
    # …and the refusal must NAME the missing unit, or an operator cannot act on it.
    # shellcheck disable=SC1007  # as above: the empty assignments are the point.
    _ulo=$( cd "$_ul" && CI= REQUIRE=0 sh conformance/agent-boundary.sh --changed changed.txt --ratified 0 2>&1 || true )
    case "$_ulo" in *union-lib.sh*) echo "selftest PASS: the refusal names conformance/union-lib.sh" ;;
      *) echo "selftest FAIL: the refusal does not name the missing unit: $_ulo"; st=1 ;; esac
    # …and under CI it escalates to rc 1, like every other unverifiable state here.
    ( cd "$_ul" && CI=true sh conformance/agent-boundary.sh --changed changed.txt --ratified 0 ) >/dev/null 2>&1 && _ulr=0 || _ulr=$?
    if [ "$_ulr" = 1 ]; then echo "selftest PASS: union-lib.sh absent + CI -> rc 1 (escalated, still fail-closed)"
    else echo "selftest FAIL: union-lib.sh absent + CI want rc 1 got $_ulr"; st=1; fi
    rm -rf "$_ul"
  else
    echo "selftest FAIL: could not mktemp for the union-lib precondition legs"; st=1
  fi

  # ── render_exit: THE WHOLE STATE TABLE, DRIVEN (review round 1, finding 3). This is the lock that
  # replaced text anchors on the workflows' inline chain — both reviewer mutants kept every anchored
  # literal and inverted the behaviour. Behaviour is asserted here, in-process AND through the CLI.
  re_chk() {  # want_exit want_arm rc approvals readable failsafe label
    _e=$1; _a=$2; _r=$3; _p=$4; _d=$5; _f=$6; _l=$7
    _got=$(render_exit "$_r" "$_p" "$_d" "$_f")
    if [ "$_got" = "exit=$_e arm=$_a" ]; then
      echo "selftest PASS: render_exit — $_l -> $_got"
    else
      echo "selftest FAIL: render_exit — $_l want 'exit=$_e arm=$_a' got '$_got'"; st=1
    fi
  }
  #        exit arm        rc ap rd fs   label
  re_chk    0 ratified      0  0  1  0 "rc 0 (ratified / nothing to ratify) -> green"
  re_chk    0 ratified      0  2  1  0 "rc 0 with approvals present -> still green"
  re_chk    0 waiting       1  0  1  0 "rc 1, no approval yet, reviews readable -> GREEN (the ruling)"
  re_chk    1 defective     1  1  1  0 "rc 1 WITH an approval that does not ratify -> RED"
  re_chk    1 defective     1  9  1  0 "…any approval count >= 1 reaches the same arm"
  # ★ THE ROUND-1 BLOCKER, PINNED: an unreadable list looks like "nobody approved yet" to a count.
  re_chk    1 defective     1  0  0  0 "rc 1, count 0 but the review list was UNREADABLE -> RED, not waiting"
  re_chk    1 error         2  0  1  0 "rc 2 (gate could not evaluate) -> RED, error arm"
  re_chk    1 error         2  0  0  1 "rc 2 outranks every other input"
  # ★ A FAIL-SAFED CLASS IS GATE DEGRADATION, so it reds on its own (round 1, finding 4).
  re_chk    1 defective     1  0  1  1 "rc 1 + FAIL-SAFED class, no approvals -> RED (not waiting)"
  re_chk    1 defective     0  0  1  1 "rc 0 + FAIL-SAFED class -> RED (never a green 'nothing to ratify')"
  # ★ UNTRUSTWORTHY INPUTS REACH `error`, NEVER A DEFAULT (round 1, finding 6).
  re_chk    1 error         1 ''  1  0 "an EMPTY approvals count -> error, never 'no approvals'"
  re_chk    1 error         1 'x' 1  0 "a non-numeric approvals count -> error"
  re_chk    1 error         1 '-1' 1 0 "a negative approvals count -> error"
  re_chk    1 error         1  0 ''  0 "an EMPTY reviews-readable -> error"
  re_chk    1 error         1  0  2  0 "an out-of-range reviews-readable -> error"
  re_chk    1 error         1  0  1 '' "an EMPTY failsafe -> error"
  re_chk    1 error        '' 0  1  0 "an EMPTY rc -> error"
  re_chk    1 error        '3' 0  1  0 "an rc outside the 0/1/2 contract -> error"
  # THE CLI SURFACE, driven separately: the workflows call the FLAGS, and a mode that decides right
  # in-process while flag parsing drops a value is the skew that would matter.
  _recli=$(sh "$0" --render-exit --rc 1 --approvals-seen 0 --reviews-readable 1 --failsafe 0) && _recr=0 || _recr=$?
  if [ "$_recli" = "exit=0 arm=waiting" ] && [ "$_recr" = 0 ]; then
    echo "selftest PASS: --render-exit CLI -> 'exit=0 arm=waiting' at process exit 0"
  else
    echo "selftest FAIL: --render-exit CLI got '$_recli' at process exit $_recr"; st=1
  fi
  _recli=$(sh "$0" --render-exit --rc 1 --approvals-seen 1 --reviews-readable 1 --failsafe 0)
  case "$_recli" in
    "exit=1 arm=defective") echo "selftest PASS: --render-exit CLI reds an approval that does not ratify" ;;
    *) echo "selftest FAIL: --render-exit CLI defective leg got '$_recli'"; st=1 ;;
  esac
  # NO INPUTS AT ALL -> the error arm, never a green. It is what a broken env binding sends, and the
  # workflows' unrecognised-arm fallback calls the mode this way ON PURPOSE for its fail-closed answer.
  _recli=$(sh "$0" --render-exit)
  case "$_recli" in
    "exit=1 arm=error") echo "selftest PASS: --render-exit with NO inputs -> error arm (never green)" ;;
    *) echo "selftest FAIL: --render-exit with no inputs got '$_recli'"; st=1 ;;
  esac

  [ "$st" = "0" ] && echo "agent-boundary --selftest: OK"
  return "$st"
}

state() {  # advisory label for the CI human-surface; CI-independent, always exit 0
  [ -f "$CORE" ] || { echo NONE; exit 0; }
  # shellcheck disable=SC1090
  . "$CORE"
  # ⚠️ THIS MODE'S CONTRACT IS "A LABEL FROM A CLOSED SET, ALWAYS EXIT 0", so it cannot refuse the way
  # run() does — and a FOURTH token is exactly the closed-vocabulary brick trap this slice already
  # names at `--for-class`. So it discloses instead, and the ceiling is stated rather than hidden:
  # with the shared unit absent this label reads NONE (adapter-only paths look like nothing to
  # ratify), and what actually holds the line is run()'s refusal above — the VERDICT is that rc, never
  # this label. The workflow discards this stderr; the disclosure is for a human running it by hand.
  union_lib_ok || echo "agent-boundary --state: conformance/union-lib.sh is missing, so the ADAPTER half of the control-plane set was not evaluated and this label reflects the guard-core floor ALONE. The gate's verdict (rc) refuses in this state; do not read this label as the gate's answer." >&2
  { [ -n "$CHANGED" ] && [ -f "$CHANGED" ]; } || { echo NONE; exit 0; }
  ratification_state "$(cat "$CHANGED")" "$RATIFIED" "$(adapter_union)"
  exit 0
}

conclusion() {  # emit the check-run mapping for <rc>; no core, no filesystem — pure.
  case "$RC" in
    0|1|2) ;;
    *) echo "usage: agent-boundary.sh --conclusion <0|1|2> [--for-state <label>] [--for-class <class>] [--for-gate <gate>]" >&2; exit 2 ;;
  esac
  # An UNKNOWN --for-gate is exit 2 with nothing on stdout — never a silent fall-back to ratification
  # prose, which would tell a ceremony-binding author to go get a code review. The `if !` guard is
  # load-bearing under `set -e`: conclusion_map RETURNS non-zero (it must not `exit`, or the in-process
  # selftest and proportional-gate-wired's behavioural drive would abort mid-run), and a bare call would
  # kill the script before this diagnostic could be printed.
  if ! conclusion_map "$RC" "$FOR_STATE" "$FOR_CLASS" "$FOR_GATE"; then
    echo "agent-boundary --conclusion: unknown --for-gate '$FOR_GATE' (declared: $CONCLUSION_GATES)." >&2
    echo "  Refusing to emit a mapping we cannot characterise; the caller must then refuse to post, which" >&2
    echo "  leaves the required check ABSENT and BLOCKS the merge (fail-closed)." >&2
    exit 2
  fi
  exit 0
}

case "$MODE" in
  selftest) selftest; exit $? ;;
  state) state ;;
  conclusion) conclusion ;;
  # ALWAYS EXIT 0 — the VERDICT is on stdout, not in this process's status. A non-zero here would be
  # read by the caller's `set -e` as the gate's answer, which is the one thing this mode must not do:
  # it decides what the CALLER's exit should be, and says so in words the caller then obeys.
  render-exit) render_exit "$RE_RC" "$RE_APPROVALS" "$RE_READABLE" "$RE_FAILSAFE"; exit 0 ;;
  complete) check_completeness ;;
  *) run ;;
esac
