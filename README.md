# iMCP-HTTP

<img src="App/AppIcon.png" alt="iMCP-HTTP app icon" width="96" height="96">

[![Check](https://github.com/huglyfe/iMCP-HTTP/actions/workflows/ci.yml/badge.svg)](https://github.com/huglyfe/iMCP-HTTP/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
![Platform: macOS 15+](https://img.shields.io/badge/platform-macOS%2015%2B-lightgrey.svg)

iMCP-HTTP is a native Mac app that lets AI clients such as Codex, Claude Code, and Cursor use your Reminders, Calendar, Contacts, Mail, Notes, and other Apple services through the [Model Context Protocol](https://modelcontextprotocol.io). It runs a local MCP server over HTTP, and every client has to be approved by you, on your Mac, through standard OAuth.

Most local MCP servers trust whatever process launches them. This one doesn't. Each client registers, asks for access, and waits until you approve it in the app and confirm with Touch ID or your password. You decide which services and individual tools are exposed, and you can pause or revoke access at any time.

> [!NOTE]
> **0.6.0-alpha.1 (development preview).** Build from source on macOS 15 or later. Expect breaking changes to tools and saved state. Builds are ad-hoc signed; notarized downloads are planned. See [status](#status) for what has been tested against real Apple data.

## Features

- Standard OAuth: dynamic client registration (RFC 7591), authorization code with PKCE, and short-lived rotating tokens. No API keys to paste.
- Each access request appears in the app and must be confirmed with macOS authentication. A client's display name is never treated as proof of identity.
- Every service starts disabled. Each one has per-tool switches, so you can allow reading reminders without allowing deletion.
- 68 typed tools with JSON schemas, exact identifiers for every write, and compact results.
- The server binds only to `127.0.0.1`, validates `Host` and `Origin`, and logs no request or Apple content.
- One small process: a SwiftUI window, a menu-bar panel, and the server share one runtime. No daemon, proxy, or copy of your Apple data.

## Services

| Service | Tools |
| --- | --- |
| Connection | `connection_check` (verifies the connection without touching Apple data) |
| Reminders | Accounts and lists; search, read, create, edit, move, delete; completion, due dates, alarms, recurrence |
| Calendar | Accounts and calendars; search, read, create, edit, move, delete events, including single occurrences of recurring series |
| Contacts | Accounts; search, read, create, edit, delete cards; groups and membership |
| Photos | Albums and filtered asset metadata (no image export, hidden assets excluded) |
| Maps | Place and address search; driving and walking routes for supplied locations |
| Bluetooth LE | Scan, connect, GATT discovery, read/write, notification subscriptions with cursor polling |
| Mail | Accounts and mailboxes; search and read; mark read/flagged, move, delete; create and rename mailboxes. No sending or drafting. |
| Notes | Accounts and folders; search, read, create, replace HTML, append text, move, delete |

Mail and Notes are driven through their public scripting dictionaries and need Automation permission. Full input and output contracts are in [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md#common-tool-contract).

## Quick start

You need full Xcode with Swift 6.2 or later (Command Line Tools alone can't build the SwiftUI macros) and Python 3.

```sh
git clone https://github.com/huglyfe/iMCP-HTTP.git
cd iMCP-HTTP
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./scripts/build-app.sh release
open dist/iMCP-HTTP.app
```

Then open **Services**, enable what you want to share, and accept the macOS permission prompts.

## Connect a client

The server listens at `http://127.0.0.1:18765/mcp`. With Codex:

```sh
codex mcp add imcp-http --url http://127.0.0.1:18765/mcp
```

Codex opens a browser login. Approve the request in the app, confirm with macOS authentication, and you're connected. Ask the client to call `connection_check` to make sure everything works.

The **Setup** tab has recipes for Claude Code, Cursor, Gemini CLI, OpenCode, VS Code, Windsurf, and Zed. Hosted connectors in ChatGPT and Claude Desktop run in the cloud and can't reach a loopback address, so they aren't supported.

Access tokens last 15 minutes and refresh automatically. A connection lasts until you revoke it. Closing the window keeps the server running; **Pause** stops all client access and **Quit** stops the server. After changing which tools are enabled, reconnect clients so they pick up the new tool list.

## Status

Automated tests run against fake services, isolated state, and a real loopback listener. They never read or change your Apple data. Native behavior has been checked by hand with disposable records:

| Service | Verified on real data | Not yet verified |
| --- | --- | --- |
| Reminders | Create, edit, complete, move, delete; alarms, recurrence, due-date filtering | Shared and read-only accounts |
| Calendar | Create, edit, move, delete; recurring series; all-day events across DST | Latest timezone fixes on saved events; shared accounts |
| Contacts | Create, edit, delete cards; custom labels | Groups, organization cards |
| Notes | Create, search, edit, append, move, delete | Locked notes, attachments, cross-account moves |
| Mail | Account and mailbox discovery, search, read | All mutations |
| Photos | Album discovery | Populated libraries, filters, paging |
| Maps | Search, walking directions | Driving directions |
| Bluetooth LE | Scanning | GATT operations against a real peripheral |

Also still open: permission persistence across signed updates, authentication cancel/retry, and sleep/wake. Apple can reject or normalize writes, and an interrupted write may have completed anyway, so inspect the record before retrying.

## Documentation

- [Setup and troubleshooting](docs/HELP.md)
- [Architecture](docs/ARCHITECTURE.md): process layout, OAuth design, and service adapters
- [Requirements](docs/REQUIREMENTS.md): tool contracts and security requirements
- [Distribution](docs/DISTRIBUTION.md): the planned Developer ID and Homebrew release path
- [Contributing](CONTRIBUTING.md) and [security policy](SECURITY.md)

## Acknowledgments

The service inventory was inspired by Mattt's [iMCP](https://github.com/mattt/iMCP). This project is an independent implementation with a different transport and authorization model, and it is not affiliated with iMCP or Apple. It is built on [SwiftMCP](https://github.com/Cocoanetics/SwiftMCP) and [Hummingbird](https://github.com/hummingbird-project/hummingbird).

## License

Apache-2.0. See [LICENSE](LICENSE). Dependencies and the small amount of adapted code keep their original licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
