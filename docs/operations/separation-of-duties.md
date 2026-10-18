# Separation of Duties — author ≠ approver

**Purpose:** ensure the identity that builds a change cannot also be the identity that ratifies it.

---

## Principle

An agent must not ratify its own work. The contract is: **author ≠ approver ≠ commit-authors** — every identity that appears in the commit history of a branch is a *builder*, and no builder may be the *sole ratifier*.

The critical constraint for agentic workflows is that the ratifying identity must be one the **building agent cannot assume**. A second token, a second bot account, or a second identity that the same agent process can mint or impersonate does not satisfy separation of duties — the agent would be self-approving with a credential it controls. The constraint is a *human-in-the-loop* or a *distinct controlled identity outside the build agent's reach* — not just a second label.

**This kit's own repo does not satisfy this principle in full, and says so rather than implying otherwise.** It runs a declared **ratification seat** — a second account belonging to the same human as the author (`.kit/ratification-seats.conf`). That seat satisfies the *agentic* half of the constraint exactly: it is an identity outside the build agent's reach, so `agent ≠ ratifier` binds by design, but only while no agent session can act as the seat's login or bypass the review requirement (an admin login with `enforce_admins: false` can merge past that requirement); until the forge identity switch is proven (agent sessions still run under the owner's login) it rests on convention plus the audit trail. It does **not** satisfy the *human* half: author and approver are one person, so **two-person review is declared ABSENT here**, not compensated for. Both halves are stated on every seat approval — the ratification check detects the seat **by login**
(`scripts/sod-check.sh --seat-approvals`) and posts the disclosure itself as a notice, so nothing has to
be typed into the approval box (the typed seat *sentence* was retired 2026-08-28) — and the arrangement retires the day a second human with write access joins (`D-240825-1`, revisit-condition D2). See [`review-lane.md`](review-lane.md#the-ratification-seat-solo) for the mechanics and the ceiling.

---

## Tiers

**Solo / lite** — a single maintainer with no distinct build bot. This case uses the honest admin-merge convention: the maintainer is simultaneously author and ratifier, but the forge logs the `--admin` bypass as an explicit, audit-visible act. The `REVIEW-RECORD` plus an independent agent review and automated CI gates form the compensating control set. See [`review-lane.md`](review-lane.md) "Solo + agent-authored PRs" for the full reasoning and its honest ceiling.

**Team / enterprise** — a distinct ratifying identity exists (a human with write access, or a second controlled identity outside the build agent). Here the SoD constraint is satisfiable: the build agent opens the PR under its own identity, and a different identity approves it. The rest of this document covers how to wire that configuration.

---

## The FLOOR — `scripts/sod-check.sh`

The kit proves the neutral SoD logic in `scripts/sod-check.sh`. It is zero forge-specific code: a pure identity-set comparison that any CI platform, any harness, and any human auditor can read and reason about.

**Three env inputs (normalized — trimmed, case-folded — before comparison):**

| Variable | Content |
|----------|---------|
| `SOD_AUTHOR` | The PR/MR author's stable machine identity (login or email — not a display name). |
| `SOD_APPROVERS` | The set of approving-reviewer identities, newline- or space-separated. |
| `SOD_COMMIT_AUTHORS` | The set of commit-author identities on the branch, newline- or space-separated. |

**Decision:** PASS iff at least one identity in `SOD_APPROVERS` is distinct from `SOD_AUTHOR` **and** distinct from every identity in `SOD_COMMIT_AUTHORS`. Both conditions must hold for a given approver — an approver who also committed is treated as a builder, not a ratifier.

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | PASS — a qualifying distinct approver was found. |
| `1` | FAIL — no qualifying approver, or the self-test failed. Also returned when inputs are absent/empty **and** the environment is `CI=true` or the `--require` flag is passed (fail-closed, anti-vacuity). |
| `2` | UNVERIFIED — inputs absent/empty in a non-CI, non-`--require` context; cannot evaluate. |

The fail-closed behaviour on missing inputs under CI is deliberate — the E4b red-team lesson: a gate that exits 0 when it cannot read its inputs silently vacuates itself.

**Identities must be stable machine identities** (GitHub logins, GitLab usernames, email addresses) — not display names, which are user-controlled and non-unique.

Prove the logic is correct at any time:

```sh
sh scripts/sod-check.sh --selftest
```

This runs the full fixture table (distinct approver, author-only approves, approver who committed, empty approvals, casing variants) and exits non-zero if any fixture regresses.

---

## NATIVE — GitHub

Two authoring identities satisfy the contract by role, and either is acceptable: a **GitHub App token** or a push-only **machine user** (below). The machine user is the recommended posture; this repo has chosen it and has not yet switched it on (see the status paragraph under [Forge identity](#forge-identity--agent-sessions-hold-no-admin)). `sparkwright doctor --as agent` verifies a *user* token; an App installation or CI token cannot read its own identity (HTTP 403), so the check reports it UNVERIFIED and the App's settings page is where its permissions are confirmed. The App pattern:

- The App is a distinct PR author (its login is `<app-slug>[bot]`), so the PR author is different from any human reviewer from the moment the PR is opened.
- A GitHub App token is scoped — the App can be granted only the permissions it needs (contents + pull-requests), with no human-seat cost.
- The App must **not** be listed in `CODEOWNERS`. If it were, GitHub's code-owner review requirement would demand the App's approval for its own PR — structurally unsatisfiable (`review-lane.md` "Solo + agent-authored PRs", caveat 2). Keep the App off `CODEOWNERS` so that human code-owner approval is the *distinct* ratification.

A **machine user** (a separate GitHub account) is the simpler alternative — no App registration required — at the cost of occupying a seat and offering less granular token scoping. It is the recommended posture for the agent's own *authoring* identity, and what it must and must not hold is stated by role in [Forge identity](#forge-identity--agent-sessions-hold-no-admin) below.

**Reference workflow:** [the reference workflow](sod-gate.github.yml) is a copy-and-adapt workflow at `docs/operations/sod-gate.github.yml`. It gathers identities from the PR event and the GitHub reviews API, passes them as `SOD_*` env vars, and calls `sh scripts/sod-check.sh --require`. Copy it into your repo's `.github/workflows/` and add `separation-of-duties / author-not-approver` as a **required status check** on `main`. All dynamic values flow via `env:` — no `${{ }}` expressions appear inside `run:` blocks.

---

## NATIVE — GitLab

GitLab satisfies the SoD constraint natively through Merge Request approval settings. No additional CI gate is required — enable the platform controls and the constraint is enforced server-side:

- **Prevent approval by author** — the MR author cannot approve their own MR.
- **Prevent approvals by users who added commits** — any user who pushed a commit to the branch is excluded from approving it.

Both options live in **Settings → Merge requests → Approval settings**. Together they express the same author ≠ approver ≠ commit-authors contract that `sod-check.sh` proves neutrally.

See [`gitlab-adoption.md`](gitlab-adoption.md) for the full GitLab wiring guide, including MR approval rules and CODEOWNERS scoping.

---

## Other forges

Apply the contract through your forge's equivalent mechanism: an approval rule that prohibits the PR/MR author from self-approving, combined with a rule that excludes commit authors from the approver pool. Feed the resulting identities into `SOD_AUTHOR`, `SOD_APPROVERS`, and `SOD_COMMIT_AUTHORS` and invoke `sh scripts/sod-check.sh --require` in CI to prove the neutral contract holds.

---

## The minimum identity model — one human plus one agent identity

The kit's minimum is one human and one agent identity. The agent is a member of the team that works on the humans' behalf, under **its own limited identity on every system it touches** (the forge and the tracker), never a human's credentials. It holds no admin anywhere; approvals are meant to come from a human identity (a boundary only once no owner login is reachable from agent sessions, see the last bullet); CI uses its own token where the system offers one.

- **One agent identity serves the whole team**: one extra seat in total, not one per person.
- **On a free tier, the same agent account may also be the CI reader**, declared as a writer with a notice on every run (`JIRA-SETUP.md` §5a). That saves a seat; it does not reduce exposure (the residuals are in §5a and the threat model, T12). The reader is then **the agent, never the reviewing persona** of [the overlap, named](#forge-identity--agent-sessions-hold-no-admin): the reader and the reviewing login stay one persona only where the reader is a separate Viewer seat.
- **How to create the identity** is each system's own setup: the forge in [`forge-identity-switch.md`](forge-identity-switch.md) and `docs/adoption/vc-hosts.md`, the tracker in its setup sheet (`JIRA-SETUP.md`, or `docs/work-tracking/adapters.md` §The agent's identity on each tracker for the others).
- **What it means for merging:** with its own forge account, the agent is not the approving identity, so the repository runs the **team** relationship, the default ([`docs/adoption/vc-hosts.md` §Solo or team](../adoption/vc-hosts.md#solo-or-team--pick-the-merge-relationship-declared-in-your-repo-the-default-is-team)). That holds as a boundary only once no owner login is reachable from agent sessions (forge-identity-switch steps 0, 2 and 5 close those paths, and step 7 proves it): until then the agent could approve as you, and team is a convention. Solo is for a repository where the agent works under the owner's one account.

---

## Forge identity — agent sessions hold no admin

SoD above keeps an agent from ratifying its own work. This section keeps it from holding the *settings* too: the identity every agent session runs as must not be able to change repository settings, variables, secrets or branch protection. Identity is the lock that converges; a text guard over commands is a seatbelt, and it does not cover every settings call.

**The rule, by role (host-neutral):** *the agent identity holds no admin on the forge; approvals come from a different identity than the author; CI uses its own token.* GitHub is the worked example below; `docs/adoption/vc-hosts.md` says how another host maps it.

**Status in this repo.** The model is stated and `sparkwright doctor --as agent` measures it, but this repo has **not yet switched the boundary on**: agent sessions still run under the owner's login, and the residual (an admin login within the agents' reach) stays open until the switch is proven (the act sheet is [`forge-identity-switch.md`](forge-identity-switch.md)).

**Solo project.** A one-account project runs the agent under its own login; `sparkwright doctor` reports that as INFO, not a warning (declaring a ratification seat in `.kit/ratification-seats.conf` turns the INFO into a counted warning). The switch becomes worth its cost once a separate identity reviews. (This is below the minimum model; see [above](#the-minimum-identity-model--one-human-plus-one-agent-identity).)

### The identity set

| Identity | Holds | Used for | Never used for |
|---|---|---|---|
| **The owner's admin login** | admin on the dev repository; owner of the public mirror | settings, variables, secrets, branch protection and the mirror's ruleset, the solo `--admin` merge where no reviewer exists | any agent session |
| **The owner's reviewing login** | push on the dev repository (GitHub counts an approval only from a user with write) | Approves, which are the forge-authenticated `approved-by` that `land` verifies | authoring commits or pushing to a PR head; never stored where an agent can reach it, because an agent holding it could Approve its own PR and pass `land`'s forge separation of duties |
| **The agent machine user** | push on the dev repository only; nothing on the mirror; admin nowhere | every agent session: branches, claims, GO notes, PRs, `land`'s merge, preparing a release | settings, variables, secrets, protection, rulesets, approvals, the mirror (dev CI publishes it) |
| **CI** | `GITHUB_TOKEN` per workflow, plus a read-only protection-read token | the gates | — |

The machine user's token is a classic token with exactly `repo` and `workflow` (step 1 of `forge-identity-switch.md`); the collaborator role bounds what the scopes can do. A fine-grained token waits for an organisation.

**The overlap, named.** The owner's reviewing login and the Jira reader seat are one persona across two systems: on GitHub a push collaborator that renders Approves, on Jira a Viewer seat whose token is a CI secret. They are two tokens in two places with two ceilings, so a compromise of the Jira CI secret yields board read, not the GitHub login. **Judgment: acceptable, no split now.** Split them when any of these happens:

- a second human reviewer joins;
- the reader seat needs board write;
- the reader becomes the agent account (free plan): the reviewing persona then holds no reader seat;
- the reviewing login's credential is found on an agent-reachable store.

### Where an owner credential is still reachable

The machine user is a lock only if no owner credential is reachable by the OS user the agents run as. Six paths to check; `sparkwright doctor` sees only the first kind (the credential `gh` resolves) and says so:

1. **The GitHub MCP connector** available to a session acts as whichever account connected it. Its control is the guard's MCP capability gate, which is policy, not a measured control. Disconnect it, or reconnect it as the machine user.
2. **A personal access token exported from the shell profile** into every session's environment. Remove it and revoke it on the forge; removing it does not invalidate copies in running shells or logs.
3. **An SSH key** registered to the admin login: a push over SSH authenticates as the admin, and with admins not enforced that reaches `main`.
4. **`gh`'s token store** (the login Keychain on macOS) is keyed by host and login, not by config directory; a separate `GH_CONFIG_DIR` hides an account from the default listing and does not separate the store.
5. **The reviewing login** must likewise sit in no store the agents can reach.
6. **The browser-control extension.** If the owner's forge sessions (admin or reviewing) live in a browser profile the extension can drive, an agent could click Approve or change settings. Keep them in a profile the extension is not connected to, or disconnect the extension from agent sessions.

**Honest ceiling.** On one shared OS user the removal of these paths is a strong seatbelt, not a boundary: anything the owner later stores on that user is reachable again. The real boundary is a separate OS user for agent sessions, holding only the machine user's credentials; it is a heavier, separate move.

### The keystroke principle

The owner decides and the agent does the keystroke: the judgment is the control, the keystroke is not. The one keystroke that is the owner's by design is the **Approve** on the forge; nothing here adds a second recurring one. The identity switch is a one-time, settings-class owner act (the steps the guard refuses an agent), and the machine user's token is re-issued once per expiry, which `doctor --as agent` warns about 30 days ahead when the forge exposes the expiry.

### The design GO after the switch

A control-plane design GO is bound today by `[committer]`, which derives only when the approver matches the design commit's committer. That tier never authenticated the owner (the agent commits under whatever identity it holds), and after the switch the committer is the machine user. The design GO record stays required before a build and is stated as `[self-asserted]`; the authenticated binding moves onto the reviewing login's Approve on the forge, the same tier `land` already uses. That change to the ceremony tooling is its own card and lands **before** the switch.

### Neutrality

- **The board backend is untouched.** Nothing here reads or writes the board; a `BACKLOG.md` adopter keeps every behaviour it had.
- **The forge contract is host-neutral; GitHub is the reference.** The kit's forge surface is already GitHub-first (the CI profiles are GitHub Actions, the protection scripts use the GitHub API). This section follows that posture and does not create it.
- **A host without a forge adapter is never a failure.** On such a host the default doctor line reads `forge identity: N/A — no forge adapter for <host>`, and `sparkwright doctor --as agent` exits 2 (UNVERIFIED, naming the missing adapter), never 1.

`sparkwright doctor` prints one advisory `forge identity:` line (login, type, permission, and the remedy when it holds admin or maintain); the exit code is unchanged. `sparkwright doctor --as agent` runs that check alone and exits 1 on admin, maintain, a login that lacks push, a permission it cannot read, an unauthenticated `gh`, or a missing `gh`; 0 on push; 2 (UNVERIFIED) on a usage error, an unverifiable host, an `origin` whose push URL names another repository than its fetch URL, or a token that cannot read its own identity (HTTP 403: an App installation or CI token, such as CI's `GITHUB_TOKEN`; the default line is N/A there). The check reads the literal `origin` host, so an SSH host alias reports no adapter. It reads `origin`'s fetch and push URLs only: a push to another remote (`remote.pushDefault`, `branch.<b>.pushRemote`, or an explicit `git push <url>`) is not checked. It never sees the credential git itself pushes with; over HTTPS and SSH it prints the credential helper's name or says the SSH key is invisible to it.

---

## Honest ceiling

**Server-side enforcement is the adopter's responsibility**, not the kit's. The kit proves the neutral logic (`scripts/sod-check.sh`) and provides per-forge reference bindings (the workflow above, the GitLab pointer). What it cannot do:

- **Run a live distinct-approver scenario in kit CI.** The kit is itself the solo case — no second controlled identity exists to open PRs and be approved by a human. The self-test proves the *logic* is correct; it cannot prove that a live forge org is configured to enforce the constraint server-side.
- **Gate the kit's own PRs via this workflow.** `sod-gate.github.yml` lives outside `.github/workflows/` deliberately — it is a reference document for adopters, not a live workflow on this repo. Running it here would block every kit PR (the kit's CI actor is the same identity as the PR author).
- **Replace `gh pr merge --admin`.** The `--admin` bypass remains a human-only, audit-trailed escape hatch for the solo/lite track. The guard/`pre-push` hook never sees it (a server-side API call, not a local git operation). See [`runtime-guards.md`](runtime-guards.md) "Honesty boundary" and [`review-lane.md`](review-lane.md) "Solo + agent-authored PRs".
- **Attribute every commit to a forge identity.** The gate compares forge logins; a commit whose author email is not linked to a forge account has no login, so the reference workflow maps it to a placeholder rather than letting it vanish silently. The kit still cannot tie that unattributed commit to whoever later approves the PR — so **require linked emails (or signed commits)** for the commit-author check to be complete, or harden the reference to fail closed when any commit is unattributed. And note the bound of the model itself: SoD stops an agent (or author) from ratifying *its own* work; it does **not** stop two colluding distinct identities — no author≠approver gate can.

The kit's honest position: it proves the neutral floor, documents the per-forge paths, and leaves server-side enforcement to the adopter's branch-protection and forge approval rules.

---

## See also

- [`review-lane.md`](review-lane.md) — the solo/lite compensating-control bundle; the `--admin` convention and its audit trail.
- [`gitlab-adoption.md`](gitlab-adoption.md) — GitLab wiring guide; native MR approval settings for SoD.
- [`runtime-guards.md`](runtime-guards.md) — the guard's honest ceiling and why `gh pr merge --admin` is outside its reach.
- [`sod-gate.github.yml`](sod-gate.github.yml) — the GitHub reference workflow (copy into `.github/workflows/`).
- [`forge-identity-switch.md`](forge-identity-switch.md) — the numbered act sheet that moves agent sessions to the push-only machine user, an actor and a proof per step.
- `scripts/sod-check.sh` — the neutral FLOOR; `--selftest` proves the logic.
- `conformance/author-not-approver-wired.sh` — the conformance lock; runs the self-test and verifies static wiring.
