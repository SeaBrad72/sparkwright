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

## Quality-lens rubric (what to check)
> Applied at the §7 Review gate alongside the correctness + security review. A reviewer (human or agent)
> marks each dimension — this is judgment, not a gate: flag concerns, don't rubber-stamp. The results go
> in *Agent-review findings* below. See `../docs/operations/code-quality.md`.

- [ ] **Readability** — a new reader follows it without the author present.
- [ ] **Simplicity (DRY / YAGNI)** — no needless abstraction; no copy-paste that should be one unit.
- [ ] **Function size & single-purpose** — small; one job; early returns over deep nesting.
- [ ] **Naming** — meaningful, intention-revealing (no throwaway names except loop counters).
- [ ] **Comment quality** — explains *why* / intent, not narration; no stale/rotted comments.
- [ ] **Type / interface design** — strong invariants + encapsulation; illegal states hard to represent.
- [ ] **Cohesion / coupling** — one responsibility; internal changes don't ripple to consumers.
- [ ] **Error handling** — structured, with codes; no swallowed errors / silent fallbacks.
- [ ] **No dead code · no debug output · no hardcoded values** that belong in config.
- [ ] **Tests** — meaningful (assert behavior, not implementation); critical paths covered.

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
