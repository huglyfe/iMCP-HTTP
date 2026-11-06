import Foundation
import IMCPCore
import Testing

@testable import IMCPHTTP

@MainActor
struct AppRuntimeTests {
  @Test func permissionRecoveryPreservesPolicyAndClearsOnlyAfterSuccess() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let listener = FixtureListener()
    let access = FixtureAppleAccess()
    let runtime = AppRuntime(
      configuration: .init(), directory: root, runServer: listener.run,
      accessOverrides: [.reminders: access])
    runtime.start()
    try await listener.waitForStart()
    await listener.reportReady()
    try await eventually { runtime.state == .running }
    await runtime.setEnabled(.reminders, true)
    #expect(!runtime.settings[.reminders])
    #expect(runtime.serviceIssues[.reminders] != nil)
    #expect(runtime.errorMessage == nil)
    runtime.refreshServiceStatus()
    #expect(runtime.serviceIssues[.reminders] != nil)
    access.allowed = true
    await runtime.setEnabled(.reminders, true)
    #expect(runtime.settings[.reminders])
    #expect(runtime.serviceIssues[.reminders] == nil)
    #expect(
      try ServiceSettings.load(from: root.appendingPathComponent("services.json"))[.reminders])
    // A permission revoked in System Settings must surface without changing the owner's choice.
    access.allowed = false
    runtime.refreshServiceStatus()
    #expect(runtime.settings[.reminders])
    #expect(runtime.serviceIssues[.reminders] != nil)
    access.allowed = true
    runtime.refreshServiceStatus()
    #expect(runtime.serviceIssues[.reminders] == nil)
    await runtime.setEnabled(.reminders, false)
    #expect(!access.enabled)
    #expect(runtime.serviceIssues[.reminders] == nil)
    await runtime.stop()
  }

  @Test func failedPermissionRequestCanBeRetriedWithoutSavingEnablement() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let listener = FixtureListener()
    let access = FixtureAppleAccess()
    access.shouldThrow = true
    let runtime = AppRuntime(
      configuration: .init(), directory: root, runServer: listener.run,
      accessOverrides: [.reminders: access])
    runtime.start()
    try await listener.waitForStart()
    await runtime.setEnabled(.reminders, true)
    #expect(runtime.serviceIssues[.reminders]?.contains("could not request") == true)
    #expect(runtime.changingService == nil)
    #expect(!runtime.settings[.reminders])
    #expect(
      !FileManager.default.fileExists(atPath: root.appendingPathComponent("services.json").path))
    access.shouldThrow = false
    access.allowed = true
    await runtime.setEnabled(.reminders, true)
    #expect(runtime.serviceIssues[.reminders] == nil)
    #expect(runtime.settings[.reminders])
    await runtime.stop()
  }

  private func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "imcp-runtime-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func startupPauseRestartAndLateReadiness() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let listener = FixtureListener()
    let runtime = AppRuntime(
      configuration: .init(port: 19870), directory: root, runServer: listener.run)
    runtime.startIfNeeded()
    try await listener.waitForStart()
    #expect(runtime.state == .starting)
    // Starting isn't Running until the listener reports readiness.
    let lateReady = await listener.ready
    await runtime.stop()
    #expect(runtime.state == .stopped)
    // A callback that was already queued must not turn a paused app green.
    await lateReady?()
    #expect(runtime.state == .stopped)
    runtime.start()
    try await listener.waitForStart()
    await listener.reportReady()
    try await eventually { runtime.state == .running }
    runtime.startIfNeeded()
    #expect(await listener.starts == 2)
    await runtime.stop()
    #expect(runtime.state == .stopped)
  }

  @Test func listenerFailureCanBeRetried() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let listener = FixtureListener(failFirst: true)
    let runtime = AppRuntime(configuration: .init(), directory: root, runServer: listener.run)
    runtime.start()
    try await eventually {
      if case .failed = runtime.state { return true }
      return false
    }
    #expect(runtime.errorMessage?.contains("HTTP listener") == true)
    runtime.start()
    try await listener.waitForStart()
    await listener.reportReady()
    try await eventually { runtime.state == .running }
    #expect(runtime.errorMessage == nil)
    await runtime.stop()
  }

  @Test func releasingRuntimeCancelsListenerAndReleasesStateDirectory() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let listener = FixtureListener()
    var runtime: AppRuntime? = AppRuntime(
      configuration: .init(), directory: root, runServer: listener.run)
    let remainingRuntime = { [weak runtime] in runtime }
    runtime?.start()
    try await listener.waitForStart()
    await listener.reportReady()
    runtime = nil
    #expect(remainingRuntime() == nil)
    // Clean up even when testing a version that accidentally retains the runtime.
    if let leaked = remainingRuntime() { await leaked.stop() }
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while await listener.ready != nil, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await listener.ready == nil)
    try await eventually { (try? StateDirectoryLock(directory: root)) != nil }
  }

  @Test func storageFailuresAreDistinctAndPreserveFiles() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let owner = try StateDirectoryLock(directory: root)
    let locked = AppRuntime(configuration: .init(), directory: root)
    locked.start()
    #expect(locked.state == .failed("App already running"))
    withExtendedLifetime(owner) {}

    let corruptRoot = try directory()
    defer { try? FileManager.default.removeItem(at: corruptRoot) }
    let data = Data("broken fixture".utf8)
    let settings = corruptRoot.appendingPathComponent("services.json")
    try data.write(to: settings)
    let badSettings = AppRuntime(configuration: .init(), directory: corruptRoot)
    badSettings.start()
    #expect(badSettings.state == .failed("Service settings could not load"))
    #expect(try Data(contentsOf: settings) == data)

    let grantRoot = try directory()
    defer { try? FileManager.default.removeItem(at: grantRoot) }
    let grants = grantRoot.appendingPathComponent("grants.json")
    try data.write(to: grants)
    let badGrants = AppRuntime(configuration: .init(), directory: grantRoot)
    badGrants.start()
    #expect(badGrants.state == .failed("Client access could not load"))
    #expect(try Data(contentsOf: grants) == data)
  }

  @Test func failedSaveKeepsServiceAndToolPolicy() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let listener = FixtureListener()
    let runtime = AppRuntime(
      configuration: .init(), directory: root, runServer: listener.run,
      saveSettings: { _, _ in throw CocoaError(.fileWriteNoPermission) })
    runtime.start()
    try await listener.waitForStart()
    await listener.reportReady()
    try await eventually { runtime.state == .running && !runtime.tools.isEmpty }
    // Maps has no native permission prompt and performs no query on enablement.
    await runtime.setEnabled(.maps, true)
    #expect(!runtime.settings[.maps])
    #expect(runtime.serviceStatus[.maps] == "Disabled")
    #expect(runtime.errorMessage?.contains("previous value") == true)
    await runtime.setToolEnabled("maps_search", false)
    #expect(!runtime.settings.disabledTools.contains("maps_search"))
    #expect(
      !FileManager.default.fileExists(atPath: root.appendingPathComponent("services.json").path))
    await runtime.stop()
  }
}

@MainActor
private final class FixtureAppleAccess: AppleAccess {
  var enabled = false
  var allowed = false
  var shouldThrow = false
  var available: Bool { enabled && allowed }
  func setEnabled(_ enabled: Bool) { self.enabled = enabled }
  func requestAccess() async throws -> Bool {
    if shouldThrow { throw CocoaError(.featureUnsupported) }
    return allowed
  }
}

private actor FixtureListener {
  var starts = 0
  var ready: (@Sendable () async -> Void)?
  let failFirst: Bool
  init(failFirst: Bool = false) { self.failFirst = failFirst }
  func run(_ server: LocalServer, ready: @escaping @Sendable () async -> Void) async throws {
    starts += 1
    if failFirst && starts == 1 { throw CocoaError(.fileReadUnknown) }
    self.ready = ready
    defer { self.ready = nil }
    try await Task.sleep(for: .seconds(30))
  }
  func waitForStart() async throws {
    try await eventually { self.ready != nil }
  }
  func reportReady() async { await ready?() }
}
