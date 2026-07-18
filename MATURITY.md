# Maturity & validation status

Sparkwright tracks maturity as a **stage**, separate from its version. This page states the current stage, the evidence behind it, and how runtime enforcement differs by harness.

## Maturity is a stage, not a version

`VERSION` (semver) answers *what changed*; maturity answers *what is validated*.

```
pre-adoption → [release-candidate] → adopted
```

**Current stage: `release-candidate`** — hardened, dogfooded, and ready to adopt. `v1.0.0` is cut when the kit reaches the `adopted` stage (the ratified 1.0 gate, KW17): an external team ships real software through the loop.

| Stage | What it means |
|-------|---------------|
| **pre-adoption** | Built by dogfooding its own loop; not yet packaged for others. |
| **`release-candidate`** *(now)* | Safe and ready to adopt: the adopter path is walked, the readiness gate is hardened, the machinery runs on every push, and the loop has built real software end-to-end. **Next milestone:** the first external adoption. |
| **adopted** | An external team has shipped real software through the kit — where it earns `v1.0.0`. |

## Evidence

- **The kit builds itself.** Its conformance harness, control-plane guard, and CI gates run on this repository on every push — the kit holds itself to the same Definition of Done it gives adopters, continuously.
- **The loop ships real software.** It has been run end-to-end to build and deploy working software, where the `builder ≠ reviewer` review layer caught real high-severity fail-open bugs an agent had shipped as green tests — including a production path that failed open, and a gate that was green only because it had been skipped.
- **Exercised across vehicles** — from that build through smaller service builds.

## Runtime enforcement by harness

Enforcement is strongest under **Claude Code** (the reference harness), which adds an inline **`PreToolUse`** denial — a risky write blocked *before it lands*. A **hookless harness** (Codex, Cursor, Copilot — anything that reads `AGENTS.md` but has no inline pre-execution hook) runs at the enforcement **floor**:

- `AGENTS.md` routing to the canonical governance docs,
- an installed `pre-push` git hook, and
- the `agent-boundary` CI backstop.

At the floor, nothing merges unsafely — CI gates every change — though a risky *local* write isn't intercepted before it lands the way it is under Claude Code. This is why `claude-code` is the reference harness and other adapters are certified to the floor. Per-harness status lives in **`adapters/`**.
