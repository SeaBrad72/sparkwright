# adapters/gemini/

Floor-only adapter for **Gemini CLI**, which reads `GEMINI.md` for project context and `.gemini/settings.json` for config, but provides no inline pre-exec guard the kit can drive.

## What this adapter declares

Every dimension is at the Kit-enforced **floor**; `mcp-gate` is `n-a`:

| Dimension | Level | Enforced by |
|-----------|-------|-------------|
| context-binding | floor | `AGENTS.md` present + routes to canonical docs |
| command-guard | floor | `hooks/pre-push` + `scripts/kit-guard` + `conformance/agent-boundary.sh` |
| history-protection | floor | `hooks/pre-push` (force-push / push-to-main guard) |
| review-roles | floor | `conformance/agent-boundary.sh` + `conformance/branch-protection.sh` |
| mcp-gate | n-a | No MCP surface wired for this adapter |

## Adopting with Gemini CLI

Gemini CLI reads `GEMINI.md` for project context and `.gemini/settings.json` for configuration. Add a project `GEMINI.md` that includes or points at `AGENTS.md` so Gemini loads the kit's canonical context. `GEMINI.md` and `.gemini/` are Gemini's control surface and are declared in this adapter's `controlPlanePaths`.

## What "floor-only" means

Enforcement holds through the universal governance layer — the `pre-push` git hook and the CI `agent-boundary` gate — which fire **regardless of which AI runtime issued the action**. There is **no harness-native inline interception** for Gemini CLI (no Claude-Code-`PreToolUse` equivalent). That is an honest ceiling, not a gap: the floor is the equal-enforcement guarantee every harness clears.

## In a shared multi-harness repo

If one repo is driven by Gemini CLI **and** Claude/other harnesses, there is **one shared control plane**, not a per-harness sandbox:

- **Register every harness you use** (keep its `adapters/<h>/` present). The CI `agent-boundary` gate protects the **union** of all present adapters' `controlPlanePaths` — so each harness's own control surface (`.claude/`, `.cursor/rules/`, `GEMINI.md`, …) is ratification-gated for **all** harnesses.
- **The git chokepoints equalize callers:** a control-plane change by Gemini CLI is blocked at `git push` and at the PR exactly as Claude's would be.
- **Real-time inline protection is asymmetric:** Claude is stopped at the keystroke; Gemini CLI is stopped at push/PR. For inline coverage of Gemini CLI's shell commands, install the caller-agnostic shims: `sh scripts/kit-guard install-shims` (shell commands only, not Gemini CLI's direct file-writes — those are caught at push/PR).

## Self-verify (the adopter-verified half)

Drive Gemini CLI through the floor in a real repo and confirm it blocks: attempt a control-plane edit (e.g. change `.github/workflows/`) and open a PR → the `control-plane-ratification` gate must block it; attempt `git push` to `main` → the `pre-push` hook must refuse. **You verify this for your harness; the kit does not claim it for you.**

## Coverage ceiling

- [`docs/operations/harness-adapters.md`](../../docs/operations/harness-adapters.md) — boundary contract + dimension table
- [`docs/operations/runtime-guards.md`](../../docs/operations/runtime-guards.md) — per-harness guard coverage matrix
- [`docs/operations/harness-enforcement-evidence.md`](../../docs/operations/harness-enforcement-evidence.md) — what is maintainer-verified vs adopter-verified
