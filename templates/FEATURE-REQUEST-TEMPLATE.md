# [Feature / Request Title] — Feature Request

> **Template.** The front door for anyone proposing functional requirements — Product Owner, BA, stakeholder, support, or an engineer capturing a need. You do **not** need to write code or know the stack to fill this in. It mirrors the Discovery prompts (`DEVELOPMENT-PROCESS.md` §5); a complete one becomes a validated candidate ready for **Plan**.

**Requested by:** [name / role] · **Backlog item:** [id / link] · **For whom (users):** [audience] · **Date:** [date]

## How to use
- Fill every section below in plain language. Bullet points are fine.
- Skip nothing: an unanswered section is a signal the idea isn't ready (that's useful, not a failure).
- Hand the finished file to the team or drop it on the board (`DEVELOPMENT-PROCESS.md` §6). The Intent owner validates it; survivors go to Plan, the rest to the roadmap parking lot.

---

## Problem & user
> What problem, for whom? What is the current pain or workaround?

[...]

## Evidence
> What tells us this is real — support tickets, user requests, telemetry, revenue? Not "we assume."

[...]

## Success metric / hypothesis
> How will we know it worked? State it measurably ("X drops by Y%", "users can now Z").

[...]

## Rough scope & risk
> Roughly how big? Any obvious risk, compliance, privacy, or children's-data flag (e.g. users under 13)? Anything explicitly out of scope?

[...]

## Innovation / AI lens
> Could AI materially improve this? Any reusable or product angle? (Optional — leave blank if not applicable.)

[...]

## UX & accessibility
> Is there a screen or visual surface? Attach/link any sketches or designer handoff. Note accessibility needs (the Definition of Done requires WCAG 2.1 AA for user-facing UI).

[...]

## Definition of Ready
> The entry gate (`DEVELOPMENT-PROCESS.md` §7; enumerated in `CLAUDE.md`). Tick each mandatory box; flag each conditional item or write **N/A**. If a mandatory box can't be ticked, the item isn't Ready — that's useful signal, not a failure.

**Mandatory**
- [ ] Acceptance criteria written (testable)
- [ ] INVEST-sliced (small vertical increment)
- [ ] Dependencies known
- [ ] Success metric / hypothesis stated (see *Success metric / hypothesis* above)

**Conditional (flag or N/A)**
- [ ] Threat-model flagged — if sensitive/regulated
- [ ] UX/a11y obligation flagged — if user-facing (see *UX & accessibility* above)
- [ ] Eval criteria flagged — if an AI feature
- [ ] Compliance obligation flagged — if a regulated domain

---

## Extended spec (Plan phase) — *optional*
> Fill this **only** when the request is promoted to **Plan** (`DEVELOPMENT-PROCESS.md` §4) and needs a
> fuller PRD before Build. It is the **manual alternative** to a brainstorming-flow spec — tool-neutral;
> if you use the superpowers brainstorming flow it produces an equivalent. A reviewer signs it off at
> the **spec gate** (§7) before Build. Leave blank for small/obvious slices — a vibe-coder or a tiny
> increment never needs it. (The base sections above — *Problem & user*, *Success metric*,
> *UX & accessibility* — carry forward; this section adds the Plan-phase depth, it doesn't repeat them.)
> After sign-off, scope changes are a **new revision** — note them here.

### Goals & non-goals
> What this delivers; what it explicitly does **not** (the YAGNI fence).

[...]

### Users & personas
> Who uses this and in what role (persona map, `DEVELOPMENT-PROCESS.md` §2).

[...]

### Functional requirements (numbered)
> Numbered, specific behaviors the system must exhibit.

[...]

### Acceptance criteria (testable)
> Pass/fail conditions; each maps to at least one test. 100% on critical paths (auth, payments, data
> integrity). These become the tests and the Reviewer's checklist.

[...]

### Data & privacy considerations
> What data is touched; PII/consent/retention/children's-data implications (`DEVELOPMENT-STANDARDS.md`
> §2 + the enterprise privacy family in `docs/enterprise/compliance-crosswalk.md`). "None" is a valid,
> explicit answer.

[...]

### Risks & mitigations
> What could go wrong technically or operationally, and the mitigation.

[...]

### Out of scope
> Deferred or explicitly excluded — so reviewers don't flag them as gaps.

[...]
