# Architecture

## Implemented

One native macOS process: SwiftUI menu-bar panel/Settings, an application runtime, embedded loopback HTTP, OAuth, MCP dispatch, and native Reminders, Calendar, Contacts, Maps, and Photos adapters. `IMCPCore` contains protocol, authorization, service settings, and Apple access; it has no SwiftUI dependency. `IMCPHTTP` composes those objects and displays state.

```text
SwiftUI owner decisions / observed state
              |
          AppRuntime
              |
 Hummingbird HTTP -> OAuth grant check -> SwiftMCP -> ToolDispatcher
                      |                                 |
             private grant snapshot                Apple service adapters
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

`AuthorizationStore` serializes transitions. `grants.json` contains only credential hashes, grant IDs/timestamps, expiry, and revocation state. Save writes a private sibling, synchronizes it, and atomically renames it before publishing in-memory state. Directory permissions are 0700, grant file 0600. No recoverable app secret or database server. Invalid/mismatched stores fail closed without replacement. `services.json` records global enablement separately. Service settings also persist a set of disabled tool names. Old settings default that set to empty, preserving existing tool availability within enabled services. State is under Application Support/iMCP-HTTP; development overrides can isolate it.

## Apple services and app ownership

The app is an `LSUIElement` accessory with no main window or Dock icon. The application delegate starts the runtime at launch; opening the menu panel is not required to start the listener. The compact panel shows server/service switches and pending OAuth decisions; Settings holds tool switches, connections, and setup.

All five services start disabled. SwiftUI exposes working service toggles and current status. Individual tool switches are global across clients and accounts. Their inventory is derived from SDK metadata without constructing Apple stores or duplicating tool schemas. Changes save before the dispatcher receives the updated disabled-name set. Discovery excludes disabled tools and dispatch checks the same set before adapter access. In-flight calls may have already started. Reminders, Calendar, Contacts, and Photos request their own macOS permission only on the owner's enable action. Maps uses supplied coordinates and queries; it never requests device location. The app persists enablement after permission and settings save. Older settings retain existing Reminders enablement and default newly introduced services to false. Every approved client shares globally enabled capabilities.

Authorization changes reach SwiftUI through one bounded `AsyncStream` snapshot observer. There is no one-second UI polling, including while paused. A one-shot timer exists only for the earliest pending visible approval and is cancelled when none remain. Service permission labels refresh when the menu/Settings opens or the app becomes active; access is checked at tool dispatch regardless of UI freshness.

`AppleAccess` is the small common interface for native enablement/permission controls. Reminders and Calendar share one lazily created `EKEventStore`; Contacts has one lazy `CNContactStore`. Disabled services do not construct/query native stores. Main-actor ownership serializes native object access and writes. EventKit reminder callbacks and MapKit callbacks convert objects to Sendable value records. Photos uses lazy PhotoKit fetch results with a native fetch limit of offset + page size + one, converting only the returned page. It retains no media, library copy, or change observer. Its framework permission is read/write because PhotoKit has no read-only library authorization level; the exposed tools are read-only metadata operations.

Reminder fetches are capped at four with a 15-second timeout; Maps caps four requests with a 20-second cancellable timeout. Calendar range reads and Contacts enumeration are synchronous native operations and can briefly occupy the main actor; worker isolation is justified only if measured usage makes this a problem.

Typed SDK macros on each service's tools/models generate metadata, schemas, and dispatch. `ToolDispatcher` composes the explicit modules through the SDK's tool-provider protocol plus availability. It rejects unavailable services, disabled tools, and unknown top-level arguments; Codable inputs reject unknown nested fields and null. Adapter protocols exist for native implementations and test fakes, not dynamic plugins. No manual schema registry or generic action router.

Shared helpers cover EventKit account/list access, dates, recurrence, display alarms, validation, and deletion receipts. Reminders/Calendar/Contacts keep their own record models and mutation semantics. Fetch returns compact summaries; get returns detail. No generic success/message envelope or duplicated account metadata in item results.

Writes use exact opaque identifiers, validate before mutation, preserve omitted fields, and return the saved object. Recurring Calendar writes additionally require the original occurrence start and an explicit `thisEvent`/`futureEvents` span. Contacts fetches individual cards with `unifyResults = false`; no linked-card merge. List/group creation names an account. Native frameworks decide account support. No automatic retry or default destination.

Queries are bounded/paginated but not snapshots. Reminders uses native completion filtering then text/date filtering; fetch snapshots omit alarms/recurrence/start/URL/location and omit notes unless text search needs them. EventKit still returns the matching set before pagination. Native date pushdown remains deferred until date-only/floating/zone semantics receive native acceptance; Calendar uses a bounded native range; Contacts stops enumeration after enough matching rows plus one. No Apple query result survives a call. See requirements for exact contracts and native feature limits. Reconnect clients after changing service enablement; the stateless transport does not broadcast discovery changes.

## Packaging and evidence

`build-app.sh` builds an ad-hoc signed, unsandboxed development bundle, identity `io.github.huglyfe.imcp-http`, with Reminders/Calendar/Contacts/Photos usage descriptions and dependency notices. It does not install a service, enable login launch, alter firewall rules, configure clients, or grant macOS permission. Production signing/notarization, permission stability across upgrades, and distribution remain unverified.

Automated evidence includes authorization/persistence failures, HTTP protocol boundaries, dispatch/date validation, exclusive app-state ownership, and an opt-in real Codex CLI 0.160.0 login/typed Reminders, Calendar, Contacts, Maps, Photos fixture/restart/revoke test. The Codex fixture invokes the native decision API directly, uses a unique temporary credential, and creates no model turn. Native clicks and Apple-data acceptance remain manual gates. No automated test reads or mutates real Apple records or calls live Maps. Unsaved value objects, fake adapters, and isolated OAuth state verify the contracts without permission prompts.
