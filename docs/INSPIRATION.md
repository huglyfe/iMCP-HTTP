# Implementation references

Use the reference relevant to the change. Check source and license at a pinned revision before reusing code. Reference projects are not build dependencies; optional local checkouts belong under ignored `inspiration/`. Record useful API constraints and design decisions here, with implementation and acceptance status in [PLAN.md](PLAN.md).

## Protocol and authorization

- SwiftMCP 1.13.0 provides typed protocol dispatch and tool metadata; Hummingbird 2.27.0 owns HTTP and listener lifetime. The official Swift MCP SDK 0.12.1 rejected the tested Codex initialize payload's structured experimental capability. This is a version-specific compatibility finding, not a claim about later SDK versions.
- MCP authorization, RFC 7591, and RFC 8252 define local public-client registration and OAuth with PKCE. Native approval grants access; client names are display data. The small adapted S256 helper is attributed in [third-party notices](../THIRD_PARTY_NOTICES.md).
- Hummingbird's event-loop provider and SwiftNIO 2.103.0's scoped `MultiThreadedEventLoopGroup` support one listener worker with automatic shutdown. No process-wide per-core pool is needed.
- Client setup references are linked beside each recipe in `Sources/IMCPHTTP/ClientSetup.swift`. Documentation establishes configuration shape; the app labels tested login/tool behavior separately. Hosted connectors cannot directly reach the loopback listener.

## Apple services

SDK headers and public framework documentation define API behavior. The following source reviews informed the design without copying implementations.

| Reference and reviewed revision | Relevant areas | Resulting decision |
| --- | --- | --- |
| [iMCP](https://github.com/mattt/iMCP/tree/a7698def394e942da196e13de4798f8b69c3f800), MIT | Apple service adapters, Contacts extensions, app/service views | Use EventKit, Contacts, MapKit, and native permissions. Keep explicit account IDs and recurring occurrence targets. Use local HTTP and OAuth for this app. |
| [apple-reminders-mcp](https://github.com/orshemtov/apple-reminders-mcp/tree/06638015e0e50330dec02fc6be69874cea181b0d), MIT | Tool names, ReminderModels, EventKitReminderStore | Support native list/item mutations with exact IDs and compact results. Completion and reopening belong in edit. |
| [remindctl](https://github.com/openclaw/remindctl/tree/cdd7a06b85272980067f0e5b386fea9e10be0cf9), MIT | EventKitStore, ReminderAlarmMutation, ReminderSnapshot | Preserve non-time alarms, handle orphan reminders, and retain native calendar dates. |
| [macos-apps-mcp](https://github.com/derekrussell/macos-apps-mcp/tree/739c0cb85340a749e8e946341b76c40fddad1e7d), MIT | Mail/Notes tools and scripts | Use account-qualified mailbox targets, native IDs, and note HTML semantics. Mailbox deletion is unavailable through the scripting dictionary. |
| [griches/apple-mcp](https://github.com/griches/apple-mcp/tree/461524625402548f7729db9f7a3758264b7644be), no root license in the reviewed snapshot | Mail/Notes/Messages scripts | Scripting does not provide full Messages history. Do not copy this source without resolving its license. |

Use [MapKit search](https://developer.apple.com/documentation/mapkit/mklocalsearch) and [directions](https://developer.apple.com/documentation/mapkit/mkdirections) for supplied locations. Use [PhotoKit](https://developer.apple.com/documentation/photokit) for album and asset metadata; richer private-database indexing is outside this app's design.

Mail and Notes use their installed `.sdef` dictionaries and OSAKit. Typed Apple-event arguments/results avoid executable string interpolation. OpenScripting's `OSASetActiveProc` supports the host's execution deadline, including interpreter loops. [Automation permission preflight](https://developer.apple.com/documentation/coreservices/3025784-aedeterminepermissiontoautomatet) gates each app independently. Use bounded reads, sanitized failures, and explicit uncertain mutation outcomes.

[CoreBluetooth](https://developer.apple.com/documentation/corebluetooth) defines generic GATT behavior. Writes without response do not guarantee delivery; reads and subscriptions share the value callback. Keep generated handles for repeated UUID instances, bounded operations, and cancellation without assuming a device protocol.

## Native interface

Apple's [Window and MenuBarExtra guidance](https://developer.apple.com/videos/play/wwdc2022/10061/) supports one normal window and a persistent compact menu panel sharing one runtime. [LocalAuthentication device-owner policy](https://developer.apple.com/documentation/LocalAuthentication/LAPolicy/deviceOwnerAuthentication) provides a fresh authentication context per approval with macOS password fallback.

[OnlySwitch](https://github.com/JackLandrin/OnlySwitch/tree/0036625f1554f0d4798ffd50383679b8ce1fc3b4) service rows and [Settings](https://github.com/sindresorhus/Settings/tree/f41475771f65379ca10852c95119a7f53f0de5a5) segmented controls informed the compact layout. These are interaction references; no source was copied. Preserve the service colors, individual tool switches, and three-tab window described in [requirements](REQUIREMENTS.md#native-interface).

## Coverage and remaining boundaries

For v0.6, the public presentation of [Settings](https://github.com/sindresorhus/Settings) (MIT), [OnlySwitch](https://github.com/JackLandrin/OnlySwitch), and [Latest](https://github.com/mangerlahn/Latest) (GPL-3.0) was reviewed for interaction and distribution examples. Retain compact native navigation, make actions and state visible, and separate downloadable-app instructions from source development. These are presentation references only: no code, artwork, or dependencies were copied. Latest's license does not apply to this independently implemented interface.

The [tool contracts](REQUIREMENTS.md#common-tool-contract) describe implemented capabilities; the [plan](PLAN.md#verification-boundary) records native acceptance. Future work must stay within the following boundaries.

| Area | Constraint |
| --- | --- |
| Reminders / Calendar | Public EventKit does not expose Reminders tags, subtasks, sections, or Smart Lists. Attendee/invitation editing is outside the current Calendar contract. |
| Contacts / Photos | Contact notes need a separate entitlement. Linked-card merging and cross-account moves are unsupported. Photos exposes metadata, without media export, hidden assets, or a database mirror. |
| Location / Capture | Require their own permission lifecycle and output contracts. Explicit-coordinate Maps tools do not need device location. |
| Shortcuts | A bounded `/usr/bin/shortcuts` integration would need cancellation and explicit side-effect semantics. No general shell or automation tool is planned. |
| Weather / Music | WeatherKit needs developer provisioning and attribution. MusicKit needs service authorization and capability checks. Neither is enabled by an ad-hoc signature. |
| Messages / Phone | The reviewed history adapters use private stores. No private database access or Full Disk Access is part of this app. |
| Home / Podcasts / News | No supported native personal-data integration has been established. A helper app or public catalog is not a substitute for one. |

Measure native query cost before optimizing it. In particular, narrowing EventKit predicates must preserve date-only, floating-date, and query-timezone semantics. Keep performance experiments isolated from personal Apple data.
