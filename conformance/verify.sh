#!/bin/sh
# verify.sh — honest aggregate conformance runner. Classifies each check:
#   [control] — verifies a live/remote/structural WORKING control
#   [doc]     — verifies DOCUMENTATION / recorded evidence EXISTS (not that it was tested)
# Prints PASS/FAIL/UNVERIFIED/N-A per check + an honest summary footer. Exit policy:
#   non-zero if any [control] check FAILS, or (under --require / CI) any check is UNVERIFIED.
#   [doc] checks that are present-but-untested PASS — honestly labelled, not hidden.
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
#   usage: sh conformance/verify.sh [--require] | --selftest
set -eu
cd "$(dirname "$0")/.."


REQUIRE=0
[ -n "${CI:-}" ] && REQUIRE=1
[ "${1:-}" = "--require" ] && REQUIRE=1

ctrl_fail=0; unverified=0; controls=0; docs=0; failed=0; nas=0
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

# ── INCOMPLETE (K16) — an interrupted run must SAY so, in its own output ────────────────────────────
# The aggregate is ~105 checks / ~281s — LONGER than the default foreground command cap of the agent
# harnesses this kit is driven with. When one of those caps fires, the run is killed mid-flight.
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
  printf 'RESULT: FAIL (INCOMPLETE — interrupted after %d check(s); this is NOT a pass)\n' "$((controls+docs))"
  echo "An interrupted run proves nothing about the checks that never ran."
  echo "The full aggregate is ~105 checks / ~5 minutes — re-run WITHOUT a command timeout"
  echo "(background it, or capture output to a file). See conformance/README.md \"What a green run means\"."
  exit "${1:-1}"
}
trap '_incomplete 130' INT
trap '_incomplete 143' TERM

# check KIND NAME COMMAND...
check() {
  kind=$1; name=$2; shift 2
  # CP7R5-VERIFY-NONTS — a --kitself check validates the kit's OWN internals (a reference profile, a
  # dev selftest) and is meaningless on an already-incepted ADOPTER tree, where incept has pruned the
  # fixtures it reads. On an adopter tree it renders N-A (not a pass, not a fail); in the kit repo it runs.
  # The tree is classified by the un-spoofable kit-marker set: an adopter export strips BOTH
  # docs/ROADMAP-KIT.md (export-ignored) AND .github/workflows/golden-path.yml (control-plane +
  # export-ignored), so their joint absence == an adopter tree. Same set incept-first-run-green.sh keys on.
  # Paths are repo-root-relative (this script cd's to the root at startup).
  if [ "${1:-}" = "--kitself" ]; then
    shift
    if [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]; then
      line "[$kind]" "$name" "N-A"; nas=$((nas+1)); return 0
    fi
  fi
  if out=$("$@" 2>&1); then rc=0; else rc=$?; fi
  case "$kind" in control) controls=$((controls+1)) ;; doc) docs=$((docs+1)) ;; esac
  if [ "$rc" = "0" ]; then
    line "[$kind]" "$name" "PASS"
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
# Reads globals $ctrl_fail/$unverified/$failed/$REQUIRE; echoes the RESULT line; returns 1 on FAIL, 0 on OK.
# When this is reached with $failed != 0, ctrl_fail is 0 and (under --require) unverified is 0, so every
# remaining failure is a doc-check — hence "$failed doc-check(s)" is exact, not an over-count.
result_sentence() {
  if [ "$ctrl_fail" != "0" ]; then echo "RESULT: FAIL (a control check failed)"; return 1; fi
  if [ "$REQUIRE" = "1" ] && [ "$unverified" != "0" ]; then echo "RESULT: FAIL (unverified under --require/CI)"; return 1; fi
  if [ "$failed" != "0" ]; then
    echo "RESULT: OK (controls verified; $failed doc-check(s) FAILED, shown above — advisory, non-blocking)"; return 0
  fi
  echo "RESULT: OK (controls verified; docs present)"; return 0
}

