import Foundation
import Testing

@testable import IMCPCore

private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) { completionHandler(nil) }
}

struct HTTPTests {
  @Test func realListenerEnforcesOAuthAndMCP() async throws {
    let f = try await AuthorizationFixture()
    defer { f.cleanup() }
    let (ready, continuation) = AsyncThrowingStream<Void, Error>.makeStream()
    let server = LocalServer(
      configuration: f.configuration, authorization: f.store, dispatcher: ToolDispatcher())
    let task = Task {
      do {
        try await server.run {
          continuation.yield(())
          continuation.finish()
        }
      } catch {
        continuation.finish(throwing: error)
        throw error
      }
    }
    defer { task.cancel() }
    for try await _ in ready { break }
    let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }

    func request(
      _ path: String, method: String = "GET", token: String? = nil,
      body: String? = nil, headers: [String: String] = [:]
    ) async throws -> (Int, Data, HTTPURLResponse) {
      var request = URLRequest(url: URL(string: "\(f.configuration.issuer)\(path)")!)
      request.httpMethod = method
      request.timeoutInterval = 5
      request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
      if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
      if let body {
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      }
      for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
      let (data, response) = try await session.data(for: request)
      let http = try #require(response as? HTTPURLResponse)
      return (http.statusCode, data, http)
    }

