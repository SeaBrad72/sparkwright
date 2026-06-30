#!/bin/sh
# promotion-readiness.sh — derive the change-class of a change-set and emit the promotion-readiness
# surfacing that INFORMS a human GO/NO-GO. ADVISORY ONLY: it surfaces, it never gates (exit 0
# always; the proportional GATES are slice 3 of the Proportional Promotion Contract,
# docs/governance/promotion-contract.md). Reuses the guard's is_control_plane_path as the SINGLE
# source of control-plane detection (sourced, never duplicated).
#
#   conformance/promotion-readiness.sh [--changed FILE] [--rung RUNG] [--class] [--no-verify]
# Change-class: control-plane > sensitive > ordinary (highest present wins). FAIL-SAFE: an empty or
# unreadable change-set, or an unavailable guard core, classifies control-plane (never silently
# ordinary). Class is DERIVED, never self-asserted — there is no flag to declare a lower class.
#   --changed FILE  newline-delimited path list (default: git diff --name-only vs the merge-base)
#   --rung RUNG     spike|integration|rc|staging|production (default rc — the meaningful go/no-go)
#   --class         print only the aggregate class and exit (the stable seam slice 3 consumes)
#   --no-verify     skip the proven-vs-attested verify.sh invocation
# (selftest lives on conformance/promotion-readiness-wired.sh — this producer has none of its own.)
# Exit: 0 always (advisory) · 2 = usage. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true

CORE=".claude/hooks/guard-core.sh"
RUNG=rc; CLASS_ONLY=0; NO_VERIFY=0; CHANGED=""; CHANGED_READ_FAIL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --changed) [ $# -ge 2 ] || { echo "usage: --changed needs a FILE" >&2; exit 2; }; CHANGED=$2; shift 2 ;;
    --rung) [ $# -ge 2 ] || { echo "usage: --rung needs a RUNG" >&2; exit 2; }; RUNG=$2; shift 2 ;;
    --class) CLASS_ONLY=1; shift ;;
    --no-verify) NO_VERIFY=1; shift ;;
    *) echo "usage: promotion-readiness.sh [--changed FILE] [--rung RUNG] [--class] [--no-verify]" >&2; exit 2 ;;
  esac
done
case "$RUNG" in spike|integration|rc|staging|production) ;;
  *) echo "usage: --rung must be spike|integration|rc|staging|production" >&2; exit 2 ;; esac

# Source the guard core for is_control_plane_path (single source of truth). Fail-safe if absent.
GUARD_OK=1
# shellcheck source=/dev/null  # $CORE is a fixed kit path resolved at runtime, not statically followable
if [ -f "$CORE" ]; then . "$CORE"; else GUARD_OK=0; fi
command -v is_control_plane_path >/dev/null 2>&1 || GUARD_OK=0

# classify_path <path> -> ordinary|sensitive|control-plane
classify_path() {
  _p=$1
  if [ "$GUARD_OK" = 1 ] && is_control_plane_path "$_p"; then echo control-plane; return; fi
  case "$_p" in
    .env.example|*/.env.example|.env.sample|*/.env.sample|.env.template|*/.env.template|.env.dist|*/.env.dist)
      echo ordinary; return ;;
    auth/*|*/auth/*|payments/*|*/payments/*|migrations/*|*/migrations/*|\
    *secret*|keys/*|*/keys/*|*id_rsa*|*id_ecdsa*|*id_ed25519*|*.key|*.pem|.env|*/.env|.env.*|*/.env.*)
      # secret coverage is a SUPERSET of the guard's own read-secret set (guard-core.sh:68) —
      # the classifier must never under-detect what the guard already flags as secret.
      echo sensitive; return ;;
  esac
  echo ordinary
}

# Resolve the change-set into $CHANGED_LIST (one path per line); FAIL-SAFE on any failure.
if [ -n "$CHANGED" ]; then
  if [ -f "$CHANGED" ]; then CHANGED_LIST=$(cat "$CHANGED"); else CHANGED_LIST=""; CHANGED_READ_FAIL=1; fi
else
  base=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || true)
  if [ -n "$base" ]; then
    CHANGED_LIST=$(git diff --name-only "$base"...HEAD 2>/dev/null || true)
  else
    CHANGED_LIST=$(git diff --name-only HEAD 2>/dev/null || true)
  fi
fi

