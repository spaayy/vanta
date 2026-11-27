# Security policy

If you find a security vulnerability in Vanta, report it privately so the Vanta team can fix it before the details are public.
This page explains how to report it, what to include and what Vanta covers.

## Report a vulnerability

Report a vulnerability through GitHub private vulnerability reporting.

> [!IMPORTANT]
> Don't open a public issue or discussion for a vulnerability that someone could exploit.
> Vanta makes system changes as TrustedInstaller, so public disclosure puts users at risk before a fix is out.

## What to include

- The affected component, such as Vanta Manager or a script in the Vanta package, and its version.
- The steps to reproduce the problem, with any proof of concept.
- The impact: what an attacker could do, and what access they need first.

## What happens next

The Vanta team reviews your report privately, and may ask you for more detail through the same report or email thread.
If the team confirms the vulnerability, it works on a fix and publishes a security advisory when the fix is released.
Keep the details private until then.

## Scope

Vanta covers everything it releases and builds from this repository:

- Vanta Manager, the desktop app under [`app/`](../app/)
- The reports service and its MCP server under [`services/`](../services/)
- The `Vanta.*` PowerShell framework and Vanta's other files under [`package/Executables/`](../package/Executables/) (the [architecture](../docs/architecture.md) explains the layout)
- The binaries in the Vanta package, listed in the [binary inventory](../package/Executables/VantaModules/README.md)
- The build tooling under [`tools/`](../tools/)

Vanta runs on Windows, so some issues are Microsoft's to fix.
If a vulnerability also affects the latest unmodified Windows, report it to Microsoft through the [Microsoft Security Response Center](https://www.microsoft.com/en-us/msrc/faqs-report-an-issue).

## Hardening ideas

For hardening ideas, and security weaknesses that nobody could exploit, open a regular issue or pull request.
Suggestions should keep the balance between security, performance and usability.

## Supported versions

Only the latest Vanta release receives security fixes.
Update to the latest release, and check that the problem is still there, before you report it.
