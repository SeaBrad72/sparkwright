# [Project Name] — Jira Setup (work-item contract)

> **Template.** `incept --backlog jira` wrote this. Follow it once to make a Jira project satisfy the kit's §6 work-item contract (`DEVELOPMENT-PROCESS.md` §6), then verify with `sh conformance/tracker-contract.sh`. Full mapping rationale: `docs/work-tracking/adapters.md` (Jira).
>
> **Tier.** This is the kit's **server-enforced** claim tier (the *Only Assignee* transition condition, §3 — the strongest of the hosted set). Convention-tier backends (last-writer-wins, claim-when-empty + re-read) use `TRACKER-SETUP-TEMPLATE.md` instead. The two are deliberately distinct, not redundant.

## 1. Workflow statuses (the six §6 states + Blocked)
Create/rename the project workflow statuses to exactly:
`Backlog → Ready → In Progress → In Review → Released → Done`, plus `Blocked` (a status or the built-in flag). The board columns mirror these; moving a card is a state change.

## 2. Required custom fields
- **Size** — a select field (e.g. `XS/S/M/L`). **Do NOT use Story Points as size** — the kit forbids estimation-as-forecast (`DEVELOPMENT-PROCESS.md` §1).
- **Risk** — a select or short-text field for risk/complexity.
- Map the rest 1:1: Summary→title · Description (or an Acceptance Criteria field)→intent + acceptance · Assignee→owner · the development panel auto-links branches/commits/PRs.

## 3. The atomic claim — "Only Assignee" transition condition (load-bearing)
This is what makes Jira a **server-enforced** single-owner claim — the strongest of the hosted set. Without it you are on the **convention tier** (last-writer-wins).
1. Project settings → **Workflows** → edit the active workflow.
2. Select the transition **into `In Progress`**.
3. Add a **Condition** → **"Only Assignee"** (or "Only the reporter/assignee can execute"), so only the current assignee can move a card to In Progress.
4. Publish the workflow.

Now claiming = assign to the agent, then transition; a second agent cannot perform the transition → no double-claim.

## 4. Verify
Set `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_TOKEN` (an Atlassian API token), then:
`sh conformance/tracker-contract.sh`
It verifies the six states + Size/Risk fields live. Add **`--deep`** to also introspect the workflow and **verify** the In-Progress transition carries the Only-Assignee condition (turning the atomic claim from *attested* into *verified*):
`sh conformance/tracker-contract.sh --deep`
