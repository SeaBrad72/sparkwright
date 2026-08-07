#!/bin/sh
# adopter-gates-parity.sh — the board/loop merge-time gates (backlog-presence, ceremony-binding,
# loop-state) ship for EVERY stack (Phase-B slice B6).
#
# Clones conformance/ratification-parity.sh's shape (design D3): a single, stack-neutral source —
# profiles/adopter-gates.yml — installed by scripts/incept.sh UNCONDITIONALLY for every stack.
# Proves that single source is present, marked, wired, stack-neutral, the SOLE copy, that incept
# installs it universally, and (Δ1) that the loop-state observe/enforce dial ships in the ACTIVE
# form the 2026-08-06 probe (PR #499) confirmed — `neutral` in observe mode, never a permanent red.
#
# HONEST CEILING (read before trusting a green):
#   - The REAL run proves the single source's PRESENCE + SHAPE + SOLE-COPY, and that incept.sh's
#     install line references it unconditionally. It does NOT run incept — that behavioural witness
#     is --selftest.
#   - The --selftest drives REAL incept for a NON-ts, EXEMPT stack (terraform) and asserts the
#     workflow LANDS byte-identical to the source. It does NOT re-prove the gate's RUNTIME behaviour
#     (the check-run POSTs, the PATCH-or-POST discriminator, the base-tree adjudication) — that needs
#     a live GitHub PR (the B5a/B6 probes did this once; this lock proves REACH, not runtime).
#
#   usage: sh conformance/adopter-gates-parity.sh [--selftest]   (run from repo root)
#   exit:  0 = single source present/marked/wired/neutral/sole + incept installs it universally (or
#          N/A on an adopter tree, or a structural GitLab N/A) · 1 = a parity gap · 2 = usage
set -eu
cd "$(dirname "$0")/.."

SRC="profiles/adopter-gates.yml"     # the single, stack-neutral source (top-level, like ratification.yml)
INCEPT="scripts/incept.sh"
WF=".github/workflows/adopter-gates.yml"
CI_WF=".github/workflows/ci.yml"

# is_adopter_tree: 0 (true) iff NOT the kit's own tree. Same two export-ignored kit-dev markers
# ratification-parity.sh uses: docs/ROADMAP-KIT.md AND .github/workflows/golden-path.yml (both
# stripped by git archive/adopter-export). Fail-closed on the kit (both present -> the audit RUNS);
# an adopter has neither -> N/A.
is_adopter_tree() {
  [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]
}

# _ag_gitlab_only_adopter [root] -> 1 iff this tree is a GitLab-CI adopter for which the board/loop
# gates are legitimately absent (mirrors proportional-gate-wired.sh::_gitlab_only_adopter's SHAPE,
# re-parameterized on THIS gate's own workflow file — that function is hardcoded to the ratification
# workflow, so it cannot be reused verbatim here). Keyed ENTIRELY on tree STRUCTURE, never on prose in
# a mutable doc (DEVELOPMENT-PROCESS.md declares these GitHub-conditional; conformance/conditional-
# gates.sh locks that declaration). The structural triple, ALL THREE required:
#   .gitlab-ci.yml present          — this tree's authoritative pipeline is GitLab
#   .github/workflows/ci.yml absent — it is NOT a GitHub adopter
#   .github/workflows/adopter-gates.yml absent — the gates are genuinely not installed here
_ag_gitlab_only_adopter() {
  _gr=${1:-.}
  { [ -f "$_gr/.gitlab-ci.yml" ] && [ ! -f "$_gr/$CI_WF" ] && [ ! -f "$_gr/$WF" ]; } \
    && echo 1 || echo 0
}

# ---- static assertions (each takes its target by ARGUMENT so --selftest can drive it against a
#      fixture, never an env var — this is a control-plane oracle) --------------------------------

# marker: cp_kit_replace (incept.sh) refuses to overwrite a destination lacking this marker.
assert_marker() { grep -qE 'COPY & ADAPT|Sparkwright' "$1"; }

