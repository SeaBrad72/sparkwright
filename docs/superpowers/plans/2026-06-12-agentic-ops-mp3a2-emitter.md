# Agentic-Ops MP-3a.2 — Trace Emitter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `scripts/agent-trace.sh` — the reference dev-time emitter that turns a Claude Code JSONL transcript into an MP-3a-schema trace (transcript-native fields solid; `gh`/`git`-correlated fields best-effort, `unknown` when not derivable).

**Architecture:** POSIX `sh` + `jq` + `gh`/`git` (the `dora.sh` idiom: jq extracts/shapes, sh orchestrates, `gh --jq` correlates). To respect streaming over a 143 MB transcript, extraction is **two-stage**: stage-1 `jq` streams the big transcript emitting tiny per-line contribution records; stage-2 `jq -s` aggregates those (now small) records + joins tool_use↔tool_result by id. A committed synthetic fixture + `--selftest` makes the whole thing deterministically testable with no real-transcript or network dependency.

**Tech Stack:** `sh` (dash-clean), `jq` (already a hard-required kit prerequisite per `preflight.sh`), `gh`/`git` (optional at runtime — degrade to `unknown`). Spec: `docs/superpowers/specs/2026-06-12-agentic-ops-mp3a2-emitter-design.md`. Branch: `feature/agentic-ops-mp3a2` (spec already committed there).

---

## Exact transcript structure (verified against real transcripts)

