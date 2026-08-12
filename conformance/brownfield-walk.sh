#!/bin/sh
# brownfield-walk.sh — end-to-end lock for the documented BROWNFIELD adoption path
# (docs/adoption/brownfield.md). Builds a real legacy fixture repo, drives it literally through the
# CORRECTED documented sequence (whole export-tree copy + the human pre-push install + the by-hand
# §3 Inception artifacts), and asserts `conformance/inception-done.sh --surface` reaches rc 0.
#
# Non-vacuity is INTRINSIC (two load-bearing arms, the kit's own proof law):
#   • POSITIVE (liveness): the corrected walk reaches inception-done --surface rc 0.
#   • NEGATIVE (load-bearing): the SAME walk skipping ONLY the human pre-push install FAILs, and FAILs
#     on the pre-push leg specifically — so a walk that proved nothing (e.g. a tree that passes without
#     the hook) is caught. The negative is what makes the positive mean something.
#   • POSITIVE (second install mode): the same walk taking §2 step 5's OTHER documented install — the one-time
#     `core.hooksPath` keystroke that makes the TRACKED hooks/pre-push live — also reaches rc 0, with
#     NO installed copy in the tree. §2 step 5 leads with that option, and a documented install no arm walks
#     is prose; arm 2 is the load-bearing negative for this arm too.
# The teeth live entirely in this walk (both arms + assertions below), NOT in a pre-oracle accumulator,
# so non-vacuity.sh reports this check UNCOVERED=no-idiom (a script-selftest outside the mutation sweep,
# the A6 ceiling precedent) — the intrinsic two-arm structure here is its non-vacuity, stated honestly.
#
# KIT-SELF: the walk drives scripts/adopter-export.sh, which needs the kit's OWN committed .git. So this
# check has no meaning on an adopter tree (it verifies the kit's own documented onboarding path). It
# renders N/A there — via verify.sh's --kitself gate AND the in-script kit-repo detector below.
#
#   sh conformance/brownfield-walk.sh [--selftest]
# Exit: 0 = both arms hold (or N/A on an adopter tree) · 1 = an arm failed · 2 = usage.
# ⚠️ DISK SAFETY: the walk copies a full export tree per run. Every fixture lives under ONE mktemp -d
# dir that a trap removes on EXIT/INT/TERM — this never leaves a multi-hundred-file tree behind.
# POSIX sh; dash-clean.
set -eu

cd "$(dirname "$0")/.."
PROFILE=typescript-node

# ── build_legacy <dir> : a pre-existing product repo (code, history, its own foreign CI) — the
#    brownfield starting point, BEFORE any kit adoption.
build_legacy() {
  _d=$1
  mkdir -p "$_d/src" "$_d/.github/workflows"
  printf "console.log('legacy app');\n"                 > "$_d/src/app.js"
  printf '{"name":"legacy-app","version":"1.0.0"}\n'    > "$_d/package.json"
  printf '# Legacy App\nOur existing product.\n'        > "$_d/README.md"
  printf 'node_modules/\n'                              > "$_d/.gitignore"
  printf 'name: legacy-ci\non: push\njobs: {}\n'        > "$_d/.github/workflows/foreign-ci.yml"
  git -C "$_d" init -q
  git -C "$_d" add -A
  git -C "$_d" -c user.email=dev@legacy -c user.name=dev commit -qm 'legacy app history'
}

