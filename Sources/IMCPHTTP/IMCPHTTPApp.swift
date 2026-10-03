import SwiftUI

@main
struct IMCPHTTPApp: App {
  @StateObject private var runtime = AppRuntime()

  var body: some Scene {
    Window("iMCP-HTTP", id: "main") {
      OverviewView(runtime: runtime)
        .task { runtime.startIfNeeded() }
    }
    .defaultSize(width: 540, height: 640)
    .windowResizability(.contentMinSize)

    MenuBarExtra("iMCP-HTTP", systemImage: "externaldrive.connected.to.line.below") {
      MenuContent(runtime: runtime)
    }
  }
}

private struct MenuContent: View {
  @ObservedObject var runtime: AppRuntime
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text(runtime.state.title)
    if !runtime.approvals.isEmpty {
      Text("\(runtime.approvals.count) connection awaiting approval")
    }
    Button("Open iMCP-HTTP") {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }
    if runtime.state == .running {
      Button("Pause Access") { Task { await runtime.stop() } }
    } else if runtime.state == .stopped {
      Button("Start Server") { runtime.start() }
    }
    Divider()
    Button("Quit iMCP-HTTP") {
      Task {
        await runtime.stop()
        NSApp.terminate(nil)
      }
    }
    .keyboardShortcut("q")
  }
}
