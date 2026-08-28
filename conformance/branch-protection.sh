#!/bin/sh
# branch-protection.sh — verify `main` is actually protected on the remote, AND that the required
# status-check CONTEXTS match what REQUIRED-CHECKS.md declares (DEVELOPMENT-STANDARDS.md §14 /
# DEVELOPMENT-PROCESS.md §12). Split at the credential seam (B4):
#   OFFLINE leg (--declared-only [FILE]): parses REQUIRED-CHECKS.md — no `gh`, no network. Registered
#     in verify.sh and swept by non-vacuity.sh.
#   LIVE leg (default, no flag): the three-state remote check below. It asserts the REVIEW
#     REQUIREMENT IS REAL — `required_pull_request_reviews.required_approving_review_count >= 1`, not
#     merely that the settings block exists (an empty block requires nothing). That number is what
#     blocks an unratified control-plane merge, and since 2026-08-28 the `control-plane-ratification`
#     check renders WAITING as GREEN because of it (RATIFICATION-WAITING-IS-GREEN) — so this gate and
#     that rendering are one control, and the count is checked here or nowhere. It ALSO compares the
#     live `required_status_checks.contexts` against the declaration: a declared-but-unbound context FAILs
#     by name; a live-but-undeclared context is an ADVISORY (never fatal, never buries the existing
#     code-owner ADVISORY below it); no declaration file present -> behaves exactly as before
#     (byte-compatible rc for inception-done's --raw consumption).
# THREE-STATE contract (the live leg):
#   exit 0  — verified protected (PR reviews + status checks required, declared contexts all bound)
#   exit 1  — verified NOT protected / a required setting or a declared context missing (FAIL)
#   exit 2  — COULD NOT VERIFY (no gh, unauthenticated, or no GitHub remote) — NOT a pass.
# A silent pass when unverifiable is false assurance; this returns a distinct status.
# Escalation: in CI (CI env set) or with --require, "could not verify" becomes exit 1 —
# in a gate the check MUST be runnable. Requires `gh` authenticated to verify.
# Guardrails: --raw returns the un-escalated three-state (0/1/2), overriding ONLY the CI-triggered
#   auto-escalation below (the `[ "$RAW" = 0 ]` line) — an explicit --require passed alongside --raw
#   still escalates (that is NOT overridden by --raw; only the ambient-CI auto-escalation is), so a
#   policy-applying caller (inception-done) can tell "unverifiable" (2) from "verified-unprotected" (1).
#   usage: sh conformance/branch-protection.sh [BRANCH] [--require] [--raw]
#          sh conformance/branch-protection.sh --declared-only [FILE]   (offline; no gh; no network)
#          sh conformance/branch-protection.sh --selftest
# NOTE (T4-B1): the LIVE leg is NOT in the per-PR conformance aggregate (verify.sh) — it needs
# repo-admin creds the least-privilege CI token can't have, so it cannot be verified in per-PR/weekly
# CI. Real-path verification is maintainer/governance-gated (run locally with an admin-authenticated
# gh). The OFFLINE --declared-only leg IS registered in verify.sh — declaration integrity needs no
# creds. Config-as-code (github_branch_protection) + a least-privilege administration:read detective
# verifier are the E9 (env/promotion governance) reference.
# CEILING (B4): detection, not prevention — an admin who removes a bound context can also edit the
# declaration; real prevention is org rulesets / IaC (Terraform's github_branch_protection resource,
# named again in scripts/branch-protection-apply.sh). Operator-triggered, not continuous — no
# mechanism runs the live leg on a cadence; "the governance gate" is a maintainer with admin `gh`
# until a gate is deliberately built. `enforce_admins:false`, measured live: every required context
# is admin-bypassable by the kit's own prescribed solo merge path (`gh pr merge --admin`). The
# offline leg proves declaration INTEGRITY, never forge state. The apply script binds contexts; it
# cannot prevent later unbinding.
# GH ENV CONTAINMENT (B4 fix round 1, SEC M-3): every `gh` call below strips GH_HOST, GH_REPO,
# GH_ENTERPRISE_TOKEN, GH_CONFIG_DIR from the subshell before invoking `gh` — a hostile value in any
# of those could redirect the API host, retarget the mutation at a different repo, or swap the
# config/creds gh reads. GH_TOKEN is left untouched and honored (the operator's real credential).
# CONTEXT-NAME CHARSET (B4 fix round 1, SEC C-1/H-2/L-2..L-4): every parsed declared context name
# must match ^[A-Za-z0-9][A-Za-z0-9._/-]*$ with length<=100, checked identically here and in
# scripts/branch-protection-apply.sh (see valid_context_name() in both — item 9's selftest cell
# proves the two copies never drift). This is the ONLY charset that can never carry a JSON metachar,
# a shell case/glob metachar, or whitespace — closing the string-concat JSON-injection class at the
# parser, not just at the body builder, and closing the `*`-glob / word-split class `set -f` (below)
# closes structurally. GitHub context names containing spaces are NOT declarable in v1: fail-closed
# with a message naming the offending line, never a silent split (see the FAIL text below).
set -eu
set -f   # noglob — every `for x in $LIST` expansion in this file is data, never a filesystem glob;
         # a declared or live context containing `*`/`?`/`[` must never turn into a directory listing.

# REPO_ROOT — resolved once from $0, used to (a) find the DEFAULT REQUIRED-CHECKS.md regardless of
# the caller's CWD (SEC H-3: an explicit --declared-only FILE argument stays caller-relative; only
# the unspecified default resolves here) and (b) detect a kit-shaped tree for the presence rule in
# declared_only() (SEC H-4). Falls back to "." if resolution fails (never fatal here).
# shellcheck disable=SC1007 # `CDPATH= cd` clears CDPATH for this one command so a user's CDPATH
# cannot redirect the cd; the empty assignment is intentional, not a mistyped value.
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || REPO_ROOT=.

