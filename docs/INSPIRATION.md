# Prior art by question

Prior art informs a decision; it is not a dependency list or a mandate to copy architecture. Check source and license at a pinned revision before reuse. Documentation review does not establish reliability.

| Question | Read first | Use |
| --- | --- | --- |
| Native permissions and initial service inventory | [iMCP](https://github.com/mattt/iMCP) | App/service structure and Apple integration details. Source reviewed at `a7698def394e942da196e13de4798f8b69c3f800` (1.6.2). Replace trust-by-name and stdio/Bonjour coordination. |
| Reminders editing/deletion | [apple-reminders-mcp](https://github.com/orshemtov/apple-reminders-mcp), [remindctl](https://github.com/openclaw/remindctl) | Identifiers, mutations, validation, and EventKit constraints. |
| MCP/HTTP infrastructure | [official Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) | Prefer tested protocol infrastructure; verify released server transport/auth capabilities. |
| Alternative Swift server patterns | [SwiftMCP](https://github.com/Cocoanetics/SwiftMCP) | Compare only if the official SDK leaves a concrete server-side gap. |
| Simple pairing UX | [SimpleBot](https://github.com/huglyfe/SillyClaw), [T3 Code](https://github.com/pingdotgg/t3code/blob/main/docs/internals/environment-auth.md) | One-time approval, durable access, revoke. Their custom exchanges are not substitutes for MCP OAuth. SimpleBot source was reviewed locally; the repo may be private. Do not copy its source into this project without a license decision. |
| Native service controls and connections | [OnlySwitch](https://github.com/JackLandrin/OnlySwitch) | Compact settings and remote-pairing interaction references. |
| Native MCP browsing | [Companion](https://github.com/mattt/Companion) | SwiftUI inspection/navigation; not an authentication blueprint. |
| Menu-bar settings polish | [Ice](https://github.com/jordanbaird/Ice) | Visual/interaction reference. GPL-3.0: avoid copying into the MIT project without a compatible licensing decision. |

## Study workflow

Read the one route needed for the active milestone. Optional source snapshots belong in ignored `inspiration/<project>/`; record revision, license, files studied, and the resulting decision here when they inform implementation. Do not vendor entire projects or import private runtime state.

SimpleBot's useful bootstrap conventions are compact product/architecture contracts, a repo agent guide, one canonical check command, and prior art routed by the active question. Its conversation engine, queues, data model, and deployment rules do not apply to this app.
