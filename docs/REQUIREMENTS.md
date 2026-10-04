# Behavior requirements

These are product contracts. Current implementation and verification limits are described in `ARCHITECTURE.md` and `PLAN.md`.

## OAuth and owner approval

- Standard MCP-compatible OAuth authorization code + PKCE S256, with RFC 7591 dynamic registration for public local clients. No custom client software or repeated manual token pasting in the intended experience.
- Authenticate the owner's decision through the native app, bound to one pending authorization request. A browser page or client-supplied name alone cannot approve itself.
- Keep the first UI minimal: client label, explanation of account-wide enabled access, Approve, Deny. Show the client identifier/details when needed to distinguish requests.
- The grant persists until explicitly revoked. Store a distinct grant per authorized connection; do not use one shared owner API key.
- Registration accepts only bounded local callback metadata, creates no approval or grant, and uses the same atomic store as grants. Bound registration rate and count; unused registrations may be pruned, while active grants keep their client registration. No client-specific authentication branches or legacy store migration.
- Pending requests and codes expire; codes are single-use, bound to client, callback, resource, and PKCE challenge. Bound pending requests and attempts to prevent unbounded approval prompts.
- Serve protected-resource and authorization-server metadata appropriate to the negotiated MCP/OAuth profile. Use a stable issuer/resource and strict registered callback validation, including standard loopback-port rules.
- Validate issuer, resource/audience, credential expiry, grant revocation, and scope on every applicable exchange/request. Use one account-access scope initially if needed by the protocol; no granular permission editor.
- Access/refresh credentials remain out of URLs, tool results, logs, repository config, screenshots, and support dumps. Authorization-code callbacks follow the standard flow and must not be logged.
- Rotate refresh credentials atomically and define replay handling; revoked grants cannot refresh. A credential refresh is not a new owner approval.
- Client labels are untrusted display data. They do not establish application identity or ownership.
- The app's local controls own authorization management; MCP tools do not issue grants or approve new clients.

## Native interface

- iMCP-style menu-bar-only accessory app: no Dock icon or main application window. A compact panel holds server/service controls; Settings may open on demand.
- The menu panel omits the setup-command button and app-name subtitle. Distinct service colors apply consistently in the panel and Settings. Setup contains an alphabetical, searchable client directory with instructions, copyable configuration, vendor links, and honest compatibility labels. Hosted clients that cannot reach loopback have explanatory entries rather than nonfunctional setup commands.
- Settings exposes individual tools within each service, client approval/revocation, and connection setup. Tool choices are global across all approved clients and available accounts, not client-specific permissions.
- Disabled tools are omitted from discovery and rejected on subsequent calls by name, including stale client discovery. Persist choices across restart; turning a service off still blocks every tool in it.
- Start the server at app launch independently of menu-panel presentation. Dismissing panels/Settings leaves it running; Quit stops it. Keep one process, lazy native stores, and measure idle memory before claiming RAM improvements.

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
- Editing supports title, notes, priority, and due date first; distinguish omission from explicit clearing. Moves require exact source item and writable destination list identifiers.
- Reject invalid dates and unknown targets; do not silently discard invalid input or change a different list.
- Date-only deadlines remain date-only. Timed deadlines preserve the documented timezone behavior.
- Delete operates on the exact identified item, including completed reminders. Return success only after framework confirmation; subsequent read verifies absence during acceptance.
- Re-fetch before mutation where needed to avoid overwriting unrelated native fields; document any unavoidable concurrency limitations.
- Native subtasks, tags, sections, and bulk operations remain outside the implemented public-API contract. Never emulate native features in notes without explicit product agreement.

## Verification

When implementation starts, add Swift tests for validation, authorization transitions, dispatch enforcement, and adapter behavior using fakes/disposable storage. Add real listener tests for protocol boundaries. CI must run actual tests once present.

Manual acceptance uses Codex and disposable Apple data: prove successful behavior, rejection, revocation, restart, and cleanup. Neither source inspection, open TCP ports, a successful build, nor permission settings alone establish acceptance.

## References

