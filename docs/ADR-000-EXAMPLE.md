# ADR-000 (EXAMPLE): Technology Stack Selection

> Worked example of the stack-decision record produced at Inception (`START-HERE.md` step 2). Copy to `docs/architecture/ADR-000-stack.md` in your project and replace with your real decision. Every project's first ADR records its stack — it's what makes the chosen `profiles/<stack>.md` authoritative for that project.

**Status:** Accepted
**Date:** [YYYY-MM-DD]
**Deciders:** [intent owner, lead]

## Context
We're starting [project]. We need a stack that fits [constraints: team skills, performance needs, hosting, time-to-market, ecosystem]. No technology was predetermined.

## Decision
Use **[e.g., TypeScript / Node.js + Next.js + PostgreSQL/Prisma]**, captured in `profiles/typescript-node.md`.

## Fit rationale
[why this stack fits THIS problem — cite the fit dimensions that drove the choice:
workload (CPU-bound vs IO/concurrent), ecosystem/libraries, team skills, deploy target,
data/ML, compliance, latency/cold-start. "It's the proven default" is NOT a fit reason —
this record must cite fit (enforced by conformance/stack-decision-integrity.sh).]

## Maturity acknowledged
[chosen stack's kit-maturity tier (verified / first-class / experimental) — recorded so the
fit-vs-maturity trade-off is explicit; see docs/STACK-SELECTION.md.]

## Alternatives considered
1. **[Option A]** — pros: [...] · cons: [...]
2. **[Option B]** — pros: [...] · cons: [...]

## Consequences
- Profile in effect: `profiles/<stack>.md` (selected / generated).
- Easier: [...]. Harder: [...]. Accepted trade-offs / tech debt: [...].

## Follow-up
- [ ] Profile selected or generated and committed
- [ ] CI baseline green on empty project (per profile)
- [ ] `.env.example` seeded from profile
