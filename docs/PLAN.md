# Implementation plan

Originally agreed 2026-10-02. This is the maintained implementation and acceptance plan for public source alpha candidate **0.5.0-alpha.1**. It records current behavior; superseded UI directions and machine-specific operational history are omitted.

## Product and settled decisions

iMCP-HTTP is a small native SwiftUI app giving approved AI clients access to Apple services. One process owns the window, persistent compact menu, loopback HTTP listener, OAuth, and Apple permissions. Closing the window keeps the server running; Quit stops it. The HTTP core remains independent of SwiftUI.

- Streamable HTTP on loopback, standard OAuth authorization-code flow with PKCE, native macOS approval, and revocable durable grants.
- Explicit global service and individual-tool choices shared by all approved clients. Access spans the Mac user's available accounts, with no per-list or per-client policy editor.
- Native frameworks own Apple data. Mail/Notes use their public scripting dictionaries; BLE exposes generic GATT operations with no target device or vendor protocol.
- Compact typed results, explicit identifiers/destinations, saved mutation records, and no automatic retry of uncertain writes.
- Apache-2.0 original application code with retained third-party notices. Source publication and signed/notarized binary distribution are separate milestones.
- Remote exposure, daemons/proxies, private Apple stores, multi-user hosting, and a plugin marketplace are outside this alpha.

## Implementation milestones

| Original milestone | Implemented result | Remaining evidence |
| --- | --- | --- |
| OAuth/transport feasibility | SwiftMCP + Hummingbird; standard dynamic registration, PKCE, protected-resource metadata and per-request authorization | OpenCode tool/restart/revoke acceptance |
| Reminders vertical slice | Account/list/item management, date filters, completion, alarms, recurrence and exact write targets | Complete native edit/move/delete, account restrictions and cleanup |
| Durable approval/app controls | Atomic grants/settings, refresh rotation, revoke, pause, single window/menu and macOS authentication | Native authentication cancellation/retry, signing and permission persistence |
| Apple-service coverage | 68 tools across Reminders, Calendar, Contacts, Maps, Photos metadata, BLE, Mail and Notes | Native acceptance by service below |
| Source alpha preparation | Apache-2.0, contributor workflow, pinned builds, dependency notices, isolated check bundles and public-facing documentation | GitHub CI on the final commit and explicit publication decision |

Bluetooth pending operations use an enum. A first request waits up to 15 seconds for the manager to leave its initial unknown/resetting state; radio-off fails explicitly. Pause/disable/cancellation ends pending work and invalidates handles. Mail and Notes share one `AutomationRunner` owned by `AppRuntime`; separate runtime instances have independent execution slots. Tool contracts remain unchanged.

## Verification boundary

Local alpha preparation passed the canonical checks: 74 tests (11 app/runtime and 63 core), formatting, repository metadata/links, debug build, bundle resources/notices, and signature validation. A fresh source-only tree independently passed the same workflow and an optimized release build. A targeted review of all 11 existing local commits found no matching credential or machine-path patterns; this is not a comprehensive secret audit. Build-tool smoke checks verified running-target preservation and invalid-output rejection. GitHub visibility remains private; no release or production cutover was performed. Hosted CI for the final changes remains pending.

Canonical checks cover authorization/persistence, real loopback HTTP, authenticated MCP contracts for every supported protocol version, strict validation, fixture/native value mapping, runtime ownership, cancellation and permission gates. Script fixtures compile fixed scripts and execute only pure helpers; BLE fixtures never initialize a radio manager. New tests cover runner contention/isolation, error/cancellation cleanup, and bounded BLE initialization through transient states.

Prior real-client fixtures verified Codex registration/login, five fake services, restart and revoke; OpenCode registration/login and saved grants passed. Prior manual acceptance verified native approval success, OAuth exchange/refresh, Deny/revoke, window close/reopen and Quit. These are distinct from current automated evidence and do not establish native Apple CRUD completeness.

