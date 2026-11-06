import SwiftUI

/// Both surfaces expose the same listener lifecycle; a failed listener never looks enabled.
struct ServerStatusView: View {
  @ObservedObject var runtime: AppRuntime

  var body: some View {
    HStack(spacing: 10) {
      if runtime.state == .starting || runtime.state == .stopping {
        ProgressView().controlSize(.small).accessibilityLabel(runtime.state.title)
      } else {
        Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
      }
      Text(runtime.state.title).font(.callout.weight(.medium))
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
      Button(actionTitle) {
        if runtime.state == .running { Task { await runtime.stop() } } else { runtime.start() }
      }
      .disabled(runtime.state == .starting || runtime.state == .stopping)
      .help(runtime.state == .running ? "Pause access for every client" : "Start the local server")
    }
  }

  private var actionTitle: String {
    switch runtime.state {
    case .running, .stopping: "Pause"
    case .failed: "Retry"
    case .stopped, .starting: "Start"
    }
  }

  private var symbol: String {
    switch runtime.state {
    case .running: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    default: "pause.circle"
    }
  }

  private var color: Color {
    switch runtime.state {
    case .running: .green
    case .failed: .orange
    default: .secondary
    }
  }
}
