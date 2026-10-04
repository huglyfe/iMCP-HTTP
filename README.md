# iMCP-HTTP

A native Mac app that gives approved AI clients access to Apple services over MCP Streamable HTTP. One process, an iMCP-style menu-bar panel, and Settings. No Dock icon or main window.

**Development implementation:** loopback HTTP, native OAuth approval, durable client grants, pause/revoke, and native Reminders, Calendar, Contacts, Maps, and read-only Photos metadata tools. Real Codex login, fixture tool calls, restart, and revocation are tested. OpenCode dynamic registration and OAuth login are also tested. Native UI, macOS permission prompts, and real disposable Apple-service writes still need manual acceptance. This repository remains private.

## Develop

Requires macOS 15+ and Swift 6.2+ with Swift Testing and `swift format` (full Xcode required with SDKs that ship SwiftUI macros).

```sh
./scripts/check.sh
open dist/iMCP-HTTP.app
```

If Command Line Tools are selected, run checks with `DEVELOPER_DIR` pointing to the installed full Xcode developer directory. This selects the toolchain for that command without changing the system setting.

Use `./scripts/build-app.sh release` for an optimized development bundle. Bundles are ad-hoc signed, unsandboxed development apps under ignored `dist/`, not notarized releases. Apple data access remains governed by macOS permission and the app's service switch. Production signing and permission persistence across upgrades are release gates.

## Connect Codex

Start the app, then:

```sh
codex mcp add imcp-http --url http://127.0.0.1:18765/mcp
codex mcp login imcp-http
```

Approve the pending request from the menu-bar icon. Clients register automatically using standard OAuth Dynamic Client Registration, then use PKCE and native approval. No client secret or manual token is needed. Names identify requests for display only; approve a login you initiated.

Settings → Setup has a searchable alphabetical directory for ChatGPT, Claude Code, Claude Desktop, Codex, Cursor, Gemini CLI, OpenCode, VS Code, Windsurf, and Zed. Each entry includes vendor documentation and verification status. Local-client recipes use the current endpoint; hosted connector entries explain why they cannot reach this Mac directly. No client configuration or tunnel is installed automatically.

Approval lasts until revoked. Tokens expire after 15 minutes and refresh without a new approval. The server switch pauses access; closing the menu panel or Settings keeps the app running. Revoke prevents subsequent calls and refresh. Existing calls may already have completed.

Enable each service in the menu panel and accept its macOS permission prompt when needed. Settings → Services also exposes individual tool switches. Disabled tools disappear from discovery and subsequent calls by name fail; all approved clients share these global choices. Approved clients share access across this Mac user's available accounts. Photos uses PhotoKit without opening Photos.app; its tools read metadata only. Maps uses supplied locations and does not request device location. Reconnect clients after changing services or tools to refresh their tool list. There is no per-list policy editor.

## Tools

39 typed tools are implemented. Discovery includes only enabled, available services. Reads return compact JSON summaries; get and mutations return detail; deletion returns `{deleted, id}`. Exact identifiers target writes. No prose success envelopes or implicit default accounts.

| Service | Operations |
| --- | --- |
| Connection | `connection_check`, with no Apple access |
| Reminders | Accounts; list/create/rename/delete lists; fetch/get/create/edit/move/delete reminders; completion, date ranges, URLs, start dates, display alarms, recurrence |
| Calendar | Accounts; list/create/rename/delete calendars; fetch/get/create/edit/move/delete exact occurrences; all-day events, recurrence, alarms, availability |
| Contacts | Accounts; search/get/create/edit/delete individual cards; names, organizations, labeled values, addresses, birthdays; groups and membership |
| Photos | Album discovery; date/media/favorite-filtered asset metadata; exact asset metadata. No image export, iCloud media download, or hidden assets |
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

See [tool contracts](docs/REQUIREMENTS.md#common-tool-contract) for fields, dates, recurrence, clearing, pagination, and native limitations. This development revision uses one current settings and grant-store format; no legacy migration is provided. Location, Shortcuts, Weather, Messages/Phone, and Capture remain future slices; the [prior-art review](docs/INSPIRATION.md#coverage-and-remaining-boundaries) records their API/permission constraints.

## Verification

The canonical check runs fixture tests, a real HTTP listener test, formatting, build, bundle metadata/signature, and whitespace checks. Automated tests never read or write real Apple records or call live Maps.

Optional real-client acceptance requires `codex`, `opencode`, and `python3` on PATH and access to the local keyring:

```sh
IMCP_RUN_CLIENT_ACCEPTANCE=1 ./scripts/check.sh
```

The fixtures use standard dynamic registration, isolated temporary state, and the native decision API, with no model turns or production client configuration changes. Codex tests all five services against fake data, restart, and revocation, then logs out its unique test credential. OpenCode tests registration/login and verifies that the server saved the resulting grant. OpenCode tool/restart/revoke acceptance remains unverified: its status command alone does not prove fresh authorized access. These tests do not verify native clicks. Listener tests use ports 19765 and 19767.

For isolated manual acceptance, launch the bundle executable with `IMCP_HTTP_DATA_DIR` set to a temporary directory and `IMCP_HTTP_PORT` set to another loopback port. Keep these development overrides out of production launch configuration.

## Project map

- [Plan](docs/PLAN.md): scope, progress, and remaining acceptance gates.
- [Architecture](docs/ARCHITECTURE.md): SDK choice, ownership, protocol and storage.
- [Requirements](docs/REQUIREMENTS.md): behavior and tool contracts.
- [Prior art](docs/INSPIRATION.md) and [agent guide](AGENTS.md).

MIT licensed application code; dependencies retain their licenses. See [third-party notices](THIRD_PARTY_NOTICES.md). Independent of iMCP and Apple; no hosted account or subscription.
