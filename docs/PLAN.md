# Initial implementation plan

Agreed 2026-10-02; implementation updated 2026-10-04. Completed code and verified behavior are distinguished below.

## Progress

- Approved 2026-10-04 slice: normal single-window app with persistent menu-bar controls, macOS-authenticated OAuth approvals, and focused acceptance/cleanup. No new services, BLE, network access, signing setup, or AppleScript adapters in this slice. Earlier menu-bar-only decisions below are historical and superseded.
- Implemented the normal window with a native Services/Connections/Setup strip below the title bar, one content area, and the familiar compact menu. Services shows its shared-controls note first; Connections/Setup omit explanatory footers; Revoke is red. The owner rejected the sidebar redesign and enclosing tab border, and both were removed.
- Each new approval uses a fresh LocalAuthentication context. One optional attempt value ties authentication to the exact request and rejects stale results. OAuth exchanges and grants remain unchanged; all Quit routes await listener shutdown.
- Initial app/authentication milestone passed 51 tests, formatting, build, and bundle/signature validation. Real Codex fixture tools/restart/revoke and OpenCode registration/login passed. Computer use recovered and verified navigation, client search, and the single-container layout. The owner completed macOS authentication twice; PKCE exchange, connection_check, refresh, native revoke, rejection after revoke, and native Deny passed. Both temporary grants were revoked; no Apple records were accessed.
- The owner accepted the final UI. Native inspection verified the final tab contents, including the single Codex setup command. Window close/reopen preserved the listener, and Command-Q released it.
- Login follow-up: removed the one-second browser reload in favor of quiet status checks and a stable approval URL. Page refresh preserves one request; errors offer retry or restart guidance; decisions near expiry keep a full callback window. Expired or consumed links show a readable end-of-request page. Codex setup now shows only `mcp add`, verified to start and finish login automatically in isolated configuration. All 55 tests and canonical checks pass. Live browser rendering, manual refresh without duplicate approval, and native Deny/validated callback passed. The owner's saved Codex connection was preserved. Final relaunch and visual inspection of the expired-link page were blocked by the locked Mac; the rebuilt bundle is ready to open.

- Implemented in the private draft: SwiftMCP + Hummingbird, loopback MCP, native OAuth consent, durable grants, refresh rotation, revoke, pause/start, and working service controls.
- Version 0.4.0 expands to 36 typed tools: connection check; Reminders account/list/item management, search/date ranges, start/URL/location/time alarms/recurrence; Calendar account/calendar/occurrence management; Contacts card/group management; Maps search/routes.
- Clean tool contracts: explicit write targets, compact fetch summaries, detail on get, saved records on writes, no prose success envelope. iMCP, apple-reminders-mcp, and remindctl source review is recorded in INSPIRATION.
- Automated checks cover service gates, strict input/patch/date/recurrence validation, native value mapping, explicitly disabled defaults, OAuth/HTTP, and SDK schemas. The opt-in Codex fixture exercises all five services with fake data, restart, and revocation. The OpenCode fixture proves dynamic registration/login and a persisted grant; its tool/restart/revoke acceptance remains pending.
- Remaining release gates: native authentication cancellation/retry, menu Open/pause/start/Quit, macOS permission flows, disposable records and cleanup, live Maps results, signing/permission persistence, sleep/wake, and memory under enabled-service workloads. Fixture tests do not replace the remaining native acceptance.
- Added three read-only Photos metadata tools through PhotoKit; 39 tools across five services. Photos is disabled until explicitly selected. Replaced UI polling with authorization snapshots and an approval-expiry timer. Lean Reminders fetch snapshots omit detail arrays and unused notes; full native fetch before pagination remains an EventKit constraint.
- Owner chose direct frameworks and deferred automation. Mail/Notes/Music AppleScript adapters are not being added. WeatherKit/MusicKit require signing/capability proof; Messages/Phone private-store access and HomeKit’s Catalyst requirement need separate decisions. Location and Capture remain direct-framework candidates. No production integration cutover or public release.
- Corrected UI direction: iMCP-style menu-bar-only app (no Dock icon or main window), compact service controls, Settings with global individual-tool switches and client management. The earlier window scaffold diverged from the intended outer shape; the HTTP/OAuth core remains independent.
- Owner direction: independent clean application design, broad Apple coverage, simple parameters and minimal JSON results; no iMCP compatibility obligation.

