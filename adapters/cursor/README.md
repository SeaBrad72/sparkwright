# adapters/cursor/

Floor-only adapter for **Cursor**, which reads project rules from `.cursor/rules/` but provides no inline pre-exec guard the kit can drive.

## Adopting with Cursor

Cursor reads project rules from `.cursor/rules/*.mdc` (the single-file `.cursorrules` form is deprecated and silently ignored in Agent mode). Add a rule file under `.cursor/rules/` that points at `AGENTS.md` so Cursor loads the kit's canonical context. `.cursor/rules/` is Cursor's own control surface: it is **not** part of the kit's hardcoded floor, and it is ratification-gated only because this adapter declares it in `controlPlanePaths` and this directory is present (see the union rule in the shared floor).

## The honest ceiling for Cursor

There is **no harness-native inline interception** for Cursor (no Claude-Code-`PreToolUse` equivalent). Claude is stopped at the keystroke; **Cursor is stopped at `git push` and at the PR — not at the keystroke.** For inline coverage of Cursor's *shell* commands, install the caller-agnostic shims: `sh scripts/kit-guard install-shims` (shell commands only, **not** Cursor's direct file-writes — those are caught at push/PR). Drive Cursor through the floor in a real repo and confirm it blocks. **You verify this for your harness; the kit does not claim it for you.**

## Everything else is the shared floor

The dimension table, what "floor-only" means, the shared-control-plane / union rule, the self-verify recipe, and the coverage-ceiling links are common to every floor-only adapter and live once in [`../README.md`](../README.md) — *"The shared floor"*.
