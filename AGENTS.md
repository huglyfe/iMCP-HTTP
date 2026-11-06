# iMCP-HTTP

iMCP-HTTP is a native Mac app that exposes Apple services (Reminders, Calendar, Contacts, Photos, Maps, Bluetooth LE, Mail, Notes) to AI clients through a local MCP server over HTTP. Clients authenticate with standard OAuth, and the Mac's owner approves each one in the app.

This file helps coding agents work in the repository. Treat it as a set of good defaults. The developer's instructions override anything here.

## What we don't compromise on

### 1. The owner approves every client

OAuth with PKCE and native approval is the only way in. Never add trust by client name, an unauthenticated fallback, a shared API key, or a custom pairing exchange. Service and tool switches are global and apply to every approved client. Approval is account-wide for enabled capabilities; there are no per-list or per-client permission editors.

### 2. Apple's data stays in Apple's frameworks

Adapters call EventKit, Contacts, PhotoKit, MapKit, CoreBluetooth, and the Mail and Notes scripting dictionaries directly. No mirror database, no private stores, no Full Disk Access. Query results don't outlive the call that produced them.

### 3. Small enough for one person to understand

One app process owns the window, the menu-bar panel, the listener, and the Apple permissions. Closing the window keeps the server running; Quit stops it. Don't add a daemon, CLI proxy, tunnel, hosted relay, or remote listener without a concrete requirement and the maintainer's agreement.

### 4. Honest about what's verified

Fixture tests prove contracts, not native behavior. The README's status table says what has been checked against real Apple data. Don't claim more than that, and update it when manual testing changes what is known.

## A small glossary

- **owner** means the person whose Mac and Apple accounts the app exposes.
- **client** means an MCP client such as Codex or Claude Code that connects over OAuth.
- **grant** means one approved client connection, with its own access and refresh tokens. Revoking it blocks later calls.
- **service** means one Apple integration (Reminders, Mail, and so on). **tool** means one MCP tool within it. Both have owner-controlled switches.
- **adapter** means the code that turns a tool call into Apple framework calls.
- **runtime** means `AppRuntime`, which owns the listener, authorization store, and service state that the SwiftUI views observe.
- **native testing** means manually exercising a service against real Apple apps with disposable data, as described in CONTRIBUTING.md.

## Three things to protect

1. **Real Apple data.** Automated tests never read or change real reminders, events, contacts, mail, notes, or photos, never initialize the Bluetooth radio, and never call live Maps. Native testing uses clearly named disposable records and confirms their cleanup.
2. **The owner's install.** `~/Library/Application Support/iMCP-HTTP` holds real grants and settings. Don't run against it, delete it, or reset macOS privacy permissions. Use `IMCP_HTTP_DATA_DIR`, a spare `IMCP_HTTP_PORT`, and a separate `IMCP_BUILD_APP_PATH` bundle. Don't install or reconfigure production client integrations during development.
3. **Secrets and personal content.** Never commit credentials, authorization codes, tokens, signing keys, account data, runtime stores, or logs. Log operation metadata, never Apple content or request bodies.

## Hit every surface

A change that works on the path you tested is often missing somewhere else. Before calling work done, check which of these apply:

- **App surfaces.** The main window and the menu-bar panel both show server status and service controls. Paused, disabled, and permission-denied states need to look right in both.
- **Tool gating.** Discovery hides disabled tools and dispatch rejects them. A new tool needs both, plus its switch in Services.
- **Reverse paths.** Enable needs disable, approve needs revoke, and a write needs a way to inspect its result. An interrupted write reports an uncertain outcome instead of retrying.
- **Contracts.** Inputs, outputs, and error codes are specified in `docs/REQUIREMENTS.md`. Change the contract and the implementation together.
- **Docs.** Check the README's service table and status table, the CHANGELOG, and HELP.md when behavior changes.

## Verifying

- `./scripts/check.sh` runs what CI runs: formatting lint, repository checks, script tests, all Swift tests, an app build, and signature verification. Run it before you finish.
- While iterating, run one suite: `swift test -j 2 --force-resolved-versions --disable-xctest --filter ReminderTests`.
- Format with `swift format format -i --recursive Package.swift Sources Tests`.
- Use Swift Testing. Use `#expect` and `#require` directly, assert exact error codes, and give every asynchronous wait a deadline.
- Test behavior that can break: authorization, persistence, HTTP and MCP contracts, input validation, date and recurrence mapping, and the logic a bug fix changed. Don't add tests that restate constants, placeholders, or what the type system already guarantees.
- Extend an existing suite or fixture before adding a new one. Reusable fakes live in `Tests/IMCPCoreTests/Fixtures`.
- For a bug, write the test that fails for that reason first, then fix it.
- When you finish, say which native testing is still unverified.

