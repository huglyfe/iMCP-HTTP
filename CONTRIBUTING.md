# Contributing

Keep iMCP-HTTP small enough for one owner to understand and maintain. Discuss new integrations, permission models, remote networking, or large UI changes before implementation. Start with [AGENTS.md](AGENTS.md), the [architecture](docs/ARCHITECTURE.md), and the relevant [tool contract](docs/REQUIREMENTS.md).

## Prerequisites

- macOS 15 or later, full Xcode with Swift 6.2 or later, and Python 3.9 or later.
- Complete Xcode's first-launch setup. Select its toolchain for your shell with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, adjusting the path as needed.
- Dependencies are pinned in `Package.resolved`. Builds use `--force-resolved-versions`; intentional upgrades must update the lockfile and review third-party notices together.

CI uses macOS 15 with Xcode 26.3 and runs the canonical checks in UTC and America/New_York. This covers floating dates on a host whose timezone differs from the input, plus DST boundaries. Newer Xcode is usable locally; native behavior on a different macOS release still requires separate acceptance.

## Daily workflow

```sh
# Format Swift source and tests.
swift format format -i --recursive Package.swift Sources Tests

# Run a focused fixture suite.
swift test -j 2 --force-resolved-versions --disable-xctest --filter BluetoothTests

# Canonical verification: repository checks, all fixtures, build, bundle, signature, formatting.
./scripts/check.sh

# Build the app you intend to launch, after quitting its previous instance.
./scripts/build-app.sh debug
open dist/iMCP-HTTP.app
```

`check.sh` forwards additional arguments to `swift test`. Its default bundle is `.build/check/iMCP-HTTP.app`; `build-app.sh` defaults to `dist/iMCP-HTTP.app`. Either accepts an absolute output override, for example `IMCP_BUILD_APP_PATH="$PWD/dist/iMCP-HTTP-next.app"`. A fresh staging bundle avoids stale resources and is signed and verified before replacing the output. The build refuses to replace an app whose executable is running at that path.

Scripts use the system toolchain and Python standard library. There is no separate package-manager bootstrap, global configuration change, or generated project to maintain. `check-repository.py` checks local Markdown links, version consistency, Python syntax, and accidental runtime artifacts; it is not a comprehensive secret scanner. `bundle-notices.py` packages the resolved dependencies' notices and the retained component licenses.

`App/AppIcon.png` is the approved icon artwork. The build uses macOS `sips` and `iconutil` to generate standard and Retina icon sizes, then embeds `AppIcon.icns` before signing. Generated iconsets stay in the temporary build directory. The compact menu-bar status symbol remains separate from the Finder/Dock icon.

## Tests

Use Swift Testing's `#expect` and `#require` directly so failures show the expressions and actual values. Keep each test focused on a behavioral boundary. Use exact error-code assertions for permission, busy, timeout, and other contract failures. Asynchronous fixture waits must have deadlines and clean up their pending work.

- `IMCPCoreTests`: authorization, persistence, HTTP/MCP contracts, input validation, native value mapping, scripting and BLE state handling. Reusable Mail/Notes and BLE fakes live in `Fixtures/`.
- `IMCPHTTPTests`: runtime ownership/lifecycle, approval authentication, and client setup recipes.
- `ScriptExecutionTests`: typed Apple-event values, sanitized errors, interpreter deadlines, script compilation, and pure HTML helpers. These do not execute Mail/Notes handlers.
- `ClientAcceptanceTests`: opt-in external CLI checks, separate from normal unit/contract coverage.

Never run automated tests against real Apple records. Creating an EventKit model or compiling a scripting dictionary is not permission or native-service acceptance. Listener fixtures use loopback ports 19765 and 19767; keep these available when running the full suite. Runtime/authentication fixtures use fake listeners.

Optional client acceptance requires `codex`, `opencode`, and `python3` on PATH, plus a usable local keyring:

```sh
IMCP_RUN_CLIENT_ACCEPTANCE=1 ./scripts/check.sh
```

This uses temporary configuration, fake Apple services, and unique disposable credentials. Codex exercises five fake services, restart, and revocation, then logs out the test credential. OpenCode verifies registration/login and the saved grant; its tool/restart/revoke behavior is not covered. These fixtures use the native decision API with no model turns or production client configuration changes. New BLE/Mail/Notes tools are covered through the in-process authenticated MCP contract fixture.

## Native acceptance

Build to a separate path and use temporary app state and a spare port:

```sh
IMCP_BUILD_APP_PATH="$PWD/dist/iMCP-HTTP-acceptance.app" ./scripts/build-app.sh debug
acceptance_dir="$(mktemp -d)"
IMCP_HTTP_DATA_DIR="$acceptance_dir" IMCP_HTTP_PORT=19875 \
  dist/iMCP-HTTP-acceptance.app/Contents/MacOS/IMCPHTTP
```

Temporary state isolates application settings and grants; macOS permissions still belong to the signed app identity. Do not reset production privacy settings or rebuild a running bundle. Use the [native acceptance checklist](docs/PLAN.md#native-acceptance), visibly disposable records/devices, independent readback in the Apple app, and verified cleanup. Revoke temporary grants, remove temporary client entries, quit the test app, and delete only the temporary state you created afterward.

## Pull requests and reports

Describe the concrete behavior change, the checks run, and any native acceptance still missing. Use synthetic examples and metadata-only logs. Never include tokens, grants, account names, Apple content, signing material, or screenshots of unrelated data. Report the macOS/Xcode version, service/tool, expected result, and a disposable reproduction.

Original contributions are made under Apache-2.0. Preserve third-party copyright and license notices, and document any adapted code in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Do not copy a prior-art implementation merely to match its behavior.

## Preparing a source alpha

1. Update the MCP version in `MCPGateway.swift`, the numeric bundle version/build in `App/Info.plist`, and the README/changelog. Repository checks catch version drift.
2. Run canonical checks and build an optimized bundle. Verify a clean source checkout can run the documented workflow without ignored local files or research repositories.
3. Review tracked files and all history being published for credentials and personal data. Keep generated apps, logs, runtime stores, local inspiration checkouts, and signing assets out of Git.
4. Review licenses against the resolved dependency graph, including vendored components. Retain the alpha's explicit native-acceptance limitations.
5. Review the final commit and GitHub CI, then obtain the owner's explicit publication instruction before changing repository visibility or creating a public release. Mark the GitHub release as a prerelease. Source publication and signed/notarized binary distribution are separate decisions.

The [plan](docs/PLAN.md) owns remaining milestones; avoid parallel roadmaps or machine-specific operational diaries in the repository.
