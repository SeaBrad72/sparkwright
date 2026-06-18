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
| 8d ✅ | **Resilience + load/soak verification** *(shipped v2.22.0)* | standards §4/§6 + process §7 (chaos/SRE) | `resilience-verification.md` + `resilience-readiness.md` + `resilience-ready.sh` (conditional, --selftest) | `resilience-ready.sh --selftest` + `check-links.sh` |
| 8e ✅ | **Progressive-delivery + smoke gates** *(shipped v2.23.0)* | process §10 + standards §14 + 8b checklist | `progressive-delivery.md` + §14 smoke-gate + tightened deployable smoke row | `check-links.sh` + the (tightened) Definition-of-Deployable checklist |
| 8f ✅ | **DORA metrics collection** *(shipped v2.24.0)* | process §14/§9 (DORA + maturity-gating) | `dora-metrics.md` + `scripts/dora.sh` (GitHub-derivable subset, graceful degradation, --selftest) | `dora.sh --selftest` (CI smoke) + `check-links.sh` |
| 6 ✅ | **Enterprise addendum** | standards §2 (partial) | compliance-control mapping (SOC2/ISO), secrets-at-scale (Vault/KMS) patterns, RBAC for ratification | `conformance/audit-evidence` checklist — enterprise addendum complete (6a–6d), v3.0.0 milestone |

## Notes
- **Slice 8 shipped in v2.24.0** (incident response · definition of deployable · DR/backup-restore · resilience+load · progressive delivery · DORA — the continuity & safe-delivery arc, complete).
- Order matches the "CI first" priority: governance is only *enforced* once CI and the agent layer are wired.
- Slices 1–2 convert the kit from *described* governance to *enforced* governance — highest leverage. **Slice 1 shipped in v2.0.0; Slice 2 in v2.1.0 — that conversion is now complete.**
- Re-prioritize at the kit's L2/L3 retros; this order is the default, not a commitment.

---

## Post-2.62.0 fix-forward backlog (from the pre-launch go/no-go arc)

The pre-launch go/no-go (8 adversarial rounds) reached **0 blockers on the supported path**. **Most of this backlog shipped in 2.62.1** (Docker-verified where marked); the rest remains fix-forward. None breaks the verified `typescript-node` path or a headline claim.

**Highs — ✅ all closed in 2.62.1:**
- ✅ **go** — shipped `.golangci.yml` (govet/staticcheck/errcheck/gosec) + pinned `golangci-lint` version + `newServer()` refactor for gosec G114. *(Docker-verified)*
- ✅ **java-spring** — OWASP dep-scan now caches NVD + accepts optional `NVD_API_KEY` + first-run caveat.
- ✅ **kotlin** — `gradle wrapper` step pinned to `--gradle-version 8.10`.

**Mediums:**
- ✅ **ts-node** Dockerfile `HEALTHCHECK` — added `src/healthcheck.ts` + fixed the distroless node path (`/nodejs/bin/node`). *(Docker-verified: container `healthy`)*
- ✅ **dotnet** — added `.editorconfig` + `Directory.Build.props`; Dockerfile publishes the app project only + drops the bad root lockfile COPY. *(Docker-verified: 0 warnings)*
- ✅ **incept** scaffold-copy now skips stray build artifacts (`node_modules`/`dist`/`coverage`/`__pycache__`/`.coverage`/`target`/`bin`/`obj`/…).
- ⬜ **dep-scan prod-scoping consistency** *(remaining)* — ts uses `--omit=dev`; python `pip-audit` and java/kotlin OWASP audit all scopes. Unify the prod-dep posture + add a non-blocking dev-advisory audit. *(Cross-stack mechanic change; ts already prod-scoped — lower value, deferred.)*

