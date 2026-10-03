import SwiftUI

@main
struct IMCPHTTPApp: App {
  var body: some Scene {
    Window("iMCP-HTTP", id: "main") {
      OverviewView()
    }
    .defaultSize(width: 520, height: 620)
    .windowResizability(.contentMinSize)

    MenuBarExtra("iMCP-HTTP", systemImage: "externaldrive.connected.to.line.below") {
      MenuContent()
    }
  }
}

private struct MenuContent: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text("Server not implemented")
    Button("Open iMCP-HTTP") {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }
    Divider()
    Button("Quit iMCP-HTTP") {
      NSApp.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}
