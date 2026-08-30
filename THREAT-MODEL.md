# Threat Model

**System:** Sparkwright — an agentic SDLC kit. **Kit version:** v3.220.0 · **Date:** 2026-08-30
**Owner:** Bradley James · **Data classification:** Internal (the kit holds no customer data)

<!-- The bolded "Kit version" token on the line above is the SINGLE marker
     conformance/runbook-current.sh grades: exactly one occurrence in this file, byte-equal to `v` +
     VERSION. It replaced a header stamp of 3.185.0 and a *different* footer stamp of 3.186.0 that
     coexisted here against VERSION 3.218.0. Do not write the bolded token anywhere else in this
     file, not even inside a comment or a code span — the count is textual, and this note is the
     mistake it is warning about (the first draft of it made the count 3). -->

> **Why this exists.** The kit ships an **autonomous agent control plane**: a pre-tool-use guard whose
> deny set is the lines carrying the `13:` prefix in `.claude/hooks/guard-core.sh` (count them:
> `grep -c "'13:" .claude/hooks/guard-core.sh` — the number is derived, never restated here). This
> document previously hardcoded "45 deny rules"; when that was checked it was wrong, and the *first*
> replacement derivation offered here was wrong too — `grep -c "printf '%s' '13:"` counts only the
> `printf '%s'` spelling and silently misses the two dozen sites using `printf '13: …'` directly. Two
> wrong numbers in a row is the argument for deriving rather than restating, not against it. Also a
> promotion/ratification system that decides when a human must approve, and a
> conformance suite whose green is the signal adopters trust. A defect in any of those is a governance
> failure, not a bug. This model covers the **kit itself**, not the applications built with it — an
> adopter writes their own from `templates/THREAT-MODEL-TEMPLATE.md`.

## System & assets