**Lows/Nits (remaining, fix-forward):** gate-sast `--config auto` network/Pro-rules caveat note · rust `llvm-tools-preview` component note · java-spring Dockerfile `mvnw`-wrapper comment · non-ts reference `ci.yml` SHA-pin (vs major-float) for parity with ts-node · run `mvn wrapper:wrapper && ./mvnw verify` once to convert java-spring from "authored" to "maintainer-verified."

---

## Harness-neutrality arc (→ `3.0.0`)

Make the kit **LLM/harness-neutral** — anyone can pick it up with any agent harness out of the gate, while **Claude Code stays the default** and is regression-locked by its existing conformance. Full adapter model; first target = the generic/AGENTS.md baseline; **split proof bar** (enforcement maintainer-verified, process authored-to-contract). Design spec: `docs/superpowers/specs/2026-06-17-harness-neutrality-design.md`. Ships as additive minors; `3.0.0` is cut at N4.

| Slice | Ships | Status |
|-------|-------|--------|
| **N1 — `agent-boundary` CI gate** | harness-independent control-plane-ratification gate + `conformance/agent-boundary.sh` + reference job + §13 clause | ✅ **shipped 2.63.0** |
| **N2 — adapter contract + `harness-adapter.sh`** | boundary-contract doc + adapter manifest + composing conformance check + name `.claude/` the `claude-code` reference adapter | ✅ **shipped 2.64.0** |
| **N3 — `generic` adapter + `incept --harness`** | generic/AGENTS.md adapter + `--harness` flag (default `claude-code`) + per-harness verification + Inception-Done enforcement | ✅ **shipped 2.65.0** |
| **N4 — proof + positioning → cut `3.0.0`** | enforcement-evidence doc (the 3 CI-locked surface selftests) + BYO adapter `_TEMPLATE` + `new-adapter.sh` + stack/harness-neutral positioning + **release `3.0.0`** | ✅ **shipped 3.0.0 — harness-neutrality arc COMPLETE** |

---

## Post-3.0.0 backlog (consolidated + prioritized)

Sources: the 11-dimension adversarial go/no-go on 3.0.0 (**GO-WITH-CONDITIONS**, 0 blockers), the post-3.0.0 weight/usefulness review, the solo-vs-team review discussion, and a proactive hardening/edge-case sweep. **Burn-down order** (default — re-prioritize at a retro): **P1 ✅ → H1 → P2 → H2 → D1 → H3 → H4 → P3 → P4.** Hardening the *enforcement model* (H1) outranks usability polish — a kit whose own gates the agent can quietly disable is worse than a slightly heavier, tamper-resistant one. None below breaks the verified `typescript-node` path or a headline claim.

### P1 — Integrity & honest enforcement ✅ *shipped 3.1.0*
N5 `controlPlanePaths` union enforcement (the gate now denies unratified changes to the union of adapter-declared paths) + profile parity (python `fail_under=80`; GitLab `gate-eval`) + conformance hardening (branch-protection advisory; honest guard-bypass-class enumeration).

### H1 — Enforcement integrity ✅ *shipped 3.2.0* — the kit's own controls now resist the agent they govern
The enforcement layer (`conformance/`, `adapters/`, the named `scripts/`, `scripts/fixtures/`, and the governing docs `DEVELOPMENT-STANDARDS`/`PROCESS` + `CLAUDE.md`) is now in `guard-core.sh::is_control_plane_path`, so weakening a gate, relaxing the Definition of Done, or adding an adapter requires ratification (**H1.1**) — `scripts/` is a named-script set so an adopter's own `scripts/` code is untouched. `harness-adapter.sh` executes `proof.check` only from a vetted `conformance/*.sh` allowlist, rejecting metacharacter/traversal strings *before* execution (**H1.2**). The agent-forgeable `ratified-control-plane` label is removed — ratification is a non-author approval; solo = logged admin-merge (**H1.3**). The kit now dogfoods the real `gate-agent-boundary` job on its own PRs (**H1.4**); an unratified control-plane diff shows the check **red** (`exit 1`) meaning *ratify me* — the "ratification required" semantics ride naming + docs since GitHub has no non-failing blocking state for a plain step (live-verified on PR #110). **D4-presentation (3.6.0, PR #114) replaced the red `exit 1` with an `action_required` merge-gate** — the job exits 0 and posts a `control-plane-ratification` check that blocks the merge in amber with no "CI failed" email (red/email reserved for real failures; live-verified). Honest ceilings: the command-string guard layer is unchanged (a `python -c`/script control-plane edit isn't caught inline — the CI gate is the post-hoc backstop); command-string false-positive tuning → P2/WS1; GitLab gate parity → H4.

