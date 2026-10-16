import SwiftUI

@main
struct IMCPHTTPApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    Window("iMCP-HTTP · Public Alpha", id: "main") {
      MainView(runtime: delegate.runtime)
    }
    .defaultSize(width: 580, height: 540)

    MenuBarExtra {
      OverviewView(runtime: delegate.runtime)
    } label: {
      MenuIcon(runtime: delegate.runtime)
    }
    .menuBarExtraStyle(.window)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let runtime = AppRuntime()
  private var terminating = false

  func applicationDidBecomeActive(_ notification: Notification) {
    runtime.refreshServiceStatus()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Server lifetime belongs to the app, independent of whether its panel is open.
    runtime.startIfNeeded()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if !terminating {
      terminating = true
      Task {
        await runtime.stop()
        sender.reply(toApplicationShouldTerminate: true)
      }
    }
    return .terminateLater
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