# is_kit_tree — DETECTED trigger, mirrors the OR-of-markers kit-self detector in
# meta-control-fresh.sh / adopter-export-wired.sh (un-spoofable: golden-path.yml is control-plane +
# export-ignored). NOT a declared-mode read.
is_kit_tree() {
  [ -f "$REPO_ROOT/docs/ROADMAP-KIT.md" ] || [ -f "$REPO_ROOT/.github/workflows/golden-path.yml" ]
}

REQUIRE="${REQUIRE:-0}"
RAW=0
BRANCH=main
DECLARED_ONLY=0
DECLARATION="REQUIRED-CHECKS.md"
DECL_EXPLICIT=0
for a in "$@"; do
  case "$a" in
    --require) REQUIRE=1 ;;
    --raw) RAW=1 ;;   # emit the un-escalated three-state (0/1/2), overriding ONLY the ambient-CI auto-escalation below; an explicit --require alongside --raw still escalates
    --declared-only) DECLARED_ONLY=1 ;;
    --selftest) ;;  # dispatched below
    -*) printf '%s\n' "usage: branch-protection.sh [BRANCH] [--require] [--raw] | --declared-only [FILE] | --selftest" >&2; exit 2 ;;
    *) if [ "$DECLARED_ONLY" = 1 ]; then DECLARATION="$a"; DECL_EXPLICIT=1; else BRANCH="$a"; fi ;;
  esac
done
[ "$DECL_EXPLICIT" = 1 ] || DECLARATION="$REPO_ROOT/REQUIRED-CHECKS.md"
[ "$RAW" = 0 ] && [ -n "${CI:-}" ] && REQUIRE=1   # CI makes the gate runnable — UNLESS --raw asked for the raw state

# Unverifiable: exit 2 normally; exit 1 (FAIL) under CI/--require (a gate must be runnable).
unverifiable() {
  if [ "$REQUIRE" = "1" ]; then
    printf '%s\n' "FAIL: branch-protection could not verify ($1) and verification is required (CI/--require)."
    exit 1
  fi
  printf '%s\n' "UNVERIFIED: $1 — run in CI or authenticate gh. (NOT a pass.)"
  exit 2
}

have_gh() {
  [ "${BP_FORCE_NO_GH:-0}" = "1" ] && return 1
  command -v gh >/dev/null 2>&1
}

# valid_context_name <name> -> 0 if it matches ^[A-Za-z0-9][A-Za-z0-9._/-]*$ and length<=100, else 1.
# This exact charset can never contain a quote/brace/colon/comma (JSON injection), a glob metachar
# (`*`, `?`, `[`), a leading `-` (a case pattern or a CLI flag could notice), or whitespace (breaks
# "for x in $LIST" word-splitting and printf sweeps). Duplicated verbatim in
# scripts/branch-protection-apply.sh (D4: that script is self-contained) — a selftest cell (below)
# proves the two copies stay identical.
valid_context_name() {
  _vcn=$1
  [ -n "$_vcn" ] || return 1
  [ "${#_vcn}" -le 100 ] || return 1
  case "$_vcn" in
    [A-Za-z0-9]*) : ;;
    *) return 1 ;;
  esac
  case "$_vcn" in
    *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  return 0
}

RD_MAX_LINES=100

# read_declaration <file> — parse the fenced ```...``` block: one context per line. Stops at the
# FIRST block's CLOSE (REV M1) — a second fence-open afterward is ignored, never merged into the
# context set (the measured bug: a usage-example block read as more declared contexts). A
# `#`-prefixed line is a comment/conditional (ignored). A line containing an angle-bracket
# placeholder (e.g. <your-check-name>) marks the file PRISTINE — neither an active context nor, on
# its own, an error. Every candidate line is charset-validated (valid_context_name, above) and the
# block is capped at RD_MAX_LINES candidate lines (SEC L-2: a DoS bound on parse cost — a huge
# declaration can no longer inflate iteration cost downstream). POSIX only (no jq): this side is our
# own trivially-greppable format (Δ7).
# Sets on return (never exits): RD_LIST (space-joined VALID, non-duplicate active contexts, may be
# empty), RD_PLACEHOLDER (0 or count), RD_DUP (0 or count), RD_DUP_NAME (first duplicate, if any),
# RD_INVALID (0 or count of charset-rejected candidate lines), RD_INVALID_NAME (the first rejected
# line, VERBATIM — always named in the FAIL message, never silently dropped), RD_TOOMANY (0 or 1:
# the RD_MAX_LINES candidate-line cap was hit).
read_declaration() {
  _rdf=$1
  RD_LIST=""; RD_PLACEHOLDER=0; RD_DUP=0; RD_DUP_NAME=""
  RD_INVALID=0; RD_INVALID_NAME=""; RD_TOOMANY=0
  _rd_in=0; _rd_done=0; _rd_n=0
  while IFS= read -r _rdl || [ -n "$_rdl" ]; do
    case "$_rdl" in
      '```'*)
        [ "$_rd_done" = 1 ] && continue   # a second fence-open after the first block's close is IGNORED
        if [ "$_rd_in" = 0 ]; then _rd_in=1; else _rd_in=0; _rd_done=1; fi
        continue ;;
    esac
    [ "$_rd_in" = 1 ] || continue
    _rdt=$(printf '%s' "$_rdl" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$_rdt" ] && continue
    case "$_rdt" in
      '#'*) continue ;;
    esac
    _rd_n=$((_rd_n + 1))
    if [ "$_rd_n" -gt "$RD_MAX_LINES" ]; then RD_TOOMANY=1; continue; fi
    case "$_rdt" in
      *'<'*'>'*) RD_PLACEHOLDER=$((RD_PLACEHOLDER + 1)); continue ;;
    esac
    if ! valid_context_name "$_rdt"; then
      RD_INVALID=$((RD_INVALID + 1))
      # R-3: sanitize BEFORE it is ever captured, not at each print site — every FAIL/ADVISORY
      # diagnostic that names RD_INVALID_NAME (declared_only() and classify()'s skip-ladder) then
      # inherits the sanitized form for free. A raw control byte (e.g. ESC) in an offending line
      # was measured erasing the FAIL prefix on ANSI terminals; strip control bytes and cap length.
      [ -n "$RD_INVALID_NAME" ] || RD_INVALID_NAME=$(printf '%s' "$_rdt" | tr -d '[:cntrl:]' | cut -c1-80)
      continue
    fi
    if [ -n "$RD_LIST" ] && printf '%s\n' $RD_LIST | grep -qxF -e "$_rdt"; then
      RD_DUP=$((RD_DUP + 1)); [ -n "$RD_DUP_NAME" ] || RD_DUP_NAME=$_rdt
    else
      RD_LIST="$RD_LIST $_rdt"
    fi
  done < "$_rdf"
  RD_LIST=$(printf '%s' "$RD_LIST" | sed 's/^ *//')
}

