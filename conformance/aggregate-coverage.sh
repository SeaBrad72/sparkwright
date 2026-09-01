#!/bin/sh
# aggregate-coverage.sh — every conformance/*.sh is accounted for by exactly one of three categories,
# so a check cannot exist outside BOTH suites unnoticed.
#   usage: sh conformance/aggregate-coverage.sh [--selftest] [--root=<dir>]
# Exit: 0 = every file accounted for · 1 = an unaccounted file, a stale/contradictory exclusion, or a
# vacuous (zero-file) scan · POSIX sh; dash-clean.
#
# WHY THIS EXISTS (CP7R5-GATE-AUTHORITY, D3). The kit runs two suites — the portable `verify.sh`
# battery and its own workflows — and NOTHING stated how they relate. The measured consequence was
# CI ⊄ verify.sh AND verify.sh ⊄ CI simultaneously: an adopter could be remote-green and locally-red
# on a required gate. The fix (all 11 emitted pipelines now run `verify.sh --require`) closes the
# gap that existed; THIS check keeps a new one from opening, which is the row's acceptance criteria
# verbatim — "a check that fails when one suite gains a required gate the other lacks".
#
# THE THREE CATEGORIES — see conformance/aggregate-exclusions.txt for the contract in full:
#   REGISTERED  named in conformance/verify.sh                (portable; adopters run it)
#   WORKFLOW    named in .github/workflows/*.yml              (enforced, kit-only)
#   LIBRARY     listed in aggregate-exclusions.txt            (sourced, never run; not a check)
#
# ★ HONEST CEILING — read before trusting a green. The WORKFLOW category counts a check whose name
# appears on a workflow line that is NEITHER a `#` comment NOR a `name:` label (see classify/_wf_exec).
# That rejects the two forms that most commonly create a false "covered" — a comment naming a check,
# and a step's `name:` label — but it does NOT prove the name sits in an actual `run:` command: a name
# in an `env:`/`with:`/`uses:` value, or in a non-executing string, still counts. Tightening this to a
# true `run:`-context matcher (single-line + block-scalar, awk-tracked like verify-enforced-wired.sh's
# _ep_github) is boarded as a follow-up — it also closes the IDENTICAL ceiling in ci-selftest-coverage.sh,
# which uses the same strip-and-match shape, so the two should move together. And even a true run:
# matcher is weaker than being REACHED at runtime: a step can be gated by an `if:`, negated, or skipped,
# and this check cannot see that. So a green here proves every check is ACCOUNTED FOR (named on a
# non-comment, non-label workflow line), never that every one actually RUNS. Do not let it stand in for that.
#
# SECOND CEILING: this check is NOT mutation-swept. conformance/non-vacuity.sh targets the verify.sh
# CONTROL SET, and this check is deliberately kit-only (measured: 56 UNACCOUNTED on a real incepted
# tree), so it sits outside the sweep — `non-vacuity.sh --only aggregate-coverage.sh` correctly
# reports "matched no targeted check". Its teeth are the --selftest below, run as its own CI step.
# That is the same posture as non-vacuity-wired.sh, and it is a weaker guarantee than the swept
# checks enjoy — stated here rather than left for someone to discover.
set -eu

ROOT="."
SELFTEST=0
for _a in "$@"; do
  case "$_a" in
    --root=*)   ROOT=${_a#--root=} ;;
    # Dispatch on the FLAG, not on $1. Accepting --selftest in the loop while dispatching on "${1:-}"
    # meant `--root=/tmp/x --selftest` ran a REAL scan of /tmp/x while the caller believed it had
    # self-tested — a silent no-op in the one command whose whole job is to prove the check works.
    --selftest) SELFTEST=1 ;;
    *) echo "FAIL: unknown argument '$_a'"; exit 1 ;;
  esac
done

# _lib_listed <root> <basename> -> 0 iff the basename has a LINE with a non-empty reason after the tab.
# A bare basename with no reason does NOT count: an unreasoned exclusion is exactly the silent
# widening this file exists to prevent, so it must fail rather than quietly pass.
_lib_listed() {
  _ll_f="$1/conformance/aggregate-exclusions.txt"
  [ -f "$_ll_f" ] || return 1
  grep -v '^[[:space:]]*#' "$_ll_f" \
    | grep -E "^$2[[:space:]]+[^[:space:]]" >/dev/null 2>&1
}

# _esc <s>: escape regex metacharacters in a basename. Unescaped, the `.` in `foo.sh` is a wildcard —
# a matcher that can say YES to the wrong file is the same class of defect as one that says yes to a
# comment. (Review finding M5.) The class covers every ERE metacharacter a basename could carry:
# `. [ \ * ^ $ + ? ( ) { } |` — so e.g. `a+b.sh` cannot spuriously match `aab.sh`.
_esc() { printf '%s' "$1" | sed 's/[].[\*^$+?(){}|]/\\&/g'; }

