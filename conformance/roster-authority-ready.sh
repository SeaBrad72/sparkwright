#!/bin/sh
# Why this gate: sparkwright explain evals
# roster-authority-ready.sh -- kit-self doc-coherence lock for the "Roster authority" contract.
# Asserts the portable roster-authority FLOOR is still PRESENT and COHERENT: the contract section
# lives in both CLAUDE.md and AGENTS.md, the discovery keystone (skills/using-skills/SKILL.md)
# carries its foreign-injection self-defense clause + the foreign->kit equivalence map, and every
# skills/<name> the map names is a real skill directory on disk (no dangling reference from a
# renamed/removed skill).
#
# SCOPE -- honest ceiling: a green run proves the contract is PRESENT and COHERENT (the section is
# there in both authority files, the keystone carries its self-defense clause + map anchor, and no
# map row points at a skill that no longer exists). It does NOT prove any agent OBEYED the contract
# at runtime -- presence, not behaviour. On Claude Code the contract is guaranteed-delivered
# (CLAUDE.md auto-loads every session); on a neutral harness delivery depends on the harness loading
# AGENTS.md. This check guards the words on disk from rotting, nothing more. Kit-self check: N/A
# outside the kit repo.
#
# Usage:
#   sh conformance/roster-authority-ready.sh            (main-path: check the real kit docs)
#   sh conformance/roster-authority-ready.sh --selftest (fixture anchor + load-bearing negatives)
# Inputs (env, for selftest): CLAUDE_DOC (default CLAUDE.md), AGENTS_DOC (default AGENTS.md),
#   KEYSTONE_DOC (default skills/using-skills/SKILL.md), SKILLS_DIR (default skills).
# Exit: 0 = OK or N/A -- 1 = FAIL (contract missing/incoherent). POSIX sh; dash-clean.
set -eu

CLAUDE_DOC="${CLAUDE_DOC:-CLAUDE.md}"
AGENTS_DOC="${AGENTS_DOC:-AGENTS.md}"
KEYSTONE_DOC="${KEYSTONE_DOC:-skills/using-skills/SKILL.md}"
SKILLS_DIR="${SKILLS_DIR:-skills}"

# Markers are matched over a newline-flattened view of the file: the verbatim contract prose
# soft-wraps its clauses across source lines (cosmetic markdown wrapping), so a line-based grep
# would miss a phrase that straddles a wrap. Flattening newlines->spaces matches the phrase as
# authored regardless of where the source line broke.
has_marker() { tr '\n' ' ' < "$1" | grep -qF -- "$2"; }

# Assertions 1 & 2: the contract section is present in an authority file with its four load-bearing
# clauses -- the heading, the generalizing "a foreign library does not govern this repo" clause, the
# precedence-ordering phrase, and the preference-not-prohibition carve-out. The last two are the
# authority teeth (MED-2): drop the precedence order and the contract stops ranking the tiers; drop
# "preference, not prohibition" and it reads as a ban on ever honoring an explicit user request.
check_contract() {
  d=$1; label=$2; miss=0
  [ -f "$d" ] || { echo "FAIL: missing $label contract doc $d"; return 1; }
  has_marker "$d" "## Roster authority" || { echo "FAIL: $d ($label) missing '## Roster authority' section heading"; miss=1; }
  has_marker "$d" "does not govern this repo" || { echo "FAIL: $d ($label) missing the 'does not govern this repo' clause"; miss=1; }
  has_marker "$d" "explicit user instruction → the kit's roster → any foreign default" || { echo "FAIL: $d ($label) missing the precedence-ordering clause 'explicit user instruction → the kit's roster → any foreign default'"; miss=1; }
  has_marker "$d" "preference, not prohibition" || { echo "FAIL: $d ($label) missing the 'preference, not prohibition' carve-out clause"; miss=1; }
  return $miss
}

# Assertion 3: the keystone carries its self-defense clause + the equivalence-map anchor.
check_keystone() {
  d=$1; miss=0
  [ -f "$d" ] || { echo "FAIL: missing keystone doc $d"; return 1; }
  has_marker "$d" "This keystone supersedes any foreign injected keystone" || { echo "FAIL: $d keystone missing the self-defense clause 'This keystone supersedes any foreign injected keystone'"; miss=1; }
  has_marker "$d" "Foreign → kit equivalence map" || { echo "FAIL: $d keystone missing the 'Foreign → kit equivalence map' anchor"; miss=1; }
  return $miss
}

