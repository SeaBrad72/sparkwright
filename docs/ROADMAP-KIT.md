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
| 5e ✅ | **CI hardening** *(shipped v2.8.0)* | standards §14 (hardening note) | all 10 `profiles/*/ci.yml` — least-privilege OIDC (push-only provenance job), checkov pin | `conformance/ci-gates.sh` + `profile-completeness.sh` |
| 6a ✅ | **Compliance crosswalk** *(shipped v2.9.0)* | standards §2/§14 | `docs/enterprise/{README,compliance-crosswalk}.md` — SOC 2 + ISO 27001:2022 + privacy family | `check-links.sh` + audit-evidence (6d) |
| 6b ✅ | **Secrets at scale** *(shipped v2.10.0)* | standards §2 | `docs/enterprise/secrets-at-scale.md` + §2 contract + `_TEMPLATE.md` pointer | `check-links.sh` |
| 6c ✅ | **Ratification RBAC** *(shipped v2.11.0)* | process §12/§13 | `docs/enterprise/ratification-rbac.md` + §13 roles/exception contract | `agent-autonomy.sh` + audit-evidence (6d) |
| 6d ✅ | **Audit-evidence capstone** *(shipped v2.12.0; `v3.0.0` milestone)* | umbrella §4d | `conformance/audit-evidence-checklist.md` — per-control evidence, ties to 6a | `check-links.sh` + the checklist itself |
| 7a ✅ | **Environments & prod safety** *(shipped v2.13.0)* | process env model + standards §14 | Dev/QA/UAT/Prod + env-aware `guard.sh` + `branch-protection.sh` | `agent-autonomy.sh` + `branch-protection.sh` |
| 7b ✅ | **Multi-persona touchpoints** *(shipped v2.14.0)* | process §2/§5/§15 | persona map + `FEATURE-REQUEST`/`SPEC` templates + persona-routed START-HERE | `check-links.sh` (+ `inception-done.sh` no regression) |
| 7c ✅ | **Containers & image supply-chain** *(shipped v2.15.0)* | standards §14/§13 + process §9 | ts-node Dockerfile/compose/devcontainer/k8s/Helm + conditional image gate | `container-supply-chain.sh` + `ci-gates.sh` (8 ids intact) |
| 7d ✅ | **Work-tracking adapters** *(shipped v2.16.0)* | process §6 | `docs/work-tracking/adapters.md` (6 trackers + BYO) + incept `--backlog` set + template | `backlog-adapters.sh` + `check-links.sh` |
| 7e ✅ | **Brownfield & `.claude/` hygiene** *(shipped v2.17.0)* | process §13 (guard) | `docs/adoption/brownfield.md` + `.claude/` scoping + incept warn | `guard-wired.sh` (gates Inception) + `check-links.sh` |
| 7f ✅ | **Doc refresh & consistency** *(shipped v2.18.0)* | — (docs only) | ratification-role casing + 10-profile count + doc-set tables + inception-done note | `check-links.sh` + casing grep |
| 8a ✅ | **Incident Response standard** *(shipped v2.19.0)* | standards §15 + process §8/§9 | §15 Incident Response + `POSTMORTEM-TEMPLATE.md` + dangling-ref fixes | `check-links.sh` + audit-evidence (Manual row) |
| 8b ✅ | **Definition of Deployable** *(shipped v2.20.0)* | process §7/§4/§10 (release readiness) | `definition-of-deployable.md` + `deployable-ready.sh` (conditional, --selftest) | `deployable-ready.sh --selftest` + `check-links.sh` |
| 8c ✅ | **DR / backup-restore + BIA** *(shipped v2.21.0)* | standards §10 + process §7/§15 + DoD (NIST 800-34) | drill reference + `BIA-TEMPLATE` + `dr-readiness.md` + `dr-ready.sh` (escalate-only) | `dr-ready.sh --selftest` + `check-links.sh` |
| 6 ✅ | **Enterprise addendum** | standards §2 (partial) | compliance-control mapping (SOC2/ISO), secrets-at-scale (Vault/KMS) patterns, RBAC for ratification | `conformance/audit-evidence` checklist — enterprise addendum complete (6a–6d), v3.0.0 milestone |

## Notes
- Order matches the "CI first" priority: governance is only *enforced* once CI and the agent layer are wired.
- Slices 1–2 convert the kit from *described* governance to *enforced* governance — highest leverage. **Slice 1 shipped in v2.0.0; Slice 2 in v2.1.0 — that conversion is now complete.**
- Re-prioritize at the kit's L2/L3 retros; this order is the default, not a commitment.

---

**Last Updated:** 2026-06-09
