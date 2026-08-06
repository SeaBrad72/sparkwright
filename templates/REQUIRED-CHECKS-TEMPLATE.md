# Required Status Checks — [Project Name]

> **Template.** The single source of truth for which GitHub status-check **contexts** must be bound
> in this repo's branch protection. `conformance/branch-protection.sh --declared-only` parses this
> file offline (no `gh`, no network); its live leg compares these names against the real
> `required_status_checks.contexts` when a maintainer runs it with admin-authenticated `gh`.
> `scripts/branch-protection-apply.sh` reads this file and POSTs any missing context. Ceiling:
> proves the DECLARATION is well-formed and, on the live leg, that it matches the forge — it does
> not prevent an admin from removing a bound context (real prevention is org rulesets / Terraform's
> `github_branch_protection`; see `scripts/branch-protection-apply.sh` and that resource).

One context per line, inside the single fenced block below. A `#`-prefixed line is a comment or a
conditional you have not turned on yet, and is ignored. Duplicate lines are a declaration error.
Replace `<your-check-name>` with the real status-check context name(s) your CI posts (the job/step
name GitHub records for this repo) — leaving the placeholder in place with no other lines is the
pristine, not-yet-configured state; leaving it in place **alongside** real entries is an error.

**Charset (v1, fail-closed):** each context name must match `^[A-Za-z0-9][A-Za-z0-9._/-]*$` and be
100 characters or fewer. **GitHub context names containing spaces are NOT declarable in v1** — a
line like `build and test` FAILs naming that exact line rather than silently splitting it into three
phantom contexts (a measured failure mode: `--apply` then bound three contexts that could never go
green, making `main` unmergeable). If your CI job/step name has a space in it, rename the job/step to
a hyphenated form (e.g. `build-and-test`) before declaring it here. Quotes, JSON punctuation, glob
characters (`*`, `?`, `[`), a leading `-`, and control characters are rejected the same way, each
FAILing by naming the offending line.

```
<your-check-name>
```
