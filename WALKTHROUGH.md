# Walkthrough — The Kit in Motion

A concrete, end-to-end picture of what a team *does* with this kit: from an empty repo to operating software. It follows one feature through the whole lifecycle so the gates, the human↔agent interplay, and the retros are tangible. Read it after `README.md`; it complements `DEVELOPMENT-PROCESS.md` (the reference) with a narrative.

```
INCEPTION (once) → [ Discover → Plan → Build → Review → Release → Done → Operate ] ↺ Discover
                     humans gate at: spec · merge · acceptance   |  agents run between gates
```

---

## Part 1 — Standing up the project (Inception / Phase 0, once)

A team — say one human lead plus a few agents — drops the kit into a fresh repo and opens `START-HERE.md`, then works the 8-step gate:

1. **Charter** — problem, users, vision, success metrics, intent owner → into the project `CLAUDE.md`.
2. **Choose stack → ADR-000** ⭐ — pick a ready `profiles/<stack>.md`, *or* generate one for any stack from `profiles/_TEMPLATE.md`. Recorded as `ADR-000`. **This is the only step that resolves "what we build it with."**
3. **Repo & environment** — protect `main`, add `.gitignore`/`.env.example`, reproducible local env, secrets wired.
4. **CI baseline** — lint/type/test/build from the profile's standard commands; **green pipeline on the empty repo** before any feature.
5. **Instantiate artifacts** — project `CLAUDE.md`, `RUNBOOK.md`, `BACKLOG.md`, seed roadmap.
6. **Per-project config** — backlog backend, agent autonomy defaults, SLO/cost posture, review routing, WIP limits, environments.
7. **Assign roles** — intent-owner / lead / builder / reviewer / on-call / security-owner → humans or agents.
8. **Inception Done gate** — all checked → enter the loop.

**Result:** a configured, CI-green project whose quality bar = *universal standards + chosen profile*.

---

## Part 2 — One feature through the loop

Trace *"add CSV export"* through `Discover → Plan → Build → Review → Release → Done → Operate`:

- **Discover** — idea enters and is validated lightly (who needs it? evidence? success metric: "X% of users export within 30 days"). Becomes a board candidate, ranked **value × urgency ÷ risk**.
- **Plan** — sliced into a small vertical increment; acceptance criteria written; threat-model if sensitive. Reaches **Definition of Ready** → **spec gate (human approves).**
- **Build** — a builder agent **claims it atomically**, works in an **isolated worktree**, TDD per the profile (**new to TDD? see the worked red-green-refactor: `docs/onboarding/first-feature-tdd.md`**). **L0 reflection-in-action** runs continuously (test → observe → adjust). The agent acts at its **autonomy tier**: writes code + opens a PR unattended (reversible), but stops at the merge gate.
- **Review** — a *different* agent + human review quality, security lens, standards (+ the **eval gate** if a prompt/model changed) → **merge gate (human approves).**
- **Release** — deploy behind a **feature flag**, staged rollout, smoke test, CHANGELOG updated, **rollback path ready** (flag-off is fastest).
- **Done** — **acceptance checkpoint** (did we build the *right* thing?), Definition of Done met, builder writes a tiny **L1 retro** on the PR.
- **Operate** — monitor in production; later, **outcome validation**: did it hit the success metric? Yes → real win. No → routes back to **Discover** as evidence.

Humans touched it at exactly **three points** (spec, merge, acceptance); agents ran at machine speed between them.

---

## Part 3 — When something goes wrong

- **Mid-build blocker / bug / red CI / rejected review** → an **Event retro** fires immediately (blameless triage: cause · fix-now vs. backlog vs. spike · prevention), from any stage, then work resumes.
- **Production incident** → on-call (human + agent-assist) triages by severity; P0/P1 escalate to the postmortem procedure; flag-off is the fastest rollback; the fix *and its prevention* route to the backlog.

---

## Part 4 — How it improves (the closed loop)

Every retro **exits into an artifact** — that routing *is* the "adjust" step:

- **L0** in-action → immediate behavior.
- **L1** per increment (agent) → durable learnings to memory; doc proposals up to L2.
- **L2** milestone (human, fed by L1 notes) → backlog / roadmap / docs changes.
- **L3** periodic → edits to the process/standards docs themselves.
- Stale flags, eval-score decline, recurring friction → **tech-debt** items with a standing paydown allocation.

A retro that changes nothing is theater; here, learning always lands somewhere.

---

## Part 5 — Many agents at once

The **board is the coordination primitive** (it replaces the standup): agents **atomically claim** items, work in **isolated worktrees**, integrate **trunk-based** in small merges, and **never review-and-merge their own work**. **WIP limits** keep parallel work from outrunning human review and integration safety. Autonomy is governed by tier (risk × reversibility), audited, and earned by metrics.

---

**The shape, in one line:** a project is *born* through Inception and *evolves* through a closed loop, with humans as a thin layer of judgment at the gates and agents doing the volume between them. Everything that varies by team — stack, tools, thresholds, cadence — lives in a profile, the project `CLAUDE.md`, or a config hook, so this spine is identical for every adopter.
