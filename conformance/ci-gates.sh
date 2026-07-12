#!/bin/sh
# ci-gates.sh — conformance check for DEVELOPMENT-STANDARDS.md §14 (CI/CD Pipeline).
# Asserts a CI workflow declares all required quality gates by their standardized
# step ids. Checks contract identifiers, not stack tools, so it is stack-neutral:
# any workflow that adopts these ids can be verified, in any language.
#
# Usage: sh conformance/ci-gates.sh <workflow-file>
# Exit:  0 = all gates present; 1 = missing gate(s) or bad usage.
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

WORKFLOW="${1:-}"

if [ -z "$WORKFLOW" ]; then
  echo "usage: ci-gates.sh <workflow-file>" >&2
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

echo "OK: $WORKFLOW declares all required CI gates ($REQUIRED)"
exit 0
