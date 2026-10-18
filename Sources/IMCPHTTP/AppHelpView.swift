import AppKit
import SwiftUI

struct AppHelpView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("iMCP-HTTP Help").font(.title2.bold())
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          section(
            "Connect your first client",
            "Enable a service in Services and accept its macOS permission prompt. Choose your client in Setup, copy its configuration, and start login. In Connections, approve only the request you initiated. Ask the client to call connection_check to verify the connection without reading Apple data."
          )
          section(
            "Control access",
            "Service and tool choices apply to every approved client. Pause stops client access; closing the window keeps the server running. Quit stops the app. Revoke blocks future calls and refreshes, but cannot undo work already started."
          )
          section(
            "Missing tools or permissions",
            "Check the service and tool switches. Review Privacy & Security in System Settings, then use Try again for the affected service. Keep Mail and Notes open. Reconnect your client after changing tools to refresh its list."
          )
          Button("Open Privacy & Security…", action: Self.openPrivacySettings)
          section(
            "Connection problems",
            "The client must run on this Mac. Hosted connectors cannot reach the local listener. If the server cannot start, quit any other copy using its port, then choose Retry. If login expires, start a fresh login in the client."
          )
          section(
            "Updates and uncertain writes",
            "Quit before replacing the app. Development builds may need permission approval again. If a write times out, inspect the item in its Apple app before retrying; it may already have completed."
          )
          Divider()
          Text(
            "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")"
          )
          .font(.caption).foregroundStyle(.secondary)
          Text(
            "Development preview. Signed downloads and Homebrew distribution are not available yet."
          )
          .font(.caption).foregroundStyle(.secondary)
          HStack {
            Link("Project", destination: URL(string: "https://github.com/huglyfe/iMCP-HTTP")!)
            Link(
              "Report a problem",
              destination: URL(
                string: "https://github.com/huglyfe/iMCP-HTTP/issues/new?template=bug_report.yml")!)
            if let licenses = Bundle.main.resourceURL?.appendingPathComponent("Licenses"),
              FileManager.default.fileExists(atPath: licenses.path)
            {
              Button("Licenses") { NSWorkspace.shared.open(licenses) }
            }
          }
          Text(
            "Reports should include versions and disposable reproduction steps. Exclude account details, Apple content, and authorization files."
          )
          .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.padding(24).frame(width: 520, height: 540)
  }

  private func section(_ title: String, _ body: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.headline).accessibilityAddTraits(.isHeader)
      Text(body).fixedSize(horizontal: false, vertical: true)
    }
  }

  static func openPrivacySettings() {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
  }
}
