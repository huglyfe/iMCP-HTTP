import IMCPCore
import SwiftUI

struct MainView: View {
  @ObservedObject var runtime: AppRuntime
  @State private var selection = Tab.services
  @State private var expandedServices: Set<AppleService> = []
  @Binding var showingHelp: Bool

  private enum Tab: String, CaseIterable {
    case services = "Services"
    case connections = "Connections"
    case setup = "Setup"
  }

  var body: some View {
    VStack(spacing: 0) {
      Picker("Section", selection: $selection) {
        ForEach(Tab.allCases, id: \.self) { tab in
          Text(
            tab == .connections && !runtime.approvals.isEmpty
              ? "Connections (\(runtime.approvals.count))" : tab.rawValue
          ).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .controlSize(.large)
      .frame(maxWidth: 360)
      .padding(.horizontal, 20)
      .padding(.vertical, 12)

      Divider()

      ServerStatusView(runtime: runtime)
        .padding(.horizontal, 20).padding(.vertical, 10)

      if !runtime.approvals.isEmpty && selection != .connections {
        Button {
          selection = .connections
        } label: {
          Label(
            runtime.approvals.count == 1
              ? "Review connection request"
              : "Review \(runtime.approvals.count) connection requests",
            systemImage: "person.crop.circle.badge.exclamationmark"
          )
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered).padding(.horizontal, 20).padding(.bottom, 10)
      }

      if let error = runtime.errorMessage {
        HStack(alignment: .top) {
          Label(error, systemImage: "exclamationmark.triangle")
            .font(.callout).fixedSize(horizontal: false, vertical: true)
          Spacer()
          Button("Dismiss", systemImage: "xmark") { runtime.errorMessage = nil }
            .labelStyle(.iconOnly).help("Dismiss error")
        }
        .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20).padding(.bottom, 10)
      }

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
    .onAppear {
      runtime.refreshServiceStatus()
      expandedServices.formUnion(runtime.settings.enabledServices)
      expandedServices.formUnion(runtime.serviceIssues.keys)
    }
    .onChange(of: runtime.settings.enabledServices) { old, new in
      expandedServices.formUnion(new.subtracting(old))
    }
    .onChange(of: runtime.serviceIssues) { _, issues in
      expandedServices.formUnion(issues.keys)
    }
    .toolbar {
      Button("Help", systemImage: "questionmark.circle") { showingHelp = true }
        .help("Setup and troubleshooting")
    }
    .sheet(isPresented: $showingHelp) { AppHelpView() }
    .background {
      Group {
        Button("Services") { selection = .services }.keyboardShortcut("1")
        Button("Connections") { selection = .connections }.keyboardShortcut("2")
        Button("Setup") { selection = .setup }.keyboardShortcut("3")
      }.hidden().accessibilityHidden(true)
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
          HStack(spacing: 8) {
            Button {
              if expandedServices.contains(service) {
                expandedServices.remove(service)
              } else {
                expandedServices.insert(service)
              }
            } label: {
              Image(
                systemName: expandedServices.contains(service) ? "chevron.down" : "chevron.right"
              )
              .font(.caption.weight(.semibold)).frame(width: 16, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              "\(expandedServices.contains(service) ? "Hide" : "Show") \(service.title) tools"
            )
            .accessibilityValue(expandedServices.contains(service) ? "Expanded" : "Collapsed")
            .help("Show or hide individual tools")
            ServiceRow(runtime: runtime, service: service)
          }
          if expandedServices.contains(service) {
            if let issue = runtime.serviceIssues[service] {
              VStack(alignment: .leading, spacing: 8) {
                Label(issue, systemImage: "exclamationmark.triangle")
                  .fixedSize(horizontal: false, vertical: true)
                HStack {
                  Button("Privacy & Security…") { AppHelpView.openPrivacySettings() }
                  Button("Try again") { Task { await runtime.setEnabled(service, true) } }
                    .disabled(runtime.changingService != nil || runtime.changingTool != nil)
                }
              }.font(.callout)
            }
            if service == .mail || service == .notes {
              Text(
                "Keep \(service.title) open while using this service. Enabling it opens the app if needed."
              )
              .font(.caption).foregroundStyle(.secondary)
            }
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
                    Text(tool.displayTitle)
                    Text(tool.readOnly ? "Read-only" : "Write")
                      .font(.caption2).foregroundStyle(.secondary)
                  }
                  Text(tool.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
              }
              .toggleStyle(.switch).controlSize(.small)
              .tint(service.color)
              .accessibilityLabel("\(service.title): \(tool.displayTitle)")
              .accessibilityHint("\(tool.readOnly ? "Read-only" : "Write"). \(tool.description)")
              .help(tool.description)
              .disabled(
                !runtime.settings[service] || runtime.changingService != nil
                  || runtime.changingTool != nil
              )
            }
          }
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
          ContentUnavailableView {
            Label("No approved clients", systemImage: "person.crop.circle.badge.plus")
          } description: {
            Text("Choose a client in Setup, start its login, then approve the request here.")
          } actions: {
            Button("Connect a client") { selection = .setup }
              .buttonStyle(.borderedProminent)
          }
        }
        ForEach(runtime.clients) { client in
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text(client.clientName).font(.headline)
              Text("Approved \(client.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
              Text(String(client.id.uuidString.prefix(8))).font(.caption.monospaced())
            }
            Spacer()
            Button("Revoke", role: .destructive) { Task { await runtime.revoke(client) } }
              .buttonStyle(.borderedProminent).tint(.red)
              .accessibilityLabel("Revoke access for \(client.clientName)")
              .help("Blocks future calls and token refreshes. Work already started may finish.")
          }
        }
      }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

extension ServiceTool {
  fileprivate var displayTitle: String {
    name.split(separator: "_").dropFirst().joined(separator: " ").capitalized
  }
}
