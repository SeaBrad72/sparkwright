# E4d — Runaway Kill-Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a harness-neutral, executable runaway circuit-breaker (`runaway-guard.sh`) that halts an orchestrated flow when cumulative tokens, step count, or agent-spawn count breach a control-plane ceiling — proven by a conformance lock.

**Architecture:** A POSIX-sh checker reads an agent-immutable ceiling config (`.kit/budget.conf`) and an append-only runtime tally (`.kit-run/tally`), and exits 0/1/2 (continue/stop/unverified). The orchestrator calls it once per step. The ceiling config + the script are control-plane (guard-protected); the tally is best-effort runtime state, with the platform LLM-API cap as the documented backstop.

**Tech Stack:** POSIX `sh` + `awk`/`sed`/`grep` only (no `jq`, no `bash`-isms — mirrors every other `conformance/*.sh`). Python 3 only for the AMBER `apply.py`.

## Global Constraints

- **POSIX sh only** — `#!/bin/sh`, `set -eu`, no bashisms; parse config with `sed`/`grep` (never `source`). Sum the tally with `awk`. (Matches `conformance/cost-governance-ready.sh`.)
- **Three-state exit convention** — `0` PASS/continue, `1` FAIL/stop, `2` UNVERIFIED; under CI (`CI` env set) or `--require`, UNVERIFIED escalates to `1`.
- **Control-plane discipline (ratified AMBER convention)** — `.claude/hooks/guard-core.sh`, `conformance/*`, `.github/workflows/*`, `scripts/runaway-guard.sh`, `.kit/budget.conf` are all control-plane. The **agent never applies control-plane changes to the real tree.** It assembles every control-plane edit into `scratchpad/e4d/apply.py`, dual-reviews the scratch, and **dry-runs `apply.py` on a throwaway clone** (proving full `verify --require` green there). **Bradley** then runs `apply.py` on the real tree + finishing edits (VERSION/CHANGELOG/README/ROADMAP) + commit + PR + admin-merge + tag (mirrors the E4e slice; [[merge-tag-authority]]).
- **Builder ≠ reviewer** — after build, dual review: a `reviewer` agent (correctness + §14 gates) AND a `security-reviewer` agent (probes the §4 integrity model). Stop at PR-green-reviewed; **Bradley** does the admin-merge + tag (see [[merge-tag-authority]]).
- **Harness-neutral** — no Claude-Code-specific dependency; the orchestration loop is a documented pattern, not a `.claude/workflows/` artifact.
- **Spec:** `docs/architecture/2026-06-25-e4d-runaway-killswitch-design.md`. **Config-format refinement (planning decision):** spec said `.kit/budget.json`; pinned to **`.kit/budget.conf`** (`KEY=VALUE`) for zero-dependency, hot-path-safe parsing (no `jq`).

---

## File map

| Path | Action | Responsibility | Control-plane |
|------|--------|----------------|:---:|
| `scripts/runaway-guard.sh` | Create | The checker: `step` / `check` / `reset` / `--selftest` | yes (named script) |
| `.kit/budget.conf` | Create | Default ceilings (adopter-editable, ratified) | yes |
| `.kit-run/` | (runtime) | Append-only tally dir — gitignored, never committed | no |
| `conformance/runaway-killswitch-wired.sh` | Create | Conformance lock + `--selftest` breach fixtures | yes (`conformance/*`) |
| `docs/operations/runaway-killswitch.md` | Create | Rationale, honest ceiling, reference loop | no |
| `.claude/hooks/guard-core.sh` | Modify | Add config + script to `is_control_plane_path`; add config to both shell matchers | yes |
| `conformance/agent-autonomy.sh` | Modify | Add fixture: budget-config mutation denied (tool + shell) | yes |
| `conformance/claims.tsv` | Modify | Register `runaway-killswitch` claim | yes |
| `conformance/claims-registry.sh` | Modify | Add `runaway-killswitch` to `REQUIRED_IDS` | yes |
| `.github/workflows/ci.yml` | Modify | Wire `--selftest` step | yes |
| `conformance/README.md` | Modify | Index row | no |
| `.gitignore` | Modify | Add `.kit-run/` | no |
| `RUNBOOK.md` | Modify | Discoverability pointer to `.kit/budget.conf` | no |
| `scratchpad/e4d/apply.py` | Create | AMBER materializer for all control-plane edits | no (scratch) |