# ── adopt <dir> <export> <install_prepush> : drive <dir> through the CORRECTED documented sequence.
#    install_prepush=yes performs the HUMAN pre-push install step; =no skips ONLY that step (the
#    load-bearing negative — an agent cannot set the hook's mode, so this step is human-only; see
#    AGENT-CANNOT-INSTALL-AN-EXECUTABLE-HOOK).
adopt() {
  _d=$1; _export=$2; _install=$3

  # §1 — copy the ENTIRE export tree in (the durable whole-tree framing: adapters/, hooks/, agents/,
  #      .claude/{guard.sh,guard-core.sh,settings.json,agents/}, .kit/, AGENTS.md all arrive together),
  #      then rename the shipped CLAUDE.md so it does not collide with the project's own.
  cp -R "$_export/." "$_d/"
  mv "$_d/CLAUDE.md" "$_d/ENGINEERING-PRINCIPLES.md"
  # §1 — the profile CI pipeline (export-ignored, so it is NOT in the tree) merged in alongside foreign CI.
  cp "$_d/profiles/$PROFILE/ci.yml" "$_d/.github/workflows/ci.yml"

  # §2/§3 — the HUMAN pre-push install. Git hooks are untracked, so the whole-tree copy brought
  #         hooks/pre-push (the source) but NOT .git/hooks/pre-push. An agent cannot set mode 755
  #         (AGENT-CANNOT-INSTALL-AN-EXECUTABLE-HOOK) — this is a human command.
  #         install=tracked performs the OTHER documented install instead — the one-time
  #         `core.hooksPath` keystroke (brownfield §2 step 5 option (a)), which makes the TRACKED
  #         hooks/pre-push the live hook and leaves the default hooks dir empty on purpose.
  if [ "$_install" = yes ]; then
    cp "$_d/hooks/pre-push" "$_d/.git/hooks/pre-push"
    chmod +x "$_d/.git/hooks/pre-push"
  elif [ "$_install" = tracked ]; then
    git -C "$_d" config core.hooksPath hooks
  fi

  # §3 — the by-hand Inception judgment artifacts incept would stamp in greenfield.
  mkdir -p "$_d/docs/architecture"
  printf '# ADR-000: Stack\nTypeScript/Node. Status: accepted.\n' > "$_d/docs/architecture/ADR-000-stack.md"
  printf '# RUNBOOK\nSetup / deploy / rollback.\n'               > "$_d/RUNBOOK.md"
  printf '# env template\nAPI_KEY=\n'                            > "$_d/.env.example"
  printf '# Backlog\n| Row | Stage |\n|---|---|\n'               > "$_d/BACKLOG.md"

  # §3 — the entry contract stamped BYTE-IDENTICAL (first '## ' section of the principles doc) into the
  #      project CLAUDE.md (the contextFile), followed by the filled project header fields incept stamps.
  _entry=$(awk '/^## /{n++} n==1{print} n==2{exit}' "$_d/ENGINEERING-PRINCIPLES.md")
  {
    printf '# Legacy App — Project CLAUDE.md\n\n'
    printf '%s\n\n' "$_entry"
    printf '## Project configuration\n'
    printf '**Project:** legacy-app\n'
    printf '**Intent owner:** the product owner\n'
    printf -- '- **Backlog backend** (§6): `BACKLOG.md`\n'
    printf -- '- **Target harness(es)** (§harness-neutrality): claude-code\n'
  } > "$_d/CLAUDE.md"

  # §3 — commit the baseline BEFORE the gate (the contextFile must be tracked).
  git -C "$_d" add -A
  git -C "$_d" -c user.email=dev@legacy -c user.name=dev commit -qm 'adopt the kit (brownfield baseline)'
}

