#!/bin/sh
# verify.sh — honest aggregate conformance runner. Classifies each check:
#   [control] — verifies a live/remote/structural WORKING control
#   [doc]     — verifies DOCUMENTATION / recorded evidence EXISTS (not that it was tested)
# Prints PASS/FAIL/UNVERIFIED/N-A per check + an honest summary footer. THREE non-FAIL outcomes, and
# they are NOT interchangeable: PASS = it ran and proved its claim · UNVERIFIED (rc 2) = it could not
# run, and is a FAIL under --require/CI · N-A = it declined to verify here and SAID SO (a --kitself row
# on an adopter tree, or a child that self-skipped on rc 0) — never blocking, never an OK. Exit policy:
#   non-zero if any [control] check FAILS, or (under --require / CI) any check is UNVERIFIED.
#   [doc] checks that are present-but-untested PASS — honestly labelled, not hidden.
# MISCONFIGURED splits rc 2: a row whose child answers with `usage: <that child's basename>` was
# INVOKED WRONG by this file's own registry — a wiring bug, not an environment one — so it FAILS
# ALWAYS, not only under --require (VERIFY-RC2-USAGE-OVERLOAD). ⚠️ SAFETY DIRECTION IS INVERTED HERE,
# and it is the first prose heuristic in this file that BLOCKS: everywhere else a false hit under-
# claims (a real proof renders N-A — visible, never green-while-dark), but a false hit HERE reds a
# legitimate row. The child-basename anchor is what carries that risk down: a bare `^usage:` key would
# also match a NESTED child's usage bubbling up through a wrapper (measured at ci-gates.sh:457). A
# check that prints its usage text in some other shape stays UNVERIFIED — the marker is a convention.
# A green run proves controls hold AND release/DR/resilience safety is DOCUMENTED — NOT
# that those procedures were tested. See conformance/README.md "What a green run means".
# SCOPE: this is a curated aggregate of the repo-runnable checks — NOT every conformance
# script. Checks needing project context or live creds (e.g. inception-done, tracker-contract,
# stack-selection — repo-admin creds it can't have in least-privilege CI; verified at the
# governance gate, see its header) and conditionally-wired checks (e.g. container-supply-chain)
# run in their own CI steps / at the adopter's gate, not here. branch-protection.sh is now SPLIT at
# the credential seam (B4): its OFFLINE declaration-integrity leg (--declared-only — no gh, no
# network) IS registered below; its LIVE forge-comparison leg still needs repo-admin gh and runs
# operator-side, not here. "aggregate" means representative.
#   usage: sh conformance/verify.sh [--require] [--changed <listing-file>] [--summary-file <path>] | --selftest
#
# ADOPTER-KIT-SELFTESTS-ON-CHANGE — `--changed <listing>` (a newline-delimited changed-paths file) lets an
# ADOPTER's pull-request run skip the rows flagged `--kitselftest` (the kit's own selftests, whose subject
# cannot have changed) and render them N-A. The skip fires ONLY when the listing is a readable, non-empty
# file AND `conformance/promotion-readiness.sh --class --changed <listing>` exits 0 and answers `ordinary` or
# `sensitive`. Everything else — no --changed, an empty/unreadable listing, a classifier failure or unknown
# answer, class `control-plane` — runs the FULL battery: every unknown costs time, never coverage. One notice
# line `kit selftests not re-run: …` precedes the Summary; `--summary-file <path>` also receives it. A run with no --changed is
# byte-for-byte the old behaviour. Design: docs/architecture/2026-10-01-adopter-kit-selftests-on-change-design.md.
# A LITERAL FORCED-FULL FLOOR (below, _ks_floor_hit) sits in front of the classifier: any listed control-plane-shaped path
# (.claude/, conformance/, scripts/, hooks/, adapters/, profiles/, .github/, .kit/, a .gitattributes / .shellcheckrc basename,
# docs/roadmap-kit.md, case-folded, plus any CR byte) forces the full battery without consulting the classifier.
# TEST SEAMS (test affordances for a TRUSTED LOCAL shell, not a security boundary): VERIFY_SELFTEST_REGISTRY=<file>
# (sourced in place of the built-in registry) and VERIFY_CLASSIFIER=<script> (in place of the real classifier). The seams
# are REFUSED outright (error, exit 2) when CI or GITHUB_ACTIONS is set, and any run that uses one is tainted: a loud
# stderr banner and an UNVERIFIED exit 2 whatever the rows did. A sourced registry runs in-process, so this is not a sandbox.
set -eu
# Refuse the test seams under CI BEFORE doing anything else (ADOPTER-KIT-SELFTESTS-ON-CHANGE fix round 1, S3).
if { [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; } && { [ -n "${VERIFY_SELFTEST_REGISTRY:-}" ] || [ -n "${VERIFY_CLASSIFIER:-}" ]; }; then
  echo "verify: REFUSED — VERIFY_SELFTEST_REGISTRY / VERIFY_CLASSIFIER are test seams and are not honoured when CI or GITHUB_ACTIONS is set" >&2
  exit 2
fi
# REVIEW R1: resolve THIS script's absolute path BEFORE the cd — `cd conformance && sh ./verify.sh`
# leaves $0 as a relative path that no longer resolves once we have moved up a directory.
_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
_KS_ORIG_PWD=$(pwd)   # a relative --changed / --summary-file path means relative to the CALLER, not the repo root
cd "$(dirname "$0")/.."

REQUIRE=0
[ -n "${CI:-}" ] && REQUIRE=1
[ "${1:-}" = "--require" ] && REQUIRE=1
# --changed / --summary-file may sit anywhere after the first word; a missing value leaves them empty,
# which means "no listing" = the full battery (the safe direction). Values are made absolute BEFORE use.
KS_CHANGED=""; KS_SUMMARY=""; _ks_prev=""
for _ks_a in "$@"; do
  case "$_ks_prev" in
    --changed) KS_CHANGED=$_ks_a ;;
    --summary-file) KS_SUMMARY=$_ks_a ;;
  esac
  [ "$_ks_a" = "--require" ] && REQUIRE=1
  _ks_prev=$_ks_a
done
case "$KS_CHANGED" in ''|/*) ;; *) KS_CHANGED="$_KS_ORIG_PWD/$KS_CHANGED" ;; esac
case "$KS_SUMMARY" in ''|/*) ;; *) KS_SUMMARY="$_KS_ORIG_PWD/$KS_SUMMARY" ;; esac

ctrl_fail=0; unverified=0; controls=0; docs=0; failed=0; nas=0; misconfigured=0
SKIP_KS=0; SKIPPED_KS=""   # --kitselftest skip mode (decided once, after the selftest block) and the rows it skipped
line() { printf '  %-9s %-18s %s\n' "$1" "$2" "$3"; }

# ── K3 — a failing gate must not hide WHY ───────────────────────────────────────────────────────────
# check() already captures the child's combined output in $out and, until v3.173.0, threw it away: the
# aggregate printed `whitespace-clean FAIL` in an otherwise 101-pass run and nothing else, so the
# operator had to RE-RUN the individual gate to learn which file was at fault. That is a diagnostic
# round trip on every failure, paid at exactly the moment the operator is least oriented — and on a
# COLD field test (where nobody may assist) it is the difference between a self-explaining failure and
# a dead end. The output was always in hand; it was simply never printed.
#
# Indented and clearly delimited so the aggregate stays SCANNABLE: only failures expand, passes stay
# one line each. A child that prints nothing still shows nothing — this surfaces existing output, it
# does not invent any.
emit_diag() {  # <check-name> <captured-output>
  [ -n "$2" ] || { printf '      (%s produced no output — re-run it directly)\n' "$1"; return 0; }
  printf '      ── %s output ──────────────────────────────\n' "$1"
  printf '%s\n' "$2" | sed 's/^/      /'
  printf '      ──────────────────────────────────────────\n'
}

# ── C6 — a check that DID NOT VERIFY must not render PASS ───────────────────────────────────────────
# THE DEFECT: check() runs the child, and on rc 0 it threw the child's own words away and printed PASS.
# But dozens of checks are CONDITIONAL — "no Dockerfile", "no data surface", "not an AI feature", "not
# the kit repo" — and they say so on stdout and exit 0. The aggregate rendered that self-declared
# NON-verification with the same token as an executed proof, so a green run over-claimed by however
# many rows had quietly skipped (MEASURED: ≥14 on the kit tree, whose Summary simultaneously reported
# `0 n/a` — the bug's own signature; ≥39 on a raw adopter export).
#
# THE PREDICATE IS MEASURED, NOT INVENTED — and the measurement CORRECTED it twice. It has two
# conjuncts, and both were forced by evidence rather than chosen.
#
# CONJUNCT 1 — the child declares a skip. Enumerated over every rc-0 self-skip branch reachable from
# the `check` rows below, the shipped idiom has exactly three shapes, all printed as a WHOLE LINE:
#   `N/A: …` / `N/A (no Dockerfile): …` / `N/A — …`        (the conditional-surface skips)
#   `<check-name>: N/A — kit-self check (…)`                (the ~20 *-wired.sh kit-self skips)
#   `SKIP: …`                                               (conformance/shellcheck.sh, tool absent)
# LINE-ANCHORING IS LOAD-BEARING, not tidiness. A check that is genuinely RUNNING prints `N/A` mid-line
# all the time — incept-first-run-green.sh renders `  [N/A]   db-postgres — …` per sub-gate and a
# `… $NAS N/A, …` summary; selftests narrate `selftest PASS: no CLAUDE.md -> N/A`. MEASURED over a full
# instrumented aggregate: 36 of the 135 rc-0 rows mention n/a or skip prose somewhere in their output
# and every one of them had really run. An unanchored match would demote all 36. The anchor takes none.
#
# CONJUNCT 2 — and the child claims NO verdict. This one is a BUILD-TIME FALSIFICATION of the design's
# assumed predicate (design §6.2 expected conjunct 1 alone). Measured on the same aggregate: conjunct 1
# on its own captured `image-supply` and `runtime-floor`, which iterate the ten profiles, skip the three
# or four that have no Dockerfile / no declared floor, and VERIFY THE REST — `image-supply` proved seven
# real supply chains and then signed off `container-supply-chain: OK (7 profile(s) … checked; others
# N/A)`. Calling that N-A under-claims: the run DID verify something. So a PARTIAL skip beside a real
# verdict stays PASS, and N-A means what it says — this check verified NOTHING here. The verdict idiom
# is uppercase `OK`/`PASS` at line start (bare or `<name>: OK`), deliberately case-SENSITIVE so ordinary
# prose ("ok, so…") cannot suppress a real skip. Measured effect: 17 rows classified → 15, and the two
# it drops are exactly the two that had proved something.
#
# FAIL DIRECTION IS SAFE BY CONSTRUCTION: this is a render-honesty change, never an authorization one.
# A false positive under-claims (a real proof shows as N-A — visible, non-blocking, never green-when-
# dark); a false negative is exactly today's status quo. HONEST CEILING: it is a prose heuristic. A
# future check that self-skips in NON-conforming prose renders PASS until its idiom is added here —
# the class is narrowed, not closed (boarded: VERIFY-SKIP-IDIOM-RESIDUAL).
is_self_skip() {  # <captured-output> — 0 when the child DECLARED it verified nothing here
  printf '%s\n' "$1" | grep -Eqi '^(N/A([^A-Za-z0-9]|$)|SKIP:|[A-Za-z0-9_.-]+:[[:space:]]*N/A([^A-Za-z0-9]|$))' || return 1
  # ZERO-COUNT REFINEMENT (VERIFY-SKIP-IDIOM-RESIDUAL, face ii): a verdict line that SELF-REPORTS zero
  # verified items suppresses nothing — `OK (0 profile(s) … checked)` is a skip wearing a verdict, and
  # C6's own rule ("N-A means this check verified NOTHING here") says so. Dropped BEFORE the verdict
  # test, so a run with a zero-count line AND a real one still passes on the real one.
  # THE KEY IS THE WHOLE SENTENCE SHAPE, not a bare `(0 `: MEASURED, conformance/*.sh emits `(0 ` on 37
  # lines — `(0 rows)`, `(0 find spawns…)`, `(0 foreign lines…)`, `(0 files)`, `(0 occurrence(s))` — and
  # a loose key would demote every row that prints one. ZERO of the 37 match this key. That tightness is
  # also what protects mechanism 3: a false N-A here would inflate the very `na` the CI walks' floor reads.
  ! printf '%s\n' "$1" | grep -Ev '\(0 [A-Za-z-]+\(s\)[^)]*checked' \
    | grep -Eq '^(OK|PASS)([^A-Za-z0-9]|$)|^[A-Za-z0-9_.-]+:[[:space:]]*(OK|PASS)([^A-Za-z0-9]|$)'
}

# is_usage_marked <captured-output> <child-basename> — 0 when a line STARTS with `usage: <basename>`
#
# ⚠️ LITERAL MATCH, DELIBERATELY NOT A REGEX. The first draft interpolated the basename into a BRE
# (`grep -q "^usage: $_base"`), where `foo.sh`'s `.` matches ANY character — so `usage: foo-sh …` was
# blamed on a row invoking `foo.sh`. Elsewhere in this file a false hit under-claims; HERE the safety
# direction is inverted (see the header) and it BLOCKS a legitimate row. The quoted `case` pattern is
# exact. The `while` reads a heredoc, not a pipe, so the assignment survives the loop.
is_usage_marked() {
  [ -n "$2" ] || return 1
  _um=1
  while IFS= read -r _uml; do
    case "$_uml" in "usage: $2"*) _um=0; break ;; esac
  done <<EOF
$1
EOF
  return "$_um"
}

# ── INCOMPLETE (K16) — an interrupted run must SAY so, in its own output ────────────────────────────
# The aggregate is WELL OVER A HUNDRED checks and takes MINUTES (measured 281s at v3.171.0; ~22min on a
# loaded host). The authoritative count is the run's own `Summary:` line — no figure is repeated here,
# because every hard-coded one in this file had gone stale by ~30 rows before C6 corrected them. That
# runtime is LONGER than the default foreground command cap of the agent harnesses this kit is driven
# with. When one of those caps fires, the run is killed mid-flight.
#
# THE EXIT CODE WAS NEVER THE GAP. A signalled run already exits non-zero (143 for TERM, 130 for INT),
# so a caller that inspects the status is not fooled. What was missing is any STATEMENT: the output
# simply stopped, leaving a partial transcript indistinguishable from a run still in progress. A human
# or agent READING that transcript had to infer completion from an ABSENCE — the weakest possible
# signal, and how a truncated run gets mistaken for a green one (CP-7 run 4, finding K16).
#
# So this trap adds the sentence, and keeps the conventional 128+signal status. `INCOMPLETE is not a
# pass` is the sibling of `UNVERIFIED is not a pass` — a second way output can look green without being
# one. HONEST CEILING: cannot fire on SIGKILL, and cannot help a consumer that simply stops reading.
_incomplete() {
  echo ""
  printf 'RESULT: FAIL (INCOMPLETE — interrupted after %d check(s); this is NOT a pass)\n' "$((controls+docs+nas))"
  echo "An interrupted run proves nothing about the checks that never ran."
  echo "The full aggregate is well over a hundred checks / several minutes — re-run WITHOUT a command timeout"
  echo "(background it, or capture output to a file). See conformance/README.md \"What a green run means\"."
  exit "${1:-1}"
}
trap '_incomplete 130' INT
trap '_incomplete 143' TERM

# check KIND NAME [--kitself | --adopter] COMMAND...
check() {
  kind=$1; name=$2; shift 2
  # CP7R5-VERIFY-NONTS — a --kitself check validates the kit's OWN internals (a reference profile, a
  # dev selftest) and is meaningless on an already-incepted ADOPTER tree, where incept has pruned the
  # fixtures it reads. On an adopter tree it renders N-A (not a pass, not a fail); in the kit repo it runs.
  # The tree is classified by the un-spoofable kit-marker set: an adopter export strips BOTH
  # docs/ROADMAP-KIT.md (export-ignored) AND .github/workflows/golden-path.yml (control-plane +
  # export-ignored), so their joint absence == an adopter tree. Same set incept-first-run-green.sh keys on.
  # Paths are repo-root-relative (this script cd's to the root at startup).
  #
  # ADOPTER-GATES-INERT (A3) — --adopter is the SIBLING classification, METADATA-ONLY: it never skips
  # the command (unlike --kitself, which short-circuits before invocation). It exists purely so
  # conformance/adopter-census.sh can read the classification off this REGISTRY LINE — the census's
  # single source of truth — for a row whose subject is the ADOPTER'S OWN artifact (their ci.yml, ADR,
  # RUNBOOK, VERSION tag, board): such a row correctly N/As on a pre-inception export (nothing authored
  # yet) and ARMS once the adopter incepts/authors, so silencing it with --kitself would be a lie — the
  # exact error A3 found and corrected (see verify.sh's registry rows below for the 9 --adopter cases).
  # The two flags are mutually exclusive: a row is either a KIT fact or an ADOPTER fact, never both.
  if [ "${1:-}" = "--kitself" ] && [ "${2:-}" = "--adopter" ]; then
    echo "verify.sh: registry error — check '$name' declares BOTH --kitself and --adopter (mutually exclusive)" >&2
    exit 2
  fi
  if [ "${1:-}" = "--adopter" ] && [ "${2:-}" = "--kitself" ]; then
    echo "verify.sh: registry error — check '$name' declares BOTH --adopter and --kitself (mutually exclusive)" >&2
    exit 2
  fi
  # --kitselftest (ADOPTER-KIT-SELFTESTS-ON-CHANGE) is the THIRD sibling, exclusive with both others in either order.
  case "${1:-}:${2:-}" in
    --kitselftest:--kitself|--kitselftest:--adopter|--kitself:--kitselftest|--adopter:--kitselftest)
      echo "verify.sh: registry error — check '$name' declares --kitselftest together with --kitself/--adopter (mutually exclusive)" >&2
      exit 2 ;;
  esac
  if [ "${1:-}" = "--kitselftest" ]; then
    shift
    # Skip mode is decided ONCE (below the selftest block) from a readable non-empty non-control-plane
    # listing; it renders through the SAME N-A path and counters as --kitself — no new verdict kind.
    if [ "$SKIP_KS" = "1" ]; then
      line "[$kind]" "$name" "N-A"; nas=$((nas+1)); SKIPPED_KS="$SKIPPED_KS $name"; return 0
    fi
  elif [ "${1:-}" = "--kitself" ]; then
    shift
    if [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]; then
      line "[$kind]" "$name" "N-A"; nas=$((nas+1)); return 0
    fi
  elif [ "${1:-}" = "--adopter" ]; then
    shift   # metadata-only: fall through and run the command like any unflagged row
  fi
  # The child's own basename, for the MISCONFIGURED key below. Taken from the ROW, not from $out.
  _base=""; for _a in "$@"; do case "$_a" in conformance/*.sh) _base=${_a##*/}; break ;; esac; done
  if out=$("$@" 2>&1); then rc=0; else rc=$?; fi
  # C6 — a child that self-declared it verified NOTHING here renders N-A, not PASS. Gated on rc = 0
  # EXACTLY, so this branch is structurally unreachable from the FAIL and rc-2/UNVERIFIED arms below:
  # no failing or unverified check can be reclassified by prose, and --require semantics are untouched.
  # Placed BEFORE the kind-increment so an N-A row leaves BOTH denominators — byte-consistent with the
  # --kitself precedent above, so N-A means one thing everywhere: this check did not verify anything
  # here, and said so. Not blocking, not OK; the reason stays in $out and is deliberately not surfaced
  # (the token + the count IS the honesty claim; one line per check, per the selftest's own pin).
  if [ "$rc" = "0" ] && is_self_skip "$out"; then
    line "[$kind]" "$name" "N-A"; nas=$((nas+1)); return 0
  fi
  case "$kind" in control) controls=$((controls+1)) ;; doc) docs=$((docs+1)) ;; esac
  if [ "$rc" = "0" ]; then
    line "[$kind]" "$name" "PASS"
  elif [ "$rc" = "2" ] && is_usage_marked "$out" "$_base"; then
    # The registry invoked this child WRONG. Blocking without --require, on purpose: a broken row is
    # invisible to a local run otherwise, and a row that never runs proves nothing while looking green.
    # Its OWN counter, and it does NOT touch $failed (the doc-check advisory tally): borrowing that
    # gave the class two blocking paths, one of which no leg could kill (a mutant dropping the
    # $failed increment survived the whole battery).
    line "[$kind]" "$name" "MISCONFIGURED"; misconfigured=$((misconfigured+1))
    emit_diag "$name" "$out"
  elif [ "$rc" = "2" ]; then
    line "[$kind]" "$name" "UNVERIFIED"; unverified=$((unverified+1))
    # Under --require/CI an UNVERIFIED IS a failure, so it earns its diagnostic too — otherwise the
    # one state most likely to be environmental ("no gh, no remote") is the hardest to act on.
    [ "$REQUIRE" = "1" ] && { failed=$((failed+1)); emit_diag "$name" "$out"; } || true
  else
    line "[$kind]" "$name" "FAIL"; failed=$((failed+1))
    [ "$kind" = "control" ] && ctrl_fail=1 || true
    emit_diag "$name" "$out"
  fi
}