Each JSONL line is one object. Relevant paths:
- Top-level: `.type` (`assistant`/`user`/…), `.timestamp` (ISO-8601), `.sessionId`, `.gitBranch`, `.message`.
- Token usage (on assistant lines): `.message.usage.input_tokens`, `.output_tokens`, `.cache_read_input_tokens`, `.cache_creation_input_tokens`.
- Tool call (in `.message.content[]`): `{type:"tool_use", id, name, input}`.
- Tool result (in a later line's `.message.content[]`): `{type:"tool_result", tool_use_id, is_error, content}` — `is_error` is `true` on failure, absent/null on success. Pairs to a `tool_use` by `tool_use_id == tool_use.id`.
- **Denial:** a `tool_result` with `is_error==true` whose `content` (stringified) matches the guard deny signature — case-insensitive `denied` AND one of `guard|control-plane|deny`.

---

## Conventions every task obeys
- `#!/bin/sh`, dash-clean (`dash -n` after each change). `set -eu`. Quote expansions.
- jq does all JSON shaping; **never** hand-parse JSON in sh. Correlation queries use `gh --jq`.
- Best-effort fields default to the JSON string `"unknown"` (or `null` for `parent.run.id`); the emitter never errors on missing `gh`/PR/branch.
- `--selftest` fixtures committed under `scripts/fixtures/`, left in place (7e guard, no `rm -rf`).
- Commit after each task (Conventional Commits).

---

## File Structure
- **Create** `scripts/fixtures/agent-trace-sample.jsonl` — the synthetic test transcript (the test input).
- **Create** `scripts/agent-trace.sh` — the emitter (arg parsing → extraction → correlation → assembly/output → `--selftest`).
- **Modify** `docs/operations/agentic-ops.md` — point the dev-time emitter section at the script; document the `unknown` sentinel + group-A/B/C provenance.
- **Hand-apply (control-plane, Bradley):** the kit-CI smoke step `agent-trace.sh --selftest`.

---

## Task 1: The fixture transcript (the test input)

**Files:** Create `scripts/fixtures/agent-trace-sample.jsonl`

A minimal synthetic transcript with hand-computable totals: 2 assistant lines (with usage + tool_use), 2 user lines (tool_results — one OK, one error; plus one denied), spanning two timestamps. **Token totals by construction:** input = 100+50 = 150; output = 20+10 = 30; cache_read = 5+0 = 5.

- [ ] **Step 1: Write the fixture**

```json
{"type":"assistant","sessionId":"sess-FIXTURE-001","gitBranch":"feature/x","timestamp":"2026-06-12T10:00:00.000Z","message":{"usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":5},"content":[{"type":"tool_use","id":"tu_read1","name":"Read","input":{"file_path":"a.txt"}},{"type":"tool_use","id":"tu_bash_ok","name":"Bash","input":{"command":"sh conformance/check-links.sh"}}]}}
{"type":"user","timestamp":"2026-06-12T10:00:01.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"tu_read1","content":"file contents"},{"type":"tool_result","tool_use_id":"tu_bash_ok","content":"OK: all relative Markdown links resolve"}]}}
{"type":"assistant","sessionId":"sess-FIXTURE-001","gitBranch":"feature/x","timestamp":"2026-06-12T10:00:05.000Z","message":{"usage":{"input_tokens":50,"output_tokens":10,"cache_read_input_tokens":0},"content":[{"type":"tool_use","id":"tu_bash_err","name":"Bash","input":{"command":"false"}},{"type":"tool_use","id":"tu_bash_denied","name":"Bash","input":{"command":"rm -rf /"}}]}}
{"type":"user","timestamp":"2026-06-12T10:00:06.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"tu_bash_err","is_error":true,"content":"exit 1"},{"type":"tool_result","tool_use_id":"tu_bash_denied","is_error":true,"content":"recursive delete is denied (control-plane integrity)"}]}}
```

- [ ] **Step 2: Verify it's valid JSONL**

Run: `while IFS= read -r l; do printf '%s' "$l" | jq -e . >/dev/null || echo BAD; done < scripts/fixtures/agent-trace-sample.jsonl && echo "all-valid"`
Expected: `all-valid` (no `BAD` lines).

- [ ] **Step 3: Commit**

```bash
git add scripts/fixtures/agent-trace-sample.jsonl
git commit -m "test(agent-trace): synthetic transcript fixture (hand-computable totals)"
```

---

## Task 2: Extraction stage + script skeleton + `--selftest` (TDD core)

**Files:** Create `scripts/agent-trace.sh`

Build the script with arg parsing, the two-stage jq extraction (group A), assembly to a partial trace, and the `--selftest` that asserts against the fixture. Implement the extraction by **iterating the jq until the selftest's exact assertions pass** — the assertions are the spec.

- [ ] **Step 1: Write the skeleton with the selftest assertions FIRST (they define done)**

Create `scripts/agent-trace.sh`. The `--selftest` runs the emitter over the fixture with `--no-correlate --stdout` and asserts the exact expected values:

```sh
#!/bin/sh
# agent-trace.sh — reference dev-time trace emitter (MP-3a.2).
# Turns a Claude Code JSONL transcript into an MP-3a-schema trace
# (docs/operations/agentic-ops.md). Transcript-native fields are solid; gh/git-
# correlated fields are best-effort (-> "unknown" when not derivable). It is a
# REFERENCE ADAPTER, not a conformance gate: it makes the trace exist, it does not
# judge behavior (that is MP-3b). sh + jq + gh, mirroring scripts/dora.sh.
#
# Usage:
#   scripts/agent-trace.sh <transcript.jsonl> [--agent-id ID] [--work-item ID] \
#       [--parent RUN_ID] [--price "IN,OUT"] [--out DIR] [--stdout] [--no-correlate]
#   scripts/agent-trace.sh --latest [flags]
#   scripts/agent-trace.sh --selftest
set -eu

AGENT_ID="claude-code"; WORK_ITEM="unknown"; PARENT="null"
PRICE=""; OUTDIR="traces"; STDOUT=0; CORRELATE=1; LATEST=0; TRANSCRIPT=""

# --- group-A extraction: tokens + timing (streaming; tiny awk aggregation) ---
extract_tokens_timing() {
  # echoes: "<in> <out> <cache_read> <start> <end>"
  _tok=$(jq -r 'select(.message.usage) | [
      (.message.usage.input_tokens // 0),
      (.message.usage.output_tokens // 0),
      (.message.usage.cache_read_input_tokens // 0)] | @tsv' "$1" \
    | awk '{i+=$1; o+=$2; c+=$3} END{printf "%d %d %d", i, o, c}')
  _times=$(jq -r 'select(.timestamp) | .timestamp' "$1" | sort)
  _start=$(printf '%s\n' "$_times" | head -1)
  _end=$(printf '%s\n' "$_times" | tail -1)
  printf '%s %s %s' "$_tok" "$_start" "$_end"
}

# --- group-A extraction: tool steps (two-stage: stream-extract -> slurp-join) ---
# Stage 1 streams the big transcript into two small NDJSON streams; stage 2 slurps
# (small) and joins tool_use to tool_result by id, preserving tool_use order.
extract_steps() {
  _uses=$(jq -c 'select(.message.content) | .message.content[]?
      | select(.type=="tool_use") | {id, name}' "$1")
  _results=$(jq -c 'select(.message.content) | .message.content[]?
      | select(.type=="tool_result")
      | {tid: .tool_use_id, err: (.is_error // false),
         denied: ((.is_error // false) and
                  ((.content|tostring|ascii_downcase) | test("denied")) and
                  ((.content|tostring|ascii_downcase) | test("guard|control-plane|deny")))}' "$1")
  # join: build a {tid: {err,denied}} map from results, map over uses in order.
  printf '%s\n' "$_results" | jq -s '
      (reduce .[] as $r ({}; .[$r.tid] = {err:$r.err, denied:$r.denied})) as $m
      | $m' > /tmp/_at_map.$$ 2>/dev/null || echo '{}' > /tmp/_at_map.$$
  printf '%s\n' "$_uses" | jq -s --slurpfile m /tmp/_at_map.$$ '
      ($m[0] // {}) as $res
      | [ .[] | . as $u | ($res[$u.id] // {err:false,denied:false}) as $r
          | {name: $u.name,
             outcome: (if $r.denied then "denied" elif $r.err then "error" else "ok" end),
             retries: 0} ]'
  rm -f /tmp/_at_map.$$ 2>/dev/null || true
}
```

(NOTE for the implementer: the `/tmp` temp + `rm -f` here is the emitter's own runtime scratch, not a fixture — it is fine to remove its own temp file. Do NOT `rm` mktemp *fixtures* in `--selftest`.)

Continue the script with assembly + the selftest:

```sh
# --- assemble the trace JSON (jq builds it; never hand-build JSON in sh) ---
emit() {
  _t="$1"
  set -- $(extract_tokens_timing "$_t")   # in out cache start end
  _in=$1; _out=$2; _cache=$3; _start=$4; _end=$5
  _steps=$(extract_steps "$_t")
  _run=$(jq -r 'select(.sessionId) | .sessionId' "$_t" | head -1)
  [ -n "$_run" ] || _run=$(basename "$_t" .jsonl)
  _cost=$(compute_cost "$_in" "$_out")    # echoes a number or the string unknown

  # correlation (group B) — best-effort; "unknown" unless --correlate succeeds
  _pr="unknown"; _reviews="unknown"; _outcome="unknown"
  if [ "$CORRELATE" -eq 1 ]; then correlate; fi   # sets _pr/_reviews/_outcome

  jq -n \
    --arg agent "$AGENT_ID" --arg run "$_run" --arg wi "$WORK_ITEM" \
    --argjson parent "$([ "$PARENT" = null ] && echo null || printf '"%s"' "$PARENT")" \
    --arg start "$_start" --arg end "$_end" \
    --argjson tin "$_in" --argjson tout "$_out" --argjson tcache "$_cache" \
    --arg cost "$_cost" \
    --arg pr "$_pr" --arg reviews "$_reviews" --arg outcome "$_outcome" \
    --argjson steps "$_steps" '
    {
      "agent.id": $agent, "run.id": $run, "work_item.id": $wi, "parent.run.id": $parent,
      start: $start, end: $end,
      tokens: {in: $tin, out: $tout, cache_read: $tcache},
      cost: ($cost | (tonumber? // .)),
      outcome: $outcome, "pr.ref": $pr, "review.rounds": ($reviews | (tonumber? // .)),
      "gates.hit": [], "gates.skipped": "unknown", "tests.written": "unknown",
      steps: $steps
    }'
}

compute_cost() {  # $1=in $2=out ; cost only when --price "IN,OUT" (per-Mtok) is given.
  # No built-in model→price table: prices drift and baking them into the kit is
  # maintenance debt. Tokens are always emitted (the objective fact); cost is
  # "unknown" unless the caller supplies --price. (YAGNI; honest over stale.)
  [ -n "$PRICE" ] || { echo "unknown"; return; }
  _pin=${PRICE%,*}; _pout=${PRICE#*,}
  awk -v i="$1" -v o="$2" -v pi="$_pin" -v po="$_pout" \
    'BEGIN{printf "%.4f", (i/1000000*pi)+(o/1000000*po)}'
}

correlate() {  # best-effort gh/git; never fail the run
  command -v gh >/dev/null 2>&1 || return 0
  _br=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
  _j=$(gh pr view "$_br" --json number,url,reviews 2>/dev/null) || return 0
  [ -n "$_j" ] || return 0
  _pr=$(printf '%s' "$_j" | jq -r '.url // "unknown"')
  _reviews=$(printf '%s' "$_j" | jq -r '.reviews | length | tostring')
  _state=$(gh pr view "$_br" --json state --jq '.state' 2>/dev/null || echo "")
  case "$_state" in MERGED) _outcome="completed";; OPEN) _outcome="handoff";; *) _outcome="unknown";; esac
}

selftest() {
  st_fail=0
  fixture="$(dirname "$0")/fixtures/agent-trace-sample.jsonl"
  CORRELATE=0
  out=$(emit "$fixture")
  # token sums (fixture: in=150, out=30, cache=5)
  [ "$(printf '%s' "$out" | jq -r '.tokens.in')" = "150" ]  || { echo "selftest FAIL: tokens.in"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.tokens.out')" = "30" ]  || { echo "selftest FAIL: tokens.out"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.tokens.cache_read')" = "5" ] || { echo "selftest FAIL: cache"; st_fail=1; }
  # required-core keys present
  for k in '"run.id"' '"agent.id"' 'start' 'end' 'outcome' 'steps'; do
    [ "$(printf '%s' "$out" | jq -e "has(${k})" 2>/dev/null)" = "true" ] || { echo "selftest FAIL: missing $k"; st_fail=1; }
  done
  # step outcomes: 4 steps, ok/ok/error/denied in order
  [ "$(printf '%s' "$out" | jq -r '.steps | length')" = "4" ] || { echo "selftest FAIL: step count"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.steps[2].outcome')" = "error" ]  || { echo "selftest FAIL: error step"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.steps[3].outcome')" = "denied" ] || { echo "selftest FAIL: denied step"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.["run.id"]')" = "sess-FIXTURE-001" ] || { echo "selftest FAIL: run.id"; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then echo "agent-trace --selftest: FAIL" >&2; return 1; fi
  echo "agent-trace --selftest: OK (tokens/steps/outcomes/run.id all match the fixture)"
  return 0
}
```

Then arg parsing + dispatch (`--selftest` → `selftest`; `--latest` → resolve newest `*.jsonl` under `${CLAUDE_PROJECT_DIR:-$HOME/.claude/projects}` matching the cwd slug; else `TRANSCRIPT=$1`). On a normal run: if `--stdout`, print `emit "$TRANSCRIPT"`; else `mkdir -p "$OUTDIR"` and write to `"$OUTDIR/$_run.json"`.

- [ ] **Step 2: Iterate the jq until the selftest passes**

Run: `sh scripts/agent-trace.sh --selftest`
Expected: `agent-trace --selftest: OK (...)`. If any `selftest FAIL:` line appears, fix the corresponding jq/awk until all assertions pass. (The fixture's hand-computed values are the contract.)

- [ ] **Step 3: dash-clean**

Run: `dash -n scripts/agent-trace.sh && echo dash-clean`
Expected: `dash-clean`.

- [ ] **Step 4: Commit**

```bash
git add scripts/agent-trace.sh
git commit -m "feat(scripts): agent-trace.sh — transcript→MP-3a-schema emitter + selftest"
```

---

## Task 3: Real-transcript smoke (DoD — prove it on real data)

**Files:** none (verification only)

- [ ] **Step 1: Emit a trace from a real kit transcript**

Run (pick a small real transcript to keep output readable):
```bash
real=$(ls -S "$HOME/.claude/projects/-Users-bradleyjames-Development-agentic-sdlc-kit/"*.jsonl | tail -2 | head -1)
sh scripts/agent-trace.sh "$real" --stdout --no-correlate | jq '{run:."run.id", start, end, tokens, steps: (.steps|length), first3: (.steps[0:3]|map(.name+":"+.outcome))}'
```
Expected: a JSON object with a real `run.id`, non-empty `start`/`end`, positive `tokens.in/out`, a positive step count, and the first few `Tool:outcome` pairs looking sane (e.g. `Read:ok`, `Bash:ok`). If `tokens` are 0 or `steps` is 0 on a real transcript, the extraction paths are wrong — fix before proceeding.

- [ ] **Step 2: Spot-check correlation (best-effort, on this branch)**

Run: `sh scripts/agent-trace.sh "$real" --stdout | jq '{outcome, pr:."pr.ref", reviews:."review.rounds"}'`
Expected: either real values (if a PR exists for the branch) or `"unknown"` — **never an error/crash**. Confirms graceful degradation.

*(No commit — verification only. If issues found, fix in Task 2 and re-commit there.)*

---

## Task 4: Docs — point agentic-ops.md at the working emitter

**Files:** Modify `docs/operations/agentic-ops.md`

- [ ] **Step 1: Update the dev-time emitter bullet**

In the "Emitters" section, replace the sentence that says the working reference emitter "is MP-3a.2" / "until then…" with a pointer to the shipped script:

```markdown
- **Dev-time (reference adapter):** Claude Code writes a JSONL session transcript (tool calls, outcomes, token usage). **`scripts/agent-trace.sh`** derives an MP-3a-schema trace from it — transcript-native fields (timing, tokens, cost, the tool-step sequence with `ok`/`error`/`denied` outcomes) are solid; `gh`/`git`-correlated fields (`pr.ref`, `review.rounds`, `outcome`, gates/tests) are **best-effort, set to `unknown` when not derivable** (never fabricated). Run `scripts/agent-trace.sh --latest --stdout` for this repo's newest session, or pass a transcript path. A Gemini-CLI / Codex / Aider shop writes its own equivalent adapter against the same schema.
```

- [ ] **Step 2: Add an `unknown`-sentinel note** near the schema (one line):

```markdown
> **The `unknown` sentinel.** An emitter that cannot derive a field records the literal `unknown` (or `null` for `parent.run.id`) rather than guessing — honesty over false precision. MP-3b treats `unknown` as missing, not as a value.
```

- [ ] **Step 3: Update the Roadmap line** — change "MP-3a.2: the working Claude Code dev-time emitter …" to mark it **done** (`scripts/agent-trace.sh`), keeping MP-3b as next.

- [ ] **Step 4: Verify links + budget**

Run: `sh conformance/check-links.sh && sh conformance/doc-budget.sh`
Expected: links OK; doc-budget OK (agentic-ops.md is not budget-capped, but confirm core-3 unaffected).

- [ ] **Step 5: Commit**

```bash
git add docs/operations/agentic-ops.md
git commit -m "docs(operations): point agentic-ops emitter section at scripts/agent-trace.sh"
```

---

## Task 5: Prepare the control-plane CI smoke step (hand-apply for Bradley)

**Files:** Hand-apply (Bradley): `.github/workflows/ci.yml`

- [ ] **Step 1: Produce the exact step** (mirrors the existing `DORA collector smoke` step in the `conformance:` job):

```yaml
      - name: Agent-trace emitter smoke (selftest over fixture)
        run: sh scripts/agent-trace.sh --selftest
```

- [ ] **Step 2: Surface it in the PR body** under "⚠️ One control-plane hand-apply", with:
```bash
KIT_GUARD_SELFEDIT=1 git add .github/workflows/ci.yml
git commit -m "ci(kit): run agent-trace selftest smoke in kit pipeline"
```

*(No repo change in this task.)*

---

## Task 6: Final verification + independent review + PR

- [ ] **Step 1: Full sweep**

Run:
```bash
sh scripts/agent-trace.sh --selftest
dash -n scripts/agent-trace.sh && echo dash-clean
sh conformance/check-links.sh
sh conformance/verify.sh | tail -3
```
Expected: selftest OK; dash-clean; links OK; `verify.sh` → RESULT: OK (unchanged — this slice adds no conformance check).

- [ ] **Step 2: Independent review (builder ≠ sole reviewer)**

Dispatch a reviewer subagent over the diff. Focus: (a) jq correctness — token aggregation, the tool_use↔tool_result id-join, denial classification; (b) the emitter never errors on missing `gh`/PR/branch (degrades to `unknown`); (c) no JSON hand-parsed in sh; (d) dash-cleanliness + `set -eu` safety (the `set -- $(...)` word-split in `emit` is intentional and safe for the numeric/ISO fields — confirm); (e) honesty: no fabricated `gates.skipped`/`outcome`.

- [ ] **Step 3: Address findings, then PR**

```bash
git push -u origin feature/agentic-ops-mp3a2
gh pr create --title "feat(agentic-ops): MP-3a.2 — dev-time trace emitter (scripts/agent-trace.sh)" --body "<summary + field-provenance + honesty + the Task-5 control-plane snippet + merge command>"
```
Report the PR number + `gh pr merge <n> --squash --admin --delete-branch`. **Do not self-merge.**

---

## Self-review (plan author)

- **Spec coverage:** §3 architecture → Tasks 2 (two-stage extraction) + skeleton. §4 field mapping → Task 2 (`emit`/`extract_*`) Group A, `correlate` Group B, flags Group C. §5 interface → Task 2 arg parsing. §6 selftest → Tasks 1–2. §7 honesty (`unknown`, not a gate) → Task 2 assembly defaults + Task 4 docs. §8 out-of-scope → respected (no MP-3b, no new conformance check). §9 DoD → Tasks 2 (emitter+selftest), 1 (fixture), 3 (real-transcript spot-check), 4 (docs), 5 (CI), 6 (review+PR). **No gaps.**
- **Placeholder scan:** none. `compute_cost` is fully coded (cost via `--price`, else `unknown`); the built-in price table was deliberately descoped (YAGNI + avoids shipping stale model prices) — a refinement over spec §4's "built-in map", noted here so the spec and plan agree: **tokens always emitted; cost is `--price`-driven, `unknown` otherwise.**
- **Consistency:** field keys (`run.id`, `tokens.in/out/cache_read`, `steps[].outcome`) match the fixture's hand-computed values and the §4 schema across Tasks 1, 2, 3.
