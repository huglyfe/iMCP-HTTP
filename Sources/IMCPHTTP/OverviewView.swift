import IMCPCore
import SwiftUI

/// iMCP's compact menu-bar interaction, backed by this app's HTTP runtime.
struct OverviewView: View {
  @ObservedObject var runtime: AppRuntime
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("iMCP-HTTP").font(.headline)
          Text(runtime.state.title).font(.caption).foregroundStyle(.secondary)
        }
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
        .disabled(runtime.state == .starting || runtime.state == .stopping)
      }
      Divider()
      Text("Services").font(.caption).foregroundStyle(.secondary)
      ForEach(AppRuntime.services) { service in
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
      Button("Copy Codex setup command") { runtime.copyConnectionCommand() }
      Button("Settings…") {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
      }
      Divider()
      Button("Quit iMCP-HTTP") { Task { await runtime.quit() } }
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
        .foregroundStyle(runtime.settings[service] ? .white : .secondary)
        .frame(width: 26, height: 26)
        .background(
          runtime.settings[service] ? Color.accentColor : Color.secondary.opacity(0.12),
          in: Circle())
      Toggle(
        service.title,
        isOn: Binding(
          get: { runtime.settings[service] },
          set: { enabled in Task { await runtime.setEnabled(service, enabled) } })
      )
      .toggleStyle(.switch).controlSize(.small)
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
    default: "gearshape"
    }
  }
}

struct ApprovalsView: View {
  @ObservedObject var runtime: AppRuntime

  var body: some View {
    ForEach(runtime.approvals) { request in
      VStack(alignment: .leading, spacing: 8) {
        Text("Connection request: \(request.clientID)").font(.headline)
        Text("Allow access to enabled tools until revoked?").font(.callout)
        Text("Approve only a login you just started. Client IDs are unverified labels.")
          .font(.caption).foregroundStyle(.secondary)
        Text(request.callback).font(.caption.monospaced()).textSelection(.enabled)
        HStack {
          Button("Deny", role: .cancel) { Task { await runtime.decide(request, approve: false) } }
          Spacer()
          Button("Approve") { Task { await runtime.decide(request, approve: true) } }
            .buttonStyle(.borderedProminent)
        }
      }
    }
  }
}
