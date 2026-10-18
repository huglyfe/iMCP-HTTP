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
  var authenticatingRequestID: String? { approvalAttempt?.requestID }
  @Published var errorMessage: String?
  let configuration: ServerConfiguration
  private let storeURL: URL
  private var authorization: AuthorizationStore?
  private let eventStore = EventKitStore()
  private lazy var reminders = EventKitReminders(eventStore: eventStore)
  private lazy var calendar = EventKitCalendar(eventStore: eventStore)
  private lazy var contacts = NativeContacts()
  private lazy var photos = NativePhotos()
  private lazy var maps = NativeMaps()
  private lazy var bluetooth = NativeBluetooth()
  private let automation = AutomationRunner()
  private lazy var mail = NativeMail(runner: automation)
  private lazy var notes = NativeNotes(runner: automation)
  @Published private(set) var settings = ServiceSettings()
  @Published private(set) var serviceStatus: [AppleService: String] = [:]
  @Published private(set) var serviceIssues: [AppleService: String] = [:]
  private let accessOverrides: [AppleService: any AppleAccess]
  @Published private(set) var changingService: AppleService?
  @Published private(set) var changingTool: String?
  @Published private(set) var tools: [ServiceTool] = []
  private lazy var dispatcher = ToolDispatcher(
    reminders: reminders, calendar: calendar, contacts: contacts, maps: maps, photos: photos,
    bluetooth: bluetooth, mail: mail, notes: notes)
  private func access(_ service: AppleService) -> any AppleAccess {
    if let override = accessOverrides[service] { return override }
    switch service {
    case .photos: return photos
    case .bluetooth: return bluetooth
    case .mail: return mail
    case .notes: return notes
    case .reminders: return reminders
    case .calendar: return calendar
    case .contacts: return contacts
    case .maps: return maps
    }
  }
  private var directoryLock: StateDirectoryLock?
  private var settingsLoaded = false
  private var hasStarted = false
  private var serverTask: Task<Void, Never>?
  private var observationTask: Task<Void, Never>?
  private let ownerAuthentication: any OwnerAuthenticating
  @Published private var approvalAttempt: (id: UUID, requestID: String)?

  typealias ServerRunner =
    @Sendable (LocalServer, @escaping @Sendable () async -> Void) async throws -> Void
  private let runServer: ServerRunner
  private let saveSettings: (ServiceSettings, URL) throws -> Void

  convenience init() {
    // Development acceptance can isolate state without touching the owner's saved grants.
    let environment = ProcessInfo.processInfo.environment
    let port = environment["IMCP_HTTP_PORT"].flatMap(Int.init) ?? 18765
    let configuration = ServerConfiguration(port: (1024...65535).contains(port) ? port : 18765)
    let directory =
      environment["IMCP_HTTP_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("iMCP-HTTP", isDirectory: true)
    self.init(configuration: configuration, directory: directory)
  }

  init(
    configuration: ServerConfiguration, directory: URL,
    runServer: @escaping ServerRunner = { server, ready in try await server.run(onReady: ready) },
    saveSettings: @escaping (ServiceSettings, URL) throws -> Void = { try $0.save(to: $1) },
    ownerAuthentication: any OwnerAuthenticating = MacOwnerAuthentication(),
    authorization: AuthorizationStore? = nil,
    accessOverrides: [AppleService: any AppleAccess] = [:]
  ) {
    self.configuration = configuration
    storeURL = directory.appendingPathComponent("grants.json")
    self.runServer = runServer
    self.saveSettings = saveSettings
    self.ownerAuthentication = ownerAuthentication
    self.authorization = authorization
    self.accessOverrides = accessOverrides
  }

  deinit {
    observationTask?.cancel()
    serverTask?.cancel()
  }

  func startIfNeeded() {
    guard !hasStarted else { return }
    hasStarted = true
    start()
  }

  func start() {
    guard serverTask == nil, state != .starting else { return }
    state = .starting
    if directoryLock == nil {
      do {
        directoryLock = try StateDirectoryLock(directory: storeURL.deletingLastPathComponent())
      } catch {
        if (error as? CocoaError)?.code == .fileLocking {
          fail(
            "App already running",
            "Another iMCP-HTTP instance owns this state directory. Quit that instance and try again."
          )
        } else {
          fail(
            "State folder unavailable",
            "The app could not open its state folder. Check folder access and available disk space."
          )
        }
        return
      }
    }
    if !settingsLoaded {
      do { settings = try ServiceSettings.load(from: settingsURL) } catch {
        fail(
          "Service settings could not load",
          "Saved service settings could not be read. The file was preserved; repair it before restarting."
        )
        return
      }
      for service in AppleService.allCases {
        access(service).setEnabled(settings[service])
        serviceStatus[service] = access(service).status
      }
      settingsLoaded = true
    }
    if authorization == nil {
      do {
        authorization = try AuthorizationStore(configuration: configuration, storeURL: storeURL)
      } catch {
        fail(
          "Client access could not load",
          "Saved client access could not be read or belongs to a different server address. The file was preserved."
        )
        return
      }
    }
    guard let authorization else { return }
    errorMessage = nil
    let disabledTools = settings.disabledTools
    serverTask = Task { [weak self, configuration, dispatcher, runServer, directoryLock] in
      // Keep exclusive state ownership until listener teardown finishes, even if
      // the UI owner is released and its deinitializer cancels this task.
      defer { withExtendedLifetime(directoryLock) {} }
      var failure: String?
      do {
        await dispatcher.setDisabledTools(disabledTools)
        self?.tools = await dispatcher.catalog()
        try Task.checkCancellation()
        await authorization.setAccepting(true)
        try Task.checkCancellation()
        try await runServer(
          LocalServer(
            configuration: configuration, authorization: authorization, dispatcher: dispatcher)
        ) { [weak self] in await self?.didStart() }
      } catch {
        if !Task.isCancelled {
          failure =
            self?.state == .running ? "Server stopped unexpectedly" : "Server could not start"
        }
      }
      await authorization.setAccepting(false)
      self?.bluetooth.suspend()
      self?.serverTask = nil
      if let failure {
        self?.fail(
          failure,
          "The local HTTP listener failed. Check whether another app is using port \(configuration.port), then try starting again."
        )
      } else {
        self?.state = .stopped
      }
    }
    if observationTask == nil {
      observationTask = Task { [weak self] in
        for await snapshot in await authorization.updates() {
          guard !Task.isCancelled else { return }
          self?.receive(snapshot)
        }
      }
    }
  }

  private func fail(_ title: String, _ message: String) {
    cancelApprovalAuthentication()
    state = .failed(title)
    errorMessage = message
  }

  func refreshServiceStatus() {
    guard settingsLoaded else { return }
    for service in AppleService.allCases {
      serviceStatus[service] = access(service).status
      // Preserve a failed enable attempt until an explicit retry or successful recovery.
      if settings[service] {
        if service == .bluetooth && state != .running { continue }
        serviceIssues[service] = access(service).available ? nil : access(service).status
      }
    }
  }

  private func didStart() {
    guard state == .starting, !Task.isCancelled else { return }
    bluetooth.resume()
    state = .running
    refreshServiceStatus()
  }

  func stop() async {
    cancelApprovalAuthentication()
    guard let task = serverTask else { return }
    state = .stopping
    bluetooth.suspend()
    task.cancel()
    await authorization?.setAccepting(false)
    await task.value
    approvals = []
  }

  func decide(_ request: PendingApproval, approve: Bool) async {
    guard state == .running, let authorization else { return }
    if !approve {
      if authenticatingRequestID == request.id { cancelApprovalAuthentication() }
      do { try await authorization.decide(id: request.id, approve: false) } catch {
        errorMessage = "This request expired. Start login again in your client."
      }
      return
    }
    guard approvalAttempt == nil, approvals.contains(where: { $0.id == request.id }) else { return }
    errorMessage = nil
    let attempt = UUID()
    approvalAttempt = (id: attempt, requestID: request.id)
    defer {
      if approvalAttempt?.id == attempt {
        approvalAttempt = nil
      }
    }
    do {
      try await ownerAuthentication.authenticate()
      // Authentication can return after cancellation, denial, pause, or expiry.
      // The actor also rechecks the exact request and expiry before issuing a code.
      guard approvalAttempt?.id == attempt, state == .running, !Task.isCancelled else { return }
      try await authorization.decide(id: request.id, approve: true)
    } catch {
      guard approvalAttempt?.id == attempt else { return }
      switch error {
      case OwnerAuthenticationError.cancelled:
        // Leave the request pending so the owner can retry or deny it.
        break
      case OwnerAuthenticationError.unavailable:
        errorMessage = "macOS authentication is unavailable. Unlock your Mac and try again."
      case OwnerAuthenticationError.failed:
        errorMessage =
          "macOS could not verify you. No access was granted. Try again or deny the request."
      default:
        errorMessage =
          "The request expired or could not be approved. Start login again in your client."
      }
    }
  }

  private func receive(_ snapshot: AuthorizationViewState) {
    approvals = snapshot.approvals
    clients = snapshot.clients
    if let id = authenticatingRequestID, !approvals.contains(where: { $0.id == id }) {
      cancelApprovalAuthentication()
    }
  }

  private func cancelApprovalAuthentication() {
    guard approvalAttempt != nil else { return }
    approvalAttempt = nil
    ownerAuthentication.cancel()
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
    defer {
      changingService = nil
      serviceStatus[service] = access(service).status
    }
    if enabled {
      do {
        guard try await access(service).requestAccess() else {
          serviceIssues[service] =
            "Access was not granted. Review \(service.title) in Privacy & Security, then try again."
          return
        }
      } catch {
        serviceIssues[service] =
          "macOS could not request access. Review Privacy & Security, then try again."
        return
      }
    }
    do {
      var updated = settings
      updated[service] = enabled
      try saveSettings(updated, settingsURL)
      access(service).setEnabled(enabled)
      settings = updated
      serviceIssues[service] = nil
      serviceStatus[service] = access(service).status
    } catch {
      errorMessage =
        "The service setting could not be saved. Its previous value is still active. Check disk access, or pause the server to stop access."
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
      try saveSettings(updated, settingsURL)
      await dispatcher.setDisabledTools(updated.disabledTools)
      settings = updated
    } catch {
      errorMessage = "The tool setting could not be saved."
    }
  }
}