# extract_live_contexts <body> — one required-status-check context per line on stdout (rc always 0;
# empty stdout means none present or the body was unparsable). jq is an OPTIONAL fast path (Δ7): the
# live side is GitHub's JSON, so unlike the declaration side a hard jq dependency would add a new
# UNVERIFIED axis for adopters without it — POSIX sed/tr is the load-bearing path.
extract_live_contexts() {
  if command -v jq >/dev/null 2>&1; then
    if _elc_j=$(printf '%s' "$1" | jq -r '.required_status_checks.contexts[]?' 2>/dev/null); then
      if [ -n "$_elc_j" ]; then printf '%s\n' "$_elc_j"; return 0; fi
    fi
  fi
  printf '%s' "$1" | tr -d '\n' \
    | sed -n 's/.*"contexts"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*"\{0,1\}//; s/"\{0,1\}[[:space:]]*$//' \
    | grep -v '^[[:space:]]*$' || true
  return 0
}

# declared_only — the OFFLINE declaration-integrity leg (Δ2): no gh, no network, ever. Reads
# $DECLARATION. Exit 0 = well-formed (or legitimately N/A) · 1 = FAIL (malformed declaration, or an
# absent declaration on a kit-shaped tree — SEC H-4: the kit must carry its own).
declared_only() {
  _dof="$DECLARATION"
  if [ ! -f "$_dof" ]; then
    if is_kit_tree; then
      printf '%s\n' "FAIL: $_dof not found — the kit must carry its own declaration (docs/ROADMAP-KIT.md or .github/workflows/golden-path.yml present in this tree; deleting REQUIRED-CHECKS.md can no longer green this check)"
      exit 1
    fi
    printf '%s\n' "N/A: $_dof not found in this tree — nothing declared to verify (this leg is opt-in, BACKLOG-pattern; stamp one via incept, or copy templates/REQUIRED-CHECKS-TEMPLATE.md)"
    exit 0
  fi
  read_declaration "$_dof"
  if [ "$RD_TOOMANY" != 0 ]; then
    printf '%s\n' "FAIL: $_dof declares more than $RD_MAX_LINES required-check context line(s) (cap exceeded — DoS bound)"
    exit 1
  fi
  if [ "$RD_INVALID" != 0 ]; then
    printf '%s\n' "FAIL: $_dof declares an invalid required-check context name: $RD_INVALID_NAME (must match ^[A-Za-z0-9][A-Za-z0-9._/-]*\$, length<=100 — GitHub context names containing spaces are NOT declarable in v1; rename the CI job/step to a hyphenated name and re-declare)"
    exit 1
  fi
  if [ "$RD_DUP" != 0 ]; then
    printf '%s\n' "FAIL: $_dof declares a duplicate required-check context: $RD_DUP_NAME"
    exit 1
  fi
  set -- $RD_LIST; _don=$#
  if [ "$RD_PLACEHOLDER" != 0 ] && [ "$_don" = 0 ]; then
    printf '%s\n' "N/A: $_dof is the pristine stamped template (placeholder present, no active context declared yet) — replace the placeholder with your CI's real check name(s)"
    exit 0
  fi
  if [ "$RD_PLACEHOLDER" != 0 ] && [ "$_don" -gt 0 ]; then
    printf '%s\n' "FAIL: $_dof mixes the unedited placeholder with $_don active declared context(s) — remove the placeholder line once real contexts are added"
    exit 1
  fi
  if [ "$_don" = 0 ]; then
    printf '%s\n' "FAIL: $_dof declares zero active required-check contexts (empty declaration, not the pristine template)"
    exit 1
  fi
  printf '%s\n' "OK: $_dof declares $_don required-check context(s):$RD_LIST"
  # ★ SAY WHAT THIS GREEN DOES NOT COVER (round 1, finding 2): this leg reads a FILE and cannot see the
  # live setting that blocks a merge — and that setting is load-bearing for a SIBLING check's colour.
  # A maintainer reading "OK" here must not conclude the requirement is in place.
  printf '%s\n' "NOTE: declaration integrity only. required_approving_review_count (>=1) is a LIVE-LEG check — run this script with no flag (needs gh + admin) to verify the review requirement that actually blocks an unratified control-plane merge."
  exit 0
}