---

## Task 0: Branch + scratchpad hygiene

**Files:**
- Modify: `.gitignore` (ensure `scratchpad/` ignored)

- [ ] **Step 1: Confirm branch + scratchpad ignored**

Run:
```bash
git branch --show-current   # expect: feature/e4d-runaway-killswitch
grep -qxF 'scratchpad/' .gitignore || printf 'scratchpad/\n' >> .gitignore
mkdir -p scratchpad/e4d
grep -q scratchpad .gitignore && echo "scratchpad ignored OK"
```
Expected: prints `scratchpad ignored OK`; `scratchpad/e4d` exists.

- [ ] **Step 2: Commit the gitignore touch if changed**

```bash
git add .gitignore && git commit -q -m "chore(e4d): ignore scratchpad build area" || echo "no change"
```

---

## Task 1: `runaway-guard.sh` — build & TDD in scratchpad

Develop the checker where the agent can write/run freely (`scratchpad/e4d/`), TDD it, then it is transcribed verbatim to `scripts/runaway-guard.sh` by `apply.py` (Task 5).

**Files:**
- Create: `scratchpad/e4d/runaway-guard.sh` (becomes `scripts/runaway-guard.sh`)
- Test: `scratchpad/e4d/test-runaway-guard.sh`

**Interfaces:**
- Produces: CLI `runaway-guard.sh step|check|reset [--tokens N] [--agents N] [--config PATH] [--tally PATH] | --selftest`. Exit `0` continue (WARN on stderr at ≥`WARN_PCT`), `1` STOP (names breached dim on stderr), `2` UNVERIFIED (missing/malformed config).
- Consumes: config keys `MAX_TOKENS MAX_STEPS MAX_AGENTS WARN_PCT COST_PER_1K_USD`; tally lines `"<tokens> <agents>"` (one per `step`).

- [ ] **Step 1: Write the failing test harness**

Create `scratchpad/e4d/test-runaway-guard.sh`:
```sh
#!/bin/sh
# TDD harness for runaway-guard.sh (run: sh scratchpad/e4d/test-runaway-guard.sh)
set -u
G="scratchpad/e4d/runaway-guard.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cfg="$tmp/budget.conf"; tally="$tmp/tally"
mkcfg() { printf 'MAX_TOKENS=%s\nMAX_STEPS=%s\nMAX_AGENTS=%s\nWARN_PCT=%s\nCOST_PER_1K_USD=0.003\n' "$1" "$2" "$3" "$4" > "$cfg"; }
run() { sh "$G" "$@" --config "$cfg" --tally "$tally"; }
pass=0; fail=0
ok() { if [ "$1" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $3 (want exit $1, got $2)"; fi; }

# under budget -> 0
mkcfg 1000 10 5 80; : > "$tally"
run step --tokens 100 --agents 1 >/dev/null 2>&1; ok 0 $? "under-budget continue"
# token breach -> 1
mkcfg 1000 10 5 80; : > "$tally"
run step --tokens 1000 --agents 1 >/dev/null 2>&1; ok 1 $? "token ceiling stop"
# step breach -> 1 (cheap-but-endless: tokens tiny, steps exceed)
mkcfg 100000 3 50 80; : > "$tally"
run step --tokens 1 --agents 0 >/dev/null 2>&1
run step --tokens 1 --agents 0 >/dev/null 2>&1
run step --tokens 1 --agents 0 >/dev/null 2>&1; ok 1 $? "step ceiling stop"
# agent breach -> 1
mkcfg 100000 50 2 80; : > "$tally"
run step --tokens 1 --agents 2 >/dev/null 2>&1; ok 1 $? "agent ceiling stop"
# warn but continue -> 0 + WARN on stderr
mkcfg 1000 10 5 80; : > "$tally"
err=$(run step --tokens 800 --agents 1 2>&1 >/dev/null); ok 0 $? "warn continue"
case "$err" in *WARN*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL: warn emitted";; esac
# missing config -> 2 (fail-closed)
run check --config "$tmp/nope.conf" >/dev/null 2>&1; ok 2 $? "missing config unverified"
# malformed config -> 2
printf 'MAX_TOKENS=abc\n' > "$cfg"; run check >/dev/null 2>&1; ok 2 $? "malformed config unverified"
# reset clears tally
mkcfg 1000 10 5 80; : > "$tally"; run step --tokens 500 --agents 1 >/dev/null 2>&1
run reset >/dev/null 2>&1; run check >/dev/null 2>&1; ok 0 $? "reset clears"
# disabled dimension (max=0) never breaches
mkcfg 0 0 0 80; : > "$tally"; run step --tokens 99999 --agents 99 >/dev/null 2>&1; ok 0 $? "max=0 disables"

echo "PASS=$pass FAIL=$fail"; [ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it — verify it fails (no script yet)**

Run: `sh scratchpad/e4d/test-runaway-guard.sh`
Expected: FAIL (script missing → all cases error).

- [ ] **Step 3: Implement `scratchpad/e4d/runaway-guard.sh`**

```sh
#!/bin/sh
# runaway-guard.sh — E4d executable runaway circuit-breaker (harness-neutral).
#
# The kit cannot MEASURE tokens (the harness/LLM-API does); it ENFORCES a ceiling on REPORTED
# usage at the orchestration seam and halts the loop. The platform LLM-API cap is the hard ceiling
# ABOVE this. The ceiling config (.kit/budget.conf) + this script are control-plane (agent-immutable);
# the tally (.kit-run/tally) is best-effort runtime state (platform cap is the backstop if defeated).
#
# Usage:
#   runaway-guard.sh step  --tokens N --agents N   # record this step's usage, then check
#   runaway-guard.sh check                         # verdict only
#   runaway-guard.sh reset                         # start a fresh run (clear tally)
#   runaway-guard.sh --selftest
# Exit: 0 continue (WARN on stderr at >=WARN_PCT) | 1 STOP (ceiling breached) | 2 UNVERIFIED (bad config).
set -eu

