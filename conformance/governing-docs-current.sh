#!/bin/sh
# governing-docs-current.sh — recurrence latch for the RETIRED control-plane hand-off.
#
# CP-8c (v3.124.0) abolished the AMBER `apply.py` hand-off (author to scratchpad/, a HUMAN runs an
# idempotent script) and replaced it with the DEV-CLONE (the agent edits directly in a disposable
# clone; the guard stays armed on the real repo; the human reviews a CI-green DIFF). CP-10 fixed
# two docs. It missed the rest, which kept PRESCRIBING the retired route — including the ones an
# agent reads BEFORE it can know better (DRIFT-1, the KW21 class in governance itself).
# CP-8c/CP-10 fixed INSTANCES and the drift recurred. This fixes the CLASS: it turns RED if a
# governing artifact ever teaches the retired convention again.
#
#   usage: sh conformance/governing-docs-current.sh [--selftest]
#   exit:  0 = every governing doc is current (or N/A: incepted tree) · 1 = a governing doc
#          prescribes the retired route, a named member is missing, or the set has drifted · 2 = usage
#
# KIT-ONLY, BY DESIGN (dual review, DRIFT-1 B1/B2). This latch governs the KIT's OWN governing docs.
# It must NOT run on an adopter's tree, for two reasons the reviewers proved with PoCs:
#   1. VACUITY BY SUBSTITUTION. `scripts/incept.sh` does `git mv CLAUDE.md ENGINEERING-PRINCIPLES.md`
#      and stamps a NEW project CLAUDE.md. Post-incept the slot named "CLAUDE.md" is still FULL — with
#      a different document. A presence check cannot see a substitution: the count stays whole and the
#      green looks earned while the real principles doc goes unscanned.
#   2. FALSE-RED ON ADOPTER PROSE. `apply.py` is a generic filename. An adopter writing "run
#      `python scripts/apply.py` for migrations" in their own file would hard-RED a zero-tolerance,
#      REQUIRED_IDS-undroppable gate — wedged by a latch about the kit's internal history.
# So: we detect an incepted tree by the kit's OWN invariant (incept.sh:195 — ENGINEERING-PRINCIPLES.md
# exists <=> already incepted) and return N/A. Live-scanned in the kit's ci.yml; NOT in verify.sh's
# portable battery. The claim's verifier is `--selftest` (fixture-based, tree-independent), so the
# claim stays registered and undroppable everywhere.
#
# HONEST CEILING (read before trusting a green):
#   - It greps a KNOWN signature over a NAMED set. It is a recurrence latch for THIS retirement —
#     NOT a general "no retired convention anywhere" prover.
#   - A paraphrase that avoids both tokens escapes it. A future retirement it has never been told
#     about escapes it entirely.
#   - It proves the governing docs no longer TEACH the retired route. It does NOT prove the
#     dev-clone route is FOLLOWED.
set -eu
cd "$(dirname "$0")/.."

# ---- the governing set (NAMED, never globbed) -------------------------------------------------
# Globbing is how a scan set silently shrinks to zero and a check goes vacuously green. So the set is
# NAMED — and a named member that is MISSING is a FAIL, not a skip (a rename would otherwise retire a
# file from the scan in silence). The `skills/*` and `agents/*` FAMILIES are additionally guarded by
# check_set_complete() below, so a NEW skill/agent cannot be born outside the fence.
governing_set() {
  cat <<'SET'
skills/build/SKILL.md
skills/continuous-discovery/SKILL.md
skills/debugging/SKILL.md
skills/demonstrate/SKILL.md
skills/design/SKILL.md
skills/evals/SKILL.md
skills/operating/SKILL.md
skills/plan/SKILL.md
skills/review/SKILL.md
skills/tdd/SKILL.md
skills/using-skills/SKILL.md
skills/verification/SKILL.md
skills/worktrees/SKILL.md
agents/engineer.agent.md
agents/orchestrator.agent.md
agents/reviewer.agent.md
agents/security.agent.md
CLAUDE.md
AGENTS.md
START-HERE.md
ONBOARDING.md
MAINTAINING.md
MATURITY.md
DEVELOPMENT-PROCESS.md
DEVELOPMENT-STANDARDS.md
docs/governance/promotion-contract.md
docs/operations/harness-adapters.md
docs/operations/meta-control.md
docs/operations/release-tag.md
templates/PROJECT-CLAUDE-TEMPLATE.md
templates/KIT-FEEDBACK-TEMPLATE.md
SET
}

# The retired-convention signature. `apply.py` = the retired VEHICLE; `AMBER` = the retired CEREMONY
# NAME. Either one, in a governing doc, means the retired route is being taught. Matched CASE-
# INSENSITIVELY (dual review): "Amber"/"Apply.py" must not slip the fence on capitalisation alone.
SIGNATURE='apply\.py|AMBER'

