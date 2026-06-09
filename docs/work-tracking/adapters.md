# Work-Tracking Adapter Guide

How to make a work-tracker satisfy the kit's **backlog contract** (`../../DEVELOPMENT-PROCESS.md` §6). This is **guidance, not integration code** — the kit ships no API client; it ships the mapping you apply once when you adopt a tracker.

## The contract every adapter must satisfy

`DEVELOPMENT-PROCESS.md` §6 defines a backend-agnostic work-item model. An adapter is conformant when it expresses all three:

1. **States** — `Backlog → Ready → In Progress → In Review → Released → Done` (+ `Blocked`).
2. **Required fields** — title · intent (why) · acceptance criteria · size (one-flow small) · risk/complexity · owner (human or agent) · links (spec / PR / milestone).
3. **Atomic claim** — entering **In Progress** is a race-safe single-owner change: no two agents grab the same item. This is the property the kit's multi-agent loop depends on; it is the load-bearing part of every map below.

**Claim strength is not equal across trackers — be honest about which tier you're on:**
- **Structural (server-enforced):** a server-side guard makes a double-claim *impossible*. Only **Jira** offers this among the hosted set, and only once you configure the transition condition (below).
- **Git-serialized:** **`BACKLOG.md`** — concurrent claims to the same row are serialized by git's non-fast-forward push + same-row merge conflict (stronger than last-writer-wins), but not absolute.
- **Convention (assignee-empty + re-read):** **GitHub · Azure DevOps · Linear · GitLab** — assignment is last-writer-wins, so the claim is *narrowed*, not closed: claim only when the owner field is empty, then **re-read after writing to detect a lost race**. Two agents that both read "empty" can both write; the re-read is how the loser finds out.

Each tracker is mapped against the same four headings: **State map · Field map · Atomic claim · Fit notes**.

---

## BACKLOG.md (default, reference)

The repo-native backend (`../../templates/BACKLOG-TEMPLATE.md`). Every other adapter is measured against it.

- **State map** — the six states are `##` section headings; an item is a table row under its current state's heading. Moving the row to a new section = a state change.
- **Field map** — table columns map 1:1: Item→title · Intent→intent · Acceptance criteria→acceptance · Size · Risk · Type · Owner · Links.
- **Atomic claim** — *git-serialized* (see tiers above). Moving a row into **In Progress** is a git commit; two agents claiming the same row are serialized by the non-fast-forward push rejection + a same-row merge conflict, so the loser is forced to reconcile and sees the winning claim — stronger than last-writer-wins. Not absolute: a clean auto-merge of the read-edit-push window can still lose a claim, so **pull before editing and re-read after pushing**. The claim is durable and auditable in history.
- **Fit notes** — zero setup, agent-readable, travels with the repo. Weak for large orgs, cross-repo portfolios, notifications, or dashboards — graduate to a hosted tracker when those matter.

## GitHub (Issues + Projects)

- **State map** — a Projects (v2) board **Status** field with columns for the six states; `Blocked` as a Status value or a `blocked` label.
- **Field map** — issue title→title · body→intent + acceptance · Project custom fields (single-select) for Size and Risk · labels for type · Assignees→owner · `Closes #`/PR links auto-associate.
- **Atomic claim** — *convention tier* (see tiers above). Assign the issue to exactly one agent **and** set Status→In Progress. GitHub assignment is last-writer-wins with no server-side conditional, so the claim is narrowed, not closed: claim only when Assignees is empty, assign, then **re-read** — two agents can both read "empty" and both assign, and the re-read is how the loser detects the lost race.
- **Fit notes** — best-in-class native PR linkage; Projects v2 fields are flexible. The claim is convention-enforced (no server-side guard) — for heavy multi-agent use, gate on "assignee empty" and re-read after assigning.

## Jira (Atlassian)

- **State map** — the project **workflow statuses** map to the six (rename/add statuses to match); `Blocked` as a status or the built-in flag.
- **Field map** — Summary→title · Description→intent + acceptance (or a dedicated Acceptance Criteria field) · a **Size** select custom field · a **Risk** custom field · Assignee→owner · the development panel auto-links branches/commits/PRs. Do **not** map Size to Story Points used for velocity — the kit forbids estimation-as-forecast (`DEVELOPMENT-PROCESS.md` §1).
- **Atomic claim** — *structural tier, once configured* (see tiers above). A workflow **transition** to In Progress is processed server-side; add an **"Only Assignee" (or equivalent) transition condition** so only the current assignee can perform it — then the transition is a genuine server-enforced single-owner claim, the strongest of the hosted set. **This condition is opt-in: default Jira workflows do not restrict the In-Progress transition, so without it you are back on the convention tier.**
- **Fit notes** — strongest workflow modeling and enterprise governance; a real server-enforced claim *when the transition condition is configured*. Heavyweight; resist the Story-Points-as-size trap.

