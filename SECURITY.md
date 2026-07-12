# Security Policy

## Reporting a vulnerability

**Security contact:** GitHub private vulnerability reporting — this repo → **Security** → **Report a vulnerability**.

**Fallback (if private reporting isn't enabled):** open a public issue titled `security: request private contact` with **no vulnerability details**, and a maintainer will reply with a private channel within 2 business days. (Maintainers: enable GitHub Private Vulnerability Reporting on the repo before publishing so the primary channel is live.)

Please report privately; do not open a public issue with details for a suspected vulnerability.

## What to expect
- **Acknowledgement:** within 2 business days.
- **Triage + severity:** within 5 business days (severity model per `DEVELOPMENT-PROCESS.md` incident guidance).
- **Fix / mitigation:** prioritized by severity; coordinated-disclosure timeline agreed with the reporter.
- **Credit:** reporters who follow coordinated disclosure are credited (opt-out respected).

## Supported versions
The current `main` and the latest tagged release are supported. Older releases are best-effort.

## Scope
In scope: the kit's own scripts, conformance checks, templates, and docs. Out of scope: third-party
dependencies (report upstream) and the inert reference pipelines under `profiles/` (they are copy-and-adapt
templates, not a deployed surface).
