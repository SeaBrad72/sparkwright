# [Project Name] — Jira Setup (work-item contract)

> **Template.** `incept --backlog jira` wrote this; follow it once, then delete this line.

Follow it to make a Jira project satisfy the kit's §6 work-item contract (`DEVELOPMENT-PROCESS.md` §6), then verify with `sh conformance/tracker-contract.sh`. Full mapping rationale: `docs/work-tracking/adapters.md` (Jira); which gates bind on your PR and the cure for each: `docs/work-tracking/adapters.md` §Which gates bind.

**Tier.** Jira offers an *only the assignee* restriction on the transitions into In Progress (§3), the basis of the kit's **server-enforced** claim tier, but only through a workflow that already carries it. The rule is measured to display; enforcement against a non-assignee is not yet measured. The default is the **convention tier** (last-writer-wins, the git claim ref as the coordination record). Convention-tier backends (last-writer-wins, claim-when-empty + re-read) use `TRACKER-SETUP-TEMPLATE.md` instead. The two are deliberately distinct, not redundant.

## Day-one act sheet

Every row is a **HUMAN ACT**: an agent stops and asks the owner, and may run only the read-only success signal. Work down the table in order; each row links to the section that explains it. These are Jira Cloud paths; Data Center differs.

**Minimum day one** for a one-account adopter is rows 3, 4, 10, 11 and 14, plus row 1 only if the site blocks API tokens. Rows 2, 5-9, 12, 13 and 15 are the team posture, and row 16 is optional. Your own token as the CI reader is recorded `over-privileged` (or `writer` if it holds no admin) and binds with a notice; a site that rejects the extended permission keys reads `unverified` and fails; and this places your own token in the per-PR job, which rows 5-9 remove.

