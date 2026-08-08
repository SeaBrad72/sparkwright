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
  # B2 Δ4(ii) / reviewer I4 — THE JUDGMENT-SURFACE RENDER IS PART OF THE GATE. ceremony-binding's
  # disposition has two halves: the gate REFUSES an unrecorded design GO, and the matched record is
  # RENDERED at the judgment surface so a minted one walks into the reviewer's field of view before
  # the click (D-240805-4). A source carrying only the first half ships adopters the enforcement
  # without the visibility — the mirror-divergence class B6 paid a Critical for. Two anchors,
  # because the SHAPE is load-bearing too: the body must go inside a GROWN FENCE, never per-field
  # markdown (a forged field closed a code span and emitted `<br>`, rendering a second
  # authoritative-looking approved-by line — measured, B2 sec H2). Negatives: cases 2h/2i.
  printf '%s\n' "$_wcode" | grep -qF 'GITHUB_STEP_SUMMARY' || { echo "FAIL: $1 never writes \$GITHUB_STEP_SUMMARY — the matched GO record would not reach the judgment surface, so an adopter's reviewer gets the gate without the visibility half of the disposition (B2 Δ4(ii))"; _w=1; }
  printf '%s\n' "$_wcode" | grep -qF 'fence="$fence"' || { echo "FAIL: $1 renders the GO record without the grown-fence guard (\`fence=\"\$fence\"\`) — ledger content is untrusted, and per-field markdown lets a forged field render a SECOND approved-by line with a stronger assurance label (measured)"; _w=1; }
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
      # B2 Δ4(ii): the judgment-surface render (grown fence + step summary) is part of the wired
      # contract, so the CLEAN fixture must carry it — otherwise this fixture asserts a gap the
      # real shipped source does not have.
      printf '  gate-ceremony-binding:\n    steps:\n'
      printf '      - run: while printf %%s "$body" | grep -qF -- "$fence"; do fence="$fence"%s`%s; done\n' "'" "'"
      printf '      - run: printf %s%%s\\n%s "$fence" "$body" "$fence" >> "$GITHUB_STEP_SUMMARY"\n' "'" "'"
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

  # 2h/2i (B2 Δ4(ii) / reviewer I4, LOAD-BEARING NEGATIVES) — a source that gates ceremony-binding
  # but never RENDERS the matched record to the judgment surface must be RED (2h), and so must one
  # that renders it WITHOUT the grown-fence guard (2i) — untrusted ledger content interpolated into
  # per-field markdown is what let a forged field render a second, stronger `approved-by` line.
  # Without these cases either anchor could be deleted with the suite still green, which is exactly
  # how an emitted profile comes to carry enforcement without visibility.
  mk_clean_src "$base/norender.yml"
  grep -v 'GITHUB_STEP_SUMMARY' "$base/norender.yml" > "$base/norender.tmp" && mv "$base/norender.tmp" "$base/norender.yml"
  if assert_wired "$base/norender.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2h — a source that never writes \$GITHUB_STEP_SUMMARY passed assert_wired; adopters would get the gate without the judgment-surface render"; st=1; else echo "OK: source with no judgment-surface render -> RED (B2 Δ4(ii) anchor is load-bearing)"; fi
  mk_clean_src "$base/nofence.yml"
  grep -v 'fence="\$fence"' "$base/nofence.yml" > "$base/nofence.tmp" && mv "$base/nofence.tmp" "$base/nofence.yml"
  if assert_wired "$base/nofence.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2i — a source rendering the GO record with no grown-fence guard passed assert_wired; a forged field could render a second approved-by line"; st=1; else echo "OK: render without the grown-fence guard -> RED (escaping anchor is load-bearing)"; fi

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

  # 9. B2 round-2, security M-new-1 — THE RENDER IS EXECUTED, not merely grepped. GitHub caps
  #    $GITHUB_STEP_SUMMARY at 1 MiB and DROPS THE WHOLE SUMMARY past it, so an unbounded render is
  #    a "hide the GO record" path by VOLUME: one forged field measured 1,601,670 bytes emitted
  #    before the bound, which would have posted ceremony-binding PASS with NOTHING rendered — the
  #    exact outcome Δ4(ii) exists to prevent, and the sentence the guard's ceiling rests on
  #    ("the honest control is Δ4(ii)'s VISIBILITY"). Cases 2h/2i only assert the render's SHAPE by
  #    grep; this one RUNS it against a FIXTURE ledger ref — never refs/notes/promotions
  #    (D-240805-3) — for BOTH real sources, which also witnesses the ci.yml/profile mirror
  #    behaviourally. Asserts: (a) a huge record renders TRUNCATED, not dropped, (b) the truncation
  #    is ANNOUNCED (silent truncation hides the record just as effectively), (c) the record's own
  #    head survives, (d) a normal record is NOT truncated and renders whole, (e) a backtick-run
  #    body still gets a fence longer than the run (the one-pass fence must not regress the escape).
  _extract_render() {  # <yml> <out-script> — lift the render step's shell out of the workflow
    awk '
      /- name: Render the matched GO record into the step summary/ { instep=1; next }
      instep && /^[[:space:]]*run: \|/ { inbody=1; next }
      inbody {
        if ($0 ~ /^[[:space:]]*$/) { print ""; next }
        if ($0 !~ /^          /) { exit }
        sub(/^          /, ""); print
      }
    ' "$1" > "$2"
    [ -s "$2" ]
  }
  _fixture_ledger() {  # <dir> <body-file> — a throwaway repo whose FIXTURE notes ref holds the record
    mkdir -p "$1"
    ( cd "$1" && git init -q . \
      && git config user.email tester@example.com && git config user.name tester \
      && git commit -q --allow-empty -m base \
      && git notes --ref=fixture-go add -F "$2" HEAD ) >/dev/null 2>&1
  }
  _fixture_ledger2() {  # <dir> <body1> <body2> — TWO commits, one scope-matching record EACH
    # (B7 rider: the render must show EVERY matching record, so its witness needs a ledger that
    # actually holds two; iteration order is annotated-SHA order, deliberately not controlled here
    # — the assertions below are order-independent).
    mkdir -p "$1"
    ( cd "$1" && git init -q . \
      && git config user.email tester@example.com && git config user.name tester \
      && git commit -q --allow-empty -m base1 \
      && git notes --ref=fixture-go add -F "$2" HEAD \
      && git commit -q --allow-empty -m base2 \
      && git notes --ref=fixture-go add -F "$3" HEAD ) >/dev/null 2>&1
  }
  _render_into() {  # <script> <repo> <summary-out> — run the extracted render as CI would
    : > "$3"
    ( cd "$2" && PROMOTION_NOTES_REF=fixture-go PR_NUMBER=909 GATE_RC=0 \
        GITHUB_STEP_SUMMARY="$3" sh "$1" ) >/dev/null 2>&1
  }
  _rbig="$base/render-big.txt"
  { printf 'gate: design\nscope: PR-909\napproved-by: someone [assurance: declared]\n'
    awk 'BEGIN { s = ""; for (i = 0; i < 1000; i++) s = s "A"; for (j = 0; j < 1600; j++) print s }'
  } > "$_rbig"
  _rtick="$base/render-tick.txt"
  { printf 'gate: design\nscope: PR-909\n'
    awk 'BEGIN { s = ""; for (i = 0; i < 2000; i++) s = s "`"; print s }'
  } > "$_rtick"
  _rsmall="$base/render-small.txt"
  printf 'gate: design\nscope: PR-909\napproved-by: owner [assurance: declared]\nbasis: docs/architecture/x-design.md\n' > "$_rsmall"
  _rn=0
  for _rsrc in "$SRC" "$CI_WF"; do
    _rn=$((_rn + 1))
    if [ ! -f "$_rsrc" ]; then echo "FAIL: selftest case9 — $_rsrc is missing; the judgment-surface render cannot be witnessed"; st=1; continue; fi
    _rscript="$base/render$_rn.sh"
    if ! _extract_render "$_rsrc" "$_rscript"; then
      echo "FAIL: selftest case9 — could not extract the render step's shell from $_rsrc (the step name or its \`run: |\` indentation changed; this case would silently stop witnessing the render)"; st=1; continue
    fi
    # (a)(b)(c) — the 1.6 MB forged record
    _rrepo="$base/rrepo$_rn"; _fixture_ledger "$_rrepo" "$_rbig"
    _rout="$base/summary-big$_rn.md"
    _render_into "$_rscript" "$_rrepo" "$_rout"
    _rbytes=$(wc -c < "$_rout" | tr -d ' ')
    if [ "$_rbytes" -le 65536 ]; then
      echo "OK: $_rsrc renders a $(wc -c < "$_rbig" | tr -d ' ')-byte record in $_rbytes bytes (under GitHub's 1 MiB summary cap, so the record is not DROPPED)"
    else
      echo "FAIL: selftest case9a — $_rsrc emitted $_rbytes bytes for one oversized record; GitHub drops a >1 MiB step summary WHOLE, so ceremony-binding would post PASS with no record rendered"; st=1
    fi
    if grep -qF 'truncated at 8 KB' "$_rout"; then
      echo "OK: $_rsrc ANNOUNCES the truncation (silent truncation hides the record just as well)"
    else
      echo "FAIL: selftest case9b — $_rsrc truncated (or dropped) the record with no notice; the reader cannot tell a short record from a cut one"; st=1
    fi
    grep -qF 'gate: design' "$_rout" \
      && echo "OK: $_rsrc keeps the record's own head inside the truncated render" \
      || { echo "FAIL: selftest case9c — $_rsrc rendered nothing of the record itself"; st=1; }
    # (d) — a NORMAL record must be untouched (the bound must not truncate ordinary records)
    _rrepo2="$base/rsmall$_rn"; _fixture_ledger "$_rrepo2" "$_rsmall"
    _rout2="$base/summary-small$_rn.md"
    _render_into "$_rscript" "$_rrepo2" "$_rout2"
    if grep -qF 'basis: docs/architecture/x-design.md' "$_rout2" && ! grep -qF 'truncated at 8 KB' "$_rout2"; then
      echo "OK: $_rsrc renders a normal record WHOLE, with no truncation notice"
    else
      echo "FAIL: selftest case9d — $_rsrc did not render a normal record whole/untruncated"; st=1
    fi
    # (f)/(g) — B7 RIDER: the render shows EVERY scope-matching record (rendering only the first
    # would show a defective record while the gate passed on a valid sibling — a D-240805-4
    # visibility lie), and the 8 KB bound is TOTAL ACROSS RECORDS, not per-record (self-review
    # finding 4: B2's measured volume attack applies with interest when N records render).
    # (f) two SMALL records -> BOTH bodies rendered, no truncation notice.
    _rtwoA="$base/render-twoA.txt"; _rtwoB="$base/render-twoB.txt"
    printf 'gate: design\nscope: PR-909\nmarker: RECORD-A-MARKER\n' > "$_rtwoA"
    printf 'gate: design\nscope: PR-909\nmarker: RECORD-B-MARKER\n' > "$_rtwoB"
    _rrepo4="$base/rtwo$_rn"; _fixture_ledger2 "$_rrepo4" "$_rtwoA" "$_rtwoB"
    _rout4="$base/summary-two$_rn.md"
    _render_into "$_rscript" "$_rrepo4" "$_rout4"
    if grep -qF 'RECORD-A-MARKER' "$_rout4" && grep -qF 'RECORD-B-MARKER' "$_rout4" \
       && ! grep -qF 'truncated at 8 KB' "$_rout4"; then
      echo "OK: $_rsrc renders BOTH scope-matching records, untruncated (render-all witnessed)"
    else
      echo "FAIL: selftest case9f — $_rsrc did not render EVERY scope-matching record (a defective record could hide behind the one rendered while the gate passed on another)"; st=1
    fi
    # (g) two records whose COMBINED size exceeds the bound -> bounded output + ANNOUNCED cut
    # (order-independent: whichever record iterates first, the TOTAL bound + notice must hold).
    _rrepo5="$base/rtwobig$_rn"; _fixture_ledger2 "$_rrepo5" "$_rtwoA" "$_rbig"
    _rout5="$base/summary-twobig$_rn.md"
    _render_into "$_rscript" "$_rrepo5" "$_rout5"
    _rbytes5=$(wc -c < "$_rout5" | tr -d ' ')
    if [ "$_rbytes5" -le 65536 ] && grep -qF 'truncated at 8 KB' "$_rout5" \
       && grep -qF 'gate: design' "$_rout5"; then
      echo "OK: $_rsrc bounds TWO records TOTAL ($_rbytes5 bytes) and announces the cut (finding 4)"
    else
      echo "FAIL: selftest case9g — $_rsrc with two records emitted $_rbytes5 bytes (want <=65536 + announced truncation + a record head) — the bound must be TOTAL across records, or N records reopen B2's volume attack"; st=1
    fi
    # (e) — the escape must survive the one-pass fence computation
    _rrepo3="$base/rtick$_rn"; _fixture_ledger "$_rrepo3" "$_rtick"
    _rout3="$base/summary-tick$_rn.md"
    _render_into "$_rscript" "$_rrepo3" "$_rout3"
    _rfence=$(awk '/^`+$/ { if (length($0) > m) m = length($0) } END { print m + 0 }' "$_rout3")
    if [ "$_rfence" -gt 2000 ]; then
      echo "OK: $_rsrc fences a 2,000-backtick body with a $_rfence-backtick fence (no content can close it)"
    else
      echo "FAIL: selftest case9e — $_rsrc emitted a $_rfence-backtick fence for a 2,000-backtick body; ledger content could close the fence and render as markdown"; st=1
    fi
  done

  if [ "$st" = 0 ]; then echo "adopter-gates-parity --selftest: OK (all cases witnessed)"; else echo "adopter-gates-parity --selftest: FAIL"; fi
  return "$st"
}

case "${1:-}" in
  --selftest) selftest ;;
  '')         run ;;
  *)          echo "usage: adopter-gates-parity.sh [--selftest]" >&2; exit 2 ;;
esac
