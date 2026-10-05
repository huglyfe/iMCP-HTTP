import Foundation
import Synchronization
import Testing

@testable import IMCPCore
@testable import IMCPHTTP

@MainActor
struct ApprovalAuthenticationTests {
  @Test func approvalRequiresAuthenticationButRefreshAndRevokeDoNot() async throws {
    let f = try Fixture()
    defer { f.cleanup() }
    try await f.start()
    let request = try await f.request()
    let decision = Task { await f.runtime.decide(request, approve: true) }
    try await eventually { f.auth.calls == 1 }
    #expect(try await f.store.callback(for: request.id) == nil)
    #expect(await f.store.clients().isEmpty)
    f.auth.complete(.success(()))
    await decision.value
    let callback = try #require(try await f.store.callback(for: request.id))
    let code = try #require(
      URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?
        .first(where: { $0.name == "code" })?.value)
    let tokens = try await f.store.exchange([
      "grant_type": "authorization_code", "client_id": request.clientID, "code": code,
      "redirect_uri": request.callback, "code_verifier": f.verifier,
      "resource": f.configuration.resource,
    ])
    let rotated = try await f.store.exchange([
      "grant_type": "refresh_token", "client_id": request.clientID,
      "refresh_token": tokens.refreshToken, "resource": f.configuration.resource,
    ])
    let grant = try #require(await f.store.clients().first)
    #expect(try await f.store.authenticate("Bearer \(rotated.accessToken)") == grant.id)
    await f.runtime.revoke(grant)
    #expect(f.auth.calls == 1)
    #expect(await f.store.clients().isEmpty)
    await f.runtime.stop()
  }

  @Test(arguments: [OwnerAuthenticationError.cancelled, .unavailable, .failed])
  func failedAuthenticationNeverApprovesAndCanRetry(_ error: OwnerAuthenticationError) async throws
  {
    let f = try Fixture()
    defer { f.cleanup() }
    try await f.start()
    let request = try await f.request()
    let first = Task { await f.runtime.decide(request, approve: true) }
    try await eventually { f.auth.calls == 1 }
    f.auth.complete(.failure(error))
    await first.value
    #expect(f.runtime.authenticatingRequestID == nil)
    #expect(try await f.store.callback(for: request.id) == nil)
    #expect(await f.store.clients().isEmpty)
    let retry = Task { await f.runtime.decide(request, approve: true) }
    try await eventually { f.auth.calls == 2 }
    f.auth.complete(.success(()))
    await retry.value
    #expect(try await f.store.callback(for: request.id) != nil)
    #expect(f.runtime.errorMessage == nil)
    await f.runtime.stop()
  }

  @Test func duplicatePromptsAreBlockedAndDenialDiscardsLateSuccess() async throws {
    let f = try Fixture()
    defer { f.cleanup() }
    try await f.start()
    let first = try await f.request()
    let second = try await f.request()
    let decision = Task { await f.runtime.decide(first, approve: true) }
    try await eventually { f.auth.calls == 1 }
    await f.runtime.decide(first, approve: true)
    await f.runtime.decide(second, approve: true)
    #expect(f.auth.calls == 1)
    // Denying another request doesn't cancel this prompt.
    await f.runtime.decide(second, approve: false)
    #expect(f.auth.cancellations == 0)
    await f.runtime.decide(first, approve: false)
    #expect(f.auth.cancellations == 1)
    f.auth.complete(.success(()))
    await decision.value
    for request in [first, second] {
      let callback = try #require(try await f.store.callback(for: request.id))
      #expect(callback.absoluteString.contains("error=access_denied"))
      #expect(!callback.absoluteString.contains("code="))
    }
    #expect(await f.store.clients().isEmpty)
    await f.runtime.stop()
  }

  @Test func pauseAndRestartDiscardLateSuccessWithoutClearingNewAttempt() async throws {
    let f = try Fixture()
    defer { f.cleanup() }
    try await f.start()
    let oldRequest = try await f.request()
    let oldDecision = Task { await f.runtime.decide(oldRequest, approve: true) }
    try await eventually { f.auth.calls == 1 }
    await f.runtime.stop()
    #expect(f.auth.cancellations == 1)
    try await f.start()
    let newRequest = try await f.request()
    let newDecision = Task { await f.runtime.decide(newRequest, approve: true) }
    try await eventually { f.auth.calls == 2 }
    f.auth.complete(.success(()))
    await oldDecision.value
    #expect(f.runtime.authenticatingRequestID == newRequest.id)
    #expect(try await f.store.callback(for: newRequest.id) == nil)
    f.auth.complete(.success(()))
    await newDecision.value
    #expect(try await f.store.callback(for: newRequest.id) != nil)
    #expect(await f.store.clients().isEmpty)
    await f.runtime.stop()
  }

  @Test func expiryCancelsPromptAndStaleRequestCannotAuthenticate() async throws {
    let f = try Fixture()
    defer { f.cleanup() }
    try await f.start()
    let request = try await f.request()
    let decision = Task { await f.runtime.decide(request, approve: true) }
    try await eventually { f.auth.calls == 1 }
    f.clock.value.withLock { $0 = $0.addingTimeInterval(181) }
    #expect(await f.store.approvals().isEmpty)
    try await eventually { f.auth.cancellations == 1 }
    f.auth.complete(.success(()))
    await decision.value
    await f.runtime.decide(request, approve: true)
    #expect(f.auth.calls == 1)
    #expect(await f.store.clients().isEmpty)
    await f.runtime.stop()
  }
}