# ---- the allowlist policy: ZERO-TOLERANCE (ratified 2026-07-14) --------------------------------
# A hit anywhere in the governing set is a VIOLATION. There is no in-set allowlist, deliberately.
#
# The rejected alternative was a context-aware rule (allow the hit when the line also carries a
# retirement marker like "retired"/"superseded"). It reads more forgiving and is strictly WEAKER:
# it opens a gaming path where a future agent re-introduces the whole prescription and satisfies
# this latch by dropping the word "retired" into the sentence — the check greens while the doc
# teaches the retired route, which is the exact failure DRIFT-1 exists to prevent.
#
# The cost is accepted and small: a governing doc may not NAME the retired convention, even to warn
# someone off it. It doesn't need to — the explainer docs that carry the history
# (docs/operations/retiring-conventions.md, docs/operations/runtime-guards.md) sit deliberately
# OUTSIDE the governing set. Governing docs teach the CURRENT route and point at those for the why.
#
# This latch exists because a fix DIDN'T STICK (CP-8c/CP-10 fixed instances; the drift recurred).
# Its whole value is that it cannot be argued with. Keep it that way.
# (Zero-tolerance takes no context, so this takes no arguments. If you are tempted to add some,
#  re-read the paragraph above first.)
is_violation() { return 0; }

