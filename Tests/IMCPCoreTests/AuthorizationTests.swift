import Foundation
import Testing

@testable import IMCPCore

struct AuthorizationFixture {
  let directory: URL
  let configuration = ServerConfiguration(port: 19765)
  let store: AuthorizationStore
  let verifier = String(repeating: "a", count: 64)

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("imcp-test-\(UUID())")
    store = try AuthorizationStore(
      configuration: configuration, storeURL: directory.appendingPathComponent("grants.json"))
  }
  func cleanup() { try? FileManager.default.removeItem(at: directory) }
  func fields() throws -> [String: String] {
    [
      "client_id": "codex", "response_type": "code",
      "redirect_uri": "http://127.0.0.1:49152/callback",
      "state": "test-state", "code_challenge_method": "S256",
      "code_challenge": try PKCE.makeChallenge(from: verifier),
      "resource": configuration.resource, "scope": "apple-services",
    ]
  }
  func code() async throws -> String {
    let id = try await store.begin(fields())
    try await store.decide(id: id, approve: true)
    let url = try require(await store.callback(for: id))
    let components = try require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    check(components.queryItems?.first(where: { $0.name == "iss" })?.value == configuration.issuer)
    return try require(components.queryItems?.first(where: { $0.name == "code" })?.value)
  }
  func exchangeFields(_ code: String) -> [String: String] {
    [
      "grant_type": "authorization_code", "client_id": "codex", "code": code,
      "redirect_uri": "http://127.0.0.1:49152/callback", "code_verifier": verifier,
      "resource": configuration.resource,
    ]
  }
  func tokens() async throws -> TokenResponse { try await store.exchange(exchangeFields(code())) }
}

struct AuthorizationTests {
  @Test func approveRestartRefreshRevoke() async throws {
    let f = try AuthorizationFixture()
    defer { f.cleanup() }
    let tokens = try await f.tokens()
    let grant = try await f.store.authenticate("Bearer \(tokens.accessToken)")
    let disk = try String(
      contentsOf: f.directory.appendingPathComponent("grants.json"), encoding: .utf8)
    check(!disk.contains(tokens.accessToken))
    check(!disk.contains(tokens.refreshToken))
    let permissions = try FileManager.default.attributesOfItem(
      atPath: f.directory.appendingPathComponent("grants.json").path)
    check((permissions[.posixPermissions] as? Int) == 0o600)
    let reopened = try AuthorizationStore(
      configuration: f.configuration, storeURL: f.directory.appendingPathComponent("grants.json"))
    check(try await reopened.authenticate("Bearer \(tokens.accessToken)") == grant)
    let rotated = try await reopened.exchange([
      "grant_type": "refresh_token", "client_id": "codex",
      "resource": f.configuration.resource, "refresh_token": tokens.refreshToken,
    ])
    check(try await reopened.authenticate("Bearer \(rotated.accessToken)") == grant)
    await expectFailure { try await reopened.authenticate("Bearer \(tokens.accessToken)") }
    try await reopened.revoke(grant)
    await expectFailure { try await reopened.authenticate("Bearer \(rotated.accessToken)") }
    let again = try AuthorizationStore(
      configuration: f.configuration, storeURL: f.directory.appendingPathComponent("grants.json"))
    await expectFailure {
      try await again.exchange([
        "grant_type": "refresh_token", "client_id": "codex",
        "resource": f.configuration.resource, "refresh_token": rotated.refreshToken,
      ])
    }
  }

  @Test func codesAreBoundAndSingleUse() async throws {
    let f = try AuthorizationFixture()
    defer { f.cleanup() }
    for field in ["code_verifier", "redirect_uri", "resource", "client_id"] {
      let code = try await f.code()
      var fields = f.exchangeFields(code)
      fields[field] = "wrong"
      await expectFailure { try await f.store.exchange(fields) }
    }
    let code = try await f.code()
    _ = try await f.store.exchange(f.exchangeFields(code))
    await expectFailure { try await f.store.exchange(f.exchangeFields(code)) }
  }

  @Test func denialAndCallbackValidation() async throws {
    let f = try AuthorizationFixture()
    defer { f.cleanup() }
    for callback in [
      "http://localhost:49152/callback", "http://127.0.0.1:49152/other",
      "http://127.0.0.1.evil:49152/callback", "https://example.com/callback",
      "http://127.0.0.1:49152/callback?x=1", "http://user@127.0.0.1:49152/callback",
    ] {
      var fields = try f.fields()
      fields["redirect_uri"] = callback
      await expectFailure { try await f.store.begin(fields) }
    }
    let id = try await f.store.begin(f.fields())
    check(try await f.store.callback(for: id) == nil)
    try await f.store.decide(id: id, approve: false)
    let url = try require(await f.store.callback(for: id))
    check(url.absoluteString.contains("error=access_denied"))
    check(!url.absoluteString.contains("code="))
    check(await f.store.clients().isEmpty)
  }

  @Test func refreshReplayRevokesFamilyAndPauseRejects() async throws {
    let f = try AuthorizationFixture()
    defer { f.cleanup() }
    let tokens = try await f.tokens()
    let fields = [
      "grant_type": "refresh_token", "client_id": "codex",
      "resource": f.configuration.resource, "refresh_token": tokens.refreshToken,
    ]
    let rotated = try await f.store.exchange(fields)
    await expectFailure { try await f.store.exchange(fields) }
    await expectFailure { try await f.store.authenticate("Bearer \(rotated.accessToken)") }
    let next = try await f.tokens()
    await f.store.setAccepting(false)
    await expectFailure { try await f.store.authenticate("Bearer \(next.accessToken)") }
    await expectFailure { try await f.store.begin(f.fields()) }
    await f.store.setAccepting(true)
    _ = try await f.store.authenticate("Bearer \(next.accessToken)")
  }

  @Test func pendingRequestsAreBoundedAndNotRecovered() async throws {
    let f = try AuthorizationFixture()
    defer { f.cleanup() }
    for _ in 0..<8 { _ = try await f.store.begin(f.fields()) }
    await expectFailure { try await f.store.begin(f.fields()) }
    let reopened = try AuthorizationStore(
      configuration: f.configuration, storeURL: f.directory.appendingPathComponent("grants.json"))
    check(await reopened.approvals().isEmpty)
  }

  @Test func expirationsAndFailedPersistenceFailClosed() async throws {
    let f = try AuthorizationFixture()
    defer { f.cleanup() }
    let tokens = try await f.tokens()
    let future = Date().addingTimeInterval(901)
    let expired = try AuthorizationStore(
      configuration: f.configuration,
      storeURL: f.directory.appendingPathComponent("grants.json"), now: { future })
    await expectFailure { try await expired.authenticate("Bearer \(tokens.accessToken)") }
    let refreshed = try await expired.exchange([
      "grant_type": "refresh_token", "client_id": "codex",
      "resource": f.configuration.resource, "refresh_token": tokens.refreshToken,
    ])
    _ = try await expired.authenticate("Bearer \(refreshed.accessToken)")
    let badPath = f.directory.appendingPathComponent("not-a-directory")
    try Data().write(to: badPath)
    let bad = try AuthorizationStore(
      configuration: f.configuration,
      storeURL: badPath.appendingPathComponent("grants.json"))
    let id = try await bad.begin(f.fields())
    try await bad.decide(id: id, approve: true)
    let callback = try require(await bad.callback(for: id))
    let code = try require(
      URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
        $0.name == "code"
      })?.value)
    await expectFailure { try await bad.exchange(f.exchangeFields(code)) }
    check(await bad.clients().isEmpty)
  }

}
