# Templates — routed by trigger

Every artifact this kit asks for has a template here. You are **not** meant to read them; you are
meant to be *sent* to one. This index says what sends you: scan the trigger column, find the row
that just fired, open exactly one file. If no trigger below applies to your project yet, none of
these are yours yet.

## Always

Reach for these whenever the work calls for them — no gate has to fire first.

| Template | Reach for it when |
|---|---|
| `FEATURE-REQUEST-TEMPLATE.md` | you have an idea to put on the board — the intake artifact; its acceptance criteria are what `conformance/dor-defined.sh` grades a Ready item against |
| `REVIEW-RECORD-TEMPLATE.md` | you are recording a review verdict outside the forge (`conformance/review-lane.sh`) |
| `TASK-CONTEXT-CONTRACT-TEMPLATE.md` | you are briefing an agent seat — the context it is owed and the prohibitions it carries (`conformance/model-tiering-plan-wired.sh`) |
| `POSTMORTEM-TEMPLATE.md` | a P0/P1 incident closed and the learning has to route back into an artifact |
| `KIT-FEEDBACK-TEMPLATE.md` | the kit itself got in your way and you want that upstream (`sh conformance/doc-markers.sh feedback-link-lifecycle`) |
| `FIELD-REPORT-TEMPLATE.md` | you ran the kit cold on a real project and are reporting what actually happened |

## At Inception

`scripts/incept.sh` stamps these into your repo for you — you fill them, you do not copy them.

| Template | Stamped as | Proven by |
|---|---|---|
| `PROJECT-CLAUDE-TEMPLATE.md` | your project `CLAUDE.md` | `conformance/onboarding-complete.sh` |
| `RUNBOOK-TEMPLATE.md` | `RUNBOOK.md` | `conformance/runbook-current.sh` |
| `SECURITY-TEMPLATE.md` | `SECURITY.md` | `conformance/security-policy.sh` |
| `REQUIRED-CHECKS-TEMPLATE.md` | `REQUIRED-CHECKS.md` | `conformance/branch-protection.sh` |
| `DECISIONS-TEMPLATE.md` | `docs/governance/DECISIONS.md` | `conformance/decision-integrity.sh` |
| `BACKLOG-TEMPLATE.md` | `BACKLOG.md`, on the repo-native backend | `conformance/backlog-presence.sh` |
| `JIRA-SETUP-TEMPLATE.md` · `TRACKER-SETUP-TEMPLATE.md` | `JIRA-SETUP.md` / `TRACKER-SETUP.md`, on a hosted backend | `conformance/tracker-contract.sh` |

Run with `--mode enterprise` and incept additionally stamps the governance set into
`docs/governance/` ready-to-fill: `THREAT-MODEL`, `PRIVACY-REVIEW`, `AI-SYSTEM-CARD`, `AI-POLICY`,
`AI-TRANSPARENCY-SIGNOFF`, `A11Y-SIGNOFF`, `BIA`, `UAT-SIGNOFF`, `WAIVER-REGISTER`. That is
**surfacing, not enforcement** — each one still keys on its own trigger below.

## When a gate fires

Each row names the check that asks for the artifact; until its trigger applies, that check renders
N/A and the template is not yours.

| Template | The check that fires | Its trigger |
|---|---|---|
| `THREAT-MODEL-TEMPLATE.md` | `conformance/threat-obligation.sh` | sensitive, regulated or personal data |
| `PRIVACY-REVIEW-TEMPLATE.md` | `sh conformance/readiness.sh privacy-ready` | data classified Confidential or Restricted |
| `AI-SYSTEM-CARD-TEMPLATE.md` | `sh conformance/readiness.sh responsible-ai-ready` | any AI feature |
| `EVAL-PLAN-TEMPLATE.md` | `sh conformance/readiness.sh eval-ready` | any AI feature — its threshold and harness |
| `AI-POLICY-TEMPLATE.md` · `AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md` · `AI-ARTIFACT-LINEAGE-TEMPLATE.md` | `sh conformance/doc-markers.sh artifact-lineage` + `conformance/responsible-ai-readiness.md` | AI-generated output reaches users or an audit trail |
| `TEST-PLAN-TEMPLATE.md` | `conformance/test-layers-ready.sh` | a QA seat owns the test lens for the increment |
| `UAT-SIGNOFF-TEMPLATE.md` | `conformance/uat-obligation.sh` | an increment needs acceptance before release |
| `A11Y-SIGNOFF-TEMPLATE.md` | `conformance/a11y-obligation.sh` | a user-facing surface |
| `BIA-TEMPLATE.md` | `sh conformance/readiness.sh dr-ready` | a data service — RTO/RPO and a restore drill |
| `WAIVER-REGISTER.md` | `conformance/waivers-valid.sh` | you are riding a deferrable gate on the waiver ramp |

## Upstream of the board

| Template | Reach for it when |
|---|---|
| `OPPORTUNITY-BRIEF-TEMPLATE.md` | FRAME — a raw signal needs framing before it is an item |
| `SHAPING-DOC-TEMPLATE.md` | SHAPE — a framed opportunity needs shaping into Ready slices |

Both belong to the optional discovery loop (`docs/discovery/discovery-loop.md`); `conformance/discovery-complete.sh` proves that layer is present and wired.
