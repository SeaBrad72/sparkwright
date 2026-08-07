#!/bin/sh
# ratification-parity.sh — the §13 control-plane-ratification gate ships for EVERY stack.
#
# DEVELOPMENT-PROCESS.md §13's separation-of-duties gate (ratification.yml) is the governance control
# that stops an agent ratifying its own control-plane change. scripts/incept.sh installs it into every
# incepted project as .github/workflows/ratification.yml. The gate is 100% STACK-NEUTRAL — it runs only
# conformance/agent-boundary.sh + promotion-readiness.sh on ubuntu-latest, no toolchain step — so it
# ships as ONE shared source (profiles/ratification.yml — a top-level, non-stack asset like
# profiles/_TEMPLATE.md), NOT one copy per profile (that would be N byte-identical files, the drift trap
# this kit avoids; a top-level file also stays invisible to every profiles/*/ stack enumerator). Proves that single source is
# present, marked, wired, stack-neutral, the SOLE copy, and that incept installs it UNCONDITIONALLY for
# every stack — the STACK-PARITY fix-shape (assert parity from a single source; never hand-copy N files),
# applied to the governance gate.
#
# HONEST CEILING (read before trusting a green):
#   - The REAL run proves the single source's PRESENCE + SHAPE + SOLE-COPY, and that incept.sh's install
#     line references it unconditionally. It does NOT run incept — that behavioural witness is --selftest.
#   - The --selftest drives REAL incept for a NON-ts, EXEMPT stack (terraform) and asserts the workflow
#     LANDS byte-identical to the source. It does NOT re-prove the gate's RUNTIME behaviour (the CP-9
#     anchors: base-tree checkout, files-API listing, yellow waiting, same-repo re-trigger) — that is
#     conformance/proportional-gate-wired.sh, and is unchanged by this slice (the file is byte-identical
#     to the old ts-node copy apart from header comments). This slice proves REACH, not runtime.
#
#   usage: sh conformance/ratification-parity.sh [--selftest]   (run from repo root)
#   exit:  0 = single source present/marked/wired/neutral/sole + incept installs it universally (or N/A
#          on an adopter tree) · 1 = a parity gap · 2 = usage
set -eu
cd "$(dirname "$0")/.."

SRC="profiles/ratification.yml"    # the single, stack-neutral source (top-level: invisible to profiles/*/ stack enumerators)
INCEPT="scripts/incept.sh"

# is_adopter_tree: 0 (true) iff NOT the kit's own tree. This gate audits the KIT's OWN reference source;
# wired into verify.sh it must N/A on any adopter tree (exit 0, NEVER 2). Same TWO export-ignored kit-dev
# markers profile-parity.sh / feature-flags-wired.sh use (both stripped by git archive/adopter-export):
# docs/ROADMAP-KIT.md AND .github/workflows/golden-path.yml. Fail-closed on the kit (both present -> the
# audit RUNS); an adopter has neither -> N/A. Chosen over "profiles/ absent" because profiles/ SHIPS.
is_adopter_tree() {
  [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]
}

# ---- static assertions (each takes its target by ARGUMENT so --selftest can drive it against a fixture,
#      NOT an env var: this is a control-plane oracle and the kit forbids letting the environment redirect
#      one — cf. profile-parity.sh / governing-docs-current.sh) --------------------------------------

# marker: cp_kit_replace (incept.sh) refuses to overwrite a destination lacking this marker (brownfield
# safety). Without it, incept silently keeps the kit's INTERNAL workflow and every parity lock passes
# pointing at the wrong file. So the source must carry it or it cannot be installed at all.
assert_marker() { grep -qE 'COPY & ADAPT|Sparkwright' "$1"; }

