# Version-Control Host Adapter Guide

The kit's git workflow is **host-neutral**. GitHub and GitLab are worked examples; **any host works if it maps the contract below.** This mirrors `docs/work-tracking/adapters.md` (trackers) for the version-control-host axis — the kit owns the *contract*, you bring the *host*.

> **`kit-update` shares its merge base at a non-branch ref.** The base lives at `refs/kit/base` (plus `refs/tags/kit-base/*`) on the remote, pushed by `kit-update --publish-base` / `--advance-base` and imported, verified, by teammates' `kit-update --from`. That a host accepts and serves a non-branch `refs/kit/*` ref is **proven on GitHub only**; GitLab, Azure DevOps and Bitbucket are unmeasured. The ref has no forge protection on any host (`docs/operations/kit-base.md`, *Share it*).

## The contract every host must satisfy

The kit needs six things from your git host. The **names** differ per host; the **mechanics** don't:

1. **Protected default branch** — no direct pushes to `main`/`master`; changes land through a merge unit.
2. **Change-proposal unit** — a PR (GitHub) / MR (GitLab) / equivalent that carries the diff, its CI run, and its review in one place.
3. **Non-author review** — at least one approval from someone *other than the author* (builder ≠ sole reviewer; the §13 separation-of-duties control in `DEVELOPMENT-STANDARDS.md`).
4. **Required status checks** — the CI **gate-IDs** (`conformance/ci-gates.sh` defines the contract; `docs/operations/ci-platforms.md` explains it) must pass before merge. The contract is the *IDs*, not a specific YAML.
5. **Solo-override + team-mode paths** — a sanctioned, *logged* way for a solo maintainer to merge when no second reviewer exists, and its team-mode counterpart (branch-admin enforcement). Under a declared solo relationship (below) that way is the agent's merge on your recorded GO; in an undeclared one-account repo it is still your own admin merge. See `docs/operations/review-lane.md`.
6. **Release tagging** — annotated tags for versioned releases (`scripts/release-tag.sh` / `release-tag.gitlab-ci.yml`).

If your host provides these — under whatever names — the kit runs unchanged.

## GitHub *(worked)*

- **Protect** `main`: Settings → Branches (require PR, require review, require status checks). `enforce_admins` on paid/org repos; it **404s on free-tier private** repos — see `review-lane.md`.
- **Proposal:** Pull Request. **Review:** required reviewers / `CODEOWNERS`. **Checks:** the `.github/workflows/ci.yml` gate-IDs.
- **Solo:** with one forge account, declare it (`MERGE_RELATIONSHIP=solo`, see *Solo or team* below) and the agent merges on your recorded GO. In an **undeclared** one-account repo the override is still yours: `gh pr merge --admin` (control-plane-ratification goes red-by-design for a solo maintainer; `--admin` is the sanctioned, logged bypass, and the guard denies it to the agent). **Tag:** `scripts/release-tag.sh`.

## GitLab *(worked)*

- **Protect** branches + **MR approval rules**: Settings → Repository → Protected branches; Settings → Merge requests → Approvals. See `docs/operations/gitlab-adoption.md`.
- **Proposal:** Merge Request. **Checks:** the `.gitlab-ci.yml` gate-IDs. **Tag:** `release-tag.gitlab-ci.yml`.

## The agent's identity on your host *(GitHub is the reference; map the rest by role)*