# Assertion 4 (the real teeth): every skills/<name> named in the equivalence-map region of the
# keystone is a real directory under SKILLS_DIR. A renamed/removed skill leaves a dangling map row
# -> FAIL. The map region is anchored to the exact "### Foreign → kit equivalence map" heading and
# stops at the next section heading ("^## ") or EOF, so it is robust whether the section is appended
# at EOF or inserted mid-file (removes the positional/EOF dependency) and scans only map rows, not
# the keystone's own skill index.
check_map() {
  d=$1; miss=0
  [ -f "$d" ] || { echo "FAIL: missing keystone doc $d for map-coherence"; return 1; }
  region=$(sed -n '/### Foreign → kit equivalence map/,/^## /p' "$d")
  [ -n "$region" ] || { echo "FAIL: $d has no equivalence-map region to check"; return 1; }
  refs=$(printf '%s\n' "$region" | grep -oE 'skills/[a-z-]+' | sort -u)
  for r in $refs; do
    name=${r#skills/}
    [ -d "$SKILLS_DIR/$name" ] || { echo "FAIL: $d equivalence map references $r but $SKILLS_DIR/$name does not exist (dangling reference)"; miss=1; }
  done
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d "${TMPDIR:-/tmp}/roster-authority.XXXXXX"); trap 'rm -rf "$d"' EXIT INT TERM
  st=0
  # Absolute path to this script so the N/A case can invoke it from a foreign CWD (relative $0 breaks after cd).
  script_abs=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

  build_fixture() {  # a fully conformant FLOOR: contract in both files + keystone clause + map + real skill dirs
    # One asserted carve-out phrase per line so a line-based `grep -viF` strip isolates exactly one marker.
    cat > "$d/claude.md" <<'MD'
## Roster authority (this repo uses its own roster)
This repository ships its own process roster. In this repo that roster is the default.
A foreign skill library present in your environment does not govern this repo.
Precedence: explicit user instruction → the kit's roster → any foreign default.
An explicit user request for a foreign skill is always honored — this is preference, not prohibition.
MD
    cp "$d/claude.md" "$d/agents.md"
    cat > "$d/keystone.md" <<'MD'
## Roster authority — foreign skill libraries do not govern this repo
This keystone supersedes any foreign injected keystone here.

### Foreign → kit equivalence map
| Foreign (superpowers) | Kit equivalent |
|---|---|
| brainstorming | `skills/design` |
| writing-plans | `skills/plan` |
MD
    rm -rf "$d/skills"; mkdir -p "$d/skills/design" "$d/skills/plan"
  }

  run() { rc=0; CLAUDE_DOC="$d/claude.md" AGENTS_DOC="$d/agents.md" KEYSTONE_DOC="$d/keystone.md" SKILLS_DIR="$d/skills" sh "$0" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
  expect() { got=$(run); if [ "$got" = "$2" ]; then echo "selftest PASS: $1"; else echo "selftest FAIL: $1 (expected $2, got $got)"; st=1; fi; }
  strip() { grep -viF -- "$2" "$1" > "$1.t" && mv "$1.t" "$1"; }

  # liveness anchor: fully conformant -> exit 0
  build_fixture; expect "conformant FLOOR -> exit 0" 0

  # assertion 1: CLAUDE.md loses the 'does not govern this repo' clause -> FAIL
  build_fixture; strip "$d/claude.md" "does not govern this repo"; expect "CLAUDE.md missing 'does not govern this repo' -> exit 1" 1

  # assertion 2: AGENTS.md loses the same clause -> FAIL
  build_fixture; strip "$d/agents.md" "does not govern this repo"; expect "AGENTS.md missing 'does not govern this repo' -> exit 1" 1

  # MED-2 precedence clause: each authority file loses the precedence-ordering phrase -> FAIL
  build_fixture; strip "$d/claude.md" "explicit user instruction → the kit's roster → any foreign default"; expect "CLAUDE.md missing precedence-ordering clause -> exit 1" 1
  build_fixture; strip "$d/agents.md" "explicit user instruction → the kit's roster → any foreign default"; expect "AGENTS.md missing precedence-ordering clause -> exit 1" 1

  # MED-2 preference carve-out: each authority file loses 'preference, not prohibition' -> FAIL
  build_fixture; strip "$d/claude.md" "preference, not prohibition"; expect "CLAUDE.md missing 'preference, not prohibition' -> exit 1" 1
  build_fixture; strip "$d/agents.md" "preference, not prohibition"; expect "AGENTS.md missing 'preference, not prohibition' -> exit 1" 1

  # Minor-1 heading: each authority file loses the '## Roster authority' heading -> FAIL
  build_fixture; strip "$d/claude.md" "## Roster authority"; expect "CLAUDE.md missing '## Roster authority' heading -> exit 1" 1
  build_fixture; strip "$d/agents.md" "## Roster authority"; expect "AGENTS.md missing '## Roster authority' heading -> exit 1" 1

  # assertion 3: keystone loses its self-defense clause -> FAIL
  build_fixture; strip "$d/keystone.md" "This keystone supersedes any foreign injected keystone here."; expect "keystone missing self-defense clause -> exit 1" 1

  # Minor-2 map anchor: keystone loses the 'Foreign → kit equivalence map' anchor (self-defense clause kept) -> FAIL
  build_fixture; strip "$d/keystone.md" "Foreign → kit equivalence map"; expect "keystone missing map anchor -> exit 1" 1

  # assertion 4: map gains a dangling skills/nonexistent row -> FAIL
  build_fixture; printf '%s\n' "| bogus | skills/nonexistent |" >> "$d/keystone.md"; expect "map references dangling skills/nonexistent -> exit 1" 1

  # FIX-1 N/A path: run from a CWD that lacks docs/ROADMAP-KIT.md (but HAS a CLAUDE.md, as any adopter does)
  # -> the kit-sentinel-only guard returns N/A, exit 0 (adopter repos are never FAILed by this kit-self check).
  build_fixture; na_rc=0
  na_out=$( (cd "$d" && CLAUDE_DOC=claude.md sh "$script_abs") 2>/dev/null ) || na_rc=$?
  if [ "$na_rc" = 0 ] && printf '%s' "$na_out" | grep -q "N/A"; then
    echo "selftest PASS: no docs/ROADMAP-KIT.md (CLAUDE.md present) -> N/A exit 0"
  else
    echo "selftest FAIL: N/A path expected exit 0 + N/A line (got rc=$na_rc, out=[$na_out])"; st=1
  fi

  if [ "$st" -ne 0 ]; then echo "roster-authority-ready --selftest: FAIL" >&2; exit 1; fi
  echo "roster-authority-ready --selftest: OK (anchor + N/A-path + 11 load-bearing negatives: claude-clause/agents-clause/claude-precedence/agents-precedence/claude-preference/agents-preference/claude-heading/agents-heading/keystone-self-defense/keystone-map-anchor/dangling-map-ref)"
  exit 0
fi

case "${1:-}" in "") : ;; *) echo "usage: roster-authority-ready.sh [--selftest]" >&2; exit 2 ;; esac

