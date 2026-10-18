# Setup and troubleshooting

Start with the [source build instructions](../README.md#build-and-run). The alpha has no downloadable installer or Homebrew cask yet. A developer account is not needed for the documented local ad-hoc build.

## First connection

1. Open the app and confirm the server is running. Start, Pause, and Retry are available in both the window and menu panel.
2. In Services, enable the service and individual tools you want the client to use. Accept the corresponding macOS permission prompt. Expand a service to review its tools; newly enabled services expand automatically.
3. Follow the client's recipe in Setup. Approve only a login you initiated, then complete macOS authentication.
4. Ask the client to call `connection_check`. This checks the connection without accessing Apple records. If testing a write, use a clearly named disposable item and confirm its removal afterward.

Service and tool switches apply to every approved client. Closing the window keeps the server running. Use Pause to stop access temporarily, Revoke to remove a connection's authorization, or Quit to stop the app.

Use Command-1, Command-2, and Command-3 for Services, Connections, and Setup. The toolbar Help button and Help menu open instructions that work offline. Copy buttons briefly show “Copied” after success. A pending request appears in the Connections tab count and a review button on other tabs.

## Common problems

| Symptom | What to check |
| --- | --- |
| Client cannot connect | Confirm the app is running and not paused, and the client uses `http://127.0.0.1:18765/mcp` on the same Mac. Check the app for a listener error or another copy already running. |
| Hosted connector cannot reach the app | The server accepts loopback connections only. A hosted connector cannot directly reach this Mac's loopback address. See the client's compatibility note in Setup. |
| Login expires or authentication is canceled | Start a fresh login from the client and approve that request. Cancellation grants no access. A displayed client name is not proof of identity. |
| Connection works but tools are missing | Check the service and individual-tool switches, then macOS permission availability. Reconnect the client to refresh its cached tool list. |
| Permission was denied | The affected service expands with a recovery message. Choose Privacy & Security, review the relevant category, then Try again. Mail and Notes use Automation permission. No service is enabled merely by opening settings. |
| Mail or Notes is unavailable | Keep the target app open and confirm its account has loaded. Re-enable the service if necessary to request Automation permission. These apps may synchronize when opened. |
| Permissions changed after rebuilding | Ad-hoc builds may need approval again. Quit before replacing a bundle. Persistence across Developer ID updates has not yet been verified. |
| A write timed out or returned an uncertain outcome | Inspect the saved item in the native Apple app before retrying. The operation may already have completed. |

Do not remove local state or reset all macOS privacy permissions as a routine troubleshooting step. A permission problem and a client authorization problem have different causes.

## Updating and removing a source build

Quit the app before rebuilding or replacing it. Read the changelog first: alpha saved-state formats may change and downgrade compatibility is not guaranteed. Keep a private backup of local app state before an upgrade that changes storage.

The default state directory is `~/Library/Application Support/iMCP-HTTP`. It contains sensitive authorization state and service choices, not a copy of Apple records. Do not attach it to bug reports. Custom development runs may use `IMCP_HTTP_DATA_DIR` instead.

To remove the app, revoke its client connections, remove the corresponding client configurations, quit, and move the app bundle to the Trash. This leaves local state in place. Delete that state separately only if you intend to discard saved authorizations and preferences. Removing the app does not delete records previously created in Apple services or automatically clear macOS privacy decisions.

## Reporting a problem

Include the app version, macOS version, affected service/client, expected result, actual result, and steps using disposable data in a [bug report](https://github.com/huglyfe/iMCP-HTTP/issues/new?template=bug_report.yml). Include an error code if available. Exclude tokens, account names, record content, state files, and screenshots of unrelated data.

Check the [acceptance gaps](PLAN.md#verification-boundary) before treating an untested account or device workflow as supported.