- [MCP authorization](https://modelcontextprotocol.io/specification/latest/basic/authorization)
- [MCP transports](https://modelcontextprotocol.io/specification/latest/basic/transports)
- [Codex MCP documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)

Consult current specifications during implementation; record the tested protocol and client versions with acceptance evidence.

## Common tool contract

Tools return JSON objects, with no prose success envelope. Fetch returns compact records and an optional `nextOffset`; get/create/edit/move return the supported detail record. Optional absent values are omitted. Account labels and write capabilities belong to list/account discovery, not every item. Deletes return `{ "deleted": true, "id": "..." }` after framework confirmation.

Use exact identifiers returned by discovery. No fuzzy write targeting, implicit default destination, automatic retry, or bulk writes. Omission preserves a patch field; explicit null and unknown fields fail. `clear` removes optional scalar fields. Replacement arrays use `[]` to clear. Contacts text fields clear with an empty string. Pages are not snapshots: restart after mutations.

Titles are nonempty and at most 1024 UTF-8 bytes; notes at most 16384. Searches are nonempty substrings up to 512 bytes, ignoring case and diacritics. Fetch limits are 1–200 (default 100), offsets 0–100000 (default 0). List/calendar selection accepts 1–50 distinct IDs. Maps has a smaller 1–20 result limit.

Calls require an active OAuth grant and current service availability. EventKit and Contacts writes are serialized on the main actor. Native stores remain authoritative; there is no atomic compare-and-swap against another app's edits. A failed or interrupted write may have an uncertain outcome: read back before retrying. Errors carry MCP `isError` and `_meta.errorCode` when the handler ran; no private framework error details are logged or returned.

## Reminders

| Tools | Arguments / result |
| --- | --- |
| `reminders_accounts`, `reminders_lists` | Discover accounts and lists (`writable` contents, `editable` list metadata). Account support for list creation varies. |
| `reminders_list_create` | `accountID`, `title` → saved list |
| `reminders_list_rename` | `id`, `title` → saved list |
| `reminders_list_delete` | `id` → deletes the list **and its contents** |
| `reminders_fetch` | `query` → `reminders`, `total`, optional `nextOffset`, resolved `timeZone` |
| `reminders_get` | `id` → detail |
| `reminders_create` | `listID`, `changes` with `title` → saved reminder |
| `reminders_edit` | `id`, `changes` → saved reminder |
| `reminders_move` | `id`, `listID` → saved reminder; use its returned ID afterward |
| `reminders_delete` | `id` → deletion |

`query` requires `listIDs`. Optional fields: `search` (title/notes), `completed`, `due`, `dueFrom`, `dueBefore`, `timeZone`, `sort`, `offset`, `limit`. `due` is `any`, `today`, `overdue`, `upcoming`, or `undated`. Today is the full local day; overdue is past timed deadlines or date-only deadlines before today; upcoming begins tomorrow. Alternatively, use inclusive `dueFrom` / exclusive `dueBefore`. Date filters default to incomplete reminders. Sort is `id` or `due` (ascending, undated last, ID ties). EventKit narrows by completion; app filtering/paging reads that matching set without caching it.

`changes` supports `title`, `notes`, `due`, `start`, `url`, `location`, `priority` (0–9), `completed`, `alarms`, `recurrence`, and `clear`. Set `completed` true/false to complete/reopen. Clearable scalars: notes, due, start, url, location. Fetch summaries include ID/list/title/priority/completion/due; get adds the optional details.

Dates use `{ "date": "2026-10-03" }`, or `{ "date": "2026-10-03", "time": "09:00:00", "timeZone": "America/New_York" }`. Time without a zone is floating; a zone requires a time. Gregorian dates and HH:MM:SS are strict; nonexistent DST times fail. Repeated fall-back times use Foundation's resolution. Date-only values stay date-only; native non-Gregorian dates are converted on read.

Reminders recurrence/completion/deletion follows EventKit's native reminder behavior. EventKit offers no reminder occurrence/series scope; the server does not invent one. Tags, subtasks, sections, Smart Lists, geofence editing, and attachment editing are unsupported.

## Calendar

`calendar_accounts`, `calendar_lists`, `calendar_list_create`, `calendar_list_rename`, and `calendar_list_delete` follow the corresponding Reminders list contracts, with list deletion removing all contained events.

| Tool | Arguments |
| --- | --- |
| `calendar_fetch` | `calendarIDs`, `start`, `end`; optional `search`, `offset`, `limit` |
| `calendar_get` | `id`, `start` from a fetched occurrence |
| `calendar_create` | `calendarID`, `changes` |
| `calendar_edit` | `id`, original `start`, explicit `span`, `changes` |
| `calendar_move` | `id`, original `start`, explicit `span`, destination `calendarID` |
| `calendar_delete` | `id`, original `start`, explicit `span` |

Fetch returns occurrences overlapping the supplied positive range (at most 366 days), sorted by start then ID. Search matches title, notes, or location. Results contain `events` and optional `nextOffset`. Get and mutations return detail. Exact ID plus start identifies a recurring occurrence; stale/moved occurrences fail instead of falling back to the first event in the series.

`span` is `thisEvent` or `futureEvents` (selected occurrence onward). Recurrence edits on a repeating event require `futureEvents`. EventKit may notify attendees when shared events change. Attendee/invitation editing is not supported.

`changes`: title, start, end, timeZone, allDay, notes, location, url, availability, alarms, recurrence, clear. Create requires title/start/end/timeZone. Changing any schedule field requires start/end/timeZone together. Start/end are ISO 8601 timestamps with seconds and an explicit UTC offset; timeZone is a named Foundation timezone retained for recurrence. End is exclusive and after start. All-day boundaries must be midnight in that zone, including across DST. Availability is busy/free/tentative/unavailable. Clearable scalars: notes/location/url.

## Alarms and recurrence

Shared by Reminders and Calendar. `alarms` replaces display time alarms, up to eight. Each is `{ "at": "2026-10-03T13:00:00Z" }` or `{ "offsetSeconds": -900 }`. Relative alarms use the item's start; new relative reminder alarms require a start date. `[]` removes display time alarms. Existing geofence, audio, email, or procedure alarms are preserved and counted in `otherAlarms` on detail reads. Native accounts may restrict/truncate alarms; the saved object is authoritative.

`recurrence` replaces the native schedule with up to one rule; `[]` removes it. A rule requires frequency daily/weekly/monthly/yearly. Optional interval defaults to 1. Optional weekdays use Sunday=1 through Saturday=7 and an optional signed ordinal `week`. Selectors include monthDays, months, yearWeeks, yearDays, and positions. Only frequency-compatible combinations are accepted; signed selectors exclude zero. Optional `until` (inclusive timestamp) and `count` are mutually exclusive. Reads include native rule details; no change preserves rules verbatim. Replacing a rule creates a Gregorian EventKit rule with native week-start defaults. Non-Gregorian calendars and custom week-start preservation during replacement are not promised.

## Contacts

| Tools | Arguments / result |
| --- | --- |
| `contacts_accounts` | Available account IDs and names |
| `contacts_fetch` | `accountID`; optional `search`, `groupID`, `offset`, `limit` → name/phone/email summaries and optional nextOffset |
| `contacts_get` | Exact `id` → supported contact details |
| `contacts_create` | `accountID`, `changes` → saved card |
| `contacts_edit`, `contacts_delete` | Exact `id` (and `changes` for edit) |
| `contacts_groups` | `accountID` → group IDs/names |
| `contacts_group_create` | `accountID`, `name` → saved group |
| `contacts_group_rename` | `id`, `name` → saved group |
| `contacts_group_delete` | `id` → removes group, preserves contacts |
| `contacts_group_membership` | `contactID`, `groupID`, `member` → resulting membership; one account only |

Reads and writes use individual stored cards (`unifyResults = false`), retaining organization-only contacts and avoiding implicit linked-card edits. Fetch enumerates only the account/group, applies search to names/phones/emails, and stops after the page plus one result. No global count or address-book mirror.

Fields: givenName, middleName, familyName, prefix, suffix, nickname, organization, department, jobTitle, phones, emails, urls, addresses, birthday. Phone/email/URL values are `{label?, value}`; arrays replace the entire field. Address fields are label/street/city/state/postalCode/country/countryCode. Birthday is `{month, day, year?}`; unknown years remain absent. `clear: ["birthday"]` removes it. Create requires givenName, familyName, or organization. Unfetched fields are preserved. Photos, contact notes, linked-card merging, cross-account moves, and Smart Groups are unsupported. Account/group write support is decided by Contacts on save.

## Maps

- `maps_search(query, near?, limit=10)`: places with name/address/coordinates and optional phone/URL. `near` is `{latitude, longitude}` and biases a 10 km region. Without it, the request uses a world region; no device-location request.
- `maps_directions(from, to, mode=driving, includeSteps=false)`: distanceMeters/travelSeconds and optional instruction steps. Mode is driving or walking; endpoints are coordinates.

Maps is independently enabled and sends supplied queries/coordinates to Apple. It does not require Location permission. Four concurrent requests maximum; native requests are cancelled on caller cancellation or after 20 seconds. Network failures return errors. Transit, live device location, map images, and reverse geocoding remain outside this slice.

## Photos

Read-only metadata through PhotoKit. Tools do not launch Photos.app, export bytes, trigger iCloud media downloads, or access hidden assets. Native authorization uses PhotoKit’s read/write library access level (there is no read-only read-access level); this does not expose write tools. Newly introduced Photos enablement defaults false on old settings.

- `photos_albums(offset=0, limit=100)`: regular and smart album IDs/titles, excluding the hidden album; optional nextOffset. Nested album folders are not enumerated.
- `photos_fetch(query)`: optional albumID, from (inclusive creation timestamp), before (exclusive), media (image/video/audio), favorite, offset, limit. Timestamps use ISO 8601 with seconds and UTC offset. Newest creation first; pages are not snapshots. Result is assets and optional nextOffset.
- `photos_get(id)`: exact visible asset metadata.

Asset metadata: ID, media, optional createdAt, width, height, optional durationSeconds, favorite. No private database, titles/captions/keywords/faces search, image content, full-library caching, or export. Standard page limits apply. Native results are capped at offset + limit + one and only the requested page is converted.
