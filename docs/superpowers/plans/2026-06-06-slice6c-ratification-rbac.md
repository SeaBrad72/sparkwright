# Slice 6c: Ratification RBAC — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Pillar 3 of the enterprise addendum — define **which roles may ratify what** (extending `DEVELOPMENT-PROCESS.md` §12/§13), and codify the **governed-exception process** that settles the Slice 5e deferred question: posture/gates are *universally required*; only a Security Owner may ratify a documented, time-boxed exception.

**Architecture:** A short contract added to §13 (Agent Governance) + a §12 cross-reference, with the full role model, separation-of-duties rules, GitHub mapping, and exception template in `docs/enterprise/ratification-rbac.md`. No new gate, no code, no script (6d's audit-evidence checklist attests it). Maps onto the existing CODEOWNERS + BRANCH-PROTECTION companions and the `agent-autonomy.sh` human-gate set (unchanged — agents still cannot self-ratify).

**Tech Stack:** Markdown · `conformance/check-links.sh`.

**Design source:** `docs/superpowers/specs/2026-06-06-slice6-enterprise-umbrella-design.md` §4c.

---

## Task 1: §13 ratification-roles subsection + §12 cross-reference (the contract)

**Files:**
- Modify: `DEVELOPMENT-PROCESS.md` (§13 insert after the autonomy-tiers paragraph at line 315, before `### Auditability` at line 317; §12 append to the "Review routing / ownership" bullet)

- [ ] **Step 1: §13 — insert the new subsection.** After this existing paragraph (the end of "### Autonomy tiers"):
```markdown
**Irreversible / high-blast-radius actions are always human-gated regardless of tier.** A project raises an action's tier as the agent-quality metrics earn it.
```
add a blank line and then exactly:
```markdown
### Ratification roles & exceptions

"Humans ratify" (§12) means a **named role**, not merely "a human." Roles and what each may ratify:

| Role | May ratify |
|------|-----------|
| **Project Owner** | requirements & scope, architecture (ADRs), breaking changes |
| **Code Owner** (per CODEOWNERS) | code PRs in their domain — the independent reviewer (builder ≠ sole merger, §12) |
| **Security Owner** | governing-doc changes (`CLAUDE.md` / STANDARDS / PROCESS), gate definitions, **supply-chain / OIDC posture exceptions**, secret-rotation policy, autonomy-tier raises |
| **Release Manager** | production deploys / promotions, rollbacks |

One person may hold several roles in a small org, but **never both the builder and the sole ratifier of the same change**. Roles map to GitHub via CODEOWNERS + branch-protection required reviewers.

**Governed exceptions.** Required gates (§14 of the standards) and security posture are **universally required — never silently "conditional."** An exception is an auditable event: a **Security-Owner-ratified, time-boxed** record stating what is waived, why, the expiry, and the compensating control. → `docs/enterprise/ratification-rbac.md`.
```

- [ ] **Step 2: §12 — append the cross-reference.** Find this exact bullet:
```markdown
- **Review routing / ownership.** CODEOWNERS-style mapping of who/which agent/lens reviews what. **An agent never reviews-and-merges its own work.**
```
and append (same line, after the bold sentence):
```markdown
 Ratification authority by role → §13 and `docs/enterprise/ratification-rbac.md`.
```
so the bullet reads: `... **An agent never reviews-and-merges its own work.** Ratification authority by role → §13 and ` `docs/enterprise/ratification-rbac.md` `.`

- [ ] **Step 3: Verify.**
```bash
grep -n "### Ratification roles & exceptions" DEVELOPMENT-PROCESS.md   # one match, in §13 between autonomy-tiers and Auditability
grep -n "Ratification authority by role" DEVELOPMENT-PROCESS.md         # one match, in §12
sh conformance/check-links.sh ; echo "exit=$?"                          # exit=0
```

- [ ] **Step 4: Commit.**
```bash
git add DEVELOPMENT-PROCESS.md
git commit -m "$(printf 'docs(process): §13 ratification roles + governed-exception; §12 cross-ref\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 2: `docs/enterprise/ratification-rbac.md` (the reference)

**Files:**
- Create: `docs/enterprise/ratification-rbac.md`

- [ ] **Step 1: Write the file** with exactly this content:

```markdown
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
```

NOTE: `audit-evidence-checklist.md` is referenced as PLAIN TEXT (backticks, not a link) because that file is created in Slice 6d — a live link would break `check-links.sh`. Keep it plain text. The `README.md` link IS live (it exists).

- [ ] **Step 2: Verify.**
```bash
sh conformance/check-links.sh ; echo "exit=$?"   # exit=0 (apply the NOTE if it flags the 6d file)
ls docs/enterprise/ratification-rbac.md
```

- [ ] **Step 3: Commit.**
```bash
git add docs/enterprise/ratification-rbac.md
git commit -m "$(printf 'docs(enterprise): ratification RBAC — roles, SoD, GitHub mapping, exception process (6c)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 3: README live link

**Files:**
- Modify: `docs/enterprise/README.md` (Contents table)

- [ ] **Step 1:** Change the plain-text row:
```markdown
| ratification-rbac.md *(Slice 6c)* | Which roles may ratify what; the governed-exception process. |
```
to a live link:
```markdown
| [ratification-rbac.md](ratification-rbac.md) | Which roles may ratify what; the governed-exception process. |
```

- [ ] **Step 2: Verify.**
```bash
sh conformance/check-links.sh ; echo "exit=$?"   # exit=0
grep -n "\[ratification-rbac.md\](ratification-rbac.md)" docs/enterprise/README.md   # one match
```

- [ ] **Step 3: Commit.**
```bash
git add docs/enterprise/README.md
git commit -m "$(printf 'docs(enterprise): make ratification-rbac README link live (6c)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 4: VERSION, CHANGELOG, ROADMAP

**Files:**
- Modify: `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: VERSION** → exactly:
```
2.11.0
```

- [ ] **Step 2: CHANGELOG** — insert above `## [2.10.0] - 2026-06-06`:
```markdown
## [2.11.0] - 2026-06-06

Slice 6c — Enterprise addendum, pillar 3: ratification RBAC. Third of four sub-slices.

### Added
- `DEVELOPMENT-PROCESS.md` §13 **"Ratification roles & exceptions"** — defines which named role (Project Owner / Code Owner / Security Owner / Release Manager) may ratify what, the builder ≠ sole-ratifier rule per change, and the **governed-exception process**: required gates/posture are universally required; a Security-Owner-ratified, time-boxed record is the only way to waive (settles the Slice 5e deferred question). §12 cross-references it.
- `docs/enterprise/ratification-rbac.md` — full role model, separation-of-duties, GitHub mapping (CODEOWNERS + branch protection + the profile companions), and the exception-record template.

### Note
No new gate, no code. The agent-autonomy human-gate set is unchanged — agents propose; a human in the appropriate role ratifies. Maps onto existing CODEOWNERS / BRANCH-PROTECTION companions; 6d's audit-evidence checklist attests it.
```

- [ ] **Step 3: ROADMAP** — insert after the `6b ✅` row:
```markdown
| 6c ✅ | **Ratification RBAC** *(shipped v2.11.0)* | process §12/§13 | `docs/enterprise/ratification-rbac.md` + §13 roles/exception contract | `agent-autonomy.sh` + audit-evidence (6d) |
```

- [ ] **Step 4: Verify.**
```bash
cat VERSION   # 2.11.0
grep -n "2.11.0" CHANGELOG.md docs/ROADMAP-KIT.md
sh conformance/check-links.sh ; echo "links exit=$?"
```

- [ ] **Step 5: Commit.**
```bash
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "$(printf 'chore(release): 2.11.0 — enterprise addendum pillar 3 (ratification RBAC)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 5: Final 6c validation

**Files:** none (verification only; fix-forward if needed).

- [ ] **Step 1: Links + structure.**
```bash
sh conformance/check-links.sh ; echo "links exit=$?"
ls -1 docs/enterprise/   # README, compliance-crosswalk, secrets-at-scale, ratification-rbac
```

- [ ] **Step 2: Contract ↔ reference ↔ consistency.**
```bash
grep -q "### Ratification roles & exceptions" DEVELOPMENT-PROCESS.md && echo "§13 contract present"
grep -q "Ratification authority by role" DEVELOPMENT-PROCESS.md && echo "§12 cross-ref present"
grep -qi "Governed exceptions" docs/enterprise/ratification-rbac.md && echo "exception process present"
grep -q "\[ratification-rbac.md\](ratification-rbac.md)" docs/enterprise/README.md && echo "README link live"
grep -qi "Security-Owner-ratified\|Security Owner" docs/enterprise/ratification-rbac.md && echo "security-owner exception authority present"
```
Expected: all five print.

- [ ] **Step 3: No regression + the existing human-gate set is intact (NOT weakened).**
```bash
sh conformance/agent-autonomy.sh >/dev/null 2>&1; echo "agent-autonomy exit=$?"   # must still pass — agents still can't self-ratify
sh conformance/profile-completeness.sh >/dev/null 2>&1; echo "completeness exit=$?"
for p in profiles/*/ci.yml; do sh conformance/ci-gates.sh "$p" >/dev/null 2>&1 || echo "FAIL $p"; done; echo "ci-gates checked"
```
Expected: agent-autonomy exit=0 (the RBAC doc must not have weakened the agent human-gate enforcement); completeness exit=0; no FAIL.

No commit unless a defect is found; fix-forward and re-run.

---

## Self-review (author)

- **Spec coverage (umbrella §4c):** §13 role model + governed-exception + §12 cross-ref → Task 1; full reference (roles, SoD, GitHub mapping, exception template) → Task 2; README live link → Task 3; version/changelog/roadmap → Task 4; validation → Task 5.
- **Settles the 5e question:** the governed-exception process (universally-required, Security-Owner-ratified, time-boxed) is in both the §13 contract and the reference doc.
- **No weakening of existing governance:** Task 5 Step 3 explicitly re-runs `agent-autonomy.sh` to confirm the agent human-gate set is intact; the RBAC layer is about *which human* ratifies, not about letting agents ratify.
- **Governing-doc change (§12/§13):** Task 1 is the highest-ratification item — committed separately for a clean review diff.
