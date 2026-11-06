import AppKit
import SwiftUI

struct SetupView: View {
  let resource: String
  @State private var search = ""
  @State private var selection: String? = "codex"
  @State private var copied: String?
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
        Button(
          copied == resource ? "Copied" : "Copy address",
          systemImage: copied == resource ? "checkmark" : "doc.on.doc"
        ) { copy(resource) }
        .help("Copy server address")
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
                  Button(
                    copied == configuration ? "Copied" : "Copy configuration",
                    systemImage: copied == configuration ? "checkmark" : "doc.on.doc"
                  ) { copy(configuration) }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
    .task(id: copied) {
      guard copied != nil else { return }
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      copied = nil
    }
  }

  private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    if NSPasteboard.general.setString(value, forType: .string) { copied = value }
  }
}
