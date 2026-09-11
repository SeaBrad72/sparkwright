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
_AGG_CC_STEP_PIN=28
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

check_loop_state_credential_order() {  # <workflow-file> -> 0 ok, 1 drop absent/misordered
  # F1: the `loop-state` job runs PR-controlled code — `conformance/loop-state.sh --head` AND
  # `scripts/promotion-verify.sh trace` (the recordless-merge leg) — with a checkout token that must
  # already be gone from .git/config, the sibling idiom the ceremony-binding and review-lane jobs use.
  # This asserts the credential-drop line PRECEDES the job's first PR-TREE invocation, counting BOTH
  # conformance/ AND scripts/ (F1-2: the loop-state job's `promotion-verify.sh trace` lives under
  # scripts/ and is PR-tree code too — an earlier fix counted only conformance/, so a drop landing
  # after a scripts/ call but before the first conformance/ call would have false-passed). No PR-tree
  # invocation in the block at all -> nothing to order -> vacuous pass (a job by this name with a
  # different shape is not this leg's concern).
  _clo_block=$(extract_job_block "$1" loop-state)
  if [ -z "$_clo_block" ]; then
    echo "FAIL: loop-state job not found in $1" >&2
    return 1
  fi
  # Comments stripped first (this file's existing convention — check_kit_seams does the same):
  # a `#` reference to `conformance/` or `scripts/` in a prose comment (as this very job's own
  # comments carry) must not count as the invocation the ordering protects.
  _clo_stripped=$(printf '%s\n' "$_clo_block" | sed 's/#.*//')
  _clo_conf=$(printf '%s\n' "$_clo_stripped" | grep -nE 'conformance/|scripts/' | head -1 | cut -d: -f1)
  [ -n "$_clo_conf" ] || return 0
  _clo_drop=$(printf '%s\n' "$_clo_stripped" | grep -n "unset-all 'http.https://github.com/.extraheader'" | head -1 | cut -d: -f1)
  if [ -z "$_clo_drop" ]; then
    echo "FAIL: loop-state job has no checkout-credential drop before its first PR-tree (conformance/ or scripts/) invocation" >&2
    return 1
  fi
  if [ "$_clo_drop" -ge "$_clo_conf" ]; then
    echo "FAIL: loop-state job's credential drop (block line $_clo_drop) does not precede its first PR-tree (conformance/ or scripts/) invocation (block line $_clo_conf)" >&2
    return 1
  fi
  return 0
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
  printf 'jobs:\n  loop-state:\n    steps:\n      - run: |\n          git config --local --unset-all '"'"'http.https://github.com/.extraheader'"'"'\n          sh conformance/loop-state.sh --head X\n' > "$d/ls/good.yml"
  if check_loop_state_credential_order "$d/ls/good.yml" >/dev/null 2>&1; then
    echo "selftest PASS: LS1 — credential drop before the first conformance/ invocation -> PASS"
  else echo "selftest FAIL: LS1 — good fixture wrongly failed"; sf=1; fi

  # negative — the drop line absent entirely
  printf 'jobs:\n  loop-state:\n    steps:\n      - run: sh conformance/loop-state.sh --head X\n' > "$d/ls/nodrop.yml"
  if check_loop_state_credential_order "$d/ls/nodrop.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: LS2 — a missing credential drop was NOT caught"; sf=1
  else echo "selftest PASS: LS2 — missing credential drop -> FAIL"; fi

  # negative — the drop line present but AFTER the conformance/ invocation
  printf 'jobs:\n  loop-state:\n    steps:\n      - run: |\n          sh conformance/loop-state.sh --head X\n          git config --local --unset-all '"'"'http.https://github.com/.extraheader'"'"'\n' > "$d/ls/misordered.yml"
  if check_loop_state_credential_order "$d/ls/misordered.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: LS3 — a credential drop AFTER the conformance/ invocation was NOT caught"; sf=1
  else echo "selftest PASS: LS3 — drop ordered after the conformance/ call -> FAIL"; fi

  # regression backstop — the kit's OWN live ci.yml must pass this leg today (the SESSION-SURFACE
  # T3/F1 fix). Gated on the same kit-tree marker AGG5/AGG6 use, so an adopter export is unjudged.
  if [ -f "$_agg_kr/.github/workflows/ci.yml" ] && { [ -f "$_agg_kr/docs/ROADMAP-KIT.md" ] || [ -f "$_agg_kr/.github/workflows/golden-path.yml" ]; }; then
    if check_loop_state_credential_order "$_agg_kr/.github/workflows/ci.yml" >/dev/null 2>&1; then
      echo "selftest PASS: LS4 — the kit's own ci.yml drops the loop-state credential before its first conformance/ invocation"
    else echo "selftest FAIL: LS4 — the kit's own ci.yml regressed the loop-state credential-drop ordering"; sf=1; fi
  else
    echo "selftest SKIP: LS4 — not a kit tree"
  fi

  # negative (F1-2) — a scripts/ invocation is PR-tree code too (the loop-state job's
  # `promotion-verify.sh trace`), so a credential drop AFTER a scripts/ call, but before the first
  # conformance/ call, must FAIL: the token is still readable when the scripts/ PR-code runs.
  printf 'jobs:\n  loop-state:\n    steps:\n      - run: |\n          sh scripts/promotion-verify.sh trace --recent 1\n          git config --local --unset-all '"'"'http.https://github.com/.extraheader'"'"'\n          sh conformance/loop-state.sh --head X\n' > "$d/ls/scriptsfirst.yml"
  if check_loop_state_credential_order "$d/ls/scriptsfirst.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: LS5 — a credential drop AFTER a scripts/ PR-code invocation was NOT caught"; sf=1
  else echo "selftest PASS: LS5 — drop ordered after a scripts/ PR-code call -> FAIL"; fi

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