# classify RC BODY — decide PASS/FAIL/UNVERIFIED from the HTTP outcome, NOT body substrings.
# Only a genuine HTTP 200 (gh exit 0) is allowed to reach the required-settings check, so a
# non-200 ERROR body that merely *names* the settings can never read as protected.
classify() {
  rc=$1; body=$2
  if [ "$rc" = "0" ]; then
    # HTTP 200: this IS the live protection config — verify the required settings are present.
    ok=0
    printf '%s' "$body" | grep -q '"required_pull_request_reviews"' || { printf '%s\n' "FAIL: required PR reviews not enabled on $BRANCH"; ok=1; }
    # ★★ THE COUNT, NOT JUST THE BLOCK (RATIFICATION-WAITING-IS-GREEN, round 1, finding 2).
    # `required_pull_request_reviews: {}` is PRESENT and requires NOTHING, and this gate green-lit it.
    # Since 2026-08-28 `control-plane-ratification` renders WAITING as GREEN precisely because this
    # count blocks server-side (DEVELOPMENT-PROCESS.md §13, THREAT-MODEL.md T6, REQUIRED-CHECKS.md all
    # name it) — a gate not checking the setting its sibling depends on is an unverified assumption.
    # No jq (this leg must run on a bare runner): strip whitespace, take the digits.
    _bp_rc_count=$(printf '%s' "$body" | tr -d ' \t\n' \
      | sed -n 's/.*"required_approving_review_count":\([0-9][0-9]*\).*/\1/p' | head -n 1)
    if [ -z "$_bp_rc_count" ]; then
      printf '%s\n' "FAIL: $BRANCH does not declare required_approving_review_count — the merge of an unratified control-plane PR is blocked by that count, and the control-plane-ratification check is GREEN while waiting BECAUSE of it (DEVELOPMENT-PROCESS.md §13). Absent, nothing blocks. Run: sh scripts/branch-protection-apply.sh --apply"; ok=1
    elif [ "$_bp_rc_count" -lt 1 ]; then
      printf '%s\n' "FAIL: $BRANCH sets required_approving_review_count=$_bp_rc_count — a review requirement of ZERO. The required_pull_request_reviews block being PRESENT means nothing on its own; with a count of 0 an unratified control-plane PR merges with a GREEN ratification check (that check explains the wait, it does not block it). Run: sh scripts/branch-protection-apply.sh --apply"; ok=1
    fi
    printf '%s' "$body" | grep -q '"required_status_checks"' || { printf '%s\n' "FAIL: required status checks not enabled on $BRANCH"; ok=1; }
    # advisory (non-fatal): CODEOWNER-review enforcement is recommended but not required by this gate
    # (an adopter who never fills CODEOWNERS can leave builder=reviewer paths under-covered — §12).
    printf '%s' "$body" | grep -q '"require_code_owner_reviews":[[:space:]]*true' || printf '%s\n' "ADVISORY: require_code_owner_reviews is not enabled on $BRANCH — CODEOWNER review is recommended so builder ≠ sole reviewer holds on protected paths (DEVELOPMENT-PROCESS.md §12)."
    # Declared-contexts comparison (B4, D1). SEC H-3/REV M3: this never skips SILENTLY any more — an
    # absent declaration, a pristine template, or a malformed one (dup/placeholder-mixed/bad-charset/
    # too-many) always prints a one-line disclosure; a malformed declaration ESCALATES to FAIL under
    # CI/--require (a gate must be runnable, and a malformed declaration is not "nothing to check").
    if [ ! -f "$DECLARATION" ]; then
      printf '%s\n' "ADVISORY: declared-context comparison SKIPPED (no $DECLARATION in this tree)"
    else
      read_declaration "$DECLARATION"
      set -- $RD_LIST; _cls_don=$#
      _cls_skip=""; _cls_malformed=0
      if [ "$RD_TOOMANY" != 0 ]; then
        _cls_skip="$DECLARATION exceeds the $RD_MAX_LINES declared-line cap"; _cls_malformed=1
      elif [ "$RD_INVALID" != 0 ]; then
        _cls_skip="$DECLARATION declares an invalid required-check context name: $RD_INVALID_NAME"; _cls_malformed=1
      elif [ "$RD_DUP" != 0 ]; then
        _cls_skip="$DECLARATION declares a duplicate required-check context: $RD_DUP_NAME"; _cls_malformed=1
      elif [ "$RD_PLACEHOLDER" != 0 ] && [ "$_cls_don" -gt 0 ]; then
        _cls_skip="$DECLARATION mixes the unedited placeholder with active declared context(s)"; _cls_malformed=1
      elif [ "$RD_PLACEHOLDER" != 0 ] && [ "$_cls_don" = 0 ]; then
        _cls_skip="$DECLARATION is the pristine stamped template"; _cls_malformed=0
      elif [ "$_cls_don" = 0 ]; then
        # R-1: a declaration present, zero placeholders, zero active contexts (an empty or
        # de-fenced ```...``` block) is malformed exactly like declared_only()'s own "zero active"
        # FAIL (above) — the live leg must not silently green this by falling through to the
        # empty-RD_LIST comparison below (which would report OK, having nothing to compare).
        _cls_skip="$DECLARATION declares zero active required-check contexts"; _cls_malformed=1
      fi

      if [ -n "$_cls_skip" ]; then
        if [ "$_cls_malformed" = 1 ] && [ "$REQUIRE" = "1" ]; then
          printf '%s\n' "FAIL: declared-context comparison SKIPPED because $_cls_skip (escalated: CI/--require)"
          ok=1
        else
          printf '%s\n' "ADVISORY: declared-context comparison SKIPPED ($_cls_skip)"
        fi
      else
        _cls_live=$(extract_live_contexts "$body")
        _cls_missing=""
        for _cls_c in $RD_LIST; do
          printf '%s\n' "$_cls_live" | grep -qxF -e "$_cls_c" || _cls_missing="$_cls_missing $_cls_c"
        done
        if [ -n "$_cls_missing" ]; then
          printf '%s\n' "FAIL: required-check context(s) declared in $DECLARATION but not live on $BRANCH:$_cls_missing — run: sh scripts/branch-protection-apply.sh --apply"
          ok=1
        fi
        _cls_extra=""
        for _cls_c in $_cls_live; do
          if [ -n "$RD_LIST" ] && printf '%s\n' $RD_LIST | grep -qxF -e "$_cls_c"; then
            :
          else
            _cls_extra="$_cls_extra $_cls_c"
          fi
        done
        [ -n "$_cls_extra" ] && printf '%s\n' "ADVISORY: live status check(s) not declared in $DECLARATION (informational, never fatal):$_cls_extra"
      fi
    fi
    [ "$ok" -eq 0 ] && printf '%s\n' "OK: $BRANCH on ${REPO:-?} is protected (PR reviews + status checks required)."
    exit "$ok"
  fi
  # Non-200. A definitive "no protection" (404) is a real FAIL; anything else (403 admin-rights,
  # 401, rate-limit, empty/transient body) is NOT determinable here -> UNVERIFIED (never a pass).
  if printf '%s' "$body" | grep -q 'Branch not protected'; then
    printf '%s\n' "FAIL: $BRANCH on ${REPO:-?} has no branch protection."; exit 1
  fi
  unverifiable "protection endpoint returned non-200 (token may lack repo-admin, or transient/empty) on ${REPO:-?}"
}

