#!/bin/sh
# inception-bootstrap-documented.sh — doc-coherence marker lock for CP-7 Slice 2's Inception
# bootstrap sequencing (design 2026-07-19; K1/K2/K3/K9/K15). Asserts that the load-bearing
# INCEPTION-EXCEPTION notes (the dev-clone / spec-first loop rules explicitly do NOT govern
# Phase-0 Inception) AND the incept-first bootstrap ORDER (do not commit before `incept`; the
# first feature branches from the committed incepted baseline, never from a restored origin/main)
# are DOCUMENTED — verbatim — across skills/design/SKILL.md, skills/build/SKILL.md, the canonical
# sequence in docs/adoption/inception-bootstrap.md, and the §3 pointer to it in DEVELOPMENT-PROCESS.md.
# This locks those notes + that sequence + the gate's pointer against silent removal / drift.
#
# HONEST CEILING: this proves the docs STATE the exception + the sequence, NOT that any run
# FOLLOWS them — Phase-0 Inception is a one-time human-run bootstrap with no repo/CI to gate
# against, so "was the order obeyed?" is un-gateable. Accuracy/obedience stay the owner's judgment.
#
#   sh conformance/inception-bootstrap-documented.sh [root]   (default: . — the repo root)
#   sh conformance/inception-bootstrap-documented.sh --selftest
# Exit: 0 = all markers present (or N/A: an incepted adopter tree) · 1 = a marker missing · 2 = usage.
# POSIX sh; dash-clean. Modeled on conformance/promotion-contract-documented.sh (verbatim single-line
# substring markers ARE the lock; a per-marker selftest negative drops ONLY its line and FAILs).
# What it changes: read-only — greps three committed docs for verbatim marker phrases; mutates nothing.
# Guardrails: read-only; no network, no writes (selftest uses a runtime mktemp fixture, never a
#   committed fixture dir); additive doc-drift lock — never weakens a gate.
set -eu

check_tree() {
  root="$1"

  # KIT-ONLY scope guard: an incepted adopter tree renames CLAUDE.md -> ENGINEERING-PRINCIPLES.md
  # (incept.sh) and does NOT carry the kit's own design/build skills or DEVELOPMENT-PROCESS.md.
  # This latch governs the KIT's OWN bootstrap docs, so an incepted tree is N/A. The kit repo has
  # CLAUDE.md (not ENGINEERING-PRINCIPLES.md), so the check RUNS in the kit repo and in CI.
  # (Same invariant as governing-docs-current.sh:129.)
  if [ -f "$root/ENGINEERING-PRINCIPLES.md" ]; then
    echo "inception-bootstrap-documented: N/A — incepted tree (this latch governs the KIT's own bootstrap docs)"
    return 0
  fi

  fail=0
  # require <label> <file> <regex> — verbatim (case-insensitive) presence of the marker line in
  # <root>/<file>. Markers span THREE files, so each require names its own file (unlike
  # promotion-contract-documented, which scans one doc).
  require() {
    _lab="$1"; _file="$2"; _re="$3"; _path="$root/$_file"
    if [ ! -f "$_path" ]; then
      echo "FAIL: marker $_lab — file missing ($_file)"; fail=1; return 0
    fi
    if grep -qiE "$_re" "$_path"; then
      echo "PASS: marker $_lab"
    else
      echo "FAIL: marker $_lab missing (/$_re/ in $_file)"; fail=1
    fi
  }

  # --- skills/design/SKILL.md: the spec-first loop rule does NOT govern Phase-0 Inception ---------
  require 'design-exception-heading' skills/design/SKILL.md 'Inception exception \(Phase 0 is not a loop feature\)'
  require 'design-not-govern-phase0' skills/design/SKILL.md 'govern Phase-0 Inception'
  require 'design-own-gate'          skills/design/SKILL.md 'Inception has its own design gate \(the charter \+ ADR-000'
  require 'design-no-precommit'      skills/design/SKILL.md 'Do not commit a spec before'

  # --- skills/build/SKILL.md: the dev-clone rule does NOT govern Inception (incept mutates in place) ---
  require 'build-exception' skills/build/SKILL.md 'Inception exception'
  require 'build-not-govern' skills/build/SKILL.md 'not govern Inception'
  require 'build-in-place'   skills/build/SKILL.md 'transforms CI/governing files'

  # --- docs/adoption/inception-bootstrap.md: the incept-first bootstrap ORDER (K1/K9/K15) ---------
  # The full sequence lives in the adoption doc (right-weight: DEVELOPMENT-PROCESS §3 is the always-
  # context-loaded gate and stays lean; the operational how-to sits alongside the other adoption docs).
  require 'seq-incepted-baseline'    docs/adoption/inception-bootstrap.md 'commit the incepted baseline'
  require 'seq-first-feature-branch' docs/adoption/inception-bootstrap.md 'first feature branches from the committed incepted baseline'
  require 'seq-never-restored'       docs/adoption/inception-bootstrap.md 'never from a restored'
  require 'seq-k1k9-noprecommit'     docs/adoption/inception-bootstrap.md 'do not commit before'
  require 'seq-no-repo-yet'          docs/adoption/inception-bootstrap.md 'There is no repo yet'
  # --- DEVELOPMENT-PROCESS.md §3: the gate must POINT to the full sequence (the pointer is load-bearing) ---
  require 'seq-pointer'              DEVELOPMENT-PROCESS.md 'docs/adoption/inception-bootstrap.md'

  if [ "$fail" -ne 0 ]; then echo "inception-bootstrap-documented: FAIL ($root)"; return 1; fi
  echo "inception-bootstrap-documented: OK — inception exception + incept-first sequence documented across design/build/process ($root)"
  return 0
}