- Cleanup slice: implemented-service inventory only; service settings use a set; stateless validation belongs to tool handlers and native alarm/recurrence values are prepared once. AppRuntime has explicit startup failure categories, cancellable lifecycle ownership, and direct fixture tests.
- Final cleanup review: fixed listener-task retention of AppRuntime, with an owner-release regression test. Scoped the HTTP listener to one event loop using the existing SwiftNIO dependency. Isolated release measurements cover disabled-service idle behavior and concurrent metadata requests; Apple-data workload measurements remain pending.
- UI refinement: removed the home subtitle and setup-command button; added distinct service colors and an alphabetical searchable directory of ten clients. Vendor docs inform recipes; verified and unverified clients remain distinct.
- Settings refinement: removed service status footers and grouped read-only tools before write tools, with both kinds labeled from existing tool metadata.
- Owner confirms there are no existing grants and requests a clean forward design. Removed the fixed Codex registration and legacy settings/store decoding. All clients now use bounded RFC 7591 public registration plus native approval and PKCE; no client-specific OAuth exchanges, production integration changes, or remote exposure.

## Product

iMCP-HTTP is a small native SwiftUI app giving approved AI clients access to Apple services. The primary user is the owner; Codex on the same Mac is the first client. Use proven libraries and native Apple frameworks with clear application, authorization, and dispatch ownership. iMCP is a product reference, not an architectural dependency.

The latest repository instruction is private creation. Keep the code suitable for open-source release from the start; publish only on a subsequent explicit instruction.

## Settled decisions

- Streamable HTTP inside the app; loopback only for the first release.
- OAuth authorization-code flow with PKCE, native owner approval, and approval until revoked.
- Separate credentials for each client grant. Account-wide capabilities shared across approved clients; no per-list or per-client tool policy editor.
- Global service enablement remains explicit and subject to macOS permissions.
- Reminders editing and deletion are the first tool additions. Existing fetch/create behavior must become reliable enough to target those operations.
- Intended initial inventory: Reminders, Calendar, Contacts, Photos, Location, Maps, Mail, Notes, Music, Messages, Phone, Home, Podcasts, News, Shortcuts, Weather, Capture, Utilities. Each adapter ships only after its requirements and availability are verified.
- Normal Mac app with one resizable window, Dock icon, and persistent compact menu-bar panel. Services, Connections, and Setup live in the window; closing it keeps the runtime alive. Native macOS authentication gates each new OAuth approval. No new service in this slice.
- Later ambition is broad Mac integration. Remote networking, computer control, native Reminders tags/subtasks, a plugin marketplace, and multi-user hosting are not first-release requirements.

## Bootstrap (completed before implementation)

- Swift 6 package with native SwiftUI app and a Foundation-independent service inventory.
- App bundling script, canonical check command, and macOS CI workflow.
- No listener, auth implementation, Apple permissions, or fake working controls.
- No third-party runtime dependencies until the implementation spike selects pinned versions.

## Current slice acceptance, 2026-10-04

- Verify launch, a single window, Dock/Command-Tab, close/reopen, menu Open, pause/start, and all Quit routes. Closing UI must not stop the listener; Quit must release it.
- In isolated state, start a standard OAuth request, approve with macOS authentication, and verify code exchange. Cancel authentication, retry, deny, expire a request, and pause during authentication; none may grant access accidentally. Verify password fallback on the owner’s Mac and normal remote-desktop workflow manually.
- Preserve existing service/tool settings and grants. Verify the familiar service rows, read-only/write grouping, permission failure visibility, Setup search, and connection revoke. Keep the three tabs below the title bar with clear spacing.
- Run `./scripts/check.sh` and opt-in client fixtures. Real native Apple-data, sleep/wake, and enabled-service memory acceptance remain distinct from fixture evidence.
- BLE (first device: owner-provided Tenovi Pillbox with forthcoming protocol docs), signing-dependent services, and AppleScript services follow only after confirming this slice.

