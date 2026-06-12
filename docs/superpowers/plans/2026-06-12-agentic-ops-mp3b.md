# Agentic-Ops MP-3b — Behavior→Tier Scorecard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `scripts/agent-scorecard.sh` — reads a directory of MP-3a-schema traces, groups by `agent.id`, computes the trace-derivable behavior metrics over a per-agent window, classifies each agent `regressed | steady | earned` against its own trailing baseline, and emits a scorecard JSON + the asymmetric tier directive (auto-downgrade on regression / security-owner-ratified raise recommendation).

**Architecture:** POSIX `sh` + `jq`, mirroring `scripts/agent-trace.sh` / `dora.sh` (jq computes/shapes; sh orchestrates; no JSON hand-parsed in sh). Fixture-driven `--selftest`: committed synthetic trace dirs with hand-designed metrics drive deterministic classification assertions. `unknown` trace fields are excluded from metrics (never coerced to 0); thin data (`< --min-runs`) → `steady`/no-directive (fail-safe). The kit **emits directives, never actuates** — it never touches `.claude/`, the guard, or any live tier store.

**Tech Stack:** `sh` (dash-clean), `jq` (already a hard-required kit prerequisite). Spec: `docs/superpowers/specs/2026-06-12-agentic-ops-mp3b-behavior-tier-design.md`. Branch: `feature/agentic-ops-mp3b` (spec already committed there). Reuse: the MP-3a trace schema (`docs/operations/agentic-ops.md`); the `dora.sh`/`agent-trace.sh` sh+jq idiom.

---

## The trace schema this consumes (from MP-3a.2's emitter)

Each trace file is one JSON object:
```json
{ "agent.id": "claude-code", "run.id": "...", "work_item.id": "unknown",
  "parent.run.id": null, "start": "ISO", "end": "ISO",
  "tokens": {"in": N, "out": N, "cache_read": N}, "cost": "unknown",
  "outcome": "completed|blocked|error|handoff|unknown",
  "pr.ref": "unknown", "review.rounds": "unknown",
  "gates.hit": [], "gates.skipped": "unknown", "tests.written": "unknown",
  "steps": [ {"name": "Bash", "outcome": "ok|error|denied", "retries": 0} ] }
```

## Metrics (computed per agent over the window, `unknown` excluded)

