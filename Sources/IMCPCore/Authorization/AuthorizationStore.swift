import Foundation

public actor AuthorizationStore {
  public let configuration: ServerConfiguration
  private let persistence: GrantPersistence
  private let now: @Sendable () -> Date
  private var grants: [ClientGrant]
  private var registrations: [RegisteredClient]
  private var recentRegistrations: [Date] = []
  private var pending: [String: PendingRequest] = [:]
  private var codes: [String: AuthorizationCode] = [:]
  private var recentRequests: [Date] = []
  private var accepting = true
  private var observer: AsyncStream<AuthorizationViewState>.Continuation?
  private var observerID: UUID?
  private var expiryTask: Task<Void, Never>?

  public init(
    configuration: ServerConfiguration, storeURL: URL,
    now: @escaping @Sendable () -> Date = Date.init
  ) throws {
    self.configuration = configuration
    self.now = now
    persistence = GrantPersistence(url: storeURL, issuer: configuration.issuer)
    let snapshot = try persistence.load()
    grants = snapshot.grants
    registrations = snapshot.registrations
    guard
      registrations.allSatisfy({ client in
        !client.id.isEmpty
          && client.id.utf8.count <= 128
          && (try? ClientRegistrationRequest(
            redirectURIs: client.redirectURIs, clientName: client.name
          ).validate(configuration: configuration)) != nil
      })
    else { throw OAuthFailure("invalid_store") }
  }

  func register(_ request: ClientRegistrationRequest) throws -> ClientRegistrationResponse {
    guard accepting else { throw OAuthFailure("temporarily_unavailable") }
    try request.validate(configuration: configuration)
    let date = now()
    recentRegistrations = recentRegistrations.filter { date.timeIntervalSince($0) < 60 }
    let activeIDs = Set(grants.filter { !$0.revoked }.map(\.clientID))
    // Keep approved clients indefinitely; discard abandoned registrations after one day.
    var next = registrations.filter {
      activeIDs.contains($0.id) || date.timeIntervalSince($0.createdAt) < 86400
    }
    guard next.count < 128, recentRegistrations.count < 10 else {
      throw OAuthFailure("temporarily_unavailable")
    }
    let client = RegisteredClient(
      id: try Credential.make(), name: request.clientName ?? "Local MCP client",
      redirectURIs: request.redirectURIs, createdAt: date)
    next.append(client)
    try persistence.save(grants, registrations: next)
    registrations = next
    recentRegistrations.append(date)
    return ClientRegistrationResponse(
      clientID: client.id, clientName: client.name, redirectURIs: client.redirectURIs,
      clientIDIssuedAt: Int(date.timeIntervalSince1970))
  }

  private func knownClient(_ id: String) -> Bool {
    registrations.contains { $0.id == id }
  }
  private func clientName(_ id: String) -> String {
    registrations.first { $0.id == id }?.name ?? "Local MCP client"
  }
  private func validCallback(_ callback: String, clientID: String) -> Bool {
    return registrations.first { $0.id == clientID }?.redirectURIs.contains {
      configuration.matchesCallback(callback, registered: $0)
    } == true
  }

  /// One native UI observer. No timer runs unless a visible approval has an expiry.
  public func updates() -> AsyncStream<AuthorizationViewState> {
    observer?.finish()
    let id = UUID()
    let (stream, continuation) = AsyncStream<AuthorizationViewState>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    observer = continuation
    observerID = id
    continuation.onTermination = { [weak self] _ in
      Task { await self?.stopObserving(id) }
    }
    prune()
    publish()
    return stream
  }

  private func stopObserving(_ id: UUID) {
    guard observerID == id else { return }
    observer = nil
    observerID = nil
    expiryTask?.cancel()
    expiryTask = nil
  }

  private func visibleApprovals() -> [PendingApproval] {
    pending.compactMap { id, value in
      guard value.callbackURL == nil else { return nil }
      return PendingApproval(
        id: id, clientID: value.request.clientID, clientName: value.request.clientName,
        callback: value.request.callback, expiresAt: value.expiresAt)
    }.sorted { $0.expiresAt < $1.expiresAt }
  }

  private func publish() {
    guard let observer else { return }
    let approvals = visibleApprovals()
    observer.yield(AuthorizationViewState(approvals: approvals, clients: clients()))
    expiryTask?.cancel()
    expiryTask = nil
    if let expiry = approvals.first?.expiresAt {
      let delay = max(0, expiry.timeIntervalSince(now()))
      expiryTask = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        await self?.prune()
      }
    }
  }

  public func clients() -> [ClientGrant] { grants.filter { !$0.revoked } }

  public func approvals() -> [PendingApproval] {
    prune()
    return visibleApprovals()
  }

  func begin(_ fields: [String: String]) throws -> String {
    prune()
    guard accepting else { throw OAuthFailure("temporarily_unavailable") }
    guard let clientID = fields["client_id"], knownClient(clientID) else {
      throw OAuthFailure("unauthorized_client")
    }
    guard fields["response_type"] == "code", let callback = fields["redirect_uri"],
      validCallback(callback, clientID: clientID), let state = fields["state"],
      !state.isEmpty, state.utf8.count <= 512,
      fields["code_challenge_method"] == "S256",
      let challenge = fields["code_challenge"], challenge.utf8.count == 43,
      challenge.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0)
          || (48...57).contains($0) || $0 == 45 || $0 == 95
      })
    else { throw OAuthFailure("invalid_request") }
    guard fields["resource"] == configuration.resource else { throw OAuthFailure("invalid_target") }
    guard fields["scope"] == ServerConfiguration.scope else { throw OAuthFailure("invalid_scope") }
    guard pending.count < 8, codes.count < 8, recentRequests.count < 10 else {
      throw OAuthFailure("temporarily_unavailable")
    }
    let id = try Credential.make()
    pending[id] = PendingRequest(
      request: AuthorizationRequest(
        clientID: clientID, clientName: clientName(clientID),
        callback: callback, state: state, challenge: challenge, resource: configuration.resource),
      expiresAt: now().addingTimeInterval(180))
    recentRequests.append(now())
    publish()
    return id
  }

  /// Called only by the native owner UI (or directly by tests), never an HTTP route.
  public func decide(id: String, approve: Bool) throws {
    prune()
    guard accepting, var item = pending[id], item.callbackURL == nil else {
      throw OAuthFailure("invalid_request")
    }
    var callback = URLComponents(string: item.request.callback)!
    var query = [
      URLQueryItem(name: "state", value: item.request.state),
      URLQueryItem(name: "iss", value: configuration.issuer),
    ]
    if approve {
      guard codes.count < 8, grants.filter({ !$0.revoked }).count < 64 else {
        throw OAuthFailure("temporarily_unavailable")
      }
      let code = try Credential.make()
      codes[Credential.hash(code)] = AuthorizationCode(
        request: item.request,
        expiresAt: now().addingTimeInterval(60))
      query.append(URLQueryItem(name: "code", value: code))
    } else {
      query.append(URLQueryItem(name: "error", value: "access_denied"))
    }
    callback.queryItems = query
    item.callbackURL = callback.url
    pending[id] = item
    publish()
  }

  func callback(for id: String) throws -> URL? {
    prune()
    guard let item = pending[id] else { throw OAuthFailure("expired_request") }
    if let callback = item.callbackURL {
      pending.removeValue(forKey: id)
      publish()
      return callback
    }
    return nil
  }

  func exchange(_ fields: [String: String]) throws -> TokenResponse {
    prune()
    guard accepting else { throw OAuthFailure("temporarily_unavailable") }
    guard let clientID = fields["client_id"], knownClient(clientID) else {
      throw OAuthFailure("invalid_client")
    }
    guard fields["resource"] == configuration.resource else { throw OAuthFailure("invalid_target") }
    if let scope = fields["scope"], scope != ServerConfiguration.scope {
      throw OAuthFailure("invalid_scope")
    }
    switch fields["grant_type"] {
    case "authorization_code": return try exchangeCode(fields)
    case "refresh_token": return try refresh(fields)
    default: throw OAuthFailure("unsupported_grant_type")
    }
  }

  private func exchangeCode(_ fields: [String: String]) throws -> TokenResponse {
    guard let rawCode = fields["code"],
      let code = codes.removeValue(forKey: Credential.hash(rawCode)),
      code.expiresAt > now(), fields["redirect_uri"] == code.request.callback,
      fields["client_id"] == code.request.clientID, fields["resource"] == code.request.resource,
      let verifier = fields["code_verifier"], Credential.validVerifier(verifier),
      try PKCE.makeChallenge(from: verifier) == code.request.challenge
    else { throw OAuthFailure("invalid_grant") }
    let tokens = try makeTokens()
    let grant = ClientGrant(
      id: UUID(), clientID: code.request.clientID, clientName: code.request.clientName,
      createdAt: now(),
      revoked: false, accessHash: Credential.hash(tokens.accessToken),
      accessExpiresAt: now().addingTimeInterval(900),
      refreshHash: Credential.hash(tokens.refreshToken), usedRefreshHashes: [])
    let next = grants.filter { !$0.revoked } + [grant]
    guard next.count <= 64 else { throw OAuthFailure("temporarily_unavailable") }
    try persist(next)
    return tokens
  }

  private func refresh(_ fields: [String: String]) throws -> TokenResponse {
    guard let token = fields["refresh_token"] else { throw OAuthFailure("invalid_grant") }
    let hash = Credential.hash(token)
    if let index = grants.firstIndex(where: {
      !$0.revoked && $0.clientID == fields["client_id"] && $0.usedRefreshHashes.contains(hash)
    }) {
      var next = grants
      next[index].revoked = true
      try persist(next)
      throw OAuthFailure("invalid_grant")
    }
    guard
      let index = grants.firstIndex(where: {
        !$0.revoked && $0.clientID == fields["client_id"] && $0.refreshHash == hash
      })
    else {
      throw OAuthFailure("invalid_grant")
    }
    let tokens = try makeTokens()
    var next = grants
    next[index].usedRefreshHashes = Array((next[index].usedRefreshHashes + [hash]).suffix(128))
    next[index].refreshHash = Credential.hash(tokens.refreshToken)
    next[index].accessHash = Credential.hash(tokens.accessToken)
    next[index].accessExpiresAt = now().addingTimeInterval(900)
    try persist(next)
    return tokens
  }

  func authenticate(_ header: String?) throws -> UUID {
    guard accepting, let header, header.hasPrefix("Bearer "), header.utf8.count <= 256 else {
      throw OAuthFailure("invalid_token")
    }
    let hash = Credential.hash(String(header.dropFirst(7)))
    guard
      let grant = grants.first(where: {
        !$0.revoked && $0.accessHash == hash
          && $0.accessExpiresAt > now()
      })
    else { throw OAuthFailure("invalid_token") }
    return grant.id
  }

  func requireActive(_ id: UUID) throws {
    guard accepting, grants.contains(where: { $0.id == id && !$0.revoked }) else {
      throw OAuthFailure("invalid_token")
    }
  }

  public func revoke(_ id: UUID) throws {
    guard let index = grants.firstIndex(where: { $0.id == id }) else { return }
    var next = grants
    next[index].revoked = true
    try persist(next)
  }

  public func setAccepting(_ value: Bool) {
    accepting = value
    if !value {
      pending.removeAll()
      codes.removeAll()
    }
    publish()
  }

  private func makeTokens() throws -> TokenResponse {
    try TokenResponse(accessToken: Credential.make(), refreshToken: Credential.make())
  }
  private func persist(_ next: [ClientGrant]) throws {
    try persistence.save(next, registrations: registrations)
    grants = next
    publish()
  }
  private func prune() {
    let date = now()
    let count = pending.count
    pending = pending.filter { $0.value.expiresAt > date }
    codes = codes.filter { $0.value.expiresAt > date }
    recentRequests = recentRequests.filter { date.timeIntervalSince($0) < 60 }
    if pending.count != count { publish() }
  }
}