The minimum is one human plus one agent identity, each on its own limited account (the model: [`separation-of-duties.md`](../operations/separation-of-duties.md) §The minimum identity model). With its own account the agent is not the approving identity, so the repository is on team ([*Solo or team*, below](#solo-or-team--pick-the-merge-relationship-declared-in-your-repo-the-default-is-team)). That holds as a boundary only once no owner login is reachable from agent sessions (`forge-identity-switch.md` steps 0, 2 and 5 close those paths, and step 7 proves it); until then the agent could approve as you, and team is a convention.

Whatever the host, the rule is by role: **the identity agent sessions run as holds no admin on the forge; approvals come from a different identity than the author; CI uses its own token.** On GitHub that is a push-only collaborator (a machine user) for the agent, your own reviewing login for Approves, and `GITHUB_TOKEN` for CI; `sh scripts/sparkwright doctor --as agent` fails a session whose login holds admin or maintain. On GitLab or Bitbucket the same roles map to a member with the Developer-level (push, no settings) role or its equivalent, a separate approver, and the pipeline's own job token; the kit has no forge adapter for those hosts yet, so `doctor` prints `forge identity: N/A — no forge adapter for <host>` and `doctor --as agent` exits 2 (UNVERIFIED), never a failure. The model and the credential paths to close are in [`separation-of-duties.md`](../operations/separation-of-duties.md) §Forge identity; the numbered setup sheet, written with role names so you can use it as your own, is [`forge-identity-switch.md`](../operations/forge-identity-switch.md).

## Solo or team — pick the merge relationship *(declared in your repo; the default is team)*

The kit's merge verbs (`promotion-verify.sh actuate` for ordinary and sensitive changes, `land` for control-plane) ask one question of your repository: **how many forge accounts does the work run under?** You answer it once, in a file the verbs read. If you never answer, the answer is **team**, the stricter bar. The two relationships:

| | **team** (the default) | **solo** |
|---|---|---|
| Who it is for | Any repo where the agent has its own forge account | A repo where the agent works under the owner's one account |
| What it needs | Two forge accounts: the owner's and the agent's own limited one. Nothing to declare | One forge account. `MERGE_RELATIONSHIP=solo` in `.kit/dials.conf`, merged once by hand |
| Forge plan | Any plan. Enforced branch protection needs a public repository or a paid plan; without it, `land` still checks the review, but the forge does not enforce it | Any plan. Nothing is enforced server-side on a free private repository |
| Who merges | The agent, through `land` (control-plane) or `actuate` (ordinary, sensitive) | The agent, the same two verbs |
| What it guarantees | A non-author approval, authenticated by the forge, plus the owner's recorded GO bound to the head sha | The owner's recorded GO, bound to the head sha, the tree and origin, and pinned at the forge with `--match-head-commit` |
| Honest cost | Two accounts to set up | **No server-side wall until you run `--replace` (below).** **The GO is the owner's own assertion, given by name;** nothing authenticates that the owner gave it. A fabricated GO note would merge, and only after-the-fact review of the trail catches it. **The after-the-fact check on GitHub:** the `trunk-trace` job in `.github/workflows/adopter-trunk-trace.yml` (incept installs it) runs `trace --recent 10` on every push to your default branch. It ships in observe mode, so it reports and never reds on the trace's verdict until you set `TRUNK_TRACE_MODE: enforce` in that file; a solo adopter who wants the red must flip it. On another host there is no job: run `git fetch origin '+refs/notes/*:refs/notes/*'` then `sh scripts/promotion-verify.sh trace --recent 10 --from refs/remotes/origin/<default-branch>` on your trunk yourself, or add them to your own pipeline |
| Getting started | Nothing to declare | Create `.kit/dials.conf` with `MERGE_RELATIONSHIP=solo` on a PR, record your GO on it (`promotion-verify.sh record`), then merge it by hand. The record makes this one hand merge part of the trail |

**Enforced branch protection needs a public repository or a paid plan (GitHub Pro, Team or Enterprise). A free private repository cannot enforce it, and it gets 2,000 GitHub Actions minutes a month. There, the merge rules are a convention the kit records and checks after the fact, not a server-side wall.** `sh scripts/sparkwright doctor` says which you have (`sh scripts/sparkwright doctor --quick` prints this line: 3 s [measured on a cold adoption of v3.247.0, 2026-11-15 UTC, n = 1, on a markdown-board project with no tracker reads], plus up to about 20 s when it reads a tracker (a timeout limit, not a measurement)): `branch protection: enforced on <branch>`, or `branch protection: unprotected: convention tier — <reason>` (an INFO line, never a failure). On a private repository the build and image attestation steps also skip unless you declare GitHub Enterprise Cloud (attestations on a private repository need it, whoever owns the repository): set the `KIT_ATTEST_PRIVATE` variable to `true`, at repository or organization level (Settings → Secrets and variables → Actions → Variables). Without it each skip prints a notice naming the cause, on an organization-owned repository the image push still runs (on a user-owned private repository the image job does not run at all), and `inception-done` / `preflight` tell you the same; a dated `na` for `gate-provenance` in `conformance/gate-dispositions.txt` is the third route.

**Declaring solo, in order.**

1. Open a PR that creates `.kit/dials.conf` with the line `MERGE_RELATIONSHIP=solo`. (An adopter export carries no dial file, so you create it. Every adopter starts undeclared, which reads team.)
2. Run `sh scripts/promotion-verify.sh record` on that PR's head sha: class `control-plane`, your own words in `--token`, your name in `--go-by`. This is the root of the whole solo grant, so it must be on the trail; with it, `trace --recent` binds the hand merge to a note instead of flagging it as recordless.
3. Merge that PR yourself, by hand. No `--admin` is needed on a free private repository. This is the one hand merge; from here the agent merges on your recorded GO, and your per-PR act is the GO only. `sh scripts/sparkwright doctor` and every `actuate` and `land` print that line.

**Two kit checks on this PR do not pass, and that is expected.** (This is the dial-file PR. The PR that first adds the kit is different: its checks and the hand merge are explained in [Your first PR](brownfield.md#your-first-pr).) The dial file is a control-plane change, so two of the kit's gates fail on this PR unless you carry their records [M: a solo-declared throwaway, 2026-11-16, where both failed and every other check passed]:
- `loop-state`: no `Kit-Row` or `Kit-Class` trailer on the head commit;
- `ceremony-binding`: no recorded design GO (`promotion-verify.sh record --gate design`).

Neither blocks the hand merge on a free private repository, because nothing is enforced there. On a repository whose protection requires them, merge it as the repository's admin.

To make both pass instead, before you open the PR:
1. Claim a board row for the change.
2. Put the `Kit-Row` and `Kit-Class: control-plane` trailers on the commit.
3. Add a short design file to the same PR: a `*-design.md` with a few real lines, which the approved commit touches.
4. Record a design GO bound to the branch, with that file as `--basis`, as the `ceremony-binding` message says. A design GO with no design file in the PR fails as an anomaly. Every later PR carries these as usual.

`sparkwright new` asks this same question ("How many forge accounts will this work run under? 1 = solo, 2 or more = team") and stamps the `CLAUDE.md` line from the answer, but it never writes the dial: a solo answer prints these three steps and lists them as owed, and the repository reads team until that PR merges.

From then on `actuate` and `land` merge on your recorded GO. They print one line saying which relationship they read and from where (`merge relationship: solo (origin/main <sha>) — the recorded GO is the control`), and `sh scripts/sparkwright doctor` prints the same in plain words (`sh scripts/sparkwright doctor --quick` prints this line: 3 s [measured on a cold adoption of v3.247.0, 2026-11-15 UTC, n = 1, on a markdown-board project with no tracker reads], plus up to about 20 s when it reads a tracker).

**Making the forge enforce it (GitHub, optional).** `incept` installs `.github/workflows/solo-go.yml` (an existing project takes it from `kit-update --from`, or by copying `profiles/solo-go.yml` to that path). It runs on `pull_request_target` from the base branch and reads your recorded GO for the PR head: green when one binds it, red when none does, and a green `na` where the repository is not solo-declared. To make the forge refuse a head with no recorded GO (the GO is self-asserted, a note the agent records satisfies it, a fabricated GO is not caught server-side, and an admin can still edit protection): list `solo-go-bound` in `REQUIRED-CHECKS.md` (by hand, in a PR), merge it, then run `sh scripts/branch-protection-apply.sh --replace` once at a terminal. It reads the target's default branch from the forge itself, and chooses the **solo-agent** profile (zero required approvals, `enforce_admins:true`, `solo-go-bound` required) only when the repository reads solo and the declaration, the workflow and the verbs are all there; any other case, an unreadable one included, writes the ordinary solo profile. Show-only (no flag) prints `review-count: live=<n> target=<0|1>` first. `sh conformance/branch-protection.sh` verifies the state, and reds a solo tree at zero approvals when `solo-go-bound` is not live. A re-run of the job (the verbs do it for you, once) reads the live GO, so a GO recorded late turns it green. On a free private repository nothing is enforced and the verbs read team-or-solo as before; the verbs' step is skipped where the workflow is not installed.

**How the declaration is read, so you can predict it.**

- From **origin's default branch**, never from the PR being merged. A PR that flips team to solo is judged by the bar it is leaving, and the flip takes effect only after it has merged.
- **Anything unreadable reads team:** no file, a missing key, an unrecognised value, an unreachable origin, a default-branch tip you have not fetched (`git fetch origin`). There is no environment variable.
- The `CLAUDE.md` line `**Governance** (§ solo/team): <mode>` that `incept` stamps can only **tighten**. If it says `team`, the relationship is team whatever the dial says. If it says `solo` and the dial is absent, the relationship is still team: that stamp has always meant "the human admin-merges", and it never becomes a grant for the agent. `sh scripts/sparkwright doctor` names a disagreement between the two (`sh scripts/sparkwright doctor --quick` prints this line: 3 s [measured on a cold adoption of v3.247.0, 2026-11-15 UTC, n = 1, on a markdown-board project with no tracker reads], plus up to about 20 s when it reads a tracker).
- Solo's bar is the recorded GO: the note on origin binds exactly the head sha, its tree is that sha's tree, it names the person who gave the GO, and it is not a design or plan gate. Control-plane always goes through `land`; `actuate` points you at the exact `land` command.
- On a repository with no enforced protection, an uncooperative agent can still run a raw `gh pr merge`; the declaration and the GO note are a drift control, not a boundary.
- This is a drift control, not a boundary: it reads whatever `origin` resolves to in your clone. What binds is server-side protection where your plan has it, and reviewing the trail.

**Leaving solo is one act.** Once protection requires `solo-go-bound`, run `sh scripts/branch-protection-apply.sh --replace --team` in the same step that changes the declaration or deletes the dial. Until then the check reads an error where the declaration says `solo-go-bound` and the dial no longer reads solo (it never reads a green `na`), and `sh scripts/sparkwright doctor` warns at zero approvals on a repository that does not read solo.

**Moving from solo to team (optional).** Solo is a complete, supported shape; nothing here is the expected path. If a second person joins later, or a team gains more people, a person (conduct, not enforced) runs `sh scripts/sparkwright team <@handle> [<@handle> ...]` on a branch of the project's checkout. It edits up to three files (it creates CODEOWNERS when there is none) and nothing else: the one value token on the `**Governance** (§ solo/team):` line of `CLAUDE.md` becomes `team`, a `solo` `MERGE_RELATIONSHIP` in `.kit/dials.conf` becomes `team`, and the handles are added to the governing `*` rule of `CODEOWNERS`. It never calls the forge, invites anyone or changes branch protection. It leaves the change in your working tree to read with `git diff` and merge it under the bar land reads today (the verb prints which); its printed next steps include the typed `branch-protection-apply.sh --replace --team` step. Run on a project that is already team, it only adds handles it does not yet name. See [`review-lane.md`](../operations/review-lane.md) §Upgrade to two-human SoD.

## Forge-adapter seam — authenticated `approved-by` *(GitHub wired; other forges remain the seam)*

The promotion record (`scripts/promotion-verify.sh record`) binds a GO to the approved
commit as a git note and labels **how** the approver's identity was established — the honest-ceiling
principle applied to identity, so a label never claims more than the evidence:

| Source | Assurance label | When |
|---|---|---|
| **Forge review/approval** — a GitHub PR review / GitLab MR approval, read via a thin adapter on this host axis | `[authenticated: <forge>-review]` | **team** — the real separation-of-duties signal (a *second* identity's approval) |
| GPG/SSH-signed approved-sha (git-native, forge-agnostic) | `[signed: gpg]` | solo or team with commit signing |
| git committer identity | `[committer]` | fallback (weak — `user.name` is self-set) |
| typed string | `[self-asserted]` | last resort (what a one-account repo records when no review can be derived) |

`scripts/promotion-verify.sh` builds the **git-native** sources (`[signed: gpg]` → `[committer]` →
`[self-asserted]`) and reads this forge-review seam through GitHub as its reference adapter. A forge
review by a second identity can exist even where the git-native sources cannot see it, so ignoring it
would record a weaker label than the evidence supports and keep `actuate` closed. `record` reads the
PR's reviews through `gh api` and emits `[authenticated: github-review]` when — and only when — the **latest** review by the claimed
approver is exactly `APPROVED`, is bound to the **resolved** approved sha, comes from a non-`Bot`
login byte-equal to `--approved-by`, and that login differs (case-insensitively) from a PR author
that itself resolved. Any gap keeps the git-native label and says why on stderr; the derivation only
ever upgrades, and never blocks a record.

**Other forges remain the seam.** GitLab MR approvals and the rest still need an adapter answering
the contract below; nothing here is GitHub-only by design, only by what has been built and measured.

**The adapter contract (per host).** To wire it, a host adapter answers one question about a merge
proposal: *"which distinct identity (not the author) formally approved it, and can that be read
back?"* — GitHub: an approving PR **review** (`gh api .../reviews`); GitLab: an MR **approval**
(`/approvals`). Concretely, for a promotion record to carry **`[authenticated: <forge>-review]`** the
adapter must return **two** facts read from the forge's PR/MR **review API** (not from the git
history, which the actor controls): (1) the **authenticated identity of the approver** — the forge
account that submitted the review, established by the forge's own authentication, not a self-typed
string; and (2) the **review state = *approved*** (an `APPROVED` PR review / a granted MR approval —
a mere comment or "changes requested" does **not** qualify). The adapter maps that pair to
`approved-by: <identity> [authenticated: <forge>-review]`, which `record` writes in place of the
git-native derivation. Hosts that cannot expose an approver identity fall back to the git-native
labels (record it honestly; never fake the stronger label) — the same three-state honesty as
`conformance/branch-protection.sh`.

**The consumer — `scripts/promotion-verify.sh actuate`.** This label is exactly what the
control-plane actuation gate consumes as its **bar**: `actuate` fails closed unless the recorded GO's
derived `approved-by:` label is `[authenticated: <forge>-review]` **and** that approver identity ≠
the commit author (`builder ≠ ratifier`). `[self-asserted]` / `[committer]` / `[signed: gpg]`-alone
all fall below the bar — so an adapter emitting this label is what turns a second-reviewer approval
into a *normal, non-`--admin`* merge the agent may actuate. **That bar is reachable on
GitHub**, and `actuate` therefore opens for **Ordinary and Sensitive** changes on an authenticated
recorded GO. **Control-plane is not merged by `actuate`:** it is refused with a pointer at the exact
`promotion-verify.sh land` command, in both relationships, and `--admin` stays denied to the agent. In a **solo-declared** repo the
label bar and the author check give way to the owner's recorded GO, bound to the head sha (below).

**Honest ceiling — wiring the seam did not raise it.** Authenticated approval is the
strongest identity signal the kit can carry, but it is only as strong as the forge's own
authentication, and the *derivation* is only as strong as the local `gh` binary and its ambient
credential: an agent that controls `PATH` can feed it fabricated reviews. That is no **new**
capability — a git note was always self-authorable, and `refs/notes/*` sits outside branch protection
— but it fixes the tier: **`[authenticated: github-review]` is a drift control at the note's own
trust tier, never proof.** What actually binds a human with push rights is server-side branch
protection + required review. The label also attests only that a qualifying review existed **when
asked**; a later dismissal is not re-checked at actuate time (the forge re-judges at merge time —
layered, not doubled). And the forge's SoD is reviewer ≠ **PR opener**, not reviewer ≠ commit pusher:
on a teammate-opened PR a builder can approve commits they authored. GitHub's own "require approval
from someone other than the most recent pusher" setting is the answer to that; the two SoD layers
here are **independent** and do not compose to close it.

## Bring your own host *(Bitbucket, Gitea, self-managed, Gerrit, …)*

Any host works if you map the six contract points:

1. Find its **protected-branch** setting; forbid direct pushes to your default branch.
2. Identify its **change-proposal unit** (Bitbucket PR, Gitea PR, Gerrit change) — that's where diff + CI + review live.
3. Require **≥1 non-author approval**. If the host can't *enforce* it, record it as a waived control with a compensating process (`templates/WAIVER-REGISTER.md`) — don't silently drop the SoD point.
4. Wire the **CI gate-IDs** as required status checks on that unit (the CI contract is host-agnostic — `ci-platforms.md`).
5. Document the host's **solo-override** and **team-mode** equivalents (the honest counterparts of `--admin` / `enforce_admins`) in your project `RUNBOOK.md`. The kit's merge verbs read the *declared merge relationship* (below) from a file in your repository, not from the host, so declaring solo or team works on any host; only the protection a host can enforce differs.
6. Point release tagging at the host's tag/release API — or tag locally and push.

**Honest ceiling:** the kit provides the *contract* and this *recipe*; actually enforcing branch protection and non-author review is your **host's** configuration. `conformance/branch-protection.sh` verifies it where the host exposes an API (three-state: PASS / UNVERIFIED / FAIL), and marks it UNVERIFIED where it cannot reach the host — a green kit run is *necessary, not sufficient* for host enforcement.
