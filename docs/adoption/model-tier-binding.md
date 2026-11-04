# Model-Tier Binding Adapter Guide

The kit's model tiering is **harness-neutral**. Each **seat** runs on the model your project judges most appropriate for what that seat does. The neutral core decides *which abstract tier* a seat's work needs (`deep` / `fast` / `light`, plus the opt-in `apex`); a per-harness **adapter** binds that abstract tier to a *concrete model* and passes it to the harness's subagent-spawn. This mirrors `docs/adoption/vc-hosts.md` (version-control hosts) for the model-dispatch axis — the kit owns the *contract*, you bring the *harness*.

- The neutral core — `scripts/model-tier.sh` + `.kit/model-tiers.conf` — **RESOLVES** the tier (pins the six judgment/verification seats so no dispatch-time request can move them, fail-closed). It is LLM-neutral and never names a model.
- The per-harness adapter **BINDS** the resolved tier to a model via the adopter-owned `.kit/model-map.conf`, and passes that model to its subagent-spawn.
- **The model is its own neutrality axis** (axis #4). The mapping is a recorded decision with evidence and a revisit trigger, and the kit ships no vendor default.

## Seats and tiers

| Seat | Roles it covers today | What it does | Typical need |
|---|---|---|---|
| `conductor` | `orchestrator` | Slices, dispatches, integrates, recommends the mapping | judgment |
| `builder` | `engineer` | Writes code to a brief, inside one worktree | build |
| `reviewer` | `reviewer`, `verification` | Judges a diff for correctness | judgment |
| `security` | `security` | Judges a diff or a design for security | judgment |
| `design` | `architect`, `plan` (and the lens seats) | Designs, plans, answers the lenses | judgment |
| `explorer` | `explorer` | Reads and searches; returns conclusions | survey |

**The tiers name a need, not a rank.** `deep`, `fast`, `light` and `apex` are labels the resolver emits; the policy never says one is "better", and two may map to the same model. Which model is best for which tier is your measured call, and it changes with every model release (quality is not monotonic across releases). **Known issue until the next slice:** the resolver script still keeps a top tier, forces `--critical-path` work to it, and reads an unrecognised change-class as top; the tier names still read as a ladder there.

**There is no change-class floor.** The shipped policy has none: a control-plane or sensitive task runs on its seat's own tier. A project that wants a floor lists the class in `FLOOR_CHANGE_CLASS` in its own `.kit/model-tiers.conf` and records why; per-class overrides in the map arrive in the next slice (303b). Your existing `.kit/model-tiers.conf` is yours: nothing in this release changes it or reds on it. An explicit `--requested apex` from a control-plane or sensitive engineer, which the old floor refused, now reaches `apex` under the shipped policy.

**Pins are a change-control property.** A pinned seat (`orchestrator`, `reviewer`, `security`, `architect`, `plan`, `verification`) refuses a dispatch-time request to move it off its mapped tier. Only a new, recorded mapping decision can. An agent still cannot cheapen a judgment seat on its own.

**The `apex` tier (opt-in).** `apex` is reachable only by the `engineer`/`architect`/`plan` seats, only on an explicit request, never by default. Map it to the most capable model your provider offers, or leave it `unset`.

## The map and its record

`.kit/model-map.conf` is adopter-owned and guard-locked. `incept` stamps it from `templates/MODEL-MAP-TEMPLATE.conf` with every value `unset`; the kit's own mapping is export-ignored and never ships.

```
decision=D-YYMMDD-N     # the docs/governance/DECISIONS.md entry that justifies the values
recorded=YYYY-MM-DD
revisit-by=YYYY-MM-DD   # recorded + 90 days is a sound default; a warning, never a failure, once the tools read it
apex=unset              # each tier -> whatever your harness's spawn takes as its model parameter
deep=unset
fast=unset
light=unset
```

- **All-`unset` is the honest single-model case.** Every seat runs whatever model the harness is on, and the tiers are advisory. Nothing goes red.
- **A bound map owes a record.** `conformance/model-tiering.sh` checks that `decision=` resolves to a ledger entry, and `conformance/decision-integrity.sh model` requires `#### Model fit rationale` in your project `CLAUDE.md`. A map that binds a model but has no `decision=` line (an existing adopter map from before this field) warns for one release and then fails; the CHANGELOG lists "record your model mapping" as the upgrade act.
- **Agent definitions stay model-free.** `.claude/agents/*.md` carry no `model:` (or `inherit` only); the model is bound at dispatch, for every seat, through the map. `conformance/model-tiering.sh` also holds vendor model names out of every kit-shipped seat-binding surface (`.kit/*.conf` other than the map, agent definitions, skills, templates, `START-HERE.md`, `AGENTS.md`).

## A worked example (not a default)

**This is an example, not a default.** The kit ships no mapping: `incept` stamps every value `unset`, and all-`unset` stays the honest single-model case. Choose your own models and record why.

**The seats, from the shipped policy [M]:**

| Seat | Tier | Why |
|---|---|---|
| builder | `fast` | It writes to a brief, with tests and review behind it. |
| reviewer, security | `deep`, pinned, never apex-eligible | A missed finding costs more than the tokens. |
| design | `deep`, or `apex` on an explicit ask | `apex` is opt-in and never the default. |
| conductor | `deep`, pinned | It judges and integrates. |
| explorer | `fast`, and it may run `light` | It reads and returns conclusions. |

**One vendor's map.** The kit's own project binds Anthropic's models as `apex=fable`, `deep=opus`, `fast=sonnet`, `light=haiku` [M, its `.kit/model-map.conf`, read 2026-11-01]. These are that project's choice. List prices, per million input / output tokens, as reported from the vendor's [pricing page](https://platform.claude.com/docs/en/about-claude/pricing) and model pages through a web search on 2026-11-01, not read from the page directly: Opus 5.5 $4 / $20, Sonnet 5.5 $2 / $10, Haiku 5.5 $0.10 / $0.50 (this Haiku price only for prompts up to 100K tokens). The search did not report a base price for Fable. Prices and model names change, so confirm them on the vendor's own page and write the date you read them. Keep `decision=` pointing at your own ledger entry, since a bound map owes a record.

**Another vendor.** Fill the same four tiers by what each seat needs, not by the vendor's own product tier names. Two tiers may share a model, and `apex` may stay `unset`. No other vendor's models are named here, because none was read for this example.

**The cost effect [E].** At the prices above, `fast` costs half of `deep` on both input and output, so running the builder on `fast` instead of `deep` saves half of whatever share of the tokens the builder spends: about 15 percent of the bill if the builder spends 30 percent of the tokens, about 35 percent if it spends 70 percent. Those two shares are assumptions, not measurements, and caching and batch discounts are left out. Measure your own token mix, read each model's list price on the vendor's own page, and write the date read.

## Revisiting and re-mapping

| Trigger | Who sees it | Enforcement |
|---|---|---|
| A new model release from a provider you use | The conductor, at each release cut | Conduct, not enforced: the kit cannot see a vendor's release |
| A measured quality drop traced to one seat | The conductor, reading a scorecard | Conduct, not enforced: attributing a drop to a seat is a judgment |
| `revisit-by` passes | The resolver and `doctor`, from the next slice (until then the date is recorded and nothing reads it) | Warned, not enforced: a model does not get worse with age |

To re-map a seat: run the current model against the candidate **on the same seat**, on real slices from your board (3 per arm is a sound default; the model is the only change), compare the seat's observable outcomes (for a builder: first-CI-green, review rounds to approval, findings; for a reviewer or security seat: findings later shown missed; plus tokens and wall-clock), then record a new `DECISIONS.md` entry that names the one it replaces and update `decision=`, `recorded=` and `revisit-by=` in one control-plane change. **Honest ceiling:** with n = 3 the A/B is directional. It can catch a large regression and cannot rank two close models, and the entry must say so.

## The contract every harness must satisfy

The kit needs three things from your harness. The **names** differ per harness; the **mechanics** don't:

1. **Read the resolved tier** — take the `model_tier` value the Orchestrator wrote into the step's Task-Context-Contract (`deep` / `fast` / `light`).
2. **Map it through `.kit/model-map.conf`** — the adopter-owned `apex=`/`deep=`/`fast=`/`light=` → model-id map (control-plane, guard-locked). This file is opaque to the neutral core: it is the one place a vendor model id appears.
3. **Pass the mapped model to the spawn** — hand the resolved model id to your harness's subagent-spawn as its model parameter (e.g. a `model:` argument).

**Graceful degradation.** If `.kit/model-map.conf` is absent, or maps every tier to a single value, all tiers collapse to one model and tiering becomes *advisory* — the plan still stamps the tier for human judgment, but the harness dispatches one model. This is the honest single-model-harness case, not a failure.

## claude-code *(worked, native)*

The reference harness binds the tier out of the box:

- `adapters/claude-code/adapter.json` declares `model-tiering: native`, with a file-presence proof: `.claude/agents/orchestrator.md` exists. **`native` here proves a file exists, not that it reads the map or passes `model:`**; no check reads what it says, so a person reading a diff to that file is the only guard.
- The dispatch surface `.claude/agents/orchestrator.md` reads the TCC `model_tier` field, resolves it through `.kit/model-map.conf`, and passes the resolved model as the `model:` parameter on its `Task` / `Workflow` spawns.
- `.kit/model-map.conf` is control-plane and guard-locked in `.claude/hooks/guard-core.sh` — an agent remapping `deep→cheap` would defeat the resolver's pins as surely as editing `.kit/model-tiers.conf`, so the map is agent-immutable.

The framework's **lying-native guard** (`conformance/harness-adapter.sh`) forces any `native` claim to carry a proof that actually passes. For `model-tiering` that proof is the presence of the dispatch file; it does not test the wiring inside it.

## Floor *(every other harness, out of the box)*

Every non-reference adapter declares `model-tiering: floor`. The FLOOR is the Slice-1 guarantee: the resolver resolves the tier and the plan's team table presents it to the human, but the harness does not *bind* it to a model. You get **advisory tiering with zero adapter work** — the decision discipline is present; the dispatch is one model. This is the correct honest default for a harness that has not (yet) written a binding.

## Bring your own binding

To reach `native` on your harness — the `docs/adoption/vc-hosts.md` pattern — write a one-file adapter binding and declare it:

1. **Map the file** — read `.kit/model-map.conf`'s `deep`/`fast`/`light` entries and translate the resolved tier to your harness's model parameter (whatever your spawn calls it).
2. **Wire the dispatch surface** — have your harness's dispatch/orchestration surface read the TCC `model_tier`, resolve through the map, and pass the model on spawn.
3. **Declare `native` with a proof** — set `model-tiering: native` in your `adapter.json` and point it at a proof: either a check that structurally verifies the wiring (the stronger claim) or a list of files that must exist (what the reference harness uses now; it proves only that the files exist). The lying-native guard will hold you to it: no passing proof, no `native`.

Until then, `floor` is the honest declaration.

## Honest ceiling

The kit proves the binding is only **DECLARED** — the map file is guard-locked and the adapter declares `native`/`floor`, but no check requires the map's tier keys; for the reference harness `native` is backed by the dispatch file existing, and no check reads that file to confirm it reads the map or passes the model. It **cannot observe which model a subagent actually ran on** at runtime — that is NATIVE to the harness and un-gateable from the kit. **Declared ≠ obeyed ≠ bound.** A green run is *necessary, not sufficient*: on a single-model harness the tier is advisory, and even on a multi-model harness the kit attests the instruction, not the executed dispatch.