CONFIG="${RUNAWAY_BUDGET_CONFIG:-.kit/budget.conf}"
TALLY="${RUNAWAY_TALLY:-.kit-run/tally}"

die2() { printf '%s\n' "$*" >&2; exit 2; }

cfg() {  # cfg KEY -> first matching value (KEY=VALUE, ignores # comments); empty if absent
  [ -f "$CONFIG" ] || return 1
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^#[:space:]]*\).*/\1/p" "$CONFIG" | head -1
}

load_config() {
  [ -f "$CONFIG" ] || die2 "2: config missing: $CONFIG (fail-closed)"
  MAX_TOKENS=$(cfg MAX_TOKENS || true)
  MAX_STEPS=$(cfg MAX_STEPS || true)
  MAX_AGENTS=$(cfg MAX_AGENTS || true)
  WARN_PCT=$(cfg WARN_PCT || true);          WARN_PCT="${WARN_PCT:-80}"
  COST_PER_1K=$(cfg COST_PER_1K_USD || true); COST_PER_1K="${COST_PER_1K:-0}"
  for v in MAX_TOKENS MAX_STEPS MAX_AGENTS WARN_PCT; do
    eval "_val=\${$v:-}"
    case "$_val" in ''|*[!0-9]*) die2 "2: config $v not a non-negative integer: '$_val' (fail-closed)";; esac
  done
}

record() { mkdir -p "$(dirname "$TALLY")"; printf '%s %s\n' "$1" "$2" >> "$TALLY"; }

sums() {  # echoes "TOKENS STEPS AGENTS"
  if [ -f "$TALLY" ]; then awk '{t+=$1; a+=$2; n++} END{printf "%d %d %d\n", t+0, n+0, a+0}' "$TALLY"
  else echo "0 0 0"; fi
}

check() {
  load_config
  # shellcheck disable=SC2046
  set -- $(sums); cur_t=$1; cur_s=$2; cur_a=$3
  breach=""; warn=""
  for d in "tokens $cur_t $MAX_TOKENS" "steps $cur_s $MAX_STEPS" "agents $cur_a $MAX_AGENTS"; do
    # shellcheck disable=SC2086
    set -- $d; nm=$1; cur=$2; max=$3
    [ "$max" -gt 0 ] || continue                 # max=0 disables the dimension
    if [ "$cur" -ge "$max" ]; then breach="$breach $nm($cur/$max)"
    elif [ $(( cur * 100 )) -ge $(( max * WARN_PCT )) ]; then warn="$warn $nm($cur/$max)"; fi
  done
  if [ -n "$breach" ]; then
    printf 'STOP: runaway ceiling breached:%s [~$%s]\n' "$breach" \
      "$(awk -v t="$cur_t" -v r="$COST_PER_1K" 'BEGIN{printf "%.4f", (t/1000)*r}')" >&2
    exit 1
  fi
  [ -n "$warn" ] && printf 'WARN: approaching ceiling (>=%s%%):%s\n' "$WARN_PCT" "$warn" >&2
  exit 0
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
tokens=0; agents=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tokens) tokens="${2:-}"; shift 2 ;;
    --agents) agents="${2:-}"; shift 2 ;;
    --config) CONFIG="${2:-}"; shift 2 ;;
    --tally)  TALLY="${2:-}";  shift 2 ;;
    --selftest) cmd="selftest"; shift ;;
    *) die2 "2: unknown arg: $1" ;;
  esac
