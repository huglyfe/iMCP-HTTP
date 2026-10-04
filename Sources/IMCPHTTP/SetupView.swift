import AppKit
import SwiftUI

struct SetupView: View {
  let resource: String
  @State private var search = ""
  @State private var selection: String? = "codex"
  private var clients: [ClientSetup] {
    ClientSetup.matching(search, in: ClientSetup.clients(resource: resource))
  }
  private var selected: ClientSetup? { clients.first { $0.id == selection } ?? clients.first }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Connect a client").font(.headline)
      HStack {
        Text(resource).font(.caption.monospaced()).textSelection(.enabled)
        Spacer()
        Button("Copy address", systemImage: "doc.on.doc") { copy(resource) }
          .labelStyle(.iconOnly).help("Copy server address")
      }
      TextField("Search clients", text: $search)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel("Search clients")
      HStack(alignment: .top, spacing: 0) {
        List(clients, selection: $selection) { client in
          Text(client.name).tag(client.id)
        }
        .listStyle(.sidebar)
        .frame(width: 155)
        Divider()
        if let client = selected {
          ScrollView {
            VStack(alignment: .leading, spacing: 14) {
              Text(client.name).font(.title2.bold())
              Label(
                client.support.rawValue,
                systemImage: client.support == .verified
                  ? "checkmark.circle"
                  : client.support == .unavailable ? "network.slash" : "info.circle"
              )
              .font(.caption)
              .foregroundStyle(client.support == .verified ? Color.green : Color.secondary)
              Text(client.instructions).fixedSize(horizontal: false, vertical: true)
              if let configuration = client.configuration {
                VStack(alignment: .leading, spacing: 8) {
                  Text(configuration).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                  Button("Copy configuration", systemImage: "doc.on.doc") { copy(configuration) }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
              }
              if client.support != .unavailable {
                Text(
                  "Enable the services you want to share in Services. Each new connection needs your approval; revoke it later in Connections."
                )
                .font(.caption).foregroundStyle(.secondary)
              }
              Link("Client documentation ↗", destination: client.documentation)
            }
            .padding(.leading, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
          }.id(client.id)
        } else {
          ContentUnavailableView.search(text: search)
            .frame(maxWidth: .infinity)
        }
      }
    }
    .padding(16)
    .onChange(of: search) { _, _ in
      if !clients.contains(where: { $0.id == selection }) { selection = clients.first?.id }
    }
  }

  private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }
}
