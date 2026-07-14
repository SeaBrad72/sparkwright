# Maturity & validation status

This page states plainly what the kit has proven, what it has not, and where its own validation stops. The kit's thesis is **`green ≠ verified`** — a passing check attests only that the check ran, never that the underlying claim is true. This file exists so a stranger can see exactly where the kit's own evidence ends.

## Maturity is a stage, not a version

`VERSION` (semver) answers *what changed*. Maturity answers *what is proven* — and the two are deliberately separate axes. The maturity milestone is a stage:

```
pre-adoption → [release-candidate] → adopted
```

**Current stage: `release-candidate`.**

`v1.0.0` is **not** the current version and is **not** claimed. It is the number cut when the kit reaches the `adopted` stage — the already-ratified 1.0 gate (KW17).

### What each stage means, and what moves it

| Stage | What it means | What moves it forward |
|-------|---------------|-----------------------|
| **pre-adoption** | Built by dogfooding its own loop. The machinery runs, but the kit had not been made safe and honest to hand to someone who isn't its author. | Walk the documented adopter path, harden the readiness gate so it verifies the *real* enforcement surface, and make the front page state what is and isn't proven. |
| **`release-candidate`** *(now)* | The kit is judged safe and honest to hand to a stranger: its adopter path has been walked and its readiness gate hardened, its builder-facing machinery is exercised on every push, and at least one real product has been built end-to-end on its loop. The gap is the **adopter experience** — no one outside the author has driven it. | An **external adopter ships** — a person or team who is not the kit's author takes a project through the loop to operating software. |
| **adopted** | An external adopter has shipped real software through the kit. This is the point the kit earns **`v1.0.0`**. | — |

## The evidence, stated plainly

### Relay — a real product, deployed

**Relay** is a real dead-man's-switch product (Next.js / Prisma, the TypeScript-Node profile), built end-to-end on the kit's loop across roughly 30 PRs with dual-review threads, and deployed to Railway. It is the strongest evidence the kit has. Its review layer — the `builder ≠ reviewer` separation — caught real fail-open bugs the agent had shipped **as passing tests**: including a production path that failed open to the database owner, and a gate that was green only because it had been skipped (both High severity, on the same PR). Relay was built solo by the kit's own author and is archived, private and read-only, at `SeaBrad72/relay`. It is an **in-house** dogfood on a real product — not an external adoption.

### Two synthetic feedback-triage dogfood runs

The loop was also validated end-to-end by two synthetic in-house dogfood runs of a feedback-triage service — the same project, exercised twice, by the same author. A smaller vehicle than Relay, and likewise in-house.

### What is exercised, and what is not

- **Builder-facing machinery — exercised.** The kit runs its own conformance harness, control-plane guard, and CI gates on every push to this repository. That machinery is genuinely put through its paces, on the kit itself, continuously.
- **Adopter experience — not yet proven.** No one outside the kit's author has driven a project through it from Inception to operating software. That is the single gap between `release-candidate` and `adopted`. Driving a real project — or a non-Claude harness — through the kit is the recommended first real-world validation.

## The enforcement ceiling by harness (an honest limit)

The kit's runtime enforcement is **not uniform across harnesses**, and the front page should not imply that it is.

On the documented adopter path, a **hookless harness** (Codex, Cursor, Copilot — anything that reads `AGENTS.md` but has no inline pre-execution hook, i.e. the `generic` adapter) gets the enforcement **floor**:

- `AGENTS.md` routing to the canonical governance docs,
- an installed `pre-push` git hook, and
- the `agent-boundary` CI backstop.

It does **not** get Claude Code's inline **`PreToolUse` denial**. That is a Claude-Code affordance — a write blocked *before it happens* — and the kit's **dev-clone** discipline (author in a disposable clone while the guard stays armed on the real repo; land on a recorded GO) leans on it. So a Codex adopter is covered at the floor by the git hook and CI: nothing merges unsafely, because CI still gates. But a risky local write is not intercepted before it lands the way it is under Claude Code. This is a real difference, not a formality — it is why `claude-code` is the reference harness and `generic` is floor-verified, not equivalent.

## `green ≠ verified`

Every check in this kit that passes tells you the check ran — nothing more. This page is the kit holding itself to that standard: it names its strongest evidence (Relay), names the smaller runs beside it, and names the one thing it cannot yet claim — that someone other than its author has used it and shipped.