| Asset | Why an attacker wants it | Where it lives |
|---|---|---|
| **The guard's deny set** | Disarming it gives an agent destructive shell, secret reads, and control-plane writes | `.claude/hooks/guard-core.sh` |
| **The change-class derivation** | Downgrading `control-plane`→`ordinary` removes the independent-ratifier requirement | **The whole derivation chain, not one script.** The *listing* is built by `.github/workflows/ratification.yml`, `profiles/ratification.yml` (adopter-facing) and `.github/workflows/ci.yml`; it is *classified* by `conformance/promotion-readiness.sh` and `conformance/obligation-lib.sh`, and *consumed* by `conformance/agent-boundary.sh`. Naming only the classifier is what let T2 hide: the classifier was hardened while three listing-builders still collapsed renames. **No class-wide lock guards this chain** — one was built and withdrawn (boarded `CHANGESET-DERIVATION-LOCK`); the only automated guards are `ratification-parity.sh`'s two anchors on the emitted profiles |
| **The obligation gates** | Suppressing them lets sensitive/regulated changes ship with no threat model, UAT or a11y record | `conformance/*-obligation.sh`, `conformance/obligation-lib.sh` |
| **The conformance green** | A vacuous PASS is worse than a FAIL: it is false assurance an adopter acts on | all of `conformance/` |
| **The published mirror** | It is what adopters install; a poisoned publish reaches every downstream tree | `scripts/publish-public.sh` |
| **CI credentials** | `GITHUB_TOKEN`, the release/publish path | `.github/workflows/*` |
| **The deny log** (added 2026-08-29, `GUARD-DENY-LOG`) — **an OBSERVATION, never a control.** One NDJSON line per guard refusal: `ts · surface · tool · arm · trigger · segment · read_shaped · session`. It exists so "are the read lanes getting better" is a measured number instead of a chat tally | **It can hold secret material, and the first cut of this row overclaimed otherwise.** `segment` is **the offending segment, ≤160 bytes, redacted for common secret shapes — NOT a guarantee that no secret can appear; the offending segment of a one-segment command IS the command** (measured: `TOKEN=… sed -i …`, `curl -H 'Authorization: Bearer …'`, `psql postgres://user:pw@…`). Masked: leading `NAME=VALUE`, `Authorization:`/`Bearer`/`Basic`, `token=`, `api_key=`, `password=`, `secret=`, URL userinfo. Unrecognised shapes survive. The other abuse is the reverse direction: an agent **forging or truncating** the file to make its own denials vanish from a harvest | `<repo-root>/.kit-run/guard-denials.ndjson` — **local**, already `.gitignore`d, never committed, never exported to adopters, never pushed. **Append-only and unbounded (no rotation)**; delete it to reset a window. `KIT_GUARD_LOG=0` disables it, so **any count is a FLOOR, not a census** — sanctioned off-switch uses are the selftest battery and a deliberate operator opt-out. ⚠️ **It is agent-writable and unauthenticated, and NOTHING IN THE KIT GATES ON IT** — that is the point: it is evidence for a human reading a harvest, and neither a forged line nor a write pathology may change a verdict. Enforced three ways: the decision is emitted BEFORE the log is touched (a planted FIFO used to hang the hook — T5 in this table, reached from one *allowed* `mkfifo`); the logger refuses a symlink, a **hardlink** (link count > 1 — a hardlink is a regular non-symlink file and passed the first two tests) or any non-regular node at the path, each of which was an append primitive onto any writable file; and every write failure is swallowed. Created `0600`. Masked shapes are enumerated in `docs/operations/runtime-guards.md` |
| **`KIT_PROTECTION_READ`** (added 2026-08-28, `REQUIRED-CONTEXT-SET-LOCK`) — a fine-grained PAT, this repo only, `Administration: read`, 90-day expiry; the first non-`GITHUB_TOKEN` credential in this CI | Reconnaissance: it reads branch protection, rulesets and bypass actors — the map of which contexts bind and where `enforce_admins:false` leaves the `--admin` path. It cannot merge, push or change protection. **Exposure route, accepted and disclosed:** `on: pull_request` runs the PR head's copy of `branch-protection-live.yml` and `conformance/branch-protection.sh` with the secret in env, so any push-capable actor — a collaborator, or an agent with the branch push the kit grants — can print it in a same-repo PR. Closing shapes: an Environment-scoped secret with a required reviewer (gates every PR on a human), or a `main` ruleset (design approach C). Rotation and the fail-closed expiry behaviour: `RUNBOOK.md` §5 | repo Actions secret; consumed only by `.github/workflows/branch-protection-live.yml` |

**Not assets:** the kit stores no customer data, no PII, no payment data, and holds no production
credentials. Its value to an attacker is **leverage over downstream repos**, not data at rest.

## Trust boundaries

1. **Agent → repository.** The agent proposes; the guard is the enforcement boundary. Crossing it
   without a recorded GO is the central threat.
2. **Contributor → control plane.** `conformance/`, `.github/workflows/`, `skills/`, `agents/`,
   `.kit/` require §13 ratification by a non-author.
3. **Kit → adopter.** The public mirror. Everything crossing it is inherited by trees we never see.
4. **CI → forge.** Workflow tokens, branch protection, the release tag.
5. **Untrusted text → verdict.** Board rows, records, commit messages and glob arguments all reach
   check output that a human or a status API reads.

## Threats (STRIDE) + mitigations