# selftest() is the non-vacuity ORACLE MARKER: this walk IS its own test (two load-bearing arms), so ALL
# of its logic + its _wfail accumulator live at/below this marker where non-vacuity.sh cannot neuter them.
# No mutable FAIL-path idiom sits ABOVE this marker, so the sweep reports this check UNCOVERED=no-idiom —
# its teeth are the intrinsic positive+negative arms, not a mutation-provable accumulator (A6 precedent).
selftest() {
  # KIT-SELF: N/A on an adopter tree (no kit .git to export from). OR-of-markers, fail-closed: run the
  # walk only when a kit-only marker is present (mirrors ci-selftest-coverage's kit-repo detector).
  if [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]; then
    echo "brownfield-walk: N/A — kit-self check (drives adopter-export against the kit's own .git; not applicable outside the kit repo)"
    return 0
  fi

  WORK=$(mktemp -d)
  # ⚠️ DISK SAFETY: one trap removes the entire fixture tree (full export ×2 fixtures) on any exit.
  trap 'rm -rf "$WORK"' EXIT INT TERM

  EXPORT="$WORK/export"
  if ! sh scripts/adopter-export.sh "$EXPORT" --profile "$PROFILE" >"$WORK/export.log" 2>&1; then
    echo "brownfield-walk: FAIL — could not produce the adopter export tree (see below)"
    sed 's/^/    | /' "$WORK/export.log"
    return 1
  fi

  _wfail=0

  # ── ARM 1 (POSITIVE / liveness): the corrected sequence reaches inception-done --surface rc 0.
  echo "--- arm 1: corrected brownfield sequence (with the human pre-push install) ---"
  _c="$WORK/corrected"
  build_legacy "$_c"
  adopt "$_c" "$EXPORT" yes
  if sh conformance/inception-done.sh --surface "$_c" >"$WORK/corrected.out" 2>&1; then
    echo "PASS: corrected walk reaches inception-done --surface rc 0"
  else
    echo "FAIL: corrected walk did NOT reach inception-done --surface rc 0 (see below)"
    sed 's/^/    | /' "$WORK/corrected.out"
    _wfail=1
  fi

  # ── ARM 2 (NEGATIVE / load-bearing): the SAME walk skipping ONLY the human pre-push install must
  #    FAIL, and FAIL on the pre-push leg — else the positive arm proves nothing.
  echo "--- arm 2: same walk, pre-push install SKIPPED (must fail on the pre-push leg) ---"
  _s="$WORK/skip-prepush"
  build_legacy "$_s"
  adopt "$_s" "$EXPORT" no
  if sh conformance/inception-done.sh --surface "$_s" >"$WORK/skip.out" 2>&1; then
    echo "FAIL: pre-push-skipped walk WRONGLY passed inception-done — the lock is vacuous"
    _wfail=1
  elif grep -q 'pre-push git hook missing' "$WORK/skip.out"; then
    echo "PASS: pre-push-skipped walk FAILs on the pre-push leg (load-bearing negative holds)"
  else
    echo "FAIL: pre-push-skipped walk failed, but NOT on the pre-push leg (unexpected cause; see below)"
    sed 's/^/    | /' "$WORK/skip.out"
    _wfail=1
  fi

  # ── ARM 3 (POSITIVE / liveness for the OTHER documented install): §2 step 5 now LEADS with tracked-hooks
  #    mode (the one-time core.hooksPath keystroke), so the walk must prove THAT path executable as
  #    written too — a recommendation no lock exercises is prose. The tree is asserted to carry NO
  #    installed copy, so its green can only come from the tracked hooks/pre-push being live; arm 2
  #    (the same tree with neither install) remains the load-bearing negative for both arms.
  echo "--- arm 3: same walk, tracked-hooks install (core.hooksPath -> the tracked hooks/ dir) ---"
  _t="$WORK/tracked-hooks"
  build_legacy "$_t"
  adopt "$_t" "$EXPORT" tracked
  if [ -e "$_t/.git/hooks/pre-push" ]; then
    echo "FAIL: the tracked-hooks fixture has an installed copy — its green would not prove the mode"
    _wfail=1
  elif sh conformance/inception-done.sh --surface "$_t" >"$WORK/tracked.out" 2>&1; then
    if grep -q 'tracked-hooks mode' "$WORK/tracked.out"; then
      echo "PASS: tracked-hooks walk reaches inception-done --surface rc 0, naming the mode (no installed copy)"
    else
      echo "FAIL: tracked-hooks walk passed but the gate did not name the mode (wrong leg passed it?)"
      sed 's/^/    | /' "$WORK/tracked.out"
      _wfail=1
    fi
  else
    echo "FAIL: tracked-hooks walk did NOT reach inception-done --surface rc 0 (see below)"
    sed 's/^/    | /' "$WORK/tracked.out"
    _wfail=1
  fi

  if [ "$_wfail" -eq 0 ]; then
    echo "OK: brownfield-walk — the documented brownfield path is executable end to end, in BOTH documented install modes, and its pre-push leg is load-bearing"
    return 0
  fi
  echo "FAIL: brownfield-walk — the documented brownfield path is not executable as written (see above)"
  return 1
}

case "${1:-}" in
  ""|--selftest) selftest; exit $? ;;
  *) echo "usage: brownfield-walk.sh [--selftest]" >&2; exit 2 ;;
esac
