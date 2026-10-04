import SwiftUI

@main
struct IMCPHTTPApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    MenuBarExtra {
      OverviewView(runtime: delegate.runtime)
    } label: {
      MenuIcon(runtime: delegate.runtime)
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(runtime: delegate.runtime)
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let runtime = AppRuntime()

  func applicationDidBecomeActive(_ notification: Notification) {
    runtime.refreshServiceStatus()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Server lifetime belongs to the app, independent of whether its panel is open.
    runtime.startIfNeeded()
  }
}

private struct MenuIcon: View {
  @ObservedObject var runtime: AppRuntime

  var body: some View {
    Image(
      systemName: runtime.approvals.isEmpty
        ? "externaldrive.connected.to.line.below" : "person.crop.circle.badge.exclamationmark"
    )
    .accessibilityLabel(
      runtime.approvals.isEmpty
        ? "iMCP-HTTP: \(runtime.state.title)" : "iMCP-HTTP: connection awaiting approval")
  }
}
