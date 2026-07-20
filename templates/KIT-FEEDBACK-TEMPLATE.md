# Kit Feedback — running friction log

> **Template.** A friction log kept **DURING** a build, not reconstructed after. Copy to your project root as `KIT-FEEDBACK.md` at adoption, stamp the header, and add one row the moment you hit friction — while the pain is fresh and the cause is legible. This is the raw capture; the end-of-run synthesis is `FIELD-REPORT-TEMPLATE.md`. Relay's entire KW backlog exists only because this log was written live.

## Stamp (fill at adoption)

| Field | Value | How to obtain |
|-------|-------|---------------|
| **Kit version** | `[e.g. 3.119.0]` | `cat VERSION` at adoption |
| **Vehicle** | `[product / repo name, e.g. sparkwright-flow, codex-probe, <brownfield-repo>]` | the thing you are building |
| **Harness** | `[claude-code / codex / cursor / …]` | the agent harness you ran |
| **Track** | `[solo / team]` | — |
| **Started** | `[YYYY-MM-DD]` | — |

Without this stamp, three concurrent dogfoods produce three unattributable anecdotes. Fill it first.

## Findings (append live — one row per friction point)

Give each finding a **K-style id** (`K1`, `K2`, …) so it is quotable in review and in the field report. **Severity:** blocker / high / medium / low.

> **Link lifecycle.** This log stays `untracked until the end-of-run synthesis commit`, yet `check-links` resolves relative links against the tracked set (`git ls-files`).
> So when a BACKLOG or field-report entry needs a finding, `cite it by its K-id as plain text, never a Markdown link` to `KIT-FEEDBACK.md` — a link becomes safe only once the synthesis commit tracks this file.

| Id | What I expected | What happened | Severity | Where (file / step) | Notes |
|----|-----------------|---------------|----------|---------------------|-------|
| K1 | [the kit's promise / my assumption] | [the actual friction] | [high] | [file, command, or phase] | [cause if known] |
| K2 | | | | | |
| K3 | | | | | |

> Add rows freely. Prefer capturing a rough row now over writing a polished one later — an unwritten finding is a lost finding.

## Wins (what worked — capture these too)

- `[e.g. dual review caught a fail-open bug shipped as a passing test — PR #NN]`

## Agent lapses (process drift you had to correct)

- `[e.g. agent left the dev-clone diff staged-but-uncommitted; had to force a commit + git show --stat]`