### P2 — Usability & governance ergonomics (light, not weak) ✅ *complete (WS1–WS4 shipped 3.3.0–3.7.0)* — *design spec: `docs/superpowers/specs/2026-06-17-p2-usability-governance-design.md`*
*(NOTE: "opt-in/modular enterprise layers" from the first backlog draft is **REJECTED** — conditional-applicability already auto-skips inapplicable controls; opt-in would re-create the add-compliance-later trap. The fix is friction-removal + surfacing, never weakening an applicable control.)*
- **WS1 — Guard false-positive fix** ✅ *shipped 3.3.0* — **deny-by-default**: keep the prior co-occurrence deny as the floor (no protection removed), allow back ONLY a provably-safe single read command (no chaining/substitution; leading verb in a strict write/exec-free read allowlist). Path basename net narrowed + `fpn` normalized (`./`, trailing `/`, `..` fixpoint) — fixes a real `.vscode/settings.json` report and the `./`/`../name` escapes. Dual corpus in `conformance/agent-autonomy.sh` locks both directions; **four adversarial security reviews** (the first attempt's allow-by-default shipped 5 weaknesses → reverted → re-architected). Residuals (compound-mention denied; `sort -o`/`xxd -r`/`perl -pi` floor gaps; var/`eval` indirection) are documented + agent-boundary-gate-backstopped.
- **WS2 — Risk-tiered solo review lane** ✅ *shipped 3.4.0* — default = recorded `reviewer`-subagent review + recorded human ratification (the logged independent review); high-risk (control-plane/security/data/prod/irreversible) = + a human structured self-review with specific acknowledgments tied to findings (anti-theater). Compliance-honest *compensating controls* → enforced two-human SoD via a single `enforce_admins: true` flip (zero rework of recorded evidence) when a teammate joins. Shipped: `templates/REVIEW-RECORD-TEMPLATE.md` · `docs/operations/review-lane.md` · §12 net-zero pointer · audit-evidence SoD row · `conformance/review-lane.sh`. Honest ceiling: the high-risk self-review is process discipline, not a fail-closed gate (agent-boundary CI gate backstops control-plane diffs).
- **WS3 — Progressive-disclosure front door** ✅ *shipped 3.5.0* — `START-HERE.md` gets a top "you do not need to read all of this" block: the first-5 core path (START-HERE · CLAUDE · DEVELOPMENT-PROCESS · profile · AGENTS) + a pull-not-push trigger map (regulated → enterprise/; live → operations/; data → continuity/; artifact → templates/); matching note in `ONBOARDING.md`; enterprise index framed pull-not-push. Nothing deleted, no gate disabled. Locked by `conformance/onboarding-complete.sh`.
- **WS4 — Persona routing** ✅ *shipped 3.7.0* — `ONBOARDING.md` "Which role are you?" table routes the non-engineer personas (PO/Designer/QA/Security Owner/DevOps) to their entry artifacts + the authoritative §2, with a "rigor is carried, not waived" note (gates are persona-blind). Interactive `incept` now prompts operator-fluency (non-coercive empty-enter). *Security Owner in the §13 ratification table was verified already present (added in WS2) — no edit.* Residual: the `incept` :118-119 fluency membership test loose-matches a multi-token string (pre-existing, non-exploitable, reviewer-confirmed) → tracked for a control-plane validation-hardening ticket.

### H2 — Containment reference (Tier 2) — ship the boundary the guard only documents
- **H2a — Reference platform boundary** ✅ *shipped 3.8.0* — *a verify-before-build pass found the egress-allowlist config was already shipped (11b: concrete default-deny + allowlist NetworkPolicy in `docs/operations/egress-control.md` + `conformance/egress-policy.sh`), and "no-egress devcontainer" was a category error for a dev inner-loop (it needs egress for package installs).* Reframed to **sandbox-FS devcontainer + egress-allowlist pairing** and closed the two real gaps: (1) the `typescript-node` profile now **dogfoods** the read-only-FS pattern it documents — a host-isolated `agent` service in `compose.yaml` (`read_only` + `tmpfs` + work-tree-only mount + `cap_drop: [ALL]` + `no-new-privileges` + `network_mode: none`, opt-in behind a compose profile so the verified app path is untouched) + a matching `.devcontainer/devcontainer.sandbox.json`; (2) concrete **AWS/GCP/Azure OIDC-federation** snippets in `containment.md` §2 (was prose-only). FS-sandbox and egress kept honestly separate; enforcement stays platform-owned. Design: `docs/superpowers/specs/2026-06-18-h2a-containment-reference-design.md`.
- **H2b — Non-Claude inline guard** — Codex/Cursor adopters have NO inline command guard (only `pre-push` + the CI floor). Build the named `kit-guard install-shims` (PATH-shims wrapping dangerous binaries → call `kit-guard` before exec) so non-Claude harnesses get inline coverage too.

### D1 — Continuous drift detection — make semantic-drift detection continuous, not heroic
Structural drift is caught continuously (badge/links/coverage-meta); SEMANTIC drift (doc-claims-vs-code, staleness) is caught only by the periodic go/no-go. Close it: a **scheduled go/no-go-lite** (cron, a few key dimensions) + a **claims-registry meta-check** (every headline claim links to a verifying check; an unbacked claim fails — generalizing `badge-version.sh`). Feeds / overlaps `sparkwright doctor` (P3).

### H3 — Agentic-risk hardening (Tier 3)
- **Secret-in-context** — the guard blocks *writing* secrets but not the agent *reading* a `.env`/key into its context (→ model provider, logs, PR). Add redaction guidance + a nudge against `cat .env`-style reads.
- **Cost/token circuit-breaker** — no budget guardrail today (the 3.0.0 go/no-go alone was ~2.36M tokens). Add a per-run budget contract + a stop.
- **Long-session drift self-check** — a periodic mid-session re-check against the active plan/standards.

### H4 — Coverage gaps (Tier 4)
- **GitLab governance parity** — branch-protection, ratification, and DORA enforcement are GitHub-only; GitLab adopters get materially less. Build the GitLab equivalents or scope the claim honestly.
- **Kit's own tool supply chain** — `jq`/`gh`/`shellcheck`/`cosign`/`syft` the conformance layer shells out to are unpinned/unverified; a compromised tool subverts the gates. Pin + verify.

### P3 — Growth & verification
- **Verified second harness (Codex) + first-class adapters** — flip the split bar's process half to *maintainer-verified*; ship `codex`/`cursor`/`gemini` adapters beyond `generic`.
- **`sparkwright doctor`** — an adopter posture command composing the conformance + readiness sweep (doubles as the adopter-facing drift detector; overlaps D1).
- **Close the operate loop** — incident → auto-postmortem stub → backlog item; DORA + `agent-scorecard` → autonomy-tier adjustment.
- **Broaden the front door** — more archetype scaffolds + deeper discovery.

### P4 — Polish (Low)
- **Operability / meta-docs** — RUNBOOK incident-response section; meta-doc staleness sweep (dates, counts).
- **Misc** — designer handoff guidance (axe/Lighthouse); ts-node AI-security pointer + eval scaffold; rename documentation-only CI step labels.

---

**Last Updated:** 2026-06-17
