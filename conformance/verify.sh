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
# stack-selection, branch-protection — repo-admin creds it can't have in least-privilege CI; verified
# at the governance gate, see its header) and conditionally-wired checks (e.g. container-supply-chain)
# run in their own CI steps / at the adopter's gate, not here. "aggregate" means representative.
#   usage: sh conformance/verify.sh [--require] | --selftest
set -eu
cd "$(dirname "$0")/.."


REQUIRE=0
[ -n "${CI:-}" ] && REQUIRE=1
[ "${1:-}" = "--require" ] && REQUIRE=1

ctrl_fail=0; unverified=0; controls=0; docs=0; failed=0
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
# The aggregate is ~103 checks / ~281s — LONGER than the default foreground command cap of the agent
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
  echo "The full aggregate is ~103 checks / ~5 minutes — re-run WITHOUT a command timeout"
  echo "(background it, or capture output to a file). See conformance/README.md \"What a green run means\"."
  exit "${1:-1}"
}
trap '_incomplete 130' INT
trap '_incomplete 143' TERM

# check KIND NAME COMMAND...
check() {
  kind=$1; name=$2; shift 2
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

  echo "verify --selftest: OK (renderer + honesty footer + non-vacuous control-PASS + INCOMPLETE-on-interrupt"
  echo "                       + K3: a FAILING check surfaces its diagnostic, a PASSING one stays one line)"; exit 0
fi

echo "Conformance verification (honest aggregate)"
echo "-------------------------------------------"
check control agent-autonomy   sh conformance/agent-autonomy.sh
check control agent-boundary   sh conformance/agent-boundary.sh --selftest
check control harness-adapter  sh conformance/harness-adapter.sh adapters/claude-code
check control harness-generic  sh conformance/harness-adapter.sh adapters/generic
check control harness-adapter-selftest sh conformance/harness-adapter.sh --selftest
check control harness-ceiling          sh conformance/harness-ceiling-disclosed.sh
check control harness-ceiling-selftest  sh conformance/harness-ceiling-disclosed.sh --selftest
check control validation-terminal-state           sh conformance/validation-terminal-state-documented.sh
check control validation-terminal-state-selftest   sh conformance/validation-terminal-state-documented.sh --selftest
check control feedback-link-lifecycle              sh conformance/feedback-link-lifecycle-documented.sh
check control feedback-link-lifecycle-selftest      sh conformance/feedback-link-lifecycle-documented.sh --selftest
check control named-adapters-selftest  sh conformance/named-adapters.sh --selftest
check control ci-gates         sh conformance/ci-gates.sh profiles/typescript-node/ci.yml --expect-seams
check control ci-gates-selftest sh conformance/ci-gates.sh --selftest
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
# sweep to lock, so the check would correctly FAIL on every adopter. Same reason verify-enforced-wired.sh
# is absent from this list. Both are enforced as ci.yml STEPS (in conformance-core, a shard of the
# required `conformance` aggregate) — a failure there still reddens the required check. Caught by
# artifact-gate on PR #309: the kit's own gate, run on the INCEPTED artifact, is what found this.
check control onboarding       sh conformance/onboarding-complete.sh
check control discovery        sh conformance/discovery-complete.sh
check control adopter-preflight sh conformance/adopter-preflight-wired.sh
check control adopter-export   sh conformance/adopter-export-wired.sh
check control mode-blind       sh conformance/mode-enforcement-blind.sh
check control orchestrator-loop sh conformance/orchestrator-loop-wired.sh
check control escalation-seam    sh conformance/escalation-wired.sh --selftest
check control proportional-gate sh conformance/proportional-gate-wired.sh --selftest
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
# KW6-A2 presence gate: selftest ONLY — no `-run` companion. Unlike backlog-current, the real run
# needs a live PR number (--pr), which exists only in PR context, so it cannot run as an offline
# verify.sh control-check; the ci.yml `backlog-presence` job calls check_pr live. check_pr is NOT dead
# code: selftest() drives it by argument (assert_msg), and the CI job invokes it on every gated PR.
check control backlog-presence  sh conformance/backlog-presence.sh --selftest
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
printf 'Summary: %d control-checks · %d doc-checks · %d unverified · %d failed\n' "$controls" "$docs" "$unverified" "$failed"
echo "A green run proves controls hold AND release/DR/resilience safety is DOCUMENTED —"
echo "it does NOT prove those procedures were tested. doc-checks verify records exist."
echo "UNVERIFIED is NOT a pass. See conformance/README.md \"What a green run means\"."

if [ "$ctrl_fail" != "0" ]; then echo "RESULT: FAIL (a control check failed)"; exit 1; fi
if [ "$REQUIRE" = "1" ] && [ "$unverified" != "0" ]; then echo "RESULT: FAIL (unverified under --require/CI)"; exit 1; fi
echo "RESULT: OK (controls verified; docs present)"; exit 0