# CP7R5-VERIFY-SUMMARY — the RESULT sentence must not claim "docs present" over FAILING doc-checks.
# Emitted via a function so --selftest drives it with synthetic counters (non-vacuous, no full aggregate).
# Reads globals $ctrl_fail/$unverified/$misconfigured/$failed/$REQUIRE; echoes RESULT; 1 on FAIL, 0 on OK.
# When this is reached with $failed != 0, ctrl_fail is 0 and (under --require) unverified is 0, so every
# remaining failure is a doc-check — hence "$failed doc-check(s)" is exact, not an over-count.
result_sentence() {
  if [ "$ctrl_fail" != "0" ]; then echo "RESULT: FAIL (a control check failed)"; return 1; fi
  if [ "$REQUIRE" = "1" ] && [ "$unverified" != "0" ]; then echo "RESULT: FAIL (unverified under --require/CI)"; return 1; fi
  # BEFORE the $failed branch, and that ORDER is the whole mechanism. ⚠️ NOT because MISCONFIGURED
  # increments $failed — it does NOT. The reason is CO-OCCURRENCE: with a MISCONFIGURED row AND any
  # failing doc-check, a $failed-first ordering prints "advisory, non-blocking" and returns 0 — a
  # FAIL-always class downgraded by an unrelated advisory failure. The selftest drives exactly that
  # pair (misconfigured=1, failed=1); a failed=0 fixture cannot tell the two orderings apart.
  if [ "$misconfigured" != "0" ]; then
    echo "RESULT: FAIL ($misconfigured check row(s) MISCONFIGURED — a child answered with its own usage text, so verify.sh's registry invoked it wrong. The row proved nothing; fix the row.)"; return 1
  fi
  if [ "$failed" != "0" ]; then
    echo "RESULT: OK (controls verified; $failed doc-check(s) FAILED, shown above — advisory, non-blocking)"; return 0
  fi
  echo "RESULT: OK (controls verified; docs present)"; return 0
}

