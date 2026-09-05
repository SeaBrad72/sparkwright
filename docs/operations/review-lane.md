# Review Lane — Risk-Tiered, Solo-to-Team

**How `builder ≠ reviewer` is satisfied when you're solo — without faking it, and without a second
human.** This is the operational detail behind the one-line clause in `../../DEVELOPMENT-PROCESS.md`
§12. It is **not a new gate**; it is *which review evidence is recorded at which risk*, and how that
evidence converts to real two-human segregation of duties the moment a teammate joins.

> **⚠️ AMENDED 2026-09-04 (`LOOP-STAGE-ARTIFACT-GATE`) — the record is now GRADED, and this paragraph
> used to say it was not.** Until that date this read: "process discipline, not a fail-closed gate — a
> solo human *can* skip writing the record". That is **no longer true where a second identity exists**.
> `conformance/review-lane.sh` is a required status context (`review-lane`) that refuses a
> sensitive/control-plane PR — and any non-docs-only ordinary one — whose head commit does not carry
> `Kit-Plan:` and `Kit-Review:` trailers naming a tracked plan file and a graded review record.
> See *The graded record* below. The
> **approval** is enforced beside it by branch protection, not by this check (amended 2026-09-05).
>
> **What is still true.** The gate proves **shape, not truth**: it cannot prove the reviewer read the
> diff, and since 2026-09-05 it proves nothing at all about **who approved** — that is the forge's,
> and the three settings the Attested-by row names are what carry it. **Solo with one account the
> approval half is unavailable**, not merely weaker: there is no non-author identity to click Approve.
> Adopters receive the lane on an `observe` dial (`REVIEW_LANE_MODE` in
> `.github/workflows/adopter-gates.yml`) whose exit condition is now *record discipline is real* —
> every code PR carrying a `Kit-Plan` and a `Kit-Review` trailer — because that, not a second identity,
> is what the check itself grades. Under that dial the old sentence still applies, and the
> compensating-control section below is what carries the weight.

## The graded record

Since 2026-09-04 the review stage leaves a file, and a gate refuses without it.