| Native service | Evidence | Still unverified |
| --- | --- | --- |
| Reminders, Calendar, Contacts | Discovery, disposable container/item creation and exact readback; Calendar range search | Complete edits/moves/deletes, recurrence/account restrictions and verified cleanup |
| Photos | Album discovery and empty-library reads | Populated-library filters/paging, hidden exclusion and permission/restart behavior |
| Maps | Validation, fixture results, live search and walking directions | Other travel modes |
| BLE | Fixture state, validation and notification-buffer coverage | Permission flows, real peripherals/GATT, notification delivery and sleep/wake |
| Mail | Script fixtures, native permission and discovery/fetch/get | Disposable mutations and cleanup |
| Notes | Script fixtures, native shared-note fetch/get, disposable create/search/get/edit/append/move/delete with readback | Locked/attachment mutation rejection, cross-account moves; empty test folder cleanup |

Native permission persistence across rebuilt ad-hoc bundles, sleep/wake, and memory under enabled-service workloads remain open. Builds must not replace the running app. Use the contributor workflow and disposable fixtures below; record results without private account data.

Latest native smoke checks verified authorized connection, Calendar discovery/fetch/get and disposable-calendar deletion with fresh-list confirmation, Contacts discovery/fetch/get, Mail discovery/fetch/get, Notes account/folder discovery, Photos albums and an empty asset fetch, Maps search/walking directions, and BLE scanning. The prior Reminders process termination and Notes false not-found failures were diagnosed and repaired; installed-app verification is recorded below. The two calendars and two reminder lists from the earlier acceptance run were removed; fresh tool discovery and the Calendar UI confirmed the acceptance entries were absent. Photos asset get and BLE GATT operations still require suitable test data/hardware.

Diagnosis confirmed both fetch failures. The live Reminders stack stopped on the EventKit search queue at a Swift main-actor assertion inside the nested `compactMap` closure in `EventKitReminders.fetch`. A synthetic EventKit callback reproduced the assertion without reading saved reminders; explicitly marking the callback `@Sendable` made that fixture pass. Notes folder resolution and note counting succeeded, but `id of container of target` failed with AppleScript `-1728` on the existing shared note. A read-only copy of the fetch script succeeded when it reused the known folder ID. The general error mapping incorrectly presents that property failure as a missing target. Both repairs are now implemented: the EventKit completion explicitly uses Sendable isolation with a background-callback regression fixture, and Notes retains explicit folder context across reads and mutations. After reinstall and owner permission approval, the installed app passed completed, incomplete and combined Reminders fetches without termination, and Notes fetch/get against the previously failing shared note. A disposable Notes item passed create, search, get, HTML replacement, plain-text append, same-account move and delete, with exact folder and content readback. Native Notes UI independently confirmed the move and deletion. The note remains recoverable in Recently Deleted; the empty disposable destination folder remains because native UI automation timed out during cleanup. Authorized connection checks remained healthy afterward.

Service/tool switches now limit busy-state dimming to the affected service/tool while retaining runtime serialization and pointer blocking during updates. This prevents unrelated controls from dimming on every change. The reinstalled app also shows secondary guidance beneath the Mail and Notes service headings to keep their apps open; enablement opens them when needed. Canonical checks passed (77 tests: 11 app/runtime and 66 core), including background EventKit callback and shared-note folder-context regressions, formatting, repository checks, build and signature validation. Native caption presence is verified; visual confirmation of the brief switch-flash fix remains pending.

## Release and later work

