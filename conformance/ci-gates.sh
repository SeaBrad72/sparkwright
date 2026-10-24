#!/bin/sh
# ci-gates.sh — conformance check for DEVELOPMENT-STANDARDS.md §14 (CI/CD Pipeline).
# Asserts a CI workflow declares all required quality gates by their standardized
# step ids. Checks contract identifiers, not stack tools, so it is stack-neutral:
# any workflow that adopts these ids can be verified, in any language.
#
# Usage: sh conformance/ci-gates.sh <workflow-file> [--expect-seams]
#        sh conformance/ci-gates.sh --own-tree [<root>]     (B7: judge THIS tree's OWN pipeline(s))
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
    for _ot_cw in ci.yml golden-path.yml; do
      # a missing file is skipped on purpose: golden-path-filter-parity.sh also treats an absent golden-path.yml as N/A
      [ -f "$_ot_root/.github/workflows/$_ot_cw" ] || continue
      check_pr_concurrency "$_ot_root/.github/workflows/$_ot_cw" || _ot_rc=1
    done
    check_runner_pins_tree "$_ot_root" || _ot_rc=1  # SWAS-306: the runner-pin lock (RP); kit trees only
    [ ! -f "$_ot_root/.github/workflows/ci.yml" ] || check_sast_parse_spans "$_ot_root/.github/workflows/ci.yml" || _ot_rc=1  # SWAS-278: the SAST-parse spans line (SP)
    [ ! -f "$_ot_root/.github/workflows/ci.yml" ] || check_guard_delta_step "$_ot_root/.github/workflows/ci.yml" || _ot_rc=1  # SWAS-301: the guard delta step (GD)
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

  [ "$_al_bad" = 0 ] || return 1
  echo "OK: aggregator-needs-lock — needs:/PG_NEEDED match, every push-graded job is accounted for, conformance-core step count pinned at $_al_pin"
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
TT_CI_EXCLUDED="conformance-core secret-scan conformance-docs"  # fetch-depth: 0 only; each reads full refs / shas, not a short name
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

selftest() {
  sf=0; d=$(mktemp -d); trap 'rm -rf "$d"' EXIT INT TERM
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
      sed 's/cf-green-on-clone, guard-battery, guard-delta\]/cf-green-on-clone, guard-battery]/' "$_gd_real" > "$d/gd/m8.yml"
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

    # OT15 — gate-test STAYS TERMINAL (reviewer LOW-4): reaching the id attests every selftest
    # step above it passed ONLY while it is the LAST step of conformance-selftests — a step
    # planted after it is NOT attested (the anchor comment at the id states exactly this).
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
      echo "selftest PASS: OT15 — id: gate-test is the LAST step of conformance-selftests (stay-terminal pinned)"
    else
      echo "selftest FAIL: OT15 — id: gate-test is no longer the terminal step of conformance-selftests; a step after it is unattested by the battery id — move it back or re-anchor the id, citing D-240805-2: $_ts_real"; sf=1
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
  else
    echo "selftest SKIP: TT0-TT5 — not a kit tree"
  fi

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

  if [ "$sf" -eq 0 ]; then echo "OK: ci-gates selftest"; exit 0; else echo "FAIL: ci-gates selftest"; exit 1; fi
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