# wired: the source must invoke the exact tokens its runtime shape depends on. Read COMMENT-STRIPPED
# code (a commented-out invocation is a hollow gate, not a wired one).
assert_wired() {  # <src-file>
  _w=0
  _wcode=$(grep -v '^[[:space:]]*#' "$1")
  printf '%s\n' "$_wcode" | grep -qF 'previous_filename' || { echo "FAIL: $1 derives its changed-file listing without projecting 'previous_filename' — a rename's SOURCE path is dropped, so a renamed control-plane/board path would be invisible to backlog-presence"; _w=1; }
  printf '%s\n' "$_wcode" | grep -qF 'test("\n")' || { echo "FAIL: $1 derives its changed-file listing with no newline guard — a crafted filename could split one API entry into two lines that each classify separately"; _w=1; }
  printf '%s\n' "$_wcode" | grep -qF 'agent-boundary.sh --conclusion' || { echo "FAIL: $1 does not invoke 'agent-boundary.sh --conclusion' — the gates would not map their verdicts to a check-run"; _w=1; }
  printf '%s\n' "$_wcode" | grep -qF 'agent-boundary.sh --check-complete' || { echo "FAIL: $1 does not invoke 'agent-boundary.sh --check-complete' — the backlog-presence gate would not notice a changed-file listing TRUNCATED at the forge's API cap"; _w=1; }
  # CODE-based anchor, not a comment (comment-stripped code cannot see prose): the WAITING check-run
  # must be posted through an `if [ -n "$concl" ]` guard, never unconditionally — an unconditional
  # post risks sending conclusion="" for the waiting state, which COMPLETES the check-run (the exact
  # red this design removes; ratification.yml documents the same trap at its own posting site).
  printf '%s\n' "$_wcode" | grep -qF 'if [ -n "$concl" ]; then' || { echo "FAIL: $1 has no conclusion-omission guard (no \`if [ -n \"\$concl\" ]; then\` before posting) — a WAITING check-run risks being posted with conclusion=\"\", which COMPLETES it (the red this design removes)"; _w=1; }
  printf '%s\n' "$_wcode" | grep -qF 'concl="neutral"' || { echo "FAIL: $1 does not post a 'neutral' conclusion — the Δ1 observe-mode dial (loop-state's day-one non-blocking colour) is missing"; _w=1; }
  return "$_w"
}

# stack-neutral: no per-stack toolchain step, read from COMMENT-STRIPPED code.
assert_stack_neutral() {  # <src-file>
  if grep -v '^[[:space:]]*#' "$1" \
     | grep -Eiq 'actions/setup-[a-z]|(^|[^-a-z])(npm|pnpm|yarn|pip|pipenv|poetry|cargo|rustup|dotnet|nuget|gradlew|gradle|mvnw|mvn|maven|bundler)([^a-z]|$)'; then
    echo "FAIL: $1 is not stack-neutral — it carries a per-stack toolchain step; the single-source install would no longer be universal"
    return 1
  fi
  return 0
}

