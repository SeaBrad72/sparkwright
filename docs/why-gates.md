# Why these gates exist

Sparkwright *enforces* gates automatically — but a gate you don't understand is a gate you
resent. This page explains the **why** behind each one: what risk it answers and why paying
the cost now is cheaper than paying it in production.

**This page adds no enforcement and waives nothing.** Every gate below activates automatically
the moment its trigger appears, whether or not you read this. The rationale here is synthesized
from the authoritative standards — each block's *Read more* points back to the canonical text.

Query any entry from the CLI: `sparkwright explain <topic>` (or `sparkwright explain --list`).

---

## threat-model
Applies IF: a change touches a sensitive OR regulated-data surface — diff-relative and DECLARATION-INDEPENDENT, so it fires whether or not you ever wrote a Data classification line. Sensitive (unchanged since HITL-1): any path containing secret, auth, password or payment, anything under migrations/, and any .env file. Regulated data (HITL-5): pii, gdpr, patient, cardholder, phi, ssn, personal-data — the acronyms and tokens are case-insensitively matched, so src/PHI_export.ts, data/PATIENT_EXPORT.csv and db/CARDHOLDER_DATA.sql all trigger; phi and ssn are SEGMENT-ANCHORED (/phi/, phi_, _phi, -phi) because a bare *phi* matched 982 paths in a 162k-file corpus. Known misses, both directions: it is a PATH heuristic, so src/models/user.rb holding PII is N/A, and an ALL-CAPS PERSONAL-DATA/ directory is N/A (personal-data is cased per word, not per letter); against that, camelCase collisions DO trigger (…OpenApiIn… contains piI) and about-philosophy.tsx matches -phi — the fail-safe posture is deliberate, because for regulated data over-triggering beats under-triggering. RENAMES ARE FOLLOWED: the change-set derivation turns git's default rename detection OFF, so a file MOVED off a sensitive path still triggers on its source path — before that, a git mv in the same PR emitted only the destination and silently derived N/A (measured: an edit to svc2/pii/export.py FAILed in place and the same edit moved to svc2/core/export.py read N/A). You ALSO owe a threat model project-wide if you declare Confidential/Restricted data (CLAUDE.md §3); that separate, declaration-triggered obligation is readiness.sh privacy-ready and the two compose rather than collide.
Why: A threat model forces you to name what an attacker wants and how they'd reach it *before*
  you build, so your controls answer known risks instead of guessing. Discovering the same gap
  after a breach costs orders of magnitude more — and may be unrecoverable for the data involved.
  The declaration path alone was not enough: a project that never recorded a data classification stayed
  N/A while a PR *introduced* PII handling, so the gate is now diff-relative as well — a change-set on a
  sensitive or regulated surface with no filled THREAT-MODEL fails. Honest ceiling: it proves a filled
  record EXISTS for a triggered change — not that it is fresh for this change, nor that the analysis is
  sound (review backstops both).
Enforced by: conformance/threat-obligation.sh (diff-relative, per-change) and conformance/readiness.sh privacy-ready (project-level, declaration-triggered)
Read more: DEVELOPMENT-STANDARDS.md §2, §14, templates/THREAT-MODEL-TEMPLATE.md

## privacy-review
Applies IF: you handle personal data (Confidential/Restricted; CLAUDE.md §3)
Why: A DPIA-lite makes you state what personal data you hold, why, and how it's deletable —
  the difference between privacy-by-design and a regulatory finding. It is the data-subject's
  rights expressed as an engineering checklist.
Enforced by: conformance/readiness.sh privacy-ready
Read more: DEVELOPMENT-STANDARDS.md §2

## evals
Applies IF: you add an `evals/` dir or declare an AI feature (CLAUDE.md §3)
Why: An AI feature without a recorded regression threshold has no definition of "still works" —
  quality drifts silently with every prompt or model change. Evals are to AI what tests are to
  code: the safety net that lets you change fast without shipping regressions.
Enforced by: conformance/readiness.sh eval-ready
Read more: DEVELOPMENT-PROCESS.md §7

## agentops
Applies IF: you declare `Agentic: yes` (CLAUDE.md §3)
Why: An autonomous agent that leaves no trace can't be audited, scored, or safely granted more
  autonomy. A trace posture is the precondition for ever trusting an agent with a higher tier —
  no evidence, no promotion.
Enforced by: conformance/readiness.sh agentops-ready
Read more: DEVELOPMENT-PROCESS.md §13

