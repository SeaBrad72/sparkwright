# Kit Threat Model (reference)

> This is Sparkwright's **OWN** threat model, published as a reference for teams evaluating the
> kit's security posture — **NOT a template**. Write your own from
> [`templates/THREAT-MODEL-TEMPLATE.md`](../../templates/THREAT-MODEL-TEMPLATE.md).

**System:** Sparkwright — an agentic SDLC kit. **Kit version:** v3.242.0 · **Date:** 2026-10-23

<!-- The phrase "Sparkwright — an agentic SDLC kit" on the line above is the K4 copy-denial
     fingerprint conformance/threat-obligation.sh checks for (OBL_KIT_FINGERPRINT_1) — do not
     reword it. -->

<!-- The bolded "Kit version" token on the line above is the SINGLE marker
     conformance/runbook-current.sh grades on this file: exactly one occurrence, byte-equal to `v` +
     VERSION. Do not write the bolded token anywhere else in this file, not even inside a comment or
     a code span — the count is textual. -->

## Drift ceiling, disclosed

This file is a **de-identified reference copy** of the kit's own dev-tree `THREAT-MODEL.md`. It is
ratcheted for **version currency only** — a release that bumps `VERSION` must also bump this file's
marker, and `conformance/runbook-current.sh` fails the build if it doesn't. It is **not** byte-synced
to the dev-tree original on every edit; content may lag between releases. Treat it as "the threat
model as of vX.Y.Z", not a live mirror. The dev-tree original is the kit's own governing record and
satisfies the kit's own `threat-obligation.sh` gate; this file does not (and is not meant to) do that
job for the kit itself, nor can it satisfy an *adopter's* threat-model obligation for their own
system — an adopter's threat model covers the application they build, not this kit.

> **Why this exists.** The kit ships an **autonomous agent control plane**: a pre-tool-use guard
> whose deny set governs shell, file, and network actions an agent can take; a promotion/ratification
> system that decides when a human must approve; and a conformance suite whose green is the signal
> adopters trust. A defect in any of those is a governance failure, not a bug. This model covers the
> **kit itself**, not the applications built with it — an adopter writes their own from
> `templates/THREAT-MODEL-TEMPLATE.md`.

## System & assets

| Asset | Why an attacker wants it | Where it lives |
|---|---|---|
| **The guard's deny set** | Disarming it gives an agent destructive shell, secret reads, and control-plane writes | `.claude/hooks/guard-core.sh` |
| **The change-class derivation** | Downgrading `control-plane`→`ordinary` removes the independent-ratifier requirement | The whole derivation chain — a CI listing built by the ratification workflow and the release CI, read by `conformance/promotion-readiness.sh` and `conformance/obligation-lib.sh`, and read by `conformance/agent-boundary.sh` |
| **The obligation gates** | Suppressing them lets sensitive/regulated changes ship with no threat model, UAT or a11y record | `conformance/*-obligation.sh`, `conformance/obligation-lib.sh` |
| **The conformance green** | A vacuous PASS is worse than a FAIL: it is false assurance an adopter acts on | all of `conformance/` |
| **The published mirror** | It is what adopters install; a poisoned publish reaches every downstream tree | `scripts/publish-public.sh` |
| **CI credentials** | The repo's workflow token, the release/publish path | `.github/workflows/*` |
| **The deny log** — one NDJSON line per guard refusal, local-only, never committed or exported to adopters | An observation, never a control; masked for common secret shapes but not a guarantee, so unrecognised shapes can survive and it can echo secret shapes the mask misses. Nothing in the kit gates on it | `<repo-root>/.kit-run/guard-denials.ndjson` |
| **A fine-grained, read-only forge token** used only to read branch protection / rulesets for the kit's own governance checks | Reconnaissance on which checks bind and where bypass paths remain; it cannot merge, push, or change protection. Exposure route: a same-repo PR can print it via the workflow that consumes it; closing shapes include an environment-scoped secret with a required reviewer, or a branch/org ruleset | a repo Actions secret, consumed only by the branch-protection-liveness workflow |
| **The agent's tracker credential** — the board token of a dedicated agent account. On macOS it is resolved at use time (no shell exports); on Linux it stays in the environment | Board writes as the agent. Any process running as the operator can read it silently while the keychain is unlocked, so this moves the exposure rather than removing it | The operator's login keychain (macOS) or the process environment (Linux) |
| **The CI tracker reader credential** — read access to the board for a pull-request check | Board reconnaissance, or board writes under a declared ceiling (see T12) | A forge Environment secret; whether it can write depends on the tracker plan |
| **The dev clone as an execution surface** — the place an agent's own code runs when the guard admits a kit script there | Agent-written code runs as the operator | An independent clone under a temp directory |

