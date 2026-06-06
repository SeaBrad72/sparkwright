# Ratification RBAC

Which roles may ratify which decisions, how that maps to GitHub, and how exceptions are governed. This is the reference for the `DEVELOPMENT-PROCESS.md` §13 "Ratification roles & exceptions" contract (and the §12 review-separation rule). See also the [responsibility boundary](README.md).

## Why roles, not just "a human"

The kit's rule is *agents propose, humans ratify* and *builder ≠ sole merger* (§12). At enterprise scale, "a human" is too coarse: ratifying a production deploy, a governing-doc change, and a code PR are different authorities. This assigns each decision to a **named role** so approval is accountable and auditable.

## Roles × ratifiable decisions

| Role | May ratify | Must NOT solely ratify |
|------|-----------|------------------------|
| **Project Owner** | requirements & scope, architecture (ADRs), breaking changes | their own code PRs |
| **Code Owner** (per CODEOWNERS domain) | code PRs in their domain — the independent reviewer | a PR they authored |
| **Security Owner** | governing-doc changes (`CLAUDE.md`/STANDARDS/PROCESS), gate definitions, supply-chain/OIDC **posture exceptions**, secret-rotation policy, autonomy-tier raises | a posture exception they themselves need for their own change |
| **Release Manager** | production deploys / promotions, rollback decisions | a deploy of their own unreviewed change |

### Separation of duties
- **Builder ≠ sole ratifier** of the same change (the core §12 rule, applied to every role).
- One person **may** hold multiple roles in a small org — but the SoD rule still binds per-change: the person who built a change cannot be its only approver.
- **Agents never ratify.** The agent-autonomy human-gate set (`DEVELOPMENT-PROCESS.md` §13, enforced by `.claude/hooks/guard.sh` + `conformance/agent-autonomy.sh`) is unchanged: agents propose; a human in the appropriate role ratifies.

## Mapping to GitHub

- **Code Owner** → `CODEOWNERS` (per-path reviewers); see each profile's `CODEOWNERS` companion.
- **Builder ≠ sole merger** → branch protection requiring ≥1 review from someone other than the author; see each profile's `BRANCH-PROTECTION.md` companion and STANDARDS §14.
- **Security Owner** → a CODEOWNERS entry on the governing docs (`CLAUDE.md`, `DEVELOPMENT-STANDARDS.md`, `DEVELOPMENT-PROCESS.md`, `.github/workflows/`, `conformance/`) so changes there require their review.
- **Release Manager** → environment protection rules / required reviewers on the production deploy job.

## Governed exceptions

Required gates and posture are **universally required**. There is no "conditional" gate — an exception is an explicit, auditable event.

**Process:** a posture/gate exception requires a **Security-Owner-ratified** record, time-boxed, before the waiver takes effect. Record it (issue, ADR, or exception log) with these fields:

| Field | Content |
|-------|---------|
| ID | unique reference |
| What is waived | the specific gate/posture requirement |
| Scope | repos/branches/jobs affected |
| Justification | why the exception is necessary |
| Compensating control | what mitigates the risk meanwhile |
| Ratified by | the Security Owner (≠ the requester) |
| Granted / Expires | dates — **time-boxed**, no open-ended waivers |
| Review | date the exception is re-evaluated or auto-expires |

An expired exception that hasn't been renewed means the requirement is back in force. Exceptions are evidence (see `conformance/audit-evidence-checklist.md`, Slice 6d).
