# iMCP-HTTP

A native Mac app that gives approved AI clients access to Apple services over MCP Streamable HTTP. One process, a main window, and a menu-bar control.

**Development implementation:** loopback HTTP, native OAuth approval, durable client grants, pause/revoke, and native Reminders, Calendar, Contacts, and Maps tools. Real Codex login, fixture tool calls, restart, and revocation are tested. Native UI, macOS permission prompts, and real disposable Apple-service writes still need manual acceptance. This repository remains private.

## Develop

Requires macOS 15+ and Swift 6.2+ with Swift Testing and `swift format` (current full Xcode recommended).

```sh
./scripts/check.sh
open dist/iMCP-HTTP.app
```

Use `./scripts/build-app.sh release` for an optimized development bundle. Bundles are ad-hoc signed, unsandboxed development apps under ignored `dist/`, not notarized releases. Apple data access remains governed by macOS permission and the app's service switch. Production signing and permission persistence across upgrades are release gates.

## Connect Codex

Start the app, then:

```sh
codex mcp add imcp-http --url http://127.0.0.1:18765/mcp --oauth-client-id codex
codex mcp login imcp-http
```

Approve the pending request in the app. The registered public client ID is `codex`; the stable callback is `http://127.0.0.1/callback` with a client-selected ephemeral port. Current Codex defaults to this callback. Native approval is required for each new grant; the client ID alone proves no identity.

Approval lasts until revoked. Tokens expire after 15 minutes and refresh without a new approval. Pause stops access; closing the window keeps the menu-bar app running. Revoke prevents subsequent calls and refresh. Existing calls may already have completed.

Enable each service explicitly in the app and accept its macOS permission prompt when needed. Approved clients share access across this Mac user's available accounts. Maps uses supplied locations and does not request device location. Reconnect clients after changing services to refresh their tool list. There is no per-list policy editor.

## Tools

36 typed tools are implemented. Discovery includes only enabled, available services. Reads return compact JSON summaries; get and mutations return detail; deletion returns `{deleted, id}`. Exact identifiers target writes. No prose success envelopes or implicit default accounts.

| Service | Operations |
| --- | --- |
| Connection | `connection_check`, with no Apple access |
| Reminders | Accounts; list/create/rename/delete lists; fetch/get/create/edit/move/delete reminders; completion, date ranges, URLs, start dates, display alarms, recurrence |
| Calendar | Accounts; list/create/rename/delete calendars; fetch/get/create/edit/move/delete exact occurrences; all-day events, recurrence, alarms, availability |
| Contacts | Accounts; search/get/create/edit/delete individual cards; names, organizations, labeled values, addresses, birthdays; groups and membership |
| Maps | Place/address search; driving/walking distance and travel time; optional instructions |

Example arguments:

```json
{"query":{"listIDs":["<list-id>"],"due":"overdue","timeZone":"America/New_York","sort":"due"}}
```

```json
{"id":"<reminder-id>","changes":{"completed":true,"clear":["due"]}}
```

```json
{"id":"<event-id>","start":"2026-10-03T13:00:00Z","span":"thisEvent","changes":{"title":"Updated title"}}
```

```json
{"accountID":"<contacts-account-id>","search":"Alex","limit":10}
```

See [tool contracts](docs/REQUIREMENTS.md#common-tool-contract) for fields, dates, recurrence, clearing, pagination, and native limitations. Version 0.4.0 changes unreleased schemas/results; reconnect development clients. Location, Shortcuts, Weather, Messages/Phone, and Capture remain future slices; the [prior-art review](docs/INSPIRATION.md#coverage-and-remaining-boundaries) records their API/permission constraints.

## Verification

The canonical check runs fixture tests, a real HTTP listener test, formatting, build, bundle metadata/signature, and whitespace checks. Automated tests never read or write real Apple records or call live Maps.

Optional real Codex acceptance requires `codex` and `python3` on PATH and access to the local keyring:

```sh
IMCP_RUN_CODEX_ACCEPTANCE=1 ./scripts/check.sh
```

It uses isolated temporary state, a unique test credential, and an ephemeral Codex session with no model turns. It approves through the native decision API, tests OAuth, typed Reminders/Calendar/Contacts/Maps tools against fake data, restart, and revocation, then logs out the test credential. It does not verify clicking the native UI or alter production Codex configuration. Listener tests use ports 19765 and 19767.

For isolated manual acceptance, launch the bundle executable with `IMCP_HTTP_DATA_DIR` set to a temporary directory and `IMCP_HTTP_PORT` set to another loopback port. Keep these development overrides out of production launch configuration.

## Project map

- [Plan](docs/PLAN.md): scope, progress, and remaining acceptance gates.
- [Architecture](docs/ARCHITECTURE.md): SDK choice, ownership, protocol and storage.
- [Requirements](docs/REQUIREMENTS.md): behavior and tool contracts.
- [Prior art](docs/INSPIRATION.md) and [agent guide](AGENTS.md).

MIT licensed application code; dependencies retain their licenses. See [third-party notices](THIRD_PARTY_NOTICES.md). Independent of iMCP and Apple; no hosted account or subscription.