if [ "${1:-}" = "--selftest" ]; then
  # deterministic: the aggregate renders its classification + honesty footer, and a
  # control failure is surfaced. We exercise the renderer, not live infra.
  # $_SELF, not $0: after the top-level cd, a relative $0 no longer resolves. VERIFY_SKIP_PREFLIGHT
  # because THIS nested run is the renderer probe — on a HEAD-less checkout the pre-flight would
  # refuse it in a second and every leg below would grade an empty string (review R2). The pre-flight
  # LANE stays proven: its dedicated leg further down runs a real --require WITHOUT this variable.
  out=$(VERIFY_SKIP_PREFLIGHT=1 sh "$_SELF" 2>&1) || true
  printf '%s\n' "$out" | grep -q "control-checks" || { echo "verify --selftest: FAIL (no summary)"; exit 1; }
  printf '%s\n' "$out" | grep -q "UNVERIFIED is NOT a pass" || { echo "verify --selftest: FAIL (no honesty footer)"; exit 1; }
  printf '%s\n' "$out" | grep -Eq '\[control\]|\[doc\]' || { echo "verify --selftest: FAIL (no classification)"; exit 1; }
  # non-vacuous: at least one [control] must actually PASS — a render of only FAILs (green-while-dark)
  # must NOT satisfy --selftest. The synthetic line below proves the control-PASS grep is load-bearing.
  printf '%s\n' "$out" | grep -q '\[control\] .* PASS' || { echo "verify --selftest: FAIL (no [control] PASS — vacuous render)"; exit 1; }
  if printf '  [control] x                FAIL\n' | grep -q '\[control\] .* PASS'; then echo "verify --selftest: FAIL (vacuous fixture wrongly matched control-PASS)"; exit 1; fi

  # -- C6 COUNT leg: the Summary's `n/a` field must EQUAL the N-A rows the run actually rendered -------
  # "Rendered AND COUNTED" is half the C6 claim, and until now NOTHING in this file asserted a count —
  # every leg graded tokens. Reuses the aggregate already captured above (no extra run). Both directions
  # are load-bearing: a mutant that renders N-A without `nas++` under-counts and dies here; one that
  # increments without rendering over-counts and dies here; and the >0 floor stops the equality going
  # vacuous on a hypothetical tree where nothing skips (the kit tree measured ≥14 at C6).
  _c6rows=$(printf '%s\n' "$out" | grep -Ec '^  \[(control|doc)\] .* N-A$') || true
  _c6na=$(printf '%s\n' "$out" | grep '^Summary:' | sed -n 's/.*· \([0-9][0-9]*\) n\/a ·.*/\1/p')
  case "${_c6na:-x}" in ''|*[!0-9]*)
    echo "verify --selftest: FAIL (the Summary line carries no parseable n/a field — the third outcome is"
    echo "  rendered but not counted, which is the half of the C6 claim nothing used to assert)"; exit 1 ;;
  esac
  if [ "$_c6rows" -eq 0 ]; then
    echo "verify --selftest: FAIL (the aggregate rendered ZERO N-A rows — either every check really executed"
    echo "  (then this leg is vacuous and the floor must be re-measured) or the skip classifier is dead)"; exit 1
  fi
  if [ "$_c6na" != "$_c6rows" ]; then
    echo "verify --selftest: FAIL (Summary says $_c6na n/a but $_c6rows N-A row(s) were rendered — the count and"
    echo "  the render disagree, so one of them is lying about how much the run actually verified)"; exit 1
  fi

  # -- SIBLING-LINE leg (PR 10, VERIFY-HEADLINE-TRUTH): the census reconciliation-of-record ------------
  # The `Summary:` scalar is parsed by the C6 leg above AND by three ci.yml walk steps, verify.sh:255 and
  # promotion-readiness.sh:407 — every one of them anchors `^Summary:` and reads the match as ONE line.
  # So the census sibling must NOT begin with that token: a second `^Summary:` match turns those scalars
  # multi-line and their sed reads garbage. BOTH halves are pinned, and both were watched RED: exactly
  # one `^Summary:` line exists, and the `Scripts:` sibling is present with all four populations.
  _sibn=$(printf '%s\n' "$out" | grep -c '^Summary:') || true
  if [ "$_sibn" != 1 ]; then
    echo "verify --selftest: FAIL (the run emitted $_sibn line(s) beginning 'Summary:', want exactly 1 —"
    echo "  every consumer of that scalar anchors ^Summary: and reads one line; a second match makes"
    echo "  their sed parse a multi-line string, which is how the n/a walk goes silently wrong)"; exit 1
  fi
  printf '%s\n' "$out" | grep -qE '^Scripts: [0-9]+ unique conformance scripts across [0-9]+ rows \([0-9]+ conformance/\*\.sh on disk; [0-9]+ registered by no row' || {
    echo "verify --selftest: FAIL (no 'Scripts:' census sibling line — the run states how many ROWS it"
    echo "  holds but not how many SCRIPTS they invoke, which is the unreconciled count verify.sh:579"
    echo "  used to answer with 'three methods, three answers')"; exit 1; }

  # ── INCOMPLETE leg (K16) — an INTERRUPTED run must SAY it was interrupted and exit non-zero ──────────
  # WHY THIS EXISTS. The aggregate takes minutes over well over a hundred checks (see the header: the
  # authoritative count is the run's own Summary line, never a figure copied into prose) — longer than the default foreground
  # command cap of the agent harnesses people drive this kit with. In CP-7 run 4 a wrapper stopped
  # reading at ~43s of output and the run was read as an unexplained stall; with no trap, a killed run's
  # partial output is INDISTINGUISHABLE from a run still in progress, so the consumer must notice an
  # ABSENCE. That is the weakest possible signal, and it is how a truncated run gets mistaken for a
  # green one. `INCOMPLETE is not a pass` is the second honesty class beside `UNVERIFIED is not a pass`.
  #
  # BEHAVIOURAL, never a text grep for `trap` — presence is not effect. This launches a REAL run, kills
  # it mid-flight with SIGTERM, and asserts on what the process actually emitted and returned.
  _kout=$(mktemp) || { echo "verify --selftest: FAIL (no tmpdir for the INCOMPLETE leg)"; exit 1; }
  VERIFY_SKIP_PREFLIGHT=1 sh "$_SELF" > "$_kout" 2>&1 &   # same reason as the renderer probe above:
                                                          # this leg needs a LONG run to kill mid-flight
  _kpid=$!
  sleep 2                      # let it start and clear at least one check; the trap fires regardless
  kill -TERM "$_kpid" 2>/dev/null || true
  if wait "$_kpid"; then _krc=0; else _krc=$?; fi
  if ! grep -q 'RESULT: FAIL (INCOMPLETE' "$_kout"; then
    echo "verify --selftest: FAIL (a SIGTERM-killed run did not announce INCOMPLETE — a truncated run is"
    echo "  indistinguishable from a passing one; the consumer would have to notice an ABSENCE)"
    rm -f "$_kout"; exit 1
  fi
  # Load-bearing: announcing INCOMPLETE while exiting 0 would be worse than silence — a caller checking
  # only the exit status would score a truncated run as GREEN.
  if [ "$_krc" = 0 ]; then
    echo "verify --selftest: FAIL (interrupted run exited 0 — a truncated run must never score as a pass)"
    rm -f "$_kout"; exit 1
  fi
  rm -f "$_kout"


  # -- K3 leg: a FAILING gate must print WHY, not just FAIL -----------------------------------------
  # This block now sits AFTER the function definitions precisely so it can drive the REAL check() and
  # emit_diag(), not a replica. Testing a copy of the logic is the classic way a green proves nothing
  # about the shipped path.
  _d=$(mktemp -d) || { echo "verify --selftest: FAIL (no tmpdir for the K3 leg)"; exit 1; }
  printf '#!/bin/sh\necho "K3-DIAGNOSTIC-MARKER: /some/path:42"\nexit 1\n' > "$_d/failing.sh"
  _k3=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0
         check control k3demo sh "$_d/failing.sh" 2>&1 )
  rm -f "$_d/failing.sh"; rmdir "$_d" 2>/dev/null || true
  printf '%s\n' "$_k3" | grep -q 'K3-DIAGNOSTIC-MARKER' || {
    echo "verify --selftest: FAIL (a failing check hid its diagnostic -- the operator must re-run the"
    echo "  individual gate to learn what broke, which is the K3 round trip this gate exists to remove)"
    exit 1; }
  # Load-bearing the other way: a PASSING check must stay ONE line, or every green run drowns in output.
  _k3p=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0
          check control k3ok true 2>&1 )
  [ "$(printf '%s\n' "$_k3p" | grep -c .)" = 1 ] || {
    echo "verify --selftest: FAIL (a PASSING check emitted more than one line -- the aggregate must stay scannable)"
    exit 1; }

  # -- CP7R5-VERIFY-NONTS leg: a --kitself check N/As on an adopter tree, RUNS on the kit tree ----------
  # A kit-self check (validates the kit's OWN reference profiles / dev selftests) has no meaning on an
  # already-incepted ADOPTER tree, where incept has pruned the fixtures it needs (e.g. ci-gates hardcodes
  # profiles/typescript-node/ci.yml; adopter-preflight's selftest reads the pruned .nvmrc). The --kitself
  # flag renders N-A there -- keyed on the un-spoofable kit-marker set (BOTH docs/ROADMAP-KIT.md AND
  # .github/workflows/golden-path.yml absent == an adopter export) -- and must ACTUALLY RUN in the kit repo.
  # Both halves are load-bearing: without N-A a non-ts adopter's first verify.sh --require is red; without
  # RUN an always-N-A mutant masks a genuinely-broken kit-self reference on the kit tree. Drives the REAL
  # check() in a counter-reset subshell (mirrors the K3 leg), never a replica.
  _kna=$( cd "$(mktemp -d)" || exit 1        # a marker-less cwd == an adopter export
          controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
          check control kitdemo --kitself false 2>&1 )
  printf '%s\n' "$_kna" | grep -q 'kitdemo .* N-A' || {
    echo "verify --selftest: FAIL (a --kitself check did not render N-A on a marker-less adopter tree --"
    echo "  a non-ts adopter's first verify.sh --require would be red on a kit-self check)"; exit 1; }
  if printf '%s\n' "$_kna" | grep -q 'FAIL'; then
    echo "verify --selftest: FAIL (a --kitself check RAN its command on a marker-less tree instead of N-A)"; exit 1
  fi
  # Load-bearing negative: in the kit repo (markers present) --kitself must NOT suppress the check -- a
  # `false` command FAILs. An always-N-A mutant renders N-A here and dies on this assertion.
  _krun=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
           check control kitdemo --kitself false 2>&1 )
  printf '%s\n' "$_krun" | grep -q 'kitdemo .* FAIL' || {
    echo "verify --selftest: FAIL (a --kitself check did not RUN on the kit tree -- an always-N-A guard would"
    echo "  mask a genuinely-broken kit-self reference; markers present must mean the check executes)"; exit 1; }

  # -- ADOPTER-GATES-INERT (A3) leg: --adopter is METADATA-ONLY -- it RUNS the command, never skips it,
  # even on a marker-less (adopter) tree, and it is mutually exclusive with --kitself ------------------
  # The whole point of the new flag is that a row whose SUBJECT is the adopter's own artifact must keep
  # RUNNING post-inception -- --kitself's registry-level skip would silence it forever, which is exactly
  # the A3 defect (roadmap-current et al.). So the load-bearing assertion is the NEGATIVE: on a
  # marker-less cwd, --kitself would render N-A without invoking the command at all; --adopter must NOT.
  _adna=$( cd "$(mktemp -d)" || exit 1       # a marker-less cwd == an adopter export
           controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
           check control addemo --adopter false 2>&1 )
  printf '%s\n' "$_adna" | grep -q 'addemo .* FAIL' || {
    echo "verify --selftest: FAIL (a --adopter check did NOT run its command on a marker-less (adopter) tree --"
    echo "  --adopter must be metadata-only, never a --kitself-style skip, or a real adopter-subject gate goes"
    echo "  permanently silent)"; exit 1; }
  # And it must run in the kit repo too (no accidental new skip path on the kit tree either).
  _adkit=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
            check control addemo2 --adopter true 2>&1 )
  printf '%s\n' "$_adkit" | grep -q 'addemo2 .* PASS' || {
    echo "verify --selftest: FAIL (a --adopter check did not run+PASS on the kit tree)"; exit 1; }
  # MUTUAL EXCLUSION: a row declaring BOTH flags is a registry error, either order, and must not silently
  # pick one.
  if ( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
       check control admix --kitself --adopter true ) >/dev/null 2>&1; then
    echo "verify --selftest: FAIL (a check registering BOTH --kitself and --adopter did not error -- they"
    echo "  must be mutually exclusive)"; exit 1
  fi
  if ( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
       check control admix2 --adopter --kitself true ) >/dev/null 2>&1; then
    echo "verify --selftest: FAIL (a check registering --adopter then --kitself did not error -- the"
    echo "  mutual-exclusion check must not depend on flag order)"; exit 1
  fi

  # -- CP7R5-VERIFY-SUMMARY leg: the RESULT sentence must be honest about failing doc-checks -----------
  # A run with a failing doc-check must NOT print "docs present"; a fully-green run must keep it. Drives
  # the REAL result_sentence() with synthetic counters -- no full aggregate. Both halves are load-bearing:
  # the first kills a mutant that keeps "docs present" over a failure; the second kills one that always
  # cries "FAILED". Exit semantics are UNCHANGED (a doc-only failure still returns 0) -- this is wording.
  _rsf=$( ctrl_fail=0; unverified=0; failed=1; REQUIRE=0; result_sentence )
  printf '%s\n' "$_rsf" | grep -q 'doc-check(s) FAILED' || {
    echo "verify --selftest: FAIL (a failing doc-check did not surface in the RESULT sentence)"; exit 1; }
  if printf '%s\n' "$_rsf" | grep -q 'docs present'; then
    echo "verify --selftest: FAIL (RESULT claimed 'docs present' while a doc-check FAILED -- the summary lied)"; exit 1
  fi
  _rsok=$( ctrl_fail=0; unverified=0; failed=0; REQUIRE=0; result_sentence )
  printf '%s\n' "$_rsok" | grep -q 'docs present' || {
    echo "verify --selftest: FAIL (a fully-green run lost its 'docs present' summary)"; exit 1; }
  # Pins the JOINT predicate: N-A requires BOTH markers absent (`&&`). A MIXED tree (exactly one marker
  # present) must RUN -- so an `&&`->`||` mutation, which would N-A a mixed tree, dies here. This is the only
  # leg that constructs a one-marker tree; without it the conjunction is untested (both other legs use
  # all-absent / all-present trees, on which `&&` and `||` agree).
  _kmix=$( _md=$(mktemp -d) && mkdir -p "$_md/docs" && : > "$_md/docs/ROADMAP-KIT.md" && cd "$_md" || exit 1
           controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
           check control kitdemo --kitself false 2>&1 )
  printf '%s\n' "$_kmix" | grep -q 'kitdemo .* FAIL' || {
    echo "verify --selftest: FAIL (a --kitself check N-A'd a MIXED-marker tree -- N-A must require BOTH kit"
    echo "  markers absent; one present means run. An && -> || regression would mis-N-A here)"; exit 1; }

  # -- C6 NEVER-OK leg: a check that DID NOT VERIFY must render N-A, never PASS ------------------------
  # The row's own acceptance criterion. Fixture-driven against the REAL check() (a counter-reset subshell,
  # mirroring the K3/--kitself legs), never a replica — a copy of the logic is the classic way a green
  # proves nothing about the shipped path. Zero additional full aggregates.
  _d6=$(mktemp -d) || { echo "verify --selftest: FAIL (no tmpdir for the C6 leg)"; exit 1; }
  printf '#!/bin/sh\necho "N/A: no data surface here — skipping"\nexit 0\n' > "$_d6/skipper.sh"
  _c6skip=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
             check control c6skip sh "$_d6/skipper.sh" 2>&1 )
  rm -f "$_d6/skipper.sh"; rmdir "$_d6" 2>/dev/null || true
  printf '%s\n' "$_c6skip" | grep -q 'c6skip .* N-A' || {
    echo "verify --selftest: FAIL (a check that exited 0 saying it verified NOTHING did not render N-A —"
    echo "  a self-declared skip is being reported with the same token as an executed proof, which is"
    echo "  exactly how a green aggregate over-claims: it counts non-verification as verification)"; exit 1; }
  # LOAD-BEARING NEGATIVE (the anti-vacuity pair's second half): the skipped row must not satisfy the
  # control-PASS grep this file's own non-vacuity leg (above) relies on. Without this, a render that
  # printed BOTH tokens, or an N-A that still read as PASS to every downstream grep, would pass silently.
  if printf '%s\n' "$_c6skip" | grep -q '\[control\] .* PASS'; then
    echo "verify --selftest: FAIL (a self-skipped check still matched the control-PASS grep — the N-A token"
    echo "  must REPLACE PASS, not accompany it, or every consumer still reads the skip as a proof)"; exit 1
  fi
  # POSITIVE ANCHOR: an executed proof must still render PASS. Kills the opposite mutant — an
  # always-N-A classifier, which would make the whole aggregate honest-looking and worthless.
  _c6ran=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
            check control c6ran sh -c 'echo "OK: really verified something"; exit 0' 2>&1 )
  printf '%s\n' "$_c6ran" | grep -q 'c6ran .* PASS' || {
    echo "verify --selftest: FAIL (an EXECUTED, passing check no longer renders PASS — an over-broad skip"
    echo "  classifier demotes real proofs to N-A, emptying the aggregate of every claim it makes)"; exit 1; }
  # ANCHOR leg: the skip idiom is matched at LINE START only. A check that is genuinely RUNNING prints
  # `N/A` mid-line as a matter of course — incept-first-run-green.sh renders `  [N/A]   <id>` per sub-gate
  # and a `… $NAS N/A, …` summary line while proving every gate. An unanchored classifier demotes those
  # real proofs; this fixture reproduces that exact shipped output shape and must still render PASS.
  _c6mid=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
            check control c6midline sh -c 'echo "  [N/A]   db-postgres — stateless fixture"; echo "  summary: 12 GREEN, 1 N/A, 0 MISCONFIGURED-RED"; exit 0' 2>&1 )
  printf '%s\n' "$_c6mid" | grep -q 'c6midline .* PASS' || {
    echo "verify --selftest: FAIL (a RUNNING check that merely mentions N/A mid-line was demoted to N-A —"
    echo "  the classifier lost its line anchor and now under-claims real proofs, e.g. every"
    echo "  incept-first-run-green row, whose per-gate render legitimately prints '  [N/A]  <id>')"; exit 1; }
  # PARTIAL-SKIP leg: a check that skips SOME items and VERIFIES the rest has verified something, so it
  # is a PASS. This fixture reproduces the two rows that falsified the design's one-conjunct predicate
  # at build time (image-supply and runtime-floor iterate the ten profiles, skip the few with no
  # Dockerfile / no declared floor, prove the rest, and sign off `… OK (7 profile(s) … checked; others
  # N/A)`). A one-conjunct mutant renders this N-A and dies here — which is the point: N-A must mean
  # NOTHING was verified, or the count stops meaning anything.
  _c6part=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
             check control c6partial sh -c 'echo "N/A (no Dockerfile): profiles/ml"; echo "OK profiles/go: supply chain present"; echo "container-supply-chain: OK (1 profile(s) checked; others N/A)"; exit 0' 2>&1 )
  printf '%s\n' "$_c6part" | grep -q 'c6partial .* PASS' || {
    echo "verify --selftest: FAIL (a check that skipped SOME items but PROVED others was rendered N-A —"
    echo "  it verified something, so N-A under-claims its own run. N-A is for a check that verified"
    echo "  NOTHING here; a partial skip beside a real verdict is a PASS)"; exit 1; }
  # AMENDED (VERIFY-SKIP-IDIOM-RESIDUAL, face ii) — the leg above pins "a partial skip beside a REAL
  # verdict stays PASS"; its unstated other half is that a ZERO-checked verdict is not a real one.
  # Same fixture, count 0: it must render N-A. Without the pair the ruling reads "any OK suppresses".
  _c6zero=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
             check control c6zero sh -c 'echo "N/A (no Dockerfile): profiles/ml"; echo "container-supply-chain: OK (0 profile(s) with a Dockerfile checked; others N/A)"; exit 0' 2>&1 )
  printf '%s\n' "$_c6zero" | grep -q 'c6zero .* N-A' || {
    echo "verify --selftest: FAIL (a verdict line self-reporting ZERO checked items still suppressed the"
    echo "  skip — 0-checked is being rendered with the same token as N-checked, so a check that iterated"
    echo "  an empty set signs off as a proof. That is face (ii) of VERIFY-SKIP-IDIOM-RESIDUAL)"; exit 1; }
  # THE KEY'S LOAD-BEARING NEGATIVE: `(0 ` appears on 37 conformance/*.sh lines that are NOT zero-count
  # verdicts. A loose key demotes each, and inflates the `na` the CI floor reads. Measured shapes, PASS.
  _c6col=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
            check control c6collide sh -c 'echo "N/A: one sub-surface skipped"; echo "OK: reconciled (0 foreign lines, 12 kept); In Review→PR (0 rows, empty); 0 SUPERSEDED-CITATION site(s) (0 occurrence(s))"; exit 0' 2>&1 )
  printf '%s\n' "$_c6col" | grep -q 'c6collide .* PASS' || {
    echo "verify --selftest: FAIL (a REAL verdict that merely contains '(0 ' was demoted to N-A — the"
    echo "  zero-count key lost its sentence shape and now under-claims every row reporting a zero of"
    echo "  something else, which also silently inflates the n/a the CI walks' floor is derived from)"; exit 1; }
  # THE SHIPPED IDIOMS, PINNED (canaries): a narrowed classifier reds here, not in the wild.
  for _idm in 'N/A: no data surface' 'N/A (no Dockerfile): profiles/ml' 'doc-markers: N/A — kit-self check (no marker)' 'SKIP: shellcheck not installed'; do
    _c6i=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
            check control c6idiom sh -c "echo \"$_idm\"; exit 0" 2>&1 )
    printf '%s\n' "$_c6i" | grep -q 'c6idiom .* N-A' || {
      echo "verify --selftest: FAIL (the shipped skip idiom \"$_idm\" no longer renders N-A — the"
      echo "  classifier narrowed, and every check using that idiom now signs off as an executed proof)"; exit 1; }
  done
  # AND THE DISCLOSED MISS, PINNED AS A MISS (conjunct 1's `^` anchor). An INDENTED skip renders PASS.
  # The anchor is load-bearing (36 rc-0 rows mention n/a mid-line and every one had really run), so
  # this is a CEILING, not a bug to widen — pinned so a future loosening is a deliberate, reviewed act.
  # The cure is the authoring rule in conformance/README.md, "Writing a check that skips".
  _c6ind=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
            check control c6indent sh -c 'echo "   N/A: indented skip — outside the column-0 idiom"; exit 0' 2>&1 )
  printf '%s\n' "$_c6ind" | grep -q 'c6indent .* PASS' || {
    echo "verify --selftest: FAIL (an INDENTED skip was classified — the line anchor was loosened. That"
    echo "  anchor keeps 36 genuinely-running rows from being demoted; widening it here is a decision"
    echo "  for a design gate, not a regex tweak. Authoring rule: conformance/README.md)"; exit 1; }

  # ── MISCONFIGURED legs (VERIFY-RC2-USAGE-OVERLOAD) — a wrong INVOCATION is not a missing CREDENTIAL —
  # Both fixtures exit 2. Only the one answering with ITS OWN basename's usage text is a registry bug,
  # and it must block WITHOUT --require; the other is the protected UNVERIFIED lane (the 15 genuine
  # cannot-verify paths), which must keep failing ONLY under --require. Run in $_d6's parent-style tmp
  # so the row names a real `conformance/<name>.sh` path — the key is taken from the ROW, not from $out.
  _dm=$(mktemp -d) || { echo "verify --selftest: FAIL (no tmpdir for the MISCONFIGURED legs)"; exit 1; }
  mkdir -p "$_dm/conformance"
  printf '#!/bin/sh\necho "usage: mcchild.sh [--flag]" >&2\nexit 2\n' > "$_dm/conformance/mcchild.sh"
  printf '#!/bin/sh\necho "cannot verify: no gh credentials here" >&2\nexit 2\n' > "$_dm/conformance/cvchild.sh"
  # THE ANCHOR'S LOAD-BEARING NEGATIVE: a row that correctly invokes ITS child, whose child in turn
  # shells out to a helper it mis-calls, BUBBLES the helper's usage text up. The registry row is fine;
  # a bare `^usage:` key would red it. Measured shape: ci-gates.sh:457.
  printf '#!/bin/sh\necho "usage: helper.sh <arg>" >&2\necho "nestchild: could not verify" >&2\nexit 2\n' > "$_dm/conformance/nestchild.sh"
  _mcu=$( cd "$_dm" || exit 1; controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0; misconfigured=0; REQUIRE=0
          check control mcusage sh conformance/mcchild.sh 2>&1; result_sentence || true )
  _mccv=$( cd "$_dm" || exit 1; controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0; misconfigured=0; REQUIRE=0
           check control mccv sh conformance/cvchild.sh 2>&1; result_sentence || true )
  _mcnest=$( cd "$_dm" || exit 1; controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0; misconfigured=0; REQUIRE=0
             check control mcnest sh conformance/nestchild.sh 2>&1 )
  rm -rf "$_dm"
  printf '%s\n' "$_mcnest" | grep -q 'mcnest .* UNVERIFIED' || {
    echo "verify --selftest: FAIL (a NESTED child's usage text, bubbled up through a correctly-invoked"
    echo "  row, was blamed on the row — the key lost its child-basename anchor and now reds honest rows)"; exit 1; }
  printf '%s\n' "$_mcu" | grep -q 'mcusage .* MISCONFIGURED' || {
    echo "verify --selftest: FAIL (a child answering with its OWN usage text rendered as an ordinary"
    echo "  UNVERIFIED — a row this file INVOKED WRONG is indistinguishable from one that could not run)"; exit 1; }
  printf '%s\n' "$_mcu" | grep -q 'RESULT: FAIL (1 check row(s) MISCONFIGURED' || {
    echo "verify --selftest: FAIL (a MISCONFIGURED row did not FAIL the run WITHOUT --require — the"
    echo "  result_sentence branch must sit BEFORE the \$failed one, or a FAIL-always class renders"
    echo "  'advisory, non-blocking' and returns 0, which is a broken row wearing a green)"; exit 1; }
  printf '%s\n' "$_mccv" | grep -q 'mccv .* UNVERIFIED' || {
    echo "verify --selftest: FAIL (a GENUINE cannot-verify rc-2 was reclassified — the usage key must be"
    echo "  anchored to the child's own basename, or the 15 credential-blocked rows all turn into FAILs)"; exit 1; }
  printf '%s\n' "$_mccv" | grep -q 'RESULT: OK' || {
    echo "verify --selftest: FAIL (an UNVERIFIED row blocked WITHOUT --require — the rc-2 lane's"
    echo "  --require-only semantics are the regression pin here, and they moved)"; exit 1; }
  # ── THE ORDERING LEG, and it needs failed >= 1 to mean anything ────────────────────────────────
  # The $_mcu fixture leaves failed=0, so both orderings agree on it and a reorder mutant SURVIVES
  # (measured, by both review seats). The discriminating input is the co-occurrence: one MISCONFIGURED
  # row beside one failing doc-check, which a $failed-first ordering renders "advisory, non-blocking"
  # at rc 0. Real result_sentence, synthetic counters; both the wording AND the rc are asserted.
  _mcord=$( ctrl_fail=0; unverified=0; failed=1; misconfigured=1; REQUIRE=0; result_sentence || true )
  ( ctrl_fail=0; unverified=0; failed=1; misconfigured=1; REQUIRE=0; result_sentence >/dev/null ) && _mcordrc=0 || _mcordrc=$?
  printf '%s\n' "$_mcord" | grep -q 'RESULT: FAIL (1 check row(s) MISCONFIGURED' || {
    echo "verify --selftest: FAIL (a MISCONFIGURED row BESIDE a failing doc-check did not FAIL — the"
    echo "  \$failed branch ran first and rendered 'advisory, non-blocking'. A FAIL-always class must"
    echo "  not be downgradable by an unrelated advisory failure; the MISCONFIGURED branch has to sit"
    echo "  BEFORE the \$failed one, and only a failed>=1 fixture can tell the two orderings apart)"; exit 1; }
  [ "$_mcordrc" = 1 ] || {
    echo "verify --selftest: FAIL (a MISCONFIGURED row beside a failing doc-check returned rc"
    echo "  $_mcordrc, not 1 — the wording said FAIL while the exit status said pass, which is the"
    echo "  worst of both: a run that reads red and grades green)"; exit 1; }

  # ── ADOPTER-KIT-SELFTESTS-ON-CHANGE legs K1-K4, K6, K7 — the --kitselftest skip is diff-gated and fails SAFE ──
  # Design: docs/architecture/2026-10-01-adopter-kit-selftests-on-change-design.md §3/§4/§7. A row flagged
  # `--kitselftest` (position 3) is skipped (renders N-A) ONLY when `--changed <listing>` names a readable,
  # NON-EMPTY listing whose class (the gates' own `promotion-readiness.sh --class --changed`) is not
  # control-plane. Everything else — no --changed, empty/unreadable listing, classifier failure, control-plane
  # class — runs the full battery. Time is spent, never coverage (D-240903-3).
  #
  # INTERFACE THE MECHANISM MUST HONOUR (test seams, both read from the environment):
  #   VERIFY_SELFTEST_REGISTRY=<file>  a file of `check ...` lines that verify.sh `.`-sources IN PLACE OF its
  #                                    built-in registry (everything else — option parse, classify-once, notice,
  #                                    --summary-file, footer — runs for real). Unset/empty = built-in registry.
  #   VERIFY_CLASSIFIER=<script>       run as `sh "$VERIFY_CLASSIFIER" --class --changed <listing>` instead of
  #                                    `sh conformance/promotion-readiness.sh --class --changed <listing>`; the
  #                                    answer is the LAST stdout line, and a NON-ZERO exit means "unknown" =>
  #                                    full run (even if it printed a class first). Unset/empty = the real one.
  # These drive the REAL option path end to end (a throwaway registry of two stub rows), never a replica.
  # Without the mechanism each leg would run the WHOLE real battery (minutes) once per leg, so the first
  # assertion checks the seams exist outside this selftest and names every leg it is withholding.
  _ksd=$(mktemp -d) || { echo "verify --selftest: FAIL (no tmpdir for the --kitselftest legs)"; exit 1; }
  _ks_die() { rm -rf "$_ksd"; echo "verify --selftest: FAIL ($1)"; shift; for _ksl in "$@"; do echo "  $_ksl"; done; exit 1; }
  _ks_out_of_selftest=$(sed '/^if \[ "\${1:-}" = "--selftest" \]/,/^fi$/d' "$_SELF")
  for _kst in VERIFY_SELFTEST_REGISTRY VERIFY_CLASSIFIER -- --kitselftest --changed --summary-file; do
    case "$_kst" in --) continue ;; esac
    printf '%s\n' "$_ks_out_of_selftest" | grep -qe "$_kst" || _ks_die "K1-K4/K7: the mechanism is absent — '$_kst' does not appear outside --selftest" \
      "legs K1 (guard-only runs everything), K2 (app-only skips as N-A + notice with 'kit v'), K3 (no --changed /" \
      "empty / unreadable listing / classifier exit!=0 => full run), K4 (renamed-away control-plane path => full run)" \
      "and K7 (--summary-file notice only on a skip) cannot run: ADOPTER-KIT-SELFTESTS-ON-CHANGE task 2 is unbuilt"
  done
  # stub check (prints a real verdict, so is_self_skip never reclassifies it) + the two-row throwaway registry
  printf '#!/bin/sh\necho "OK: stub verified"\nexit 0\n' > "$_ksd/pass.sh"
  printf '%s\n' "check control kst-marked --kitselftest sh $_ksd/pass.sh" "check control kst-plain sh $_ksd/pass.sh" > "$_ksd/registry.sh"
  # classifier stubs: `ordinary` + exit 3 (a mechanism that ignores the exit status would SKIP — the leg must catch it)
  printf '#!/bin/sh\necho ordinary\nexit 3\n' > "$_ksd/failclass.sh"
  # _ks_run <classifier-or-empty> [verify.sh args...] -> the run's combined output (rc deliberately ignored:
  # the footer of a two-row registry is not under test). Classifier passed positionally, not as a prefix
  # assignment, so nothing persists after a function call on any shell.
  _ks_run() {
    _ksc=$1; shift
    # `env -u CI -u GITHUB_ACTIONS`: the seams are REFUSED under CI, and this selftest itself runs in CI.
    env -u CI -u GITHUB_ACTIONS VERIFY_SKIP_PREFLIGHT=1 VERIFY_SELFTEST_REGISTRY="$_ksd/registry.sh" VERIFY_CLASSIFIER="$_ksc" sh "$_SELF" "$@" 2>&1 || true
  }
  # _ks_row <output> <row> <token> : 0 when the row line carries that token (PASS or N-A)
  _ks_row() { printf '%s\n' "$1" | grep -Eq "\\[control\\] +$2 +$3\$"; }
  _ks_noticelines() { printf '%s\n' "$1" | grep -c '^kit selftests not re-run:' || true; }
  # the REAL classifier, run from the repo root (this script cd'd there) against an absolute listing path
  _ks_class() { sh conformance/promotion-readiness.sh --class --changed "$1" 2>/dev/null | tail -1; }
  # _ks_full <label> <output> : the marked row RAN (PASS), no N-A on it, no skip notice — a FULL battery
  _ks_full() {
    _ks_row "$2" kst-marked PASS || _ks_die "$1: the --kitselftest row did not RUN to PASS — a skip fired where the full battery was required" "output was:" "$2"
    if _ks_row "$2" kst-marked 'N-A'; then _ks_die "$1: the --kitselftest row rendered N-A where the full battery was required"; fi
    _ks_row "$2" kst-plain PASS || _ks_die "$1: the plain row did not run to PASS" "output was:" "$2"
    [ "$(_ks_noticelines "$2")" = 0 ] || _ks_die "$1: a skip notice was printed although nothing was skipped"
  }

  # K1 — THE SECURITY PROPERTY: a listing naming only the guard (.claude/hooks/guard.sh) is control-plane by the
  # REAL classifier, so every --kitselftest row RUNS. Two-part: the classifier answer is pinned first, so the
  # leg cannot go green by a classifier drifting to `ordinary` AND the mechanism skipping together.
  printf '.claude/hooks/guard.sh\n' > "$_ksd/k1.list"
  [ "$(_ks_class "$_ksd/k1.list")" = control-plane ] || _ks_die "K1: the REAL classifier no longer calls .claude/hooks/guard.sh control-plane — the skip's whole safety premise (design §6) is gone"
  _ks_k1=$(_ks_run "" --changed "$_ksd/k1.list" --summary-file "$_ksd/k1.summary")
  _ks_full K1 "$_ks_k1"

  # K2 — an ordinary listing skips the marked row as N-A, leaves the plain row running, prints ONE notice
  # naming the skipped row and carrying the kit version. The REAL classifier again (pinned not control-plane).
  printf 'src/app.ts\n' > "$_ksd/k2.list"
  _ks_c2=$(_ks_class "$_ksd/k2.list")
  case "$_ks_c2" in ordinary|sensitive) ;; *) _ks_die "K2: the REAL classifier answered '$_ks_c2' for src/app.ts, not ordinary/sensitive — the leg would be vacuous" ;; esac
  _ks_k2=$(_ks_run "" --changed "$_ksd/k2.list" --summary-file "$_ksd/k2.summary")
  _ks_row "$_ks_k2" kst-marked 'N-A' || _ks_die "K2: an app-only listing did not render the --kitselftest row N-A" "output was:" "$_ks_k2"
  if _ks_row "$_ks_k2" kst-marked PASS; then _ks_die "K2: the skipped row ALSO rendered PASS — N-A must replace PASS, never accompany it"; fi
  _ks_row "$_ks_k2" kst-plain PASS || _ks_die "K2: a plain row in the same registry stopped running when a --kitselftest row was skipped" "output was:" "$_ks_k2"
  [ "$(_ks_noticelines "$_ks_k2")" = 1 ] || _ks_die "K2: want exactly ONE 'kit selftests not re-run:' notice line, got $(_ks_noticelines "$_ks_k2")" "output was:" "$_ks_k2"
  printf '%s\n' "$_ks_k2" | grep '^kit selftests not re-run:' | grep -q 'kit v' || _ks_die "K2: the notice does not carry the kit version ('kit v<ver>')"
  printf '%s\n' "$_ks_k2" | grep '^kit selftests not re-run:' | grep -q 'kst-marked' || _ks_die "K2: the notice does not name the skipped row (kst-marked)"

  # K3 — EVERY unknown costs time, never coverage: four legs, each must run the marked row in full.
  _ks_k3a=$(_ks_run "")                                              # (a) no --changed at all (the hand run)
  _ks_full "K3a (no --changed)" "$_ks_k3a"
  : > "$_ksd/k3.empty"                                               # (b) an EMPTY listing
  _ks_k3b=$(_ks_run "" --changed "$_ksd/k3.empty")
  _ks_full "K3b (empty listing)" "$_ks_k3b"
  _ks_k3c=$(_ks_run "" --changed "$_ksd/no-such-listing")            # (c) a NONEXISTENT listing path
  _ks_full "K3c (nonexistent listing)" "$_ks_k3c"
  _ks_k3d=$(_ks_run "$_ksd/failclass.sh" --changed "$_ksd/k2.list")  # (d) classifier exits non-zero (after printing `ordinary`)
  _ks_full "K3d (classifier exits non-zero)" "$_ks_k3d"
  # and the stub seam is itself live: the same stub class WITHOUT a failing exit must be able to skip (else K3d is vacuous)
  printf '#!/bin/sh\necho ordinary\nexit 0\n' > "$_ksd/okclass.sh"
  _ks_k3e=$(_ks_run "$_ksd/okclass.sh" --changed "$_ksd/k2.list")
  _ks_row "$_ks_k3e" kst-marked 'N-A' || _ks_die "K3: VERIFY_CLASSIFIER is not honoured (a stub answering 'ordinary', exit 0 did not skip) — leg K3d would be vacuous" "output was:" "$_ks_k3e"

  # SEAM leg (security) — the two test seams must NEVER produce a verdict. A seam run whose rows all PASS must
  # still print the loud stderr banner, end with an UNVERIFIED RESULT, and exit 2; both seams are checked.
  # The registry seam is always on (the real registry would run for minutes); pass 1 adds nothing, pass 2 also
  # sets the classifier seam, whose banner must then be named too.
  printf '#!/bin/sh\necho control-plane\nexit 0\n' > "$_ksd/cpclass.sh"
  for _kss in VERIFY_SELFTEST_REGISTRY VERIFY_CLASSIFIER; do
    if [ "$_kss" = VERIFY_CLASSIFIER ]; then _ks_sv_cls="$_ksd/cpclass.sh"; else _ks_sv_cls=""; fi
    if _ks_sout=$(env -u CI -u GITHUB_ACTIONS VERIFY_SKIP_PREFLIGHT=1 VERIFY_SELFTEST_REGISTRY="$_ksd/registry.sh" VERIFY_CLASSIFIER="$_ks_sv_cls" sh "$_SELF" --changed "$_ksd/k1.list" 2>&1); then _ks_srcode=0; else _ks_srcode=$?; fi
    _ks_row "$_ks_sout" kst-marked PASS || _ks_die "SEAM($_kss): the all-PASS stub registry did not run (leg vacuous)" "output was:" "$_ks_sout"
    [ "$_ks_srcode" = 2 ] || _ks_die "SEAM($_kss): a test-seam run that would otherwise be all-PASS exited $_ks_srcode, not 2 — an env var could forge a green"
    printf '%s\n' "$_ks_sout" | grep -q "verify: TEST SEAM ACTIVE ($_kss) — this run is NOT a verdict" || _ks_die "SEAM($_kss): no loud 'TEST SEAM ACTIVE ($_kss)' banner"
    printf '%s\n' "$_ks_sout" | grep -q '^RESULT: UNVERIFIED (TEST SEAM ACTIVE' || _ks_die "SEAM($_kss): the summary does not say UNVERIFIED / TEST SEAM ACTIVE"
  done

  # SEAM-UNDER-CI leg — a seam under CI=true (or GITHUB_ACTIONS) is REFUSED: exit 2, the refusal, and NO row output.
  for _kci in CI GITHUB_ACTIONS; do
    if _ks_cout=$(env -u CI -u GITHUB_ACTIONS "$_kci=true" VERIFY_SKIP_PREFLIGHT=1 VERIFY_SELFTEST_REGISTRY="$_ksd/registry.sh" sh "$_SELF" --changed "$_ksd/k2.list" 2>&1); then _ks_crc=0; else _ks_crc=$?; fi
    [ "$_ks_crc" = 2 ] || _ks_die "SEAM-CI($_kci): a seam under $_kci=true exited $_ks_crc, not 2 (refused)"
    printf '%s\n' "$_ks_cout" | grep -q '^verify: REFUSED' || _ks_die "SEAM-CI($_kci): no 'verify: REFUSED' message" "output was:" "$_ks_cout"
    if _ks_row "$_ks_cout" kst-marked PASS || _ks_row "$_ks_cout" kst-marked 'N-A'; then _ks_die "SEAM-CI($_kci): rows ran although the seam must be refused before anything else"; fi
  done

  # K1b / K1c / floor legs — the LITERAL FORCED-FULL FLOOR (S1/R2/R5/R7). Each listing is paired with a classifier
  # stub answering `ordinary`, exit 0, so ONLY the floor can force the full run (the stub's skip power is proven by
  # K3e above). K1b: an unnamed .kit/ conf (agent-autonomy's on-disk leg). K1c: the guard itself, with the classifier
  # declassifying it (a PR that broke _cpp_match). Then a .shellcheckrc, a case-folded .GITHUB/ path, and a CRLF listing.
  _ks_floor() {  # <label> <listing-bytes-printf-format>
    printf "$2" > "$_ksd/floor.list"
    _ks_full "$1" "$(_ks_run "$_ksd/okclass.sh" --changed "$_ksd/floor.list")"
  }
  _ks_floor K1b '.kit/newthing.conf\n'
  _ks_floor K1c '.claude/hooks/guard-core.sh\n'
  _ks_floor 'floor(.shellcheckrc)' 'src/.shellcheckrc\n'
  _ks_floor 'floor(.GITHUB case-fold)' '.GITHUB/x\n'
  _ks_floor 'floor(CRLF listing)' 'src/app.ts\r\n'
  # S7: a non-ASCII byte forces the full battery (Unicode fold evasion: long-s U+017F = UTF-8 \305\277 aliasing `scripts/`).
  _ks_floor 'floor(S7 non-ASCII long-s)' '\305\277cripts/x.sh\n'
  # S6: a floor ERROR is a full run, not "no hit". There is no awk seam, so a stub `awk` that fails is put FIRST on PATH for the
  # child only; with the classifier stubbed `ordinary` a fail-open floor would skip, a fail-closed one runs the full battery.
  mkdir -p "$_ksd/failbin"; printf '#!/bin/sh\nexit 2\n' > "$_ksd/failbin/awk"; chmod +x "$_ksd/failbin/awk"
  printf 'src/app.ts\n' > "$_ksd/floor.list"
  _ks_oldpath=$PATH; PATH="$_ksd/failbin:$PATH"
  _ks_s6=$(_ks_run "$_ksd/okclass.sh" --changed "$_ksd/floor.list")
  PATH=$_ks_oldpath
  _ks_full "S6 (floor awk fails => full run)" "$_ks_s6"

  # K4 — a control-plane path RENAMED AWAY (git diff --no-renames lists old AND new): the old path alone
  # keeps the class control-plane, so the full battery runs. REAL classifier, two-line listing.
  printf 'scripts/old-name.sh\nsrc/new-name.ts\n' > "$_ksd/k4.list"
  [ "$(_ks_class "$_ksd/k4.list")" = control-plane ] || _ks_die "K4: the REAL classifier did not call a listing containing scripts/old-name.sh control-plane"
  _ks_k4=$(_ks_run "" --changed "$_ksd/k4.list")
  _ks_full "K4 (renamed-away control-plane path)" "$_ks_k4"

  # K7 — --summary-file receives the notice when rows were skipped (K2's run), and NOTHING when none were (K1's).
  [ -s "$_ksd/k2.summary" ] || _ks_die "K7: --summary-file stayed empty although a row was skipped — the notice never reached the run page"
  grep -q '^kit selftests not re-run:' "$_ksd/k2.summary" || _ks_die "K7: the --summary-file content is not the skip notice"
  grep -q 'kit v' "$_ksd/k2.summary" || _ks_die "K7: the --summary-file notice lacks the kit version"
  [ ! -s "$_ksd/k1.summary" ] || _ks_die "K7: --summary-file was written although NO row was skipped (guard-only listing)"

  # K6 — LAST (it reds until the marker rows are applied, plan task 3): the REAL registry carries at least one
  # --kitselftest row, and agent-autonomy's is one of them. Read off this file's own `^check` rows, the same
  # single source the census reads; the fixtures above are printf strings, so they cannot satisfy these greps.
  _ks_nrows=$(grep -Ec '^check +[a-z]+ +[A-Za-z0-9_.-]+ +--kitselftest( |$)' "$_SELF") || true
  [ "${_ks_nrows:-0}" -ge 1 ] || _ks_die "K6: the registry has NO --kitselftest row — the marker set is empty, so --changed can skip nothing"
  grep -Eq '^check +control +agent-autonomy +--kitselftest( |$)' "$_SELF" || _ks_die "K6: the agent-autonomy row does not carry --kitselftest — the 532 s row the whole change exists to skip"
  rm -rf "$_ksd"

  # ── PRE-FLIGHT leg (B3) — a HEAD-less tree must fail FAST and name the TRUE cause ─────────────────
  # Behavioural: a real no-commit repo + this very script; asserts exit status, wording AND the clock.
  # The fixture is a whole git repo, so it is trap-cleaned (review R1): the earlier inline `rmdir` left
  # a .git behind on every run, and on an early `exit 1` it never ran at all.
  #
  # _vs_preflight_fired <text> : 0 when <text> contains the PRE-FLIGHT'S OWN refusal, ANCHORED to the
  # start of a line (SANITIZER-UNSET-RESTORES-EXPORTED, defect 2). The old probes grepped the bare
  # phrase `no commits yet`, which a FAILING CHILD'S SURFACED DIAGNOSTIC can carry — inception-done.sh
  # prints a leg header `--- (b9) tracked mode, unborn HEAD (no commits yet) ---` — so an unrelated
  # child failure was reported as "the pre-flight fired on a tree WITH history", a false attribution
  # that sends the reader to the wrong file. Both probes below go through this one matcher so the
  # negative and the positive can never drift apart.
  _vs_preflight_fired() {
    printf '%s\n' "$1" | grep -q '^verify: this repository has no commits yet'
  }

  # selftest_preflight_anchor: the anchor is load-bearing in BOTH directions — a child's prose that
  # merely MENTIONS the phrase must not match, and the pre-flight's real sentence must.
  selftest_preflight_anchor() {
    _pa_child='--- (b9) tracked mode, unborn HEAD (no commits yet) ---'
    _pa_real='verify: this repository has no commits yet — commit the incepted baseline first (git add -A && git commit -m "chore: incept baseline"), then re-run. Nothing below can be evaluated against an empty history.'
    if _vs_preflight_fired "$_pa_child"; then
      echo "verify --selftest: FAIL (the pre-flight probe matched a CHILD'S prose — '(no commits yet)' in a surfaced diagnostic would again be read as the pre-flight firing)"; exit 1
    fi
    if ! _vs_preflight_fired "$_pa_real"; then
      echo "verify --selftest: FAIL (the pre-flight probe no longer matches the pre-flight's OWN sentence — the leg below would be vacuous)"; exit 1
    fi
  }
  selftest_preflight_anchor

  _b3=$(mktemp -d) || { echo "verify --selftest: FAIL (no tmpdir for the pre-flight leg)"; exit 1; }
  trap 'rm -rf "$_b3"' EXIT
  mkdir -p "$_b3/conformance"; cp "$_SELF" "$_b3/conformance/verify.sh"
  ( cd "$_b3" && git init -q . 2>/dev/null ) || true; _b3st=$(date +%s)
  if _b3out=$(sh "$_b3/conformance/verify.sh" --require 2>&1); then _b3rc=0; else _b3rc=$?; fi
  _b3el=$(( $(date +%s) - _b3st ))
  [ "$_b3rc" = 0 ] && { echo "verify --selftest: FAIL (a repo with NO COMMITS exited 0 — an empty history cannot be evaluated, so that green is green-while-dark)"; exit 1; }
  _vs_preflight_fired "$_b3out" || { echo "verify --selftest: FAIL (a HEAD-less tree did not name the true cause — the adopter is sent to 'recopy the kit tree' when all that is missing is the first commit)"; exit 1; }
  [ "$_b3el" -gt 10 ] && { echo "verify --selftest: FAIL (a HEAD-less tree took ${_b3el}s to fail — the pre-flight must precede the battery)"; exit 1; }
  # Load-bearing the other way: it must NOT fire on a tree that HAS a commit (the aggregate above).
  _vs_preflight_fired "$out" && { echo "verify --selftest: FAIL (the pre-flight fired on a tree WITH history — it would block every real run)"; exit 1; } || true

  echo "verify --selftest: OK (renderer + honesty footer + non-vacuous control-PASS + INCOMPLETE-on-interrupt"
  echo "                       + K3: a FAILING check surfaces its diagnostic, a PASSING one stays one line"
  echo "                       + --kitself N-A/RUNS/mixed + VERIFY-SUMMARY: no 'docs present' over a doc-fail"
  echo "                       + C6: a self-declared skip renders N-A not PASS, an executed proof keeps PASS,"
  echo "                         a mid-line N/A mention and a PARTIAL skip beside a real verdict both stay"
  echo "                         PASS, and the Summary n/a count equals the N-A rows rendered)"
  echo "                       + ZERO-COUNT: a verdict reporting 0 checked items renders N-A, while a real"
  echo "                         verdict merely containing '(0 ' stays PASS; the three shipped skip idioms"
  echo "                         are pinned as canaries and the INDENTED-skip miss is pinned as a ceiling"
  echo "                       + MISCONFIGURED: a child answering with its OWN basename's usage text is a"
  echo "                         registry wiring bug and FAILS without --require, while a genuine"
  echo "                         cannot-verify rc 2 stays UNVERIFIED and blocks only under --require"
  echo "                       + KSOC K1-K4/K6/K7: --kitselftest rows skip (N-A + notice + --summary-file) only on a"
  echo "                         readable non-empty non-control-plane --changed listing; the guard, a renamed-away"
  echo "                         control-plane path, no/empty/unreadable listing and a failing classifier all run full"
  echo "                       + PRE-FLIGHT: NO COMMITS fails in seconds naming the missing first"
  echo "                         commit, and stays silent on a tree that has history — both probes"
  echo "                         ANCHORED to the pre-flight's OWN sentence, so a failing child's prose"
  echo "                         mentioning '(no commits yet)' is never read as the pre-flight firing)"; exit 0
