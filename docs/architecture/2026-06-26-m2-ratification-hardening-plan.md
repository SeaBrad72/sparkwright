# M2-Ratification-Hardening (+ Release-Coherence) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Close the release-coherence gap (VERSION↔git-tag, item e) and harden three M2-S5 follow-ons — verdict-enum normalization (b), a shared version-compare helper (d), and a trimmed future-pin clause (a). Item (c) is a deliberate non-action.

**Architecture:** Two new POSIX-sh conformance scripts (`version-helpers.sh` lib, `version-tag-coherent.sh` check) + a small tag-push workflow, plus targeted edits to `conformance/meta-control-fresh.sh`. All control-plane → built+tested in `scratchpad/m2h/`, materialized by a security-reviewed `apply.py`, dry-run on a clone; **Bradley applies** on the real tree (AMBER convention).

**Tech Stack:** POSIX `sh` + `awk`/`sed`/`sort -V` (no jq, no bashisms). Python 3 for `apply.py`. GitHub Actions YAML.

## Global Constraints

- **POSIX sh only** (`#!/bin/sh`, `set -eu`, no bashisms/`local`/arrays); semver compare via `sort -V`. Mirrors existing `conformance/*.sh`.
- **Three-state exit:** `0` PASS/NA · `1` FAIL · `2` UNVERIFIED; under CI (`CI` env) or `--require`, UNVERIFIED→1.
- **Control-plane discipline (ratified AMBER):** the agent NEVER applies control-plane changes to the real tree. It builds in `scratchpad/m2h/`, assembles `scratchpad/m2h/apply.py`, dual-reviews, and dry-runs `apply.py` on a throwaway clone (full `verify --require` green). Bradley applies + finishing + PR + merge + tag. [[merge-tag-authority]]
- **ci-selftest-coverage invariant:** every script that ships a `--selftest` MUST be wired into `ci.yml` (the E4d lesson). Both new scripts ship `--selftest` → both get a ci.yml step.
- **Offline-determinism:** the meta-control gate and (e) must stay offline (`git` only, no network).
- **Honest ceiling (item a):** the future-pin clause is defense-in-depth, NOT a tamper boundary; the marker's control-plane status is the real defense. State this; do not over-claim.
- **Branch:** `feature/m2-ratification-hardening` (already created). Spec: `docs/architecture/2026-06-26-m2-ratification-hardening-design.md`.

---

## File map

| Path | Action | Responsibility | Control-plane |
|------|--------|----------------|:---:|
| `conformance/version-helpers.sh` | Create | `ver_norm`/`ver_ge`/`ver_gt` lib + `--selftest` | yes (`conformance/*`) |
| `conformance/version-tag-coherent.sh` | Create | (e) VERSION↔tag coherence check + `--selftest` | yes |
| `.github/workflows/release-coherence.yml` | Create | run (e) on `push: tags: ['v*']` | yes |
| `conformance/meta-control-fresh.sh` | Modify | (a) future-pin clause + (b) verdict enum; source the lib | yes |
| `conformance/verify.sh` | Modify | register `version-tag-coherent` control check | yes |
| `conformance/claims.tsv` | Modify | claim `version-tag-coherent` | yes |
| `conformance/claims-registry.sh` | Modify | add to `REQUIRED_IDS` | yes |
| `conformance/README.md` | Modify | index rows (lib + check) | no |
| `.github/workflows/ci.yml` | Modify | `--selftest` steps for both new scripts | yes |
| `docs/operations/meta-control.md` | Modify | (a) honest-ceiling note | no |
| `scratchpad/m2h/apply.py` | Create | AMBER materializer | no (scratch) |

---

## Task 0: Scratch hygiene

- [ ] **Step 1**
Run:
```bash
git branch --show-current   # expect feature/m2-ratification-hardening
grep -qxF 'scratchpad/' .gitignore || printf 'scratchpad/\n' >> .gitignore
mkdir -p scratchpad/m2h
echo ok
```

---

## Task 1: `version-helpers.sh` (d) — build & TDD in scratch

**Files:** Create `scratchpad/m2h/version-helpers.sh` (→ `conformance/version-helpers.sh`)

