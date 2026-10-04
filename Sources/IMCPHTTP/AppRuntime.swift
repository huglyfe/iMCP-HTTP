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
  static let services: [AppleService] = [.reminders, .calendar, .contacts, .maps, .photos]
  private let eventStore = EventKitStore()
  private lazy var reminders = EventKitReminders(eventStore: eventStore)
  private lazy var calendar = EventKitCalendar(eventStore: eventStore)
  private lazy var contacts = NativeContacts()
  private lazy var photos = NativePhotos()
  private lazy var maps = NativeMaps()
  @Published private(set) var settings = ServiceSettings()
  @Published private(set) var serviceStatus: [AppleService: String] = [:]
  @Published private(set) var changingService: AppleService?
  @Published private(set) var changingTool: String?
  @Published private(set) var tools: [ServiceTool] = []
  private lazy var dispatcher = ToolDispatcher(
    reminders: reminders, calendar: calendar, contacts: contacts, maps: maps, photos: photos)
  private func access(_ service: AppleService) -> any AppleAccess {
    switch service {
    case .photos: photos
    case .reminders: reminders
    case .calendar: calendar
    case .contacts: contacts
    case .maps: maps
    default: preconditionFailure("Unimplemented service")
    }
  }
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
        settings = try ServiceSettings.load(from: settingsURL)
        for service in Self.services {
          access(service).setEnabled(settings[service])
          serviceStatus[service] = access(service).status
        }
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
      await dispatcher.setDisabledTools(self.settings.disabledTools)
      self.tools = await dispatcher.catalog()
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
      for await snapshot in await authorization.updates() {
        guard !Task.isCancelled else { return }
        self?.approvals = snapshot.approvals
        self?.clients = snapshot.clients
      }
    }
  }

  func refreshServiceStatus() {
    guard settingsLoaded else { return }
    for service in Self.services { serviceStatus[service] = access(service).status }
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
    } catch {
      errorMessage =
        "The request expired or could not be approved. Start login again in your client."
    }
  }

  func revoke(_ grant: ClientGrant) async {
    do {
      try await authorization?.revoke(grant.id)
    } catch { errorMessage = "Revocation could not be saved. Pause access and try again." }
  }

  private var settingsURL: URL {
    storeURL.deletingLastPathComponent().appendingPathComponent("services.json")
  }

  func setEnabled(_ service: AppleService, _ enabled: Bool) async {
    guard settingsLoaded, changingService == nil, changingTool == nil else { return }
    changingService = service
    defer { changingService = nil }
    do {
      if enabled, !(try await access(service).requestAccess()) {
        errorMessage =
          "Access was not granted. Allow \(service.title) in System Settings → Privacy & Security."
        return
      }
      var updated = settings
      updated[service] = enabled
      try updated.save(to: settingsURL)
      access(service).setEnabled(enabled)
      settings = updated
      serviceStatus[service] = access(service).status
    } catch {
      errorMessage =
        "The service setting could not be saved or permission could not be requested. Pause the server if you need to stop access."
    }
  }

  func setToolEnabled(_ name: String, _ enabled: Bool) async {
    guard settingsLoaded, changingService == nil, changingTool == nil,
      tools.contains(where: { $0.name == name })
    else { return }
    changingTool = name
    defer { changingTool = nil }
    do {
      var updated = settings
      if enabled { updated.disabledTools.remove(name) } else { updated.disabledTools.insert(name) }
      try updated.save(to: settingsURL)
      await dispatcher.setDisabledTools(updated.disabledTools)
      settings = updated
    } catch {
      errorMessage = "The tool setting could not be saved."
    }
  }

  func quit() async {
    await stop()
    NSApp.terminate(nil)
  }

  func copyConnectionCommand() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(connectionCommand, forType: .string)
  }
}
