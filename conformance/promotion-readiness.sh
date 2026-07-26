#!/bin/sh
# promotion-readiness.sh — derive the change-class of a change-set and emit the promotion-readiness
# surfacing that INFORMS a human GO/NO-GO. ADVISORY ONLY: it surfaces, it never gates (exit 0
# always; the proportional GATES are slice 3 of the Proportional Promotion Contract,
# docs/governance/promotion-contract.md). Reuses the guard's is_control_plane_path as the SINGLE
# source of control-plane detection (sourced, never duplicated).
#
#   conformance/promotion-readiness.sh [--changed FILE] [--rung RUNG] [--class] [--no-verify]
# Change-class: control-plane > sensitive > ordinary (highest present wins). FAIL-SAFE: an empty or
# unreadable change-set, an unavailable guard core, **an unresolvable merge-base**, or **a newline byte in
# any path name** classifies control-plane (never silently ordinary). Class is DERIVED, never
# self-asserted — there is no flag to declare a lower class.
#
# ⚠️ DISCLOSED CEILING — SUBMODULES. This is a stated LIMIT, not one of the fail-safe conditions above:
# a changed gitlink is classified on the SUBMODULE PATH ALONE and is NOT escalated. Neither
# `git diff --name-only` on the superproject nor the forge's PR-files API descends into a gitlink, so a
# bump of `vendor/dep` emits exactly `vendor/dep` — the interior paths never reach classification.
# Measured 2026-07-26 with a live superproject+submodule fixture.
#   WHY NOT ESCALATED: control-plane PATTERNS inside a submodule are not control-plane AUTHORITY in the
#   superproject — GitHub Actions reads workflows only from the superproject, so a submodule's
#   `.github/workflows/*` never runs. A gitlink is a PINNED THIRD-PARTY DEPENDENCY WITH A RATIFIED CALL
#   SITE, structurally like a lockfile bump, a `uses: org/action@sha` pin, or a container digest — none
#   of which this kit classes as control-plane. Escalating gitlinks alone would be an inconsistency
#   dressed as a fix.
#   THE RESIDUAL THAT DOES BITE (this is the half worth knowing): if the superproject EXECUTES content
#   from the submodule — a workflow step running `vendor/dep/script.sh`, or a symlink from a
#   control-plane path into it — then that content has authority this gate never classified. Creating
#   such a call site is ITSELF a control-plane change and is ratified once; only subsequent CONTENT
#   changes ride free.
#   Policy for opaque subtrees is deliberately unsettled here and is boarded as `SUBMODULE-CLASS-POLICY`
#   (likely shape: an adopter-declared submodule policy, declared ONCE rather than per bump). Adopters
#   using submodules carry this residual today.
#   NOTE FOR LOCAL USE: the base is resolved as `origin/main` then `main` ONLY. On a checkout whose default
#   branch is `master`/`trunk`/`develop`, or a detached HEAD with no remote, no base resolves — so a local
#   run reports `control-plane` for EVERYTHING. That is deliberate (the old fallback compared the WORKTREE
#   to HEAD, which one dirty ordinary file could use to hide every committed control-plane change). To
#   classify a specific set instead, pass `--changed FILE`. CI is unaffected: every CI caller passes it.
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
  # A2 (case). The control-plane half above folds inside is_control_plane_path; the SENSITIVE tier below
  # is a second, independent matcher and was byte-literal — measured: `Auth/x`, `*.PEM` and `.ENV` all
  # fell through to `ordinary`, lowering the ceremony for exactly the reason A2 exists.
  #
  # ⚠️ EVALUATE BOTH SPELLINGS AND TAKE THE HIGHER CLASS — do NOT simply substitute the folded form.
  # An earlier draft replaced the subject and evaluated once, which is NOT monotone: the `.env.example`
  # EXEMPT branch comes first, so folding let a path reach an exemption it could not reach unfolded.
  # Measured downgrade: `secrets/.ENV.EXAMPLE` and `auth/.ENV.TEMPLATE` went sensitive -> ORDINARY.
  # is_control_plane_path is safe because it ORs (literal OR folded); this function must do the same.
  _cs=$_p
  case "$_p" in *[A-Z]*) _cs=$(printf '%s' "$_p" | LC_ALL=C tr 'A-Z' 'a-z') ;; esac
  if [ "$_cs" != "$_p" ]; then
    _c_raw=$(_classify_one "$_p")
    _c_fold=$(_classify_one "$_cs")
    # highest wins: sensitive > ordinary (control-plane is already returned above)
    if [ "$_c_raw" = sensitive ] || [ "$_c_fold" = sensitive ]; then echo sensitive; else echo ordinary; fi
    return
  fi
  _classify_one "$_p"
}

