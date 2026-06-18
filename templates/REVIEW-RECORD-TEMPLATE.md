# Review Record

**The recorded independent review + ratification for one change** — the solo lane's evidence that
`builder ≠ reviewer` was satisfied without a second human (`../docs/operations/review-lane.md`). Copy
into your project (or attach to the PR/audit record), one per change. **Default-tier** changes need the
top three sections; **high-risk** changes (control-plane · security/auth boundary · data/schema
migration · prod deploy · money/irreversible) ALSO need the **Acknowledgments** section.

| Field | Value |
|-------|-------|
| Change / PR | #___ |
| Risk tier | `default` \| `high-risk` — trigger: ___ |
| Builder | ___ |
| Independent review by | the kit's `reviewer` (+ `security-reviewer` if a security/auth/data/AI boundary) subagent — findings recorded below |

## Agent-review findings
*(Paste the reviewer subagent's findings — correctness/quality, and security where applicable — each with a verdict. "No findings at severity X" is a valid, recordable result.)*

- ___

## Human ratification
- **Ratified by:** ___ *(≠ builder where a second human with write access exists; solo: the accountable maintainer, recorded)*
- **Date:** ___
- **Disposition:** findings addressed · accepted-with-reason · waived *(cite exception ID in `WAIVER-REGISTER.md`)*

## High-risk acknowledgments  *(REQUIRED for the high-risk tier — the anti-theater requirement)*
For **each material finding**, a *specific* acknowledgment tied to it — never a bare "approved":

- Finding ___ → *I reviewed this; resolved by ___ / accepted because ___.*
- Control-plane / security obligation ___ → *acknowledged: ___.*

## Compensating control (solo)
This bundle — a **recorded independent agent-review** + an **accountable recorded human ratification** +
the **automated gates** (CI, the `agent-boundary` control-plane gate, the guard) — is the legitimate
compensating control for true two-human segregation of duties at solo scale. Recorded from day one, the
evidence carries over with **zero rework** when a second human with write access joins: their non-author
approval satisfies the required-review rule, and a single **`enforce_admins: true`** flip then enforces
real two-human SoD (that flip is what removes the owner `--admin` bypass). See
`../docs/operations/review-lane.md`.

> **Honest ceiling.** This record is *process discipline, not a fail-closed gate* — a solo human can
> skip writing it (mechanically blocking it requires a second actor the solo case lacks). The kit makes
> it the path of least resistance and audit-visible; the `agent-boundary` CI gate still forces
> ratification on any control-plane diff regardless.
