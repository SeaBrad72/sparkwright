# adapters/codex/

Floor-only adapter for **OpenAI Codex CLI**, which reads `AGENTS.md` as its project-instructions file (Codex's equivalent of `CLAUDE.md`) but provides no inline pre-exec guard.

## Adopting with Codex

Codex loads `AGENTS.md` from the repo root on the first turn — the kit's `AGENTS.md` brief routes to the canonical docs, so no extra wiring is needed. Codex's per-user config lives at `~/.codex/config.toml`, **outside the repo**, so unlike `cursor` and `gemini` this adapter declares no in-repo Codex namespace in `controlPlanePaths` — there is nothing in the tree to gate.

## The honest ceiling for Codex

There is **no harness-native inline interception** for Codex (no Claude-Code-`PreToolUse` equivalent). Claude is stopped at the keystroke; **Codex is stopped at `git push` and at the PR — not at the keystroke.** For inline coverage of Codex's *shell* commands, install the caller-agnostic shims: `sh scripts/kit-guard install-shims` (shell commands only, **not** Codex's direct file-writes — those are caught at push/PR). Drive Codex through the floor in a real repo and confirm it blocks. **You verify this for your harness; the kit does not claim it for you.**

## Everything else is the shared floor

The dimension table, what "floor-only" means, the shared-control-plane / union rule, the self-verify recipe, and the coverage-ceiling links are common to every floor-only adapter and live once in [`../README.md`](../README.md) — *"The shared floor"*.