run() {
  have_gh || unverifiable "gh not installed"
  REPO=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GH_CONFIG_DIR; gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  [ -n "$REPO" ] || unverifiable "no GitHub repo context"
  PROT=$(unset GH_HOST GH_REPO GH_ENTERPRISE_TOKEN GH_CONFIG_DIR; gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null) && rc=0 || rc=$?
  classify "$rc" "$PROT"
}

selftest() {
  st=0
  # shellcheck disable=SC1007  # CI= intentionally clears the var for the subprocess
  out=$(CI= REQUIRE=0 BP_FORCE_NO_GH=1 sh "$0" 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "2" ]; then echo "selftest PASS: no-gh local -> exit 2 (UNVERIFIED)"; else echo "selftest FAIL: no-gh local should be exit 2 (got $rc)"; st=1; fi
  printf '%s' "$out" | grep -q UNVERIFIED || { echo "selftest FAIL: missing UNVERIFIED message"; st=1; }
  out=$(CI=true BP_FORCE_NO_GH=1 sh "$0" 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "1" ]; then echo "selftest PASS: no-gh + CI -> exit 1 (FAIL escalation)"; else echo "selftest FAIL: no-gh+CI should be exit 1 (got $rc)"; st=1; fi
  # shellcheck disable=SC1007  # CI= intentionally clears the var for the subprocess
  out=$(CI= BP_FORCE_NO_GH=1 sh "$0" --require 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "1" ]; then echo "selftest PASS: no-gh + --require -> exit 1"; else echo "selftest FAIL: no-gh+--require should be exit 1 (got $rc)"; st=1; fi
  out=$(CI=true BP_FORCE_NO_GH=1 sh "$0" --raw 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "2" ] && printf '%s' "$out" | grep -q UNVERIFIED && ! printf '%s' "$out" | grep -q '^usage:'; then
    echo "selftest PASS: --raw ignores CI escalation -> exit 2 (UNVERIFIED)"
  else
    echo "selftest FAIL: --raw under CI should be UNVERIFIED exit 2 (got rc=$rc, out=$out)"; st=1
  fi
  # HTTP-status-based parse, tested IN-PROCESS via classify() (no production-reachable stub
  # seam — an env var must never be able to force a pass). classify() calls exit, so each
  # case runs in a subshell that also sets the REQUIRE level for the unverifiable path.
  # DECLARATION defaults to a path that can never exist, so these six PRE-B4 cells keep their
  # pre-B4 behaviour untouched even though the kit's own REQUIRED-CHECKS.md now sits at repo root.
  cls() {  # expect_rc require rc body label [declaration-file]
    e=$1; req=$2; r=$3; b=$4; lbl=$5; d=${6:-/nonexistent-required-checks-$$}
    ( REQUIRE="$req"; REPO=selftest; DECLARATION="$d"; classify "$r" "$b" ) >/dev/null 2>&1 && g=0 || g=$?
    if [ "$g" = "$e" ]; then echo "selftest PASS: $lbl -> exit $g"; else echo "selftest FAIL: $lbl want $e got $g"; st=1; fi
  }
  cls 0 0 0 '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{}}' "200 + both settings + a review count of 1"
  cls 1 0 0 '{}' "200 + missing settings"
  # ★ THE COUNT CELLS (review round 1, finding 2). A count of 0 is a review requirement that requires
  # nothing, and the green-while-waiting ratification rendering leans on this exact number.
  cls 1 0 0 '{"required_pull_request_reviews":{"required_approving_review_count":0},"required_status_checks":{}}' "200 + review count of ZERO -> FAIL (nothing would block an unratified CP merge)"
  cls 1 0 0 '{"required_pull_request_reviews":{},"required_status_checks":{}}' "200 + reviews block PRESENT but no count at all -> FAIL (presence is not a requirement)"
  cls 0 0 0 '{"required_pull_request_reviews":{"required_approving_review_count":2},"required_status_checks":{}}' "200 + a count above 1 -> PASS (the gate asserts a floor, not an exact value)"
  cls 0 0 0 '{"required_pull_request_reviews": { "required_approving_review_count" : 1 },"required_status_checks":{}}' "the count parses through arbitrary JSON whitespace"
  cls 1 0 1 '{"message":"Branch not protected","status":"404"}' "404 not-protected"
  cls 2 0 1 '{"message":"Must have admin rights to Repository."}' "403 admin-rights -> UNVERIFIED"
  cls 1 1 1 '{"message":"Must have admin rights to Repository."}' "403 admin + CI/require -> FAIL"
  cls 2 0 1 '{"message":"validation failed","errors":["required_pull_request_reviews","required_status_checks"]}' "non-200 spoof body -> UNVERIFIED (not a false pass)"

  # ── B4: declared-contexts comparison + the offline --declared-only leg. Fixtures live in a
  # mktemp dir, trap-cleaned; never a committed fixture (which would poison the self-scanning gates).
  _bpdir=""; _ghdir=""; _ghenvdir=""
  trap 'rm -rf "$_bpdir" "$_ghdir" "$_ghenvdir" 2>/dev/null || true' EXIT
  _bpdir=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for declared-context fixtures"; st=1; }
  printf '# fixture\n\n```\nci\ncontrol-plane-ratification\n```\n' > "$_bpdir/good.md"
  printf '```\nci\nci\n```\n' > "$_bpdir/dup.md"
  printf '```\n<your-check-name>\n```\n' > "$_bpdir/pristine.md"
  printf '```\n<your-check-name>\nci\n```\n' > "$_bpdir/mixed.md"
  printf '```\n```\n' > "$_bpdir/empty.md"
  # B4 fix round 1: charset / DoS / second-fence fixtures (SEC C-1/H-2/L-2..L-4, REV M1).
  printf '```\n"allow_force_pushes":true\n```\n' > "$_bpdir/inject.md"          # C-1: JSON-metachar/quote injection attempt
  printf '```\nci\n*\n```\n' > "$_bpdir/glob.md"                                 # bare glob declared
  printf '```\nbuild and test\n```\n' > "$_bpdir/spacey.md"                      # space-containing name (v1: not declarable)
  printf '```\n-bad-context\n```\n' > "$_bpdir/dash.md"                          # leading dash
  printf '```\nci\tbad\n```\n' > "$_bpdir/ctrl.md"                               # control char (embedded tab)
  printf '```\nci\n\033[31mFAKE\033[0m\n```\n' > "$_bpdir/esc.md"                # R-3: raw ESC/ANSI sequence in the context name
  { printf '```\n'; _i=1; while [ "$_i" -le 101 ]; do printf 'ctx-%s\n' "$_i"; _i=$((_i + 1)); done; printf '```\n'; } > "$_bpdir/toomany.md"
  printf '```\nci\ncontrol-plane-ratification\n```\n\nExample usage:\n```\nusage-example-context\n```\n' > "$_bpdir/twofence.md"

  clsd() {  # expect_rc needle require rc body declaration-file label — classify() WITH a real declaration
    e=$1; needle=$2; req=$3; r=$4; b=$5; d=$6; lbl=$7
    out=$( ( REQUIRE="$req"; REPO=selftest; DECLARATION="$d"; classify "$r" "$b" ) 2>&1 ) && g=0 || g=$?
    if [ "$g" = "$e" ] && printf '%s\n' "$out" | grep -qF -e "$needle"; then
      echo "selftest PASS: $lbl -> exit $g"
    else
      echo "selftest FAIL: $lbl want rc=$e needle='$needle' got rc=$g out=[$out]"; st=1
    fi
  }
  clsd 1 "FAIL: required-check context(s) declared" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":["ci"]}}' \
    "$_bpdir/good.md" "declared-missing context (control-plane-ratification) -> FAIL naming it"
  clsd 1 "run: sh scripts/branch-protection-apply.sh --apply" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":["ci"]}}' \
    "$_bpdir/good.md" "declared-missing FAIL appends the remedy (REV L3)"
  clsd 1 "FAIL: required-check context(s) declared" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/good.md" "live contexts:[] with active declared contexts -> FAIL"
  clsd 0 "ADVISORY: live status check(s) not declared" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":["ci","control-plane-ratification","extra-check"]}}' \
    "$_bpdir/good.md" "live \\ declared -> ADVISORY, non-fatal (still exit 0)"
  clsd 0 "OK: main on selftest is protected" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":["ci","control-plane-ratification"]}}' \
    "$_bpdir/good.md" "conformant declaration + matching live -> OK"
  # SEC H-3/REV M3: skip disclosure — every skip route prints a line; malformed escalates under --require.
  clsd 0 "ADVISORY: declared-context comparison SKIPPED" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/dup.md" "malformed (duplicate) declaration, no --require -> ADVISORY disclosure, non-fatal"
  clsd 1 "FAIL: declared-context comparison SKIPPED" 1 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/dup.md" "malformed (duplicate) declaration + --require -> escalates to FAIL"
  clsd 0 "ADVISORY: declared-context comparison SKIPPED" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/mixed.md" "malformed (placeholder-mixed) declaration, no --require -> ADVISORY disclosure"
  clsd 1 "FAIL: declared-context comparison SKIPPED" 1 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/mixed.md" "malformed (placeholder-mixed) declaration + --require -> escalates to FAIL"
  clsd 1 "FAIL: declared-context comparison SKIPPED" 1 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/inject.md" "malformed (bad-charset) declaration + --require -> escalates to FAIL"
  clsd 0 "ADVISORY: declared-context comparison SKIPPED" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/pristine.md" "pristine template -> ADVISORY disclosure, NEVER escalates (not malformed)"
  clsd 0 "ADVISORY: declared-context comparison SKIPPED" 1 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/pristine.md" "pristine template + --require -> still ADVISORY, never FAIL"
  clsd 0 "ADVISORY: declared-context comparison SKIPPED" 1 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/does-not-exist-clsd.md" "absent declaration + --require -> still ADVISORY, never FAIL"
  # R-1: declared, zero placeholders, zero active contexts (empty/de-fenced block) — the sixth skip
  # route. Must disclose like every other malformed case, and escalate to FAIL under --require;
  # previously this fell through the ladder silently and read as OK (nothing to compare).
  clsd 0 "ADVISORY: declared-context comparison SKIPPED" 0 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/empty.md" "empty/de-fenced (zero active contexts) declaration, no --require -> ADVISORY disclosure (R-1)"
  clsd 1 "FAIL: declared-context comparison SKIPPED" 1 0 \
    '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":[]}}' \
    "$_bpdir/empty.md" "empty/de-fenced (zero active contexts) declaration + --require -> escalates to FAIL (R-1)"

  clsdo() {  # expect_rc needle file label — declared_only() direct
    e=$1; needle=$2; f=$3; lbl=$4
    out=$( ( DECLARATION="$f"; declared_only ) 2>&1 ) && g=0 || g=$?
    if [ "$g" = "$e" ] && printf '%s\n' "$out" | grep -qF -e "$needle"; then
      echo "selftest PASS: $lbl -> exit $g"
    else
      echo "selftest FAIL: $lbl want rc=$e needle='$needle' got rc=$g out=[$out]"; st=1
    fi
  }
  clsdo 1 "duplicate required-check context" "$_bpdir/dup.md" "duplicate declared context -> FAIL naming it"
  clsdo 1 "mixes the unedited placeholder" "$_bpdir/mixed.md" "placeholder mixed with active contexts -> FAIL"
  clsdo 1 "declares zero active" "$_bpdir/empty.md" "empty (not pristine) declaration -> FAIL"
  clsdo 0 "declares 2 required-check context(s)" "$_bpdir/good.md" "well-formed declaration -> OK naming the count"
  clsdo 1 "allow_force_pushes" "$_bpdir/inject.md" "JSON-metachar/quote injection attempt -> FAIL naming it (C-1)"
  clsdo 1 "*" "$_bpdir/glob.md" "bare glob '*' declared -> FAIL naming it"
  clsdo 1 "build and test" "$_bpdir/spacey.md" "space-containing context name -> FAIL naming it (v1: not declarable)"
  clsdo 1 "-bad-context" "$_bpdir/dash.md" "leading-dash context name -> FAIL naming it"
  clsdo 1 "invalid required-check context name" "$_bpdir/ctrl.md" "control char (embedded tab) in context name -> FAIL"
  clsdo 1 "cap exceeded" "$_bpdir/toomany.md" "more than 100 declared context lines -> FAIL (DoS bound)"
  clsdo 0 "declares 2 required-check context(s)" "$_bpdir/twofence.md" "second fence-open ignored (usage-example never merges in) -> OK naming 2"

  # R-3: the invalid-name FAIL line must never carry a raw control/ESC byte (measured erasing the
  # FAIL prefix on ANSI terminals). Assert the sanitized form directly rather than trusting a visual
  # read: stripping control bytes from the actual output must be a no-op if it was already clean.
  _esc_out=$( ( DECLARATION="$_bpdir/esc.md"; declared_only ) 2>&1 ) || true
  _esc_clean=$(printf '%s' "$_esc_out" | tr -d '[:cntrl:]')
  if printf '%s' "$_esc_out" | grep -qF -- "invalid required-check context name" && [ "$_esc_out" = "$_esc_clean" ]; then
    echo "selftest PASS: invalid-name FAIL line carries no raw control/ESC bytes (R-3)"
  else
    echo "selftest FAIL: invalid-name FAIL line still carries raw control bytes (R-3) (out=[$_esc_out])"; st=1
  fi

  clsdo_root() {  # expect_rc needle root file label — declared_only() with a REPO_ROOT override too
    e=$1; needle=$2; root=$3; f=$4; lbl=$5
    out=$( ( REPO_ROOT="$root"; DECLARATION="$f"; declared_only ) 2>&1 ) && g=0 || g=$?
    if [ "$g" = "$e" ] && printf '%s\n' "$out" | grep -qF -e "$needle"; then
      echo "selftest PASS: $lbl -> exit $g"
    else
      echo "selftest FAIL: $lbl want rc=$e needle='$needle' got rc=$g out=[$out]"; st=1
    fi
  }
  # HERMETIC kit-tree fixture (B4 round 3, the B3 hermeticity lesson recurring): the ambient
  # $REPO_ROOT is kit-shaped in the dev repo but carries NEITHER marker in a built export (both
  # docs/ROADMAP-KIT.md and .github/workflows/golden-path.yml are export-ignored), so asserting
  # this cell against $REPO_ROOT passed here and silently flipped to the N/A branch inside the
  # export artifact (measured: CI's artifact-gate got rc=0 "N/A" where FAIL was required). Plant a
  # throwaway root that carries ONLY the marker is_kit_tree() reads, independent of which tree this
  # selftest happens to run inside — production is_kit_tree()/declared_only() are unchanged; only
  # this cell's evidence source moves.
  _bpkitroot="$_bpdir/kitroot"
  mkdir -p "$_bpkitroot/docs"
  : > "$_bpkitroot/docs/ROADMAP-KIT.md"
  clsdo_root 1 "the kit must carry its own declaration" "$_bpkitroot" "$_bpdir/nonexistent-kit.md" "kit-tree, absent declaration -> FAIL (SEC H-4)"
  clsdo_root 0 "N/A" "$_bpdir" "$_bpdir/nonexistent-adopter.md" "adopter/export tree (no kit markers), absent declaration -> N/A"

  # --declared-only must NEVER touch gh/network — prove it with a PATH-stub gh that records
  # any invocation (argument-borne PATH manipulation, no env-forced stub of the check itself).
  _ghdir=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the gh-stub fixture"; st=1; }
  printf '#!/bin/sh\necho called >> "%s/called"\nexit 0\n' "$_ghdir" > "$_ghdir/gh"
  chmod +x "$_ghdir/gh"
  ( PATH="$_ghdir:$PATH" sh "$0" --declared-only "$_bpdir/good.md" ) >/dev/null 2>&1 || true
  if [ -f "$_ghdir/called" ]; then
    echo "selftest FAIL: --declared-only invoked gh (network path touched)"; st=1
  else
    echo "selftest PASS: --declared-only never touches gh/network"
  fi

  # Parser-drift lock (SEC L-1/REV): read_declaration() here and ad_read_declaration() in
  # scripts/branch-protection-apply.sh must NEVER disagree on the same fixture — the two copies of
  # valid_context_name() (and the surrounding parse) must never drift (the B3 mirror lesson).
  # scripts/branch-protection-apply.sh --print-parsed is a read-only debug surface for exactly this
  # cross-check (no gh, no mutation, plain output of its own parsed active-context list).
  _pdb_files="$_bpdir/good.md $_bpdir/dup.md $_bpdir/pristine.md $_bpdir/mixed.md $_bpdir/empty.md $_bpdir/inject.md $_bpdir/glob.md $_bpdir/spacey.md $_bpdir/dash.md $_bpdir/ctrl.md $_bpdir/esc.md $_bpdir/toomany.md $_bpdir/twofence.md"
  _pdb_bad=0
  for _pdb_f in $_pdb_files; do
    read_declaration "$_pdb_f"
    _pdb_a=$(printf '%s\n' $RD_LIST | sort)
    _pdb_b=$(sh "$REPO_ROOT/scripts/branch-protection-apply.sh" --declaration="$_pdb_f" --print-parsed 2>/dev/null | sort)
    if [ "$_pdb_a" != "$_pdb_b" ]; then
      echo "selftest FAIL: parser drift on $_pdb_f — branch-protection.sh=[$_pdb_a] apply.sh=[$_pdb_b]"
      st=1; _pdb_bad=1
    fi
  done
  [ "$_pdb_bad" = 0 ] && echo "selftest PASS: both parsers agree across the fixture battery (no drift)"

  # GH env containment (SEC M-3): GH_HOST/GH_REPO/GH_ENTERPRISE_TOKEN/GH_CONFIG_DIR must never reach
  # the gh subprocess (a hostile value could redirect the API host, retarget the repo, or swap
  # creds/config); GH_TOKEN must still reach it (the operator's real credential). Proven with a stub
  # gh that dumps its OWN environment — this environment has no controlling tty and CI has no reason
  # to spoof GH_HOST, so this is the assert-the-unset path the design anticipates as an alternative to
  # "still hits the stub" (a stub has no real host to differentiate against).
  _ghenvdir=$(mktemp -d) || { echo "selftest FAIL: no tmpdir for the GH-env fixture"; st=1; }
  _ghenvlog="$_ghenvdir/env.log"
  : > "$_ghenvlog"
  cat > "$_ghenvdir/gh" <<STUB
#!/bin/sh
env | grep '^GH_' | sort >> "$_ghenvlog" 2>/dev/null || true
case "\$*" in
  *"repo view"*) echo "me/repo" ;;
  *) printf '%s' '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":[]}}' ;;