    let metadata = try await request("/.well-known/oauth-protected-resource/mcp")
    #expect(metadata.0 == 200)
    let missing = try await request("/mcp", method: "POST", body: "{}")
    #expect(missing.0 == 401)
    #expect(
      missing.2.value(forHTTPHeaderField: "WWW-Authenticate")?.contains("resource_metadata") == true
    )
    #expect(
      try await request(
        "/.well-known/oauth-authorization-server", headers: ["Origin": "https://evil.example"]
      ).0 == 403)
    #expect(
      try await request(
        "/.well-known/oauth-authorization-server", headers: ["Host": "evil.example"]
      ).0 == 400)

    let registered = try await request(
      "/register", method: "POST",
      body:
        #"{"client_name":"HTTP fixture","redirect_uris":["http://127.0.0.1:49152/callback"],"token_endpoint_auth_method":"none","grant_types":["authorization_code","refresh_token"],"response_types":["code"]}"#
    )
    #expect(registered.0 == 201)
    let registration = try #require(
      JSONSerialization.jsonObject(with: registered.1) as? [String: Any])
    let clientID = try #require(registration["client_id"] as? String)
    #expect(registration["client_secret"] == nil)
    #expect(registration["token_endpoint_auth_method"] as? String == "none")
    #expect(await f.store.clients().isEmpty)
    #expect(
      try await request(
        "/register", method: "POST", body: #"{"redirect_uris":["https://example.com/callback"]}"#
      ).0 == 400)
    #expect(
      try await request("/register", method: "POST", body: String(repeating: "x", count: 8193)).0
        == 413)

    // Standard browser request, followed by a native owner decision.
    var url = URLComponents()
    var fields = try f.fields()
    fields["client_id"] = clientID
    url.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
    let authorization = try await request("/authorize?\(url.percentEncodedQuery!)")
    #expect(authorization.0 == 303)
    let waitingPath = try #require(authorization.2.value(forHTTPHeaderField: "Location"))
    let pending = try #require(await f.store.approvals().first)
    #expect(waitingPath == "/approval?id=\(pending.id)")
    for _ in 0..<3 {
      let page = try await request(waitingPath)
      #expect(page.0 == 200)
      let html = String(decoding: page.1, as: UTF8.self)
      #expect(!html.contains("http-equiv=\"refresh\""))
      #expect(!html.contains("test-state"))
      #expect(page.2.value(forHTTPHeaderField: "Cache-Control") == "no-store")
      let policy = try #require(page.2.value(forHTTPHeaderField: "Content-Security-Policy"))
      #expect(policy.contains("script-src 'nonce-") && policy.contains("connect-src 'self'"))
      #expect(!policy.contains("unsafe-inline"))
    }
    #expect(await f.store.approvals().count == 1)
    let statusPath = "/approval/status?id=\(pending.id)"
    let waiting = try await request(statusPath)
    #expect(waiting.0 == 200)
    #expect(
      try JSONSerialization.jsonObject(with: waiting.1) as? [String: Bool] == ["ready": false])
    #expect(try await request(statusPath, headers: ["Origin": "https://evil.example"]).0 == 403)
    #expect(try await request(statusPath, method: "POST").0 == 404)
    #expect(try await request("/approve", method: "POST", body: "{}").0 == 404)
    try await f.store.decide(id: pending.id, approve: true)
    for _ in 0..<3 {
      let ready = try await request(statusPath)
      #expect(ready.0 == 200)
      #expect(try JSONSerialization.jsonObject(with: ready.1) as? [String: Bool] == ["ready": true])
    }
    let redirect = try await request("/approval?id=\(pending.id)")
    #expect(redirect.0 == 302)
    let location = try #require(redirect.2.value(forHTTPHeaderField: "Location"))
    let callback = try #require(URLComponents(string: location))
    let code = try #require(callback.queryItems?.first(where: { $0.name == "code" })?.value)
    var exchangeFields = f.exchangeFields(code)
    exchangeFields["client_id"] = clientID
    url.queryItems = exchangeFields.map { URLQueryItem(name: $0.key, value: $0.value) }
    let exchange = try await request(
      "/token", method: "POST", body: url.percentEncodedQuery!,
      headers: ["Content-Type": "application/x-www-form-urlencoded"])
    #expect(exchange.0 == 200)
    let tokens = try JSONDecoder().decode(TokenResponse.self, from: exchange.1)
    #expect(exchange.2.value(forHTTPHeaderField: "Cache-Control") == "no-store")
    #expect(try await request(statusPath).0 == 400)
    let ended = try await request(waitingPath)
    #expect(ended.0 == 400)
    #expect(ended.2.value(forHTTPHeaderField: "Content-Type") == "text/html; charset=utf-8")
    #expect(String(decoding: ended.1, as: UTF8.self).contains("Start login again in your client"))

    let deniedID = try await f.store.begin(fields)
    try await f.store.decide(id: deniedID, approve: false)
    #expect(try await request("/approval/status?id=\(deniedID)").0 == 200)
    let denial = try await request("/approval?id=\(deniedID)")
    #expect(denial.0 == 302)
    let deniedLocation = try #require(denial.2.value(forHTTPHeaderField: "Location"))
    #expect(deniedLocation.contains("error=access_denied") && !deniedLocation.contains("code="))

    let initialize = """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","clientInfo":{"name":"acceptance","version":"1"},"capabilities":{"experimental":{"codex/auth-change":{}}}}}
      """
    let initialized = try await request(
      "/mcp", method: "POST", token: tokens.accessToken, body: initialize)
    #expect(initialized.0 == 200)
    let initJSON = try #require(JSONSerialization.jsonObject(with: initialized.1) as? [String: Any])
    #expect(initJSON["error"] == nil)
    let result = try #require(initJSON["result"] as? [String: Any])
    let capabilities = try #require(result["capabilities"] as? [String: Any])
    #expect((capabilities["tools"] as? [String: Any])?["listChanged"] as? Bool == false)
    let listing = try await request(
      "/mcp", method: "POST", token: tokens.accessToken,
      body: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
    #expect(String(decoding: listing.1, as: UTF8.self).contains("connection_check"))
    let call =
      #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"connection_check","arguments":{}}}"#
    async let first = request("/mcp", method: "POST", token: tokens.accessToken, body: call)
    async let second = request("/mcp", method: "POST", token: tokens.accessToken, body: call)
    for result in try await [first, second] {
      #expect(result.0 == 200)
      let envelope = try #require(JSONSerialization.jsonObject(with: result.1) as? [String: Any])
      let reply = try #require(envelope["result"] as? [String: Any])
      let content = try #require(reply["content"] as? [[String: Any]])
      let text = try #require(content.first?["text"] as? String)
      let object = try #require(
        JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
      #expect(object["connected"] as? Bool == true && object["appleDataAccessed"] as? Bool == false)
    }
    #expect(try await request("/mcp", token: tokens.accessToken).0 == 405)
    #expect(
      try await request(
        "/mcp", method: "POST", token: tokens.accessToken,
        body: String(repeating: "x", count: 65537)
      ).0 == 413)
    #expect(
      try await request(
        "/mcp", method: "POST", token: tokens.accessToken, body: call, headers: ["Accept": ";"]
      ).0 == 406)
    let disabled = try await request(
      "/mcp", method: "POST", token: tokens.accessToken,
      body:
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"reminders_delete","arguments":{"id":"fake"}}}"#
    )
    #expect(String(decoding: disabled.1, as: UTF8.self).contains("isError"))
    let grant = try await f.store.authenticate("Bearer \(tokens.accessToken)")
    try await f.store.revoke(grant)
    #expect(
      try await request("/mcp", method: "POST", token: tokens.accessToken, body: call).0 == 401)
    task.cancel()
    _ = try? await task.value
  }

}