| # | Threat | Vector | Mitigation | Residual |
|---|---|---|---|---|
| T1 | **Elevation** — agent disarms the guard, or reaches an admin-only forge endpoint without one | `KIT_GUARD_SELFEDIT=1`, or editing `guard-core.sh`; **and (added 2026-08-25) the REST endpoints that ARE those acts**: `PUT …/pulls/:n/merge` (the REST form of `gh pr merge --admin`) · **any mutating method on the whole `…/branches/*/protection` subtree**, including `DELETE …/protection/required_status_checks`, which drops every required context at once · repo and org `…/rulesets` · `…/git/refs` (a `PATCH` with `force=true` is a force-push over the API) · `…/collaborators/*` (a `PUT` mints an admin) · and the repo root under `DELETE` **or `PATCH`** (a `default_branch` swap moves protection off the branch everything merges to) | Global kill switch is documented as never-use; control-plane edits routed to a dev-clone with the guard armed on the real repo; `agent-autonomy.sh` fixtures per mutation form (Write/Edit, `>` redirect, `sed -i`). **The REST forms are denied by the S6R disjunct (`_s6_gh_api_admin`) on the existing S6 arm** — a load-bearing DENY cell per endpoint shape and per spelling variant in `conformance/agent-autonomy.sh` and `conformance/promotion-actuate-wired.sh` (count them there rather than here), with positive cells pinning the read/poster traffic, the owner's A3 read-back pipelines, and `branch-protection-apply.sh`'s additive contexts POST | An interpreter invocation is the canonical bypass — **disclosed, not closed**; the platform, not the guard, is the real boundary. **"Denied" here means DENIED WHEN WRITTEN PLAINLY**, and the gap between that and "denied" is the honest residual: (i) **indirection** — `$VAR`, `$(cat f)`, `xargs`, a `gh alias` that expands to the call: the bytes scanned are not the bytes that run; (ii) **quoted wrappers — NARROWED 2026-08-26 by `GUARD-READ-LANE-2`'s rider.** A **same-command** wrapper now **DENIES**: `sh -c 'gh pr merge 5 --admin'`, `bash -lc '…'`, `xargs -0 sh -c '…'`, an intra-command line continuation (`gh \`⏎`pr merge 5 --admin`), and a `$VAR` form whose bytes are present in the same command (`CMD='gh pr merge 5 --admin'; sh -c "$CMD"`) — because the porcelain arm is applied to a quote- and continuation-normalised view with a case-folded lead, not because any wrapper was enumerated. All of these were **ALLOW on the base tree**, measured, and each is a load-bearing DENY cell (`R …`, `T2R2 …`). The **cross-command** wrapper is unchanged and folds into (i): an exported `$VAR`, `$(cat f)`, or a `gh alias` set in an earlier call carries bytes the guard never holds. Also closed in the same slice: `gh -R o/r pr merge 5 --admin` was **ALLOW since the arm was written** — `gh` hoists `-R/--repo`, so an adjacency test for `gh pr merge` missed it; the arm now tests token **ORDER**. **S6R happened to survive the wrapper class all along** — measured, pinned by a cell, luck rather than design, and still not to be generalised (`GUARD-QUOTED-WRAPPER-BLINDS-COMMAND-ARMS`, the rider row, closed here for the same-command half); (iii) **percent-encoded path segments** are not decoded — `…/pulls/5/%6Derge` is ALLOW, measured (boarded on `GUARD-REST-ADMIN-CURL-SIBLING`); (iv) every path test is a **substring match, not an argv parse** (boarded `GUARD-S6R-POSITIONAL-PATH-EXTRACT`); (v) **laundering a control-plane write through a downstream interpreter — CLOSED for the control-plane arms, 2026-08-26.** Three shapes were **ALLOW at `4b3debc3`**, measured: `echo "cp e .claude/hooks/guard-core.sh" \| sh` (a read verb's arguments are *data*), `cat <<'EOF' \| sh` and `sh <<'EOF'` (a quoted heredoc body is inert *data* under #567's Arm E) — three routes to a write on the guard's own source. Two more holes of the same family were found while closing it: (1) a **pre-existing** one, live on `main` — a bare control-plane **directory** name piped into a shell (`ls conformance \| sh`, a literal-token hit rather than a pathhit); and (2) **brace expansion synthesising a flag** after the guard had judged one inert token (`sed -n 1p {-i,.claude/hooks/guard-core.sh}` — an in-place edit of the guard spelled as a read; `awk … {-v,<cp>}` likewise), whose provenance is narrower than "was ALLOW on `main`": that spelling was **latent** on `main` (masked by the blanket `sed` deny) and was made **reachable by T6's refund in this branch**, then caught and closed in the same branch by T7. The class *was* live on `main` via the already-refunded `grep` lane (`grep x {-r,<cp>}`, harmless). All are now DENY: a segment led by an interpreter and **fed by a pipe** forces every upstream segment to be scanned **raw**, and an operand carrying `{ } ,` or a leading glob byte is never treated as a path. **Residuals, disclosed:** an unrecognised interpreter binary name (`busybox sh`, `./sh`, a renamed shell) is outside the list — the lexicon ceiling, unchanged; a heredoc whose consumer is off the content-consumer list **over-denies** (the fail-safe direction; boarded `GUARD-HEREDOC-CONSUMER-LIST` so admission is a census, not a drip); and a pre-planted file named `-delete` reached by an unquoted `*` operand is unseeable — the guard does not read the filesystem. **S6R is also a speed bump on ONE client:** `curl`, `wget`, `python -c "requests…"` and `node -e` reach the identical endpoints, as do the `gh` porcelain verbs `gh repo delete` / `gh ruleset delete` / `gh repo edit --default-branch` (boarded `GUARD-REST-ADMIN-CURL-SIBLING`, `GUARD-GH-VERB-ADMIN-SIBLINGS`). **`--hostname` (GHES) is NOT a gap — it denies**, because the host is normalized away and the path is what is matched; a fixture cell pins that. Until 2026-08-25 the REST form was **rc=0** — measured — and the #567 unstick (2026-08-19) used it on a recorded GO (`D-240825-1` (3)) |
| T2 | **Tampering** — control-plane change ships without a ratifier | Rename a file out of the control-plane set so `--class` derives `ordinary` | **UPDATE 2026-08-25 — the ENUMERATION half of this row is CLOSED for the `.claude/*` family.** `GUARD-PATH-ENUMERATION-INCOMPLETE` S1–S3 shipped and merged ([#556](https://github.com/SeaBrad72/sparkwright-dev/pull/556) guard-side membership by derivation · [#558](https://github.com/SeaBrad72/sparkwright-dev/pull/558) union-aware merge-side `--class` parity · [#559](https://github.com/SeaBrad72/sparkwright-dev/pull/559) the reclassification ratchet), moving the measured-ALLOW set to **0** at the guard, at `--class`, and at the union, with a never-enumerated file caught at zero matcher edits. Read the epic-closure row on the board, not this paragraph, for the metric. **STILL OPEN, and it is an enumeration remnant, not a derivation one:** the `scripts/` and `profiles/` pathhit legs are left-anchored while the incumbent `skills/`/`conformance/`/`adapters/` legs are unanchored substrings — anchoring them is a deny *relaxation* needing its own fixtures and a monotonicity run, boarded as `GUARD-S1-HARDENING-RESIDUALS` (c). **MITIGATED at all FIVE derivation sites.** The first analysis named only the classifier and was wrong about where the threat lived: `promotion-readiness.sh` is *advisory*, while the **required** `control-plane-ratification` gate reads a PR-files-API listing that collapses a rename to its destination (the source survives only in `previous_filename`, which nothing read). Fixed: the three API listings project `previous_filename`; the two git derivations pass `--no-renames`; `ratification-parity.sh` anchors the `previous_filename` projection so no emitted profile regresses (load-bearing negative present). **No class-wide lock ships with this release** — one was built and withdrawn: a text scanner over shell source was defeated three times across three review rounds (a same-line decoy, a continuation decoy, a trailing-backslash line never scanned, then a comment-continuation that blinded it entirely, flag reordering that hid `git diff -M --name-only`, and a pipe that is not a segment boundary), and each repair introduced roughly as many holes as it closed. Boarded as `CHANGESET-DERIVATION-LOCK` with that evasion catalogue as required design input. **So the five sites are fixed and individually mutation-proven, but nothing observes the CLASS: a sixth collapsing derivation would be unobserved.** The API listings additionally carry a **newline guard**, because `jq -r` emits a raw newline and a crafted filename otherwise split one API entry into two lines that each classified separately — measured to defeat the suffix-constrained `agents/*.agent.md` pattern and post the required gate GREEN. All monotone — a rename can only *add* the source path. Mutation-proven, including under a hostile host `diff.renames=false` | **Residual, and real.** (a) **CLOSED this release, and the earlier wording here was wrong.** A newline in a filename splits the path so each fragment is classified alone; this document previously claimed "control-plane is fail-safe" from that, which is **false** — `is_control_plane_path` includes SUFFIX-constrained patterns (`agents/*.agent.md`), so `agents/x⏎.agent.md` splits into `agents/x` + `.agent.md` and **neither** matches (measured; a control-plane→ordinary downgrade). POSIX `sh` cannot *preserve* such a path, but it can *detect* one: the `-z` stream carries a newline byte only when a filename does, so both producers now treat that as a **derive failure** and fail-safe. Mutation-proven. (b) **No class lock ships.** The five sites are fixed and each is individually mutation-proven, but nothing detects a **sixth** collapsing derivation — a new workflow listing, or a new producer, would be unobserved until someone noticed. This is the largest residual in this row and it is deliberate: the withdrawn scanner is boarded as `CHANGESET-DERIVATION-LOCK`, because shipping a check whose own claim register was demonstrably false is worse than shipping none. (c) The GO record's `--class` is self-asserted and never cross-checked against the derivation (boarded, `PROMOTION-GO-CLASS-CROSSCHECK`). (d) `enforce_admins: false` — see residual #6. (e) **The Files API returns at most 3000 files.** `--paginate` then simply stops — a *success*, not an error — so neither `set -e` nor the empty-listing escalation fires, and a control-plane path past the cap is invisible to the required gate. Not introduced or worsened by this release (the cap counts entries, not lines); reachable in a monorepo adopter and paddable deliberately. **Unguarded — disclosed, not closed.** |
| T3 | **Repudiation** — what merged ≠ what was approved | Push after approval; merge a different tree | `dismiss_stale` on push; `promotion-verify check` asserts `shipped == approved` by **tree equality** on both main and the tag | Requires the operator to actually run `check` — it is a step, not a trigger |
| T4 | **Information disclosure / tampering** — a poisoned or rewritten mirror reaches every downstream tree | A new file ships by allow-by-omission; **or the mirror's `main` (and the two `history/*` archive refs) is force-pushed or deleted, because none of them is protected** | `publish-public.sh` runs gitleaks + a sensitivity scan **fail-closed** before push; `.gitattributes export-ignore` strips internal artifacts. `scripts/branch-protection-apply.sh` already takes `--repo=`/`--branch=`, so the mirror and both history refs are *reachable* by it; `RUNBOOK.md` §5 now carries the show-only and `--apply` invocations and the API read-back | New-public-surface is still **allow-by-omission** (boarded, `PUB-POLICY`). **Two DIFFERENT states, and round 1 of this slice wrongly merged them into one sentence.** (1) **Mirror `main` (`SeaBrad72/sparkwright`): as of this PR: mirror `main` unprotected (API 404); owner keystroke A3 pending.** Show-only proves the gap; only the owner's `--apply` at a TTY closes it. (2) **The two history refs are on `sparkwright-dev`, NOT on the mirror — they do not exist there — and they are NOT unprotected.** Repository ruleset `history-refs-immutable` (forge id 21114562) is **active** over `refs/heads/history/**` with rules `deletion` + `non_fast_forward` and **`bypass_actors: []`** (`D-240822-1` (1)), which makes them **tamper-PROOF for those two vectors**, not merely tamper-evident. The residual there is narrow and named: **an admin disabling or deleting the ruleset** — and the agent's route to that act (`PATCH`/`DELETE` on `…/rulesets/N`) is exactly what S6R now denies, leaving it an owner keystroke that GitHub logs |
| T5 | **DoS** — a check hangs or exhausts CI | Malformed argument to a gate | Fixed this release: a value-less gate-defining flag spun forever emitting ~7 MB/s (44 MB in 6 CPU-s). Now a named FAIL | Other unbounded loops not systematically audited |
| T6 | **Spoofing** — author approves their own control-plane change | Self-approval | `author-not-approver-wired.sh` + §13 requires a non-author ratifier; `builder ≠ ratifier`. **Reclassified 2026-08-25 (`D-240825-1` (2)):** on this repo the second identity `ISBrad72` is *the maintainer's ratification seat*, declared in `.kit/ratification-seats.conf`. It enforces `agent ≠ ratifier` — the agent cannot mint that approval, which is friction-test-real — and it does **not** provide two-person review. `scripts/sod-check.sh --seat-approvals` DETECTS a seat approval **by login** and the workflow emits the disclosure itself as a `::notice` (the typed *seat sentence* was retired 2026-08-28 — it graded the approver's typing, not the change). **What blocks an unratified control-plane merge is the branch-protection review requirement** (`required_approving_review_count: 1`, server-side); since 2026-08-28 the ratification check is **green with a notice while waiting** and reds only when an approval is present that still does not ratify, or when the gate cannot evaluate (`RATIFICATION-WAITING-IS-GREEN`; it was red-while-waiting for one day under `REQUIRED-CHECK-POSTED-VIA-API-NOT-MATCHED`, and a faked yellow before that) | **The seat is the same human as the author, and this document now says so instead of implying otherwise.** Two-person review is **declared absent**, not satisfied; `separation-of-duties.md`, `review-lane.md`, `MATURITY.md` and `CODEOWNERS` all name it. Seat detection proves an *identity*, never that a human read the diff. ⚠️ **Residual, disclosed:** the green-while-waiting rendering depends on that review requirement staying ≥ 1 — dropping it to 0 would leave an unratified control-plane PR green and unblocked (`conformance/branch-protection.sh` is what holds it). Retires at D2 (a second human with write access), when `enforce_admins` flips too |
| T7 | **Tampering** — a gate passes by not running | Vacuous green | Non-vacuity sweep mutates every check and requires the mutant to die; liveness anchors paired with load-bearing negatives | **`artifact-gate` is vacuously green over ~61 files** — semgrep cannot parse a one-line `case` and swallows to EOF. Boarded `SAST-PARSE-COMPLETENESS`. **Parse completeness is observable by no gate.** |
| T8 | **Elevation** — an obligation gate is switched off by its caller | `--record DECOY.md`, `--exclude-globs '*'`, `--stub-pattern` | Closed this release: `--` sentinel + first-assignment-wins fence five gate-defining arguments; universal-glob refusal; exclusion shape assertion | `KIT_OBL_TEST=1` in the **environment** still reopens the engine's fixture flags (boarded `OBLIGATION-TESTMODE-ENV-FLAG`). `ceremony-binding`'s own env-borne flag (`KIT_CB_TEST` enabling `--changed`) is **removed** — the gate implements no fixture flag, and argv `--changed` is refused rc 2 (slice A4) |

## Privacy (LINDDUN-lite)

The kit processes **no personal data**. It stores contributor handles in commit metadata and
promotion notes (`refs/notes/promotions`) — GitHub identities already public in the repo history.
No DPIA required; `readiness.sh privacy-ready` correctly derives N/A for this project.

**One caveat:** adopter trees may hold PII. The kit's obligation gates read **path names only**, never
file contents, so no adopter data crosses into kit-owned tooling.

## Agentic-AI lens — OWASP Agentic Top 10

| Risk | Posture |
|---|---|
| **Excessive agency** | The guard's deny set plus the recorded-GO requirement. Agents actuate mechanics; humans hold judgment. `runaway-guard.sh` caps token/step/agent dimensions. |
| **Prompt injection** | Board rows, records and glob arguments are attacker-influenceable text reaching check output. Verified this release: injection battery (`$(id)`, backticks, format strings, raw ANSI) produced **zero** command execution and zero caller bytes in any verdict. |
| **Tool misuse** | Gate-defining arguments are fenced (T8). Fixture flags are test-mode gated — **except via the environment** (open). |
| **Identity & impersonation** | `builder ≠ reviewer ≠ ratifier`, enforced by §13 and the non-author check. |
| **Unsafe output handling** | Check verdicts strip control bytes before rendering template-controlled text (the ANSI-repaint fix in `a11y-obligation.sh`). **Extended this release to `promotion-readiness.sh`'s surfacing**, where it was a *forgery* vector, not merely cosmetic: v3.184.0's `PROMOTION-PATH-QUOTING` replaced git's `core.quotePath=true` (which **escaped** control bytes) with `-z` + `quotePath=false` (**raw** passthrough), and PR authors name files. Measured: a filename carrying `CR` + `ESC[2K` + `ESC[1A` printed a **forged** `Change-class (aggregate): ordinary` line and scrolled the true `control-plane` line out of view — on the surface a human reads to give the §13 GO. Stripped at the **render** boundary only; stripping before `classify_path` would let a crafted name become a *lower* class (the fail-open direction). Board-controlled text still reaches `echo` in `backlog-current.sh` — pre-existing, exit code unaffected. |
| **Memory / context poisoning** | Agent memory is advisory; every load-bearing claim is re-measured. This release recorded twelve cases of an executor correctly refusing a false instruction from its own brief. |

## Residual risk

**Accepted, tracked, and disclosed at the point of use:**

1. **No class-wide lock guards the change-set derivation (MED)** — T2 above is mitigated at all five
   **known** sites, each individually mutation-proven, but nothing detects a **sixth**. A scanner was built
   and withdrawn: over three review rounds it was defeated by a same-line decoy, a continuation decoy, a
   trailing-backslash line it never scanned, a `\`-terminated **comment** that hid an entire derivation,
   an **argument reorder** (`diff "$base"...HEAD --name-only -z`) that drops `--no-renames` while looking
   harmless, and `&`/`|`/subshell separators its segmenter did not treat as boundaries. Each repair opened
   roughly as many holes as it closed, and its own claim register was demonstrably false — so it is boarded
   (`CHANGESET-DERIVATION-LOCK`) with that catalogue as required design input rather than shipped. Keeping
   the two producer derivations convergent is a **human** obligation until it lands. It also cannot tell whether a given
   listing is actually consumed by a classifier; it assumes any workflow-level listing is, which is the
   fail-safe direction. **No class-wide lock ships this release** (see T2 residual (b)); the five known
   sites are fixed and mutation-proven individually, and a sixth would be unobserved.
   **`profiles/` paths classify `ordinary`** — measured: `profiles/ratification.yml` and `profiles/*/ci.yml`
   both derive `ordinary`, so **the adopter-facing §13 gate and the ten emitted CI workflows can be edited
   with no independent ratifier**. That is a governance gap in its own right, independent of T2, and it is
   the reason a self-service exemption sentinel was judged unsafe to ship. Boarded as
   `PROFILES-ORDINARY-CLASS`.
   **One git derivation remains unguarded against newline splitting:** `.github/workflows/ci.yml`'s
   `backlog-presence` listing pipes `-z` output through `tr` without a newline check, so a crafted path
   still mis-splits there. Its consumer is board hygiene, not the ratifier, so the reachable impact is a
   wrong `backlog-presence` verdict rather than a §13 downgrade — **disclosed, not closed**.
   Sibling residuals: the **newline-in-filename** downgrade is **CLOSED this release** — both git producers
   fail-closed on a newline byte in the `-z` stream, and the three API listings carry a `jq` guard that
   refuses a splittable listing (the earlier wording here, "control-plane is fail-safe", was **false**: the
   suffix-constrained `agents/*.agent.md` pattern is defeated by a split — see T2 residual (a)). Still open:
   the GO record's `--class` is self-asserted and never cross-checked against the derivation (boarded,
   `PROMOTION-GO-CLASS-CROSSCHECK`), and a trailing `\r` or space in a path defeats the same
   suffix-constrained patterns (lower reachability — such a name is inert to the filesystem glob — but the
   *class* "a control byte in a filename defeats a suffix-constrained pattern" is only half closed).
2. **`SAST-PARSE-COMPLETENESS` (MED)** — T7. **Now the highest open item.** The SAST control is blind to
   most of the shell fleet.
3. **`OBLIGATION-TESTMODE-ENV-FLAG` (LOW)** — T8. Requires control of the process environment.
4. **Guard bypass via interpreter invocation** — architectural, disclosed since CP-8. The guard is a
   speed bump; the platform is the boundary.
5. **Obligation gates are path heuristics** — a file holding PII with no telltale name derives N/A.
   Named misses: `medical/`, `biometric`, `passport`, `iban`, `tax_id`, `nhs_number`, ALL-CAPS
   `PERSONAL-DATA/`.
6. **The three obligation jobs are now REQUIRED contexts on this repo — with one live caveat, so this
   is not "enforced" without qualification.** The exact set is declared in `REQUIRED-CHECKS.md` (the
   source of truth `conformance/branch-protection.sh` and `scripts/branch-protection-apply.sh` read —
   never retype the count or the names here, they drift; read the declaration).
   (a) **CLOSED (B4), qualified:** closed on the operator-run live leg; the declaration
   (`REQUIRED-CHECKS.md`) is ordinary-class and editable by the same actor who could remove a live
   context; no cadence exists (the live leg runs only when a maintainer chooses to run it) — nothing
   in-repo used to declare them, so silently removing one was undetectable —
   `branch-protection.sh` only asserted that required-status-checks *existed at all*.
   `REQUIRED-CHECKS.md` + `branch-protection.sh --declared-only`/its live leg now FAIL BY NAME on a
   declared-but-unbound context. Was boarded as `BRANCH-PROTECTION-DECLARATION-LOCK`; discharged.
   (b) **Rewritten 2026-08-25. `enforce_admins: false` persists by design; what changed is who can
   reach the bypass.** The admin route — `gh pr merge --admin` **and its REST implementation**,
   `PUT /repos/:o/:r/pulls/:n/merge` — still bypasses every declared context for anyone holding an
   admin token. Until this release the guard denied only the porcelain flag, so the agent's REST route
   was **open and measured at rc=0**; it is now guard-denied by the S6R disjunct (T1), which is a
   speed bump on one client and not a boundary. **Solo ratification therefore remains the owner's
   keystroke on a recorded GO** — that judgment, not the check, is the control, exactly as
   `D-240813-5` says. `enforce_admins` stays `false` while the repo is solo (flipping it would lock
   the sole maintainer out of their own recovery path — `docs/operations/review-lane.md` states the
   trap) and flips at D2, when a second human with write access exists and the ratification seat
   retires. Adopters who enable `enforce_admins` and require reviews get the stronger property today.

**Explicitly not accepted:** a vacuous green. Where a check cannot prove its claim, it says so in its
own header rather than passing quietly.

## Sign-off

**Threat model reviewed by:** security-reviewer (independent lens; `builder ≠ reviewer`)
**Date:** 2026-07-25 · refreshed 2026-08-25 (the version stamp is the header's single marker — a second
stamp here is what let this file carry two different release claims at once)
**Basis:** first written during Slice B `OBLIGATION-HARDEN` (closed T5/T8, surfaced T2/T7). **Revised in the
T2 slice**, whose *plan review* — `reviewer` + `security-reviewer` dispatched on the design and plan
**before any build** — established that this document's own T2 analysis was scoped to the wrong asset: it
named the classifier when the threat lived in the three *listing builders* feeding it, two of which were
live bypasses and one of which ships to every adopter. That finding is why the asset row above now names
the whole chain. **The re-review trigger below fired on this slice** (a change to the promotion contract's
derivation) and the review happened at the plan gate rather than after the fact.
**Refreshed 2026-08-25 in `KIT-EVAL-2-TIER-A` (`D-240825-1`).** The 2026-08-25 kit-evaluation rerun found
this document stamped 3.185.0 against VERSION 3.218.0 — 33 minor releases and ~18 guard commits of drift,
with a hardcoded "45 deny rules" that measured 42 on the day. Rows T1, T2, T4 and T6 were rewritten
against the tree as it actually is, residual #6(b) was rewritten around a route that had been open the
whole time, and the drift itself is now ratcheted: `conformance/runbook-current.sh` grades this file's header
version marker on every run, so the next such gap reds CI instead of waiting for an evaluator.
Re-review when the control plane changes shape — a new guard matcher, a new gate class, a change to
the promotion contract, **or the version ratchet reds**.