done

case "$cmd" in
  step)
    case "$tokens$agents" in *[!0-9]*) die2 "2: --tokens/--agents must be non-negative integers";; esac
    record "$tokens" "$agents"; check ;;
  check) check ;;
  reset) rm -f "$TALLY" ;;
  selftest) sh scratchpad/e4d/test-runaway-guard.sh ;;   # NOTE: apply.py rewrites this line (Task 5)
  *) die2 "2: usage: runaway-guard.sh step|check|reset [--tokens N] [--agents N] | --selftest" ;;
esac
```

- [ ] **Step 4: Run the harness — verify it passes**

Run: `sh scratchpad/e4d/test-runaway-guard.sh`
Expected: `PASS=11 FAIL=0` (exit 0).

- [ ] **Step 5: Commit the scratch build**

```bash
git add -f scratchpad/e4d/runaway-guard.sh scratchpad/e4d/test-runaway-guard.sh 2>/dev/null || true
git commit -q -m "build(e4d): runaway-guard checker + TDD harness (scratch)" || echo "scratch ignored — ok, carried in tree"
```
(Scratch is gitignored; this step is a no-op marker. The artifact travels via `apply.py`.)

---

## Task 2: `runaway-killswitch-wired.sh` conformance lock — build & TDD in scratchpad

Mirror `conformance/cost-governance-ready.sh` style. The `--selftest` is self-contained (builds its own temp config + tally; invokes the installed `scripts/runaway-guard.sh`). It is the kit's proof the breach logic has teeth.

**Files:**
- Create: `scratchpad/e4d/runaway-killswitch-wired.sh` (becomes `conformance/runaway-killswitch-wired.sh`)

**Interfaces:**
- Consumes: `scripts/runaway-guard.sh` (Task 1).
- Produces: `sh conformance/runaway-killswitch-wired.sh --selftest` → exit 0 iff present+executable+breach-logic correct; else 1.

- [ ] **Step 1: Implement the conformance check (selftest IS the test)**

```sh
#!/bin/sh
# runaway-killswitch-wired.sh — E4d: the runaway circuit-breaker is installed + has teeth.
#
# Proves: scripts/runaway-guard.sh exists, is executable, and ENFORCES each ceiling
# (tokens / steps / agents), warns before breach, and fails closed on a bad config.
# A green run does NOT prove a hard LLM-API spend cap (platform-owned) or a tamper-proof
# tally (best-effort) — see docs/operations/runaway-killswitch.md. Necessary, not sufficient.
#
# Usage: sh conformance/runaway-killswitch-wired.sh [--require] | --selftest
set -eu
GUARD="scripts/runaway-guard.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

