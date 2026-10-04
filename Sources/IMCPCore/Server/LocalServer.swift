import Foundation
import HTTPTypes
import Hummingbird
import Logging
import NIOPosix

public struct LocalServer: Sendable {
  public let configuration: ServerConfiguration
  public let authorization: AuthorizationStore
  public let dispatcher: ToolDispatcher

  public init(
    configuration: ServerConfiguration, authorization: AuthorizationStore,
    dispatcher: ToolDispatcher
  ) {
    self.configuration = configuration
    self.authorization = authorization
    self.dispatcher = dispatcher
  }

  public func run(onReady: @escaping @Sendable () async -> Void = {}) async throws {
    // No request/access logger: authorization URLs and Apple content must stay out of logs.
    let logger = Logger(label: "imcp-http", factory: { _ in SwiftLogNoOpLogHandler() })
    // One event loop serves this bounded local listener. Release it on pause/failure
    // instead of creating a process-wide worker for every CPU core.
    try await MultiThreadedEventLoopGroup.withEventLoopGroup(numberOfThreads: 1) { group in
      let app = Application(
        responder: LocalResponder(
          configuration: configuration,
          authorization: authorization,
          gateway: MCPGateway(authorization: authorization, dispatcher: dispatcher)),
        server: .http1(
          configuration: .init(
            idleTimeout: .seconds(10),
            httpDecoderConfiguration: .init(
              maxHeaderFieldSize: 8192, maxHeaderListSize: 16384, maxHeaderFieldCount: 64))),
        configuration: .init(
          address: .hostname("127.0.0.1", port: configuration.port),
          backlog: 32, reuseAddress: true,
          availableConnectionsDelegate: .maximum(32, logger: logger)
        ),
        onServerRunning: { _ in await onReady() }, eventLoopGroupProvider: .shared(group),
        logger: logger)
      try await app.run()
    }
  }
}

struct LocalResponder: HTTPResponder {
  typealias Context = BasicRequestContext
  let configuration: ServerConfiguration
  let authorization: AuthorizationStore
  let gateway: MCPGateway

  func respond(to request: Request, context: Context) async throws -> Response {
    // Hummingbird moves Host into HTTPRequest.authority. Only our exact listener is valid.
    guard request.head.authority == "127.0.0.1:\(configuration.port)",
      request.uri.string.utf8.count <= 8192,
      request.uri.string.hasPrefix("/"), !request.uri.string.hasPrefix("//")
    else { return error("invalid_host", status: .badRequest) }
    if let origin = request.headers[.origin], origin != configuration.issuer {
      return error("invalid_origin", status: .forbidden)
    }
    do {
      return try await route(request)
    } catch let failure as OAuthFailure {
      if failure.code == "expired_request", request.method == .get, request.uri.path == "/approval"
      {
        return try page(status: .badRequest, content: ApprovalPage.expired)
      }
      return error(
        failure.code,
        status: failure.code == "temporarily_unavailable" ? .tooManyRequests : .badRequest)
    } catch is DecodingError {
      return error("invalid_request", status: .badRequest)
    } catch is URLEncodedFormError {
      return error("invalid_request", status: .badRequest)
    } catch let failure as any HTTPResponseError {
      return error("invalid_request", status: failure.status)
    } catch {
      return self.error("server_error", status: .internalServerError)
    }
  }

