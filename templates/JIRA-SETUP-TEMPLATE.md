# [Project Name] — Jira Setup (work-item contract)

> **Template.** `incept --backlog jira` wrote this; follow it once, then delete this line.

Follow it to make a Jira project satisfy the kit's §6 work-item contract (`DEVELOPMENT-PROCESS.md` §6), then verify with `sh conformance/tracker-contract.sh`. Full mapping rationale: `docs/work-tracking/adapters.md` (Jira); which gates bind on your PR and the cure for each: `docs/work-tracking/adapters.md` §Which gates bind.

**Tier.** This is the kit's **server-enforced** claim tier (the *Only Assignee* transition condition, §3 — the strongest of the hosted set). Convention-tier backends (last-writer-wins, claim-when-empty + re-read) use `TRACKER-SETUP-TEMPLATE.md` instead. The two are deliberately distinct, not redundant.

## 0. Preflight — can the kit reach and use this site? (read-only; run it before §1)
Before the conf exists: `sh conformance/tracker-contract.sh --preflight --base https://<site>.atlassian.net --project <KEY>`. After §4: `sh conformance/tracker-contract.sh --preflight` alone. **Data Center:** stamp §4 first (`--base` takes only an Atlassian Cloud site). Confirm the site on the card's first line is your own before trusting anything below it — Atlassian API tokens work on any Atlassian site.
- **Verdict words:** PASS · FAIL · TIER · INFO · ASK · UNVERIFIED. **Fix every FAIL before §1**; TIER, INFO and ASK are information (ASK names a question for your site admin).
- **Run it once with each credential:** `--as ci` with the CI reader's token (§5a), `--as dev` with a developer's.
- **CI reachability is measured on the runner, not on your machine.** Once §4 and §5 are merged, open `Actions → Adopter Tracker Gates → Run workflow`; its preflight step reports whether the runner can reach the site.
- **If CI cannot reach it** (IP allowlist or VPN), set the repository variable `KIT_TRACKER_RUNNER` to a self-hosted runner label inside your network.
- **Two runner risks.** (1) A label no runner matches **queues forever**, and because `tracker-board-gates` is a required check every PR waits: unset `KIT_TRACKER_RUNNER` or bring the runner online. (2) A self-hosted runner for a `pull_request_target` job belongs **only on a private repo or an ephemeral runner** (the job parses fork head objects beside the Jira secret); the gates job warns when it sees a public repo on a self-hosted runner (an ephemeral, network-isolated runner is a risk you accept and record in your waiver register, not a cure). The warning stays silent where `runner.environment` is unset (older GHES, or runners pinned with `--disableupdate` or a pinned image) and on internal repos (`private: true`, yet every enterprise member can open a PR from a fork).

## 1. Workflow statuses (the six §6 states + Blocked) — **HUMAN ACT — an agent stops and asks the
owner**: this is a Jira project-admin edit.
Create/rename the project workflow statuses to exactly:
`Backlog → Ready → In Progress → In Review → Released → Done`, plus `Blocked` (a status or the built-in flag). The board columns mirror these; moving a card is a state change.
Success signal (read-only): `sh conformance/tracker-contract.sh --discover` prints every status on
the Jira site (its `/status` read is site-wide, not per-project); confirm the six mapped names (plus
`Blocked`, if you made it a status) appear in that list.