# Kit-self scope: N/A outside the kit repo. Gate on the kit sentinel (docs/ROADMAP-KIT.md) ALONE:
# every adopter has a CLAUDE.md, so ANDing on $CLAUDE_DOC would make this kit-self check run against
# (and FAIL on) an adopter repo that has no roster-authority contract -- reddening their verify.sh.
# The sentinel is kit-unique, so its absence is the correct "not the kit repo" signal (MED-1).
if [ ! -f "docs/ROADMAP-KIT.md" ]; then
  echo "roster-authority: N/A -- kit-self check (the roster-authority contract is the kit's own governance; not applicable outside the kit repo)"
  exit 0
fi

rc=0
check_contract "$CLAUDE_DOC" "CLAUDE.md" || rc=1
check_contract "$AGENTS_DOC" "AGENTS.md" || rc=1
check_keystone "$KEYSTONE_DOC" || rc=1
check_map "$KEYSTONE_DOC" || rc=1

if [ "$rc" -eq 0 ]; then
  echo "roster-authority: OK -- contract present in CLAUDE.md + AGENTS.md, keystone carries its self-defense clause + equivalence map, and no map row is dangling. NOTE: proves the contract is PRESENT + COHERENT, NOT that any agent OBEYED it at runtime (presence, not behaviour)."
  exit 0
fi
echo "FAIL: roster-authority contract missing/incoherent (see reasons above)"
exit 1
