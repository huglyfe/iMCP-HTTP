# Implementation plan

Originally agreed 2026-10-02. This is the maintained implementation and acceptance plan for public source alpha candidate **0.5.0-alpha.3**. It records current behavior; superseded UI directions and machine-specific operational history are omitted.

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
| Reminders vertical slice | Account/list/item management, date filters, completion, alarms, recurrence and exact write targets | Broader account restrictions and permission persistence |
| Durable approval/app controls | Atomic grants/settings, refresh rotation, revoke, pause, single window/menu and macOS authentication | Native authentication cancellation/retry, signing and permission persistence |
| Apple-service coverage | 68 tools across Reminders, Calendar, Contacts, Maps, Photos metadata, BLE, Mail and Notes | Native acceptance by service below |
| Source alpha preparation | Apache-2.0, contributor workflow, pinned builds, dependency notices, isolated check bundles and public-facing documentation | GitHub CI on the final commit and explicit publication decision |

Bluetooth pending operations use an enum. A first request waits up to 15 seconds for the manager to leave its initial unknown/resetting state; radio-off fails explicitly. Pause/disable/cancellation ends pending work and invalidates handles. Mail and Notes share one `AutomationRunner` owned by `AppRuntime`; separate runtime instances have independent execution slots. Tool contracts remain unchanged.

## Verification boundary

The source alpha uses disposable fixtures, unsaved native value objects, isolated OAuth state, and loopback HTTP tests. Automated checks never read or mutate saved Apple records, initialize the Bluetooth radio, or call live Maps. Native acceptance below is prior manual evidence, not a claim that every service or account type is fully tested.

The earlier candidate passed 83 tests locally but failed nine all-day Calendar assertions on hosted CI. Running the same fixture under UTC reproduced the failure: midnight timestamps in a supplied timezone reached EventKit as foreign instants, which EventKit rounded in the Mac timezone. All-day schedule parsing now preserves the input civil date when constructing Mac-local boundaries. Tests cover UTC, New York, Los Angeles, and Tokyo, including spring/fall DST and multi-day ranges. CI runs the canonical checks under UTC and America/New_York. Timed events retain their exact instants.

Canonical checks passed in UTC and America/New_York with 84 tests (11 app/runtime and 73 core), formatting, repository metadata/link validation, debug build, bundle notices, and signature verification. A clean source-only checkout, an optimized release build, and hosted CI remain in progress. No new native Apple-data acceptance is implied by these checks.

Publication hygiene reviewed the 13 pre-release commits (286 unique blobs) for common credential/private-key patterns, personal-email domains, absolute user-home paths, and runtime artifact paths; no matches were found. The tracked file inventory contains source, tests, documentation, build configuration, and retained licenses. This targeted review is not a comprehensive secret or security audit. Git author/committer metadata remains part of the history being published. Build packaging verified notices for all 30 resolved dependencies; the dependency lockfile is unchanged.

Prior client fixtures verified Codex registration/login, five fake services, restart and revoke; OpenCode registration/login and saved grants passed. OpenCode tool/restart/revoke behavior remains unverified. Native owner approval success, OAuth refresh, Deny/revoke, window close/reopen, and Quit have manual evidence. Authentication cancellation/retry and update-time permission persistence remain open.

| Native service | Evidence | Still unverified |
| --- | --- | --- |
| Reminders | Disposable create/get/edit, complete/reopen, due filtering, alarms/recurrence, moves, list rename/delete, and verified cleanup; due-only/start-preservation corrections read back from saved records | Broader shared/read-only account restrictions and permission persistence |
| Calendar | Disposable create/get/edit/move, recurring pagination and occurrence deletion, calendar cleanup; DST and multi-day all-day saved-record readback | Saved-record acceptance of the later omitted-allDay correction and the latest cross-timezone conversion; broader account restrictions |
| Contacts | Native discovery/reads and disposable create/get/edit/delete with native/custom label preservation and cleanup | Groups/membership, organization cards, account restrictions |
| Photos | Album discovery and empty-library reads | Populated filters/paging/get, hidden exclusion, permission/restart behavior |
| Maps | Native search and walking directions | Driving and other supported-option acceptance |
| BLE | Native scanning; fixture validation, state, cancellation, and notification-buffer coverage | Real peripheral GATT operations, notification delivery, permission flows and sleep/wake |
| Mail | Native permission, account/mailbox discovery, search/fetch/get | Disposable mutations and cleanup |
| Notes | Shared-note reads and disposable create/search/get/edit/append/move/delete with readback | Locked/attachment rejection, cross-account moves, and confirmation of the earlier empty test-folder cleanup |

The old acceptance calendars and reminder lists were removed with fresh reads confirming absence. Notes deletion follows native Recently Deleted retention. No automated cleanup may touch personal records. Native visual confirmation of the service-switch dimming fix, sleep/wake, and memory under enabled-service workloads remain open.

## Release scope and publication gates

The first public candidate is **0.5.0-alpha.3**. This release is source-only, with ad-hoc development bundles and explicit experimental-service limitations.

Before publication:

1. Pass canonical checks, the clean-checkout release build, and UTC/New York hosted CI on the candidate commit.
2. Review the tracked files and all history that will become public for credentials, personal data, generated runtime artifacts, and attribution. Record the scope of the review without claiming a comprehensive security audit.
3. Reconcile README, changelog, architecture, and this plan with actual implementation and acceptance evidence. Keep current native gaps visible.
4. Review and merge the implementation pull request so the default branch contains the app. The existing default branch still contains only the early scaffold until that merge.
5. Obtain an explicit owner instruction to change repository visibility and create the GitHub prerelease. Preparing the candidate does not publish it.

**Version 0.6** is planned for Developer ID-signed, notarized distribution and selected capabilities that require Apple developer provisioning. It includes the Apple Events entitlement needed by Mail/Notes under Hardened Runtime, first-install acceptance, and permission-persistence checks across two signed builds. Each new capability needs a separate feasibility and native-acceptance slice; a signature alone does not grant access. [WeatherKit](https://developer.apple.com/weatherkit/) is one candidate, subject to its capability and attribution requirements. Automatic updates are not required for the source alpha.

Later service candidates and API constraints remain in [INSPIRATION.md](INSPIRATION.md#coverage-and-remaining-boundaries). Add one complete service at a time. Measure Mail/Notes search performance with disposable data before introducing batching or other optimization.

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