**Interfaces — Produces:** `ver_norm V` (strip leading `v`); `ver_ge A B` (exit 0 iff A≥B); `ver_gt A B` (exit 0 iff A>B). Sourced by Tasks 2 & 3.

- [ ] **Step 1: Implement** `scratchpad/m2h/version-helpers.sh`:
```sh
#!/bin/sh
# version-helpers.sh — shared semver comparison (POSIX sh; SOURCE this, or run --selftest).
# Used by meta-control-fresh.sh and version-tag-coherent.sh. Comparison via `sort -V` (version sort,
# so 1.10.0 > 1.9.0). Callers validate X.Y.Z before comparing; these assume normalized-ish input.
ver_norm() { printf '%s' "$1" | sed 's/^v//'; }
# ver_ge A B : true (0) iff A >= B
ver_ge() {
  _a=$(ver_norm "$1"); _b=$(ver_norm "$2")
  [ "$_a" = "$_b" ] && return 0
  [ "$(printf '%s\n%s\n' "$_a" "$_b" | sort -V | tail -1)" = "$_a" ]
}
# ver_gt A B : true (0) iff A > B
ver_gt() {
  _a=$(ver_norm "$1"); _b=$(ver_norm "$2")
  [ "$_a" = "$_b" ] && return 1
  [ "$(printf '%s\n%s\n' "$_a" "$_b" | sort -V | tail -1)" = "$_a" ]
}
if [ "${1:-}" = "--selftest" ]; then
  vf=0
  _ck() { if eval "$1"; then echo "PASS: $2"; else echo "version-helpers --selftest: FAIL ($2)"; vf=1; fi; }
  _ck 'ver_ge 1.0.0 1.0.0' "ge equal"
  _ck 'ver_ge 1.2.0 1.1.9' "ge greater"
  _ck '! ver_ge 1.0.0 1.0.1' "ge lesser=false"
  _ck 'ver_ge v2.0.0 1.9.9' "ge strips v"
  _ck 'ver_gt 1.0.1 1.0.0' "gt greater"
  _ck '! ver_gt 1.0.0 1.0.0' "gt equal=false"
  _ck '! ver_gt 1.0.0 2.0.0' "gt lesser=false"
  _ck 'ver_gt 1.10.0 1.9.0' "gt numeric 10>9 (not lexical)"
  _ck 'ver_ge 1.10.0 1.9.0' "ge numeric 10>9 (not lexical)"
  [ "$vf" = 0 ] && { echo "version-helpers --selftest: OK"; exit 0; } || exit 1
fi
```

- [ ] **Step 2: Run** `sh scratchpad/m2h/version-helpers.sh --selftest` → expect `version-helpers --selftest: OK` (9 PASS, exit 0).
- [ ] **Step 3:** `shellcheck -s sh scratchpad/m2h/version-helpers.sh` (if available) → clean.

---

## Task 2: `version-tag-coherent.sh` (e) — build & TDD in scratch

**Files:** Create `scratchpad/m2h/version-tag-coherent.sh` (→ `conformance/version-tag-coherent.sh`)

**Interfaces — Consumes:** `version-helpers.sh` (sourced from the same dir). **Produces:** `sh conformance/version-tag-coherent.sh [dir] [--require] | --selftest`; exit 0 PASS/NA, 1 FAIL, 2 UNVERIFIED.

