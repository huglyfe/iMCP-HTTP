# Behavior requirements

These are product contracts. Current implementation and verification limits are described in `ARCHITECTURE.md` and `PLAN.md`.

## OAuth and owner approval

- Standard MCP-compatible OAuth authorization code + PKCE S256. No custom client software or repeated manual token pasting in the intended experience.
- Authenticate the owner's decision through the native app, bound to one pending authorization request. A browser page or client-supplied name alone cannot approve itself.
- Keep the first UI minimal: client label, explanation of account-wide enabled access, Approve, Deny. Show the client identifier/details when needed to distinguish requests.
- The grant persists until explicitly revoked. Store a distinct grant per authorized connection; do not use one shared owner API key.
- Pending requests and codes expire; codes are single-use, bound to client, callback, resource, and PKCE challenge. Bound pending requests and attempts to prevent unbounded approval prompts.
- Serve protected-resource and authorization-server metadata appropriate to the negotiated MCP/OAuth profile. Use a stable issuer/resource and strict registered callback validation, including standard loopback-port rules.
- Validate issuer, resource/audience, credential expiry, grant revocation, and scope on every applicable exchange/request. Use one account-access scope initially if needed by the protocol; no granular permission editor.
- Access/refresh credentials remain out of URLs, tool results, logs, repository config, screenshots, and support dumps. Authorization-code callbacks follow the standard flow and must not be logged.
- Rotate refresh credentials atomically and define replay handling; revoked grants cannot refresh. A credential refresh is not a new owner approval.
- Client labels are untrusted display data. They do not establish application identity or ownership.
- The app's local controls own authorization management; MCP tools do not issue grants or approve new clients.

## HTTP and lifecycle

- Loopback binding only; reject unexpected Host and Origin values to prevent browser-origin abuse. Implement standard MCP Origin behavior, including rejection of an invalid supplied Origin and support for legitimate native clients without one.
- No unauthenticated tool calls, including on loopback. Protocol discovery may remain public where required.
- No wildcard CORS or implicit authentication fallback. Bound request sizes, connection count, and pending work.
- Bind failures are visible as failures, never a green Running state. Stop/Quit closes listeners and live sessions.
- Restart recovers durable grants and revocations, not pending approvals or in-progress tool calls.
- No automatic retry of Apple mutations after an unknown outcome.

## Tools and Apple access

- All approved clients share globally enabled services across the current macOS user's available accounts. No per-list restrictions in the first release.
- Global enablement and current OS permissions are enforced on calls, not only when listing tools.
- The tool list contains implemented, available, enabled tools; planned service names are never advertised as working tools.
- Preserve the iMCP suite as the initial inventory, subject to adapter acceptance and OS/developer capability constraints.
- Use explicit read-only/destructive annotations and machine-readable errors/results. An annotation is not access control.
- The app does not promise tool-call approval dialogs inside Codex; client-side approval policy remains the client's responsibility.

## Reminders: first useful slice

- List and fetch return opaque list/item identifiers and account/source context so duplicate names are distinguishable.
- Editing and deletion require a specific identifier. Stale, missing, inaccessible, and read-only targets fail clearly.
- Editing supports title, notes, priority, and due date first; distinguish omission from explicit clearing. List moves follow once verified.
- Reject invalid dates and unknown targets; do not silently discard invalid input or change a different list.
- Date-only deadlines remain date-only. Timed deadlines preserve the documented timezone behavior.
- Delete operates on the exact identified item, including completed reminders. Return success only after framework confirmation; subsequent read verifies absence during acceptance.
- Re-fetch before mutation where needed to avoid overwriting unrelated native fields; document any unavoidable concurrency limitations.
- Native subtasks, tags, sections, recurrence editing, and bulk operations are later feasibility/implementation slices. Never emulate native features in notes without explicit product agreement.

## Verification

When implementation starts, add Swift tests for validation, authorization transitions, dispatch enforcement, and adapter behavior using fakes/disposable storage. Add real listener tests for protocol boundaries. CI must run actual tests once present.

Manual acceptance uses Codex and disposable Apple data: prove successful behavior, rejection, revocation, restart, and cleanup. Neither source inspection, open TCP ports, a successful build, nor permission settings alone establish acceptance.

## References

- [MCP authorization](https://modelcontextprotocol.io/specification/latest/basic/authorization)
- [MCP transports](https://modelcontextprotocol.io/specification/latest/basic/transports)
- [Codex MCP documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)

Consult current specifications during implementation; record the tested protocol and client versions with acceptance evidence.

## Implemented Reminders contract

Calls require an active grant, global Reminders enablement, and current full EventKit authorization. All accounts/lists available to the current macOS user share that permission. Services are checked on dispatch and again inside the adapter. Disabled tools cannot be invoked directly by name.

- `reminders_lists`: no arguments; returns `lists` with `id`, `title`, `account`, `accountID`, `writable`.
- `reminders_fetch`: required `listID`; optional `completed` boolean (omitted means both), `offset` 0–100000 (default 0), `limit` 1–200 (default 100). Returns `reminders`, `total`, optional `nextOffset`. Sorted by opaque item ID. A changing list can shift pages; restart pagination after mutations. EventKit fetches the selected list internally; the app retains no database/cache.
- `reminders_get`: required exact `id`. Includes completed items.
- `reminders_create`: required `listID` and `changes` object with a nonempty `title`.
- `reminders_edit`: required exact `id` and nonempty `changes`. Only `title`, `notes`, `due`, `priority`, and `completed` are supported. Omission preserves the field. Null clears notes/due only. Title is at most 1024 UTF-8 bytes; notes at most 16384. Priority is an integer 0–9 (0 none, 1 highest). Completed true/false completes/reopens.
- `reminders_delete`: required exact `id`; success is `{deleted: true, id: ...}` only after EventKit confirms removal. A missing/stale ID fails, including after a previous successful delete.

Due input accepts strictly valid `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SSZ` / `YYYY-MM-DDTHH:MM:SS±HH:MM` strings. Fractions, offset-free times, and unknown offsets (`-00:00`) are rejected. Date-only values have no time or timezone; timed values normalize to UTC. Due output uses Foundation `DateComponents` (native components/calendar and optional timezone), preserving floating/date-only meaning from existing items. A nil notes/due field is omitted in record output; input null explicitly clears it.

Unknown fields and incorrect types fail before mutation. No default list fallback, list moves, recurrence edits, alarms, tags, sections, subtasks, or bulk writes. Existing unrelated EventKit fields are left alone. The adapter refreshes the exact object before patching, but EventKit does not provide an atomic compare-and-swap against concurrent edits from other apps.

Writes are serialized on the main actor without automatic retries. EventKit errors return `write_failed` and instruct readback before retrying because no success was confirmed. Unsaved cached object changes are reset after a failure. HTTP disconnect or process termination during a write can leave an unknown outcome. Read and inspect the target/list before any retry.

Tool failures carry a readable message, MCP `isError`, and `_meta.errorCode` where the tool handler ran. Codes include `invalid_arguments`, `unknown_tool`, `service_unavailable`, `service_disabled`, `permission_denied`, `not_found`, `read_only`, `write_failed`, `read_failed`, `busy`, and `timeout`. SDK-level validation may report its own MCP error before dispatch. Reads are limited to four concurrent EventKit fetches with a 15-second cancellable timeout.
