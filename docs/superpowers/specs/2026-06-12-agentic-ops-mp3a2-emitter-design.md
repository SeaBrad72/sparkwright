# Agentic-Ops MP-3a.2 — Dev-Time Trace Emitter — Design

**Status:** approved (brainstorm), ready for implementation planning
**Arc:** Modern Practices, Slice MP-3a.2 (emitter). Depends on MP-3a (the trace contract, merged #73). Feeds MP-3b (behavior→tier loop).

---

## 1. Problem & context

MP-3a froze the trace **contract** (the OTel-GenAI-anchored schema in `docs/operations/agentic-ops.md`) and shipped `agentops-ready.sh` (declares the discipline). What it did *not* ship is a working **emitter** — so today there are no actual traces. MP-3a.2 builds the **reference dev-time emitter**: the Claude Code *adapter* that turns a session JSONL transcript into a schema-conformant trace.

Why it matters: the kit is built *by* an agent following its own loop. The emitter run over the kit's own session transcripts produces real traces — the **calibration corpus MP-3b needs** to set behavior thresholds from data, not guesswork. It also makes the kit's "dogfoods its own loop" claim (`MAINTAINING.md` §5) *measurable*, and is the concrete "reference adapter" proving the schema maps to a real harness.

## 2. Settled decisions (from brainstorm)

- **Language: POSIX `sh` + `jq` + `gh`/`git`.** `jq` is already a hard-required universal kit prerequisite (`preflight.sh`); `python3` is only required on the Python/ML/data stacks, so Python would add a universal dependency. `dora.sh` is direct precedent (JSON + date-math + aggregation + `gh` correlation in sh+jq). Keeps the kit's tooling uniform.
- **Fidelity: transcript core + best-effort correlation.** Solidly extract every transcript-native field; do a best-effort `gh`/`git` enrichment for the rest; mark any field it cannot determine as **`unknown`** (never error).
- **It is a *tool*, not a conformance gate.** Lives in `scripts/`, validated by its own `--selftest` over a committed fixture (mirrors `dora.sh`'s CI smoke). No new `conformance/*.sh`.

## 3. Architecture & components

One script, `scripts/agent-trace.sh` (`#!/bin/sh`, dash-clean), three internal stages + I/O:

1. **Arg/input resolution** — accept a transcript path, or `--latest` (newest `*.jsonl` in the Claude Code project dir, default `~/.claude/projects/<cwd-slug>/`). Flags: `--agent-id <id>` (default `claude-code`), `--work-item <id>`, `--parent <run-id>`, `--price "<in>,<out>"` (per-Mtok override), `--stdout`, `--out <dir>` (default `traces/`), `--selftest`.
2. **Transcript extraction (jq over the JSONL stream)** — produces the transcript-native fields (§4 group A). Streams line-by-line (`jq -c`), so the 143 MB transcript is fine. `tool_use`↔`tool_result` paired by `id` (`tool_use.id` = `tool_result.tool_use_id`).
3. **Best-effort correlation (`gh`/`git`)** — fills §4 group B where derivable from the current branch (a merged/open PR, review count, gate/test inference), each defaulting to `unknown`. Never fails the run if `gh` is absent or there's no PR.
4. **Assembly + output (jq)** — merge A+B into one MP-3a-schema JSON object; write `traces/<run.id>.json` (or `--stdout`).

Boundary discipline (mirrors `dora.sh`): **jq does extraction/shaping; sh orchestrates; `gh --jq` does the correlation queries.** No value is hand-parsed from JSON in sh.

## 4. Field mapping (transcript → MP-3a schema)

**Group A — transcript-native (always populated):**

| Schema field | Source |
|---|---|
| `run.id` | the transcript filename UUID (session id) |
| `start` · `end` | min / max `timestamp` across lines |
| `tokens.in` · `tokens.out` | sum of `message.usage.input_tokens` / `output_tokens` over assistant lines; `tokens.cache_read` summed separately |
| `cost` | `tokens × price`; built-in map for the default Claude models (opus/sonnet/haiku) + `--price` override; **`unknown`** if model unrecognized and no override |
| tool-step list | each `tool_use` (ordered): `tool.name`; `tool.outcome` = `error` if the paired `tool_result.is_error` else `ok`; `denied` when a guard `hook_blocking_error` / permission-deny is the result; `retries` = count of error→same-tool-retry |

**Group B — best-effort `gh`/`git` correlation (`unknown` when not derivable):**

| Schema field | Derivation |
|---|---|
| `pr.ref` | `gh pr view --json number,url` for the current branch |
| `review.rounds` | distinct review submissions on that PR (`gh pr view --json reviews`) |
| `outcome` | merged PR → `completed`; open PR → `handoff`; none → `unknown` (never guessed as error) |
| `gates.hit[]` | scan Bash steps for executed `conformance/*.sh` / `npm test` / `*test*` commands |
| `gates.skipped[]` | **`unknown`** by default (a non-run is not observable from a transcript) — documented limitation, not faked |
| `tests.written` | `true` if any Edit/Write step targeted a test path; else `unknown` |

**Group C — caller-supplied identity (flags):** `agent.id` (`--agent-id`, default `claude-code`), `work_item.id` (`--work-item`, else `unknown`), `parent.run.id` (`--parent`, else `null`).

## 5. Interface

```
scripts/agent-trace.sh <transcript.jsonl> [--agent-id ID] [--work-item ID]
                       [--parent RUN_ID] [--price "IN,OUT"] [--out DIR]
                       [--stdout] [--no-correlate]
scripts/agent-trace.sh --latest [flags]      # newest transcript for this repo
scripts/agent-trace.sh --selftest            # parse a committed fixture, assert schema
```

`--no-correlate` skips the `gh`/`git` enrichment stage entirely (group-B fields → `unknown`); used by `--selftest` for determinism and available to anyone wanting a transcript-only trace.

Output: a single JSON object conforming to the MP-3a required-core (+ recommended where available). Exit `0` on success (including when correlated fields are `unknown`), `1` on a real failure (unreadable transcript, malformed JSON throughout), `2` on bad usage.

## 6. Testing — fixture-driven `--selftest`

A tiny **committed fixture transcript** `scripts/fixtures/agent-trace-sample.jsonl` (a handful of synthetic JSONL lines: two assistant messages with `usage` + `tool_use` blocks, matching `tool_result`s incl. one `is_error` and one guard-denied, spanning two timestamps). `--selftest`:
1. runs the emitter over the fixture (`--stdout`, no git correlation — pass `--no-correlate` or run outside a repo context),
2. asserts the output JSON has every **required-core** key (`run.id`, `start`, `end`, `tokens.in`, `tokens.out`, `outcome`, tool-step list with `name`/`outcome`),
3. asserts the known-error step has `outcome: error`, the denied step has `outcome: denied`, and token sums match the fixture's hand-computed totals,
4. leaves fixtures in place (7e guard).

Deterministic, no dependence on real transcripts or network/`gh`. Wired into kit CI as a smoke step (mirrors `dora.sh --selftest` — control-plane, hand-applied).

## 7. Honesty boundary

- The emitter produces a trace **as faithfully as the transcript + git allow**; correlated fields are explicitly `unknown` when not derivable — it never fabricates `gates.skipped` or guesses `outcome: error`. The `unknown` sentinel is first-class, documented in `agentic-ops.md`.
- It is a **reference adapter, not a conformance gate** — running it proves nothing about whether the agent behaved; that is MP-3b's (trend-scored) job. The emitter just makes the trace exist.
- Single-harness by construction: it parses Claude Code's format. A Cursor/Codex/Aider shop writes its own adapter against the same schema (the portability split stated in `agentic-ops.md`).

## 8. Out of scope

- **No behavior scoring / tier logic** — that's MP-3b.
- **No real-time hook** — it's a post-hoc batch emitter over a completed transcript (a live PostToolUse hook emitter is a possible future, not now).
- **No new `conformance/*.sh`** — validated by `--selftest`, not a gate.
- **No multi-transcript aggregation / dashboards** — one transcript → one trace; aggregation is a consumer concern (MP-3b).
- **No runtime/OTel emitter** — that's the product-agent adapter, documented in agentic-ops.md but not built here.

## 9. Definition of Done

- `scripts/agent-trace.sh` (sh+jq+gh, dash-clean) emitting a required-core-conformant trace from a real transcript, with best-effort correlation and `unknown` for gaps.
- `scripts/fixtures/agent-trace-sample.jsonl` + `--selftest` (schema + outcome + token-sum assertions), fixtures left in place.
- `docs/operations/agentic-ops.md` updated: the emitter section points at `scripts/agent-trace.sh` as the working dev-time reference adapter (replacing "MP-3a.2 will ship…"), documents the `unknown` sentinel and the group-A/B/C field provenance.
- Kit-CI smoke step (`agent-trace.sh --selftest`) prepared as a control-plane hand-apply.
- Independent review (builder ≠ sole reviewer) → SHIP; PR ratified by Bradley; MINOR release.
- A real trace generated from one of the kit's own transcripts and spot-checked (the first corpus entry for MP-3b).
