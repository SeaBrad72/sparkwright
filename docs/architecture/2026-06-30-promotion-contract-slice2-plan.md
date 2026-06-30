# Promotion-Contract Slice 2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the advisory change-class classifier + promotion-readiness surfacing (`conformance/promotion-readiness.sh`) and its regression-lock, registered as the `promotion-readiness` claim — no enforcement (that is Slice 3).

**Architecture:** A POSIX-sh producer in `conformance/` (auto-guard-immutable) that sources `.claude/hooks/guard-core.sh` to reuse `is_control_plane_path`, classifies a change-set (control-plane > sensitive > ordinary, fail-safe *up*), and emits a 6-field surfacing (proven-vs-attested reused from `verify.sh`). A sibling lock proves the classifier is derived + fail-safe + mislabel-can't-downgrade. Delivered via one clone-proven AMBER `apply.py`.

**Tech Stack:** POSIX sh (dash-clean), the kit's conformance/claims registry, Python 3 for `apply.py`.

## Global Constraints

- **POSIX sh, dash-clean** — must pass `conformance/shellcheck.sh`.
- **Advisory only** — the producer exits `0` always; it surfaces, never gates. No enforcement in this slice.
- **Single source of truth** — the producer **sources** `guard-core.sh`; it never re-implements control-plane detection, and never redefines `guard_check_*` (would trip `guard-core-sourced.sh`'s anti-fork check).
- **Fail-safe** — empty/unreadable change-set, or guard core unavailable, classifies **control-plane** (highest), never silently ordinary. Class is derived, never self-asserted.
- **No uncommented `--selftest` in the producer** — the lock owns `--selftest`; an uncommented `--selftest` token in the producer would make `ci-selftest-coverage` demand it be wired.
- **Control-plane edits via `apply.py` only** (guard denies direct shell/Write to `conformance/`). Author+test in scratchpad, embed into `apply.py`, human applies. Idempotent, all-or-abort, per-file buffered, version-finishing folded in (VERSION 3.80.0→3.81.0 + README badge + CHANGELOG).
- **Governance close separate + human-run** (M2-S5).
- **Version:** 3.80.0 → **3.81.0** (MINOR).

---

## File Structure

| File | Responsibility | Delivery |
|------|----------------|----------|
| `conformance/promotion-readiness.sh` | NEW — classifier + surfacing producer | apply.py (base64) |
| `conformance/promotion-readiness-wired.sh` | NEW — the lock + non-vacuous selftest | apply.py (base64) |
| `conformance/claims.tsv` | +claim `promotion-readiness` | apply.py |
| `conformance/claims-registry.sh` | +id in REQUIRED_IDS | apply.py |
| `.github/workflows/ci.yml` | +1 step (lock `--selftest`) | apply.py |
| `docs/governance/promotion-contract.md` | flip Slice-2 build-status row to shipped | apply.py |
| `CHANGELOG.md` / `VERSION` / `README.md` | 3.81.0 + badge | apply.py |

Build/test in `scratchpad/promo-slice2/` (session scratchpad, not the repo).

---

## Task 1: Author + TDD the producer + lock (scratchpad)

**Files:**
- Create: `<scratch>/promotion-readiness.sh`
- Create: `<scratch>/promotion-readiness-wired.sh`

**Interfaces:**
- Produces: `promotion-readiness.sh [--changed FILE] [--rung RUNG] [--class] [--no-verify]` (exit 0/2); `promotion-readiness-wired.sh [--selftest]` (exit 0/1/2).

- [ ] **Step 1: Write the producer** `promotion-readiness.sh`:

```sh
#!/bin/sh
# promotion-readiness.sh — derive the change-class of a change-set and emit the promotion-readiness
# surfacing that INFORMS a human GO/NO-GO. ADVISORY ONLY: it surfaces, it never gates (exit 0
# always; the proportional GATES are slice 3 of the Proportional Promotion Contract,
# docs/governance/promotion-contract.md). Reuses the guard's is_control_plane_path as the SINGLE
# source of control-plane detection (sourced, never duplicated).
#
#   conformance/promotion-readiness.sh [--changed FILE] [--rung RUNG] [--class] [--no-verify]
# Change-class: control-plane > sensitive > ordinary (highest present wins). FAIL-SAFE: an empty or
# unreadable change-set, or an unavailable guard core, classifies control-plane (never silently
# ordinary). Class is DERIVED, never self-asserted — there is no flag to declare a lower class.
#   --changed FILE  newline-delimited path list (default: git diff --name-only vs the merge-base)
#   --rung RUNG     spike|integration|rc|staging|production (default rc — the meaningful go/no-go)
#   --class         print only the aggregate class and exit (the stable seam slice 3 consumes)
#   --no-verify     skip the proven-vs-attested verify.sh invocation
# (selftest lives on conformance/promotion-readiness-wired.sh — this producer has none of its own.)
# Exit: 0 always (advisory) · 2 = usage. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true

CORE=".claude/hooks/guard-core.sh"
RUNG=rc; CLASS_ONLY=0; NO_VERIFY=0; CHANGED=""; CHANGED_READ_FAIL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --changed) CHANGED=${2:-}; shift 2 ;;
    --rung) RUNG=${2:-}; shift 2 ;;
    --class) CLASS_ONLY=1; shift ;;
    --no-verify) NO_VERIFY=1; shift ;;
    *) echo "usage: promotion-readiness.sh [--changed FILE] [--rung RUNG] [--class] [--no-verify]" >&2; exit 2 ;;
  esac
done
case "$RUNG" in spike|integration|rc|staging|production) ;;
  *) echo "usage: --rung must be spike|integration|rc|staging|production" >&2; exit 2 ;; esac

# Source the guard core for is_control_plane_path (single source of truth). Fail-safe if absent.
GUARD_OK=1
if [ -f "$CORE" ]; then . "$CORE"; else GUARD_OK=0; fi
command -v is_control_plane_path >/dev/null 2>&1 || GUARD_OK=0

# classify_path <path> -> ordinary|sensitive|control-plane
classify_path() {
  _p=$1
  if [ "$GUARD_OK" = 1 ] && is_control_plane_path "$_p"; then echo control-plane; return; fi
  case "$_p" in
    .env.example|*/.env.example|.env.sample|*/.env.sample|.env.template|*/.env.template|.env.dist|*/.env.dist)
      echo ordinary; return ;;
    auth/*|*/auth/*|payments/*|*/payments/*|migrations/*|*/migrations/*|\
    *secret*|*secrets*|*/keys/*|*.key|*.pem|.env|*/.env|.env.*|*/.env.*)
      echo sensitive; return ;;
  esac
  echo ordinary
}

# Resolve the change-set into $CHANGED_LIST (one path per line); FAIL-SAFE on any failure.
if [ -n "$CHANGED" ]; then
  if [ -f "$CHANGED" ]; then CHANGED_LIST=$(cat "$CHANGED"); else CHANGED_LIST=""; CHANGED_READ_FAIL=1; fi
else
  base=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || true)
  if [ -n "$base" ]; then
    CHANGED_LIST=$(git diff --name-only "$base"...HEAD 2>/dev/null || true)
  else
    CHANGED_LIST=$(git diff --name-only HEAD 2>/dev/null || true)
  fi
fi

# Aggregate = highest class present.
agg=ordinary; n=0
OLDIFS=$IFS; IFS='
'
for _p in $CHANGED_LIST; do
  [ -n "$_p" ] || continue
  n=$((n+1))
  c=$(classify_path "$_p")
  case "$c" in
    control-plane) agg=control-plane ;;
    sensitive) [ "$agg" = control-plane ] || agg=sensitive ;;
  esac
done
IFS=$OLDIFS

# FAIL-SAFE: no readable change-set, or a degraded classifier -> highest class.
if [ "$n" = 0 ] || [ "$CHANGED_READ_FAIL" = 1 ] || [ "$GUARD_OK" = 0 ]; then agg=control-plane; fi

if [ "$CLASS_ONLY" = 1 ]; then echo "$agg"; exit 0; fi

# disposition <class> <rung> -> the matrix cell text (mirrors docs/governance/promotion-contract.md)
disposition() {
  case "$1:$2" in
    ordinary:spike) echo "Agent autonomous (L3); cheap gates advisory; no human gate" ;;
    ordinary:integration) echo "Automated gates required; agent self-review; GO lightweight/delegable" ;;
    ordinary:rc) echo "The meaningful go/no-go — human GO vs this surfacing; builder != reviewer; DoD + acceptance-criteria checked" ;;
    ordinary:staging) echo "smoke + acceptance sign-off" ;;
    ordinary:production) echo "human-commanded; progressive rollout; rollback ready" ;;
    sensitive:spike) echo "Human-gated (always)" ;;
    sensitive:integration) echo "High-risk review lane; human GO" ;;
    sensitive:rc) echo "full dual review + human GO" ;;
    sensitive:staging) echo "+ threat/privacy re-check" ;;
    sensitive:production) echo "human-commanded; irreversible-gated" ;;
    control-plane:spike) echo "Human-authored (always)" ;;
    control-plane:integration) echo "AMBER apply + control-plane-ratification" ;;
    control-plane:rc) echo "human ratify + meta-control" ;;
    control-plane:staging|control-plane:production) echo "N/A — control-plane does not deploy to runtime rungs" ;;
    *) echo "(unknown cell)" ;;
  esac
}

# Proven-vs-attested: reuse verify.sh's [control] vs [doc] split (the kit's own honesty stance).
pv="proven-vs-attested: skipped (--no-verify)"
if [ "$NO_VERIFY" = 0 ]; then
  if [ -f conformance/verify.sh ]; then
    pv=$(sh conformance/verify.sh 2>/dev/null | grep -E '^Summary:|UNVERIFIED is NOT a pass' || true)
    [ -n "$pv" ] || pv="proven-vs-attested: UNAVAILABLE (run conformance/verify.sh)"
  else
    pv="proven-vs-attested: UNAVAILABLE (conformance/verify.sh not found)"
  fi
fi

# Acceptance-criteria: BACKLOG.md if trivially present, else attest at the gate (slice 3+).
if [ -f BACKLOG.md ]; then ac="see BACKLOG.md for the story's acceptance criteria"; else ac="attest at gate (tracker-sourced at the RC gate — slice 3+)"; fi

echo "=== Promotion-readiness surfacing ==="
echo "Rung (destination): $RUNG"
echo ""
echo "1. What changed ($n path(s)):"
printf '%s\n' "$CHANGED_LIST" | while IFS= read -r _q; do [ -n "$_q" ] || continue; printf '   [%s] %s\n' "$(classify_path "$_q")" "$_q"; done
echo ""
echo "2. Change-class (aggregate): $agg"
echo ""
echo "3. Blast-radius (class x rung): $(disposition "$agg" "$RUNG")"
echo ""
echo "4. Proven-vs-attested:"
printf '%s\n' "$pv" | sed 's/^/   /'
echo ""
echo "5. DoD + acceptance-criteria:"
echo "   Definition of Done: see CLAUDE.md \"Definition of Done\""
echo "   ACCEPTANCE-CRITERIA: $ac"
echo ""
echo "6. Regression surface:"
echo "   REGRESSION-SURFACE: human attests (not auto-derived — this is the judgment, not a fact)"
echo ""
echo "(Advisory surfacing — informs the human GO/NO-GO. It does not gate; exit 0.)"
exit 0
```

- [ ] **Step 2: Write the lock** `promotion-readiness-wired.sh`:

```sh
#!/bin/sh
# promotion-readiness-wired.sh — regression-lock for the change-class classifier: prove it is
# DERIVED + FAIL-SAFE (defaults UP, never silently ordinary) and that a mislabel cannot downgrade.
# Part of the Proportional Promotion Contract (docs/governance/promotion-contract.md), slice 2.
#   sh conformance/promotion-readiness-wired.sh [--selftest]
# Exit: 0 = ok · 1 = drift · 2 = usage. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true
PR="conformance/promotion-readiness.sh"

cls() { sh "$PR" --changed "$1" --class --no-verify 2>/dev/null; }  # <changed-file> -> class

selftest() {
  st=0; d=$(mktemp -d)
  printf 'conformance/x.sh\n'                                    > "$d/cp.txt"
  printf 'src/auth/login.ts\n'                                   > "$d/sens.txt"
  printf 'src/util/format.ts\n'                                  > "$d/ord.txt"
  printf 'src/util/format.ts\nsrc/auth/login.ts\nconformance/x.sh\n' > "$d/mix.txt"
  : > "$d/empty.txt"
  ck() {  # <want> <changed-file> <label>
    _g=$(cls "$2")
    if [ "$_g" = "$1" ]; then echo "PASS: $3 -> $_g"; else echo "FAIL: $3 want $1 got $_g"; st=1; fi
  }
  ck control-plane "$d/cp.txt"    "control-plane path"
  ck sensitive     "$d/sens.txt"  "sensitive path"
  ck ordinary      "$d/ord.txt"   "ordinary path"
  ck control-plane "$d/mix.txt"   "mixed -> highest wins"
  ck control-plane "$d/empty.txt" "empty set -> fail-safe up"
  ck control-plane "$d/no-such-file-$$.txt" "missing changed-file -> fail-safe up"
  # load-bearing negative: control-plane + sensitive must NOT downgrade to ordinary
  # (a classifier mutated to always-ordinary fails the cp/sens/mix checks above AND these).
  [ "$(cls "$d/cp.txt")" != ordinary ]   || { echo "FAIL: control-plane downgraded to ordinary"; st=1; }
  [ "$(cls "$d/sens.txt")" != ordinary ] || { echo "FAIL: sensitive downgraded to ordinary"; st=1; }
  if [ "$st" = 0 ]; then echo "OK: promotion-readiness-wired selftest"; else echo "FAIL: promotion-readiness-wired selftest"; fi
  return $st
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") [ -f "$PR" ] || { echo "FAIL: missing $PR"; exit 1; }
      echo "OK: promotion-readiness producer present"; exit 0 ;;
  *) echo "usage: promotion-readiness-wired.sh [--selftest]" >&2; exit 2 ;;
esac
```

- [ ] **Step 3: Run the lock selftest — expect all PASS**

Run: `sh <scratch>/promotion-readiness-wired.sh --selftest` (from a checkout root so `$PR` resolves; in scratchpad, copy both files into a temp repo-root-like dir OR set `cd` appropriately — see Task 2 for the in-tree run).
Expected: 6 `PASS:` lines + `OK: promotion-readiness-wired selftest`, exit 0.

- [ ] **Step 4: Shellcheck both files**

Run: `shellcheck <scratch>/promotion-readiness.sh <scratch>/promotion-readiness-wired.sh`
Expected: clean (no error/warning; match house style — explicit `if/then/else`, no `A && B || C`).

- [ ] **Step 5: Mutation-prove non-vacuity (two mutations)**

(a) Mutate `classify_path` to `echo ordinary` unconditionally → the cp/sens/mix checks + the two explicit negatives must FAIL.
(b) Remove the fail-safe line (`if [ "$n" = 0 ] ... agg=control-plane`) → the empty-set and missing-file checks must FAIL.
Expected: each mutation makes `--selftest` exit 1. Revert both.

---

## Task 2: Prove real classification on the kit's own tree

**Files:** none modified — runs the scratchpad producer against real paths.

- [ ] **Step 1: control-plane + ordinary real-runs** (copy both scripts to a throwaway clone so `$PR`/`guard-core.sh` resolve; or run from a clone in Task 3). Build a `--changed` file with `conformance/verify.sh` → expect `--class` = `control-plane`; a file with `README.md` → `ordinary`; a file with `src/auth/x.ts` → `sensitive`.

Run (in a clone root):
```sh
printf 'conformance/verify.sh\n' > /tmp/c.txt; sh conformance/promotion-readiness.sh --changed /tmp/c.txt --class --no-verify   # control-plane
printf 'README.md\n'            > /tmp/o.txt; sh conformance/promotion-readiness.sh --changed /tmp/o.txt --class --no-verify   # ordinary
```
Expected: `control-plane`, then `ordinary`.

- [ ] **Step 2: full surfacing render**

Run: `sh conformance/promotion-readiness.sh --changed /tmp/c.txt --rung rc` (with verify) and `--no-verify`.
Expected: all six sections render; section 3 shows the `control-plane:rc` cell ("human ratify + meta-control"); section 4 shows `verify.sh`'s `Summary:` line with verify, and `skipped (--no-verify)` without; exit 0 both ways.

---

## Task 3: Author the AMBER `apply.py`

**Files:**
- Create: `<scratch>/apply.py`

- [ ] **Step 1: Write `apply.py`** (validate ALL anchors before any write; each edit idempotent; per-file buffer):

1. **Write** `conformance/promotion-readiness.sh` + `conformance/promotion-readiness-wired.sh` from base64 payloads (mode 0755).
2. **`conformance/claims.tsv`** — insert after the `promotion-contract\t` row (or append), idempotent (skip if `promotion-readiness\t` present):
```
promotion-readiness	change-class is derived (not self-asserted) and fail-safe, and the promotion-readiness surfacing is produced (conformance/promotion-readiness.sh)	sh conformance/promotion-readiness-wired.sh --selftest
```
3. **`conformance/claims-registry.sh`** — add `promotion-readiness` to `REQUIRED_IDS` (insert after the token `promotion-contract`). Idempotent.
4. **`.github/workflows/ci.yml`** — insert one step after the `Promotion-contract documented self-test` step (anchor: `        run: sh conformance/promotion-contract-documented.sh --selftest`):
```yaml
      - name: Promotion-readiness classifier self-test (change-class derived + fail-safe)
        run: sh conformance/promotion-readiness-wired.sh --selftest
```
   Idempotent: skip if `promotion-readiness-wired.sh` already in ci.yml.
5. **`docs/governance/promotion-contract.md`** — in the build-status table, replace the Slice-2 row's `planned` cell with `**v3.81.0**` (anchor the row by its `**2. Change-class derivation` prefix; replace only the trailing `| planned |`). Idempotent.
6. **`CHANGELOG.md`** — prepend a `## [3.81.0] — 2026-06-30` entry (anchor: `## [3.80.0]`).
7. **`VERSION`** — `3.80.0` → `3.81.0`.
8. **`README.md`** — badge `` `v3.80.0` `` → `` `v3.81.0` ``.

Print a changed-paths summary + the governance-close reminder.

---

## Task 4: Clone-prove the apply.py

- [ ] **Step 1: Clone, apply** (separate Bash calls to avoid the control-plane guard tripping on compound commands naming `conformance/`):
```sh
T=$(mktemp -d); git clone -q . "$T/c"; cp <scratch>/apply.py "$T/c/apply.py"; cd "$T/c" && python3 apply.py
```
Expected: 9-path changed summary, exit 0.

- [ ] **Step 2: Proof battery** (each its own simple invocation):
```sh
sh conformance/promotion-readiness-wired.sh --selftest   # 6 PASS + OK
sh conformance/promotion-readiness.sh --changed <(printf 'conformance/x.sh\n') --class --no-verify  # control-plane
sh conformance/claims-registry.sh        # PASS: promotion-readiness + coverage intact
sh conformance/ci-selftest-coverage.sh   # OK (lock wired; producer not flagged — no uncommented --selftest)
sh conformance/shellcheck.sh             # clean
sh conformance/verify.sh --require       # RESULT OK
```
Expected: all exit 0. (If `<(...)` process-substitution is unavailable under `sh`, use a temp file.)

- [ ] **Step 3: Idempotency** — `python3 apply.py` again → no-op; `git diff --stat` unchanged vs first apply.

- [ ] **Step 4: Teeth on the real lock** — in the clone, edit `conformance/promotion-readiness.sh`'s `classify_path` to `echo ordinary` unconditionally; `sh conformance/promotion-readiness-wired.sh --selftest` must FAIL (control-plane/sensitive downgraded). Restore.

---

## Task 5: Dual review + meta-control panel + hand-off

- [ ] **Step 1: Dual review** — dispatch `reviewer` (classifier correctness; fail-safe completeness; selftest non-vacuity; advisory-exit-0; no `guard_check_*` redefinition; apply.py discipline) and `security-reviewer` (the producer surfaces no secret values; sourcing guard-core introduces no injection; the classifier can't be downgraded by self-assertion; conformance/ two-matcher coverage needs no guard edit; `verify.sh` invocation is safe). Fold findings.

- [ ] **Step 2: Meta-control panel #32** — `docs/architecture/2026-06-30-meta-control-32.md`; per-epic-aware verdict (this is Slice 2 of the ratified epic).

- [ ] **Step 3: Hand-off** (human owns apply/commit/PR/merge/tag — [[merge-tag-authority]]):
```bash
python3 <scratch>/apply.py
printf '3.81.0 GO\n' > docs/governance/.meta-control-last   # governance close (M2-S5)
# + append the meta-control-log row
git add -A && git commit -m "feat(promotion-contract): change-class classifier + promotion-readiness surfacing (v3.81.0)"
git show --stat HEAD   # confirm both new files + claims.tsv + claims-registry.sh + ci.yml + promotion-contract.md + version trio + governance close
git push -u origin feat/promotion-contract-slice2
gh pr create --fill
gh pr checks <#>       # conformance GREEN; only control-plane-ratification red (by-design, solo)
gh pr merge <#> --squash --admin --delete-branch
git checkout main && git pull && sh scripts/release-tag.sh   # after main CI green
```

- [ ] **Step 4: Post-ship coherence** — fresh-clone `verify --require` green; `v3.81.0` on HEAD; update memory.

---

## Self-Review

**Spec coverage:**
- Producer (classify + surfacing, source guard-core, fail-safe, exit-0) → Task 1 step 1. ✓
- Lock + load-bearing fail-safe negative → Task 1 step 2, mutation-proof step 5. ✓
- Proven-vs-attested from verify.sh → Task 1 step 1 (`pv`), Task 2 step 2. ✓
- conformance/ placement / no guard edit → File Structure + Task 3 (no guard-core.sh in the edit list). ✓
- Claim + REQUIRED_IDS + ci.yml wiring → Task 3 steps 2–4. ✓
- promotion-contract.md build-status flip → Task 3 step 5. ✓
- Version finishing → Task 3 steps 6–8. ✓
- ci-selftest-coverage non-interaction (no uncommented `--selftest` in producer) → Global Constraints + Task 4 step 2. ✓
- Clone-proof / idempotency / teeth → Task 4. ✓
- Dual review + ship → Task 5. ✓

**Placeholder scan:** producer + lock are complete source; apply.py anchors are exact; no TBDs. ✓

**Type/name consistency:** `classify_path` / `disposition` / `cls` / `ck` / class strings `ordinary|sensitive|control-plane` / claim id `promotion-readiness` / files `promotion-readiness.sh` + `promotion-readiness-wired.sh` consistent across all tasks and the design. ✓