## 2. Required custom fields — **HUMAN ACT — an agent stops and asks the owner**: this is a Jira
project-admin edit.
- **Size** — a select field (e.g. `XS/S/M/L`). **Do NOT use Story Points as size** — the kit forbids estimation-as-forecast (`DEVELOPMENT-PROCESS.md` §1).
- **Risk** — a select or short-text field for risk/complexity.
- Map the rest 1:1: Summary→title · Description (or an Acceptance Criteria field)→intent + acceptance · Assignee→owner · the development panel auto-links branches/commits/PRs.
- **Which issue type the kit creates.** `board create` makes issue type **Task** unless `.kit/tracker.conf` says
  `create.issuetype=<name>` (or you pass `--type`). On a **team-managed** project a custom field's id is **per
  issue type** — Task's Size is not Story's — and the conf holds one `field.size`/`field.risk`, so map those to the
  ids of the type you create. Find them with `sh conformance/tracker-contract.sh --fields` (read-only; it prints every
  type's Size/Risk ids and the lines to paste). Add Size/Risk to **that type's** create screen. A company-managed
  project usually shares one id across types.
- **Acceptance Criteria.** Map `field.acceptance` to your Acceptance Criteria field so the DoR flag reads it. The DoR flag checks presence only, never content. `board create` still carries acceptance in the description.
- **Fields your Jira requires on create** (a project may require Components, Fix Version, a Team select, and so on). Run `sh conformance/tracker-contract.sh --fields`: its REQUIRED section lists each one (id, kind, name, allowed values) and prints a paste line for every one the conf does not yet cover. Map each in `.kit/tracker.conf` with `create.<fieldId>=<value>` (a default for every card), or `create.<fieldId>=prompt` (the agent supplies it per card with `board create --field <fieldId>=<value>`). The conf holds **mechanics only**: which value is right for your team is semantics, and belongs in the project `CLAUDE.md` (the agent reads it there; if it is silent, the agent asks the owner). Without a mapping `board create` refuses before it posts, naming the line to add.
Success signal (read-only): `sh conformance/tracker-contract.sh` (no flag) passes its field-presence
leg without naming a missing Size/Risk field, **and** its create-coherence leg (`field.size`/`field.risk` is on the
create type's screen; a `label:` mapping is not left beside a same-named select), **and** its required-field leg (every field Jira requires on create is covered by `field.size`/`field.risk` or a `create.<fieldId>=` line; the leg prints field ids and names, never allowed values). A FAIL names the line to paste.
**Honest ceiling:** create-meta does not report a requirement enforced by a workflow validator (for example on the Create transition). Such a refusal still reaches you as a failed create, with a hint to run `--fields`; the kit cannot see it in advance.

## 3. The atomic claim — "Only Assignee" transition condition (load-bearing) — **HUMAN ACT — an
agent stops and asks the owner**: this is a Jira workflow-admin edit.
This is what makes Jira a **server-enforced** single-owner claim — the strongest of the hosted set. Without it you are on the **convention tier** (last-writer-wins).

> **Caveat — the condition exists only on company-managed projects.** Jira's UI offers no "Only Assignee" restriction
> on a team-managed project (its "restrict who can move a work item" lists users, permissions, groups and custom-field
> users, never the assignee), so a team-managed project is on the **convention tier**: `board claim` still assigns and
> transitions there, just not exclusively. `tracker-contract.sh --deep` reports which tier you are on and grades what the
> workflow actually carries (`TIER: convention` is rc 0, a supported tier; a company-managed project missing the
> condition FAILs). Reading a company-managed project's workflows needs a Jira-admin token (Administer Jira); without
> one, or when the workflows could not be read, `--deep` prints UNVERIFIED (rc 2), never a pass. Data Center is
> UNVERIFIED too (no REST read of transition conditions).

1. Project settings → **Workflows** → edit the active workflow.
2. Select the transition **into `In Progress`**.
3. Add a **Condition** → **"Only Assignee"** (or "Only the reporter/assignee can execute"), so only the current assignee can move a card to In Progress.
4. Publish the workflow.

Now claiming = assign to the agent, then transition; a second agent cannot perform the transition → no double-claim.
Success signal (read-only, an admin token, one-time — see §5h): `sh conformance/tracker-contract.sh --deep` verifies every transition into In Progress in this project's own workflows carries an exclusive Only-Assignee condition, or reports the tier it found.

## 4. `.kit/tracker.conf` — the pin (TBG-TRACKER-CONF)
`incept --backlog jira` stamped `.kit/tracker.conf`: a strict, fail-closed `key=value` file naming
the host (`base_url=`, **https only** — the host is the pin, never override it from an environment
variable), `flavour=cloud|datacenter`, `project=`, the `state.<kit-state>=<tracker-status>` /
`field.<name>=` maps, and `create.issuetype=` (the issue type `board create` makes; default `Task`,
see §2). `field.size`/`field.risk` is both what `board create` **writes** and what the readers **read**:
`customfield_NNNNN` (a select or string field on the create type's screen) or `label:<prefix>`. It
carries **no secret**. A field your Jira requires on create is mapped by `create.<fieldId>=<value>`, where
`<fieldId>` is `customfield_NNNNN` or one of `priority`, `components`, `fixVersions`, `duedate`, `labels` (the writable set the
adapter prints with `writable-create-keys`; `parent` and `description` are in it too but are filled **only** by
`board create --parent` / `--description` - a conf `create.parent=` / `create.description=` line is ignored with a
NOTE), and the value is one of: `prompt` (nothing is filled; the agent passes
`board create --field <fieldId>=<value>` per card), `id:<digits>` (a Jira option/entity id), or a literal (printable
ASCII, at most 80 bytes, no `|`, no leading or trailing space). Each key appears once and must not repeat a `field.*`
id. Validate it any time with:
`sh scripts/tracker-conf.sh .kit/tracker.conf`

**Who may edit it.** `.kit/tracker.conf` is control-plane: an agent cannot edit it in place, because the
runtime guard denies every mutation form on that file. That is by design, since the conf pins the host the
trusted job sends the Jira secret to. There are two routes: the owner edits it, or the agent edits it with
Edit/Write in a **dev-clone** under the temp root (`git clone . /private/tmp/<name>`, a literal path;
`docs/operations/runtime-guards.md` §*The dev-clone affordance*), validates it there with
`sh scripts/tracker-conf.sh .kit/tracker.conf`, and pushes a branch. Either way the change is a control-plane
PR, so it costs what `START-HERE.md`'s solo track says. One gap is disclosed: a dev-clone carries no installed
pre-push hook, so CI and the owner's review are the checks on that branch. (cold test 2, items 36, 42 and 78)

**Two modes:**
- **Greenfield** (`incept --backlog jira`, no `--existing`): the conf ships with a full identity
  state map (every kit state names itself) — edit `base_url`/`project` for your instance, and
  rename the tracker-side statuses in §1 above to match, or edit the `state.*` lines to match your
  existing tracker statuses.
- **Brownfield / existing tracker** (`incept --backlog jira --existing`): the conf ships with an
  **empty** state map. Set the credentials below, then run:
  `sh conformance/tracker-contract.sh --discover`
  to print your instance's id↔name status map, and add one `state.<kit-state>=<tracker-status>`
  line per §4.1 kit state (`DEVELOPMENT-PROCESS.md` §4.1) — the **first** line for a given kit
  state is the `move` target when more than one tracker status maps to it. See also
  `docs/adoption/brownfield.md` for adopting the kit into an existing repository generally.

## 5. Credentials — two credentials, two jobs

**5a. The trusted reader's CI credential — Browse Projects only, on one project. HUMAN ACT — an
agent stops and asks the owner** to create the account and its token; an agent never holds site/org
credentials.
The `tracker-board-gates` job (the trusted reader, `profiles/adopter-tracker-gates.yml`) authenticates
with a **dedicated service account** whose Jira permission on this one project is **Browse Projects
only** — no create/edit/transition/assign/admin. The adapter calls your site's `base_url` directly;
Atlassian's scoped API tokens are served through a different gateway (`api.atlassian.com/ex/jira/…`)
the adapter does not route to yet, so use the service account's classic API token (Cloud) or Personal
Access Token (Data Center) — least privilege comes from the account's own permission (Browse Projects
only, one project), not the token type. "One project" holds only if no other project's permission
scheme (or a site-wide group grant) gives that account anything: the §5c probe checks five
permissions on this project only and never measures the account's reach into other projects. Give
the token an expiry where your Jira offers one, and rotate it on a schedule. The scoped-token route
is boarded as `TRACKER-JIRA-SCOPED-TOKEN-ROUTE`. Store the token as a **repository Actions secret**, never a
GitHub Environment secret unless you have added `environment:` to both jobs yourself (§5d).
**HUMAN ACT — an agent stops and asks the owner:** adding a repository Actions secret needs repo-admin
GitHub access.

- **`KIT_TRACKER_TOKEN`** — always required: the service account's API token (Cloud) or Personal
  Access Token (Data Center).
- **`KIT_TRACKER_USER`** — the service account's email, required only under `auth=basic`; not needed
  under `auth=bearer` (Data Center PAT).

Success signal (read-only): `gh secret list` shows `KIT_TRACKER_TOKEN` (and `KIT_TRACKER_USER` when
`auth=basic`) among the repository secrets. An agent can run it only if its own token carries
Secrets: read (secret *names* only — values are never readable via the API); a repo-admin
credential is never an agent's. Otherwise it is a human check.

If either required secret is missing, the job's own pre-check names it and nothing else, byte-for-byte:
`::error title=tracker-board-gates: tracker credentials not configured::add the repository Actions secret $_missing`
(`profiles/adopter-tracker-gates.yml`). Fix: add the named repository Actions secret and re-run.

**5b. The developer's own credential — for the write verbs, never a CI secret.**
`sparkwright board claim|release|move|create` (`scripts/board.sh`) writes with **your own**
`KIT_TRACKER_USER`/`KIT_TRACKER_TOKEN`, exported in your own shell — **never** the CI secret above
(A5, `scripts/board.sh` header: "the developer's own KIT_TRACKER_USER/TOKEN, never a CI-scoped
token"). On Data Center with `auth=bearer`, also export **`KIT_TRACKER_AUTH=bearer`** in that shell
before running a write verb — writes read `KIT_TRACKER_AUTH` from the environment (default
`basic`), independently of what the conf declares for reads (DS-5). Without it the write runs as
`basic`: if `KIT_TRACKER_USER` (or `JIRA_EMAIL`) is unset it is refused locally before any request
("refused: credential (user) outside the allowed charset"); if it is set, the PAT goes as HTTP
Basic to the `base_url` in your working tree's `.kit/tracker.conf` — the credential does not leave
that host, but Data Center will reject it.

**`land` closes the card where your credential is.** After the merge, `land` (and `actuate`) run
`sh scripts/board.sh release <ROW> --stale`: on a tracker that moves the card to your `state.done`
(with a claim ref held the proof is the merged PR; with none, nothing is checked and `board.sh` says UNPROVEN), proves it by post-read, and deletes the claim ref. This happens in
the shell that runs `land`, so it needs the credential above exported there. If the move fails the
merge stands (exit 0), a WARN names the one command, and the last line reads
`board: NOT CLOSED — see the WARN above`; the happy path ends `board: closed`. A merge made in the
forge UI moves nothing: run `sh scripts/board.sh release <ROW> --stale` afterwards. (`board release`
without `--stale`, the holder giving a claim back, still ends the card at `state.ready`.)

**5c. What the over-privilege probe does — detects, never blocks.**
Every credential is probed for five permissions on the project: `CREATE_ISSUES`, `EDIT_ISSUES`,
`TRANSITION_ISSUES`, `ASSIGN_ISSUES`, `ADMINISTER_PROJECTS` (`scripts/tracker-jira.sh`'s
`tj_permissions`, ~:1237). Holding **any one** of them makes the probe print `over-privileged`; the
trusted job then logs a **NOTICE and binds anyway** — byte-for-byte: `seam: NOTICE — record
credential is over-privileged for this read (binding anyway, S-11)` (`conformance/backlog-lib.sh`).
**The gate does not refuse an over-privileged credential; the adopter is the one who acts on the
NOTICE** — the kit does not, and cannot, enforce least privilege from outside the account.
A failed or unparsable probe itself prints the bare word `unverified` (`scripts/tracker-jira.sh`'s
`tj_permissions` prints exactly one of `over-privileged` | `ok` | `unverified`); `tracker-read.sh`
then writes the record line `credential unverified` (`scripts/tracker-read.sh:~22`) and downgrades
the read's own verdict to `unverified` rather than binding (never defaults to `ok`) — **this outcome
is red**: the record never reaches `verdict bound`. The CI service account (Browse Projects only,
§5a) will probe `ok`; your own write-capable developer token (§5b) is *expected* to probe
`over-privileged` when you run it locally — that is not a bug.

**5d. Environments — the shipped profile declares none.**
`profiles/adopter-tracker-gates.yml` ships with no `environment:` key on either job, so a GitHub
Environment secret reads **empty** there — both `KIT_TRACKER_USER`/`KIT_TRACKER_TOKEN` must be
**repository** Actions secrets (§5a), not Environment secrets, unless you add `environment: <name>`
to **both** jobs yourself. That is a control-plane edit and needs ratification like any other. A
`main`-only deployment branch policy on that Environment works; required reviewers on it would hold
every PR waiting on a human approval — decide that trade-off deliberately, don't inherit it by
accident. Do not copy the kit's own `tracker-live.yml` "never repo-level" rule into this project —
that rule is about the kit's *own* live-probe workflow, not a rule this template's shipped profile
follows.

**5e. Fork PRs.** `pull_request_target` (used by the trusted reader) runs with repository secrets
even on a PR from a fork. The control is that it only ever runs **base-branch code** (S-1) — a fork
PR's own workflow-file or script edits cannot reach the secret. The Browse-Projects-only,
single-project account (§5a) further bounds what that secret is worth if it were ever exposed.
Rotate `KIT_TRACKER_TOKEN`/`KIT_TRACKER_USER` if the workflow file or `.kit/tracker.conf` is ever
found to have changed outside a ratified control-plane PR.

The same "base-branch code only" control means a PR that *changes* the trusted job
(`.github/workflows/adopter-tracker-gates.yml`, its scripts, or `.kit/tracker.conf`) is judged by the **old**
job, so it may not pass `tracker-board-gates` on its own PR. When it does not pass, **solo:** the owner merges
it with the admin merge (the agent records the GO; the guard denies the agent `--admin`), and the new job's
first real run is the next PR. **Team (`enforce_admins:true`):** untested. Expect the owner to lift
`tracker-board-gates` from the required checks for that one merge and restore it afterwards; do not leave it
lifted. (cold test 2, item 47)

**5f. The forbid list — never:**
- a human developer's own token as the CI secret (§5a always uses a dedicated service account);
- a site-, org-, or project-admin account as the CI credential;
- a password as `KIT_TRACKER_TOKEN` on Data Center — a Personal Access Token with `auth=bearer` only;
- a token written into `.kit/tracker.conf` — the conf's own grammar (`scripts/tracker-conf.sh`)
  refuses an unknown key and refuses userinfo in `base_url`, so a `user:token@host` or a bespoke
  `token=` line is refused outright — or committed to git in any other file;
- a token pasted into agent chat, a commit message, or a PR description/comment;
- an agent reading a real `.env` file — the guard refuses that read by design; a human exports the
  credential into their own shell instead.

**5g. Binding the pin — what `.kit/tracker.conf`'s `base_url`/`project` comparison actually does.**
`hooks/pre-push` (`:171-172`) tries `origin/main:.kit/tracker.conf`, falling back to
`origin/master:.kit/tracker.conf`, and hands whichever copy it finds to `scripts/tracker-read.sh` as
that script's origin-conf argument. `tracker-read.sh` itself does not know a branch name — it only
compares the working tree's `.kit/tracker.conf` `base_url`/`project` against **the origin-conf file
it was given**, and refuses to send the token at all on a mismatch — byte-for-byte:
`refused: local .kit/tracker.conf pin diverges from origin's — token not sent (S-2)`
(`scripts/tracker-read.sh:87`). When the file it was given does not exist,
`tracker-read.sh` skips the compare (`:81`) and the read goes ahead — the token is sent with
nothing to compare against — but the pre-push hook never takes that path:
with no origin copy of the conf it stops before calling the reader and sends no token
(`hooks/pre-push:171-177`; the greenfield case below). In CI, the **base branch's own conf is the
reference** the seam checks a record's `pin sha256:` against. No step ever writes a new reference value into a local state file, and there
is no standing state that carries forward from one check to the next — the only way to change what
the comparison checks against is a **ratified control-plane PR that edits `.kit/tracker.conf`**,
merged to `main`, then `git fetch` (or a fresh clone) locally so the working tree's origin copy
matches. Cure for the refusal above: `git fetch && git rebase origin/main` (or re-clone), then
re-run; if the conf itself is wrong, open a control-plane PR to correct it — do not hand-edit it
around the refusal.

**Greenfield — no `.kit/tracker.conf` on `origin` yet.** Before `.kit/tracker.conf` has ever landed
on `main`, `hooks/pre-push` finds no `origin/main` or `origin/master` copy to compare against and,
byte-for-byte (`hooks/pre-push:175`):
`no origin pin to compare — token not sent (S-2); TOFU persistence is TRACKER-S2-TOFU-PIN-PERSIST, deferred`
— the sentence says plainly that this does not exist yet today, as a boarded row. Cure: land
`.kit/tracker.conf` on `main` first, through the ratified control-plane PR every conf edit needs,
then `git fetch` locally so `origin/main` carries the copy `tracker-read.sh` compares against.

**5h. `--deep` needs Jira admin — HUMAN ACT — an agent stops and asks the owner, never in CI.**
`sh conformance/tracker-contract.sh --deep` introspects the workflow's transition conditions, which
needs the **global Administer Jira** permission for a company-managed project (it makes one
`POST /rest/api/3/workflows` per issue type of this project; a team-managed project needs only project admin) — a permission neither the CI service account
(§5a, Browse Projects only) nor an agent should ever hold. Run `--deep` **once**, by hand, in your own shell, with
an admin's own token exported in that shell only for the duration of the command — never in `.env`,
never in CI, never in an agent's shell. An agent (including the cold-test agent) runs only the base
check (no flag) and `--discover`; it never runs `--deep`.

## 6. Bind branch protection before your first PR — **HUMAN ACT — an agent stops and asks the
owner**: this needs an admin-authenticated `gh` and a `y/N` confirmation (`scripts/branch-protection-apply.sh`
header).

Before opening the first PR on this repository, run:
`sh scripts/branch-protection-apply.sh --apply`
Success signal (read-only, an agent can check it): run `sh scripts/branch-protection-apply.sh` with
no flag — its default is show-only — and it prints `Dry-run: nothing to add — every declared context
is already bound live.` once `tracker-board-gates` is bound.

**What "red" means today, honestly.** On `jira`, the PR-tree `loop-state` gate's row leg **stands
aside** — prints the exact sentence
`N/A: board governance is delegated to the required context 'tracker-board-gates' (live on the base branch)`
— once the base declares the tracker, the base's
`.kit/tracker.conf` passes the base's own validator, and the base branch's LIVE protection requires
`tracker-board-gates` (the HUMAN ACT above). The step-aside itself does not depend on the two
repository secrets — only the trusted job needs them, to bind (go green) and produce the tracker
record the PR-tree leg delegates to. Until the bind is live, the row leg stays **red (rc 1)**,
curable by a ratified `board-governance` waiver, tracked in your repo's `WAIVER-REGISTER.md`
(`templates/WAIVER-REGISTER.md`).

**Still red after binding `tracker-board-gates`?** Other causes: the base's `.kit/tracker.conf` is
missing or refused by the base's own validator; the protection is a repository ruleset rather than
classic branch protection (the read only sees `required_status_checks.contexts`, so a ruleset-only
requirement reads as not-live); on a **private** repository, reading the base branch's protection is
unmeasured (LS-D4) — if it returns nothing, the step-aside stays off, red, curable by the same
waiver. See `docs/work-tracking/adapters.md` §Which gates bind for the full per-gate picture and
cure per cell (`#708`).

## 7. Verify
`sh conformance/tracker-contract.sh`
It verifies the six states + Size/Risk fields live, reading `.kit/tracker.conf` (or, for a tree
predating this slice, the legacy `JIRA_BASE_URL` + `JIRA_EMAIL` + `JIRA_TOKEN` triple). Add
**`--deep`** to also read this project's own workflows and **report the tier** — *verified* server-enforced
(Only-Assignee on every transition into In Progress), the team-managed convention tier, or UNVERIFIED (§3):
`sh conformance/tracker-contract.sh --deep`
