#!/bin/sh
# ci-gates.sh — conformance check for DEVELOPMENT-STANDARDS.md §14 (CI/CD Pipeline).
# Asserts a CI workflow declares all required quality gates by their standardized
# step ids. Checks contract identifiers, not stack tools, so it is stack-neutral:
# any workflow that adopts these ids can be verified, in any language.
#
# Usage: sh conformance/ci-gates.sh <workflow-file> [--expect-seams]
#        sh conformance/ci-gates.sh --own-tree [<root>]     (B7: judge THIS tree's OWN pipeline(s))
#        sh conformance/ci-gates.sh --line-breaks [<root>]  (SWAS-447: the read-only line-break ban over the kit's judged files)
#        sh conformance/ci-gates.sh --selftest
# Exit:  0 = all gates present and every kit-owned invocation resolves · 1 = missing gate(s),
#        a kit-owned invocation whose subcommand does not resolve, or bad usage.
#        --own-tree: 0 = judged green / disclosed N/A (raw export, adopter-owned, or LOUD all-na)
#        · 1 = a missing required id on an emitted/kit pipeline, an invalid disposition file, or
#        a marked tree with no pipeline at all. See the OWN-TREE block below.
#
# Matching is best-effort and structural; a gate counts when it appears either as a
# GitHub Actions step id — `id: <gate>` — OR as a GitLab CI job key — `<gate>:` at
# column 0 — at the start of a line (NOT inside a comment or a quoted value). The
# contract is the gate-ids; the CI platform is open (GitHub Actions, GitLab CI, or any
# platform that adopts the ids — see docs/operations/ci-platforms.md). This prevents a
# workflow passing by merely *mentioning* a gate id (e.g. `# id: gate-lint`).
# It does not parse YAML, so a gate id inside a multi-line block scalar, or a non-gate
# job coincidentally named `gate-X`, could still be a false positive. For stronger
# guarantees use a YAML parser (e.g. `yq -r '.jobs[].steps[].id'`). This shell check is a
# portable, zero-dependency gate and should be paired with the pipeline actually running.
set -eu

# --- emitted-CI seam ---------------------------------------------------------------
# K9 (CP-7 run 4): profiles/typescript-node/ci.yml called `sh scripts/otel-trace.sh --emit`,
# a subcommand the script's dispatch does not have -> exit 2 on every adopter's FIRST CI run,
# failing AC4 and AC5. Nothing executed the emitted run-blocks, so a grep-level lock never saw it.
# Comments are stripped first: a token appearing only in a comment must not satisfy the lock.
#
# MEASURED CEILING — what this seam check does NOT see. Stated in the artifact, not only in the
# design doc, because a reader of a green run is entitled to know the shape of that green:
#   - EXTRACTION: only `sh|bash <unquoted scripts/... OR conformance/... path> <token>` forms are seen.
#     CP7R5-NINE-PROFILES added the conformance/ prefix, so the `sh conformance/verify.sh --require` seam
#     shared by every emitted pipeline is now judged. `./scripts/x.sh sub` and `sh "scripts/x.sh" sub`
#     remain invisible to it.
#   - ROOT: resolution is against the KIT root (`$(dirname "$0")/..`), NOT the tree the emitted
#     workflow will actually run in. It proves the kit is self-consistent, not that an adopter's
#     checkout is.
#   - SILENT PASSES (fail-open by design — a blocking gate must not reject legal shell): script
#     absent from this tree; target not `$1`-dispatch style; token not a verb (see the filter).
#   - COMMENT STRIP: `sed 's/#.*//'` truncates at ANY `#`, including one inside a quoted YAML
#     scalar. Verified: `run: base=${p##*/}; sh scripts/otel-trace.sh --bogus` reduces to
#     `run: base=${p` and the invocation vanishes unjudged. Fail-open; accepted under the
#     zero-dependency (no YAML parser) constraint, but it is a real hole, not a rounding error.
#   - FIRST TOKEN ONLY: a wrong FLAG passed to a right subcommand is invisible — `span --traec`
#     resolves exactly as well as `span --trace`.
#   - NOT A PARSER: the predicate knows three line-anchored dispatch shapes — a `case` arm, an
#     `if/elif [ "$1" = sub ]` test, and (CP7R5-NINE-PROFILES) a BARE `[ "$1" = sub ]` equality, the form
#     verify.sh uses for --require. The dispatch-style guard that decides whether a script is judged at
#     all recognizes the same three shapes; what happens to any OTHER shape:
#       * NONE of the three present (a pure table, an `eval` dispatch, `getopts` — which dispatches on
#         `case "$opt"`, never on `$1`): the guard skips the script entirely -> SILENT PASS. These
#         belong to the fail-OPEN bullet above, not here.
#       * A recognized dispatch shape present but the real verb dispatch built another way — e.g. an
#         unrelated inner option loop, as scripts/adopter-export.sh:385 has: the script IS judged, the
#         verb is not found -> UNRESOLVED.
#     That second, narrow band is the only one that fails CLOSED, and it is the one to widen first
#     if a false FAIL appears. Do not read this bullet as a general fail-closed guarantee.
#   - BARE-`[` PRECISION LOSS (CP7R5-NINE-PROFILES, named by security review): the bare `[ "$1" = sub ]`
#     shape is indistinguishable from a stray guard/hint (`[ "$1" = X ] && echo ...`) or a negation
#     (`[ "$1" != X ]` — `[^]]*=` matches `!=`). Such a line RESOLVES its token even when the token is NOT
#     a working verb, so a genuine K9 (`case … *) exit 2`) coincidentally mentioned in a bare `[` line
#     false-PASSes — a real fail-OPEN band, a sliver of the CP-7 I1 class reopened. Accepted, NOT a
#     rounding error: verify.sh's real --require dispatch IS exactly `[ "${1:-}" = "--require" ] && …`, so
#     a tighter predicate would false-FAIL it — the two are structurally identical. No live fleet seam is
#     masked (every real seam is genuinely handled). If a false PASS appears, tighten the case-arm anchor.
check_kit_seams() {  # <workflow-file> <script-root> [expect-seams:0|1] -> 0 ok, 1 unresolved
  _wf=$1; _root=$2; _expect=${3:-0}
  # No temp file: the judging loop is the LAST stage of the pipeline and its stdout is captured, so
  # the verdict crosses the subshell boundary with nothing on disk to leak on SIGINT.
  # A workflow with no kit-owned invocations is vacuously OK (most profiles are pure toolchain).
  # Each surviving token emits a `J` line (JUDGED) so the caller can tell "nothing to judge" from
  # "judged and clean" -- see the --expect-seams guard below. One extraction, two facts; deriving the
  # count from a second copy of this regex would recreate the two-sources-of-truth bug that took
  # adopter-export-wired red.
  _res=$(sed 's/#.*//' "$_wf" 2>/dev/null \
    | grep -oE '(sh|bash)[[:space:]]+(scripts|conformance)/[a-zA-Z0-9_.-]+\.sh[[:space:]]+[-a-zA-Z0-9_./]+' \
    | sed -E 's/^(sh|bash)[[:space:]]+//' | sort -u \
    | while read -r _script _sub; do
        # Not every token after a script path is a dispatch subcommand. Reject: empty; `--`
        # (end-of-options); a bare file descriptor from a redirection (`2>/dev/null` yields `2`);
        # and any token carrying a character outside [-a-zA-Z0-9_] -- a path or filename such as
        # `gp_spans.ndjson`, a glob, or a shell expansion. The extraction class above deliberately
        # admits `.` and `/` so the WHOLE token is seen here: truncating `gp_spans.ndjson` to
        # `gp_spans` would hand this filter a word that looks like a verb. Surviving tokens are
        # therefore drawn from [-a-zA-Z0-9_]+, which holds no ERE metacharacter -- that enforced
        # invariant is why the predicate below can interpolate $_sub unescaped.
        # `(`-led patterns are REQUIRED here, not style: bash 3.2 (the system shell on macOS)
        # cannot parse a bare `pat)` case arm inside a $( ) substitution -- it reads the arm's `)`
        # as the closing paren and dies on `;;`. dash accepts both forms; bash 3.2 only this one.
        case "$_sub" in
          (''|--|*[!-a-zA-Z0-9_]*) continue ;;
          (*[!0-9]*) : ;;                    # has a non-digit -> a real word, judge it
          (*) continue ;;                    # all digits -> a redirection fd, not a subcommand
        esac
        [ -f "$_root/$_script" ] || continue  # pruned/absent in this tree -> not our seam to judge
        # Only a verb-dispatch script HAS subcommands to resolve against; one that takes a positional
        # argument (no `case "$1"`, no `if [ "$1"`, no bare `[ "$1"` equality) must never be judged --
        # rejecting its legal invocation would be a false positive on a blocking gate. Three dispatch
        # shapes are recognized: a `case "$1"` line, an `if/elif [ "$1"` test, and a bare `[ "$1"`
        # equality (the form verify.sh uses for --require, added by CP7R5-NINE-PROFILES).
        grep -qE 'case[[:space:]]+"?\$\{?1|(el)?if[[:space:]]+\[[[:space:]]+"?\$\{?1|^[[:space:]]*\[[[:space:]]+"?\$\{?1' "$_root/$_script" || continue
        # Resolve against the DISPATCH, not against the file. Three dispatch shapes are honoured, and
        # ALL must OPEN a line, so a mention of the verb in a usage string, a comment, or any other
        # prose can never satisfy the lock. A whole-file grep cannot tell "resolves against the
        # dispatch" from "appears somewhere" -- exactly how one `printf` help line in
        # scripts/otel-trace.sh silently vouched for two verbs it does not implement (CP-7 I1).
        #   _armRE: a `case` arm -- optionally `(`-led, optionally preceded by other alternates in
        #           an `a|b|sub)` chain.
        #   _ifRE:  an `if [ "$1" = sub ]` / `elif` equality dispatch -- measured on the real tree in
        #           scripts/explain.sh and scripts/adopter-export.sh, whose live CI invocations a
        #           case-arm-only predicate would falsely FAIL. CP7R5-NINE-PROFILES made the `(el)?if`
        #           keyword OPTIONAL so a BARE `[ "$1" = sub ]` also resolves -- the form verify.sh uses
        #           for --require. NOT unconditionally sound: a bare (or negated) `[ "$1" = sub ]` line
        #           resolves sub even when it is a stray guard/hint, not the real dispatch -- see the
        #           "BARE-`[` PRECISION LOSS" bullet in the ceiling header. Accepted because verify.sh's
        #           genuine --require dispatch is this exact shape and cannot be told apart.
        # Neither regex carries a top-level `|`, so alternating them in one pass is safe.
        _armRE="^[[:space:]]*\(?(\"?[-a-zA-Z0-9_*]+\"?[[:space:]]*\|[[:space:]]*)*\"?${_sub}\"?[[:space:]]*[)|]"
        # `[$]`, not `\$`: this is a DOUBLE-quoted string, where the shell collapses `\$` to a bare
        # `$` and ERE then reads it as the end-of-line anchor -- the regex silently never matches.
        _ifRE="^[[:space:]]*((el)?if[[:space:]]+)?\[[[:space:]]+\"?[$]\{?1[^]]*=[[:space:]]*\"?${_sub}\"?[[:space:]]*\]"
        printf 'J\n'                        # this token survived every filter: it WAS judged
        if ! sed 's/#.*//' "$_root/$_script" | grep -qE "$_armRE|$_ifRE"; then
          printf 'F %s %s\n' "$_script" "$_sub"
        fi
      done)
  _judged=$(printf '%s\n' "$_res" | grep -c '^J$' || true)
  _bad=$(printf '%s\n' "$_res" | sed -n 's/^F /\
  /p')
  # --expect-seams: for a workflow KNOWN to carry kit-owned invocations, an empty match set is a
  # FAILURE TO EXTRACT, not a pass. Without this, any change the ceiling already names as invisible
  # (`./scripts/x.sh`, `sh "scripts/x.sh"`, an earlier `#` on the same run-line) silently drops the
  # match set to zero and this check stays green having judged nothing -- the same "proxy trusted in
  # place of the thing" failure the seam lock exists to close, one level up. Off by default so
  # genuinely seam-free profiles stay stack-neutrally green.
  if [ "$_expect" = "1" ] && [ "${_judged:-0}" -eq 0 ]; then
    echo "FAIL: $_wf --expect-seams: ZERO kit-owned invocations were extracted." >&2
    echo "This workflow is declared to carry them, so an empty match set means the extractor judged" >&2
    echo "NOTHING -- it does not mean the seams are sound. See the EXTRACTION ceiling in this file." >&2
    return 1
  fi
  [ -z "$_bad" ] && return 0
  echo "FAIL: $_wf invokes kit-owned command(s) whose subcommand does not resolve:$_bad" >&2
  echo "The emitted CI must only call interfaces the shipped script actually provides (CP-7 K9)." >&2
  return 1
}

# ══ B7 — THE OWN-TREE LEG (`--own-tree [<root>]`) — D-240805-2's reserved clause, executed. ═════════
# Judges THE TREE'S OWN installed pipeline(s) against the 8 gate ids, minus the tree's VALIDATED
# `na` dispositions (conformance/gate-dispositions.txt; ABSENT = all 8 required — the adopter
# default). This is the non-kitself leg: the row adopters run on their own tree, where deleting
# `gate-sbom` from an installed (emitted) pipeline goes RED — the spine AC, live.
#
# DISCOVERY PROVENANCE — copied from conformance/verify-enforced-wired.sh, NOT shelled out to
# (different contract: that script judges `verify.sh --require` WIRING, this judges GATE IDS):
#   * GH_WF/GL_WF file-presence selection            — verify-enforced-wired.sh:63-64
#   * judge EVERY pipeline present + zero-found      — verify-enforced-wired.sh:836-851
#   * three-state disposition + tree markers         — verify-enforced-wired.sh:235-285
#     (_wf_disposition / _must_have_workflow / _kit_source, incl. the provenance axis: an
#     ADOPTER-origin pipeline missing ids is a DISCLOSED N/A-with-remedy, never FAIL — the kit's
#     own brownfield docs instruct adopters to merge the gate ids by hand, so failing them for
#     not having done it yet is failing them for a state the kit's documentation created).
#
# HONEST CEILINGS (§8 of the B7 design, stated where they live):
#   * ID PRESENCE IS DECLARATION, NOT EXECUTION — a `gate-sbom` id on a no-op step satisfies this
#     leg (Leg A's ceiling, inherited). The contract is "the gate exists and is named"; gate
#     QUALITY is each tool's own concern. Pair with the pipeline actually running.
#   * The disposition file is a DECIDED EXEMPTION surface — it makes an exemption recorded and
#     ratified instead of silent-structural; it cannot make an `na` reason true. Adopter-authored
#     files are bounded by their own forge review, nothing else.
#   * REMOVING the emitted-origin marker downgrades a missing-id FAIL to the ADOPTER-OWNED
#     disclosed N/A — a self-assertion of ownership (verify-enforced-wired's own stated ceiling,
#     inherited with the copied axis).
#   * `check_kit_seams` (Leg B) does NOT run in --own-tree mode: its resolution root is the KIT
#     tree by design (see the dispatch at the foot; ceiling bullets above). Own-tree seam-checking
#     would be a NEW contract and is out of scope here — stated, not implied.

# ONE id list for both modes (Leg A's REQUIRED= below the marker aliases this; a second literal
# copy would be a drift pair nothing locks).
OWN_GATE_IDS="gate-lint gate-type-check gate-test gate-build gate-secret-scan gate-dep-scan gate-sbom gate-provenance"
OWN_DISP_FILE="conformance/gate-dispositions.txt"
OWN_ORIGIN_MARKER='# kit-pipeline-origin: emitted'

# read_dispositions <file> — validate the disposition artifact; print its `na` ids (one line,
# space-led words) on stdout. RULES (each violation FAILS LOUD naming the line — the
# hermetic-exclusions bypass-surface pattern: an invalid file never widens or narrows the
# required set silently): every one of the 8 ids exactly once · kind is apply|na · `na` REQUIRES
# a non-empty reason — whitespace-only counts as empty (`apply` reasons optional) · `#` comments
# and blank lines ignored.
# rc 0 valid · 1 invalid (violations on stderr).
read_dispositions() {
  _rd_f=$1
  _rd_tab=$(printf '\t')
  _rd_seen=" "; _rd_bad=0; _rd_ln=0; _rd_na=""
  while IFS= read -r _rd_line || [ -n "$_rd_line" ]; do
    _rd_ln=$((_rd_ln + 1))
    case "$_rd_line" in ''|'#'*) continue ;; esac
    _rd_id=${_rd_line%%"$_rd_tab"*}
    _rd_rest=${_rd_line#*"$_rd_tab"}
    if [ "$_rd_rest" = "$_rd_line" ]; then
      echo "FAIL: $_rd_f line $_rd_ln is malformed — expected gate-<id><TAB>apply|na<TAB><reason>: $_rd_line" >&2
      _rd_bad=1; continue
    fi
    _rd_kind=${_rd_rest%%"$_rd_tab"*}
    _rd_reason=""
    if [ "$_rd_rest" != "$_rd_kind" ]; then _rd_reason=${_rd_rest#*"$_rd_tab"}; fi
    case " $OWN_GATE_IDS " in
      (*" $_rd_id "*) : ;;
      (*) echo "FAIL: $_rd_f line $_rd_ln names an unknown gate id '$_rd_id' (the 8: $OWN_GATE_IDS)" >&2
          _rd_bad=1; continue ;;
    esac
    case "$_rd_seen" in
      (*" $_rd_id "*)
        echo "FAIL: $_rd_f line $_rd_ln — $_rd_id appears more than once (every id exactly once)" >&2
        _rd_bad=1; continue ;;
    esac
    _rd_seen="$_rd_seen$_rd_id "
    case "$_rd_kind" in
      (apply) : ;;
      (na)
        # TRIM before the emptiness test [B7 polish, reviewer LOW-3]: `na<TAB>   ` (a reason
        # that is only spaces/tabs) is as reasonless as an absent one — without the trim it
        # slips the widening lock the message below names.
        case "$_rd_reason" in
          (*[![:space:]]*) _rd_na="$_rd_na $_rd_id" ;;
          (*)
            echo "FAIL: $_rd_f line $_rd_ln — 'na' REQUIRES a non-empty reason (whitespace-only counts as empty; a reasonless exemption is a silent widening): $_rd_line" >&2
            _rd_bad=1; continue ;;
        esac ;;
      (*) echo "FAIL: $_rd_f line $_rd_ln — disposition must be 'apply' or 'na', got '$_rd_kind'" >&2
          _rd_bad=1; continue ;;
    esac
  done < "$_rd_f"
  for _rd_g in $OWN_GATE_IDS; do
    case "$_rd_seen" in
      (*" $_rd_g "*) : ;;
      (*) echo "FAIL: $_rd_f is missing an entry for $_rd_g — every one of the 8 ids must appear exactly once (an absent line is an UNDECIDED gate, not an exemption)" >&2
          _rd_bad=1 ;;
    esac
  done
  [ "$_rd_bad" -eq 0 ] || return 1
  printf '%s\n' "$_rd_na"
  return 0
}

# ══ B8 — `--disposition <gate-id> <file>` — the SINGLE-SOURCED query mode ═══════════════════════
# (GATE-PROVENANCE-SELF-DISABLES-AND-NEVER-GATES-THE-MERGE, PHASE-B-SPINE.) release-tag.sh's
# provenance_gate consults this rather than minting a third disposition parser — the
# BRANCH-SCOPE-END-TO-END row documents exactly how parity copies rot; this reuses
# read_dispositions() verbatim (no second parser). See
# docs/architecture/2026-08-08-b8-provenance-honesty-design.md §4.1.
#
# disposition_query <gate-id> <file> -> prints EXACTLY one of: apply | na | absent.
#   absent = the file does not exist at all (the adopter default — ABSENT = all 8 required, apply).
#   apply  = the file is valid and the gate id is dispositioned apply (or has no na line for it).
#   na     = the file is valid and the gate id is validated na.
# An UNREADABLE or INVALID file (fails read_dispositions' own violations) is NEVER silently
# treated as `na` — it fails safe TOWARD LOUD, printing `apply` with a stderr warning (the design's
# explicit fail-safe direction: an undecided/broken disposition must never quietly exempt a gate).
# rc is always 0 — the query itself never fails; an unreadable/invalid input is a printed VALUE
# (apply, with a warning), never a missing verdict a caller must additionally special-case.
disposition_query() {
  _dqg=$1; _dqf=$2
  if [ ! -f "$_dqf" ]; then
    echo absent
    return 0
  fi
  if ! _dqna=$(read_dispositions "$_dqf"); then
    echo "WARN: $_dqf is an invalid or unreadable disposition file — fail-safe: apply (see the FAIL line(s) above for the violation)" >&2
    echo apply
    return 0
  fi
  case " $_dqna " in
    (*" $_dqg "*) echo na ;;
    (*) echo apply ;;
  esac
  return 0
}

# own_gate_declared <workflow-file> <gate> -> 0 declared. MATCH SEMANTICS = Leg A's, verbatim:
# a GitHub `id: gate-X` step OR a GitLab `gate-X:` job key, line-anchored, never a comment.
own_gate_declared() {
  _od_gh="^[[:space:]]*(-[[:space:]]+)?id:[[:space:]]*[\"']?${2}[\"']?[[:space:]]*(#.*)?\$"
  _od_gl="^${2}:[[:space:]]*(#.*)?\$"
  grep -Eq "$_od_gh" "$1" || grep -Eq "$_od_gl" "$1"
}

_own_remedies() {
  echo "    Remedies — choose ONE, deliberately:"
  echo "      1. RESTORE the id in the pipeline (platform shapes: docs/operations/ci-platforms.md), or"
  echo "      2. DECLARE the gate na-with-reason in conformance/gate-dispositions.txt — a decided,"
  echo "         reviewed exemption (control-plane; your forge review is its ratification surface;"
  echo "         see that file's header)."
}

# _own_origin <wf> <kit-source:0|1> -> emitted|kitsource|adopter (the provenance axis, copied).
_own_origin() {
  if grep -qF "$OWN_ORIGIN_MARKER" "$1" 2>/dev/null; then echo emitted
  elif [ "$2" = 1 ]; then echo kitsource
  else echo adopter; fi
}

# _own_judge <wf> <origin> — reads $OWN_REQ (required set) / $OWN_NA_PRETTY (na set).
_own_judge() {
  _oj_wf=$1; _oj_or=$2
  _oj_missing=""
  for _oj_g in $OWN_REQ; do
    own_gate_declared "$_oj_wf" "$_oj_g" || _oj_missing="$_oj_missing $_oj_g"
  done
  if [ -z "$_oj_missing" ]; then
    if [ -z "$OWN_REQ" ]; then
      # THE LOUD ZERO (self-review finding 5): an all-na disposition is NEVER a bare green.
      echo "OK: $_oj_wf — all 8 gates dispositioned na — this pipeline is judged against NOTHING."
      echo "    na set:$OWN_NA_PRETTY"
      echo "    A green here proves ONLY that a recorded, reviewed all-na disposition exists"
      echo "    ($OWN_DISP_FILE); no gate id was checked."
    else
      echo "OK: $_oj_wf declares its required CI gates ($OWN_REQ)"
      if [ -n "$OWN_NA_PRETTY" ]; then
        echo "    (na by disposition:$OWN_NA_PRETTY — decided exemptions, not enforcement)"
      fi
    fi
    return 0
  fi
  case "$_oj_or" in
    (adopter)
      # Provenance separates DRIFT from an UNMET DOCUMENTED MERGE OBLIGATION (the copied axis).
      echo "N/A (ADOPTER-OWNED): $_oj_wf carries no kit-pipeline-origin marker and is missing:$_oj_missing"
      echo "    A foreign/brownfield pipeline is not FAILED for the state the kit's own adoption docs"
      echo "    created (merge the gate ids by hand — docs/adoption/brownfield.md). Disclosed, not silent:"
      _own_remedies
      return 0 ;;
    (*)
      echo "FAIL: $_oj_wf is missing required CI gate(s):$_oj_missing"
      if [ "$_oj_or" = kitsource ]; then
        echo "    (the KIT'S OWN tree — self-enforcement drift on the D-240805-2 apply set)"
      fi
      _own_remedies
      return 1 ;;
  esac
}

# check_pr_concurrency <workflow-file> (SWAS-274): the kit's PR-cancel lock. Exactly one concurrency: key,
# at column 0 (a job-level one lets a new job escape it), whose group and cancel-in-progress lines equal
# the design's strings byte for byte. A github.ref group, a missing github.workflow prefix, or a cancel
# that is not synchronize-only would cancel or drop a main run, or red the head on a reopen.
PRC_GROUP='${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}'
PRC_CANCEL="\${{ github.event_name == 'pull_request' && github.event.action == 'synchronize' }}"
check_pr_concurrency() {  # <workflow-file> -> 0 ok; 1 block absent, duplicated, job-level, or its group/cancel line drifted
  _pc_src=$(sed 's/#.*//' "$1")
  _pc_n=$(printf '%s\n' "$_pc_src" | grep -cE '^[[:space:]]*["'"'"']?concurrency["'"'"']?:' || true)
  _pc_top=$(printf '%s\n' "$_pc_src" | grep -c '^concurrency:[[:space:]]*$' || true)
  if [ "$_pc_n" != 1 ] || [ "$_pc_top" != 1 ]; then
    echo "FAIL: $1 concurrency: block must appear exactly once, at column 0 (found $_pc_n key(s), $_pc_top at column 0; a job-level one lets a new job escape the cancel)" >&2
    return 1
  fi
  _pc_rc=0
  _pc_g=$(printf '%s\n' "$_pc_src" | _prc_val group)
  _pc_c=$(printf '%s\n' "$_pc_src" | _prc_val cancel-in-progress)
  if [ "$_pc_g" != "$PRC_GROUP" ]; then
    echo "FAIL: $1 concurrency group is '$_pc_g' (must be exactly '$PRC_GROUP'; a ref or sha key lets back-to-back main runs replace each other, and no workflow prefix lets CI and golden-path cancel each other)" >&2
    _pc_rc=1
  fi
  if [ "$_pc_c" != "$PRC_CANCEL" ]; then
    echo "FAIL: $1 concurrency cancel-in-progress is '$_pc_c' (must be exactly '$PRC_CANCEL'; anything wider can cancel a main run or a same-head reopen)" >&2
    _pc_rc=1
  fi
  return "$_pc_rc"
}

_prc_val() {  # <key> (stdin: comment-stripped workflow) -> the trimmed value of the top-level concurrency block's two-space key
  awk -v k="  $1:" '
    /^concurrency:/ { inb = 1; next }
    /^[^ \t]/ { inb = 0 }
    inb && index($0, k) == 1 { v = substr($0, length(k) + 1); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v; exit }'
}

# check_runner_pinned <file> (SWAS-306): the kit's runner-pin lock (RP). Every `ubuntu-` token on a code line
# (comments stripped, matched case-insensitively, a trailing . or - trimmed so "ubuntu-24.04." at a sentence end
# compares as the label) must equal KIT_HOSTED_RUNNER. One text rule reds ubuntu-latest, ubuntu-slim, a stray
# ubuntu-22.04, a matrix os: entry, an input default and an expression fallback, wherever they sit. A container
# tag (ubuntu:26.04) has no "ubuntu-" and is not a runner label. It reads text: a label that arrives from a
# variable at run time is invisible to it. The one place to move at an Ubuntu migration is this constant.
KIT_HOSTED_RUNNER=ubuntu-24.04
check_runner_pinned() {  # <file> -> 0 ok; 1 any ubuntu- token on a code line is not KIT_HOSTED_RUNNER
  sed 's/#.*//' "$1" | awk -v want="$KIT_HOSTED_RUNNER" -v file="$1" '
    { rest = tolower($0)
      while (match(rest, /ubuntu-[a-z0-9._-]*/)) {
        tok = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
        sub(/[.-]+$/, "", tok)
        if (tok != want) {
          printf "FAIL: %s:%d runner label '\''%s'\'' is not '\''%s'\'' (pin every kit runner to the one image the gates are proven on; SWAS-306)\n", file, NR, tok, want > "/dev/stderr"
          bad = 1
        }
      }
    }
    END { exit bad }'
}

# check_runner_pins_tree <root> (SWAS-306): RP over a KIT tree. Reads every .github/workflows/*.yml|*.yaml, plus
# the shipped adopter templates (profiles/*.yml, profiles/*/ci.yml, docs/operations/*.github.yml) when present;
# a template glob that matches nothing is skipped. Liveness counts only the workflows: zero files read, or zero
# ubuntu- tokens in them, is a FAIL (a glob that matched nothing must not pass).
check_runner_pins_tree() {  # <root> -> 0 ok; 1 an unpinned label, or the leg read nothing
  _rt_rc=0; _rt_files=0; _rt_tokens=0
  for _rt_f in "$1"/.github/workflows/*.yml "$1"/.github/workflows/*.yaml; do
    [ -f "$_rt_f" ] || continue
    _rt_files=$((_rt_files + 1))
    _rt_tokens=$((_rt_tokens + $(sed 's/#.*//' "$_rt_f" | grep -ci 'ubuntu-' || true)))
    check_runner_pinned "$_rt_f" || _rt_rc=1
  done
  if [ "$_rt_files" = 0 ] || [ "$_rt_tokens" = 0 ]; then
    echo "FAIL: RP liveness — read $_rt_files workflow file(s) and $_rt_tokens ubuntu- token line(s) under $1/.github/workflows (a kit tree runs on $KIT_HOSTED_RUNNER; a glob that matched nothing must not pass)" >&2
    _rt_rc=1
  fi
  for _rt_f in "$1"/profiles/*.yml "$1"/profiles/*/ci.yml "$1"/docs/operations/*.github.yml; do
    [ -f "$_rt_f" ] || continue
    check_runner_pinned "$_rt_f" || _rt_rc=1
  done
  return "$_rt_rc"
}

# check_line_breaks <file> (SWAS-447, LB): a YAML parser ends a line at CR (and, in YAML 1.1, at NEL, LS, PS)
# but every LF-split lock in this file reads one record per LF, so a hidden key behind such a byte is invisible to the locks. This refuses
# the bytes in a whole file: CR (its own alternative), the other C0 controls except TAB and LF, DEL, the C1 controls (NEL named), LS
# and PS. NUL is found separately (awk cannot see it portably) and named by file. Octal escapes only: no banned byte in this source.
# Each hit prints one line (file, LF line number, name, hex bytes) to stderr and adds to _lb_hits; rc 1 on any hit.
# WHAT IT PROVES: no judged file holds a banned byte at scan time. It does not parse YAML (SWAS-445 is the parser grade). Scope: the kit's
# own workflows and the templates it ships (check_line_breaks_tree); adopter trees are out of scope, so adopter-side RES-1 stays open until
# SWAS-445. Not judged: dependabot.yml, conformance/fixtures/*/ci.yml, invalid UTF-8 (a parser rejects it). It reads the worktree, so a
# core.autocrlf=true checkout reds locally on LF blobs. CEILING: the --own-tree call runs inside the workflow it judges, so a hidden key on
# that job can neuter it; the --shard-join calls are independent runners, and a local --own-tree or --line-breaks run is outside the YAML.
# Call sites: own_tree_run (kit trees, first in the kit block), shard_join_run (before the shape judge), and --line-breaks [<root>].
_lb_hits=0
check_line_breaks() {  # <file> -> 0 no banned byte; 1 any banned byte (every hit is reported)
  _lb_rc=0
  if _lb_o=$(LC_ALL=C awk -v file="$1" '
    function hex(s,   i, h) { h = ""; for (i = 1; i <= length(s); i++) h = h (i > 1 ? " " : "") sprintf("%02x", ord[substr(s, i, 1)]); return h }
    function scan(re, name,   s, b, nm) {
      s = $0
      while (match(s, re)) {
        b = substr(s, RSTART, RLENGTH)
        nm = name
        if (name == "C0") nm = (b == "\015") ? "CR" : (b == "\013") ? "VT" : (b == "\014") ? "FF" : (b == "\177") ? "DEL" : "C0 control"
        printf "FAIL: %s:%d: %s (%s) inside a line: a YAML parser reads a line break here and the LF-split locks do not (SWAS-447)\n", file, NR, nm, hex(b)
        s = substr(s, RSTART + RLENGTH)
      }
    }
    BEGIN { for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i }
    {
      scan("\\015", "C0")
      scan("[\\001-\\010\\013\\014\\016-\\037\\177]", "C0")
      scan("\\302\\205", "NEL")
      scan("\\302[\\200-\\204\\206-\\237]", "C1 control")
      scan("\\342\\200\\250", "LS")
      scan("\\342\\200\\251", "PS")
    }' "$1"); then _lb_arc=0; else _lb_arc=$?; fi
  if [ "$_lb_arc" != 0 ]; then
    echo "FAIL: $1: the line-break scan did not run (awk rc $_lb_arc): an unreadable file or a broken awk must not read as clean (SWAS-447)" >&2
    _lb_hits=$((_lb_hits + 1))
    return 1
  fi
  if [ -n "$_lb_o" ]; then
    printf '%s\n' "$_lb_o" >&2
    _lb_hits=$((_lb_hits + $(printf '%s\n' "$_lb_o" | wc -l)))
    _lb_rc=1
  fi
  if ! LC_ALL=C tr -d '\000' < "$1" | cmp -s - "$1"; then
    echo "FAIL: $1: NUL (00) in the file: not YAML-printable (SWAS-447; named by file, not by line)" >&2
    _lb_hits=$((_lb_hits + 1)); _lb_rc=1
  fi
  return "$_lb_rc"
}

# check_line_breaks_tree <root> (SWAS-447, LB): the check over the kit's judged file set (the RP set plus the
# GitLab templates). Liveness: zero .github/workflows files read is a FAIL. Sets _lb_files and _lb_hits for the caller.
check_line_breaks_tree() {  # <root> -> 0 ok; 1 any banned byte, or no workflow file was read
  _lt_rc=0; _lb_files=0; _lb_wf=0; _lb_hits=0
  for _lt_f in "$1"/.github/workflows/*.yml "$1"/.github/workflows/*.yaml "$1"/.github/workflows/.*.yml "$1"/.github/workflows/.*.yaml; do  # the dot globs: a plain * skips dot-named files
    [ -f "$_lt_f" ] || continue
    _lb_files=$((_lb_files + 1)); _lb_wf=$((_lb_wf + 1))
    check_line_breaks "$_lt_f" || _lt_rc=1
  done
  if [ "$_lb_wf" = 0 ]; then
    echo "FAIL: line-break liveness: read no workflow file under $1/.github/workflows (a glob that matched nothing must not pass; SWAS-447)" >&2
    _lt_rc=1
  fi
  for _lt_f in "$1"/.gitlab-ci.yml "$1"/profiles/*.yml "$1"/profiles/*/ci.yml "$1"/profiles/*/ci.gitlab-ci.yml \
               "$1"/docs/operations/*.github.yml "$1"/docs/operations/*.gitlab-ci.yml; do
    [ -f "$_lt_f" ] || continue
    _lb_files=$((_lb_files + 1))
    check_line_breaks "$_lt_f" || _lt_rc=1
  done
  [ "$_lt_rc" != 0 ] || echo "OK: line-break ban — $_lb_files file(s) read under $1"
  return "$_lt_rc"
}

# check_sast_parse_spans <workflow-file> (SWAS-278 278a, SP): the kit's SAST-parse step must print where semgrep
# says each parse error is. semgrep's message echoes the file's opening text, so the real location lives only in
# each error's spans; without the spans line a parse failure names a file and no line. Inside the step named
# "SAST parse coverage", exactly one `jq -r` line reads .errors[] | .spans[]? from sast-semgrep.json and prints
# "semgrep-span:", and that same line ends `|| true` so it can never decide the verdict (the jq -e lines do).
check_sast_parse_spans() {  # <workflow-file> -> 0 ok; 1 the spans line is absent, duplicated, or can fail the step
  _sp_c=$(awk '
    /^      - name: SAST parse coverage/ { inb = 1; next }
    inb && /^      - name:/ { inb = 0 }
    inb && /jq -r/ && /\.spans\[\]\?/ && /semgrep-span:/ && /sast-semgrep\.json/ { all++; if ($0 ~ /\|\| true[ \t]*$/) soft++ }
    inb && /jq -r/ && /semgrep-loc:/ && /sast-semgrep\.json/ { lall++; if ($0 ~ /\|\| true[ \t]*$/) lsoft++ }
    inb && /echo "semgrep-bisect: / { ball++ }
    inb && /_spc_bisect "\$_spc_f"/ { call++; if ($0 ~ /_spc_bisect "\$_spc_f" \|\| true;/) csoft++ }
    END { print all + 0, soft + 0, lall + 0, lsoft + 0, ball + 0, call + 0, csoft + 0 }' "$1")
  set -- "$1" $_sp_c
  _sp_all=$2; _sp_soft=$3; _sp_lall=$4; _sp_lsoft=$5; _sp_ball=$6; _sp_call=$7; _sp_csoft=$8
  if [ "$_sp_ball" != 1 ]; then
    echo "FAIL: $1 the SAST parse coverage step must carry exactly one line printing the prefix-bisect result (echo \"semgrep-bisect: ...\"); found $_sp_ball" >&2
    return 1
  fi
  if [ "$_sp_call" != 1 ] || [ "$_sp_csoft" != 1 ]; then
    echo "FAIL: $1 the prefix-bisect call must appear once and end '|| true' so the diagnostic is non-fatal and never decides the verdict (calls=$_sp_call, soft=$_sp_csoft)" >&2
    return 1
  fi
  if [ "$_sp_lall" != 1 ]; then
    echo "FAIL: $1 the SAST parse coverage step must carry exactly one jq -r line printing each PartialParsing location (semgrep-loc:, from the .type array); found $_sp_lall" >&2
    return 1
  fi
  if [ "$_sp_lsoft" != 1 ]; then
    echo "FAIL: $1 the semgrep-loc line must end '|| true' so it is non-fatal and never decides the verdict" >&2
    return 1
  fi
  if [ "$_sp_all" != 1 ]; then
    echo "FAIL: $1 the SAST parse coverage step must carry exactly one jq -r line printing each semgrep error's spans (semgrep-span:, from .errors[] | .spans[]?); found $_sp_all" >&2
    return 1
  fi
  if [ "$_sp_soft" != 1 ]; then
    echo "FAIL: $1 the semgrep-span line must end '|| true' so it is non-fatal and never decides the verdict" >&2
    return 1
  fi
  return 0
}

# check_guard_delta_step <workflow-file> (SWAS-301 301a, GD): the `guard-delta` job must replay every recorded cell against the BASE
# core (see the block comment inside). Nothing may mask its verdict: exactly one bare `--delta` line, no continue-on-error.
check_guard_delta_step() {  # <workflow-file> -> 0 ok; 1 the step is absent, vacuous or masked
  # SWAS-301 (round 3): the delta is its OWN job, `guard-delta`. The job must exist once with a timeout and the guard-battery lane
  # condition, check out two commits, take HEAD^1 as its base (never HEAD, never a merge-base or a fetch), SKIP only through a
  # diff of the WHOLE .claude/hooks/ directory and only with an explicit SKIP line, write the base core, end in a bare --delta
  # line, and be named in the required `conformance` aggregator's needs: list so its failure blocks.
  _gd_c=$(awk '
    /^  guard-delta:[ \t]*$/ { inb = 1; jobs++; next }
    inb && /^  [a-z]/ { inb = 0 }
    inb && /^    timeout-minutes: [0-9]+[ \t]*$/ { tmo++ }
    inb && /^    if: needs\.changes\.outputs\.docs_only != .true. && needs\.changes\.outputs\.push_graded != .true./ { lane++ }
    inb && /^          fetch-depth: 2[ \t]/ { fd2++ }
    inb && /fetch-depth:/ && !/fetch-depth: 2[ \t]/ { fdother++ }
    inb && /^ *base=/ { bases++; if ($0 !~ /git rev-parse HEAD\^1\)/) badbase++ }
    inb && /merge-base|git fetch/ { mbf++ }
    inb && /git diff --quiet "\$base" HEAD -- \.claude\/hooks\/[ ;]/ { diffl++; if ($0 ~ /guard-core\.sh/) narrow++ }
    inb && /echo "SKIP: guard delta/ && /no hook file changed since \$base/ { skipl++ }
    inb && /git show "\$base:\.claude\/hooks\/guard-core\.sh" > "\$RUNNER_TEMP\/pristine-core\.sh"/ { show++ }
    inb && /sh conformance\/agent-autonomy\.sh --delta/ { anyrun++ }
    inb && /^ +sh conformance\/agent-autonomy\.sh --delta "\$RUNNER_TEMP\/pristine-core\.sh"[ \t]*$/ { run++ }
    inb && /continue-on-error/ { coe++ }
    END { print jobs + 0, tmo + 0, lane + 0, fd2 + 0, fdother + 0, bases + 0, badbase + 0, mbf + 0, diffl + 0, narrow + 0, skipl + 0, show + 0, anyrun + 0, run + 0, coe + 0 }' "$1")
  _gd_w=$(awk '/^  conformance:[ \t]*$/ { inb = 1; next } inb && /^  [a-z]/ { inb = 0 } inb && /^    needs: / && /[ \[,]guard-delta[],]/ { w++ } END { print w + 0 }' "$1")
  set -- "$1" $_gd_c "$_gd_w"
  # $2 jobs $3 timeout $4 lane $5 fetch-depth:2 $6 other fetch-depth $7 base= lines $8 bad base $9 merge-base/fetch ${10} hooks diff
  # ${11} narrowed diff ${12} SKIP line ${13} git show ${14} any --delta ${15} bare --delta ${16} continue-on-error ${17} wired
  if [ "$2" != 1 ]; then
    echo "FAIL: $1 the workflow must carry exactly one 'guard-delta' job (the zero-verdict-move proof); found $2" >&2; return 1
  fi
  if [ "$3" != 1 ]; then
    echo "FAIL: $1 the guard-delta job must carry a timeout-minutes bound; found $3" >&2; return 1
  fi
  if [ "$4" != 1 ]; then
    echo "FAIL: $1 the guard-delta job must carry guard-battery's lane condition (docs_only and push_graded); found $4" >&2; return 1
  fi
  if [ "$5" != 1 ] || [ "$6" != 0 ] || [ "$9" != 0 ]; then
    echo "FAIL: $1 the guard-delta job must check out exactly two commits (fetch-depth: 2) and take its base from HEAD^1 with no other fetch-depth, merge-base or git fetch (fetch-depth 2=$5, other=$6, merge-base/fetch=$9)" >&2; return 1
  fi
  if [ "$7" != 1 ] || [ "$8" != 0 ]; then
    echo "FAIL: $1 the guard-delta job must take its base only from git rev-parse HEAD^1, because a base pinned to HEAD compares a core with itself (base lines=$7, other=$8)" >&2; return 1
  fi
  if [ "${10}" != 1 ] || [ "${11}" != 0 ]; then
    echo "FAIL: $1 the guard-delta skip must compare the WHOLE .claude/hooks/ directory (git diff --quiet \"\$base\" HEAD -- .claude/hooks/ ...), never guard-core.sh alone: a guard.sh-only change must not skip (whole-directory diffs=${10}, narrowed=${11})" >&2; return 1
  fi
  if [ "${12}" != 1 ]; then
    echo "FAIL: $1 the guard-delta skip must print an explicit 'SKIP: guard delta ... no hook file changed since \$base' line, never a silent green; found ${12}" >&2; return 1
  fi
  if [ "${13}" != 1 ]; then
    echo "FAIL: $1 the guard-delta job must write the base core with git show \"\$base:.claude/hooks/guard-core.sh\" to \$RUNNER_TEMP/pristine-core.sh; found ${13}" >&2; return 1
  fi
  if [ "${15}" != 1 ] || [ "${14}" != 1 ]; then
    echo "FAIL: $1 the guard-delta job must run '--delta' exactly once as a bare line 'sh conformance/agent-autonomy.sh --delta \"\$RUNNER_TEMP/pristine-core.sh\"' with nothing after it, so its failure is not masked (--delta lines=${14}, bare lines=${15})" >&2; return 1
  fi
  if [ "${16}" != 0 ]; then
    echo "FAIL: $1 the guard-delta job carries continue-on-error, which would mask its verdict" >&2; return 1
  fi
  if [ "${17}" != 1 ]; then
    echo "FAIL: $1 the required 'conformance' aggregator does not name guard-delta in its needs: list, so a failing delta would not block the merge" >&2; return 1
  fi
  return 0
}

# check_boundary_redteam_step <workflow-file> (SWAS-359 352a, BR): the `boundary-redteam` job must run the live red-team cells only when a boundary file
# changed, with an explicit SKIP otherwise; must carry a timeout and the guard-battery lane condition; must be named in the required `conformance`
# aggregator's needs: list; must run the harness exactly once; and must not carry continue-on-error (report-only is the harness's own `--report-only`
# flag, visible on the run line, until slice 352b removes it).
# SWAS-363: five steps (found by name prefix, the self-test's name carries a changing mutant count) must each carry the exact gate line as their next key
# line; the live step's `run: |` body is pinned as an exact ordered sequence that ends at the dedent out of the block, so any other line in it reds.
# SWAS-404: six steps now carry a name prefix (the sixth is the CANDIDATE leg, whose `if:` is `${{ !cancelled() && steps.gate.outputs.live == 'yes' }}`),
# and the run lines are counted apart: a `sh conformance/boundary-redteam.sh ... --measure ...` line is the candidate leg (exactly once, its seven-line body
# pinned below), every other non-selftest run line is the default leg (exactly once, report-only).
check_boundary_redteam_step() {  # <workflow-file> -> 0 ok; 1 the job is absent, ungated, vacuous or masked
  # the candidate step's body, one pinned line each (compared inside awk after the 10-space indent)
  _brc1='mkdir -p "$RUNNER_TEMP/cand/.claude"'
  _brc2='cp .claude/settings.json "$RUNNER_TEMP/cand/.claude/settings.json"'
  _brc3='test -f "$GITHUB_WORKSPACE/docs/patches/2026-10-25-boundary-default-352b.settings.patch" || { echo "the 352b patch is gone; the v3.242 measurement needs it present" >&2; exit 1; }'
  _brc4='if git -C "$RUNNER_TEMP/cand" apply -R --check "$GITHUB_WORKSPACE/docs/patches/2026-10-25-boundary-default-352b.settings.patch" >/dev/null 2>&1; then echo "patch apply: skipped (already applied)"; else git -C "$RUNNER_TEMP/cand" apply "$GITHUB_WORKSPACE/docs/patches/2026-10-25-boundary-default-352b.settings.patch"; echo "patch apply: applied"; fi'
  _brc5='jq '"'"'.sandbox.network.strictAllowlist = true'"'"' "$RUNNER_TEMP/cand/.claude/settings.json" > "$RUNNER_TEMP/candidate-strict.json"'
  _brc6='sha256sum .claude/settings.json docs/patches/2026-10-25-boundary-default-352b.settings.patch "$RUNNER_TEMP/candidate-strict.json"'
  _brc7='sh conformance/boundary-redteam.sh --settings "$RUNNER_TEMP/candidate-strict.json" --measure C36,C37,C37c'
  _br_all=$(awk -v c1="$_brc1" -v c2="$_brc2" -v c3="$_brc3" -v c4="$_brc4" -v c5="$_brc5" -v c6="$_brc6" -v c7="$_brc7" '
    BEGIN {
      cb[1] = c1; cb[2] = c2; cb[3] = c3; cb[4] = c4; cb[5] = c5; cb[6] = c6; cb[7] = c7
      candif = "        if: ${{ !cancelled() && steps.gate.outputs.live == \047yes\047 }}"
      # SWAS-363: one source for the exit-3 warning shape (the counter and the body pin both read it) and for the exact gate line.
      warnre = "^ +if \\[ \"\\$rc\" -eq 3 \\]; then echo \"::warning::[^\"]*NO CELL RAN[^\"]*\"; echo \"[^\"]*\" >> \"\\$GITHUB_STEP_SUMMARY\"; exit 0; fi[ \t]*$"
      ifline = "        if: steps.gate.outputs.live == \047yes\047"
      np = 6
      pfx[1] = "Install Node 24"
      pfx[2] = "Install the sandbox\047s Linux prerequisites"
      pfx[3] = "Allow unprivileged user namespaces for the sandbox"
      pfx[4] = "Boundary red-team — live cells"
      pfx[5] = "Boundary red-team harness full self-test"
      pfx[6] = "Boundary red-team — candidate leg"
    }
    /^  boundary-redteam:[ \t]*$/ { inb = 1; jobs++; next }
    inb && /^  [a-z]/ { inb = 0 }
    inb && /^    timeout-minutes: [0-9]+[ \t]*$/ { tmo++ }
    inb && /^    if: needs\.changes\.outputs\.docs_only != .true. && needs\.changes\.outputs\.push_graded != .true./ { lane++ }
    inb && /^          fetch-depth: 2[ \t]/ { fd2++ }
    inb && /fetch-depth:/ && !/fetch-depth: 2[ \t]/ { fdother++ }
    inb && /^ *base=/ { bases++; if ($0 !~ /git rev-parse HEAD\^1\)/) badbase++ }
    inb && /git diff --quiet "\$base" HEAD -- / { diffl++; ps = $0; sub(/;.*$/, "", ps); if (ps ~ /\.claude\/settings\.json/ && ps ~ /templates\/sandbox-strict\.settings\.local\.json/ && ps ~ /conformance\/guard-wired\.sh/ && ps ~ /docs\/patches\/2026-10-25-boundary-default-352b\.settings\.patch/ && ps ~ /conformance\/boundary-redteam\.sh/) fullspec++ }
    inb && /echo "SKIP: boundary red-team/ && /did not run/ { skipl++ }
    # SWAS-363: the run body of the live step is pinned in order, up to the dedent out of `run: |` (a line at the step key indent or shallower).
    inb && inrun && !/^[ \t]*$/ {
      match($0, /^ */)
      if (RLENGTH <= 8) {
        if (bidx != 4 && !bbad) { bbad = 1; bdiag = "the block ended after " bidx " pinned line(s), want 4" }
        inrun = 0
      } else {
        bidx++; line = $0; sub(/^ +/, "", line); ok = 0
        if (bidx == 1 && line == "rc=0") ok = 1
        if (bidx == 2 && $0 ~ /^ +sh conformance\/boundary-redteam\.sh --report-only \|\| rc=\$\?[ \t]*$/) ok = 1
        if (bidx == 3 && $0 ~ warnre) ok = 1
        if (bidx == 4 && $0 ~ /^ +exit "\$rc"[ \t]*$/) ok = 1
        if (!ok && !bbad) { bbad = 1; bdiag = line }
      }
    }
    # SWAS-404: the run body of the candidate step is pinned in order, six lines, up to the dedent out of its run block (a comment or any other line reds)
    inb && inrun6 && !/^[ \t]*$/ {
      match($0, /^ */)
      if (RLENGTH <= 8) {
        if (cidx != 7 && !cbad) { cbad = 1; cdiag = "the block ended after " cidx " pinned line(s), want 7" }
        inrun6 = 0
      } else {
        cidx++; cline = $0; sub(/^ +/, "", cline)
        if (!(cidx <= 7 && $0 == ("          " cb[cidx])) && !cbad) { cbad = 1; cdiag = cline }
      }
    }
    # the six steps that carry the diff gate are found by their name prefix; the next key line must be the exact gate line
    inb && /^      - / {
      cur = 0; want = 0; gcur = (index($0, "      - name: Boundary red-team — the runtime cells") == 1)
      for (i = 1; i <= np; i++) if (index($0, "      - name: " pfx[i]) == 1) { pcount[i]++; cur = i; want = 1 }
    }
    inb && want && !/^      - / && !/^[ \t]*$/ && !/^[ \t]*#/ { if ($0 != (cur == 6 ? candif : ifline)) pbad[cur] = 1; want = 0 }
    # nothing may change how the pinned steps run or what they inherit: no shell:/env:/working-directory:/continue-on-error: key on them, no defaults:, no GITHUB_ENV or BASH_ENV in the job
    /^defaults:/ { if (xdiag == "") xdiag = "the workflow carries a top-level defaults: key" }
    inb && /^    defaults:/ { if (xdiag == "") xdiag = "the boundary-redteam job carries a defaults: key" }
    inb && /GITHUB_ENV|BASH_ENV|GITHUB_PATH/ { if (xdiag == "") xdiag = "the job text names GITHUB_ENV, BASH_ENV or GITHUB_PATH" }
    /BASH_ENV/ { if (xdiag == "") xdiag = "the workflow file names BASH_ENV" }
    /^env:/ { if (xdiag == "") xdiag = "the workflow carries a top-level env: key" }
    inb && /^    env:/ { if (xdiag == "") xdiag = "the boundary-redteam job carries an env: key" }
    inb && gcur && /^        (shell|env|working-directory|continue-on-error|if):/ { k = $0; sub(/^ +/, "", k); sub(/:.*/, "", k); if (xdiag == "") xdiag = "the gate step carries a " k ": key (it must run unconditionally, unchanged)" }
    inb && cur > 0 && /^        (shell|env|working-directory|continue-on-error):/ { k = $0; sub(/^ +/, "", k); sub(/:.*/, "", k); if (xdiag == "") xdiag = "the step named " pfx[cur] "... carries a " k ": key" }
    inb && cur == 4 && /^        run:/ { runs4++; if ($0 ~ /^        run: \|$/) { inrun = 1; bidx = 0 } else if (!bbad) { bbad = 1; bdiag = "run: is not a literal block" } }
    # SWAS-404: the candidate step (the sixth prefix) has one `run: |` block of exactly six lines, each equal to its pinned text after the 10-space indent
    inb && cur == 6 && /^        run:/ { runs6++; if ($0 ~ /^        run: \|$/) { inrun6 = 1; cidx = 0 } else if (!cbad) { cbad = 1; cdiag = "run: is not a literal block" } }
    # the default leg is a run line with no --measure; the candidate leg is a run line that names --measure (counted apart, each exactly once)
    inb && /^ +sh conformance\/boundary-redteam\.sh/ && !/--selftest/ && !/ --measure / { runs++; if ($0 ~ /--report-only/) ro++ }
    inb && /^ +sh conformance\/boundary-redteam\.sh/ && !/--selftest/ && / --measure / { cruns++ }
    inb && /^ +run: sh conformance\/boundary-redteam\.sh --selftest([ \t]+#.*)?$/ { st++ }
    inb && /continue-on-error/ { coe++ }
    inb && /^ +sh conformance\/boundary-redteam\.sh --report-only \|\| rc=\$\?[ \t]*$/ { rcgood++ }
    inb && /^ +exit "\$rc"[ \t]*$/ { exitrc++ }
    inb && /\|\| true/ { ortrue++ }
    inb && $0 ~ warnre { warn++ }
    inb && /SWAS-354/ { expiry++ }
    END {
      if (inrun && bidx != 4 && !bbad) { bbad = 1; bdiag = "the block ended after " bidx " pinned line(s), want 4" }
      if (runs4 != 1 && !bbad) { bbad = 1; bdiag = "the live step has " runs4 + 0 " run: keys, want 1" }
      if (inrun6 && cidx != 7 && !cbad) { cbad = 1; cdiag = "the block ended after " cidx + 0 " pinned line(s), want 7" }
      if (runs6 != 1 && !cbad) { cbad = 1; cdiag = "the candidate step has " runs6 + 0 " run: keys, want 1" }
      for (i = 1; i <= np; i++) if (pcount[i] != 1 || pbad[i]) { pins++; if (pdiag == "") pdiag = "the step named " pfx[i] "... (found " pcount[i] + 0 ", want 1, with the exact gate line next)" }
      print jobs + 0, tmo + 0, lane + 0, fd2 + 0, fdother + 0, bases + 0, badbase + 0, diffl + 0, fullspec + 0, skipl + 0, pins + 0, runs + 0, ro + 0, coe + 0, rcgood + 0, exitrc + 0, ortrue + 0, warn + 0, expiry + 0,bbad + 0, st + 0, cruns + 0, cbad + 0
      print pdiag
      print bdiag
      print xdiag
      print cdiag
    }' "$1")
  _br_c=$(printf '%s\n' "$_br_all" | sed -n 1p); _br_pd=$(printf '%s\n' "$_br_all" | sed -n 2p); _br_bd=$(printf '%s\n' "$_br_all" | sed -n 3p); _br_xd=$(printf '%s\n' "$_br_all" | sed -n 4p); _br_cd=$(printf '%s\n' "$_br_all" | sed -n 5p)
  # outside the job: every PR's conformance-selftests must run the mutant-free --selftest-core and never the full-mutant --selftest
  _br_o=$(awk '
    /^  boundary-redteam:[ \t]*$/ { inj = 1; next }
    inj && /^  [a-z]/ { inj = 0 }
    !inj && /sh conformance\/boundary-redteam\.sh --selftest-core/ { core++ }
    !inj && /sh conformance\/boundary-redteam\.sh --selftest([ \t]+#.*)?$/ { full++ }
    END { print core + 0, full + 0 }' "$1")
  _br_w=$(awk '/^  conformance:[ \t]*$/ { inb = 1; next } inb && /^  [a-z]/ { inb = 0 } inb && /^    needs: / && /[ \[,]boundary-redteam[],]/ { w++ } END { print w + 0 }' "$1")
  set -- "$1" $_br_c $_br_o "$_br_w"
  # $2 jobs $3 timeout $4 lane $5 fetch-depth:2 $6 other fetch-depth $7 base= lines $8 bad base $9 diff lines ${10} full pathspec
  # ${11} SKIP line ${12} pinned steps whose if: line is not exact (SWAS-363, six since SWAS-404; want 0) ${13} default-leg run lines ${14} report-only run lines ${15} continue-on-error
  # ${16}-${22} pinned run line, exit "$rc" lines, '|| true', exit-3 warning, SWAS-354, bad live-step body, full self-test lines (the harness-in-pathspec count is folded into the full-pathspec pin ${10})
  # ${23} candidate-leg run lines (a --measure line; SWAS-404) ${24} candidate step body deviation (want 0) ${25} core selftest ${26} full selftest outside the job ${27} wired
  if [ "$2" != 1 ]; then
    echo "FAIL: $1 the workflow must carry exactly one 'boundary-redteam' job (the runtime red-team cells); found $2" >&2; return 1
  fi
  if [ "$3" != 1 ]; then
    echo "FAIL: $1 the boundary-redteam job must carry a timeout-minutes bound; found $3" >&2; return 1
  fi
  if [ "$4" != 1 ]; then
    echo "FAIL: $1 the boundary-redteam job must carry guard-battery's lane condition (docs_only and push_graded); found $4" >&2; return 1
  fi
  if [ "$5" != 1 ] || [ "$6" != 0 ]; then
    echo "FAIL: $1 the boundary-redteam job must check out exactly two commits (fetch-depth: 2) with no other fetch-depth (fetch-depth 2=$5, other=$6)" >&2; return 1
  fi
  if [ "$7" != 1 ] || [ "$8" != 0 ]; then
    echo "FAIL: $1 the boundary-redteam job must take its base only from git rev-parse HEAD^1 (base lines=$7, other=$8)" >&2; return 1
  fi
  if [ "$9" != 1 ] || [ "${10}" != 1 ]; then
    echo "FAIL: $1 the boundary-redteam job must be diff-gated: one 'git diff --quiet \"\$base\" HEAD -- ...' naming .claude/settings.json, templates/sandbox-strict.settings.local.json, conformance/guard-wired.sh, the SWAS-404 candidate patch docs/patches/2026-10-25-boundary-default-352b.settings.patch and the harness conformance/boundary-redteam.sh (diff lines=$9, full pathspec=${10})" >&2; return 1
  fi
  if [ "${11}" != 1 ]; then
    echo "FAIL: $1 the boundary-redteam job must print an explicit 'SKIP: boundary red-team ... did not run' line when no boundary file changed, never a silent green; found ${11}" >&2; return 1
  fi
  if [ "${12}" != 0 ]; then
    echo "FAIL: $1 the boundary-redteam job's six gated steps (Install Node 24, the sandbox prerequisites, the userns allowance, the live cells, the full self-test, the SWAS-404 candidate leg) must be gated on steps.gate.outputs.live == 'yes': each one's next key line must be exactly '        if: steps.gate.outputs.live == 'yes'' (no trailing comment, not commented out), or for the candidate leg exactly '        if: \${{ !cancelled() && steps.gate.outputs.live == 'yes' }}', or the diff gate gates nothing; first problem: $_br_pd" >&2; return 1
  fi
  if [ -n "$_br_xd" ]; then
    echo "FAIL: $1 the boundary-redteam job must not change how its steps run or what they inherit (no shell:, env:, working-directory: or continue-on-error: key on a pinned step, no defaults: in the job or the workflow, no GITHUB_ENV or BASH_ENV in the job); first problem: $_br_xd" >&2; return 1
  fi
  if [ "${23}" != 1 ]; then
    echo "FAIL: $1 the boundary-redteam job must run the candidate leg (a 'sh conformance/boundary-redteam.sh ... --measure ...' line, SWAS-404) exactly once; found ${23}" >&2; return 1
  fi
  if [ "${24}" != 0 ]; then
    echo "FAIL: $1 the candidate step's body must be exactly seven lines, in order: the scratch directory, the copy of the shipped settings, the fail-closed presence test of the 352b patch, the patch apply (or its exact skip line), the strictAllowlist jq, the sha256sum line and the one run line 'sh conformance/boundary-redteam.sh --settings \"\$RUNNER_TEMP/candidate-strict.json\" --measure C36,C37,C37c'; any other line (a comment, a '|| true', an exit 0 after exit 3) is refused, because the step is not report-only and an INCONCLUSIVE or a FAIL must red it; first deviation: $_br_cd" >&2; return 1
  fi
  if [ "${13}" != 1 ]; then
    echo "FAIL: $1 the boundary-redteam job must run the default leg 'sh conformance/boundary-redteam.sh' (no --measure) exactly once; found ${13}" >&2; return 1
  fi
  if [ "${14}" != 1 ]; then
    echo "FAIL: $1 the boundary-redteam run line must carry --report-only until slice 352b lands the default (the live run under today's sandbox-off default reports many OPEN cells)" >&2; return 1
  fi
  if [ "${15}" != 0 ]; then
    echo "FAIL: $1 the boundary-redteam job carries continue-on-error, which would mask its verdict" >&2; return 1
  fi
  # fields ${16}.. : pinned run line, exit "$rc" lines, '|| true', exit-3 warning, SWAS-354, aggregator (checked below)
  if [ "${16}" != 1 ] || [ "${17}" != 1 ] || [ "${18}" != 0 ]; then
    echo "FAIL: $1 the boundary-redteam run must be the pinned pair 'sh conformance/boundary-redteam.sh --report-only || rc=\$?' then exactly one 'exit \"\$rc\"', with no '|| true' (pinned run line=${16}, exit \"\$rc\" lines=${17}, '|| true'=${18}): a masked exit would turn every red into a green" >&2; return 1
  fi
  if [ "${19}" != 1 ]; then
    echo "FAIL: $1 exit 3 (the runtime could not start) must stay a visible warning: one 'if [ \"\$rc\" -eq 3 ]; then' line in the pinned shape, carrying '::warning::', 'NO CELL RAN' and a GITHUB_STEP_SUMMARY line, ending 'exit 0; fi'; found ${19}" >&2; return 1
  fi
  if [ "${20}" -lt 1 ]; then
    echo "FAIL: $1 the boundary-redteam job must name SWAS-354 (slice 352b) as the card that removes --report-only; found ${20} mentions" >&2; return 1
  fi
  if [ "${21}" != 0 ]; then
    echo "FAIL: $1 the run step's body must be exactly: 'rc=0', the pinned --report-only run line, the exit-3 warning line and exit \"\$rc\", in that order, up to the end of the run: | block; any other line inside it (a comment included) is refused, because an early or widened exit 0 would green every red; first deviation: $_br_bd" >&2; return 1
  fi
  if [ "${22}" != 1 ]; then
    echo "FAIL: $1 the boundary-redteam job must run the full-mutant 'sh conformance/boundary-redteam.sh --selftest' exactly once, behind the diff gate; found ${22}" >&2; return 1
  fi
  if [ "${25}" != 1 ] || [ "${26}" != 0 ]; then
    echo "FAIL: $1 conformance-selftests must run the mutant-free 'sh conformance/boundary-redteam.sh --selftest-core' exactly once and the full --selftest nowhere outside the diff-gated job (core=${25}, full outside=${26}): the full mutant run is too slow for every PR" >&2; return 1
  fi
  if [ "${27}" != 1 ]; then
    echo "FAIL: $1 the required 'conformance' aggregator does not name boundary-redteam in its needs: list, so a failing red-team job would not block the merge" >&2; return 1
  fi
  return 0
}

# check_h2_defer_step <workflow-file> (SWAS-376 Slice 0, H2D): the fixture-hermeticity lane step in `conformance-core` lets both faces of every touched
# selftest defer the bare guard battery to `guard-battery` (the CI-BARE-BATTERY-ONCE contract). It must (C2) clone the workspace to
# $RUNNER_TEMP/gb-ref and pass KIT_GUARD_BATTERY_REF and KIT_GUARD_BATTERY_VARIANTS INLINE to the one `selftest-hermetic.sh --touched` call, as an exact
# four-line continued command, with no other line of the job naming either variable (a job-level or step-level env, or a write to $GITHUB_ENV, would
# disqualify later steps from the local pre-push census and leak the defer past the lane); and (C4) carry a step-level `timeout-minutes: 180`.
check_h2_defer_step() {  # <workflow-file> -> 0 ok; 1 the step is absent, unbounded, not deferring, or the variables leak
  # The H2 step's whole run body, byte for byte (the BR17 method): the guard branch, the fetch, the merge-base branch, the clone and the four-line call, nothing else.
  _h2_exp=$(mktemp)
  cat > "$_h2_exp" <<'H2BODY'
          if [ "$GITHUB_EVENT_NAME" != "pull_request" ] || [ -z "${GITHUB_BASE_REF:-}" ]; then
            echo "N/A by design: not a pull_request (event=$GITHUB_EVENT_NAME) — the touched lane is per-PR; pushes to main re-run nothing it has not already graded"
            exit 0
          fi
          git fetch -q --no-tags origin "+refs/heads/$GITHUB_BASE_REF:refs/remotes/origin/$GITHUB_BASE_REF"
          if ! git merge-base HEAD "refs/remotes/origin/$GITHUB_BASE_REF" >/dev/null 2>&1; then
            echo "FAIL: merge-base between HEAD and origin/$GITHUB_BASE_REF is underivable on a full-history checkout — refusing to silent-pass (investigate the history)"
            exit 1
          fi
          git clone -q "$GITHUB_WORKSPACE" "$RUNNER_TEMP/gb-ref"
          HERMETIC_BASE="refs/remotes/origin/$GITHUB_BASE_REF" \
            KIT_GUARD_BATTERY_REF="$RUNNER_TEMP/gb-ref" \
            KIT_GUARD_BATTERY_VARIANTS="case0-tmp0-git1-uid00 case0-tmp1-git1-uid00" \
            sh conformance/selftest-hermetic.sh --touched
H2BODY
  _h2_all=$(awk '
    NR == FNR { want[++nwant] = $0; next }
    # the run body is compared line by line BEFORE the comment and blank skips below: a comment or a blank line inside it would join the
    # backslash continuation of the inline call and leave the assignments unexported (a parser differential), so every line counts
    inh && inrun {
      if ($0 ~ /^[ \t]*$/) rl = 0; else { match($0, /^ */); rl = RLENGTH }
      if ($0 !~ /^[ \t]*$/ && rl <= 8) inrun = 0
      else { bi++; if ($0 != want[bi] && bdiag == "") { bdiag = "line " bi " reads [" $0 "]"; sub(/\[ +/, "[", bdiag) } }
    }
    /^[ \t]*#/ { next }
    /^[ \t]*$/ { next }
    /^env:[ \t]*$/ { wenv = 1; next }
    wenv && /^[A-Za-z]/ { wenv = 0 }
    wenv && /^  (PATH|BASH_ENV):/ { wenvbad++ }
    /^ +GB_CONSUMERS: / { gbn++; if (index($0, "needs.conformance-core.result")) gbok++ }
    /^  conformance-core:[ \t]*$/ { inj = 1; next }
    inj && /^  [a-z]/ { inj = 0 }
    !inj { next }
    /^    (continue-on-error|defaults|env):/ { jobkey++ }
    /^      - / { inh = 0; if (index($0, "      - name: Fixture-hermeticity lane") == 1) { inh = 1; steps++; st = 0 } }
    inh && /^        (continue-on-error|if|shell|working-directory|env):/ { keymask++ }
    inh && /^        run: \|[ \t]*$/ { inrun = 1; nruns++ }
    inh && /^        timeout-minutes: 180[ \t]*$/ { tmo++ }
    inh && /^        timeout-minutes:/ && !/^        timeout-minutes: 180[ \t]*$/ { tmoother++ }
    inh && /^ +git clone -q "\$GITHUB_WORKSPACE" "\$RUNNER_TEMP\/gb-ref"[ \t]*$/ { clone++; clonenr = NR }
    inh && /selftest-hermetic\.sh/ { lanecalls++ }
    inh && /GITHUB_ENV/ { h2env++ }
    inh && /KIT_GUARD_BATTERY/ { kitin++ }
    !inh && /KIT_GUARD_BATTERY/ { kitout++ }
    inh {
      if ($0 ~ /^ +HERMETIC_BASE="refs\/remotes\/origin\/\$GITHUB_BASE_REF" \\$/) st = 1
      else if (st == 1 && $0 ~ /^ +KIT_GUARD_BATTERY_REF="\$RUNNER_TEMP\/gb-ref" \\$/) st = 2
      else if (st == 2 && $0 ~ /^ +KIT_GUARD_BATTERY_VARIANTS="case0-tmp0-git1-uid00 case0-tmp1-git1-uid00" \\$/) st = 3
      else if (st == 3 && $0 ~ /^ +sh conformance\/selftest-hermetic\.sh --touched[ \t]*$/) { callok++; callnr = NR; st = 0 }
      else st = 0
    }
    END {
      bbad = (nruns != 1 || bi != nwant || bdiag != "") ? 1 : 0
      if (bbad && bdiag == "") bdiag = "the body holds " bi + 0 " line(s) under " nruns + 0 " literal run block(s), want " nwant
      print steps + 0, tmo + 0, tmoother + 0, clone + 0, lanecalls + 0, h2env + 0, kitin + 0, kitout + 0, callok + 0, (clone == 1 && callok == 1 && clonenr < callnr) ? 1 : 0, keymask + 0, jobkey + 0, bbad, wenvbad + 0, gbn + 0, gbok + 0
      print bdiag
    }' "$_h2_exp" "$1")
  rm -f "$_h2_exp"
  _h2_bd=$(printf '%s\n' "$_h2_all" | sed -n 2p)
  _h2_c=$(printf '%s\n' "$_h2_all" | sed -n 1p)
  set -- "$1" $_h2_c
  # $2 H2 steps $3 timeout-minutes: 180 $4 other timeout $5 clone lines $6 lane call mentions $7 GITHUB_ENV in the step $8 variable lines in the step
  # $9 variable lines elsewhere in conformance-core ${10} exact pinned calls ${11} clone-before-call
  if [ "$2" != 1 ]; then
    echo "FAIL: $1 conformance-core must carry exactly one 'Fixture-hermeticity lane' step (the H2 lane); found $2" >&2; return 1
  fi
  if [ "$3" != 1 ] || [ "$4" != 0 ]; then
    echo "FAIL: $1 the H2 step must carry timeout-minutes: 180 as a step key (a hung lane is bounded at 180 min, not the 360-min job default); found 180=$3, other=$4" >&2; return 1
  fi
  if [ "$5" != 1 ]; then
    echo "FAIL: $1 the H2 step must clone the workspace to \$RUNNER_TEMP/gb-ref (git clone -q \"\$GITHUB_WORKSPACE\" \"\$RUNNER_TEMP/gb-ref\"): the defer needs a same-commit reference that is not the tree under test; found $5" >&2; return 1
  fi
  if [ "$7" != 0 ]; then
    echo "FAIL: $1 the H2 step must not write to GITHUB_ENV: the defer variables reach the lane call only, never later steps (the local pre-push census reads a KIT_* leak as a disqualifier)" >&2; return 1
  fi
  if [ "${10}" != 1 ] || [ "$6" != 1 ] || [ "$8" != 2 ] || [ "${11}" != 1 ]; then
    echo "FAIL: $1 the H2 step must pass KIT_GUARD_BATTERY_REF and KIT_GUARD_BATTERY_VARIANTS inline to the one lane call, after the clone: the exact four-line command HERMETIC_BASE=... \\ KIT_GUARD_BATTERY_REF=\"\$RUNNER_TEMP/gb-ref\" \\ KIT_GUARD_BATTERY_VARIANTS=\"case0-tmp0-git1-uid00 case0-tmp1-git1-uid00\" \\ sh conformance/selftest-hermetic.sh --touched, unmasked (pinned calls=${10}, lane mentions=$6, variable lines=$8, clone before call=${11})" >&2; return 1
  fi
  if [ "$9" != 0 ]; then
    echo "FAIL: $1 no other line of conformance-core may name KIT_GUARD_BATTERY (a job or step env:, or a write to \$GITHUB_ENV, would leak the defer past the H2 call); found $9" >&2; return 1
  fi
  # fix round (reviewer m1, F1): nothing may mask the lane's verdict, as the BR lock refuses for its steps
  if [ "${12}" != 0 ]; then
    echo "FAIL: $1 the H2 step must not carry a step-level key that masks or changes the lane (continue-on-error, if, shell, working-directory, env); found ${12}" >&2; return 1
  fi
  if [ "${13}" != 0 ]; then
    echo "FAIL: $1 conformance-core must not set a job-level continue-on-error, defaults or env key (it would mask or change every step, the H2 lane included; an env: can re-point PATH so the pinned sh and git resolve to a planted binary); found ${13}" >&2; return 1
  fi
  if [ "${15}" != 0 ]; then
    echo "FAIL: $1 the workflow-level env: must not name PATH or BASH_ENV (it re-points every job's shell and binaries, the H2 lane included); found ${15}" >&2; return 1
  fi
  if [ "${14}" != 0 ]; then
    echo "FAIL: $1 the H2 run body must be exactly the pinned sequence (the N/A-on-push guard branch with its exit 0, the base fetch, the merge-base branch with its exit 1, the gb-ref clone and the four-line inline call), with no other line in the block: any extra line (an exit, an exec, a flipped condition, a trailing true) can green or skip the lane; first deviation: $_h2_bd" >&2; return 1
  fi
  if [ "${16}" != 1 ] || [ "${17}" != 1 ]; then
    echo "FAIL: $1 the aggregate's GB_CONSUMERS must name needs.conformance-core.result once, so the H2 deferral is bound to guard-battery's result (GB_CONSUMERS lines=${16}, naming conformance-core=${17})" >&2; return 1
  fi
  return 0
}

own_tree_run() {  # [<root>]  (default .)
  _ot_root=${1:-.}
  if [ ! -d "$_ot_root" ]; then
    echo "FAIL: --own-tree root '$_ot_root' is not a directory (fail-closed: a check that cannot find its subject must not report success)"
    return 1
  fi
  _ot_ghwf="$_ot_root/.github/workflows/ci.yml"
  _ot_glwf="$_ot_root/.gitlab-ci.yml"
  # Tree markers — copied from _must_have_workflow / _kit_source (verify-enforced-wired.sh:265-285),
  # incl. the disjointness caveat: ENGINEERING-PRINCIPLES.md marks an INCEPTED ADOPTER and must
  # never imply kit-source (an incepted brownfield adopter has it and neither kit marker).
  _ot_must=0
  if [ -f "$_ot_root/ENGINEERING-PRINCIPLES.md" ] || [ -f "$_ot_root/docs/ROADMAP-KIT.md" ] \
     || [ -f "$_ot_root/.github/workflows/golden-path.yml" ]; then _ot_must=1; fi
  _ot_kit=0
  if [ -f "$_ot_root/docs/ROADMAP-KIT.md" ] || [ -f "$_ot_root/.github/workflows/golden-path.yml" ]; then
    _ot_kit=1
  fi

  OWN_REQ="$OWN_GATE_IDS"; OWN_NA_PRETTY=""
  if [ -f "$_ot_root/$OWN_DISP_FILE" ]; then
    if _ot_na=$(read_dispositions "$_ot_root/$OWN_DISP_FILE"); then
      OWN_REQ=""
      for _ot_g in $OWN_GATE_IDS; do
        case "$_ot_na " in
          (*" $_ot_g "*) OWN_NA_PRETTY="$OWN_NA_PRETTY $_ot_g" ;;
          (*) OWN_REQ="$OWN_REQ $_ot_g" ;;
        esac
      done
      OWN_REQ=${OWN_REQ# }
      echo "dispositions: $_ot_root/$OWN_DISP_FILE valid — na:${OWN_NA_PRETTY:- (none)}"
    else
      echo "FAIL: $_ot_root/$OWN_DISP_FILE is INVALID (violations above) — an invalid disposition file"
      echo "      never widens or narrows the required set silently. Fix it, or delete it (absent = all 8 required)."
      return 1
    fi
  fi
  # Zero-enumeration guard: an EMPTY required set is legal ONLY as a validated all-na disposition
  # (and then it is LOUD, above); an empty CONTRACT list is a broken check, never a pass.
  if [ -z "$OWN_REQ" ] && [ -z "$OWN_NA_PRETTY" ]; then
    echo "FAIL: zero gate ids enumerated — refusing to pass on an empty enumeration."
    return 1
  fi

  _ot_seen=0; _ot_rc=0
  if [ -f "$_ot_ghwf" ]; then
    _ot_seen=$((_ot_seen + 1))
    _own_judge "$_ot_ghwf" "$(_own_origin "$_ot_ghwf" "$_ot_kit")" || _ot_rc=1
  fi
  if [ -f "$_ot_glwf" ]; then
    _ot_seen=$((_ot_seen + 1))
    _own_judge "$_ot_glwf" "$(_own_origin "$_ot_glwf" "$_ot_kit")" || _ot_rc=1
  fi
  if [ "$_ot_kit" = 1 ]; then  # SWAS-274: the kit's own PR-cancel lock (kit-tree guard; adopters carry no such block)
    check_line_breaks_tree "$_ot_root" || _ot_rc=1  # SWAS-447: first, so a hidden line break is named before any LF-split lock below is trusted
    for _ot_cw in ci.yml golden-path.yml; do
      # a missing file is skipped on purpose: golden-path-filter-parity.sh also treats an absent golden-path.yml as N/A
      [ -f "$_ot_root/.github/workflows/$_ot_cw" ] || continue
      check_pr_concurrency "$_ot_root/.github/workflows/$_ot_cw" || _ot_rc=1
    done
    check_runner_pins_tree "$_ot_root" || _ot_rc=1  # SWAS-306: the runner-pin lock (RP); kit trees only
    [ ! -f "$_ot_root/.github/workflows/ci.yml" ] || check_sast_parse_spans "$_ot_root/.github/workflows/ci.yml" || _ot_rc=1  # SWAS-278: the SAST-parse spans line (SP)
    [ ! -f "$_ot_root/.github/workflows/ci.yml" ] || check_guard_delta_step "$_ot_root/.github/workflows/ci.yml" || _ot_rc=1  # SWAS-301: the guard delta step (GD)
    [ ! -f "$_ot_root/.github/workflows/ci.yml" ] || check_boundary_redteam_step "$_ot_root/.github/workflows/ci.yml" || _ot_rc=1  # SWAS-359: the boundary red-team job (BR)
    [ ! -f "$_ot_root/.github/workflows/ci.yml" ] || check_h2_defer_step "$_ot_root/.github/workflows/ci.yml" || _ot_rc=1  # SWAS-376: the H2 step's battery defer (H2D)
    [ ! -f "$_ot_root/.github/workflows/ci.yml" ] || check_shard_join_shape "$_ot_root/.github/workflows/ci.yml" conformance-docs || _ot_rc=1  # SWAS-409: the docs shard (C30, C31) is graded live in every docs leg
    [ ! -f "$_ot_root/.github/workflows/ci.yml" ] || check_shard_join_shape "$_ot_root/.github/workflows/ci.yml" conformance-selftests || _ot_rc=1  # SWAS-409: the selftests shard (C31, C32)
  fi
  if [ "$_ot_seen" = 0 ]; then
    # The zero-found three-state (verify-enforced-wired.sh:845-849, copied).
    if [ "$_ot_must" = 1 ]; then
      echo "FAIL: a kit/incepted tree carries NO CI pipeline at all — looked for $_ot_ghwf and $_ot_glwf."
      echo "      Fail-closed: run scripts/incept.sh --ci <github|gitlab>, or add one by hand."
      return 1
    fi
    echo "N/A: ci-gates --own-tree — raw pre-incept export: no pipeline and no incepted/kit marker"
    echo "     (incept installs a pipeline; there is nothing to judge yet)."
    return 0
  fi
  if [ "$_ot_rc" = 0 ]; then
    echo "OK: ci-gates --own-tree — $_ot_seen pipeline(s) judged on $_ot_root (id presence is a"
    echo "    DECLARATION; execution is not attested — pair with the pipeline actually running)."
  fi
  return "$_ot_rc"
}

# ══ TIER0-LOCKS-OWED (b) — THE AGGREGATOR needs: / CLASSIFIER DRIFT-LOCK ═══════════════════════
# Discharges the boarded `AGGREGATOR-NEEDS-LOCK` disclosure (design §4b): the `conformance`
# aggregator's `needs:` list (ci.yml) and the classifier's `PG_NEEDED` constant
# (ci-classify-changes.sh) are hand-maintained mirrors of "every job that feeds the required
# `conformance` context", and a job added to one without the other runs, reds, and the required
# context stays green (or the reverse: a job the classifier still waits on but the aggregator
# forgot). Two legs, both structural (this file does not parse YAML — same ceiling as the rest of
# it):
#   (1) every job whose `if:` carries the docs-only/push-graded skip predicate (`push_graded` —
#       the superset; every such job also skips on docs-only except `conformance-docs`, which
#       skips on push-graded alone) is EITHER a member of the aggregator's `needs:` array OR
#       carries the literal per-job exemption marker on that SAME `if:` line. The marker is not a
#       hand list living in this file (that would carry the very drift this lock discharges) — it
#       is a string search on ci.yml itself, so the four deliberately-exempt jobs
#       (non-vacuity/artifact-gate/artifact-gate-gitlab/artifact-gate-brownfield — none a required
#       check, each a "a job-level skip is safe") stay exempt only as long as THEIR OWN if: line
#       says so.
#   (2) `PG_NEEDED` (∪ `conformance-docs`, − the literal `conformance` self-reference, which names
#       the aggregator job itself and is not a member of its own `needs:`) equals the aggregator's
#       `needs:` array, as SETS.
# A per-job step-count PIN on `conformance-core` (the job most churned) reds an unclassified step
# added there without updating this lock's constant — deliberately high-friction: the pin is meant
# to force a human look at the new step's `if:`, not to be silently bumped by a future edit.
# 28 -> 29 on 2026-09-17 (PREPUSH-CI-PARITY): the `prepush-lane census` step. THE LOOK THE PIN FORCES,
# recorded rather than silently bumped — the step carries NO step-level `if:` and is governed by
# conformance-core's job-level one (docs-only / push-graded skip), which is CORRECT for it: a
# docs-only change-set cannot have touched ci.yml, so there is no new mention for the census to grade.
_AGG_CC_STEP_PIN=29
_agg_marker='not a required check -> a job-level skip is safe'

# _agg_job_step_count <yml> <job> -> the count of top-level (6-space `- `) step entries under
# <job>, from its header line to the next 2-space-indented job header (or EOF).
_agg_job_step_count() {
  _ajs_yml="$1"; _ajs_job="$2"
  _ajs_start=$(grep -n "^  ${_ajs_job}:\$" "$_ajs_yml" | head -1 | cut -d: -f1)
  [ -n "$_ajs_start" ] || { echo -1; return; }
  _ajs_end=$(awk -v s="$_ajs_start" 'NR>s && /^  [A-Za-z0-9_-]+:$/{print NR; exit}' "$_ajs_yml")
  if [ -n "$_ajs_end" ]; then
    sed -n "${_ajs_start},$((_ajs_end - 1))p" "$_ajs_yml" | grep -c '^      - '
  else
    sed -n "${_ajs_start},\$p" "$_ajs_yml" | grep -c '^      - '
  fi
}

# aggregator_needs_lock <ci-yml> <ci-classify-changes.sh> -> rc0 iff both legs above hold.
aggregator_needs_lock() {
  _al_yml="$1"; _al_cls="$2"; _al_pin="${3:-$_AGG_CC_STEP_PIN}"
  { [ -f "$_al_yml" ] && [ -r "$_al_yml" ]; } || { echo "FAIL: aggregator-needs-lock — cannot read $_al_yml"; return 1; }
  { [ -f "$_al_cls" ] && [ -r "$_al_cls" ]; } || { echo "FAIL: aggregator-needs-lock — cannot read $_al_cls"; return 1; }

  # the ONE bracketed `needs: [...]` line — the conformance aggregator's, and the only job in this
  # file whose needs: is an array rather than a bare job name.
  _al_needs_n=$(grep -Ec '^ *needs: \[.*\]$' "$_al_yml")
  if [ "$_al_needs_n" -ne 1 ]; then
    echo "FAIL: aggregator-needs-lock — expected exactly one bracketed 'needs: [...]' line (the conformance aggregator's) in $_al_yml, found $_al_needs_n"
    return 1
  fi
  _al_needs_line=$(grep -E '^ *needs: \[.*\]$' "$_al_yml")
  _al_needs_raw=${_al_needs_line#*\[}; _al_needs_raw=${_al_needs_raw%%\]*}
  _al_needs_set=$(printf '%s' "$_al_needs_raw" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sort -u)

  # PG_NEEDED, minus the aggregator's own name (it is not a member of its own needs:), plus
  # conformance-docs (the CI-LANE-BY-CHANGE-CLASS shard the classifier does not itself gate).
  _al_pg_raw=$(grep -E "^PG_NEEDED='" "$_al_cls" | sed "s/^PG_NEEDED='//; s/'\$//")
  [ -n "$_al_pg_raw" ] || { echo "FAIL: aggregator-needs-lock — could not read PG_NEEDED from $_al_cls"; return 1; }
  _al_pg_set=$(printf '%s\n' $_al_pg_raw | grep -v '^conformance$')
  _al_pg_set=$(printf '%s\nconformance-docs\n' "$_al_pg_set" | grep -v '^$' | sort -u)

  _al_bad=0
  if [ "$_al_pg_set" != "$_al_needs_set" ]; then
    echo "FAIL: aggregator-needs-lock — PG_NEEDED (- conformance, + conformance-docs) != the aggregator's needs::"
    echo "  derived from PG_NEEDED: $(printf '%s' "$_al_pg_set" | tr '\n' ' ')"
    echo "  aggregator needs:       $(printf '%s' "$_al_needs_set" | tr '\n' ' ')"
    _al_bad=1
  fi

  # every job carrying the push-graded `if:` skip is in needs: or marked exempt on that same line.
  # AWK, not shell case-parsing (a job header can carry a trailing `# ...` comment on the SAME
  # line — `cf-doctor:            # 492s...` — which a plain `case '  '*:)` glob does not survive):
  # for each line containing `if:` and `push_graded`, print `<nearest-preceding-2-space-job>\t<line>`.
  _al_needs_sp=" $(printf '%s' "$_al_needs_set" | tr '\n' ' ') "
  _al_ifjobs_f=$(mktemp)
  awk '
    /^  [A-Za-z0-9_-]+:/ { j = $0; sub(/^  /, "", j); sub(/:.*/, "", j) }
    /if:/ && /push_graded/ { print j "\t" $0 }
  ' "$_al_yml" > "$_al_ifjobs_f"
  while IFS="$(printf '\t')" read -r _al_job _al_line; do
    [ -n "$_al_job" ] || continue
    case "$_al_needs_sp" in
      *" $_al_job "*) continue ;;                               # in needs: -> accounted for
    esac
    case "$_al_line" in
      *"$_agg_marker"*) continue ;;                             # marked exempt -> accounted for
    esac
    echo "FAIL: aggregator-needs-lock — job '$_al_job' carries the push-graded if: skip but is neither in the aggregator's needs: nor marked exempt ('$_agg_marker')"
    _al_bad=1
  done < "$_al_ifjobs_f"
  rm -f "$_al_ifjobs_f"

  # the step-count pin on conformance-core.
  _al_cc=$(_agg_job_step_count "$_al_yml" conformance-core)
  if [ "$_al_cc" != "$_al_pin" ]; then
    echo "FAIL: aggregator-needs-lock — conformance-core carries $_al_cc top-level steps, pinned at $_al_pin; a step was added or removed without updating this lock's constant (and, before that, without confirming the new step's if: is accounted for)"
    _al_bad=1
  fi

  # SWAS-281 TW1: the non-required ci-time-report job can never red a run (continue-on-error, a timeout, in no needs:, every run: line wrapped).
  check_ci_time_report "$_al_yml" >&2 || { echo "FAIL: aggregator-needs-lock — the ci-time-report job (TW1) is not never-red; see above"; _al_bad=1; }

  [ "$_al_bad" = 0 ] || return 1
  echo "OK: aggregator-needs-lock — needs:/PG_NEEDED match, every push-graded job is accounted for, conformance-core step count pinned at $_al_pin"
  return 0
}

# ══ SWAS-281 (CI-TIME-BUDGET) TW1 — the WARN job can never red a run ═════════════════════════════════════════
# `ci-time-report` annotates measured minutes with ::warning:: only (hosted-runner time is not a red gate). A run that is not `success`
# trips ci-classify-changes.sh's run-not-success rule on the next push's grading, so a time report that could fail would cost coverage
# routing. The wrapper in the script cannot catch a job timeout, a failed checkout or a lost runner: `continue-on-error: true` on the JOB
# does. This lock holds, on the job's comment-stripped text: (a) job-level continue-on-error: true, (b) a timeout-minutes, (c) the name
# appears nowhere outside its own block (so it is in no `needs:` and no required context), (d) every run: command line ends `|| :` or
# `|| true` and no line holds an `exit`, (e) no ::error::. An ABSENT job passes (a job that is not there cannot red a run); the selftest's
# real-tree leg (TW1r) is what requires it to exist in the kit's ci.yml. HONEST CEILING: line-based, not a YAML parser.
check_ci_time_report() {  # <workflow-file> -> 0 ok or job absent; 1 not never-red
  _tw_blk=$(extract_job_block "$1" ci-time-report | sed 's/#.*//')
  [ -n "$_tw_blk" ] || return 0
  _tw_bad=0
  if [ "$(printf '%s\n' "$_tw_blk" | grep -c '^    continue-on-error: true[[:space:]]*$')" != 1 ]; then
    echo "FAIL: $1 ci-time-report must carry job-level 'continue-on-error: true' exactly once (a timeout or lost runner would otherwise make the run's conclusion failure) (TW1)" >&2; _tw_bad=1
  fi
  if ! printf '%s\n' "$_tw_blk" | grep -Eq '^    timeout-minutes: [0-9]+[[:space:]]*$'; then
    echo "FAIL: $1 ci-time-report must carry a job-level timeout-minutes (TW1)" >&2; _tw_bad=1
  fi
  _tw_re='(needs:.*|^[[:space:]]*-[[:space:]]+)ci-time-report([^A-Za-z0-9_./-]|$)|needs\.ci-time-report'
  _tw_all=$(sed 's/#.*//' "$1" | grep -Ec "$_tw_re" || true)
  _tw_own=$(printf '%s\n' "$_tw_blk" | grep -Ec "$_tw_re" || true)
  if [ "$_tw_all" != "$_tw_own" ]; then
    echo "FAIL: $1 the name ci-time-report appears outside its own job ($_tw_all lines in the file, $_tw_own inside it): it must be in no needs: and no required context (TW1)" >&2; _tw_bad=1
  fi
  # (f) it reads every other job's time, so it must wait for every other job: each job id in the file is in its needs: (block list or inline).
  _tw_ids=$(sed 's/#.*//' "$1" | awk '/^jobs:[ \t]*$/ { inj = 1; next } /^[^ \t]/ { inj = 0 } inj && /^  [A-Za-z0-9_-]+:[ \t]*$/ { j = $1; sub(/:$/, "", j); if (j != "ci-time-report") print j }')
  _tw_need=$(printf '%s\n' "$_tw_blk" | awk '
    /^    needs:/ { v = $0; sub(/^    needs:[ \t]*/, "", v); if (v != "") { gsub(/[\[\],]/, " ", v); k = split(v, t, " "); for (i = 1; i <= k; i++) print t[i]; n = 0 } else n = 1; next }
    n && /^      - / { print $2; next }
    n && !/^      / { n = 0 }')
  for _tw_j in $_tw_ids; do
    case " $(printf '%s' "$_tw_need" | tr '\n' ' ') " in
      *" $_tw_j "*) : ;;
      *) echo "FAIL: $1 ci-time-report does not list job $_tw_j in its needs: (it reads every job's time, so it must wait for every job; add it) (TW1)" >&2; _tw_bad=1 ;;
    esac
  done
  if printf '%s\n' "$_tw_blk" | grep -q '::error'; then
    echo "FAIL: $1 ci-time-report emits ::error:: (it annotates with ::warning:: only) (TW1)" >&2; _tw_bad=1
  fi
  _tw_unw=$(printf '%s\n' "$_tw_blk" | awk '
    function ends_ok(s) { return (s ~ /\|\| (:|true)[ \t]*$/) }
    /^ *(- )?run:/ {
      ind = match($0, /[^ -]/) - 1; v = $0; sub(/^ *(- )?run:[ \t]*/, "", v); blk = 0
      if (v ~ /^[|>]/) { blk = 1; rind = ind; next }
      if (v != "" && (!ends_ok(v) || v ~ /(^|[^A-Za-z_-])exit([^A-Za-z_-]|$)/)) print NR ": " v
      next
    }
    blk { if ($0 ~ /^[ \t]*$/) next; cur = match($0, /[^ ]/) - 1; if (cur <= rind) { blk = 0 } else { if (!ends_ok($0) || $0 ~ /(^|[^A-Za-z_-])exit([^A-Za-z_-]|$)/) print NR ": " $0; next } }')
  if [ -n "$_tw_unw" ]; then
    printf '%s\n' "$_tw_unw" | while IFS= read -r _tw_l; do echo "FAIL: $1 ci-time-report has a command outside the || : wrapper, or an exit (job line $(printf '%s' "$_tw_l" | tr -d '[:cntrl:]')) (TW1)" >&2; done
    _tw_bad=1
  fi
  return "$_tw_bad"
}

# ══ SWAS-281 (CI-TIME-BUDGET) — `--count-legs [<root>]`: the runner jobs one full run starts ═══════════════════
# Read-only. For every .github/workflows/*.yml|*.yaml with a `pull_request`, `push` or `pull_request_target` trigger it prints
# `<workflow> <job> <legs>` per job, then `total <n>`; the conformance-mass-budget `jobs` surface reads the total. A job's legs are its
# matrix size: the product of the axis lengths plus its `include:` entries (an include that only extends an existing combination is
# counted too, an over-count the design discloses); 1 with no matrix. FAIL-CLOSED (rc 1, `FAIL: count-legs --` lines): a matrix or
# strategy that is an expression or otherwise unparseable; a reusable-workflow `uses:` job (its legs cannot be counted from this file);
# a `workflow_run` trigger anywhere; a `pull_request_target` trigger outside ONE allowlist entry keyed to the file AND the job id
# (D-240919-2(3): the tracker board gate), where the file may hold exactly one job that names pull_request_target and it must be
# that one; a counted file with no parsable job; no counted file at all. HONEST CEILING: line-based awk at the indents the kit's
# workflows use, not a YAML parser; a flow-style `jobs: {..}` or a matrix built by a template would FAIL closed, not count.
CL_PRIV_FILE="adopter-tracker-gates.yml"
CL_PRIV_JOB="tracker-board-gates"
_cl_scan() {  # <workflow-file> -> records on stdout: `T <trigger>`, `J <job> <legs>`, `U <job>`, `X <job>`, `P <job>`
  sed 's/#.*//' "$1" | LC_ALL=C awk '
    function flush_job(   sz, k) {
      if (job == "") return
      if (matrix) {
        if (expr) { print "X " job; job = ""; return }
        for (k = 1; k <= naxes; k++) if (cnt[k] < 1) { print "X " job; job = ""; return }
        if (naxes == 0 && inc == 0) { print "X " job; job = ""; return }
        sz = (naxes > 0) ? 1 : 0
        for (k = 1; k <= naxes; k++) sz *= cnt[k]
        sz += inc
      } else sz = 1
      print "J " job " " sz
      job = ""
    }
    /^[ \t]*$/ { next }
    /^[^ \t]/ {
      flush_job(); injobs = 0; inon = 0
      if ($0 ~ /^("on"|\047on\047|on):/) {
        inon = 1; v = $0; sub(/^[^:]*:[ \t]*/, "", v); gsub(/[\[\],]/, " ", v)
        n = split(v, t, /[ \t]+/); for (i = 1; i <= n; i++) if (t[i] != "") print "T " t[i]
        next
      }
      if ($0 ~ /^jobs:[ \t]*$/) injobs = 1
      next
    }
    inon {
      if ($0 ~ /^  [A-Za-z_]+:/) { k = $1; sub(/:.*/, "", k); print "T " k }
      else if ($0 ~ /^  - /) { print "T " $2 }
      next
    }
    injobs && /^  [A-Za-z0-9_-]+:[ \t]*$/ {
      flush_job(); job = $1; sub(/:$/, "", job)
      matrix = 0; inmatrix = 0; expr = 0; naxes = 0; inc = 0; cur = ""; pdone = 0; delete cnt
      next
    }
    injobs && job != "" {
      ind = match($0, /[^ ]/) - 1
      if (!pdone && $0 ~ /pull_request_target/) { print "P " job; pdone = 1 }
      if (ind == 4 && $0 ~ /^    uses:/) print "U " job
      if (ind == 4 && $0 ~ /^    if:/) { iv = $0; sub(/^    if:[ \t]*/, "", iv); sub(/[ \t]+$/, "", iv); print "I " job " " iv }
      if (ind == 4 && $0 ~ /^    strategy:[ \t]*[^ \t]/) { matrix = 1; expr = 1 }
      if (ind == 6 && $0 ~ /^      matrix:/) {
        matrix = 1; inmatrix = 1; v = $0; sub(/^      matrix:[ \t]*/, "", v); if (v != "") expr = 1
        next
      }
      if (inmatrix && ind <= 6) inmatrix = 0
      if (!inmatrix) next
      if (ind == 8 && $0 ~ /^        [A-Za-z0-9_-]+:/) {
        key = $1; sub(/:$/, "", key); v = $0; sub(/^        [A-Za-z0-9_-]+:[ \t]*/, "", v)
        if (key == "include") { cur = "include"; if (v != "") expr = 1 }
        else if (key == "exclude") { cur = "exclude" }
        else {
          cur = "axis"; naxes++; cnt[naxes] = 0
          if (v ~ /\$\{\{/) expr = 1
          else if (v ~ /^\[/) { s = v; gsub(/[\[\] \t]/, "", s); cnt[naxes] = (s == "") ? 0 : gsub(/,/, ",", s) + 1 }
          else if (v != "") expr = 1
        }
        next
      }
      if (ind >= 10 && $0 ~ /^ *- /) {
        if (cur == "axis") cnt[naxes]++
        else if (cur == "include") inc++
      }
    }
    END { flush_job() }'
}
count_legs_run() {  # <root> -> 0 ok; 1 a refusal (FAIL lines on stdout)
  _cl_root=${1:-.}; _cl_bad=0; _cl_tot=0; _cl_files=0
  for _cl_f in "$_cl_root"/.github/workflows/*.yml "$_cl_root"/.github/workflows/*.yaml; do
    [ -f "$_cl_f" ] || continue
    _cl_b=${_cl_f##*/}
    case "$_cl_b" in *[!A-Za-z0-9._-]*) echo "FAIL: count-legs -- a workflow file name is off-shape (want [A-Za-z0-9._-]+): [$(printf '%s' "$_cl_b" | tr -d '[:cntrl:]')]"; _cl_bad=1; continue ;; esac
    _cl_rec=$(_cl_scan "$_cl_f")
    _cl_tr=" $(printf '%s\n' "$_cl_rec" | sed -n 's/^T //p' | tr '\n' ' ') "
    case "$_cl_tr" in *" workflow_run "*) echo "FAIL: count-legs -- $_cl_b has a workflow_run trigger: it runs work this count cannot see, with the base's privileges (forbidden everywhere)"; _cl_bad=1; continue ;; esac
    _cl_priv=$(printf '%s\n' "$_cl_rec" | sed -n 's/^P //p')
    case "$_cl_tr" in *" pull_request_target "*)
      if [ "$_cl_b" != "$CL_PRIV_FILE" ]; then
        echo "FAIL: count-legs -- $_cl_b has a pull_request_target trigger and is not the one allowlisted file ($CL_PRIV_FILE, job $CL_PRIV_JOB; ruling D-240919-2(3)); a new privileged trigger is a deliberate control-plane edit"; _cl_bad=1; continue
      fi
      if [ "$_cl_priv" != "$CL_PRIV_JOB" ]; then
        echo "FAIL: count-legs -- $_cl_b must hold exactly one privileged (pull_request_target) job and it must be $CL_PRIV_JOB; found: [$(printf '%s' "$_cl_priv" | tr '\n' ' ' | tr -d '[:cntrl:]')]"; _cl_bad=1; continue
      fi
      # A job with NO job-level `if:` also runs on pull_request_target (a workflow-level trigger reaches every job), so every OTHER job in this
      # file must carry an `if:` that names only the schedule / workflow_dispatch events.
      _cl_ifs=$(printf '%s\n' "$_cl_rec" | sed -n 's/^I //p')
      _cl_fb=0
      for _cl_oj in $(printf '%s\n' "$_cl_rec" | sed -n 's/^J \([^ ]*\) .*/\1/p'); do
        [ "$_cl_oj" != "$CL_PRIV_JOB" ] || continue
        _cl_it=$(printf '%s\n' "$_cl_ifs" | sed -n "s/^$_cl_oj //p" | head -n 1)
        if [ -z "$_cl_it" ]; then
          echo "FAIL: count-legs -- $_cl_b job [$_cl_oj] has no job-level if: and so also runs on pull_request_target; every job in the allowlisted file other than $CL_PRIV_JOB must name only schedule or workflow_dispatch"; _cl_fb=1; continue
        fi
        if ! printf '%s' "$_cl_it" | LC_ALL=C grep -qE "^github\.event_name == '(schedule|workflow_dispatch)'( \|\| github\.event_name == '(schedule|workflow_dispatch)')*\$"; then
          echo "FAIL: count-legs -- $_cl_b job [$_cl_oj] has an if: that does not name only schedule or workflow_dispatch (privileged-trigger reach)"; _cl_fb=1
        fi
      done
      if [ "$_cl_fb" -ne 0 ]; then _cl_bad=1; continue; fi ;;
    esac
    case "$_cl_tr" in *" pull_request "*|*" push "*|*" pull_request_target "*) : ;; *) continue ;; esac
    _cl_files=$((_cl_files + 1)); _cl_njobs=0
    _cl_u=$(printf '%s\n' "$_cl_rec" | sed -n 's/^U //p')
    if [ -n "$_cl_u" ]; then echo "FAIL: count-legs -- $_cl_b job [$(printf '%s' "$_cl_u" | tr '\n' ' ')] is a reusable-workflow uses: job: its legs cannot be counted from this file"; _cl_bad=1; continue; fi
    _cl_x=$(printf '%s\n' "$_cl_rec" | sed -n 's/^X //p')
    if [ -n "$_cl_x" ]; then echo "FAIL: count-legs -- $_cl_b job [$(printf '%s' "$_cl_x" | tr '\n' ' ')] has a matrix or strategy that is an expression or cannot be parsed: its legs cannot be counted (never 1)"; _cl_bad=1; continue; fi
    _cl_jl=$(printf '%s\n' "$_cl_rec" | sed -n 's/^J //p')
    _cl_njobs=$(printf '%s\n' "$_cl_jl" | grep -c '[^[:space:]]' || true)
    printf '%s\n' "$_cl_jl" | awk -v f="$_cl_b" 'NF == 2 { print f " " $1 " " $2 }'
    _cl_tot=$((_cl_tot + $(printf '%s\n' "$_cl_jl" | awk 'NF == 2 { t += $2 } END { print t + 0 }')))
    if [ "$_cl_njobs" -eq 0 ]; then echo "FAIL: count-legs -- $_cl_b has a pull_request/push trigger but no parsable job: a zero reading is a broken counter, not a free workflow"; _cl_bad=1; fi
  done
  if [ "$_cl_files" -eq 0 ]; then echo "FAIL: count-legs -- no workflow with a pull_request or push trigger under $_cl_root/.github/workflows (a zero reading is a broken counter)"; _cl_bad=1; fi
  [ "$_cl_bad" -eq 0 ] || return 1
  echo "total $_cl_tot"
  return 0
}

# ══ SWAS-409 (CI-SHAPING S4) — C30/C31/C32: THE SHARD JOINS ════════════════════════════════════════════════════
# `conformance-selftests` (n = 4) and `conformance-docs` (n = 2) run as static non-matrix legs `<join>-1..n` and a JOIN that keeps the old job name,
# so the aggregator, PG_NEEDED and branch protection are untouched. `--shard-join <join> "$LEG_RESULTS" [<workflow>]` is the join's first step:
#   C31  the structure holds: legs named <join>-1..n (n >= 2) each once; the join's needs: is a BLOCK list of exactly `changes` plus the legs; the
#        job-level env LEG_RESULTS names each leg's needs.<leg>.result once, in order (job level, never step level: a job-level ${{ }} env makes
#        prepush-lane.sh turn every join step into a context line, which keeps its --derive parity exact); the join runs under !cancelled(); and
#        NOTHING IN A LEG CAN LET A MEMBER'S FAILURE READ AS SUCCESS (the lock class of BR19 above): no step-level if:, no step- or job-level
#        continue-on-error (a job-level one reports `success`), no matrix, no custom shell (a step `shell:` or a job- or workflow-level
#        `defaults: run: shell:` other than exactly bash or sh; `bash {0}` drops -e, so a multi-command step would grade only its last command), no
#        GITHUB_ENV / BASH_ENV / GITHUB_PATH in a leg (T0: the install trio writes none, so the lock bans them everywhere, stricter than "outside
#        the prologue" with the same verdict on the real tree), no BASH_ENV or ENV key in an env: map at workflow, job or step level (bash sources
#        it before every step, so it could `set +e`). Selftest legs 2-n carry a BYTE COPY of leg 1's install trio.
#        Then every leg result must be `success`, and an IN-RUN NEGATIVE runs the same predicate on a synthesised `success skipped ...` and requires a RED.
#   C30  docs: the legs hold exactly the pinned member count (steps minus the checkout and jq prologue), no member twice, none byte-equal to a step
#        of a non-leg job, no leg without a member. CEILING: weaker than C29 — a step swapped at the same count, and an in-place edit of a member's
#        run text, pass; both rest on review.
#   C32  (selftests) the join's `Battery complete (gate-test)` is its LAST step, after the shard-join and --legs steps, and no leg carries a
#        gate-test id: reaching it attests every join check, which attest every leg (extends OT15 in the KIT section of the selftest).
# HONEST CEILING: line-based awk at the indents the kit's workflows use (jobs at 2, steps at 6, step keys at 8), the same as the rest of this file; it
# is not a YAML parser. extract_job_block is the one extractor (no second parser); _sj_blk only cuts its output at a job header that carries a comment.
_SJ_DOCS_PIN=59   # T0 (SWAS-409 plan §2.6): the 61 docs steps minus the checkout and the jq probe. Adding or removing a docs step reds until this moves, by a deliberate control-plane edit.
_sj_marker='not a required check -> a job-level skip is safe'
_sj_fail() { echo "FAIL: shard-join — $*"; _sj_bad=1; }
_sj_blk() {  # <wf> <job> -> the job's lines, cut at the next 2-space job header even when that header carries a trailing comment
  extract_job_block "$1" "$2" | awk 'NR == 1 { print; next } /^  [A-Za-z0-9_-]+:([ \t]|$)/ { exit } { print }'
}
_sj_code() { grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' || :; }   # code lines only: no comment-only and no blank lines
_sj_nk() { sed -E "s/^( *(- )?)[\"']([A-Za-z0-9_.-]+)[\"'][[:space:]]*:/\1\3:/"; }   # S-M1/S-M2: a quoted mapping key ("if": false) reads as the bare key, so no lock below is escaped by quoting it
_sj_noalias() {  # <label> <normalised code lines> -> a FAIL when a merge key or an alias could hide a key from the locks (the line-based reader cannot expand either)
  printf '%s\n' "$2" | grep -Eq '^ *(- )?<<[[:space:]]*:|:[[:space:]]+\*[A-Za-z0-9_-]+[[:space:]]*(#.*)?$|^ *- \*[A-Za-z0-9_-]+' && _sj_fail "$1 uses a YAML merge key or alias, which the line-based locks cannot expand (write the keys out)"
  return 0
}
_sj_locks() {  # <label: leg X | join X> <normalised code lines> -> a FAIL per way to make a step's failure read as success or change how a later step runs (one body for a leg and a join)
  printf '%s\n' "$2" | grep -Eq '^(        |      - )if[[:space:]]*:' && _sj_fail "$1 carries a step-level if: (a skipped member reads as success)"
  printf '%s\n' "$2" | grep -Eq '^    continue-on-error[[:space:]]*:' && _sj_fail "$1 carries a job-level continue-on-error (the job reports success whatever failed)"
  printf '%s\n' "$2" | grep -Eq '^(        |      - )continue-on-error[[:space:]]*:' && _sj_fail "$1 carries a step-level continue-on-error (it masks that step)"
  for _sjl_sh in $(_sj_shells "$2" S); do
    case "$_sjl_sh" in bash|sh) : ;; *) _sj_fail "$1 has a custom shell on a step ($_sjl_sh): a template such as 'bash {0}' drops -e, so a multi-command step would grade only its last command" ;; esac
  done
  for _sjl_sh in $(_sj_shells "$2" D); do
    case "$_sjl_sh" in bash|sh) : ;; *) _sj_fail "$1 has a custom shell in its job-level defaults ($_sjl_sh): it applies to every step, and a template such as 'bash {0}' drops -e" ;; esac
  done
  printf '%s\n' "$2" | grep -Eq 'GITHUB_ENV|BASH_ENV|GITHUB_PATH' && _sj_fail "$1 names GITHUB_ENV, BASH_ENV or GITHUB_PATH: it may not change how a later step runs or what it inherits"
  printf '%s\n' "$2" | grep -Eq '^ +ENV[[:space:]]*:' && _sj_fail "$1 sets an ENV key in an env: map: bash sources it before every step"
  return 0
}
_sj_errexit() {  # <label> <leg code lines> -> a FAIL when a leg's run text switches errexit off or ends a step in a bare exit 0 (S-L1/R-M1: either lets a failed member read as success)
  printf '%s\n' "$2" | grep -Eq '^[[:space:]]*(- )?(run:[[:space:]]*)?set([[:space:]]+[-+][A-Za-z]+)*[[:space:]]+\+[A-Za-z]*e[A-Za-z]*([[:space:];&]|$)|^[[:space:]]*(- )?(run:[[:space:]]*)?set[[:space:]]+\+o[[:space:]]+errexit' && _sj_fail "$1 switches errexit off with set +e: a failing member would not fail the step"
  printf '%s\n' "$2" | grep -Eq '^[[:space:]]*(- )?(run:[[:space:]]*)?exit 0[[:space:]]*(#.*)?$' && _sj_fail "$1 carries a bare exit 0: the step reads as success whatever ran before it"
  return 0
}
_sj_allow() {  # <label> <join|leg> <job block, raw> <wf> <job> -> a FAIL per line whose shape is not on the allow-list (option A: an allow-list, not pattern-chasing)
  # Allowed: a comment or blank; a run block body (deeper than its run: key; also no command may start with trap, shopt, set +e/+o or a bare exit 0); and
  # the bare keys of the measured set: job 4 needs/if/runs-on/steps/env, job env 6 LEG_RESULTS (join), step start 6 name/uses, step 8 env/id/run/uses/with,
  # 10 GH_TOKEN/fetch-depth/node-version, a needs item 6. A value may not open with { [ ! & * | > (a block header only on run), a quote must close on its line.
  _sja_b=$(grep -n -m 1 -E "^  $5:([[:space:]]|\$)" "$4" | cut -d: -f1)
  _sja_o=$(printf '%s\n' "$3" | awk -v lab="$1" -v kind="$2" -v base="${_sja_b:-1}" '
    function bad(why) { printf "FAIL: shard-join — %s line %d: %s: %s\n", lab, base + NR - 1, why, substr($0, 1, 80); n++ }
    function shape(v) {  # 1 = a value that may stand, 2 = a block-scalar header, 0 = not allowed
      sub(/^[ \t]+/, "", v)
      if (v ~ /^#/) return 1
      if (v ~ /^"/) return (v ~ /^"([^"\\]|\\.)*"([ \t]+#.*)?$/)
      if (v ~ /^\047/) return (v ~ ("^\047([^\047]|\047\047)*\047([ \t]+#.*)?$"))
      sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
      if (v ~ /^[|>][-+0-9]*$/) return 2
      return (v !~ /^[{\[!&*|>]/)
    }
    function key(t, set) { k = t; sub(/:.*$/, "", k); return (t ~ /^[A-Za-z_][A-Za-z0-9_-]*:([ \t]|$)/ && index(" " set " ", " " k " ")) }
    NR == 1 { if ($0 !~ /^  [a-z0-9-]+:[ \t]*(#.*)?$/) bad("line shape not in the allow-list"); next }
    blk {
      if ($0 ~ /^[ \t]*$/) next
      match($0, /^ */)
      if (RLENGTH > 8) {
        t = substr($0, RLENGTH + 1)
        if (t ~ /^trap([ \t]|$)/ || t ~ /^shopt([ \t]|$)/ || t ~ /^set[ \t]+([^#]*[ \t])?\+[A-Za-z]*[eo]/ || t ~ /^exit[ \t]+0([ \t;&|#]|$)/) bad("block-scalar content may not start a command with trap, shopt, set +e/+o or a bare exit 0")
        next
      }
      blk = 0
    }
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    {
      match($0, /^ */); ind = RLENGTH; t = substr($0, ind + 1); ok = 0; v = t; sub(/^[^:]*:/, "", v)
      if (ind == 4 && key(t, "needs if runs-on steps env")) { ctx = k; ok = shape(v) }
      else if (ind == 6 && t ~ /^- /) {
        item = substr(t, 3); iv = item; sub(/^[^:]*:/, "", iv)
        if (ctx == "needs") ok = (item ~ /^[a-z0-9-]+[ \t]*(#.*)?$/)
        else if (ctx == "steps" && key(item, "name uses")) ok = shape(iv)
      }
      else if (ind == 6 && ctx == "env" && kind == "join" && key(t, "LEG_RESULTS")) ok = shape(v)
      else if (ind == 8 && key(t, "env id run uses with")) { ok = shape(v); if (ok == 2 && k != "run") ok = 0; if (ok == 2) blk = 1 }
      else if (ind == 10 && key(t, "GH_TOKEN fetch-depth node-version")) ok = shape(v)
      if (ok == 0) bad("line shape not in the allow-list")
    }
    END { exit 0 }')
  [ -z "$_sja_o" ] || { printf '%s\n' "$_sja_o"; _sj_bad=1; }
  return 0
}
_sj_join_steps() {  # <wf> <join> <shard-join line> <legs line|-> -> ok | bad: the join's steps are EXACTLY the checkout, the shard-join call, (selftests) the --legs call, (selftests) gate-test (R-I1)
  _sj_steps "$1" "$2" | cut -f3 | awk -F'~' -v c1="$3" -v c2="$4" '
    { n = NR }
    NR == 1 { bad += !($0 ~ /^      - uses: actions\/checkout@/ && NF == 1); next }
    NR == 2 { bad += !(NF == 2 && $1 ~ /^      - name:/ && $2 == c1); next }
    NR == 3 && c2 != "-" { bad += !(NF == 2 && $1 ~ /^      - name:/ && $2 == c2); next }
    NR == 4 && c2 != "-" { bad += !(NF == 3 && $1 ~ /^      - name:/ && $2 == "        id: gate-test" && $3 ~ /^        run:/); next }
    { bad++ }
    END { if (n != (c2 == "-" ? 2 : 4)) bad++; print (bad ? "bad" : "ok") }'
}
_sj_legs() {  # <wf> <join> -> the leg job keys <join>-<digits>, in file order
  sed 's/#.*//' "$1" | awk -v j="$2" '$0 ~ ("^  " j "-[0-9]+:[ \t]*$") { k = $1; sub(/:$/, "", k); print k }'
}
_sj_steps() {  # <wf> <job> -> one record per step: name TAB id TAB key; key = the step's code lines joined with ~ (comments and blanks dropped)
  _sj_blk "$1" "$2" | awk '
    function flush() { if (instep) printf "%s\t%s\t%s\n", sname, sid, key; instep = 0; sname = ""; sid = ""; key = "" }
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    /^    steps:([ \t]|$)/ { st = 1; next }   # a needs: list is 6-space dash lines too: only what follows steps: is a step
    !st { next }
    /^      - / { flush(); instep = 1 }
    instep {
      key = key (key == "" ? "" : "~") $0
      l = $0; sub(/^      - /, "        ", l)
      if (l ~ /^        name:/) { v = l; sub(/^        name:[ \t]*/, "", v); sub(/[ \t]+$/, "", v); sname = v }
      if (l ~ /^        id:/) { v = l; sub(/^        id:[ \t]*/, "", v); sub(/[ \t]+$/, "", v); sid = v }
    }
    END { flush() }'
}
_sj_trio_key() {  # <wf> <leg> <name-prefix> -> the key of the leg's first step whose name starts with the prefix
  _sj_steps "$1" "$2" | awk -F'\t' -v p="$3" 'index($1, p) == 1 { print $3; exit }'
}
_sj_shells() {  # <leg code lines> <S|D> -> the `shell:` values (spaces as ~), S = on a step (any indent but inside defaults:), D = inside the job-level defaults: block
  printf '%s\n' "$1" | awk -v want="$2" '
    /^    defaults[ \t]*:/ { ind = 1; next }
    ind && /^    [^ ]/ { ind = 0 }
    /^ *(- )?shell[ \t]*:/ {
      v = $0; sub(/^ *(- )?shell[ \t]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v); gsub(/["\047]/, "", v); gsub(/ /, "~", v)
      if ((ind ? "D" : "S") == want) print v
    }'
}
_sj_results() {  # <legs: space list> <results: space list> -> 0 only with exactly one `success` per leg; names each break
  _sr_rc=0
  if [ -z "$(printf '%s' "$2" | tr -d ' ')" ]; then echo "FAIL: shard-join — no leg results (an empty LEG_RESULTS adjudicated nothing)"; return 1; fi
  _sr_nl=$(printf '%s\n' $1 | grep -c .)
  _sr_nr=$(printf '%s\n' $2 | grep -c .)
  if [ "$_sr_nr" -ne "$_sr_nl" ]; then echo "FAIL: shard-join — $_sr_nr results for $_sr_nl legs (a leg's result is missing or extra)"; return 1; fi
  set -- $1 -- $2
  _sr_legs=""
  while [ "$1" != -- ]; do _sr_legs="$_sr_legs $1"; shift; done
  shift
  for _sr_leg in $_sr_legs; do
    if [ "$1" != success ]; then echo "FAIL: shard-join — leg $_sr_leg reported '$1'"; _sr_rc=1; fi
    shift
  done
  return "$_sr_rc"
}
check_shard_join_shape() {  # <workflow> <join> [<docs-pin>] -> 0 sound; 1 with each break printed as a `FAIL: shard-join — ...` line on stdout
  _sj_wf=$1; _sj_join=$2; _sj_pin=${3:-$_SJ_DOCS_PIN}; _sj_bad=0
  [ -f "$_sj_wf" ] || { _sj_fail "workflow not found: $_sj_wf"; return 1; }
  _sj_ll=$(_sj_legs "$_sj_wf" "$_sj_join")
  if [ -z "$_sj_ll" ]; then _sj_fail "no leg jobs named $_sj_join-<n> in $_sj_wf (a join with no legs grades nothing)"; return 1; fi
  _sj_n=$(printf '%s\n' "$_sj_ll" | grep -c .)
  [ "$_sj_n" -ge 2 ] || _sj_fail "$_sj_join has $_sj_n leg: at least 2 are needed (one leg is not a shard)"
  _sj_i=1
  for _sj_l in $_sj_ll; do
    [ "$_sj_l" = "$_sj_join-$_sj_i" ] || _sj_fail "leg jobs must be named $_sj_join-1..$_sj_n, each once, in order (found $_sj_l at position $_sj_i)"
    _sj_i=$((_sj_i + 1))
  done
  _sj_jb=$(_sj_blk "$_sj_wf" "$_sj_join")
  if [ -z "$_sj_jb" ]; then _sj_fail "no join job $_sj_join in $_sj_wf"; return 1; fi
  _sj_jc=$(printf '%s\n' "$_sj_jb" | _sj_code | _sj_nk)
  _sj_noalias "join $_sj_join" "$_sj_jc"
  _sj_allow "join $_sj_join" join "$_sj_jb" "$_sj_wf" "$_sj_join"
  # the join's needs: is a block list of exactly `changes` plus the legs
  if ! printf '%s\n' "$_sj_jc" | grep -q '^    needs:[[:space:]]*$'; then
    _sj_fail "the join's needs: must be a block list (needs: then one '- <job>' line each), naming changes and every leg"
  else
    _sj_nd=$(printf '%s\n' "$_sj_jc" | awk '/^    needs:[ \t]*$/ { n = 1; next } n && /^      - / { v = $0; sub(/^      - /, "", v); sub(/[ \t]+$/, "", v); print v; next } n { exit }')
    for _sj_x in changes $_sj_ll; do
      printf '%s\n' "$_sj_nd" | grep -qx -- "$_sj_x" || _sj_fail "the join's needs: lacks $_sj_x"
    done
    for _sj_x in $_sj_nd; do
      case " changes $(printf '%s' "$_sj_ll" | tr '\n' ' ') " in
        *" $_sj_x "*) : ;;
        *) _sj_fail "the join's needs: names $_sj_x, which is neither changes nor a leg" ;;
      esac
    done
  fi
  # LEG_RESULTS: ONE key, at JOB level (6-space entry under a 4-space env:), naming each leg's result once, in leg order, and nothing else
  if [ "$(printf '%s\n' "$_sj_jc" | grep -c 'LEG_RESULTS[[:space:]]*:')" -ne 1 ]; then
    _sj_fail "LEG_RESULTS must be declared exactly once, as a JOB-level env of the join (a step-level one leaves the join's other steps deriving into the local pre-push lane)"
  fi
  _sj_lr=$(printf '%s\n' "$_sj_jc" | awk '/^    env:[ \t]*$/ { e = 1; next } e && /^      LEG_RESULTS:/ { v = $0; sub(/^      LEG_RESULTS:[ \t]*/, "", v); print v; exit } e && !/^      / { exit }')
  if [ -z "$_sj_lr" ]; then
    _sj_fail "LEG_RESULTS must be a job-level env of the join (env: at 4 spaces, LEG_RESULTS at 6), not a step-level one"
  else
    _sj_got=$(printf '%s\n' "$_sj_lr" | grep -o 'needs\.[A-Za-z0-9_-]*\.result' | tr '\n' ' ')
    _sj_want=""
    for _sj_x in $_sj_ll; do _sj_want="${_sj_want}needs.$_sj_x.result "; done
    [ "$_sj_got" = "$_sj_want" ] || _sj_fail "LEG_RESULTS must name each leg's needs.<leg>.result exactly once, in leg order (got: ${_sj_got:-none}; want: $_sj_want)"
    _sj_rest=$(printf '%s\n' "$_sj_lr" | sed 's/\${{[[:space:]]*needs\.[A-Za-z0-9_-]*\.result[[:space:]]*}}//g; s/"//g' | tr -d ' ')
    [ -z "$_sj_rest" ] || _sj_fail "LEG_RESULTS may hold only the needs.<leg>.result expressions (found extra text: $_sj_rest)"
  fi
  # the join runs even when a leg failed or was cancelled (the explicit LEG_RESULTS check then reds by name)
  printf '%s\n' "$_sj_jc" | grep -E '^    if:' | sed 's/[[:space:]]#.*//' | grep -qF '!cancelled()' || _sj_fail "the join's if: must carry !cancelled() (so a failed leg reds the join by name instead of skipping it)"
  # the join's steps: the shard-join call (it carries the in-run negative) first, then (selftests) the partition check, then gate-test last
  _sj_c1="        run: sh conformance/ci-gates.sh --shard-join $_sj_join \"\$LEG_RESULTS\""
  if [ "$(printf '%s\n' "$_sj_jc" | grep -c -x -F -- "$_sj_c1")" -ne 1 ]; then
    _sj_fail "the join must run, as a one-line step, exactly: sh conformance/ci-gates.sh --shard-join $_sj_join \"\$LEG_RESULTS\" (that call carries the in-run negative)"
  fi
  # R-I1: the join's step list is EXACT (a masked or extra step would let the join green without attesting the legs), and the join gets the leg locks
  _sj_c2l=-; [ "$_sj_join" = conformance-selftests ] && _sj_c2l="        run: sh conformance/ci-selftest-coverage.sh --legs $_sj_join"
  [ "$(_sj_join_steps "$_sj_wf" "$_sj_join" "$_sj_c1" "$_sj_c2l")" = ok ] || _sj_fail "the join's step list must be exactly: the checkout, the shard-join call$([ "$_sj_c2l" = - ] || echo ', the --legs call, gate-test (id gate-test)') and nothing else, each a single run or uses (no extra step, no with:/env:)"
  _sj_locks "join $_sj_join" "$_sj_jc"
  printf '%s\n' "$_sj_jc" | grep -Eq '^        env[[:space:]]*:' && _sj_fail "join $_sj_join carries a step-level env: (the join's inputs are its job-level env and nothing else)"
  if [ "$_sj_join" = conformance-selftests ]; then
    _sj_c2="        run: sh conformance/ci-selftest-coverage.sh --legs $_sj_join"
    [ "$(printf '%s\n' "$_sj_jc" | grep -c -x -F -- "$_sj_c2")" -eq 1 ] || _sj_fail "the join must run, as a one-line step, exactly: sh conformance/ci-selftest-coverage.sh --legs $_sj_join (the selftest partition)"
    _sj_n1=$(printf '%s\n' "$_sj_jc" | grep -n -x -F -- "$_sj_c1" | head -n 1 | cut -d: -f1)
    _sj_n2=$(printf '%s\n' "$_sj_jc" | grep -n -x -F -- "$_sj_c2" | head -n 1 | cut -d: -f1)
    _sj_n3=$(printf '%s\n' "$_sj_jc" | grep -n -E '^        id:[[:space:]]*gate-test[[:space:]]*$' | head -n 1 | cut -d: -f1)
    _sj_gt=$(_sj_steps "$_sj_wf" "$_sj_join" | awk -F'\t' '$2 == "gate-test" { c++ } END { print c + 0 }')
    _sj_last=$(_sj_steps "$_sj_wf" "$_sj_join" | tail -n 1 | cut -f2)
    if [ "$_sj_gt" -ne 1 ] || [ "$_sj_last" != gate-test ]; then
      _sj_fail "gate-test must be the last step of the join, exactly once (reaching it attests the shard-join and partition steps above it, which attest every leg; gate-test steps: $_sj_gt, last step id: ${_sj_last:-none})"
    elif [ -n "$_sj_n1" ] && [ -n "$_sj_n2" ] && { [ "$_sj_n1" -gt "$_sj_n3" ] || [ "$_sj_n2" -gt "$_sj_n3" ]; }; then
      _sj_fail "gate-test must come after the shard-join and --legs steps it attests"
    fi
    for _sj_l in $_sj_ll; do
      _sj_steps "$_sj_wf" "$_sj_l" | awk -F'\t' '$2 == "gate-test" { f = 1 } END { exit !f }' && _sj_fail "leg $_sj_l carries id: gate-test, which belongs to the join (a leg-level gate-test attests only that leg)"
    done
  fi
  # workflow-level surface: a custom shell, or a BASH_ENV / ENV key in an env: map, applies to every leg
  _sj_top=$(awk '/^jobs:/ { exit } { print }' "$_sj_wf" | _sj_code | _sj_nk)
  for _sj_sh in $(printf '%s\n' "$_sj_top" | sed -n 's/^ *shell:[[:space:]]*//p' | sed "s/[[:space:]]*\$//; s/[\"']//g" | tr ' ' '~'); do
    case "$_sj_sh" in bash|sh) : ;; *) _sj_fail "the workflow-level defaults set a custom shell ($_sj_sh): a template such as 'bash {0}' drops -e, so a multi-command leg step would grade only its last command" ;; esac
  done
  printf '%s\n' "$_sj_top" | grep -Eq '^ +(BASH_ENV|ENV)[[:space:]]*:|BASH_ENV' && _sj_fail "the workflow-level env names BASH_ENV or ENV: bash sources it before every step, so it could turn off -e for every leg"
  # per leg: nothing may let a member's failure read as success
  for _sj_l in $_sj_ll; do
    _sj_lb=$(_sj_blk "$_sj_wf" "$_sj_l"); _sj_lc=$(printf '%s\n' "$_sj_lb" | _sj_code | _sj_nk)
    printf '%s\n' "$_sj_lb" | grep -E '^    if:' | grep -qF -- "$_sj_marker" || _sj_fail "leg $_sj_l: its job-level if: lacks the marker '$_sj_marker' on the same line (the aggregator lock needs it)"
    printf '%s\n' "$_sj_lc" | grep -Eq '^    strategy[[:space:]]*:' && _sj_fail "leg $_sj_l is a matrix (strategy:): legs are static job keys, because a matrix job disqualifies every step from the local pre-push lane"
    _sj_noalias "leg $_sj_l" "$_sj_lc"
    _sj_allow "leg $_sj_l" leg "$_sj_lb" "$_sj_wf" "$_sj_l"
    _sj_locks "leg $_sj_l" "$_sj_lc"
    _sj_errexit "leg $_sj_l" "$_sj_lc"
  done
  # selftests: legs 2-n carry a byte copy of leg 1's install trio (the three steps that change the runner for every later step)
  if [ "$_sj_join" = conformance-selftests ]; then
    for _sj_p in "Install Node 24" "Install the sandbox's Linux prerequisites" "Allow unprivileged user namespaces"; do
      _sj_k1=$(_sj_trio_key "$_sj_wf" "$_sj_join-1" "$_sj_p")
      if [ -z "$_sj_k1" ]; then _sj_fail "leg $_sj_join-1 lacks the install trio step '$_sj_p...'"; continue; fi
      _sj_i=1
      for _sj_l in $_sj_ll; do
        if [ "$_sj_i" -gt 1 ]; then
          _sj_ki=$(_sj_trio_key "$_sj_wf" "$_sj_l" "$_sj_p")
          if [ -z "$_sj_ki" ]; then _sj_fail "leg $_sj_l lacks the install trio step '$_sj_p...' (every later member would run on a different runner than it did before the split)"
          elif [ "$_sj_ki" != "$_sj_k1" ]; then _sj_fail "leg $_sj_l's install trio step '$_sj_p...' differs from leg $_sj_join-1's (it must be a byte copy)"; fi
        fi
        _sj_i=$((_sj_i + 1))
      done
    done
  fi
  # docs (C30): the pinned member count, no duplicate, no foreign member, no empty leg
  if [ "$_sj_join" = conformance-docs ]; then
    _sj_all=""; _sj_tot=0
    for _sj_l in $_sj_ll; do
      _sj_mem=$(_sj_steps "$_sj_wf" "$_sj_l" | awk -F'\t' '!(index($1, "jq available") == 1 || $3 ~ /uses: actions\/checkout/)')
      _sj_cnt=$(printf '%s' "$_sj_mem" | grep -c . || :)
      [ "$_sj_cnt" -gt 0 ] || _sj_fail "empty leg: $_sj_l has no member step beyond the checkout and jq prologue"
      _sj_tot=$((_sj_tot + _sj_cnt))
      _sj_all=$(printf '%s\n%s' "$_sj_all" "$_sj_mem")
    done
    [ "$_sj_tot" -eq "$_sj_pin" ] || _sj_fail "the docs legs hold $_sj_tot member steps, the pin is $_sj_pin (a docs step was added or removed: move _SJ_DOCS_PIN by a deliberate control-plane edit, or restore the step)"
    _sj_dup=$(printf '%s\n' "$_sj_all" | grep . | cut -f3 | sort | uniq -d | head -n 1)
    [ -z "$_sj_dup" ] || _sj_fail "duplicate member step in the docs legs: $(printf '%s' "$_sj_dup" | cut -c1-120)"
    _sj_jobs=$(sed 's/#.*//' "$_sj_wf" | awk '/^jobs:[ \t]*$/ { inj = 1; next } /^[^ \t]/ { inj = 0 } inj && /^  [A-Za-z0-9_-]+:[ \t]*$/ { j = $1; sub(/:$/, "", j); print j }')
    _sj_kf=$(mktemp)
    for _sj_o in $_sj_jobs; do
      case " $(printf '%s' "$_sj_ll" | tr '\n' ' ') $_sj_join " in *" $_sj_o "*) continue ;; esac
      _sj_steps "$_sj_wf" "$_sj_o" | cut -f3 | grep . > "$_sj_kf" || :
      [ -s "$_sj_kf" ] || continue
      _sj_hit=$(printf '%s\n' "$_sj_all" | grep . | cut -f3 | grep -x -F -f "$_sj_kf" | head -n 1 || :)
      [ -z "$_sj_hit" ] || _sj_fail "foreign member: a docs leg step is byte-equal to a step of job $_sj_o: $(printf '%s' "$_sj_hit" | cut -c1-120)"
    done
    rm -f "$_sj_kf"
  fi
  return "$_sj_bad"
}
shard_join_run() {  # <join> <results> [<workflow> [<docs-pin>]] -> the join's first step (CI passes only the first two; the rest is for the selftest's fixtures)
  _sr_wf=${3:-$(dirname "$0")/../.github/workflows/ci.yml}
  check_line_breaks "$_sr_wf" || return 1  # SWAS-447: a hidden line break blinds the LF-split allow-list below; never inside check_shard_join_shape (own_tree_run calls that too)
  check_shard_join_shape "$_sr_wf" "$1" "${4:-}" || return 1
  _sr_ls=$(_sj_legs "$_sr_wf" "$1" | tr '\n' ' ')
  _sj_results "$_sr_ls" "$2" || return 1
  # IN-RUN NEGATIVE: a leg-result predicate that always passes would green every broken run. Re-run it on a synthesised result list with the
  # second leg `skipped` and require a RED.
  _sr_neg=""; _sr_i=1
  for _sr_l in $_sr_ls; do
    if [ "$_sr_i" -eq 2 ]; then _sr_neg="$_sr_neg skipped"; else _sr_neg="$_sr_neg success"; fi
    _sr_i=$((_sr_i + 1))
  done
  _sr_neg=${_sr_neg# }
  if _sj_results "$_sr_ls" "$_sr_neg" >/dev/null; then
    echo "FAIL: shard-join — the in-run negative accepted a synthesised skipped leg ($_sr_neg): the leg-result predicate is vacuous"; return 1
  fi
  echo "in-run negative: '$_sr_neg' reds, as required"
  echo "OK: shard-join $1 — $(printf '%s\n' $_sr_ls | grep -c .) legs, the structure holds, every leg reported success"
  return 0
}

# ── SESSION-SURFACE T3/F1+F4 — two structural ordering/argument legs ──────────────────────────
# Neither is wired into the main gate-id enforcement path above (this file's normal invocation
# grades an EMITTED adopter pipeline, never the kit's own .github/workflows/ci.yml — see
# verify.sh's `check control ci-gates` lines). Both are exercised ONLY through --selftest, where
# they are run once against synthetic fixtures (the load-bearing negatives) and once against the
# kit's own live ci.yml (the regression backstop: RED here would mean the fix in ci.yml regressed).
# No new registered check name: same `ci-gates-selftest` entry in verify.sh covers both.

extract_job_block() {  # <workflow-file> <job-name> -> the job's line + every line until the next
  # top-level (2-space-indented) job key, on stdout. Best-effort/line-anchored, matching this
  # file's existing style (Leg A's gate-id match, K9's dispatch-shape scan) — not a YAML parser.
  awk -v _job="  ${2}:" '
    $0 == _job { infound=1; print; next }
    infound && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { exit }
    infound { print }
  ' "$1"
}

check_cred_before_prtree() {  # <workflow-file> <job> -> 0 ok, 1 no effective drop before PR-tree code
  # SWAS-250. A job that runs PR-controlled code (`conformance/` or `scripts/`, comments stripped;
  # F1-2: BOTH count) must have no checkout credential reachable by then. Two shapes pass:
  #   (a) every checkout before the first PR-tree line carries `persist-credentials: false`;
  #   (b) the CRED-DROP block (BEGIN, VERIFY, VERIFY-END, END markers in order) sits wholly before
  #       that line, and its verify is a `--show-origin ... --get-regexp` read with NO `--local`
  #       (a `--local` read cannot see the includeIf file checkout v7 writes).
  # The bare `--local --unset-all` string no longer counts: it removes nothing checkout v7 wrote.
  # No PR-tree invocation at all -> vacuous pass.
  _ccp_block=$(extract_job_block "$1" "$2")
  if [ -z "$_ccp_block" ]; then echo "FAIL: $2 job not found in $1" >&2; return 1; fi
  _ccp_code=$(printf '%s\n' "$_ccp_block" | sed 's/#.*//')
  _ccp_pr=$(printf '%s\n' "$_ccp_code" | grep -nE 'conformance/|scripts/' | head -1 | cut -d: -f1)
  [ -n "$_ccp_pr" ] || return 0
  _ccp_co=$(printf '%s\n' "$_ccp_code" | head -n "$((_ccp_pr - 1))" | grep -c 'uses: actions/checkout')
  _ccp_pf=$(printf '%s\n' "$_ccp_code" | head -n "$((_ccp_pr - 1))" | grep -c 'persist-credentials: false')
  if [ "$_ccp_co" -gt 0 ] && [ "$_ccp_co" -eq "$_ccp_pf" ]; then return 0; fi
  _ccp_m() { printf '%s\n' "$_ccp_block" | grep -n "$1" | head -1 | cut -d: -f1; }
  _ccp_b=$(_ccp_m '# CRED-DROP-BEGIN'); _ccp_v=$(_ccp_m '# CRED-DROP-VERIFY$')
  _ccp_ve=$(_ccp_m '# CRED-DROP-VERIFY-END'); _ccp_e=$(_ccp_m '# CRED-DROP-END')
  if [ -z "$_ccp_b" ] || [ -z "$_ccp_v" ] || [ -z "$_ccp_ve" ] || [ -z "$_ccp_e" ] \
     || ! [ "$_ccp_b" -lt "$_ccp_v" ] || ! [ "$_ccp_v" -lt "$_ccp_ve" ] || ! [ "$_ccp_ve" -lt "$_ccp_e" ] \
     || [ "$(printf '%s\n' "$_ccp_block" | sed -n "${_ccp_v},${_ccp_ve}p" | sed 's/#.*//' | grep -c 'git config --show-origin .*--get-regexp')" -lt 1 ]; then
    echo "FAIL: $2 job has no complete CRED-DROP block (markers in order, with an includes-following verify read) and not every checkout is persist-credentials: false" >&2
    return 1
  fi
  if [ "$_ccp_e" -ge "$_ccp_pr" ]; then
    echo "FAIL: $2 job's CRED-DROP block (ends at block line $_ccp_e) does not precede its first PR-tree (conformance/ or scripts/) invocation (block line $_ccp_pr)" >&2
    return 1
  fi
  return 0
}

check_loop_state_credential_order() { check_cred_before_prtree "$1" loop-state; }  # SWAS-250: old name kept

cred_block() {  # <file> <job> [verify] -> the job's CRED-DROP block (or only its verify part), de-indented
  extract_job_block "$1" "$2" | awk -v v="${3:-}" '
    !v && /# CRED-DROP-END/ { print; exit }
    v && /# CRED-DROP-VERIFY-END/ { exit }
    v && /# CRED-DROP-VERIFY$/ { on=1 }
    !v && /# CRED-DROP-BEGIN/ { on=1 }
    on { print }' | sed 's/^          //'
}

cred_scenario() {  # <dir> <layout v7|v4|own|clean> <where rt|out> <script> -> _cs_pre _cs_rc _cs_out _cs_reach _cs_gone _cs_own
  # A throwaway repo shaped like what actions/checkout leaves, then <script> under `bash -e` (how the
  # runner runs a step with no `shell:`). HOME and the system config are pinned so the host cannot leak in.
  _cs_d=$1; mkdir -p "$_cs_d/rt" "$_cs_d/out" "$_cs_d/home"; _cs_d=$(cd "$_cs_d" && pwd -P); _cs_r="$_cs_d/repo"
  _cs_g() { env HOME="$_cs_d/home" XDG_CONFIG_HOME="$_cs_d/home" GIT_CONFIG_NOSYSTEM=1 git "$@"; }
  _cs_g init -q "$_cs_r"
  _cs_c="$_cs_d/$3/git-credentials-0b1e2c3d-aaaa-bbbb-cccc-0123456789ab.config"
  case "$2" in
    v7) printf '[http "https://github.com/"]\n\textraheader = AUTHORIZATION: basic SIMTOKEN250\n' > "$_cs_c"
        _cs_g -C "$_cs_r" config "includeIf.gitdir:$_cs_r/.git.path" "$_cs_c"
        _cs_g -C "$_cs_r" config "includeIf.gitdir:$_cs_r/.git/worktrees/*.path" "$_cs_c"
        _cs_g -C "$_cs_r" config "includeIf.gitdir:/github/workspace/.git.path" "/github/runner_temp/$(basename "$_cs_c")" ;;
    v4) _cs_g -C "$_cs_r" config 'http.https://github.com/.extraheader' 'AUTHORIZATION: basic SIMTOKEN250' ;;
    own) printf '[user]\n\tname = x\n' > "$_cs_d/own.config"; _cs_g -C "$_cs_r" config "includeIf.gitdir:$_cs_r/.git.path" "$_cs_d/own.config" ;;
    xinc) printf '[http "https://github.com/"]\n\textraheader = AUTHORIZATION: basic SIMTOKEN250\n' > "$_cs_d/other.config"  # a header in an include the name-scan cannot see
        _cs_g -C "$_cs_r" config "includeIf.gitdir:$_cs_r/.git.path" "$_cs_d/other.config" ;;
  esac
  _cs_probe() { (cd "$_cs_r" && _cs_g config --get-all 'http.https://github.com/.extraheader' >/dev/null 2>&1 && echo REACHABLE || echo none); }
  _cs_pre=$(_cs_probe)
  if _cs_out=$(cd "$_cs_r" && env HOME="$_cs_d/home" XDG_CONFIG_HOME="$_cs_d/home" GIT_CONFIG_NOSYSTEM=1 RUNNER_TEMP="$_cs_d/rt" bash -e "$4" 2>&1); then _cs_rc=0; else _cs_rc=$?; fi
  _cs_reach=$(_cs_probe)
  if [ -f "$_cs_c" ]; then _cs_gone=present; else _cs_gone=gone; fi
  if [ -f "$_cs_d/own.config" ] && _cs_g -C "$_cs_r" config --local --get-all "includeIf.gitdir:$_cs_r/.git.path" | grep -q own.config; then _cs_own=kept; else _cs_own=lost; fi
}

check_backlog_presence_base_board() {  # <workflow-file> -> 0 ok, 1 --base-board missing entirely
  # F4: the `backlog-presence` job's gate invocation must be ABLE to pass --base-board (extracted
  # from origin/main:BACKLOG.md), or the branch form's change-set-new Done arm fail-safes to
  # no-bind on every CI run, forcing a second push. At least one invocation line in the block
  # naming both backlog-presence.sh and --base-board is required (a conditional fallback line for
  # an unreadable base board, mirroring hooks/pre-push's own fail-safe, is legitimate and does not
  # need to repeat the flag).
  _cbp_block=$(extract_job_block "$1" backlog-presence)
  if [ -z "$_cbp_block" ]; then
    echo "FAIL: backlog-presence job not found in $1" >&2
    return 1
  fi
  if ! printf '%s\n' "$_cbp_block" | grep -q 'backlog-presence\.sh.*--base-board'; then
    echo "FAIL: backlog-presence job's gate invocation never carries --base-board" >&2
    return 1
  fi
  return 0
}

# TRUNK-REF-TAG-SHADOW slice 1 (SWAS-247) — the trunk-tag tripwire step, in EVERY job that reads the
# trunk after a tag-bearing checkout (each job's own checkout fetches the tags when THAT job runs, so a
# decoy tag + a single-job rerun would otherwise derive narrow). One declared list per workflow; the TT4z
# scan below ties each list to the YAML, so a new tag-bearing job cannot arrive without the step.
TT_CI_JOBS="ceremony-binding loop-state review-lane backlog-presence threat-obligation uat-obligation a11y-obligation"
TT_CI_EXCLUDED="conformance-core secret-scan conformance-docs-1 conformance-docs-2"  # fetch-depth: 0 only; each reads full refs / shas, not a short name. SWAS-409: the docs job is now two legs (both depth 0, the same reason the job had) and a join that checks out at the default depth (it reads ci.yml only), so the join leaves the list. Security seat: this edit WIDENS the tripwire's exclusion by one name and narrows it by none that still holds tags.
TT_AG_JOBS="ceremony-binding review-lane loop-state"
TT_AG_EXCLUDED=""
# Revision 3: the remote read (TRUNK_TAG_REMOTE: "1") lives ONLY in the job that already held the checkout
# credential for its notes fetch; every other job judges its own local tags and needs no credential.
TT_REMOTE_JOB="ceremony-binding"
# Revision 3 (TT6): every listed checkout keeps the persist-credentials value it has on main, so no job
# gains a token. "<workflow> <job> <values in checkout order: persisted|false>" (persisted = the default).
TT_PC_TABLE="ci backlog-presence persisted,false
ci threat-obligation persisted
ci uat-obligation persisted
ci a11y-obligation persisted
ci ceremony-binding persisted
ci review-lane persisted
ci loop-state persisted,false
ag ceremony-binding persisted
ag review-lane persisted
ag loop-state false,false"

tt_step_of() {  # <workflow-file> <job> -> the raw text of that job's step that lists this checkout's tags
  # (a comment-only mention above a step belongs to the PREVIOUS step's buffer and is stripped before
  # the match, so prose can never stand in for the step).
  extract_job_block "$1" "$2" | awk '
    function flush() { if (sbuf ~ /git for-each-ref/ && sbuf ~ /refs\/tags/) printf "%s", buf; buf = ""; sbuf = "" }
    /^      - / { flush() }
    { buf = buf $0 "\n"; l = $0; sub(/#.*/, "", l); sbuf = sbuf l "\n" }
    END { flush() }'
}

tt_body_of() {  # <workflow-file> <job> -> that step's run: body, indent removed (what the runner executes)
  tt_step_of "$1" "$2" | awk '
    /^        run: \|[[:space:]]*$/ { inb = 1; next }
    inb { if ($0 ~ /^          /) print substr($0, 11); else if ($0 ~ /^[[:space:]]*$/) print ""; else exit }'
}

check_trunk_tag_tripwire() {  # <workflow-file> <job> -> 0 ok; 1 step absent, misordered, conditional, or followed by a fetch that may bring tags
  _ctt_block=$(extract_job_block "$1" "$2")
  if [ -z "$_ctt_block" ]; then echo "FAIL: $2 job not found in $1" >&2; return 1; fi
  _ctt_strip=$(printf '%s\n' "$_ctt_block" | sed 's/#.*//')
  _ctt_ls=$(printf '%s\n' "$_ctt_strip" | grep -n 'git for-each-ref.*refs/tags' | head -1 | cut -d: -f1)
  if [ -z "$_ctt_ls" ]; then
    echo "FAIL: $2 job has no trunk-tag tripwire step (git for-each-ref over refs/tags)" >&2; return 1
  fi
  _ctt_step=$(tt_step_of "$1" "$2" | sed 's/#.*//')
  if ! printf '%s\n' "$_ctt_step" | grep -q 'TRUNK_TAG_REMOTE'; then
    echo "FAIL: $2 trunk-tag tripwire lacks the TRUNK_TAG_REMOTE mode switch" >&2; return 1
  fi
  _ctt_co=$(printf '%s\n' "$_ctt_strip" | grep -n 'uses: actions/checkout' | tail -1 | cut -d: -f1)
  if [ -z "$_ctt_co" ] || [ "$_ctt_co" -ge "$_ctt_ls" ]; then
    echo "FAIL: $2 trunk-tag tripwire (block line $_ctt_ls) does not come after the job's last checkout" >&2; return 1
  fi
  # the first of the credential drop and the first PR-tree (conformance/ or scripts/) invocation: the step must precede it
  # The drop is found by its marker line, searched in the UNSTRIPPED block (the strip deletes # comments, and the marker is one);
  # a job with no drop block (persist-credentials: false) keeps the first-PR-tree-line limit. Stripping keeps line numbers, so the two compare.
  _ctt_lim=$(printf '%s\n' "$_ctt_strip" | grep -n -e 'conformance/' -e 'scripts/' | head -1 | cut -d: -f1)
  _ctt_drop=$(printf '%s\n' "$_ctt_block" | grep -n '^[[:space:]]*# CRED-DROP-BEGIN' | head -1 | cut -d: -f1)
  if [ -n "$_ctt_drop" ] && { [ -z "$_ctt_lim" ] || [ "$_ctt_drop" -lt "$_ctt_lim" ]; }; then _ctt_lim=$_ctt_drop; fi
  if [ -n "$_ctt_lim" ] && [ "$_ctt_ls" -ge "$_ctt_lim" ]; then
    echo "FAIL: $2 trunk-tag tripwire (block line $_ctt_ls) does not precede the credential drop or the first PR-tree invocation (block line $_ctt_lim); a private repository could not be read, or PR code ran first" >&2; return 1
  fi
  if printf '%s\n' "$_ctt_step" | grep -Eq '^[[:space:]]*(- )?(if|continue-on-error):'; then
    echo "FAIL: $2 trunk-tag tripwire step carries an if: or continue-on-error: key" >&2; return 1
  fi
  # rule (e): the remote mode is set to exactly "1" in the one job that held the credential on main, and nowhere else.
  _ctt_envn=$(printf '%s\n' "$_ctt_strip" | grep -c '^[[:space:]]*TRUNK_TAG_REMOTE:' || true)
  _ctt_env=$(printf '%s\n' "$_ctt_step" | awk '/^        env:[ \t]*$/ { e = 1; next } /^        run:/ { e = 0 } e { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print }')
  if [ "$2" = "$TT_REMOTE_JOB" ]; then
    if [ "$_ctt_env" != 'TRUNK_TAG_REMOTE: "1"' ] || [ "$_ctt_envn" != 1 ]; then
      echo "FAIL: $2 trunk-tag tripwire step must carry exactly env: TRUNK_TAG_REMOTE: \"1\" (the remote read), and the job nowhere else sets it (rule e)" >&2; return 1
    fi
  elif [ -n "$_ctt_env" ] || [ "$_ctt_envn" != 0 ] || printf '%s\n' "$_ctt_step" | grep -q '^        env:'; then
    echo "FAIL: $2 sets TRUNK_TAG_REMOTE or carries an env: key on the tripwire; only $TT_REMOTE_JOB reads the remote, so no other job may (rule e)" >&2; return 1
  fi
  _ctt_late=$(printf '%s\n' "$_ctt_strip" | awk -v n="$_ctt_ls" 'NR > n && /git fetch/ && (!/--no-tags/ || /--tags/) { print NR; exit }')
  if [ -n "$_ctt_late" ]; then
    echo "FAIL: $2 has a git fetch after the tripwire (block line $_ctt_late) that may bring tags in; every later fetch must carry --no-tags" >&2; return 1
  fi
  return 0
}

check_trunk_full_ref() {  # <workflow-file> -> 0 ok, 1 a trunk read a same-named tag could shadow
  # SWAS-246: git resolves a short name with tags AHEAD of heads, so a pushed tag `main` (as a fetch
  # source) or `origin/main` (as a local read) replaces the trunk the recordless-merge backstop and
  # the board gate read. Selftest-only (no registered check name). Comments stripped first; line-based.
  # (a) every operand of a `git fetch <remote> ...` starts with refs/ or +refs/.
  # (b) a git show/diff/merge-base/log/rev-parse/rev-list line, or a --from line, never names
  #     `origin/` unless it is preceded by `remotes/`.
  # (c) the loop-state block's show-ref --verify guard comes BEFORE its `promotion-verify.sh trace`.
  _tf_out=$(sed 's/#.*//' "$1" | awk -v f="$1" '
    function bad(why) { print "FAIL: trunk-full-ref - " f ":" NR ": " why " [" $0 "]" }
    function shadow(tok,   s, p) {
      s = tok
      while ((p = index(s, "origin/")) > 0) {
        if (substr(s, 1, p - 1) !~ /remotes\/$/) return 1
        s = substr(s, p + 7)
      }
      return 0
    }
    {
      line = $0; gsub(/[;|&()<>`]/, " ; ", line); gsub(/[\047"]/, "", line)
      n = split(line, t, /[ \t]+/)
      for (i = 1; i <= n; i++) {
        if (t[i] == "--from" || t[i] ~ /^--from=/) {
          for (k = 1; k <= n; k++) if (shadow(t[k])) { bad("--from reads a short name; use refs/remotes/origin/<branch>"); break }
        }
        if (t[i] != "git") continue
        j = i + 1
        while (j <= n && t[j] != ";") {
          if (t[j] == "-c") j += 2
          else if (substr(t[j], 1, 1) == "-") j++
          else break
        }
        sub_c = t[j]
        if (sub_c == "fetch") {
          for (k = j + 1; k <= n && substr(t[k], 1, 1) == "-"; k++) ;
          for (k = k + 1; k <= n && t[k] != ";"; k++)
            if (t[k] != "" && t[k] !~ /^[0-9]+$/ && t[k] !~ /^\+?refs\//) { bad("fetch operand " t[k] " is a short name; fetch +refs/heads/<branch>:refs/remotes/origin/<branch>"); break }
        } else if (index(" show diff merge-base log rev-parse rev-list ", " " sub_c " ") > 0 && sub_c != "") {
          for (k = j + 1; k <= n && t[k] != ";"; k++)
            if (shadow(t[k])) { bad("git " sub_c " reads a short name; use refs/remotes/origin/<branch>"); break }
        }
      }
    }
  ')
  if [ -n "$_tf_out" ]; then printf '%s\n' "$_tf_out" >&2; return 1; fi
  _tf_block=$(extract_job_block "$1" loop-state | sed 's/#.*//')
  _tf_trace=$(printf '%s\n' "$_tf_block" | grep -nF 'promotion-verify.sh trace' | head -1 | cut -d: -f1)
  [ -n "$_tf_trace" ] || return 0
  _tf_guard=$(printf '%s\n' "$_tf_block" | grep -nF 'show-ref --verify -q refs/remotes/origin/main' | head -1 | cut -d: -f1)
  if [ -z "$_tf_guard" ] || [ "$_tf_guard" -ge "$_tf_trace" ]; then
    echo "FAIL: trunk-full-ref - $1: loop-state has no 'git show-ref --verify -q refs/remotes/origin/main' before its trace (a tag named refs/remotes/origin/main would resolve)" >&2
    return 1
  fi
  return 0
}

tt_tagbearing() {  # <workflow-file> -> "<job> <trigger>" for each way a job can hold tags (comment-stripped)
  sed 's/#.*//' "$1" | awk '
    /^  [A-Za-z0-9_-]+:[ \t]*$/ { j = $1; sub(/:$/, "", j) }
    j == "" { next }
    /fetch-depth:[ \t]*0[ \t]*$/ { print j " fetch-depth:0" }
    /fetch-tags:[ \t]*true/ { print j " fetch-tags:true" }
    /git fetch/ && (!/--no-tags/ || /--tags/) { print j " git-fetch-may-bring-tags" }'
}

check_tt_tagbearing() {  # <workflow-file> <declared-jobs> <excluded-jobs> -> 0 ok; 1 a tag-bearing job is neither guarded nor a named exclusion
  _cz=0
  for _cz_hit in $(tt_tagbearing "$1" | sort -u | tr ' ' ':'); do
    _cz_job=${_cz_hit%%:*}; _cz_trig=${_cz_hit#*:}
    case " $2 " in
      *" $_cz_job "*) continue ;;
    esac
    case " $3 " in
      *" $_cz_job "*) [ "$_cz_trig" = "fetch-depth:0" ] && continue ;;
    esac
    echo "FAIL: $1 job $_cz_job holds tags ($_cz_trig) but carries no trunk-tag tripwire and is not a named exclusion" >&2; _cz=1
  done
  return "$_cz"
}

_tt_mut() {  # <workflow> <job> <delete|move|nofl> [<step-name-prefix>] -> stdout: the workflow with ONLY that job's step deleted, moved to the job's end, or its first later --no-tags fetch loosened
  awk -v job="  $2:" -v mode="$3" -v pfx="      - name: ${4:-Trunk-name tag tripwire}" '
    { a[NR] = $0 }
    $0 == job { js = NR }
    js && !je && NR > js && /^  [A-Za-z0-9_-]+:[ \t]*$/ { je = NR }
    END {
      if (!je) je = NR + 1
      for (i = js + 1; i < je && !ss; i++) if (index(a[i], pfx) == 1) ss = i
      for (se = ss + 1; se < je && a[se] !~ /^      - /; se++) ;
      tg = je  # "afterdrop": land the step just after the step that holds the CRED-DROP-END marker (F1)
      if (mode == "afterdrop") {
        for (i = js + 1; i < je && !de; i++) if (a[i] ~ /^[ \t]*# CRED-DROP-END/) de = i
        if (de) for (tg = de + 1; tg < je && a[tg] !~ /^      - /; tg++) ;
      }
      for (i = 1; i <= NR; i++) {
        if (mode == "nofl") { if (i >= se && i < je && !done && a[i] ~ /git fetch --no-tags/) { sub(/ --no-tags/, "", a[i]); done = 1 }; print a[i]; continue }
        if (ss && i >= ss && i < se) { if (mode == "move" || mode == "afterdrop") hold = hold a[i] "\n"; continue }
        if (i == tg) printf "%s", hold
        print a[i]
      }
      if (tg > NR) printf "%s", hold
    }' "$1"
}

tt_pc_of() {  # <workflow-file> <job> -> the persist-credentials value of each actions/checkout in the job, in order, comma-joined (persisted|false)
  extract_job_block "$1" "$2" | sed 's/#.*//' | awk '
    function flush() { if (inco) out = out (out == "" ? "" : ",") (fl ? "false" : "persisted"); inco = 0; fl = 0 }
    /^      - / { flush(); if ($0 ~ /uses: actions\/checkout/) inco = 1 }
    inco && /persist-credentials:[ \t]*false/ { fl = 1 }
    END { flush(); print out }'
}

check_tt_credentials() {  # <ci|ag> <workflow-file> <job> -> 0 when every checkout keeps main's persist-credentials value (TT6); 1 on any difference
  _ctc_want=$(printf '%s\n' "$TT_PC_TABLE" | awk -v w="$1" -v j="$3" '$1 == w && $2 == j { print $3 }')
  _ctc_got=$(tt_pc_of "$2" "$3")
  if [ -z "$_ctc_want" ]; then echo "FAIL: $3 ($1) has no persist-credentials row in TT_PC_TABLE" >&2; return 1; fi
  if [ "$_ctc_got" != "$_ctc_want" ]; then
    echo "FAIL: $3 ($1) persist-credentials differs from main: checkouts are '$_ctc_got', main has '$_ctc_want' (no job may gain or lose a token)" >&2; return 1
  fi
  return 0
}

_tt_pcmut() {  # <workflow> <job> <remove|add> -> stdout: the workflow with ONLY that job's first `persist-credentials: false` removed, or one added to its first checkout
  awk -v job="  $2:" -v mode="$3" '
    $0 == job { inj = 1; print; next }
    inj && /^  [A-Za-z0-9_-]+:[ \t]*$/ { inj = 0 }
    inj && mode == "remove" && !done && /^          persist-credentials: false/ { done = 1; next }
    inj && mode == "add" && !done && /uses: actions\/checkout/ { want = 1 }
    { print }
    inj && mode == "add" && !done && want && /^        with:/ { print "          persist-credentials: false"; done = 1; want = 0 }
  ' "$1"
}

_tt_envmut() {  # <workflow> <job> <remove|zero|add> -> stdout: the workflow with ONLY that job's tripwire env removed, set to "0", or added
  awk -v job="  $2:" -v mode="$3" '
    $0 == job { inj = 1; print; next }
    inj && /^  [A-Za-z0-9_-]+:[ \t]*$/ { inj = 0; instep = 0 }
    inj && index($0, "      - name: Trunk-name tag tripwire") == 1 { instep = 1; print; if (mode == "add") { print "        env:"; print "          TRUNK_TAG_REMOTE: \"1\"" } ; next }
    instep && /^      - / { instep = 0 }
    instep && mode == "remove" && /^        env:[ \t]*$/ { skip = 1; next }
    instep && skip { skip = 0; next }
    instep && mode == "zero" && /TRUNK_TAG_REMOTE:/ { sub(/"1"/, "\"0\"") }
    { print }
  ' "$1"
}

# Fixture helpers for TT0-TT3 (selftest-only; throwaway bare repos under $d, file:// only, no network).
_tt_git() { env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c user.name=tt -c user.email=tt@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

_tt_fixture() {  # <dir> <default-branch> -> <dir>/origin.git: trunk commit A, branch pr = B (conformance/x.sh) then C (notes.md)
  mkdir -p "$1/seed" || return 1
  _tt_git init -q --bare -b "$2" "$1/origin.git" || return 1
  _tt_git init -q -b "$2" "$1/seed" || return 1
  printf 'a\n' > "$1/seed/README"
  _tt_git -C "$1/seed" add README && _tt_git -C "$1/seed" commit -q -m a || return 1
  _tt_a=$(_tt_git -C "$1/seed" rev-parse HEAD)
  _tt_git -C "$1/seed" checkout -q -b pr || return 1
  mkdir -p "$1/seed/conformance"; printf 'x\n' > "$1/seed/conformance/x.sh"
  _tt_git -C "$1/seed" add conformance/x.sh && _tt_git -C "$1/seed" commit -q -m b || return 1
  _tt_b=$(_tt_git -C "$1/seed" rev-parse HEAD)
  printf 'n\n' > "$1/seed/notes.md"
  _tt_git -C "$1/seed" add notes.md && _tt_git -C "$1/seed" commit -q -m c || return 1
  _tt_c=$(_tt_git -C "$1/seed" rev-parse HEAD)
  _tt_git -C "$1/seed" push -q "file://$1/origin.git" "$2" pr "$2:release" "$2:develop"
}

selftest() {
  _st_begin
  sf=0
  mkdir -p "$d/scripts"
  # a stand-in kit script whose dispatch supports exactly: new-trace | span | --selftest
  printf '#!/bin/sh\ncase "${1:-}" in\n  --selftest) exit 0 ;;\n  new-trace) exit 0 ;;\n  span) exit 0 ;;\n  *) exit 2 ;;\nesac\n' > "$d/scripts/otel-trace.sh"

  # GOOD: every invoked subcommand exists in the dispatch
  printf 'jobs:\n  ci:\n    steps:\n      - run: |\n          sh scripts/otel-trace.sh new-trace\n          sh scripts/otel-trace.sh span --trace x\n' > "$d/good.yml"
  if check_kit_seams "$d/good.yml" "$d" >/dev/null 2>&1; then
    echo "selftest PASS: supported subcommands -> PASS"
  else echo "selftest FAIL: good fixture wrongly failed"; sf=1; fi

  # BAD (the K9 fixture): an unsupported subcommand must FAIL
  printf 'jobs:\n  ci:\n    steps:\n      - run: sh scripts/otel-trace.sh --bogus\n' > "$d/bad.yml"
  if check_kit_seams "$d/bad.yml" "$d" >/dev/null 2>&1; then
    echo "selftest FAIL: unsupported subcommand NOT caught"; sf=1
  else echo "selftest PASS: unsupported subcommand -> FAIL"; fi

  # BAD: the invocation appears ONLY in a comment -> must not satisfy the lock (comment-strip)
  printf 'jobs:\n  ci:\n    steps:\n      - run: |\n          # sh scripts/otel-trace.sh --bogus\n          echo ok\n' > "$d/commented.yml"
  if check_kit_seams "$d/commented.yml" "$d" >/dev/null 2>&1; then
    echo "selftest PASS: commented-out invocation ignored"
  else echo "selftest FAIL: comment wrongly treated as live"; sf=1; fi

  # I1 KILL FIXTURE (the whole point of anchoring to the case arm): a stand-in whose USAGE STRING
  # names `new-trace` but whose dispatch has NO such arm. A predicate that greps the WHOLE target
  # script -- including a plain `grep -qF -- "$_sub"` substring match -- calls this resolved and the
  # check passes; only a predicate anchored to the arm itself catches it. Without this leg the
  # substring mutant SURVIVES and the lock is carried by a printf in a help message (CP-7 I1).
  mkdir -p "$d/usage/scripts"
  # It also carries an `if`-form dispatch for a DIFFERENT verb, so the if-form branch below is live
  # while this leg runs: proving that branch cannot be what lets a usage-string mention through.
  # Three decoys for `new-trace`, each killing a distinct predicate-loosening mutant:
  #   1. the usage string           -> kills the plain-substring mutant (round-1 I1)
  #   2. `new-trace() { :; }`       -> line-initial, so it kills a mutant that drops the `[)|]`
  #      arm terminator (a function definition is NOT a dispatch arm)
  #   3. `... then echo "try new-trace"` -> kills a mutant that relaxes _ifRE to `^\s*(el)?if.*sub`
  # The real dispatch offers ONLY `span` and `--selftest`; `new-trace` must stay UNRESOLVED.
  printf '#!/bin/sh\nnew-trace() { :; }\nif [ -n "${FOO:-}" ]; then echo "try new-trace"; fi\nif [ "${1:-}" = "span" ]; then exit 0; fi\ncase "${1:-}" in\n  --selftest) exit 0 ;;\n  "") printf "usage: otel-trace.sh new-trace | span --trace ID | --selftest\\n" >&2; exit 2 ;;\n  *) exit 2 ;;\nesac\n' > "$d/usage/scripts/otel-trace.sh"
  printf 'jobs:\n  ci:\n    steps:\n      - run: sh scripts/otel-trace.sh new-trace\n' > "$d/usage/wf.yml"
  if check_kit_seams "$d/usage/wf.yml" "$d/usage" >/dev/null 2>&1; then
    echo "selftest FAIL: a verb named only in a usage string was counted as a resolved subcommand"; sf=1
  else echo "selftest PASS: usage-string mention does NOT resolve (predicate anchored to the case arm)"; fi

  # I2 FIXTURE (measured on the real tree): not every dispatch is a `case` arm. scripts/explain.sh
  # and scripts/adopter-export.sh dispatch --selftest with `if [ "${1:-}" = "--selftest" ]` while
  # carrying an UNRELATED inner `case "$1"` option loop. Judging only case arms calls those live,
  # working CI invocations unresolved -- a false FAIL, and worse than the check's other blind spots
  # because every one of those fails OPEN. This must PASS.
  printf 'jobs:\n  ci:\n    steps:\n      - run: sh scripts/adopter-export.sh --selftest\n' > "$d/ifform.yml"
  printf '#!/bin/sh\nif [ "${1:-}" = "--selftest" ]; then exit 0; fi\nwhile [ $# -gt 0 ]; do\n  case "$1" in\n    --profile) shift 2 ;;\n    *) shift ;;\n  esac\ndone\nexit 0\n' > "$d/scripts/adopter-export.sh"
  if check_kit_seams "$d/ifform.yml" "$d" >/dev/null 2>&1; then
    echo "selftest PASS: if-form dispatch resolves (not only case arms)"
  else echo "selftest FAIL: if-form dispatch wrongly judged unresolved"; sf=1; fi

  # I2 FIXTURE: the first token after a script path is not always a subcommand. A bare file
  # descriptor from a redirection must not be judged as one -- this is legal shell and a blocking
  # gate may not reject it.
  printf 'jobs:\n  ci:\n    steps:\n      - run: sh scripts/otel-trace.sh 2>/dev/null\n' > "$d/fd.yml"
  if check_kit_seams "$d/fd.yml" "$d" >/dev/null 2>&1; then
    echo "selftest PASS: redirection fd not judged a subcommand"
  else echo "selftest FAIL: redirection fd wrongly judged a subcommand"; sf=1; fi

  # I2 FIXTURE: a positional FILE argument is not a subcommand either. The extractor must see the
  # WHOLE token (`gp_spans.ndjson`) rather than truncating it to a plausible-looking word, or the
  # filter cannot tell a filename from a verb.
  printf 'jobs:\n  ci:\n    steps:\n      - run: sh scripts/otlp-export.sh gp_spans.ndjson --dry-run\n' > "$d/fileArg.yml"
  printf '#!/bin/sh\nTRACE=""\nwhile [ $# -gt 0 ]; do\n  case "$1" in\n    --dry-run) shift ;;\n    *) TRACE="$1"; shift ;;\n  esac\ndone\nexit 0\n' > "$d/scripts/otlp-export.sh"
  if check_kit_seams "$d/fileArg.yml" "$d" >/dev/null 2>&1; then
    echo "selftest PASS: positional file argument not judged a subcommand"
  else echo "selftest FAIL: positional file argument wrongly judged a subcommand"; sf=1; fi

  # I2 FIXTURE: a script with no `$1` dispatch at all has nothing to resolve against, so its
  # positional argument must not be judged (`sh scripts/new-profile.sh teststack` is live today).
  printf 'jobs:\n  ci:\n    steps:\n      - run: sh scripts/new-profile.sh teststack\n' > "$d/positional.yml"
  printf '#!/bin/sh\nname="${1:?need a name}"\nmkdir -p "profiles/$name"\nexit 0\n' > "$d/scripts/new-profile.sh"
  if check_kit_seams "$d/positional.yml" "$d" >/dev/null 2>&1; then
    echo "selftest PASS: non-dispatch script's positional arg not judged"
  else echo "selftest FAIL: non-dispatch script's positional arg wrongly judged"; sf=1; fi

  # VACUITY GUARD: a workflow with no kit-owned invocations passes, but must not be
  # how every real workflow passes -- the bad fixtures above prove the extractor has teeth.
  printf 'jobs:\n  ci:\n    steps:\n      - run: npm ci\n' > "$d/none.yml"
  if check_kit_seams "$d/none.yml" "$d" >/dev/null 2>&1; then
    echo "selftest PASS: no kit seams -> vacuously OK"
  else echo "selftest FAIL: seam-free workflow wrongly failed"; sf=1; fi

  # CONFORMANCE-SEAM legs (CP7R5-NINE-PROFILES): the ONE kit-owned seam every emitted pipeline shares is
  # `sh conformance/verify.sh --require` -- a `conformance/` path the extractor did not see, dispatched by
  # verify.sh via a bare `[ "$1" = --require ]` (and an `if [ "$1" = --selftest ]`), NEITHER a `case` arm.
  # This stub mirrors that exact dispatch shape, so a green here proves all three seams the real verify.sh
  # exercises: conformance/-path extraction, if/bare-[ dispatch detection, and bare-[ equality resolution.
  mkdir -p "$d/conformance"
  printf '#!/bin/sh\n[ "${1:-}" = "--require" ] && exit 0\nif [ "${1:-}" = "--selftest" ]; then exit 0; fi\nexit 2\n' > "$d/conformance/verify.sh"
  printf 'jobs:\n  ci:\n    steps:\n      - run: sh conformance/verify.sh --require\n' > "$d/conf-good.yml"
  # --expect-seams=1: also proves the extractor now EXTRACTS the conformance seam (a still-blind extractor
  # yields zero matches and FAILs here with "ZERO kit-owned invocations") -- the load-bearing non-vacuity.
  if check_kit_seams "$d/conf-good.yml" "$d" 1 >/dev/null 2>&1; then
    echo "selftest PASS: conformance/ seam with a resolvable flag -> PASS (bare-[ dispatch resolved; extractor saw it)"
  else echo "selftest FAIL: real conformance/verify.sh --require wrongly unresolved or unseen"; sf=1; fi
  # The K9 mutant for the SHARED seam: a bogus flag (what a `--requires` typo would be) must FAIL.
  printf 'jobs:\n  ci:\n    steps:\n      - run: sh conformance/verify.sh --bogus\n' > "$d/conf-bad.yml"
  if check_kit_seams "$d/conf-bad.yml" "$d" >/dev/null 2>&1; then
    echo "selftest FAIL: unresolved conformance/ subcommand NOT caught (K9 class open on the shared seam)"; sf=1
  else echo "selftest PASS: unresolved conformance/ subcommand -> FAIL"; fi

  # MAIN-PATH leg (load-bearing): the four cases above call check_kit_seams DIRECTLY, which proves the
  # function but NOT the `|| exit 1` wiring in the main path. A slice that only tests the function can
  # ship a check whose result is never acted on. Drive one case through the real entry point.
  # The fixture carries all 8 gate ids so it cannot fail for the OTHER reason, and the assertion is on a
  # DISCRIMINATING message -- an exit code alone would also match the missing-gates failure.
  # NOTE the resolution root: invoked as `sh "$0"`, the child resolves _root to $(dirname "$0")/.. --
  # the REAL kit tree, not "$d". This leg therefore fails because the real scripts/otel-trace.sh has no
  # `--bogus` arm. It fails CLOSED (a checkout without a sibling scripts/ reports "did not act"), and
  # the non-vacuity harness runs mutants inside conformance/, so the sweep is unaffected.
  { for g in gate-lint gate-type-check gate-test gate-build gate-secret-scan gate-dep-scan gate-sbom gate-provenance; do
      printf '      - id: %s\n' "$g"; done
    printf '      - run: sh scripts/otel-trace.sh --bogus\n'; } > "$d/mainpath.yml"
  if _out=$(sh "$0" "$d/mainpath.yml" 2>&1); then _rc=0; else _rc=$?; fi
  if [ "$_rc" -ne 0 ] && printf '%s' "$_out" | grep -q "does not resolve"; then
    echo "selftest PASS: main path acts on the seam failure"
  else
    echo "selftest FAIL: main path did not act on the seam failure (rc=$_rc): $_out"; sf=1
  fi

  # --expect-seams leg: an invocation the extractor CANNOT see (quoted script path -- named as
  # invisible in this file's own EXTRACTION ceiling) must PASS by default (stack-neutral: a seam-free
  # workflow is legitimately green) and FAIL under --expect-seams (a workflow declared to carry seams
  # that yields an empty match set has judged NOTHING). Without this leg, --expect-seams could be
  # inert and no other leg would notice.
  { for g in gate-lint gate-type-check gate-test gate-build gate-secret-scan gate-dep-scan gate-sbom gate-provenance; do
      printf '      - id: %s\n' "$g"; done
    printf '      - run: sh "scripts/otel-trace.sh" new-trace\n'; } > "$d/invisible.yml"
  if _o1=$(sh "$0" "$d/invisible.yml" 2>&1); then _r1=0; else _r1=$?; fi
  if _o2=$(sh "$0" "$d/invisible.yml" --expect-seams 2>&1); then _r2=0; else _r2=$?; fi
  if [ "$_r1" -eq 0 ] && [ "$_r2" -ne 0 ] && printf '%s' "$_o2" | grep -q "ZERO kit-owned invocations"; then
    echo "selftest PASS: --expect-seams turns an empty match set into a failure"
  else
    echo "selftest FAIL: --expect-seams inert (default rc=$_r1, expect-seams rc=$_r2): $_o2"; sf=1
  fi

  # `J` must be emitted AFTER the filters, not before: a token rejected as a non-subcommand (here a
  # redirection fd) was never judged, so --expect-seams must still fire. The leg above uses a fixture
  # with zero EXTRACTED tokens, so it cannot see a `J` hoisted above the `continue` filters.
  { for g in gate-lint gate-type-check gate-test gate-build gate-secret-scan gate-dep-scan gate-sbom gate-provenance; do
      printf '      - id: %s\n' "$g"; done
    printf '      - run: sh scripts/otel-trace.sh 2>/dev/null\n'; } > "$d/fdonly.yml"
  if _o3=$(sh "$0" "$d/fdonly.yml" --expect-seams 2>&1); then _r3=0; else _r3=$?; fi
  if [ "$_r3" -ne 0 ] && printf '%s' "$_o3" | grep -q "ZERO kit-owned invocations"; then
    echo "selftest PASS: a filtered-out token does not count as judged"
  else
    echo "selftest FAIL: filtered token counted as judged (rc=$_r3): $_o3"; sf=1
  fi
  _st_mark SEAMS

  # ── B7 legs (D-240805-2 executed): the OWN-TREE mode + the disposition artifact ─────────────────
  # The mode judges THE TREE'S OWN installed pipeline(s) — .github/workflows/ci.yml AND
  # .gitlab-ci.yml, every one present — against the 8 gate ids minus the tree's VALIDATED na
  # dispositions (conformance/gate-dispositions.txt). Fixtures are PURE FILE TREES (no git): the
  # mode reads markers + files only, so these legs are hermetic by construction (no identity, no
  # notes ref, no ambient repository state).
  ALLG="gate-lint gate-type-check gate-test gate-build gate-secret-scan gate-dep-scan gate-sbom gate-provenance"
  _ot_gh() { # <root> <marker:1|0> [ids...] — a GitHub-shaped pipeline at the root
    _og_r=$1; _og_m=$2; shift 2
    mkdir -p "$_og_r/.github/workflows"
    { if [ "$_og_m" = 1 ]; then printf '%s\n' '# kit-pipeline-origin: emitted'; fi
      printf 'jobs:\n  ci:\n    steps:\n'
      for _og_g in "$@"; do printf '      - id: %s\n' "$_og_g"; done
      printf '      - run: echo toolchain\n'
    } > "$_og_r/.github/workflows/ci.yml"
  }
  _ot_gl() { # <root> [ids...] — a GitLab-shaped pipeline (job keys at column 0)
    _ol_r=$1; shift
    { printf '%s\n' '# kit-pipeline-origin: emitted'
      for _ol_g in "$@"; do printf '%s:\n  script: [echo ok]\n' "$_ol_g"; done
    } > "$_ol_r/.gitlab-ci.yml"
  }
  _ot_case() { # <name> <root> <want-rc> <want-substr> <desc> — one own-tree run through the REAL entry point
    _oc_n=$1; _oc_r=$2; _oc_rc=$3; _oc_s=$4; _oc_d=$5
    if _oc_out=$(sh "$0" --own-tree "$_oc_r" 2>&1); then _oc_got=0; else _oc_got=$?; fi
    if [ "$_oc_got" = "$_oc_rc" ] && printf '%s' "$_oc_out" | grep -qF -- "$_oc_s"; then
      echo "selftest PASS: $_oc_n — $_oc_d"
    else
      echo "selftest FAIL: $_oc_n — $_oc_d (rc=$_oc_got want $_oc_rc, want text '$_oc_s'): $_oc_out"; sf=1
    fi
  }
  _ot_disp_kit() { # <root> — a D-240805-2-shaped disposition file: 3 apply + 5 na-with-reason
    mkdir -p "$1/conformance"
    { printf 'gate-secret-scan\tapply\tshipped\n'
      printf 'gate-test\tapply\tselftest battery\n'
      printf 'gate-lint\tapply\tshell lint\n'
      printf 'gate-type-check\tna\tPOSIX sh, no type system\n'
      printf 'gate-build\tna\tno build artifact\n'
      printf 'gate-dep-scan\tna\tno dependency manifest\n'
      printf 'gate-sbom\tna\tnothing to attest\n'
      printf 'gate-provenance\tna\tnothing to attest\n'
    } > "$1/conformance/gate-dispositions.txt"
  }

  # OT1 — all 8 ids on the tree's own EMITTED pipeline (incepted-adopter marker) -> green.
  mkdir -p "$d/ot1"; : > "$d/ot1/ENGINEERING-PRINCIPLES.md"
  # shellcheck disable=SC2086 # $ALLG is a deliberate word-list
  _ot_gh "$d/ot1" 1 $ALLG
  _ot_case OT1 "$d/ot1" 0 "OK: ci-gates --own-tree" "all 8 ids on the tree's own emitted pipeline -> green"

  # OT2 — THE SPINE AC VERBATIM: delete gate-sbom from an EMITTED pipeline -> RED naming it,
  # and (self-review finding 1) BOTH remedies are named AT THE POINT OF FAILURE.
  mkdir -p "$d/ot2"; : > "$d/ot2/ENGINEERING-PRINCIPLES.md"
  _ot_gh "$d/ot2" 1 gate-lint gate-type-check gate-test gate-build gate-secret-scan gate-dep-scan gate-provenance
  _ot_case OT2 "$d/ot2" 1 "gate-sbom" "emitted pipeline missing gate-sbom -> RED naming it (spine AC)"
  if _o2=$(sh "$0" --own-tree "$d/ot2" 2>&1); then :; fi
  if printf '%s' "$_o2" | grep -qF "RESTORE the id" && printf '%s' "$_o2" | grep -qF "gate-dispositions.txt"; then
    echo "selftest PASS: OT2b — the FAIL names both remedies (restore the id / declare na-with-reason)"
  else
    echo "selftest FAIL: OT2b — the FAIL must name BOTH remedies at the point it fires (finding 1): $_o2"; sf=1
  fi

  # OT3 — a RAW pre-incept export (no marker, no pipeline) -> N/A, rc 0 (three-state zero-found).
  mkdir -p "$d/ot3"
  _ot_case OT3 "$d/ot3" 0 "N/A: ci-gates --own-tree" "raw export: no pipeline + no marker -> N/A"

  # OT4 — a KIT/incepted-marked tree with NO pipeline at all -> FAIL (fail-closed zero-found).
  mkdir -p "$d/ot4/docs"; : > "$d/ot4/docs/ROADMAP-KIT.md"
  _ot_case OT4 "$d/ot4" 1 "NO CI pipeline" "kit-marker tree with no pipeline -> FAIL"

  # OT5 — a GitLab-only adopter IS judged: all 8 job keys green; missing one -> RED naming it.
  mkdir -p "$d/ot5"; : > "$d/ot5/ENGINEERING-PRINCIPLES.md"
  # shellcheck disable=SC2086
  _ot_gl "$d/ot5" $ALLG
  _ot_case OT5 "$d/ot5" 0 "OK: ci-gates --own-tree" "gitlab-only tree, all 8 job keys -> green"
  mkdir -p "$d/ot5b"; : > "$d/ot5b/ENGINEERING-PRINCIPLES.md"
  _ot_gl "$d/ot5b" gate-type-check gate-test gate-build gate-secret-scan gate-dep-scan gate-sbom gate-provenance
  _ot_case OT5b "$d/ot5b" 1 "gate-lint" "gitlab-only tree missing gate-lint -> RED (the platform IS judged)"

  # OT6 — BOTH pipelines present: EVERY one is judged; one bad -> RED (judge-all, no selection).
  mkdir -p "$d/ot6"; : > "$d/ot6/ENGINEERING-PRINCIPLES.md"
  # shellcheck disable=SC2086
  _ot_gh "$d/ot6" 1 $ALLG
  _ot_gl "$d/ot6" gate-lint gate-type-check gate-test gate-build gate-secret-scan gate-dep-scan gate-provenance
  _ot_case OT6 "$d/ot6" 1 ".gitlab-ci.yml" "both present, gitlab file missing an id -> RED (both judged)"

  # OT7 — a FOREIGN (unmarked) pipeline on an adopter tree missing ids -> the ADOPTER-OWNED
  # disclosed N/A, rc 0, with the remedies still named (the brownfield witness — the kit's own
  # artifact-gate-brownfield job runs verify.sh --require over exactly this shape; provenance
  # separates DRIFT from an UNMET DOCUMENTED MERGE OBLIGATION, verify-enforced-wired.sh's own axis).
  mkdir -p "$d/ot7"; : > "$d/ot7/ENGINEERING-PRINCIPLES.md"
  _ot_gh "$d/ot7" 0
  _ot_case OT7 "$d/ot7" 0 "ADOPTER-OWNED" "foreign unmarked pipeline -> disclosed N/A, not FAIL"
  if _o7=$(sh "$0" --own-tree "$d/ot7" 2>&1); then :; fi
  if printf '%s' "$_o7" | grep -qF "gate-dispositions.txt"; then
    echo "selftest PASS: OT7b — the disclosed N/A still names the disposition remedy"
  else
    echo "selftest FAIL: OT7b — the ADOPTER-OWNED N/A must still name the remedies: $_o7"; sf=1
  fi

  # OT8 — a VALID disposition file NARROWS the required set to its apply lines; deleting an APPLY
  # id from the pipeline still REDs (the disposition never exempts an apply gate).
  mkdir -p "$d/ot8"; : > "$d/ot8/ENGINEERING-PRINCIPLES.md"; _ot_disp_kit "$d/ot8"
  _ot_gh "$d/ot8" 1 gate-secret-scan gate-test gate-lint
  _ot_case OT8 "$d/ot8" 0 "OK: ci-gates --own-tree" "3-apply/5-na disposition + the 3 apply ids -> green"
  mkdir -p "$d/ot8b"; : > "$d/ot8b/ENGINEERING-PRINCIPLES.md"; _ot_disp_kit "$d/ot8b"
  _ot_gh "$d/ot8b" 1 gate-secret-scan gate-lint
  _ot_case OT8b "$d/ot8b" 1 "gate-test" "disposition present, an APPLY id deleted -> RED naming it"

  # OT9 — a reasonless `na` is a SILENT WIDENING and must FAIL LOUD naming the line.
  mkdir -p "$d/ot9/conformance"; : > "$d/ot9/ENGINEERING-PRINCIPLES.md"
  # shellcheck disable=SC2086
  _ot_gh "$d/ot9" 1 $ALLG
  { printf 'gate-secret-scan\tapply\tshipped\n'; printf 'gate-test\tapply\tbattery\n'
    printf 'gate-lint\tapply\tlint\n';           printf 'gate-type-check\tna\treason\n'
    printf 'gate-build\tna\n';                   printf 'gate-dep-scan\tna\treason\n'
    printf 'gate-sbom\tna\treason\n';            printf 'gate-provenance\tna\treason\n'
  } > "$d/ot9/conformance/gate-dispositions.txt"
  _ot_case OT9 "$d/ot9" 1 "non-empty reason" "reasonless na -> FAIL naming the line"

  # OT9b — a WHITESPACE-ONLY `na` reason is the SAME silent widening and must FAIL naming the
  # line (reviewer LOW-3: without the trim, `na<TAB>   ` slips the lock OT9 witnesses — the
  # security seat's trailing-TAB-empty variant already reds via the same test; both stay green).
  mkdir -p "$d/ot9b/conformance"; : > "$d/ot9b/ENGINEERING-PRINCIPLES.md"
  # shellcheck disable=SC2086
  _ot_gh "$d/ot9b" 1 $ALLG
  { printf 'gate-secret-scan\tapply\tshipped\n'; printf 'gate-test\tapply\tbattery\n'
    printf 'gate-lint\tapply\tlint\n';           printf 'gate-type-check\tna\treason\n'
    printf 'gate-build\tna\t   \n';              printf 'gate-dep-scan\tna\treason\n'
    printf 'gate-sbom\tna\treason\n';            printf 'gate-provenance\tna\treason\n'
  } > "$d/ot9b/conformance/gate-dispositions.txt"
  _ot_case OT9b "$d/ot9b" 1 "whitespace-only counts as empty" "whitespace-only na reason -> FAIL naming the line"

  # OT10 — a DUPLICATE id must FAIL naming the line (exactly-once is the contract).
  mkdir -p "$d/ot10"; : > "$d/ot10/ENGINEERING-PRINCIPLES.md"
  # shellcheck disable=SC2086
  _ot_gh "$d/ot10" 1 $ALLG
  _ot_disp_kit "$d/ot10"; printf 'gate-lint\tapply\tagain\n' >> "$d/ot10/conformance/gate-dispositions.txt"
  _ot_case OT10 "$d/ot10" 1 "more than once" "duplicate id line -> FAIL naming it"

  # OT11 — a MISSING id must FAIL (an absent line is an UNDECIDED gate, not an exemption).
  mkdir -p "$d/ot11/conformance"; : > "$d/ot11/ENGINEERING-PRINCIPLES.md"
  # shellcheck disable=SC2086
  _ot_gh "$d/ot11" 1 $ALLG
  grep -v '^gate-provenance' "$d/ot10/conformance/gate-dispositions.txt" | grep -v 'again' \
    > "$d/ot11/conformance/gate-dispositions.txt"
  _ot_case OT11 "$d/ot11" 1 "missing an entry for gate-provenance" "missing id line -> FAIL naming it"

  # OT12 — THE LOUD ZERO (self-review finding 5): all 8 dispositioned na is NEVER a bare green —
  # the OK line must say the pipeline is judged against NOTHING and list the set. A bare OK here
  # is a leg failure.
  mkdir -p "$d/ot12/conformance"; : > "$d/ot12/ENGINEERING-PRINCIPLES.md"
  _ot_gh "$d/ot12" 1
  { for _g12 in $ALLG; do printf '%s\tna\tdecided elsewhere\n' "$_g12"; done
  } > "$d/ot12/conformance/gate-dispositions.txt"
  _ot_case OT12 "$d/ot12" 0 "judged against NOTHING" "all-8-na disposition -> LOUD zero, never a bare green"
  _st_mark OT

  # ── B8 legs (GATE-PROVENANCE-SELF-DISABLES-AND-NEVER-GATES-THE-MERGE, PHASE-B-SPINE) ───────────
  # `--disposition <gate-id> <file>` — single-sourced query mode reusing read_dispositions verbatim
  # (release-tag.sh's provenance_gate calls this rather than minting a third parser; see
  # docs/architecture/2026-08-08-b8-provenance-honesty-design.md §4.1). Prints exactly apply|na|absent.
  _dq_case() { # <name> <gate> <file> <want-out> <desc> — drives the REAL entry point, not the function
    _dqn=$1; _dqg=$2; _dqf=$3; _dqw=$4; _dqd=$5
    _dqo=$(sh "$0" --disposition "$_dqg" "$_dqf" 2>/dev/null)
    if [ "$_dqo" = "$_dqw" ]; then
      echo "selftest PASS: $_dqn — $_dqd"
    else
      echo "selftest FAIL: $_dqn — $_dqd (got '$_dqo' want '$_dqw')"; sf=1
    fi
  }
  mkdir -p "$d/dq1"; _ot_disp_kit "$d/dq1"
  _dq_case DQ1 gate-secret-scan "$d/dq1/conformance/gate-dispositions.txt" apply "an apply-dispositioned gate -> prints apply"
  _dq_case DQ2 gate-provenance "$d/dq1/conformance/gate-dispositions.txt" na "an na-dispositioned gate -> prints na"
  _dq_case DQ3 gate-provenance "$d/does-not-exist/gate-dispositions.txt" absent "no disposition file at the path -> prints absent"
  mkdir -p "$d/dq4/conformance"
  printf 'gate-lint\tbogus-kind\treason\n' > "$d/dq4/conformance/gate-dispositions.txt"
  _dq_case DQ4 gate-lint "$d/dq4/conformance/gate-dispositions.txt" apply "an INVALID disposition file -> fails safe to apply (loud, never quiet)"
  # DQ4b: the invalid-file case must WARN on stderr — fail-safe toward LOUD, never silent.
  if _dq4err=$(sh "$0" --disposition gate-lint "$d/dq4/conformance/gate-dispositions.txt" 2>&1 >/dev/null); then :; fi
  if printf '%s' "$_dq4err" | grep -qi "fail-safe"; then
    echo "selftest PASS: DQ4b — an invalid disposition file WARNS on stderr (not silently loud)"
  else
    echo "selftest FAIL: DQ4b — an invalid disposition file must warn on stderr: $_dq4err"; sf=1
  fi
  # DQ5 (mutant-kill anchor for the fail-safe direction): an invalid file must NEVER print na — that
  # would be the fail-quiet direction the design explicitly rejects (§4.1: "defaults to apply — fail-
  # safe toward loud"). A mutant that flips the default to `na` survives DQ4 only if DQ4's fixture
  # gate happens to already be apply-shaped elsewhere; this leg targets the value directly.
  # [reviewer Minor-5a, fix round 1]: asserts on its OWN freshly-captured output, not on `$_dqo`
  # left over from DQ4's LAST `_dq_case` call — `_dqo` is a plain (non-`local`) shell variable in
  # `_dq_case`, so it leaks across calls; a prior leg's value happening to already be non-`na`
  # would let this leg pass vacuously without ever driving the real entry point itself.
  _dq5o=$(sh "$0" --disposition gate-lint "$d/dq4/conformance/gate-dispositions.txt" 2>/dev/null)
  if [ "$_dq5o" != "na" ]; then
    echo "selftest PASS: DQ5 — invalid-file fail-safe never yields 'na' (the fail-quiet direction is closed)"
  else
    echo "selftest FAIL: DQ5 — invalid-file fail-safe yielded 'na' (fail-quiet, not fail-safe)"; sf=1
  fi
  _st_mark DQ

  # RP2/RP3/RP5/RP6 (SWAS-306) — the runner-pin lock (RP). Hermetic: fixtures only, no kit tree needed.
  # Every negative must RED and name its token and file; a function that is absent cannot pass a negative.
  mkdir -p "$d/rp"
  _rp_neg() { # <id> <want-token> <desc> <yaml-line> — one code line that must RED
    printf 'jobs:\n  j:\n    %s\n' "$4" > "$d/rp/$1.yml"
    if _rp_o=$(check_runner_pinned "$d/rp/$1.yml" 2>&1); then
      echo "selftest FAIL: $1 — $3 was NOT caught"; sf=1
    elif printf '%s\n' "$_rp_o" | grep -qF -- "'$2'" && printf '%s\n' "$_rp_o" | grep -qF -- "$d/rp/$1.yml"; then
      echo "selftest PASS: $1 — $3 -> RED, naming '$2' and the file"
    else echo "selftest FAIL: $1 — $3 reds without naming '$2' and the file: $_rp_o"; sf=1; fi
  }
  _rp_neg RP2a ubuntu-latest "runs-on: ubuntu-latest" 'runs-on: ubuntu-latest'
  _rp_neg RP2b ubuntu-latest "an expression fallback to ubuntu-latest" "runs-on: \${{ vars.X || 'ubuntu-latest' }}"
  _rp_neg RP2c ubuntu-latest "a matrix os: [ubuntu-latest]" 'matrix: { os: [ubuntu-latest] }'
  _rp_neg RP2d ubuntu-22.04 "a wrong pin, ubuntu-22.04" 'runs-on: ubuntu-22.04'
  _rp_neg RP2e ubuntu-slim "runs-on: ubuntu-slim" 'runs-on: ubuntu-slim'
  _rp_neg RP2f ubuntu-latest "a mixed-case Ubuntu-Latest" 'runs-on: Ubuntu-Latest'
  _rp_neg RP2g ubuntu-latest "a trailing hyphen, ubuntu-latest-" 'runs-on: ubuntu-latest-'
  { printf 'jobs:\n  j:\n'
    printf '    # ubuntu-latest moved to 26\n'
    printf '    runs-on: ubuntu-24.04\n'
    printf "    container: { image: ubuntu:26.04 }\n"
    printf "    env: { R: \"\${{ vars.X || 'ubuntu-24.04' }}\" }\n"
    printf '    steps:\n      - run: echo "the label is ubuntu-24.04."\n'
  } > "$d/rp/RP3.yml"
  if _rp_o=$(check_runner_pinned "$d/rp/RP3.yml" 2>&1); then
    echo "selftest PASS: RP3 — a comment, the pin, a container tag, an expression fallback and a sentence-final pin all pass"
  else echo "selftest FAIL: RP3 — an allowed shape was rejected: $_rp_o"; sf=1; fi
  mkdir -p "$d/rp5/.github/workflows" "$d/rp5/docs" "$d/rp5b/.github/workflows" "$d/rp5b/docs"
  : > "$d/rp5/docs/ROADMAP-KIT.md"; : > "$d/rp5b/docs/ROADMAP-KIT.md"
  printf 'jobs:\n  j:\n    runs-on: self-hosted\n' > "$d/rp5b/.github/workflows/x.yml"
  _ot_case RP5 "$d/rp5" 1 "RP liveness" "a kit tree with an empty .github/workflows -> RED (a glob that matched nothing must not pass)"
  _ot_case RP5b "$d/rp5b" 1 "RP liveness" "a kit tree whose workflows hold no ubuntu- token -> RED"
  mkdir -p "$d/rp6"; : > "$d/rp6/ENGINEERING-PRINCIPLES.md"
  # shellcheck disable=SC2086 # $ALLG is a deliberate word-list
  _ot_gh "$d/rp6" 1 $ALLG
  printf '  other:\n    runs-on: ubuntu-latest\n' >> "$d/rp6/.github/workflows/ci.yml"
  _ot_case RP6 "$d/rp6" 0 "OK: ci-gates --own-tree" "an adopter tree on ubuntu-latest -> green (RP is N/A off a kit tree)"
  _st_mark RP

  # OT13/OT14 — KIT-SOURCE legs (skip with a reason off-kit: the ruling lock binds the KIT's
  # shipped file; an adopter tree has no such file — and MAY author its own, which must not red).
  _kr="$(dirname "$0")/.."
  if [ -f "$_kr/docs/ROADMAP-KIT.md" ] || [ -f "$_kr/.github/workflows/golden-path.yml" ]; then
    # OT13 — THE RULING LOCK (self-review finding 2, the claim-gate-counts literal-lock pattern):
    # the SHIPPED kit file's apply set is EXACTLY {gate-secret-scan, gate-test, gate-lint} —
    # D-240805-2's trio, literal. A ratified-but-sloppy edit that drifts it REDs here and must be
    # changed IN THE SAME SLICE as this leg, citing the ruling (or its successor under the
    # REVISIT-CONDITION: the kit ships a build artifact).
    _rl_want="gate-lint gate-secret-scan gate-test"
    _rl_got=$(awk -F'\t' '!/^[[:space:]]*#/ && NF>=2 && $2=="apply" {print $1}' \
      "$_kr/conformance/gate-dispositions.txt" 2>/dev/null | sort | tr '\n' ' ')
    _rl_got=${_rl_got% }
    if [ "$_rl_got" = "$_rl_want" ]; then
      echo "selftest PASS: OT13 — the shipped disposition file's apply set == the D-240805-2 trio (ruling-locked)"
    else
      echo "selftest FAIL: OT13 — the shipped kit disposition drifted from D-240805-2 (got '$_rl_got', want '$_rl_want')"; sf=1
    fi
    # OT14 — the kit-side AC: delete `id: gate-test` from a SCRATCH COPY of the real ci.yml
    # (never the tracked file) -> RED naming gate-test under the kit's own disposition.
    mkdir -p "$d/ot14/.github/workflows" "$d/ot14/docs" "$d/ot14/conformance"
    : > "$d/ot14/docs/ROADMAP-KIT.md"
    grep -v 'id: gate-test' "$_kr/.github/workflows/ci.yml" > "$d/ot14/.github/workflows/ci.yml"
    cp "$_kr/conformance/gate-dispositions.txt" "$d/ot14/conformance/gate-dispositions.txt"
    _ot_case OT14 "$d/ot14" 1 "gate-test" "the real ci.yml minus id: gate-test -> RED (kit-side AC)"
    # PC0-PC8 (SWAS-274) — the PR-cancel lock. PC0 is the positive control on both REAL workflows; each mutant
    # below is a SCRATCH COPY of the real ci.yml and must red AND name its cause. A mutant is only judged
    # when PC0 is green, so a missing block cannot make every mutant red for the wrong reason.
    mkdir -p "$d/pc"
    _pc_ctl=0
    for _pc_w in ci.yml golden-path.yml; do
      if check_pr_concurrency "$_kr/.github/workflows/$_pc_w" >/dev/null 2>&1; then
        echo "selftest PASS: PC0 — the real $_pc_w carries the exact concurrency block"
      else echo "selftest FAIL: PC0 — the real $_pc_w does not carry the exact concurrency block (SWAS-274)"; sf=1; _pc_ctl=1; fi
    done
    _pc_real="$_kr/.github/workflows/ci.yml"
    if [ "$_pc_ctl" = 0 ]; then
      sed "s/^  cancel-in-progress:.*/  cancel-in-progress: true/" "$_pc_real" > "$d/pc/m1.yml"
      sed "s/ && github.event.action == 'synchronize'//" "$_pc_real" > "$d/pc/m2.yml"
      sed 's/^  group:.*/  group: ${{ github.workflow }}-${{ github.ref }}/' "$_pc_real" > "$d/pc/m3.yml"
      sed 's/^  group:.*/  group: ${{ github.event.pull_request.number || github.run_id }}/' "$_pc_real" > "$d/pc/m4.yml"
      sed '/^concurrency:/,/^  cancel-in-progress:/d' "$_pc_real" > "$d/pc/m5.yml"
      awk '{ print } $0 == "  changes:" { print "    concurrency:"; print "      group: x" }' "$_pc_real" > "$d/pc/m6.yml"
      awk '{ print } $0 == "  changes:" { print "    \"concurrency\": x" }' "$_pc_real" > "$d/pc/m7.yml"
      for _pc_m in "m1:cancel-in-progress:PC1:cancel-in-progress true (the main exemption dropped)" \
                   "m2:cancel-in-progress:PC2:the synchronize condition dropped" \
                   "m3:concurrency group:PC3:group on github.ref" \
                   "m4:concurrency group:PC4:group without github.workflow" \
                   "m5:exactly once:PC5:the block deleted" \
                   "m6:exactly once:PC6:a second concurrency: key nested under the first real job" \
                   "m7:exactly once:PC6b:a quoted concurrency key under a job"; do
        _pc_f=${_pc_m%%:*}; _pc_r=${_pc_m#*:}; _pc_want=${_pc_r%%:*}; _pc_r=${_pc_r#*:}
        _pc_id=${_pc_r%%:*}; _pc_desc=${_pc_r#*:}
        if _pc_o=$(check_pr_concurrency "$d/pc/$_pc_f.yml" 2>&1); then
          echo "selftest FAIL: $_pc_id — $_pc_desc was NOT caught"; sf=1
        elif printf '%s\n' "$_pc_o" | grep -qF -- "$_pc_want"; then
          echo "selftest PASS: $_pc_id — $_pc_desc -> RED, naming '$_pc_want'"
        else echo "selftest FAIL: $_pc_id — $_pc_desc reds without naming '$_pc_want': $_pc_o"; sf=1; fi
      done
      # PC7/PC8 — the --own-tree wiring, through the REAL entry point on a kit-marked scratch tree: the real
      # pair is green, and the same tree with a mutated ci.yml is RED naming the cancel line.
      mkdir -p "$d/pc7/.github/workflows" "$d/pc7/docs" "$d/pc7/conformance"
      : > "$d/pc7/docs/ROADMAP-KIT.md"
      cp "$_pc_real" "$d/pc7/.github/workflows/ci.yml"
      cp "$_kr/.github/workflows/golden-path.yml" "$d/pc7/.github/workflows/golden-path.yml"
      cp "$_kr/conformance/gate-dispositions.txt" "$d/pc7/conformance/gate-dispositions.txt"
      _ot_case PC7 "$d/pc7" 0 "OK: ci-gates --own-tree" "the real pair on a kit-marked tree -> green"
      cp "$d/pc/m1.yml" "$d/pc7/.github/workflows/ci.yml"
      _ot_case PC8 "$d/pc7" 1 "cancel-in-progress" "--own-tree reds a kit tree whose ci.yml cancels every run"
    fi
    # SP0-SP3 (SWAS-278 278a) — the SAST-parse spans lock. SP0 is the positive control on the REAL ci.yml; each mutant
    # is a SCRATCH COPY of it and must red AND name its cause (judged only when SP0 is green, so a missing line cannot
    # make a mutant red for the wrong reason). SP1 deletes the spans line; SP2 drops its `|| true`; SP3 runs the
    # deletion through the REAL --own-tree entry point on the kit-marked scratch tree.
    mkdir -p "$d/sp"
    _sp_real="$_kr/.github/workflows/ci.yml"
    if check_sast_parse_spans "$_sp_real" >/dev/null 2>&1; then
      echo "selftest PASS: SP0 — the real ci.yml's SAST parse coverage step prints semgrep's error spans, non-fatally"
      grep -v 'semgrep-span:' "$_sp_real" > "$d/sp/m1.yml"
      sed '/semgrep-span:/s/ || true[[:space:]]*$//' "$_sp_real" > "$d/sp/m2.yml"
      grep -v 'semgrep-loc:' "$_sp_real" > "$d/sp/m4.yml"
      sed '/semgrep-loc:/s/ || true[[:space:]]*$//' "$_sp_real" > "$d/sp/m5.yml"
      grep -v 'echo "semgrep-bisect: ' "$_sp_real" > "$d/sp/m6.yml"
      sed 's/_spc_bisect "\$_spc_f" || true;/_spc_bisect "$_spc_f";/' "$_sp_real" > "$d/sp/m7.yml"
      for _sp_m in "m1:exactly one jq -r line printing each semgrep error's spans:SP1:the spans line deleted" \
                   "m6:printing the prefix-bisect result:SP6:the bisect line deleted" \
                   "m7:prefix-bisect call must appear once and end '|| true':SP7:the bisect made fatal (|| true dropped)" \
                   "m2:semgrep-span line must end '|| true':SP2:the spans line made fatal (|| true dropped)" \
                   "m4:printing each PartialParsing location:SP4:the semgrep-loc line deleted" \
                   "m5:semgrep-loc line must end '|| true':SP5:the semgrep-loc line made fatal (|| true dropped)"; do
        _sp_f=${_sp_m%%:*}; _sp_r=${_sp_m#*:}; _sp_want=${_sp_r%%:*}; _sp_r=${_sp_r#*:}
        _sp_id=${_sp_r%%:*}; _sp_desc=${_sp_r#*:}
        if cmp -s "$_sp_real" "$d/sp/$_sp_f.yml"; then
          echo "selftest FAIL: $_sp_id — the mutant equals the original (nothing to mutate; the spans line is not pinned)"; sf=1
        elif _sp_o=$(check_sast_parse_spans "$d/sp/$_sp_f.yml" 2>&1); then
          echo "selftest FAIL: $_sp_id — $_sp_desc was NOT caught"; sf=1
        elif printf '%s\n' "$_sp_o" | grep -qF -- "$_sp_want"; then
          echo "selftest PASS: $_sp_id — $_sp_desc -> RED, naming '$_sp_want'"
        else echo "selftest FAIL: $_sp_id — $_sp_desc reds without naming '$_sp_want': $_sp_o"; sf=1; fi
      done
      mkdir -p "$d/sp3/.github/workflows" "$d/sp3/docs" "$d/sp3/conformance"
      : > "$d/sp3/docs/ROADMAP-KIT.md"
      cp "$_kr/conformance/gate-dispositions.txt" "$d/sp3/conformance/gate-dispositions.txt"
      cp "$d/sp/m1.yml" "$d/sp3/.github/workflows/ci.yml"
      _ot_case SP3 "$d/sp3" 1 "semgrep error's spans" "--own-tree reds a kit tree whose SAST parse step lost its spans line"
    else
      echo "selftest FAIL: SP0 — the real ci.yml's SAST parse coverage step does not print semgrep's error spans (SWAS-278 278a)"; sf=1
    fi
    # GD0-GD9 (SWAS-301 301a) — the guard-delta job lock. GD0 is the positive control on the REAL ci.yml; each mutant is a
    # SCRATCH COPY and must red AND name its cause (judged only when GD0 is green). GD1 deletes the job, GD2 appends `|| true`
    # to the --delta line, GD3 pins the base to HEAD (the vacuous comparison), GD5 narrows the skip's diff to guard-core.sh alone,
    # GD6 makes the skip silent, GD7 drops the timeout, GD8 unwires the job from the required aggregator, GD4 runs the deletion
    # through the REAL --own-tree entry point on a kit-marked scratch tree, and GD9 is the behavioural leg (a real git fixture).
    mkdir -p "$d/gd"
    _gd_real="$_kr/.github/workflows/ci.yml"
    if check_guard_delta_step "$_gd_real" >/dev/null 2>&1; then
      echo "selftest PASS: GD0 — the real ci.yml's guard-delta job runs --delta against HEAD^1's core, skips only explicitly, unmasked and wired"
      awk '/^  guard-delta:/ { skip = 1; next } skip && /^  [a-z]/ { skip = 0 } !skip' "$_gd_real" > "$d/gd/m1.yml"
      sed 's/pristine-core\.sh"$/pristine-core.sh" || true/' "$_gd_real" > "$d/gd/m2.yml"
      sed 's/base=\$(git rev-parse HEAD^1)/base=$(git rev-parse HEAD)/' "$_gd_real" > "$d/gd/m3.yml"
      sed 's/ -- \.claude\/hooks\/ \.claude\/mcp-policy\.json/ -- .claude\/hooks\/guard-core.sh .claude\/mcp-policy.json/' "$_gd_real" > "$d/gd/m5.yml"
      sed '/echo "SKIP: guard delta/d' "$_gd_real" > "$d/gd/m6.yml"
      sed '/^    timeout-minutes: /d' "$_gd_real" > "$d/gd/m7.yml"
      sed 's/cf-green-on-clone, guard-battery, guard-delta, boundary-redteam\]/cf-green-on-clone, guard-battery, boundary-redteam]/' "$_gd_real" > "$d/gd/m8.yml"
      for _gd_m in "m1:exactly one 'guard-delta' job:GD1:the guard-delta job deleted" \
                   "m2:with nothing after it, so its failure is not masked:GD2:the --delta line made soft with '|| true'" \
                   "m3:a base pinned to HEAD compares a core with itself:GD3:the base pinned to HEAD (vacuous)" \
                   "m5:compare the WHOLE .claude/hooks/ directory:GD5:the skip narrowed to guard-core.sh alone" \
                   "m6:print an explicit 'SKIP:GD6:the skip made silent" \
                   "m7:timeout-minutes bound:GD7:the timeout removed" \
                   "m8:does not name guard-delta in its needs:GD8:the job unwired from the required aggregator"; do
        _gd_f=${_gd_m%%:*}; _gd_r=${_gd_m#*:}; _gd_want=${_gd_r%%:*}; _gd_r=${_gd_r#*:}
        _gd_id=${_gd_r%%:*}; _gd_desc=${_gd_r#*:}
        if cmp -s "$_gd_real" "$d/gd/$_gd_f.yml"; then
          echo "selftest FAIL: $_gd_id — the mutant equals the original (nothing to mutate; the step is not pinned)"; sf=1
        elif _gd_o=$(check_guard_delta_step "$d/gd/$_gd_f.yml" 2>&1); then
          echo "selftest FAIL: $_gd_id — $_gd_desc was NOT caught"; sf=1
        elif printf '%s\n' "$_gd_o" | grep -qF -- "$_gd_want"; then
          echo "selftest PASS: $_gd_id — $_gd_desc -> RED, naming '$_gd_want'"
        else echo "selftest FAIL: $_gd_id — $_gd_desc reds without naming '$_gd_want': $_gd_o"; sf=1; fi
      done
      mkdir -p "$d/gd4/.github/workflows" "$d/gd4/docs" "$d/gd4/conformance"
      : > "$d/gd4/docs/ROADMAP-KIT.md"
      cp "$_kr/conformance/gate-dispositions.txt" "$d/gd4/conformance/gate-dispositions.txt"
      cp "$d/gd/m1.yml" "$d/gd4/.github/workflows/ci.yml"
      _ot_case GD4 "$d/gd4" 1 "exactly one 'guard-delta' job" "--own-tree reds a kit tree whose workflow lost the guard-delta job"
      # GD9 — the behavioural leg. The skip's pathspec is read OUT OF the real ci.yml and run in a throwaway git repo: a change to
      # guard.sh ALONE must not skip (the diff reports a difference), a change outside the hook files must skip, and the
      # guard-core.sh-only pathspec of GD5 would wrongly skip the guard.sh change, which shows the fixture is sensitive to it.
      _gd_ln=$(grep -F 'git diff --quiet "$base" HEAD -- ' "$_gd_real" | head -n 1)
      _gd_spec=${_gd_ln#*HEAD -- }; _gd_spec=${_gd_spec%%; then*}
      _gd_fx="$d/gdfx"; mkdir -p "$_gd_fx/.claude/hooks" "$_gd_fx/docs"
      _gd_git() { git -C "$_gd_fx" -c user.name=gd -c user.email=gd@example.invalid -c commit.gpgsign=false "$@"; }
      if [ -n "$_gd_spec" ] && _gd_git init -q . >/dev/null 2>&1; then
        printf 'a\n' > "$_gd_fx/.claude/hooks/guard-core.sh"; printf 'a\n' > "$_gd_fx/.claude/hooks/guard.sh"; printf 'a\n' > "$_gd_fx/docs/x.md"
        _gd_git add -A >/dev/null 2>&1; _gd_git commit -q -m base >/dev/null 2>&1
        printf 'b\n' > "$_gd_fx/.claude/hooks/guard.sh"
        _gd_git commit -q -a -m guard-sh-only >/dev/null 2>&1
        # shellcheck disable=SC2086  # the pathspec words are the point; none holds a glob byte
        if _gd_git diff --quiet HEAD^ HEAD -- $_gd_spec; then
          echo "selftest FAIL: GD9a — a guard.sh-only change would SKIP the guard delta (pathspec [$_gd_spec])"; sf=1
        else echo "selftest PASS: GD9a — a change to guard.sh alone does NOT skip the guard delta"; fi
        # shellcheck disable=SC2086
        if _gd_git diff --quiet HEAD^ HEAD -- .claude/hooks/guard-core.sh .claude/mcp-policy.json .kit/roster.conf; then
          echo "selftest PASS: GD9b — the narrowed (guard-core.sh only) pathspec WOULD skip it, so the fixture is sensitive to the narrowing"
        else echo "selftest FAIL: GD9b — the fixture does not distinguish the narrowed pathspec"; sf=1; fi
        printf 'b\n' > "$_gd_fx/docs/x.md"; _gd_git commit -q -a -m docs-only >/dev/null 2>&1
        # shellcheck disable=SC2086
        if _gd_git diff --quiet HEAD^ HEAD -- $_gd_spec; then
          echo "selftest PASS: GD9c — a change outside the hook files SKIPs the guard delta"
        else echo "selftest FAIL: GD9c — a docs-only change would not skip (pathspec [$_gd_spec])"; sf=1; fi
      else echo "selftest FAIL: GD9 — could not read the skip pathspec from ci.yml or initialise the fixture repo"; sf=1; fi
    else
      echo "selftest FAIL: GD0 — the real ci.yml's guard-delta job is not sound (SWAS-301 301a)"; sf=1
    fi
    # BR0-BR9 (SWAS-359 352a) — the boundary-redteam job lock. BR0 is the positive control on the REAL ci.yml; each mutant is a SCRATCH COPY
    # and must red AND name its cause. BR1 deletes the job, BR2 drops the timeout, BR3 drops the diff gate (the pathspec), BR4 makes the skip
    # silent, BR5 unwires the job from the required aggregator, BR6 adds continue-on-error, BR7 removes --report-only (the job is report-only
    # until 352b, and the lock names that state), BR8 ungates the live run from the diff gate, BR9 runs the deletion through the REAL --own-tree.
    mkdir -p "$d/br"
    _br_real="$_kr/.github/workflows/ci.yml"
    if check_boundary_redteam_step "$_br_real" >/dev/null 2>&1; then
      echo "selftest PASS: BR0 — the real ci.yml's boundary-redteam job is diff-gated with an explicit skip, bounded, report-only, unmasked and wired"
      awk '/^  boundary-redteam:/ { skip = 1; next } skip && /^  [a-z]/ { skip = 0 } !skip' "$_br_real" > "$d/br/m1.yml"
      awk '/^  boundary-redteam:/ { inb = 1 } inb && /^    timeout-minutes: / { inb = 0; next } { print }' "$_br_real" > "$d/br/m2.yml"
      sed 's/ -- \.claude\/settings\.json templates\/sandbox-strict\.settings\.local\.json conformance\/guard-wired\.sh docs\/patches\/2026-10-25-boundary-default-352b\.settings\.patch conformance\/boundary-redteam\.sh;/ -- conformance\/boundary-redteam.sh;/' "$_br_real" > "$d/br/m3.yml"
      sed 's/ docs\/patches\/2026-10-25-boundary-default-352b\.settings\.patch conformance\/boundary-redteam\.sh;/ conformance\/boundary-redteam.sh;/' "$_br_real" > "$d/br/m28.yml"
      sed '/echo "SKIP: boundary red-team/d' "$_br_real" > "$d/br/m4.yml"
      sed 's/guard-battery, guard-delta, boundary-redteam\]/guard-battery, guard-delta]/' "$_br_real" > "$d/br/m5.yml"
      awk '/^  boundary-redteam:/ { print; print "    continue-on-error: true"; next } { print }' "$_br_real" > "$d/br/m6.yml"
      sed 's/boundary-redteam\.sh --report-only || rc=\$?/boundary-redteam.sh || rc=$?/' "$_br_real" > "$d/br/m7.yml"
      awk '/^        if: steps\.gate\.outputs\.live == .yes.$/ { n++; if (n == 4) next } { print }' "$_br_real" > "$d/br/m8.yml"
      sed 's/^\( *\)exit "\$rc"$/\1exit 0/' "$_br_real" > "$d/br/m10.yml"
      sed 's/boundary-redteam\.sh --report-only || rc=\$?/boundary-redteam.sh --report-only || true/' "$_br_real" > "$d/br/m11.yml"
      sed '/if \[ "\$rc" -eq 3 \]; then echo "::warning::/d' "$_br_real" > "$d/br/m12.yml"
      sed 's/ conformance\/boundary-redteam\.sh; then/; then/' "$_br_real" > "$d/br/m13.yml"
      sed 's/SWAS-354/SWAS-000/g' "$_br_real" > "$d/br/m14.yml"
      sed 's/boundary-redteam\.sh --selftest-core/boundary-redteam.sh --selftest/' "$_br_real" > "$d/br/m15.yml"
      sed '/^        run: sh conformance\/boundary-redteam\.sh --selftest  # full: all mutants$/d' "$_br_real" > "$d/br/m16.yml"
      awk '{ print } /boundary-redteam\.sh --report-only \|\| rc=\$\?/ { print "          if [ \"$rc\" -eq 2 ]; then exit 0; fi" }' "$_br_real" > "$d/br/m17.yml"
      # SWAS-363: BR17b-BR17g pin the live step's run body (an exact ordered sequence up to the dedent), BR18-BR18c pin the gate line on the named steps
      awk '{ print } /boundary-redteam\.sh --report-only \|\| rc=\$\?/ { print "          [ \"$rc\" -eq 3 ] || exit 0" }' "$_br_real" > "$d/br/m17b.yml"
      sed 's/if \[ "\$rc" -eq 3 \]; then echo/if [ "$rc" -eq 3 ] || [ "$rc" -ne 0 ]; then echo/' "$_br_real" > "$d/br/m17c.yml"
      awk '{ print } /boundary-redteam\.sh --report-only \|\| rc=\$\?/ { print "          rc=0" }' "$_br_real" > "$d/br/m17d.yml"
      awk '/boundary-redteam\.sh --report-only \|\| rc=\$\?/ { print "          exit 0" } { print }' "$_br_real" > "$d/br/m17e.yml"
      sed 's/(reason printed above); NO CELL RAN; green/(reason printed above); green/' "$_br_real" > "$d/br/m17f.yml"
      awk '{ print } /boundary-redteam\.sh --report-only \|\| rc=\$\?/ { print "          # x"; print "          rc=0" }' "$_br_real" > "$d/br/m17g.yml"
      awk '/^      - name: Boundary red-team harness full self-test/ { f = 1 } f && /^        if: / { print "        if: false"; f = 0; next } { print }' "$_br_real" > "$d/br/m18.yml"
      awk '/^      - name: Boundary red-team harness full self-test/ { f = 1 } f && /^        if: / { print "        if: false  # steps.gate.outputs.live == \047yes\047"; f = 0; next } { print }' "$_br_real" > "$d/br/m18b.yml"
      awk '/^      - name: Boundary red-team — live cells/ { f = 1 } f && /^        if: / { print "        # " substr($0, 9); f = 0; next } { print }' "$_br_real" > "$d/br/m18c.yml"
      # BR19-BR19g: nothing may change how the pinned steps run or what they inherit
      awk '/^      - name: Boundary red-team — live cells/ { f = 1 } { print } f && /^        if: / { print "        shell: sh {0}"; f = 0 }' "$_br_real" > "$d/br/m19.yml"
      awk '/^      - name: Boundary red-team harness full self-test/ { f = 1 } { print } f && /^        if: / { print "        env:"; f = 0 }' "$_br_real" > "$d/br/m19b.yml"
      awk '/^      - name: Install Node 24/ { f = 1 } { print } f && /^        if: / { print "        working-directory: /"; f = 0 }' "$_br_real" > "$d/br/m19c.yml"
      awk '/^      - name: Install Node 24/ { f = 1 } { print } f && /^        if: / { print "        continue-on-error: true"; f = 0 }' "$_br_real" > "$d/br/m19d.yml"
      awk '{ print } /^  boundary-redteam:/ { print "    defaults:" }' "$_br_real" > "$d/br/m19e.yml"
      awk 'NR == 1 { print "defaults:" } { print }' "$_br_real" > "$d/br/m19f.yml"
      awk '{ print } /^ +base=/ { print "          echo y >> \"$GITHUB_ENV\"" }' "$_br_real" > "$d/br/m19g.yml"
      awk '{ print } /^ +base=/ { print "          export BASH_ENV=/x" }' "$_br_real" > "$d/br/m19h.yml"
      awk '{ print } /^ +base=/ { print "          echo /x >> \"$GITHUB_PATH\"" }' "$_br_real" > "$d/br/m19i.yml"
      awk '/^  boundary-redteam:/ { j = 1 } j && /^        id: gate$/ { print; print "        shell: sh"; j = 0; next } { print }' "$_br_real" > "$d/br/m19j.yml"
      awk '/^  boundary-redteam:/ { j = 1 } j && /^        id: gate$/ { print; print "        if: false"; j = 0; next } { print }' "$_br_real" > "$d/br/m19k.yml"
      awk 'NR == 1 { print "env:"; print "  BASH_ENV: /x" } { print }' "$_br_real" > "$d/br/m19l.yml"
      awk '{ print } /^  boundary-redteam:/ { print "    env:" }' "$_br_real" > "$d/br/m19m.yml"
      # BR20-BR30 (SWAS-404): the candidate leg. Each mutant is a scratch copy of the real ci.yml and must red AND name its cause.
      awk '/^      - name: Boundary red-team — candidate leg/ { skip = 1; next } skip && /^      - / { skip = 0 } skip && /^  [a-z]/ { skip = 0 } !skip' "$_br_real" > "$d/br/m20.yml"
      awk '{ print } /^ +sh conformance\/boundary-redteam\.sh --settings .* --measure / { print }' "$_br_real" > "$d/br/m21.yml"
      sed 's/--measure C36,C37,C37c$/--measure C36,C37,C37c || true/' "$_br_real" > "$d/br/m22.yml"
      awk '{ print } /^ +sh conformance\/boundary-redteam\.sh --settings .* --measure / { print "          [ \"$?\" -eq 3 ] && exit 0" }' "$_br_real" > "$d/br/m23.yml"
      sed 's/!cancelled() [&][&] //' "$_br_real" > "$d/br/m24.yml"
      sed 's/strictAllowlist = true/strictAllowlist = false/' "$_br_real" > "$d/br/m25.yml"
      sed 's/--measure C36,C37,C37c$/--measure C36/' "$_br_real" > "$d/br/m26.yml"
      sed '/^          if git -C /d' "$_br_real" > "$d/br/m27.yml"
      sed '/^          test -f /d' "$_br_real" > "$d/br/m29.yml"
      sed 's/ conformance\/boundary-redteam\.sh; then/; then  # conformance\/boundary-redteam.sh;/' "$_br_real" > "$d/br/m30.yml"
      sed 's/ -- \.claude\/settings\.json templates/ -- templates/; s/boundary-redteam\.sh; then$/boundary-redteam.sh; then  # .claude\/settings.json/' "$_br_real" > "$d/br/m31.yml"
      for _br_m in "m20:the step named Boundary red-team — candidate leg:BR20:the candidate step deleted" \
                   "m21:must run the candidate leg:BR21:the candidate run line doubled" \
                   "m22:the candidate step's body must be exactly:BR22:|| true added to the candidate run line" \
                   "m23:the candidate step's body must be exactly:BR23:an exit 0 after exit 3 planted after the candidate run line" \
                   "m24:the step named Boundary red-team — candidate leg:BR24:!cancelled() dropped from the candidate step's if:" \
                   "m25:the candidate step's body must be exactly:BR25:the strictAllowlist jq line altered" \
                   "m26:the candidate step's body must be exactly:BR26:the candidate run line's --measure list narrowed" \
                   "m27:the candidate step's body must be exactly:BR27:the patch apply line removed" \
                   "m29:the candidate step's body must be exactly:BR29:the fail-closed patch presence test removed (a missing patch would be skipped silently)" \
                   "m28:candidate patch docs/patches/2026-10-25-boundary-default-352b.settings.patch:BR28:the candidate patch dropped from the diff gate (a patch-only PR would skip the measurement green)" \
                   "m30:the harness conformance/boundary-redteam.sh (diff lines:BR30:the harness dropped from the pathspec while a trailing comment still names it (only the full-pathspec pin sees it)" \
                   "m31:the harness conformance/boundary-redteam.sh (diff lines:BR31:.claude/settings.json dropped from the pathspec while a trailing comment still names it" \
                   "m19i:must not change how its steps run:BR19i:GITHUB_PATH written in the job" \
                   "m19j:must not change how its steps run:BR19j:a shell: key on the gate step" \
                   "m19k:must not change how its steps run:BR19k:an if: false on the gate step" \
                   "m19l:must not change how its steps run:BR19l:a workflow-level env: naming BASH_ENV" \
                   "m19m:must not change how its steps run:BR19m:a job-level env: key" \
                   "m19:must not change how its steps run:BR19:a shell: key added to the live step" \
                   "m19b:must not change how its steps run:BR19b:an env: key added to the full self-test step" \
                   "m19c:must not change how its steps run:BR19c:a working-directory: key added to the Node step" \
                   "m19d:must not change how its steps run:BR19d:continue-on-error added to a pinned step" \
                   "m19e:must not change how its steps run:BR19e:a defaults: key added to the job" \
                   "m19f:must not change how its steps run:BR19f:a top-level defaults: key added to the workflow" \
                   "m19g:must not change how its steps run:BR19g:a write to GITHUB_ENV planted in the job" \
                   "m19h:must not change how its steps run:BR19h:BASH_ENV exported in the job" \
                   "m15:mutant-free:BR15:the every-PR selftest step reverted to the full-mutant run" \
                   "m16:full-mutant:BR16:the full self-test removed from the diff-gated job" \
                   "m17:the run step's body must be exactly:BR17:an early exit 0 planted before the final exit" \
                   "m17b:the run step's body must be exactly:BR17b:[ \"\$rc\" -eq 3 ] || exit 0 planted after the harness line" \
                   "m17c:must stay a visible warning:BR17c:the warning condition widened so its exit 0 greens every failure" \
                   "m17d:the run step's body must be exactly:BR17d:rc=0 planted after the harness line (it resets the verdict)" \
                   "m17e:the run step's body must be exactly:BR17e:exit 0 planted before the harness line" \
                   "m17f:must stay a visible warning:BR17f:NO CELL RAN removed from the warning's echo" \
                   "m17g:the run step's body must be exactly:BR17g:a comment then rc=0 planted after the harness line (a comment does not end the block)" \
                   "m18:must be gated:BR18:the full self-test's if: set to false" \
                   "m18b:must be gated:BR18b:the full self-test's if: false hiding the gate text in a trailing comment" \
                   "m18c:must be gated:BR18c:the live step's if: line commented out" \
                   "m10:must be the pinned pair:BR10:the final exit made a constant exit 0" \
                   "m11:must be the pinned pair:BR11:the run line masked with || true" \
                   "m12:must stay a visible warning:BR12:the exit-3 warning removed (a silent green)" \
                   "m13:and the harness conformance/boundary-redteam.sh (diff lines:BR13:the harness dropped from the diff gate" \
                   "m14:must name SWAS-354:BR14:the report-only expiry card removed" \
                   "m1:exactly one 'boundary-redteam' job:BR1:the boundary-redteam job deleted" \
                   "m2:timeout-minutes bound:BR2:the timeout removed" \
                   "m3:must be diff-gated:BR3:the diff gate narrowed to the harness alone" \
                   "m4:must print an explicit:BR4:the skip made silent" \
                   "m5:does not name boundary-redteam in its needs:BR5:the job unwired from the required aggregator" \
                   "m6:carries continue-on-error:BR6:continue-on-error added" \
                   "m7:must carry --report-only until slice 352b:BR7:--report-only removed before the default lands" \
                   "m8:must be gated on steps.gate.outputs.live:BR8:the live steps ungated from the diff gate"; do
        _br_f=${_br_m%%:*}; _br_r=${_br_m#*:}; _br_want=${_br_r%%:*}; _br_r=${_br_r#*:}
        _br_id=${_br_r%%:*}; _br_desc=${_br_r#*:}
        if cmp -s "$_br_real" "$d/br/$_br_f.yml"; then
          echo "selftest FAIL: $_br_id — the mutant equals the original (nothing to mutate; the job is not pinned)"; sf=1
        elif _br_o=$(check_boundary_redteam_step "$d/br/$_br_f.yml" 2>&1); then
          echo "selftest FAIL: $_br_id — $_br_desc was NOT caught"; sf=1
        elif printf '%s\n' "$_br_o" | grep -qF -- "$_br_want"; then
          echo "selftest PASS: $_br_id — $_br_desc -> RED, naming '$_br_want'"
        else echo "selftest FAIL: $_br_id — $_br_desc reds without naming '$_br_want': $_br_o"; sf=1; fi
      done
      mkdir -p "$d/br9/.github/workflows" "$d/br9/docs" "$d/br9/conformance"
      : > "$d/br9/docs/ROADMAP-KIT.md"
      cp "$_kr/conformance/gate-dispositions.txt" "$d/br9/conformance/gate-dispositions.txt"
      cp "$d/br/m1.yml" "$d/br9/.github/workflows/ci.yml"
      _ot_case BR9 "$d/br9" 1 "exactly one 'boundary-redteam' job" "--own-tree reds a kit tree whose workflow lost the boundary-redteam job"
    else
      echo "selftest FAIL: BR0 — the real ci.yml's boundary-redteam job is not sound (SWAS-359 352a)"; sf=1
    fi
    # H2D0-H2D10 (SWAS-376 Slice 0, C2 + C4) — the H2 step's battery-defer lock. H2D0 is the positive control on the REAL ci.yml; each mutant is a
    # SCRATCH COPY and must red AND name its cause. The first occurrence only is mutated where another job repeats the text: H2 is the first
    # `gb-ref` clone in the file (cf-verify-enforced, cf-export-claims and cf-claims write the same variables to $GITHUB_ENV, legitimately).
    # H2D1 deletes the clone, H2D2/H2D3 drop one variable from the call, H2D4 writes a variable to $GITHUB_ENV inside the step, H2D5 adds a job
    # env: naming one to conformance-core, H2D6 deletes the step timeout, H2D7 changes it, H2D8 renames the step (the lock finds none),
    # H2D9 masks the call with `|| true`, H2D10 runs the clone deletion through the REAL --own-tree entry point.
    mkdir -p "$d/h2"
    _h2_real="$_kr/.github/workflows/ci.yml"
    if check_h2_defer_step "$_h2_real" >/dev/null 2>&1; then
      echo "selftest PASS: H2D0 — the real ci.yml's H2 step clones the workspace, passes the defer variables inline to the one lane call, is bounded at 180 min and leaves conformance-core's environment alone"
      awk '/git clone -q "\$GITHUB_WORKSPACE" "\$RUNNER_TEMP\/gb-ref"/ && !done { done = 1; next } { print }' "$_h2_real" > "$d/h2/m1.yml"
      sed '/^ *KIT_GUARD_BATTERY_REF="\$RUNNER_TEMP\/gb-ref" \\$/d' "$_h2_real" > "$d/h2/m2.yml"
      sed '/^ *KIT_GUARD_BATTERY_VARIANTS="case0-tmp0-git1-uid00 case0-tmp1-git1-uid00" \\$/d' "$_h2_real" > "$d/h2/m3.yml"
      awk '{ print } /git clone -q "\$GITHUB_WORKSPACE" "\$RUNNER_TEMP\/gb-ref"/ && !done { done = 1; print "          echo \"KIT_GUARD_BATTERY_REF=$RUNNER_TEMP/gb-ref\" >> \"$GITHUB_ENV\"" }' "$_h2_real" > "$d/h2/m4.yml"
      awk '{ print } /^  conformance-core:[ \t]*$/ { print "    env:"; print "      KIT_GUARD_BATTERY_REF: /x" }' "$_h2_real" > "$d/h2/m5.yml"
      awk '/^      - name: Fixture-hermeticity lane/ { inh = 1 } inh && /^        timeout-minutes: 180[ \t]*$/ { inh = 0; next } { print }' "$_h2_real" > "$d/h2/m6.yml"
      awk '/^      - name: Fixture-hermeticity lane/ { inh = 1 } inh && /^        timeout-minutes: 180[ \t]*$/ { inh = 0; print "        timeout-minutes: 360"; next } { print }' "$_h2_real" > "$d/h2/m7.yml"
      sed 's/^      - name: Fixture-hermeticity lane/      - name: Fixture hermeticity lane/' "$_h2_real" > "$d/h2/m8.yml"
      sed 's/^\( *\)sh conformance\/selftest-hermetic\.sh --touched$/\1sh conformance\/selftest-hermetic.sh --touched || true/' "$_h2_real" > "$d/h2/m9.yml"
      # H2D11-H2D19 (fix round): nothing may mask the lane's verdict. A step-level key that masks or changes it (continue-on-error, if, shell,
      # working-directory, env), a job-level continue-on-error, an `exit` before the call (other than the two pinned guard branches) or any line
      # after the call, and a GB_CONSUMERS without conformance-core (the deferral must be bound to guard-battery's result).
      for _h2_k in "m11:continue-on-error: true" "m12:if: false" "m13:shell: sh {0}" "m14:working-directory: /" "m15:env:"; do
        awk -v ins="        ${_h2_k#*:}" '/^      - name: Fixture-hermeticity lane/ { f = 1 } { print } f && /^        timeout-minutes: 180[ \t]*$/ { print ins; f = 0 }' "$_h2_real" > "$d/h2/${_h2_k%%:*}.yml"
      done
      awk '{ print } /^  conformance-core:[ \t]*$/ { print "    continue-on-error: true" }' "$_h2_real" > "$d/h2/m16.yml"
      awk '/git clone -q "\$GITHUB_WORKSPACE" "\$RUNNER_TEMP\/gb-ref"/ && !done { done = 1; print "          exit 0" } { print }' "$_h2_real" > "$d/h2/m17.yml"
      awk '{ print } /^ +sh conformance\/selftest-hermetic\.sh --touched[ \t]*$/ && !done { done = 1; print "          exit 0" }' "$_h2_real" > "$d/h2/m18.yml"
      sed 's/ \${{ needs\.conformance-core\.result }}$//' "$_h2_real" > "$d/h2/m19.yml"
      # security-confirm round: the H2 run body is pinned byte for byte (the BR17 method), not pattern-matched for exits. m20 flips the guard
      # condition (N/A and exit 0 on every PR), m21 duplicates the exempt echo+exit pair before the clone, m22 plants `exec true` (no `exit` word),
      # m23 changes the echo text, m24 deletes the fetch.
      awk '/^      - name: Fixture-hermeticity lane/ { f = 1 } f && !done && /^ +if \[ "\$GITHUB_EVENT_NAME" != "pull_request" \]/ { done = 1; sub(/if \[/, "if true || [") } { print }' "$_h2_real" > "$d/h2/m20.yml"
      awk '/git clone -q "\$GITHUB_WORKSPACE" "\$RUNNER_TEMP\/gb-ref"/ && !done { done = 1; print "          echo \"N/A by design: dup\""; print "          exit 0" } { print }' "$_h2_real" > "$d/h2/m21.yml"
      awk '/git clone -q "\$GITHUB_WORKSPACE" "\$RUNNER_TEMP\/gb-ref"/ && !done { done = 1; print "          exec true" } { print }' "$_h2_real" > "$d/h2/m22.yml"
      awk '/^      - name: Fixture-hermeticity lane/ { f = 1 } f && !done && /re-run nothing it has not already graded/ { done = 1; sub(/re-run nothing/, "re-run something") } { print }' "$_h2_real" > "$d/h2/m23.yml"
      awk '/^      - name: Fixture-hermeticity lane/ { f = 1 } f && !done && /^ +git fetch -q --no-tags origin/ { done = 1; next } { print }' "$_h2_real" > "$d/h2/m24.yml"
      # re-confirm round: P5 a comment or a blank line inside the run block joins the backslash continuation and unexports the inline assignments
      # (m25 a comment, m26 a blank line, both right after the VARIANTS line); P9 a job-level env: on conformance-core can re-point PATH (m27), and a
      # workflow-level env: naming PATH (m28) or BASH_ENV (m29) does the same for every job.
      awk '{ print } /^ +KIT_GUARD_BATTERY_VARIANTS="case0-tmp0-git1-uid00 case0-tmp1-git1-uid00" \\$/ { print "            # x" }' "$_h2_real" > "$d/h2/m25.yml"
      awk '{ print } /^ +KIT_GUARD_BATTERY_VARIANTS="case0-tmp0-git1-uid00 case0-tmp1-git1-uid00" \\$/ { print "" }' "$_h2_real" > "$d/h2/m26.yml"
      awk '{ print } /^  conformance-core:[ \t]*$/ { print "    env:"; print "      PATH: docs/bin:/usr/bin" }' "$_h2_real" > "$d/h2/m27.yml"
      awk 'NR == 1 { print "env:"; print "  PATH: docs/bin:/usr/bin" } { print }' "$_h2_real" > "$d/h2/m28.yml"
      awk 'NR == 1 { print "env:"; print "  BASH_ENV: /x" } { print }' "$_h2_real" > "$d/h2/m29.yml"
      for _h2_m in "m11:step-level key that masks:H2D11:continue-on-error on the step" \
                   "m12:step-level key that masks:H2D12:if: false on the step" \
                   "m13:step-level key that masks:H2D13:a shell: key on the step" \
                   "m14:step-level key that masks:H2D14:a working-directory: key on the step" \
                   "m15:step-level key that masks:H2D15:an env: key on the step" \
                   "m16:must not set a job-level:H2D16:continue-on-error on conformance-core" \
                   "m17:run body must be exactly:H2D17:an exit 0 planted before the lane call" \
                   "m18:run body must be exactly:H2D18:an exit 0 planted after the lane call" \
                   "m20:run body must be exactly:H2D20:the guard condition flipped (if true ||, N/A on every PR)" \
                   "m21:run body must be exactly:H2D21:the exempt echo+exit pair duplicated before the clone" \
                   "m22:run body must be exactly:H2D22:exec true planted before the clone (no exit word)" \
                   "m23:run body must be exactly:H2D23:the N/A echo text changed" \
                   "m24:run body must be exactly:H2D24:the base fetch deleted" \
                   "m25:run body must be exactly:H2D25:a comment line after the VARIANTS line (it would unexport the inline assignments)" \
                   "m26:run body must be exactly:H2D26:a blank line after the VARIANTS line" \
                   "m27:must not set a job-level:H2D27:a job-level env: re-pointing PATH on conformance-core" \
                   "m28:workflow-level env:H2D28:a workflow-level env: naming PATH" \
                   "m29:workflow-level env:H2D29:a workflow-level env: naming BASH_ENV" \
                   "m19:GB_CONSUMERS:H2D19:conformance-core dropped from GB_CONSUMERS (the deferral bound to nothing)"; do
        _h2_f=${_h2_m%%:*}; _h2_r=${_h2_m#*:}; _h2_want=${_h2_r%%:*}; _h2_r=${_h2_r#*:}
        _h2_id=${_h2_r%%:*}; _h2_desc=${_h2_r#*:}
        if cmp -s "$_h2_real" "$d/h2/$_h2_f.yml"; then
          echo "selftest FAIL: $_h2_id — the mutant equals the original (nothing to mutate; the step is not pinned)"; sf=1
        elif _h2_o=$(check_h2_defer_step "$d/h2/$_h2_f.yml" 2>&1); then
          echo "selftest FAIL: $_h2_id — $_h2_desc was NOT caught"; sf=1
        elif printf '%s\n' "$_h2_o" | grep -qF -- "$_h2_want"; then
          echo "selftest PASS: $_h2_id — $_h2_desc -> RED, naming '$_h2_want'"
        else echo "selftest FAIL: $_h2_id — $_h2_desc reds without naming '$_h2_want': $_h2_o"; sf=1; fi
      done
      for _h2_m in "m1:must clone the workspace to \$RUNNER_TEMP/gb-ref:H2D1:the same-commit clone deleted" \
                   "m2:must pass KIT_GUARD_BATTERY_REF and KIT_GUARD_BATTERY_VARIANTS inline:H2D2:KIT_GUARD_BATTERY_REF dropped from the call" \
                   "m3:must pass KIT_GUARD_BATTERY_REF and KIT_GUARD_BATTERY_VARIANTS inline:H2D3:KIT_GUARD_BATTERY_VARIANTS dropped from the call" \
                   "m4:must not write to GITHUB_ENV:H2D4:a defer variable written to \$GITHUB_ENV inside the step" \
                   "m5:no other line of conformance-core may name KIT_GUARD_BATTERY:H2D5:a job-level env: naming the variable" \
                   "m6:must carry timeout-minutes:H2D6:the step timeout deleted" \
                   "m7:must carry timeout-minutes:H2D7:the step timeout changed to 360" \
                   "m8:exactly one 'Fixture-hermeticity lane' step:H2D8:the step renamed so the lock finds none" \
                   "m9:must pass KIT_GUARD_BATTERY_REF and KIT_GUARD_BATTERY_VARIANTS inline:H2D9:the lane call masked with || true"; do
        _h2_f=${_h2_m%%:*}; _h2_r=${_h2_m#*:}; _h2_want=${_h2_r%%:*}; _h2_r=${_h2_r#*:}
        _h2_id=${_h2_r%%:*}; _h2_desc=${_h2_r#*:}
        if cmp -s "$_h2_real" "$d/h2/$_h2_f.yml"; then
          echo "selftest FAIL: $_h2_id — the mutant equals the original (nothing to mutate; the step is not pinned)"; sf=1
        elif _h2_o=$(check_h2_defer_step "$d/h2/$_h2_f.yml" 2>&1); then
          echo "selftest FAIL: $_h2_id — $_h2_desc was NOT caught"; sf=1
        elif printf '%s\n' "$_h2_o" | grep -qF -- "$_h2_want"; then
          echo "selftest PASS: $_h2_id — $_h2_desc -> RED, naming '$_h2_want'"
        else echo "selftest FAIL: $_h2_id — $_h2_desc reds without naming '$_h2_want': $_h2_o"; sf=1; fi
      done
      mkdir -p "$d/h2t/.github/workflows" "$d/h2t/docs" "$d/h2t/conformance"
      : > "$d/h2t/docs/ROADMAP-KIT.md"
      cp "$_kr/conformance/gate-dispositions.txt" "$d/h2t/conformance/gate-dispositions.txt"
      cp "$d/h2/m1.yml" "$d/h2t/.github/workflows/ci.yml"
      _ot_case H2D10 "$d/h2t" 1 "must clone the workspace to \$RUNNER_TEMP/gb-ref" "--own-tree reds a kit tree whose H2 step lost its same-commit clone"
    else
      echo "selftest FAIL: H2D0 — the real ci.yml's H2 step is not sound (SWAS-376 Slice 0)"; sf=1
    fi
    # GD10 (SWAS-332) — the guard-delta stress-cell exclusion lock. `agent-autonomy.sh --delta` does not replay a NAMED list of cap and
    # budget stress cells (AA_DELTA_STRESS: each replay pass over them costs minutes); the guard-battery job runs them with an asserted
    # DENY (an `scp_deny` cell), so a flipped verdict there is a bare-battery FAIL, not a delta finding. The lock: the list equals the
    # pinned set exactly, the exclusion code is in aa_cell_record, and every excluded id has an `scp_deny` cell. GD10 is the positive
    # control on the real file; each mutant is a scratch copy and must red AND name its cause.
    _gd_stress_pin='SC-D27 SC-D28 SC-D31 SC-D45 SC-P9 SC-P10'
    check_delta_stress() {   # <agent-autonomy.sh> -> rc 0 when the exclusion lock holds; names the break otherwise
      _ds_list=$(sed -n "s/^AA_DELTA_STRESS='\(.*\)'\$/\1/p" "$1" | head -n 1 | tr -s ' ' | sed 's/^ //; s/ $//')
      [ "$_ds_list" = "$_gd_stress_pin" ] || { echo "the exclusion list differs from the pinned set [$_ds_list]"; return 1; }
      # the exclusion code, anchored INSIDE aa_cell_record and not in a comment line (a commented-out copy does not count)
      sed -n '/^aa_cell_record() {/,/^}/p' "$1" | grep -v '^[[:space:]]*#' | grep -qF 'case "$1" in "$_as_id "*)' \
        || { echo "the exclusion code is gone from aa_cell_record (or only commented out)"; return 1; }
      grep -Eq '^AA_STRESS_PIN=9([^0-9]|$)' "$1" || { echo "the pinned count AA_STRESS_PIN=9 is gone"; return 1; }
      grep -qF 'AA_STRESS_N" -ne "$AA_STRESS_PIN"' "$1" || { echo "the --delta check of the excluded count against AA_STRESS_PIN is gone"; return 1; }
      for _ds_id in $_ds_list; do
        grep -Eq "^ *scp_deny [^ ]+ \"$_ds_id " "$1" || { echo "excluded id $_ds_id has no asserted-DENY cell in the guard-battery"; return 1; }
      done
      # every battery line that carries a stress id must be an `scp_deny ... C` cell (a reused id on another kind of cell is refused),
      # and there are exactly nine of them
      _ds_alt=$(printf '%s' "$_ds_list" | tr ' ' '|')
      _ds_bad=$(grep -E "\"($_ds_alt) " "$1" | grep -Ev '^ *scp_deny .* C$' | head -n 1)
      [ -z "$_ds_bad" ] || { echo "a line carries a stress id but is not an scp_deny C cell: $_ds_bad"; return 1; }
      _ds_n=$(grep -cE "\"($_ds_alt) " "$1")
      [ "$_ds_n" = 9 ] || { echo "the stress-labelled cells number $_ds_n, the pinned count is 9"; return 1; }
      return 0
    }
    _gd_aa="$_kr/conformance/agent-autonomy.sh"
    mkdir -p "$d/gd10"
    if check_delta_stress "$_gd_aa" >/dev/null 2>&1; then
      echo "selftest PASS: GD10 — the delta's stress-cell exclusion list equals the pinned set, its code is in place and every excluded id has an asserted-DENY cell"
      sed "s/^AA_DELTA_STRESS=' /AA_DELTA_STRESS=' SC-D1 /" "$_gd_aa" > "$d/gd10/m1.sh"
      sed "s/^AA_DELTA_STRESS=' /AA_DELTA_STRESS=' cat /" "$_gd_aa" > "$d/gd10/m2.sh"
      sed 's/case "\$1" in "\$_as_id "\*)/case "$1" in "zz "*)/' "$_gd_aa" > "$d/gd10/m3.sh"
      sed '/^scp_deny .*"SC-D31 /d' "$_gd_aa" > "$d/gd10/m4.sh"
      awk '{ print } /^scp_deny .*"SC-P9 / { print "assert_allow \"SC-P9 a reused id on a non-stress cell\" \"$(scpj \047echo x\047)\"" }' "$_gd_aa" > "$d/gd10/m5.sh"
      sed 's/^    case "\$1" in "\$_as_id "\*)/    # case "$1" in "$_as_id "*)/' "$_gd_aa" > "$d/gd10/m6.sh"
      sed 's/AA_STRESS_N" -ne "\$AA_STRESS_PIN"/AA_STRESS_N" -ne "$AA_STRESS_N"/' "$_gd_aa" > "$d/gd10/m7.sh"
      for _gd_m in "m1:differs from the pinned set:GD10a:an SC-D1 cell added to the exclusion list" \
                   "m2:differs from the pinned set:GD10b:an H3a-style cell (cat) added to the exclusion list" \
                   "m3:exclusion code is gone:GD10c:the exclusion code removed from aa_cell_record" \
                   "m4:no asserted-DENY cell:GD10d:an excluded id whose guard-battery DENY cell is deleted" \
                   "m5:not an scp_deny C cell:GD10e:an assert_allow reusing the SC-P9 id on a non-stress cell" \
                   "m6:or only commented out:GD10f:the exclusion code commented out inside aa_cell_record" \
                   "m7:check of the excluded count against AA_STRESS_PIN is gone:GD10g:the --delta check of the excluded count removed"; do
        _gd_f=${_gd_m%%:*}; _gd_r=${_gd_m#*:}; _gd_want=${_gd_r%%:*}; _gd_r=${_gd_r#*:}
        _gd_id=${_gd_r%%:*}; _gd_desc=${_gd_r#*:}
        if cmp -s "$_gd_aa" "$d/gd10/$_gd_f.sh"; then
          echo "selftest FAIL: $_gd_id — the mutant equals the original (nothing to mutate; the lock is not pinned)"; sf=1
        elif _gd_o=$(check_delta_stress "$d/gd10/$_gd_f.sh" 2>&1); then
          echo "selftest FAIL: $_gd_id — $_gd_desc was NOT caught"; sf=1
        elif printf '%s\n' "$_gd_o" | grep -qF -- "$_gd_want"; then
          echo "selftest PASS: $_gd_id — $_gd_desc -> RED, naming '$_gd_want'"
        else echo "selftest FAIL: $_gd_id — $_gd_desc reds without naming '$_gd_want': $_gd_o"; sf=1; fi
      done
    else
      echo "selftest FAIL: GD10 — the delta's stress-cell exclusion lock does not hold on the real agent-autonomy.sh (SWAS-332)"; sf=1
    fi
    # RP1/RP4 (SWAS-306) — the runner-pin lock through the REAL entry point on a kit-marked scratch tree holding
    # the real workflows and profile templates: green as shipped; red, naming the file and the alias, when one
    # runs-on (or one tracker fallback) is reverted. cmp guards: a mutant that equals the original proves nothing.
    _rp_tree="$d/rp1"
    mkdir -p "$_rp_tree/.github/workflows" "$_rp_tree/docs/operations" "$_rp_tree/conformance" "$_rp_tree/profiles"
    : > "$_rp_tree/docs/ROADMAP-KIT.md"
    cp "$_kr"/.github/workflows/*.yml "$_rp_tree/.github/workflows/"
    cp "$_kr"/docs/operations/*.github.yml "$_rp_tree/docs/operations/"
    cp "$_kr/conformance/gate-dispositions.txt" "$_rp_tree/conformance/"
    for _rp_p in "$_kr"/profiles/*.yml "$_kr"/profiles/*/ci.yml; do
      [ -f "$_rp_p" ] || continue
      _rp_rel=${_rp_p#"$_kr"/profiles/}
      mkdir -p "$_rp_tree/profiles/$(dirname "$_rp_rel")"
      cp "$_rp_p" "$_rp_tree/profiles/$_rp_rel"
    done
    _ot_case RP1 "$_rp_tree" 0 "OK: ci-gates --own-tree" "the real workflows and profile templates on a kit-marked tree -> green"
    _rp_mut() { # <id> <real-file> <awk-program> <want-file> <desc> — mutate one copy in place, judge, restore
      _rm_id=$1; _rm_real=$2; _rm_dst="$_rp_tree/.github/workflows/$(basename "$2")"
      awk "$3" "$_rm_real" > "$d/rp/$_rm_id.mut"
      if cmp -s "$_rm_real" "$d/rp/$_rm_id.mut"; then
        echo "selftest FAIL: $_rm_id — the mutant equals the original (nothing to revert; the shipped file is not pinned)"; sf=1; return
      fi
      cp "$d/rp/$_rm_id.mut" "$_rm_dst"
      if _rm_o=$(sh "$0" --own-tree "$_rp_tree" 2>&1); then _rm_rc=0; else _rm_rc=$?; fi
      cp "$_rm_real" "$_rm_dst"
      if [ "$_rm_rc" = 1 ] && printf '%s' "$_rm_o" | grep -qF -- "'ubuntu-latest'" && printf '%s' "$_rm_o" | grep -qF -- "$4"; then
        echo "selftest PASS: $_rm_id — $5 -> RED, naming 'ubuntu-latest' and $4"
      else echo "selftest FAIL: $_rm_id — $5 (rc=$_rm_rc, want 1 naming 'ubuntu-latest' and $4): $_rm_o"; sf=1; fi
    }
    _rp_mut RP4a "$_kr/.github/workflows/ci.yml" '!d && /runs-on: ubuntu-24.04/ { sub(/ubuntu-24.04/, "ubuntu-latest"); d = 1 } { print }' \
      "workflows/ci.yml:" "the real ci.yml with one runs-on reverted"
    _rp_mut RP4b "$_kr/.github/workflows/adopter-tracker-gates.yml" "!d && /'ubuntu-24.04'/ { sub(/ubuntu-24.04/, \"ubuntu-latest\"); d = 1 } { print }" \
      "workflows/adopter-tracker-gates.yml:" "the tracker workflow with one fallback reverted"

    # OT15 — gate-test STAYS TERMINAL (reviewer LOW-4): reaching the id attests every step above
    # it passed ONLY while it is the LAST step of conformance-selftests — a step planted after
    # it is NOT attested (the anchor comment at the id states exactly this).
    # SWAS-409 (C32): conformance-selftests is now the JOIN over the legs conformance-selftests-1..n. The
    # probe is unchanged and still addresses the job by that key, which is now the join: the join's
    # gate-test attests the join's steps above it, and those attest the legs (the shard-join step
    # requires every leg to have concluded `success`, the --legs step requires the legs to partition
    # the capable set). Its position, and its absence from every leg, are graded by SJ30-SJ32 below.
    # Same grep/awk discipline as OT14: line-shape parsing of the real ci.yml, never a YAML lib.
    _ts_probe() { # <workflow-file> -> TERMINAL | NOT-TERMINAL (…)
      awk '
        /^  conformance-selftests:/ { injob = 1; next }
        injob && /^  [A-Za-z0-9_"-]+:/ { injob = 0 }
        injob && /^      - / { step++ }
        injob && /^        id: gate-test[[:space:]]*$/ { gt = step }
        END { if (gt > 0 && gt == step) print "TERMINAL"
              else print "NOT-TERMINAL (gate-test at step " gt + 0 " of " step + 0 ")" }
      ' "$1"
    }
    _ts_real=$(_ts_probe "$_kr/.github/workflows/ci.yml")
    if [ "$_ts_real" = TERMINAL ]; then
      echo "selftest PASS: OT15 — id: gate-test is the LAST step of the conformance-selftests join, which attests the legs through the join's checks (stay-terminal pinned)"
    else
      echo "selftest FAIL: OT15 — id: gate-test is no longer the terminal step of the conformance-selftests join; a step after it is unattested by the join's id, and the join's checks are what attest the legs — move it back or re-anchor the id, citing D-240805-2: $_ts_real"; sf=1
    fi
    # The planted-step mutant, on a SCRATCH COPY (never the tracked file): a step appended after
    # gate-test must read NOT-TERMINAL, proving the probe can red rather than always agreeing.
    mkdir -p "$d/ot15"
    awk '
      { print }
      /^        id: gate-test[[:space:]]*$/ { plant = 1 }
      plant && /^        run: / { print "      - name: planted step (OT15 mutant)"; print "        run: echo planted"; plant = 0 }
    ' "$_kr/.github/workflows/ci.yml" > "$d/ot15/ci.yml"
    if [ "$(_ts_probe "$d/ot15/ci.yml")" != TERMINAL ]; then
      echo "selftest PASS: OT15b — a step planted after gate-test reads NOT-TERMINAL (the probe has teeth)"
    else
      echo "selftest FAIL: OT15b — the planted-step mutant still reads TERMINAL; the stay-terminal probe is vacuous"; sf=1
    fi
  else
    echo "selftest SKIP: OT13/OT14/OT15 — kit-source legs (no kit marker here; the ruling lock binds the kit's shipped file only)"
  fi
  _st_mark KIT

  # ── TIER0-LOCKS-OWED (b): THE AGGREGATOR needs:/CLASSIFIER DRIFT-LOCK ────────────────────────
  # A minimal but STRUCTURALLY REAL fixture pair (a tiny ci.yml + a tiny ci-classify-changes.sh),
  # not the kit's own 1900-line files — so a mutant is a ONE-LINE edit and the leg the mutant
  # targets is unambiguous.
  mkdir -p "$d/agg"
  _agg_write_yml() { # <path> <needs-line>
    cat > "$1" <<AGGYML
jobs:
  changes:
    runs-on: ubuntu-latest
  conformance-core:
    needs: changes
    if: needs.changes.outputs.docs_only != 'true' && needs.changes.outputs.push_graded != 'true'
    steps:
      - uses: actions/checkout@x
      - name: one
        run: echo 1
      - name: two
        run: echo 2
  conformance-docs:
    needs: changes
    if: needs.changes.outputs.push_graded != 'true'
    steps:
      - uses: actions/checkout@x
  side-job:
    needs: changes
    if: needs.changes.outputs.docs_only != 'true' && needs.changes.outputs.push_graded != 'true'   # not a required check -> a job-level skip is safe
    steps:
      - uses: actions/checkout@x
  conformance:
    $2
    if: always()
    steps:
      - run: echo done
AGGYML
  }
  _agg_write_cls() { # <path> <pg-needed-value>
    cat > "$1" <<AGGCLS
#!/bin/sh
PG_NEEDED='$2'
AGGCLS
  }

  # liveness: a matched pair -> OK, rc0.
  _agg_write_yml "$d/agg/ci-ok.yml" "needs: [changes, conformance-core, conformance-docs]"
  _agg_write_cls "$d/agg/cls-ok.sh" "changes conformance-core conformance"
  if _agg_out=$(sh "$0" --aggregator-lock "$d/agg/ci-ok.yml" "$d/agg/cls-ok.sh" 3 2>&1); then _agg_rc=0; else _agg_rc=$?; fi
  case "$_agg_out" in
    *"OK: aggregator-needs-lock"*) [ "$_agg_rc" -eq 0 ] && echo "selftest PASS: AGG1 — matched needs:/PG_NEEDED pair -> OK, rc0" \
      || { echo "selftest FAIL: AGG1 — matched pair printed OK but rc=$_agg_rc"; sf=1; } ;;
    *) echo "selftest FAIL: AGG1 — matched pair did not read OK; out='$_agg_out'"; sf=1 ;;
  esac

  # negative — job dropped from needs: (still carries the push-graded if:, no exemption marker):
  # a job present in the pipeline but ABSENT from the aggregator's needs: must red.
  _agg_write_yml "$d/agg/ci-dropped.yml" "needs: [changes, conformance-docs]"        # conformance-core dropped
  if _agg_out=$(sh "$0" --aggregator-lock "$d/agg/ci-dropped.yml" "$d/agg/cls-ok.sh" 3 2>&1); then _agg_rc=0; else _agg_rc=$?; fi
  case "$_agg_out" in
    *"job 'conformance-core' carries the push-graded if:"*) [ "$_agg_rc" -ne 0 ] && echo "selftest PASS: AGG2 — a job dropped from needs: (no marker) -> reds, naming the job" \
      || { echo "selftest FAIL: AGG2 — named the dropped job but rc=0"; sf=1; } ;;
    *) echo "selftest FAIL: AGG2 — dropping a job from needs: did not red / did not name it; out='$_agg_out'"; sf=1 ;;
  esac

  # negative — marker-delete mutant: side-job's exemption marker is removed (still absent from
  # needs:) -> must red, naming side-job.
  _agg_write_yml "$d/agg/ci-nomarker.yml" "needs: [changes, conformance-core, conformance-docs]"
  sed 's/   # not a required check -> a job-level skip is safe//' "$d/agg/ci-nomarker.yml" > "$d/agg/ci-nomarker2.yml"
  if _agg_out=$(sh "$0" --aggregator-lock "$d/agg/ci-nomarker2.yml" "$d/agg/cls-ok.sh" 3 2>&1); then _agg_rc=0; else _agg_rc=$?; fi
  case "$_agg_out" in
    *"job 'side-job' carries the push-graded if:"*) [ "$_agg_rc" -ne 0 ] && echo "selftest PASS: AGG3 — deleting the exemption marker on a not-needed job -> reds, naming the job" \
      || { echo "selftest FAIL: AGG3 — named side-job but rc=0"; sf=1; } ;;
    *) echo "selftest FAIL: AGG3 — the marker-delete mutant did not red / did not name side-job; out='$_agg_out'"; sf=1 ;;
  esac
  # ...and the SAME pipeline WITH its marker intact must NOT red on side-job (the marker is load-bearing, not decorative).
  if _agg_out2=$(sh "$0" --aggregator-lock "$d/agg/ci-nomarker.yml" "$d/agg/cls-ok.sh" 3 2>&1); then _agg_rc2=0; else _agg_rc2=$?; fi
  case "$_agg_out2" in
    *"side-job"*) echo "selftest FAIL: AGG3b — side-job flagged even WITH its marker intact; out='$_agg_out2'"; sf=1 ;;
    *) echo "selftest PASS: AGG3b — the same pipeline WITH the marker intact does not flag side-job" ;;
  esac

  # negative — PG_NEEDED drift: a phantom name appended to PG_NEEDED with no matching needs: entry
  # -> the set-equality leg reds.
  _agg_write_cls "$d/agg/cls-phantom.sh" "changes conformance-core conformance phantom-shard"
  if _agg_out=$(sh "$0" --aggregator-lock "$d/agg/ci-ok.yml" "$d/agg/cls-phantom.sh" 3 2>&1); then _agg_rc=0; else _agg_rc=$?; fi
  case "$_agg_out" in
    *"PG_NEEDED"*) [ "$_agg_rc" -ne 0 ] && echo "selftest PASS: AGG4 — a phantom PG_NEEDED entry with no needs: match -> reds" \
      || { echo "selftest FAIL: AGG4 — flagged PG_NEEDED mismatch but rc=0"; sf=1; } ;;
    *) echo "selftest FAIL: AGG4 — a phantom PG_NEEDED entry did not red; out='$_agg_out'"; sf=1 ;;
  esac

  # negative — the step-count pin: this file's OWN conformance-core step count must still equal
  # $_AGG_CC_STEP_PIN (proves the pin is wired to the real file, not a fixture-only constant), and a
  # planted extra step on a SCRATCH COPY of the real file must red it.
  _agg_kr="$(dirname "$0")/.."
  # KIT-SELF (artifact-gate first-live-run, CONTROL-PLANE-COVERAGE 2026-09-10): AGG5/AGG6 verify the
  # KIT's OWN ci.yml/classify-changes pair, so they run only on a kit tree. An INCEPTED adopter tree
  # HAS a .github/workflows/ci.yml (stamped from its chosen profile), which is NOT the kit's and has
  # no aggregator-needs structure — running AGG5/AGG6 against it FAILs "out=''" and reds every
  # adopter's artifact-gate. Gate on a kit marker present too (the twin-marker discriminator,
  # adopter-census.sh:170): a kit tree keeps docs/ROADMAP-KIT.md or golden-path.yml (both
  # export-ignored), an adopter export/incept has neither.
  if [ -f "$_agg_kr/.github/workflows/ci.yml" ] && { [ -f "$_agg_kr/docs/ROADMAP-KIT.md" ] || [ -f "$_agg_kr/.github/workflows/golden-path.yml" ]; }; then
    if _agg_out=$(sh "$0" --aggregator-lock 2>&1); then _agg_rc=0; else _agg_rc=$?; fi
    case "$_agg_out" in
      *"top-level steps, pinned at"*) echo "selftest FAIL: AGG5 — the kit's OWN ci.yml reds the step-count pin (bump _AGG_CC_STEP_PIN); out='$_agg_out'"; sf=1 ;;
      *"OK: aggregator-needs-lock"*) echo "selftest PASS: AGG5 — the kit's own ci.yml/classify-changes pair is locked green today" ;;
      *) echo "selftest FAIL: AGG5 — the kit's own pair did not read OK; out='$_agg_out'"; sf=1 ;;
    esac
    mkdir -p "$d/agg/real"
    sed '/^  conformance-core:/,/^  [A-Za-z0-9_-]*:/{ /^      - uses: actions\/checkout/a\
      - name: PLANTED MUTANT STEP (AGG6)\
        run: echo mutant
    }' "$_agg_kr/.github/workflows/ci.yml" > "$d/agg/real/ci.yml"
    if _agg_out=$(sh "$0" --aggregator-lock "$d/agg/real/ci.yml" "$_agg_kr/conformance/ci-classify-changes.sh" 2>&1); then _agg_rc=0; else _agg_rc=$?; fi
    case "$_agg_out" in
      *"top-level steps, pinned at"*) [ "$_agg_rc" -ne 0 ] && echo "selftest PASS: AGG6 — a step planted into the real conformance-core reds the step-count pin" \
        || { echo "selftest FAIL: AGG6 — named the pin mismatch but rc=0"; sf=1; } ;;
      *) echo "selftest FAIL: AGG6 — a planted step in conformance-core did not red the pin; out='$_agg_out'"; sf=1 ;;
    esac
  else
    echo "selftest SKIP: AGG5/AGG6 — not a kit tree (no kit-source ci.yml, or an adopter export/incept where the kit markers are pruned); these legs verify the kit's OWN ci.yml pair"
  fi
  _st_mark AGG

  # ── SESSION-SURFACE T3/F1 — loop-state credential-drop ordering ────────────────────────────
  mkdir -p "$d/ls"
  # SWAS-250: a minimal CRED-DROP block (markers in order + an includes-following verify read) is what
  # the pin now looks for; the bare `--local --unset-all` string no longer counts (LS8).
  _ls_blk='          # CRED-DROP-BEGIN (SWAS-250)\n          # CRED-DROP-VERIFY\n          git config --show-origin --name-only --get-regexp x\n          # CRED-DROP-VERIFY-END\n          # CRED-DROP-END\n'
  printf 'jobs:\n  loop-state:\n    steps:\n      - run: |\n'"$_ls_blk"'          sh conformance/loop-state.sh --head X\n' > "$d/ls/good.yml"
  if check_loop_state_credential_order "$d/ls/good.yml" >/dev/null 2>&1; then
    echo "selftest PASS: LS1 — credential drop before the first conformance/ invocation -> PASS"
  else echo "selftest FAIL: LS1 — good fixture wrongly failed"; sf=1; fi

  # negative — the drop line absent entirely
  printf 'jobs:\n  loop-state:\n    steps:\n      - run: sh conformance/loop-state.sh --head X\n' > "$d/ls/nodrop.yml"
  if check_loop_state_credential_order "$d/ls/nodrop.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: LS2 — a missing credential drop was NOT caught"; sf=1
  else echo "selftest PASS: LS2 — missing credential drop -> FAIL"; fi

  # negative — the drop line present but AFTER the conformance/ invocation
  printf 'jobs:\n  loop-state:\n    steps:\n      - run: |\n          sh conformance/loop-state.sh --head X\n'"$_ls_blk" > "$d/ls/misordered.yml"
  if check_loop_state_credential_order "$d/ls/misordered.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: LS3 — a credential drop AFTER the conformance/ invocation was NOT caught"; sf=1
  else echo "selftest PASS: LS3 — drop ordered after the conformance/ call -> FAIL"; fi

  # regression backstop — the kit's OWN live ci.yml must pass this leg today (the SESSION-SURFACE
  # T3/F1 fix). Gated on the same kit-tree marker AGG5/AGG6 use, so an adopter export is unjudged.
  if [ -f "$_agg_kr/.github/workflows/ci.yml" ] && { [ -f "$_agg_kr/docs/ROADMAP-KIT.md" ] || [ -f "$_agg_kr/.github/workflows/golden-path.yml" ]; }; then
    # LS10 (SWAS-250; folds LS4) — the fleet pin: the six jobs that claim to hold no token, kit tree only.
    _ls_ci="$_agg_kr/.github/workflows/ci.yml"; _ls_ag="$_agg_kr/profiles/adopter-gates.yml"; _ls_bad=""
    for _ls_j in ceremony-binding loop-state review-lane; do
      check_cred_before_prtree "$_ls_ci" "$_ls_j" >/dev/null 2>&1 || _ls_bad="$_ls_bad ci.yml:$_ls_j"
      [ "$_ls_j" = loop-state ] || check_cred_before_prtree "$_ls_ag" "$_ls_j" >/dev/null 2>&1 || _ls_bad="$_ls_bad adopter-gates.yml:$_ls_j"
    done
    check_cred_before_prtree "$_ls_ag" loop-state >/dev/null 2>&1 || _ls_bad="$_ls_bad adopter-gates.yml:loop-state"
    _ls_five=$(for _ls_x in "$_ls_ci:ceremony-binding" "$_ls_ci:loop-state" "$_ls_ci:review-lane" "$_ls_ag:ceremony-binding" "$_ls_ag:review-lane"; do cred_block "${_ls_x%%:*}" "${_ls_x#*:}" | cksum | cut -d' ' -f1; done | sort -u | wc -l | tr -d ' ')
    if [ -z "$_ls_bad" ] && [ "$_ls_five" = 1 ] && [ -n "$(cred_block "$_ls_ci" ceremony-binding)" ]; then
      echo "selftest PASS: LS10 — all six token-free jobs pass the pin and the five CRED-DROP blocks are byte-identical (folds LS4)"
    else echo "selftest FAIL: LS10 — pin failures:${_ls_bad:- none}; distinct block copies=$_ls_five (want 1)"; sf=1; fi
  else
    echo "selftest SKIP: LS10 — not a kit tree"
  fi

  # negative (F1-2) — a scripts/ invocation is PR-tree code too (the loop-state job's
  # `promotion-verify.sh trace`), so a credential drop AFTER a scripts/ call, but before the first
  # conformance/ call, must FAIL: the token is still readable when the scripts/ PR-code runs.
  printf 'jobs:\n  loop-state:\n    steps:\n      - run: |\n          sh scripts/promotion-verify.sh trace --recent 1\n'"$_ls_blk"'          sh conformance/loop-state.sh --head X\n' > "$d/ls/scriptsfirst.yml"
  if check_loop_state_credential_order "$d/ls/scriptsfirst.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: LS5 — a credential drop AFTER a scripts/ PR-code invocation was NOT caught"; sf=1
  else echo "selftest PASS: LS5 — drop ordered after a scripts/ PR-code call -> FAIL"; fi

  # ── SWAS-250 — the drop must remove what checkout v7 writes (an includeIf file), not only a local key ──
  # Run the real scripts under `bash -e` (how the runner runs a step); needs bash + git, else SKIP loudly.
  if command -v bash >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    printf '%s\n' "git config --local --unset-all 'http.https://github.com/.extraheader' 2>/dev/null || true" \
      "if git config --local --get-all 'http.https://github.com/.extraheader' >/dev/null 2>&1; then exit 1; fi" > "$d/ls/old-drop.sh"
    # LS6 — the reproduction: the OLD drop (--local unset, --local check) passes yet leaves the token reachable.
    cred_scenario "$d/cs6" v7 rt "$d/ls/old-drop.sh"
    if [ "$_cs_pre" = REACHABLE ] && [ "$_cs_rc" = 0 ] && [ "$_cs_reach" = REACHABLE ]; then
      echo "selftest PASS: LS6 — the old --local drop exits 0 on the v7 layout and the token is still readable (the reproduction)"
    else echo "selftest FAIL: LS6 — expected the old drop to pass while leaving the token reachable (pre=$_cs_pre rc=$_cs_rc reach=$_cs_reach)"; sf=1; fi
    # LS8 — the load-bearing negative: a --local-only drop fails the pin, so it can never satisfy it again.
    printf 'jobs:\n  loop-state:\n    steps:\n      - run: |\n          git config --local --unset-all '"'"'http.https://github.com/.extraheader'"'"'\n          git config --local --get-all x\n          sh conformance/loop-state.sh --head X\n' > "$d/ls/localonly.yml"
    if check_cred_before_prtree "$d/ls/localonly.yml" loop-state >/dev/null 2>&1; then
      echo "selftest FAIL: LS8 — a --local-only drop satisfied the pin"; sf=1
    else echo "selftest PASS: LS8 — a --local-only drop (which leaves the v7 token reachable) fails the pin"; fi
  else echo "selftest SKIP: LS6/LS8 — bash or git missing"; fi

  if [ -f "$_agg_kr/.github/workflows/ci.yml" ] && { [ -f "$_agg_kr/docs/ROADMAP-KIT.md" ] || [ -f "$_agg_kr/.github/workflows/golden-path.yml" ]; } && command -v bash >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    cred_block "$_agg_kr/.github/workflows/ci.yml" ceremony-binding > "$d/ls/live.sh"
    { echo 'set -f'; cred_block "$_agg_kr/.github/workflows/ci.yml" ceremony-binding verify; } > "$d/ls/verify.sh"
    # LS7 — the LIVE block, extracted from the real ci.yml, executed under bash -e in five layouts.
    _ls7=""
    for _ls_l in "a v7 rt" "b v7 out" "c v4 rt" "d clean rt" "e own rt"; do
      set -- $_ls_l
      cred_scenario "$d/cs7$1" "$2" "$3" "$d/ls/live.sh"
      [ "$_cs_rc" = 0 ] && [ "$_cs_reach" = none ] || _ls7="$_ls7 ($1: rc=$_cs_rc reach=$_cs_reach: $(printf '%s' "$_cs_out" | tail -n 2 | tr '\n' ' '))"
      case "$1" in a|b|c) [ "$_cs_pre" = REACHABLE ] || _ls7="$_ls7 ($1: layout not live before the drop)" ;; esac
      case "$1" in a|b) [ "$_cs_gone" = gone ] || _ls7="$_ls7 ($1: credentials file still present)" ;; esac
      case "$1" in e) [ "$_cs_own" = kept ] || _ls7="$_ls7 (e: the adopter's own include was removed)" ;; esac
    done
    if [ -z "$_ls7" ]; then echo "selftest PASS: LS7 — the live CRED-DROP block runs clean under bash -e: v7 (in and outside RUNNER_TEMP), v4, clean repo, adopter-own include"
    else echo "selftest FAIL: LS7 —$_ls7"; sf=1; fi
    # LS9 — the live VERIFY part alone: it must refuse a live credential (names only) and pass a clean repo.
    _ls9=""
    for _ls_l in "v7 1" "v4 1" "xinc 1" "clean 0"; do
      set -- $_ls_l
      cred_scenario "$d/cs9$1" "$1" rt "$d/ls/verify.sh"
      [ "$_cs_rc" = "$2" ] || _ls9="$_ls9 ($1: rc=$_cs_rc want $2)"
      case "$_cs_out" in *SIMTOKEN250*) _ls9="$_ls9 ($1: the token appeared in the output)" ;; esac
    done
    if [ -z "$_ls9" ]; then echo "selftest PASS: LS9 — the live verify alone refuses v7, v4 and a header hidden in a foreign include (exit 1, names only, no token printed) and passes a clean repo"
    else echo "selftest FAIL: LS9 —$_ls9"; sf=1; fi
  else echo "selftest SKIP: LS7/LS9 — not a kit tree, or bash/git missing"; fi
  _st_mark LS

  # ── SESSION-SURFACE T3/F4 — backlog-presence carries --base-board ──────────────────────────
  mkdir -p "$d/bp"
  printf 'jobs:\n  backlog-presence:\n    steps:\n      - run: |\n          out=$(sh conformance/backlog-presence.sh --dir . --pr "$PR" --changed /tmp/c.txt --branch "$H" --base-board /tmp/base-BACKLOG.md --claims 2>&1); rc=$?\n' > "$d/bp/good.yml"
  if check_backlog_presence_base_board "$d/bp/good.yml" >/dev/null 2>&1; then
    echo "selftest PASS: BP1 — --base-board present on the gate invocation -> PASS"
  else echo "selftest FAIL: BP1 — good fixture wrongly failed"; sf=1; fi

  # negative — --base-board dropped entirely
  printf 'jobs:\n  backlog-presence:\n    steps:\n      - run: |\n          out=$(sh conformance/backlog-presence.sh --dir . --pr "$PR" --changed /tmp/c.txt --branch "$H" --claims 2>&1); rc=$?\n' > "$d/bp/nodrop.yml"
  if check_backlog_presence_base_board "$d/bp/nodrop.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: BP2 — a gate invocation with NO --base-board was NOT caught"; sf=1
  else echo "selftest PASS: BP2 — --base-board missing -> FAIL"; fi

  # regression backstop — the kit's OWN live ci.yml.
  if [ -f "$_agg_kr/.github/workflows/ci.yml" ] && { [ -f "$_agg_kr/docs/ROADMAP-KIT.md" ] || [ -f "$_agg_kr/.github/workflows/golden-path.yml" ]; }; then
    if check_backlog_presence_base_board "$_agg_kr/.github/workflows/ci.yml" >/dev/null 2>&1; then
      echo "selftest PASS: BP3 — the kit's own ci.yml passes --base-board to backlog-presence.sh"
    else echo "selftest FAIL: BP3 — the kit's own ci.yml regressed the --base-board argument"; sf=1; fi
  else
    echo "selftest SKIP: BP3 — not a kit tree"
  fi
  _st_mark BP

  # ── TRUNK-REF-TAG-SHADOW slice 1 (SWAS-247) — TT0-TT5: the trunk-tag tripwire ───────────────────
  # Kit-tree only (the legs run the body that SHIPS in the kit's ci.yml, and TT5 pins the adopter copy
  # byte-identical to it). Fixtures are throwaway bare repos under $d reached by file://, trap-cleaned.
  if [ -f "$_agg_kr/.github/workflows/ci.yml" ] && { [ -f "$_agg_kr/docs/ROADMAP-KIT.md" ] || [ -f "$_agg_kr/.github/workflows/golden-path.yml" ]; }; then
    _tt_ci="$_agg_kr/.github/workflows/ci.yml"; _tt_ag="$_agg_kr/profiles/adopter-gates.yml"
    _tt_bodyf="$d/tt-body.sh"; tt_body_of "$_tt_ci" ceremony-binding > "$_tt_bodyf"
    # TT0 — the premise: a tag named origin/main wins the short name and the merge-base class derivation misses the PR's first commit.
    mkdir -p "$d/tt0"; _tt_fixture "$d/tt0" main
    _tt_git -C "$d/tt0/origin.git" update-ref refs/tags/origin/main "$_tt_b"
    _tt_git clone -q "file://$d/tt0/origin.git" "$d/tt0/clone" && _tt_git -C "$d/tt0/clone" checkout -q -b prx refs/remotes/origin/pr
    _t0_short=$(_tt_git -C "$d/tt0/clone" rev-parse origin/main 2>/dev/null || true)
    _t0_full=$(_tt_git -C "$d/tt0/clone" rev-parse refs/remotes/origin/main 2>/dev/null || true)
    _t0_bad=$(_tt_git -C "$d/tt0/clone" diff --name-only "$(_tt_git -C "$d/tt0/clone" merge-base HEAD origin/main 2>/dev/null)" HEAD 2>/dev/null || true)
    _t0_good=$(_tt_git -C "$d/tt0/clone" diff --name-only "$(_tt_git -C "$d/tt0/clone" merge-base HEAD refs/remotes/origin/main)" HEAD 2>/dev/null || true)
    case "$_t0_bad" in *conformance/x.sh*) _t0_ok=0 ;; *) _t0_ok=1 ;; esac
    case "$_t0_good" in *conformance/x.sh*) : ;; *) _t0_ok=0 ;; esac
    if [ "$_t0_short" = "$_tt_b" ] && [ "$_t0_full" = "$_tt_a" ] && [ "$_t0_ok" = 1 ]; then
      echo "selftest PASS: TT0 — the origin/main tag wins the short name and the merge-base change set lacks conformance/x.sh (the premise)"
    else echo "selftest FAIL: TT0 — the shadowing premise did not reproduce (short='$_t0_short' full='$_t0_full' bad='$_t0_bad' good='$_t0_good')"; sf=1; fi

    # TT1 — no false positive: tags that merely resemble a refused name (exact prefix tests).
    mkdir -p "$d/tt1"; _tt_fixture "$d/tt1" main; _tt1_a=$_tt_a
    _tt_git clone -q "file://$d/tt1/origin.git" "$d/tt1/clone"
    for _t1 in v1.0.0 release-1 mainline origin-x AHEAD; do
      _tt_git -C "$d/tt1/origin.git" update-ref "refs/tags/$_t1" "$_tt1_a"
      _tt_git -C "$d/tt1/clone" update-ref "refs/tags/$_t1" "$_tt1_a"
    done
    # both modes: the switch absent (local only) and exactly 1 (local plus remote). The fixture has branches release and develop, so release-1 is a tag that only resembles the branch release.
    for _tt_m in unset 1; do
      if [ "$_tt_m" = unset ]; then unset _tt_mode; _tt_ml=local; else _tt_mode=1; _tt_ml=remote; fi
      _tt_expect "TT1[$_tt_ml]" "$d/tt1/clone" 0 "OK - no tag shadows the trunk or a branch" "v1.0.0, release-1 (beside a release branch), mainline, origin-x and AHEAD are not refused (exact rules)"
    done

    # TT2 — every refused shape, one at a time, in BOTH modes. Local mode: the tag exists only in the clone (the origin is not read). Remote mode: the tag exists only on the origin (the clone does not hold it), then in both. The shapes include HEAD, origin and the branch-name rule (develop, pr).
    for _t2 in main master HEAD FETCH_HEAD origin origin/main refs/remotes/origin/main remotes/origin/main x/refs/y develop pr; do
      _tt_git -C "$d/tt1/origin.git" update-ref "refs/tags/$_t2" "$_tt1_a" 2>/dev/null \
        || { echo "selftest FAIL: TT2 — could not plant tag $_t2 on the origin"; sf=1; continue; }
      _tt_git -C "$d/tt1/clone" update-ref "refs/tags/$_t2" "$_tt1_a" 2>/dev/null \
        || { echo "selftest FAIL: TT2 — could not plant tag $_t2 in the clone"; sf=1; continue; }
      unset _tt_mode
      _tt_expect "TT2[$_t2][local]" "$d/tt1/clone" 1 "(refs/tags/$_t2; found: local)" "the tag held by the checkout is refused and named, found local, with the switch absent"
      _tt_mode=1
      _tt_expect "TT2[$_t2][both]" "$d/tt1/clone" 1 "(refs/tags/$_t2; found: local origin)" "the tag held by the checkout and the forge is refused and named, found local and origin"
      _tt_git -C "$d/tt1/clone" update-ref -d "refs/tags/$_t2"
      _tt_expect "TT2[$_t2][remote]" "$d/tt1/clone" 1 "(refs/tags/$_t2; found: origin)" "the tag only the forge holds is refused and named, found origin, in remote mode"
      unset _tt_mode
      _tt_expect "TT2[$_t2][local-clean]" "$d/tt1/clone" 0 "OK - no tag shadows the trunk or a branch (local only)" "the same tag on the forge only is NOT read in local mode (the local check judges this checkout)"
      _tt_git -C "$d/tt1/origin.git" update-ref -d "refs/tags/$_t2"
    done
    mkdir -p "$d/tt2b"; _tt_fixture "$d/tt2b" trunk
    _tt_git clone -q "file://$d/tt2b/origin.git" "$d/tt2b/clone"
    _tt_git -C "$d/tt2b/origin.git" update-ref refs/tags/trunk "$_tt_a"
    _tt_mode=1
    _tt_expect "TT2[default=trunk]" "$d/tt2b/clone" 1 "(refs/tags/trunk; found: origin)" "a tag named for the origin's own default branch is refused and named (remote mode reads the HEAD symref)"
    # local-only: fetched into the clone, then deleted from the forge, so ls-remote is clean but the local copy still shadows.
    _tt_git -C "$d/tt1/origin.git" update-ref refs/tags/origin/main "$_tt1_a"
    _tt_git -C "$d/tt1/clone" fetch -q origin refs/tags/origin/main:refs/tags/origin/main
    _tt_git -C "$d/tt1/origin.git" update-ref -d refs/tags/origin/main
    _tt_expect "TT2[local-only]" "$d/tt1/clone" 1 "found: local)" "a shadowing tag that only the checkout still holds is refused, found local only, even in remote mode"
    _tt_git -C "$d/tt1/clone" tag -d origin/main >/dev/null

    # TT3 — fail closed. Remote mode: an unreadable remote, a remote with no branches, a remote whose HEAD names an unborn branch (each clone keeps its local origin branches, so the remote cases are reached).
    _tt_mode=1
    _tt_git clone -q "file://$d/tt1/origin.git" "$d/tt3clone"
    _tt_git -C "$d/tt3clone" remote set-url origin "file://$d/tt3-missing.git"
    _tt_expect TT3a "$d/tt3clone" 1 "ls-remote failed 3 times" "an unreadable remote is refused after the retries (fail-closed)"
    _tt_git init -q --bare -b main "$d/tt3-empty.git"
    _tt_git clone -q "file://$d/tt1/origin.git" "$d/tt3empty" && _tt_git -C "$d/tt3empty" remote set-url origin "file://$d/tt3-empty.git"
    _tt_expect TT3b "$d/tt3empty" 1 "the remote lists no branches" "a remote with no branches is refused (fail-closed)"
    _tt_git init -q --bare -b nope "$d/tt3-unborn.git"
    _tt_git -C "$d/tt1/seed" push -q "file://$d/tt3-unborn.git" main:other
    _tt_git clone -q "file://$d/tt1/origin.git" "$d/tt3unborn" && _tt_git -C "$d/tt3unborn" remote set-url origin "file://$d/tt3-unborn.git"
    _tt_expect TT3c "$d/tt3unborn" 1 "no HEAD symref" "a remote whose HEAD names an unborn branch is refused (fail-closed)"
    # Local mode (and remote mode): a checkout with no refs/remotes/origin/* branch is refused, because a tag-bearing checkout always holds them.
    _tt_git init -q "$d/tt3norb" && _tt_git -C "$d/tt3norb" remote add origin "file://$d/tt1/origin.git"
    for _tt_m in unset 1; do
      if [ "$_tt_m" = unset ]; then unset _tt_mode; else _tt_mode=1; fi
      _tt_expect "TT3d[$_tt_m]" "$d/tt3norb" 1 "holds no refs/remotes/origin branch" "a checkout with no remote-tracking branch is refused (fail-closed)"
    done
    # The mode switch: unset and empty are local only (accepted); every other value is a red, never "off".
    unset _tt_mode
    _tt_expect "TT3[mode unset]" "$d/tt1/clone" 0 "(local only)" "the switch absent runs the local check only"
    _tt_mode=""
    _tt_expect "TT3[mode empty]" "$d/tt1/clone" 0 "(local only)" "an empty switch runs the local check only"
    for _tt_mode in 0 yes " 1" true "1 " 2; do
      _tt_expect "TT3[mode '$_tt_mode']" "$d/tt1/clone" 1 "TRUNK_TAG_REMOTE must be empty or 1" "a garbled switch value is refused, never treated as off"
    done
    # The local check runs BEFORE the switch is parsed: an unset switch with a shadowing LOCAL tag is red, and a garbled switch in a directory that is no repository fails on the refs listing, not on the switch.
    unset _tt_mode
    _tt_git -C "$d/tt1/clone" update-ref refs/tags/origin/main "$_tt1_a"
    _tt_expect "TT3[unset+local tag]" "$d/tt1/clone" 1 "(refs/tags/origin/main; found: local)" "with the switch absent a local origin/main tag is still refused (the local check is not skipped)"
    _tt_git -C "$d/tt1/clone" update-ref -d refs/tags/origin/main
    mkdir -p "$d/tt3nogit"; _tt_mode="yes"
    _tt_expect "TT3[local first]" "$d/tt3nogit" 1 "cannot list this checkout's refs" "the local listing runs before the switch is parsed (a garbled switch outside a repository dies on the listing first)"
    unset _tt_mode

    # TT4 / TT5 — per job, in both workflows (each mutant edits ONLY the named job's block, so a pass in one job cannot mask a miss in another).
    for _tt_wf in ci ag; do
      if [ "$_tt_wf" = ci ]; then _tt_f=$_tt_ci; _tt_jobs=$TT_CI_JOBS; _tt_excl=$TT_CI_EXCLUDED
      else _tt_f=$_tt_ag; _tt_jobs=$TT_AG_JOBS; _tt_excl=$TT_AG_EXCLUDED; fi
      for _tt_j in $_tt_jobs; do
        _tt_l="$_tt_wf/$_tt_j"
        if [ -f "$_tt_f" ] && check_trunk_tag_tripwire "$_tt_f" "$_tt_j" >/dev/null 2>&1; then
          echo "selftest PASS: TT4a[$_tt_l] — the live job carries the step, ordered and unconditional (the anchor the mutants are measured against)"
        else echo "selftest FAIL: TT4a[$_tt_l] — the live job does not pass the step check"; sf=1; fi
        _tt_mut "$_tt_f" "$_tt_j" delete > "$d/tt-m.yml"
        _t4_msg=$(check_trunk_tag_tripwire "$d/tt-m.yml" "$_tt_j" 2>&1 >/dev/null || true)
        case "$_t4_msg" in
          *"$_tt_j job has no trunk-tag tripwire step"*) echo "selftest PASS: TT4b[$_tt_l] — the step deleted -> FAIL, naming the job" ;;
          *) echo "selftest FAIL: TT4b[$_tt_l] — the deleted step was not caught as absent; msg='$_t4_msg'"; sf=1 ;;
        esac
        _tt_mut "$_tt_f" "$_tt_j" move > "$d/tt-m.yml"
        _t4_msg=$(check_trunk_tag_tripwire "$d/tt-m.yml" "$_tt_j" 2>&1 >/dev/null || true)
        case "$_t4_msg" in
          *"does not precede the credential drop or the first PR-tree invocation"*) echo "selftest PASS: TT4c[$_tt_l] — the step moved after the drop or the PR-tree invocation -> FAIL" ;;
          *) echo "selftest FAIL: TT4c[$_tt_l] — the misordered step was not caught; msg='$_t4_msg'"; sf=1 ;;
        esac
        tt_body_of "$_tt_f" "$_tt_j" > "$d/tt-body-j.sh" 2>/dev/null || :
        if [ -s "$_tt_bodyf" ] && cmp -s "$_tt_bodyf" "$d/tt-body-j.sh"; then
          echo "selftest PASS: TT5[$_tt_l] — the run: body is byte-identical to the first copy"
        else echo "selftest FAIL: TT5[$_tt_l] — the run: body is missing or differs from the first copy"; sf=1; fi
        # rule (e): the remote switch is exactly "1" in the remote job (removed or "0" -> FAIL) and absent everywhere else (added -> FAIL).
        if [ "$_tt_j" = "$TT_REMOTE_JOB" ]; then _tt_ems="remove zero"; else _tt_ems="add"; fi
        for _tt_em in $_tt_ems; do
          _tt_envmut "$_tt_f" "$_tt_j" "$_tt_em" > "$d/tt-m.yml"
          _t4_msg=$(check_trunk_tag_tripwire "$d/tt-m.yml" "$_tt_j" 2>&1 >/dev/null || true)
          case "$_t4_msg" in
            *"(rule e)"*) echo "selftest PASS: TT4e[$_tt_l][$_tt_em] — the TRUNK_TAG_REMOTE env $_tt_em -> FAIL (rule e)" ;;
            *) echo "selftest FAIL: TT4e[$_tt_l][$_tt_em] — the env mutant was not caught; msg='$_t4_msg'"; sf=1 ;;
          esac
        done
        # TT6 — this job's checkouts keep main's persist-credentials values (no job gains a token).
        if [ -f "$_tt_f" ] && check_tt_credentials "$_tt_wf" "$_tt_f" "$_tt_j" >/dev/null 2>&1; then
          echo "selftest PASS: TT6[$_tt_l] — every checkout keeps main's persist-credentials value"
        else echo "selftest FAIL: TT6[$_tt_l] — a checkout's persist-credentials differs from main"; sf=1; fi
      done
      # TT4z — the list itself: a job that holds tags (fetch-depth 0, fetch-tags true, or a fetch that may bring them) is guarded or a named exclusion.
      if check_tt_tagbearing "$_tt_f" "$_tt_jobs" "$_tt_excl" >/dev/null 2>&1; then
        echo "selftest PASS: TT4z[$_tt_wf] — every tag-bearing job is guarded or a named exclusion"
      else echo "selftest FAIL: TT4z[$_tt_wf] — an unlisted tag-bearing job"; sf=1; fi
    done
    # TT4f (review F1) — the step placed between # CRED-DROP-END and the first conformance/ line (every job that carries a drop block): the drop is gone by then, so the step must still red. The limit is the marker, not a literal unset line.
    for _tt_fw in ci:ceremony-binding ci:loop-state ci:review-lane ag:ceremony-binding ag:review-lane ag:loop-state; do
      if [ "${_tt_fw%%:*}" = ci ]; then _tt_f=$_tt_ci; else _tt_f=$_tt_ag; fi
      _tt_j=${_tt_fw#*:}
      _tt_mut "$_tt_f" "$_tt_j" afterdrop > "$d/tt-m.yml"
      _t4_msg=$(check_trunk_tag_tripwire "$d/tt-m.yml" "$_tt_j" 2>&1 >/dev/null || true)
      case "$_t4_msg" in
        *"does not precede the credential drop or the first PR-tree invocation"*) echo "selftest PASS: TT4f[$_tt_fw] — the step placed after # CRED-DROP-END, before the first conformance/ line -> FAIL" ;;
        *) echo "selftest FAIL: TT4f[$_tt_fw] — the step after the drop block was not caught; msg='$_t4_msg'"; sf=1 ;;
      esac
    done
    # A later fetch that may bring tags (ceremony-binding's --no-tags dropped) -> FAIL on rule (d).
    _tt_mut "$_tt_ci" ceremony-binding nofl > "$d/tt-m.yml"
    _t4_msg=$(check_trunk_tag_tripwire "$d/tt-m.yml" ceremony-binding 2>&1 >/dev/null || true)
    case "$_t4_msg" in
      *"may bring tags in"*) echo "selftest PASS: TT4d — a tag-fetching git fetch after the step -> FAIL" ;;
      *) echo "selftest FAIL: TT4d — the tag-fetching fetch was not caught; msg='$_t4_msg'"; sf=1 ;;
    esac
    # TT6 load-bearing negatives, both directions: the revision-2 shape (the adopter loop-state head checkout WITHOUT persist-credentials: false, a token it never had) and its mirror (persist-credentials: false added to the kit ceremony-binding checkout, which would break its notes fetch and the remote read).
    _tt_pcmut "$_tt_ag" loop-state remove > "$d/tt-m.yml"
    _t4_msg=$(check_tt_credentials ag "$d/tt-m.yml" loop-state 2>&1 >/dev/null || true)
    case "$_t4_msg" in
      *"loop-state (ag) persist-credentials differs from main"*) echo "selftest PASS: TT6[LS] — the adopter loop-state head checkout without persist-credentials: false -> FAIL, naming the job" ;;
      *) echo "selftest FAIL: TT6[LS] — the revision-2 credential shape was not caught; msg='$_t4_msg'"; sf=1 ;;
    esac
    _tt_pcmut "$_tt_ci" ceremony-binding add > "$d/tt-m.yml"
    _t4_msg=$(check_tt_credentials ci "$d/tt-m.yml" ceremony-binding 2>&1 >/dev/null || true)
    case "$_t4_msg" in
      *"ceremony-binding (ci) persist-credentials differs from main"*) echo "selftest PASS: TT6[CB] — persist-credentials: false added to the kit ceremony-binding checkout -> FAIL, so the pin binds both ways" ;;
      *) echo "selftest FAIL: TT6[CB] — the mirror mutant was not caught; msg='$_t4_msg'"; sf=1 ;;
    esac
    # TT4z mutants (job|yaml line|trigger): a new job with a depth-0 checkout, an excluded job gaining fetch-tags, a new job whose fetch lacks --no-tags.
    for _tz in "zz-new|fetch-depth: 0|fetch-depth:0" "secret-scan|fetch-tags: true|fetch-tags:true" "zz-fetch|run: git fetch origin|git-fetch-may-bring-tags"; do
      _tz_job=${_tz%%|*}; _tz_rest=${_tz#*|}; _tz_line=${_tz_rest%%|*}; _tz_trig=${_tz_rest#*|}
      { cat "$_tt_ci"; printf '  %s:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          %s\n' "$_tz_job" "$_tz_line"; } > "$d/tt-z.yml"
      _t4_msg=$(check_tt_tagbearing "$d/tt-z.yml" "$TT_CI_JOBS" "$TT_CI_EXCLUDED" 2>&1 >/dev/null || true)
      case "$_t4_msg" in
        *"job $_tz_job holds tags ($_tz_trig)"*) echo "selftest PASS: TT4z[$_tz_job] — a new $_tz_trig trigger outside the list -> FAIL, naming the job and the trigger" ;;
        *) echo "selftest FAIL: TT4z[$_tz_job] — the unlisted $_tz_trig trigger was not caught; msg='$_t4_msg'"; sf=1 ;;
      esac
    done
    # TT4zd (SWAS-409): the two docs legs are the depth-0 jobs now. With the exclusion list WITHOUT them, TT4z must red on the real ci.yml, naming the leg
    # and the trigger — the proof that the two names added to TT_CI_EXCLUDED are load-bearing (and that the docs join, at the default depth, needs none).
    for _tz_leg in conformance-docs-1 conformance-docs-2; do
      _t4_msg=$(check_tt_tagbearing "$_tt_ci" "$TT_CI_JOBS" "conformance-core secret-scan" 2>&1 >/dev/null || true)
      case "$_t4_msg" in
        *"job $_tz_leg holds tags (fetch-depth:0)"*) echo "selftest PASS: TT4zd[$_tz_leg] — without its name in TT_CI_EXCLUDED the real ci.yml's depth-0 docs leg -> FAIL, naming the job and the trigger" ;;
        *) echo "selftest FAIL: TT4zd[$_tz_leg] — the leg was not flagged without its exclusion; msg='$_t4_msg'"; sf=1 ;;
      esac
    done
    case "$TT_CI_EXCLUDED" in
      *conformance-docs-1*conformance-docs-2*) echo "selftest PASS: TT4ze — TT_CI_EXCLUDED names both docs legs" ;;
      *) echo "selftest FAIL: TT4ze — TT_CI_EXCLUDED lacks a docs leg: $TT_CI_EXCLUDED"; sf=1 ;;
    esac
    case " $TT_CI_EXCLUDED " in
      *" conformance-docs "*) echo "selftest FAIL: TT4zf — the docs JOIN is still in TT_CI_EXCLUDED, but it checks out at the default depth and holds no tags: drop it"; sf=1 ;;
      *) echo "selftest PASS: TT4zf — the docs join (default-depth checkout) is not in TT_CI_EXCLUDED" ;;
    esac
  else
    echo "selftest SKIP: TT0-TT5 — not a kit tree"
  fi
  _st_mark TT

  # ── SWAS-246 — the trunk is read by its FULL ref (TF0-TF6) ─────────────────────────────────
  mkdir -p "$d/tf"
  _tf_hdr='jobs:\n  x:\n    steps:\n      - run: |\n'
  _tf_fetch_old="git fetch --no-tags origin main:refs/remotes/origin/main || true"
  _tf_bl='BACK''LOG.md'  # fixture TEXT only: assembled from parts so no source line is a literal board read to board-parser-drift
  _tf_show_old="if git show origin/main:${_tf_bl} > /tmp/base-${_tf_bl} 2>/dev/null; then"
  _tf_diff_old='git -c core.quotePath=false diff --name-only -z --no-renames "origin/${BASE_REF}...HEAD" > /tmp/changed.z'
  _tf_ls_good="  loop-state:\n    steps:\n      - run: |\n          git fetch --no-tags origin '+refs/heads/main:refs/remotes/origin/main' || true\n          git show-ref --verify -q refs/remotes/origin/main || exit 1\n          sh scripts/promotion-verify.sh trace --recent 10 --from refs/remotes/origin/main\n"
  printf "jobs:\n$_tf_ls_good  backlog-presence:\n    steps:\n      - run: |\n          git -c core.quotePath=false diff --name-only -z --no-renames \"refs/remotes/origin/\${BASE_REF}...HEAD\" > /tmp/changed.z\n          if git show refs/remotes/origin/main:${_tf_bl} > /tmp/base-${_tf_bl} 2>/dev/null; then\n" > "$d/tf/good.yml"
  if check_trunk_full_ref "$d/tf/good.yml" >/dev/null 2>&1; then
    echo "selftest PASS: TF1 — the four fixed spellings and the show-ref guard -> PASS"
  else echo "selftest FAIL: TF1 — good fixture wrongly failed"; sf=1; fi
  printf "${_tf_hdr}          $_tf_fetch_old\n" > "$d/tf/fetch.yml"
  if check_trunk_full_ref "$d/tf/fetch.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: TF2 — today's short-name fetch line was NOT caught"; sf=1
  else echo "selftest PASS: TF2 — today's short-name fetch line -> FAIL"; fi
  printf "${_tf_hdr}          sh scripts/promotion-verify.sh trace --recent 10 --from origin/main\n" > "$d/tf/from.yml"
  if check_trunk_full_ref "$d/tf/from.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: TF3 — --from origin/main was NOT caught"; sf=1
  else echo "selftest PASS: TF3 — --from origin/main -> FAIL"; fi
  printf "${_tf_hdr}          $_tf_show_old\n" > "$d/tf/show.yml"
  printf "${_tf_hdr}          $_tf_diff_old\n" > "$d/tf/diff.yml"
  if check_trunk_full_ref "$d/tf/show.yml" >/dev/null 2>&1 || check_trunk_full_ref "$d/tf/diff.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: TF4 — an exact live 'if git show origin/main' or 'git -c k=v diff origin/' line was NOT caught"; sf=1
  else echo "selftest PASS: TF4 — the exact live git show and git -c diff lines -> FAIL"; fi
  printf "jobs:\n$_tf_ls_good" | grep -vF 'show-ref' > "$d/tf/noguard.yml"
  if check_trunk_full_ref "$d/tf/noguard.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: TF4b — a loop-state trace with no show-ref guard was NOT caught"; sf=1
  else echo "selftest PASS: TF4b — loop-state without the show-ref guard -> FAIL"; fi
  printf "${_tf_hdr}          # git show origin/main:${_tf_bl}\n          echo \"merge-base between HEAD and origin/\$X\"\n" > "$d/tf/prose.yml"
  if check_trunk_full_ref "$d/tf/prose.yml" >/dev/null 2>&1; then
    echo "selftest PASS: TF5 — a comment and an echo line are not judged"
  else echo "selftest FAIL: TF5 — prose wrongly failed"; sf=1; fi

  # TF6 real-fleet backstop (kit tree only): S1-S4 are fixed in every workflow and template.
  if [ -f "$_agg_kr/.github/workflows/ci.yml" ] && { [ -f "$_agg_kr/docs/ROADMAP-KIT.md" ] || [ -f "$_agg_kr/.github/workflows/golden-path.yml" ]; }; then
    _tf_bad=0
    for _tf_wf in "$_agg_kr"/.github/workflows/*.yml "$_agg_kr"/profiles/*.yml "$_agg_kr"/profiles/*/ci.yml; do
      [ -f "$_tf_wf" ] || continue
      check_trunk_full_ref "$_tf_wf" || _tf_bad=1
    done
    if [ "$_tf_bad" = 0 ]; then
      echo "selftest PASS: TF6 — every workflow and profile template reads the trunk by its full ref"
    else echo "selftest FAIL: TF6 — a workflow or template reads the trunk by a short name a tag can shadow"; sf=1; fi
  else
    echo "selftest SKIP: TF6 — not a kit tree"
  fi

  # TF0 premise (local bare repo, no network): the short spelling lands a same-named tag, the full
  # spelling lands the trunk, and show-ref --verify refuses a tag named refs/remotes/origin/main.
  _tf_g="git -c commit.gpgsign=false -c user.name=t -c user.email=t@t"
  git init -q --bare "$d/tf/o.git" && git init -q "$d/tf/w" && git -C "$d/tf/w" symbolic-ref HEAD refs/heads/main \
    && $_tf_g -C "$d/tf/w" commit -q --allow-empty -m a && git -C "$d/tf/w" tag main \
    && $_tf_g -C "$d/tf/w" commit -q --allow-empty -m b \
    && git -C "$d/tf/w" push -q "$d/tf/o.git" refs/heads/main refs/tags/main 2>/dev/null
  _tf_tag=$(git -C "$d/tf/w" rev-parse refs/tags/main 2>/dev/null); _tf_trunk=$(git -C "$d/tf/w" rev-parse refs/heads/main 2>/dev/null)
  git init -q "$d/tf/c1" && git init -q "$d/tf/c2"
  git -C "$d/tf/c1" fetch -q --no-tags "$d/tf/o.git" main:refs/remotes/origin/main 2>/dev/null
  git -C "$d/tf/c2" fetch -q --no-tags "$d/tf/o.git" '+refs/heads/main:refs/remotes/origin/main' 2>/dev/null
  if [ -n "$_tf_tag" ] && [ "$_tf_tag" != "$_tf_trunk" ] \
    && [ "$(git -C "$d/tf/c1" rev-parse refs/remotes/origin/main 2>/dev/null)" = "$_tf_tag" ] \
    && [ "$(git -C "$d/tf/c2" rev-parse refs/remotes/origin/main 2>/dev/null)" = "$_tf_trunk" ]; then
    echo "selftest PASS: TF0 — the short fetch lands the tag, the full fetch lands the trunk"
  else echo "selftest FAIL: TF0 — git's resolution no longer matches the premise of the full-ref lock"; sf=1; fi
  git -C "$d/tf/w" tag refs/remotes/origin/main "$_tf_tag" 2>/dev/null
  if [ "$(git -C "$d/tf/w" rev-parse refs/remotes/origin/main 2>/dev/null)" = "$_tf_tag" ] \
    && ! git -C "$d/tf/w" show-ref --verify -q refs/remotes/origin/main; then
    echo "selftest PASS: TF0b — a tag named refs/remotes/origin/main resolves, and show-ref --verify refuses it"
  else echo "selftest FAIL: TF0b — the show-ref --verify guard no longer refuses a tag spelling"; sf=1; fi
  _st_mark TF

  # ST0-ST8 (SWAS-363) — the selftest fails closed. These cells sit in the LAST section and each planted copy dies right after its _st_begin call,
  # before it reaches any section, so a copy can never start copies of its own (no environment seam exists; ST5 asserts it). The copy lives at
  # $d/st/conformance/ci-gates.sh; its kit root ($d/st) is never read. ST0, the positive control, is printed by _st_end itself on the real run.
  # The call word, the exit-trap word and the awk builtin are assembled from parts, so no source line here is itself a mark, a trap line or a
  # bare use of the builtin (the static checks below, and `grep -w`, read this file).
  mkdir -p "$d/st/conformance"
  _st_mk=_st_ma; _st_mk="${_st_mk}rk"
  _st_tr=tra; _st_tr="${_st_tr}p"
  _st_xp=e; _st_xp="${_st_xp}xp"
  _st_dn=_st_do; _st_dn="${_st_dn}ne"
  _st_plant() {  # <plant-line> [<line-to-drop>] -> the real file with the plant right after the _st_begin call (and one line dropped); _st_planted says whether it landed
    awk -v plant="$1" -v drop="${2:-}" '
      drop != "" && index($0, drop) { next }
      { print }
      /^  _st_begin$/ { print "  " plant }' "$0" > "$d/st/conformance/ci-gates.sh"
    if grep -qxF -- "  $1" "$d/st/conformance/ci-gates.sh"; then _st_planted=1
    else _st_planted=0; echo "selftest FAIL: ST — plant not inserted ($1): the copy is not run, and the cell that needed it is not judged"; sf=1; fi
  }
  _st_run() {  # <name=value preset for the copy's environment> -> _st_out, _st_rc of the planted copy (not run when the plant did not land)
    if [ "$_st_planted" != 1 ]; then _st_out=''; _st_rc=-1; return 0; fi
    if _st_out=$(env "$1" sh "$d/st/conformance/ci-gates.sh" --selftest 2>&1); then _st_rc=0; else _st_rc=$?; fi
  }
  _st_judge() {  # <id> <desc> <want-rc> <needle>... -> PASS when _st_rc is <want-rc> and _st_out holds every needle
    if [ "$_st_planted" != 1 ]; then return 0; fi
    _sj_id=$1; _sj_desc=$2; _sj_rc=$3; shift 3
    _sj_ok=1
    if [ "$_st_rc" != "$_sj_rc" ]; then _sj_ok=0; fi
    for _sj_n in "$@"; do
      case "$_st_out" in
        *"$_sj_n"*) : ;;
        *) _sj_ok=0 ;;
      esac
    done
    if [ "$_sj_ok" = 1 ]; then echo "selftest PASS: $_sj_id — $_sj_desc"
    else echo "selftest FAIL: $_sj_id — $_sj_desc (rc=$_st_rc want $_sj_rc; needles: $*; out='$_st_out')"; sf=1; fi
  }
  _st_endmark="ended before its end marker"
  _st_plant "exit 0"
  _st_run _st_probe=0; _st1_out=$_st_out
  _st_judge ST1 "a planted exit 0 right after _st_begin -> the copy exits 1, naming the missing end marker and no section reached" 1 "$_st_endmark" "last section: none"
  _st_plant "awk 'BEGIN { $_st_xp = 1 }'; exit 97"
  _st_run _st_probe=0; _st2_out=$_st_out
  _st_judge ST2 "a builtin used as an awk variable (the F1 trigger) aborts the copy -> exit 1, naming the missing end marker" 1 "$_st_endmark" "last section: none"
  if [ "$_st_planted" = 1 ]; then
    case "$_st_out" in
      *"rc 97"*) echo "selftest FAIL: ST2b — the awk accepted the builtin as a variable, so ST2 replayed nothing (the copy reached its backstop exit 97)"; sf=1 ;;
      *) echo "selftest PASS: ST2b — the awk really aborted (the backstop exit 97 was not reached)" ;;
    esac
  fi
  _st_plant "exit 0"
  _st_run "$_st_dn=1"
  _st_judge ST4 "an environment-preset _st_done=1 plus a planted exit 0 still exits 1 (the state is reset with no conditions)" 1 "$_st_endmark"
  case "$_st1_out$_st2_out" in
    *"selftest PASS: ST"*) echo "selftest FAIL: ST5 — a planted copy printed an ST cell, so it ran past its plant and could nest copies of its own"; sf=1 ;;
    *) echo "selftest PASS: ST5 — the planted copies die before any section (no ST cell line in their output), so they cannot recurse" ;;
  esac
  _st_plant "kill -TERM \$\$"
  _st_run _st_probe=0
  _st_judge ST7 "a TERM sent to the copy exits 1 with rc 130 named (an interrupted run is never green)" 1 "$_st_endmark" "rc 130"
  _st_plant "kill -TERM \$\$" "$_st_tr 'exit 130' INT TERM"
  _st_run _st_probe=0
  _st_named=0
  case "$_st_out" in
    *"rc 130"*) _st_named=1 ;;
  esac
  if [ "$_st_planted" != 1 ]; then :
  elif grep -qF "$_st_tr 'exit 130' INT TERM" "$d/st/conformance/ci-gates.sh"; then
    echo "selftest FAIL: ST7m — the INT/TERM line was not dropped from the mutant (nothing to mutate)"; sf=1
  elif [ "$_st_rc" = 1 ] && [ "$_st_named" = 1 ]; then
    echo "selftest FAIL: ST7m — without the INT/TERM line a TERM still read as exit 1 with rc 130 named: ST7 pins nothing"; sf=1
  else echo "selftest PASS: ST7m — without the INT/TERM line a TERM no longer reads as exit 1 with rc 130 named (rc=$_st_rc), so ST7 has teeth"; fi
  # ST3 — the ledger, in-process: the exact set, each id once, in any order.
  _st_ledger() {  # <id> <list> <seen> <want-needle|-> <desc> -> a '-' needle wants rc 0, otherwise rc 1 naming the needle
    if _sl_o=$(_st_check "$2" "$3"); then _sl_rc=0; else _sl_rc=1; fi
    _sl_named=0
    case "$_sl_o" in
      *"$4"*) _sl_named=1 ;;
    esac
    if [ "$4" = "-" ] && [ "$_sl_rc" = 0 ]; then echo "selftest PASS: $1 — $5"
    elif [ "$4" != "-" ] && [ "$_sl_rc" = 1 ] && [ "$_sl_named" = 1 ]; then echo "selftest PASS: $1 — $5 -> RED, naming '$4'"
    else echo "selftest FAIL: $1 — $5 (rc=$_sl_rc, needle '$4'): $_sl_o"; sf=1; fi
  }
  _st_ledger ST3a "A B" " B A" - "every listed section marked once, in any order -> OK"
  _st_ledger ST3 "A B" " A" "section B" "a section never reached"
  _st_ledger ST3b "A B" " A B B" "section B was marked 2 times" "a section marked twice"
  _st_ledger ST3c "A" " A Z" "section Z" "a mark for an id outside the list"
  # ST3d — _st_end itself: a shortfall sets sf (so the verdict line follows) and still sets the end marker; a complete ledger leaves sf alone.
  _st_sf=$(_ST_SECTIONS="A B"; _st_seen=" A"; sf=0; _st_end --no-trap-check >/dev/null; echo "$sf$_st_done")
  if [ "$_st_sf" = 11 ]; then echo "selftest PASS: ST3d — _st_end on a shortfall sets sf=1 and the end marker (the verdict line then reds)"
  else echo "selftest FAIL: ST3d — _st_end on a shortfall left sf/_st_done as '$_st_sf' (want 11)"; sf=1; fi
  _st_sf=$(_ST_SECTIONS="A B"; _st_seen=" B A"; sf=0; _st_end --no-trap-check >/dev/null; echo "$sf$_st_done")
  if [ "$_st_sf" = 01 ]; then echo "selftest PASS: ST3e — _st_end on a complete ledger leaves sf=0 and sets the end marker"
  else echo "selftest FAIL: ST3e — _st_end on a complete ledger left sf/_st_done as '$_st_sf' (want 01)"; sf=1; fi
  # ST8 — S3: _st_end also reads the shell's own trap listing; a replaced EXIT trap (one that no longer names _st_done) sets sf. The trap is set inside the subshell, so the listing is that subshell's own.
  _st_sf=$($_st_tr ':' EXIT; _ST_SECTIONS="A"; _st_seen=" A"; sf=0; _st_end >/dev/null; echo "$sf")
  if [ "$_st_sf" = 1 ]; then echo "selftest PASS: ST8m — _st_end with the EXIT trap replaced sets sf=1 (the EXIT trap was replaced)"
  else echo "selftest FAIL: ST8m — _st_end with a replaced EXIT trap left sf='$_st_sf' (want 1)"; sf=1; fi
  _st_sf=$($_st_tr 'x=$_st_done' EXIT; _ST_SECTIONS="A"; _st_seen=" A"; sf=0; _st_end >/dev/null; echo "$sf")
  if [ "$_st_sf" = 0 ]; then echo "selftest PASS: ST8b — _st_end with an EXIT trap that names _st_done leaves sf=0"
  else echo "selftest FAIL: ST8b — _st_end with an EXIT trap naming _st_done left sf='$_st_sf' (want 0)"; sf=1; fi
  _st_sf=$($_st_tr - EXIT; $_st_tr 'x=$_st_done' INT; _ST_SECTIONS="A"; _st_seen=" A"; sf=0; _st_end >/dev/null; echo "$sf")
  if [ "$_st_sf" = 1 ]; then echo "selftest PASS: ST8c — a trap that names _st_done on INT, not EXIT, does not count (sf=1)"
  else echo "selftest FAIL: ST8c — _st_end accepted a non-EXIT trap naming _st_done (sf='$_st_sf', want 1)"; sf=1; fi
  # ST8cm — the mutant of ST8c: _st_end with its EXIT-line requirement loosened back to "any trap line naming _st_done". Its function text is cut out of the mutated copy and sourced in a subshell.
  awk '{ i = index($0, " | grep -Eq "); if (i && index($0, "EXIT|0")) $0 = substr($0, 1, i - 1) " | grep -q .; then" } { print }' "$0" > "$d/st/m8c.sh"
  sed -n '/^_st_end() {/,/^}/p' "$d/st/m8c.sh" > "$d/st/end_m.sh"
  if cmp -s "$0" "$d/st/m8c.sh" || ! grep -qF 'grep -q .; then' "$d/st/end_m.sh"; then
    echo "selftest FAIL: ST8cm — the loosening was not applied to the copy (nothing to mutate)"; sf=1
  else
    _st_sf=$(. "$d/st/end_m.sh"; $_st_tr - EXIT; $_st_tr 'x=$_st_done' INT; _ST_SECTIONS="A"; _st_seen=" A"; sf=0; _st_end >/dev/null; echo "$sf")
    if [ "$_st_sf" = 0 ]; then echo "selftest PASS: ST8cm — with the EXIT-line requirement loosened, the ST8c scenario reads sf=0, so ST8c would red (it has teeth)"
    else echo "selftest FAIL: ST8cm — with the EXIT-line requirement loosened the ST8c scenario still reads sf='$_st_sf': ST8c pins nothing"; sf=1; fi
  fi  # ST3m — every _ST_SECTIONS id is exactly one plain top-level mark line in selftest() (a mark in a pipeline or a subshell would be lost).
  if _st_o=$(check_st_marks "$0"); then echo "selftest PASS: ST3m0 — every _ST_SECTIONS id has exactly one plain top-level mark line in selftest()"
  else echo "selftest FAIL: ST3m0 — the real file's marks do not match _ST_SECTIONS: $_st_o"; sf=1; fi
  sed "/^  ${_st_mk} OT\$/d" "$0" > "$d/st/m1.sh"
  sed "s/^  ${_st_mk} DQ\$/  true | ${_st_mk} DQ/" "$0" > "$d/st/m2.sh"
  awk -v m="  $_st_mk RP" '{ print } $0 == m { print }' "$0" > "$d/st/m3.sh"
  awk -v l="  $_st_dn=1" '{ print } /^  _st_begin$/ { print l }' "$0" > "$d/st/m4.sh"
  sed '/^  _st_end$/d' "$0" > "$d/st/m5.sh"
  awk '{ print } $0 == "  _st_end" { print "  sf=0" }' "$0" > "$d/st/m6.sh"
  for _st_m in "m1:section OT:ST3m:a mark deleted" "m2:section DQ:ST3m2:a mark moved into a pipeline" "m3:section RP:ST3m3:a mark doubled" \
               "m4:exactly one assignment, inside _st_end():ST3m4:a second end-marker assignment planted after _st_begin" \
               "m5:exactly once as a plain top-level line:ST3m5:the _st_end call deleted" \
               "m6:immediately before the verdict line:ST3m6:a line planted between the _st_end call and the verdict"; do
    _st_f=${_st_m%%:*}; _st_r=${_st_m#*:}; _st_want=${_st_r%%:*}; _st_r=${_st_r#*:}
    _st_id=${_st_r%%:*}; _st_desc=${_st_r#*:}
    if cmp -s "$0" "$d/st/$_st_f.sh"; then echo "selftest FAIL: $_st_id — the mutant equals the original (nothing to mutate)"; sf=1
    else
      # the text is matched in-process with case: the old printf|grep -q verdict flipped once with the needle present (cause not reproduced; a writer SIGPIPE cannot change a non-pipefail status, so likely a grep spawn failure or a signal under load); case removes the external step
      if _st_o=$(check_st_marks "$d/st/$_st_f.sh"); then _st_cr=0; else _st_cr=$?; fi
      _st_named=0
      case "$_st_o" in
        *"$_st_want"*) _st_named=1 ;;
      esac
      if [ "$_st_cr" = 0 ]; then echo "selftest FAIL: $_st_id — $_st_desc was NOT caught"; sf=1
      elif [ "$_st_named" = 1 ]; then echo "selftest PASS: $_st_id — $_st_desc -> RED, naming '$_st_want'"
      else echo "selftest FAIL: $_st_id — $_st_desc reds without naming '$_st_want' (check rc $_st_cr, mutant $(wc -l < "$d/st/$_st_f.sh") lines, original $(wc -l < "$0"), $(grep -c '_st_done[[:space:]]*=[[:space:]]*1' "$d/st/$_st_f.sh" || :) end-marker lines): $_st_o"; sf=1; fi
    fi
  done
  # ST6 — exactly one exit trap (EXIT or 0) in the whole file; a second would silently replace the sentinel.
  if _st_o=$(check_one_exit_trap "$0"); then echo "selftest PASS: ST6a — the real file holds exactly one exit-trap line (the sentinel in _st_begin)"
  else echo "selftest FAIL: ST6a — $_st_o"; sf=1; fi
  _st_plant "$_st_tr 'rm -rf \"\$d\"' EXIT"; cp "$d/st/conformance/ci-gates.sh" "$d/st/m6.sh"
  _st_plant "$_st_tr 'rm -rf \"\$d\"' exit"; cp "$d/st/conformance/ci-gates.sh" "$d/st/m6c.sh"
  _st_plant "$_st_tr 'x' INT; return 0"; cp "$d/st/conformance/ci-gates.sh" "$d/st/m6d.sh"
  awk -v plant="$_st_tr ':' 0" '/^selftest\(\) \{/ { print plant } { print }' "$0" > "$d/st/m6b.sh"
  # ST6d is a negative control, not a mutant: a trap on INT followed by a separate command is not an exit trap, so the count stays at one
  if _st_o=$(check_one_exit_trap "$d/st/m6d.sh"); then echo "selftest PASS: ST6d — a trap on INT followed by a separate command is not counted as an exit trap"
  else echo "selftest FAIL: ST6d — a trap on INT followed by a separate command was counted: $_st_o"; sf=1; fi
  for _st_m in "m6:ST6:a second EXIT trap planted after _st_begin" "m6b:ST6b:a trap on 0 planted at top level outside selftest()" "m6c:ST6c:a trap on lowercase exit planted after _st_begin"; do
    _st_f=${_st_m%%:*}; _st_r=${_st_m#*:}; _st_id=${_st_r%%:*}; _st_desc=${_st_r#*:}
    _st_file="$d/st/$_st_f.sh"
    if cmp -s "$0" "$_st_file"; then echo "selftest FAIL: $_st_id — the mutant equals the original (nothing to mutate)"; sf=1
    else
      if _st_o=$(check_one_exit_trap "$_st_file"); then _st_cr=0; else _st_cr=$?; fi
      _st_named=0
      case "$_st_o" in
        *"want exactly one"*) _st_named=1 ;;
      esac
      if [ "$_st_cr" = 0 ]; then echo "selftest FAIL: $_st_id — $_st_desc was NOT caught"; sf=1
      elif [ "$_st_named" = 1 ]; then echo "selftest PASS: $_st_id — $_st_desc -> RED, naming 'want exactly one'"
      else echo "selftest FAIL: $_st_id — $_st_desc reds without naming 'want exactly one' (check rc $_st_cr): $_st_o"; sf=1; fi
    fi
  done
  _st_mark ST

  # ── SWAS-281 (CI-TIME-BUDGET) — `--count-legs` (B4, B17) and the ci-time-report lock TW1 (B11) ──────────────────
  _cl_mk() {  # <root> <file> <yaml, with \n escapes>
    mkdir -p "$1/.github/workflows"; printf '%b' "$3" > "$1/.github/workflows/$2"
  }
  _cl_mut() {  # <name> <sed-expr> : a MUTANT of this very script, applied to a temp copy; prints its path, or fails if the mutation did not apply
    sed "$2" "$0" > "$d/mut-$1.sh"
    if cmp -s "$0" "$d/mut-$1.sh"; then echo "selftest FAIL: mutant $1 did not apply (the sed matched nothing)" >&2; return 1; fi
    printf '%s\n' "$d/mut-$1.sh"
  }
  _cl_pr='on:\n  pull_request:\n  push:\n    branches: [main]\njobs:\n'
  _cl_expect() {  # <leg> <root> <want-rc> <needle> <what> [script]: run `--count-legs <root>` and grade its rc and one needle
    _ce_s=${6:-$0}
    if _ce_o=$(sh "$_ce_s" --count-legs "$2" 2>&1); then _ce_rc=0; else _ce_rc=$?; fi
    case "$_ce_o" in *"$4"*) _ce_n=1 ;; *) _ce_n=0 ;; esac
    if [ "$_ce_rc" = "$3" ] && [ "$_ce_n" = 1 ]; then echo "selftest PASS: $1 — $5"
    else echo "selftest FAIL: $1 — $5 (rc=$_ce_rc want $3; needle '$4'; out='$_ce_o')"; sf=1; fi
  }
  _cl_mk "$d/cl1" a.yml "${_cl_pr}  a:\n    strategy:\n      fail-fast: false\n      matrix:\n        v: [x, y]\n        s: [1, 2, 3, 4]\n    steps:\n      - run: x\n  b:\n    steps:\n      - run: y\n"
  _cl_expect B4a "$d/cl1" 0 "a.yml a 8" "a 2 x 4 matrix counts 8 legs (fail-fast is not an axis)"
  _cl_expect B4a2 "$d/cl1" 0 "total 9" "a job with no matrix counts 1, and the total is the sum"
  _cl_mk "$d/cl2" a.yml "${_cl_pr}  a:\n    strategy:\n      matrix:\n        include:\n          - k: 1\n          - k: 2\n          - k: 3\n    steps:\n      - run: x\n"
  _cl_expect B4b "$d/cl2" 0 "a.yml a 3" "an include: list counts its entries"
  _cl_mk "$d/cl3" a.yml "${_cl_pr}  a:\n    strategy:\n      matrix:\n        os:\n          - one\n          - two\n    steps:\n      - run: x\n"
  _cl_expect B4c "$d/cl3" 0 "a.yml a 2" "a block-list axis counts its items"
  _cl_mk "$d/cl4" a.yml "${_cl_pr}  a:\n    strategy:\n      matrix: \${{ fromJSON(needs.x.outputs.m) }}\n    steps:\n      - run: x\n"
  _cl_expect B4d "$d/cl4" 1 "FAIL: count-legs" "an expression matrix is a FAIL, never 1"
  _cl_mutc=$(_cl_mut matrix 's/sz \*= cnt\[k\]/sz *= 1/') || sf=1
  if [ -n "${_cl_mutc:-}" ] && ! sh "$_cl_mutc" --count-legs "$d/cl1" 2>&1 | grep -qF "a.yml a 8"; then
    echo "selftest PASS: B4m — the ignore-the-matrix mutant no longer prints 8 for the 2 x 4 fixture"
  else echo "selftest FAIL: B4m — the matrix mutant still prints 8, so the 2 x 4 fixture cannot see it"; sf=1; fi
  # B17: every triggered workflow, no list to forget; refusals; the one allowlisted privileged job.
  _cl_mk "$d/cl5" z-unlisted.yml "${_cl_pr}  q:\n    steps:\n      - run: x\n"
  _cl_mk "$d/cl5" s.yml 'on:\n  schedule:\n    - cron: "0 7 * * 1"\njobs:\n  sched:\n    steps:\n      - run: x\n'
  _cl_expect B17a "$d/cl5" 0 "z-unlisted.yml q 1" "an unlisted workflow with a pull_request trigger is counted"
  if sh "$0" --count-legs "$d/cl5" 2>&1 | grep -qF "s.yml"; then echo "selftest FAIL: B17a2 — a schedule-only workflow was counted"; sf=1
  else echo "selftest PASS: B17a2 — a schedule-only workflow is not counted"; fi
  _cl_mk "$d/cl6" a.yml "${_cl_pr}  u:\n    uses: ./.github/workflows/other.yml\n"
  _cl_expect B17b "$d/cl6" 1 "reusable" "a reusable-workflow uses: job is a FAIL (its legs cannot be counted here)"
  _cl_mk "$d/cl7" a.yml 'on:\n  workflow_run:\n    workflows: [CI]\njobs:\n  w:\n    steps:\n      - run: x\n'
  _cl_expect B17c "$d/cl7" 1 "workflow_run" "a workflow_run trigger is a FAIL"
  _cl_mk "$d/cl8" other.yml 'on:\n  pull_request_target:\njobs:\n  p:\n    steps:\n      - run: x\n'
  _cl_expect B17d "$d/cl8" 1 "pull_request_target" "a pull_request_target trigger in any file but the allowlisted one is a FAIL"
  _cl_ok='on:\n  pull_request_target:\n  schedule:\n    - cron: "17 6 * * *"\njobs:\n  tracker-board-gates:\n    if: github.event_name == '"'"'pull_request_target'"'"'\n    steps:\n      - run: x\n  tracker-board-drift:\n    if: github.event_name == '"'"'schedule'"'"'\n    steps:\n      - run: y\n'
  _cl_mk "$d/cl9" adopter-tracker-gates.yml "$_cl_ok"
  _cl_expect B17e "$d/cl9" 0 "adopter-tracker-gates.yml tracker-board-gates 1" "the allowlisted file with its one tracker-board-gates privileged job is counted and green"
  _cl_mk "$d/cl10" adopter-tracker-gates.yml 'on:\n  pull_request_target:\njobs:\n  tracker-board-gates:\n    if: github.event_name == '"'"'pull_request_target'"'"'\n    steps:\n      - run: x\n  second:\n    if: github.event_name == '"'"'pull_request_target'"'"'\n    steps:\n      - run: y\n'
  _cl_expect B17f "$d/cl10" 1 "privileged" "MUTANT a second privileged job in the allowlisted file is a FAIL"
  _cl_mk "$d/cl11" adopter-tracker-gates.yml 'on:\n  pull_request_target:\njobs:\n  renamed-gates:\n    if: github.event_name == '"'"'pull_request_target'"'"'\n    steps:\n      - run: x\n'
  _cl_expect B17g "$d/cl11" 1 "privileged" "MUTANT the allowed job renamed is a FAIL (the allowlist is keyed to the file AND the job id)"
  _cl_mk "$d/cl12" adopter-tracker-gates.yml 'on:\n  pull_request_target:\njobs:\n  tracker-board-gates:\n    if: github.event_name == '"'"'pull_request_target'"'"'\n    steps:\n      - run: x\n  noif:\n    steps:\n      - run: y\n'
  _cl_expect B17i "$d/cl12" 1 "no job-level if" "MUTANT a second job with NO if: in the allowlisted file (it also runs on pull_request_target) is a FAIL"
  _cl_mk "$d/cl13" adopter-tracker-gates.yml 'on:\n  pull_request_target:\njobs:\n  tracker-board-gates:\n    if: github.event_name == '"'"'pull_request_target'"'"'\n    steps:\n      - run: x\n  other:\n    if: github.actor != '"'"'x'"'"'\n    steps:\n      - run: y\n'
  _cl_expect B17j "$d/cl13" 1 "does not name only schedule or workflow_dispatch" "MUTANT a second job whose if: names no other event is a FAIL"
  _cl_mutd=$(_cl_mut allowlist 's/"adopter-tracker-gates.yml"/"never-this-file.yml"/') || sf=1
  [ -z "${_cl_mutd:-}" ] || _cl_expect B17h "$d/cl9" 1 "pull_request_target" "MUTANT the allowlist dropped: the allowlisted file now FAILs, so the allowlist is load-bearing" "$_cl_mutd"
  # the kit's own tree, when this is one: every triggered workflow parses, and ci.yml's battery matrix is counted
  if [ -f "$_agg_kr/.github/workflows/ci.yml" ] && { [ -f "$_agg_kr/docs/ROADMAP-KIT.md" ] || [ -f "$_agg_kr/.github/workflows/golden-path.yml" ]; }; then
    _cl_expect B4r "$_agg_kr" 0 "ci.yml guard-battery-shard 8" "the real tree parses: guard-battery-shard is 2 variants x 4 shards = 8 legs"
  else echo "selftest SKIP: B4r — not a kit tree"; fi

  # TW1 (B11): the ci-time-report job can never red a run.
  _tw_job='  ci-time-report:\n    needs:\n      - a\n    if: always()\n    continue-on-error: true\n    timeout-minutes: 5\n    runs-on: ubuntu-24.04\n    steps:\n      - run: sh scripts/ci-time-report.sh || :\n'
  printf '%b' "jobs:\n  a:\n    steps:\n      - run: x\n$_tw_job" > "$d/tw-good.yml"
  if check_ci_time_report "$d/tw-good.yml" >/dev/null 2>&1; then echo "selftest PASS: TW1[good] — a continue-on-error, timed, unrequired, wrapped job passes"
  else echo "selftest FAIL: TW1[good] — the good fixture wrongly failed"; sf=1; fi
  _tw_try() {  # <leg> <why> <yaml-with-escapes> : a mutant that must FAIL, naming <why>
    printf '%b' "$3" > "$d/tw-m.yml"
    _tw_m=$(check_ci_time_report "$d/tw-m.yml" 2>&1 || true)
    case "$_tw_m" in *"$2"*) echo "selftest PASS: $1 — $2" ;; *) echo "selftest FAIL: $1 — not caught ($2); msg='$_tw_m'"; sf=1 ;; esac
  }
  _tw_try TW1a "continue-on-error" "jobs:\n  a:\n    steps:\n      - run: x\n  ci-time-report:\n    needs:\n      - a\n    if: always()\n    timeout-minutes: 5\n    steps:\n      - run: sh scripts/ci-time-report.sh || :\n"
  _tw_try TW1b "timeout-minutes" "jobs:\n  a:\n    steps:\n      - run: x\n  ci-time-report:\n    continue-on-error: true\n    steps:\n      - run: sh scripts/ci-time-report.sh || :\n"
  _tw_try TW1c "outside its own job" "jobs:\n  conformance:\n    needs: [a, ci-time-report]\n    steps:\n      - run: x\n$_tw_job"
  _tw_try TW1d "outside the || : wrapper" "jobs:\n  ci-time-report:\n    continue-on-error: true\n    timeout-minutes: 5\n    steps:\n      - run: |\n          sh scripts/ci-time-report.sh || :\n          exit 1\n"
  _tw_try TW1e "outside the || : wrapper" "jobs:\n  ci-time-report:\n    continue-on-error: true\n    timeout-minutes: 5\n    steps:\n      - run: sh scripts/ci-time-report.sh\n"
  _tw_try TW1f "::error" "jobs:\n  ci-time-report:\n    continue-on-error: true\n    timeout-minutes: 5\n    steps:\n      - run: echo '::error::x' || :\n"
  _tw_try TW1g "does not list job b in its needs" "jobs:\n  a:\n    steps:\n      - run: x\n  b:\n    steps:\n      - run: y\n$_tw_job"
  if [ -f "$_agg_kr/.github/workflows/ci.yml" ] && [ -f "$_agg_kr/conformance/ci-classify-changes.sh" ] && { [ -f "$_agg_kr/docs/ROADMAP-KIT.md" ] || [ -f "$_agg_kr/.github/workflows/golden-path.yml" ]; }; then
    _tw_r=$(check_ci_time_report "$_agg_kr/.github/workflows/ci.yml" 2>&1 || true)
    if [ -z "$_tw_r" ] \
       && [ "$(extract_job_block "$_agg_kr/.github/workflows/ci.yml" ci-time-report | sed 's/#.*//' | grep -c 'continue-on-error: true')" = 1 ]; then
      echo "selftest PASS: TW1r — the real ci.yml carries the ci-time-report job (liveness) and it passes TW1"
    else echo "selftest FAIL: TW1r — the real ci.yml has no ci-time-report job, or it fails TW1: [$_tw_r]"; sf=1; fi
    awk 'BEGIN{j=0} /^  ci-time-report:/{j=1} j && /^    continue-on-error: true/{next} /^  [a-z]/&&!/^  ci-time-report:/{j=0} {print}' "$_agg_kr/.github/workflows/ci.yml" > "$d/tw-real.yml"
    _tw_a=$(aggregator_needs_lock "$d/tw-real.yml" "$_agg_kr/conformance/ci-classify-changes.sh" 2>&1 || true)
    case "$_tw_a" in *"continue-on-error"*) echo "selftest PASS: TW1w — the aggregator lock itself reds when the real job loses continue-on-error (the lock is wired)" ;;
      *) echo "selftest FAIL: TW1w — --aggregator-lock stayed green without continue-on-error; msg='$_tw_a'"; sf=1 ;; esac
  else echo "selftest SKIP: TW1r/TW1w — not a kit tree"; fi
  _st_mark TB

  # ── SWAS-409 (CI-SHAPING S4) — the shard joins: C30 (docs pin and partition), C31 (structure, leg results, the no-weakening lock class), C32 (gate-test) ──
  # Every negative is a one-line edit of a generated BASE workflow and must red AND name its cause. The base fixtures are built here, not read from the
  # live ci.yml, so a cell never depends on the file it grades; SJ60/SJ61 grade the live file. The M cells run a sed-edited COPY of this script on the same
  # fixtures through the `--shard-join` run mode and require the cell's expectation to FAIL under the mutation (the mutant is caught).
  mkdir -p "$d/sj"
  _sj_q="'"
  _sj_if="needs.changes.outputs.docs_only != ${_sj_q}true${_sj_q} && needs.changes.outputs.push_graded != ${_sj_q}true${_sj_q}"
  _sj_dif="needs.changes.outputs.push_graded != ${_sj_q}true${_sj_q}"
  _sj_hdr() {  # <leg> <if-clause> -> a leg job header with the aggregator marker on its if: line
    printf '  %s:\n    needs: changes\n    if: %s   # not a required check -> a job-level skip is safe\n    runs-on: ubuntu-24.04\n    steps:\n' "$1" "$2"
  }
  _sj_trio() {
    printf '      - name: Install Node 24 (x)\n        uses: actions/setup-node@x\n        with:\n          node-version: %s24%s\n' "$_sj_q" "$_sj_q"
    printf '      - name: Install the sandbox%ss Linux prerequisites (x)\n        run: sudo apt-get install -y bubblewrap socat\n' "$_sj_q"
    printf '      - name: Allow unprivileged user namespaces (x)\n        run: |\n          key=kernel.x\n          sudo sysctl -w "$key=0" || echo could-not-set\n'
  }
  _sj_join_head() {  # <join> <legs...> -> the join's job header through its env (steps follow)
    _sjh_j=$1; shift
    printf '  %s:\n    needs:\n      - changes\n' "$_sjh_j"
    for _sjh_l in "$@"; do printf '      - %s\n' "$_sjh_l"; done
    printf '    if: ${{ !cancelled() && %s }}\n    runs-on: ubuntu-24.04\n    env:\n      LEG_RESULTS:' "$_sj_if"
    for _sjh_l in "$@"; do printf ' ${{ needs.%s.result }}' "$_sjh_l"; done
    printf '\n    steps:\n      - uses: actions/checkout@x\n'
  }
  _sj_base_st() {  # <file> [gatefirst] -> a sound selftests shard workflow: 2 legs with the trio, a join with shard-join, --legs, gate-test last
    {
      printf 'on:\n  pull_request:\njobs:\n  changes:\n    runs-on: ubuntu-24.04\n'
      _sj_hdr conformance-selftests-1 "$_sj_if"; printf '      - uses: actions/checkout@x\n      - name: a self-test\n        run: sh conformance/a.sh --selftest\n'; _sj_trio
      _sj_hdr conformance-selftests-2 "$_sj_if"; printf '      - uses: actions/checkout@x\n'; _sj_trio; printf '      - name: b self-test\n        run: sh conformance/b.sh --selftest\n'
      _sj_join_head conformance-selftests conformance-selftests-1 conformance-selftests-2
      if [ "${2:-}" = gatefirst ]; then printf '      - name: Battery complete (gate-test)\n        id: gate-test\n        run: echo done\n'; fi
      printf '      - name: Legs\n        run: sh conformance/ci-gates.sh --shard-join conformance-selftests "$LEG_RESULTS"\n'
      printf '      - name: Partition\n        run: sh conformance/ci-selftest-coverage.sh --legs conformance-selftests\n'
      if [ "${2:-}" != gatefirst ]; then printf '      - name: Battery complete (gate-test)\n        id: gate-test\n        run: echo done\n'; fi
    } > "$1"
  }
  _sj_base_dc() {  # <file> -> a sound docs shard workflow: a core job (for the foreign test), 2 legs with 2 members each, and the join (pin 4)
    {
      printf 'on:\n  pull_request:\njobs:\n  changes:\n    runs-on: ubuntu-24.04\n  conformance-core:\n    needs: changes\n    steps:\n      - uses: actions/checkout@x\n      - name: core-only\n        run: sh conformance/core.sh\n'
      _sj_hdr conformance-docs-1 "$_sj_dif"; printf '      - uses: actions/checkout@x\n        with:\n          fetch-depth: 0\n      - name: jq available (x)\n        run: jq --version\n      - name: m1\n        run: sh conformance/m1.sh\n      - name: m2\n        run: sh conformance/m2.sh\n'
      _sj_hdr conformance-docs-2 "$_sj_dif"; printf '      - uses: actions/checkout@x\n        with:\n          fetch-depth: 0\n      - name: jq available (x)\n        run: jq --version\n      - name: m3\n        run: sh conformance/m3.sh\n      - name: m4\n        run: sh conformance/m4.sh\n'
      _sj_join_head conformance-docs conformance-docs-1 conformance-docs-2
      printf '      - name: Legs\n        run: sh conformance/ci-gates.sh --shard-join conformance-docs "$LEG_RESULTS"\n'
    } > "$1"
  }
  _sj_cell() {  # <id> <desc> <want-rc> <needle|-> <wf> <join> [<pin>] -> check_shard_join_shape on the fixture, graded on rc and one needle
    if _sjc_o=$(check_shard_join_shape "$5" "$6" "${7:-}" 2>&1); then _sjc_rc=0; else _sjc_rc=$?; fi
    _sjc_ok=1
    [ "$_sjc_rc" = "$3" ] || _sjc_ok=0
    if [ "$4" != "-" ]; then case "$_sjc_o" in *"$4"*) : ;; *) _sjc_ok=0 ;; esac; fi
    if [ "$_sjc_ok" = 1 ]; then echo "selftest PASS: $1 — $2"
    else echo "selftest FAIL: $1 — $2 (rc=$_sjc_rc want $3; needle '$4'; out='$_sjc_o')"; sf=1; fi
  }
  _sj_run() {  # <script> <join> <results> <wf> [<pin>] -> _sjr_rc, _sjr_o of the `--shard-join` run mode
    if _sjr_o=$(sh "$1" --shard-join "$2" "$3" "$4" ${5:+"$5"} 2>&1); then _sjr_rc=0; else _sjr_rc=$?; fi
  }
  _sj_runcell() {  # <id> <desc> <want-rc> <needle|-> <join> <results> <wf> [<script>]
    _sj_run "${8:-$0}" "$5" "$6" "$7"
    _sjr_ok=1
    [ "$_sjr_rc" = "$3" ] || _sjr_ok=0
    if [ "$4" != "-" ]; then case "$_sjr_o" in *"$4"*) : ;; *) _sjr_ok=0 ;; esac; fi
    if [ "$_sjr_ok" = 1 ]; then echo "selftest PASS: $1 — $2"
    else echo "selftest FAIL: $1 — $2 (rc=$_sjr_rc want $3; needle '$4'; out='$_sjr_o')"; sf=1; fi
  }
  _sj_base_st "$d/sj/st.yml"; _sj_base_dc "$d/sj/dc.yml"
  _sj_cell SJ1a "a sound selftests shard workflow (2 legs, trio byte-copied, join with shard-join, --legs, gate-test last) -> OK" 0 - "$d/sj/st.yml" conformance-selftests
  _sj_cell SJ1b "a sound docs shard workflow (2 legs of 2 members, the pin 4 matches) -> OK" 0 - "$d/sj/dc.yml" conformance-docs 4
  # C31 — the leg results, through the run mode
  _sj_runcell SJ2 "all legs success -> OK, and the in-run negative ran" 0 "in-run negative" conformance-selftests "success success" "$d/sj/st.yml"
  _sj_runcell SJ3 "a skipped leg -> RED, naming the leg and the result" 1 "leg conformance-selftests-2 reported 'skipped'" conformance-selftests "success skipped" "$d/sj/st.yml"
  _sj_runcell SJ4 "a failed leg -> RED, naming the leg and the result" 1 "leg conformance-selftests-1 reported 'failure'" conformance-selftests "failure success" "$d/sj/st.yml"
  _sj_runcell SJ5 "a cancelled leg -> RED, naming the leg and the result" 1 "leg conformance-selftests-2 reported 'cancelled'" conformance-selftests "success cancelled" "$d/sj/st.yml"
  _sj_runcell SJ6 "one result for two legs -> RED on the count" 1 "1 results for 2 legs" conformance-selftests "success" "$d/sj/st.yml"
  _sj_runcell SJ6b "three results for two legs -> RED on the count" 1 "3 results for 2 legs" conformance-selftests "success success success" "$d/sj/st.yml"
  _sj_runcell SJ7 "empty results -> RED (an empty LEG_RESULTS adjudicated nothing)" 1 "no leg results" conformance-selftests "" "$d/sj/st.yml"
  # C31 — the structure
  _sj_mutate() {  # <name> <awk-or-sed...> : writes $d/sj/<name>.yml from the base; the first arg after the name selects the tool
    _sjm_n=$1; _sjm_t=$2; shift 2
    if [ "$_sjm_t" = awk ]; then awk "$@" "$d/sj/st.yml" > "$d/sj/$_sjm_n.yml"; else sed "$@" "$d/sj/st.yml" > "$d/sj/$_sjm_n.yml"; fi
    if cmp -s "$d/sj/st.yml" "$d/sj/$_sjm_n.yml"; then echo "selftest FAIL: SJ-mutate $_sjm_n — the mutation did not apply (nothing to mutate)"; sf=1; fi
  }
  _sj_mutate stif awk '{ print } /^      - name: a self-test$/ { print "        if: always()" }'
  _sj_cell SJ10 "a step-level if: in a leg -> RED" 1 "step-level if:" "$d/sj/stif.yml" conformance-selftests
  _sj_mutate stcoe awk '{ print } /^      - name: a self-test$/ { print "        continue-on-error: true" }'
  _sj_cell SJ11 "a step-level continue-on-error in a leg -> RED" 1 "step-level continue-on-error" "$d/sj/stcoe.yml" conformance-selftests
  _sj_mutate jobcoe awk '{ print } /^  conformance-selftests-1:$/ { print "    continue-on-error: true" }'
  _sj_cell SJ12 "a job-level continue-on-error on a leg -> RED (the job would report success)" 1 "job-level continue-on-error" "$d/sj/jobcoe.yml" conformance-selftests
  _sj_mutate shbad awk '{ print } /^      - name: a self-test$/ { print "        shell: bash {0}" }'
  _sj_cell SJ13 "a step shell: bash {0} -> RED (it drops -e)" 1 "custom shell on a step" "$d/sj/shbad.yml" conformance-selftests
  _sj_mutate shbash awk '{ print } /^      - name: a self-test$/ { print "        shell: bash" }'
  _sj_cell SJ13b "a step shell: bash (exact) -> RED (option A: shell is not on the allow-list of step keys at all)" 1 "line shape not in the allow-list" "$d/sj/shbash.yml" conformance-selftests
  _sj_mutate shsh awk '{ print } /^      - name: a self-test$/ { print "        shell: sh" }'
  _sj_cell SJ13c "a step shell: sh (exact) -> RED (option A: shell is not on the allow-list of step keys at all)" 1 "line shape not in the allow-list" "$d/sj/shsh.yml" conformance-selftests
  _sj_mutate defjob awk '{ print } /^  conformance-selftests-1:$/ { print "    defaults:"; print "      run:"; print "        shell: bash {0}" }'
  _sj_cell SJ14 "a job-level defaults: run: shell: bash {0} on a leg -> RED" 1 "custom shell in its job-level defaults" "$d/sj/defjob.yml" conformance-selftests
  _sj_mutate defwf awk 'NR == 1 { print "defaults:"; print "  run:"; print "    shell: bash {0}" } { print }'
  _sj_cell SJ15 "a workflow-level defaults: run: shell: bash {0} -> RED" 1 "workflow-level defaults set a custom shell" "$d/sj/defwf.yml" conformance-selftests
  _sj_mutate ghenv sed 's|^        run: sh conformance/a.sh --selftest$|        run: echo a=1 >> "$GITHUB_ENV"|'
  _sj_cell SJ16a "a GITHUB_ENV write in a leg -> RED" 1 "GITHUB_ENV, BASH_ENV or GITHUB_PATH" "$d/sj/ghenv.yml" conformance-selftests
  _sj_mutate bashenv sed 's|^        run: sh conformance/a.sh --selftest$|        run: export BASH_ENV=/x|'
  _sj_cell SJ16b "a BASH_ENV export in a leg -> RED" 1 "GITHUB_ENV, BASH_ENV or GITHUB_PATH" "$d/sj/bashenv.yml" conformance-selftests
  _sj_mutate ghpath sed 's|^        run: sh conformance/a.sh --selftest$|        run: echo /x >> "$GITHUB_PATH"|'
  _sj_cell SJ16c "a GITHUB_PATH write in a leg -> RED" 1 "GITHUB_ENV, BASH_ENV or GITHUB_PATH" "$d/sj/ghpath.yml" conformance-selftests
  _sj_mutate envjob awk '{ print } /^  conformance-selftests-1:$/ { print "    env:"; print "      BASH_ENV: /x" }'
  _sj_cell SJ18a "a job-level env: BASH_ENV: on a leg -> RED" 1 "BASH_ENV" "$d/sj/envjob.yml" conformance-selftests
  _sj_mutate envstep awk '{ print } /^      - name: a self-test$/ { print "        env:"; print "          ENV: /x" }'
  _sj_cell SJ18b "a step-level env: ENV: on a leg -> RED (bash sources it before every step)" 1 "ENV key" "$d/sj/envstep.yml" conformance-selftests
  _sj_mutate envwf awk 'NR == 1 { print "env:"; print "  BASH_ENV: /x" } { print }'
  _sj_cell SJ18c "a workflow-level env: BASH_ENV: -> RED" 1 "workflow-level env names BASH_ENV" "$d/sj/envwf.yml" conformance-selftests
  _sj_mutate matrix awk '{ print } /^  conformance-selftests-1:$/ { print "    strategy:"; print "      matrix:"; print "        s: [1, 2]" }'
  _sj_cell SJ27 "a matrix on a leg -> RED (legs are static jobs)" 1 "is a matrix" "$d/sj/matrix.yml" conformance-selftests
  _sj_mutate nomark awk '!d && sub(/   # not a required check -> a job-level skip is safe$/, "") { d = 1 } { print }'
  _sj_cell SJ29 "a leg if: without the aggregator marker -> RED" 1 "lacks the marker" "$d/sj/nomark.yml" conformance-selftests
  _sj_mutate trio1 awk '/^  conformance-selftests-2:$/ { l2 = 1 } l2 && /bubblewrap socat$/ { sub(/socat$/, "socats") } { print }'
  _sj_cell SJ19 "leg 2's trio differing from leg 1's by one byte -> RED" 1 "differs from leg conformance-selftests-1" "$d/sj/trio1.yml" conformance-selftests
  _sj_mutate trio0 awk '/^  conformance-selftests-2:$/ { l2 = 1 } l2 && /^      - name: Allow unprivileged user namespaces/ { skip = 1; next } skip && /^      - / { skip = 0 } skip && /^  [a-z]/ { skip = 0 } l2 && skip { next } { print }'
  _sj_cell SJ20 "leg 2 missing a trio step -> RED" 1 "lacks the install trio step 'Allow unprivileged user namespaces" "$d/sj/trio0.yml" conformance-selftests
  _sj_mutate lrstep awk '/^    env:$/ { skipenv = 1; next } skipenv && /^      LEG_RESULTS:/ { next } { skipenv = 0 } { print } /^      - name: Legs$/ { print "        env:"; print "          LEG_RESULTS: ${{ needs.conformance-selftests-1.result }} ${{ needs.conformance-selftests-2.result }}" }'
  _sj_cell SJ21 "LEG_RESULTS at step level instead of job level -> RED" 1 "job-level env" "$d/sj/lrstep.yml" conformance-selftests
  _sj_mutate needsmiss sed '/^      - conformance-selftests-2$/d'
  _sj_cell SJ22 "a leg missing from the join's needs -> RED" 1 "needs: lacks conformance-selftests-2" "$d/sj/needsmiss.yml" conformance-selftests
  _sj_mutate needsextra awk '{ print } /^      - conformance-selftests-2$/ { print "      - cf-other" }'
  _sj_cell SJ23 "a non-leg job in the join's needs besides changes -> RED" 1 "neither changes nor a leg" "$d/sj/needsextra.yml" conformance-selftests
  _sj_mutate needsflow awk '/^    needs:$/ && !done { print "    needs: [changes, conformance-selftests-1, conformance-selftests-2]"; skip = 1; done = 1; next } skip && /^      - / { next } { skip = 0; print }'
  _sj_cell SJ23b "the join's needs as a flow list instead of a block list -> RED" 1 "needs: must be a block list" "$d/sj/needsflow.yml" conformance-selftests
  _sj_mutate names3 sed 's/conformance-selftests-2/conformance-selftests-3/g'
  _sj_cell SJ24 "leg names not 1..n (-1 and -3) -> RED" 1 "must be named conformance-selftests-1..2" "$d/sj/names3.yml" conformance-selftests
  _sj_mutate one awk '/^  conformance-selftests-2:$/ { skip = 1; next } skip && /^  [a-z]/ { skip = 0 } skip { next } /^      - conformance-selftests-2$/ { next } { sub(/ \$\{\{ needs.conformance-selftests-2.result \}\}/, ""); print }'
  _sj_cell SJ25 "a single leg (n = 1) -> RED" 1 "at least 2 are needed" "$d/sj/one.yml" conformance-selftests
  _sj_mutate nostep sed '/^        run: sh conformance\/ci-gates.sh --shard-join conformance-selftests "\$LEG_RESULTS"$/d'
  _sj_cell SJ26 "the shard-join step missing from the join (so no in-run negative runs) -> RED" 1 "that call carries the in-run negative" "$d/sj/nostep.yml" conformance-selftests
  _sj_mutate nocancel sed 's/\${{ !cancelled() && /${{ /'
  _sj_cell SJ28 "a join if: without !cancelled() -> RED" 1 "must carry !cancelled()" "$d/sj/nocancel.yml" conformance-selftests
  # C32 — gate-test attests the legs through the join
  _sj_mutate gtlast awk '{ print } END { print "      - name: tail"; print "        run: echo tail" }'
  _sj_cell SJ30 "a step after gate-test in the join -> RED" 1 "gate-test must be the last step of the join" "$d/sj/gtlast.yml" conformance-selftests
  _sj_mutate gtleg awk '{ print } /^      - name: a self-test$/ { print "        id: gate-test" }'
  _sj_cell SJ31 "id: gate-test inside a leg -> RED" 1 "carries id: gate-test" "$d/sj/gtleg.yml" conformance-selftests
  _sj_base_st "$d/sj/gtfirst.yml" gatefirst
  _sj_cell SJ32 "gate-test before the shard-join step -> RED" 1 "gate-test must be the last step of the join" "$d/sj/gtfirst.yml" conformance-selftests
  # C30 — the docs pin and partition (fixture pin 4)
  _sj_cell SJ40 "the pin one above the member count (a step removed) -> RED" 1 "the pin is 5" "$d/sj/dc.yml" conformance-docs 5
  _sj_cell SJ41 "the pin one below the member count (a step added) -> RED" 1 "the pin is 3" "$d/sj/dc.yml" conformance-docs 3
  awk '{ print } /^      - name: m3$/ { f = 1 } f && /^        run: sh conformance\/m3.sh$/ { print "      - name: m1"; print "        run: sh conformance/m1.sh"; f = 0 }' "$d/sj/dc.yml" > "$d/sj/dcdup.yml"
  _sj_cell SJ42 "a member in both docs legs -> RED (duplicate)" 1 "duplicate member step" "$d/sj/dcdup.yml" conformance-docs 5
  sed 's|^      - name: m4$|      - name: core-only|; s|^        run: sh conformance/m4.sh$|        run: sh conformance/core.sh|' "$d/sj/dc.yml" > "$d/sj/dcforeign.yml"
  _sj_cell SJ43 "a docs member byte-equal to a conformance-core step -> RED (foreign)" 1 "foreign member" "$d/sj/dcforeign.yml" conformance-docs 4
  awk '/^  conformance-docs-2:$/ { l2 = 1 } l2 && /^      - name: m[34]$/ { skip = 1; next } skip && /^        run:/ { skip = 0; next } { print }' "$d/sj/dc.yml" > "$d/sj/dcempty.yml"
  _sj_cell SJ44 "a docs leg holding only the prologue -> RED (empty leg)" 1 "empty leg" "$d/sj/dcempty.yml" conformance-docs 2
  # R-I1: the JOIN is locked like a leg (exact step list; the same masking keys), S-M1/S-M2: quoted keys are normalised, merge keys and aliases banned,
  # S-L1: a leg's run text may not switch errexit off or end in a bare exit 0, S-L2: a comment cannot satisfy the !cancelled() check
  _sj_jstep="        run: sh conformance/ci-gates.sh --shard-join conformance-selftests \"\$LEG_RESULTS\""
  _sj_mutate jcoe awk -v s="$_sj_jstep" '{ print } $0 == s { print "        continue-on-error: true" }'
  _sj_cell SJ50 "a step-level continue-on-error on the join's shard-join step -> RED" 1 "join conformance-selftests carries a step-level continue-on-error" "$d/sj/jcoe.yml" conformance-selftests
  _sj_mutate jjcoe awk '{ print } /^  conformance-selftests:$/ { print "    continue-on-error: true" }'
  _sj_cell SJ51 "a job-level continue-on-error on the join -> RED" 1 "join conformance-selftests carries a job-level continue-on-error" "$d/sj/jjcoe.yml" conformance-selftests
  _sj_mutate jextra awk -v s="$_sj_jstep" '{ print } $0 == s { print "      - name: extra"; print "        run: echo hi" }'
  _sj_cell SJ52 "an extra step between the join's shard-join and --legs steps -> RED (the exact step list)" 1 "step list" "$d/sj/jextra.yml" conformance-selftests
  _sj_mutate jghenv sed 's|^        run: sh conformance/ci-gates.sh --shard-join conformance-selftests "\$LEG_RESULTS"$|        run: echo "LEG_RESULTS=success success" >> "$GITHUB_ENV"|'
  _sj_cell SJ53 "a join step writing LEG_RESULTS to GITHUB_ENV -> RED" 1 "join conformance-selftests names GITHUB_ENV" "$d/sj/jghenv.yml" conformance-selftests
  _sj_mutate qif awk '{ print } /^      - name: a self-test$/ { print "        \"if\": false" }'
  _sj_cell SJ54 "a double-quoted \"if\" on a leg step -> RED (quotes do not escape the lock)" 1 "step-level if:" "$d/sj/qif.yml" conformance-selftests
  _sj_mutate qsif awk -v q="'" '{ print } /^      - name: a self-test$/ { print "        " q "if" q ": false" }'
  _sj_cell SJ55 "a single-quoted 'if' on a leg step -> RED" 1 "step-level if:" "$d/sj/qsif.yml" conformance-selftests
  _sj_mutate qjcoe awk '{ print } /^  conformance-selftests-1:$/ { print "    \"continue-on-error\": true" }'
  _sj_cell SJ56 "a double-quoted job-level \"continue-on-error\" on a leg -> RED" 1 "leg conformance-selftests-1 carries a job-level continue-on-error" "$d/sj/qjcoe.yml" conformance-selftests
  _sj_mutate qlr awk '{ print } /^      - name: Legs$/ { print "        env:"; print "          \"LEG_RESULTS\": success success" }'
  _sj_cell SJ57 "a quoted \"LEG_RESULTS\" step-level env in the join -> RED (counted as a second declaration)" 1 "declared exactly once" "$d/sj/qlr.yml" conformance-selftests
  _sj_mutate mrg awk '{ print } /^      - name: a self-test$/ { print "        <<: *x" }'
  _sj_cell SJ58 "a YAML merge key (<<: *x) on a leg step -> RED" 1 "merge key or alias" "$d/sj/mrg.yml" conformance-selftests
  _sj_mutate alias awk '{ print } /^      - name: a self-test$/ { print "        foo: *x" }'
  _sj_cell SJ59 "a YAML alias value on a leg step -> RED" 1 "merge key or alias" "$d/sj/alias.yml" conformance-selftests
  _sj_mutate jmrg awk '{ print } /^  conformance-selftests:$/ { print "    <<: *x" }'
  _sj_cell SJ59b "a YAML merge key on the join -> RED" 1 "join conformance-selftests uses a YAML merge key or alias" "$d/sj/jmrg.yml" conformance-selftests
  _sj_mutate setpe awk '$0 == "        run: sh conformance/a.sh --selftest" { print "        run: |"; print "          set +e"; print "          sh conformance/a.sh --selftest"; next } { print }'
  _sj_cell SJ62 "a multi-line leg run block with set +e -> RED" 1 "set +e" "$d/sj/setpe.yml" conformance-selftests
  _sj_mutate exit0 awk '$0 == "        run: sh conformance/a.sh --selftest" { print "        run: |"; print "          sh conformance/a.sh --selftest"; print "          exit 0"; next } { print }'
  _sj_cell SJ63 "a multi-line leg run block ending in a bare exit 0 -> RED" 1 "bare exit 0" "$d/sj/exit0.yml" conformance-selftests
  _sj_mutate jenv awk -v s="$_sj_jstep" '$0 == s { print "        env:"; print "          X: 1" } { print }'
  _sj_cell SJ65 "a step-level env: on a join step -> RED" 1 "join conformance-selftests carries a step-level env:" "$d/sj/jenv.yml" conformance-selftests
  _sj_mutate cmtcancel awk '/!cancelled\(\)/ { sub(/!cancelled\(\) && /, ""); print $0 "   # !cancelled()"; next } { print }'
  _sj_cell SJ64 "!cancelled() only inside the join if:'s trailing comment -> RED" 1 "must carry !cancelled()" "$d/sj/cmtcancel.yml" conformance-selftests
  # Option A (owner ruling): an ALLOW-LIST of line shapes replaces pattern-chasing, so a key hidden by an escape (N1), a flow node (N2), an explicit key (N3),
  # a tag or anchor, or a trap/shopt in a run block fails because its SHAPE is not allowed, not because a known spelling matched.
  _sj_mutate qesc awk -v bs='\\' '{ print } /^      - name: a self-test$/ { print "        \"" bs "x69f\": false" }'
  _sj_cell SJ70 "N1a: a double-quoted key with a hex escape for the i of if, on a leg step -> RED, by line shape" 1 "leg conformance-selftests-1 line" "$d/sj/qesc.yml" conformance-selftests
  _sj_mutate qescj awk -v bs='\\' '{ print } /^  conformance-selftests-1:$/ { print "    \"continue-on-erro" bs "x72\": true" }'
  _sj_cell SJ71a "N1b: a hex-escaped job-level continue-on-error key on a leg -> RED, by line shape" 1 "leg conformance-selftests-1 line" "$d/sj/qescj.yml" conformance-selftests
  _sj_mutate qescjj awk -v bs='\\' '{ print } /^  conformance-selftests:$/ { print "    \"continue-on-erro" bs "x72\": true" }'
  _sj_cell SJ71b "N1b: a hex-escaped job-level continue-on-error key on the join -> RED, by line shape" 1 "join conformance-selftests line" "$d/sj/qescjj.yml" conformance-selftests
  _sj_mutate flow awk '/^      - name: a self-test$/ && !done { print "      - { if: false, name: x,"; print "        run: sh conformance/a.sh --selftest"; print "      }"; done = 1 } { print }'
  _sj_cell SJ72 "N2: a multi-line flow-mapping step -> RED, by line shape" 1 "line shape not in the allow-list" "$d/sj/flow.yml" conformance-selftests
  _sj_mutate xkey awk '{ print } /^      - name: a self-test$/ { print "        ? if"; print "        : false" }'
  _sj_cell SJ73a "N3a: an explicit key (? if / : false) on a leg step -> RED, by line shape" 1 "line shape not in the allow-list" "$d/sj/xkey.yml" conformance-selftests
  _sj_mutate xkeyj awk '{ print } /^  conformance-selftests-1:$/ { print "    ? continue-on-error"; print "    : true" }'
  _sj_cell SJ73b "N3b: an explicit job-level key (? continue-on-error / : true) on a leg -> RED, by line shape" 1 "line shape not in the allow-list" "$d/sj/xkeyj.yml" conformance-selftests
  _sj_mutate tagv awk '{ print } /^      - name: a self-test$/ { print "        id: !!str x" }'
  _sj_cell SJ74 "a tagged value line on a leg step -> RED, by line shape" 1 "line shape not in the allow-list" "$d/sj/tagv.yml" conformance-selftests
  _sj_mutate trapx awk '$0 == "        run: sh conformance/a.sh --selftest" { print "        run: |"; print "          trap \047exit 0\047 EXIT"; print "          sh conformance/a.sh --selftest"; next } { print }'
  _sj_cell SJ75 "a trap in a leg run block -> RED" 1 "may not start a command with trap" "$d/sj/trapx.yml" conformance-selftests
  _sj_mutate shoptx awk '$0 == "        run: sh conformance/a.sh --selftest" { print "        run: |"; print "          shopt -u -o errexit"; print "          sh conformance/a.sh --selftest"; next } { print }'
  _sj_cell SJ76 "a shopt in a leg run block -> RED" 1 "may not start a command with trap" "$d/sj/shoptx.yml" conformance-selftests
  _sj_mutate allowok awk '$0 == "        run: sh conformance/a.sh --selftest" { print "        # a comment"; print ""; print "        id: aself   # a trailing comment"; print "        env:"; print "          GH_TOKEN: ${{ github.token }}"; print "        run: |"; print "          set -e"; print "          if: not-a-key"; print "          sh conformance/a.sh --selftest"; print "          exit 1"; next } { print }'
  _sj_cell SJ77 "every allowed shape together (comment, blank, id, env GH_TOKEN, run block with set -e, key-looking content, exit 1) -> OK" 0 - "$d/sj/allowok.yml" conformance-selftests
  # the live ci.yml, when this is a kit tree
  _sj_kr="$(dirname "$0")/.."
  if [ -f "$_sj_kr/.github/workflows/ci.yml" ] && { [ -f "$_sj_kr/docs/ROADMAP-KIT.md" ] || [ -f "$_sj_kr/.github/workflows/golden-path.yml" ]; }; then
    _sj_cell SJ60 "the live ci.yml's conformance-selftests shard is sound (legs, join, trio, gate-test)" 0 - "$_sj_kr/.github/workflows/ci.yml" conformance-selftests
    _sj_cell SJ61 "the live ci.yml's conformance-docs shard is sound (legs, join, the pin $_SJ_DOCS_PIN, no foreign member)" 0 - "$_sj_kr/.github/workflows/ci.yml" conformance-docs
  else echo "selftest SKIP: SJ60/SJ61 — not a kit tree"; fi
  # M1-M8: sed-edited copies of THIS script, run through the run mode on the fixtures above; the cell's own expectation must FAIL under the mutation.
  _sj_mutcell() {  # <id> <desc> <sed-expr> <cell: join|results|wf|want-rc|needle>
    sed "$3" "$0" > "$d/sj/$1.sh"
    if cmp -s "$0" "$d/sj/$1.sh"; then echo "selftest FAIL: $1 — the mutant equals the original (nothing to mutate; the line is not pinned)"; sf=1; return 0; fi
    _sjm_join=${4%%|*}; _sjm_r=${4#*|}; _sjm_res=${_sjm_r%%|*}; _sjm_r=${_sjm_r#*|}; _sjm_wf=${_sjm_r%%|*}; _sjm_r=${_sjm_r#*|}; _sjm_want=${_sjm_r%%|*}; _sjm_nd=${_sjm_r#*|}
    _sjm_pin=""
    case "$_sjm_join" in *@*) _sjm_pin=${_sjm_join#*@}; _sjm_join=${_sjm_join%@*} ;; esac   # a docs join may carry its pin as join@N
    # the positive control: the UNMUTATED script must satisfy the cell's expectation, or "the mutant fails it" proves nothing (rc 127 would also fail it)
    _sj_run "$0" "$_sjm_join" "$_sjm_res" "$_sjm_wf" "$_sjm_pin"
    _sjm_ok=1
    [ "$_sjr_rc" = "$_sjm_want" ] || _sjm_ok=0
    case "$_sjr_o" in *"$_sjm_nd"*) : ;; *) _sjm_ok=0 ;; esac
    if [ "$_sjm_ok" != 1 ]; then echo "selftest FAIL: $1 — the unmutated script does not satisfy the cell (rc=$_sjr_rc want $_sjm_want; needle '$_sjm_nd'): $_sjr_o"; sf=1; return 0; fi
    _sj_run "$d/sj/$1.sh" "$_sjm_join" "$_sjm_res" "$_sjm_wf" "$_sjm_pin"
    _sjm_ok=1
    [ "$_sjr_rc" = "$_sjm_want" ] || _sjm_ok=0
    case "$_sjr_o" in *"$_sjm_nd"*) : ;; *) _sjm_ok=0 ;; esac
    if [ "$_sjm_ok" = 1 ]; then echo "selftest FAIL: $1 — $2 was NOT caught (the run still gave rc $_sjr_rc naming '$_sjm_nd')"; sf=1
    else echo "selftest PASS: $1 — $2 -> the cell's expectation fails under the mutant (rc=$_sjr_rc), so the cell has teeth"; fi
  }
  _sj_mutcell SJM1 "accepting a skipped leg" 's/if \[ "\$1" != success \]; then echo "FAIL: shard-join — leg/if [ "$1" != success ] \&\& [ "$1" != skipped ]; then echo "FAIL: shard-join — leg/' "conformance-selftests|success skipped|$d/sj/st.yml|1|leg conformance-selftests-2 reported 'skipped'"
  _sj_mutcell SJM2 "dropping the results-count check" 's/if \[ "\$_sr_nr" -ne "\$_sr_nl" \]; then/if false; then/' "conformance-selftests|success success success|$d/sj/st.yml|1|3 results for 2 legs"
  _sj_mutcell SJM3 "skipping the step-level if: test" "s/grep -Eq '^(        |      - )if\[\[:space:\]\]\*:'/grep -Eq '^(        |      - )xif[[:space:]]*:'/" "conformance-selftests|success success|$d/sj/stif.yml|1|step-level if:"
  _sj_mutcell SJM4 "skipping the job-level continue-on-error test" "s/grep -Eq '^    continue-on-error\[\[:space:\]\]\*:'/grep -Eq '^    xcontinue-on-error[[:space:]]*:'/" "conformance-selftests|success success|$d/sj/jobcoe.yml|1|job-level continue-on-error"
  _sj_mutcell SJM5 "skipping the job-level defaults: test" 's/for _sjl_sh in \$(_sj_shells "\$2" D); do/for _sjl_sh in; do/' "conformance-selftests|success success|$d/sj/defjob.yml|1|custom shell in its job-level defaults"
  _sj_mutcell SJM6 "skipping the trio byte compare" 's/elif \[ "\$_sj_ki" != "\$_sj_k1" \]; then/elif false; then/' "conformance-selftests|success success|$d/sj/trio1.yml|1|differs from leg conformance-selftests-1"
  _sj_mutcell SJM8 "deleting the in-run negative" '/^  if _sj_results "\$_sr_ls" "\$_sr_neg" >\/dev\/null; then$/,/^  echo "in-run negative/d' "conformance-selftests|success success|$d/sj/st.yml|0|in-run negative"
  _sj_base_dc "$d/sj/dcm.yml"
  _sj_mutcell SJM7 "making the docs pin a >= test" 's/\[ "\$_sj_tot" -eq "\$_sj_pin" \]/[ "$_sj_tot" -ge "$_sj_pin" ]/' "conformance-docs@3|success success|$d/sj/dcm.yml|1|the pin is 3"
  # the round's new locks (R-I1, S-M1/S-M2, S-L1, S-L2): each mutant disables one and must make its named fixture's expectation fail
  _sj_mutcell SJM9 "skipping the join's exact step list" 's/" = ok ] || _sj_fail/" = ok ] || :/' "conformance-selftests|success success|$d/sj/jextra.yml|1|step list"
  _sj_mutcell SJM10 "replacing the quoted-key normaliser with cat" 's/^_sj_nk() {.*/_sj_nk() { cat; }/' "conformance-selftests|success success|$d/sj/qif.yml|1|step-level if:"
  _sj_mutcell SJM11 "skipping the set +e test" 's/(run:\[\[:space:\]\]\*)?set(/(run:[[:space:]]*)?xset(/' "conformance-selftests|success success|$d/sj/setpe.yml|1|switches errexit off"
  _sj_mutcell SJM12 "not running the leg locks on the join" 's/^  _sj_locks "join /  : "join /' "conformance-selftests|success success|$d/sj/jcoe.yml|1|join conformance-selftests carries a step-level continue-on-error"
  _sj_mutcell SJM13 "letting a trailing comment satisfy the !cancelled() check" 's/ | sed .s\/\[\[:space:\]\]#\.\*\/\/. | grep -qF/ | grep -qF/' "conformance-selftests|success success|$d/sj/cmtcancel.yml|1|must carry !cancelled()"
  # option A: each mutant disables one half of the allow-list (the shape test, the block-content ban) and the fixture that half owns must stop failing
  _sj_mutcell SJM14 "disabling the allow-list on the N1 shape" 's/^\( *\)_sj_allow "/\1: "/' "conformance-selftests|success success|$d/sj/qesc.yml|1|leg conformance-selftests-1 line"
  _sj_mutcell SJM15 "disabling the allow-list on the N2 shape" 's/^\( *\)_sj_allow "/\1: "/' "conformance-selftests|success success|$d/sj/flow.yml|1|line shape not in the allow-list"
  _sj_mutcell SJM16 "disabling the allow-list on the N3 shape" 's/^\( *\)_sj_allow "/\1: "/' "conformance-selftests|success success|$d/sj/xkey.yml|1|line shape not in the allow-list"
  _sj_mutcell SJM17 "disabling the block-content ban on the trap shape" 's/if (t ~ \/^trap/if (0 \&\& t ~ \/^trap/' "conformance-selftests|success success|$d/sj/trapx.yml|1|may not start a command with trap"
  _sj_mutcell SJM18 "disabling the block-content ban on the shopt shape" 's/|| t ~ \/^shopt/|| 0 \&\& t ~ \/^shopt/' "conformance-selftests|success success|$d/sj/shoptx.yml|1|may not start a command with trap"
  _st_mark SJ

  # ── SWAS-447 — the line-break ban (LB): check_line_breaks, check_line_breaks_tree, and their two call sites (own_tree_run, shard_join_run) ──
  # Every fixture is built here with printf / awk octal escapes inside $d/lb: no banned byte is ever typed into this file or committed. LB0 pins the positive
  # control first (its bytes are asserted before it is graded), so a printf that failed to write the high bytes cannot make the near-miss cell vacuous.
  mkdir -p "$d/lb"
  _lb_cell() {  # <id> <desc> <want-rc> <file> <needle>... -> check_line_breaks on the fixture, graded on rc and on every needle
    _lbc_id=$1; _lbc_desc=$2; _lbc_want=$3; _lbc_f=$4; shift 4
    if _lbc_o=$(check_line_breaks "$_lbc_f" 2>&1); then _lbc_rc=0; else _lbc_rc=$?; fi
    _lbc_ok=1
    [ "$_lbc_rc" = "$_lbc_want" ] || _lbc_ok=0
    for _lbc_n in "$@"; do case "$_lbc_o" in *"$_lbc_n"*) : ;; *) _lbc_ok=0 ;; esac; done
    if [ "$_lbc_ok" = 1 ]; then echo "selftest PASS: $_lbc_id — $_lbc_desc"
    else echo "selftest FAIL: $_lbc_id — $_lbc_desc (rc=$_lbc_rc want $_lbc_want; needles '$*'; out='$_lbc_o')"; sf=1; fi
  }
  _lb_tcell() {  # <id> <desc> <want-rc> <root> <needle>... -> check_line_breaks_tree on the fixture root, graded on rc and on every needle
    _lbt_id=$1; _lbt_desc=$2; _lbt_want=$3; _lbt_root=$4; shift 4
    if _lbt_o=$(check_line_breaks_tree "$_lbt_root" 2>&1); then _lbt_rc=0; else _lbt_rc=$?; fi
    _lbt_ok=1
    [ "$_lbt_rc" = "$_lbt_want" ] || _lbt_ok=0
    for _lbt_n in "$@"; do case "$_lbt_o" in *"$_lbt_n"*) : ;; *) _lbt_ok=0 ;; esac; done
    if [ "$_lbt_ok" = 1 ]; then echo "selftest PASS: $_lbt_id — $_lbt_desc"
    else echo "selftest FAIL: $_lbt_id — $_lbt_desc (rc=$_lbt_rc want $_lbt_want; needles '$*'; out='$_lbt_o')"; sf=1; fi
  }
  # LB0: the positive control and the near-miss guard. TAB, an em dash, NBSP and e-acute share lead bytes with banned sequences and must pass.
  printf 'name: x\n\tk: v\n# em\342\200\224dash nbsp\302\240 e\303\251\n' > "$d/lb/ok.yml"
  _lb_len=$(wc -c < "$d/lb/ok.yml" | tr -d ' ')
  _lb_hx=$(od -An -tx1 "$d/lb/ok.yml" | tr -d ' \n')
  case "$_lb_hx" in *e28094*c2a0*c3a9*) _lb_seq=1 ;; *) _lb_seq=0 ;; esac
  if [ "$_lb_len" = 37 ] && [ "$_lb_seq" = 1 ]; then _lb_cell LB0 "a clean file with TAB, an em dash, NBSP and e-acute passes (the fixture's 37 bytes and its three multibyte sequences were asserted first)" 0 "$d/lb/ok.yml"
  else echo "selftest FAIL: LB0 — the fixture is not what the cell assumes (length $_lb_len want 37; multibyte sequences present: $_lb_seq): a printf that dropped the high bytes would make the near-miss cell vacuous"; sf=1; fi
  printf 'a: 1\n# lead-byte neighbours: U+2027 \342\200\247 and U+202A \342\200\252 and U+00A0 \302\240 and U+00A1 \302\241\n' > "$d/lb/near.yml"
  _lb_cell LB0b "the neighbours of NEL, LS and PS (U+2027, U+202A, c2 a0, c2 a1) are not banned" 0 "$d/lb/near.yml"
  printf 'a: 1\nb: 2\nid: y\015        if: false\nc: 3\n' > "$d/lb/cr.yml"
  _lb_cell LB1 "a lone CR with a hidden key behind it, on line 3 -> RED, naming the line and CR" 1 "$d/lb/cr.yml" ":3:" "CR (0d)" "(SWAS-447)"
  printf 'run: x\015\nname: y\015\n' > "$d/lb/crlf.yml"
  _lb_cell LB2 "CRLF line endings -> RED (a CR is banned wherever it sits), naming both lines" 1 "$d/lb/crlf.yml" ":1:" ":2:" "CR (0d)"
  printf 'a: x\302\205y\n' > "$d/lb/nel.yml"
  _lb_cell LB3 "NEL (U+0085) -> RED" 1 "$d/lb/nel.yml" ":1:" "NEL (c2 85)"
  printf 'a: x\342\200\250y\n' > "$d/lb/ls.yml"
  _lb_cell LB4 "LS (U+2028) -> RED" 1 "$d/lb/ls.yml" ":1:" "LS (e2 80 a8)"
  printf 'a: x\342\200\251y\n' > "$d/lb/ps.yml"
  _lb_cell LB5 "PS (U+2029) -> RED" 1 "$d/lb/ps.yml" ":1:" "PS (e2 80 a9)"
  printf 'a: x\013y\n' > "$d/lb/vt.yml"
  _lb_cell LB6 "VT -> RED" 1 "$d/lb/vt.yml" ":1:" "VT (0b)"
  printf 'a: x\014y\n' > "$d/lb/ff.yml"
  _lb_cell LB7 "FF -> RED" 1 "$d/lb/ff.yml" ":1:" "FF (0c)"
  printf 'a: 1\nb: x\036y\nc: 2\nd: x\177y\n' > "$d/lb/rsdel.yml"
  _lb_cell LB8 "RS on line 2 and DEL on line 4 -> RED, naming both lines" 1 "$d/lb/rsdel.yml" ":2:" "C0 control (1e)" ":4:" "DEL (7f)"
  printf 'a: x\302\237y\n' > "$d/lb/c1.yml"
  _lb_cell LB9 "a C1 control (c2 9f) -> RED" 1 "$d/lb/c1.yml" ":1:" "C1 control (c2 9f)"
  printf 'a: 1\000b\n' > "$d/lb/nul.yml"
  _lb_cell LB10 "NUL -> RED, named by file" 1 "$d/lb/nul.yml" "NUL (00)"
  # LB11: the tree walk, one fixture root grown a file at a time
  _lb_r="$d/lb/t1"; mkdir -p "$_lb_r/.github/workflows" "$_lb_r/profiles/x"
  printf 'on: push\n' > "$_lb_r/.github/workflows/ci.yml"
  printf 'a: 1\n' > "$_lb_r/profiles/x/ci.yml"
  _lb_tcell LB11a "a clean root: ci.yml plus one template -> OK, reading 2 files" 0 "$_lb_r" "2 file(s) read under"
  printf 'a: x\342\200\250y\n' > "$_lb_r/profiles/x/ci.yml"
  _lb_tcell LB11b "LS in profiles/x/ci.yml -> RED, naming the template" 1 "$_lb_r" "profiles/x/ci.yml:1:" "LS (e2 80 a8)"
  printf 'a: 1\n' > "$_lb_r/profiles/x/ci.yml"
  printf 'a: 1\015b: 2\n' > "$_lb_r/.github/workflows/b.yaml"
  _lb_tcell LB11c "CR in .github/workflows/b.yaml -> RED, naming the .yaml workflow" 1 "$_lb_r" ".github/workflows/b.yaml:1:" "CR (0d)"
  rm -f "$_lb_r/.github/workflows/b.yaml"
  printf 'a: x\342\200\251y\n' > "$_lb_r/profiles/x/ci.gitlab-ci.yml"
  _lb_tcell LB11d "PS in a GitLab template (profiles/x/ci.gitlab-ci.yml) -> RED" 1 "$_lb_r" "profiles/x/ci.gitlab-ci.yml:1:" "PS (e2 80 a9)"
  rm -f "$_lb_r/profiles/x/ci.gitlab-ci.yml"
  printf 'a: x\302\205y\n' > "$_lb_r/.gitlab-ci.yml"
  _lb_tcell LB11e "NEL in a root .gitlab-ci.yml -> RED" 1 "$_lb_r" ".gitlab-ci.yml:1:" "NEL (c2 85)"
  printf 'a: 1\000b\n' > "$_lb_r/.gitlab-ci.yml"
  _lb_tcell LB11f "NUL in a root .gitlab-ci.yml -> RED, named by file" 1 "$_lb_r" "NUL (00)"
  printf 'a: 1\015b: 2\n' > "$_lb_r/.github/workflows/.hidden.yml"
  _lb_tcell LB11g "CR in a dot-named workflow (.github/workflows/.hidden.yml) -> RED (a plain * glob skips dot files)" 1 "$_lb_r" ".github/workflows/.hidden.yml:1:" "CR (0d)"
  rm -f "$_lb_r/.github/workflows/.hidden.yml" "$_lb_r/.gitlab-ci.yml"
  _lb_tcell LB11h "the same root with no dot-named file and no root GitLab file -> OK, the dot globs matching nothing are harmless" 0 "$_lb_r" "2 file(s) read under"
  # F1: the scan must not read as clean when it did not run (a broken awk, an unreadable file)
  mkdir -p "$d/lb/stub"; printf '#!/bin/sh\nexit 2\n' > "$d/lb/stub/awk"; chmod +x "$d/lb/stub/awk"
  if _lbs_o=$(PATH="$d/lb/stub:$PATH"; check_line_breaks "$d/lb/ok.yml" 2>&1); then _lbs_rc=0; else _lbs_rc=$?; fi
  case "$_lbs_o" in *"the line-break scan did not run (awk rc 2)"*) _lbs_n=1 ;; *) _lbs_n=0 ;; esac
  if [ "$_lbs_rc" = 1 ] && [ "$_lbs_n" = 1 ]; then echo "selftest PASS: LB15 — an awk stub that exits 2 -> RED naming that the scan did not run (a clean file is not read as clean)"
  else echo "selftest FAIL: LB15 — rc=$_lbs_rc, out='$_lbs_o'"; sf=1; fi
  _lb_cell LB15b "an unreadable (absent) file -> RED as a scan that did not run, not as NUL" 1 "$d/lb/absent.yml" "the line-break scan did not run"
  mkdir -p "$d/lb/t2/profiles/x"; printf 'a: 1\n' > "$d/lb/t2/profiles/x/ci.yml"
  _lb_tcell LB12 "a root with a template but no workflow file -> RED on liveness (a glob that matched nothing must not pass)" 1 "$d/lb/t2" "line-break liveness"
  # LB13/LB14: the two call sites, through the run modes of a COPY-free run of this script. Graded by the needle, not by rc (a fixture tree is red for other reasons).
  _lb_ndl="inside a line: a YAML parser reads a line break here"
  _lb_run() {  # <script> <kind: tree|own|join> <root-or-workflow> -> _lbr_o, the run mode's output
    case "$2" in
      tree) _lbr_o=$(sh "$1" --line-breaks "$3" 2>&1) || : ;;
      own) _lbr_o=$(sh "$1" --own-tree "$3" 2>&1) || : ;;
      join) _lbr_o=$(sh "$1" --shard-join conformance-selftests "success success" "$3" 2>&1) || : ;;
    esac
  }
  _lb_cellrun() {  # <id> <desc> <kind> <root-or-wf> <want: has|lacks> -> the needle must be present (has) or absent (lacks) in the run mode's output
    _lb_run "$0" "$3" "$4"
    case "$_lbr_o" in *"$_lb_ndl"*) _lbn_has=1 ;; *) _lbn_has=0 ;; esac
    if { [ "$5" = has ] && [ "$_lbn_has" = 1 ]; } || { [ "$5" = lacks ] && [ "$_lbn_has" = 0 ]; }; then echo "selftest PASS: $1 — $2"
    else echo "selftest FAIL: $1 — $2 (wanted the line-break needle $5; out='$_lbr_o')"; sf=1; fi
  }
  _lb_k="$d/lb/k"; mkdir -p "$_lb_k/.github/workflows"
  printf 'on: push\n' > "$_lb_k/.github/workflows/ci.yml"
  printf 'name: g\njobs:\n  a:\n    steps:\n      - run: x\015        if: false\n' > "$_lb_k/.github/workflows/golden-path.yml"
  _lb_cellrun LB13 "--own-tree on a kit tree whose golden-path.yml hides a key behind a CR -> the SWAS-447 line-break line appears (no other path emits it)" own "$_lb_k" has
  printf 'name: g\njobs:\n  a:\n    steps:\n      - run: x\n' > "$_lb_k/.github/workflows/golden-path.yml"
  _lb_cellrun LB13b "the same kit tree with a clean golden-path.yml -> no line-break line (the needle is not emitted unconditionally)" own "$_lb_k" lacks
  _lb_cellrun LB13c "--line-breaks <clean root> -> no line-break line (the read-only mode runs the same walk)" tree "$_lb_k" lacks
  printf 'name: g\n\tx: 1\015y: 2\n' > "$_lb_k/.github/workflows/golden-path.yml"
  _lb_cellrun LB13d "--line-breaks <root> with a CR in golden-path.yml -> the SWAS-447 line-break line appears" tree "$_lb_k" has
  awk '$0 == "        run: sh conformance/a.sh --selftest" { print $0 "\015        if: false"; next } { print }' "$d/sj/st.yml" > "$d/lb/st-cr.yml"
  _lb_cellrun LB14 "--shard-join on a workflow whose leg line hides if: false behind a CR -> the line-break line, before any allow-list verdict" join "$d/lb/st-cr.yml" has
  case "$_lbr_o" in *"allow-list"*) echo "selftest FAIL: LB14b — the join reached the allow-list judge on a file with a hidden break (the ban must run first)"; sf=1 ;; *) echo "selftest PASS: LB14b — the join stopped at the ban, before the allow-list judge" ;; esac
  _lb_cellrun LB14c "--shard-join on the clean selftests workflow -> no line-break line" join "$d/sj/st.yml" lacks
  # LBr: the real kit tree is clean, and the walk is live (exactly the judged set; the count moves only with a deliberate template add or remove)
  if [ -f "$_agg_kr/.github/workflows/ci.yml" ] && [ -f "$_agg_kr/conformance/ci-classify-changes.sh" ] && { [ -f "$_agg_kr/docs/ROADMAP-KIT.md" ] || [ -f "$_agg_kr/.github/workflows/golden-path.yml" ]; }; then
    if check_line_breaks_tree "$_agg_kr" > "$d/lb/lbr.out" 2>&1; then _lbr_rc=0; else _lbr_rc=$?; fi
    if [ "$_lbr_rc" = 0 ] && [ "$_lb_files" = 25 ]; then echo "selftest PASS: LBr — the real kit tree holds no banned byte, and the walk read exactly the 25 judged files"
    else echo "selftest FAIL: LBr — the real kit tree: rc=$_lbr_rc, $_lb_files file(s) read (want rc 0 and exactly 25; a template add or remove moves the count by a deliberate edit): $(cat "$d/lb/lbr.out")"; sf=1; fi
  else echo "selftest SKIP: LBr — not a kit tree"; fi
  # the mutants: a sed-edited COPY of this script runs the cell's fixture; the original must show the needle (the positive control) and the mutant must not.
  # A sed that matches nothing is "unbound" and fails loud: the pinned line moved, and a mutant equal to the original proves nothing.
  _lb_mut() {  # <id> <desc> <sed-expr> <kind> <root-or-wf> <liveness-line the mutant run must still print>
    sed "$3" "$0" > "$d/lb/$1.sh"
    if cmp -s "$0" "$d/lb/$1.sh"; then echo "selftest FAIL: $1 — unbound: the sed matched nothing (the pinned line moved or was renamed), so the mutant equals the original"; sf=1; return 0; fi
    _lb_run "$0" "$4" "$5"
    case "$_lbr_o" in *"$_lb_ndl"*) : ;; *) echo "selftest FAIL: $1 — the unmutated script does not show the line-break needle on this fixture (out='$_lbr_o')"; sf=1; return 0 ;; esac
    _lb_run "$d/lb/$1.sh" "$4" "$5"
    case "$_lbr_o" in
      *"$_lb_ndl"*) echo "selftest FAIL: $1 — $2 was NOT caught (the mutant still names the line-break needle)"; sf=1 ;;
      *"$6"*) echo "selftest PASS: $1 — $2 -> the needle is gone under the mutant and the run went on to its liveness line '$6', so the cell has teeth" ;;
      *) echo "selftest FAIL: $1 — the mutant run died early: the needle is gone but the liveness line '$6' is absent too (out='$_lbr_o')"; sf=1 ;;
    esac
  }
  mkdir -p "$d/lb/m1/.github/workflows"
  cp "$d/lb/cr.yml" "$d/lb/m1/.github/workflows/a.yml"; cp "$d/lb/crlf.yml" "$d/lb/m1/.github/workflows/b.yml"
  _lb_mut LBm1 "dropping the CR alternative from the ban (LB1, LB2)" 's/scan("\\\\015", "C0")/scan("\\\\377", "C0")/' tree "$d/lb/m1" "file(s) read under"
  _lb_mut LBm2 "deleting the own_tree_run call (LB13)" '/^    check_line_breaks_tree "\$_ot_root" || _ot_rc=1/d' own "$_lb_k" "RP liveness"
  _lb_mut LBm3 "deleting the shard_join_run call (LB14)" '/^  check_line_breaks "\$_sr_wf" || return 1/d' join "$d/lb/st-cr.yml" "in-run negative"
  _st_mark LB
  _st_end

  if [ "$sf" -eq 0 ]; then echo "OK: ci-gates selftest"; exit 0; else echo "FAIL: ci-gates selftest"; exit 1; fi
}

# Selftest-only verdict writer, moved here from above selftest() (SWAS-363, security seat): it writes sf and _te_ok, so before the marker the non-vacuity
# flip (var=1 -> var=0) would have left every cell through it printing FAIL without being able to fail the run. Functions resolve at call time.
_tt_expect() {  # <leg> <clone> <want-rc> <needle|-> <what> -> runs the SHIPPED body ($_tt_bodyf) in <clone>, in the mode $_tt_mode (UNSET = the variable absent)
  if [ "${_tt_mode+set}" = set ]; then
    if _te_out=$(cd "$2" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$d" TRUNK_TAG_WAITS="0 0 0" TRUNK_TAG_REMOTE="$_tt_mode" sh -e "$_tt_bodyf" 2>&1); then _te_rc=0; else _te_rc=$?; fi
  else
    if _te_out=$(cd "$2" && env -u TRUNK_TAG_REMOTE GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$d" TRUNK_TAG_WAITS="0 0 0" sh -e "$_tt_bodyf" 2>&1); then _te_rc=0; else _te_rc=$?; fi
  fi
  _te_ok=1
  [ "$_te_rc" = "$3" ] || _te_ok=0
  if [ "$4" != "-" ]; then case "$_te_out" in *"$4"*) : ;; *) _te_ok=0 ;; esac; fi
  if [ "$_te_ok" = 1 ]; then echo "selftest PASS: $1 — $5"
  else echo "selftest FAIL: $1 — $5 (rc=$_te_rc want $3; needle '$4'; out='$_te_out')"; sf=1; fi
}

# --- SWAS-363: the selftest fails closed ------------------------------------------------------------------------------
# The sentinel is test machinery and sits here, after selftest(), in the oracle region the non-vacuity harness copies unchanged (shell functions resolve at
# call time), so its accumulator flip measures the cells and not the sentinel: a flipped trap beside a flipped end marker would otherwise launder every red to rc 0.
# The selftest used to end with one verdict line (OK: ... exit 0) and nothing checked that the run reached it: a lock helper that aborted
# mid-run (an awk program using one of its own builtin names as a variable) left every later leg unrun and the exit green. Now the EXIT trap forces
# exit 1 unless _st_end was reached, and _st_end fails a run in which any lock family in _ST_SECTIONS was not marked exactly once.
# Ceiling: a leg that goes vacuous INSIDE a section that still reaches its mark is not seen here; its own positive control and mutant are the only defence.
_st_begin() {  # first statement of selftest(): state reset with no conditions (an inherited _st_done=1 must not survive), then the traps
  d=$(mktemp -d)
  _st_done=0 _st_seen='' _st_last=''
  _ST_SECTIONS='SEAMS OT DQ RP KIT AGG LS BP TT TF ST TB SJ LB'
  trap '_st_rc=$?; rm -rf "$d"; if [ "$_st_done" != 1 ]; then echo "FAIL: ci-gates selftest ended before its end marker (last section: ${_st_last:-none}, rc $_st_rc)" >&2; exit 1; fi; exit "$_st_rc"' EXIT
  trap 'exit 130' INT TERM
}
_st_mark() { _st_seen="$_st_seen $1"; _st_last=$1; }  # a top-level call at the end of each lock family; never in a pipeline or a subshell, where it would be lost
_st_check() {  # <list> <seen> -> rc 0 when every listed id was seen exactly once and nothing else was; names each break
  _sc_bad=0
  for _sc_id in $1; do
    _sc_n=0
    for _sc_s in $2; do
      if [ "$_sc_s" = "$_sc_id" ]; then _sc_n=$((_sc_n + 1)); fi
    done
    if [ "$_sc_n" -eq 0 ]; then echo "section $_sc_id was never reached (a lock family cut short, or its mark is gone)"; _sc_bad=1
    elif [ "$_sc_n" -gt 1 ]; then echo "section $_sc_id was marked $_sc_n times (once is the rule)"; _sc_bad=1; fi
  done
  for _sc_s in $2; do
    case " $1 " in
      *" $_sc_s "*) : ;;
      *) echo "section $_sc_s was marked but is not in _ST_SECTIONS"; _sc_bad=1 ;;
    esac
  done
  [ "$_sc_bad" = 0 ]
}
_st_end() {  # [--no-trap-check] last act before the verdict line: grade the ledger and the EXIT trap, then set the end marker so the verdict line (through sf) decides the exit
  if _st_o=$(_st_check "$_ST_SECTIONS" "$_st_seen"); then
    echo "selftest PASS: ST0 — the run reached its end marker with every section in _ST_SECTIONS marked exactly once"
  else
    printf '%s\n' "$_st_o" | while IFS= read -r _st_l; do echo "selftest FAIL: ST — $_st_l"; done
    sf=1
  fi
  if [ "${1:-}" != --no-trap-check ]; then
    # the shell's own listing of its traps, written from the current shell (no subshell): the sentinel must still be the EXIT trap
    trap > "$d/trap.out" 2>/dev/null || :
    if grep -F _st_done "$d/trap.out" 2>/dev/null | grep -Eq '[ ](EXIT|0)$'; then
      echo "selftest PASS: ST8 — the EXIT trap still names _st_done at the end marker"
    else
      echo "selftest FAIL: ST — the EXIT trap was replaced (it no longer names _st_done)"; sf=1
    fi
  fi
  _st_done=1
}
check_st_marks() {  # <ci-gates.sh> -> rc 0 when every _ST_SECTIONS id appears as exactly one plain top-level mark line in selftest(); names each break
  _cm_list=$(sed -n "s/^  _ST_SECTIONS='\(.*\)'\$/\1/p" "$1" | head -n 1)
  if [ -z "$_cm_list" ]; then echo "no _ST_SECTIONS list found in $1"; return 1; fi
  _cm_marks=$(awk '
    /^selftest\(\) \{/ { ins = 1; next }
    ins && /^\}/ { ins = 0 }
    ins && /^[ \t]*#/ { next }
    ins && /(^|[^A-Za-z0-9_])_st_mark([^A-Za-z0-9_]|$)/ {
      if ($0 ~ /^  _st_mark [A-Z0-9]+$/) print "M " $2
      else print "B " $0
    }' "$1")
  _cm_bad=0
  for _cm_id in $_cm_list; do
    _cm_n=$(printf '%s\n' "$_cm_marks" | grep -c "^M $_cm_id\$" || :)
    if [ "$_cm_n" != 1 ]; then echo "section $_cm_id has $_cm_n plain top-level mark lines in selftest(), want exactly 1"; _cm_bad=1; fi
  done
  _cm_extra=$(printf '%s\n' "$_cm_marks" | grep '^B ' || :)
  if [ -n "$_cm_extra" ]; then echo "a mark call that is not a plain top-level line (a pipeline, a subshell, an indented or trailing form would lose it): $_cm_extra"; _cm_bad=1; fi
  for _cm_m in $(printf '%s\n' "$_cm_marks" | sed -n 's/^M //p'); do
    case " $_cm_list " in
      *" $_cm_m "*) : ;;
      *) echo "a mark for $_cm_m is not in _ST_SECTIONS"; _cm_bad=1 ;;
    esac
  done
  # the end marker is set in exactly one place (inside _st_end), and _st_end is called exactly once, at top level, right before the verdict line
  _cm_e=$(awk -v q="'" '
    BEGIN { sq = q "[^" q "]*" q }
    /^[ \t]*#/ { next }
    { l = $0; gsub(sq, " ", l); gsub(/"[^"]*"/, " ", l); sub(/(^|[ \t])#.*$/, " ", l) }
    want && !/^[ \t]*$/ { if ($0 !~ /^  if \[ "\$sf" -eq 0 \]; then echo "OK: ci-gates selftest"/) bad = 1; want = 0 }
    /^_st_end\(\) \{/ { inend = 1 }
    inend && /^\}/ { inend = 0 }
    l ~ /_st_done[ \t]*=[ \t]*1/ { tot++; if (inend) inn++ }
    $0 == "  _st_end" { calls++; want = 1 }
    END { print tot + 0, inn + 0, calls + 0, bad + 0 }' "$1")
  set -- "$1" $_cm_e
  if [ "$2" != 1 ] || [ "$3" != 1 ]; then echo "the end marker must be set by exactly one assignment, inside _st_end() (found $2 in the file, $3 inside _st_end)"; _cm_bad=1; fi
  if [ "$4" != 1 ]; then echo "the selftest must call _st_end exactly once as a plain top-level line (found $4)"; _cm_bad=1; fi
  if [ "$5" != 0 ]; then echo "the _st_end call must be immediately before the verdict line"; _cm_bad=1; fi
  [ "$_cm_bad" = 0 ]
}
check_one_exit_trap() {  # <ci-gates.sh> -> rc 0 when exactly one trap command in the WHOLE file names EXIT (any case) or 0 as a word of its own command (a second would silently replace the sentinel)
  _ce_n=$(awk -v q="'" '
    BEGIN { cmd = "tra" "p"; sq = q "[^" q "]*" q }
    /^[ \t]*#/ { next }
    {
      l = $0
      gsub(sq, " ", l); gsub(/"[^"]*"/, " ", l); sub(/(^|[ \t])#.*$/, " ", l); gsub(/[()]/, " ", l)
      ns = split(l, seg, /[;&|]/)
      for (s = 1; s <= ns; s++) {
        n = split(seg[s], w, /[ \t]+/); at = 0
        for (i = 1; i <= n; i++) if (w[i] == cmd) at = i
        if (at) for (i = at + 1; i <= n; i++) if (toupper(w[i]) == "EXIT" || w[i] == "0") { c++; break }
      }
    }
    END { print c + 0 }' "$1")
  if [ "$_ce_n" != 1 ]; then echo "the file holds $_ce_n exit-trap lines (EXIT or 0), want exactly one, the sentinel in _st_begin: a second would silently replace it"; return 1; fi
  return 0
}

# --selftest dispatch — BEFORE the usage check below, or `--selftest` is read as a filename.
# `exit $?` rather than relying on selftest() to exit: a refactor to `return` would otherwise fall
# through to WORKFLOW="--selftest" and die with a misleading "workflow file not found".
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  # B7: the own-tree leg. Leg B (check_kit_seams) does NOT run in this mode — its resolution root
  # is the kit tree by design; see the OWN-TREE ceiling block above.
  --own-tree)
    shift
    if [ $# -gt 1 ]; then echo "usage: ci-gates.sh --own-tree [<root>]" >&2; exit 1; fi
    own_tree_run "${1:-.}"; exit $? ;;
  # B8: the single-sourced disposition query mode (see disposition_query's header above).
  --disposition)
    shift
    if [ $# -ne 2 ]; then echo "usage: ci-gates.sh --disposition <gate-id> <file>" >&2; exit 1; fi
    disposition_query "$1" "$2"; exit $? ;;
  # TIER0-LOCKS-OWED (b): the aggregator needs:/classifier drift-lock. Defaults to this kit's own
  # ci.yml + ci-classify-changes.sh; a selftest fixture passes both explicitly.
  # SWAS-281: the read-only runner-job counter the conformance-mass-budget `jobs` surface reads (see count_legs_run).
  --count-legs)
    shift
    if [ $# -gt 1 ]; then echo "usage: ci-gates.sh --count-legs [<root>]" >&2; exit 1; fi
    count_legs_run "${1:-$(dirname "$0")/..}"; exit $? ;;
  # SWAS-409 (CI-SHAPING S4): the shard join's first step (see the SHARD JOINS block above).
  --shard-join)
    shift
    if [ $# -lt 2 ] || [ $# -gt 4 ]; then echo "usage: ci-gates.sh --shard-join <join> \"<leg results>\" [<workflow> [<docs-pin>]]" >&2; exit 1; fi
    shard_join_run "$@"; exit $? ;;
  # SWAS-447: the read-only line-break ban over the kit's judged file set (the tree walk of check_line_breaks_tree).
  --line-breaks)
    shift
    if [ $# -gt 1 ]; then echo "usage: ci-gates.sh --line-breaks [<root>]" >&2; exit 1; fi
    check_line_breaks_tree "${1:-$(dirname "$0")/..}"; exit $? ;;
  --aggregator-lock)
    shift
    _al_root="$(dirname "$0")/.."
    _al_y="${1:-$_al_root/.github/workflows/ci.yml}"
    _al_c="${2:-$_al_root/conformance/ci-classify-changes.sh}"
    aggregator_needs_lock "$_al_y" "$_al_c" "${3:-}"; exit $? ;;
esac

WORKFLOW=""; EXPECT_SEAMS=0
for _a in "$@"; do
  case "$_a" in
    (--expect-seams) EXPECT_SEAMS=1 ;;
    (-*) echo "usage: ci-gates.sh <workflow-file> [--expect-seams] | --selftest" >&2; exit 1 ;;
    (*) [ -n "$WORKFLOW" ] && { echo "usage: ci-gates.sh <workflow-file> [--expect-seams]" >&2; exit 1; }
        WORKFLOW=$_a ;;
  esac
done

if [ -z "$WORKFLOW" ]; then
  echo "usage: ci-gates.sh <workflow-file> [--expect-seams] | --selftest" >&2
  exit 1
fi
if [ ! -f "$WORKFLOW" ]; then
  echo "error: workflow file not found: $WORKFLOW" >&2
  exit 1
fi

# 8 standardized step ids implementing the 7 contract gates
# (gate 7 = supply-chain = gate-sbom + gate-provenance). 'install' is setup, not a gate.
# ALIASED to the single OWN_GATE_IDS list (B7): a second literal copy would be a drift pair
# nothing locks — Leg A and the own-tree leg must judge the same contract.
REQUIRED="$OWN_GATE_IDS"

missing=""
for gate in $REQUIRED; do
  # GitHub Actions step id, OR GitLab CI job key (a top-level job named exactly gate-X).
  gh_id="^[[:space:]]*(-[[:space:]]+)?id:[[:space:]]*[\"']?${gate}[\"']?[[:space:]]*(#.*)?\$"
  gl_job="^${gate}:[[:space:]]*(#.*)?\$"
  if ! grep -Eq "$gh_id" "$WORKFLOW" && ! grep -Eq "$gl_job" "$WORKFLOW"; then
    missing="$missing $gate"
  fi
done

if [ -n "$missing" ]; then
  echo "FAIL: $WORKFLOW is missing required CI gate(s):$missing" >&2
  echo "See DEVELOPMENT-STANDARDS.md §14 (CI/CD Pipeline)." >&2
  exit 1
fi

check_kit_seams "$WORKFLOW" "$(dirname "$0")/.." "$EXPECT_SEAMS" || exit 1

echo "OK: $WORKFLOW declares all required CI gates ($REQUIRED)"
exit 0