**Not assets:** the kit stores no customer data, no PII, no payment data. It holds no *production*
credentials, but it **does hold tracker credentials**: on the operator's machine an agent credential in
the OS keychain, and in CI a reader credential. Its value to an attacker is **leverage over downstream
repos and the board that governs them**, not data at rest.

## Trust boundaries

1. **Agent → repository.** The agent proposes; the guard is the enforcement boundary. Crossing it
   without a recorded GO is the central threat.
2. **Contributor → control plane.** `conformance/`, `.github/workflows/`, `skills/`, `agents/`,
   `.kit/` require ratification by a non-author.
3. **Kit → adopter.** The public mirror. Everything crossing it is inherited by trees we never see.
4. **CI → forge.** Workflow tokens, branch protection, the release tag.
5. **Untrusted text → verdict.** Board rows, records, commit messages and glob arguments all reach
   check output that a human or a status API reads.
6. **Agent session → OS secret store.** The operator's keychain is not the repository's, and any process running as the operator can ask it for every item whose access list admits the OS keychain CLI: the kit's token, other tools' tokens, possibly the operator's forge login. The kit's only
   controls here are a text guard in one harness and the resolver's own fixed read; no shipped layer
   enforces this boundary at the OS.
7. **Dev clone → real repository and operator machine.** Code written in a clone is agent-authored, and
   the guard admits a closed set of kit-script runs there, and an admitted run executes that code as the operator.

## Threats (STRIDE) — summary

The dev-tree original carries the full, currently-measured detail (per-mitigation fixture counts,
residual percentages, live incident narratives) for each row below; this reference states the
**threat class and posture**, not the day's exact figures.

