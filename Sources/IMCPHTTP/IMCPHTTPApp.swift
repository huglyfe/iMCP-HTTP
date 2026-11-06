import SwiftUI

@main
struct IMCPHTTPApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var showingHelp = false

  var body: some Scene {
    Window("iMCP-HTTP · v0.6 Preview", id: "main") {
      MainView(runtime: delegate.runtime, showingHelp: $showingHelp)
        .preferredColorScheme(previewColorScheme)
    }
    .defaultSize(width: 680, height: 660)
    .commands { AppCommands(showingHelp: $showingHelp) }

    MenuBarExtra {
      OverviewView(runtime: delegate.runtime)
        .preferredColorScheme(previewColorScheme)
    } label: {
      MenuIcon(runtime: delegate.runtime)
    }
    .menuBarExtraStyle(.window)
  }

  // Visual acceptance can exercise both appearances without changing the owner's Mac settings.
  private var previewColorScheme: ColorScheme? {
    #if DEBUG
      switch ProcessInfo.processInfo.environment["IMCP_HTTP_PREVIEW_APPEARANCE"] {
      case "light": .light
      case "dark": .dark
      default: nil
      }
    #else
      nil
    #endif
  }
}

private struct AppCommands: Commands {
  @Binding var showingHelp: Bool
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .help) {
      Button("iMCP-HTTP Help") {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        showingHelp = true
      }.keyboardShortcut("?", modifiers: .command)
    }
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
