---
name: operating
description: Use when a live signal arrives on a running system — the kit's own operate-phase craft skill (a kit-original; superpowers has no operate craft). Assess blast radius, map to an autonomy tier, surface findings advisory-not-actuating, and close the loop back to discover.
---

# Operating — handle a live signal safely (blast-radius-aware, advisory-not-actuating)

The kit's own operate-phase craft: a live signal on a running system → a safe, documented response with blast radius assessed and an autonomy tier mapped before any action is proposed — and never actuated catastrophically by the agent. The Orchestrator wears the Operations hat to invoke this craft (it is a *hat*, not a seat — agents-vs-skills rule: the kit has no standing live system to operate, so no standing Ops seat is warranted; demand-gated on a live system and distinct prod authority, a clean future promotion). A kit-original — superpowers has no operate craft skill.

<!-- The frontmatter and the discipline phrases below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for these exact kit-distinctive
     markers (each quoted — some contain internal commas; preserve them verbatim):
       "name: operating"  "blast radius"  "advisory, not actuating"
       "the human commands the catastrophic action"  "autonomy tier"  "surface, don't actuate"
     Edits that drop or rename any of them can turn the skill-spine lock RED. -->

## When to use
When a **live signal** arrives on a running system — an alert, an anomaly in the telemetry, an error spike, a failed health check — and the Orchestrator must handle it safely during the **operate phase**. Operate signals feed back to Discover (postmortem → backlog); this is the loop-close that makes the kit's loop whole. Do not invoke for debugging a local dev build; use `skills/debugging/SKILL.md` for root-cause work that is not yet in production.

## The craft — the 6-step flow for handling a live signal safely

1. **Observe.** Read the telemetry the kit already emits — the Factor-14 quartet: health (`/healthz`), structured logs (E5-log), OTel spans (E5-trace), Prometheus counters (`/metrics`). Retrieve a specific trace by id via the E5 query path (`GET /api/traces/{id}` against the queryable backend, proven by E5-ops-query). The skill *points at* the E5 telemetry stack as the observable surface; it adds no new tooling.

2. **Triage.** Correlate signals. The `request_id` ↔ `trace_id` correlation established by E5-log and E5-trace lets you link a log line to its span and vice-versa. Establish severity (Is this a spike or a floor change? Is it isolated to one endpoint or systemic?). Root-cause work **composes with `skills/debugging/SKILL.md`** — once you have a hypothesis, hand the reproduce-as-a-regression-test cycle to the debugging skill; do not duplicate it here.

3. **Assess blast radius.** Before proposing *any* remediation action, characterize what the action touches, whether it is reversible, and the radius if it goes wrong. This is the signature discipline of this skill: **blast radius** is assessed *before* acting, not assumed or skipped. Ask: What changes? Who is affected? What is the rollback path? Is this reversible within the RTO? A high-blast-radius action is human-gated regardless of any other tier mapping.

4. **Map to an autonomy tier.** Apply the L0–L3 tier matrix from `DEVELOPMENT-PROCESS §13` (governed by risk × reversibility × blast radius). Investigation and triage are L0–L1 (act and report). **Anything irreversible or high-blast-radius is human-gated regardless of its apparent tier.** The tier maps intent to authority; it never overrides the blast-radius gate.

5. **Advisory, not actuating.** The agent *surfaces* findings and a recommended action; it does **not** actuate catastrophic or irreversible changes. **The human commands the catastrophic action.** Surface, don't actuate: present the finding, the blast radius assessment, the recommended action, and the options — then stop and wait. High-risk actions route through the escalation seam: `escalate.sh raise → await → resolve` (the `escalate.sh` ops-trigger is a documented extension point; the advisory hand-off is the FLOOR). The agent never self-issues a verdict on a catastrophic action.

6. **Close the loop.** Operate signals feed back to Discover — postmortem → backlog via the existing `operate-loop` tooling (`docs/operations/operate-loop.md`). **Never-actuate** on the close: the tooling scaffolds and parses the postmortem record; it does not auto-detect incidents or auto-create tracker items. The human writes the postmortem verdict; the agent formats and routes it.

## Honest ceiling
- **What is provable:** the craft is *provided* (this SKILL.md exists, carries the load-bearing markers, and is indexed by `skills/using-skills/SKILL.md`), the **agents-vs-skills rule is respected** (Ops is a hat, not a seat), and the keystone/reference wiring is structurally locked. Generic paraphrase fails the markers (non-vacuity via `check_operating_skill`).
- **What is NOT provable:** triage *quality* is un-gateable — there is no CI check that an agent triaged a real production alert correctly; the relationship is inherently advisory. The structural proof is wiring and provision, not good judgement.
- **Documented extension point:** the `escalate.sh` ops-trigger is **not wired** (banked as `escalate-ops-trigger-banked`) — the skill prescribes the escalation hand-off, and the existing `escalate.sh` knows only `runaway-breach` today. The skill teaches "high-risk → route through `escalate.sh`" and points at the seam; an ops-specific trigger (option set, `--selftest` extension) is a future slice, gated on a concrete live-system consumer.
- **Relationship to existing docs:** the skill *references* the operate substrate (`docs/operations/operate-loop.md`, `docs/operations/agentic-ops.md`, the §13 tier matrix) and encodes the *judgement* on top — it does **not** duplicate the tooling docs.

## Rationalizations to refuse
| Rationalization | Why it fails |
|---|---|
| "It's reversible enough, I'll just do it." | **Blast radius** is assessed before acting, not assumed. Assess and surface; the human decides. |
| "I can see the fix clearly, I'll apply it." | Surface, don't actuate: present the finding and the recommended action. **The human commands the catastrophic action.** |
| "This alert is obviously X, I don't need to correlate." | Triage + correlate before concluding. Obvious patterns mask compounding failures. Compose with `skills/debugging/SKILL.md` for RCA. |
| "The tier matrix says L1, so I can just act." | **Autonomy tier** maps intent to authority; it never overrides the blast-radius gate. Irreversible or high-blast-radius actions are human-gated regardless. |
| "I'll route this through escalate.sh automatically." | Surface, don't actuate. Escalation is a hand-off the agent *initiates*, not a trigger the agent *resolves*. The human ratifies the verdict. |
| "I'll create the postmortem item automatically." | The operate-loop tooling scaffolds; the human authors the postmortem verdict. Never-actuate on the close. |

## Terminal state
Signal observed → triaged + correlated (`request_id` ↔ `trace_id`, `GET /api/traces/{id}`) → **blast radius** assessed → **autonomy tier** mapped (L0–L3, §13) → **advisory, not actuating**: findings and recommended action surfaced to the human, or routed through `escalate.sh raise` for high-risk actions → loop closed: postmortem scaffolded, signal fed back to Discover as a backlog item. **Nothing catastrophic was actuated by the agent; the human commanded the catastrophic action.**
