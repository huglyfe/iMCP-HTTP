# Changelog

## Unreleased

- Bundle the approved app icon for Finder, Dock, and Command-Tab using generated standard and Retina representations.
- Label the main window and README explicitly as a public alpha.

## 0.5.0-alpha.3 - source published 2026-10-16

First public source alpha. Earlier alpha builds were private development builds. No tagged GitHub release or binary download was published.

- Native Mac window and persistent menu-bar controls. Closing the window keeps the local server running.
- Loopback Streamable HTTP MCP with OAuth dynamic registration, PKCE, macOS-authenticated approval, durable grants, refresh, pause, and revocation.
- Global service and individual-tool switches across 68 tools for Reminders, Calendar, Contacts, Photos metadata, Maps, BLE, Mail, and Notes.
- Calendar all-day schedules use exclusive ends and preserve civil dates across input and Mac timezones. Reminder due-date changes preserve or explicitly clear the start.
- Required create inputs and output fields, machine-readable validation errors, compact read summaries, native Contacts labels, and explicit uncertain outcomes after Mail mutations.
- Bounded CoreBluetooth operations and fixed Mail/Notes scripts with a shared automation runner, typed arguments, and cancellation handling.
- Pinned dependencies, isolated fixture tests, UTC/DST CI coverage, staged app builds, and bundled dependency notices.
- Apache-2.0 original code with retained third-party licenses.

Native acceptance and remaining gaps are recorded in [the plan](docs/PLAN.md#verification-boundary). BLE GATT, Mail mutations, populated Photos queries, some account restrictions, the latest Calendar changes on saved records, sleep/wake, and permission persistence remain open. This source alpha provides ad-hoc development bundles. Developer ID-signed and notarized distribution is planned for v0.6.
