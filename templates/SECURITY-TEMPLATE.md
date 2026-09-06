# Security Policy

> **Template.** Inception stamps this as your project's `SECURITY.md`, replacing the kit's own. The contact below is a real DEFAULT, not a placeholder — but it is only live once you **enable private vulnerability reporting** on your repo (Settings → Code security). Switch it for a security mailbox if that is what your org runs, then delete this line.

## Reporting a vulnerability

**Security contact:** GitHub private vulnerability reporting — this repo → **Security** → **Report a vulnerability**.

**Channel repo:** `[owner/repo]` — verified live by `conformance/security-channel-live.sh`.

**Fallback (if private reporting isn't enabled yet):** open a public issue titled `security: request private contact` with **no vulnerability details**, and a maintainer will reply with a private channel.

Please report security vulnerabilities **privately** — do not open a public issue with details.
Alternatives, if your org runs one:
- a dedicated security mailbox (e.g. `security@your-org.example`), or
- a `.well-known/security.txt` contact for the deployed service.

## What to expect

<!-- These response times are DEFAULTS, and they are a public promise the moment you ship this file.
     Adjust them to what you can actually meet, or delete this section. This comment survives Inception's
     template-banner strip on purpose, so the commitment never becomes invisible boilerplate. -->

- **Acknowledgement:** within **2 business days**.
- **Triage + severity:** within **5 business days** (we use the §-severity model in `RUNBOOK.md`).
- **Fix / mitigation:** prioritized by severity; coordinated-disclosure timeline agreed with the reporter.
- **Credit:** we credit reporters who follow coordinated disclosure (opt-out respected).

## Supported versions
| Version | Supported |
|---------|-----------|
| latest `main` / current release | ✅ |
| older releases | best-effort / per support policy |

## Scope
In scope: this project's own code + deployed surfaces. Out of scope: third-party dependencies
(report upstream; we track via `gate-dep-scan`) and findings requiring privileged local access.
