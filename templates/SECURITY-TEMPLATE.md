# Security Policy

> **Template.** Copy to your project root as `SECURITY.md` (Inception scaffolds it).
> Replace the `[security-contact]` placeholder with a real reporting channel before shipping.
> Delete this blockquote once filled.

## Reporting a vulnerability

**Security contact:** [security-contact]

Please report security vulnerabilities **privately** — do not open a public issue. Preferred
channels (use whichever your org runs):
- **GitHub private vulnerability reporting** (repo → Security → "Report a vulnerability"), or
- a dedicated security mailbox (e.g. `security@your-org.example`), or
- a `.well-known/security.txt` contact for the deployed service.

## What to expect
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