selftest() {
  [ -f "$GUARD" ] || fail "missing $GUARD"
  [ -x "$GUARD" ] || fail "$GUARD not executable"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  cfg="$tmp/c"; tally="$tmp/t"
  mkcfg() { printf 'MAX_TOKENS=%s\nMAX_STEPS=%s\nMAX_AGENTS=%s\nWARN_PCT=%s\nCOST_PER_1K_USD=0.003\n' "$1" "$2" "$3" "$4" >"$cfg"; }
  R() { sh "$GUARD" "$@" --config "$cfg" --tally "$tally"; }
  expect() { _w=$1; shift; "$@" >/dev/null 2>&1; _g=$?; [ "$_g" = "$_w" ] || fail "$_desc (want $_w, got $_g)"; }

  _desc="under-budget continues"; mkcfg 1000 10 5 80; : >"$tally"; expect 0 R step --tokens 100 --agents 1
  _desc="token breach stops";     mkcfg 1000 10 5 80; : >"$tally"; expect 1 R step --tokens 1000 --agents 0
  _desc="step breach stops";      mkcfg 999999 2 99 80; : >"$tally"; R step --tokens 1 --agents 0 >/dev/null 2>&1; expect 1 R step --tokens 1 --agents 0
  _desc="agent breach stops";     mkcfg 999999 99 2 80; : >"$tally"; expect 1 R step --tokens 1 --agents 2
  _desc="warn continues";         mkcfg 1000 10 5 80; : >"$tally"; expect 0 R step --tokens 800 --agents 1
  _desc="breach names the dim";   mkcfg 1000 10 5 80; : >"$tally"; case "$(R step --tokens 1000 --agents 0 2>&1 >/dev/null)" in *tokens*) : ;; *) fail "breach must name the dimension";; esac
  _desc="missing config -> 2";    expect 2 R check --config "$tmp/nope"
  _desc="malformed config -> 2";  printf 'MAX_TOKENS=x\n' >"$cfg"; expect 2 R check
  _desc="reset clears";           mkcfg 1000 10 5 80; : >"$tally"; R step --tokens 500 --agents 1 >/dev/null 2>&1; R reset --tally "$tally" >/dev/null 2>&1; expect 0 R check
  echo "runaway-killswitch-wired: selftest OK"
}

case "${1:-}" in
  --selftest) selftest ;;
  --require|"") selftest ;;   # no project-state aspect; the teeth ARE the selftest
  *) echo "usage: runaway-killswitch-wired.sh [--require] | --selftest" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: Run against the scratch guard — verify pass**

Run: `GUARD=scratchpad/e4d/runaway-guard.sh sh scratchpad/e4d/runaway-killswitch-wired.sh --selftest`
(Temporarily point `GUARD` at the scratch path for this dry run.)
Expected: `runaway-killswitch-wired: selftest OK` (exit 0).

- [ ] **Step 3: Mutation-kill check (prove the lock has teeth)**