if [ "${1:-}" = "--selftest" ]; then
  # deterministic: the aggregate renders its classification + honesty footer, and a
  # control failure is surfaced. We exercise the renderer, not live infra.
  out=$(sh "$0" 2>&1) || true
  printf '%s\n' "$out" | grep -q "control-checks" || { echo "verify --selftest: FAIL (no summary)"; exit 1; }
  printf '%s\n' "$out" | grep -q "UNVERIFIED is NOT a pass" || { echo "verify --selftest: FAIL (no honesty footer)"; exit 1; }
  printf '%s\n' "$out" | grep -Eq '\[control\]|\[doc\]' || { echo "verify --selftest: FAIL (no classification)"; exit 1; }
  # non-vacuous: at least one [control] must actually PASS — a render of only FAILs (green-while-dark)
  # must NOT satisfy --selftest. The synthetic line below proves the control-PASS grep is load-bearing.
  printf '%s\n' "$out" | grep -q '\[control\] .* PASS' || { echo "verify --selftest: FAIL (no [control] PASS — vacuous render)"; exit 1; }
  if printf '  [control] x                FAIL\n' | grep -q '\[control\] .* PASS'; then echo "verify --selftest: FAIL (vacuous fixture wrongly matched control-PASS)"; exit 1; fi

  # ── INCOMPLETE leg (K16) — an INTERRUPTED run must SAY it was interrupted and exit non-zero ──────────
  # WHY THIS EXISTS. The aggregate takes ~281s for 103 checks — longer than the default foreground
  # command cap of the agent harnesses people drive this kit with. In CP-7 run 4 a wrapper stopped
  # reading at ~43s of output and the run was read as an unexplained stall; with no trap, a killed run's
  # partial output is INDISTINGUISHABLE from a run still in progress, so the consumer must notice an
  # ABSENCE. That is the weakest possible signal, and it is how a truncated run gets mistaken for a
  # green one. `INCOMPLETE is not a pass` is the second honesty class beside `UNVERIFIED is not a pass`.
  #
  # BEHAVIOURAL, never a text grep for `trap` — presence is not effect. This launches a REAL run, kills
  # it mid-flight with SIGTERM, and asserts on what the process actually emitted and returned.
  _kout=$(mktemp) || { echo "verify --selftest: FAIL (no tmpdir for the INCOMPLETE leg)"; exit 1; }
  sh "$0" > "$_kout" 2>&1 &
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

  echo "verify --selftest: OK (renderer + honesty footer + non-vacuous control-PASS + INCOMPLETE-on-interrupt"
  echo "                       + K3: a FAILING check surfaces its diagnostic, a PASSING one stays one line"
  echo "                       + --kitself N-A/RUNS/mixed + VERIFY-SUMMARY: no 'docs present' over a doc-fail)"; exit 0
fi

