# adapters/

One subdirectory per harness. Each holds:
- `adapter.json` — the declarative manifest (schema in [`docs/operations/harness-adapters.md`](../docs/operations/harness-adapters.md))
- `README.md` — harness-specific notes

## What an adapter is

An adapter is a thin, harness-native binding that *references* the repo's universal governance layer. It declares which dimensions the harness covers natively, which stay at the floor, and where conformance checks live. It does **not** copy or fork any policy or process.

## Adapters

| Adapter | Description |
|---------|-------------|
| `adapters/claude-code/` | Reference adapter — Claude Code with native hooks, MCP policy, and subagents. |
| `adapters/generic/` | Floor-only adapter for any other AGENTS.md-reading harness with no inline guard (Copilot, …). |
| `adapters/codex/` | Floor-only adapter for **OpenAI Codex CLI** (reads `AGENTS.md`). |
| `adapters/cursor/` | Floor-only adapter for **Cursor** (reads `.cursor/rules/*.mdc`). |
| `adapters/gemini/` | Floor-only adapter for **Gemini CLI** (reads `GEMINI.md` + `.gemini/`). |

`incept --harness <list>` (default `claude-code`) selects which adapter(s) a project targets and runs the conformance check for each.

## The shared floor

Every **floor-only** adapter (`codex`, `cursor`, `gemini`, `generic`, and any harness scaffolded by `scripts/new-adapter.sh`) shares everything below. Each `adapters/<harness>/README.md` carries only its **delta** — what that harness reads, how to wire it, and its own honest ceiling — and points back here for the rest.

**What "floor-only" means.** Enforcement holds through the **universal governance layer** — the `pre-push` git hook and the CI `agent-boundary` gate — which fire **regardless of which AI runtime issued the action**. A floor-only harness has **no harness-native inline interception** (no Claude-Code-`PreToolUse` equivalent): it is stopped at `git push` once the pre-push hook is installed, and at the PR unconditionally — not at the keystroke. That is an honest ceiling, not a gap — the floor is the equal-enforcement guarantee every harness clears.

**What a floor-only adapter declares** — every dimension at the Kit-enforced floor, `mcp-gate` `n-a`:

| Dimension | Level | Enforced by |
|-----------|-------|-------------|
| context-binding | floor | `AGENTS.md` present + routes to canonical docs |
| command-guard | floor | `hooks/pre-push` + `scripts/kit-guard` + `conformance/agent-boundary.sh` |
| history-protection | floor | `hooks/pre-push` (force-push / push-to-main guard) |
| review-roles | floor | `conformance/agent-boundary.sh` + `conformance/branch-protection.sh` |
| mcp-gate | n-a | No MCP surface wired for this adapter |
| orchestration | floor | the four seat definitions present (`agents/*.agent.md`) |
| model-tiering | floor | `conformance/model-tiering.sh` |

**In a shared multi-harness repo there is ONE control plane, not a per-harness sandbox — and it is protected in two layers, only one of which depends on a manifest:**

1. **The kit's own control-plane floor is UNCONDITIONAL — manifest or not.** `conformance/agent-boundary.sh` classifies a path as control-plane if **guard-core's hardcoded set** knows it: `.claude/`, `.github/workflows/`, `conformance/`, `skills/`, `adapters/`, `scripts/`, `profiles/`, `agents/*.agent.md`, `CODEOWNERS`, `hooks/pre-push`, `scripts/kit-guard`, `.gitattributes`, the governing docs, and the meta-control marker + log — **among others; the full set is compiled into `guard-core.sh`, and this list is a subset, not the enumeration.** That set is compiled into the guard, so it holds for **every** harness and every caller **whether or not any adapter is registered**, and **no manifest can shrink it**. Registering (or removing) an adapter never changes whether `.claude/` — or any other floor path — is protected.
2. **A harness's own surface *beyond* that floor is union-derived, and gated only while its declaring adapter is present.** `.cursor/rules/`, `GEMINI.md` and `.gemini/` are **not** in the hardcoded floor. They are protected because the adapter that declares them in `controlPlanePaths` (`adapters/cursor/`, `adapters/gemini/`) is present in the tree, and the gate protects the **union** of every present adapter's declared paths. Delete that adapter directory and its extra paths leave the union — the floor is unaffected, but that harness's private surface is no longer ratification-gated.

The rule that follows: **register every harness you actually use** (keep its `adapters/<h>/` present). That is what extends protection over each harness's *own* control surface for **all** harnesses. And **the git chokepoints equalize callers** either way: a control-plane change made by any harness is blocked at `git push` once the pre-push hook is installed, and at the PR unconditionally, exactly as Claude's would be.

**Self-verify (the adopter-verified half).** Drive your harness through the floor in a real repo and confirm it blocks: attempt a control-plane edit (e.g. change `.github/workflows/`) and open a PR → the `control-plane-ratification` gate must block it; attempt `git push` to `main` → the `pre-push` hook must refuse. **You verify this for your harness; the kit does not claim it for you.**

**Coverage ceiling** — the three documents that bound what any adapter can claim:

- [`docs/operations/harness-adapters.md`](../docs/operations/harness-adapters.md) — boundary contract + the 7-dimension table
- [`docs/operations/runtime-guards.md`](../docs/operations/runtime-guards.md) — per-harness guard coverage matrix
- [`docs/operations/harness-enforcement-evidence.md`](../docs/operations/harness-enforcement-evidence.md) — what is maintainer-verified vs adopter-verified

## Reference adapter

`adapters/claude-code/` is the reference adapter. It references the live `.claude/` governance layer in this repo — the files there are **not** duplicated here.

## BYO — adding a new harness

Any harness is supported. Run:

```sh
sh scripts/new-adapter.sh <harness-name>
```

This scaffolds `adapters/<harness>/{adapter.json,README.md}` from the `adapters/_TEMPLATE/` skeleton — floor-only, conforms immediately. Customize `controlPlanePaths` for the harness's namespace, point `contextFile` at the document that harness actually auto-loads (the scaffold ships `AGENTS.md`), and upgrade any dimension to `"native"` with a `proof` when the harness supports inline interception. Validate with:

```sh
sh conformance/harness-adapter.sh adapters/<harness>
```

This is the same guided, validated workflow that `scripts/new-profile.sh` provides for stacks.

## Contract

The adapter boundary contract — the 7-dimension table, manifest schema, and conformance rules — is in `docs/operations/harness-adapters.md`. The dimension set is **closed**: a manifest key outside the seven is a FAIL, because the Kit enforces no floor for it.

`contextFile` is a **required** top-level field naming the document that harness auto-loads (`claude-code` → `CLAUDE.md`; the rest → `AGENTS.md`). An **absent** `contextFile` is a FAIL, never a default — a default would silently rebind every future adapter to a file its harness may never read. The value is boundary-validated: bare relative path; no empty, `.` or `.git` component; no symlink; a regular file; and tracked wherever the repo has a populated index (git absent or no repo is UNVERIFIED, never a pass). The entry contract (§1) must be **byte-identical in every adapter's declared `contextFile`** — enforced by `conformance/agents-brief.sh`, which compares the first `## ` section of every declared document byte for byte (a marker-grep would be satisfied by keeping the heading and appending underneath it). The invariant is per-adapter and the set is derived from the manifests, so adding a harness costs exactly: declare `contextFile`, put §1 in it, and add nothing between §1 and the next `## `. Full rules + the `cursor` / `gemini` residuals: `docs/operations/harness-adapters.md`.
