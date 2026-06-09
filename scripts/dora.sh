#!/bin/sh
# dora.sh — report the GitHub-derivable DORA subset for the current repo.
#
# A REPORT, not a gate. Computes what is universally derivable from any GitHub repo
# (release cadence, PR lead time, review latency) via `gh` (+ gh's built-in --jq for
# date math — no separate jq needed). Metrics that need deployment + incident data
# (true deployment frequency, change-failure rate, MTTR, retro-action closure) are
# ADOPTER-WIRED and printed with how-to pointers. DEGRADES GRACEFULLY — any gh failure
# (no gh / no auth / missing scope / no network) prints "unavailable" for that metric
# and continues — and ALWAYS exits 0. A reporting tool must never fail a pipeline for
# lack of data. See docs/operations/dora-metrics.md.
#
# Usage:
#   sh scripts/dora.sh [--window DAYS]   (default 30)
#   sh scripts/dora.sh --selftest        (deterministic degradation self-test; no network)
set -eu

WINDOW="${WINDOW:-30}"
case "$WINDOW" in ""|*[!0-9]*) echo "WINDOW must be a positive integer" >&2; exit 2 ;; esac
[ "$WINDOW" -gt 0 ] || { echo "WINDOW must be a positive integer (got 0)" >&2; exit 2; }

have_gh() {
  [ "${DORA_FORCE_NO_GH:-0}" = "1" ] && return 1
  command -v gh >/dev/null 2>&1
}

report() {
  echo "DORA metrics (GitHub-derivable subset) — window: ${WINDOW}d"
  echo "---------------------------------------------------------------"

  if ! have_gh; then
    echo "gh not available (install GitHub CLI + run 'gh auth login') — GitHub-derivable metrics need it:"
    echo "  - Release cadence: unavailable (needs gh)"
    echo "  - PR lead time: unavailable (needs gh)"
    echo "  - Review latency: unavailable (needs gh)"
  else
    # Release cadence (deployment-frequency proxy): releases published within the window.
    if rc="$(gh api "repos/{owner}/{repo}/releases?per_page=100" \
              --jq "[.[] | select(((.published_at // .created_at)|fromdateiso8601) > (now - ${WINDOW}*86400))] | length" 2>/dev/null)"; then
      echo "  - Release cadence: ${rc} release(s) in last ${WINDOW}d (deployment-frequency proxy; true deploy-freq adopter-wired)"
    else
      echo "  - Release cadence: unavailable (needs gh auth + contents:read)"
    fi

    # PR lead time (lead-time proxy): avg created->merged hours for PRs merged in the window.
    if lt="$(gh pr list --state merged --limit 200 --json createdAt,mergedAt \
              --jq "[.[] | select(.mergedAt != null) | select((.mergedAt|fromdateiso8601) > (now - ${WINDOW}*86400)) | ((.mergedAt|fromdateiso8601) - (.createdAt|fromdateiso8601))] | if length > 0 then (add/length/3600 | floor) else -1 end" 2>/dev/null)"; then
      if [ "$lt" = "-1" ] || [ -z "$lt" ]; then
        echo "  - PR lead time: no PRs merged in last ${WINDOW}d"
      else
        echo "  - PR lead time: ~${lt} h avg created->merged (lead-time proxy; deploy leg adopter-wired)"
      fi
    else
      echo "  - PR lead time: unavailable (needs gh auth + pull-requests:read)"
    fi

    # Review latency (agentic): avg created->first-review hours (->merged if no review).
    if rl="$(gh pr list --state merged --limit 200 --json createdAt,mergedAt,reviews \
              --jq "[.[] | select(.mergedAt != null) | select((.mergedAt|fromdateiso8601) > (now - ${WINDOW}*86400)) | ((if (.reviews|length) > 0 then (.reviews[0].submittedAt|fromdateiso8601) else (.mergedAt|fromdateiso8601) end) - (.createdAt|fromdateiso8601))] | if length > 0 then (add/length/3600 | floor) else -1 end" 2>/dev/null)"; then
      if [ "$rl" = "-1" ] || [ -z "$rl" ]; then
        echo "  - Review latency: no PRs merged in last ${WINDOW}d"
      else
        echo "  - Review latency: ~${rl} h avg created->first-review (human-bottleneck signal, §14)"
      fi
    else
      echo "  - Review latency: unavailable (needs gh auth + pull-requests:read)"
    fi
  fi

  echo ""
  echo "Adopter-wired (need deployment + incident data — see docs/operations/dora-metrics.md):"
  echo "  - Deployment frequency (true): record GitHub Deployments from your deploy workflow"
  echo "  - Change-failure rate: deployments causing an incident/revert / total deployments"
  echo "  - MTTR: incident open->resolved (the postmortem / incident records, standards §15)"
  echo "  - Retro-action closure (agentic): share of retro action items closed (backlog labels, process §6)"
}

selftest() {
  out="$(DORA_FORCE_NO_GH=1 sh "$0" 2>/dev/null)" || { echo "dora --selftest: FAIL (non-zero exit on no-gh path)" >&2; return 1; }
  printf '%s\n' "$out" | grep -q "gh not available" || { echo "dora --selftest: FAIL (missing degradation message)" >&2; return 1; }
  printf '%s\n' "$out" | grep -q "Adopter-wired" || { echo "dora --selftest: FAIL (missing adopter-wired block)" >&2; return 1; }
  echo "dora --selftest: OK (no-gh path degrades cleanly and exits 0)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --window)
    WINDOW="${2:-}"
    case "$WINDOW" in ""|*[!0-9]*) echo "usage: --window needs a positive integer" >&2; exit 2 ;; esac
    [ "$WINDOW" -gt 0 ] || { echo "usage: --window needs a positive integer (got 0)" >&2; exit 2; }
    report; exit 0 ;;
  "") report; exit 0 ;;
  *) echo "usage: sh scripts/dora.sh [--window DAYS] | --selftest" >&2; exit 2 ;;
esac
