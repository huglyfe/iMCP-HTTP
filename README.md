# iMCP-HTTP

A native Mac app that gives approved AI clients access to Apple services over MCP Streamable HTTP. One process, a main window, and a menu-bar control.

**Development implementation:** loopback HTTP, native OAuth approval, durable client grants, pause/revoke, and EventKit Reminders tools. Real Codex login, tool use, restart, and revocation are tested. Native UI, macOS permission prompts, and real disposable Reminders writes still need manual acceptance. This repository remains private.

## Develop

Requires macOS 15+ and Swift 6.2+ with Swift Testing and `swift format` (current full Xcode recommended).

```sh
./scripts/check.sh
open dist/iMCP-HTTP.app
```

Use `./scripts/build-app.sh release` for an optimized development bundle. Bundles are ad-hoc signed, unsandboxed development apps under ignored `dist/`, not notarized releases. EventKit access remains governed by macOS permission and the app's service switch. Production signing and permission persistence across upgrades are release gates.

## Connect Codex

Start the app, then:

```sh
codex mcp add imcp-http --url http://127.0.0.1:18765/mcp --oauth-client-id codex
codex mcp login imcp-http
```

Approve the pending request in the app. The registered public client ID is `codex`; the stable callback is `http://127.0.0.1/callback` with a client-selected ephemeral port. Current Codex defaults to this callback. Native approval is required for each new grant; the client ID alone proves no identity.

Approval lasts until revoked. Tokens expire after 15 minutes and refresh without a new approval. Pause stops access; closing the window keeps the menu-bar app running. Revoke prevents subsequent calls and refresh. Existing calls may already have completed.

Enable Reminders explicitly in the app and accept the macOS permission prompt. Approved clients then share access across this Mac user's available Reminders accounts. Reconnect clients after changing services to refresh their tool list. There is no per-list policy editor.

## Tools

`connection_check` never accesses Apple data. When Reminders is enabled and macOS permits access:

| Tool | Behavior |
| --- | --- |
| `reminders_lists` | List exact list/account identifiers and write availability |
| `reminders_fetch` | Paginate one list; optionally filter completed items |
| `reminders_get` | Read an exact item, including completed items |
| `reminders_create` | Create in an explicit list; title required |
| `reminders_edit` | Patch title, notes, due date, priority, completion |
| `reminders_delete` | Delete the exact item |

See [Reminders contract](docs/REQUIREMENTS.md#implemented-reminders-contract) for clearing fields, dates, pagination, and error behavior. Other Apple services are not implemented.

## Verification

The canonical check runs fixture tests, a real HTTP listener test, formatting, build, bundle metadata/signature, and whitespace checks. Automated tests never read or write real reminders.

Optional real Codex acceptance requires `codex` and `python3` on PATH and access to the local keyring:

```sh
IMCP_RUN_CODEX_ACCEPTANCE=1 ./scripts/check.sh
```

It uses isolated temporary state, a unique test credential, and an ephemeral Codex session with no model turns. It approves through the native decision API, tests OAuth/tool use/restart/revoke, then logs out the test credential. It does not verify clicking the native UI or alter production Codex configuration. Listener tests use ports 19765 and 19767.

For isolated manual acceptance, launch the bundle executable with `IMCP_HTTP_DATA_DIR` set to a temporary directory and `IMCP_HTTP_PORT` set to another loopback port. Keep these development overrides out of production launch configuration.

## Project map

- [Plan](docs/PLAN.md): scope, progress, and remaining acceptance gates.
- [Architecture](docs/ARCHITECTURE.md): SDK choice, ownership, protocol and storage.
- [Requirements](docs/REQUIREMENTS.md): behavior and Reminders contract.
- [Prior art](docs/INSPIRATION.md) and [agent guide](AGENTS.md).

MIT licensed application code; dependencies retain their licenses. See [third-party notices](THIRD_PARTY_NOTICES.md). Independent of iMCP and Apple; no hosted account or subscription.
