# Promotion Log — retired (records now live in `refs/notes/promotions`)

**Status:** Retired pointer (S5a, v3.100.0). This file is **no longer written to.** Promotion GO records
are now bound to the approved commit as **git notes** under `refs/notes/promotions` — a
**tree-invariant** placement (the record can never perturb the tree it approves, so
`scripts/promotion-verify.sh check` can never false-fail because of it). This closes S4-finding #1
(an in-tree append to this log perturbed the approved tree). Model:
`docs/governance/promotion-contract.md` → *Approve→execute→log*.

## Where the records are now

- **Written by** `scripts/promotion-verify.sh record` → `git notes --ref=promotions add` on the
  approved-sha (out of tree).
- **Viewed with** `scripts/promotion-verify.sh log` (a human-readable **projection** of the notes —
  one source of truth, rendered on demand; not a second synced surface).
- **Read by** `scripts/promotion-verify.sh check` to verify `shipped == approved`.
- **Shared with** `git push origin refs/notes/promotions` (notes need an explicit push — the record
  script prints this guidance; a forgotten push means the record isn't shared).

> **What the record proves — and does not.** It is auditable evidence that an explicit, per-gate human
> GO existed, bound to a specific commit, *before* the agent actuated a merge/tag. The `approved-by`
> line now carries a **derived assurance label** — `[signed: gpg]` → `[committer]` → `[self-asserted]`
> — that never overclaims *how* identity was established (an unsigned commit can never be
> `[signed: gpg]`). Authenticated team approval (`[authenticated: <forge>-review]`) is a **seam** in
> `docs/adoption/vc-hosts.md`, wired when a team consumer exists. The one CI-gateable guarantee riding
> on the record is `shipped == approved` (verified by `check`).
>
> **Notes bind, they do not authenticate.** A git note is a *mutable* ref: it solves *placement*
> (tree-invariant binding), not tamper-evidence. Tamper-evidence of the *approval* rides on the
> `approved-by` source's assurance, not on the note storage. A compromised/malicious actor could
> self-author a note binding any SHA — that threat is the S4 deploy-failsafe circuit-breaker's job,
> not this record. The solo/team SoD labels stay honest regardless.
>
> **Supersede ceiling.** `record` uses `git notes add -f`, so re-recording a GO on the *same*
> approved-sha **supersedes** the prior note — prior gate history is not retained in the trail; view
> the current recorded state with `promotion-verify.sh log`.
>
> **Read the label, not the body.** The authoritative assurance is the trailing derived label on the
> `approved-by:` line (derived, honest) — consumers must read *that* line's label, not substring-scan
> the whole note body, because a `--token`/`--basis`/`--scope` value may legitimately contain bracket
> text (e.g. `approval-token: "GO [per PR #257]"`).

## History (honest migration note)

The S2 worked example (PR #257 / `9f3c1a2…`) that previously lived here as an append-only Markdown
block has been superseded by the notes model. No prior GO is lost or rewritten — the log file simply
stops being the record surface. From v3.100.0 forward, `promotion-verify.sh log` is the trail.

## Scope (unchanged)

Records promotions of **NON-control-plane** work, where the agent may actuate the keystroke after a
recorded GO. **Control-plane promotions stay human-actuated** (bootstrap) — ratified through
`control-plane-ratification`, not this record. `builder ≠ ratifier`: the agent may prepare, execute,
and record a promotion; it never ratifies one.