| | |
|---|---|
| **Plan artifact** | `docs/plans/<date>-<row-slug>.md` from [`PLAN-RECORD-TEMPLATE`](../../templates/PLAN-RECORD-TEMPLATE.md) · trailer `Kit-Plan:` |
| **Review artifact** | `docs/reviews/<date>-<row-slug>.md` from [`REVIEW-RECORD-TEMPLATE`](../../templates/REVIEW-RECORD-TEMPLATE.md) · trailer `Kit-Review:` (comma-separated for a consolidated PR) |
| **Graded for** | Builder ≠ Reviewer · rounds citing commits inside the PR, closing on APPROVE · every finding disposed (`fixed <sha>` \| `accepted — <reason>` \| `waived — WAIVER-<id>`) · every design-promised control resolving to an executable `path::test-name` · a security-review verdict, or a waiver carrying all four `D-240904-1` criteria |
| **Attested by** | **branch protection, not this check** (amended 2026-09-05, `REVIEW-LANE-WAITING-IS-GREEN`). The approver types **nothing** and clicks **Approve**; three server-side settings carry it — `required_approving_review_count >= 1` (a non-author approval exists), `dismiss_stale_reviews` (a push dismisses every prior approval, so an approval carried across a fix push does not count), `require_last_push_approval` (whoever pushed the head cannot approve their own push). `conformance/branch-protection.sh` FAILs when any of the three is false or absent, and that leg is the required context `branch-protection-live`. *(The gate itself read the forge's review list until 2026-09-05 and returned WAITING while none existed — which a job renders RED, cleared only by a manual re-run. Deleted: the forge enforces the same properties on every merge attempt, with no run to wait on. And `D-240904-2`, 2026-09-04, had already struck the typed attestation line — author-controlled text proved only that someone could copy a string a command printed for them.)* |
| **Scope cut** | an **ordinary AND docs-only** change-set is N-A. That is the classifier's cut, not the gate's judgment. |
| **Verdicts** | `0` pass/N-A · `2` refusal — a missing, malformed or self-reviewed **record**, or a change-set the gate could not derive. Two values, and no third: the check runs **once per push** and is green or red like every other gate. *(`1` meant WAITING and is retired, not recycled — see the Attested-by row.)* |

**What makes "never reviewed" RED is the record, not the keystroke.** The T1 defect — 24 of 24
approvals over work with no review record at all — is refused by the record grading above, which is
where it belongs. The approval proves a second identity looked at *this tree*; it has never proved
they read anything, and the kit does not claim it does.

Run `sh conformance/review-lane.sh --pre-push` before pushing: it grades everything CI will except the
approval, which no local run can see.

## The two tiers

Review rigor follows the kit's existing **risk × reversibility** gradient — not a blanket checklist
(effort-management ritual → faked), and not agent-review-only on everything (too thin where it matters).

| Tier | Triggers | What is recorded |
|------|----------|------------------|
| **Default** | features · fixes · docs · refactors | The kit's **`reviewer`** subagent performs a **recorded, independent** review; the human **ratifies, recorded** — a [`REVIEW-RECORD`](../../templates/REVIEW-RECORD-TEMPLATE.md). That logged pair **is** the independent review. No separate human checklist. Fast. |
| **High-risk** | control-plane (the `agent-boundary` set) · security/auth boundary · data/schema migration · prod deploy · money / irreversible | The above **plus a human structured self-review**: in the `REVIEW-RECORD` *Acknowledgments* section, a **specific acknowledgment tied to each material agent-reviewer finding** (not a bare "approved"). This is the **anti-theater** requirement — it forces the maintainer to engage with what the reviewer actually found. |

For a security/auth/data/AI boundary, the independent review adds the **`security-reviewer`** subagent
(the §7 security gate), and its findings are recorded the same way.

## The trigger is already wired

You do not configure the high-risk tier — it keys off mechanisms that already exist:

- **Control-plane** is exactly the `agent-boundary` set (`../../conformance/agent-boundary.sh`, reusing
  `guard-core.sh::is_control_plane_path`, incl. the N5 adapter union). A PR touching it already *must* be
  ratified; the solo lane attaches a recorded review to that ratification.
- **The §13 autonomy tiers** already classify security/data/prod/irreversible actions.

So "high-risk" is not a new judgment call layered on top — it is the union of triggers the kit already
enforces.

## Compliance honesty — compensating controls

True segregation of duties (a *different human* builds vs. approves) is **impossible solo**. Auditors
accept **compensating controls** for small orgs, *provided they are real and recorded*. The solo bundle —

1. a recorded **independent agent-review** (`reviewer`/`security-reviewer`),
2. an **accountable, recorded human ratification** (the `REVIEW-RECORD`, with specific acknowledgments on
   high-risk), and
3. the **automated gates** (the 7 required CI gates, the `agent-boundary` control-plane gate, the guard)

— is a legitimate, defensible control set for the SoD / independent-code-review control, mapped in
`../../conformance/audit-evidence-checklist.md`. Because it is recorded **from day one**, it is not a
"we'll add review later" deferral (the trap WS-rejected opt-in re-creates) — it is the control,
operating, with an audit trail.

## Upgrade to two-human SoD — one setting, zero rework of evidence

GitHub branch protection on `main` already requires **one non-author approval**. Solo, you satisfy it
with an **owner admin-merge** (`gh pr merge --admin`, `enforce_admins: false`) — GitHub logs the bypass,
and that log is the audit trail of "solo maintainer self-ratified" (see `../../START-HERE.md`). When a
**second human with write access** joins, you tighten to real, *enforced* two-human SoD:

- *they* approve the PR — the existing required-review rule is now met by a real second party, **and**
- you **flip `enforce_admins: true`** (one setting) so an owner admin-merge can no longer bypass that
  required review. *(With `enforce_admins: false`, an admin keeps the `--admin` bypass even after a
  second approval exists — so the flip is what actually enforces the second human.)*

That is the **only** change: no process is rebuilt and no evidence re-created — every `REVIEW-RECORD` you
wrote solo remains valid history, and the branch-protection rule itself is unchanged. Optionally also set
`require_code_owner_reviews` + populate `CODEOWNERS` to route approval by path (the P1 branch-protection
advisory nudges this) — **but only once a second human exists; enabling it solo traps you (see the caveats below).** So the solo→team upgrade is **one `enforce_admins` flip with zero rework of the
recorded compensating-control evidence** — not a re-architecture.

> **Caveat — a private repo needs a paid plan for this flip.** Full branch protection (including
> `enforce_admins`) on a **private** repo requires GitHub **Pro / Team / Enterprise**; on a private
> *free-tier* repo the `enforce_admins` API returns **404** and the protection can't be set. **Public**
> repos and **paid** private repos are unaffected. On a private free-tier repo the solo `--admin` lane
> still holds — CI plus the recorded `REVIEW-RECORD` remain your compensating control — and the one-flip
> upgrade lands the moment the repo is on a plan that supports `enforce_admins`. (The kit verifies the
> SoD *logic* regardless of plan; only the server-side *enforcement* is plan-gated.)
>
> **Caveat — until that flip, `main` is admin-writable from *any* clone.** With solo
> `enforce_admins: false`, a plain `git push` by the repository owner will land on `main`, bypassing the
> PR and required-check rules; GitHub records the bypass, and that log is the audit trail. The local
> `pre-push` hook reduces the chance of doing this by accident — but `git clone` copies neither
> `.git/hooks/` nor `.git/config`, so a **fresh clone has no local guard at all** until one is installed.
> `sh scripts/preflight.sh` refuses when it is missing and prints the install command. That is a *signal*,
> not a boundary: the bypass itself is server-side, where no local hook can see it (see *Solo +
> agent-authored PRs*, caveat 1, below), and the residual is **disclosed, not closed** — the one flip
> above is what closes it.

## Solo + agent-authored PRs — two honesty caveats

When the agent opens PRs under your identity, two things are true that the headline "humans ratify via code-owner approval" wording can hide:

1. **`gh pr merge --admin` is server-side — the runtime guard never sees it.** The guard/`pre-push` hook gates only *local* git; an `--admin` merge is a GitHub API call outside its reach. So the admin-merge is an **audit-trailed convention, not a kit-enforced gate** — and the agent must **prepare the green PR and hand you the merge command**, never run it itself (see [`runtime-guards.md`](./runtime-guards.md) "Honesty boundary" and [`../../AGENTS.md`](../../AGENTS.md)). This `--admin` bypass stays human. A *normal* (non-`--admin`) merge of an Ordinary/Sensitive PR is delegable **after a recorded GO** — execution is delegable post-GO, control-plane stays human (see [`../governance/promotion-contract.md`](../governance/promotion-contract.md)).
2. **Don't require code-owner review while solo + agent-authored.** If the sole owner is also the sole code owner, GitHub **forbids self-approval**, so a required code-owner approval is **structurally unsatisfiable** — the PR stays `BLOCKED` with green CI, and only `--admin` clears it (observed live). Rely on required status checks + the logged admin-merge instead. For a *real* approval gate, have the agent author PRs under a **separate identity** so author ≠ approver — the bot-identity pattern, **deferred to the E-series containment work (E4)**. Once a distinct ratifying identity exists (a GitHub App token, a machine user, or GitLab's native approval rules), see [`separation-of-duties.md`](separation-of-duties.md) for the full wiring.

