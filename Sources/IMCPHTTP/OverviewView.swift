import IMCPCore
import SwiftUI

struct OverviewView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 6) {
          Text("iMCP-HTTP")
            .font(.largeTitle.bold())
          Text("Apple services for your AI clients.")
            .foregroundStyle(.secondary)
        }

        GroupBox("Development preview") {
          VStack(alignment: .leading, spacing: 8) {
            Label("Server not implemented", systemImage: "pause.circle")
            Text("This skeleton does not listen for connections or access Apple data.")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
        }

        GroupBox("Planned services") {
          VStack(spacing: 0) {
            ForEach(AppleService.allCases) { service in
              HStack {
                Text(service.title)
                Spacer()
                Text(service == .reminders ? "First implementation" : "Planned")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .padding(.vertical, 6)
            }
          }
          .padding(8)
        }

        GroupBox("Clients") {
          Text("OAuth approval and client management are planned. No clients are authorized.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
      }
      .padding(24)
    }
    .frame(minWidth: 440, minHeight: 440)
  }
}
