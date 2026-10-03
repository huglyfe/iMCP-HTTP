# Architecture

## Implemented today

Two Swift Package Manager targets, no external dependencies:

- `IMCPCore`: stable names for the planned Apple-service inventory. No data access or network behavior.
- `IMCPHTTP`: SwiftUI main window and menu-bar item. It displays development status honestly.

`App/Info.plist` gives the development bundle its own identity: `io.github.huglyfe.imcp-http`. `scripts/build-app.sh` creates an ad-hoc signed `.app`. It has no production signing configuration or permission entitlements. `scripts/check.sh` checks Swift formatting, shell syntax, compilation, bundle metadata, signature, and whitespace. There are no behavioral tests yet because no server behavior exists.

## Intended structure as behavior arrives

```text
SwiftUI window / menu bar
        | owner decisions and observed state
App runtime (lifecycle and composition)
        |
Embedded HTTP + MCP adapter
        |
Authorization -> tool dispatcher -> Apple service adapters
        |                              |
Local grant/credential store       Apple frameworks
```

The diagram is a set of responsibilities, not a mandate for one target per box. Begin with folders in the existing targets; split packages only when concrete coupling or testing needs justify it.

## Ownership

- The app runtime owns the listener, service instances, startup, and shutdown.
- Authorization owns pending consent, client grants, token exchange, and revocation. The UI cannot mint trusted client identity from a name.
- The dispatcher owns registered tool lookup and global enablement checks; all transports use it.
- Each Apple adapter owns framework access and mutation serialization where needed. It returns typed results without UI references.
- Apple frameworks own calendars, reminders, contacts, and other user data. Do not mirror their databases.
- A single local store will own grant/revocation facts. Select its implementation during the auth spike; prefer simple transactional storage and opaque credentials hashed at rest. Keychain owns any necessary recoverable app secret. No separate database server.
- Account-wide access means the current macOS user's accessible accounts and globally enabled services, bounded by OS authorization. It is not an Apple ID login flow or system-wide access to other macOS users.

## Protocol and dependencies

Use established MCP/HTTP implementations. The official Swift SDK is the first candidate; no version is selected by this bootstrap. Keep `Package.resolved` committed once dependencies exist. Do not implement JSON-RPC, HTTP parsing, PKCE primitives, or cryptography from scratch.

App authorization policy and native consent still require application code even with library support. The feasibility slice must resolve library support for server-side OAuth rather than infer it from client-side OAuth documentation.

OAuth approval lasts until revoked; access tokens may have short lifetimes and rotate refresh credentials. Validate each request against the current grant so revocation is effective before the next operation. Revocation cannot undo an already completed Apple mutation.

## Local transport

Bind only to loopback. Endpoint port and issuer scheme remain spike decisions. Test local HTTP compatibility explicitly; do not equate OAuth's loopback callback allowance with permission for every authorization endpoint to use HTTP. If selected implementations require HTTPS for the issuer, choose and document a local trust approach without silently bypassing validation or modifying the system trust store.

No LAN binding, Tailscale Serve, router changes, background daemon, or hosted identity provider is included in the skeleton.

## Packaging and permission boundary

The Swift package keeps the bootstrap buildable with Command Line Tools. The `.app` bundle provides an early stable identity. Before Apple-service acceptance, choose and verify sandbox entitlements, usage descriptions, signing identity, and persistence of TCC permissions across rebuilds. Use full Xcode when required. Do not promise that development ad-hoc signing establishes a production permission contract.

## Upstream strategy

This is an original private scaffold informed by iMCP, not a GitHub fork. Reuse selected implementations with their notices after review. Keep an exact upstream revision in `THIRD_PARTY_NOTICES.md` for imported code. Avoid wholesale copying of upstream network coordination, updater identities, trust state, or entitlements.
