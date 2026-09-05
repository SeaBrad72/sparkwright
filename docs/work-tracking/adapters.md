# Work-Tracking Adapter Guide

How to make a work-tracker satisfy the kit's **backlog contract** (`../../DEVELOPMENT-PROCESS.md` §6). This is **guidance, not integration code** — the kit ships no API client; it ships the mapping you apply once when you adopt a tracker.

## The contract every adapter must satisfy

`DEVELOPMENT-PROCESS.md` §6 defines a backend-agnostic work-item model. An adapter is conformant when it expresses all three:

1. **States** — `Backlog → Ready → In Progress → In Review → Released → Done` (+ `Blocked`).
2. **Required fields** — title · intent (why) · acceptance criteria · size (one-flow small) · risk/complexity · owner (human or agent) · links (spec / PR / milestone).
3. **Atomic claim** — entering **In Progress** is a race-safe single-owner change: no two agents grab the same item. This is the property the kit's multi-agent loop depends on; it is the load-bearing part of every map below.

**Claim strength is not equal across trackers — be honest about which tier you're on:**
- **Structural (server-enforced):** a server-side guard makes a double-claim *impossible*. Only **Jira** offers this among the hosted set, and only once you configure the transition condition (below).
- **Forge-serialized at claim time:** **`BACKLOG.md`** with `scripts/board-claim.sh` — the claim is a ref on the forge (`refs/claims/<ROW-ID>`), created by a push with no `+`, so the forge's non-fast-forward rule refuses the second claimant **at claim time** and names the first. A claim ref stops *accidental* double-work between cooperating sessions; it does **not** stop an actor with push rights who force-pushes or deletes the ref. One tier above git-serialized, below structural.
- **Git-serialized:** **`BACKLOG.md`** with no claim verb — concurrent claims to the same row are serialized by git's non-fast-forward push + same-row merge conflict (stronger than last-writer-wins), but **at merge time, not claim time**: both sessions have already built by the time git notices.
- **Convention (assignee-empty + re-read):** **GitHub · Azure DevOps · Linear · GitLab** — assignment is last-writer-wins, so the claim is *narrowed*, not closed: claim only when the owner field is empty, then **re-read after writing to detect a lost race**. Two agents that both read "empty" can both write; the re-read is how the loser finds out.

Each tracker is mapped against the same four headings: **State map · Field map · Atomic claim · Fit notes**.

---

## BACKLOG.md (default, reference)

The repo-native backend (`../../templates/BACKLOG-TEMPLATE.md`). Every other adapter is measured against it.

- **State map** — the six states are `##` section headings; an item is a table row under its current state's heading. Moving the row to a new section = a state change.
- **Row identity** — a row's id is the **first backticked token of its Item cell**, matching `[A-Z0-9][A-Z0-9-]*`; decoration before it (`✅`, `⏸`, `**`) is allowed, so `` | ✅ **`KW6-A2`** — extract the parser | `` resolves to `KW6-A2`. One grammar, four consumers: it is the `Kit-Row` trailer value, the ref name `board-claim.sh` pushes, the id `backlog-current.sh`'s Disposition clause resolves, and what `loop-state.sh`'s row check reports as `resolved`. **It must be unique across the board** — two rows carrying one id are refused as AMBIGUOUS rather than silently binding to whichever came first. A row with only a prose title resolves to nothing. What `resolved` proves: the id names exactly one row on THIS board. What it does not prove: that the row describes the change (a row boarded and closed in the same PR resolves), or that anyone but the commit's own author typed it.
- **Field map** — table columns map 1:1: Item→title · Intent→intent · Acceptance criteria→acceptance · Size · Risk · Type · Owner · Links.
- **Atomic claim** — *forge-serialized at claim time* (see tiers above). `sh scripts/board-claim.sh claim <ROW-ID>` pushes an orphan commit to `refs/claims/<ROW-ID>` on origin **without** a `+`, so the forge's non-fast-forward rule is a server-side compare-and-swap: the second claimant is refused **immediately** and told who holds the row, on which branch, since when. The same verb moves the row Ready → In Progress, so the claim and the row move are one act rather than two that can diverge. `release` deletes the ref under a compare-and-swap old value; `check [<ROW>|--all]` lists live claims; the CI presence gate's `--claims` arm reds any In Progress row without a live claim for this branch, and `promotion-verify.sh actuate` releases the claim at merge.
  **Honest ceiling, stated plainly:** this stops *accidental* double-work between cooperating sessions (it is a coordination lock, not an access control). It does **not** stop an actor with push rights, and — measured, not assumed — such an actor needs no `--force` to take the row: a claim commit that is a *child* of the existing one is a fast-forward, so a plain push replaces the holder. **A cooperating client refuses (`fetch first`); an actor with push rights overwrites with or without `--force`,** and can delete the ref outright. **Whether that leaves a trace is forge-dependent:** on an organisation with git-event audit logging the pusher is recorded; on a **personal repository** there is no git-event audit log and branch activity covers `refs/heads/*` only, so a deleted claim ref leaves **no trace**. The claimant is the commit's committer — recorded, not authenticated. Without the verb the backend falls back to the *git-serialized* tier, where the two claims collide only at the second merge.
  **Scope today, so nobody assumes a gate they do not have:** adopters get `scripts/board-claim.sh` in the export, but the CI claims arm is **kit-CI only** — an adopter enables it by adding `--claims` to `backlog-presence.sh` in its own presence job, which needs `origin` reachable from that job (the pre-push hook deliberately never passes it, so a push-time gate never needs the forge).
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
- **Bootstrap & verify** — `incept --backlog jira` writes a project-stamped `JIRA-SETUP.md` (statuses · Size/Risk fields · the Only-Assignee condition); `sh conformance/tracker-contract.sh` verifies the live instance (states/fields verified; the transition condition attested).

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

