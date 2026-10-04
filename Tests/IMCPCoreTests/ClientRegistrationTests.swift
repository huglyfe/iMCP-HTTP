import Foundation
import Testing

@testable import IMCPCore

struct ClientRegistrationTests {
  private func registration(
    _ name: String = "Fixture client", callback: String = "http://localhost:43123/oauth/callback"
  ) -> ClientRegistrationRequest {
    ClientRegistrationRequest(
      redirectURIs: [callback], clientName: name, tokenEndpointAuthMethod: "none")
  }

  private func tokens(_ f: AuthorizationFixture, client: String, callback: String) async throws
    -> TokenResponse
  {
    var fields = try f.fields()
    fields["client_id"] = client
    fields["redirect_uri"] = callback
    let id = try await f.store.begin(fields)
    #expect(await f.store.clients().isEmpty)
    try await f.store.decide(id: id, approve: true)
    let url = try #require(await f.store.callback(for: id))
    let code = try #require(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
        $0.name == "code"
      }?.value)
    var exchange = f.exchangeFields(code)
    exchange["client_id"] = client
    exchange["redirect_uri"] = callback
    return try await f.store.exchange(exchange)
  }

  @Test func registrationApprovalRestartRefreshAndRevoke() async throws {
    let f = try await AuthorizationFixture()
    defer { f.cleanup() }
    let client = try await f.store.register(registration())
    #expect(await f.store.clients().isEmpty)
    #expect(await f.store.approvals().isEmpty)
    // Native callback ports may change, but the path and host stay registered.
    let token = try await tokens(
      f, client: client.clientID, callback: "http://localhost:43124/oauth/callback")
    let id = try await f.store.authenticate("Bearer \(token.accessToken)")
    let reopened = try AuthorizationStore(
      configuration: f.configuration, storeURL: f.directory.appendingPathComponent("grants.json"))
    #expect(try await reopened.authenticate("Bearer \(token.accessToken)") == id)
    #expect(await reopened.clients().first?.clientName == "Fixture client")
    let fields = [
      "grant_type": "refresh_token", "client_id": client.clientID,
      "refresh_token": token.refreshToken, "resource": f.configuration.resource,
    ]
    let rotated = try await reopened.exchange(fields)
    await expectFailure { try await reopened.authenticate("Bearer \(token.accessToken)") }
    try await reopened.revoke(id)
    await expectFailure { try await reopened.authenticate("Bearer \(rotated.accessToken)") }
    await expectFailure {
      try await reopened.exchange(
        fields.merging(["refresh_token": rotated.refreshToken]) { _, new in new })
    }
  }

  @Test func callbacksAndMetadataFailClosed() async throws {
    let f = try await AuthorizationFixture()
    defer { f.cleanup() }
    for callback in [
      "https://example.com/callback", "http://192.168.1.1:43123/callback",
      "http://127.0.0.1.evil:43123/callback", "http://user@localhost:43123/callback",
      "http://localhost:43123/callback#fragment", "http://localhost:43123/callback?next=x",
      "http://localhost:19765/callback", "http://localhost:80/callback",
      "http://LOCALHOST:43123/callback",
    ] {
      await expectFailure { try await f.store.register(registration(callback: callback)) }
    }
    for request in [
      ClientRegistrationRequest(redirectURIs: []),
      ClientRegistrationRequest(
        redirectURIs: ["http://localhost:43123/callback"],
        tokenEndpointAuthMethod: "client_secret_basic"),
      ClientRegistrationRequest(
        redirectURIs: ["http://localhost:43123/callback"], grantTypes: ["client_credentials"]),
      ClientRegistrationRequest(redirectURIs: ["http://localhost:43123/callback"], scope: "other"),
      registration("Misleading\nlabel"),
    ] { await expectFailure { try await f.store.register(request) } }
    let client = try await f.store.register(registration())
    for callback in ["http://localhost:43124/other", "http://127.0.0.1:43124/oauth/callback"] {
      var fields = try f.fields()
      fields["client_id"] = client.clientID
      fields["redirect_uri"] = callback
      await expectFailure { try await f.store.begin(fields) }
    }
    #expect(
      f.configuration.matchesCallback(
        "http://[::1]:43124/callback", registered: "http://[::1]:43123/callback"))
  }

  @Test func credentialsStayBoundToTheirRegisteredClient() async throws {
    let f = try await AuthorizationFixture()
    defer { f.cleanup() }
    let first = try await f.store.register(registration("First"))
    let second = try await f.store.register(registration("Second"))
    let token = try await tokens(
      f, client: first.clientID, callback: "http://localhost:43123/oauth/callback")
    let fields = [
      "grant_type": "refresh_token", "client_id": first.clientID,
      "refresh_token": token.refreshToken, "resource": f.configuration.resource,
    ]
    await expectFailure {
      try await f.store.exchange(fields.merging(["client_id": second.clientID]) { _, new in new })
    }
    let rotated = try await f.store.exchange(fields)
    // Another client's replay must neither rotate nor revoke the original grant.
    await expectFailure {
      try await f.store.exchange(fields.merging(["client_id": second.clientID]) { _, new in new })
    }
    _ = try await f.store.authenticate("Bearer \(rotated.accessToken)")
    await expectFailure { try await f.store.exchange(fields) }
    await expectFailure { try await f.store.authenticate("Bearer \(rotated.accessToken)") }
  }

  @Test func registrationIsBoundedPausedAndPruned() async throws {
    let f = try await AuthorizationFixture()
    defer { f.cleanup() }
    for _ in 0..<9 { _ = try await f.store.register(registration()) }
    await expectFailure { try await f.store.register(registration()) }
    await f.store.setAccepting(false)
    await expectFailure { try await f.store.register(registration()) }
    let later = Date().addingTimeInterval(86401)
    let reopened = try AuthorizationStore(
      configuration: f.configuration, storeURL: f.directory.appendingPathComponent("grants.json"),
      now: { later })
    _ = try await reopened.register(registration())
    let snapshot = try GrantPersistence(
      url: f.directory.appendingPathComponent("grants.json"), issuer: f.configuration.issuer
    ).load()
    #expect(snapshot.registrations.count == 1)
  }

  @Test func registrationSaveFailureDoesNotChangeMemory() async throws {
    let f = try await AuthorizationFixture()
    defer { f.cleanup() }
    let url = f.directory.appendingPathComponent("grants.json")
    let original = try Data(contentsOf: url)
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    await expectFailure { try await f.store.register(registration()) }
    try FileManager.default.removeItem(at: url)
    try original.write(to: url)
    let client = try await f.store.register(registration())
    let snapshot = try GrantPersistence(url: url, issuer: f.configuration.issuer).load()
    #expect(Set(snapshot.registrations.map(\.id)) == [f.clientID, client.clientID])
    #expect(snapshot.grants.isEmpty)
  }

  @Test func approvedRegistrationsSurviveAbandonedRegistrationCleanup() async throws {
    let f = try await AuthorizationFixture()
    defer { f.cleanup() }
    let client = try await f.store.register(registration())
    _ = try await tokens(
      f, client: client.clientID, callback: "http://localhost:43123/oauth/callback")
    let later = Date().addingTimeInterval(86401)
    let url = f.directory.appendingPathComponent("grants.json")
    let reopened = try AuthorizationStore(
      configuration: f.configuration, storeURL: url, now: { later })
    let next = try await reopened.register(registration())
    let snapshot = try GrantPersistence(url: url, issuer: f.configuration.issuer).load()
    #expect(Set(snapshot.registrations.map(\.id)) == [client.clientID, next.clientID])
    #expect(snapshot.grants.count == 1)
  }
}
