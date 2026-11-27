> **DRAFT: inferred from the repository by an agent. Not ratified. A person reviews it and moves what is right into place.**

# Inception draft: <CHARTER | ADR-000-stack | RUNBOOK | BACKLOG-GAPS | GUARD-PROPOSALS | PROJECT-CLAUDE>

Every draft under `docs/inception-draft/` starts with the banner line above, exactly as written, and then this legend. The skill is `skills/inception-from-code/SKILL.md`. The banner and the tags belong to the draft. When a person moves a fact into a ratified file, they edit what is wrong, drop the banner and the tags they do not want, and delete the draft. `conformance/inception-done.sh` fails while `docs/inception-draft/` exists or one of the four ratified files still carries a banner line.

The one greenfield draft, `PROJECT-CLAUDE`, is written from the owner's words in session, not from a repository, so it starts with this second banner line instead of the first, exactly as written:

> **DRAFT: written by an agent from the owner's words in session. Not ratified. A person reviews it and moves what is right into place.**

## Tag legend

Each stated fact carries exactly one tag.

| Tag | Meaning | What sits beside it |
|---|---|---|
| `[verified]` | The agent ran a read-only command from outside the repository and saw the result. | The command, written out. |
| `[read]` | Quoted or paraphrased from a file in the repository. | The `path:line`. |
| `[inferred]` | Concluded from one or more `[read]` facts. | The `[read]` facts it rests on, named. |
| `[asserted]` | The agent's judgment, with no source. Kept only where a template field needs a value and none can be read. | Nothing. These are the facts most worth checking. |
| `[owner-stated]` | The owner said it in this session. Used only in the `PROJECT-CLAUDE` draft. | The date said, written beside it. |

A field with no supporting fact stays unfilled: the ratified template's own placeholder stays in place.

## Headings to keep

Start each draft from its ratified template's headings, and keep them. decision-integrity reds a missing `## Fit rationale` or `#### Deploy-target fit rationale`:

- `ADR-000-stack.md`: `## Fit rationale`
- `RUNBOOK.md`: `#### Deploy-target fit rationale`
- `CHARTER.md`: `## 1. Overview`, and the fields it becomes (`inception-done` checks it in strict mode, and only WARNs until SWAS-1019)

## Example

- Runtime: Node 22 `[read]` `<file>:<line>`
- Runtime version flag answers 22 `[verified]` by `<version command>`, run with the working directory outside the repository
- Deploys on merge to main `[inferred]` from the two `[read]` facts it names (`<file>:<line>` each)
- Owner of the on-call rota: `[asserted]`
- Autonomy tiers: review everything `[owner-stated]` 2026-11-19
