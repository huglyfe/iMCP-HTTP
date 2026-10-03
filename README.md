# iMCP-HTTP

A native SwiftUI Mac app for owner-approved access to Apple services over MCP Streamable HTTP.

**Status: project skeleton.** The app opens a development overview and menu-bar item. It has no HTTP listener, OAuth implementation, credentials, or Apple-service access yet. The project starts private; public release is a separate owner decision.

## Direction

- Codex on the same Mac is the first client.
- OAuth approval lasts until revoked; client credentials remain independently revocable.
- Approved clients share account-wide access to globally enabled services, subject to macOS permissions.
- Reminders editing and deletion are the first service improvements.
- The initial service inventory follows iMCP; additional Mac capabilities come in later slices.

## Develop

Requires macOS 15+ and a Swift 6 toolchain with `swift format` (current Xcode Command Line Tools or Xcode). Full Xcode and signing setup will be needed for production packaging and permission acceptance.

```sh
./scripts/check.sh
open dist/iMCP-HTTP.app
```

For an optimized development bundle, run `./scripts/build-app.sh release`. Bundles are ad-hoc signed and generated under ignored `dist/`; they are not notarized releases. Open `Package.swift` in Xcode to inspect the source. Use the bundled app for later permission testing, not `swift run`.

## Project map

- [Plan](docs/PLAN.md): agreed product scope, sequence, and acceptance gates.
- [Architecture](docs/ARCHITECTURE.md): implemented skeleton and intended boundaries.
- [Requirements](docs/REQUIREMENTS.md): behavior to implement, including OAuth and Reminders.
- [Prior art](docs/INSPIRATION.md): references routed by the question being solved.
- [Agent guide](AGENTS.md): working conventions and verification.

## Attribution

Inspired by [Mattt's iMCP](https://github.com/mattt/iMCP). This repository begins as an original scaffold, not a GitHub fork or a copy of upstream source. It is independent and is not affiliated with or endorsed by iMCP or Apple. Preserve upstream notices when reusing implementation code; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

MIT licensed. No hosted account or subscription is planned.