## 1. OAuth and transport feasibility

The feasibility comparison selected SwiftMCP 1.13.0 core and Hummingbird 2.27.0. The released official Swift SDK rejects Codex object-valued experimental capabilities. SwiftMCP passed without a dependency fork. See architecture for the transport and native-consent boundaries.

Resolve: protocol/release version; HTTP server integration; local issuer scheme accepted by Codex and the chosen libraries; stable endpoint/port; client registration; callback matching; native consent handoff; token storage. Record the selected versions and decisions in architecture.

The initial proof used a pre-registered Codex client. The current implementation uses RFC 7591 dynamic registration for local-client interoperability. CIMD remains deferred: do not fetch arbitrary client metadata URLs without a concrete requirement and defined validation policy.

Acceptance: real Codex discovers authorization metadata, completes PKCE-backed login with owner approval, and calls a harmless test tool; denial, wrong verifier, code reuse, wrong audience, missing token, and revoked access fail. No Apple data required for this spike.

## 2. Reminders vertical slice

Introduce typed inputs/results and an EventKit adapter with an explicit concurrency owner. Implement list and item identifiers, fetch/create, edit, and delete. Use native EventKit identifiers as opaque handles; stale identifiers fail explicitly.

Patch semantics must distinguish omitted fields from clearing values. Reject invalid dates and nonexistent or ambiguous targets; never silently redirect a write to the default list. Preserve date-only semantics. Start with title, notes, due date, priority, and list targeting; additional fields require their own proof.

Acceptance: disposable reminder create -> edit -> independent readback in Reminders -> delete -> confirmed absence. Test invalid updates, stale IDs, account restrictions, and permission denial. Delete does not pretend success after an error; an interrupted write reports an uncertain outcome instead of retrying blindly.

## 3. Durable approval and app controls

Persist owner grants until revoked. Access credentials may expire and refresh without asking the owner again. Restart must preserve valid grants and revocations. Keep credential exchange and revocation atomic.

Implement service toggles reflecting real macOS authorization, client details, and revoke. Names are display labels. New sensitive services are disabled until the owner enables them; existing approved clients then share the enabled account-wide capabilities.

Acceptance: connect -> approve -> use -> restart -> reconnect -> revoke -> reject subsequent tool calls and refresh. Pause stops tool access. Closing the window or menu panel leaves the app available; Quit stops it.

## 4. Bring across the iMCP suite

Port one service at a time through the same dispatcher and authorization path. Review its permission ownership, licensing, return schema, failure behavior, and availability before enabling it. Do not retain Bonjour or stdio relay infrastructure simply because upstream has it.

Messages/Phone may need selected-file access and non-EventKit libraries; WeatherKit may require developer capabilities. Keep unavailable services visibly unavailable. Avoid private APIs unless separately decided and documented.

Acceptance: per-service read and permitted disposable write checks; disabled services cannot be invoked by name; protocol tools list matches actual implemented and enabled capability.

## 5. Personal release, then publication

Verify app identity, signing, entitlements, permission prompts, launch/reopen, sleep/wake, startup failure, and memory at idle. Choose update/distribution machinery only when needed. Public source release does not require finished notarized binaries.

Publish only after owner approval of visibility. Keep original notices for imported code, review tracked files for private data, and describe supported clients and known limitations honestly.

## First useful release gate

Codex on this Mac logs in once, lists enabled tools, edits and deletes a disposable reminder, reconnects after app restart, and loses access after revoke. The existing production integrations are replaced only after this proof and explicit cutover authorization.

## Native acceptance checklist

Apple-service acceptance remains pending; fixture tests do not establish it. Native authentication success, refresh, revoke, and Deny have separate verified evidence above. Use an isolated app state directory/port and an isolated client entry, then remove that entry and revoke its grant when finished. Never run an automated test against the owner's reminder data.

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