## a11y
Applies IF: a change touches a user-facing UI surface — the components/views/pages/screens/ui/frontend/styles directories (repo-root or nested), or a UI/view-template markup file (.tsx .jsx .vue .svelte .css .scss .less .html .htm .j2 .jinja .jinja2 .erb .hbs .handlebars .ejs .twig .pug .haml .slim .liquid .mustache .astro .njk .tmpl .gohtml .templ .tpl .cshtml .razor .jsp .jspx .ftl .heex .eex). A bare templates/ directory is deliberately NOT a trigger (Helm/CloudFormation use it). Known misses, both directions: config templates sharing a markup extension are excused only where they are ENUMERATED — an exclusion list of compound suffixes (.conf.j2 .cfg.j2 .yaml.j2 .yml.j2 .conf.erb .ini.erb .conf.tpl .yaml.tpl .yml.tpl .sh.tpl) plus _-prefixed Helm partials (templates/_helpers.tpl), all evaluated BEFORE the surface globs, so Ansible nginx.conf.j2 and Helm _helpers.tpl are N/A. The residual is a CLASS, not a case, and it still triggers: any compound suffix not on that list (.json.tpl .sh.erb .ini.j2 .env.tpl .yml.erb), and a bare <name>.tpl with no inner extension (Terraform user_data.tpl) — which is indistinguishable by path from a Smarty view template and so could not be excluded even in principle. The list is the mainstream cases, deliberately not exhaustive: for an exclusion, ADDING is the dangerous direction. In the other direction, server-rendered .php/.blade.php, Android res/layout/*.xml, and unlisted engines (.vm/.st/.dust) do NOT trigger. Renames are followed (rename detection is off in the derivation), so a UI file MOVED out of a UI directory still triggers on its source path.
Why: Accessibility is not a polish step — keyboard, contrast, and screen-reader support are how
  a large fraction of users reach your product at all, and retrofitting them is far costlier than
  building them in. It is also, in many jurisdictions, a legal floor. Riding the obligation engine, a
  UI-surface change with no filled A11Y-SIGNOFF at the repository root fails the gate, so the WCAG 2.1 AA
  audit is evidenced, not assumed. Honest ceiling: it proves a filled sign-off EXISTS — not that the audit
  was performed competently, that its pass/fail verdicts are truthful, or that the record is FRESH for
  this change (one committed record satisfies every later UI PR; the record carries a Date and a story
  link so review can judge staleness). "Filled" is coarse — but not trivially faked: an empty, sub-floor
  or heading-less record fails the engine's substance floor. Eight lines of prose under a heading passes.
Enforced by: conformance/a11y-obligation.sh
Read more: DEVELOPMENT-STANDARDS.md §14, templates/A11Y-SIGNOFF-TEMPLATE.md

## uat
Applies IF: a change touches a user-facing taste surface — the components/views/pages/screens/ui/frontend/styles directories (repo-root or nested), or a UI/view-template markup file (.tsx .jsx .vue .svelte .css .scss .less .j2 .jinja .jinja2 .erb .hbs .handlebars .ejs .twig .pug .haml .slim .liquid .mustache .astro .njk .tmpl .gohtml .templ .tpl .cshtml .razor .jsp .jspx .ftl .heex .eex). A bare templates/ directory is deliberately NOT a trigger (Helm/CloudFormation/cookiecutter use it). Known misses, both directions: config templates and non-view files sharing a markup extension DO trigger (Ansible nginx.conf.j2, mypyc's module_shim.tmpl); .html/.htm do NOT — the one deliberate divergence from a11y, because semantic HTML is an accessibility surface but a raw .html edit is not necessarily a change of *taste*, which also means app/templates/index.html is gated for a11y and N/A here — and neither do unlisted engines (.mako .vm .st .dust). Renames are followed (rename detection is off in the derivation), so a taste-surface file MOVED out of a UI directory still triggers on its source path.
Why: Automated tests prove a UI *works*; they cannot prove a human *accepts* it. A UAT sign-off is the
  recorded moment someone with standing exercised the surface and judged it fit — the taste half of "done"
  that green pixels alone never capture. Riding the obligation engine, an unfilled or absent record on a
  taste-surface change fails the gate, so acceptance is evidenced, not assumed. Honest ceiling: it proves a
  filled record exists, not that the reviewer's taste was sound (review backstops that).
Enforced by: conformance/uat-obligation.sh
Read more: DEVELOPMENT-PROCESS.md §9, DEVELOPMENT-STANDARDS.md §14

## dr
Applies IF: you add durable data (a database / persistent store)
Why: Backups you've never restored are a hope, not a plan. A recorded restore drill proves you
  can actually recover within your RPO/RTO — the one time you need it is the worst time to learn
  it doesn't work.
Enforced by: conformance/readiness.sh dr-ready
Read more: DEVELOPMENT-PROCESS.md §7

## resilience
Applies IF: you add a deployable service
Why: Failure is a when, not an if. Declaring how the service degrades, retries, and recovers
  turns an outage from an incident into a non-event — and forces you to find the single points
  of failure before they find you.
Enforced by: conformance/readiness.sh resilience-ready
Read more: DEVELOPMENT-STANDARDS.md §14

## deployable
Applies IF: you add a Dockerfile or a deploy workflow
Why: "Works on my machine" is where outages are born. A declared, reproducible release posture
  (build, config, health, rollback) is what makes a deploy boring — and boring deploys are the
  goal.
Enforced by: conformance/deployable-ready.sh
Read more: DEVELOPMENT-PROCESS.md §10

## container-supply-chain
Applies IF: you add a Dockerfile
Why: Your image is only as trustworthy as what's inside it. An image SBOM plus build provenance
  lets you answer "are we affected?" the day the next critical CVE drops — without it, you're
  grepping Dockerfiles under incident pressure.
Enforced by: conformance/container-supply-chain.sh
Read more: DEVELOPMENT-STANDARDS.md §14

## secret-scan
Applies IF: always (floor gate, every project)
Why: A committed secret is leaked the instant it's pushed — git history is forever and public
  mirrors are instant. Scanning every push catches the mistake before it becomes a rotation
  scramble and an audit finding.
Enforced by: DEVELOPMENT-STANDARDS.md §14 (secret-scan gate)
Read more: DEVELOPMENT-STANDARDS.md §2, §14

## sbom-provenance
Applies IF: always (floor gate; image provenance gated on repo visibility)
Why: An SBOM is the bill of materials that turns "do we use log4j?" from a multi-day audit into
  a one-line query, and provenance proves an artifact came from your pipeline and wasn't swapped.
  Together they are how you survive a supply-chain attack instead of being its vector.
Enforced by: conformance/provenance-precondition.sh (wired in the kit's own CI; ships to you to run or wire)
Read more: DEVELOPMENT-STANDARDS.md §14

## builder-not-reviewer
Applies IF: always (floor gate, every PR)
Why: The person who wrote a change is the worst-placed to see its blind spots — that's not a
  character flaw, it's how attention works. A second set of eyes is the cheapest, highest-yield
  defect filter there is, which is why builder ≠ reviewer is never waived.
Enforced by: conformance/review-lane.sh (wired in the kit's own CI; ships to you to run or wire)
Read more: DEVELOPMENT-PROCESS.md §12

---

*Beyond the gates, a few core **process terms** you'll meet in `START-HERE.md` — also queryable via
`sparkwright explain <topic>`:*

## autonomy-tier
Applies IF: always — every change is classified by risk × reversibility before an agent acts (CLAUDE.md, Agent governance)
Why: An agent's freedom should scale with how much a mistake costs and how hard it is to undo. Low-risk,
  reversible work runs autonomously; irreversible or high-blast-radius actions (prod deploy, data
  migration, money) stay human-gated. Tiering autonomy by risk is what lets you grant speed where it's
  cheap and keep a hand on the wheel where it isn't — and autonomy is *earned* by metrics, not assumed.
Enforced by: conformance/agent-autonomy.sh
Read more: DEVELOPMENT-PROCESS.md §13

## intent-owner
Applies IF: always — every feature names the human who accepts it (the ratifier)
Why: Agents propose; a human ratifies. Someone must own "is this actually what we want?" — the call no
  gate can make for you. Naming the intent owner up front means a change always has an accountable human
  behind its *purpose*, separate from whoever (or whatever) built it. It is the human half of "agents
  propose, humans ratify".
Defined in: DEVELOPMENT-PROCESS.md §2 (roles) + §12 (ratification) + CLAUDE.md (working style)
Read more: docs/operations/review-lane.md

## wip-limit
Applies IF: always — pull-based flow caps how much work is in progress at once
Why: Starting is easy; finishing is what ships. A WIP limit lets you pull the next item only when
  capacity frees up, so bottlenecks surface instead of hiding behind a pile of half-done work, and
  context-switching (the silent tax on quality) drops. It is the Kanban core the kit keeps after
  dropping story points and sprints — flow over throughput theater.
Defined in: DEVELOPMENT-PROCESS.md §4 (the loop) + §12 (multi-agent coordination)
Read more: DEVELOPMENT-PROCESS.md
