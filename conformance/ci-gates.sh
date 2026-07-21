#!/bin/sh
# ci-gates.sh — conformance check for DEVELOPMENT-STANDARDS.md §14 (CI/CD Pipeline).
# Asserts a CI workflow declares all required quality gates by their standardized
# step ids. Checks contract identifiers, not stack tools, so it is stack-neutral:
# any workflow that adopts these ids can be verified, in any language.
#
# Usage: sh conformance/ci-gates.sh <workflow-file> [--selftest]
# Exit:  0 = all gates present and every kit-owned invocation resolves · 1 = missing gate(s),
#        a kit-owned invocation whose subcommand does not resolve, or bad usage.
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
#   - EXTRACTION: only `sh|bash <unquoted scripts/... path> <token>` forms are seen.
#     `./scripts/x.sh sub` and `sh "scripts/x.sh" sub` are invisible to it.
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
#   - NOT A PARSER: the predicate knows exactly two dispatch shapes, both line-anchored — a `case`
#     arm and an `if [ "$1" = sub ]` equality test. What happens to any OTHER dispatch shape depends
#     on whether the script still contains SOME `case "$1"` line, because that is the gate the
#     dispatch-style guard reads:
#       * NO `case "$1"` anywhere (a pure table, an `eval` dispatch, `getopts` — which dispatches on
#         `case "$opt"`, never on `$1`): the guard skips the script entirely -> SILENT PASS. These
#         belong to the fail-OPEN bullet above, not here.
#       * SOME `case "$1"` present but the real verb dispatch built another way — e.g. an unrelated
#         inner option loop, as scripts/adopter-export.sh:385 has: the script IS judged, the verb is
#         not found -> UNRESOLVED.
#     That second, narrow band is the only one that fails CLOSED, and it is the one to widen first
#     if a false FAIL appears. Do not read this bullet as a general fail-closed guarantee.
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
    | grep -oE '(sh|bash)[[:space:]]+scripts/[a-zA-Z0-9_.-]+\.sh[[:space:]]+[-a-zA-Z0-9_./]+' \
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
        # Only a verb-dispatch script HAS subcommands to resolve against; one that takes a
        # positional argument (no `case "$1"`) must never be judged -- rejecting its legal
        # invocation would be a false positive on a blocking gate.
        grep -qE 'case[[:space:]]+"?\$\{?1' "$_root/$_script" || continue
        # Resolve against the DISPATCH, not against the file. Two dispatch shapes are honoured, and
        # BOTH must OPEN a line, so a mention of the verb in a usage string, a comment, or any other
        # prose can never satisfy the lock. A whole-file grep cannot tell "resolves against the
        # dispatch" from "appears somewhere" -- exactly how one `printf` help line in
        # scripts/otel-trace.sh silently vouched for two verbs it does not implement (CP-7 I1).
        #   _armRE: a `case` arm -- optionally `(`-led, optionally preceded by other alternates in
        #           an `a|b|sub)` chain.
        #   _ifRE:  an `if [ "$1" = sub ]` / `elif` equality dispatch -- measured on the real tree in
        #           scripts/explain.sh and scripts/adopter-export.sh, whose live CI invocations a
        #           case-arm-only predicate would falsely FAIL.
        # Neither regex carries a top-level `|`, so alternating them in one pass is safe.
        _armRE="^[[:space:]]*\(?(\"?[-a-zA-Z0-9_*]+\"?[[:space:]]*\|[[:space:]]*)*\"?${_sub}\"?[[:space:]]*[)|]"
        # `[$]`, not `\$`: this is a DOUBLE-quoted string, where the shell collapses `\$` to a bare
        # `$` and ERE then reads it as the end-of-line anchor -- the regex silently never matches.
        _ifRE="^[[:space:]]*(el)?if[[:space:]]+\[[[:space:]]+\"?[$]\{?1[^]]*=[[:space:]]*\"?${_sub}\"?[[:space:]]*\]"
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

  if [ "$sf" -eq 0 ]; then echo "OK: ci-gates selftest"; exit 0; else echo "FAIL: ci-gates selftest"; exit 1; fi
}

# --selftest dispatch — BEFORE the usage check below, or `--selftest` is read as a filename.
# `exit $?` rather than relying on selftest() to exit: a refactor to `return` would otherwise fall
# through to WORKFLOW="--selftest" and die with a misleading "workflow file not found".
case "${1:-}" in --selftest) selftest; exit $? ;; esac

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
REQUIRED="gate-lint gate-type-check gate-test gate-build gate-secret-scan gate-dep-scan gate-sbom gate-provenance"

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
