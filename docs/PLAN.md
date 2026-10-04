# Initial implementation plan

Agreed 2026-10-02; implementation updated 2026-10-03. Completed code and verified behavior are distinguished below.

## Progress

- Implemented in the private draft: SwiftMCP + Hummingbird, loopback MCP, native OAuth consent, durable grants, refresh rotation, revoke, pause/start, and working service controls.
- Version 0.4.0 expands to 36 typed tools: connection check; Reminders account/list/item management, search/date ranges, start/URL/location/time alarms/recurrence; Calendar account/calendar/occurrence management; Contacts card/group management; Maps search/routes.
- Clean tool contracts: explicit write targets, compact fetch summaries, detail on get, saved records on writes, no prose success envelope. iMCP, apple-reminders-mcp, and remindctl source review is recorded in INSPIRATION.
- Automated checks cover service gates, strict input/patch/date/recurrence validation, native value mapping, backward-compatible disabled defaults, OAuth/HTTP, and SDK schemas. The opt-in Codex fixture exercises all five services with fake data, restart, and revocation.
- Remaining release gates: native Approve/Deny clicks, menu/Settings behavior, macOS permission flows, disposable records and cleanup, live Maps results, signing/permission persistence, sleep/wake, and measured idle memory. Computer-use app inspection currently fails with a native-pipe error; fixture tests do not replace this acceptance.
- Added three read-only Photos metadata tools through PhotoKit; 39 tools across five services. Photos stays disabled on upgrade. Replaced UI polling with authorization snapshots and an approval-expiry timer. Lean Reminders fetch snapshots omit detail arrays and unused notes; full native fetch before pagination remains an EventKit constraint.
- Owner chose direct frameworks and deferred automation. Mail/Notes/Music AppleScript adapters are not being added. WeatherKit/MusicKit require signing/capability proof; Messages/Phone private-store access and HomeKit’s Catalyst requirement need separate decisions. Location and Capture remain direct-framework candidates. No production integration cutover or public release.
- Corrected UI direction: iMCP-style menu-bar-only app (no Dock icon or main window), compact service controls, Settings with global individual-tool switches and client management. The earlier window scaffold diverged from the intended outer shape; the HTTP/OAuth core remains independent.
- Owner direction: independent clean application design, broad Apple coverage, simple parameters and minimal JSON results; no iMCP compatibility obligation.

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
- Menu-bar-only accessory app with a compact panel for server state, services, and pending approval. Settings holds individual tools, approved clients/revoke, and setup. Keep iMCP’s interaction concept while simplifying the core.
- Later ambition is broad Mac integration. Remote networking, computer control, native Reminders tags/subtasks, a plugin marketplace, and multi-user hosting are not first-release requirements.

## Bootstrap (completed before implementation)

- Swift 6 package with native SwiftUI app and a Foundation-independent service inventory.
- App bundling script, canonical check command, and macOS CI workflow.
- No listener, auth implementation, Apple permissions, or fake working controls.
- No third-party runtime dependencies until the implementation spike selects pinned versions.

## 1. OAuth and transport feasibility

The feasibility comparison selected SwiftMCP 1.13.0 core and Hummingbird 2.27.0. The released official Swift SDK rejects Codex object-valued experimental capabilities. SwiftMCP passed without a dependency fork. See architecture for the transport and native-consent boundaries.

Resolve: protocol/release version; HTTP server integration; local issuer scheme accepted by Codex and the chosen libraries; stable endpoint/port; client registration; callback matching; native consent handoff; token storage. Record the selected versions and decisions in architecture.

Prefer a minimal pre-registered public client for the first proof if supported cleanly. Evaluate CIMD/DCR only as required for actual client interoperability. Do not fetch arbitrary client metadata URLs without a defined validation policy.

Acceptance: real Codex discovers authorization metadata, completes PKCE-backed login with owner approval, and calls a harmless test tool; denial, wrong verifier, code reuse, wrong audience, missing token, and revoked access fail. No Apple data required for this spike.

## 2. Reminders vertical slice

Introduce typed inputs/results and an EventKit adapter with an explicit concurrency owner. Implement list and item identifiers, fetch/create, edit, and delete. Use native EventKit identifiers as opaque handles; stale identifiers fail explicitly.

