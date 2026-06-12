# Executive Brief — Agentic SDLC Kit

The leadership (VP-Eng / CTO) front door. Two pages, scope-honest. For the full enterprise addendum see [README.md](README.md); for the framework mapping, [compliance-crosswalk.md](compliance-crosswalk.md).

---

## 1. What it is

A portable, *executable* governance & assurance layer for agentic software development — a methodology **plus** a conformance harness you own and run in **your own CI**. It is not a platform you buy, not a runtime you depend on, and not a service that holds your code or credentials. You copy it into your repo, choose your stack, and the checks run on every push.

## 2. Why now

Agents increasingly take the first pass at the SDLC. The field's own data is the warning: AI adoption layered onto weak governance was associated with a **+30% change-failure rate** and **+23.5% incidents per PR** ([competitive benchmark, A5 record](../superpowers/reviews/2026-06-10-competitive-benchmark.md)). Agents amplify whatever discipline — or lack of it — they are dropped into. This kit is the guardrails-first answer: agents move fast *inside* enforced boundaries, so throughput becomes safe to lean on rather than a risk multiplier.

## 3. What leadership gets

- **Relative assurance against irreversible damage.** A committed agent guard (PROCESS §13), branch protection (builder ≠ sole merger), and destructive-action denials make it hard for an agent *or* a human to trivially cause irreversible harm — now reused across runtimes via a git `pre-push` hook and a `kit-guard` CLI ([runtime-guards.md](../operations/runtime-guards.md)). This is risk reduction, not a guarantee — see §5.
- **Audit-ready evidence.** Controls map to SOC 2, ISO 27001:2022, and NIST SSDF (SP 800-218) ([compliance-crosswalk.md](compliance-crosswalk.md)), with a per-control evidence list ([audit-evidence-checklist.md](../../conformance/audit-evidence-checklist.md)), a ratification RBAC model ([ratification-rbac.md](ratification-rbac.md)), and a tested guard.
- **No lock-in.** Vendor-neutral, stack-neutral, POSIX-clean. It sits *alongside* your IDP and CI, not instead of them.

## 4. How it's different

From the [A5 benchmark](../superpowers/reviews/2026-06-10-competitive-benchmark.md), three properties together are rare:

- **Agent-native *and* enforcement-native** — executable, CI-verified checks an agent or a human runs the same way. Not portal templates, not PDF norms.
- **Honesty as a feature** — *"green ≠ verified,"* a three-state conformance model, and a guard positioned as a speed bump, not a boundary. The kit tells you where its own controls stop.
- **Complements, doesn't replace** — it has no UI, catalog, or token broker; it layers assurance onto whatever platform you already run.

## 5. Honest boundaries

The runtime guard is a **speed bump, not a boundary** for shell and interpreter commands — a deny-list over a shell cannot contain a determined or compromised agent (interpreters and obfuscation defeat pattern-matching; `--no-verify` bypasses the git hook). Two honest refinements (Slices 11a–11c): the guard now **enforces** a deny-by-default **MCP capability gate** in-process (the one in-process control that is real enforcement — by tool name only), and the kit now **ships + verifies references** for the four platform controls — a network-egress allowlist (the only real exfiltration defense), separate production credentials, a sandboxed filesystem, and scoped short-lived tokens — which remain **platform-enforced** (Kit-assisted, not Kit-enforced). Adopt both — the guard prevents accidents cheaply; the platform boundary is what you certify. See [platform-safety-boundary.md](platform-safety-boundary.md).

## 6. Compliance at a glance

| Framework | What the kit assures | Org-owned |
|-----------|----------------------|-----------|
| **SOC 2** (Security + Privacy) | CI quality gates, secret-scan, SBOM + provenance, branch protection, agent guard, audit-logging primitives — mechanical evidence (CC6–CC9, CC1) | Personnel/HR, physical security, vendor risk, the platform safety boundary, and the privacy *program* (notice, consent, DSAR) |
| **ISO 27001:2022** (Annex A) | Secure development life cycle, change management, supply-chain integrity, access control in CI, logging (A.8.25/.28/.32, A.5.21) | Screening (A.6), physical controls (A.7), supplier relationships (A.5.19–.22), network egress/segregation (A.8.20–.23) |
| **NIST SSDF** (SP 800-218) + **SLSA** | Secure-build practices mapped per control (PO/PS/PW/RV); **SLSA Build L2** provenance on artifacts built by the reference pipeline (authenticated, service-generated, digest-bound) | The org's broader SSDF program adoption; SLSA L3 (hermetic build) if required |

Full mapping, with per-row *Kit-enforced / Kit-assisted / Org-owned* responsibility → [compliance-crosswalk.md](compliance-crosswalk.md).

Since Slices 11a–11c, the agent/runtime platform-boundary rows (egress, sandboxed FS, scoped tokens, separate prod credentials) are **Kit-assisted** (reference shipped + wiring verified, host-enforced), and the **MCP capability gate** is **Kit-enforced** (by tool name). The drift-guard `conformance/assurance-tiers.sh` holds these tiers in place.

## 7. Where to go next

| You are a… | Start with |
|------------|------------|
| **Leader (VP-Eng / CTO)** | This brief, then [ORG-ROLLOUT.md](ORG-ROLLOUT.md) and [ROI-MODEL.md](ROI-MODEL.md) |
| **Engineer** | [START-HERE.md](../../START-HERE.md) — Inception and stack selection |
| **Auditor** | The enterprise docs in [this directory](./) — crosswalk, evidence checklist, RBAC, safety boundary |
| **Operator** | Your project RUNBOOK (from [RUNBOOK-TEMPLATE.md](../../templates/RUNBOOK-TEMPLATE.md)) and [conformance/README.md](../../conformance/README.md) |