# The literal tier matcher, factored out so classify_path can evaluate both spellings and take the
# higher class. Returns ordinary|sensitive for a path already known not to be control-plane.
_classify_one() {
  _p=$1
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
  # NO RESOLVABLE BASE -> DERIVE FAILURE (H3). Previously an empty $base fell through to the
  # `git diff --name-only HEAD` fallback, which is WORKTREE-vs-HEAD, not branch-vs-base. Measured: with
  # a single dirty ORDINARY file the fallback returned exactly that one path, so n=1, the n=0 fail-safe
  # never fired, and every COMMITTED control-plane change on the branch was invisible -> `ordinary`.
  # That is fail-OPEN on the derivation feeding a §13 authorization decision. This now matches
  # obligation-lib.sh's obl_changeset (referenced BY NAME): an underivable base is a DERIVE FAILURE,
  # which the fail-safe routes to `control-plane`. Removes a divergence that used to be documented as
  # deliberate. An operator who genuinely wants to classify a specific set passes `--changed FILE`.
  [ -n "$base" ] || CHANGED_READ_FAIL=1
  # PATH QUOTING (PROMOTION-PATH-QUOTING; mirrors the `git -c core.quotePath=false … -z` derivation
  # in obligation-lib.sh's obl_changeset — referenced BY NAME, never by line number: an earlier
  # citation here drifted twice as that function's commentary grew, which is the same staleness class
  # BOARD-ROW-ARITY and the T1/T2 comment corrections were about).
  # Under git's default core.quotePath=true a path with any non-ASCII byte is emitted WRAPPED IN
  # DOUBLE QUOTES with octal escapes ("\.github/workflows/d\303\251ploy.yml"). The leading '"'
  # defeats is_control_plane_path, so an accented control-plane file classified `ordinary` and the
  # §13 promotion ceremony silently downgraded from human-ratified to agent-autonomous.
  # RENAMES (PROMOTION-RENAME-CLASS-DOWNGRADE; T2 in THREAT-MODEL.md — the same `--no-renames` fix
  # obligation-lib.sh's obl_changeset carries, again referenced BY NAME, not by line number).
  # Git detects renames BY DEFAULT and `--name-only` then emits ONLY THE DESTINATION path, so a file
  # moved OUT of the control-plane set is classified on its destination alone: measured on git 2.48.1,
  # a repo whose only change is `git mv .github/workflows/deploy.yml docs/x.yml` scores R100, derives
  # `docs/x.yml` alone, and classified `ordinary` — the §13 ceremony silently downgraded from
  # human-ratified to agent-autonomous. Same failure shape as PROMOTION-PATH-QUOTING, different door,
  # same function. `--no-renames` is a FLAG, so it also overrides a user's or a CI host's
  # `diff.renames` config — a config-only fix would be defeated by the next runner.
  # MONOTONE: un-collapsing an `R` entry can only ever ADD the source path, and the aggregate is the
  # HIGHEST class present, so no change-set can classify LOWER after this fix.
  # MONOTONE: unquoting can only ever ADD matches — no change-set can classify LOWER after this fix.
  # WHICH HALF IS PROVEN — measured, not reasoned. Mutants run against
  # `sh conformance/promotion-readiness-wired.sh --selftest`:
  #   drop `-z` only                   -> quote-in-name leg RED   (that leg is its ONLY killer)
  #   drop `core.quotePath=false` only -> ALL THREE LEGS SURVIVE   (unproven — see below)
  #   drop both                        -> nonascii AND quote-in-name RED
  # So `-z` is the strictly stronger control and is the half that carries this fix: NUL output is
  # never quoted at all, whereas core.quotePath=false only stops non-ASCII octal escaping and still
  # quotes a path containing '"'. core.quotePath=false is retained as defense-in-depth for readers
  # and for any future non-`-z` consumer, but NO leg proves it — do not claim otherwise.
  # A temp file, NOT a pipe: `git … | tr` makes the pipeline's status tr's and would discard the
  # derive-failure signal the `CHANGED_READ_FAIL` fail-safe below depends on (by NAME, not by line number —
  # this file's own rule, and the numeric form had already drifted twice). POSIX sh has no PIPESTATUS.
  # NEWLINE-IN-NAME: no longer mis-split — DETECTED and routed to the fail-safe (see the detector below).
  # The old ceiling here said newline-in-name "is not covered"; that was a disclosed FAIL-OPEN, and the
  # residual that bounded it wrongly claimed control-plane was safe from it. Both are now closed by
  # refusing to classify a change-set whose NUL stream carries a newline byte.
  _z=$(mktemp 2>/dev/null) || _z=""
  if [ -z "$_z" ]; then
    CHANGED_LIST=""; CHANGED_READ_FAIL=1
  else
    if [ -n "$base" ]; then
      if git -c core.quotePath=false diff --name-only -z --no-renames "$base"...HEAD > "$_z" 2>/dev/null; then _ok=1; else _ok=0; fi
    else
      if git -c core.quotePath=false diff --name-only -z --no-renames HEAD > "$_z" 2>/dev/null; then _ok=1; else _ok=0; fi
    fi
    # NEWLINE-IN-FILENAME -> DERIVE FAILURE (fail-closed). A path containing a literal newline cannot be
    # carried through `$()` in POSIX sh, so `tr '\0' '\n'` SPLITS it into fragments and each fragment is
    # classified separately. That is a real DOWNGRADE, not a cosmetic limit, and the "control-plane is
    # fail-safe" reading was WRONG: `is_control_plane_path` includes SUFFIX-constrained patterns
    # (`agents/*.agent.md`), so `agents/x<newline>.agent.md` splits into `agents/x` + `.agent.md` and
    # NEITHER fragment matches -> ordinary. Sensitive patterns split the same way (`*secret*`, `*.pem`).
    # We cannot PRESERVE such a path in POSIX sh — but we can DETECT it, which is all fail-closed needs:
    # the NUL stream from `-z` contains a newline byte ONLY when a filename does. Measured: 0 for every
    # well-formed change-set, >=1 for a crafted one. So refuse to classify instead of mis-classifying.
    if [ "$_ok" = 1 ] && [ "$(LC_ALL=C tr -cd '\n' < "$_z" | wc -c | tr -d ' ')" != 0 ]; then
      _ok=0   # a filename carries a literal newline -> route to the fail-safe, never split-and-classify
    fi
    if [ "$_ok" = 1 ]; then
      CHANGED_LIST=$(tr '\0' '\n' < "$_z") || CHANGED_READ_FAIL=1
    else
      CHANGED_LIST=""; CHANGED_READ_FAIL=1
    fi
    rm -f "$_z"
  fi
fi

# Aggregate = highest class present.
agg=ordinary; n=0
# `IFS= read` is command-scoped -- never a global IFS assignment (semgrep: ifs-tampering).
# Heredoc-fed, NOT piped: the loop stays in this shell, so `agg` and `n` survive it.
# `read` performs no pathname expansion, so the old `set -f` glob guard is now redundant.
while IFS= read -r _p; do
  [ -n "$_p" ] || continue
  n=$((n+1))
  c=$(classify_path "$_p")
  case "$c" in
    control-plane) agg=control-plane ;;
    sensitive) [ "$agg" = control-plane ] || agg=sensitive ;;
  esac