- [ ] **Step 1: Implement** `scratchpad/m2h/version-tag-coherent.sh` (note: the source line points at the scratch lib for now; apply.py installs both to `conformance/` where the relative source resolves):
```sh
#!/bin/sh
# version-tag-coherent.sh — release coherence: VERSION must agree with the git tag state.
# (1) VERSION >= highest reachable semver tag; (2) HEAD tagged (semver) => VERSION == that tag.
# Catches a release whose VERSION bump was skipped (e.g. tag v3.49.0 on a VERSION=3.48.18 commit) —
# a gap badge-version (README<->VERSION only) cannot see. Threat model: HUMAN mistake, not agent
# attack (local tags acceptable). Offline (git only). Proves coherence, NOT that the right version was chosen.
# Exit: 0 PASS/NA · 1 FAIL · 2 UNVERIFIED (no git/not a repo) — escalates under CI/--require.
#   sh conformance/version-tag-coherent.sh [project-dir] [--require] | --selftest
set -eu
_here=$(CDPATH='' cd "$(dirname "$0")" && pwd)
. "$_here/version-helpers.sh"
REQUIRE="${REQUIRE:-0}"; [ -n "${CI:-}" ] && REQUIRE=1
DIR=.
for a in "$@"; do
  case "$a" in
    --require) REQUIRE=1 ;;
    --selftest) ;;
    -*) echo "usage: version-tag-coherent.sh [project-dir] [--require] | --selftest" >&2; exit 2 ;;
    *) DIR="$a" ;;
  esac
done
unverified() { printf 'UNVERIFIED: %s\n' "$1" >&2; [ "$REQUIRE" = "1" ] && exit 1; exit 2; }
check() {
  _d="$1"
  [ -f "$_d/VERSION" ] || { echo "version-tag-coherent: N/A — no VERSION file"; return 0; }
  _v=$(ver_norm "$(tr -d '[:space:]' < "$_d/VERSION" 2>/dev/null || true)")
  printf '%s' "$_v" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "version-tag-coherent: N/A — VERSION '$_v' not semver"; return 0; }
  ( cd "$_d" && git rev-parse --git-dir >/dev/null 2>&1 ) || unverified "not a git repo / git unavailable ($_d)"
  _tags=$( cd "$_d" && git tag --merged HEAD 2>/dev/null | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' || true )
  if [ -z "$_tags" ]; then echo "version-tag-coherent: N/A — no reachable semver tags yet"; return 0; fi
  _hi=$(printf '%s\n' "$_tags" | sort -V | tail -1)
  if ver_gt "$_hi" "$_v"; then
    echo "FAIL: VERSION $_v is BEHIND the highest reachable tag v$_hi — a release tag must not exceed VERSION. Bump VERSION."
    return 1
  fi
  _headtags=$( cd "$_d" && git tag --points-at HEAD 2>/dev/null | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' || true )
  for _t in $_headtags; do
    if [ "$_t" != "$_v" ]; then
      echo "FAIL: HEAD is tagged v$_t but VERSION is $_v — a tagged release commit must declare its own version. Bump VERSION to $_t (or move the tag)."
      return 1
    fi
  done
  echo "version-tag-coherent: OK (VERSION $_v; highest reachable tag v$_hi; HEAD tags coherent)"
  return 0
}
if [ "${1:-}" = "--selftest" ]; then
  sf=0; _t=$(mktemp -d)
  _repo() { # <dir> <VERSION> ; inits a repo with one commit
    mkdir -p "$1"; printf '%s\n' "$2" > "$1/VERSION"
    ( cd "$1" && git init -q && git -c user.email=c@k -c user.name=c add -A \
      && git -c user.email=c@k -c user.name=c commit -q -m s ) >/dev/null 2>&1
  }
  _exp() { if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "version-tag-coherent --selftest: FAIL ($1: want rc $2 got $3)"; sf=1; fi; }
  # A. VERSION==HEAD tag → PASS(0)
  d="$_t/a"; _repo "$d" "1.0.0"; ( cd "$d" && git tag v1.0.0 ) >/dev/null 2>&1
  rc=0; ( REQUIRE=0; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "VERSION==HEAD tag" 0 "$rc"
  # B. seam: VERSION ahead, HEAD untagged, older tag reachable → PASS(0)
  d="$_t/b"; _repo "$d" "1.0.0"; ( cd "$d" && git tag v1.0.0 && printf '1.1.0\n' > VERSION && git -c user.email=c@k -c user.name=c commit -aqm bump ) >/dev/null 2>&1
  rc=0; ( REQUIRE=0; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "seam: VERSION ahead, HEAD untagged" 0 "$rc"
  # C. today's bug: HEAD tagged AHEAD of VERSION → FAIL(1)
  d="$_t/c"; _repo "$d" "3.48.18"; ( cd "$d" && git tag v3.49.0 ) >/dev/null 2>&1
  rc=0; ( REQUIRE=0; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "tag ahead of VERSION (the v3.49.0 bug)" 1 "$rc"
  # D. stale tag at a bumped HEAD: HEAD tagged BEHIND VERSION → FAIL(1)
  d="$_t/d"; _repo "$d" "2.0.0"; ( cd "$d" && git tag v1.0.0 ) >/dev/null 2>&1
  rc=0; ( REQUIRE=0; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "HEAD tagged behind VERSION" 1 "$rc"
  # E. no tags → N/A(0)
  d="$_t/e"; _repo "$d" "1.0.0"
  rc=0; ( REQUIRE=0; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "no tags = N/A" 0 "$rc"
  # F. not a git repo → UNVERIFIED(2), escalates to 1 under --require
  d="$_t/f"; mkdir -p "$d"; printf '1.0.0\n' > "$d/VERSION"
  rc=0; ( REQUIRE=0; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "no git = UNVERIFIED(2)" 2 "$rc"
  rc=0; ( REQUIRE=1; check "$d" ) >/dev/null 2>&1 || rc=$?; _exp "no git + --require = FAIL(1)" 1 "$rc"
  rm -rf "$_t"
  [ "$sf" = 0 ] && { echo "version-tag-coherent --selftest: OK"; exit 0; } || exit 1
fi
check "$DIR"
```

