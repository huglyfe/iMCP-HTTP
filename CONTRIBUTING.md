# Contributing

Thanks for your interest. iMCP-HTTP is deliberately small: one process, standard OAuth, and Apple's own frameworks as the only source of Apple data. Please open an issue to discuss new services, permission models, networking changes, or large UI changes before you start on them. Read [ARCHITECTURE.md](docs/ARCHITECTURE.md) and the relevant [tool contract](docs/REQUIREMENTS.md) first.

## Prerequisites

- macOS 15 or later
- Full Xcode with Swift 6.2 or later, with its first-launch setup completed
- Python 3.9 or later (scripts use only the standard library)

Point your shell at Xcode's toolchain, adjusting the path if needed:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Dependencies are pinned in `Package.resolved` and builds use `--force-resolved-versions`. When you upgrade a dependency, update the lockfile and review [third-party notices](THIRD_PARTY_NOTICES.md) in the same change.

## Daily workflow

```sh
# Format Swift sources and tests.
swift format format -i --recursive Package.swift Sources Tests

# Run one test suite.
swift test -j 2 --force-resolved-versions --disable-xctest --filter BluetoothTests

# Run everything CI runs: lint, repository checks, tests, app build, signature check.
./scripts/check.sh

# Build and launch a debug app (quit any running copy first).
./scripts/build-app.sh debug
open dist/iMCP-HTTP.app
```

`check.sh` passes extra arguments through to `swift test`. It builds into `.build/check/iMCP-HTTP.app` so it never replaces the app you're running; `build-app.sh` builds into `dist/`. Set `IMCP_BUILD_APP_PATH` to an absolute path to choose another location. Builds are staged in a fresh directory and verified before replacing the output, and `build-app.sh` refuses to overwrite an app that is currently running.

`scripts/check-repository.py` checks local Markdown links, version consistency, Python syntax, and accidentally committed runtime files. It is not a secret scanner.

CI runs `check.sh` on every pull request and on pushes to `main`, using macOS 15 and Xcode 26.3, once in UTC and once in America/New_York to catch timezone and DST bugs.

## Tests

Tests use Swift Testing. Use `#expect` and `#require` directly so failures show the actual values, assert exact error codes for contract failures, and give every asynchronous wait a deadline.

| Target | Covers |
| --- | --- |
| `IMCPCoreTests` | Authorization, persistence, HTTP/MCP contracts, input validation, native value mapping, scripting and BLE state. Shared fakes live in `Fixtures/`. |
| `IMCPHTTPTests` | Runtime lifecycle, approval authentication, client setup recipes |
| `ScriptExecutionTests` | Apple-event values, sanitized errors, interpreter deadlines, script compilation. Mail and Notes handlers are not executed. |
| `ClientAcceptanceTests` | Opt-in end-to-end checks with real client CLIs |

Automated tests must never touch real Apple records, initialize the Bluetooth radio, or call live Maps. Listener tests use loopback ports 19765 and 19767, so keep those free.

The client acceptance tests need `codex`, `opencode`, and a working keyring. They use temporary configuration, fake services, and disposable credentials:

```sh
IMCP_RUN_CLIENT_ACCEPTANCE=1 ./scripts/check.sh
```

Codex is exercised through login, tool calls, restart, and revocation. OpenCode is covered through registration and login only.

## Testing against real Apple services

Fixtures can't prove that EventKit, Contacts, or Mail behave the way the code expects. For changes to a service adapter, also test by hand using a separate app bundle, temporary state, and a spare port:

```sh
IMCP_BUILD_APP_PATH="$PWD/dist/iMCP-HTTP-test.app" ./scripts/build-app.sh debug
test_dir="$(mktemp -d)"
IMCP_HTTP_DATA_DIR="$test_dir" IMCP_HTTP_PORT=19875 \
  dist/iMCP-HTTP-test.app/Contents/MacOS/IMCPHTTP
```

Temporary state isolates settings and grants, but macOS permissions still belong to the app's signing identity. Don't reset your privacy settings for a test.

Work only with clearly named disposable data, such as a list called `iMCP test 2026-11-05`, and look up exact IDs instead of writing to existing lists, calendars, or mailboxes. For each operation, check the result in the Apple app itself, not just in the tool response. When you're done, delete the test records and containers, confirm they're gone, revoke the test grant, and remove the temporary client entry and state directory. Mail's scripting dictionary can't delete mailboxes, and deleted notes go to Recently Deleted, so finish those by hand.

A few areas need particular care:

- Calendar: timed and all-day events across a DST boundary, and `thisEvent` versus `futureEvents` edits on a recurring series.
- Reminders and Contacts: omitted fields are preserved, and `clear` removes only what it names.
- Bluetooth: use a peripheral you own. Never write to an unknown nearby device.
- Permissions: allow and deny flows, disabled tools rejecting stale calls, and settings surviving a restart.

For UI checks on a debug build, add `IMCP_HTTP_PREVIEW_APPEARANCE=light` or `dark` to the launch. It changes only the app's appearance and is ignored in release builds. Check both appearances at the 580 × 540 minimum window size, plus keyboard shortcuts, empty and error states, and Help.

Mention in your pull request what you tested this way and what you couldn't.

## Pull requests

Describe the behavior change, the checks you ran, and any native testing still missing. Use synthetic examples and keep tokens, grants, account names, Apple content, and unrelated screenshots out of issues and pull requests.

Contributions are accepted under Apache-2.0. If you adapt third-party code, keep its copyright and license notice and record it in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Releasing

1. Update the version in `Sources/IMCPCore/Server/MCPGateway.swift`, `App/Info.plist`, the README, and the changelog. `check.sh` fails if they disagree.
2. Run `check.sh` and build a release bundle from a clean checkout.
3. Review the diff and history being published for credentials and personal data. Generated apps, logs, runtime state, and signing material stay out of Git.
4. Review licenses against the resolved dependency graph.
5. Tag the release and publish it on GitHub as a prerelease.

Signed and notarized builds and the Homebrew cask are described in [DISTRIBUTION.md](docs/DISTRIBUTION.md). To package a local development build:

```sh
./scripts/build-app.sh release
python3 scripts/package-app.py dist/iMCP-HTTP.app --development
```

Archives and `.sha256` files go to `dist/packages/`, named with the version, build number, and architecture. Existing files are never overwritten; use `--output-dir` for a separate run. Without `--development`, the script requires an app that is already Developer ID signed, hardened, notarized, stapled, and accepted by Gatekeeper. It doesn't sign or publish anything itself.

The build generates the Finder and Dock icon from `App/AppIcon.png` with `sips` and `iconutil`.