| # | act | who | where | success signal |
|---|-----|-----|-------|----------------|
| 1 | Clear an authentication policy that blocks API tokens on a claimed domain (N1) | org admin | Atlassian Administration → Security → Authentication policies | [§0](#0-preflight--can-the-kit-reach-and-use-this-site-read-only-run-it-before-1) `--preflight` `auth` line PASS (blocked: 401 at the site and at `api.atlassian.com`) |
| 2 | Plan: Standard or above, to assign space roles and edit permission schemes (N2) | owner | Atlassian Administration → Billing | the space's People page offers roles beyond Administrator and Guest |
| 3 | Your own credential for setup, set for the command only (`KIT_TRACKER_USER=<email> KIT_TRACKER_TOKEN="$T" sh conformance/tracker-contract.sh --preflight --base https://<site>.atlassian.net --project <KEY> --as dev`, T read silently as in N7), never exported in a shell that launches an agent; `unset T` after ([§0](#0-preflight--can-the-kit-reach-and-use-this-site-read-only-run-it-before-1)) | you | your terminal | `--preflight --as dev` PASS |
| 4 | Statuses (the six plus Blocked), required fields, and, optionally, a workflow that carries "only the assignee" (§1-§3) | Jira admin | Settings → Work items → Workflows (statuses alongside) | `sh conformance/tracker-contract.sh` ([§7](#7-verify)) |
| 5 | Space roles Member and Viewer, created once at site level (N3) | Jira admin | Settings → System → Security: Space roles → Add Space roles | both roles are listed |
| 6 | Copy the permission scheme. Remove every write grant held by any logged-in user (`applicationRole`), Anyone (public) or a site-wide group, and confirm nothing is granted to Anyone. Keeping any-logged-in "Browse projects" is a disclosure choice; remove it if the board is confidential. Grant Viewer: "Browse projects", so the CI reader does not depend on the broad grant. Grant Member: "Create issues", "Edit issues", "Transition issues", "Assign issues", "Assignable user", "Add comments", "Schedule issues", "Resolve issues" and "Close issues", with no "Delete issues" and no admin (N4, N5). Associate the copy with the space | Jira admin | Settings → Work items → Work item attributes: Permission Schemes; then Space settings → Permissions → Actions → Use a different scheme → Associate | the space's Permissions page names the copy; rows 7 and 9 prove the grants |
| 7 | The agent account: a dedicated account added as Member | owner | the space's People page → Add people (the role list shows Member once row 5 is done) | `--preflight --as agent` PASS: `browse · create · transition · assign; no admin, no delete`. The probe does not test "Schedule issues"; the proof is the first `board rank` |
| 8 | The agent's token into the login Keychain ([§5](#5-credentials--two-credentials-two-jobs), 5b) | the operator, in their own terminal | `security add-generic-password …` | `sparkwright doctor`: `keychain (read for the identity check) - runs as <agent>` |
| 9 | The CI reader: an existing dedicated non-human seat (not a person's own account, not the agent account), Viewer only on this space, used on no other space; its token expiring and rotated ([§5](#5-credentials--two-credentials-two-jobs), 5a; N6) | owner | the space's People page | `--preflight --as ci`: browse only |
| 10 | Fill `.kit/tracker.conf` and land it on `main`: a control-plane PR the owner admin-merges, and until it lands no token is sent ([§4](#4-kittrackerconf--the-pin-tbg-tracker-conf), 5g) | owner | the repository | `sh scripts/tracker-conf.sh .kit/tracker.conf` exits 0 silently; the conf is on `origin/main` |
| 11 | Repository secrets: `KIT_TRACKER_TOKEN`, plus `KIT_TRACKER_USER` under `auth=basic` (N7) | repo admin | `gh secret set` | `gh secret list`; the next PR's log prints `tracker reader: …<id tail>` |
| 12 | Repository variables, only if needed: `KIT_TRACKER_RUNNER`; the reader-ceiling pair; `KIT_TRACKER_LIVE_ROW` ([§0](#0-preflight--can-the-kit-reach-and-use-this-site-read-only-run-it-before-1), 5a) | repo admin | Settings → Secrets and variables → Actions → Variables | `gh variable list` |
| 13 | Prove the runner reaches the site ([§0](#0-preflight--can-the-kit-reach-and-use-this-site-read-only-run-it-before-1)) | repo admin | Actions → Adopter Tracker Gates → Run workflow | its preflight step reports reachability |
| 14 | The bootstrap push, then bind branch protection: `--replace` on a fresh `main`, `--apply` after ([§6](#6-bind-branch-protection-before-your-first-pr--human-act--an-agent-stops-and-asks-the-owner-replace-typed-at-a-real-terminal); N8) | repo admin | a real terminal, with admin `gh` | the no-flag dry-run prints `Dry-run: nothing to add` |
| 15 | A waiver, only if row 14 cannot bind (a ruleset, or a private repository whose read is unmeasured) | owner | `WAIVER-REGISTER.md`, a `board-governance` row | `sh conformance/waivers-valid.sh --active board-governance` |
| 16 | Optional: `--deep` once, by a Jira admin, never in CI (5h, [§7](#7-verify)) | Jira admin | their own terminal | the tier is reported |

**Notes**
- **N1.** A clean 193-character classic token still reads 401 when the domain's authentication policy blocks API tokens. Fix the policy, not the token.
- **N2.** On Free, space roles cannot be assigned and permission schemes cannot be edited. Standard unlocks both.
- **N3.** Space roles are site-level. Create them once, then fill them per space on the People page.
- **N4.** A copied scheme keeps every any-logged-in-user grant. Remove the writes explicitly.
- **N5.** Without "Schedule issues", `board rank` answers 403 and names it. Without "Resolve issues" or "Close issues", the board's transitions fail.
- **N6.** The CI reader is an existing licence, not a new one. The seat is dedicated and non-human: never a person's own account, never the agent account.
- **N7. `gh secret set`.** The interactive paste can land the token in `KIT_TRACKER_USER`. Set the email with `--body`. For the token:
  1. Read it silently: `read -rs T` (bash or zsh), or `trap 'stty echo' INT; stty -echo; IFS= read -r T; stty echo` in POSIX sh.
  2. Step 2 needs row 10's conf on `main`. Prove it with the kit's own check, not curl, which would put the token in argv and accept an anonymous 200: `KIT_TRACKER_USER=<email> KIT_TRACKER_TOKEN="$T" sh conformance/tracker-contract.sh --preflight --as ci`.
  3. Store it: `printf '%s' "$T" | gh secret set KIT_TRACKER_TOKEN`.
  4. `unset T`.
- **N8.** The approval that counts is the GitHub review button on the PR's current head. An "approved" said in an agent session does not register with branch protection.

## 0. Preflight — can the kit reach and use this site? (read-only; run it before §1)
Before the conf exists: `sh conformance/tracker-contract.sh --preflight --base https://<site>.atlassian.net --project <KEY>`. After §4: `sh conformance/tracker-contract.sh --preflight` alone. **Data Center:** stamp §4 first (`--base` takes only an Atlassian Cloud site). Confirm the site on the card's first line is your own before trusting anything below it — Atlassian API tokens work on any Atlassian site.
- **Verdict words:** PASS · FAIL · TIER · INFO · ASK · UNVERIFIED. **Fix every FAIL before §1**; TIER, INFO and ASK are information (ASK names a question for your site admin).
- **Minimum curl: 7.54.0.** The adapter's config sets `suppress-connect-headers` (so a proxy's `CONNECT` reply is never read as Jira's answer); an older curl rejects the unknown option and every request fails with `unverified: curl exit 2`. Check `curl --version` on every machine and runner that runs the adapter.
- **A credential Jira did not accept is rc 6, not an empty result.** Jira Cloud serves a wrong token as an anonymous user; the preflight's `auth` line then reads FAIL "the site did not accept the credential", and `board list` and the other verbs say "the tracker rejected the credential".
- **Run it once with each credential, and know what each role asserts.** For setup, run `--as dev` (the default) with **your own** credential: it checks you can browse, create, transition and assign, and sets no upper bound, because your own account may legitimately be an admin while you configure the site (a credential that is an admin gets one INFO line saying so). Then run `--as agent` with the **agent pair** (§5b): it adds the upper bound and FAILs when that credential holds `ADMINISTER`, `SYSTEM_ADMIN`, `ADMINISTER_PROJECTS` or `DELETE_ISSUES`, because lanes must run as a dedicated non-admin account. Run `--as ci` with the CI reader's token (§5a): browse only, and FAIL on anything more. Every role prints an `identity` line naming the account (`--as ci` shows only the last 8 characters of its id).
- **CI reachability is measured on the runner, not on your machine.** Once §4 and §5 are merged, open `Actions → Adopter Tracker Gates → Run workflow`; its preflight step reports whether the runner can reach the site.
- **If CI cannot reach it** (IP allowlist or VPN), set the repository variable `KIT_TRACKER_RUNNER` to a self-hosted runner label inside your network. **HUMAN ACT — an agent stops and asks the owner:** a repository admin sets it.
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
- **Success metric.** Add a **paragraph** (multi-line text) custom field named "Success metric" to the create screen of the issue type you create, then map `field.metric=customfield_NNNNN` beside `field.acceptance`. The trusted job grades a `dor-metric` flag on every Ready card, and a flag whose `field.*` key is unmapped reads UNVERIFIED (rc 2), which fails the job; `board create --metric <text>` writes the field. It cannot be mapped to `description`, since the conf refuses two `field.*` keys with one value, and the flag checks presence only. Find the id with `sh conformance/tracker-contract.sh --fields`.
- **Fields your Jira requires on create** (a project may require Components, Fix Version, a Team select, and so on). Run `sh conformance/tracker-contract.sh --fields`: its REQUIRED section lists each one (id, kind, name, allowed values) and prints a paste line for every one the conf does not yet cover. Map each in `.kit/tracker.conf` with `create.<fieldId>=<value>` (a default for every card), or `create.<fieldId>=prompt` (the agent supplies it per card with `board create --field <fieldId>=<value>`). The conf holds **mechanics only**: which value is right for your team is semantics, and belongs in the project `CLAUDE.md` (the agent reads it there; if it is silent, the agent asks the owner). Without a mapping `board create` refuses before it posts, naming the line to add.
Success signal (read-only): `sh conformance/tracker-contract.sh` (no flag) passes its field-presence
leg without naming a missing Size/Risk field, **and** its create-coherence leg (`field.size`/`field.risk` is on the
create type's screen; a `label:` mapping is not left beside a same-named select), **and** its required-field leg (every field Jira requires on create is covered by `field.size`/`field.risk` or a `create.<fieldId>=` line; the leg prints field ids and names, never allowed values). A FAIL names the line to paste.
**Honest ceiling:** create-meta does not report a requirement enforced by a workflow validator (for example on the Create transition). Such a refusal still reaches you as a failed create, with a hint to run `--fields`; the kit cannot see it in advance.

## 3. The claim — convention by default, server-enforced through a workflow that carries the condition (optional) — **HUMAN ACT — an
agent stops and asks the owner**: this is a Jira workflow-admin edit.
By default you are on the **convention tier**: `board claim` assigns and transitions, last-writer-wins, and the git claim ref is the coordination record. Jira's current workflow editors offer no assignee-only restriction to add (measured 2026-10-12: "Restrict who can move a work item" lists users, roles, permissions, groups and custom-field users, never the assignee), so the old recipe "add a Condition → Only Assignee" no longer exists. `tracker-contract.sh --deep` grades `TIER: convention` (rc 0, a supported tier) and, for a company-managed space, prints the route below.

**The route to the server-enforced tier (company-managed space) — measured to display, not yet to enforcement.** A workflow that already carries the rule still shows it, and can be copied:
1. Settings → Work items → **Workflows**: find a workflow whose transition into In Progress shows "Restrict who can move a work item — only the assignee" (for example an inactive classic default workflow).
2. Actions → **Copy**; in the copy, map its statuses to the space's statuses (including the conf's `state.in-progress`).
3. Assign the copy to the space through its workflow scheme, then publish. If the workflow scheme is shared with other spaces, copy the scheme first and associate the copy with this space only.
4. Verify with `sh conformance/tracker-contract.sh --deep` using an admin token: `PASS: deep — server-enforced claim` means every transition into In Progress carries the rule. A partial result names the uncovered transitions.

Honest ceiling: nobody has yet assigned a copy to a space and confirmed that a non-assignee cannot move the card; the rule is measured to display, not yet to enforcement.

> **Caveat — team-managed spaces.** The measured option list in a team-managed space is the same and its custom-field picker is empty; no route was found, so a team-managed space stays on the **convention tier**. Reading a company-managed space's workflows needs a Jira-admin token (Administer Jira); without one, or when the workflows could not be read, `--deep` prints UNVERIFIED (rc 2), never a pass. Data Center is UNVERIFIED too (no REST read of transition conditions).

Success signal (read-only, an admin token, one-time — see §5h): `sh conformance/tracker-contract.sh --deep` reports the tier it measured.

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
scheme (or a site-wide group grant) gives that account anything: the §5c probe checks eight
permissions (five on this project, three that reach beyond it) and never measures the account's reach into other projects. Check the
account with `sh conformance/tracker-contract.sh --preflight --as ci` using its token: it must read "browse only". On every PR the
trusted job prints `tracker reader: …<last 8 characters of the account id>` before it reads, so the log names which identity the CI
secret is (never a display name). (A live probe workflow, such as the kit's own `tracker-live`, needs the repository variable
`KIT_TRACKER_LIVE_ROW` to name a long-lived **non-epic** card in a status the conf maps, and it fails any record that is not
`bound` with credential `ok`.) **The Free-plan ceiling:** a Free Jira plan's permission scheme ("Default software scheme") cannot be
edited and grants Browse together with Create, Edit, Transition and Assign to every licensed user, so no account on that plan can be
a Viewer-only reader. If that is your plan, say so with two repository variables: `KIT_TRACKER_READER_CEILING=licensed-writer` and
`KIT_TRACKER_READER_CEILING_CARD=<KEY-n>` (the boarded card that moves you to a plan with an editable scheme; form `ABC-123`).
The ceiling is **bounded**: the record says `credential writer` for an account that can create, edit, transition or assign but holds
no `ADMINISTER`, `SYSTEM_ADMIN`, `ADMINISTER_PROJECTS` and no `DELETE_ISSUES`, and only `writer` passes the live probe, with a notice
on every run naming the ceiling, the card and "trail: GitHub settings audit log". An `over-privileged` reader (any admin-class key
or delete held) fails whatever the tier, `unverified` fails, a missing or ill-formed card fails, and unset or `viewer` keeps the strict
reading (a `writer` then fails). `sh conformance/tracker-contract.sh --preflight --as ci` still prints FAIL for a writer, adding where
it can be accepted. **Residual risk, stated:** on such a plan the per-PR `pull_request_target` job holds a board-**write** token as a
repository secret, and the ceiling changes a verdict, not that exposure. Use a **dedicated account** for the CI reader with **no
`DELETE_ISSUES`** (the probe checks that key only; other destructive project permissions are not probed), used on **no other
project**, with an **expiring and rotated token**, and **separate from the agent account** (§5b). The card's KEY format is checked
(`ABC-123`); the kit does not check that the card exists, so keep it on the board. Give
the token an expiry where your Jira offers one, and rotate it on a schedule. The scoped-token route
is boarded as `TRACKER-JIRA-SCOPED-TOKEN-ROUTE`. Store the token as a **repository Actions secret**, never a
GitHub Environment secret unless you have added `environment:` to both jobs yourself (§5d).
**HUMAN ACT — an agent stops and asks the owner:** adding a repository Actions secret needs repo-admin
GitHub access.

A site on a Standard plan or above can run the Viewer-reader posture with no ceiling variables set, and an existing **dedicated non-human** seat can be the reader with no new licence (the act sheet's row 9 and note N6).

**HUMAN ACT — an agent stops and asks the owner:** setting or deleting `KIT_TRACKER_READER_CEILING`,
`KIT_TRACKER_READER_CEILING_CARD` or `KIT_TRACKER_LIVE_ROW`. The two ceiling variables exempt a writer reader from the
strict reading (builder is not ratifier); `KIT_TRACKER_LIVE_ROW` configures the live probe, and deleting it makes the probe
skip green, which switches that check off rather than delaying it. A repository admin sets them in their own terminal or on
the settings page. **Residual, stated:** no guard in the kit enforces this. An agent session that holds
repository-admin GitHub rights (for example one running under the owner's own `gh` login) can set them, and the trail is
GitHub's settings audit log; watch it for all three. The lock, agent sessions that hold no right to change repository
settings, is stated in `docs/operations/separation-of-duties.md` §Forge identity (the identity set, the credential paths an
owner login can still be reached through, and `sparkwright doctor --as agent`, which fails a session whose login holds
admin); until the switch it describes sets up, give agent sessions a GitHub identity without repository admin where you can. The per-PR trusted job only detects an over-privileged reader (its record
says `over-privileged` and it binds with a NOTICE, never refusing); only a live probe workflow fails it, and the kit ships
none to adopters (its own `tracker-live` is kit-only and runs weekly or when dispatched by hand, so there a swapped token
can bind for up to a week). Without such a workflow nothing fails it, and it binds on every PR until someone reads the NOTICE.

- **`KIT_TRACKER_TOKEN`** — always required: the service account's API token (Cloud) or Personal
  Access Token (Data Center).
- **`KIT_TRACKER_USER`** — the service account's email, required only under `auth=basic`; not needed
  under `auth=bearer` (Data Center PAT).

Success signal (read-only): `gh secret list` shows `KIT_TRACKER_TOKEN` (and `KIT_TRACKER_USER` when
`auth=basic`) among the repository secrets. An agent can run it only if its own token carries
Secrets: read (secret *names* only — values are never readable via the API); a repo-admin
credential is never an agent's. Otherwise it is a human check.

If either required secret is missing, the job's own pre-check names it and nothing else, byte-for-byte:
`::error title=tracker-board-gates: tracker credentials not configured::add the Actions secret $_missing (in the job's environment, if it declares one)`
(`profiles/adopter-tracker-gates.yml`). Fix: add the named Actions secret and re-run.

**5b. The developer's own credential — for the write verbs, never a CI secret.**
`sparkwright board claim|release|move|create|comment|rank` (`scripts/board.sh`; `list` only reads) writes with **your own**
`KIT_TRACKER_USER`/`KIT_TRACKER_TOKEN`, exported in your own shell — **never** the CI secret above
(A5, `scripts/board.sh` header: "the developer's own KIT_TRACKER_USER/TOKEN, never a CI-scoped
token"). The auth kind (`basic` or, for a Data Center PAT, `bearer`) comes from the `auth=` line of
`.kit/tracker.conf` (default `basic`), so a bearer user exports nothing for it: `board.sh` and
`board migrate` read it from the conf unless `KIT_TRACKER_AUTH` is already set in the environment.

**Store it once in the macOS login Keychain, and export nothing (SECRETS-INJECTION-AT-LAUNCH).** The adapter
(`scripts/tracker-jira.sh`) looks for the credential in this order: first the environment (the four variables
above, as a pair: if any of `KIT_TRACKER_USER`, `KIT_TRACKER_TOKEN`, `JIRA_EMAIL` or `JIRA_TOKEN` is set, the
environment is used alone and the Keychain is never read, so an exported email is never paired with a stored token);
then a login Keychain item whose **service** is `sparkwright-tracker:<host>` (the exact host as written in `base_url`
in `.kit/tracker.conf`, case-sensitive; a `base_url` with a port cannot use the Keychain item, so it stays on the
environment only), whose **account** is your email and whose **password** is the token. Run this once, in your own
terminal. **HUMAN ACT — an agent stops and asks the owner:** a human stores the token in their own terminal.

```
security add-generic-password -U -s sparkwright-tracker:<host> -a <email> -w
```

With `-w` last, `security` prompts for the token twice, so it never lands on the command line or in shell history.
**Make the item with this CLI command, not Keychain Access.app:** an item made in the app trusts only the app and would
raise a dialog on every read, while the CLI's own item lists `security` in its access list and reads silently. This is
macOS only: on Linux the environment path is unchanged.

**Which identity the item holds.** **HUMAN ACT — an agent stops and asks the owner:** a Jira site admin creates the
account, and a human mints its token signed in as that account. Store the credential your agent sessions run as: a
**dedicated agent account that is a Member of the space with no admin of any kind** (not Jira administrator, not system administrator, not space administrator (`ADMINISTER_PROJECTS`)),
and **without Delete Issues** (remove Delete from its space role; the working set of create, edit, transition and assign stays;
`--as agent` checks `DELETE_ISSUES` only, and other destructive project permissions are not probed).
This is the only credential kept in the Keychain; it is never your own admin account. Verify it with
`sh conformance/tracker-contract.sh --preflight --as agent`: that role FAILs, naming the cure, when the credential holds
`ADMINISTER`, `SYSTEM_ADMIN`, `ADMINISTER_PROJECTS` or `DELETE_ISSUES`, and its `identity` line names the account the lanes
will act as. A different identity, such as your own, stays exported in that person's own terminal, where the environment wins.
The host binding is a control: a `base_url` changed to another host looks up another service name and finds nothing, so the
token cannot be sent to a different site.

`sparkwright doctor` prints one line, `tracker credential: env - runs as <name> (<id>)`, `keychain (read for the identity check) - runs as <name> (<id>)`,
`- Jira did not accept it`, `- not reachable`, a one-sentence Keychain failure, or `none - store a token once: JIRA-SETUP-TEMPLATE §5b`.
With a credential present it makes two bounded reads of the site through the adapter (who the credential is, and which
permissions it holds; at most about 20 seconds when offline), which is why the Keychain wording says the item is read. It never
prints the token. When the credential holds an admin or delete permission the line adds `- HOLDS <list>: lanes must run as a
non-admin agent account, run --preflight --as agent` and doctor shows one warning (advisory; it never fails the build).
A locked Keychain or a pending dialog ends within 10 seconds with a message, never a hang (measured live 2026-10-12 with the dialog unanswered: 10.3 s) (a second line, 'credential (user) outside the allowed charset', may follow the timeout message; it comes from the timeout, not from a second fault).
**Honest ceiling:** this moves the exposure and does not remove it. The token leaves the session environment and your
typed exports, but while the login Keychain is unlocked, any shell that can run `security find-generic-password ... -w`
reads it silently.
**`land` closes the card where your credential is.** After the merge, `land` (and `actuate`) run
`sh scripts/board.sh release <ROW> --stale`: on a tracker that moves the card to your `state.done`
(with a claim ref held the proof is the merged PR; with none, nothing is checked and `board.sh` says UNPROVEN), proves it by post-read, and deletes the claim ref. This happens in
the shell that runs `land`, so it needs the credential above exported there. If the move fails the
merge stands (exit 0), a WARN names the one command, and the last line reads
`board: NOT CLOSED — see the WARN above`; the happy path ends `board: closed`. A merge made in the
forge UI moves nothing: run `sh scripts/board.sh release <ROW> --stale` afterwards. (`board release`
without `--stale`, the holder giving a claim back, still ends the card at `state.ready`.)

**5c. What the over-privilege probe does — detects, never blocks.**
Every credential is probed for eight permissions: five on the project (`CREATE_ISSUES`, `EDIT_ISSUES`,
`TRANSITION_ISSUES`, `ASSIGN_ISSUES`, `ADMINISTER_PROJECTS`) and three that reach beyond it (`ADMINISTER`,
`SYSTEM_ADMIN`, `DELETE_ISSUES`), so a site administrator's secret is flagged on every PR's record
(`scripts/tracker-jira.sh`'s `tj_permissions`). If a site rejects one of the three newer keys, the probe retries with the five
original ones; it then reports `over-privileged` only if `ADMINISTER_PROJECTS` is held, and otherwise `unverified` (never `ok` and
never `writer`, because the three global keys were not read: a write-capable reader on such a site records `unverified`, fail-closed
by design). Holding an admin-class key (`ADMINISTER`, `SYSTEM_ADMIN`, `ADMINISTER_PROJECTS`) or `DELETE_ISSUES` makes the probe print
`over-privileged`; holding only create, edit, transition or assign (with all four of those answered no) prints `writer`
(the record says `credential writer`, bound with its own notice; see the ceiling in §5a); the
trusted job then logs a **NOTICE and binds anyway** — byte-for-byte: `seam: NOTICE — record
credential is over-privileged for this read (binding anyway, S-11)` (`conformance/backlog-lib.sh`).
**The gate does not refuse an over-privileged credential; the adopter is the one who acts on the
NOTICE** — the kit does not, and cannot, enforce least privilege from outside the account.
A failed or unparsable probe itself prints the bare word `unverified` (`scripts/tracker-jira.sh`'s
`tj_permissions` prints exactly one of `ok` | `writer` | `over-privileged` | `unverified`); `tracker-read.sh`
then writes the record line `credential unverified` (`scripts/tracker-read.sh:~22`) and downgrades
the read's own verdict to `unverified` rather than binding (never defaults to `ok`) — **this outcome
is red**: the record never reaches `verdict bound`. The CI service account (Browse Projects only,
§5a) will probe `ok`; your own write-capable developer token (§5b) is *expected* to probe `writer` when it holds no admin-class
key and no `DELETE_ISSUES` (`over-privileged` if it holds any of them) when you run it locally — that is not a bug. The probe
checks `DELETE_ISSUES` only; other destructive project permissions (delete comments, attachments or worklogs, move issues, change
the reporter, bulk change, manage sprints) are not probed.

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
- a site-, org-, or project-admin account as the CI credential, or as the agent credential (`--as agent` FAILs on it);
- an admin token (a site administrator's, or any admin's) on disk: not in `.env`, not in a shell profile, not in the Keychain item the
  lanes read. An admin acts in the admin's own terminal, with a token exported for that command only, and never anywhere else;
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
`POST /rest/api/3/workflows` per work type of this space; a team-managed space needs only space admin) — a permission neither the CI service account
(§5a, Browse Projects only) nor an agent should ever hold. Run `--deep` **once**, by hand, in your own shell, with
an admin's own token exported in that shell only for the duration of the command — never in `.env`,
never in CI, never in an agent's shell. An agent (including the cold-test agent) runs only the base
check (no flag) and `--discover`; it never runs `--deep`.
Expect `--deep` to read `TIER: convention` for most spaces (rc 0, a supported tier): Jira's current editors offer no assignee-only restriction to add (§3).

## 6. Bind branch protection before your first PR — **HUMAN ACT — an agent stops and asks the owner**: REPLACE typed at a real terminal

This needs an admin-authenticated `gh`. `--replace` asks for the word REPLACE typed at a real terminal, resets every protection setting, and pins the repository's merges to squash-only. It writes the solo profile by default; pass `--team` for a team (`profiles/<stack>/BRANCH-PROTECTION.md`; `scripts/branch-protection-apply.sh` header).

Before opening the first PR on this repository, run `sh scripts/branch-protection-apply.sh --replace` on an unprotected `main` (the first time, after the bootstrap push); run `--apply` once `main` is protected. If the dry-run says "not protected yet", protection was never established: run `--replace`.
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
**`--deep`** to also read this space's own workflows and **report the tier** — server-enforced
(only-the-assignee on every transition into In Progress; the rule is measured to display, enforcement against a non-assignee not yet measured), the convention tier (none or only some transitions covered; a partial names what is uncovered), a FAIL only when no transition reaches In Progress or the conf's status is not a status of the space, or UNVERIFIED (§3):
`sh conformance/tracker-contract.sh --deep`
