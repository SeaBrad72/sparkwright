# Agent break-glass — halt → revert → rotate → postmortem

**What this is:** the one coherent procedure for *the agent went wrong* — runaway, compromised, or confidently-wrong — and you need to stop it, undo its actions, assume its credentials are burned, and learn. It is **assembly, not invention**: it names *when* and *in what order* to reach for primitives the kit already ships, for the one threat none of them individually addressed (an agent that actuated a bad **control-plane** change). It is the recovery net that makes delegated control-plane actuation ([the S6 capability grant](../governance/promotion-contract.md)) responsible — you don't hand over the keys until you can *undo* a mistake fast and have *proven* the undo works.

> **Honest ceiling — read this first.** The **HALT** below is *resource*-based ([`runaway-guard.sh`](../../scripts/runaway-guard.sh) meters reported usage) **plus** *manual* (a human noticing). **There is no bad-action auto-detector** — nothing here automatically decides the agent is compromised or wrong. **Solo, you are the monitor:** break-glass is the procedure you run *when you notice*, not an alarm that fires. The detection half of recovery (monitoring/alerting that *fires* on a bad action) is future work (KW23). Do not read this runbook as automatic compromise-detection.

---

## When to break the glass

Any of: the agent is looping / burning budget (runaway); you suspect its credentials or session are compromised; it actuated a change you did not ratify, or ratified against a bad judgment. If in doubt, break the glass — the steps are reversible and cheap relative to a bad control-plane change riding to users.

---

## 1. HALT — stop the loop, freeze actuation

- **Meter + circuit-break the loop:** [`scripts/runaway-guard.sh`](../../scripts/runaway-guard.sh) enforces a ceiling on *reported* token/agent usage at the orchestration seam (`runaway-guard.sh check` → exit 1 = STOP). The platform LLM-API cap is the hard ceiling above it.
- **Kill the session:** terminate the agent process / harness session so no further tool calls or keystrokes land. Freeze all actuation (no more merges, tags, deploys, applies).
- **Honest ceiling:** this halt is *resource-based + manual*. `runaway-guard` catches *runaway* (a resource signature); it does **not** detect a *bad action* taken within budget. Solo, the trigger is **you noticing**. (See the top-of-file ceiling.)

## 2. REVERT — undo the actions

Undo in the order matching what the agent touched. **Control-plane first** — it is the highest-consequence surface and the one this net was built for.

- **Control-plane change** (the kit's own guardrails / gates / governance — the S5b-drilled path): `git revert <bad control-plane merge>`, then **prove restoration by reusing the promotion `check`** — the same tree-equality that proves `shipped == approved` also proves *reverted == last-good*:
  ```
  git revert --no-edit <bad-control-plane-merge>
  sh scripts/promotion-verify.sh check --ref HEAD --approved-sha <last-good-sha>   # tree restored?
  sh conformance/verify.sh                                                          # conformance restored?
  ```
  This restoration is **drilled and CI-gated** by [`conformance/control-plane-revert-drill.sh`](../../conformance/control-plane-revert-drill.sh) (`--selftest`): on a fixture it applies a bad control-plane change, reverts it, asserts the reverted tree **equals** the last-good tree (via the same [`scripts/promotion-verify.sh`](../../scripts/promotion-verify.sh) `check`) and a conformance-shaped marker is green — with a **load-bearing negative** proving a *non-restoring* revert FAILs. No new revert command; recovery reuses the promotion mechanism.
- **Deploy** (a bad release reached an environment): follow the rollback order in [`progressive-delivery.md`](./progressive-delivery.md) — **flag-off → redeploy-previous → revert + redeploy**; in canary/blue-green the cheapest rollback is *don't widen* / *don't cut over*. **Deferred to KW23:** proving redeploy-previous *in anger* against a real staging environment (needs staging, unbuilt). This runbook documents the deploy-rollback *procedure*; the in-anger drill rides KW23.
- **Data** (a bad data mutation): restore per the DR [`backup-restore-drill.md`](../continuity/backup-restore-drill.md).

## 3. ROTATE — assume the credentials are burned

Treat any credential the agent could reach as compromised.

- Rotate tokens/keys per [`containment.md` §2](./containment.md) — prefer **OIDC → role federation** (short-lived, re-minted per run) so rotation is re-minting, not a manual key swap.
- **Revoke the agent's session** and any long-lived token it held; re-issue least-privilege.
- Confirm prod credentials were segregated ([`containment.md` §3](./containment.md), SoD) — a burned dev/agent token must not have reached prod.

## 4. POSTMORTEM — learn, route to the backlog

- Scaffold the record: `sh scripts/postmortem.sh new --id <ID> --severity <P0|P1|P2|P3> --title "<title>"` (from [`templates/POSTMORTEM-TEMPLATE.md`](../../templates/POSTMORTEM-TEMPLATE.md)).
- Route action items to the backlog: `sh scripts/postmortem.sh to-backlog <postmortem.md>`.
- Feed the findings back into the loop — the "adjust" step. A break-glass event should tighten a gate, a guard, or the autonomy posture, not just get patched.

---

## What this proves, and what it does not

- **Proves now:** control-plane **restoration** — `git revert` + tree-equality restores the last-good control-plane tree, drilled and CI-gated ([`control-plane-revert-drill.sh`](../../conformance/control-plane-revert-drill.sh)). This is the concrete S6 precondition, provable with no deploy.
- **Deferred (KW23):** the deploy-rollback drill *in anger* (needs staging) and monitoring/alerting that *fires* (the detection half).
- **Ceiling (restated):** the HALT is resource-based + manual — **no bad-action auto-detector**; solo, the human is the monitor. See [`promotion-contract.md`](../governance/promotion-contract.md) ("The general kill-switch posture") for why the retained human keystroke is a *kill-switch, not a validation*.