fi

# ── PRE-FLIGHT: an EMPTY HISTORY is not a conformance failure, it is a missing first commit ─────────
# MEASURED (B3, KIT-EVAL-2): an adopter's first act after `incept` is `verify.sh --require`; on a
# not-yet-committed tree it ran the whole battery (384s) then said `guard-wired FAIL: tracked
# hooks/pre-push missing from HEAD — recopy the kit tree`: both halves wrong (nothing is missing; there
# is no HEAD). Sits immediately before the battery, AFTER the --selftest exit (review R1), so the
# selftest stays runnable from a HEAD-less checkout. VERIFY_SKIP_PREFLIGHT is set ONLY by the
# selftest's own renderer probe, which needs a full aggregate rather than this refusal; the dedicated
# pre-flight leg deliberately does NOT set it, so the lane below is still proven end-to-end.
if [ -z "${VERIFY_SKIP_PREFLIGHT:-}" ] && git rev-parse --git-dir >/dev/null 2>&1 && ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "verify: this repository has no commits yet — commit the incepted baseline first (git add -A && git commit -m \"chore: incept baseline\"), then re-run. Nothing below can be evaluated against an empty history."
  exit 1
fi

# ── TEST SEAMS NEVER PRODUCE A VERDICT (ADOPTER-KIT-SELFTESTS-ON-CHANGE, security). The two env seams the
# selftest drives (a replacement registry; a stub classifier) would, in a real CI run, let whoever sets an
# environment variable forge a green (empty registry) or a skip (stub class). So a run that uses either
# says so loudly on stderr and ends UNVERIFIED (exit 2) whatever the rows did — see the footer.
SEAM_ACTIVE=""
for _ks_seam in VERIFY_SELFTEST_REGISTRY VERIFY_CLASSIFIER; do
  eval "_ks_sv=\${$_ks_seam:-}"
  [ -n "$_ks_sv" ] || continue
  echo "verify: TEST SEAM ACTIVE ($_ks_seam) — this run is NOT a verdict" >&2
  SEAM_ACTIVE="$SEAM_ACTIVE${SEAM_ACTIVE:+, }$_ks_seam"
