# Kit Roadmap — Remaining Slices

The kit's **own backlog** (dogfooding `DEVELOPMENT-PROCESS.md` §6). The Foundation increment (this release, `v1.0.0`) established the meta-layer. Each remaining slice ships as a **contract → reference → conformance** vertical (`MAINTAINING.md` §1), in priority order, each with its own spec → plan → build.

| Order | Slice | Contract (mostly written) | Reference implementation to build | Conformance check |
|-------|-------|---------------------------|-----------------------------------|-------------------|
| 1 ✅ | **CI/CD** *(shipped v2.0.0)* | standards §14 + process §10/§15 | `profiles/typescript-node/ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`; kit-own `.github/workflows/ci.yml` | `conformance/ci-gates.sh` |
| 2 ✅ | **Agent governance** *(shipped v2.1.0)* | process §13 + enforcement-reference note | `.claude/` — `settings.json`, `hooks/guard.sh`, `reviewer` + `security-reviewer` subagents, `README.md` | `conformance/agent-autonomy.sh` |
| 3 ✅ | **Inception bootstrap** *(shipped v2.2.0; absorbed templates)* | START-HERE 8-step gate | `scripts/incept.sh` + `RUNBOOK-TEMPLATE.md` + flow-board `BACKLOG-TEMPLATE.md` | `conformance/inception-done.sh` |
| ~~4~~ | **Template fixes** *(absorbed into Slice 3, v2.2.0)* | DoD + process §6 | RUNBOOK-TEMPLATE.md + flow-board BACKLOG-TEMPLATE.md shipped | covered by `inception-done.sh` |
| 5 ✅ | **Enterprise profiles** *(v2.3.0 → v2.5.0)* | `profiles/_TEMPLATE.md` | Python, Java/Spring (v2.3.0); .NET, Go, Rust, Kotlin + BYO `new-profile.sh` (v2.4.0); **ML — eval-gate-centric (v2.5.0)** | `conformance/profile-completeness.sh` |
| 5c2 ✅ | **Data-engineering profile** *(shipped v2.6.0)* | `profiles/_TEMPLATE.md` | `profiles/data-engineering/` — dbt + Dagster + Python; `gate-data-quality` (dbt build + Great Expectations) | `conformance/profile-completeness.sh` |
| 5d ✅ | **Terraform/IaC profile** *(shipped v2.7.0)* | `profiles/_TEMPLATE.md` | `profiles/terraform/` — Terraform + tflint + Checkov + conftest/OPA + Trivy; `gate-policy`; §14 via IaC analogs | `conformance/profile-completeness.sh` |
| 6 | **Enterprise addendum** | standards §2 (partial) | compliance-control mapping (SOC2/ISO), secrets-at-scale (Vault/KMS) patterns, RBAC for ratification | `conformance/audit-evidence` checklist |

## Notes
- Order matches the "CI first" priority: governance is only *enforced* once CI and the agent layer are wired.
- Slices 1–2 convert the kit from *described* governance to *enforced* governance — highest leverage. **Slice 1 shipped in v2.0.0; Slice 2 in v2.1.0 — that conversion is now complete.**
- Re-prioritize at the kit's L2/L3 retros; this order is the default, not a commitment.

---

**Last Updated:** 2026-06-06
