# Work-Tracking Adapter Guide

How to make a work-tracker satisfy the kit's **backlog contract** (`../../DEVELOPMENT-PROCESS.md` §6). This is **guidance, not integration code** — the kit ships no API client; it ships the mapping you apply once when you adopt a tracker.

## The contract every adapter must satisfy

`DEVELOPMENT-PROCESS.md` §6 defines a backend-agnostic work-item model. An adapter is conformant when it expresses all three:

1. **States** — `Backlog → Ready → In Progress → In Review → Released → Done` (+ `Blocked`).
2. **Required fields** — title · intent (why) · acceptance criteria · size (one-flow small) · risk/complexity · owner (human or agent) · links (spec / PR / milestone).
3. **Atomic claim** — entering **In Progress** is a race-safe single-owner change: no two agents grab the same item. This is the property the kit's multi-agent loop depends on; it is the load-bearing part of every map below.

Each tracker is mapped against the same four headings: **State map · Field map · Atomic claim · Fit notes**.

---

## BACKLOG.md (default, reference)

The repo-native backend (`../../templates/BACKLOG-TEMPLATE.md`). Every other adapter is measured against it.

- **State map** — the six states are `##` section headings; an item is a table row under its current state's heading. Moving the row to a new section = a state change.
- **Field map** — table columns map 1:1: Item→title · Intent→intent · Acceptance criteria→acceptance · Size · Risk · Type · Owner · Links.
- **Atomic claim** — moving a row into **In Progress** is a git commit. Git is the lock: a second agent racing the same claim hits a merge conflict / rejected non-fast-forward push, so exactly one wins. The claim is durable and auditable in history.
- **Fit notes** — zero setup, agent-readable, travels with the repo. Weak for large orgs, cross-repo portfolios, notifications, or dashboards — graduate to a hosted tracker when those matter.

## GitHub (Issues + Projects)

- **State map** — a Projects (v2) board **Status** field with columns for the six states; `Blocked` as a Status value or a `blocked` label.
- **Field map** — issue title→title · body→intent + acceptance · Project custom fields (single-select) for Size and Risk · labels for type · Assignees→owner · `Closes #`/PR links auto-associate.
- **Atomic claim** — assign the issue to exactly one agent **and** set Status→In Progress. Convention: an agent claims only if Assignees is empty, then assigns itself. The assignment is observable but last-writer-wins, so the empty-check-before-claim is what makes it safe.
- **Fit notes** — best-in-class native PR linkage; Projects v2 fields are flexible. The claim is convention-enforced (no server-side guard) — for heavy multi-agent use, gate on "assignee empty" and re-read after assigning.

## Jira (Atlassian)

- **State map** — the project **workflow statuses** map to the six (rename/add statuses to match); `Blocked` as a status or the built-in flag.
- **Field map** — Summary→title · Description→intent + acceptance (or a dedicated Acceptance Criteria field) · a **Size** select custom field · a **Risk** custom field · Assignee→owner · the development panel auto-links branches/commits/PRs. Do **not** map Size to Story Points used for velocity — the kit forbids estimation-as-forecast (`DEVELOPMENT-PROCESS.md` §1).
- **Atomic claim** — Assignee + a workflow **transition** to In Progress, guarded by a condition (only the assignee may transition). Jira transitions are server-side atomic — this is a genuine race-safe claim, the strongest of the hosted options.
- **Fit notes** — strongest workflow modeling and enterprise governance; real transactional claim via transition conditions. Heavyweight; resist the Story-Points-as-size trap.

## Azure DevOps (Boards)

- **State map** — the work-item **State** field / Board columns map to the six (e.g. New→Backlog, Approved→Ready, Active→In Progress, Resolved→In Review, Closed→Done; add a Released state via process customization). `Blocked` via a tag or the Blocked field.
- **Field map** — Title→title · Description→intent · the built-in **Acceptance Criteria** field→acceptance · a Size custom field · Tags for risk/type · Assigned To→owner · native branch/commit/PR linking.
- **Atomic claim** — Assigned To + State→Active; the State change is server-side. Enforce single-assignee; claim only when Assigned To is empty.
- **Fit notes** — native PR/branch linkage and a built-in Acceptance Criteria field that maps cleanly; strong in Microsoft/.NET shops. Matching all six states may need process customization.

## Linear

- **State map** — workflow **states** (Backlog, Todo, In Progress, In Review, Done) map to the six; add a **Released** state or treat Done as Released+Done explicitly; `Blocked` via a label or a blocked-by relation.
- **Field map** — title · description→intent + acceptance · the **estimate** field→size · labels for risk/type · Assignee→owner · GitHub/GitLab sync auto-links PRs and can auto-advance state on PR open.
- **Atomic claim** — Assignee + state→In Progress; Linear's per-issue updates are transactional. Single-assignee convention; the Git sync moving the item on PR open can serve as a corroborating signal.
- **Fit notes** — fast, developer-native, excellent Git sync. Opinionated state model — map Released deliberately. SaaS-only (no self-host).

## GitLab (Issues / Boards)

- **State map** — GitLab issues are natively open/closed, so model the six states with **scoped labels** (`workflow::ready`, `workflow::in-progress`, `workflow::in-review`, …) as board lists; `Blocked` via a scoped label or a blocking-issue link.
- **Field map** — title · description→intent + acceptance · scoped labels for size/risk/type · Assignee→owner · native MR/commit linking (`Closes #`).
- **Atomic claim** — Assignee + set the `workflow::in-progress` scoped label. **Scoped labels are mutually exclusive** — setting one removes the prior `workflow::*` — which gives a clean single-state guarantee; combined with assignee-empty-before-claim this is race-safe in practice.
- **Fit notes** — scoped labels yield clean mutually-exclusive states; native MR linkage; **self-hostable** (key for regulated / air-gapped enterprises). Board state lives in labels rather than a first-class field.

---

## Bring your own tracker

Any tracker works if it satisfies the three contract points:

1. **States** — map its statuses to the six (+ Blocked).
2. **Fields** — map the seven required fields to its fields/labels/custom fields.
3. **Atomic claim** — find a **race-safe** single-owner transition. Prefer a server-side transition (Jira) or a mutually-exclusive state primitive (GitLab scoped labels). If your tool has **no** race-safe primitive, document a compensating convention — single-assignee + check-assignee-empty-before-claim + a short claim TTL — **and record the residual risk** that two agents could still double-claim. Do not pretend the gap is closed; the kit's multi-agent safety depends on naming it.

> General PM tools (Asana, Monday, ClickUp) can be mapped via this recipe, but they lack a race-safe claim primitive and native PR/commit linkage — treat the atomic-claim and traceability caveats above as binding before using one as a multi-agent backlog.
