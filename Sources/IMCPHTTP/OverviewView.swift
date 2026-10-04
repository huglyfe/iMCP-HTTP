import IMCPCore
import SwiftUI

/// The familiar compact panel shares the main window’s single runtime.
struct OverviewView: View {
  @ObservedObject var runtime: AppRuntime
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("iMCP-HTTP").font(.headline)
        Spacer()
        Toggle(
          "Enable MCP Server",
          isOn: Binding(
            get: { runtime.state == .running },
            set: { enabled in
              if enabled { runtime.start() } else { Task { await runtime.stop() } }
            })
        )
        .toggleStyle(.switch).labelsHidden()
        .help(runtime.state.title)
        .accessibilityValue(runtime.state.title)
        .disabled(runtime.state == .starting || runtime.state == .stopping)
      }
      Divider()
      Text("Services").font(.caption).foregroundStyle(.secondary)
      ForEach(AppleService.allCases) { service in
        ServiceRow(runtime: runtime, service: service)
      }
      if !runtime.approvals.isEmpty {
        Divider()
        ScrollView {
          ApprovalsView(runtime: runtime)
        }.frame(maxHeight: 220)
      }
      if let error = runtime.errorMessage {
        Text(error).font(.caption).foregroundStyle(.red)
        Button("Dismiss") { runtime.errorMessage = nil }
      }
      Divider()
      Button("Open iMCP-HTTP…") {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
      }
      Divider()
      Button("Quit iMCP-HTTP") { NSApp.terminate(nil) }
    }
    .buttonStyle(.plain)
    .padding(14)
    .frame(width: 300)
    .onAppear { runtime.refreshServiceStatus() }
  }
}

struct ServiceRow: View {
  @ObservedObject var runtime: AppRuntime
  let service: AppleService

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: service.icon)
        .foregroundStyle(runtime.settings[service] ? .white : service.color)
        .frame(width: 26, height: 26)
        .background(
          runtime.settings[service] ? service.color : service.color.opacity(0.12),
          in: Circle())
      Toggle(
        service.title,
        isOn: Binding(
          get: { runtime.settings[service] },
          set: { enabled in Task { await runtime.setEnabled(service, enabled) } })
      )
      .toggleStyle(.switch).controlSize(.small)
      .tint(service.color)
      .disabled(runtime.changingService != nil || runtime.changingTool != nil)
    }
    .help(runtime.serviceStatus[service] ?? "Disabled")
  }
}

extension AppleService {
  var icon: String {
    switch self {
    case .photos: "photo"
    case .reminders: "list.bullet"
    case .calendar: "calendar"
    case .contacts: "person.crop.circle"
    case .maps: "map"
    }
  }

  var color: Color {
    switch self {
    case .reminders: .blue
    case .calendar: .red
    case .contacts: .orange
    case .maps: .green
    case .photos: .purple
    }
  }
}

struct ApprovalsView: View {
  @ObservedObject var runtime: AppRuntime

  var body: some View {
    ForEach(runtime.approvals) { request in
      VStack(alignment: .leading, spacing: 8) {
        Text("Connection request: \(request.clientName)").font(.headline)
        Text("Allow access to enabled tools until revoked?").font(.callout)
        Text("macOS will ask you to authenticate.").font(.caption).foregroundStyle(.secondary)
        Text("Approve only a login you just started. Client names are unverified labels.")
          .font(.caption).foregroundStyle(.secondary)
        Text("Client ID: \(request.clientID)").font(.caption.monospaced()).textSelection(.enabled)
        Text(request.callback).font(.caption.monospaced()).textSelection(.enabled)
        HStack {
          Button("Deny", role: .cancel) { Task { await runtime.decide(request, approve: false) } }
          Spacer()
          if runtime.authenticatingRequestID == request.id {
            ProgressView().controlSize(.small)
          }
          Button(runtime.authenticatingRequestID == request.id ? "Authenticating…" : "Approve") {
            Task { await runtime.decide(request, approve: true) }
          }
          .buttonStyle(.borderedProminent)
          .disabled(runtime.authenticatingRequestID != nil || runtime.state != .running)
        }
      }
    }
  }
}
