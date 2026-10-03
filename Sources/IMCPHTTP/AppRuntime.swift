import AppKit
import Combine
import Foundation
import IMCPCore

@MainActor
final class AppRuntime: ObservableObject {
  enum State: Equatable {
    case stopped, starting, running, stopping
    case failed(String)
    var title: String {
      switch self {
      case .stopped: "Paused"
      case .starting: "Starting…"
      case .running: "Running on this Mac"
      case .stopping: "Stopping…"
      case .failed(let message): message
      }
    }
  }

  @Published private(set) var state: State = .stopped
  @Published private(set) var approvals: [PendingApproval] = []
  @Published private(set) var clients: [ClientGrant] = []
  @Published var errorMessage: String?
  let configuration: ServerConfiguration
  private let storeURL: URL
  private var authorization: AuthorizationStore?
  let reminders = EventKitReminders()
  @Published private(set) var remindersEnabled = false
  @Published private(set) var remindersStatus = "Disabled"
  @Published private(set) var changingReminders = false
  private lazy var dispatcher = ToolDispatcher(reminders: reminders)
  private var directoryLock: StateDirectoryLock?
  private var settingsLoaded = false
  private var hasStarted = false
  private var serverTask: Task<Void, Never>?
  private var observationTask: Task<Void, Never>?

  init() {
    // Development acceptance can isolate state without touching the owner's saved grants.
    let environment = ProcessInfo.processInfo.environment
    let port = environment["IMCP_HTTP_PORT"].flatMap(Int.init) ?? 18765
    configuration = ServerConfiguration(port: (1024...65535).contains(port) ? port : 18765)
    let directory =
      environment["IMCP_HTTP_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("iMCP-HTTP", isDirectory: true)
    storeURL = directory.appendingPathComponent("grants.json")
  }

  var connectionCommand: String {
    "codex mcp add imcp-http --url \(configuration.resource) --oauth-client-id codex"
  }

  func startIfNeeded() {
    guard !hasStarted else { return }
    hasStarted = true
    start()
  }

  func start() {
    guard serverTask == nil, state != .starting else { return }
    state = .starting
    do {
      if directoryLock == nil {
        directoryLock = try StateDirectoryLock(directory: storeURL.deletingLastPathComponent())
      }
      if !settingsLoaded {
        let enabled = try ServiceSettings.load(from: settingsURL).remindersEnabled
        reminders.setEnabled(enabled)
        remindersEnabled = enabled
        remindersStatus = reminders.status
        settingsLoaded = true
      }
      if authorization == nil {
        authorization = try AuthorizationStore(configuration: configuration, storeURL: storeURL)
      }
    } catch {
      state = .failed("Could not load saved client access")
      errorMessage =
        "Client access could not be loaded. Existing data was preserved. Another app instance may already own this state directory."
      return
    }
    guard let authorization else { return }
    serverTask = Task { [weak self, configuration, dispatcher] in
      guard let self else { return }
      await authorization.setAccepting(true)
      do {
        try await LocalServer(
          configuration: configuration, authorization: authorization, dispatcher: dispatcher
        ).run {
          await self.didStart()
        }
        self.state = .stopped
      } catch {
        if Task.isCancelled {
          self.state = .stopped
        } else {
          self.state = .failed("Server could not start")
          self.errorMessage =
            "The local port may already be in use. Pause the other instance and try again."
        }
      }
      await authorization.setAccepting(false)
      self.serverTask = nil
    }
    observationTask?.cancel()
    observationTask = Task { [weak self] in
      while !Task.isCancelled {
        let pending = await authorization.approvals()
        let clients = await authorization.clients()
        self?.approvals = pending
        self?.clients = clients
        self?.remindersStatus = self?.reminders.status ?? "Disabled"
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
      }
    }
  }

  private func didStart() { state = .running }

  func stop() async {
    guard let task = serverTask else { return }
    state = .stopping
    await authorization?.setAccepting(false)
    task.cancel()
    await task.value
    approvals = []
  }

  func decide(_ request: PendingApproval, approve: Bool) async {
    do {
      try await authorization?.decide(id: request.id, approve: approve)
      approvals = await authorization?.approvals() ?? []
    } catch {
      errorMessage =
        "The request expired or could not be approved. Start login again in your client."
    }
  }

  func revoke(_ grant: ClientGrant) async {
    do {
      try await authorization?.revoke(grant.id)
      clients = await authorization?.clients() ?? []
    } catch { errorMessage = "Revocation could not be saved. Pause access and try again." }
  }

  private var settingsURL: URL {
    storeURL.deletingLastPathComponent().appendingPathComponent("services.json")
  }

  func setRemindersEnabled(_ enabled: Bool) async {
    guard settingsLoaded, !changingReminders else { return }
    changingReminders = true
    defer { changingReminders = false }
    do {
      if enabled, !(try await reminders.requestAccess()) {
        errorMessage =
          "Reminders access was not granted. You can allow it in System Settings → Privacy & Security → Reminders."
        return
      }
      try ServiceSettings(remindersEnabled: enabled).save(to: settingsURL)
      reminders.setEnabled(enabled)
      remindersEnabled = enabled
      remindersStatus = reminders.status
    } catch {
      errorMessage =
        "The service setting could not be saved or permission could not be requested. Pause the server if you need to stop access."
    }
  }

  func copyConnectionCommand() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(connectionCommand, forType: .string)
  }
}
