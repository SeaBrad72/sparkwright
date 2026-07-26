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
    *) echo "usage: agent-boundary.sh --changed <file> --ratified <0|1> [--require] | --selftest | --state | --conclusion <rc> [--for-state <label>] [--for-class <class>] | --check-complete --changed <file>" >&2; exit 2 ;;
  esac
done

# Resolve + source the deny-matrix core (the control-plane path set lives there).
CORE="${KIT_GUARD_CORE:-$(dirname "$0")/../.claude/hooks/guard-core.sh}"
# adapters/ registry — beyond the kit-standard guard-core set, the gate also protects each harness's
# OWN declared control-plane surface: the union of controlPlanePaths across adapters/*/adapter.json
# (P1 / N5 — turns the manifest's declarative inventory into real enforcement).
ADAPTERS_DIR="${KIT_ADAPTERS_DIR:-$(dirname "$0")/../adapters}"

# adapter_union: echo the union of controlPlanePaths across adapters/*/adapter.json (sorted-unique).
# jq-absent or no adapters/ -> empty union (the hardcoded guard-core floor still applies regardless).
adapter_union() {
  command -v jq >/dev/null 2>&1 || return 0
  [ -d "$ADAPTERS_DIR" ] || return 0
  for _m in "$ADAPTERS_DIR"/*/adapter.json; do
    [ -f "$_m" ] || continue
    jq -r '.controlPlanePaths[]? // empty' "$_m" 2>/dev/null
  done | sort -u
}

# path_in_union <path> <union-list>: 0 if <path> matches a union entry — exact, or a directory-prefix
# entry ending in '/'. Union entries never contain spaces, so word-splitting the list is safe.
# A2 (case). The adapter-declared surface is the OTHER half of this gate's control-plane set, and it
# was byte-literal while is_control_plane_path folded — so `.Cursor/rules` stayed ordinary and the union
# half remained evadable by one capital letter. Fold BOTH the subject and each declared entry; adapter
# manifests are author-written, so an entry may itself carry uppercase.
path_in_union() {
  _pp=$1; _u=$2
  case "$_pp" in *[A-Z]*) _pp=$(printf '%s' "$_pp" | LC_ALL=C tr 'A-Z' 'a-z') ;; esac
  # `for _e in $_u` needs WORD splitting but must NOT get PATHNAME expansion: a manifest entry such as
  # `conformance/*` would otherwise expand to the existing files, so a NEW file under that directory
  # would not match the union at all. Adapter manifests are author-controlled input to an
  # authorization predicate, so disable globbing for the loop and restore it after.
  # Save the caller's noglob state and restore it, rather than an unconditional `set +f` — the
  # established pattern in guard-core.sh. An unconditional restore silently clears a caller's `set -f`.
  _piu_g=0; case "$-" in *f*) _piu_g=1 ;; esac
  set -f
  for _e in $_u; do
    case "$_e" in *[A-Z]*) _e=$(printf '%s' "$_e" | LC_ALL=C tr 'A-Z' 'a-z') ;; esac
    # IMPLEMENT the glob rather than degrading to match-all. An earlier draft treated any entry
    # containing * ? or [ as an unsupported shape and returned MATCH, reasoning that fail-closed beats a
    # silent no-match. Measured, that made ONE glob entry in ANY adapter manifest classify EVERY path
    # control-plane — `README.md`, `package.json`, `totally/unrelated.txt` — turning the required gate
    # into an always-red check with no diagnostic naming the offending entry. Over-classification is the
    # safe direction but a blanket merge block is not a usable one.
    # `case` patterns are NOT subject to pathname expansion, so the glob works directly and `set -f`
    # (kept, for the unquoted word-split above) does not affect it. `docs/*` now matches
    # `docs/CAPABILITIES.md` and NOT `src/App.tsx` — the behaviour the fail-closed branch was standing in
    # for. Unquoted `$_e` on the pattern side is deliberate: that is what makes it a pattern.
    # shellcheck disable=SC2254  # intentional: the union entry IS the pattern
    case "$_pp" in $_e) [ "$_piu_g" = 1 ] || set +f; return 0 ;; esac
    [ "$_pp" = "$_e" ] && { [ "$_piu_g" = 1 ] || set +f; return 0; }
    case "$_e" in */) case "$_pp" in "$_e"*) [ "$_piu_g" = 1 ] || set +f; return 0 ;; esac ;; esac
  done
  [ "$_piu_g" = 1 ] || set +f
  return 1
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
# PURE: no env, no filesystem, no network. This is the half that can be unit-tested; whether GitHub
# honours the status it is handed is a live question, and only a live probe can answer it.
conclusion_map() {
  _rc=$1; _cm_state=${2:-NONE}; _cm_class=${3:-control-plane}
  case "$_rc" in
    0)
      _status=completed; _concl=success
      if [ "$_cm_state" = RATIFIED-BY-SECOND-REVIEWER ]; then
        _title="Ratified by a second reviewer — control-plane change approved"
        _summary="What changed: a control-plane change (change-class: ${_cm_class}). State: RATIFIED-BY-SECOND-REVIEWER — a non-author reviewer approved this PR, so separation-of-duties is genuinely satisfied. No action needed. More: docs/operations/review-lane.md."
      else
        _title="No control-plane change — nothing to ratify"
        _summary="What changed: change-class ${_cm_class}; no control-plane paths in the diff. This §13 governance gate has nothing to ratify. No action needed."
      fi
      ;;
    1)
      _status=in_progress; _concl=""
      _title="Awaiting ratification — a human must approve before this control-plane change can merge"
      _summary="What changed: a control-plane change (the kit's own guardrails / CI / standards / governance). Change-class: control-plane. Why: control-plane changes must be ratified by a human before merge. This gate is WAITING, not failing — it is a §13 governance merge-gate, NOT a build failure, and no test failed. It will stay yellow (and keep blocking the merge) until a human acts. Current SoD state: SOLO-ADMIN-OVERRIDE-LOGGED — no non-author approval is present yet, so the only merge path is a logged solo admin-override (honestly weaker than a second reviewer). To proceed: (a) get a non-author approval on this PR — this check re-runs on the approval and turns green as RATIFIED-BY-SECOND-REVIEWER; or (b) solo — merge via 'gh pr merge --squash --admin --delete-branch'; GitHub logs the override as the audit trail. More: docs/operations/review-lane.md."
      ;;
    *)
      _status=completed; _concl=failure
      _title="Gate error — could not evaluate the control-plane diff"
      _summary="The control-plane-ratification gate could not evaluate the PR diff (change listing unavailable). This IS a real error — unlike the other states it needs fixing. See conformance/agent-boundary.sh."
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
# conclusion_map renders as YELLOW "Awaiting ratification — a human must approve" and whose summary
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
  [ -n "$CHANGED" ] || unverifiable "no --changed listing supplied"
  [ -f "$CHANGED" ] || unverifiable "--changed listing not found: $CHANGED"
  _paths=$(cat "$CHANGED")
  _union=$(adapter_union)
  if boundary_decide "$_paths" "$RATIFIED" "$_union"; then exit 0; else exit 1; fi
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
  dc 0 "scripts/deploy.sh" 0 "adopter own script (not kit) -> PASS"

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

  [ "$st" = "0" ] && echo "agent-boundary --selftest: OK"
  return "$st"
}

state() {  # advisory label for the CI human-surface; CI-independent, always exit 0
  [ -f "$CORE" ] || { echo NONE; exit 0; }
  # shellcheck disable=SC1090
  . "$CORE"
  { [ -n "$CHANGED" ] && [ -f "$CHANGED" ]; } || { echo NONE; exit 0; }
  ratification_state "$(cat "$CHANGED")" "$RATIFIED" "$(adapter_union)"
  exit 0
}

conclusion() {  # emit the check-run mapping for <rc>; no core, no filesystem — pure. Always exit 0.
  case "$RC" in
    0|1|2) ;;
    *) echo "usage: agent-boundary.sh --conclusion <0|1|2> [--for-state <label>] [--for-class <class>]" >&2; exit 2 ;;
  esac
  conclusion_map "$RC" "$FOR_STATE" "$FOR_CLASS"
  exit 0
}

case "$MODE" in
  selftest) selftest; exit $? ;;
  state) state ;;
  conclusion) conclusion ;;
  complete) check_completeness ;;
  *) run ;;
esac
