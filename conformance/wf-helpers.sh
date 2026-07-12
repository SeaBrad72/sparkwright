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

# wf_extract_links <file>: print each relative-Markdown-link target in <file>, with code regions
# removed FIRST — fenced blocks (``` / ~~~) AND inline `code` spans — so prose that merely *quotes*
# link syntax (e.g. documenting the `]( )` form in backticks) is not mistaken for a real link. A link
# inside code renders as text, never a live link, so ignoring it is correctness, not a loophole.
# Single source of truth for the kit's two link-checkers (check-links.sh + adopter-export-wired.sh).
# Conservative by design: rare nested-/mismatched-fence shapes may OVER-extract vs a strict CommonMark
# renderer — fail-safe (a possible false-flag, never a missed real link; verified against `marked`).
wf_extract_links() {
  awk '
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }   # toggle on a fence line; drop the fence line
    fence { next }                                       # drop everything inside a fenced block
    { gsub(/`[^`]*`/, ""); print }                       # drop inline `code` spans, keep the rest
  ' "$1" | grep -oE ']\([^)]+\)' | sed -E 's/^\]\(//; s/\)$//'
}
