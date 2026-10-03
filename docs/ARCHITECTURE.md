# Architecture

## Implemented

One native macOS process: SwiftUI main window/menu bar, an application runtime, embedded loopback HTTP, OAuth, MCP dispatch, and an EventKit Reminders adapter. `IMCPCore` contains protocol, authorization, service settings, and Apple access; it has no SwiftUI dependency. `IMCPHTTP` composes those objects and displays state.

```text
SwiftUI owner decisions / observed state
              |
          AppRuntime
              |
 Hummingbird HTTP -> OAuth grant check -> SwiftMCP -> ToolDispatcher
                      |                                 |
             private grant snapshot                EventKitReminders
                      |                                 |
                native consent                     Apple frameworks
```

## Selected libraries

SwiftMCP 1.13.0 provides JSON-RPC models/decoding, protocol negotiation, MCP dispatch, metadata, schemas, and tool results/errors. Hummingbird 2.27.0 provides HTTP parsing, listener lifecycle, connection/body limits, and URL-encoded form decoding. HTTPTypes 1.8.0 and Logging 1.15.1 are explicitly declared because the adapter imports them. `Package.resolved` pins the full dependency graph.

The released official Swift MCP SDK 0.12.1 was tested against Codex's `experimental: {"codex/auth-change": {}}` initialize payload and rejected it because its capability values are strings. SwiftMCP accepts it. No dependency fork or inbound payload rewriting is required.

SwiftMCP's Server and OpenAPI traits are disabled. Its Client trait is enabled because version 1.13.0's `@MCPServer` macro always generates a typed client, even with `generateClient: false`. This uses the supported SDK surface without a fork; the application does not instantiate that client or launch subprocesses. Its built-in transport's cached session authorization and synchronous authorization callback do not fit this app's durable native approval actor. A small stateless adapter joins the SDK to Hummingbird and authenticates every request. It advertises no tool-list notifications because this transport cannot deliver them. There is no extra proxy, daemon, legacy SSE endpoint, custom JSON-RPC decoder, or Apple-data mirror.

CryptoKit supplies SHA-256 and Security supplies secure random bytes. The S256 helper is adapted with the upstream license retained; see notices. Authorization policy and native consent are app code; no library is assumed to provide a native authorization server.

## HTTP and MCP

- Bind `127.0.0.1:18765`; issuer `http://127.0.0.1:18765`; resource `/mcp`. The real Codex acceptance test proves this same-Mac HTTP profile. It is not a remote-deployment design.
- Exact Host validation; supplied Origin must equal issuer. Native requests without Origin work. No CORS grant.
- Stateless Streamable HTTP: authenticated POST with JSON response; accepted notifications return 202; GET/SSE returns 405. No resumable sessions, server-initiated requests, subscriptions, or asynchronous job protocol.
- SwiftMCP negotiates `2025-11-25`, `2025-06-18`, or `2025-03-26`. Present `MCP-Protocol-Version` headers must name a supported version. Each request binds a fresh SDK `Session` context to the HTTP version (missing header defaults to `2025-03-26`), so output schemas and structured results follow that version. Initialization still negotiates from its body. Body `_meta` cannot override the HTTP version. The context is discarded after the request; no session IDs or shared request table are exposed.
- Limits: 32 connections, HTTP idle timeout 10 seconds, 16 KiB aggregate headers, 8 KiB individual header/URI, 64 headers, 64 KiB MCP body, 8 KiB token body. HTTP parsing stays in Hummingbird/NIO.
- Responses prohibit caching and referrer leakage; approval HTML denies embedded resources/framing. No access/request/Apple-content logger.
- App startup reports Running only from the listener's ready callback. Bind errors remain errors. Address reuse permits immediate restart after socket shutdown, without enabling port sharing. A state-directory lease prevents multiple app writers even while paused.

The version fallback follows the [2025-11-25 Streamable HTTP specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#protocol-version-header).

## Authorization and storage

One public pre-registered client, `codex`, with no client secret. Only canonical `http://127.0.0.1:<ephemeral-port>/callback` is accepted (ports 1024–65535, excluding the listener). Client IDs are display labels, not proof of which executable initiated a request. The owner approves only a login they started.

Public metadata advertises the authorization/token endpoints, S256, the `apple-services` account-wide scope, and issuer response validation. `/authorize` creates a pending native request; `/approval` polls only for the result. Neither endpoint can approve it. The UI calls the authorization actor's decision method; callbacks include `state` and `iss` on approval and denial. No arbitrary client-metadata fetching or dynamic registration.

Pending approvals expire after three minutes; codes after one minute. Codes are single use, hashed in memory, and bound to client/callback/resource/PKCE. Limits: eight pending requests, eight codes, ten authorization attempts per minute, and 64 active grants. Restart/pause drops pending requests and codes.

Each grant has independent opaque access and refresh tokens. Access expires after 15 minutes. Refresh rotates both credentials, invalidating the previous access token; replay of one of the last 128 refresh hashes revokes that grant family. Older refresh tokens still fail but cannot identify the family. Revocation rejects subsequent bearer requests and refresh. It cannot undo a completed or already-started mutation.

`AuthorizationStore` serializes transitions. `grants.json` contains only credential hashes, grant IDs/timestamps, expiry, and revocation state. Save writes a private sibling, synchronizes it, and atomically renames it before publishing in-memory state. Directory permissions are 0700, grant file 0600. No recoverable app secret or database server. Invalid/mismatched stores fail closed without replacement. `services.json` records global enablement separately. State is under Application Support/iMCP-HTTP; development overrides can isolate it.

## Reminders and app ownership

Reminders starts disabled. Enable requests full EventKit access using the bundled usage description; the preference is persisted only after successful permission and settings save. Permission/enablement are rechecked on each operation, so stale client tool lists cannot bypass disablement. Reconnect clients after enabling to refresh discovery; this initial stateless transport does not broadcast changes.

The main actor owns EventKit objects and serializes mutations. Framework fetch callbacks produce Sendable snapshots before returning to that actor. Fetches are cancellable, capped at four, and time out after 15 seconds. Other services have no adapters or advertised tools.

`ReminderTools` uses SDK macros on typed functions/models to derive metadata, input/output schemas, and dispatch. `ToolDispatcher` owns availability enforcement and rejects unknown top-level arguments; Codable inputs reject unknown nested fields and explicit null. Clearing uses an explicit field list. There is no separate manual tool registry.

Read/create/edit/complete/reopen/move/delete use exact opaque identifiers. Patches validate before writing and refresh the target first. No retry or redirection to a default list. The same small date object is used on input/output, preserving date-only, floating, and named-zone semantics. Queries resolve the clock/timezone once, use native completion predicates, then filter text/dates and sort before paging. No Apple query result survives the call. See the requirements for the full tool contract and unavoidable concurrent-edit limitations.

## Packaging and evidence

`build-app.sh` builds an ad-hoc signed, unsandboxed development bundle, identity `io.github.huglyfe.imcp-http`, with a Reminders full-access usage description and dependency notices. It does not install a service, enable login launch, alter firewall rules, configure clients, or grant macOS permission. Production signing/notarization, permission stability across upgrades, and distribution remain unverified.

Automated evidence includes authorization/persistence failures, HTTP protocol boundaries, dispatch/date validation, exclusive app-state ownership, and an opt-in real Codex CLI 0.160.0 login/typed-query/fixture-move/restart/revoke test. The Codex fixture invokes the native decision API directly, uses a unique temporary credential, and creates no model turn. Native clicks and Apple-data acceptance remain manual gates. No automated test reads or mutates real reminders.
