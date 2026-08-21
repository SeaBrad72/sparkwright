# adapters/generic/

Floor-only adapter for **any harness that reads `AGENTS.md`** but provides no inline pre-exec guard and has no adapter of its own. It is the **catch-all**: use it when your runtime has no named adapter here, or scaffold a named one with `sh scripts/new-adapter.sh <harness-name>`.

## Adopting with a generic harness

Point the runtime at the repo-root `AGENTS.md` — the kit's brief routes from there to the canonical docs — and confirm it actually auto-loads that file. Because this adapter is not bound to one named runtime, it declares **no harness-specific in-repo namespace** in `controlPlanePaths`; only the kit's own floor paths are listed. If your harness *does* keep an in-repo control surface (a rules directory, a settings file), do not stretch this adapter over it: scaffold a named adapter and declare that path there, so the union covers it.

## The honest ceiling for a generic harness

There is **no harness-native inline interception** here (no Claude-Code-`PreToolUse` equivalent) — that is what "generic" means. Claude is stopped at the keystroke; **a generic harness is stopped at `git push` and at the PR — not at the keystroke.** For inline coverage of its *shell* commands, install the caller-agnostic shims: `sh scripts/kit-guard install-shims` (shell commands only, **not** the harness's direct file-writes — those are caught at push/PR). Drive your harness through the floor in a real repo and confirm it blocks. **You verify this for your harness; the kit does not claim it for you.**

## Everything else is the shared floor

The dimension table, what "floor-only" means, the shared-control-plane / union rule, the self-verify recipe, and the coverage-ceiling links are common to every floor-only adapter and live once in [`../README.md`](../README.md) — *"The shared floor"*.
