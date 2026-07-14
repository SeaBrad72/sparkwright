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
- **`controlPlanePaths`** — non-empty array declaring the control-plane surface this harness can modify (the guard + its config, CI, CODEOWNERS, the harness's own settings). The `agent-boundary` gate **enforces the union of these paths across all adapters**, in addition to the kit-standard `guard-core.sh::is_control_plane_path` floor: an unratified PR touching any declared path fails the gate. (For example, the `generic` adapter declares `AGENTS.md`, so an unratified `AGENTS.md` edit is caught even though it sits outside the guard-core set.) Entries are matched exactly or as a directory prefix (a value ending in `/`). List every control-plane file the harness can touch so the gate — and a human reviewer — protect the complete set.
- **`bindingFiles`** — array; every listed path must exist in the repo (verified by `harness-adapter.sh`).
- **`dimensions`** — all five dimensions must appear. Each carries:
  - `level`: `"native"` | `"floor"` | `"n-a"`. Only `mcp-gate` may be `"n-a"` (when the harness has no MCP surface).
  - `proof` (optional on `"floor"`; required on `"native"`): either `check` (a **bare `conformance/*.sh` path** — no arguments, shell metacharacters, or `..` traversal — that must exit 0; `harness-adapter.sh` rejects anything else *before running it*), `files` (paths that must exist), or both.

**Invariants:**
- Every dimension's **floor** must hold regardless of `level` — a `native` claim does not exempt the floor.
- A `native` dimension **must** carry a `proof` that passes — the lying-native guard enforces this (`harness-adapter.sh` fails if proof is absent or the check exits non-zero).
- Only `mcp-gate` may carry `"n-a"` — every other dimension has a floor that applies universally.
- A `proof.check` is **executed only if it is a bare `conformance/*.sh` path** that exists (no arguments, no shell metacharacters, no `..` traversal) — `harness-adapter.sh` rejects anything else *before running it*, so a malformed or hostile `check` cannot run and cannot then prove `native`. Combined with `adapters/` being control-plane (an unratified adapter change fails the `agent-boundary` gate), adding or changing a `proof.check` is both ratification-gated and value-constrained.

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

**The ceiling, stated plainly.** On the documented adopter path a hookless harness gets the floor and *only* the floor: `AGENTS.md`, an installed `pre-push` git hook, and the `agent-boundary` CI backstop. It does **not** get Claude Code's inline `PreToolUse` denial — a write blocked *before it happens*. That interception is a Claude-Code affordance, and the kit's **dev-clone** workflow (author in a disposable clone while the guard stays armed on the real repo; land on a recorded GO) depends on it. A `generic` adopter is fully covered against unsafe *merges* — CI still gates — but does not get pre-execution interception locally. This is why `claude-code` is the reference harness and `generic` is floor-verified, not equivalent.

`incept --harness <list>` (default `claude-code`, multi-select) selects which adapter(s) a project targets and runs `conformance/harness-adapter.sh` for each at Inception. The result is recorded in the project's conformance evidence.

---

## Choosing a harness — cards, maturity & fit

Harness is a **concretization axis** — a place the kit forces a real-world choice — so it is neutral **by construction**: comparable cards, a fit-derived selection, an honest maturity disclosure, and a machine gate (`conformance/harness-decision-integrity.sh`) that rejects bias-appeal. This section is harness's worked instance of the recipe in [neutrality-by-construction.md](../adoption/neutrality-by-construction.md) (harness = instance #3, after stack #1 and deploy-target #2).

### The maturity criterion (read this first)

**Maturity = exercised, not merely declared.** An adapter's `adapter.json` *declaring* a dimension against the boundary contract is necessary but **not** sufficient for a maturity tier above experimental. A tier of `verified` requires the kit to have actually run the harness end-to-end and proven its dimensions; a tier of `floor-verified` requires the universal-layer floor to be proven on it. Declaring conformance on paper is **not** the same as exercising it — do not read "experimental" as "supported."

| Tier | Meaning | Adapters |
|------|---------|----------|
| **verified (first-class)** | The kit **self-hosts** on it; native dimensions proven end-to-end. | `claude-code` |
| **floor-verified** | The universal-layer floor (`AGENTS.md` + git hook + CI backstop) is proven; no native bonus by definition. | `generic` |
| **experimental** | **Declared** against the boundary contract but **not exercised end-to-end by the kit** — *unproven*, not "supported." Adopt with the expectation that you are the one exercising it. | `gemini` · `codex` · `cursor` |

### Comparable cards

Every option carries the same uniform fields: **Name · Best for · Avoid when · Maturity tier · Key fit dimensions**. No favourite gets a richer entry.

#### claude-code
- **Best for:** teams that want the deepest native enforcement — inline `PreToolUse` interception, native subagents (`reviewer`/`security-reviewer`), an MCP gate; the harness the kit itself runs on.
- **Avoid when:** your primary model-family is not Claude, or your workflow must live inside an IDE surface this harness does not cover.
- **Maturity tier:** **verified (first-class)** — the kit self-hosts on it; native dimensions proven.
- **Key fit dimensions:** native-hooks (pre-exec interception) · multi-agent (subagents) · MCP gate · model-family (Claude).

#### generic
- **Best for:** any harness that reads `AGENTS.md` but has no inline pre-exec hook (Codex, Cursor, Copilot, …); guarantees the equal-enforcement floor through the git hook + CI backstop.
- **Avoid when:** you need proven native inline interception — pick a harness that declares (and proves) a native dimension.
- **Maturity tier:** **floor-verified** — the `AGENTS.md` floor is proven; no native bonus by definition.
- **Key fit dimensions:** portability across runtimes · existing-tooling reuse · offline / air-gapped compatibility · CI-native enforcement.

#### gemini
- **Best for:** teams standardized on the Gemini model-family / Google tooling who want the boundary-contract floor.
- **Avoid when:** you need proven native interception today, or you cannot own the end-to-end exercise yourself.
- **Maturity tier:** **experimental** — declared against the boundary contract but not exercised end-to-end by the kit (unproven).
- **Key fit dimensions:** model-family (Gemini) · existing tooling.

#### codex
- **Best for:** teams on OpenAI Codex-family tooling that want the floor via the `generic` path.
- **Avoid when:** you need verified native enforcement (subagents / MCP) out of the box.
- **Maturity tier:** **experimental** — declared against the boundary contract but not exercised end-to-end by the kit (unproven).
- **Key fit dimensions:** model-family · existing tooling · IDE surface.

#### cursor
- **Best for:** teams whose primary surface is the Cursor IDE and who want the boundary-contract floor.
- **Avoid when:** you need proven native subagent / MCP enforcement.
- **Maturity tier:** **experimental** — declared against the boundary contract but not exercised end-to-end by the kit (unproven).
- **Key fit dimensions:** IDE-embedded workflow · existing tooling.

### Selection rubric + steer-away

Choose from **fit dimensions**, never from "it's the default":

1. **Name the fit dimensions that matter** for this project — e.g. do you need native pre-exec interception (native-hooks), multi-agent review, an MCP gate, a specific model-family, an IDE-embedded workflow, or offline operation?
2. **Match them to a card's "Key fit dimensions."** The best-fit harness is the one whose fit dimensions cover your needs — not the most familiar one.
3. **Cross-check maturity, then disclose the trade-off.** If your best-fit harness is `experimental` while `claude-code` is `verified`, state **both** — best-fit *and* maturity — and have the owner ratify the trade-off explicitly (the fit-vs-maturity disclosure). The kit never silently downgrades fit to maturity or vice versa.
4. **Record the choice with a cited fit reason** in the project `CLAUDE.md` §harness-neutrality `#### Harness fit rationale` field. `conformance/harness-decision-integrity.sh` rejects bias-appeal ("it's the proven default," "everyone uses it") and requires a named fit dimension.

**Steer-away:** "we always use X," "X is the proven default," or "everyone uses X" are **not** fit reasons — the anti-bias gate fails an artifact that names no fit dimension. A verified maturity tier is a reason to *disclose and ratify* a trade-off, not a licence to skip the fit derivation.

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
