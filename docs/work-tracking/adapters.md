# Work-Tracking Adapter Guide

How to make a work-tracker satisfy the kit's **backlog contract** (`../../DEVELOPMENT-PROCESS.md` §6). This is **guidance, not integration code** for most backends — the kit ships a Jira reader + write verbs (`scripts/tracker-jira.sh`, `scripts/tracker-read.sh`) as its one shipped adapter; for every other declared tracker it ships the mapping you apply once when you adopt it, with no adapter behind it.

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
- **Atomic claim** — *forge-serialized at claim time* (see tiers above). `sh scripts/board-claim.sh claim <ROW-ID>` pushes an orphan commit to `refs/claims/<ROW-ID>` on origin **without** a `+`, so the forge's non-fast-forward rule is a server-side compare-and-swap: the second claimant is refused **immediately** and told who holds the row, on which branch, since when. The same verb moves the row Ready → In Progress, so the claim and the row move are one act rather than two that can diverge. `release` deletes the ref under a compare-and-swap old value; `check [<ROW>|--all]` lists live claims; the CI presence gate's `--claims` arm reds any In Progress row without a live claim for this branch, and **both** `promotion-verify.sh actuate` **and** `land` release the claim at merge (`B2-SESSION-IDENTITY-LEDGER`; `land` did not, and eight shipped slices left their refs behind).

  **Since `B2-SESSION-IDENTITY-LEDGER` (2026-09-16), four additions — all on the same honest tier:**
  - **A declared session on the claim.** The CLAIM file carries `session: <id> (declared)`, minted by `claim` into `<toplevel>/.kit-run/session.id` (gitignored, per-worktree). **Declared, never authenticated** — it is an input to nothing that authorizes. A re-claim from a *different* session on the same claimant+branch extends the claim with a **child commit under a lease**, so the ref becomes the chain of sessions that held the row; the same session pushes nothing. A claim written before the field existed reads `unknown`.
  - **`status` — who holds what, with evidence.** `sparkwright status` renders every claim with its session chain, `branch on origin` / `pr` / `board` evidence lines, a `LIVE` or `STALE-PROVABLE (P?)` reading, and the last release record for the row.
  - **`release --stale` must PROVE staleness.** Two proofs: **P2** a non-cross-repository PR from that head is MERGED and none is OPEN · **P3** the row sits in `## Done` on the default branch's board. Neither "no commits since" nor **"the branch is absent on origin"** is a proof — the latter was one in the first build and was withdrawn on live acceptance, because under one-push-per-PR a slice's branch reaches origin only at its final push, so it is the *normal* state of a healthy in-build slice. Both are printed as evidence. A dead session whose work never reached origin is the human dial's case, deliberately. P2/P3 are the forge PR and the **md board**: on a declared hosted tracker `claim` refuses outright (S-L5), so no claim ref exists there to reclaim — the tracker seam (Milestone B, `TRACKER-BACKED-GOVERNANCE`) owes its own Done-proof before a hosted backend gets a claim primitive, and no fourth proof is invented to cover a case that cannot occur. With no proof it refuses (rc 1), prints the evidence, and names the one human override (`KIT_CLAIM_FORCE_RELEASE="<reason>"`). Every non-holder release, forced or proven, pushes a record to `refs/claims-log/<ROW-ID>` **before** the delete. ⚠️ That namespace is one more unprotected ref: it is a **trace, not tamper-evidence**.
  - **`resume` — the cold start.** `sparkwright resume <ROW-ID>` reconstructs a parked slice from the claim, the branch head's trailers, the design GO record (label printed verbatim beside the note's own committer, *as recorded, not re-derived*), the plan, the review record and the board row, and names ONE next step from a fixed table. **Read-only**: not a claim, not a checkout, not a write.
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
- **Bootstrap & verify** — `incept --backlog jira` writes a project-stamped `JIRA-SETUP.md` (statuses · Size/Risk fields · the Only-Assignee condition); verify in this order: `sh conformance/tracker-contract.sh --preflight` (reach, credential, permissions, tier card; read-only) → `--fields` (the required create fields and the conf lines to paste) → no flag (states and fields verified live) → `--deep` (the Only-Assignee condition on every transition into In Progress, a Jira-admin once-off).