| # | Threat | Vector | Mitigation posture | Residual |
|---|---|---|---|---|
| T1 | **Elevation** — agent disarms the guard, or reaches an admin-only forge endpoint without one | A global kill-switch env var; editing the guard's own source; REST endpoints that are the admin acts a CLI wraps (protection changes, ruleset changes, ref force-writes, collaborator grants, repo deletion/transfer) | Kill switch is documented as never-use; control-plane edits are routed to a dev-clone with the guard armed on the real repo; a deny arm derived from the endpoint's HTTP method + path, covering the porcelain CLI, its REST form, and known wrapper/indirection shapes measured against the base tree | **Disclosed, not closed.** An interpreter invocation (Python/Node making the same HTTP call) is the canonical bypass — the guard is a speed bump, not a boundary. The platform's own credential scoping and server-side branch/ruleset protection are the real control |
| T2 | **Tampering** — control-plane change ships without a ratifier | Rename a file out of the control-plane set so class derivation reads `ordinary` | Mitigated at every known derivation site (the CI listings, the classifier, the merge-side parity check), each individually fixture-proven, with a newline/rename-collapse guard on every listing | No class-wide lock observes a **sixth**, not-yet-existing derivation site — disclosed as the largest residual; a governed proposal to close it was built and withdrawn after being defeated three times by increasingly subtle shell-parsing evasions, and is boarded as future work rather than shipped half-working |
| T3 | **Repudiation** — what merged ≠ what was approved | Push after approval; merge a different tree | Stale-approval dismissal on push; a promotion-verify check asserts shipped tree equals approved tree, on both the branch and the release tag | Requires the operator to actually run the check — it is a step, not an automatic trigger |
| T4 | **Tampering** — a poisoned or rewritten mirror reaches every downstream tree | A new file ships by allow-by-omission; the mirror's default branch or history refs are force-pushed or deleted | The publish script runs a secret scanner plus a sensitivity scan, fail-closed, before every push; an export-ignore contract strips internal artifacts; the mirror's default branch and archival history refs carry forge-side immutability rulesets with zero bypass actors | New public surface is still allow-by-omission (tracked as future work); ruleset targeting the *symbolic* default branch rather than a literal ref name means a default-branch swap could, in principle, move immutability off the branch everyone merges to — disclosed and unmitigated at the forge layer |
| T5 | **Denial of service** — a check hangs or exhausts CI | Malformed argument to a gate | A value-less gate-defining flag that spun forever emitting large volumes of output was fixed to fail with a named error | Other unbounded loops are not systematically audited |
| T6 | **Spoofing** — author approves their own control-plane change | Self-approval | A non-author-ratifier check plus a `builder ≠ ratifier` rule; a "ratification seat" declared out-of-band identifies an approval, but on a small/solo team that seat can be the same human as the author | **Declared absent, not satisfied**, until a second human with repo write access exists. What actually blocks an unratified merge today is the forge's required-review count plus the owner's own judgment on each recorded approval — that judgment, not the check, is the control |
| T7 | **Tampering** — a gate passes by not running | A parser silently swallows input it cannot handle and reports vacuous green | A non-vacuity sweep mutates every check and requires the mutant to die; liveness anchors paired with load-bearing negative fixtures | At least one static-analysis gate is measured vacuously green over a class of files its parser cannot handle — parse completeness is not observable by any check yet |
| T8 | **Elevation** — an obligation gate is switched off by its caller | A decoy `--record` target, a universal exclude-glob, an internal test-mode stub pattern | Gate-defining arguments are fenced (first-assignment-wins, sentinel-protected); universal-glob refusal; exclusion-shape assertions | A process-environment test-mode flag on one engine still reopens its fixture path — narrow, requires control of the CI environment itself, not the diff |
| T10 | **Information disclosure / Elevation** — the agent's keychain tracker token is read and misused | An agent session, or code it wrote, reads the keychain item while the keychain is unlocked, then exfiltrates it or writes the board with it | The token leaves the session environment and typed exports; the resolver reads at use time with a fixed command, a host-bound lookup and a time bound, and each failure ends with a distinct message; the adapter suppresses shell tracing around every line that touches the credential; the account is meant to be a dedicated non-admin member (running as it is opt-in, see T12); the guard's read deny refuses a typed read of any such item, not only the kit's | **The exposure moves, it does not shrink**: the item's own access list admits the OS keychain CLI, so any process running as the operator (an agent shell, or a package install script in any project) can read it while the keychain is unlocked, and the same route reaches every other keychain item that admits it, including other tools' tokens and possibly the operator's forge token. Keychain dialogs are a consent surface: an operator who clicks "Always Allow" on a dialog an agent-run tool triggered widens access permanently, so deny any dialog you did not start yourself. True isolation (a broker, short-lived tokens) is future work. The locked-keychain behaviour was proven against a stub on CI; the real-keychain timing is an operator observation |
| T11 | **Information disclosure** — the guard's secret-store read deny is mistaken for a boundary | Any route the typed text does not show: a script the agent writes and then runs, an interpreter building the command at run time, a renamed or copied resolver, a session already holding the token in its environment, other secret stores | The guard refuses a command that names a secret-store tool unless the whole command is literal, then judges the literal command precisely (reads that print a secret, sourcing the resolver, tracing the adapter). The adapter's own read is allowed by construction | **A seatbelt, not a boundary, and only in the harness that runs the hook** (a different agent harness gets nothing from it). An interpreter or agent-written script still reaches the store. **No shipped kit layer sees that read, and whether an OS sandbox would is unmeasured**: the kit's strict sandbox profile restricts writes, and a keychain read is a service call rather than a file read. Some documentation wording over-claims this and is tracked as future work |
| T12 | **Elevation / Spoofing** — the board is written as an administrator, or by a reader that can write | Agent lanes run as an administrator's account; the CI reader holds write permission; an agent session changes the repository variables that declare the reader's ceiling | A preflight role refuses an admin or delete-capable agent credential; doctor names the identity a session runs as; the CI reader's record distinguishes a writer from an over-privileged reader, and only the out-of-band live check (scheduled weekly or run by hand) refuses an admin- or delete-capable reader; the per-pull-request job notices it in either posture and never refuses. **Two postures, both real for adopters.** (a) On a tracker plan whose permission scheme cannot be edited, no read-only reader exists, so the reader is a licensed writer **by declaration**, with a notice on each pull request; that puts a board-write secret in a `pull_request_target` job. (b) On a plan with an editable scheme, the reader holds browse access only and writes are held by a member role. **The kit's own repository has run posture (b) since 2026-10-11**; (a) remains the documented posture for a plan that cannot edit its scheme | **Either posture** only detects an over-privileged reader per pull request, with a notice; a reader secret swapped for an administrator's token still passes each PR until the next live check, a latency of up to a week. Setting the repository variables that declare the ceiling is a human act that no guard enforces, and an agent session holding the owner's forge login could set them, accepted until the agent has its own forge identity. Running as the agent account is opt-in |
| T13 | **Elevation / Information disclosure** — agent-written code in a dev clone reaches the keychain through an admitted kit-script run | The agent edits a script in its clone, then runs it where the guard admits a self-test, help or gate run | A closed set of admitted commands; every argument must resolve under the clone (only redirect targets may also resolve outside the protected root); the clone must be an independent clone under a temp directory; glob and brace bytes are declined | **An admitted run executes arbitrary agent-written code as the operator: it can reach the keychain, the forge credentials and pushes, and, under the default profile (the opt-in strict sandbox profile restricts writes to its listed control-plane paths; keychain reads are unmeasured, T11), can write the protected tree's control plane, because the guard's file-write denies see only typed text. That is an execution-path bypass of the guard's text denies.** Where the guard already admits interpreter runs elsewhere, this makes the reach available through a sanctioned verb rather than adding a capability no other route has. **The control prevents accidental credential use, not deliberate use.** The whole-command byte decline has a mutant of its own and is the only control on the script token; the per-argument byte test has none |
| T15 | **Information disclosure / Elevation** — the fetch helper reaches an internal service through a rebound name, or its errors map one | An allowlisted name the attacker controls resolves to a loopback, private-LAN or link-local address; the fetch helper fetches it, or its error text tells refused, timed-out, TLS-failed and failed-tunnel apart | The sandbox proxy refuses a name that resolves to loopback (measured 2026-10-25, loopback only); for every other address, https only, port 443 and curl's default certificate and hostname check, so an internal service cannot return content for the name (inferred); resolution, connection, timeout, TLS and failed-tunnel errors print one fixed line with curl's text withheld. **Adding `-k`/`--insecure` or any other option that disables or replaces certificate verification is a security regression**: the helper's self-test pins its whole curl argument list | Private-range rebinding through the proxy is unmeasured, so the TLS check alone carries it; the connection still reaches the internal host; timing still differs; output length is a channel (constant on the fixed-line path, varying on the pass-through and the refusal lines); a CA-store override in the environment (CURL_CA_BUNDLE, SSL_CERT_FILE) is not pinned by the self-test's argument-list check; an agent can run `curl -k` itself |