@MainActor
private final class FixtureAuthentication: OwnerAuthenticating {
  var calls = 0
  var cancellations = 0
  private var replies: [CheckedContinuation<Void, any Error>] = []

  func authenticate() async throws {
    calls += 1
    try await withCheckedThrowingContinuation { replies.append($0) }
  }
  // Intentionally permit a late success to prove the runtime rejects it.
  func cancel() { cancellations += 1 }
  func complete(_ result: Result<Void, any Error>) { replies.removeFirst().resume(with: result) }
}

@MainActor
private struct Fixture {
  let root: URL
  let configuration = ServerConfiguration(port: 19872)
  let verifier = String(repeating: "a", count: 64)
  let clock: FixtureClock
  let store: AuthorizationStore
  let auth = FixtureAuthentication()
  let runtime: AppRuntime

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("imcp-approval-\(UUID())")
    let clock = FixtureClock()
    self.clock = clock
    store = try AuthorizationStore(
      configuration: configuration, storeURL: root.appendingPathComponent("grants.json"),
      now: { clock.value.withLock { $0 } })
    runtime = AppRuntime(
      configuration: configuration, directory: root,
      runServer: { _, ready in
        await ready()
        try await Task.sleep(for: .seconds(30))
      }, ownerAuthentication: auth, authorization: store)
  }
  func start() async throws {
    runtime.start()
    try await eventually { runtime.state == .running }
  }
  func request() async throws -> PendingApproval {
    let callback = "http://127.0.0.1:49152/callback"
    let client = try await store.register(
      ClientRegistrationRequest(redirectURIs: [callback], clientName: "Disposable auth fixture"))
    let id = try await store.begin([
      "client_id": client.clientID, "response_type": "code", "redirect_uri": callback,
      "state": "fixture", "code_challenge_method": "S256",
      "code_challenge": try PKCE.makeChallenge(from: verifier),
      "resource": configuration.resource, "scope": ServerConfiguration.scope,
    ])
    try await eventually { runtime.approvals.contains(where: { $0.id == id }) }
    return try #require(runtime.approvals.first(where: { $0.id == id }))
  }
  func cleanup() { try? FileManager.default.removeItem(at: root) }
}

private final class FixtureClock: Sendable {
  let value = Mutex(Date())
}