# _wf_exec <root> <escaped-basename> -> 0 iff the check's name appears on a workflow line that is
# NEITHER a `#` comment NOR a `name:` label. This rejects the two forms that most commonly fake a
# "covered" (a comment naming a check; a step's `name:` label) — the HIGH-3 defect — but it is NOT a
# true execution-context matcher: a name in an `env:`/`with:`/`uses:` value or a non-executing string
# still passes. A single-line `run:.*` anchor was rejected because it would MISS block-scalar (`run: |`)
# invocations — the form most kit checks use — turning real checks UNACCOUNTED; the honest full fix is a
# run:-context awk matcher (boarded, and shared with ci-selftest-coverage.sh, which uses this same
# strip-and-match shape). See the HONEST CEILING note above. (Review finding HIGH-3, partial.)
_wf_exec() {
  sed 's/#.*//' "$1"/.github/workflows/*.yml 2>/dev/null \
    | grep -vE '^[[:space:]]*-?[[:space:]]*name:' \
    | grep -qE "conformance/$2([[:space:]]|$)"
}

# classify <root> <basename> -> REGISTERED | WORKFLOW | LIBRARY | UNACCOUNTED
#
# REGISTERED requires a REAL DISPATCH LINE, not a mention. The first version grepped for the bare
# basename anywhere in verify.sh, so a COMMENT satisfied it — and this very slice added a comment
# naming aggregate-coverage.sh, which made the check classify ITSELF as registered. Deleting its only
# execution site would then have left the coverage lock green while the check ran nowhere: the exact
# inverse of what it exists to prove. (Review finding M3/I3, CONFIRMED by both reviewers.)
classify() {
  _c_root="$1"; _c_b="$2"; _c_e=$(_esc "$2")
  if grep -qE "^[[:space:]]*check[[:space:]]+(control|doc)[[:space:]]+.*conformance/$_c_e([[:space:]]|$)" \
       "$_c_root/conformance/verify.sh" 2>/dev/null; then echo REGISTERED; return; fi
  if _wf_exec "$_c_root" "$_c_e"; then echo WORKFLOW; return; fi
  if _lib_listed "$_c_root" "$_c_b";                                                            then echo LIBRARY;  return; fi
  echo UNACCOUNTED
}

# ── THE EXPORTED-ORPHAN CENSUS (BOARD-DRIFT-SHIPS-ORPHANED, PR 11) ────────────────────────────────
#
# A DIFFERENT QUESTION FROM classify()'s, on a different population, and that is why it is a second
# predicate rather than a fourth category. classify() asks "is this check accounted for by ONE OF THE
# KIT'S TWO SUITES" — and WORKFLOW is a legitimate answer for a kit-only check. This census asks the
# ADOPTER'S question: "of the checks that actually SHIP to me, is there one that nothing runs and
# nothing describes?" A workflow answer is no answer at all there, because every one of this kit's
# workflows is `export-ignore`d. `board-drift.sh` was exactly that file: WORKFLOW-accounted here,
# green, and shipped to adopters as a check with no runner and no documentation.
#
# MEMBERSHIP IS MEASURED WITH `git archive HEAD`, NEVER `git check-attr`. The export is a SECOND TREE
# that the individual gates cannot see, and check-attr answers a different question (what a pattern
# says) from the one that matters (what the archive actually contains) — the session-35 lesson, and
# the reason #595 redded twice. HEAD is pinned deliberately: the accounting is read from HEAD too, so
# an UNCOMMITTED README row cannot satisfy the census. The verdict is then a pure function of the
# commit, identical on every checkout, and "describe it" cannot be discharged by an unsaved edit.
#
# CEILING: this enforces ACCOUNTED-FOR-NESS, not that anyone runs the check, and a README row is
# DISCLOSURE, not enforcement. It cannot judge whether the row's prose is true — `adopter-told.sh`
# grades claim-verbs, which is precisely the upgrade a README row buys over silence.

# _exported_shs <root> -> the conformance/*.sh BASENAMES present in the adopter export, one per line.
_exported_shs() {
  ( cd "$1" && git archive HEAD 2>/dev/null | tar -tf - 2>/dev/null ) \
    | sed -n 's|^conformance/\([^/]*\.sh\)$|\1|p'
}

# _head_registered <root> <escaped-basename> -> 0 iff HEAD's verify.sh carries a real DISPATCH row.
# Same shape as classify()'s REGISTERED arm — a comment mention must not satisfy it there or here.
_head_registered() {
  ( cd "$1" && git show HEAD:conformance/verify.sh 2>/dev/null ) \
    | grep -qE "^[[:space:]]*check[[:space:]]+(control|doc)[[:space:]]+.*conformance/$2([[:space:]]|$)"
}

# _readme_row <root> <escaped-basename> -> 0 iff HEAD's conformance/README.md carries a TABLE ROW
# whose FIRST CELL names the basename.
#
# STRUCTURAL, AND THAT IS THE WHOLE POINT. A bare mention-grep is the identical defect this file's own
# history records at the classify() comment above: a COMMENT naming a check satisfied the first
# version of REGISTERED, and the check classified ITSELF as registered. A prose sentence naming
# board-drift.sh would satisfy a mention-grep while telling an adopter nothing about how to run it.
# `[^|]*` cannot cross a cell boundary, so a basename in the *second* cell does not count either.
_readme_row() {
  ( cd "$1" && git show HEAD:conformance/README.md 2>/dev/null ) \
    | grep -qE "^\|[^|]*$2[^|]*\|"
}

# _lib_declared <root> <escaped-basename> -> 0 iff HEAD's aggregate-exclusions.txt declares it with a
# reason. A sourced library legitimately ships without a runner; it is not a check.
_lib_declared() {
  ( cd "$1" && git show HEAD:conformance/aggregate-exclusions.txt 2>/dev/null ) \
    | grep -v '^[[:space:]]*#' | grep -qE "^$2[[:space:]]+[^[:space:]]"
}

# ── THE DECLARED BASELINE, AND WHY THIS IS A RATCHET RATHER THAN AN ABSOLUTE ZERO ──────────────────
#
# ⚠️ THE ROW'S NUMBER WAS FALSE, AND SO WAS THE DESIGN'S. Both said this census reads 1 today
# (`board-drift.sh`) and 0 after. MEASURED at 4a397972 with the commands this check runs: 158 exported
# conformance/*.sh — 97 registered, 24 README-described, 3 declared libraries, and **34** accounted
# for by NOTHING BUT AN `export-ignore`d WORKFLOW. `board-drift.sh` is not *the* orphan; it is one of
# thirty-four files in precisely its situation. The boarded defect is a CLASS, not an instance.
#
# That measurement forecloses both simpler shapes. An absolute-zero census reds 34 times on the kit's
# own tree. Admitting WORKFLOW as an accounting route would pass `board-drift.sh` WITHOUT a README row
# — the census would be green while blind to the exact file it was built for, and the row's own
# success metric ("re-introducing an orphan is caught") could never fire.
#
# So the population is DECLARED, by name, and the list may only SHRINK — enforced by THREE arms, and
# it takes all three (the first draft of this paragraph claimed the ratchet on two, which the security
# review correctly refused):
#   1. a member not on this list is a new orphan and FAILS;
#   2. a member on this list that has since become accounted, or stopped shipping, is STALE and FAILS,
#      so the list cannot outlive its subjects;
#   3. the NAME COUNT is pinned (`BASELINE_MAX`) and may only fall — which is the only arm that sees a
#      SWAP, because appending a name leaves a perfectly consistent list that arms 1 and 2 accept.
# `board-drift.sh` is deliberately ABSENT: this PR describes it in README.md, so deleting that row puts
# it back in the undeclared population (arm 1) and re-declaring it to silence that pushes the count to
# 34 (arm 3). That is the row's ratchet, live, on the real tree.
#
# The other 33 are DISCLOSED, not blessed. Each is the same defect at a different address; disposing
# of them (export-ignore the kit-internal ones, describe the adopter-useful ones) is follow-on work
# this slice deliberately does not smuggle in.
EXPORT_ORPHAN_BASELINE="actionlint-valid.sh
aggregate-coverage.sh
claim-gate-counts.sh
claims-registry.sh
decision-integrity.sh
drift-watch-wired.sh
explain-wired.sh
golden-path-filter-parity.sh
golden-path-wired.sh
green-on-clone.sh
incept-containment.sh
kit-base.sh
kit-current.sh
kit-manifest.sh
kit-update-identity.sh
kit-update-merge.sh
meta-control-fresh.sh
model-map-binding.sh
model-tiering-legible.sh
model-tiering-plan-wired.sh
model-tiering-value.sh
model-tiering.sh
non-vacuity-wired.sh
promotion-readiness-wired.sh
promotion-readiness.sh
provenance-precondition.sh
release-tagged.sh
repo-ownership.sh
review-lane.sh
shim-coverage.sh
template-detectors-aligned.sh
tier-advice-wired.sh
union-ratchet.sh"

# ── THE SHRINK-ONLY COUNT PIN (security review F1 — the seat's CONDITION) ──────────────────────────
#
# The staleness arm alone does NOT make this a ratchet, and saying it did was the sentence the review
# caught. Both evasions are SAME-DIFF and one line each:
#   (a) ship a new orphan and append its name here — the census stays green;
#   (b) delete board-drift.sh's README row and re-add its name here — the census stays green, and the
#       staleness arm is silent because the file genuinely is unaccounted again.
# Neither is caught by arithmetic or by staleness, because both leave a CONSISTENT list. What both
# do is push the NAME COUNT to 34. So the count is pinned, and it may only fall: raising it is a
# ratified edit to this constant, in the diff, where a reviewer sees it.
# Shape borrowed from HISTORICAL_LINES_ACKS in conformance-mass-budget.sh (the retirement pin) for the
# same reason it exists there: a count sees a swap that a consistency check cannot.
BASELINE_MAX=33

# _on_baseline <baseline> <basename> -> 0 iff declared. Whole-line match; never a substring.
_on_baseline() {
  printf '%s\n' "$1" | grep -qxF "$2"
}

# _orphan_census <root> [baseline] -> 0 no undeclared orphans · 1 orphan / stale / non-git / vacuous.
# The baseline is a PARAMETER so the selftest can drive the REAL predicate with fixture data instead
# of a replica — the same discipline _scan already follows with classify().
_orphan_census() {
  _oc_root="$1"; _oc_base="${2-$EXPORT_ORPHAN_BASELINE}"; _oc_pin="${3-$BASELINE_MAX}"
  _oc_rc=0; _oc_n=0; _oc_v=0; _oc_d=0
  # THE PIN, CHECKED FIRST so its verdict is never buried under the per-file lines it explains.
  # `-gt`, so 34 reds and a shrink to 32 passes: the list may only get shorter without a ratified edit.
  _oc_cnt=0
  if [ -n "$_oc_base" ]; then _oc_cnt=$(printf '%s\n' "$_oc_base" | grep -c '[^[:space:]]'); fi
  if [ "$_oc_cnt" -gt "$_oc_pin" ]; then
    echo "FAIL: the exported-orphan baseline carries $_oc_cnt name(s) but is pinned at $_oc_pin, and it"
    echo "      may only SHRINK. Appending a name is how BOTH same-diff evasions look: shipping a new"
    echo "      orphan and declaring it, or deleting a README row and re-declaring the file. Repair the"
    echo "      orphan instead; lowering BASELINE_MAX is the only edit this pin expects to see."
    _oc_rc=1
  fi
  # NON-GIT ROOT IS UNVERIFIED **AND** NONZERO — never a silent skip. A census that cannot measure
  # export membership has proved nothing, and printing a green over that is the green-while-dark class
  # board-drift.sh's own D-leg exists to forbid.
  if ! ( cd "$_oc_root" 2>/dev/null && git rev-parse -q --verify HEAD >/dev/null 2>&1 ); then
    echo "UNVERIFIED: '$_oc_root' is not a git repository with a HEAD, so export membership cannot be"
    echo "            measured (git archive HEAD is the only honest source). This is NOT a pass."
    return 1
  fi
  _oc_exp="$(_exported_shs "$_oc_root")"
  # HEREDOC-FED `while IFS= read -r`, and the form satisfies THREE constraints at once — each of which
  # killed one of the obvious alternatives (review M2, then the artifact gate's semgrep rule):
  #   · `for x in $list` word-splits on the DEFAULT IFS, so any basename containing whitespace
  #     shatters into two bogus names. The failure direction is the dangerous one: neither fragment
  #     matches a README row or a baseline entry, so a legitimately accounted file reds — and in the
  #     staleness loop below a two-word entry reads as two ghosts.
  #   · Setting IFS GLOBALLY to a newline fixes that, and is what this shipped with — but it trips the
  #     blocking semgrep rule `bash.lang.security.ifs-tampering`, whose own guidance is to scope IFS to
  #     the `read` instead. The gate forbids narrowing the rule, so the file changes.
  #   · A `printf | while read` PIPELINE scopes IFS correctly but runs the loop body in a SUBSHELL,
  #     which silently discards every counter below (_oc_n, _oc_v, _oc_d, _oc_rc) — the census would
  #     then report zero of everything and pass vacuously.
  # A HEREDOC redirection spawns no subshell, so the counters persist, and `IFS=` is a per-command
  # prefix on `read` alone, never a global assignment. The selftest's counting legs are what prove the
  # first half of that; the census's own verdict line proves the second.
  # Nothing in conformance/ carries a whitespace basename today; that is a fact about the tree, not a
  # guarantee, and this form is correct regardless.
  while IFS= read -r _oc_b; do
    [ -n "$_oc_b" ] || continue
    _oc_n=$((_oc_n + 1))
    _oc_e=$(_esc "$_oc_b")
    _head_registered "$_oc_root" "$_oc_e" && continue
    _readme_row     "$_oc_root" "$_oc_e" && continue
    _lib_declared   "$_oc_root" "$_oc_e" && continue
    if _on_baseline "$_oc_base" "$_oc_b"; then _oc_d=$((_oc_d + 1)); continue; fi
    echo "FAIL: $_oc_b SHIPS IN THE ADOPTER EXPORT but is neither registered in conformance/verify.sh,"
    echo "      nor carried by a row in conformance/README.md's index table, nor a declared library,"
    echo "      nor on the declared orphan baseline — an adopter receives a check that nothing runs"
    echo "      and nothing describes. Add a README table row whose FIRST CELL names it (a prose"
    echo "      mention does not count), register it, or export-ignore it. Do NOT extend the"
    echo "      baseline: it is a ratchet and may only shrink."
    _oc_v=$((_oc_v + 1)); _oc_rc=1
  done <<EOF
$_oc_exp
EOF
  # STALENESS, THE SECOND OF THE THREE ARMS THAT MAKE THIS A RATCHET. An entry whose file is now
  # accounted (or no longer exported) is STALE, and a stale declaration is how an exemption outlives
  # its justification — the same rule this file already applies to aggregate-exclusions.txt.
  # ⚠️ THIS ARM ALONE IS NOT THE RATCHET, and an earlier draft of this comment claimed it was. It
  # cannot see a SWAP: delete board-drift.sh's README row and re-add its name here and the list is
  # perfectly consistent, so nothing here objects. The COUNT PIN above is what refuses that, because
  # the swap takes the list to 34. Staleness stops the list rotting; the pin stops it growing;
  # together with the per-file arm they are the ratchet.
  # Same heredoc-while form, same three reasons (see above).
  while IFS= read -r _oc_l; do
    [ -n "$_oc_l" ] || continue
    _oc_le=$(_esc "$_oc_l")
    if ! printf '%s\n' "$_oc_exp" | grep -qxF "$_oc_l"; then
      echo "FAIL: the orphan baseline lists '$_oc_l', which is not in the export (stale entry — remove it)"
      _oc_rc=1; continue
    fi
    if _head_registered "$_oc_root" "$_oc_le" || _readme_row "$_oc_root" "$_oc_le" \
       || _lib_declared "$_oc_root" "$_oc_le"; then
      echo "FAIL: the orphan baseline lists '$_oc_l', but it is now accounted for. Remove it from the"
      echo "      baseline in this diff — the ratchet only counts if a repair is recorded as one."
      _oc_rc=1
    fi
  done <<EOF
$_oc_base
EOF
  # Zero exported checks means the archive read failed or the tree is not this kit — same posture as
  # the zero-file guard below: a green over nothing asserts nothing.
  if [ "$_oc_n" = 0 ]; then
    echo "FAIL: the exported-orphan census saw ZERO exported conformance/*.sh under '$_oc_root' — refusing to pass vacuously"
    return 1
  fi
  [ "$_oc_rc" = 0 ] && echo "OK: exported-orphan census — $_oc_n exported conformance/*.sh, $_oc_v undeclared orphan(s), $_oc_d declared-and-disclosed (baseline; shrink-only)"
  return "$_oc_rc"
}

# _scan <root> -> 0 all accounted, 1 otherwise. Drives the REAL classify(), never a replica.
_scan() {
  _s_root="$1"; _s_rc=0; _s_n=0
  for _s_f in "$_s_root"/conformance/*.sh; do
    [ -f "$_s_f" ] || continue
    _s_n=$((_s_n + 1))
    _s_b=$(basename "$_s_f")
    case "$(classify "$_s_root" "$_s_b")" in
      UNACCOUNTED)
        echo "FAIL: $_s_b is in NEITHER suite and is not a declared library."
        echo "      Register it in conformance/verify.sh (portable), wire it as a workflow step"
        echo "      (kit-only), or declare it with a reason in conformance/aggregate-exclusions.txt."
        _s_rc=1 ;;
    esac
  done
  # A zero-file scan must FAIL. Without this, pointing the check at a tree with no conformance/
  # directory would report success over nothing at all.
  [ "$_s_n" != 0 ] || { echo "FAIL: scanned ZERO conformance/*.sh under '$_s_root' — refusing to pass vacuously"; _s_rc=1; }
  # A LIBRARY entry naming a file that does not exist is stale, and a stale list is how an exclusion
  # outlives its justification. An entry that is ALSO registered is a contradiction: it claims the
  # file is not a check while verify.sh runs it as one.
  if [ -f "$_s_root/conformance/aggregate-exclusions.txt" ]; then
    # awk's default field splitting handles BOTH tab and space. A `read` with IFS=' ' does NOT split
    # on tab, which silently yields "name<TAB>firstword" as the basename — caught here by the
    # positive selftest leg, not by any of the negative ones.
    for _e_b in $(grep -v '^[[:space:]]*#' "$_s_root/conformance/aggregate-exclusions.txt" | awk 'NF {print $1}'); do
      [ -f "$_s_root/conformance/$_e_b" ] || { echo "FAIL: exclusion lists '$_e_b', which does not exist (stale entry)"; _s_rc=1; }
      # The contradiction check must cover BOTH suites. Checking only verify.sh left a real bypass:
      # a check enforced ONLY as a workflow step could be relabelled a LIBRARY and silently retired —
      # delete the step, add one line here, and no gate objects. (Review finding M4, CONFIRMED.)
      _e_e=$(_esc "$_e_b")
      if grep -qE "^[[:space:]]*check[[:space:]]+(control|doc)[[:space:]]+.*conformance/$_e_e([[:space:]]|$)" \
           "$_s_root/conformance/verify.sh" 2>/dev/null; then
        echo "FAIL: '$_e_b' is declared a LIBRARY but verify.sh runs it as a check (contradiction)"; _s_rc=1
      fi
      if _wf_exec "$_s_root" "$_e_e"; then
        echo "FAIL: '$_e_b' is declared a LIBRARY but a workflow runs it as a check (contradiction)"; _s_rc=1
      fi
    done
  fi
  [ "$_s_rc" = 0 ] && echo "OK: all $_s_n conformance/*.sh accounted for (registered | workflow-wired | declared library)"
  return "$_s_rc"
}

# selftest() — the CI non-vacuity sweep mutates only lines ABOVE this marker, so every kill-assertion
# below stays live. Helpers placed above would be neutered along with the code they test.
if [ "$SELFTEST" = 1 ]; then
  d=$(mktemp -d) || { echo "aggregate-coverage --selftest: FAIL (no tmpdir)"; exit 1; }
  st=0
  _mk() { # _mk <name> — a fixture root with one check per category
    mkdir -p "$d/$1/conformance" "$d/$1/.github/workflows"
    printf 'check control a sh conformance/a.sh\n'      > "$d/$1/conformance/verify.sh"
    # verify.sh is ITSELF a conformance/*.sh and so must be accounted for like any other — in the
    # real tree it classifies WORKFLOW because ci.yml runs it. A fixture that omits this is not a
    # "fully-accounted" tree at all, which is how the positive leg earns its keep.
    printf 'run: sh conformance/b.sh\nrun: sh conformance/verify.sh --require\n' > "$d/$1/.github/workflows/ci.yml"
    printf '#\n' > "$d/$1/conformance/a.sh"
    printf '#\n' > "$d/$1/conformance/b.sh"
    printf '#\n' > "$d/$1/conformance/c.sh"
    printf 'c.sh\ta declared library, sourced never run\n' > "$d/$1/conformance/aggregate-exclusions.txt"
  }
  _mk good
  _scan "$d/good" >/dev/null || { echo "FAIL: selftest — a fully-accounted fixture must PASS"; st=1; }

  # Each category is load-bearing: drop its evidence and the file must become UNACCOUNTED.
  _mk drop_reg;  printf '\n' > "$d/drop_reg/conformance/verify.sh"
  _scan "$d/drop_reg" >/dev/null && { echo "FAIL: selftest — a check missing from BOTH suites must FAIL"; st=1; }
  _mk drop_wf;   printf '\n' > "$d/drop_wf/.github/workflows/ci.yml"
  _scan "$d/drop_wf" >/dev/null && { echo "FAIL: selftest — a workflow-only check losing its step must FAIL"; st=1; }
  _mk drop_lib;  printf '#\n' > "$d/drop_lib/conformance/aggregate-exclusions.txt"
  _scan "$d/drop_lib" >/dev/null && { echo "FAIL: selftest — an undeclared library must FAIL"; st=1; }

  # A reasonless exclusion must NOT satisfy the list — the whole point of naming exclusions.
  _mk noreason; printf 'c.sh\n' > "$d/noreason/conformance/aggregate-exclusions.txt"
  _scan "$d/noreason" >/dev/null && { echo "FAIL: selftest — a REASONLESS exclusion wrongly satisfied the list"; st=1; }

  # A stale entry (names a file that does not exist) must FAIL, or an exclusion outlives its subject.
  _mk stale; printf 'c.sh\treal\nghost.sh\tnames a file that does not exist\n' > "$d/stale/conformance/aggregate-exclusions.txt"
  _scan "$d/stale" >/dev/null && { echo "FAIL: selftest — a STALE exclusion entry wrongly passed"; st=1; }

  # A file both declared a library AND registered is a contradiction, not a belt-and-braces pass.
  _mk contra; printf 'c.sh\treal\na.sh\tclaims a REGISTERED check is not a check\n' > "$d/contra/conformance/aggregate-exclusions.txt"
  _scan "$d/contra" >/dev/null && { echo "FAIL: selftest — a LIBRARY entry contradicting verify.sh wrongly passed"; st=1; }

  # M3: a COMMENT mention in verify.sh must NOT count as REGISTERED.
  _mk comment_only
  printf '# see conformance/a.sh for the pattern\n' > "$d/comment_only/conformance/verify.sh"
  printf 'run: sh conformance/b.sh\nrun: sh conformance/verify.sh --require\n' > "$d/comment_only/.github/workflows/ci.yml"
  _scan "$d/comment_only" >/dev/null && { echo "FAIL: selftest — a COMMENT mention wrongly counted as REGISTERED"; st=1; }

  # M4: a workflow-enforced check must NOT be retirable by relabelling it a LIBRARY.
  _mk contra_wf
  printf 'c.sh\treal\nb.sh\tclaims a WORKFLOW-enforced check is not a check\n' > "$d/contra_wf/conformance/aggregate-exclusions.txt"
  _scan "$d/contra_wf" >/dev/null && { echo "FAIL: selftest — a LIBRARY entry contradicting a WORKFLOW step wrongly passed"; st=1; }

  # HIGH-3: a check named ONLY in a workflow COMMENT must NOT count as WORKFLOW. b.sh appears solely in
  # a `#` comment (its `run:` step is gone), so it must fall through to UNACCOUNTED. Before the arm was
  # tightened this fixture PASSed wrongly (the comment satisfied the permissive grep).
  _mk wf_comment
  printf 'run: sh conformance/verify.sh --require\n# runs conformance/b.sh as part of the suite\n' > "$d/wf_comment/.github/workflows/ci.yml"
  _scan "$d/wf_comment" >/dev/null && { echo "FAIL: selftest — a check named only in a workflow COMMENT wrongly counted as WORKFLOW"; st=1; }

  # M3: _esc must be load-bearing. a.sh is genuinely UNACCOUNTED; axsh is REGISTERED. If _esc were a
  # no-op, a.sh's regex (`.` as a wildcard) would spuriously match axsh's registration line, a.sh
  # would be misclassified REGISTERED, and the scan would wrongly PASS. It must FAIL.
  mkdir -p "$d/esc/conformance" "$d/esc/.github/workflows"
  printf 'check control axsh sh conformance/axsh\n' > "$d/esc/conformance/verify.sh"
  printf 'run: sh conformance/verify.sh --require\n' > "$d/esc/.github/workflows/ci.yml"
  printf '#\n' > "$d/esc/conformance/a.sh"
  _scan "$d/esc" >/dev/null && { echo "FAIL: selftest — _esc no-op let a.sh match axsh's registration"; st=1; }

  # THE VACUITY LEG (review M1): a conformance/ with NO .sh at all must FAIL via the zero-guard — not
  # via UNACCOUNTED. The old leg wrote conformance/verify.sh into the fixture, so it failed as
  # UNACCOUNTED (verify.sh isn't a scanned check) and mutating the zero-guard to always-true SURVIVED.
  # With zero .sh present, the ONLY thing that can fail this leg is the zero-guard, so that mutation
  # now goes RED.
  mkdir -p "$d/empty/conformance"
  _scan "$d/empty" >/dev/null && { echo "FAIL: selftest — a ZERO-file scan must FAIL, never pass vacuously"; st=1; }

  # =======================================================================================
  # PR 11 — THE EXPORTED-ORPHAN CENSUS (BOARD-DRIFT-SHIPS-ORPHANED).
  # Fixture roots are `git init`-ed and COMMITTED, because the census measures export membership with
  # `git archive HEAD` and reads its accounting from HEAD. A non-git fixture would make every one of
  # these legs SKIP into the UNVERIFIED arm and prove nothing — the vet's C4ii finding.
  # =======================================================================================
  _mkgitfix() { # <name> <README body> — a: registered · b: the file under test · c: declared library
    mkdir -p "$d/$1/conformance"
    printf 'check control a sh conformance/a.sh\n' > "$d/$1/conformance/verify.sh"
    printf '#\n' > "$d/$1/conformance/a.sh"
    printf '#\n' > "$d/$1/conformance/b.sh"
    printf '#\n' > "$d/$1/conformance/c.sh"
    printf 'c.sh\ta declared library, sourced never run\n' > "$d/$1/conformance/aggregate-exclusions.txt"
    printf '%s\n' "$2" > "$d/$1/conformance/README.md"
    ( cd "$d/$1" && git init -q && git config user.email t@x && git config user.name t \
        && git config commit.gpgsign false && git add -A && git commit -qm fixture ) >/dev/null 2>&1
  }
  _CEN_ROW='| Check | Type |
|---|---|
| `b.sh` | script | described |
| `verify.sh` | script | the aggregate |'
  _CEN_NOROW='| Check | Type |
|---|---|
| `verify.sh` | script | the aggregate |'
  _CEN_PROSE="$_CEN_NOROW

Note: b.sh is discussed at length in this paragraph of prose."
  _cen() { if CO=$(_orphan_census "$1" "$2" "${3-33}" 2>&1); then CR=0; else CR=1; fi; }

  # LIVENESS: every exported file accounted by one of the three real routes -> PASS at zero.
  _mkgitfix cen_ok "$_CEN_ROW"
  _cen "$d/cen_ok" ""
  [ "$CR" = 0 ] || { echo "FAIL: selftest — a fully-accounted EXPORT must pass the census; out=[$CO]"; st=1; }

  # NEGATIVE: an exported check accounted by nothing must RED, and must NAME the file (a bare rc
  # would not tell the adopter which check they were shipped blind).
  _mkgitfix cen_orphan "$_CEN_NOROW"
  _cen "$d/cen_orphan" ""
  { [ "$CR" = 1 ] && printf '%s' "$CO" | grep -q 'FAIL: b.sh SHIPS IN THE ADOPTER EXPORT'; } \
    || { echo "FAIL: selftest — an exported orphan must RED naming the file; rc=$CR out=[$CO]"; st=1; }

  # MENTION-IS-NOT-A-ROW: the basename appears in README PROSE but in no table row. This is the exact
  # defect classify()'s REGISTERED arm shipped with once already (a comment satisfied it), and a
  # mention-grep here would let a sentence discharge the obligation to tell an adopter how to run it.
  _mkgitfix cen_prose "$_CEN_PROSE"
  _cen "$d/cen_prose" ""
  { [ "$CR" = 1 ] && printf '%s' "$CO" | grep -q 'FAIL: b.sh SHIPS IN THE ADOPTER EXPORT'; } \
    || { echo "FAIL: selftest — a PROSE MENTION wrongly satisfied the census; rc=$CR out=[$CO]"; st=1; }

  # The baseline declares the known population, so a declared orphan passes (disclosed, not blessed).
  _mkgitfix cen_declared "$_CEN_NOROW"
  _cen "$d/cen_declared" "b.sh"
  { [ "$CR" = 0 ] && printf '%s' "$CO" | grep -q '1 declared-and-disclosed'; } \
    || { echo "FAIL: selftest — a baseline-declared orphan must pass and be counted; rc=$CR out=[$CO]"; st=1; }

  # ★ THE RATCHET (the row's success metric). A baseline entry that has since become accounted is
  # STALE and must RED, so the list can only shrink and nobody can quietly re-add a repaired file.
  _mkgitfix cen_stale "$_CEN_ROW"
  _cen "$d/cen_stale" "b.sh"
  { [ "$CR" = 1 ] && printf '%s' "$CO" | grep -q 'but it is now accounted for'; } \
    || { echo "FAIL: selftest — a STALE baseline entry (now accounted) must RED; rc=$CR out=[$CO]"; st=1; }

  # A baseline entry naming a file that does not ship at all is stale in the other direction.
  _mkgitfix cen_ghost "$_CEN_ROW"
  _cen "$d/cen_ghost" "ghost.sh"
  { [ "$CR" = 1 ] && printf '%s' "$CO" | grep -q 'which is not in the export'; } \
    || { echo "FAIL: selftest — a baseline entry naming a non-exported file must RED; rc=$CR out=[$CO]"; st=1; }

  # ★ THE COUNT PIN (security review F1's condition). Both same-diff evasions look identical to arms 1
  # and 2 — the list stays consistent — and both push the NAME COUNT past the pin. Fixture: a baseline
  # of 2 names against a pin of 1, with b.sh genuinely an orphan, so the list is CONSISTENT and only
  # the count can object. `-gt` is load-bearing: a pin of 2 here must pass.
  _mkgitfix cen_pin "$_CEN_NOROW"
  _cen "$d/cen_pin" 'b.sh
ghostless.sh' 1
  { [ "$CR" = 1 ] && printf '%s' "$CO" | grep -q 'may only SHRINK'; } \
    || { echo "FAIL: selftest — a baseline ABOVE its pin must RED (the swap evasion); rc=$CR out=[$CO]"; st=1; }
  # ...and the pin must not fire below itself, or it would be a blanket refusal rather than a ratchet.
  _cen "$d/cen_pin" 'b.sh' 1
  { [ "$CR" = 0 ] && ! printf '%s' "$CO" | grep -q 'may only SHRINK'; } \
    || { echo "FAIL: selftest — a baseline AT its pin must not trip the count arm; rc=$CR out=[$CO]"; st=1; }

  # NON-GIT ROOT: UNVERIFIED **and** nonzero. Never a silent skip — a census that could not measure
  # export membership has proved nothing, and a green over that is the green-while-dark class.
  _cen "$d/good" ""
  { [ "$CR" = 1 ] && printf '%s' "$CO" | grep -q '^UNVERIFIED:'; } \
    || { echo "FAIL: selftest — a non-git root must print UNVERIFIED and exit NONZERO; rc=$CR out=[$CO]"; st=1; }

  # ★ THE LIVE SUBJECT. The kit's own tree, through the SHIPPED baseline constant — this is the leg
  # that makes `board-drift.sh`'s README row load-bearing: delete that row and this goes RED, because
  # the file is deliberately absent from the baseline. It is also the only leg that can catch the
  # shipped baseline drifting out of date.
  if _orphan_census . >/dev/null 2>&1; then
    :
  else
    echo "FAIL: selftest — the census does not pass on the kit's own tree with the SHIPPED baseline"
    _orphan_census . 2>&1 | sed 's/^/       /'
    st=1
  fi

  rm -rf "$d" 2>/dev/null || true
  if [ "$st" = 0 ]; then
    echo "OK: aggregate-coverage selftest (each of the 3 categories load-bearing; reasonless, stale"
    echo "                       and contradictory exclusions rejected; zero-file scan FAILs)"
    exit 0
  fi
  exit 1
fi

# BOTH predicates run, and BOTH verdicts are printed, before the exit code is composed. Short-circuit
# would hide the second answer behind the first failure, and they are independent questions.
_agg_rc=0
_scan          "$ROOT" || _agg_rc=1
_orphan_census "$ROOT" || _agg_rc=1
exit "$_agg_rc"