- [ ] **Step 2: Run** `sh scratchpad/m2h/version-tag-coherent.sh --selftest` → expect `version-tag-coherent --selftest: OK` (7 PASS incl. the v3.49.0-bug fixture C, exit 0).
- [ ] **Step 3:** shellcheck clean.

---

## Task 3: `meta-control-fresh.sh` (a) + (b) — modify scratch copy & TDD

**Files:** copy `conformance/meta-control-fresh.sh` → `scratchpad/m2h/meta-control-fresh.sh`, edit there.

**Interfaces — Consumes:** `version-helpers.sh` (sourced).

- [ ] **Step 1: Copy** the current file: `cp conformance/meta-control-fresh.sh scratchpad/m2h/meta-control-fresh.sh`.

- [ ] **Step 2: Source the lib.** After line 27 (`_here=$(...)`), before `cd "$_here/.."`, add:
```sh
. "$_here/version-helpers.sh"
```
Then DELETE the now-duplicated local `ver_norm()` definition (the `ver_norm() { ...; }` line) — it comes from the lib.

- [ ] **Step 3: (d) dedup the inline compare in `count_newer`.** Replace the `if [ "$(printf '%s\n%s\n' "$_m" "$_t" | sort -V | tail -1)" = "$_t" ]; then` line with:
```sh
    if ver_gt "$_t" "$_m"; then
```

- [ ] **Step 4: (a) trim + clause + (d) in `validate_state`.** Replace the entire `if [ -f "$ROOT/VERSION" ]; then ... fi` future-pin block (current lines 112-120) with:
```sh
  # (a, trimmed) Two checks, both DEFENSE-IN-DEPTH only — the real guarantee is the marker's
  # control-plane status (the guard denies agent writes; see docs/operations/meta-control.md).
  #  i. marker must not be AHEAD of VERSION (rejects a fabricated 99.0.0 future-pin).
  # ii. marker must correspond to a real release point: an existing semver tag OR exactly == VERSION
  #     (the unreleased ship-seam). Rejects a plausible-but-fabricated in-between marker that (i) alone
  #     would accept. Enforced only when an anchor exists (VERSION present); lenient otherwise so an
  #     adopter who versions differently is not over-constrained.
  if [ -f "$ROOT/VERSION" ]; then
    _vraw=$(ver_norm "$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || true)")
    if printf '%s' "$_vraw" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      if ver_gt "$MVER" "$_vraw"; then
        echo "FAIL: marker version $MVER is ahead of VERSION $_vraw — a future-pinned marker would pin the gate FRESH forever. Set the marker to a real run's version (<= VERSION)."
        return 1
      fi
      _is_tag=0
      for _t in $(tags_list); do [ "$_t" = "$MVER" ] && { _is_tag=1; break; }; done
      if [ "$_is_tag" = "0" ] && [ "$MVER" != "$_vraw" ]; then
        echo "FAIL: marker $MVER is neither a released tag nor == VERSION $_vraw — the marker must correspond to a real release point or the current ship-seam version."
        return 1
      fi
    fi
  fi
```