  private func route(_ request: Request) async throws -> Response {
    switch (request.method, request.uri.path) {
    case (.get, "/.well-known/oauth-protected-resource"),
      (.get, "/.well-known/oauth-protected-resource/mcp"):
      return try json([
        "resource": configuration.resource, "authorization_servers": [configuration.issuer],
        "scopes_supported": [ServerConfiguration.scope], "bearer_methods_supported": ["header"],
      ])
    case (.get, "/.well-known/oauth-authorization-server"):
      return try json([
        "issuer": configuration.issuer,
        "authorization_endpoint": "\(configuration.issuer)/authorize",
        "token_endpoint": "\(configuration.issuer)/token",
        "registration_endpoint": "\(configuration.issuer)/register",
        "response_types_supported": ["code"],
        "grant_types_supported": ["authorization_code", "refresh_token"],
        "code_challenge_methods_supported": ["S256"],
        "token_endpoint_auth_methods_supported": ["none"],
        "scopes_supported": [ServerConfiguration.scope],
        "authorization_response_iss_parameter_supported": true,
      ])
    case (.post, "/register"):
      guard request.headers[.contentType]?.split(separator: ";").first == "application/json" else {
        throw OAuthFailure("invalid_client_metadata")
      }
      let body = try await request.body.collect(upTo: 8192)
      let registration = try JSONDecoder().decode(
        ClientRegistrationRequest.self, from: Data(body.readableBytesView))
      let client = try await authorization.register(registration)
      var response = Response(
        status: .created, headers: [.contentType: "application/json"],
        body: .init(byteBuffer: ByteBuffer(bytes: try JSONEncoder().encode(client))))
      protect(&response)
      return response
    case (.get, "/authorize"):
      let fields = try form(request.uri.query ?? "")
      let id = try await authorization.begin(fields)
      // Refreshing the waiting page must never create another authorization request.
      var response = Response(status: .seeOther, headers: [.location: "/approval?id=\(id)"])
      protect(&response)
      return response
    case (.get, "/approval/status"):
      let fields = try form(request.uri.query ?? "")
      guard fields.count == 1, let id = fields["id"] else { throw OAuthFailure("invalid_request") }
      let ready = try await authorization.approvalReady(for: id)
      return try json(["ready": ready])
    case (.get, "/approval"):
      let fields = try form(request.uri.query ?? "")
      guard fields.count == 1, let id = fields["id"] else { throw OAuthFailure("invalid_request") }
      if let callback = try await authorization.callback(for: id) {
        var response = Response(status: .found, headers: [.location: callback.absoluteString])
        protect(&response)
        return response
      }
      return try page { ApprovalPage.html(id: id, nonce: $0) }
    case (.post, "/token"):
      guard
        request.headers[.contentType]?.split(separator: ";").first
          == "application/x-www-form-urlencoded",
        request.headers[.authorization] == nil
      else { throw OAuthFailure("invalid_request") }
      let body = try await request.body.collect(upTo: 8192)
      let fields = try form(String(buffer: body))
      let tokens = try await authorization.exchange(fields)
      var response = Response(
        status: .ok, headers: [.contentType: "application/json"],
        body: .init(byteBuffer: ByteBuffer(bytes: try JSONEncoder().encode(tokens))))
      protect(&response)
      return response
    case (_, "/mcp"):
      let grant: UUID
      do { grant = try await authorization.authenticate(request.headers[.authorization]) } catch {
        var response = self.error("invalid_token", status: .unauthorized)
        response.headers[.wwwAuthenticate] =
          "Bearer resource_metadata=\"\(configuration.issuer)/.well-known/oauth-protected-resource\", scope=\"\(ServerConfiguration.scope)\""
        return response
      }
      guard request.uri.query == nil else { throw OAuthFailure("invalid_request") }
      let body = try await request.body.collect(upTo: 65536)
      let result = try await gateway.respond(
        method: request.method, headers: request.headers,
        body: Data(body.readableBytesView), grant: grant)
      var response = Response(
        status: result.status, headers: result.headers,
        body: .init(byteBuffer: ByteBuffer(bytes: result.data)))
      protect(&response)
      return response
    default: return error("not_found", status: .notFound)
    }
  }

  private func form(_ raw: String) throws -> [String: String] {
    try URLEncodedFormDecoder().decode([String: String].self, from: raw)
  }

  private func page(
    status: HTTPTypes.HTTPResponse.Status = .ok, content: (String) -> String
  ) throws -> Response {
    let nonce = try Credential.make()
    var response = Response(
      status: status, headers: [.contentType: "text/html; charset=utf-8"],
      body: .init(byteBuffer: ByteBuffer(string: content(nonce))))
    protect(&response)
    response.headers[HTTPField.Name("Content-Security-Policy")!] =
      "default-src 'none'; script-src 'nonce-\(nonce)'; style-src 'nonce-\(nonce)'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
    return response
  }

  private func json(_ value: [String: Any]) throws -> Response {
    var response = Response(
      status: .ok, headers: [.contentType: "application/json"],
      body: .init(byteBuffer: ByteBuffer(bytes: try JSONSerialization.data(withJSONObject: value))))
    protect(&response)
    return response
  }

  private func error(_ code: String, status: HTTPTypes.HTTPResponse.Status) -> Response {
    var response = Response(
      status: status, headers: [.contentType: "application/json"],
      body: .init(byteBuffer: ByteBuffer(string: "{\"error\":\"\(code)\"}")))
    protect(&response)
    return response
  }

  private func protect(_ response: inout Response) {
    response.headers[.cacheControl] = "no-store"
    response.headers[HTTPField.Name("Pragma")!] = "no-cache"
    response.headers[HTTPField.Name("Referrer-Policy")!] = "no-referrer"
    response.headers[HTTPField.Name("X-Content-Type-Options")!] = "nosniff"
    response.headers[HTTPField.Name("Content-Security-Policy")!] =
      "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"
  }
}
