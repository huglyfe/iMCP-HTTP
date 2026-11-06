# Changelog

All notable changes to this project are documented here. The project uses [semantic versioning](https://semver.org); while in alpha, any release may include breaking changes.

## 0.6.0-alpha.1 (unreleased)

### Added

- Server status and Start/Pause/Retry controls in both the main window and the menu-bar panel.
- Offline in-app help, Command-1/2/3 tab shortcuts, and copy confirmation.
- Pending approvals are visible from every tab, and the Connections tab has an actionable empty state.
- `scripts/package-app.py` builds versioned, architecture-labeled ZIP archives with checksums. Release archives must be Developer ID signed, notarized, and stapled; ad-hoc builds need an explicit `--development` flag.
- App icon for Finder, Dock, and Command-Tab.
- Troubleshooting guide, distribution guide, bug report form, and security policy.

### Changed

- Permission failures now appear next to the affected service, with buttons to open Privacy & Security and retry.
- Busy controls block keyboard activation as well as clicks, and accessibility labels are clearer.
- CI runs once per pull request and once on `main` instead of on every branch push.

## 0.5.0-alpha.3 (2026-10-16)

First public source release.

### Added

- Native Mac window and menu-bar panel. Closing the window keeps the server running.
- Loopback Streamable HTTP MCP server with OAuth dynamic registration, PKCE, macOS-authenticated approval, durable grants, token refresh, pause, and revocation.
- 68 tools for Reminders, Calendar, Contacts, Photos metadata, Maps, Bluetooth LE, Mail, and Notes, with global service and per-tool switches.
- Machine-readable validation errors, compact read summaries, and explicit "uncertain outcome" results when a Mail write can't be read back.
- Bounded CoreBluetooth operations and fixed Mail/Notes scripts with typed arguments and cancellation.
- All-day Calendar events use exclusive end dates and keep their calendar dates across timezones. Changing a reminder's due date preserves or explicitly clears its start date.
- Pinned dependencies, isolated fixture tests, CI across UTC and America/New_York, and bundled dependency notices.