Rows T10-T13 and T15 are numbered to match the dev-tree original; the credential-exposure part of its T9 (a
pull-request-triggered job holding a tracker credential) is summarised in T12.

## Privacy (LINDDUN-lite)

The kit processes **no personal data** as a product. It stores contributor handles in commit
metadata and promotion notes — identities already public in the repo's own history. No DPIA is
required for the kit itself; an adopter's own privacy-review gate correctly derives N/A for a
project like this one.

**One caveat:** adopter trees may hold PII. The kit's obligation gates read **path names only**,
never file contents, so no adopter data crosses into kit-owned tooling.

## Agentic-AI lens — OWASP Agentic Top 10

| Risk | Posture |
|---|---|
| **Excessive agency** | The guard's deny set plus the recorded-GO requirement. Agents actuate mechanics; humans hold judgment. A runaway-guard check caps token/step/agent dimensions per slice (board row); steps are off by default. |
| **Prompt injection** | Board rows, records and glob arguments are attacker-influenceable text reaching check output. An injection battery (shell substitution, backticks, format strings, raw ANSI) is measured to produce zero command execution and zero caller bytes reaching a verdict. |
| **Tool misuse** | Gate-defining arguments are fenced (see T8). Fixture flags are test-mode gated, except via the process environment (disclosed above). |
| **Identity & impersonation** | `author ≠ approver` is enforced by a non-author check; `builder ≠ reviewer ≠ ratifier` holds by design, and agent ≠ ratifier binds only once agent sessions run as a non-admin identity (T6). Tracker identity (T10, T12): lanes are meant to run as a dedicated non-admin agent account with its token in the OS keychain, plus a separate CI reader; that is opt-in, and the repository variables declaring the reader's ceiling are a human act no guard enforces. |
| **Unsafe output handling** | Check verdicts strip control bytes before rendering attacker-influenceable text (filenames, board rows) — closing a forgery vector where a crafted filename could repaint a terminal to hide the true verdict line. |
| **Memory / context poisoning** | Agent memory is advisory; every load-bearing claim is re-measured rather than trusted from a prior session. |