# wired: the gate must invoke the two conformance scripts that ARE its adjudication (the exact tokens
# proportional-gate-wired.sh anchors). A source that stopped calling them would install a hollow gate.
# Read COMMENT-STRIPPED code (as assert_stack_neutral does) — a commented-out invocation is a hollow
# gate, not a wired one, and a raw grep would count the comment and pass it vacuously.
assert_wired() {  # <src-file>
  _w=0
  _wcode=$(grep -v '^[[:space:]]*#' "$1")
  printf '%s\n' "$_wcode" | grep -qF 'promotion-readiness.sh --class'  || { echo "FAIL: $1 does not invoke 'promotion-readiness.sh --class' — the gate would not classify the diff"; _w=1; }
  # T2 (L9). The anchor above is satisfied by an invocation fed a DEFECTIVE listing — it sees the call,
  # never the argument that decides the answer. A files-API listing built with a bare `.[].filename`
  # drops a rename's SOURCE path, so `git mv <control-plane> <ordinary>` classified `ordinary` and this
  # gate passed with "nothing to ratify". Anchor the projection itself so none of the emitted profiles
  # can regress to the collapsing form while still satisfying the invocation anchor.
  # T2. These two anchors are now the ONLY automated guard on the emitted profiles' listing shape — the
  # class-wide scanner was built and withdrawn (boarded `CHANGESET-DERIVATION-LOCK`), so do not delete
  # them expecting something else to catch it. Both have load-bearing negatives (selftest case 2c/2d).
  printf '%s\n' "$_wcode" | grep -qF 'previous_filename'  || { echo "FAIL: $1 derives its changed-file listing without projecting 'previous_filename' — a rename's SOURCE path is dropped, so a renamed control-plane path would be invisible to the gate and §13 would silently downgrade to agent-autonomous"; _w=1; }
  printf '%s\n' "$_wcode" | grep -qF 'test("\n")'  || { echo "FAIL: $1 derives its changed-file listing with no newline guard — \`jq -r\` emits a RAW newline, so a crafted filename splits one API entry into two lines that each classify separately (measured: a split control-plane path derives 'ordinary' and this gate posts GREEN)"; _w=1; }
  printf '%s\n' "$_wcode" | grep -qF 'agent-boundary.sh --conclusion'  || { echo "FAIL: $1 does not invoke 'agent-boundary.sh --conclusion' — the gate would not map its verdict to a check-run"; _w=1; }
  # A4. Third anchor on the listing's TRUSTWORTHINESS, alongside 2c (rename source) and 2d (newline).
  # Those two guard the listing's SHAPE; this guards its COMPLETENESS. GitHub's List-PR-files API stops
  # at a cap and reports SUCCESS, so a truncated listing looks healthy and the gate classifies on paths
  # it cannot enumerate — posting GREEN "nothing to ratify". An emitted profile that drops this call
  # ships an adopter a gate blind to truncation while parity stays green, which is the Slice-B
  # kit-tree-only regression shape. Load-bearing negative: selftest case 2e.
  printf '%s\n' "$_wcode" | grep -qF 'agent-boundary.sh --check-complete'  || { echo "FAIL: $1 does not invoke 'agent-boundary.sh --check-complete' — the gate would not notice a changed-file listing TRUNCATED at the forge's API cap, and would classify (and post GREEN) on a change-set it cannot fully enumerate"; _w=1; }
  # B2 Δ4(ii) / reviewer I4 — THE JUDGMENT-SURFACE RENDER IS PART OF THE GATE, not a kit-tree extra.
  # The kit's own ratification.yml renders the derived state/class into the step summary so a
  # reviewer sees what the gate decided without opening the log; an emitted profile that drops it
  # ships adopters the ENFORCEMENT half of the disposition without the VISIBILITY half — the exact
  # mirror-divergence class B6 paid a Critical for. Cheap to anchor, so anchored. Load-bearing
  # negative: selftest case 2f.
  printf '%s\n' "$_wcode" | grep -qF 'GITHUB_STEP_SUMMARY'  || { echo "FAIL: $1 never writes \$GITHUB_STEP_SUMMARY — the derived ratification state/class would not reach the judgment surface, so an adopter's reviewer gets the gate without the visibility half of the disposition (B2 Δ4(ii))"; _w=1; }
  printf '%s\n' "$_wcode" | grep -qF 'ratification state'  || { echo "FAIL: $1 does not render the 'ratification state' line into the step summary — the two derived lines (state + reconciled class) are what make the gate's decision legible before the click"; _w=1; }
  return "$_w"
}

