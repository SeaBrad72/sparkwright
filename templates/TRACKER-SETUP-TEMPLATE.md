# [Project Name] — [BACKEND] Setup (work-item contract)

> **Template.** `incept --backlog [BACKEND]` wrote this. `[BACKEND]` is a **convention-tier** backend: its claim is enforced by discipline (assign-when-empty + re-read), not by server config. Full mapping: `docs/work-tracking/adapters.md` (find the `[BACKEND]` section).

## Board = the six §6 states
Create board columns for `Backlog → Ready → In Progress → In Review → Released → Done` (+ `Blocked` as a column or label). Moving a card is a state change (`DEVELOPMENT-PROCESS.md` §6).

## Required fields
title · intent (why) · acceptance criteria · Size (not story points) · Risk · owner · links (spec / PR / milestone) — map these to the backend's native fields/labels per `adapters.md`.

## Identity
Create one agent account on this tracker with the narrowest role that can assign and transition; never use a person's account (`adapters.md` §The agent's identity on each tracker).

## The claim (convention tier — be honest about it)
Assignment is last-writer-wins, so the claim is **narrowed, not closed**: claim only when the owner field is **empty**, set it, then **re-read after writing** to detect a lost race. Two agents that both read "empty" can both write; the re-read is how the loser finds out. Jira can reach a server-enforced claim only through a workflow that already carries an assignee-only restriction (measured to display, not yet to enforcement; `JIRA-SETUP` §3 via `incept --backlog jira`).