## Residual risk — accepted, tracked, and disclosed

1. **No class-wide lock guards the change-set derivation.** Every known site is individually
   fixture-proven; nothing detects a *new* site appearing. A general-purpose scanner for this was
   built and withdrawn after being defeated three times in review — each fix opened roughly as many
   holes as it closed — so it is tracked as future work rather than shipped half-working.
2. **A static-analysis gate is vacuously green over a class of files its parser cannot handle.**
   Parse completeness itself is not yet observable by any check.
3. **A process-environment test-mode flag** on one obligation engine still reopens its internal
   fixture path; requires control of the CI environment, not the diff under review.
4. **Guard bypass via interpreter invocation is architectural**, and disclosed rather than hidden:
   the guard is a speed bump; the platform (credential scoping, server-side branch/ruleset
   protection) is the real boundary.
5. **Obligation gates are path heuristics.** A file holding sensitive data with no telltale name or
   path derives "not applicable" rather than being caught.
6. **Solo/small-team ratification** — where a project has one maintainer, the "non-author ratifier"
   seat can be filled by the same human under a declared, narrow exception. This is stated plainly
   rather than implied to be two-person review, and it retires automatically once a second human
   with write access exists.
7. **The agent's keychain token is readable by any process running as the operator while the keychain is unlocked.** The
   control is a text guard in one harness plus a least-privilege account. Whether any OS sandbox blocks
   such a read is unmeasured; isolation is future work.
8. **A declared reader ceiling** (on a plan whose permission scheme cannot be edited): a board-write secret
   in a pull-request-triggered job, detected with a notice, not refused; the declaring variables are a
   human act no guard enforces. It retires on a plan with an editable scheme.
9. **Agent-written code in a dev clone** can reach the keychain through an admitted kit-script run; the
   control prevents accidental, not deliberate, use.
10. **The secret scan covers a pull request's own commits, not every branch, on each run.** A secret pushed
    to a branch with no open pull request is caught only by the weekly all-refs sweep, up to 7 days after
    the push; rotate on detection, not on the sweep.

**Explicitly not accepted:** a vacuous green. Where a check cannot prove its claim, it says so in its
own header rather than passing quietly.

## Sign-off

**Threat model reviewed by:** an independent security-reviewer lens (`builder ≠ reviewer`), same
discipline the kit requires of its own control-plane changes.
**Basis:** derived from the kit's own dev-tree `THREAT-MODEL.md`, itself re-reviewed each time the
control plane changes shape (a new guard matcher, a new gate class, a change to the promotion
contract) or the version ratchet reds.
