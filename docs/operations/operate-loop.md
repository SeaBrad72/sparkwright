# Operate loop — incident → postmortem → backlog

**`sparkwright postmortem` closes the learning half of the operate loop:** an incident happens → a human runs `sparkwright postmortem new` to scaffold a stub → the team fills in the analysis → `sparkwright postmortem to-backlog` parses the action items and emits backlog stubs → a human reviews, creates the items, and actuates them in their tracker.

The mechanizable edges (scaffolding from incident metadata, parsing the action-items table) are automated. The judgment edges (the analysis, ratification of each action item, creating and assigning tracker items) remain human-owned. This is the kit's **never-actuate principle**: the tool generates and parses; it does not auto-detect incidents or auto-create live tracker items.

## The closed loop

```
Incident
  │
  ▼ (human: record incident metadata)
sparkwright postmortem new --id INC-042 --severity P1 --title "Login timeouts"
  │    scaffolds postmortems/INC-042.md from templates/POSTMORTEM-TEMPLATE.md
  │    (no-clobber; reads human-supplied metadata; no auto-detection)
  │
  ▼ (team: fill the analysis — timeline, root causes, contributing factors, blameless summary)
postmortems/INC-042.md  ← human-authored incident analysis
  │
  ▼ (human: run when action items section is complete)
sparkwright postmortem to-backlog postmortems/INC-042.md
  │    parses ## 7. Action items table; skips placeholders and blank rows
  │    emits backlog Ready-row stubs to stdout (for paste or tracker import)
  │
  ▼ (human: review stubs, create items in tracker, assign owners, actuate)
BACKLOG.md  /  Jira  /  Linear  /  GitHub Issues  /  …
  │
  ▼ (team: build the fix; the loop closes — DEVELOPMENT-PROCESS.md §15; CLAUDE.md principle 6)
Next iteration
```

## `sparkwright postmortem new`

Scaffolds a postmortem stub from incident metadata. Reads `templates/POSTMORTEM-TEMPLATE.md`, substitutes the header placeholders (`[Incident Title]`, `[id]`, `[P0 / P1 / P2 / P3]`, `[name / role]`, `[date]`, `[open / closed]`), and writes to `postmortems/<ID>.md`. No-clobber: exits non-zero if the target already exists.

```sh
sparkwright postmortem new \
  --id INC-042 \
  --severity P1 \
  --title "Login timeouts after cache failover" \
  [--commander "alice / SRE lead"] \
  [--date 2026-06-19] \
  [--out postmortems]
```

Required: `--id`, `--severity` (P0/P1/P2/P3), `--title`. Optional: `--commander`, `--date` (defaults to today UTC), `--out` (defaults to `postmortems/`).

## `sparkwright postmortem to-backlog`

Parses the `## 7. Action items` table in a completed postmortem and emits backlog Ready-row stubs to stdout. Skips the header row, separator, blank lines, and placeholder rows (`[action]` cells). The output is for **human review and paste** — it is not automatically committed or sent to a tracker.

```sh
sparkwright postmortem to-backlog postmortems/INC-042.md
```

Output format: one backlog Ready row per real action, with the incident ID, type (prevent / detect-faster / mitigate-faster), owner, and source file as columns. Copy the rows you want into `BACKLOG.md` or import them into your tracker (see `docs/work-tracking/adapters.md`).

**Known limitation:** a literal `|` inside an action cell is treated as a column separator and truncates the action text. Use "or", "and", or a similar alternative in action cells instead of `|`.

## Postmortem template

`templates/POSTMORTEM-TEMPLATE.md` provides the full blameless structure: summary, impact, timeline, root causes, contributing factors, what went well, action items (§ 7 — the section `to-backlog` reads), and blameless statement.

Required for **P0/P1**, recommended for P2. The standard is in `DEVELOPMENT-STANDARDS.md` §15; the process arc (incident → postmortem → backlog → loop) is in `DEVELOPMENT-PROCESS.md` §15.

## Honest ceiling

`sparkwright postmortem` scaffolds and parses the **mechanizable edges**:

- **Scaffolds** from human-supplied incident metadata (ID, severity, title, commander, date). It does **not** auto-detect incidents from logs, alerts, or monitoring — the kit's never-actuate principle.
- **Parses** the action-items table and emits stubs. It does **not** auto-create items in any tracker — the human reviews and actuates.

The judgment work — the analysis (timeline, root causes, contributing factors, blameless summary), ratification of each action item, and tracker actuation — is **human-owned**. The tool makes the mechanizable part fast and consistent; it does not replace the deliberate team process.

## Governance ties

- **`DEVELOPMENT-STANDARDS.md` §15** — the incident response arc (severity levels, postmortem requirement, action-item routing).
- **`CLAUDE.md` principle 6** — "the loop closes — production teaches the next iteration; learning routes back into an artifact."
- **`DEVELOPMENT-PROCESS.md` §6/§15** — where postmortem action items route: backlog items or recurring-maintenance tasks, with owner and due date.

## Slice context

This is **operate-loop Slice 1 of 2**. Slice 1 closes the incident → postmortem → backlog arc. **Slice 2** (planned — not yet shipped) will compose `dora.sh` + `agent-scorecard.sh` into a tier RECOMMENDATION that a human ratifies and applies; it does not auto-actuate an autonomy-tier change.
