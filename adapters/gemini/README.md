# adapters/gemini/

Floor-only adapter for **Gemini CLI**, which reads `GEMINI.md` for project context and `.gemini/settings.json` for config, but provides no inline pre-exec guard the kit can drive.

## Adopting with Gemini CLI

Gemini CLI reads `GEMINI.md` for project context and `.gemini/settings.json` for configuration. Add a project `GEMINI.md` that includes or points at `AGENTS.md` so Gemini loads the kit's canonical context. `GEMINI.md` and `.gemini/` are Gemini's own control surface: they are **not** part of the kit's hardcoded floor, and they are ratification-gated only because this adapter declares them in `controlPlanePaths` and this directory is present (see the union rule in the shared floor).

## The honest ceiling for Gemini CLI

There is **no harness-native inline interception** for Gemini CLI (no Claude-Code-`PreToolUse` equivalent). Claude is stopped at the keystroke; **Gemini CLI is stopped at `git push` and at the PR — not at the keystroke.** For inline coverage of Gemini CLI's *shell* commands, install the caller-agnostic shims: `sh scripts/kit-guard install-shims` (shell commands only, **not** Gemini CLI's direct file-writes — those are caught at push/PR). Drive Gemini CLI through the floor in a real repo and confirm it blocks. **You verify this for your harness; the kit does not claim it for you.**

## Everything else is the shared floor

The dimension table, what "floor-only" means, the shared-control-plane / union rule, the self-verify recipe, and the coverage-ceiling links are common to every floor-only adapter and live once in [`../README.md`](../README.md) — *"The shared floor"*.