## Azure DevOps (Boards)

- **State map** — the work-item **State** field / Board columns map to the six (e.g. New→Backlog, Approved→Ready, Active→In Progress, Resolved→In Review, Closed→Done; add a Released state via process customization). `Blocked` via a tag or the Blocked field.
- **Field map** — Title→title · Description→intent · the built-in **Acceptance Criteria** field→acceptance (present on **User Story** in the Agile/Scrum process; on Bug/Task/CMMI types add it via process customization) · a Size custom field · Tags for risk/type · Assigned To→owner · native branch/commit/PR linking.
- **Atomic claim** — *convention tier* (see tiers above). Assigned To + State→Active; the State write is server-side but `Assigned To` is last-writer-wins, so claim only when Assigned To is empty and **re-read after assigning** to detect a lost race.
- **Fit notes** — native PR/branch linkage and (on User Story items) a built-in Acceptance Criteria field that maps cleanly; strong in Microsoft/.NET shops. Matching all six states may need process customization.

## Linear

- **State map** — workflow **states** (Backlog, Todo, In Progress, In Review, Done) map to the six; add a **Released** state or treat Done as Released+Done explicitly; `Blocked` via a label or a blocked-by relation.
- **Field map** — title · description→intent + acceptance · the **estimate** field→size · labels for risk/type · Assignee→owner · GitHub/GitLab sync auto-links PRs and can auto-advance state on PR open.
- **Atomic claim** — *convention tier* (see tiers above). Assignee + state→In Progress; Linear applies a single update atomically (no partial write), but assignment is still last-writer-wins, so claim only when the assignee is empty and **re-read** — same tier as GitHub/ADO. The Git sync moving the item on PR open is a corroborating signal, not the claim.
- **Fit notes** — fast, developer-native, excellent Git sync. Opinionated state model — map Released deliberately. SaaS-only (no self-host).

## GitLab (Issues / Boards)

- **State map** — GitLab issues are natively open/closed, so model the six states with **scoped labels** (`workflow::ready`, `workflow::in-progress`, `workflow::in-review`, …) as board lists; `Blocked` via a scoped label or a blocking-issue link.
- **Field map** — title · description→intent + acceptance · scoped labels for size/risk/type · Assignee→owner · native MR/commit linking (`Closes #`).
- **Atomic claim** — *convention tier* (see tiers above). Assignee + set the `workflow::in-progress` scoped label. **Scoped labels are mutually exclusive** — applying one removes the prior `workflow::*`, so an issue is never in two states at once. But that is a single-**state** guarantee, **not** a single-**claim** one: two agents can both apply `workflow::in-progress` and both self-assign on an unowned item (assignee is last-writer-wins). So GitLab is the same convention tier as GitHub/ADO — claim only when the assignee is empty and **re-read**; the scoped label just keeps state hygiene clean.
- **Fit notes** — scoped labels keep state unambiguous (never two `workflow::` labels at once); native MR linkage; **self-hostable** (key for regulated / air-gapped enterprises). Board state lives in labels rather than a first-class field. The claim itself is convention-enforced, not stronger than GitHub.

---

## Bring your own tracker

Any tracker works if it satisfies the three contract points:

1. **States** — map its statuses to the six (+ Blocked).
2. **Fields** — map the seven required fields to its fields/labels/custom fields.
3. **Atomic claim** — find a **race-safe** single-owner transition. The only *structural* guard among the named set is a **server-enforced transition condition** (Jira's "Only Assignee" transition), which makes a double-claim impossible. Most trackers have **no** such primitive — assignment is last-writer-wins, and conveniences like GitLab's mutually-exclusive scoped labels guarantee single-*state*, not single-*claim*. For those, document the compensating convention — claim only when the owner field is empty + **re-read after writing** + a short claim TTL — **and record the residual risk** that two agents could still double-claim. Do not pretend the gap is closed; the kit's multi-agent safety depends on naming it.

> General PM tools (Asana, Monday, ClickUp) can be mapped via this recipe, but they lack a race-safe claim primitive and native PR/commit linkage — treat the atomic-claim and traceability caveats above as binding before using one as a multi-agent backlog.