# stack-neutral: the single-source approach is only honest if the source carries NO per-stack toolchain
# step. Anchored on actions/setup-<lang> (the canonical, unambiguous stack signal) plus package-manager
# verbs, read from COMMENT-STRIPPED code so the header prose can name them freely. A re-specialized source
# (e.g. someone adds setup-node) would still install for every stack but no longer be one — FAIL.
assert_stack_neutral() {  # <src-file>
  if grep -v '^[[:space:]]*#' "$1" \
     | grep -Eiq 'actions/setup-[a-z]|(^|[^-a-z])(npm|pnpm|yarn|pip|pipenv|poetry|cargo|rustup|dotnet|nuget|gradlew|gradle|mvnw|mvn|maven|bundler)([^a-z]|$)'; then
    echo "FAIL: $1 is not stack-neutral — it carries a per-stack toolchain step; the single-source install would no longer be universal"
    return 1
  fi
  return 0
}

# single-source family-lock: the source is the TOP-LEVEL profiles/ratification.yml, so NO
# profiles/<stack>/ratification.yml may exist — any per-profile subdir copy (a resurrected ts-node copy,
# or a new profile shipping its own divergent gate) is caught here, not in an adopter.
assert_single_source() {  # <profiles-root>
  _s=0
  for _f in "$1"/*/ratification.yml; do
    [ -f "$_f" ] || continue                                   # unexpanded glob when none exist
    echo "FAIL family-lock: $_f is a per-profile ratification copy — the single source is the top-level <root>/ratification.yml; remove it (a per-profile gate re-opens the drift this slice closes)"
    _s=1
  done
  return "$_s"
}

# incept installs it UNCONDITIONALLY: the install line references the shared source AND is not re-gated on
# a per-stack file. A static grep — the behavioural witness (incept actually produces the workflow for a
# non-ts stack) is the --selftest below. Both, because a grep proves the line exists, the run proves it works.
assert_incept_universal() {  # <incept-file>
  _i=0
  grep -qF 'profiles/ratification.yml' "$1" || { echo "FAIL: $1 does not install ratification from profiles/ratification.yml"; _i=1; }
  if grep -qF 'profiles/${STACK}/ratification.yml' "$1"; then
    echo "FAIL: $1 still gates the ratification install on a per-stack file (profiles/\${STACK}/ratification.yml) — 9 stacks would silently get no gate"
    _i=1
  fi
  return "$_i"
}

# ---- the run ------------------------------------------------------------------------------------------
run() {
  if is_adopter_tree; then
    echo "ratification-parity: N/A — kit-self check (audits the kit's own reference source; not present on an adopter tree)"
    return 0
  fi
  fail=0
  if [ -f "$SRC" ]; then
    assert_marker "$SRC" || { echo "FAIL: $SRC lacks the kit marker (COPY & ADAPT|Sparkwright) — cp_kit_replace would refuse to install it"; fail=1; }
    assert_wired "$SRC"        || fail=1
    assert_stack_neutral "$SRC" || fail=1
  else
    echo "FAIL: the single source $SRC is MISSING — no stack would get the §13 ratification gate"
    fail=1
  fi
  assert_single_source profiles   || fail=1
  assert_incept_universal "$INCEPT" || fail=1

  if [ "$fail" -ne 0 ]; then
    echo "FAIL: ratification-parity — the §13 gate does not ship uniformly for every stack"
    return 1
  fi
  echo "OK: ratification-parity — single source present, marked, wired, stack-neutral, sole copy; incept installs it universally"
  return 0
}

# ---- selftest (non-vacuity: every assertion is WITNESSED against a fixture and must be RED-able; the
#      behavioural case drives REAL incept, mirroring kit-base.sh / kit-update-*.sh) --------------------
selftest() {
  st=0
  base=$(mktemp -d)
  trap 'rm -rf "$base"' EXIT

  # A minimal CLEAN source fixture: carries the marker, both wiring tokens, and no toolchain step.
  mk_clean_src() {  # <path>
    mkdir -p "$(dirname "$1")"
    {
      printf '# COPY & ADAPT — reference ratification gate (Sparkwright)\n'
      printf 'jobs:\n  ratify:\n    runs-on: ubuntu-latest\n    steps:\n'
      # The listing projection is part of the wired contract (T2/L9), so the CLEAN fixture must carry it —
      # otherwise this fixture asserts a gap that the real shipped workflows do not have.
      printf '      - run: gh api "repos/x/pulls/1/files" -q %s[.[] | .filename, (.previous_filename // empty)] | if any(test("\\n")) then error("nl") else .[] end%s > /tmp/changed.txt\n' "'" "'"
      # A4: the completeness call is part of the wired contract too, for the same reason as the
      # projection above — the CLEAN fixture must carry everything the real shipped workflows carry,
      # or it asserts a gap they do not have.
      printf '      - run: sh conformance/agent-boundary.sh --check-complete --changed /tmp/changed.txt\n'
      printf '      - run: sh conformance/promotion-readiness.sh --class --no-verify\n'
      printf '      - run: sh conformance/agent-boundary.sh --conclusion "$rc"\n'
      # B2 Δ4(ii): the judgment-surface render is part of the wired contract too — same reason as
      # the two anchors above; the CLEAN fixture must carry everything the shipped workflows carry.
      printf '      - run: printf %s- **ratification state**: `%%s`\\n%s "$state" >> "$GITHUB_STEP_SUMMARY"\n' "'" "'"
    } > "$1"
  }

  # 1. CLEAN source -> every static assertion PASSES.
  mk_clean_src "$base/src.yml"
  _ok=1
  assert_marker        "$base/src.yml" || _ok=0
  assert_wired         "$base/src.yml" >/dev/null 2>&1 || _ok=0
  assert_stack_neutral "$base/src.yml" >/dev/null 2>&1 || _ok=0
  if [ "$_ok" = 1 ]; then echo "OK: clean source -> marker + wired + stack-neutral all PASS"; else echo "FAIL: selftest case1 — a clean source fixture reported a gap"; st=1; fi

  # 2. UNWIRED source (drop a conformance call) -> assert_wired RED.
  mk_clean_src "$base/nowire.yml"
  grep -v 'agent-boundary.sh --conclusion' "$base/nowire.yml" > "$base/nowire.yml.tmp" && mv "$base/nowire.yml.tmp" "$base/nowire.yml"
  if assert_wired "$base/nowire.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2 — a source missing a conformance call passed assert_wired"; st=1; else echo "OK: unwired source -> RED (assert_wired)"; fi

  # 2b. HOLLOW source: the wiring is COMMENTED OUT, not deleted -> assert_wired RED (comment-strip is
  #     load-bearing; a raw grep would count the comment and pass a hollow gate vacuously).
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf 'jobs:\n  ratify:\n    steps:\n'
    printf '      - run: sh conformance/promotion-readiness.sh --class --no-verify\n'
    printf '      # - run: sh conformance/agent-boundary.sh --conclusion "$rc"\n'
  } > "$base/hollow.yml"
  if assert_wired "$base/hollow.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2b — a source with COMMENTED-OUT wiring passed assert_wired (hollow gate)"; st=1; else echo "OK: commented-out wiring -> RED (assert_wired comment-strip)"; fi

  # 2c. LOAD-BEARING NEGATIVE for the previous_filename anchor (T2/L9). Without this case, DELETING that
  #     anchor leaves this selftest AND the real-tree run green, and `non-vacuity.sh` still reports KILLED
  #     because it neuters all FAIL paths at once and structurally cannot see one missing assertion.
  #     Measured. A source can carry both invocations and still derive a rename-collapsing listing.
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf 'jobs:\n  ratify:\n    steps:\n'
    printf '      - run: gh api "repos/x/pulls/1/files" -q %s.[].filename%s > /tmp/changed.txt\n' "'" "'"
    printf '      - run: sh conformance/promotion-readiness.sh --class --no-verify\n'
    printf '      - run: sh conformance/agent-boundary.sh --conclusion "$rc"\n'
  } > "$base/collapsing.yml"
  if assert_wired "$base/collapsing.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2c — a source deriving its listing WITHOUT previous_filename passed assert_wired; a renamed control-plane path would be invisible to the gate"; st=1; else echo "OK: listing without previous_filename -> RED (T2 anchor is load-bearing)"; fi

  # 2d. LOAD-BEARING NEGATIVE for the newline-guard anchor. A source can project previous_filename and
  #     STILL emit a splittable listing, because `jq -r` renders a raw newline. Without this case, deleting
  #     the guard anchor leaves the selftest green — the same gap case 2c was added to close for the other
  #     anchor. These two anchors are the only automated guard left after the class scanner was withdrawn.
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf 'jobs:\n  ratify:\n    steps:\n'
    printf '      - run: gh api "repos/x/pulls/1/files" -q %s.[] | .filename, (.previous_filename // empty)%s > /tmp/changed.txt\n' "'" "'"
    printf '      - run: sh conformance/promotion-readiness.sh --class --no-verify\n'
    printf '      - run: sh conformance/agent-boundary.sh --conclusion "$rc"\n'
  } > "$base/noguard.yml"
  if assert_wired "$base/noguard.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2d — a source projecting previous_filename but with NO newline guard passed assert_wired; a crafted filename would split one API entry into two lines that each classify separately"; st=1; else echo "OK: listing without a newline guard -> RED (guard anchor is load-bearing)"; fi

  # 2e. LOAD-BEARING NEGATIVE for the A4 completeness anchor. A source can carry a perfectly-shaped
  #     listing (previous_filename + newline guard) and still be blind to TRUNCATION, because the API
  #     stops at its cap and reports SUCCESS. Without this case, deleting the --check-complete anchor
  #     leaves the selftest green — the same gap 2c and 2d exist to close for the other two anchors.
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf 'jobs:\n  ratify:\n    steps:\n'
    printf '      - run: gh api "repos/x/pulls/1/files" -q %s.[] | .filename, (.previous_filename // empty) | if any(test("\\n")) then error("x") else .[] end%s > /tmp/changed.txt\n' "'" "'"
    printf '      - run: sh conformance/promotion-readiness.sh --class --no-verify\n'
    printf '      - run: sh conformance/agent-boundary.sh --conclusion "$rc"\n'
  } > "$base/nocap.yml"
  if assert_wired "$base/nocap.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2e — a source with a well-shaped listing but NO --check-complete call passed assert_wired; a listing truncated at the forge's API cap would classify as complete and the gate would post GREEN on a change-set it cannot enumerate"; st=1; else echo "OK: listing with no truncation check -> RED (A4 anchor is load-bearing)"; fi

  # 2f (B2 Δ4(ii) / reviewer I4, LOAD-BEARING NEGATIVE) — a source that gates but never RENDERS the
  # derived state/class to the judgment surface must be RED. Without this case the render anchor
  # could be deleted and the suite would stay green, which is precisely how an emitted profile comes
  # to ship the enforcement half of a disposition without its visibility half (the mirror-divergence
  # class B6 paid a Critical for).
  mk_clean_src "$base/norender.yml"
  grep -v 'GITHUB_STEP_SUMMARY' "$base/norender.yml" > "$base/norender2.yml"
  mv "$base/norender2.yml" "$base/norender.yml"
  if assert_wired "$base/norender.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f — a source that never writes \$GITHUB_STEP_SUMMARY passed assert_wired; adopters would get the gate without the judgment-surface render"; st=1; else echo "OK: source with no judgment-surface render -> RED (B2 Δ4(ii) anchor is load-bearing)"; fi

  # 3. STACK-SPECIALIZED source (plant actions/setup-node) -> assert_stack_neutral RED.
  mk_clean_src "$base/stacky.yml"
  printf '      - uses: actions/setup-node@v4\n' >> "$base/stacky.yml"
  if assert_stack_neutral "$base/stacky.yml" >/dev/null 2>&1; then echo "FAIL: selftest case3 — a source carrying actions/setup-node passed assert_stack_neutral"; st=1; else echo "OK: stack-specialized source -> RED (assert_stack_neutral)"; fi

  # 4. FAMILY LOCK: a per-profile SUBDIR copy -> assert_single_source RED.
  mkdir -p "$base/prof/go"
  : > "$base/prof/go/ratification.yml"
  if assert_single_source "$base/prof" >/dev/null 2>&1; then echo "FAIL: selftest case4 — a per-profile ratification copy passed the family lock"; st=1; else echo "OK: per-profile subdir copy -> RED (family lock)"; fi
  # ...and a root with ONLY the top-level source (no subdir copy) must PASS.
  mkdir -p "$base/prof2"; : > "$base/prof2/ratification.yml"
  if assert_single_source "$base/prof2" >/dev/null 2>&1; then echo "OK: top-level source only, no subdir copy -> PASS"; else echo "FAIL: selftest case4b — a clean single-source root was flagged by the family lock"; st=1; fi

  # 5. INCEPT INSTALL LINE: re-gated per-stack, or not referencing the shared source -> assert_incept_universal RED.
  printf '%s\n' 'cp_kit_replace "profiles/ratification.yml" .github/workflows/ratification.yml' > "$base/incept-good.sh"
  if assert_incept_universal "$base/incept-good.sh" >/dev/null 2>&1; then echo "OK: unconditional shared-source install -> PASS"; else echo "FAIL: selftest case5a — a correct incept install line was flagged"; st=1; fi
  printf '%s\n' '[ -f "profiles/${STACK}/ratification.yml" ] && cp_kit_replace "profiles/${STACK}/ratification.yml" .github/workflows/ratification.yml' > "$base/incept-bad.sh"
  if assert_incept_universal "$base/incept-bad.sh" >/dev/null 2>&1; then echo "FAIL: selftest case5b — a per-stack-gated install line passed assert_incept_universal"; st=1; else echo "OK: per-stack-gated install -> RED (assert_incept_universal)"; fi

  # 6. BEHAVIOURAL WITNESS: drive REAL incept for terraform (a NON-ts, EXEMPT stack) against this tree's
  #    working state and assert .github/workflows/ratification.yml LANDS byte-identical to the source.
  #    git stash create captures tracked working-tree MODIFICATIONS (not untracked new files — a newly
  #    added source must be committed or `git add`ed to be witnessed); it falls back to HEAD on a clean
  #    tree, which is the case in CI. This is the tree-independent proof the static greps cannot give:
  #    that incept actually produces the gate for a stack that is not ts-node.
  if command -v git >/dev/null 2>&1 && [ -f "$INCEPT" ]; then
    _ref=$(git stash create 2>/dev/null || true); [ -n "$_ref" ] || _ref=$(git rev-parse HEAD 2>/dev/null || echo HEAD)
    _t="$base/incept"; mkdir -p "$_t"
    if git archive "$_ref" 2>/dev/null | tar -x -C "$_t" 2>/dev/null; then
      if ( cd "$_t" && sh scripts/incept.sh --noninteractive --name RatParity --intent-owner CI \
             --stack terraform --backlog md --ci github --harness claude-code ) >/dev/null 2>&1; then
        if [ -f "$_t/.github/workflows/ratification.yml" ] \
           && diff "$_t/.github/workflows/ratification.yml" "$_t/profiles/ratification.yml" >/dev/null 2>&1; then
          echo "OK: incept --stack terraform -> .github/workflows/ratification.yml lands == profiles/ratification.yml (non-ts, exempt stack witnessed)"
        else
          echo "FAIL: selftest case6 — incepting a non-ts (terraform) stack did NOT install the ratification gate from the shared source"; st=1
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
  #    LOAD-BEARING: strip the carve-out and run() proceeds, hits the missing shared source, exit 1 — so
  #    this reddens if the N/A guard is ever removed, which is what lets the gate live in verify.sh.
  _a="$base/adopter"; mkdir -p "$_a"
  if _c7=$( cd "$_a" && SRC="profiles/ratification.yml" INCEPT="scripts/incept.sh"; run 2>&1 ); then _c7rc=0; else _c7rc=$?; fi
  if [ "$_c7rc" = 0 ] && printf '%s\n' "$_c7" | grep -q 'N/A — kit-self check'; then
    echo "OK: adopter-shaped tree (no kit-dev markers) -> N/A, exit 0 (kit-self carve-out)"
  else
    echo "FAIL: selftest case7 — adopter tree did not N/A green (rc=$_c7rc): $_c7"; st=1
  fi

  if [ "$st" = 0 ]; then echo "ratification-parity --selftest: OK (all cases witnessed)"; else echo "ratification-parity --selftest: FAIL"; fi
  return "$st"
}

case "${1:-}" in
  --selftest) selftest ;;
  '')         run ;;
  *)          echo "usage: ratification-parity.sh [--selftest]" >&2; exit 2 ;;
esac
