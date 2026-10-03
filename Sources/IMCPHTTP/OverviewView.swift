import IMCPCore
import SwiftUI

struct OverviewView: View {
  @ObservedObject var runtime: AppRuntime

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 6) {
          Text("iMCP-HTTP").font(.largeTitle.bold())
          Text("Apple services for your AI clients.").foregroundStyle(.secondary)
        }
        GroupBox {
          HStack {
            VStack(alignment: .leading, spacing: 6) {
              Label(
                runtime.state.title,
                systemImage: runtime.state == .running ? "checkmark.circle.fill" : "pause.circle")
              Text(runtime.configuration.resource).font(.caption.monospaced()).textSelection(
                .enabled)
            }
            Spacer()
            if runtime.state == .running {
              Button("Pause") { Task { await runtime.stop() } }
            } else {
              Button("Start") { runtime.start() }
                .disabled(runtime.state == .starting || runtime.state == .stopping)
            }
          }.padding(8)
        }

        ForEach(runtime.approvals) { request in
          GroupBox("Connection request") {
            VStack(alignment: .leading, spacing: 10) {
              Text("Allow this client until revoked?").font(.headline)
              Text(
                "Access covers all globally enabled services and accounts available to this Mac user."
              )
              Text("Public client: \(request.clientID)").font(.caption)
              Text(request.callback).font(.caption.monospaced()).textSelection(.enabled)
              Text(
                "Client IDs are labels, not verified application identities. Approve only a login you just started."
              )
              .font(.caption).foregroundStyle(.secondary)
              HStack {
                Button("Deny", role: .cancel) {
                  Task { await runtime.decide(request, approve: false) }
                }
                Spacer()
                Button("Approve") { Task { await runtime.decide(request, approve: true) } }
                  .buttonStyle(.borderedProminent)
              }
            }.padding(8)
          }
        }

        GroupBox("Connect Codex") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Add the server once, then run codex mcp login imcp-http and approve here.")
              .font(.callout)
            Text(runtime.connectionCommand).font(.caption.monospaced()).textSelection(.enabled)
            Button("Copy setup command") { runtime.copyConnectionCommand() }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }

        GroupBox("Services") {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(AppRuntime.services) { service in
              Toggle(
                isOn: Binding(
                  get: { runtime.settings[service] },
                  set: { enabled in Task { await runtime.setEnabled(service, enabled) } }
                )
              ) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(service.title)
                  Text(runtime.serviceStatus[service] ?? "Disabled").font(.caption).foregroundStyle(
                    .secondary)
                }
              }.disabled(runtime.changingService != nil)
            }
            Text(
              "Enabled services are available to every approved client. Reconnect clients after changing services."
            )
            .font(.caption).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }

        GroupBox("Approved clients") {
          VStack(alignment: .leading, spacing: 12) {
            if runtime.clients.isEmpty { Text("No approved clients").foregroundStyle(.secondary) }
            ForEach(runtime.clients) { client in
              HStack {
                VStack(alignment: .leading, spacing: 3) {
                  Text(client.clientID).font(.headline)
                  Text(client.createdAt, style: .date).font(.caption)
                  Text(String(client.id.uuidString.prefix(8))).font(.caption.monospaced())
                }
                Spacer()
                Button("Revoke", role: .destructive) { Task { await runtime.revoke(client) } }
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
      }.padding(24)
    }
    .frame(minWidth: 460, minHeight: 460)
    .alert(
      "iMCP-HTTP",
      isPresented: Binding(
        get: { runtime.errorMessage != nil },
        set: { if !$0 { runtime.errorMessage = nil } })
    ) {
      Button("OK") { runtime.errorMessage = nil }
    } message: {
      Text(runtime.errorMessage ?? "")
    }
  }
}
