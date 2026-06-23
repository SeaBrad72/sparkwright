# Review Lane — Risk-Tiered, Solo-to-Team

**How `builder ≠ reviewer` is satisfied when you're solo — without faking it, and without a second
human.** This is the operational detail behind the one-line clause in `../../DEVELOPMENT-PROCESS.md`
§12. It is **not a new gate**; it is *which review evidence is recorded at which risk*, and how that
evidence converts to real two-human segregation of duties the moment a teammate joins.

> **Read this first (honest ceiling).** The high-risk self-review below is **process discipline, not a
> fail-closed gate**: a solo human *can* skip writing the record (mechanically blocking it requires a
> second actor the solo case lacks). What the kit does is make the record the path of least resistance,
> audit-visible, and — for control-plane changes — backstopped by the `agent-boundary` CI gate, which
> forces ratification on those diffs regardless of whether a record was written.

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

## Solo + agent-authored PRs — two honesty caveats

When the agent opens PRs under your identity, two things are true that the headline "humans ratify via code-owner approval" wording can hide:

1. **`gh pr merge --admin` is server-side — the runtime guard never sees it.** The guard/`pre-push` hook gates only *local* git; an `--admin` merge is a GitHub API call outside its reach. So the admin-merge is an **audit-trailed convention, not a kit-enforced gate** — and the agent must **prepare the green PR and hand you the merge command**, never run it itself (see [`runtime-guards.md`](./runtime-guards.md) "Honesty boundary" and [`../../AGENTS.md`](../../AGENTS.md)).
2. **Don't require code-owner review while solo + agent-authored.** If the sole owner is also the sole code owner, GitHub **forbids self-approval**, so a required code-owner approval is **structurally unsatisfiable** — the PR stays `BLOCKED` with green CI, and only `--admin` clears it (observed live). Rely on required status checks + the logged admin-merge instead. For a *real* approval gate, have the agent author PRs under a **separate identity** so author ≠ approver — the bot-identity pattern, **deferred to the E-series containment work (E4)**. Once a distinct ratifying identity exists (a GitHub App token, a machine user, or GitLab's native approval rules), see [`separation-of-duties.md`](separation-of-duties.md) for the full wiring.

## See also
- [`drift-self-check.md`](./drift-self-check.md) — the agent's in-loop re-check; **run it before requesting review** so the reviewer inherits less drift (the cheapest catch is the earliest one).
- [`../../templates/REVIEW-RECORD-TEMPLATE.md`](../../templates/REVIEW-RECORD-TEMPLATE.md) — the recorded artifact.
- [`../../DEVELOPMENT-PROCESS.md`](../../DEVELOPMENT-PROCESS.md) §12 (coordination / builder ≠ sole merger) · §13 (ratification roles).
- [`../../conformance/audit-evidence-checklist.md`](../../conformance/audit-evidence-checklist.md) — the SoD/code-review evidence row.
- [`../enterprise/ratification-rbac.md`](../enterprise/ratification-rbac.md) — which named role may ratify what.
