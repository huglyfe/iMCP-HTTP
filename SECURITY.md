# Security policy

iMCP-HTTP gives AI clients access to personal data, so security reports are taken seriously.

## Supported versions

Only the latest alpha on `main` receives fixes.

## Reporting a vulnerability

Please report vulnerabilities privately through [GitHub's private vulnerability reporting](https://github.com/huglyfe/iMCP-HTTP/security/advisories/new), not in a public issue. Include the version or commit, your macOS version, and steps to reproduce using synthetic data. Don't include real tokens, grant files, or Apple content.

You should get an initial response within a week. Once a fix is available, the advisory will be published with credit to you unless you'd rather stay anonymous.

## Scope

Examples of issues in scope:

- Getting a token or tool access without the owner's approval in the app
- Bypassing Host or Origin validation, or reaching the server from another machine or a web page
- Calling a disabled service or tool
- Token, refresh, or revocation flaws
- Leaking Apple content into logs, errors, or files

Approval protects against clients you haven't approved. It can't tell apart two programs that present the same name, and it can't protect you from malware already running as your macOS user. See [ARCHITECTURE.md](docs/ARCHITECTURE.md#authorization-and-storage) for the authorization design.