esac
STUB
  chmod +x "$_ghenvdir/gh"
  GH_HOST=evil.example GH_REPO=evil/evil GH_ENTERPRISE_TOKEN=evil-ent-token GH_CONFIG_DIR=/evil-config GH_TOKEN=real-op-token \
    PATH="$_ghenvdir:$PATH" sh "$0" --raw >/dev/null 2>&1 || true
  if grep -q '^GH_HOST=\|^GH_REPO=\|^GH_ENTERPRISE_TOKEN=\|^GH_CONFIG_DIR=' "$_ghenvlog"; then
    echo "selftest FAIL: a stripped GH_* var reached the gh subprocess (log: $(cat "$_ghenvlog" 2>/dev/null))"; st=1
  else
    echo "selftest PASS: GH_HOST/GH_REPO/GH_ENTERPRISE_TOKEN/GH_CONFIG_DIR never reach the gh subprocess"
  fi
  if grep -q '^GH_TOKEN=real-op-token' "$_ghenvlog"; then
    echo "selftest PASS: GH_TOKEN (the operator's real credential) still reaches the gh subprocess"
  else
    echo "selftest FAIL: GH_TOKEN was stripped too (it must be honored, not contained) (log: $(cat "$_ghenvlog" 2>/dev/null))"; st=1
  fi

  [ "$st" = "0" ] && echo "branch-protection --selftest: OK"
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --declared-only) declared_only; exit $? ;;
  *) run ;;
esac