## The ratification seat (solo)

This kit's own repo runs a **ratification seat**: a second GitHub account (`@ISBrad72`) belonging to
the same human as the author (`@SeaBrad72`), declared in
`.kit/ratification-seats.conf` (kit-internal, export-ignored — deliberately a code span, not a link:
a kept doc must not link to a file the adopter export prunes). It is the concrete answer
to caveat 2 above, and it is worth being exact about what it buys, because the honest version is
narrower than a PR page suggests and wider than "it's fake".

**What it enforces — and this half is real.** `agent ≠ ratifier`. The building agent cannot mint that
approval: it has no credential for the seat, and no amount of model cooperation gets it one —
**so long as no seat credential is present in the agent's environment (unchecked; environmental, not
enforced)**. That survives the friction test — it still binds if the agent stops cooperating — which
is exactly why the 2026-08-25 evaluation's proposal to *retire* the seat was rejected (`D-240825-1`).
Retiring it would have discarded a working control to fix a labelling problem.

**What it does NOT provide.** Two-person review. One human still writes and approves the change.
On this repo two-person review is **declared absent**, not satisfied, and
[`separation-of-duties.md`](separation-of-duties.md) is the statement of record.

**The disclosure — detected, not typed.** When a declared seat is among the approvers, the
ratification check says so itself, as a GitHub **notice** on the run:

> `<login>` is a declared ratification seat — the same human as the author; this enforces
> agent ≠ ratifier and is NOT a second-person review

`scripts/sod-check.sh --seat-approvals` does the detection **by login**, wired into the ratify step of
`.github/workflows/ratification.yml`; the workflow renders the prose. It is a notice: it never changes
the verdict, and a seat approval is never treated as worse than any other.

⚠️ **The typed seat sentence was RETIRED on 2026-08-28.** Until then a seat's approval body had to
carry that sentence verbatim or the check parked at WAITING. It graded the approver's typing rather
than the change — the login is what the forge vouches for, and no body text can make the disclosure
truer — so the sentence added a way for a healthy approval to park a governance gate and nothing else.
**There is now nothing to type into an approval box.** (`scripts/sod-check.sh --seat-bodies` survives
as a deprecated alias of the detection mode, so an in-flight caller does not break.)

**Ceiling:** this detects an identity, never that a human read the diff. Its value is that the
disclosure is emitted beside the approval instead of living in a doc.

**The flip (D2).** When a second human with write access joins: delete the seat line from
`.kit/ratification-seats.conf`, stop declaring two-person review absent, and flip
`enforce_admins: true` per the upgrade section above. One person, one file, one setting.

## See also
- [`drift-self-check.md`](./drift-self-check.md) — the agent's in-loop re-check; **run it before requesting review** so the reviewer inherits less drift (the cheapest catch is the earliest one).
- [`../../templates/REVIEW-RECORD-TEMPLATE.md`](../../templates/REVIEW-RECORD-TEMPLATE.md) — the recorded artifact.
- [`../../DEVELOPMENT-PROCESS.md`](../../DEVELOPMENT-PROCESS.md) §12 (coordination / builder ≠ sole merger) · §13 (ratification roles).
- [`../../conformance/audit-evidence-checklist.md`](../../conformance/audit-evidence-checklist.md) — the SoD/code-review evidence row.
- [`../enterprise/ratification-rbac.md`](../enterprise/ratification-rbac.md) — which named role may ratify what.
