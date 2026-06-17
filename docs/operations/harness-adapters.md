# Harness Adapters — Boundary Contract

One contract, many runtimes. An adapter is a thin, harness-native binding that points at the universal governance layer; it never forks policy or process. Add a harness → add a subdirectory under `adapters/`; the universal layer (`CLAUDE.md`, `DEVELOPMENT-PROCESS.md`, hooks, conformance scripts) stays untouched.

Multi-harness coexistence rule: adapters occupy additive, non-conflicting namespaces — `adapters/<harness>/` — so any two runtimes can share the same repo without clashing.

> **Principle — floor first, native is additive.** The floor is the equal-enforcement guarantee: every harness ships it, no exceptions. Native dimensions are a bonus when the harness supports them; they are verified, not assumed. An unchecked "native" claim is caught by the lying-native guard (see The conformance check).

---

## The boundary contract — 5 dimensions

| Dimension | Floor *(kit-enforced, every harness)* | Native bonus *(kit-assisted, if supported)* | Verified by |
|-----------|--------------------------------------|---------------------------------------------|-------------|
| **context-binding** | `AGENTS.md` present + routes to canonical docs | Harness-native rules file (e.g. `.claude/settings.json` + `CLAUDE.md`) | `conformance/agents-brief.sh` |
| **command-guard** | `pre-push` + `kit-guard` CLI + `agent-boundary` gate | Inline pre-exec interception (Claude Code `PreToolUse` hook) | `conformance/guard-core-sourced.sh` + `conformance/guard-wired.sh` |
| **history-protection** | Universal `pre-push` hook (force-push / push-to-main) | *(none — universal hook is sufficient)* | `pre-push` presence |
| **review-roles** | `agent-boundary` gate + branch-protection reference | Native subagents (`reviewer.md`, `security-reviewer.md`) | `conformance/branch-protection.sh` |
| **mcp-gate** | N/A if no MCP | `mcp-policy` wired (`guard_check_mcp` + `mcp-policy.json`) | `conformance/mcp-policy.sh` |

> The "Verified by" column spans both the floor verifier (e.g. `conformance/guard-core-sourced.sh`, run for every harness) and the native-proof verifier (e.g. `conformance/guard-wired.sh`, `conformance/mcp-policy.sh`, run only when `level` is `"native"`); the manifest-schema section below documents which script fills which role.

---

## The manifest schema

Each adapter declares its binding in `adapters/<harness>/adapter.json`. The shape:

```json
{
  "harness": "<string>",
  "controlPlanePaths": ["<path>", "…"],
  "bindingFiles": ["<path>", "…"],
  "dimensions": {
    "<dimension>": {
      "level": "native | floor | n-a",
      "proof": {
        "check": "<conformance-script-path>",
        "files": ["<path>", "…"]
      }
    }
  }
}
```

**Field rules:**

- **`harness`** — string; must match the directory name under `adapters/`.
- **`controlPlanePaths`** — non-empty array; feeds the `agent-boundary` gate's union set (the gate denies PRs that touch any listed path without ratification). Must include every control-plane file the harness can modify.
- **`bindingFiles`** — array; every listed path must exist in the repo (verified by `harness-adapter.sh`).
- **`dimensions`** — all five dimensions must appear. Each carries:
  - `level`: `"native"` | `"floor"` | `"n-a"`. Only `mcp-gate` may be `"n-a"` (when the harness has no MCP surface).
  - `proof` (optional on `"floor"`; required on `"native"`): either `check` (a conformance script that must exit 0), `files` (paths that must exist), or both.

**Invariants:**
- Every dimension's **floor** must hold regardless of `level` — a `native` claim does not exempt the floor.
- A `native` dimension **must** carry a `proof` that passes — the lying-native guard enforces this (`harness-adapter.sh` fails if proof is absent or the check exits non-zero).
- Only `mcp-gate` may carry `"n-a"` — every other dimension has a floor that applies universally.
- A `proof.check` script is trusted on the same basis as any `conformance/*.sh` the kit already runs: adapter manifests are control-plane-adjacent and change only through ratified review (they sit beside the `.claude/` paths the `agent-boundary` gate guards).

---

## The conformance check

```sh
sh conformance/harness-adapter.sh adapters/<harness>
```

Three-state exit:

| Exit | Meaning |
|------|---------|
| 0 | All dimensions pass (floor held; native proofs verified) |
| 1 | One or more dimensions fail — output names the failing dimension + reason |
| 2 | Manifest missing or malformed JSON |

Self-test (fixture corpus):

```sh
sh conformance/harness-adapter.sh --selftest
```

---

## The `generic` adapter — floor-only proof

`adapters/generic/` is the floor-only adapter for any harness that reads `AGENTS.md` but provides no inline pre-exec guard — Codex, Cursor, Copilot, and similar runtimes. It declares every dimension at `floor` and `mcp-gate: n-a`. This proves that a hookless harness fully clears the boundary contract bar: enforcement holds through the universal governance layer (the git hook + CI backstop) without any harness-native interception.

`incept --harness <list>` (default `claude-code`, multi-select) selects which adapter(s) a project targets and runs `conformance/harness-adapter.sh` for each at Inception. The result is recorded in the project's conformance evidence.

---

## BYO — adding a new harness

Any harness is supported via a guided, validated workflow — parity with the `scripts/new-profile.sh` story for stacks:

```sh
sh scripts/new-adapter.sh <harness-name>
```

This scaffolds `adapters/<harness>/{adapter.json,README.md}` from the `adapters/_TEMPLATE/` skeleton. The generated adapter is **floor-only** and conforms immediately (`sh conformance/harness-adapter.sh adapters/<harness>` exits 0). Refine from there:

1. Set `controlPlanePaths` for the harness's namespace (config file, rules directory, settings path).
2. Upgrade a dimension to `"native"` with a `proof` (`check` and/or `files`) when the harness supports inline pre-exec interception, native subagents, or an MCP gate.
3. Validate after each change: `sh conformance/harness-adapter.sh adapters/<harness>`.
4. Select it at Inception: `sh scripts/incept.sh --harness <harness-name>`.

A floor-only adapter is always fully covered by the universal governance layer. The kit is never limited to the adapters it ships.

---

## Honest note

The floor is the equal-enforcement guarantee — it holds on every harness without cooperation from the runtime. Native is additive: it tightens enforcement when the harness supports inline interception (pre-exec hooks, subagents). A harness that supports native should declare it and prove it; one that doesn't stays at floor and is still fully covered by the universal layer.

Inline command interception varies by harness capability — see [runtime-guards.md](runtime-guards.md) for the full matrix of what each surface covers and where the ceiling is.
