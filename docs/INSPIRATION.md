# Prior art by question

Prior art informs a decision; it is not a dependency list or a mandate to copy architecture. Check source and license at a pinned revision before reuse. Documentation review does not establish reliability.

| Question | Read first | Use |
| --- | --- | --- |
| Native permissions and initial service inventory | [iMCP](https://github.com/mattt/iMCP) | App/service structure and Apple integration details. Source reviewed at `a7698def394e942da196e13de4798f8b69c3f800` (1.6.2). Replace trust-by-name and stdio/Bonjour coordination. |
| Reminders editing/deletion | [apple-reminders-mcp](https://github.com/orshemtov/apple-reminders-mcp), [remindctl](https://github.com/openclaw/remindctl) | Identifiers, mutations, validation, and EventKit constraints. |
| MCP/HTTP infrastructure | [official Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) | Prefer tested protocol infrastructure; verify released server transport/auth capabilities. |
| Alternative Swift server patterns | [SwiftMCP](https://github.com/Cocoanetics/SwiftMCP) | Selected at 1.13.0 after the official SDK failed the exact Codex initialize fixture; typed protocol/tools with Hummingbird owning HTTP; the Client trait is required by its macros. |
| Simple pairing UX | [SimpleBot](https://github.com/huglyfe/SillyClaw), [T3 Code](https://github.com/pingdotgg/t3code/blob/main/docs/internals/environment-auth.md) | One-time approval, durable access, revoke. Their custom exchanges are not substitutes for MCP OAuth. SimpleBot source was reviewed locally; the repo may be private. Do not copy its source into this project without a license decision. |
| Native service controls and connections | [OnlySwitch](https://github.com/JackLandrin/OnlySwitch) | Compact settings and remote-pairing interaction references. |
| Native MCP browsing | [Companion](https://github.com/mattt/Companion) | SwiftUI inspection/navigation; not an authentication blueprint. |
| Menu-bar settings polish | [Ice](https://github.com/jordanbaird/Ice) | Visual/interaction reference. GPL-3.0: avoid copying into the MIT project without a compatible licensing decision. |

## Study workflow

Read the one route needed for the active milestone. Optional source snapshots belong in ignored `inspiration/<project>/`; record revision, license, files studied, and the resulting decision here when they inform implementation. Do not vendor entire projects or import private runtime state.

SimpleBot's useful bootstrap conventions are compact product/architecture contracts, a repo agent guide, one canonical check command, and prior art routed by the active question. Its conversation engine, queues, data model, and deployment rules do not apply to this app.

## Implementation decision, 2026-10-03

The owner requested a clean cut from iMCP. Reviewed released SwiftMCP 1.13.0 protocol dispatch/metadata and optional transport code, Hummingbird 2.27.0 application/lifecycle/form/body APIs, official Swift SDK 0.12.1 client capability decoder and PKCE helper, and Apple EventKit headers for identifiers, access, fetch cancellation, dates, refresh, and mutation. Only the small attributed S256 helper was adapted; no iMCP or other Reminders implementation was copied. Native EventKit is the Reminders authority.

## Apple service/tool review, 2026-10-03

Reviewed these source revisions directly (all MIT licensed); no implementation code was copied:

| Repository / revision | Files studied | Decision |
| --- | --- | --- |
| [iMCP](https://github.com/mattt/iMCP/tree/a7698def394e942da196e13de4798f8b69c3f800) `a7698def` | `App/Services/{Calendar,Contacts,Reminders,Maps,Location,Shortcuts,Weather,Messages,Phone,Capture,Utilities}.swift`, Contacts extensions | Use EventKit, Contacts, and MapKit directly. Keep account IDs and recurring occurrence targeting. Do not inherit stdio/Bonjour, Ontology models, implicit default lists, unified-card mutations, or permission coupling between Maps and Location. |
| [apple-reminders-mcp](https://github.com/orshemtov/apple-reminders-mcp/tree/06638015e0e50330dec02fc6be69874cea181b0d) `06638015` | ToolNames, ReminderModels, EventKitReminderStore | Add account/list CRUD and richer native fields. Consolidate completion/reopen into edit; avoid duplicate query tools, bulk operations, and success/message/warnings envelopes. |
| [remindctl](https://github.com/openclaw/remindctl/tree/cdd7a06b85272980067f0e5b386fea9e10be0cf9) `cdd7a06b` | EventKitStore, ReminderAlarmMutation, EventKitReminderSnapshot | Preserve non-time alarms when editing time alarms; handle orphan reminders; keep calendar dates native. Do not adopt fuzzy write targets or URL-in-notes mirroring. |

Apple SDK headers were the API authority for EventKit dates, recurrence restrictions, alarm types, calendar immutability, event spans, and Contacts fetch/save semantics. [MapKit search](https://developer.apple.com/documentation/mapkit/mklocalsearch) and [directions](https://developer.apple.com/documentation/mapkit/mkdirections) supply the Maps slice. Prior-art breadth is not proof of native acceptance or a reason to expose unused fields.

### Coverage and remaining boundaries

| Service | This implementation | Remaining work / constraint |
| --- | --- | --- |
| Reminders | Accounts/lists CRUD, search/date ranges, item CRUD/move/complete, URLs/start dates, display time alarms, recurrence | Native disposable acceptance; public EventKit does not expose Reminders tags/subtasks/sections/Smart Lists |
| Calendar | Accounts/calendars CRUD, bounded occurrence search, exact occurrence CRUD/move, recurrence/alarms/availability | Native recurring/shared calendar acceptance; attendee/invitation editing is outside this contract |
| Contacts | Individual-card search/CRUD, organizations, names/phones/emails/URLs/addresses/birthday, groups/membership | Native account/write acceptance; no notes entitlement, photos, Smart Groups, merge, or cross-account moves |
| Maps | Place/address search, driving/walking routes, optional instructions | Native network acceptance; no device-location dependency, transit, reverse geocoding, or map images |
| Location | Not implemented | Separate Core Location permission lifecycle and cancellable one-shot current location; do not couple to explicit-coordinate Maps tools |
| Shortcuts | Not implemented | Supported `/usr/bin/shortcuts` list/run path is promising; needs bounded process I/O, cancellation, and explicit automation-side-effect semantics |
| Weather | Not implemented | WeatherKit developer capability/signing and required attribution must be proven; avoid a hidden third-party weather backend |
| Messages / Phone history | Not implemented | iMCP reads private SQLite stores with owner-selected folder access; not a public Apple framework adapter. No database access or Full Disk Access was added |
| Capture | Not implemented | Screen/camera/microphone have separate permissions and binary output contracts; require their own slice |
| Utilities | Not implemented | Add only concrete useful operations; no general shell, file, or automation escape hatch |

### Tool design rules

- One operation per tool; explicit IDs for writes and explicit destinations on create/move.
- Flat read arguments when practical; one `changes` object for patches and one existing `query` for Reminders filters. No generic service/action router.
- Typed JSON objects, compact search summaries, detail on get, saved record on mutation, minimal deletion receipt.
- Omit absent values and empty optional detail arrays. Put names/capabilities in discovery, not repeated on every record.
- Short action descriptions. Include only distinctions needed to avoid a wrong operation (such as recurrence scope or whole-list deletion).
- Strict validation and native failure reporting; no compatibility aliases, notes-based feature emulation, or mirror database.

## Menu-bar UI correction, 2026-10-03

Reviewed iMCP at the same pinned `a7698def` revision: `App/App.swift`, `App/Views/ContentView.swift`, `ServiceToggleView.swift`, and `ServicesSettingsView.swift`, plus its MIT license (copyright 2025 Mattt). Reuse the interaction concept: menu-bar accessory, compact service rows, and Settings with individual tool controls. This implementation uses original SwiftUI code; no upstream source/assets, updater, window-resizing workaround, SwiftUI bindings in core, or stdio/Bonjour machinery are imported. HTTP setup and OAuth approval replace upstream connection setup and trust-by-name.

## Additional Apple apps and performance review, 2026-10-03

Owner preference: direct frameworks; defer app automation. No app data, Automation permissions, or private databases were inspected. Only installed scripting dictionaries, SDK headers, source snapshots, and official documentation were read. No code was copied.

- [macos-apps-mcp](https://github.com/derekrussell/macos-apps-mcp/tree/739c0cb85340a749e8e946341b76c40fddad1e7d), MIT, copyright 2026 Derek Russell: reviewed tools/_osascript.py, tools/mail.py, tools/notes.py and scripts/mail.applescript / notes.applescript. Bounded subprocess automation, exact IDs/account-qualified targets, and HTML note content are useful references, but this is not a direct-framework implementation. No subprocess wrapper is adopted.
- [griches/apple-mcp](https://github.com/griches/apple-mcp/tree/461524625402548f7729db9f7a3758264b7644be): reviewed mail/notes/messages AppleScript modules and installed Mail/Notes/Messages/Music scripting dictionaries. Automation can read Mail/Notes and send Messages, but Messages scripting does not provide full history. No source reuse; the checked snapshot has no root license file, so do not copy code without resolving its license.
- iMCP’s pinned Weather, Messages, and Phone adapters: WeatherKit needs developer capabilities; message/call history queries private SQLite stores and folder bookmarks/WAL handling. Keep those integrations deferred rather than silently introducing database copies or broad disk access.
- [osxphotos](https://github.com/RhetTbull/osxphotos): documentation describes SQLite-copy/in-memory indexing for richer library metadata. Avoid that architecture here; use [PhotoKit](https://developer.apple.com/documentation/photokit) for a bounded metadata-only slice. PHFetchOptions/PHPhotoLibrary/PHAsset SDK headers are the API authority.

| App | Supported path / decision |
| --- | --- |
| Photos | Implemented: PhotoKit album/asset metadata. No bytes/export/hidden assets or database mirror. |
| Mail | MailKit is a Mail extension framework, not general inbox querying. AppleScript path deferred; no IMAP credentials/provider backend introduced. |
| Notes | No suitable public direct Notes data framework found. Scripting/Shortcuts or private database work would change the agreed access model; deferred. |
| Weather | [WeatherKit](https://developer.apple.com/weatherkit/) supports macOS, requires Developer Program access/capability signing and attribution. Current bundle is ad-hoc signed; deferred until entitlement-backed acceptance. |
| Music | [MusicKit](https://developer.apple.com/documentation/musickit) supports macOS; app service/developer token generation, user authorization, and subscription capabilities require proof. Music.app automation is deferred. |
| Messages | History needs private chat.db in reviewed iMCP source; AppleScript sending is automation. Neither path is implemented. |
| Phone | iMCP history reads private CallHistoryDB; [CallKit](https://developer.apple.com/documentation/callkit) integrates an app’s calls and does not supply the owner’s Phone history. Deferred. |
| Home | [HomeKit platform metadata](https://developer.apple.com/tutorials/data/documentation/homekit.json) lists Mac Catalyst, not native macOS. No helper app/Catalyst rewrite introduced. |
| Podcasts | [Apple iTunes Search API](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/Searching.html) supports public podcast search, not a verified personal subscriptions/progress API. No substitute catalog tool advertised as library integration. |
| News | [Apple News API](https://developer.apple.com/documentation/applenewsapi) publishes/manages publisher articles; no suitable supported personal-reader integration found. Deferred. |

Performance: use authorization-state snapshots instead of idle polling. Reminders summary snapshots omit alarm/recurrence arrays and unused fields. EventKit still returns the native matching collection; native date predicate narrowing is deferred because query-zone/date-only/floating semantics must not regress merely to reduce RAM.