| Metric | Definition |
|---|---|
| `denial_rate` | share of all tool-steps in the window with `outcome == "denied"` |
| `error_blocked_rate` | share of runs with `outcome` in {`error`,`blocked`} |
| `retry_rate` | mean over runs of `sum(steps[].retries)` |
| `review_rounds_mean` | mean of `review.rounds` over runs where it is a number (else excluded) |
| `out_token_trend` | sign of (recent-half mean `tokens.out` − baseline-half mean) — informational |
| `gate_skip_rate` | `"unknown"` in v1 (every trace's `gates.skipped` is `"unknown"`) — excluded from the trigger |

**Risk metrics (drive classification):** `denial_rate`, `error_blocked_rate`, `retry_rate`, `review_rounds_mean`. `out_token_trend` is informational (informs `earned`, never triggers a downgrade — spend is a §2 concern).

## Classification (symmetric trailing baseline)

Sort an agent's runs by `start`. Split into **baseline** (older half) and **recent** (newer half).
- `regressed` — any risk metric's *recent* value exceeds its *baseline* value by ≥ the configured margin (rate metrics: percentage-point margin `--margin`, default 0.15; counts: `retry`/`review` margin in absolute units).
- `earned` — every risk metric's *recent* value is ≤ its baseline value AND the recent half is "clean" (denial_rate==0 AND error_blocked_rate==0) AND the baseline had room to improve (baseline denial or error > 0).
- `steady` — otherwise, OR fewer than `--min-runs` runs (default 5) in the window.

`regressed` → emit a **downgrade directive**; `earned` → emit a **raise recommendation**; `steady` → no directive.

---

## File Structure
- **Create** `scripts/fixtures/scorecard/{good-bot,bad-bot,thin-bot}-*.json` — synthetic traces with hand-designed metrics (the test corpus).
- **Create** `scripts/agent-scorecard.sh` — the scorecard tool (read dir → group → metrics → classify → directive → output) + `--selftest`.
- **Modify** `docs/operations/agentic-ops.md` — flesh out the MP-3b section (scorecard, asymmetric directives, metric set, `unknown`-is-missing, relative-to-self/local calibration).
- **Modify** `DEVELOPMENT-PROCESS.md` §13 — a **+0 append** to the "Agent-quality metrics" line (line 379) pointing at the scorecard.
- **Modify** `conformance/agentic-ops-readiness.md` — fill row 6 (blank checklist + worked example) from placeholder to a real Auto/Manual pairing.
- **Hand-apply (control-plane, Bradley):** the kit-CI `agent-scorecard.sh --selftest` smoke step.

---

## Conventions every task obeys
- `#!/bin/sh`, `set -eu`, dash-clean (`dash -n`), quote expansions. jq does all JSON shaping.
- `unknown` (string) is **excluded** from a metric, never coerced to 0/false.
- Directives are **emitted only** — never mutate `.claude/`, guard, or any tier config.
- `--selftest` fixtures committed under `scripts/fixtures/scorecard/`, left in place (7e guard).
- Commit after each task (Conventional Commits).

---

## Task 1: The fixture trace corpus (the test input)

**Files:** Create nine files under `scripts/fixtures/scorecard/`. The selftest runs with `--min-runs 2 --window 6` so 4 runs/agent suffices (2 baseline + 2 recent); thin-bot gets 1 run (< min-runs).

**Designed outcomes:** `good-bot` → `earned` (baseline dirty, recent clean); `bad-bot` → `regressed` (baseline clean, recent dirty); `thin-bot` → `steady` (1 run < min-runs).

- [ ] **Step 1: Write the fixtures**

`good-bot-1.json` (baseline, oldest, has an error + a denied step):
```json
{"agent.id":"good-bot","run.id":"g1","start":"2026-06-10T01:00:00Z","outcome":"error","review.rounds":3,"gates.skipped":"unknown","steps":[{"name":"Bash","outcome":"denied","retries":1}]}
```
`good-bot-2.json` (baseline, older, completed):
```json
{"agent.id":"good-bot","run.id":"g2","start":"2026-06-10T02:00:00Z","outcome":"completed","review.rounds":2,"gates.skipped":"unknown","steps":[{"name":"Read","outcome":"ok","retries":0}]}
```
`good-bot-3.json` (recent, clean):
```json
{"agent.id":"good-bot","run.id":"g3","start":"2026-06-10T03:00:00Z","outcome":"completed","review.rounds":1,"gates.skipped":"unknown","steps":[{"name":"Read","outcome":"ok","retries":0}]}
```
`good-bot-4.json` (recent, clean):
```json
{"agent.id":"good-bot","run.id":"g4","start":"2026-06-10T04:00:00Z","outcome":"completed","review.rounds":1,"gates.skipped":"unknown","steps":[{"name":"Bash","outcome":"ok","retries":0}]}
```
`bad-bot-1.json` (baseline, clean):
```json
{"agent.id":"bad-bot","run.id":"b1","start":"2026-06-10T01:00:00Z","outcome":"completed","review.rounds":1,"gates.skipped":"unknown","steps":[{"name":"Read","outcome":"ok","retries":0}]}
```
`bad-bot-2.json` (baseline, clean):
```json
{"agent.id":"bad-bot","run.id":"b2","start":"2026-06-10T02:00:00Z","outcome":"completed","review.rounds":1,"gates.skipped":"unknown","steps":[{"name":"Read","outcome":"ok","retries":0}]}
```
`bad-bot-3.json` (recent, blocked + denied step):
```json
{"agent.id":"bad-bot","run.id":"b3","start":"2026-06-10T03:00:00Z","outcome":"blocked","review.rounds":4,"gates.skipped":"unknown","steps":[{"name":"Bash","outcome":"denied","retries":2}]}
```
`bad-bot-4.json` (recent, error + denied step):
```json
{"agent.id":"bad-bot","run.id":"b4","start":"2026-06-10T04:00:00Z","outcome":"error","review.rounds":3,"gates.skipped":"unknown","steps":[{"name":"Bash","outcome":"denied","retries":1}]}
```
`thin-bot-1.json` (only 1 run → steady):
```json
{"agent.id":"thin-bot","run.id":"t1","start":"2026-06-10T01:00:00Z","outcome":"completed","review.rounds":1,"gates.skipped":"unknown","steps":[{"name":"Read","outcome":"ok","retries":0}]}
```

- [ ] **Step 2: Verify all nine are valid JSON**

Run: `for f in scripts/fixtures/scorecard/*.json; do jq -e . "$f" >/dev/null || echo "BAD $f"; done && echo all-valid`
Expected: `all-valid`.

- [ ] **Step 3: Commit**

```bash
git add scripts/fixtures/scorecard/
git commit -m "test(agent-scorecard): synthetic trace corpus (good/bad/thin bots)"
```

---

## Task 2: The scorecard tool + `--selftest` (TDD core)

**Files:** Create `scripts/agent-scorecard.sh`

Build the tool and **iterate the jq until the selftest's classification assertions pass**. The fixtures' designed outcomes (good-bot→earned, bad-bot→regressed, thin-bot→steady) are the contract.

- [ ] **Step 1: Write the script skeleton + the selftest assertions (they define done)**

Create `scripts/agent-scorecard.sh`:

```sh
#!/bin/sh
# agent-scorecard.sh — per-agent behavior scorecard over a window of traces (MP-3b).
# Reads MP-3a-schema traces (scripts/agent-trace.sh output), groups by agent.id,
# computes trace-derivable behavior metrics over a window, classifies each agent
# regressed|steady|earned vs its OWN trailing baseline, and emits a scorecard +
# the asymmetric tier directive (auto-downgrade on regression / ratified-raise
# recommendation on earned). It EMITS directives; it NEVER actuates (never touches
# .claude/, the guard, or any tier store). sh + jq, mirroring scripts/agent-trace.sh.
#
# Honesty: "unknown" trace fields are EXCLUDED from a metric (never coerced to 0).
# Thin data (< --min-runs) or absent data -> steady, no directive (fail-safe).
# A green --selftest proves correct COMPUTATION on a fixture, not that any real
# agent behaved. It is a tool, not a gate; it fails no PR.
#
# Usage:
#   scripts/agent-scorecard.sh [--traces DIR] [--window N] [--min-runs N] \
#       [--margin F] [--out DIR] [--stdout]
#   scripts/agent-scorecard.sh --selftest
set -eu

TRACES="traces"; WINDOW=20; MIN_RUNS=5; MARGIN="0.15"; OUTDIR="scorecards"; STDOUT=0

# score_agent: stdin = JSON array of an agent's trace objects; args control thresholds.
# Emits the per-agent scorecard object (metrics + classification + directive).
# All metric math + classification is in jq (no JSON parsed in sh).
score_agent() {
  jq -s --argjson window "$WINDOW" --argjson minruns "$MIN_RUNS" \
        --argjson margin "$MARGIN" '
    # ... runs come in as the slurped array (one agent) ...
    (sort_by(.start) | (if length > $window then .[-$window:] else . end)) as $runs
    | ($runs | length) as $n
    | ($runs[: ($n/2 | floor)]) as $base
    | ($runs[($n/2 | floor):]) as $rec
    | def denial($a): ($a | [.[].steps[]?.outcome] | if length==0 then 0
                       else (map(select(.=="denied")) | length) / length end);
      def errrate($a): ($a | if length==0 then 0
                       else (map(select(.outcome=="error" or .outcome=="blocked")) | length)/length end);
      def retry($a): ($a | if length==0 then 0 else (map([.steps[]?.retries] | add // 0) | add / length) end);
      def reviews($a): ($a | [.[]."review.rounds" | select(type=="number")]
                       | if length==0 then null else (add/length) end);
      {
        "agent.id": ($runs[0]["agent.id"] // "unknown"),
        runs: $n,
        metrics: {
          denial_rate: denial($runs), error_blocked_rate: errrate($runs),
          retry_rate: retry($runs), review_rounds_mean: reviews($runs),
          gate_skip_rate: "unknown"
        },
        baseline: {denial: denial($base), err: errrate($base)},
        recent:   {denial: denial($rec), err: errrate($rec)}
      }
      # classification:
      | .classification = (
          if $n < $minruns then "steady"
          elif (.recent.denial - .baseline.denial) >= $margin
               or (.recent.err - .baseline.err) >= $margin then "regressed"
          elif (.recent.denial == 0 and .recent.err == 0)
               and (.baseline.denial > 0 or .baseline.err > 0) then "earned"
          else "steady" end )
      | .directive = (
          if .classification == "regressed" then
            {action:"auto-downgrade", reason:"recent risk metrics exceed trailing baseline by >= margin",
             recommend:"lower this agent’s autonomy tier one level (fail-safe; no ratification needed)"}
          elif .classification == "earned" then
            {action:"raise-recommendation", reason:"sustained improvement vs trailing baseline",
             recommend:"route to Security owner to ratify a one-level autonomy-tier raise (§13)"}
          else null end )
    '
}

# run_all: group all traces by agent.id, score each, collect into one report.
run_all() {
  _dir="$1"
  _agents=$(jq -r '."agent.id" // "unknown"' "$_dir"/*.json 2>/dev/null | sort -u)
  printf '['
  _first=1
  for _a in $_agents; do
    _card=$(jq -e --arg a "$_a" 'select(."agent.id" == $a)' "$_dir"/*.json | score_agent)
    [ "$_first" -eq 1 ] && _first=0 || printf ','
    printf '%s' "$_card"
  done
  printf ']'
}

selftest() {
  st_fail=0
  fx="$(dirname "$0")/fixtures/scorecard"
  WINDOW=6; MIN_RUNS=2; MARGIN="0.15"
  out=$(run_all "$fx")
  _cls() { printf '%s' "$out" | jq -r --arg a "$1" '.[] | select(."agent.id"==$a) | .classification'; }
  [ "$(_cls good-bot)" = "earned" ]     || { echo "selftest FAIL: good-bot should be earned (got $(_cls good-bot))"; st_fail=1; }
  [ "$(_cls bad-bot)" = "regressed" ]   || { echo "selftest FAIL: bad-bot should be regressed (got $(_cls bad-bot))"; st_fail=1; }
  [ "$(_cls thin-bot)" = "steady" ]     || { echo "selftest FAIL: thin-bot should be steady (got $(_cls thin-bot))"; st_fail=1; }
  # directive presence matches classification
  [ "$(printf '%s' "$out" | jq -r '.[]|select(."agent.id"=="bad-bot")|.directive.action')" = "auto-downgrade" ] \
      || { echo "selftest FAIL: bad-bot needs an auto-downgrade directive"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.[]|select(."agent.id"=="good-bot")|.directive.action')" = "raise-recommendation" ] \
      || { echo "selftest FAIL: good-bot needs a raise-recommendation"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.[]|select(."agent.id"=="thin-bot")|.directive')" = "null" ] \
      || { echo "selftest FAIL: thin-bot must have no directive"; st_fail=1; }
  # honesty: gate_skip_rate stays unknown (never coerced to a number)
  [ "$(printf '%s' "$out" | jq -r '.[0].metrics.gate_skip_rate')" = "unknown" ] \
      || { echo "selftest FAIL: gate_skip_rate must be unknown"; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then echo "agent-scorecard --selftest: FAIL" >&2; return 1; fi
  echo "agent-scorecard --selftest: OK (earned/regressed/steady + directives + unknown-honesty all match the fixtures)"
  return 0
}
```

Then arg parsing + dispatch: `--selftest` → `selftest`; else `run_all "$TRACES"` and either `--stdout` or write each agent's card to `"$OUTDIR/<agent>.json"` (slug the agent id for the filename with `tr -c 'A-Za-z0-9._-' '_'`, per the MP-3a.2 path-safety lesson). Handle an empty/absent traces dir gracefully (emit `[]`, exit 0).

- [ ] **Step 2: Iterate jq until the selftest passes**

Run: `sh scripts/agent-scorecard.sh --selftest`
Expected: `agent-scorecard --selftest: OK (...)`. Fix the jq/classification until all assertions pass; the fixtures' designed outcomes are the contract — do NOT weaken assertions.

- [ ] **Step 3: dash-clean**

Run: `dash -n scripts/agent-scorecard.sh && echo dash-clean`
Expected: `dash-clean`.

- [ ] **Step 4: Commit**

```bash
git add scripts/agent-scorecard.sh
git commit -m "feat(scripts): agent-scorecard.sh — per-agent behavior scorecard + tier directives"
```

---

## Task 3: Real-trace smoke + threshold calibration note

**Files:** none (verification + a value for Task 4)

- [ ] **Step 1: Generate real traces and score them**

```bash
td=$(mktemp -d)
for t in $(ls -S "$HOME/.claude/projects/-Users-bradleyjames-Development-agentic-sdlc-kit/"*.jsonl | tail -6); do
  sh scripts/agent-trace.sh "$t" --no-correlate --out "$td" >/dev/null 2>&1 || true
done
ls "$td" | wc -l   # how many traces produced
sh scripts/agent-scorecard.sh --traces "$td" --min-runs 2 --window 20 --stdout | jq '.[] | {agent:."agent.id", runs, classification, metrics}'
```
Expected: a scorecard array over the real `claude-code` agent — runs > 0, real metric numbers, a sane `classification` (almost certainly `steady` for a healthy agent), `gate_skip_rate: "unknown"`, **no crash**. This is the calibration observation: note the real `denial_rate`/`error_blocked_rate` magnitudes — they confirm the default `--margin 0.15` is sane (a healthy agent sits well below it).

- [ ] **Step 2: Record the calibration observation** for Task 4 (the doc): one line, e.g. "on the kit's own corpus the building agent's denial/error rates sit near 0, so the default margin 0.15 / min-runs 5 classify it `steady` — regression must be a real, sustained jump." *(No commit — verification only; fix Task 2 if the real run crashes or misclassifies a healthy agent.)*

---

## Task 4: Docs — agentic-ops.md MP-3b section + §13 pointer + readiness row 6

**Files:** Modify `docs/operations/agentic-ops.md`, `DEVELOPMENT-PROCESS.md`, `conformance/agentic-ops-readiness.md`

- [ ] **Step 1: Flesh out the MP-3b section in `docs/operations/agentic-ops.md`**

Replace the roadmap's "MP-3b:" stub line with a real subsection:

```markdown
## Behavior → autonomy-tier loop (MP-3b)

`scripts/agent-scorecard.sh` reads a window of traces, groups by `agent.id`, and computes
the trace-derivable behavior metrics — `denial_rate`, `error_blocked_rate`, `retry_rate`,
`review_rounds_mean` (risk metrics), plus an informational `out_token_trend`. `gate_skip_rate`
is `unknown` in v1 (a non-run isn't observable from a transcript). It classifies each agent
against its **own trailing baseline** (older half vs recent half of the window):

- **regressed** — a risk metric jumped past the baseline by ≥ the margin → a **fail-safe
  auto-downgrade directive** (tighten the agent's tier; no ratification needed).
- **earned** — sustained improvement to clean → a **raise recommendation** routed to the
  **Security owner** to ratify a tier raise (§13).
- **steady** (incl. `< --min-runs`) — no directive.

**The kit emits directives; it never actuates** — it never mutates `.claude/`, the guard, or
any tier store; the adopter wires the directive into their enforcement plane. **`unknown` is
treated as missing, never zero** — an agent is never downgraded on absent data. Thresholds are
**relative to the agent's own history**, calibrated **locally** from the adopter's own traces;
the kit ships only sensitivity defaults and **never pools or phones home** any agent data.
```

- [ ] **Step 2: §13 pointer — a `+0` append to line 379** (budget: PROCESS is 468/470)

In `DEVELOPMENT-PROCESS.md`, append to the END of the existing line 379 (no new line):
`Reliability earns autonomy; regressions revoke it.` → add: ` These metrics are computed by \`scripts/agent-scorecard.sh\` over a per-agent window and feed tier moves **asymmetrically** — a fail-safe auto-downgrade directive on regression, a Security-owner-ratified raise on earned improvement (\`docs/operations/agentic-ops.md\`).`

- [ ] **Step 3: Verify the budget held**

Run: `sh conformance/doc-budget.sh`
Expected: `PASS: DEVELOPMENT-PROCESS.md 468/470` (unchanged — append added text to an existing line, not a new line) and `OK: core docs within budget`. If it shows 469/470, that's still PASS (acceptable); if >470, shorten the appended sentence.

- [ ] **Step 4: Fill readiness row 6** in `conformance/agentic-ops-readiness.md`

Blank-checklist row 6 (line ~19) — replace the placeholder with a real Auto/Manual split:
```markdown
| 6a | Behavior-scorecard discipline declared — agent traces scored over a window (`scripts/agent-scorecard.sh`) *(documented)* | | | **Auto:** agentops-ready.sh (RUNBOOK §8) |
| 6b | Tier directives actually drive moves — a downgrade tightened / a ratified raise loosened a real agent's tier *(verified)* | | | Manual |
```
Worked-example row 6 (line ~30) — change from "N / MP-3b not yet shipped" to a `Y` example, e.g. `6a` → "Y · scorecard run in CI weekly over `traces/`" and `6b` → "Y · a regressed agent's tier was lowered via the platform policy".

- [ ] **Step 5: Verify links**

Run: `sh conformance/check-links.sh`
Expected: `OK: all relative Markdown links resolve`.

- [ ] **Step 6: Commit**

```bash
git add docs/operations/agentic-ops.md DEVELOPMENT-PROCESS.md conformance/agentic-ops-readiness.md
git commit -m "docs: MP-3b scorecard — agentic-ops section + §13 pointer + readiness row 6"
```

---

## Task 5: Prepare the control-plane CI smoke step (hand-apply for Bradley)

**Files:** Hand-apply (Bradley): `.github/workflows/ci.yml`

- [ ] **Step 1: Produce the exact step** (next to the `Agent-trace emitter smoke` step):
```yaml
      - name: Agent-scorecard smoke (selftest over fixture corpus)
        run: sh scripts/agent-scorecard.sh --selftest
```
- [ ] **Step 2: Surface it in the PR body** with the `KIT_GUARD_SELFEDIT=1 git add … ; git commit` apply commands. *(No repo change in this task.)*

---

## Task 6: Final verification + independent review + PR

- [ ] **Step 1: Full sweep**
```bash
sh scripts/agent-scorecard.sh --selftest
dash -n scripts/agent-scorecard.sh && echo dash-clean
sh conformance/check-links.sh
sh conformance/doc-budget.sh
sh conformance/verify.sh | tail -3
```
Expected: selftest OK; dash-clean; links OK; doc-budget OK; `verify.sh` RESULT: OK (unchanged — no new conformance check).

- [ ] **Step 2: Independent review (builder ≠ sole reviewer)** — dispatch a reviewer subagent. Focus: (a) jq classification correctness (baseline/recent split, margin comparison, the earned/regressed/steady boundaries); (b) `unknown` is excluded not zeroed (verify `review.rounds:"unknown"` doesn't skew the mean, and `gate_skip_rate` stays `unknown`); (c) thin-data + empty-dir + single-agent + missing-`start` all degrade to `steady`/`[]` without crashing; (d) the tool never writes outside `--out` (agent-id slugged) and never touches `.claude/`/guard; (e) honesty wording (directive ≠ actuation; declared ≠ verified).

- [ ] **Step 3: Address findings, then PR**
```bash
git push -u origin feature/agentic-ops-mp3b
gh pr create --title "feat(agentic-ops): MP-3b — behavior scorecard → autonomy-tier directives" --body "<summary + asymmetric model + unknown-is-missing + relative-to-self/local + Task-5 control-plane snippet + the 2.56.0 arc-close note + merge command>"
```
Report the PR number + `gh pr merge <n> --squash --admin --delete-branch`. **Do not self-merge.**

---

## Self-review (plan author)
- **Spec coverage:** §1 framing → Task 4 docs. §2 asymmetric/emit-not-actuate → Task 2 `.directive` + Task 4 wording. §3 scorecard tool → Task 2. §4 metrics → Task 2 jq defs + Task 4 table. §5 honesty (`unknown`=missing, `<min-runs`→steady) → Task 2 classification + selftest assertions. §6 trailing-baseline + relative/local → Task 2 split + Task 4 doc. §7 governance/conformance → Task 4 (§13 pointer + readiness row 6) + Task 5 (CI smoke). §8 out-of-scope → respected (no auto-raise, no actuation, no git-churn). §9 DoD → Tasks 1–6 + the 2.56.0 release noted for arc close. **No gaps.**
- **Placeholder scan:** the jq `# ... runs come in ...` comment is a guide inside otherwise-complete jq; the classification + metric jq is fully written. The fixtures are concrete with designed outcomes. The only deliberately-empirical value (the calibration observation) is a documented Task-3 observation, not code. No banned placeholders.
- **Consistency:** metric names (`denial_rate`, `error_blocked_rate`, `retry_rate`, `review_rounds_mean`, `gate_skip_rate`), classifications (`regressed|steady|earned`), and directive actions (`auto-downgrade`/`raise-recommendation`) are identical across Tasks 1, 2, 4 and the selftest assertions.
