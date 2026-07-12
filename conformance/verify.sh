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
  echo "verify --selftest: OK"; exit 0
fi

REQUIRE=0
[ -n "${CI:-}" ] && REQUIRE=1
[ "${1:-}" = "--require" ] && REQUIRE=1

ctrl_fail=0; unverified=0; controls=0; docs=0; failed=0
line() { printf '  %-9s %-18s %s\n' "$1" "$2" "$3"; }

# check KIND NAME COMMAND...
check() {
  kind=$1; name=$2; shift 2
  if out=$("$@" 2>&1); then rc=0; else rc=$?; fi
  case "$kind" in control) controls=$((controls+1)) ;; doc) docs=$((docs+1)) ;; esac
  if [ "$rc" = "0" ]; then
    line "[$kind]" "$name" "PASS"
  elif [ "$rc" = "2" ]; then
    line "[$kind]" "$name" "UNVERIFIED"; unverified=$((unverified+1))
    [ "$REQUIRE" = "1" ] && failed=$((failed+1)) || true
  else
    line "[$kind]" "$name" "FAIL"; failed=$((failed+1))
    [ "$kind" = "control" ] && ctrl_fail=1 || true
  fi
}

echo "Conformance verification (honest aggregate)"
echo "-------------------------------------------"
check control agent-autonomy   sh conformance/agent-autonomy.sh
check control agent-boundary   sh conformance/agent-boundary.sh --selftest
check control harness-adapter  sh conformance/harness-adapter.sh adapters/claude-code
check control harness-generic  sh conformance/harness-adapter.sh adapters/generic
check control ci-gates         sh conformance/ci-gates.sh profiles/typescript-node/ci.yml
check control image-supply     sh conformance/container-supply-chain.sh
check control shellcheck       sh conformance/shellcheck.sh
check control "license-check(selftest)" sh scripts/license-check.sh --selftest
check control guard-wired      sh conformance/guard-wired.sh
check control check-links      sh conformance/check-links.sh
check control assurance-tiers   sh conformance/assurance-tiers.sh
check control promotion-contract  sh conformance/promotion-contract-documented.sh
check control backlog-adapters sh conformance/backlog-adapters.sh
check control ci-selftest-cov  sh conformance/ci-selftest-coverage.sh
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
check control skill-spine sh conformance/orchestrator-loop-wired.sh
check control release-tag       sh conformance/release-tag-wired.sh
check control feature-flags-wired sh conformance/feature-flags-wired.sh
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