# ---- set-completeness: a new skill/agent cannot be born outside the fence ----------------------
# The set is NAMED (not globbed) for anti-vacuity. The cost of naming is that it can go STALE — the
# original DRIFT-1 set missed 6 skills, an agent, START-HERE.md and MATURITY.md, and a planted
# prescription in START-HERE.md sailed straight through. So: enumerate the families ON DISK and FAIL
# if anything resolved is not in the named set. Named for anti-vacuity, family-locked for coverage.
check_set_complete() {
  _root=$1; _gap=0
  for _found in "$_root"/skills/*/SKILL.md "$_root"/agents/*.agent.md; do
    [ -f "$_found" ] || continue                    # unexpanded glob when a family is absent
    _rel=${_found#"$_root"/}
    if ! governing_set | grep -qxF "$_rel"; then
      echo "FAIL: $_rel exists on disk but is NOT in the named governing set (set drift — add it)"
      _gap=1
    fi
  done
  return "$_gap"
}

# ---- the scan ----------------------------------------------------------------------------------
scan() {
  _root=$1; _viol=0; _scanned=0

  # KIT-ONLY: an incepted tree is N/A (see the header). incept.sh:195 uses this same invariant.
  if [ -f "$_root/ENGINEERING-PRINCIPLES.md" ]; then
    echo "governing-docs-current: N/A — incepted tree (this latch governs the KIT's own governing docs)"
    return 0
  fi

  check_set_complete "$_root" || _viol=1

  for _f in $(governing_set); do
    if [ ! -f "$_root/$_f" ]; then
      # A NAMED member that is missing is a FAILURE, never a silent skip: a rename or a typo would
      # otherwise retire a file from the scan and still print a confident "OK — N scanned".
      echo "FAIL: named governing artifact '$_f' is MISSING (renamed? removed? — the scan set must track it)"
      _viol=1
      continue
    fi
    _scanned=$((_scanned + 1))
    while IFS= read -r _hit; do
      [ -n "$_hit" ] || continue
      _n=${_hit%%:*}; _t=${_hit#*:}
      if is_violation; then
        echo "FAIL: $_f:$_n prescribes the RETIRED control-plane hand-off (dev-clone is the current route)"
        echo "    | $_t"
        _viol=1
      fi
    done <<EOF
$(grep -niE "$SIGNATURE" "$_root/$_f" 2>/dev/null || true)
EOF
  done

  # Anti-vacuity backstop: a scan that resolved NOTHING is a failure, never a green.
  if [ "$_scanned" -eq 0 ]; then
    echo "FAIL: governing set resolved to ZERO files under '$_root' — vacuous scan, not a pass"
    return 1
  fi
  if [ "$_viol" -ne 0 ]; then
    echo "governing-docs-current: FAIL — $_scanned scanned; the retired convention is still prescribed (or the set drifted)"
    return 1
  fi
  echo "governing-docs-current: OK — $_scanned governing artifact(s) scanned; none prescribes the retired hand-off"
  return 0
}

# ---- selftest (non-vacuity: the check must be RED-able) ----------------------------------------
# Fixtures LEFT in place (no rm -rf; the 7e guard convention).
selftest() {
  st=0
  base=$(mktemp -d)

  # A minimal COMPLETE fixture tree: every named member present, all clean.
  mk_clean() {
    _d=$1
    for _m in $(governing_set); do
      mkdir -p "$_d/$(dirname "$_m")"
      printf '# governing doc\nControl-plane work is authored in a dev-clone; the human reviews the diff.\n' > "$_d/$_m"
    done
  }

  mk_clean "$base/clean"
  if scan "$base/clean" >/dev/null 2>&1; then
    echo "OK: clean governing set -> GREEN"
  else
    echo "FAIL: selftest — a clean governing set wrongly reddened"; st=1
  fi

  # NEGATIVE (load-bearing): a governing doc that PRESCRIBES the retired route must go RED.
  # If this passes, the check is dead and every green it ever emitted was worthless.
  mk_clean "$base/planted"
  printf 'Author it under `scratchpad/`, assemble an idempotent `apply.py`, and hand it to the human (AMBER).\n' \
    >> "$base/planted/skills/plan/SKILL.md"
  if scan "$base/planted" >/dev/null 2>&1; then
    echo "FAIL: selftest — planted retired prescription did NOT redden the scan (check is dead)"; st=1
  else
    echo "OK: planted retired-convention prescription -> RED"
  fi

  # CASE-INSENSITIVITY: capitalisation must not slip the fence.
  mk_clean "$base/case"
  printf 'The Amber hand-off: a human runs Apply.Py from scratchpad.\n' >> "$base/case/MAINTAINING.md"
  if scan "$base/case" >/dev/null 2>&1; then
    echo "FAIL: selftest — a case-variant prescription escaped (needs -i)"; st=1
  else
    echo "OK: case-variant prescription -> RED"
  fi

  # MISSING NAMED MEMBER must FAIL, not silently scan fewer files (dual review M3).
  mk_clean "$base/missing"
  rm -f "$base/missing/skills/plan/SKILL.md"
  if scan "$base/missing" >/dev/null 2>&1; then
    echo "FAIL: selftest — a MISSING named member passed (silent-skip vacuity)"; st=1
  else
    echo "OK: missing named member -> FAIL (no silent skip)"
  fi

  # SET DRIFT: a NEW skill on disk that is not in the named set must FAIL (dual review M1/M4) —
  # otherwise a future skill is born outside the fence and can teach the retired route freely.
  mk_clean "$base/drift"
  mkdir -p "$base/drift/skills/brand-new"
  printf '# brand-new skill\n' > "$base/drift/skills/brand-new/SKILL.md"
  if scan "$base/drift" >/dev/null 2>&1; then
    echo "FAIL: selftest — a skill outside the named set passed (set drift undetected)"; st=1
  else
    echo "OK: skill outside the named set -> FAIL (set-drift caught)"
  fi

  # INCEPTED TREE -> N/A (kit-only). Both dual-review BLOCKER PoCs, verbatim:
  #   B1 — incept RENAMES CLAUDE.md -> ENGINEERING-PRINCIPLES.md and stamps a NEW project CLAUDE.md.
  #        The slot stays FULL, so the old code printed a confident "OK — 18 scanned" while the real
  #        principles doc (unscanned) fully prescribed the retired route. A presence check cannot see
  #        a SUBSTITUTION. We must NOT emit a green here — N/A is the honest answer.
  #   B2 — `apply.py` is a generic filename; an adopter's own prose must never RED an undroppable gate.
  mk_clean "$base/incepted"
  printf '# kit principles (renamed by incept)\nAuthor under `scratchpad/`, assemble an idempotent `apply.py` (the AMBER hand-off).\n' \
    > "$base/incepted/ENGINEERING-PRINCIPLES.md"
  printf 'Run `python scripts/apply.py` to apply our DB migrations.\n' >> "$base/incepted/AGENTS.md"
  _out=$(scan "$base/incepted" 2>&1) && _rc=0 || _rc=1
  if [ "$_rc" = 0 ] && printf '%s' "$_out" | grep -q 'N/A'; then
    echo "OK: incepted tree -> N/A (no false green over a substituted slot; adopter prose cannot RED it)"
  elif [ "$_rc" = 0 ]; then
    echo "FAIL: selftest — incepted tree returned a GREEN, not N/A (vacuity by substitution: $_out)"; st=1
  else
    echo "FAIL: selftest — an incepted tree was scanned and RED-ed on adopter prose"; st=1
  fi

  # ANTI-VACUITY: an empty tree resolves ZERO governing docs -> must FAIL, never green.
  mkdir -p "$base/empty"
  if scan "$base/empty" >/dev/null 2>&1; then
    echo "FAIL: selftest — an EMPTY governing set passed (vacuous green)"; st=1
  else
    echo "OK: empty governing set -> FAIL (no vacuous green)"
  fi

  if [ "$st" = 0 ]; then echo "governing-docs-current --selftest: OK (fixtures in $base)"; else echo "governing-docs-current --selftest: FAIL"; fi
  return "$st"
}

case "${1:-}" in
  --selftest) selftest ;;
  '') scan "." ;;
  *) echo "usage: governing-docs-current.sh [--selftest]" >&2; exit 2 ;;
esac