## Pull requests

- Don't open a PR, push, tag, publish a release, or change repository visibility unless the maintainer asks.
- Commit titles are short imperative summaries.
- The PR body states the behavior change, the checks you ran, and any native testing still missing. UI changes include before and after screenshots in light and dark appearance.
- Use synthetic examples. No tokens, account names, or Apple content in PRs, issues, or screenshots.

## Documentation

- `README.md` is for users: what the app does, how to build and connect, and what is verified.
- `docs/REQUIREMENTS.md` holds the product contracts, which describe intended behavior. `docs/ARCHITECTURE.md` describes how they are implemented and the platform limits. Keep the two distinct.
- `CONTRIBUTING.md` owns the developer workflow and the native testing procedure. `docs/HELP.md` covers setup and troubleshooting for users. `docs/DISTRIBUTION.md` covers signed releases.
- When a documented decision changes, rewrite the affected text rather than appending a new account of it.
- Use relative paths, portable instructions, and synthetic examples. Machine-specific notes stay out of the repository.

## Plans and work artifacts

- Don't commit implementation plans, research notes, or agent scratch files.
- Optional checkouts of reference projects belong in the gitignored `inspiration/` directory. Check the license at a pinned revision before reusing any code, and record adapted code in `THIRD_PARTY_NOTICES.md` with its license in `LICENSES/`. Copying a design idea or interaction doesn't require attribution; copying code does.
- Record notable changes in `CHANGELOG.md`.

## How it works

Hummingbird accepts a request on `127.0.0.1:18765`, and `LocalServer` validates `Host` and `Origin` and serves the OAuth endpoints. MCP requests carry a bearer token that the `AuthorizationStore` actor checks against its grant snapshot. `MCPGateway` hands authenticated requests to SwiftMCP, which decodes JSON-RPC and calls `ToolDispatcher`. The dispatcher rejects unavailable services and disabled tools, then calls the service's adapter, which reads or writes through the Apple framework and returns typed value records. The transport is stateless: no sessions, no server push.

New access requests appear in the app. `AppRuntime` confirms each approval with LocalAuthentication before the authorization actor issues a code. Details are in `docs/ARCHITECTURE.md`.

## Where code lives

- `Sources/IMCPCore` contains everything except UI, with no SwiftUI dependency.
  - `Server/` has the listener, OAuth endpoints, approval page, MCP gateway, and tool dispatcher.
  - `Authorization/` has registration, grants, token rotation, and atomic persistence.
  - `Reminders/`, `Calendar/`, `Contacts/`, `Photos/`, `Maps/`, `Bluetooth/`, `Mail/`, and `Notes/` each hold one service's models, tools, and native adapter. Mail and Notes include their bundled AppleScript.
  - `Automation/` runs the fixed Mail and Notes scripts with typed arguments and deadlines.
  - `Shared/` has permission access, date handling, EventKit helpers, and input validation.
- `Sources/IMCPHTTP` is the SwiftUI app: `AppRuntime`, the window and menu-bar views, owner authentication, and client setup recipes.
- `Tests/` has the two test targets plus client acceptance fixtures in `Tests/Fixtures`.
- `scripts/` has `check.sh`, the app builder, packaging, and repository checks. They use only the system toolchain and the Python standard library.

## Taste

- Keep transport, authorization, dispatch, and service access separable. Extract a protocol only when a real implementation or test needs it.
- SwiftUI displays runtime state and submits owner decisions. Core code never depends on SwiftUI bindings.
- Tool schemas come from SwiftMCP's typed macros. Don't add a manual schema registry, a generic action router, or a success/message envelope.
- Writes use exact identifiers and explicit destinations. No default destination, and no automatic retry of a write whose outcome is uncertain.
- Native objects stay on the main actor; only `Sendable` value records leave an adapter.
- Measure before optimizing a native query, and do it with disposable data.
- Default to no comment. Write one for a constraint, an Apple quirk, or an invariant the code can't show.
- Validate external input at the boundary and trust guarantees established inside the system.
- If a rule here fights the task in front of you, say so and get the maintainer's sign-off before breaking it.
