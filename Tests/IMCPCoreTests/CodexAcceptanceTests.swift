import Foundation
import Testing

@testable import IMCPCore

struct CodexAcceptanceTests {
  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["IMCP_RUN_CODEX_ACCEPTANCE"] == "1"),
    .timeLimit(.minutes(3)))
  func realCodexLoginRestartAndRevoke() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let configuration = ServerConfiguration(port: 19767)
    let url = root.appendingPathComponent("grants.json")
    var authorization = try AuthorizationStore(configuration: configuration, storeURL: url)
    func start(_ store: AuthorizationStore) async throws -> Task<Void, Error> {
      let (ready, continuation) = AsyncThrowingStream<Void, Error>.makeStream()
      let task = Task {
        do {
          try await LocalServer(
            configuration: configuration, authorization: store,
            dispatcher: ToolDispatcher(testReminders: FakeReminders())
          ).run {
            continuation.yield(())
            continuation.finish()
          }
        } catch {
          continuation.finish(throwing: error)
          throw error
        }
      }
      for try await _ in ready { break }
      return task
    }
    var server = try await start(authorization)
    defer { server.cancel() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/codex_acceptance.py")
    process.arguments = ["python3", script.path, root.path, configuration.issuer]
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    defer { if process.isRunning { process.terminate() } }
    let deadline = ContinuousClock.now.advanced(by: .seconds(130))
    while process.isRunning, ContinuousClock.now < deadline {
      for request in await authorization.approvals() {
        try await authorization.decide(id: request.id, approve: true)
      }
      for action in ["restart", "revoke"] {
        let marker = root.appendingPathComponent(action)
        let done = root.appendingPathComponent(action + "-done")
        if FileManager.default.fileExists(atPath: marker.path),
          !FileManager.default.fileExists(atPath: done.path)
        {
          if action == "restart" {
            server.cancel()
            _ = try? await server.value
            authorization = try AuthorizationStore(configuration: configuration, storeURL: url)
            server = try await start(authorization)
          } else {
            for grant in await authorization.clients() { try await authorization.revoke(grant.id) }
          }
          try Data().write(to: done)
        }
      }
      try await Task.sleep(for: .milliseconds(50))
    }
    check(!process.isRunning)
    if process.isRunning { process.terminate() }
    process.waitUntilExit()
    check(process.terminationStatus == 0)
    check(FileManager.default.fileExists(atPath: root.appendingPathComponent("revoke-done").path))
    server.cancel()
    _ = try? await server.value
  }
}