### Moving an existing board

An adopter whose live board is `BACKLOG.md` moves its open rows into the declared tracker with one verb, `sparkwright board migrate` (`scripts/board-migrate.sh`). It reads the Ready and Blocked tables and the `## Backlog (unrefined)` bullets, and creates each card through `board create` (so every card gets that verb's required-field refusal and its read-back proof) and `tracker-jira.sh transition`; it writes nowhere else. It needs a declared tracker (`.kit/tracker.conf`); on `md` it refuses. Today the tracker is Jira.

**The plan decides every row.** Nothing is inferred. You write a TAB-separated plan file, `#` starts a comment, and the order of the `row` lines is the rank order (a Jira Software board ranks a new issue last, so creating in plan order ranks the cards in plan order):

```
epic	Milestone C
epic	Parked
row	SHELLCHECK-NORC	keep	Milestone C
row	OLD-IDEA	drop	-	superseded by the C roster work
row	DUP-OF-IT	merge:SHELLCHECK-NORC	-	same fail-open class
row	THE-SWITCH	stay	-	closes in the frozen file
new	NEW-CARD	Milestone C	S	med	a card that is on no board today
```

- `epic` is created first, in file order. A name is 1 to 60 characters. An epic that receives no card is still created.
- `keep` makes a card under the named (declared) epic; under an epic named `Parked` it also gets the label `parked`. `drop` makes no card, and `--freeze` writes the Done entry "dropped at migration triage - <reason>". `merge:<OTHER>` makes no card; `<OTHER>` must be a `keep` row, its card gains an "Absorbs" line, and `--freeze` writes a Done pointer. `stay` leaves the row, unedited, in the frozen file (use it for rows in Done or Released, for work in flight, and for the switch row itself). `drop` and `merge` need a reason of 1 to 200 characters.
- `new` declares a card that is on no board today. Its ID is the summary and its intent the description. Size and Risk may be `-`, which means `S` and `med`. New cards are created after every `keep` card, in plan order.
- A row in In Progress or In Review must be `stay`; work in flight is not moved by a batch.

**The card.** Item becomes the summary (cut at the last space before 240 characters, the full text opening the description), and Intent, Acceptance criteria, Links and Success metric become four labelled description sections. Size and Risk go through the `field.size` / `field.risk` mapping. Type `defect` or `bug` makes a Bug, anything else a Task. A Ready row is transitioned to `state.ready`, a Blocked row to `state.blocked`, and an unrefined or parked row is left in the workflow's initial status, which the preflight cannot read; a mismatch with `state.backlog` shows in the census. No assignee is set. Bullets in the unrefined section are parsed only in the exact shape `> - [ ] **`ID`** (Size, ...) - text`; any other checkbox line is not a row, stays where it is, and is counted in the dry run as "left in place".

**The run.**

1. `sparkwright board migrate --from BACKLOG.md --plan <plan> --dry-run`. It makes no tracker call and needs no credentials. It refuses, listing every reason at once, when a row to be moved is missing from the plan, an ID repeats, a plan row is not on the board, an epic is undeclared, a merge target is not a `keep` row, a reason is missing, a field holds a control byte, a `new` line is malformed, or the plan creates more epics and cards than `list_cap`. Read the printed plan: one line per epic and card, in the order they will be created and ranked, then a count line.
2. Optional: `--screen <file>` takes an identifier list in the publish gate's grammar (a plain line is a case-insensitive substring, a `word:` line is a whole word) and refuses any card whose summary or description matches, printing only the row ID and a hit count, never the entry or the text. It runs on a dry run too.
3. The live run (the same command without `--dry-run`), with `KIT_TRACKER_USER` / `KIT_TRACKER_TOKEN` exported in your own shell. A preflight that only reads refuses before the first write if the credentials are missing, the account holds no write permission, an issue type or its `parent` / `labels` / description field is missing, a Size or Risk value is not an allowed value of its field, a required field would not be filled, or a mapped state is not a status of the project. Then it creates the epics, then the cards in plan order, appending `ROW-ID<TAB>KEY<TAB>created|done` to the ledger (`--ledger`, default `.kit/board-migration.tsv`) as it goes. A refusal from `board create` or a transition stops the run naming the row; nothing is retried blind. Re-run the same command to resume: finished rows are skipped, a created row only gets its transition. At the end the census reads the project and exits 1 if its card count differs from the ledger's (`census OK` otherwise).
4. `sparkwright board migrate --from BACKLOG.md --plan <plan> --ledger <ledger> --freeze --date <YYYY-MM-DD>` rewrites the markdown board in place: a "this board is history" banner under the title, the moved rows removed (each of Ready, Blocked and the unrefined section keeps its heading and gains a "Moved to <project>" line), and a Done entry for every dropped and merged row. It makes no tracker call, refuses unless every planned row has a finished ledger line, and a second run changes nothing.

Five ceilings. (1) Rank is the creation order; the fixtures prove the order, not that your site ranks by it, so look at the board. (2) A crash between a card's create and its ledger line, followed by a re-run, would create that card twice; the census shows it, and the cure is deleting the duplicate by hand. (3) The permission probe cannot name which write permission the account holds: it reports only that it holds one, so a missing create permission fails on the first epic and a missing transition permission fails on the first Ready card (resumable from the ledger). (4) The preflight cannot read the status a new card lands in; a workflow whose initial status is not `state.backlog` shows only in the census by state. (5) The census counts epics in the mapped `state.*` statuses; epics on a separate workflow show as a mismatch after a good run. `board create` takes the backend from the `CLAUDE.md` declaration, so for the live run the declaration must already name the tracker.

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

This is the **one place** this is stated — every other section, and every other doc (`RUNBOOK.md`, `JIRA-SETUP-TEMPLATE.md`), links here rather than repeating it. `jira` is the kit's **one shipped adapter** (`TRACKER-BACKED-GOVERNANCE`); a **declared tracker with no adapter** — `github` · `linear` · `ado` · `gitlab` — has no seam that can read it, so it is named **UNBOUND** below rather than left to be inferred.

| gate | `md` | `jira` (the one shipped adapter) | declared tracker, no adapter (`github`/`linear`/`ado`/`gitlab`) |
|---|---|---|---|
| `loop-state` (row check, `Kit-Row` resolves) | **binds** — PR-tree, required context | the trusted job binds the row leg through its own tracker record; the **PR-tree job's own row leg** **stands aside (base requires `tracker-board-gates`)** once the base declares the tracker, the base's `.kit/tracker.conf` passes the base's own validator, and the base branch's LIVE protection requires `tracker-board-gates` — otherwise **red (rc 1) — its refusal names the bind cure**. On a **private** repo, reading the base's protection is unmeasured (LS-D4): if it returns nothing, the step-aside stays off, red, curable by a waiver | **red (rc 1) — its refusal sentence reads NOT ENFORCED** |
| `backlog-presence` (PR-cell binding + `--claims`) | **binds** — PR-tree, required context | the trusted job (`tracker-board-gates`, required) binds it; the PR-tree job **stands aside (base requires tracker-board-gates)** only when the base's LIVE branch protection requires that context — otherwise **NOT ENFORCED (rc 3)**, red, with its cure | **NOT ENFORCED (rc 3)** — the same cures the list below gives (move to `md`, a ratified waiver, or a future adapter) |
| `backlog-current` (state-appropriate evidence) | **not run** as a merge gate — the kit self-tests the check instead | **binds** — inside `tracker-board-gates` only | **not run** at all |
| `board-drift` | **not run** — not scheduled | **runs (detector — never blocks)** — the scheduled `tracker-board-drift` job | **not run** — not shipped; `incept` stamps no conf for it |
| `ceremony-binding` | **binds** — backend-independent | **binds** | **binds** |

**What you do, per non-binding outcome:**
- **`loop-state`'s row leg and `backlog-presence`, both NOT ENFORCED (adapterless tracker)** — no adapter exists to cure either short of: move the backlog to `md`, or carry a ratified `board-governance` waiver (below), or (future) build/ship an adapter. There is no equivalent of `tracker-board-gates` for these trackers today, so "bind `tracker-board-gates`" is not an available cure here.
- **`loop-state`'s PR-tree row leg on `jira`** — one bind act now clears BOTH gates: add `tracker-board-gates` to `REQUIRED-CHECKS.md`, then **HUMAN ACT (repo admin) — an agent stops and asks:** run `sh scripts/branch-protection-apply.sh --apply` so the base's LIVE branch protection requires it; only then does the PR-tree row leg stand aside for `loop-state` too. Until that bind is live, the row leg stays red unless a ratified `board-governance` waiver covers it (below — `templates/WAIVER-REGISTER.md`).
- **`backlog-presence` on `jira`, before your first PR** — add `tracker-board-gates` to `REQUIRED-CHECKS.md`, then **HUMAN ACT (repo admin) — an agent stops and asks:** run `sh scripts/branch-protection-apply.sh --apply` (it needs an admin-authenticated `gh`) so your base's LIVE branch protection requires it; only then does the PR-tree job stand aside. Success signal: a read-only run of the same script (no `--apply`) reports `Dry-run: nothing to add — every declared context is already bound live.` Skip this and every PR is **NOT ENFORCED (rc 3)** with the cure named in the red.
- **`backlog-current` not run (jira, outside `tracker-board-gates`)** — nothing to do; it only ever runs there.
- **`backlog-current` / `board-drift` not run at all (adapterless tracker)** — same cure as above: move to `md`, build/ship an adapter, or accept the gap named honestly.

**Say it plainly:** a declared tracker with **no adapter** — `github`, `linear`, `ado`, `gitlab` — is **UNBOUND** for every gate above except `ceremony-binding` (which is backend-independent by construction). Nothing you do inside a pull request changes that; only the cures above do.

**How we know (proof per "binds" cell, named legs — read them yourself; this doc is timeless, not a build-day snapshot):**
- `loop-state` (`md` row leg; the jira row leg binds only inside the trusted job's own tracker record; the PR-tree row leg's step-aside): `conformance/loop-state.sh::selftest` — the row-resolution legs (e.g. "a Kit-Row leading an Item cell must RESOLVE") for `md`; the trusted-job row binding is proven by the treeless-positive checks against `seam_row_state`/`seam_row_flag` on a good tracker record; the step-aside itself is legs `delegate/delegated`, `delegate/not-live`, `delegate/record-wins` and `delegate/other-legs-bind`; the workflow wiring behind it is pinned by the kit's own CI (`conformance/adopter-gates-parity.sh::assert_t2_base_checkout_loop_state` and `assert_t2_live_contexts_loop_state`).
- `backlog-presence` (`md`, `jira`, and the base-decided step-aside): `conformance/backlog-presence.sh::selftest` — legs `delegate/delegated` and `delegate/not-live` exercise the step-aside predicate the trusted-job wiring depends on.
- `backlog-current` (`jira`): `conformance/backlog-current.sh::selftest` — leg `T9/L0`.
- `board-drift` (`jira`): `conformance/board-drift.sh::selftest` — legs `J` and `K`, the tracker-arm §4.5 inversion pair (~:498-515).
- `ceremony-binding` (all three columns): `conformance/ceremony-binding.sh::selftest` — backend-independent by construction.

**What NOT ENFORCED means, and what it does not.** It is a colour, not a control: for a tracker with no adapter, the kit has no seam that can read it, so it declines to claim it checked one. Nothing you change in a pull request clears it. Two ladders exist:

1. **Build or adopt an adapter** — `jira` is the one shipped today (`TRACKER-BACKED-GOVERNANCE`); `github`/`linear`/`ado`/`gitlab` have none yet.
2. **A ratified `board-governance` waiver** in `WAIVER-REGISTER.md` — a human-signed, dated, ≤90-day row with an owner, a ratifier and a remediation plan. It renders the affected gates green **and the NOT ENFORCED notice still prints on every run**, so the exception is never invisible. `incept` stamps the row for you on a non-`md` choice, with `[owner]` and `[security-owner]` placeholders that a human must fill — a stamp is not a ratification, and `sh conformance/waivers-valid.sh --active board-governance` refuses it until both cells are real.

**Who can sign it, stated rather than implied.** The register is read from the pull request's **own tree**, so the author, the `Owner` and the `Ratified-by` of a `board-governance` row may all be the same person, in one commit — this is the register's standing self-ratification ceiling (every waiver in it has it), narrowed here by nothing. What *is* separated in adopter CI: the register comes from the PR head, but `conformance/waivers-valid.sh` — the validator that grades it — is the **base checkout's** copy, so a PR cannot write itself a waiver and rewrite the rules that judge it in the same commit. Segregation of duties over the row itself is the forge's job (a CODEOWNER review on `WAIVER-REGISTER.md`), not this gate's.

The local `pre-push` hook relays `backlog-presence`'s rc 3 (NOT ENFORCED) and allows the push; `loop-state`'s row-leg refusal on an adapterless tracker follows the `KIT_PUSH_DECL` dial — allowed under `observe`, refused under `enforce` unless a waiver covers it. Separately, on `jira` (a tracker WITH an adapter), when under `KIT_PUSH_DECL=enforce` (set in `.kit/dials.conf`) the verdict is a genuine NOT ENFORCED that the *local* reader could not verify, the hook downgrades to allow and prints a note that CI is the backstop, rather than blocking every local push on a condition no local commit can fix (`hooks/pre-push:308-334`). "Could not verify" has two distinct sources: the reader's own rc 1 (a refusal, including an S-2 pin mismatch) and rc 2 (unverified — no token, or unreachable), both marked at `hooks/pre-push:212-217`; and the hook's own stop when `origin/main` and `origin/master` carry no `.kit/tracker.conf` — it never calls the reader and sends no token (`hooks/pre-push:171-178`). The required CI context still reds.

Other gates, briefly:
- `board-claim.sh` — binds on `md` only; refuses elsewhere (it writes `refs/claims/<ROW-ID>` for an `md` board only).
- `tracker-contract.sh` — not a per-PR gate; verifies a live `jira` instance's states/fields and attests the claim condition.

## Bring your own tracker

Any tracker works if it satisfies the three contract points:

1. **States** — map its statuses to the six (+ Blocked).
2. **Fields** — map the seven required fields to its fields/labels/custom fields.
3. **Atomic claim** — find a **race-safe** single-owner transition. The only *structural* guard among the named set is a **server-enforced transition condition** (Jira's "Only Assignee" transition), which makes a double-claim impossible. Most trackers have **no** such primitive — assignment is last-writer-wins, and conveniences like GitLab's mutually-exclusive scoped labels guarantee single-*state*, not single-*claim*. For those, document the compensating convention — claim only when the owner field is empty + **re-read after writing** + a short claim TTL — **and record the residual risk** that two agents could still double-claim. Do not pretend the gap is closed; the kit's multi-agent safety depends on naming it.

> General PM tools (Asana, Monday, ClickUp) can be mapped via this recipe, but they lack a race-safe claim primitive and native PR/commit linkage — treat the atomic-claim and traceability caveats above as binding before using one as a multi-agent backlog.