done <<CHANGED_EOF
$CHANGED_LIST
CHANGED_EOF

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
    control-plane:integration) echo "Dev-clone authoring + control-plane-ratification" ;;
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
# RENDER BOUNDARY — strip control bytes from attacker-influenceable path names (H2).
# WHY: PROMOTION-PATH-QUOTING (v3.184.0) replaced git's default core.quotePath=true — which ESCAPED
# control bytes — with `-z` + quotePath=false, which passes them through RAW. Nothing then stripped
# them, and every path is rendered into the surfacing a HUMAN READS to give the §13 GO. Measured: a
# filename carrying CR + ESC[2K + ESC[1A prints a FORGED "2. Change-class (aggregate): ordinary" line
# and scrolls the true `control-plane` line away. A PR author names files, so this is untrusted input
# reaching a decision surface — the class already fixed in a11y-obligation.sh (referenced BY NAME).
# STRIP AT RENDER ONLY, NEVER BEFORE classify_path: stripping before classification would let a
# crafted name become a DIFFERENT (lower) class — the fail-OPEN direction. Classification above sees
# the raw bytes; only the human-facing echo is sanitized.
# CEILING: removes control bytes, not a merely misleading printable name (e.g. a homoglyph).
_render_safe() { LC_ALL=C printf '%s' "$1" | LC_ALL=C tr -d '\000-\010\013-\037\177'; }
# DERIVE-FAILURE DISCLOSURE. When the base was underivable the class is fail-safed to control-plane, but
# the listing below is a WORKTREE-vs-HEAD diff — the very derivation this check condemns — so printing it
# unlabelled next to a `control-plane` verdict makes the two sections contradict each other on the surface
# a human reads to give the §13 GO. Say so plainly instead.
# Branch the wording on WHICH cause fired: with no resolvable base the listing below is a worktree diff;
# with a newline in a path name the listing is EMPTY. Saying "worktree diff" for both is inaccurate in one
# of its own branches, on the surface a human reads to give the §13 GO.
if [ "$CHANGED_READ_FAIL" = 1 ] && [ -z "${CHANGED:-}" ]; then
  if [ -z "$base" ]; then
    echo "   (derive failure: NO RESOLVABLE BASE — the class below is FAIL-SAFED to control-plane, and the"
    echo "    listing that follows is a WORKTREE diff, not the branch's change-set. The base is resolved as"
    echo "    origin/main then main only; pass --changed FILE to classify a specific set.)"
  else
    echo "   (derive failure: A PATH NAME CARRIES A NEWLINE — such a path cannot be carried through POSIX"
    echo "    sh without splitting into fragments that classify separately, so the class below is"
    echo "    FAIL-SAFED to control-plane and the listing that follows is EMPTY, not the change-set.)"
  fi
fi
echo "1. What changed ($n path(s)):"
printf '%s\n' "$CHANGED_LIST" | while IFS= read -r _q; do [ -n "$_q" ] || continue; printf '   [%s] %s\n' "$(classify_path "$_q")" "$(_render_safe "$_q")"; done
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
echo "7. Demonstrable increment (taste-surface):"
echo "   If this change has a taste-surface (UI/UX/flow/working-functionality/table), demonstrate it and record the verdict in a UAT sign-off (skills/demonstrate). Advisory — surfaced, not gated this slice."
echo ""
echo "(Advisory surfacing — informs the human GO/NO-GO. It does not gate; exit 0.)"
exit 0