- [ ] **Step 5: (b) verdict enum — add a validator helper.** Immediately before `validate_state()` add:
```sh
# (b) verdict enum: uppercase-normalize + restrict to the allowed set. Prevents a lowercase
# `deferred` from evading the serial-DEFERRED cap and rejects garbage verdicts.
norm_verdict() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
valid_verdict() { case "$1" in GO|NO-GO|DEFERRED) return 0 ;; *) return 1 ;; esac }
```

- [ ] **Step 6: (b) apply in `validate_state`.** After `_lverdict=$(log_field 6)` and `_lver=$(ver_norm "$_lver")`, normalize + validate both verdicts. Replace the desync `if [ "$MVER" != "$_lver" ] || [ "$MVERDICT" != "$_lverdict" ]; then` block's lead-in by inserting, just before it:
```sh
  MVERDICT=$(norm_verdict "$MVERDICT"); _lverdict=$(norm_verdict "$_lverdict")
  if ! valid_verdict "$MVERDICT"; then echo "FAIL: marker verdict '$MVERDICT' is not one of GO|NO-GO|DEFERRED."; return 1; fi
  if ! valid_verdict "$_lverdict"; then echo "FAIL: log verdict '$_lverdict' is not one of GO|NO-GO|DEFERRED."; return 1; fi
```
(The existing desync comparison then compares the normalized values.)

- [ ] **Step 7: (b) apply in `trailing_deferred`.** In the awk body, change `v=$6; gsub(/^[ \t]+|[ \t]+$/,"",v); rows[++n]=v` to uppercase: `v=$6; gsub(/^[ \t]+|[ \t]+$/,"",v); rows[++n]=toupper(v)`.

- [ ] **Step 8: Add regression fixtures** to the selftest (before the `rm -rf "$_t"` line). Append:
```sh
  # M. (a) marker is a non-tag value < VERSION and != VERSION → FAIL (the new clause; bare <=VERSION would pass)
  _d="$_t/m"; _mkfix "$_d" "1.0.5 GO" "1.0.5" "GO" "2.0.0"; rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0 1.0.1" run ) >/dev/null 2>&1 || rc=$?; _expect "(a) non-tak marker !=VERSION = FAIL" 1 "$rc"
  # N. (b) two consecutive lowercase `deferred` → OVERDUE (serial cap no longer evadable by case)
  _d="$_t/n"; mkdir -p "$_d/docs/governance"; : > "$_d/docs/ROADMAP-KIT.md"; printf '99.99.99\n' > "$_d/VERSION"
  printf '1.0.0 deferred\n' > "$_d/docs/governance/.meta-control-last"
  { printf '| Date | Version | Trigger | Profile | Verdict | Artifact | Ledger |\n'; printf '|---|---|---|---|---|---|---|\n'; printf '| 2026-01-01 | 0.9.0 | t | l | deferred | a | s |\n'; printf '| 2026-01-02 | 1.0.0 | t | l | deferred | a | s |\n'; } > "$_d/docs/governance/meta-control-log.md"
  rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0" run ) >/dev/null 2>&1 || rc=$?; _expect "(b) lowercase deferred x2 = OVERDUE" 1 "$rc"
  # O. (b) garbage verdict → FAIL
  _d="$_t/o"; _mkfix "$_d" "1.0.0 MAYBE" "1.0.0" "MAYBE"; rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0" run ) >/dev/null 2>&1 || rc=$?; _expect "(b) garbage verdict = FAIL" 1 "$rc"
```
(Fix the typo in your copy: the label should read "(a) non-tag marker".)