The source alpha can describe experimental integrations explicitly while native acceptance remains incomplete. It does not claim notarized distribution or production cutover readiness. Complete the publication checks in [CONTRIBUTING.md](../CONTRIBUTING.md#preparing-a-source-alpha), review the exact commit and GitHub CI, and obtain an explicit owner instruction before changing visibility or creating a release.

Later service candidates and API constraints are recorded in [INSPIRATION.md](INSPIRATION.md#coverage-and-remaining-boundaries). Add one complete service slice at a time. Mail/Notes search performance should be measured with disposable native data before adding batching or other optimization. No performance refactor is part of this cleanup.

## Native acceptance

Apple-service acceptance is partial; fixture tests do not establish native behavior. Native authentication success, refresh, revoke, Deny, window close/reopen, and Quit have prior manual evidence. Recheck them when those paths change. Use an isolated app state directory/port and an isolated client entry, then remove that entry and revoke its grant when finished. Never run an automated test against the owner's reminder data.

1. Verify global tool switches hide disabled tools and reject stale calls, persist across restart, and preserve service-level gating. Verify native Approve and Deny for separate login attempts, pause/start, window close/reopen, menu Open, and Quit. Confirm startup listens independently of presentation and the app has a Dock icon. Enable Reminders through the native macOS permission flow.
2. Create two visibly named disposable lists in Reminders, for example `iMCP acceptance source <timestamp>` and `iMCP acceptance destination <timestamp>`. Discover their exact IDs; do not use an owner's existing list as an implicit target.
3. Create identifiable disposable reminders with a date-only deadline, a named-zone timed deadline, and no due date. Verify each in Reminders and through `reminders_get`.
4. Search the selected lists by a unique test-title prefix; verify today/overdue/upcoming/undated, completion filtering, due sort, and pagination against those items. Include a DST boundary fixture when practical.
5. Edit title/notes/priority, clear notes/due with `clear`, complete/reopen, and verify unrelated native fields remain intact. Check a disposable recurring item separately before treating recurrence behavior as accepted.
6. Move an item between the two lists, use its returned identifier, independently verify its destination in Reminders, and confirm the source no longer contains it. Verify missing/read-only destinations fail without a source change where such an account is available.
7. Restart/reconnect; revoke and confirm subsequent calls fail. Delete only disposable items, independently verify absence, and remove the empty disposable lists. Record success or the exact remaining gate without storing account names/content or credentials.

8. Enable Calendar independently. In disposable calendars, create timed and all-day events across a DST boundary; query/get/edit/move/delete them. For a disposable recurring series, verify `thisEvent` and `futureEvents` against native Calendar and verify stale start targets fail. Check shared/read-only account behavior without touching existing events. Remove disposable calendars and verify absence.
9. Enable Contacts independently. Create disposable person and organization cards in an explicit account; verify names/phones/emails/URLs/addresses/unknown-year birthday, omitted-field preservation, and clearing. Create/rename a disposable group, add/remove the test card, verify membership and same-account failure, then remove the group/cards and verify absence. Do not test deletion on a unified personal card.
10. Enable Maps without Location access. Search a public address near explicit coordinates; check a known driving/walking route and optional instructions. Disable it and verify stale tool calls fail. No personal device location is needed.
11. Restart and confirm each saved service preference. Confirm services absent from the saved enabled-service set remain disabled. Record exact outcomes, without account names, content, credentials, or screenshots of unrelated data.
12. Enable Photos manually and verify albums, date/media/favorite filtering, metadata paging/get, hidden-asset exclusion, disabled-tool rejection, and restart preferences using identifiable disposable Photos assets. No native photo acceptance or permission request is performed by automated tests.

## BLE, Mail, and Notes acceptance

1. Build to a separate bundle with `IMCP_BUILD_APP_PATH` when the existing app is running; do not overwrite its signature during acceptance. Use temporary app state and a spare loopback port. Never reset production grants, services, or privacy settings as part of a test.
2. Enable each new service explicitly. Verify allowed/denied Automation and Bluetooth prompts, persisted enablement, disabled tools, and stale-call rejection. Mail and Notes may launch and sync as part of enablement; OS permission dialogs require the owner when macOS demands it.
3. With an identifiable disposable BLE peripheral, scan, connect, discover duplicate-UUID services/characteristics by distinct handles, read, write with/without response, subscribe, observe cursor polling and overflow, unsubscribe, and disconnect. Confirm radio-off, disconnect, timeout/cancellation, service-change invalidation, pause/restart, and power/sleep recovery. Do not send arbitrary bytes to an unknown nearby device.
4. In a dedicated disposable Mail mailbox with a manually supplied test message, fetch/search/get, toggle read/flagged, move to another disposable mailbox, verify saved state independently in Mail, delete the message, and confirm native retention. Test renamed/stale mailbox IDs and account mismatch rejection. Delete the disposable mailboxes manually in Mail: its scripting dictionary does not provide reliable mailbox deletion.
5. In a dedicated Notes folder, create a uniquely named disposable note, verify title/escaped text/HTML, search/get, replace HTML, append text, and move within the same account. Verify locked/attachment edit rejection without changing personal notes. Delete the disposable note, independently confirm the result, and remove the test folder manually. Do not infer cleanup or native acceptance from fixture tests.
6. Permission or hardware blocks leave the implementation and automated evidence intact; record the specific unverified native operations without weakening access controls.
