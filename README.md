# iMCP-HTTP

A native Mac app that gives approved AI clients access to Apple services through a local HTTP MCP server. One window manages services, individual tools, and connections; a compact menu-bar panel keeps the server within reach.

**Public alpha candidate: 0.5.0-alpha.3.** Build from source on macOS 15 or later. APIs and saved-state formats may change. Bundles are ad-hoc signed development apps; notarized downloads and automatic updates are not provided. Native acceptance varies by service; the remaining gaps are listed below.

## Build and run

Install full Xcode with Swift 6.2 or later, complete Xcode's first-launch setup, and have Python 3 on PATH. Command Line Tools alone are insufficient for SDKs that require SwiftUI macros.

```sh
git clone https://github.com/huglyfe/iMCP-HTTP.git
cd iMCP-HTTP
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./scripts/check.sh
./scripts/build-app.sh release
open dist/iMCP-HTTP.app
```

Adjust `DEVELOPER_DIR` if Xcode is installed elsewhere. Checks build a separate bundle under `.build/check/`, so they do not overwrite the app you use. Quit the normal app before rebuilding it. Rebuilding an ad-hoc signed app may require macOS permission approval again.

## Connect a client

The server listens only on `http://127.0.0.1:18765/mcp`. For Codex on the same Mac:

```sh
codex mcp add imcp-http --url http://127.0.0.1:18765/mcp
```

The command starts OAuth login. Approve your pending request in the app, then authenticate with macOS. Approve only a login you initiated: the displayed client name is not proof of application identity. No manual token or client secret is needed.

Enable the services you want in **Services** and accept their macOS permission prompts. All services start disabled. Each service also has individual tool switches, shared by every approved client. Approved clients can access the enabled capabilities across this Mac user's available accounts.

Access persists until revoked. Tokens expire after 15 minutes and refresh automatically. Pause stops client access; closing the window keeps the server running; Quit stops it. Revoke blocks subsequent calls and refreshes but cannot undo work already started. Reconnect clients after changing tool availability to refresh discovery.

**Setup** includes recipes and verification status for other clients. Codex login/tools/restart/revoke and OpenCode registration/login have fixture acceptance. Hosted ChatGPT and Claude connectors cannot reach this loopback endpoint directly; remote exposure is outside this alpha.

## Services

68 typed tools are implemented. Discovery shows only enabled, available capabilities. Fetches return compact summaries; get and mutations return details; deletion returns `{deleted, id}`. Writes use exact identifiers and explicit destinations.

| Service | Operations |
| --- | --- |
| Connection | `connection_check`, with no Apple access |
| Reminders | Accounts, lists, search/read/create/edit/move/delete, completion, dates, alarms, recurrence |
| Calendar | Accounts, calendars, search/read/create/edit/move/delete exact occurrences, all-day events, recurrence, alarms |
| Contacts | Accounts, search/read/create/edit/delete individual cards, groups and membership |
| Photos | Albums and filtered asset metadata; no image export or hidden assets |
| Maps | Place/address search, driving/walking routes and travel time using supplied locations |
| Bluetooth LE | Scan/connect/disconnect, GATT discovery, base64 read/write, notification/indication subscriptions and cursor polling |
| Mail | Accounts/mailboxes, message search/read, read/flag edits, move/delete, mailbox create/rename; no send/draft tools |
| Notes | Accounts/folders, search/read/create, HTML replacement, plain-text append, move/delete |

Mail and Notes use the apps' public scripting dictionaries and require Automation permission; those apps may launch and synchronize. BLE uses CoreBluetooth, shares connections/subscriptions across clients, and releases them on pause, disable, or quit. No device-specific protocol is assumed.

See [tool contracts](docs/REQUIREMENTS.md#common-tool-contract) for fields, pagination, dates, clearing, and native limitations. For example, `reminders_edit` preserves omitted fields:

```json
{"id":"<reminder-id>","changes":{"completed":true,"clear":["due"]}}
```

## Alpha limitations and verification

- Disposable native tests have exercised Reminders and Calendar creation, edits, moves, recurrence, deletion, and cleanup; Contacts card edits/deletion; and Notes creation, edits, append, move, and deletion. This is evidence for those workflows, not every account type or OS release.
- BLE scanning, Mail reads, Photos album/empty-library reads, and Maps search/walking routes have native smoke evidence. BLE GATT, Mail mutations, populated Photos filters/paging, Contacts group workflows, and account restrictions remain unverified. Notes locked/attachment rejection and cross-account moves also need acceptance.
- The latest Calendar schedule corrections have fixture coverage but still need saved-record acceptance on the release build. Permission persistence across rebuilt apps, authentication cancellation/retry, sleep/wake, and enabled-service memory behavior remain open.
- Apple may reject writes or normalize content. An interrupted mutation can have an uncertain outcome; inspect saved state before retrying. Native deletion follows the app/account's retention rules.
- There is one current settings/grant format and no automatic migration guarantee during alpha. No remote listener, per-client tool policy, background daemon, or private Apple database access is included.

Automated checks use fake service data, isolated temporary state, a real loopback HTTP listener, and fixed script fixtures. They do not read or mutate personal Apple records, initialize the Bluetooth radio, or call live Maps. Native acceptance is tracked separately in the [plan](docs/PLAN.md#native-acceptance).

## Release scope

The first public release is a source alpha. Version 0.6 is planned for Developer ID-signed, notarized downloads, permission-persistence testing across updates, and selected services that require Apple capabilities. Each service still needs its own entitlement, provisioning, and native acceptance; signing alone does not enable it. Automatic updates are not part of the current release.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for focused tests, formatting, client fixtures, and isolated manual runs. The [architecture](docs/ARCHITECTURE.md), [requirements](docs/REQUIREMENTS.md), [plan](docs/PLAN.md), and [prior-art review](docs/INSPIRATION.md) describe implementation boundaries and remaining work.

Original application code is licensed under [Apache-2.0](LICENSE). Dependencies and adapted code retain their original licenses; see [third-party notices](THIRD_PARTY_NOTICES.md). This project is independent of iMCP and Apple.
