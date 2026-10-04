import IMCPCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var runtime: AppRuntime

  var body: some View {
    TabView {
      Form {
        ForEach(AppleService.allCases) { service in
          Section {
            ForEach(runtime.tools.filter { $0.service == service }) { tool in
              Toggle(
                isOn: Binding(
                  get: { !runtime.settings.disabledTools.contains(tool.name) },
                  set: { enabled in Task { await runtime.setToolEnabled(tool.name, enabled) } }
                )
              ) {
                VStack(alignment: .leading, spacing: 3) {
                  HStack {
                    Text(
                      tool.name.replacingOccurrences(of: "\(service.rawValue)_", with: "")
                        .replacingOccurrences(of: "_", with: " ").capitalized)
                    if tool.readOnly {
                      Text("Read-only").font(.caption2).foregroundStyle(.secondary)
                    }
                  }
                  Text(tool.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
              }
              .toggleStyle(.switch).controlSize(.small)
              .tint(service.color)
              .disabled(
                !runtime.settings[service] || runtime.changingService != nil
                  || runtime.changingTool != nil)
            }
          } header: {
            ServiceRow(runtime: runtime, service: service)
          } footer: {
            Text(runtime.serviceStatus[service] ?? "Disabled")
          }
        }
        Text(
          "Controls apply to every approved client across available accounts. Reconnect clients after changing tools."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      .formStyle(.grouped)
      .tabItem { Label("Services", systemImage: "switch.2") }

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          ApprovalsView(runtime: runtime)
          Text("Approved clients").font(.headline)
          if runtime.clients.isEmpty {
            Text("No approved clients").foregroundStyle(.secondary)
          }
          ForEach(runtime.clients) { client in
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(client.clientName).font(.headline)
                Text(client.createdAt, style: .date).font(.caption)
                Text(String(client.id.uuidString.prefix(8))).font(.caption.monospaced())
              }
              Spacer()
              Button("Revoke", role: .destructive) { Task { await runtime.revoke(client) } }
            }
          }
          Text(
            "Approval lasts until revoked. Each client has independent credentials and shares the globally enabled tools."
          )
          .font(.callout).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
      }
      .tabItem { Label("Connections", systemImage: "person.2") }

      SetupView(resource: runtime.configuration.resource)
        .tabItem { Label("Setup", systemImage: "link") }
    }
    .padding(8)
    .frame(width: 580, height: 540)
    .onAppear { runtime.refreshServiceStatus() }
    .alert(
      "iMCP-HTTP",
      isPresented: Binding(
        get: { runtime.errorMessage != nil },
        set: { if !$0 { runtime.errorMessage = nil } }
      )
    ) {
      Button("OK") { runtime.errorMessage = nil }
    } message: {
      Text(runtime.errorMessage ?? "")
    }
  }
}
