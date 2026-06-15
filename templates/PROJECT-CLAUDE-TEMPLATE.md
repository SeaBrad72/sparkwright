# [Project Name] — Claude Project Guide

> **Template.** Copy to a new project's `CLAUDE.md` during Inception (Phase 0, see `DEVELOPMENT-PROCESS.md` §3). Fill every `[...]`. Delete guidance blockquotes once filled. This file declares the project's identity and its per-project configuration of the global process/standards.

**Project:** [name]
**Intent owner:** [who owns the why]
**Status:** [Inception / Active / Maintenance / Paused]
**Created:** [date]
**Kit version adopted:** [vX.Y.Z — the Agentic SDLC Kit release this project was incepted from; see the kit's `CHANGELOG.md`]

---

## Inherited standards (do not duplicate)

This project follows the Agentic SDLC Kit. Read these (paths relative to wherever the kit lives in/by your repo), do not restate them here:

- **Principles + Definition of Done:** `CLAUDE.md`
- **Process (the flow):** `DEVELOPMENT-PROCESS.md`
- **Standards (the universal bar):** `DEVELOPMENT-STANDARDS.md`
- **Your stack profile (the concrete how):** `profiles/<your-stack>.md`

This file holds only what is **specific to this project**.

---

## 1. Overview

**Problem:** [what problem this solves, for whom]
**Vision / success metrics:** [how we know it's working]
**Scope boundaries:** [what's explicitly in / out]

## 2. Tech stack (ADR-000)

> Chosen at Inception via a spike; full rationale + alternatives in `docs/architecture/ADR-000-*.md`.

- **Language(s) / runtime:** [...]
- **Framework(s):** [...]
- **Data store:** [...]
- **Testing:** [...]
- **Deploy target / hosting:** [...]
- **Key libraries / services:** [...]

## 3. Per-project process configuration

> These are the knobs `DEVELOPMENT-PROCESS.md` says are set per project.

- **Backlog backend** (§6): [`BACKLOG.md` / GitHub / Jira / Azure DevOps / Linear / GitLab] — [link] (mapping: `docs/work-tracking/adapters.md`)
- **Autonomy-tier defaults** (§12): [defaults, or deltas from the standard action→tier matrix]
  - e.g. `deploy to staging → L2 (autonomous behind smoke gate)`; everything else inherits defaults
- **SLO / error-budget posture** (§9): [soft track-and-guide / hard-gating] — [target SLOs if defined]
- **Data classification** (§privacy): [Public / Internal / Confidential / Restricted] — the highest tier this project handles. Confidential/Restricted ⇒ a privacy review (`docs/enterprise/data-governance.md`; verified by `conformance/privacy-ready.sh`).
- **Operator fluency** (§onboarding): [Novice / Adjacent / Practitioner] — the human operator's enterprise-SDLC experience; the agent adapts its assistance accordingly (`ONBOARDING.md`; behaviour in `docs/operations/operator-fluency.md`).
- **Review routing / ownership** (§11): [who/which agent reviews what; CODEOWNERS link]
- **WIP limits:** [per-stage or global cap]
- **Environments** (§ "Environments & promotion"): Dev → QA → UAT → Prod — [per-tier deploy trigger]; [if collapsing tiers, name which you use + one-line reason]. Production promotion is human-gated.
- **Agent-ops** *(if agentic)*: set `Agentic: yes` and declare the agent-run trace posture in RUNBOOK §8 (`Agent-ops:`); see `docs/operations/agentic-ops.md`. Verified by `conformance/agentops-ready.sh`.

## 4. Roles (this project)

> Fill each function from `DEVELOPMENT-PROCESS.md` §2 with a human or agent. One may hold several; builder ≠ reviewer; humans ratify. For a role-oriented view (PO/BA · Designer · QA · DevOps/SRE mapped to these functions), see the **Personas** table in §2.

| Function | Who/what |
|----------|----------|
| Intent owner | [...] |
| Lead / integrator | [...] |
| Builder(s) | [...] |
| Reviewer(s) | [...] |
| On-call / operator | [...] |
| Security owner | [...] |

## 5. Quickstart

> Stack-appropriate, copy-paste-ready. Keep current (artifact-flow owner: building agent).

```bash
# install
[...]
# run locally
[...]
# test
[...]
# build
[...]
```

## 6. Project conventions & gotchas

> Only non-obvious, project-specific things. Patterns that generalize go to the pattern library, not here.

- [convention or gotcha]
- [convention or gotcha]

## 7. Key references

- **Repo:** [link]
- **Live / staging URLs:** [links]
- **Backlog / board:** [link]
- **Roadmap:** [link]
- **RUNBOOK:** `./RUNBOOK.md`

---

**Last Updated:** [date]
