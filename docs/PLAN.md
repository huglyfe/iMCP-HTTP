# Initial implementation plan

Agreed 2026-10-02. This document is the plan, not evidence that a feature exists.

## Product

iMCP-HTTP is a small native SwiftUI app giving approved AI clients access to Apple services. The primary user is the owner; Codex on the same Mac is the first client. Reuse proven libraries and selected iMCP integrations while rebuilding application coordination, authorization, and dispatch with clear ownership.

The latest repository instruction is private creation. Keep the code suitable for open-source release from the start; publish only on a subsequent explicit instruction.

## Settled decisions

- Streamable HTTP inside the app; loopback only for the first release.
- OAuth authorization-code flow with PKCE, native owner approval, and approval until revoked.
- Separate credentials for each client grant. Account-wide capabilities shared across approved clients; no per-list or per-client tool policy editor.
- Global service enablement remains explicit and subject to macOS permissions.
- Reminders editing and deletion are the first tool additions. Existing fetch/create behavior must become reliable enough to target those operations.
- Intended initial inventory: Reminders, Calendar, Contacts, Location, Maps, Messages, Phone, Shortcuts, Weather, Capture, Utilities. Each adapter ships only after its requirements and availability are verified.
- A compact main window plus menu-bar access. Initial controls: server state, services, approved clients, revoke.
- Later ambition is broad Mac integration. Remote networking, computer control, native Reminders tags/subtasks, a plugin marketplace, and multi-user hosting are not first-release requirements.

## Bootstrap (this repository)

- Swift 6 package with native SwiftUI app and a Foundation-independent service inventory.
- App bundling script, canonical check command, and macOS CI workflow.
- No listener, auth implementation, Apple permissions, or fake working controls.
- No third-party runtime dependencies until the implementation spike selects pinned versions.

## 1. OAuth and transport feasibility

Before choosing a large server framework, prove the smallest real Codex flow with the official Swift MCP SDK and an appropriate embedded HTTP implementation. Inspect released SDK source; client OAuth support does not imply an embedded authorization server is provided.

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

Acceptance: connect -> approve -> use -> restart -> reconnect -> revoke -> reject subsequent tool calls and refresh. Pause stops tool access. Closing the window leaves the app available; Quit stops it.

## 4. Bring across the iMCP suite

Port one service at a time through the same dispatcher and authorization path. Review its permission ownership, licensing, return schema, failure behavior, and availability before enabling it. Do not retain Bonjour or stdio relay infrastructure simply because upstream has it.

Messages/Phone may need selected-file access and non-EventKit libraries; WeatherKit may require developer capabilities. Keep unavailable services visibly unavailable. Avoid private APIs unless separately decided and documented.

Acceptance: per-service read and permitted disposable write checks; disabled services cannot be invoked by name; protocol tools list matches actual implemented and enabled capability.

## 5. Personal release, then publication

Verify app identity, signing, entitlements, permission prompts, launch/reopen, sleep/wake, startup failure, and memory at idle. Choose update/distribution machinery only when needed. Public source release does not require finished notarized binaries.

Publish only after owner approval of visibility. Keep original notices for imported code, review tracked files for private data, and describe supported clients and known limitations honestly.

## First useful release gate

Codex on this Mac logs in once, lists enabled tools, edits and deletes a disposable reminder, reconnects after app restart, and loses access after revoke. The existing production integrations are replaced only after this proof and explicit cutover authorization.
