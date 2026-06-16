#!/bin/sh
# wf-helpers.sh — shared helpers for the conformance checks (single source of truth).
# SOURCED, not executed: checks do `. "$(dirname "$0")/wf-helpers.sh"` near the top, the same
# pattern .claude/hooks/guard.sh + hooks/pre-push use to source guard-core.sh. No `set -eu`
# here (the sourcing script owns shell options); this file defines functions only. It is not a
# conformance check itself (no --selftest, not in verify.sh) — it is linted by shellcheck.sh.

# Does $1 (a workflow file) indicate a deploy surface? We match only STRUCTURAL
# deploy signals — a GitHub deployment `environment:` key, or a job KEY named
# deploy-ish (`deploy:`, `deploy-prod:`). We deliberately do NOT match free-text
# step `name:`/`id:` containing "deploy": that over-triggers on benign workflows
# like a "deploy docs" GitHub Pages step, which would wrongly force release-readiness
# on a non-service project (a library/CLI). Detection stays conservative; the
# definition-of-deployable.md checklist is the gate of record, so a missed signal is
# still caught by a human applying the checklist. (_wf is prefixed to avoid clobbering
# a caller's `wf` loop variable — POSIX sh functions have no local scope.)
wf_is_deploy() {
  _wf="$1"
  if grep -Eq '^[[:space:]]*environment:' "$_wf"; then return 0; fi
  if grep -Eq '^[[:space:]]+deploy[A-Za-z0-9_-]*:[[:space:]]*$' "$_wf"; then return 0; fi
  return 1
}
