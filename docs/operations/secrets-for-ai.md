# Secrets for AI Features — Adopter Playbook

AI features are usually the **first** thing in a project that needs a real
third-party credential — a model API key — live in the dev loop. So the
secret-handling friction below is intrinsic to the first AI slice, not
incidental. This is the inner-loop playbook; the shared/staging/prod/regulated
story is [`secrets-at-scale.md`](../enterprise/secrets-at-scale.md).

## The playbook

- **Set CI secrets from a file, never hand-paste.** Hand-pasting a key into a
  secret field drags trailing whitespace/newlines that surface later as a 401
  that looks like a product bug. Pipe from a file instead:

  ```sh
  printf '%s' "$KEY" > key.txt          # or write it however you obtained it
  gh secret set OPENAI_API_KEY < key.txt
  rm key.txt                            # delete the local copy after
  ```

- **Don't rotate the key mid-loop.** Rotating the provider key without updating
  the stored secret (CI *and* local) breaks the eval/CI in a way indistinguishable
  from a code regression — you will chase a "bug" that is a stale credential.
  Rotate at a quiescent point and update both ends together.

- **Don't select the key in-editor.** An IDE that auto-attaches or auto-selects
  `.env` can pull the secret into the agent's context through a channel the guard
  may never see — an editor attachment is not a `Read`-tool call. The guard denies
  the agent's *own* reads of secret material (`cat .env`, the `Read` tool), but it
  is a speed bump, not containment (see [`runtime-guards.md`](runtime-guards.md)).
  Keep the key out of editor selections and context attachments regardless.

- **`.env` is the local floor only.** Anything beyond local dev — shared,
  staging, production, or regulated data — belongs in a managed store. See
  [`secrets-at-scale.md`](../enterprise/secrets-at-scale.md).

## Running the live eval is a human/CI step

For an AI feature, the eval is the test suite (`DEVELOPMENT-STANDARDS.md`
[§AI Evaluations](../../DEVELOPMENT-STANDARDS.md#ai-evaluations-eval-driven-development)).
By policy, running the eval against the **real provider** is a human or CI step,
not an agent step — and the guard's secret-read deny backs this up by blocking the
agent from reading a live key *file* (`.env`, key files) into context. This is a
**speed bump, not a hard boundary**: if the key is already exported as an env var,
or reached via the interpreter channel, the agent is not mechanically stopped — so
the human/CI handoff is the actual control, with the guard removing the easy
mistakes (see [`runtime-guards.md`](runtime-guards.md)). The split:

- The **agent** authors the eval set, the dataset, the rubric, and the harness,
  and wires the §7 Eval gate into CI.
- A **human or CI** runs the suite with the real key and reports the score back.

So "see the eval pass before wiring CI" reads as a handoff: the agent builds and
wires; a human/CI executes the live run. Plan the eval with
[`EVAL-PLAN-TEMPLATE.md`](../../templates/EVAL-PLAN-TEMPLATE.md); readiness is
[`eval-readiness.md`](../../conformance/eval-readiness.md).

## See also

- [`secrets-at-scale.md`](../enterprise/secrets-at-scale.md) — managed stores, OIDC, rotation
- [`eval-readiness.md`](../../conformance/eval-readiness.md) — the eval readiness checklist
- [`runtime-guards.md`](runtime-guards.md) — what the guard denies and why
- `DEVELOPMENT-STANDARDS.md` §Secrets management + §AI Evaluations