## Which gates bind

The kit's board-bound gates read `BACKLOG.md`, and **only** `BACKLOG.md`. On any hosted backend they say so, out loud, rather than passing quietly — a green light over governance nobody verified is worse than a red (`D-240903-1` §3).

| Gate | `md` | `github` · `jira` · `ado` · `linear` · `gitlab` |
|---|---|---|
| `backlog-presence` (PR-cell binding + `--claims`) | binds | **NOT ENFORCED** — rc 3, red; green-with-notice under a ratified `board-governance` waiver |
| `backlog-current` (state-appropriate evidence) | binds | **NOT ENFORCED** — rc 3, red; same waiver rule |
| `loop-state` row check (`Kit-Row` resolves) | binds (reports `resolved`) | **NOT ENFORCED** — refused under `enforce`; same waiver rule |
| `board-claim.sh` | binds | refuses (it writes `refs/claims/<ROW-ID>` for an `md` board only) |
| `tracker-contract.sh` | — | states/fields verified, claim condition attested |

**What NOT ENFORCED means, and what it does not.** It is a colour, not a control: the kit has no seam that can read your tracker, so it declines to claim it checked one. Nothing you change in a pull request clears it. Two ladders exist:

1. **`TRACKER-BACKED-GOVERNANCE`** — the tracker read seam. Until it ships, this gap is real.
2. **A ratified `board-governance` waiver** in `WAIVER-REGISTER.md` — a human-signed, dated, ≤90-day row with an owner, a ratifier and a remediation plan. It renders the three gates green **and the NOT ENFORCED notice still prints on every run**, so the exception is never invisible. `incept` stamps the row for you on a non-`md` choice, with `[owner]` and `[security-owner]` placeholders that a human must fill — a stamp is not a ratification, and `sh conformance/waivers-valid.sh --active board-governance` refuses it until both cells are real.

**Who can sign it, stated rather than implied.** The register is read from the pull request's **own tree**, so the author, the `Owner` and the `Ratified-by` of a `board-governance` row may all be the same person, in one commit — this is the register's standing self-ratification ceiling (every waiver in it has it), narrowed here by nothing. What *is* separated in adopter CI: the register comes from the PR head, but `conformance/waivers-valid.sh` — the validator that grades it — is the **base checkout's** copy, so a PR cannot write itself a waiver and rewrite the rules that judge it in the same commit. Segregation of duties over the row itself is the forge's job (a CODEOWNER review on `WAIVER-REGISTER.md`), not this gate's.

The local `pre-push` hook is the one consumer that lets rc 3 through: it relays the sentence and allows the push, because a push-time speed bump is not where you should first learn the kit has no tracker seam. The required CI context still reds.

## Bring your own tracker

Any tracker works if it satisfies the three contract points:

1. **States** — map its statuses to the six (+ Blocked).
2. **Fields** — map the seven required fields to its fields/labels/custom fields.
3. **Atomic claim** — find a **race-safe** single-owner transition. The only *structural* guard among the named set is a **server-enforced transition condition** (Jira's "Only Assignee" transition), which makes a double-claim impossible. Most trackers have **no** such primitive — assignment is last-writer-wins, and conveniences like GitLab's mutually-exclusive scoped labels guarantee single-*state*, not single-*claim*. For those, document the compensating convention — claim only when the owner field is empty + **re-read after writing** + a short claim TTL — **and record the residual risk** that two agents could still double-claim. Do not pretend the gap is closed; the kit's multi-agent safety depends on naming it.

> General PM tools (Asana, Monday, ClickUp) can be mapped via this recipe, but they lack a race-safe claim primitive and native PR/commit linkage — treat the atomic-claim and traceability caveats above as binding before using one as a multi-agent backlog.
