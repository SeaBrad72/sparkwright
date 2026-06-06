#!/bin/sh
# ci-gates.sh — conformance check for DEVELOPMENT-STANDARDS.md §14 (CI/CD Pipeline).
# Asserts a CI workflow declares all required quality gates by their standardized
# step ids. Checks contract identifiers, not stack tools, so it is stack-neutral:
# any workflow that adopts these ids can be verified, in any language.
#
# Usage: sh conformance/ci-gates.sh <workflow-file>
# Exit:  0 = all gates present; 1 = missing gate(s) or bad usage.
#
# Matching is best-effort and structural: a gate counts only when `id: <gate>`
# appears as a YAML key at the start of a line (leading whitespace allowed),
# NOT inside a comment or a quoted value. This prevents a workflow from passing
# by merely *mentioning* a gate id (e.g. `# id: gate-lint`) without running it.
# It does not parse YAML, so a gate id inside a multi-line block scalar could
# still be a false positive. For stronger guarantees use a YAML parser, e.g.
#   yq -r '.jobs[].steps[].id' <workflow> | grep -Fxq <gate>
# This shell check is a portable, zero-dependency gate and should be paired with
# the pipeline actually running (the kit's own CI runs the real workflow).
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
  if ! grep -Eq "^[[:space:]]*(-[[:space:]]+)?id:[[:space:]]*[\"']?${gate}[\"']?[[:space:]]*(#.*)?\$" "$WORKFLOW"; then
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