# single-source family-lock: the source is the TOP-LEVEL profiles/adopter-gates.yml, so NO
# profiles/<stack>/adopter-gates.yml may exist.
assert_single_source() {  # <profiles-root>
  _s=0
  for _f in "$1"/*/adopter-gates.yml; do
    [ -f "$_f" ] || continue
    echo "FAIL family-lock: $_f is a per-profile adopter-gates copy — the single source is the top-level <root>/adopter-gates.yml; remove it"
    _s=1
  done
  return "$_s"
}

# incept installs it UNCONDITIONALLY: the install line references the shared source AND is not
# re-gated on a per-stack file.
assert_incept_universal() {  # <incept-file>
  _i=0
  grep -qF 'profiles/adopter-gates.yml' "$1" || { echo "FAIL: $1 does not install the board/loop gates from profiles/adopter-gates.yml"; _i=1; }
  if grep -qF 'profiles/${STACK}/adopter-gates.yml' "$1"; then
    echo "FAIL: $1 still gates the adopter-gates install on a per-stack file (profiles/\${STACK}/adopter-gates.yml) — every non-default stack would silently get no gates"
    _i=1
  fi
  return "$_i"
}

# Δ1 — the loop-state observe/enforce dial: mode defaults to observe (a NUDGE, never a block) and
# posts 'neutral' in that mode. The PROBE RESULT (dev-repo PR #499, 2026-08-06) CONFIRMED neutral as
# the correct colour, so this lock asserts the ACTIVE form — not the commented-out fallback.
assert_loop_state_active() {  # <src-file>
  _l=0
  # I2 (surviving mutant, reviewer): read the dial from COMMENT-STRIPPED code, same idiom as the
  # loop-state.sh --head anchor below — a raw grep over the whole file is satisfied by a prose
  # duplicate sitting in a COMMENT (e.g. stale header text) even when the live code default has
  # drifted to enforce. Comment-stripping first closes that: only a literal, live-code default counts.
  _wcode=$(grep -v '^[[:space:]]*#' "$1")
  printf '%s\n' "$_wcode" | grep -qF 'LOOP_STATE_MODE: observe' || { echo "FAIL: $1 does not default LOOP_STATE_MODE to observe — the day-one non-blocking dial is missing or mis-defaulted"; _l=1; }
  printf '%s\n' "$_wcode" | grep -qF 'concl="neutral"' || { echo "FAIL: $1 does not post concl=\"neutral\" for the observe branch"; _l=1; }
  # The gate itself (loop-state.sh --head) must still be INVOKED (never fully commented out) — Δ1
  # ships ACTIVE, not the commented-block fallback.
  printf '%s\n' "$_wcode" | grep -qF 'loop-state.sh --head' || { echo "FAIL: $1 does not invoke loop-state.sh --head — the gate is not ACTIVE (looks like the commented-out fallback form, which is not what the 2026-08-06 probe ruled for)"; _l=1; }
  return "$_l"
}

# ---- the run --------------------------------------------------------------------------------------
run() {
  if is_adopter_tree; then
    echo "adopter-gates-parity: N/A — kit-self check (audits the kit's own reference source; not present on an adopter tree)"
    return 0
  fi
  if [ "$(_ag_gitlab_only_adopter)" = 1 ]; then
    echo "N/A: adopter-gates-parity — GitLab adopter; backlog-presence/ceremony-binding/loop-state are"
    echo "     declared GitHub-conditional gates in DEVELOPMENT-PROCESS.md (GitHub check-runs, which"
    echo "     GitLab does not provide). Already-ratified platform gap; manual equivalents documented in"
    echo "     docs/operations/gitlab-adoption.md."
    return 0
  fi
  fail=0
  if [ -f "$SRC" ]; then
    assert_marker "$SRC" || { echo "FAIL: $SRC lacks the kit marker (COPY & ADAPT|Sparkwright) — cp_kit_replace would refuse to install it"; fail=1; }
    assert_wired "$SRC"         || fail=1
    assert_stack_neutral "$SRC" || fail=1
    assert_loop_state_active "$SRC" || fail=1
  else
    echo "FAIL: the single source $SRC is MISSING — no stack would get the board/loop gates"
    fail=1
  fi
  assert_single_source profiles      || fail=1
  assert_incept_universal "$INCEPT"  || fail=1

  if [ "$fail" -ne 0 ]; then
    echo "FAIL: adopter-gates-parity — the board/loop gates do not ship uniformly for every stack"
    return 1
  fi
  echo "OK: adopter-gates-parity — single source present, marked, wired, stack-neutral, sole copy; incept installs it universally; loop-state ships ACTIVE in observe mode"
  return 0
}

# ---- selftest (non-vacuity: every assertion is WITNESSED against a fixture and must be RED-able) --
selftest() {
  st=0
  base=$(mktemp -d)
  trap 'rm -rf "$base"' EXIT

  # A minimal CLEAN source fixture: carries the marker, all wiring tokens, the Δ1 observe dial, and
  # no toolchain step.
  mk_clean_src() {  # <path>
    mkdir -p "$(dirname "$1")"
    {
      printf '# COPY & ADAPT — reference adopter-gates workflow (Sparkwright)\n'
      printf 'env:\n  LOOP_STATE_MODE: observe\n'
      printf 'jobs:\n  gate-backlog-presence:\n    steps:\n'
      printf '      - run: gh api "repos/x/pulls/1/files" -q %s[.[] | .filename, (.previous_filename // empty)] | if any(test("\\n")) then error("nl") else .[] end%s > /tmp/changed.txt\n' "'" "'"
      printf '      - run: sh conformance/agent-boundary.sh --check-complete --changed /tmp/changed.txt\n'
      printf '      - run: sh conformance/agent-boundary.sh --conclusion "$rc"\n'
      printf '      - run: if [ -n "$concl" ]; then true; fi\n'
      printf '  gate-loop-state:\n    steps:\n'
      printf '      - run: sh conformance/loop-state.sh --head "$SHA"\n'
      printf '      - run: status="completed"; concl="neutral"\n'
    } > "$1"
  }

  # 1. CLEAN source -> every static assertion PASSES.
  mk_clean_src "$base/src.yml"
  _ok=1
  assert_marker            "$base/src.yml" || _ok=0
  assert_wired              "$base/src.yml" >/dev/null 2>&1 || _ok=0
  assert_stack_neutral       "$base/src.yml" >/dev/null 2>&1 || _ok=0
  assert_loop_state_active   "$base/src.yml" >/dev/null 2>&1 || _ok=0
  if [ "$_ok" = 1 ]; then echo "OK: clean source -> marker + wired + stack-neutral + loop-state-active all PASS"; else echo "FAIL: selftest case1 — a clean source fixture reported a gap"; st=1; fi

  # 2. UNWIRED source (drop a conformance call) -> assert_wired RED.
  mk_clean_src "$base/nowire.yml"
  grep -v 'agent-boundary.sh --conclusion' "$base/nowire.yml" > "$base/nowire.yml.tmp" && mv "$base/nowire.yml.tmp" "$base/nowire.yml"
  if assert_wired "$base/nowire.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2 — a source missing a conformance call passed assert_wired"; st=1; else echo "OK: unwired source -> RED (assert_wired)"; fi

  # 2b. HOLLOW: the wiring is COMMENTED OUT, not deleted -> assert_wired RED (comment-strip is
  #     load-bearing).
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf 'jobs:\n  x:\n    steps:\n'
    printf '      - run: gh api "repos/x/pulls/1/files" -q %s[.[] | .filename, (.previous_filename // empty)] | if any(test("\\n")) then error("nl") else .[] end%s > /tmp/changed.txt\n' "'" "'"
    printf '      - run: sh conformance/agent-boundary.sh --check-complete --changed /tmp/changed.txt\n'
    printf '      # - run: sh conformance/agent-boundary.sh --conclusion "$rc"\n'
    printf '      # - run: if [ -n "$concl" ]; then true; fi\n'
  } > "$base/hollow.yml"
  if assert_wired "$base/hollow.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2b — a source with COMMENTED-OUT wiring passed assert_wired (hollow gate)"; st=1; else echo "OK: commented-out wiring -> RED (assert_wired comment-strip)"; fi

  # 2c. LOAD-BEARING NEGATIVE for the previous_filename anchor: a listing derived WITHOUT it must FAIL.
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf 'jobs:\n  x:\n    steps:\n'
    printf '      - run: gh api "repos/x/pulls/1/files" -q %s.[].filename%s > /tmp/changed.txt\n' "'" "'"
    printf '      - run: sh conformance/agent-boundary.sh --check-complete --changed /tmp/changed.txt\n'
    printf '      - run: sh conformance/agent-boundary.sh --conclusion "$rc"\n'
    printf '      - run: if [ -n "$concl" ]; then true; fi\n'
    printf '      - run: concl="neutral"\n'
  } > "$base/collapsing.yml"
  if assert_wired "$base/collapsing.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2c — a source deriving its listing WITHOUT previous_filename passed assert_wired"; st=1; else echo "OK: listing without previous_filename -> RED (T2 anchor is load-bearing)"; fi

  # 2d. LOAD-BEARING NEGATIVE for the newline-guard anchor.
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf 'jobs:\n  x:\n    steps:\n'
    printf '      - run: gh api "repos/x/pulls/1/files" -q %s.[] | .filename, (.previous_filename // empty)%s > /tmp/changed.txt\n' "'" "'"
    printf '      - run: sh conformance/agent-boundary.sh --check-complete --changed /tmp/changed.txt\n'
    printf '      - run: sh conformance/agent-boundary.sh --conclusion "$rc"\n'
    printf '      - run: if [ -n "$concl" ]; then true; fi\n'
    printf '      - run: concl="neutral"\n'
  } > "$base/noguard.yml"
  if assert_wired "$base/noguard.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2d — a source projecting previous_filename but with NO newline guard passed assert_wired"; st=1; else echo "OK: listing without a newline guard -> RED (guard anchor is load-bearing)"; fi

  # 2e. LOAD-BEARING NEGATIVE for the --check-complete anchor.
  mk_clean_src "$base/nocap.yml"
  grep -v 'check-complete' "$base/nocap.yml" > "$base/nocap.yml.tmp" && mv "$base/nocap.yml.tmp" "$base/nocap.yml"
  if assert_wired "$base/nocap.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2e — a source with no --check-complete call passed assert_wired"; st=1; else echo "OK: listing with no truncation check -> RED (A4 anchor is load-bearing)"; fi

  # 2f. LOAD-BEARING NEGATIVE for the conclusion-omission guard.
  mk_clean_src "$base/noomit.yml"
  grep -v 'if \[ -n "\$concl" \]; then' "$base/noomit.yml" > "$base/noomit.yml.tmp" && mv "$base/noomit.yml.tmp" "$base/noomit.yml"
  if assert_wired "$base/noomit.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f — a source with no conclusion-omission guard passed assert_wired"; st=1; else echo "OK: no conclusion-omission guard -> RED"; fi

  # 2g. LOAD-BEARING NEGATIVE for the Δ1 neutral anchor.
  mk_clean_src "$base/noneutral.yml"
  grep -v 'concl="neutral"' "$base/noneutral.yml" > "$base/noneutral.yml.tmp" && mv "$base/noneutral.yml.tmp" "$base/noneutral.yml"
  if assert_wired "$base/noneutral.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2g — a source that never posts neutral passed assert_wired"; st=1; else echo "OK: no neutral posting -> RED (Δ1 anchor is load-bearing)"; fi

  # 3. STACK-SPECIALIZED source (plant actions/setup-node) -> assert_stack_neutral RED.
  mk_clean_src "$base/stacky.yml"
  printf '      - uses: actions/setup-node@v4\n' >> "$base/stacky.yml"
  if assert_stack_neutral "$base/stacky.yml" >/dev/null 2>&1; then echo "FAIL: selftest case3 — a source carrying actions/setup-node passed assert_stack_neutral"; st=1; else echo "OK: stack-specialized source -> RED (assert_stack_neutral)"; fi

  # 4. FAMILY LOCK: a per-profile SUBDIR copy -> assert_single_source RED.
  mkdir -p "$base/prof/go"
  : > "$base/prof/go/adopter-gates.yml"
  if assert_single_source "$base/prof" >/dev/null 2>&1; then echo "FAIL: selftest case4 — a per-profile adopter-gates copy passed the family lock"; st=1; else echo "OK: per-profile subdir copy -> RED (family lock)"; fi
  mkdir -p "$base/prof2"; : > "$base/prof2/adopter-gates.yml"
  if assert_single_source "$base/prof2" >/dev/null 2>&1; then echo "OK: top-level source only, no subdir copy -> PASS"; else echo "FAIL: selftest case4b — a clean single-source root was flagged by the family lock"; st=1; fi

  # 5. INCEPT INSTALL LINE: re-gated per-stack, or not referencing the shared source -> RED.
  printf '%s\n' 'cp_kit_replace "profiles/adopter-gates.yml" .github/workflows/adopter-gates.yml' > "$base/incept-good.sh"
  if assert_incept_universal "$base/incept-good.sh" >/dev/null 2>&1; then echo "OK: unconditional shared-source install -> PASS"; else echo "FAIL: selftest case5a — a correct incept install line was flagged"; st=1; fi
  printf '%s\n' '[ -f "profiles/${STACK}/adopter-gates.yml" ] && cp_kit_replace "profiles/${STACK}/adopter-gates.yml" .github/workflows/adopter-gates.yml' > "$base/incept-bad.sh"
  if assert_incept_universal "$base/incept-bad.sh" >/dev/null 2>&1; then echo "FAIL: selftest case5b — a per-stack-gated install line passed assert_incept_universal"; st=1; else echo "OK: per-stack-gated install -> RED (assert_incept_universal)"; fi

  # 5c. Δ1 LOAD-BEARING NEGATIVE: a source defaulting to enforce (not observe) must FAIL.
  mk_clean_src "$base/enforcedefault.yml"
  sed 's/LOOP_STATE_MODE: observe/LOOP_STATE_MODE: enforce/' "$base/enforcedefault.yml" > "$base/enforcedefault.yml.tmp" && mv "$base/enforcedefault.yml.tmp" "$base/enforcedefault.yml"
  if assert_loop_state_active "$base/enforcedefault.yml" >/dev/null 2>&1; then echo "FAIL: selftest case5c — a source defaulting LOOP_STATE_MODE to enforce (not observe) passed assert_loop_state_active"; st=1; else echo "OK: enforce-by-default source -> RED (Δ1 day-one non-blocking default is load-bearing)"; fi

  # 5e. I2 SURVIVING MUTANT (reviewer): the live CODE default is enforce, but a COMMENT elsewhere in
  #     the file duplicates the literal string "LOOP_STATE_MODE: observe" (stale header prose) — a
  #     raw (non-comment-stripped) grep would be satisfied by that comment even though the real
  #     default has drifted. Must RED.
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf '# stale header prose (never updated):    LOOP_STATE_MODE: observe   (default — a nudge)\n'
    printf 'env:\n  LOOP_STATE_MODE: enforce\n'
    printf 'jobs:\n  gate-loop-state:\n    steps:\n'
    printf '      - run: sh conformance/loop-state.sh --head "$SHA"\n'
    printf '      - run: status="completed"; concl="neutral"\n'
  } > "$base/commentdup.yml"
  if assert_loop_state_active "$base/commentdup.yml" >/dev/null 2>&1; then echo "FAIL: selftest case5e — a source defaulting to enforce in CODE, with only a COMMENT duplicating 'LOOP_STATE_MODE: observe', passed assert_loop_state_active (I2 surviving mutant)"; st=1; else echo "OK: comment-only observe duplicate with enforce live in code -> RED (I2 mutant killed)"; fi

  # 5d. Δ1 LOAD-BEARING NEGATIVE: the FALLBACK shape (loop-state.sh --head fully commented out, no
  #     invocation at all) must NOT read as ACTIVE.
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf 'env:\n  LOOP_STATE_MODE: observe\n'
    printf 'jobs:\n  gate-loop-state:\n    steps:\n'
    printf '      # - run: sh conformance/loop-state.sh --head "$SHA"\n'
    printf '      - run: status="completed"; concl="neutral"\n'
  } > "$base/commentedblock.yml"
  if assert_loop_state_active "$base/commentedblock.yml" >/dev/null 2>&1; then echo "FAIL: selftest case5d — a source with loop-state.sh --head fully COMMENTED OUT (the fallback shape) passed assert_loop_state_active"; st=1; else echo "OK: commented-out-block fallback shape -> RED (Δ1 ships ACTIVE, not the fallback)"; fi

  # 6. BEHAVIOURAL WITNESS: drive REAL incept for terraform (a NON-ts, EXEMPT stack) against this
  #    tree's working state and assert .github/workflows/adopter-gates.yml LANDS byte-identical to
  #    the source. Mirrors ratification-parity.sh's own case 6.
  if command -v git >/dev/null 2>&1 && [ -f "$INCEPT" ]; then
    _ref=$(git stash create 2>/dev/null || true); [ -n "$_ref" ] || _ref=$(git rev-parse HEAD 2>/dev/null || echo HEAD)
    _t="$base/incept"; mkdir -p "$_t"
    if git archive "$_ref" 2>/dev/null | tar -x -C "$_t" 2>/dev/null; then
      if ( cd "$_t" && sh scripts/incept.sh --noninteractive --name AdopterGatesParity --intent-owner CI \
             --stack terraform --backlog md --ci github --harness claude-code ) >/dev/null 2>&1; then
        if [ -f "$_t/.github/workflows/adopter-gates.yml" ] \
           && diff "$_t/.github/workflows/adopter-gates.yml" "$_t/profiles/adopter-gates.yml" >/dev/null 2>&1; then
          echo "OK: incept --stack terraform -> .github/workflows/adopter-gates.yml lands == profiles/adopter-gates.yml (non-ts, exempt stack witnessed)"
        else
          echo "FAIL: selftest case6 — incepting a non-ts (terraform) stack did NOT install the board/loop gates from the shared source"; st=1
        fi
      else
        echo "FAIL: selftest case6 — incept --stack terraform did not complete (cannot witness the install)"; st=1
      fi
    else
      echo "FAIL: selftest case6 — could not archive the working tree to drive incept"; st=1
    fi
  else
    echo "FAIL: selftest case6 — git or $INCEPT unavailable; cannot witness the behavioural install"; st=1
  fi

  # 7. KIT-SELF N/A: an adopter-shaped tree (NEITHER kit-dev marker) -> run() N/A, exit 0, never a FAIL.
  _a="$base/adopter"; mkdir -p "$_a"
  if _c7=$( cd "$_a" && SRC="profiles/adopter-gates.yml" INCEPT="scripts/incept.sh"; run 2>&1 ); then _c7rc=0; else _c7rc=$?; fi
  if [ "$_c7rc" = 0 ] && printf '%s\n' "$_c7" | grep -q 'N/A — kit-self check'; then
    echo "OK: adopter-shaped tree (no kit-dev markers) -> N/A, exit 0 (kit-self carve-out)"
  else
    echo "FAIL: selftest case7 — adopter tree did not N/A green (rc=$_c7rc): $_c7"; st=1
  fi

  # 8. GITLAB STRUCTURAL N/A (Δ6): a GitLab-only adopter (.gitlab-ci.yml, no GitHub CI, no adopter-
  #    gates workflow) -> the platform-conditional escape; a GitHub tree with the SAME markers must
  #    NOT take it (checked normally instead).
  _gl="$base/gl"; mkdir -p "$_gl"; : > "$_gl/.gitlab-ci.yml"
  [ "$(_ag_gitlab_only_adopter "$_gl")" = 1 ] || { echo "FAIL: selftest case8a — a GitLab adopter (.gitlab-ci.yml, no adopter-gates workflow) must take the platform-conditional N/A"; st=1; }
  _gh="$base/gh"; mkdir -p "$_gh/.github/workflows"; : > "$_gh/$CI_WF"
  [ "$(_ag_gitlab_only_adopter "$_gh")" = 0 ] || { echo "FAIL: selftest case8b — a GitHub adopter must NOT take the GitLab escape (its missing gates are real drift)"; st=1; }

  if [ "$st" = 0 ]; then echo "adopter-gates-parity --selftest: OK (all cases witnessed)"; else echo "adopter-gates-parity --selftest: FAIL"; fi
  return "$st"
}

case "${1:-}" in
  --selftest) selftest ;;
  '')         run ;;
  *)          echo "usage: adopter-gates-parity.sh [--selftest]" >&2; exit 2 ;;
esac
