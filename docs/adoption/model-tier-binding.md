# Model-Tier Binding Adapter Guide

The kit's model tiering is **harness-neutral**. The neutral core decides *which abstract tier* a piece of work needs (`deep` / `fast` / `light`); a per-harness **adapter** binds that abstract tier to a *concrete model* and passes it to the harness's subagent-spawn. This mirrors `docs/adoption/vc-hosts.md` (version-control hosts) for the model-dispatch axis — the kit owns the *contract*, you bring the *harness*.

- The neutral core — `scripts/model-tier.sh` + `.kit/model-tiers.conf` — **RESOLVES** the tier (pins the six judgment/verification seats to `deep`, floors control-plane / critical-path / sensitive work to `deep`, fail-closed). It is LLM-neutral and never names a model.
- The per-harness adapter **BINDS** the resolved tier to a model via the adopter-owned `.kit/model-map.conf`, and passes that model to its subagent-spawn.

**The `apex` tier (opt-in, above `deep`).** As of FABLE-TIER the policy also defines `apex` — a tier *above* `deep` for exceptionally-complex work, reachable only by the `engineer`/`architect`/`plan` seats and only on ordinary-class tasks (control-plane/sensitive/critical still floor to `deep`; judgment seats reviewer/security/orchestrator stay `deep`). The reference map binds `apex=fable`; **a non-Claude adopter maps `apex=` to their own most-capable model** (e.g. their provider's top-tier model), exactly as they map the other tiers. It is opt-in per plan — the resolver returns `apex` only on an explicit request, never by default.

The split is deliberate: the resolver's *judgment* (what deserves the strong model) stays portable and testable; the *mapping* to a vendor model stays adopter-owned and swappable.

## The contract every harness must satisfy

The kit needs three things from your harness. The **names** differ per harness; the **mechanics** don't:

1. **Read the resolved tier** — take the `model_tier` value the Orchestrator wrote into the step's Task-Context-Contract (`deep` / `fast` / `light`).
2. **Map it through `.kit/model-map.conf`** — the adopter-owned `apex=`/`deep=`/`fast=`/`light=` → model-id map (control-plane, guard-locked). This file is opaque to the neutral core: it is the one place a vendor model id appears.
3. **Pass the mapped model to the spawn** — hand the resolved model id to your harness's subagent-spawn as its model parameter (e.g. a `model:` argument).

**Graceful degradation.** If `.kit/model-map.conf` is absent, or maps every tier to a single value, all tiers collapse to one model and tiering becomes *advisory* — the plan still stamps the tier for human judgment, but the harness dispatches one model. This is the honest single-model-harness case, not a failure.

## claude-code *(worked, native)*

The reference harness binds the tier out of the box:

- `adapters/claude-code/adapter.json` declares `model-tiering: native`, with proof `conformance/model-map-binding.sh`.
- The dispatch surface `.claude/agents/orchestrator.md` reads the TCC `model_tier` field, resolves it through `.kit/model-map.conf`, and passes the resolved model as the `model:` parameter on its `Task` / `Workflow` spawns.
- `.kit/model-map.conf` is control-plane and guard-locked in `.claude/hooks/guard-core.sh` — an agent remapping `deep→cheap` would defeat the resolver's pins as surely as editing `.kit/model-tiers.conf`, so the map is agent-immutable.

The framework's **lying-native guard** (`conformance/harness-adapter.sh`) forces any `native` claim to carry a proof that actually passes — you cannot declare `native` without `model-map-binding.sh` going green.

## Floor *(every other harness, out of the box)*

Every non-reference adapter declares `model-tiering: floor`. The FLOOR is the Slice-1 guarantee: the resolver resolves the tier and the Build Plan stamps it for human ratification, but the harness does not *bind* it to a model. You get **advisory tiering with zero adapter work** — the decision discipline is present; the dispatch is one model. This is the correct honest default for a harness that has not (yet) written a binding.

## Bring your own binding

To reach `native` on your harness — the `docs/adoption/vc-hosts.md` pattern — write a one-file adapter binding and declare it:

1. **Map the file** — read `.kit/model-map.conf`'s `deep`/`fast`/`light` entries and translate the resolved tier to your harness's model parameter (whatever your spawn calls it).
2. **Wire the dispatch surface** — have your harness's dispatch/orchestration surface read the TCC `model_tier`, resolve through the map, and pass the model on spawn.
3. **Declare `native` with a proof** — set `model-tiering: native` in your `adapter.json` and point it at a proof check that structurally verifies the wiring. The lying-native guard will hold you to it: no passing proof, no `native`.

Until then, `floor` is the honest declaration.

## Honest ceiling

The kit proves the binding is **WIRED** — the map is declared and guard-locked, the adapter declares `native`/`floor` honestly, and the dispatch surface is structurally checked to read the map and pass the model. It **cannot observe which model a subagent actually ran on** at runtime — that is NATIVE to the harness and un-gateable from the kit. **Declared ≠ obeyed ≠ bound.** A green run is *necessary, not sufficient*: on a single-model harness the tier is advisory, and even on a multi-model harness the kit attests the instruction, not the executed dispatch.