# mktemp fixtures; assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard convention).
selftest() {
  st=0
  base=$(mktemp -d)
  good="$base/good"
  mkdir -p "$good/skills/design" "$good/skills/build" "$good/docs/adoption"

  # A complete, correct fixture: every marker on its OWN line in the right file. (No
  # ENGINEERING-PRINCIPLES.md — else the N/A guard would short-circuit and mask the negatives.)
  cat > "$good/skills/design/SKILL.md" <<'EOF'
### Inception exception (Phase 0 is not a loop feature)
The spec-first loop rule does not govern Phase-0 Inception.
Inception has its own design gate (the charter + ADR-000, fit/maturity).
Do not commit a spec before incept has created the repo.
EOF
  cat > "$good/skills/build/SKILL.md" <<'EOF'
Inception exception: the dev-clone rule governs control-plane changes in the loop.
It does not govern Inception.
incept transforms CI/governing files in place because it IS the bootstrap.
EOF
  cat > "$good/docs/adoption/inception-bootstrap.md" <<'EOF'
Run incept, then commit the incepted baseline (the first commit).
The first feature branches from the committed incepted baseline.
It is never from a restored origin/main that would drop the inception evidence.
K1/K9 — do not commit before incept.
There is no repo yet: incept is what git-inits it.
EOF
  # Two lines on purpose: the seq-pointer negative drops the pointer line, and `grep -v` must still
  # emit >=1 line (a single-line file would make grep -v exit 1 and abort the selftest under set -e).
  cat > "$good/DEVELOPMENT-PROCESS.md" <<'EOF'
## 3. Project Inception (Phase 0) — the conceptual gate.
Bootstrap order (incept-first): full sequence in docs/adoption/inception-bootstrap.md.
EOF

  # 1. Positive anchor: all markers present -> exit 0.
  if check_tree "$good" >/dev/null 2>&1; then
    echo "selftest PASS: complete fixture -> OK"
  else
    echo "selftest FAIL: complete fixture should pass"; st=1
  fi

  # 2. Per-marker negatives — the LOAD-BEARING teeth. For EACH marker, drop ONLY its line and assert
  #    the check exits 1 AND names the missing marker label. A dead always-pass mechanism fails here.
  #    spec = 'label|dropkey|relpath' where dropkey is a fixed substring unique to that marker's line.
  for spec in \
    'design-exception-heading|not a loop feature|skills/design/SKILL.md' \
    'design-not-govern-phase0|govern Phase-0 Inception|skills/design/SKILL.md' \
    'design-own-gate|its own design gate|skills/design/SKILL.md' \
    'design-no-precommit|Do not commit a spec before|skills/design/SKILL.md' \
    'build-exception|Inception exception|skills/build/SKILL.md' \
    'build-not-govern|not govern Inception|skills/build/SKILL.md' \
    'build-in-place|transforms CI/governing files|skills/build/SKILL.md' \
    'seq-incepted-baseline|commit the incepted baseline|docs/adoption/inception-bootstrap.md' \
    'seq-first-feature-branch|first feature branches from the committed incepted baseline|docs/adoption/inception-bootstrap.md' \
    'seq-never-restored|never from a restored|docs/adoption/inception-bootstrap.md' \
    'seq-k1k9-noprecommit|do not commit before|docs/adoption/inception-bootstrap.md' \
    'seq-no-repo-yet|There is no repo yet|docs/adoption/inception-bootstrap.md' \
    'seq-pointer|docs/adoption/inception-bootstrap.md|DEVELOPMENT-PROCESS.md'
  do
    lab=${spec%%|*}; rest=${spec#*|}; key=${rest%%|*}; rel=${rest#*|}
    tdir="$base/drop-$lab"
    cp -R "$good" "$tdir"
    grep -v "$key" "$good/$rel" > "$tdir/$rel"
    if out=$(check_tree "$tdir" 2>&1); then
      echo "selftest FAIL: dropping $lab should FAIL (non-vacuity broken!)"; st=1
    elif printf '%s\n' "$out" | grep -q "$lab"; then
      echo "selftest PASS: dropped $lab -> FAIL naming it"
    else
      echo "selftest FAIL: dropped $lab -> FAILed but did not name the marker"; st=1
    fi
  done

  if [ "$st" -ne 0 ]; then echo "inception-bootstrap-documented --selftest: FAIL" >&2; return 1; fi
  echo "inception-bootstrap-documented --selftest: OK (positive anchor + all 13 per-marker negatives behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  -*) echo "usage: inception-bootstrap-documented.sh [root] | --selftest" >&2; exit 2 ;;
  *) check_tree "${1:-.}"; exit $? ;;
esac