echo "Conformance verification (honest aggregate)"
echo "-------------------------------------------"
# branch-protection's OFFLINE leg only (B4) — declaration-integrity, no gh, no network; see the
# SCOPE note above for why the LIVE leg stays out of this aggregate.
check control branch-protection-declared    sh conformance/branch-protection.sh --declared-only
check control branch-protection-selftest    sh conformance/branch-protection.sh --selftest
check control agent-autonomy   sh conformance/agent-autonomy.sh
check control agent-boundary   sh conformance/agent-boundary.sh --selftest
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
# registered here — the COUNT IS UNRECONCILED: three methods have given three answers, so no number is
# asserted anywhere in this slice. Scoping and closing the set is CONFORMANCE-MUTATION-COVERAGE-GAP in
# BACKLOG.md, whose first task is to establish the number with a method that is itself tested.)
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
# phase-gate is the EDIT-TIME sibling of loop-state's merge-time refusal floor ([S1a-i]). BOTH modes
# are registered, and both are base-INDEPENDENT: the default mode checks the §5 reason vocabulary,
# the totality of the rc contract over it and the T2 ceremony allowlist's must-refuse fixtures, while
# the selftest builds every fixture it needs (hermetic w.r.t. the ambient tree — its green was
# re-verified in a dev-clone, a fresh clone and a base-less checkout). No --kitself: nothing here
# grades the kit's own roster or budgets, so an adopter tree answers the same.
# ⚠️ WHAT THIS ROW BUYS FROM THE MUTATION SWEEP — MEASURED HERE, NOT INHERITED. Registering it is what
# enrols the file in non-vacuity.sh (the sweep selects from these `^check control` rows). But that
# sweep builds ONE COMPOSITE mutant per file, neutering every idiom above the selftest() marker at
# once. Re-measured on this file at the shipped tree (plan §12 A7's ACC=0 + one control-flow idiom is
# SUPERSEDED — the file has grown): APPLIED 46, ACC 7, CTL 39, MARK 2302; of those 46 sites, 7 are
# PHANTOMS inside pre-marker COMMENTS (4 accumulator, 3 control-flow — the inflation non-vacuity.sh's
# own honest ceiling warns about, since mutate() has no lexer), leaving 39 real CODE sites.
# So a `KILLED: phase-gate.sh` green proves that AT LEAST ONE of those 39 sites is observed by the
# selftest — never that each is, and never 39 kills. The load-bearing coverage is the hand-run
# mutation evidence recorded at the legs themselves, together with the 13 sites the file DECLARES
# unpoliced with a measured empty kill set. Do not quote the green as more than one mutant
# (CONFORMANCE-MUTATION-COVERAGE-GAP on the board is the row that scopes this class).
check control phase-gate               sh conformance/phase-gate.sh
check control phase-gate-selftest       sh conformance/phase-gate.sh --selftest
check control harness-ceiling          sh conformance/harness-ceiling-disclosed.sh
check control harness-ceiling-selftest  sh conformance/harness-ceiling-disclosed.sh --selftest
check control pipeline-origin          sh conformance/pipeline-origin.sh
check control pipeline-origin-selftest  sh conformance/pipeline-origin.sh --selftest
check control validation-terminal-state           sh conformance/validation-terminal-state-documented.sh
check control validation-terminal-state-selftest   sh conformance/validation-terminal-state-documented.sh --selftest
check control feedback-link-lifecycle              sh conformance/feedback-link-lifecycle-documented.sh
check control feedback-link-lifecycle-selftest      sh conformance/feedback-link-lifecycle-documented.sh --selftest
check control named-adapters-selftest  sh conformance/named-adapters.sh --selftest
check control ci-gates         --kitself sh conformance/ci-gates.sh profiles/typescript-node/ci.yml --expect-seams
check control ci-gates-selftest sh conformance/ci-gates.sh --selftest
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
check control shellcheck       sh conformance/shellcheck.sh
check control "license-check(selftest)" sh scripts/license-check.sh --selftest
check control guard-wired      sh conformance/guard-wired.sh
check control check-links      sh conformance/check-links.sh
check control whitespace-clean  sh conformance/whitespace-clean.sh
check control build-output-ignored  sh conformance/build-output-ignored.sh
check control assurance-tiers   sh conformance/assurance-tiers.sh
check control promotion-contract  sh conformance/promotion-contract-documented.sh
check control inception-bootstrap  sh conformance/inception-bootstrap-documented.sh
check control backlog-adapters sh conformance/backlog-adapters.sh
check control ci-selftest-cov  sh conformance/ci-selftest-coverage.sh
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
check control verify-enforced  sh conformance/verify-enforced-wired.sh
check control onboarding       sh conformance/onboarding-complete.sh
check control discovery        sh conformance/discovery-complete.sh
check control adopter-preflight --kitself sh conformance/adopter-preflight-wired.sh
check control adopter-export   sh conformance/adopter-export-wired.sh
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
check control orchestrator-loop sh conformance/orchestrator-loop-wired.sh
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
check control eval-harness      sh conformance/eval-harness-wired.sh --selftest
check control eval-harness-runs sh conformance/eval-harness-runs.sh --selftest
check control roster-guard      sh conformance/roster-guard-wired.sh --selftest
check control conflict-safe-integration sh conformance/orchestrator-loop-wired.sh
# NOT REGISTERED HERE (deliberate): conformance/incept-containment.sh. It is KIT-ONLY — its fixtures build an
# UN-INCEPTED export via `git archive HEAD`, which needs a committed kit SOURCE. The incepted adopter artifact
# (artifact-gate) has no such HEAD, and a real adopter never re-incepts (incept refuses an already-incepted
# tree), so the check cannot and should not run there. Same class as kit-base.sh / kit-manifest.sh. Its teeth
# run as a dedicated ci.yml step on the kit source (which satisfies ci-selftest-coverage) plus the standing
# self-negative inside --selftest; non-vacuity sweeps conformance/*.sh directly, so it is covered regardless.
check control skill-spine sh conformance/orchestrator-loop-wired.sh
check control release-tag       sh conformance/release-tag-wired.sh
check control feature-flags-wired sh conformance/feature-flags-wired.sh
check control profile-parity   sh conformance/profile-parity.sh
check control ratification-parity sh conformance/ratification-parity.sh
check control adopter-gates-parity sh conformance/adopter-gates-parity.sh
check control poster-parity       sh conformance/poster-parity.sh
check control containment-audit   sh conformance/containment-audit-wired.sh
check control token-scope         sh conformance/token-scope.sh
check control runtime-security    sh conformance/runtime-security.sh
check control structured-logging  sh conformance/structured-logging-wired.sh
check control app-tracing         sh conformance/app-tracing-wired.sh
check control metrics-endpoint    sh conformance/metrics-endpoint-wired.sh
check control otlp-backend        sh conformance/otlp-backend-wired.sh
check control trace-query         sh conformance/trace-query-wired.sh
check control agentops-sensor    sh conformance/agentops-sensor-wired.sh
check control author-not-approver sh conformance/author-not-approver-wired.sh
check control runaway-killswitch sh conformance/runaway-killswitch-wired.sh --selftest
check control version-tag-coherent sh conformance/version-tag-coherent.sh
check control promotion-verify  sh conformance/promotion-verify-wired.sh --selftest
check control control-plane-revert-drill  sh conformance/control-plane-revert-drill.sh --selftest
check control promotion-actuate  sh conformance/promotion-actuate-wired.sh --selftest
check control promotion-actuate-run  sh conformance/promotion-actuate-wired.sh
check control incept-first-run-green  sh conformance/incept-first-run-green.sh --selftest
check control inception-done-surface  sh conformance/inception-done.sh --selftest
check control incept-first-run-green-profile  sh conformance/incept-first-run-green.sh profiles/typescript-node
check control incept-first-run-green-go  sh conformance/incept-first-run-green.sh profiles/go
check control incept-first-run-green-python  sh conformance/incept-first-run-green.sh profiles/python
check control incept-first-run-green-rust  sh conformance/incept-first-run-green.sh profiles/rust
check control incept-first-run-green-java-spring  sh conformance/incept-first-run-green.sh profiles/java-spring
check control incept-first-run-green-kotlin  sh conformance/incept-first-run-green.sh profiles/kotlin
check control incept-first-run-green-dotnet  sh conformance/incept-first-run-green.sh profiles/dotnet
check control incept-first-run-green-terraform  sh conformance/incept-first-run-green.sh profiles/terraform
check control incept-first-run-green-data-engineering  sh conformance/incept-first-run-green.sh profiles/data-engineering
check control incept-first-run-green-ml  sh conformance/incept-first-run-green.sh profiles/ml
check control stack-decision-integrity  sh conformance/stack-decision-integrity.sh --selftest
check control stack-decision-integrity-adr  sh conformance/stack-decision-integrity.sh
check control deploy-decision-integrity  sh conformance/deploy-decision-integrity.sh --selftest
check control deploy-decision-integrity-run  sh conformance/deploy-decision-integrity.sh
check control harness-decision-integrity  sh conformance/harness-decision-integrity.sh --selftest
check control harness-decision-integrity-run  sh conformance/harness-decision-integrity.sh
check control script-disclosure  sh conformance/script-disclosure.sh --selftest
check control script-disclosure-scan  sh conformance/script-disclosure.sh
check control backlog-current  sh conformance/backlog-current.sh --selftest
check control backlog-current-run  sh conformance/backlog-current.sh .
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
check doc     deployable-ready sh conformance/deployable-ready.sh
check doc     dr-ready         sh conformance/dr-ready.sh
check doc     resilience-ready sh conformance/resilience-ready.sh
check doc     eval-ready       sh conformance/eval-ready.sh
check doc     eval-ready-ml    sh conformance/eval-ready.sh profiles/ml
check doc     observability-ready sh conformance/observability-ready.sh
check doc     responsible-ai-ready sh conformance/responsible-ai-ready.sh
check doc     responsible-ai-ready-ml sh conformance/responsible-ai-ready.sh profiles/ml
check doc     test-data-ready  sh conformance/test-data-ready.sh
check doc     test-layers-ready sh conformance/test-layers-ready.sh
check doc     preview-env-ready sh conformance/preview-env-ready.sh
check doc     agentops-ready  sh conformance/agentops-ready.sh
check doc     security-policy sh conformance/security-policy.sh
check doc     privacy-ready   sh conformance/privacy-ready.sh
check doc     feature-flags-ready sh conformance/feature-flags-ready.sh
check doc     gate-eval-secrets sh conformance/gate-eval-secrets-ready.sh
check doc     artifact-lineage sh conformance/artifact-lineage-ready.sh
check doc     roster-authority sh conformance/roster-authority-ready.sh

echo ""
printf 'Summary: %d control-checks · %d doc-checks · %d unverified · %d n/a · %d failed\n' "$controls" "$docs" "$unverified" "$nas" "$failed"
echo "A green run proves controls hold AND release/DR/resilience safety is DOCUMENTED —"
echo "it does NOT prove those procedures were tested. doc-checks verify records exist."
echo "UNVERIFIED is NOT a pass. See conformance/README.md \"What a green run means\"."

result_sentence; exit $?