# Aggregate = highest class present.
agg=ordinary; n=0
OLDIFS=$IFS; IFS='
'
set -f  # no pathname expansion: a changed path containing '*' must not glob-expand against cwd
for _p in $CHANGED_LIST; do
  [ -n "$_p" ] || continue
  n=$((n+1))
  c=$(classify_path "$_p")
  case "$c" in
    control-plane) agg=control-plane ;;
    sensitive) [ "$agg" = control-plane ] || agg=sensitive ;;
  esac
done
set +f
IFS=$OLDIFS

# FAIL-SAFE: no readable change-set, or a degraded classifier -> highest class.
if [ "$n" = 0 ] || [ "$CHANGED_READ_FAIL" = 1 ] || [ "$GUARD_OK" = 0 ]; then agg=control-plane; fi

if [ "$CLASS_ONLY" = 1 ]; then echo "$agg"; exit 0; fi

# disposition <class> <rung> -> the matrix cell text (mirrors docs/governance/promotion-contract.md)
disposition() {
  case "$1:$2" in
    ordinary:spike) echo "Agent autonomous (L3); cheap gates advisory; no human gate" ;;
    ordinary:integration) echo "Automated gates required; agent self-review; GO lightweight/delegable" ;;
    ordinary:rc) echo "The meaningful go/no-go — human GO vs this surfacing; builder != reviewer; DoD + acceptance-criteria checked" ;;
    ordinary:staging) echo "smoke + acceptance sign-off" ;;
    ordinary:production) echo "human-commanded; progressive rollout; rollback ready" ;;
    sensitive:spike) echo "Human-gated (always)" ;;
    sensitive:integration) echo "High-risk review lane; human GO" ;;
    sensitive:rc) echo "full dual review + human GO" ;;
    sensitive:staging) echo "+ threat/privacy re-check" ;;
    sensitive:production) echo "human-commanded; irreversible-gated" ;;
    control-plane:spike) echo "Human-authored (always)" ;;
    control-plane:integration) echo "AMBER apply + control-plane-ratification" ;;
    control-plane:rc) echo "human ratify + meta-control" ;;
    control-plane:staging|control-plane:production) echo "N/A — control-plane does not deploy to runtime rungs" ;;
    *) echo "(unknown cell)" ;;
  esac
}

# Proven-vs-attested: reuse verify.sh's [control] vs [doc] split (the kit's own honesty stance).
pv="proven-vs-attested: skipped (--no-verify)"
if [ "$NO_VERIFY" = 0 ]; then
  if [ -f conformance/verify.sh ]; then
    pv=$(sh conformance/verify.sh 2>/dev/null | grep -E '^Summary:|UNVERIFIED is NOT a pass' || true)
    [ -n "$pv" ] || pv="proven-vs-attested: UNAVAILABLE (run conformance/verify.sh)"
  else
    pv="proven-vs-attested: UNAVAILABLE (conformance/verify.sh not found)"
  fi
fi

# Acceptance-criteria: BACKLOG.md if trivially present, else attest at the gate (slice 3+).
if [ -f BACKLOG.md ]; then ac="see BACKLOG.md for the story's acceptance criteria"; else ac="attest at gate (tracker-sourced at the RC gate — slice 3+)"; fi

echo "=== Promotion-readiness surfacing ==="
echo "Rung (destination): $RUNG"
echo ""
echo "1. What changed ($n path(s)):"
printf '%s\n' "$CHANGED_LIST" | while IFS= read -r _q; do [ -n "$_q" ] || continue; printf '   [%s] %s\n' "$(classify_path "$_q")" "$_q"; done
echo ""
echo "2. Change-class (aggregate): $agg"
echo ""
echo "3. Blast-radius (class x rung): $(disposition "$agg" "$RUNG")"
echo ""
echo "4. Proven-vs-attested:"
printf '%s\n' "$pv" | sed 's/^/   /'
echo ""
echo "5. DoD + acceptance-criteria:"
echo "   Definition of Done: see CLAUDE.md \"Definition of Done\""
echo "   ACCEPTANCE-CRITERIA: $ac"
echo ""
echo "6. Regression surface:"
echo "   REGRESSION-SURFACE: human attests (not auto-derived — this is the judgment, not a fact)"
echo ""
echo "(Advisory surfacing — informs the human GO/NO-GO. It does not gate; exit 0.)"
exit 0
