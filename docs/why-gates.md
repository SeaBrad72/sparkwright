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
Applies IF: you declare Confidential/Restricted data (CLAUDE.md §3)
Why: A threat model forces you to name what an attacker wants and how they'd reach it *before*
  you build, so your controls answer known risks instead of guessing. Discovering the same gap
  after a breach costs orders of magnitude more — and may be unrecoverable for the data involved.
Enforced by: conformance/privacy-ready.sh
Read more: DEVELOPMENT-STANDARDS.md §2, §14

## privacy-review
Applies IF: you handle personal data (Confidential/Restricted; CLAUDE.md §3)
Why: A DPIA-lite makes you state what personal data you hold, why, and how it's deletable —
  the difference between privacy-by-design and a regulatory finding. It is the data-subject's
  rights expressed as an engineering checklist.
Enforced by: conformance/privacy-ready.sh
Read more: DEVELOPMENT-STANDARDS.md §2

## evals
Applies IF: you add an `evals/` dir or declare an AI feature (CLAUDE.md §3)
Why: An AI feature without a recorded regression threshold has no definition of "still works" —
  quality drifts silently with every prompt or model change. Evals are to AI what tests are to
  code: the safety net that lets you change fast without shipping regressions.
Enforced by: conformance/eval-ready.sh
Read more: DEVELOPMENT-PROCESS.md §7

## agentops
Applies IF: you declare `Agentic: yes` (CLAUDE.md §3)
Why: An autonomous agent that leaves no trace can't be audited, scored, or safely granted more
  autonomy. A trace posture is the precondition for ever trusting an agent with a higher tier —
  no evidence, no promotion.
Enforced by: conformance/agentops-ready.sh
Read more: DEVELOPMENT-PROCESS.md §13

## a11y
Applies IF: you ship a user-facing UI
Why: Accessibility is not a polish step — keyboard, contrast, and screen-reader support are how
  a large fraction of users reach your product at all, and retrofitting them is far costlier than
  building them in. It is also, in many jurisdictions, a legal floor.
Enforced by: DEVELOPMENT-STANDARDS.md §14 (a11y gate)
Read more: DEVELOPMENT-STANDARDS.md §14

## dr
Applies IF: you add durable data (a database / persistent store)
Why: Backups you've never restored are a hope, not a plan. A recorded restore drill proves you
  can actually recover within your RPO/RTO — the one time you need it is the worst time to learn
  it doesn't work.
Enforced by: conformance/dr-ready.sh
Read more: DEVELOPMENT-PROCESS.md §7

## resilience
Applies IF: you add a deployable service
Why: Failure is a when, not an if. Declaring how the service degrades, retries, and recovers
  turns an outage from an incident into a non-event — and forces you to find the single points
  of failure before they find you.
Enforced by: conformance/resilience-ready.sh
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
Enforced by: conformance/provenance-precondition.sh
Read more: DEVELOPMENT-STANDARDS.md §14

## builder-not-reviewer
Applies IF: always (floor gate, every PR)
Why: The person who wrote a change is the worst-placed to see its blind spots — that's not a
  character flaw, it's how attention works. A second set of eyes is the cheapest, highest-yield
  defect filter there is, which is why builder ≠ reviewer is never waived.
Enforced by: conformance/review-lane.sh
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