- [ ] **Step 9: Run** `sh scratchpad/m2h/meta-control-fresh.sh --selftest`. The real-tree assertions read the LIVE `conformance/` path — run it with `META_CONTROL_ROOT` pointing at a clone OR accept that the "wired into drift-watch/doctor" checks read the real tree (unchanged, still pass). Expect all fixtures A–O PASS, `OK`, exit 0. If the real-tree source-path check fails because the lib isn't installed yet, that is expected pre-apply — validate fully on the clone in Task 6 instead, and here assert only that fixtures A–O pass (run the fixture block).
- [ ] **Step 10:** shellcheck clean.

---

## Task 4: `release-coherence.yml` workflow (e) + ops-doc note (a)

**Files:** Create `scratchpad/m2h/release-coherence.yml` (→ `.github/workflows/release-coherence.yml`); note the ops-doc edit for apply.py.

- [ ] **Step 1: Author the workflow** (robust tag-push catch; SHA-pinned per `action-pinning`):
```yaml
name: release-coherence
# (e) On every v* tag push, assert VERSION agrees with the tag (catches a skipped VERSION bump at
# release time — the v3.49.0 incident). Per-PR/drift-watch coverage is via conformance/verify.sh.
on:
  push:
    tags: ['v*']
  workflow_dispatch:
permissions:
  contents: read
jobs:
  version-tag-coherent:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10  # v6.0.3
        with:
          fetch-depth: 0
      - name: VERSION must agree with the pushed tag
        run: sh conformance/version-tag-coherent.sh --require
```

- [ ] **Step 2: Ops-doc note (a)** — record the exact text apply.py will insert into `docs/operations/meta-control.md` (a non-control-plane doc; apply.py edits it for atomicity). Add, in the section describing the marker/freshness gate, a sentence:
> The freshness gate also rejects a marker that is future-pinned or that corresponds to no real release point (a tag or the current `VERSION`). This is **defense-in-depth, not a tamper boundary** — the actual guarantee that an agent cannot move the marker is its control-plane status (the guard denies writes); an offline file-based gate cannot resist an attacker who can already write the marker.

---

## Task 5: AMBER materializer `scratchpad/m2h/apply.py`

**Files:** Create `scratchpad/m2h/apply.py`. Idempotent + fail-closed (abort with `sys.exit(1)` if any anchor is missing; no partial apply). Pure Python 3. Operates relative to CWD.

