# Version-Control Host Adapter Guide

The kit's git workflow is **host-neutral**. GitHub and GitLab are worked examples; **any host works if it maps the contract below.** This mirrors `docs/work-tracking/adapters.md` (trackers) for the version-control-host axis — the kit owns the *contract*, you bring the *host*.

## The contract every host must satisfy

The kit needs six things from your git host. The **names** differ per host; the **mechanics** don't:

1. **Protected default branch** — no direct pushes to `main`/`master`; changes land through a merge unit.
2. **Change-proposal unit** — a PR (GitHub) / MR (GitLab) / equivalent that carries the diff, its CI run, and its review in one place.
3. **Non-author review** — at least one approval from someone *other than the author* (builder ≠ sole reviewer; the §13 separation-of-duties control in `DEVELOPMENT-STANDARDS.md`).
4. **Required status checks** — the CI **gate-IDs** (`conformance/ci-gates.sh` defines the contract; `docs/operations/ci-platforms.md` explains it) must pass before merge. The contract is the *IDs*, not a specific YAML.
5. **Solo-override + team-mode paths** — a sanctioned, *logged* way for a solo maintainer to merge when no second reviewer exists, and its team-mode counterpart (branch-admin enforcement). See `docs/operations/review-lane.md`.
6. **Release tagging** — annotated tags for versioned releases (`scripts/release-tag.sh` / `release-tag.gitlab-ci.yml`).

If your host provides these — under whatever names — the kit runs unchanged.

## GitHub *(worked)*

- **Protect** `main`: Settings → Branches (require PR, require review, require status checks). `enforce_admins` on paid/org repos; it **404s on free-tier private** repos — see `review-lane.md`.
- **Proposal:** Pull Request. **Review:** required reviewers / `CODEOWNERS`. **Checks:** the `.github/workflows/ci.yml` gate-IDs.
- **Solo override:** `gh pr merge --admin` (control-plane-ratification goes red-by-design for a solo maintainer; `--admin` is the sanctioned, logged bypass). **Tag:** `scripts/release-tag.sh`.

## GitLab *(worked)*

- **Protect** branches + **MR approval rules**: Settings → Repository → Protected branches; Settings → Merge requests → Approvals. See `docs/operations/gitlab-adoption.md`.
- **Proposal:** Merge Request. **Checks:** the `.gitlab-ci.yml` gate-IDs. **Tag:** `release-tag.gitlab-ci.yml`.

## Forge-adapter seam — authenticated `approved-by` *(seam, not wired)*

The promotion record (`scripts/promotion-verify.sh record`, KW1 · S5a) binds a GO to the approved
commit as a git note and labels **how** the approver's identity was established — the honest-ceiling
principle applied to identity, so a label never claims more than the evidence:

| Source | Assurance label | When |
|---|---|---|
| **Forge review/approval** — a GitHub PR review / GitLab MR approval, read via a thin adapter on this host axis | `[authenticated: <forge>-review]` | **team** — the real separation-of-duties signal (a *second* identity's approval) |
| GPG/SSH-signed approved-sha (git-native, forge-agnostic) | `[signed: gpg]` | solo or team with commit signing |
| git committer identity | `[committer]` | fallback (weak — `user.name` is self-set) |
| typed string | `[self-asserted]` | last resort (today's solo default) |

S5a builds the **git-native** sources (`[signed: gpg]` → `[committer]` → `[self-asserted]`) in
`scripts/promotion-verify.sh` and **defines this forge-review seam** — it does **not** wire it. The
reason is `defer-build-ahead`: solo has **no** forge review (no second reviewer exists), so a
forge-review reader has no consumer yet. The seam is wired when a **team** consumer exists (T2 /
enterprise — it pairs with the S6 control-plane actuation grant), where a forge approval by an
identity *other than the author* becomes the load-bearing SoD signal.

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

**The consumer — `scripts/promotion-verify.sh actuate` (S6).** This label is exactly what the S6
control-plane actuation gate consumes as its **bar**: `actuate` fails closed unless the recorded GO's
derived `approved-by:` label is `[authenticated: <forge>-review]` **and** that approver identity ≠
the commit author (`builder ≠ ratifier`). `[self-asserted]` / `[committer]` / `[signed: gpg]`-alone
all fall below the bar — so an adapter emitting this label is what turns a team's second-reviewer
approval into a *normal, non-`--admin`* control-plane merge the agent may actuate. Wired only when a
**team** consumer exists (T2 / enterprise); solo, no authenticated label is producible, so the bar is
unmeetable and the `--admin` kill-switch stays the human's one act — consistent by construction.

**Honest ceiling:** authenticated approval is the *strongest* identity signal the kit can carry, but
it is only as strong as the forge's own authentication, and it is **team-only** — solo genuinely
cannot have a second-identity approval, and the label says so (`[self-asserted]` / `[signed: gpg]`),
never a faked `[authenticated: …]`.

## Bring your own host *(Bitbucket, Gitea, self-managed, Gerrit, …)*

Any host works if you map the six contract points:

1. Find its **protected-branch** setting; forbid direct pushes to your default branch.
2. Identify its **change-proposal unit** (Bitbucket PR, Gitea PR, Gerrit change) — that's where diff + CI + review live.
3. Require **≥1 non-author approval**. If the host can't *enforce* it, record it as a waived control with a compensating process (`templates/WAIVER-REGISTER.md`) — don't silently drop the SoD point.
4. Wire the **CI gate-IDs** as required status checks on that unit (the CI contract is host-agnostic — `ci-platforms.md`).
5. Document the host's **solo-override** and **team-mode** equivalents (the honest counterparts of `--admin` / `enforce_admins`) in your project `RUNBOOK.md`.
6. Point release tagging at the host's tag/release API — or tag locally and push.

**Honest ceiling:** the kit provides the *contract* and this *recipe*; actually enforcing branch protection and non-author review is your **host's** configuration. `conformance/branch-protection.sh` verifies it where the host exposes an API (three-state: PASS / UNVERIFIED / FAIL), and marks it UNVERIFIED where it cannot reach the host — a green kit run is *necessary, not sufficient* for host enforcement.
