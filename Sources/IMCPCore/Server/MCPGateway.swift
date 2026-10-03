import Foundation
import HTTPTypes
import SwiftMCP

/// A bounded, stateless Streamable HTTP adapter. SwiftMCP owns JSON-RPC decoding,
/// protocol negotiation, method dispatch, and MCP result encoding; Hummingbird owns HTTP.
struct MCPGateway: Sendable {
  let authorization: AuthorizationStore
  let dispatcher: ToolDispatcher

  struct Reply: Sendable {
    var status: HTTPResponse.Status
    var data: Data = Data()
    var headers: HTTPFields = [.contentType: "application/json"]
  }

  func respond(method: HTTPRequest.Method, headers: HTTPFields, body: Data, grant: UUID)
    async throws -> Reply
  {
    guard method == .post else {
      return Reply(status: .methodNotAllowed, headers: [.allow: "POST"])
    }
    guard mediaTypes(headers[.contentType]).contains("application/json") else {
      return Reply(status: .unsupportedMediaType)
    }
    guard mediaTypes(headers[.accept]).contains("application/json") else {
      return Reply(status: .notAcceptable)
    }
    if let version = headers[HTTPField.Name("MCP-Protocol-Version")!],
      !MCPProtocolVersion.supported.contains(version)
    {
      return Reply(status: .badRequest)
    }
    let message: JSONRPCMessage
    do { message = try JSONDecoder().decode(JSONRPCMessage.self, from: body) } catch {
      let failure = JSONRPCMessage.errorResponse(
        id: nil, error: .init(code: -32700, message: "Invalid JSON-RPC message"))
      return Reply(status: .badRequest, data: try JSONEncoder().encode(failure))
    }
    let server = RequestServer(authorization: authorization, dispatcher: dispatcher, grant: grant)
    // The SDK reads the protocol from its task-local session. Use a request-local
    // context, not a retained HTTP session, to preserve stateless/concurrent dispatch.
    // Missing headers default to the original Streamable HTTP revision per the spec.
    let context = Session(id: UUID())
    await context.setNegotiatedProtocolVersion(
      headers[HTTPField.Name("MCP-Protocol-Version")!] ?? MCPProtocolVersion.fallbackHTTP)
    let response = await context.work { _ in await server.handleMessage(message) }
    guard var response else { return Reply(status: .accepted) }
    // Capability delivery belongs to the transport. The SDK defaults to a
    // persistent connection; this stateless transport cannot deliver list changes.
    if ["initialize", "server/discover"].contains(message.method ?? ""),
      case .response(let envelope) = response,
      case .object(var result) = envelope.result,
      case .object(var capabilities) = result["capabilities"]
    {
      capabilities["tools"] = .object(["listChanged": false])
      capabilities.removeValue(forKey: "completions")
      result["capabilities"] = .object(capabilities)
      response = .response(id: envelope.id, result: .object(result))
    }
    return Reply(status: .ok, data: try JSONEncoder().encode(response))
  }

  private func mediaTypes(_ value: String?) -> [String] {
    (value ?? "").split(separator: ",").map {
      $0.split(separator: ";", omittingEmptySubsequences: false)[0].trimmingCharacters(
        in: .whitespaces
      ).lowercased()
    }
  }
}

private struct RequestServer: MCPServer, MCPToolProviding {
  let authorization: AuthorizationStore
  let dispatcher: ToolDispatcher
  let grant: UUID
  var serverName: String { "iMCP-HTTP" }
  var serverVersion: String { "0.3.0" }
  var mcpToolMetadata: [MCPToolMetadata] {
    get async {
      guard (try? await authorization.requireActive(grant)) != nil else { return [] }
      return await dispatcher.tools()
    }
  }
  func callTool(_ name: String, arguments: JSONDictionary) async throws -> Encodable & Sendable {
    try await authorization.requireActive(grant)
    return try await dispatcher.call(name, arguments: arguments)
  }
}
