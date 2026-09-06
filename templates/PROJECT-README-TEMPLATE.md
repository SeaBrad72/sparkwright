# [Project Name]

> **Template.** Inception stamps this as your project's `README.md`, replacing the kit's own. Fill the
> "What this is" and "Get started" sections — they are the only two a newcomer reads — then delete
> this line.

**Intent owner:** [who owns the why]
**Created:** [date]
**Kit version adopted:** [vX.Y.Z]

## What this is

[One paragraph: the problem this project solves and for whom. Write it before you write code — if you
cannot, the charter in `CLAUDE.md` §1 is where to work it out.]

## Get started

```
# [the one command that gets a new contributor from clone to running]
```

[Prerequisites, environment variables (`.env.example`), and the first thing to try once it runs.
`RUNBOOK.md` carries the full setup, deploy, troubleshoot and rollback detail — keep this section to
the happy path.]

## How this project is run

This project follows a defined engineering process, and the documents are part of the repo:

- **`CLAUDE.md`** — the project guide: charter, per-project config, roles. Read it first.
- **`ENGINEERING-PRINCIPLES.md`** — the principles and the Definition of Done. Authoritative.
- **`DEVELOPMENT-PROCESS.md`** — how work flows: Discover → Plan → Build → Review → Release.
- **`DEVELOPMENT-STANDARDS.md`** + `profiles/<stack>.md` — the quality bar and its concrete form.
- **`START-HERE.md`** — the guided path if you are new to the process itself.
- **`RUNBOOK.md`** — operating the system: setup, deploy, troubleshoot, rollback.
- **`SECURITY.md`** — how to report a vulnerability.

Contributions go through a branch, a PR, and the gates declared in `REQUIRED-CHECKS.md`.

---

Built with [Sparkwright](https://github.com/SeaBrad72/sparkwright) [vX.Y.Z].
