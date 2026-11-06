import IMCPCore
import SwiftUI

/// The familiar compact panel shares the main window’s single runtime.
struct OverviewView: View {
  @ObservedObject var runtime: AppRuntime
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ServerStatusView(runtime: runtime)
      Divider()
      Text("Services").font(.caption).foregroundStyle(.secondary)
      ForEach(AppleService.allCases) { service in
        ServiceRow(runtime: runtime, service: service)
          .disabled(runtime.state != .running)
          .opacity(runtime.state == .running ? 1 : 0.5)
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
    .frame(width: 320)
    .onAppear { runtime.refreshServiceStatus() }
  }
}

struct ServiceRow: View {
  @ObservedObject var runtime: AppRuntime
  let service: AppleService

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: service.icon)
        .accessibilityHidden(true)
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
      .accessibilityValue(
        runtime.serviceIssues[service] ?? runtime.serviceStatus[service] ?? "Disabled")
      if runtime.changingService == service {
        ProgressView().controlSize(.small).accessibilityLabel(
          "Requesting access to \(service.title)")
      }
      if runtime.serviceIssues[service] != nil {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          .accessibilityLabel(
            "\(service.title) needs attention. Open the main window to resolve it.")
      }
    }
    .help(runtime.serviceStatus[service] ?? "Disabled")
  }
}

extension AppleService {
  var icon: String {
    switch self {
    case .photos: "photo"
    case .bluetooth: "antenna.radiowaves.left.and.right"
    case .mail: "envelope"
    case .notes: "note.text"
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
    case .bluetooth: .indigo
    case .mail: .cyan
    case .notes: .yellow
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
          .lineLimit(2).truncationMode(.middle).help(request.callback)
        HStack {
          Button("Deny") { Task { await runtime.decide(request, approve: false) } }
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
      .padding(12)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
  }
}