done
readonly SEAM_ACTIVE   # a sourced seam registry cannot clear the taint (an assignment to it aborts the run)

# ── --kitselftest skip decision: classify ONCE, before any row runs, failing toward the FULL battery ───
# Skip mode needs ALL of: a --changed listing that is a readable NON-EMPTY file; a classifier that exits 0;
# and an answer of `ordinary` or `sensitive` (the last stdout line). Anything else — including `control-plane`,
# an empty answer, or a token this file does not know — leaves SKIP_KS=0 and every row runs.
# THE LITERAL FORCED-FULL FLOOR (security S1 / reviewer R2, R5, R7). The classifier below runs the PR's OWN checked-out
# guard-core (promotion-readiness.sh sources .claude/hooks/guard-core.sh), so a PR that breaks `_cpp_match` would
# declassify ITSELF and earn its own skip. This floor therefore must NEVER depend on the classifier, the guard, or any
# other file a PR can edit: it is a literal path test over the listing, run BEFORE the classifier is even invoked. Each
# path is case-folded (a case-insensitive checkout resolves `.GITHUB/` to `.github/`) and stripped of a leading `./`, and
# ANY of these forces the full battery: `.claude/` (anywhere), `conformance/`, `scripts/`, `hooks/`, `adapters/`,
# `profiles/`, `.github/`, `.kit/` (agent-autonomy's on-disk leg enumerates `git ls-files '.kit/*.conf'`), a basename of
# `.gitattributes` / `.shellcheckrc` / `shellcheckrc` (shellcheck honours a repo rc), `docs/roadmap-kit.md` (a kit-marker
# latch), or ANY byte outside printable ASCII (S7: a CR, a tab, or a non-ASCII byte — a CR would defeat every match above, and
# a Unicode fold such as the Kelvin sign in `.Kit` or the long-s in `ſcripts` can alias a control-plane directory on a
# case-insensitive runner).
# FAIL-CLOSED (S6): _ks_floor_hit returns 3 ONLY when it positively examined the whole listing and found no floor path. EVERY
# other status — a hit (0), a failed mktemp/tr/awk, a missing tool, a signal — is a FULL run. The stages write temp files and
# are checked one by one, because a pipeline's status under `set -e` without pipefail is only its LAST stage.
_ks_floor_hit() {  # <listing> -> 3 = examined, no floor path (skip allowed); anything else = FULL battery
  _kf_t=$(mktemp) || return 0
  if _kf_odd=$(LC_ALL=C tr -d ' -~\n' < "$1"); then :; else rm -f "$_kf_t"; return 0; fi
  [ -z "$_kf_odd" ] || { rm -f "$_kf_t"; return 0; }
  if LC_ALL=C tr 'A-Z' 'a-z' < "$1" > "$_kf_t"; then :; else rm -f "$_kf_t"; return 0; fi
  if LC_ALL=C awk '
    { p = $0; sub(/^\.\//, "", p); n = p; sub(/.*\//, "", n) }
    p ~ /^\.claude\// || p ~ /\/\.claude\// { f = 1 }
    p ~ /^(conformance|scripts|hooks|adapters|profiles|\.github|\.kit)\// { f = 1 }
    n == ".gitattributes" || n == ".shellcheckrc" || n == "shellcheckrc" || p == "docs/roadmap-kit.md" { f = 1 }
    END { exit(f ? 0 : 3) }' "$_kf_t"; then _kf_rc=0; else _kf_rc=$?; fi
  rm -f "$_kf_t"
  return "$_kf_rc"
}
if [ -n "$KS_CHANGED" ] && [ -f "$KS_CHANGED" ] && [ -r "$KS_CHANGED" ] && [ -s "$KS_CHANGED" ]; then
  if _ks_floor_hit "$KS_CHANGED"; then _ks_fr=0; else _ks_fr=$?; fi
  if [ "$_ks_fr" != 3 ]; then
    :   # forced full (a floor hit OR a floor error): the classifier is not even consulted
  elif _ks_cls=$(env -u KIT_ADAPTERS_DIR -u KIT_UNION_LIB sh "${VERIFY_CLASSIFIER:-conformance/promotion-readiness.sh}" --class --changed "$KS_CHANGED" 2>/dev/null); then
    # (the two KIT_* env seams of the classifier are scrubbed, as loop-state.sh does: an env var cannot move a path out of the set)
    _ks_cls=$(printf '%s\n' "$_ks_cls" | tail -n 1)
    case "$_ks_cls" in ordinary|sensitive) SKIP_KS=1 ;; esac
  fi
fi

echo "Conformance verification (honest aggregate)"
echo "-------------------------------------------"
# branch-protection's OFFLINE leg only (B4) — declaration-integrity, no gh, no network; see the
# SCOPE note above for why the LIVE leg stays out of this aggregate.
# --adopter (ADOPTER-GATES-INERT A3): the subject is the ADOPTER'S OWN declared required-checks file —
# it correctly N/As on a pre-inception export (nothing declared yet) and ARMS once the adopter authors
# their own declaration; --kitself would silence a real adopter gate forever.
# TEST SEAM (selftest only; the run is forced UNVERIFIED in the footer): a replacement registry is sourced
# INSTEAD of the built-in rows below. The wrapper is deliberately UNINDENTED so every `check` row below still
# begins in column 0 (the census awk, the `Scripts:` reconciliation and the K6 leg all read them as text).
if [ -n "${VERIFY_SELFTEST_REGISTRY:-}" ]; then
  # shellcheck source=/dev/null  # a test-only seam resolved at runtime
  . "$VERIFY_SELFTEST_REGISTRY"
else
check control branch-protection-declared    --adopter sh conformance/branch-protection.sh --declared-only
check control branch-protection-selftest    sh conformance/branch-protection.sh --selftest
# --kitselftest (design §3 (a)+(b)): inputs are the guard (.claude/hooks/*), the named .kit/*.conf and conformance/ scripts it
# drives, plus its own temp fixtures. Residual (record in review): its `git ls-files '.kit/*.conf'` leg also sees an UNNAMED
# .kit/<x>.conf an adopter could add (not a control-plane path): closed by the .kit/ rule (any listed .kit/ path forces a full run).
check control agent-autonomy   --kitselftest sh conformance/agent-autonomy.sh
check control agent-boundary   sh conformance/agent-boundary.sh --selftest
check control hardlink-integrity          sh conformance/hardlink-integrity.sh
check control hardlink-integrity-selftest sh conformance/hardlink-integrity.sh --selftest
check control harness-adapter  sh conformance/harness-adapter.sh adapters/claude-code
check control harness-generic  sh conformance/harness-adapter.sh adapters/generic
check control harness-adapter-selftest sh conformance/harness-adapter.sh --selftest
# agents-brief carries the ENTRY-CONTRACT lock (§1 byte-identical in every adapter's declared
# contextFile). It ran only in CI and via harness-adapter's floor_holds, so `non-vacuity.sh --only
# agents-brief.sh` matched NO targeted check — the sweep selects from `^check control` rows here, and
# the lock that makes the whole entry-contract slice real therefore had ZERO mutation coverage.
# Registering it is what gives it teeth locally AND in the CI sweep.
check control agents-brief             sh conformance/agents-brief.sh
check control agents-brief-selftest     sh conformance/agents-brief.sh --selftest
# doc-budget carried the SAME zero-mutation-coverage gap: it runs in CI, it was never a `check control`
# row here, and the sweep selects only from these rows — so `non-vacuity.sh --only doc-budget.sh`
# matched no targeted check. The ratchet that keeps the core governing docs from re-bloating had no
# proof it can still fail. (It is one of a set of workflow-invoked conformance checks that are not
# registered here. THE RECONCILIATION-OF-RECORD IS THE RUN'S OWN `Scripts:` LINE, printed beside the
# Summary at the foot of this file (PR 10): rows · unique scripts · files on disk · files no row
# invokes, computed at runtime. "Three methods, three answers" was true because the three methods count
# three DIFFERENT populations; that line names all of them. Which unregistered files SHOULD be
# registered stays CONFORMANCE-MUTATION-COVERAGE-GAP's question — the count is no longer part of it.)
#
# --kitself IS LOAD-BEARING, and it is a CATEGORY distinction, not a convenience. doc-budget budgets
# CLAUDE.md / DEVELOPMENT-PROCESS.md / DEVELOPMENT-STANDARDS.md — the KIT's own core-3 governing docs,
# and its whole purpose is an anti-re-bloat ratchet on kit-authored prose. On an INCEPTED tree
# `CLAUDE.md` is the project CHARTER: a different document that merely shares a filename, whose length
# is the adopter's business. Registering the rows unqualified made this slice's own +25-line entry
# contract in templates/PROJECT-CLAUDE-TEMPLATE.md red a BRAND-NEW project's first
# `verify.sh --require` (MEASURED: stamped charter 143 lines vs a budget of 135, rc 1) — a kit ratchet
# charged to adopter content. Raising the number would only postpone the same collision.
check control doc-budget               --kitself sh conformance/doc-budget.sh
check control doc-budget-selftest       --kitself sh conformance/doc-budget.sh --selftest
# conformance-mass-budget (CUT-A7) is doc-budget's sibling one level up: doc-budget ratchets the core
# governing PROSE, this ratchets the kit's own conformance MASS (lines + files + the `^check control `
# census right here in this file). --kitself IS LOAD-BEARING on BOTH rows, and non-negotiably so: it
# is the identical exposure doc-budget MEASURED above — a kit ratchet charged to adopter content. An
# adopter's conformance/ holds THEIR checks; holding them to the kit's line count would red a
# brand-new tree's first `verify.sh --require` for growth that is none of the kit's business. The
# check ALSO stands down in-script on the same OR-of-markers detector (arming evaluated BEFORE any
# enumeration, so an adopter never reaches its fail-closed refusal), so neither surface alone is the
# switch. ⚠️ These two rows are themselves counted by the census this check budgets — adding them cost
# the founding measurement, which is why GENESIS was taken on the POST-diff tree.
check control conformance-mass-budget          --kitself sh conformance/conformance-mass-budget.sh
check control conformance-mass-budget-selftest --kitself sh conformance/conformance-mass-budget.sh --selftest
# loop-state is the universal refusal floor (KIT-ADHERENCE-ENFORCEMENT B1). ONLY the --selftest is
# registered here: this file accepts BASE-INDEPENDENT checks, and the REAL gate needs the PR head SHA
# (`--head <sha>`), which does not exist on an arbitrary tree. The real gate runs as a PR-context job
# in ci.yml — the same split ceremony-binding already uses (selftest backstop vs diff-relative gate).
# Registering the selftest is also what puts loop-state inside `non-vacuity.sh`'s swept set, which
# selects from these `^check control` rows: without this row the gate would ship a green nobody has
# proven can go red — exactly the CONFORMANCE-MUTATION-COVERAGE-GAP this row avoids inheriting.
# --kitself IS LOAD-BEARING here, exactly as it is for doc-budget above. THE LIVE REASON: this
# selftest's map-completeness anchor grades the KIT's own roster, so an adopter who adds a single
# project skill reds it — measured. On an adopter tree that roster is the adopter's business, not a
# kit assertion.
# ⚠️ A SECOND REASON WAS ONCE GIVEN HERE AND IS NOW STALE — that BACKLOG.md being export-ignore'd
# inverted the row leg's negative. The same commit made the row legs hermetic (they run against a
# fixture board), so the selftest now PASSES with BACKLOG.md removed; re-measured at ce49514. It is
# recorded rather than deleted so nobody later "fixes" the hermetic fixtures and drops this flag on
# the strength of a reason that no longer applies. The reason above carries the flag alone.
# A --kitself row is still a `^check control` row, so non-vacuity coverage survives (verified:
# `non-vacuity.sh --only loop-state.sh` reports KILLED).
check control loop-state-selftest      --kitself sh conformance/loop-state.sh --selftest
# pre-push (B1) runs loop-state.sh --head on the pushed HEAD as a local speed bump — the same
# script path, at the same SHA CI grades (design Δ1: head-of-ref, identical to the PR head).
# Registering only the SELFTEST here (not a live invocation) rides the same split as loop-state
# itself: the real gate needs a pushed SHA that does not exist on an arbitrary tree. --kitself
# because the hook's selftest (like loop-state's) grades against this repo's own throwaway
# fixtures and self-invocation path, the same category as the doc-budget / loop-state rows above.
# ⚠️ This row's own script path (hooks/pre-push, not conformance/*.sh) is NOT a
# `conformance/[a-z0-9-]+\.sh` token, so non-vacuity.sh's target_set CANNOT select it — measured
# (see docs/architecture/2026-08-05-b1-pre-push-entry-declaration-design.md §7, amended with this
# measurement). The hook's mutation-sweepable region (decl_check_ref, above its own --selftest
# marker) is proven by hand-run cases inside that file's own selftest, not by this sweep. Same
# caveat as the design's own §7: the predicate's class leg still reads the ambient worktree at
# grading time, not a pristine checkout of the graded SHA — "identical SHA" is a claim about
# WHICH commit is graded, not a guarantee the working tree matches it byte-for-byte.
check control pre-push-selftest        --kitself sh hooks/pre-push --selftest
# dial-state (DIAL-DELIVERY Δ-A) — the presence+values lock on .kit/dials.conf, the repo-carried
# state the two rows above actually read. The LIVE check is registered (not just a selftest): it is
# base-independent and needs no SHA, and it is the row that would red a COMMITTED disarm — the whole
# point of moving the dial out of an env var. --kitself IS LOAD-BEARING and is the same category as
# the three rows above: `.kit/dials.conf` is export-ignored, so an adopter tree legitimately has
# none and reads observe by design; holding an adopter to the kit's flip would be a kit ratchet
# charged to adopter content (the doc-budget lesson). The check ALSO scope-guards itself in-script
# on the same un-spoofable marker set, so neither surface alone is the switch. Registering it here
# is additionally what enrols the file in non-vacuity.sh's sweep (which selects from these
# `^check control` rows), and its own --selftest runs as a dedicated ci.yml step (H3 pair pointer:
# conformance-selftests, "dial-state self-test").
check control dial-state               --kitself sh conformance/dial-state.sh
# permission-surface-audit (C3 PERMISSION-SURFACE-DELIVERY-AUDIT) — reconciles the shipped
# .claude/settings.json allow/ask/deny surface + the PreToolUse hook against the checked enumeration
# conformance/sanctioned-commands.tsv, and resolves every ruling-only/deliberately-absent ruling-ref
# against DECISIONS.md. The LIVE check is registered (base-INDEPENDENT — pure tracked-text compare, no
# SHA/base needed) and is the row that reds a committed shipped-vs-ruling disagreement. --kitself IS
# LOAD-BEARING and the same category as the four rows above: the enumeration is export-ignored, so an
# adopter tree legitimately carries none and reads N/A by design (adopters populate their own). The
# check ALSO scope-guards itself in-script on the same un-spoofable marker set, so neither surface
# alone is the switch. Registering it here enrols the file in non-vacuity.sh's sweep (which selects
# from these `^check control` rows); its own --selftest runs as a dedicated ci.yml step
# (conformance-selftests, "permission-surface-audit self-test").
check control permission-surface-audit --kitself sh conformance/permission-surface-audit.sh
# tool-coverage (C5 GUARD-TOOL-COVERAGE-GREP-GLOB) — the content-tool FAMILY LOCK. Keys on C3's
# sanctioned-commands.tsv guard-backstop column (corrected in C5): every tool-name allow/ask row must
# carry a recorded backstop (full/residual-family/declared-uncovered), never a silent `none`, and each
# claimed backstop must have a matching guard.sh case arm. Detection-not-enumeration: a newly-added
# content tool (forced into the TSV by C3's reconcile lock) reds this unless a human wires/declares it.
# The LIVE check is registered (base-INDEPENDENT — pure tracked-text compare of the TSV against
# guard.sh, no SHA/base needed). --kitself IS LOAD-BEARING and the same category as the rows above: the
# enumeration is export-ignored, so an adopter tree carries none and reads N/A (adopters populate their
# own). The check ALSO scope-guards itself in-script on the same un-spoofable marker set, so neither
# surface alone is the switch. Registering it here enrols the file in non-vacuity.sh's sweep (which
# selects from these `^check control` rows); its own --selftest runs as a dedicated ci.yml step
# (conformance-selftests, "tool-coverage self-test").
check control tool-coverage            --kitself sh conformance/tool-coverage.sh
# adopter-told (C7 ADOPTER-TOLD-LOOP-GATES-ARE-ENFORCED) — the shipped prose must not tell an adopter
# a gate is ENFORCED when nothing in what they receive enforces it. It builds a real adopter export
# (~0.4s), classifies every conformance check as hard-reachable / dial-reachable (observe-dialed
# profiles/adopter-gates.yml) / unreachable, and reds a claim-verb line naming a check the adopter
# cannot reach — unless the line discloses the dial or is narrowed to the kit's own CI and true there.
# STILL NO --kitself IN THE FIRST-INVOCATION SENSE, and this is the distinction from the four rows
# above: this check ARMS ITSELF in-script on the same un-spoofable kit-marker pair, so a registry-level
# skip would be redundant on the adopter side — its N/A is a self-declared skip (C6 renders it N-A), not
# a registry-level suppression, and on an ARMED tree an export or parse failure is a FAIL rather than an
# N/A. --kitself (ADOPTER-GATES-INERT A3): the SUBJECT graded is the KIT'S OWN shipped prose (does the
# kit's own documentation overclaim what an adopter's export enforces) — a genuine kit fact, never the
# adopter's artifact, so the registry flag is added purely for the census's benefit; the self-arming
# logic above is unchanged and is what actually governs behaviour. Registering it here also enrols it in
# non-vacuity.sh's sweep (which selects from these `^check control` rows); its own --selftest runs as a
# dedicated ci.yml step (conformance-selftests, "adopter-told self-test") and the LIVE check runs in
# `docs-links` — a required, no-`if:` job that SURVIVES the docs_only skip, unlike
# cf-verify-enforced/cf-export, which are disarmed on exactly the `.md` PRs a prose-claim check governs
# (measured, C7 design §2.7).
check control adopter-told             --kitself sh conformance/adopter-told.sh
# TOMBSTONE (2026-08-19, CUT-PHASE-GATE-PARK, `D-240819-3` amending `D-240804-1`): two `check control`
# rows for the edit-time phase gate stood here. The gate was PARKED to the history branch
# `history/phase-gate-s1a-i` — it had no wired caller, so it denied nothing, and its registration here
# was buying one composite mutant per sweep run over the single largest file in the corpus. Do not
# re-add a row without re-adding the script; the rows and the file move together (see
# `docs/kit-internals/retiring-conventions.md`, the tombstone there, for the history ref and what
# re-wiring would take).
# --kitself (ADOPTER-GATES-INERT A3): both rows drive a REAL `incept` run as their OWN fixture (to
# prove the KIT'S OWN incept mechanism discloses the harness ceiling correctly) — a kit fact about the
# kit's tooling, never a specific adopter's already-incepted tree.
check control harness-ceiling          --kitself sh conformance/harness-ceiling-disclosed.sh
check control harness-ceiling-selftest  --kitself sh conformance/harness-ceiling-disclosed.sh --selftest
# --kitself (ADOPTER-GATES-INERT A3): proves the KIT'S OWN incept mechanism stamps a non-colliding
# pipeline-origin marker — a kit fact about incept's own emission, never a specific adopter's tree.
check control pipeline-origin          --kitself sh conformance/pipeline-origin.sh
check control pipeline-origin-selftest  --kitself sh conformance/pipeline-origin.sh --selftest
# CONFORMANCE-DOC-FAMILIES-MERGE (D-240828-4): these four rows used to name two single-purpose
# scripts. Both folded into the table-driven conformance/doc-markers.sh (subject:
# conformance/doc-markers.tsv) with their marker labels preserved verbatim — the mutants those
# selftests killed are now GENERATED per table row, one per marker, and still die by label. The rows
# stay FOUR AND DISTINCT on purpose: `^check control ` is both the census the mass budget ratchets
# and the target set non-vacuity.sh sweeps, so collapsing them would silently drop two rows of
# mutation coverage while the budget read it as a saving.
check control validation-terminal-state           sh conformance/doc-markers.sh validation-terminal-state
check control validation-terminal-state-selftest   sh conformance/doc-markers.sh validation-terminal-state --selftest
check control feedback-link-lifecycle              sh conformance/doc-markers.sh feedback-link-lifecycle
check control feedback-link-lifecycle-selftest      sh conformance/doc-markers.sh feedback-link-lifecycle --selftest
check control named-adapters-selftest  sh conformance/named-adapters.sh --selftest
check control ci-gates         --kitself sh conformance/ci-gates.sh profiles/typescript-node/ci.yml --expect-seams
# B7 (D-240805-2 executed) — the NON-kitself leg: THIS tree's OWN installed pipeline(s) judged
# against the 8 gate ids minus the tree's validated na dispositions
# (conformance/gate-dispositions.txt; absent = all 8 — the adopter default, the kit's file being
# export-ignored). Deliberately NOT --kitself: this is the row adopters run — an adopter deleting
# gate-sbom from their emitted pipeline goes RED on their own tree (the Phase-B spine AC). Raw
# pre-incept export disposes N/A; an unmarked FOREIGN (brownfield) pipeline disposes
# ADOPTER-OWNED N/A-with-remedy, never FAIL (the verify-enforced-wired provenance axis, copied).
# On the kit tree it binds the kit's own meta-CI to the D-240805-2 3-apply set.
# --adopter, NOT --kitself (ADOPTER-GATES-INERT A3 STOP-AND-FLAG): the census-reconciliation input to
# this build listed ci-gates-own under the --kitself group, but the paragraph immediately above and the
# script's own "raw pre-incept export: no pipeline and no incepted/kit marker" N/A message (ci-gates.sh)
# say the opposite — the subject is THE TREE'S OWN INSTALLED PIPELINE, it correctly N/As pre-inception
# (no pipeline exists yet) and ARMS the moment incept emits one, exactly the pattern the other 8
# --adopter rows share. `--kitself` here would have PERMANENTLY SILENCED the exact adopter-facing
# enforcement the paragraph above says this row exists for. Re-classified during T4's mandatory re-triage
# pass; flagged in the build's self-verify report for reviewer attention.
check control ci-gates-own     --adopter sh conformance/ci-gates.sh --own-tree
check control ci-gates-selftest sh conformance/ci-gates.sh --selftest
# TIER0-LOCKS-OWED (b) — the aggregator needs:/classifier drift-lock, live on the KIT's OWN
# .github/workflows/ci.yml + conformance/ci-classify-changes.sh (the shape this lock judges — a
# many-shard `conformance` aggregator with a hand-maintained PG_NEEDED mirror — is this repo's own
# meta-CI, not an adopter's emitted single-pipeline profile). --kitself: an adopter export carries
# neither this ci.yml's aggregator shape nor this exact classifier constant.
check control ci-gates-aggregator-lock --kitself sh conformance/ci-gates.sh --aggregator-lock
# A8/T1-09 — the kit's own ci.yml must carry a real secret-scan gate. The LIVE check + its --selftest are
# gitleaks-FREE (pure grep over the workflow + runtime fixtures), so both are portable and mutation-swept.
# The gitleaks-DEPENDENT planted-secret liveness proof lives under --scan-selftest and runs ONLY in the
# dedicated `secret-scan` CI job (which downloads the pinned binary) — registering it here would UNVERIFIED-
# red the offline aggregate on any host without gitleaks. See conformance/secret-scan-wired.sh's header.
# --kitself on the LIVE check: it asserts THE KIT'S OWN .github/workflows/ci.yml carries the secret-scan
# gate — that file is export-ignored, so on an adopter/export tree it is absent and the check must N/A,
# not FAIL (adopters get their own secret-scan via their profile pipeline + ci-gates.sh). Without this
# it reds green-on-clone: the adopter's first push would be RED (measured on PR-486 CI). The --selftest
# is tree-independent (runtime fixtures) so it stays portable and mutation-swept.
check control secret-scan-wired --kitself sh conformance/secret-scan-wired.sh
check control secret-scan-wired-selftest  sh conformance/secret-scan-wired.sh --selftest
check control dep-scan-visibility           sh conformance/dep-scan-visibility.sh
check control dep-scan-visibility-selftest   sh conformance/dep-scan-visibility.sh --selftest
check control image-supply     sh conformance/container-supply-chain.sh
# --kitselftest (design §3 (a)): lints only scripts/*.sh, conformance/*.sh, profiles/*/scaffold/scripts/*.sh, scripts/kit-guard and
# hooks/pre-push - every one a control-plane path (its --selftest uses temp fixtures only).
check control shellcheck       --kitselftest sh conformance/shellcheck.sh
check control "license-check(selftest)" sh scripts/license-check.sh --selftest
check control guard-wired      sh conformance/guard-wired.sh
check control check-links      sh conformance/check-links.sh
# citation-live (C9 CITATION-LIVE, ruling D-240804-2) — the COMPLEMENT of the row above, and the pair
# is the point: check-links validates Markdown LINKS and deliberately SKIPS code spans, where ~85% of
# the kit's `path.ext:LINE` citations live (its own header discloses that ceiling). This row grades
# exactly those, over the LIVING Markdown corpus only — the dated record (designs, plans, CHANGELOG,
# the meta-control log) is exempt-and-REPORTED, because a dated document's citations were correct
# against the tree of its own date. STILL SELF-ARMING, for adopter-told's reason: the check ARMS ITSELF
# in-script on the same un-spoofable kit-marker pair, so on an armed tree a failed corpus enumeration
# or a zero-citation domain is a FAIL rather than an N/A, while an adopter tree with no citations
# self-declares N/A (C6 renders it N-A). --kitself (ADOPTER-GATES-INERT A3): the SUBJECT is "the kit's
# LIVING Markdown"/"the kit's governance record" (its own header) — a genuine kit fact; the flag is
# added purely for the census, the self-arming logic above still governs actual behaviour. Registering
# it here also enrols the file in non-vacuity.sh's sweep (which selects from these `^check control`
# rows); its own --selftest runs as a dedicated ci.yml step (conformance-selftests, "citation-live
# self-test") and the LIVE check runs in `docs-links` — the same required, no-`if:` job that survives
# the docs_only skip, chosen for the same reason: a citation-decay check governs exactly the `.md`-only
# PRs that disarm cf-verify-enforced.
check control citation-live    --kitself sh conformance/citation-live.sh
# citation-history (the sixth-dial slice, route (b), ruling D-240815-2d) — the row above grades whether
# a cited line still EXISTS; this one grades the WRITING SHAPE that carries a dead value forward. The
# two are deliberately separate files: citation-live is mode-pure and its logic is frozen by this
# slice, so the new grammar lands beside it rather than inside its mutation region. The LIVE row is
# registered (base-INDEPENDENT — a `git ls-files` enumeration and one awk pass, no SHA, no merge-base)
# and it is sub-second. STILL SELF-ARMING, for citation-live's exact reason: the check ARMS ITSELF
# in-script on the same un-spoofable kit-marker pair, so on an armed tree an unreadable or unenumerable
# corpus is a FAIL rather than an N/A, while an adopter tree self-declares the line-anchored N/A that C6
# renders N-A (de-lining is the kit's own writing convention; the adopter face is the doctrine, not this
# gate). --kitself (ADOPTER-GATES-INERT A3): the subject is the kit's own writing convention over its
# own docs corpus, purely for the census; the self-arming logic still governs behaviour. Registering it
# here also enrols the file in non-vacuity.sh's sweep (which selects from these `^check control` rows);
# its own --selftest runs as a dedicated ci.yml step (conformance-selftests, "citation-history
# self-test") and the LIVE check runs in `docs-links` — the same required, no-`if:` job, chosen for the
# same reason: a lint over `.md` prose governs exactly the `.md`-only PRs that disarm cf-verify-enforced.
check control citation-history --kitself sh conformance/citation-history.sh
# decision-id-live (DANGLING-DECISION-ID-CITES) — the citation-live family ONE LEVEL UP: citation-live
# asks "does the cited LINE still exist"; this row asks "does the cited RULING still exist". A `D-*` id
# is the kit's strongest form of authority and was unforgeable only by convention — a living doc could
# carry an authority-shaped token to a ruling never recorded and nothing would red it. This grades every
# `D-YYMMDD-N` cited in a LIVING `.md` for membership in DECISIONS.md's `**`D-...`` headers (folding a
# dotted `.N` sub-id to its parent, the sanctioned-commands.tsv:54 precedent); the dated record is
# exempt-and-REPORTED (the C9 dated principle) and a `.sh` fixture id is out of the `.md`-only domain by
# construction. HONEST CEILING: it proves the parent ruling EXISTS, never that a sub-item number or the
# ruling's SUBSTANCE is real (Q3). KIT-SELF, and now --kitself (ADOPTER-GATES-INERT A3): the ids are the
# kit's own governance vocabulary, so the check ARMS ITSELF on the same un-spoofable kit-marker pair —
# on an armed tree a missing/empty DECISIONS.md or a zero-citation domain is a FAIL, while an adopter
# tree self-declares the line-anchored N/A that C6 renders N-A; the registry flag is added purely for
# the census, the self-arming logic still governs behaviour. Registering it here also enrols the file in
# non-vacuity.sh's sweep (which selects from these `^check control` rows); its own --selftest runs as a
# dedicated ci.yml step (conformance-selftests, "decision-id-live self-test") and the LIVE check runs in
# `docs-links` — the same required, no-`if:` job, chosen because a ruling-citation check governs exactly
# the `.md`-only PRs that disarm cf-verify-enforced.
check control decision-id-live --kitself sh conformance/decision-id-live.sh
# roadmap-current (C10 ROADMAP-STALE-RECONCILE) — the SIBLING of the row above and placed here for the
# same reason: both grade whether a LIVING document still tells the truth about the tree it describes.
# citation-live asks "does the line this doc cites still exist"; this row asks "does the roadmap still
# call SHIPPED work pending". Measured at the C10 probe, seven ROADMAP.md items carried a pending glyph
# while BACKLOG.md's `## Done` carried a row for each. The reconciliation was done by hand in that
# slice; THIS ROW IS THE RATCHET that keeps the count at zero. STILL NO --kitself, for citation-live's
# exact reason: the check ARMS ITSELF in-script on the same un-spoofable kit-marker pair, so on an armed
# tree a dead ROADMAP.md, an absent `## Done` section or a zero-marker stub is a FAIL rather than an N/A.
# --adopter (ADOPTER-GATES-INERT A3, correcting an earlier --kitself estimate): the check's own header
# says "An adopter who KEEPS a ROADMAP.md and a BACKLOG.md with a Done section is graded normally" — the
# subject is the ADOPTER'S OWN roadmap<->board coherence, self-arming and borderline, but adopter-subject
# nonetheless. `--kitself` would have permanently silenced a real gate the moment an adopter authors
# either file; `--adopter` keeps it census-visible without that lie. Registering it here also enrols the
# file in non-vacuity.sh's sweep (which selects from these `^check control` rows); its own --selftest
# runs as a dedicated ci.yml step (conformance-selftests, "roadmap-current self-test") and the LIVE check
# runs in `docs-links` — the same required, no-`if:` job, chosen because a roadmap-honesty check governs
# exactly the `.md`-only PRs that disarm cf-verify-enforced.
check control roadmap-current  --adopter sh conformance/roadmap-current.sh
# runbook-current (C11 KIT-RUNBOOK) — the THIRD member of the living-document family above, and it sits
# here for the family's reason: citation-live asks "does the line this doc cites still exist", roadmap-current
# asks "does the roadmap still call SHIPPED work pending", and this row asks "do the kit's own release-pinned
# governing records — RUNBOOK.md and THREAT-MODEL.md — still name the release they describe". The threat model
# joined the marker table in A4 of KIT-EVAL-2-TIER-A (`D-240825-1`): it was stamped 3.185.0 (header) and 3.186.0
# (footer) against VERSION 3.218.0, so the document defining what the guard is FOR had no ratchet while the
# runbook had one. Extending this row's check was the cheap path; a second check would have been the expensive
# one (CONFORMANCE-MASS-BUDGET). Measured at the C11 probe, the kit had NO RUNBOOK.md at all and
# its cold-resume path ran entirely through one agent's private memory — a friction-test failure. C11 authored
# the file; THIS ROW IS THE RATCHET that keeps it existing and dated. STILL SELF-ARMING, for the same reason
# the two rows above carry: the check ARMS ITSELF in-script on the same un-spoofable kit-marker pair, so on an
# armed tree an absent RUNBOOK.md or THREAT-MODEL.md, a missing/duplicated/stale marker or a dead VERSION is a
# FAIL rather than an N/A, while an adopter tree (where both records are export-ignored and the adopter's own
# are stamped from the templates) self-declares N/A and C6 renders it N-A. --kitself (ADOPTER-GATES-INERT A3):
# the subject is explicitly "the KIT'S OWN release-pinned governing records" (this comment's own words) — a
# genuine kit fact; the registry flag is added purely for the census, the self-arming logic above still
# governs behaviour. Registering it here also enrols the file in non-vacuity.sh's sweep
# (which selects from these `^check control` rows); its own --selftest runs as a dedicated ci.yml step
# (conformance-selftests, "runbook-current self-test") and the LIVE check runs in `docs-links` — the same
# required, no-`if:` job, chosen because a runbook-currency check governs exactly the `.md`-only PRs that
# disarm cf-verify-enforced. HONEST CEILING, so the row is not read as more than it is: it proves EXISTENCE +
# VERSION-STRING CURRENCY, never that a single procedure in the file is true.
check control runbook-current  --kitself sh conformance/runbook-current.sh
check control whitespace-clean  sh conformance/whitespace-clean.sh
check control build-output-ignored  sh conformance/build-output-ignored.sh
check control assurance-tiers   sh conformance/assurance-tiers.sh
check control promotion-contract  sh conformance/promotion-contract-documented.sh
check control inception-bootstrap  sh conformance/inception-bootstrap-documented.sh
check control backlog-adapters sh conformance/backlog-adapters.sh
# --kitself (ADOPTER-GATES-INERT A3): scans "the kit's own checks" (conformance/*.sh, scripts/*.sh,
# hooks/pre-push, its own header) for --selftest wiring into the KIT's own ci.yml — a kit fact, and
# meaningless once an adopter's export prunes those very files/that workflow.
check control ci-selftest-cov  --kitself sh conformance/ci-selftest-coverage.sh
check control runtime-floor   sh conformance/runtime-floor-coherent.sh
# Registered here (unlike non-vacuity-wired below) BECAUSE IT IS PORTABLE: a pure classifier over a file
# listing, with no dependency on the kit's own ci.yml, so it behaves identically on an adopter artifact.
# It lives in conformance/ (not scripts/) DELIBERATELY: the non-vacuity sweep's target_set only greps
# `conformance/*.sh`, so a classifier in scripts/ would never be mutation-tested. A classifier that could be
# neutered into "everything is docs-only" would silently skip the conformance gates — it MUST be swept.
check control ci-classify      sh conformance/ci-classify-changes.sh --selftest
# NOT REGISTERED HERE (deliberate): conformance/non-vacuity-wired.sh. It locks THE KIT'S OWN ci.yml
# (that the shard matrix launches every leg the sweep declares). This battery is PORTABLE — adopters run
# it too — and after incept an adopter's .github/workflows/ci.yml is THEIR pipeline, which has no sharded
# sweep to lock, so the check would correctly FAIL on every adopter. It is enforced as a ci.yml STEP (in
# conformance-core, a shard of the required `conformance` aggregate) — a failure there still reddens the
# required check. Caught by artifact-gate on PR #309: the kit's own gate, run on the INCEPTED artifact.
# Every exclusion from this battery is named with its reason in conformance/aggregate-exclusions.txt,
# and conformance/aggregate-coverage.sh FAILs on any check that is neither registered nor excluded.
#
# ★ verify-enforced-wired.sh USED TO SHARE THAT EXCLUSION — and no longer does (CP7R5-GATE-AUTHORITY).
# The old reasoning was "an adopter's ci.yml is THEIR pipeline, so the check would fail on every
# adopter". That was TRUE while no emitted pipeline ran the aggregate. Now that all 11 emitted
# pipelines carry a real `verify.sh --require` step, an incepted tree PASSES it — measured on a real
# export→incept before this line was written, not reasoned. So it is registered below, and an adopter
# who deletes the step goes RED: that is the enforcement, not a regression. Its --fleet mode stays
# kit-only (an adopter's tree is pruned to one profile) and is enforced as a ci.yml step instead.
# --adopter (ADOPTER-GATES-INERT A3): the subject is the ADOPTER'S OWN ci.yml running `verify --require`
# — it correctly N/As pre-inception (no emitted pipeline yet) and ARMS the moment incept emits one;
# --kitself would silence exactly the enforcement this row exists for.
check control verify-enforced  --adopter sh conformance/verify-enforced-wired.sh
check control onboarding       sh conformance/onboarding-complete.sh
check control discovery        sh conformance/discovery-complete.sh
check control adopter-preflight --kitself sh conformance/adopter-preflight-wired.sh
# --kitself (ADOPTER-GATES-INERT A3): "regression-lock for the S3 adopter-clean obtain MECHANISM"
# (its own header) — proves the KIT'S OWN exporter (scripts/adopter-export.sh) works, never a specific
# adopter's already-exported tree, and it needs the kit's own committed HEAD to run at all.
check control adopter-export   --kitself sh conformance/adopter-export-wired.sh
# adopter-export-claims (NON-VACUITY-SHARD2-FLOOR) — the exported tree's OWN claims-registry proof,
# un-nested out of the row above. THE ROW FORM IS `--selftest`, DELIBERATELY, and the reason is the
# whole point of the slice: the LIVE check runs two full exports and two claims-registry runs (~316s
# measured), and this aggregate is run by cf-verify-enforced AND by every local `verify.sh --require`.
# A live-form row here would charge both of them the cost the un-nesting just removed — reversing the
# cure's sign. Registering the CHEAP selftest is what enrols the file in non-vacuity.sh's sweep (which
# selects from these `^check control` rows), exactly as the loop-state and brownfield-walk rows above do.
# The LIVE both-faces proof runs in ci.yml's `cf-export-claims` job (adjudicated by the `conformance`
# aggregator) and weekly in drift-watch.yml. NOT --kitself: the selftest is hermetic (fixture trees with
# canned registries, no kit file read), so it is portable and must stay green inside the export too.
# WHAT THIS LANE GIVES UP (the coverage delta, stated): `verify.sh --require` no longer proves the
# exported tree's own claims-registry — an orphaned maintainer-only claim now surfaces only in
# cf-export-claims (non-docs PRs) and the weekly drift-watch, no longer in this local/enforced lane.
check control adopter-export-claims-selftest sh conformance/adopter-export-claims.sh --selftest
# A7 brownfield end-to-end lock: drives a legacy fixture through the CORRECTED docs/adoption/brownfield.md
# sequence to inception-done --surface rc 0, with a load-bearing negative (pre-push-skipped => FAIL).
# --kitself: it produces the tree via scripts/adopter-export.sh, which needs the kit's OWN committed .git,
# so it has no meaning on an adopter tree (N/A there; the walk also self-detects the kit repo). Its teeth
# live in the two-arm walk (a script-selftest), so non-vacuity.sh reports it UNCOVERED=no-idiom.
check control brownfield-walk  --kitself sh conformance/brownfield-walk.sh --selftest
# A2 archive lock (row CODEOWNERS-ROOT-EXPORT-LEAK): offline — `git archive HEAD` runs locally, no
# network. N/A on a non-repo or unborn-HEAD tree, so a freshly incepted adopter stays green.
# --kitself: the invariant is the KIT's (maintainer handles must not ship in the export). On an
# adopter tree the same scan would red their own legitimate handles (e.g. dual-forge CODEOWNERS
# naming the identities their .github/CODEOWNERS declares) — a false-red for a policy that is not
# theirs (review I-2). Adopter trees render N/A; the kit-side lock stays fully binding.
check control codeowners-export-clean --kitself sh conformance/codeowners-export-clean.sh
check control mode-blind       sh conformance/mode-enforcement-blind.sh
# --kitself (ADOPTER-GATES-INERT A3, design §2 bucket (b)): the E4/E5 reference-lock family below
# (orchestrator-loop, feature-flags-wired, containment-audit, runtime-security, structured-logging,
# app-tracing, metrics-endpoint, otlp-backend, trace-query, agentops-sensor) — each script's own header
# already states "kit-self lock; NOT that an adopter's app does": today they instrument the KIT's OWN
# reference app, keyed on golden-path.yml + the kit scaffold. The adopter-facing successor (grading the
# adopter's OWN deployed app) is the boarded ADOPTER-OPERATIONAL-CONFORMANCE row, not this slice.
check control orchestrator-loop --kitself sh conformance/orchestrator-loop-wired.sh
check control escalation-seam    sh conformance/escalation-wired.sh --selftest
check control proportional-gate sh conformance/proportional-gate-wired.sh --selftest
# HITL obligation engine (HITL-1/2/4/5 — HITL-5's regulated-data surface rides threat-obligation.sh's own
# selftest, so the scope label names it too). ONLY the fixture-driven, base-INDEPENDENT selftests are registered
# in this offline aggregate. The REAL diff-relative gates (sh conformance/threat-obligation.sh,
# conformance/uat-obligation.sh and conformance/a11y-obligation.sh, no args) are DELIBERATELY NOT here:
# each derives its change-set from
# `merge-base HEAD origin/main`, and by design a non-derivable base fails CLOSED (routes to 'uncertain' ->
# requires the record). In a base-less context — a shallow CI checkout with origin/main unfetched, or a
# fresh `git clone` on an adopter tree with no resolvable base — that correct fail-closed behavior would
# redden `verify.sh --require` for every caller, which is a false positive at the aggregate level (the
# aggregate must be green on any well-formed tree regardless of git-fetch depth). So each real gate runs as
# a dedicated PR-context CI step with a resolvable base (fetch-depth: 0 -> origin/main resolves) — the kit's
# own `threat-obligation`/`uat-obligation`/`a11y-obligation` jobs in ci.yml, and the reference adopter steps in
# profiles/typescript-node/ci.yml. This mirrors how promotion-readiness.sh (the same merge-base diff-relative
# pattern) runs only in the PR-context ratification.yml, never in this aggregate. The engine
# (obligation-lib.sh) still carries its own mutation-tested selftest so non-vacuity.sh mutates + kills its
# FAIL paths directly; threat-obligation.sh, uat-obligation.sh and a11y-obligation.sh each expose their
# selftest as behavioral proof. All selftests are base-independent (they build their own fixtures), so they
# belong here.
check control obligation-lib-selftest    sh conformance/obligation-lib.sh --selftest
check control threat-obligation-selftest sh conformance/threat-obligation.sh --selftest
check control uat-obligation-selftest    sh conformance/uat-obligation.sh --selftest
check control a11y-obligation-selftest   sh conformance/a11y-obligation.sh --selftest
# ceremony-binding follows the SAME split as the three obligations above: the selftest is
# base-independent (every leg builds its own git fixture repos, each hermetic w.r.t. the surrounding
# repository and its notes ref) and belongs here; the diff-relative REAL gate lives in ci.yml's PR-context job, where
# `origin/main` and refs/notes/promotions both resolve.
check control ceremony-binding-selftest  sh conformance/ceremony-binding.sh --selftest
# selftest-hermetic (PHASE-B-HYGIENE H2) — the fixture-hermeticity lane. ONLY the --selftest is
# registered: it is base-independent and hermetic by construction (every fixture repo is built by
# the selftest itself, identity inline), so it belongs in this offline aggregate on ANY tree — and
# registering it is what enrols the lane in non-vacuity.sh's sweep. The REAL gate is diff-relative
# (--touched needs a resolvable merge-base) and runs as a PR-context ci.yml step in conformance-core
# — the same split the HITL obligations and ceremony-binding rows above use. No --kitself: nothing
# here reads the kit's roster or budgets; an adopter tree answers identically.
check control selftest-hermetic  sh conformance/selftest-hermetic.sh --selftest
check control non-vacuity      sh conformance/non-vacuity.sh --selftest
# coverage-census (PR 10): the STATIC half of the mutation-coverage census — re-derive which control
# scripts are mutation-targeted vs excluded and diff against the ratified conformance/nv-coverage.tsv.
# Grep-class, ZERO mutants, so no measurable CI time (D-240815-3). --kitself for the doc-budget reason:
# the census records the KIT's control set; an adopter's own checks are their business.
check control coverage-census  --kitself sh conformance/non-vacuity.sh --coverage-census
check control eval-harness      sh conformance/eval-harness-wired.sh --selftest
check control eval-harness-runs sh conformance/eval-harness-runs.sh --selftest
check control roster-guard      sh conformance/roster-guard-wired.sh --selftest
# GATE-SUBJECT-IS-THE-ADOPTERS-SYSTEM (K13): the regression-lock for the two arms added to
# has_deploy_surface (conformance/surface-lib.sh) — surface-lib.sh itself has no --selftest of its own
# by design (aggregate-exclusions.txt); this is its wired companion. Portable (mktemp fixtures only,
# not kit-self), so registered plainly like roster-guard above.
check control surface-lib-wired sh conformance/surface-lib-wired.sh --selftest
# TRIPLE COLLAPSED (PR 10): `conflict-safe-integration` and `skill-spine` sat here as two MORE rows
# invoking orchestrator-loop-wired.sh with IDENTICAL arguments — one script run three times per aggregate
# for zero extra evidence. Both CLAIM IDS ARE UNTOUCHED (claims.tsv, REQUIRED_IDS, the S3b carve;
# DECISIONS:179 — dropping a verify row and dropping a claim are separate acts). HONEST NOTE: the claims
# job still runs each id's verifier, so the three identical runs remain THERE.
# NOT REGISTERED HERE (deliberate): conformance/incept-containment.sh. It is KIT-ONLY — its fixtures build an
# UN-INCEPTED export via `git archive HEAD`, which needs a committed kit SOURCE. The incepted adopter artifact
# (artifact-gate) has no such HEAD, and a real adopter never re-incepts (incept refuses an already-incepted
# tree), so the check cannot and should not run there. Same class as kit-base.sh / kit-manifest.sh. Its teeth
# run as a dedicated ci.yml step on the kit source (which satisfies ci-selftest-coverage) plus the standing
# self-negative inside --selftest; non-vacuity sweeps conformance/*.sh directly, so it is covered regardless.
check control release-tag       sh conformance/release-tag-wired.sh
# --kitself (ADOPTER-GATES-INERT A3): feature-flags-wired is "regression-lock for the E2 feature-flag
# REFERENCE" (its own header) — the kit's own reference wiring, not a specific adopter's app.
check control feature-flags-wired --kitself sh conformance/feature-flags-wired.sh
# --kitself: "PARITY across the app-stack PROFILES" (its own header) — grades the KIT's own template
# set (all ten profiles), meaningless on an adopter tree pruned to the ONE profile they chose.
check control profile-parity   --kitself sh conformance/profile-parity.sh
# --kitself: "ships for EVERY stack" (its own header) — grades the KIT's own template set across all
# profiles, same reason as profile-parity above.
check control ratification-parity --kitself sh conformance/ratification-parity.sh
# --kitself: same reason as ratification-parity — "ship for EVERY stack" (its own header), the kit's
# own template set.
check control adopter-gates-parity --kitself sh conformance/adopter-gates-parity.sh
# --kitself: locks that a retired KIT mechanism (check-run posters) stays retired across the kit's own
# workflows — a kit fact, not an adopter artifact.
check control poster-parity       --kitself sh conformance/poster-parity.sh
# --kitself (design §2 bucket (b), E4/E5 family): see the note above orchestrator-loop.
check control containment-audit   --kitself sh conformance/containment-audit-wired.sh
check control token-scope         sh conformance/token-scope.sh
# --kitself (E4/E5 family, design §2 bucket (b) — see the note above orchestrator-loop): each script's
# own header states "kit-self lock; NOT that an adopter's app does" — proves the KIT's reference app is
# instrumented, not that an adopter's arbitrary app is. The adopter-facing successor is the boarded
# ADOPTER-OPERATIONAL-CONFORMANCE row.
check control runtime-security    --kitself sh conformance/runtime-security.sh
check control structured-logging  --kitself sh conformance/structured-logging-wired.sh
check control app-tracing         --kitself sh conformance/app-tracing-wired.sh
check control metrics-endpoint    --kitself sh conformance/metrics-endpoint-wired.sh
check control otlp-backend        --kitself sh conformance/otlp-backend-wired.sh
check control trace-query         --kitself sh conformance/trace-query-wired.sh
check control agentops-sensor    --kitself sh conformance/agentops-sensor-wired.sh
check control author-not-approver sh conformance/author-not-approver-wired.sh
# --kitselftest (design §3 (a)+(b)): reads scripts/runaway-guard.sh and the real .kit/budget.conf (both control-plane) + temp git fixtures.
check control runaway-killswitch --kitselftest sh conformance/runaway-killswitch-wired.sh --selftest
# --adopter (ADOPTER-GATES-INERT A3): the subject is the ADOPTER'S OWN VERSION file vs THEIR OWN git
# tags — it correctly N/As pre-inception (no tags cut yet) and ARMS once the adopter releases; --kitself
# would silence a real adopter gate forever.
check control version-tag-coherent --adopter sh conformance/version-tag-coherent.sh
# --kitselftest (design §3 (a)+(b)): reads scripts/promotion-verify.sh, conformance/backlog-lib.sh, hooks/pre-push, .claude/hooks/guard-core.sh and
# .github/workflows/ci.yml (all control-plane) + temp git fixtures. Residual: the ci.yml trace-lock latches on the kit marker docs/ROADMAP-KIT.md
# (existence only; an adopter tree never carries it).
check control promotion-verify  --kitselftest sh conformance/promotion-verify-wired.sh --selftest
check control control-plane-revert-drill  sh conformance/control-plane-revert-drill.sh --selftest
# --kitselftest on both rows (design §3 (a)+(b)): the selftest reads scripts/promotion-verify.sh, conformance/verify.sh, .claude/hooks/guard-core.sh and
# the real .kit/budget.conf (all control-plane) + temp git fixtures; the bare run only greps those same three control-plane files.
check control promotion-actuate  --kitselftest sh conformance/promotion-actuate-wired.sh --selftest
check control promotion-actuate-run  --kitselftest sh conformance/promotion-actuate-wired.sh
# --kitself (ADOPTER-GATES-INERT A3): every leg below drives a REAL `incept` against the KIT's OWN
# `profiles/<x>` reference scaffold (needs the kit's committed HEAD + its own profiles/ directory,
# neither of which ships in an adopter export, which is pruned to the ONE profile the adopter chose).
# A kit fact about the kit's ten reference stacks, never a specific adopter's tree.
check control incept-first-run-green  --kitself sh conformance/incept-first-run-green.sh --selftest
check control inception-done-surface  sh conformance/inception-done.sh --selftest
check control incept-first-run-green-profile  --kitself sh conformance/incept-first-run-green.sh profiles/typescript-node
check control incept-first-run-green-go  --kitself sh conformance/incept-first-run-green.sh profiles/go
check control incept-first-run-green-python  --kitself sh conformance/incept-first-run-green.sh profiles/python
check control incept-first-run-green-rust  --kitself sh conformance/incept-first-run-green.sh profiles/rust
check control incept-first-run-green-java-spring  --kitself sh conformance/incept-first-run-green.sh profiles/java-spring
check control incept-first-run-green-kotlin  --kitself sh conformance/incept-first-run-green.sh profiles/kotlin
check control incept-first-run-green-dotnet  --kitself sh conformance/incept-first-run-green.sh profiles/dotnet
check control incept-first-run-green-terraform  --kitself sh conformance/incept-first-run-green.sh profiles/terraform
check control incept-first-run-green-data-engineering  --kitself sh conformance/incept-first-run-green.sh profiles/data-engineering
check control incept-first-run-green-ml  --kitself sh conformance/incept-first-run-green.sh profiles/ml
check control stack-decision-integrity  sh conformance/stack-decision-integrity.sh --selftest
# --adopter (ADOPTER-GATES-INERT A3): the LIVE leg's subject is the ADOPTER'S OWN stack-choice ADR
# rationale — it correctly N/As pre-inception (no ADR authored yet) and ARMS once the adopter writes
# one; --kitself would silence a real adopter gate forever. The --selftest sibling above is hermetic
# (fixture-driven) and stays unflagged.
check control stack-decision-integrity-adr  --adopter sh conformance/stack-decision-integrity.sh
check control deploy-decision-integrity  sh conformance/deploy-decision-integrity.sh --selftest
# --adopter, same reason as stack-decision-integrity-adr above: the subject is the adopter's OWN
# deploy-target rationale.
check control deploy-decision-integrity-run  --adopter sh conformance/deploy-decision-integrity.sh
check control harness-decision-integrity  sh conformance/harness-decision-integrity.sh --selftest
# --adopter, same reason again: the subject is the adopter's OWN harness-fit rationale.
check control harness-decision-integrity-run  --adopter sh conformance/harness-decision-integrity.sh
check control script-disclosure  sh conformance/script-disclosure.sh --selftest
check control script-disclosure-scan  sh conformance/script-disclosure.sh
# shell-parse-lint (SEMGREP-BASH-PARSE-KIT-WIDE T1): the shared SAST-parse structural lint —
# its own fixtures, then a live run over the default list (conformance/sast-parse-files.txt).
check control shell-parse-lint  sh conformance/shell-parse-lint.sh --selftest
check control shell-parse-lint-run  sh conformance/shell-parse-lint.sh
# board-parser-drift (BOARD-PIPE-ESCAPE CI fix round, collected-not-gated): the mutation-proof
# selftest AND the live corpus/enum run both register — the real run is base-independent (reads the
# repo's own board-claim.sh/backlog-lib.sh/meta-control-fresh.sh/backlog-current.sh, no live creds).
check control board-parser-drift  sh conformance/board-parser-drift.sh --selftest
check control board-parser-drift-run  sh conformance/board-parser-drift.sh
check control backlog-current  sh conformance/backlog-current.sh --selftest
# --adopter (ADOPTER-GATES-INERT A3): the subject is the ADOPTER'S OWN BACKLOG.md board hygiene — it
# correctly N/As pre-inception (no board authored yet) and ARMS once the adopter starts one; --kitself
# would silence a real adopter gate forever.
check control backlog-current-run  --adopter sh conformance/backlog-current.sh .
# owner-step-markers (PHASE-B-HYGIENE R1) — stale `OWNER STEP OPEN` / "not yet bound live" markers
# must not outlive their steps. Both rows are base-independent (git ls-files + grep; the selftest
# builds its own fixture repos), so live + selftest register here and enter the mutation sweep.
check control owner-step-markers          sh conformance/owner-step-markers.sh
check control owner-step-markers-selftest  sh conformance/owner-step-markers.sh --selftest
# KW6-A2 presence gate: selftest ONLY — no `-run` companion. Unlike backlog-current, the real run
# needs a live PR number (--pr), which exists only in PR context, so it cannot run as an offline
# verify.sh control-check; the ci.yml `backlog-presence` job calls check_pr live. check_pr is NOT dead
# code: selftest() drives it by argument (assert_msg), and the CI job invokes it on every gated PR.
check control backlog-presence  sh conformance/backlog-presence.sh --selftest
# T0-09 — pairs with the `check doc security-policy` row below: that row proves the disclosure
# policy is RECORDED; security-channel-live.sh probes the FORGE SETTING it advertises (PVR enabled
# on the declared `Channel repo:`). Selftest ONLY — same shape as backlog-presence above: the live
# probe needs gh+network+auth, and adopters run `verify.sh --require` offline with no GH_TOKEN
# (all ten profiles/*/ci.yml), so registering the live row would red every adopter's documented
# first CI push. The LIVE probe runs as a dedicated step in the kit's own ci.yml (step-scoped
# GH_TOKEN, beside the security-policy real-path step); adopters MAY wire the live run into their
# own pipeline the same way (no profile ships the step yet). check_channel is NOT dead code:
# selftest() drives it by argument, and the
# CI step invokes it live. The load-bearing negative lives in --selftest (stubbed
# {"enabled":false}); the live repo must never serve as the negative.
check control security-channel-live-selftest sh conformance/security-channel-live.sh --selftest
# TIER0-LOCKS-OWED (c): review-lane.sh was wired ONLY in ci.yml, so `non-vacuity.sh --only
# review-lane.sh` matched no targeted check and the mutation sweep never covered the kit's newest
# control-plane gate (the review-record grammar). Selftest-only, same shape as backlog-presence and
# security-channel-live above: the live `review-lane.sh --pre-push` / `--pr` runs need a real git
# history / forge context that a hermetic offline sweep does not carry; those live paths run in
# ci.yml and at the pre-push speed bump, not here. review-lane.sh is NOT dead code registered only
# for the sweep's sake: its --selftest oracle drives the same functions the live callers invoke.
check control review-lane      sh conformance/review-lane.sh --selftest
# --kitselftest (design §3 (a)+(b)): reads conformance/* (incl. prepush-twins.tsv, shellcheck.sh, ci-classify-changes.sh), the CI workflow and
# profiles/typescript-node/ci.yml (all control-plane) + temp fixtures; BACKLOG.md/CHANGELOG.md appear only as strings in its cache-key code.
check control prepush-lane    --kitselftest sh conformance/prepush-lane.sh --selftest   # selftest only (why + ceiling: conformance/README.md index row; the live faces run the KIT's battery and --census grades the KIT's ci.yml, so neither is portable — the census is its own conformance-core step). Not dead code: --selftest drives what `sparkwright prepush` invokes live.
# CONFORMANCE-DOC-FAMILIES-MERGE (D-240828-4): the nine conditional readiness rows now dispatch into
# conformance/readiness.sh (subject: conformance/readiness.tsv) and the two kit-doc marker rows into
# conformance/doc-markers.sh (subject: conformance/doc-markers.tsv). SAME ROW NAMES, same three-state
# contract, same per-case wording — the row name is what a reader and the summary see, and it did not
# move. deployable-ready / test-layers-ready / feature-flags-ready / roster-authority / security-policy
# are NOT part of the fold (structural detectors and mixed checks); they still name their own scripts.
check doc     deployable-ready sh conformance/deployable-ready.sh
check doc     dr-ready         sh conformance/readiness.sh dr-ready
check doc     resilience-ready sh conformance/readiness.sh resilience-ready
check doc     eval-ready       sh conformance/readiness.sh eval-ready
check doc     eval-ready-ml    --kitself sh conformance/readiness.sh eval-ready profiles/ml
check doc     observability-ready sh conformance/readiness.sh observability-ready
check doc     responsible-ai-ready sh conformance/readiness.sh responsible-ai-ready
check doc     responsible-ai-ready-ml --kitself sh conformance/readiness.sh responsible-ai-ready profiles/ml
check doc     test-data-ready  sh conformance/readiness.sh test-data-ready
check doc     test-layers-ready sh conformance/test-layers-ready.sh
check doc     preview-env-ready sh conformance/readiness.sh preview-env-ready
check doc     agentops-ready  sh conformance/readiness.sh agentops-ready
check doc     security-policy sh conformance/security-policy.sh
check doc     privacy-ready   sh conformance/readiness.sh privacy-ready
check doc     feature-flags-ready sh conformance/feature-flags-ready.sh
check doc     gate-eval-secrets sh conformance/doc-markers.sh gate-eval-secrets
check doc     artifact-lineage sh conformance/doc-markers.sh artifact-lineage
check doc     dod-precedence  sh conformance/doc-markers.sh dod-precedence
check doc     collected-not-gated sh conformance/doc-markers.sh collected-not-gated
check doc     roster-authority sh conformance/roster-authority-ready.sh
fi

echo ""
# ADOPTER-KIT-SELFTESTS-ON-CHANGE — ONE notice line when any --kitselftest row was skipped. Never says the
# skipped checks "passed" (design F1: the skip INHERITS the base's verdict, it does not check it). Nothing
# is printed or written when nothing was skipped.
if [ -n "$SKIPPED_KS" ]; then
  _ks_ver=""
  for _ks_src in "origin/kit-base:VERSION" "kit-base:VERSION"; do
    [ -z "$_ks_ver" ] || break
    _ks_ver=$(git show "$_ks_src" 2>/dev/null | head -n 1 | tr -d ' \t\r') || _ks_ver=""
  done
  [ -n "$_ks_ver" ] || _ks_ver=$(head -n 1 VERSION 2>/dev/null | tr -d ' \t\r') || _ks_ver=""
  [ -n "$_ks_ver" ] || _ks_ver=unknown
  _ks_names=${SKIPPED_KS# }
  _ks_note="kit selftests not re-run: $_ks_names — this PR changes no control-plane path, so their subject is byte-identical to the base; they run in full on every push to main and on the scheduled run (kit v$_ks_ver)"
  printf '%s\n' "$_ks_note"
  if [ -n "$KS_SUMMARY" ]; then ( printf '%s\n' "$_ks_note" >> "$KS_SUMMARY" ) 2>/dev/null || true; fi
fi
# `misconfigured` is APPENDED AFTER `failed`, never inserted: three ci.yml walk steps parse this line
# with `sed -n 's/.*· \([0-9]*\) n\/a ·.*/\1/p'`, which needs the `· ` that follows `n/a` to survive.
printf 'Summary: %d control-checks · %d doc-checks · %d unverified · %d n/a · %d failed · %d misconfigured\n' "$controls" "$docs" "$unverified" "$nas" "$failed" "$misconfigured"
# ── THE CENSUS RECONCILIATION-OF-RECORD (PR 10, VERIFY-HEADLINE-TRUTH). A SIBLING line, never an edit to
# the format string above, and it deliberately does NOT begin with the token `Summary` — that scalar is
# read as ONE line by this file's own C6 leg, three ci.yml walk steps and promotion-readiness.sh:407, so
# a second `^Summary:` match would make every one of those seds parse a multi-line string.
# THREE REAL POPULATIONS, NOT ONE NUMBER: registered ROWS, the unique SCRIPTS they invoke, and the FILES
# on disk. All three are true, none is the others, and the fourth field (files no row invokes: libs,
# ci-only, kit-self) is the gap that made the mismatch look like an error. Computed at RUNTIME — every
# hard-coded count in this file had gone stale by C6.
_sc_reg=$(grep -E '^check ' "$_SELF" 2>/dev/null | grep -oE 'conformance/[a-z0-9-]+\.sh' | sort -u) || _sc_reg=""
_sc_uniq=$(printf '%s\n' "$_sc_reg" | grep -c 'conformance/') || _sc_uniq=0
_sc_rows=$(grep -c '^check ' "$_SELF" 2>/dev/null) || _sc_rows=0
_sc_disk=0; _sc_norow=0
for _scf in conformance/*.sh; do
  [ -f "$_scf" ] || continue
  _sc_disk=$((_sc_disk + 1))
  printf '%s\n' "$_sc_reg" | grep -Fxq "$_scf" || _sc_norow=$((_sc_norow + 1))
done
printf 'Scripts: %d unique conformance scripts across %d rows (%d conformance/*.sh on disk; %d registered by no row: libs, ci-only, kit-self)\n' "$_sc_uniq" "$_sc_rows" "$_sc_disk" "$_sc_norow"
echo "A green run proves controls hold AND release/DR/resilience safety is DOCUMENTED —"
echo "it does NOT prove those procedures were tested. doc-checks verify records exist."
echo "UNVERIFIED is NOT a pass. See conformance/README.md \"What a green run means\"."

if [ -n "$SEAM_ACTIVE" ]; then
  # A seam run is a TEST of this file, never a verdict: the rows above may be a stub registry, and the
  # Scripts: line above counts the BUILT-IN registry's rows, not necessarily the ones this run executed.
  echo "RESULT: UNVERIFIED (TEST SEAM ACTIVE: $SEAM_ACTIVE — this run is NOT a verdict, whatever the rows above say)"
  exit 2
fi
result_sentence; exit $?
