# Prior art by question

Prior art informs a decision; it is not a dependency list or a mandate to copy architecture. Check source and license at a pinned revision before reuse. Documentation review does not establish reliability.

| Question | Read first | Use |
| --- | --- | --- |
| Native permissions and initial service inventory | [iMCP](https://github.com/mattt/iMCP) | App/service structure and Apple integration details. Source reviewed at `a7698def394e942da196e13de4798f8b69c3f800` (1.6.2). Replace trust-by-name and stdio/Bonjour coordination. |
| Reminders editing/deletion | [apple-reminders-mcp](https://github.com/orshemtov/apple-reminders-mcp), [remindctl](https://github.com/openclaw/remindctl) | Identifiers, mutations, validation, and EventKit constraints. |
| MCP/HTTP infrastructure | [official Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) | Prefer tested protocol infrastructure; verify released server transport/auth capabilities. |
| Alternative Swift server patterns | [SwiftMCP](https://github.com/Cocoanetics/SwiftMCP) | Selected at 1.13.0 after the official SDK failed the exact Codex initialize fixture; core only, with Hummingbird owning HTTP. |
| Simple pairing UX | [SimpleBot](https://github.com/huglyfe/SillyClaw), [T3 Code](https://github.com/pingdotgg/t3code/blob/main/docs/internals/environment-auth.md) | One-time approval, durable access, revoke. Their custom exchanges are not substitutes for MCP OAuth. SimpleBot source was reviewed locally; the repo may be private. Do not copy its source into this project without a license decision. |
| Native service controls and connections | [OnlySwitch](https://github.com/JackLandrin/OnlySwitch) | Compact settings and remote-pairing interaction references. |
| Native MCP browsing | [Companion](https://github.com/mattt/Companion) | SwiftUI inspection/navigation; not an authentication blueprint. |
| Menu-bar settings polish | [Ice](https://github.com/jordanbaird/Ice) | Visual/interaction reference. GPL-3.0: avoid copying into the MIT project without a compatible licensing decision. |

## Study workflow

Read the one route needed for the active milestone. Optional source snapshots belong in ignored `inspiration/<project>/`; record revision, license, files studied, and the resulting decision here when they inform implementation. Do not vendor entire projects or import private runtime state.

SimpleBot's useful bootstrap conventions are compact product/architecture contracts, a repo agent guide, one canonical check command, and prior art routed by the active question. Its conversation engine, queues, data model, and deployment rules do not apply to this app.

## Implementation decision, 2026-10-03

The owner requested a clean cut from iMCP. Reviewed released SwiftMCP 1.13.0 protocol dispatch/metadata and optional transport code, Hummingbird 2.27.0 application/lifecycle/form/body APIs, official Swift SDK 0.12.1 client capability decoder and PKCE helper, and Apple EventKit headers for identifiers, access, fetch cancellation, dates, refresh, and mutation. Only the small attributed S256 helper was adapted; no iMCP or other Reminders implementation was copied. Native EventKit is the Reminders authority.
