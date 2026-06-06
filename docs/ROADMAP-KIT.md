# Kit Roadmap — Remaining Slices

The kit's **own backlog** (dogfooding `DEVELOPMENT-PROCESS.md` §6). The Foundation increment (this release, `v1.0.0`) established the meta-layer. Each remaining slice ships as a **contract → reference → conformance** vertical (`MAINTAINING.md` §1), in priority order, each with its own spec → plan → build.

| Order | Slice | Contract (mostly written) | Reference implementation to build | Conformance check |
|-------|-------|---------------------------|-----------------------------------|-------------------|
| 1 ✅ | **CI/CD** *(shipped v2.0.0)* | standards §14 + process §10/§15 | `profiles/typescript-node/ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`; kit-own `.github/workflows/ci.yml` | `conformance/ci-gates.sh` |
| 2 | **Agent governance layer** | process §13 (autonomy tiers) | `.claude/settings.json` allowlist, hooks blocking irreversible actions, reviewer/security subagents | `conformance/agent-autonomy` — a tier breach is blocked |
| 3 | **Inception bootstrap** | START-HERE 8-step gate | `init` script: scaffold structure, CI, stamped project `CLAUDE.md`/`RUNBOOK`/`BACKLOG` | Inception-Done checklist, automated |
| 4 | **Template fixes** | DoD + process §6 | rewrite `BACKLOG-TEMPLATE.md` to the flow-board model; add `RUNBOOK-TEMPLATE.md` | `conformance/template-lint` — placeholders filled, matches §6 |
| 5 | **Enterprise profiles** | `profiles/_TEMPLATE.md` | `profiles/python.md` + `profiles/java-spring.md` with real config files | `conformance/profile-completeness` — every section filled |
| 6 | **Enterprise addendum** | standards §2 (partial) | compliance-control mapping (SOC2/ISO), secrets-at-scale (Vault/KMS) patterns, RBAC for ratification | `conformance/audit-evidence` checklist |

## Notes
- Order matches the "CI first" priority: governance is only *enforced* once CI and the agent layer are wired.
- Slices 1–2 convert the kit from *described* governance to *enforced* governance — highest leverage. **Slice 1 shipped in v2.0.0.**
- Re-prioritize at the kit's L2/L3 retros; this order is the default, not a commitment.

---

**Last Updated:** 2026-06-05