- [ ] **Step 1: Write `apply.py`** with these operations:
1. **Install** `scratchpad/m2h/version-helpers.sh` → `conformance/version-helpers.sh` (0755); `scratchpad/m2h/version-tag-coherent.sh` → `conformance/version-tag-coherent.sh` (0755).
2. **Overwrite** `conformance/meta-control-fresh.sh` with `scratchpad/m2h/meta-control-fresh.sh` (the edited copy). Fail-closed: assert the scratch copy contains `. "$_here/version-helpers.sh"` AND `valid_verdict` (proof it's the edited version) before overwriting.
3. **Install** `scratchpad/m2h/release-coherence.yml` → `.github/workflows/release-coherence.yml`.
4. **verify.sh** — insert `check control version-tag-coherent sh conformance/version-tag-coherent.sh` adjacent to the other `check control` lines (idempotent: skip if `version-tag-coherent` already present; fail-closed if the anchor block isn't found).
5. **claims.tsv** — append TAB row (idempotent): `version-tag-coherent\tVERSION agrees with the git tag state (no skipped release bump)\tsh conformance/version-tag-coherent.sh --selftest`.
6. **claims-registry.sh** — append ` version-tag-coherent` to `REQUIRED_IDS` (idempotent).
7. **ci.yml** — add two steps (match neighbor format/indent), idempotent:
   - `- name: conformance — version helpers (selftest)\n  run: sh conformance/version-helpers.sh --selftest`
   - `- name: conformance — version↔tag coherence (selftest)\n  run: sh conformance/version-tag-coherent.sh --selftest`
8. **conformance/README.md** — add index rows for `version-helpers.sh` (lib) and `version-tag-coherent.sh` (check; gate: per-PR + drift-watch + tag-push), idempotent.
9. **docs/operations/meta-control.md** — insert the Task 4 Step 2 sentence (idempotent: skip if already present; fail-closed if the target section anchor absent).
10. Print a summary; `sys.exit(1)` if any required anchor was missing.

- [ ] **Step 2:** `python3 -m py_compile scratchpad/m2h/apply.py && echo compiles`.

---

## Task 6: Dry-run on a throwaway clone (agent verifies; does NOT touch real tree)

- [ ] **Step 1: Clone + carry scratch:**
```bash
CLONE=$(mktemp -d)/m2h; git clone -q . "$CLONE" && git -C "$CLONE" checkout -q feature/m2-ratification-hardening
cp -R scratchpad "$CLONE"/scratchpad; echo "$CLONE" > .superpowers/sdd/clone-path.txt; echo "$CLONE"
```
- [ ] **Step 2: Apply on the clone:** `( cd "$CLONE" && python3 scratchpad/m2h/apply.py )` → exit 0.
- [ ] **Step 3: Targeted (true exits):**
```bash
( cd "$CLONE" && sh conformance/version-helpers.sh --selftest \
  && sh conformance/version-tag-coherent.sh --selftest \
  && sh conformance/meta-control-fresh.sh --selftest \
  && sh conformance/ci-selftest-coverage.sh )
```
Expect all exit 0 (ci-selftest-coverage confirms both new scripts are wired).
- [ ] **Step 4: Full aggregate:** `( cd "$CLONE" && sh conformance/verify.sh --require && sh conformance/claims-registry.sh )` → 0 failed; `version-tag-coherent PASS` present; claims coverage intact (count +1).
- [ ] **Step 5: Record** clone path + results in `.superpowers/sdd/m2h-report.md`. Do NOT modify the real tree.

---

## Task 7: Dual review (builder ≠ reviewer)

- [ ] **Step 1:** Generate the materialized diff from the clone (`git -C "$CLONE" add -A && git -C "$CLONE" diff --cached > .superpowers/sdd/m2h-materialized.diff`).
- [ ] **Step 2:** Dispatch `reviewer` (correctness, POSIX, kit conventions, §14 gates, design↔impl fidelity; confirm (a)'s trim is sound and existing fixtures A–L still pass) and `security-reviewer` (the (a) honest-ceiling claim is accurate and not over-stated; (b) enum can't be evaded; (e) catches the v3.49.0 shape and is offline; no new control-plane hole) on the diff + clone.
- [ ] **Step 3:** Address Critical/Important via fix subagents; re-review until both APPROVE. Record minors for this final review.

---

## Task 8: Handoff to Bradley

- [ ] **Step 1:** Present the dry-run evidence + both verdicts + the apply/PR/merge/tag commands. This slice adds NO VERSION bump of its own unless you choose to release it as its own version — recommend bundling under the next version bump or a patch (e.g. v3.49.1); the new `version-tag-coherent` gate will then enforce its own coherence.
- [ ] **Step 2:** Bradley runs `python3 scratchpad/m2h/apply.py` + finishing (VERSION/README/CHANGELOG/ROADMAP — now guarded by (e)) + `verify --require` + commit + PR + admin-merge + tag. Agent does not apply control-plane to the real tree.

---

## Self-review (plan vs spec)

- **Spec coverage:** (e) → Tasks 2,4,5,6 (check + tag-push workflow + verify.sh + claims). (b) → Task 3 Steps 5-7 + fixtures N,O. (d) → Task 1 + Task 3 Steps 2-4 (consumed in a & e). (a) → Task 3 Step 4 + fixture M + ops note (Task 4 Step 2). (c) → deliberately absent (design records the non-action). No gaps.
- **Placeholder scan:** complete code for both new scripts + the workflow; meta-control edits are exact string replacements; apply.py ops enumerated with idempotency/fail-closed. No TODO/TBD.
- **Type/name consistency:** `ver_norm`/`ver_ge`/`ver_gt` defined in Task 1, consumed in Tasks 2-3; `norm_verdict`/`valid_verdict` defined+used in Task 3; claim id `version-tag-coherent` consistent across Tasks 5 ops 4-8; exit codes 0/1/2 uniform.