Run: break a ceiling comparison in the scratch guard (e.g. change `-ge` to `-gt` won't trip; instead make `check` always `exit 0`) and re-run Step 2 — expect FAIL. Revert.
Expected: the selftest catches a neutered checker.

---

## Task 3: Operations doc + default config + discoverability (non-control-plane parts direct)

**Files:**
- Create: `docs/operations/runaway-killswitch.md`
- Modify: `RUNBOOK.md` (pointer)
- (`.kit/budget.conf` default content authored here, but WRITTEN by `apply.py` — it's control-plane)

- [ ] **Step 1: Write the ops doc**

Create `docs/operations/runaway-killswitch.md` covering: the seam it guards; the three dimensions; the `.kit/budget.conf` keys; the honest ceiling (no hard spend cap; tally best-effort; wall-clock = platform timeout); and a **harness-neutral reference loop**:
```sh
# Reference: orchestrator calls the guard once per step; halts + escalates on STOP.
sh scripts/runaway-guard.sh reset
while work_remains; do
  run_one_step                       # harness does the work, reports usage
  if ! sh scripts/runaway-guard.sh step --tokens "$STEP_TOKENS" --agents "$STEP_AGENTS"; then
    escalate "runaway kill-switch tripped"; break
  fi
done
```
Cross-link `docs/operations/cost-governance.md` (H3b: declare) and the feature-flags doc (E2: release toggle). State the §4 integrity model + residual-risk plainly.

- [ ] **Step 2: Author the default `.kit/budget.conf` content (for apply.py to write)**

```ini
# .kit/budget.conf — E4d runaway ceilings (CONTROL-PLANE: raising a ceiling is a ratified act).
# A dimension is DISABLED when its value is 0. Tune to your run profile; see docs/operations/runaway-killswitch.md.
MAX_TOKENS=2000000
MAX_STEPS=200
MAX_AGENTS=50
WARN_PCT=80
COST_PER_1K_USD=0.003
```

- [ ] **Step 3: Add the RUNBOOK pointer**

Add under the operations section of `RUNBOOK.md`:
```markdown
- **Runaway kill-switch:** ceilings in `.kit/budget.conf`; the orchestration loop calls `scripts/runaway-guard.sh step` (see `docs/operations/runaway-killswitch.md`).
```

- [ ] **Step 4: Commit the non-control-plane docs**

```bash
git add docs/operations/runaway-killswitch.md RUNBOOK.md
git commit -q -m "docs(e4d): runaway kill-switch ops doc + RUNBOOK pointer"
```

---

## Task 4: Author the AMBER materializer `scratchpad/e4d/apply.py`

One reviewable Python script that performs every control-plane edit idempotently. It is security-reviewed (Task 6) **before** it runs (Task 5).

**Files:**
- Create: `scratchpad/e4d/apply.py`

**Interfaces:**
- Consumes: the tested `scratchpad/e4d/runaway-guard.sh` + `scratchpad/e4d/runaway-killswitch-wired.sh`.
- Produces: materialized control-plane files listed in the File map.

- [ ] **Step 1: Write `apply.py`** with these operations (each idempotent; abort if an anchor is missing):

1. **Install scripts:** copy `scratchpad/e4d/runaway-guard.sh` → `scripts/runaway-guard.sh` (chmod 0755), rewriting the `selftest)` dispatch line to `selftest) sh conformance/runaway-killswitch-wired.sh --selftest ;;`. Copy `scratchpad/e4d/runaway-killswitch-wired.sh` → `conformance/runaway-killswitch-wired.sh` (chmod 0755).
2. **Write config:** create `.kit/budget.conf` with the Task 3 Step 2 content (only if absent; never clobber an adopter's ceilings).
3. **guard-core.sh — `is_control_plane_path`:** in the `case` block, insert two alternations before the closing `CLAUDE.md` arm:
   ```
   .kit/budget.conf|*/.kit/budget.conf|\
   scripts/runaway-guard.sh|*/scripts/runaway-guard.sh|\
   ```
4. **guard-core.sh — shell mutation matcher (the line-7 regex):** append `|\.kit/budget\.conf` inside the alternation group (so a shell write to the config is caught). Do NOT add the script here (named scripts stay invocable — matches `sod-check.sh`).
5. **guard-core.sh — redirect-target matcher (the line-10 regex):** append `|\.kit/budget\.conf` inside that alternation group.
6. **claims.tsv:** append a TAB-separated row:
   ```
   runaway-killswitch	the runaway circuit-breaker is installed and enforces token/step/agent ceilings	sh conformance/runaway-killswitch-wired.sh --selftest
   ```
7. **claims-registry.sh:** append ` runaway-killswitch` to the `REQUIRED_IDS="..."` string (line 17).
8. **ci.yml:** add a step after the cost-governance step:
   ```yaml
   - name: conformance — runaway kill-switch (E4d)
     run: sh conformance/runaway-killswitch-wired.sh --selftest
   ```
9. **conformance/README.md:** add an index row for `runaway-killswitch-wired.sh` (Type: script; Contract: runaway ceiling enforced; Gate: per-PR + drift-watch).
10. **agent-autonomy.sh:** add a fixture asserting an agent cannot raise its own ceiling — both the Write/Edit path AND a shell `echo MAX_TOKENS=9 > .kit/budget.conf` are DENIED by the guard (mirror the existing M2-S5 marker fixture). Print PASS/FAIL like the surrounding fixtures.
11. **.gitignore:** ensure `.kit-run/` present.
12. Print a unified summary of files changed; exit non-zero if any anchor was not found (fail-closed, no partial apply).

- [ ] **Step 2: Dry-run lint the materializer**

Run: `python3 -m py_compile scratchpad/e4d/apply.py && echo "apply.py compiles"`
Expected: `apply.py compiles`.

---

## Task 5: Dry-run `apply.py` on a throwaway clone (agent verifies; does NOT touch the real tree)

The agent proves `apply.py` materializes a fully-green tree **on a clone**, never on the real control-plane files. Bradley applies for real in Task 7.

- [ ] **Step 1: Clone the working tree to a scratch location**

Run:
```bash
CLONE=$(mktemp -d)/e4d-dryrun
git clone -q . "$CLONE" && git -C "$CLONE" checkout -q feature/e4d-runaway-killswitch
cp -R scratchpad "$CLONE"/scratchpad   # carry the (gitignored) scratch artifacts + apply.py
echo "clone: $CLONE"
```

- [ ] **Step 2: Apply on the clone**

Run: `(cd "$CLONE" && python3 scratchpad/e4d/apply.py)`
Expected: summary of changed files; exit 0; no anchor-missing abort.

- [ ] **Step 3: Verify the new lock + guard integrity on the clone**

Run:
```bash
( cd "$CLONE" \
  && sh conformance/runaway-killswitch-wired.sh --selftest \
  && sh conformance/agent-autonomy.sh \
  && sh scripts/runaway-guard.sh --selftest )
```
Expected: all exit 0; agent-autonomy reports the new budget-config fixtures PASS.

- [ ] **Step 4: Full aggregate + claims + doctor on the clone (the real gate)**

Run:
```bash
( cd "$CLONE" \
  && sh conformance/verify.sh --require \
  && sh conformance/claims-registry.sh \
  && sh scripts/doctor.sh )
```
Expected: 0 failed; `runaway-killswitch` present in claims coverage (no silent-drop); doctor Overall PASS.

- [ ] **Step 5: Record the dry-run result** in the report file (clone path, exit codes, claims count) for the reviewers. Do NOT modify the real tree.

---

## Task 6: Dual review (builder ≠ reviewer)

- [ ] **Step 1: Correctness/standards review** — dispatch the `reviewer` agent over the diff (`git diff main...HEAD`): POSIX-sh correctness, three-state, §14 gates, claims coverage, no over-claim in docs.
- [ ] **Step 2: Security review** — dispatch the `security-reviewer` agent specifically on the §4 integrity model: (a) is `.kit/budget.conf` denied via BOTH the Write/Edit tool AND shell redirect? (b) can the script be invoked but not blanked? (c) is the tally residual-risk honestly documented (no over-claim)? (d) does a malformed/missing config fail closed under CI?
- [ ] **Step 3: Address findings** — re-run Tasks 4–5 for any control-plane fix (edit `apply.py`, re-apply); re-run reviews until both APPROVE.

---

## Task 7: Handoff to Bradley (apply + finishing + PR + merge — human-ratified)

The agent stops here with a reviewed, dry-run-verified `scratchpad/e4d/apply.py`. Bradley runs the AMBER apply + finishing on the real tree.

- [ ] **Step 1: Agent presents the handoff packet** — the dry-run result (clone path, green verify, claims count), both review verdicts, and the exact commands below.

- [ ] **Step 2: Bradley runs (on the real tree):**

```bash
python3 scratchpad/e4d/apply.py                                  # materialize control-plane edits
# finishing edits: bump VERSION (e.g. 3.48.19), add CHANGELOG entry (honest-ceiling verb),
#                  README badge if needed, ROADMAP-KIT.md E4d -> done
sh conformance/verify.sh --require && sh conformance/claims-registry.sh && sh scripts/doctor.sh
git add -A && git commit -m "feat(e4d): runaway kill-switch — executable circuit-breaker + conformance lock (v3.48.19)"
git push -u origin feature/e4d-runaway-killswitch
gh pr create --title "feat(e4d): runaway kill-switch (v3.48.19)" --body "<summary + honest-ceiling note + review verdicts>"
```

- [ ] **Step 3:** After CI green + review, Bradley does the admin-merge + tag (do not self-merge — [[merge-tag-authority]]).

---

## Self-review (plan vs spec)

- **Spec coverage:** §1 boundary → Task 3 doc + reference loop. §2 checker/exit codes/dimensions → Task 1. §3 config/tally split → Task 1 + Task 3 Step 2 + Task 4 op 2/11. §4 integrity (both matchers, residual risk) → Task 4 ops 3–5 + 10, Task 6 Step 2. §5 conformance/registration → Task 2 + Task 4 ops 6–9. §6 docs → Task 3. §7 scope (no wall-clock/no dollar-precision) → honored (cost is derived-only, no time dim). §8 process (AMBER + dual review + Bradley merges) → Tasks 4–7. **No gaps.**
- **Placeholder scan:** complete code for both scripts and the test harness; `apply.py` operations are enumerated with exact anchors/strings; PR body `<summary>` is the only intentional fill-in. OK.
- **Type/name consistency:** `runaway-guard.sh` verbs (`step|check|reset|--selftest`), config keys (`MAX_TOKENS/MAX_STEPS/MAX_AGENTS/WARN_PCT/COST_PER_1K_USD`), tally format (`"<tokens> <agents>"`), claim id (`runaway-killswitch`), and exit codes (0/1/2) are identical across Tasks 1, 2, 4. Consistent.
