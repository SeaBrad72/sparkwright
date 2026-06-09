# [Incident Title] — Postmortem

> **Template.** A **blameless** postmortem for a production incident (required for P0/P1, recommended for P2 — see `DEVELOPMENT-STANDARDS.md` §15). It examines **systems and contributing factors, never individual blame**. The goal is durable learning: every action item routes back onto the board (`DEVELOPMENT-PROCESS.md` §6 / §15).

**Incident ID:** [id] · **Severity:** [P0 / P1 / P2 / P3] · **Date:** [date] · **Incident commander:** [name / role] · **Status:** [open / closed]

## How to use
- Fill every section in plain language; bullet points are fine.
- Times in UTC. Keep the timeline factual and chronological.
- Hand the finished file to the team and link each action item to its backlog entry.
- Save the completed postmortem where your project keeps incident records (e.g. a `postmortems/` directory) and link it from the incident's board item (`DEVELOPMENT-PROCESS.md` §6).

---

## 1. Summary
> Two or three sentences: what happened, in plain language.

[...]

## 2. Impact
> Who and what was affected · duration (detect → resolve) · users or data affected · any SLA/SLO breach.

[...]

## 3. Timeline (UTC)
> The scribe's record: detected → declared → key mitigations → resolved.

| Time (UTC) | Event |
|------------|-------|
| [YYYY-MM-DD hh:mm] | [what happened] |

## 4. Root cause(s) & contributing factors
> The systems view ("5 whys" is a useful tool). **Blameless:** describe what in the system allowed this, not who.

[...]

## 5. Detection
> How we found out (alert · user report · telemetry) and how quickly. If detection lagged, say why.

[...]

## 6. What went well / what didn't
> Candid and system-focused. What helped the response; what got in the way.

[...]

## 7. Action items
> The loop-closing artifact. Each item has an owner, a due date, and a backlog link. Type: prevent (stop recurrence) · detect-faster · mitigate-faster.

| Action | Owner | Due | Backlog link | Type |
|--------|-------|-----|--------------|------|
| [action] | [owner] | [date] | [#id] | [prevent / detect-faster / mitigate-faster] |

## 8. Blameless statement
> This postmortem examines systems and processes, not people. We assume everyone acted with good intent and the information they had at the time.