Patch semantics must distinguish omitted fields from clearing values. Reject invalid dates and nonexistent or ambiguous targets; never silently redirect a write to the default list. Preserve date-only semantics. Start with title, notes, due date, priority, and list targeting; additional fields require their own proof.

Acceptance: disposable reminder create -> edit -> independent readback in Reminders -> delete -> confirmed absence. Test invalid updates, stale IDs, account restrictions, and permission denial. Delete does not pretend success after an error; an interrupted write reports an uncertain outcome instead of retrying blindly.

## 3. Durable approval and app controls

Persist owner grants until revoked. Access credentials may expire and refresh without asking the owner again. Restart must preserve valid grants and revocations. Keep credential exchange and revocation atomic.

Implement service toggles reflecting real macOS authorization, client details, and revoke. Names are display labels. New sensitive services are disabled until the owner enables them; existing approved clients then share the enabled account-wide capabilities.

Acceptance: connect -> approve -> use -> restart -> reconnect -> revoke -> reject subsequent tool calls and refresh. Pause stops tool access. Dismissing the panel or Settings leaves the app available; Quit stops it.

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

Still pending; fixture tests do not establish Apple-service acceptance. Use an isolated app state directory/port and an isolated client entry, then remove that entry and revoke its grant when finished. Never run an automated test against the owner's reminder data.

1. Verify global tool switches hide disabled tools and reject stale calls, persist across restart, and preserve service-level gating. Verify native Approve and Deny for separate login attempts, pause/start, panel dismiss/reopen, Settings, and Quit. Confirm startup listens without opening the panel and the app has no Dock icon. Enable Reminders through the native macOS permission flow.
2. Create two visibly named disposable lists in Reminders, for example `iMCP acceptance source <timestamp>` and `iMCP acceptance destination <timestamp>`. Discover their exact IDs; do not use an owner's existing list as an implicit target.
3. Create identifiable disposable reminders with a date-only deadline, a named-zone timed deadline, and no due date. Verify each in Reminders and through `reminders_get`.
4. Search the selected lists by a unique test-title prefix; verify today/overdue/upcoming/undated, completion filtering, due sort, and pagination against those items. Include a DST boundary fixture when practical.
5. Edit title/notes/priority, clear notes/due with `clear`, complete/reopen, and verify unrelated native fields remain intact. Check a disposable recurring item separately before treating recurrence behavior as accepted.
6. Move an item between the two lists, use its returned identifier, independently verify its destination in Reminders, and confirm the source no longer contains it. Verify missing/read-only destinations fail without a source change where such an account is available.
7. Restart/reconnect; revoke and confirm subsequent calls fail. Delete only disposable items, independently verify absence, and remove the empty disposable lists. Record success or the exact remaining gate without storing account names/content or credentials.

8. Enable Calendar independently. In disposable calendars, create timed and all-day events across a DST boundary; query/get/edit/move/delete them. For a disposable recurring series, verify `thisEvent` and `futureEvents` against native Calendar and verify stale start targets fail. Check shared/read-only account behavior without touching existing events. Remove disposable calendars and verify absence.
9. Enable Contacts independently. Create disposable person and organization cards in an explicit account; verify names/phones/emails/URLs/addresses/unknown-year birthday, omitted-field preservation, and clearing. Create/rename a disposable group, add/remove the test card, verify membership and same-account failure, then remove the group/cards and verify absence. Do not test deletion on a unified personal card.
10. Enable Maps without Location access. Search a public address near explicit coordinates; check a known driving/walking route and optional instructions. Disable it and verify stale tool calls fail. No personal device location is needed.
11. Restart and confirm each saved service preference. Confirm newly added services remain disabled when loading an old Reminders-only settings fixture. Record exact outcomes, without account names, content, credentials, or screenshots of unrelated data.
12. Enable Photos manually and verify albums, date/media/favorite filtering, metadata paging/get, hidden-asset exclusion, disabled-tool rejection, and restart preferences using identifiable disposable Photos assets. No native photo acceptance or permission request is performed by automated tests.
