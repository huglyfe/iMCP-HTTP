import IMCPCore
import SwiftUI

struct MainView: View {
  @ObservedObject var runtime: AppRuntime
  @State private var selection = Tab.services

  private enum Tab: String, CaseIterable {
    case services = "Services"
    case connections = "Connections"
    case setup = "Setup"
  }

  var body: some View {
    VStack(spacing: 0) {
      Picker("Section", selection: $selection) {
        ForEach(Tab.allCases, id: \.self) { tab in
          Text(tab.rawValue).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .controlSize(.large)
      .frame(maxWidth: 360)
      .padding(.horizontal, 20)
      .padding(.vertical, 12)

      Divider()

      Group {
        switch selection {
        case .services: services
        case .connections: connections
        case .setup: SetupView(resource: runtime.configuration.resource)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(minWidth: 580, minHeight: 540)
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

  private var services: some View {
    Form {
      Text(
        "Controls apply to every approved client across available accounts. Reconnect clients after changing tools."
      )
      .font(.caption).foregroundStyle(.secondary)
      ForEach(AppleService.allCases) { service in
        Section {
          ForEach(
            runtime.tools.filter { $0.service == service }.sorted { $0.readOnly && !$1.readOnly }
          ) { tool in
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
                  Text(tool.readOnly ? "Read-only" : "Write")
                    .font(.caption2).foregroundStyle(.secondary)
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
        }
      }
    }
    .formStyle(.grouped)
  }

  private var connections: some View {
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
              .buttonStyle(.borderedProminent).tint(.red)
          }
        }
      }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
