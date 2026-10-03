import Foundation
import HTTPTypes
import SwiftMCP
import Testing

@testable import IMCPCore

struct MCPContractTests {
  @Test func protocolVersionControlsResultsAndSchemas() async throws {
    let f = try AuthorizationFixture()
    defer { f.cleanup() }
    let tokens = try await f.tokens()
    let grant = try await f.store.authenticate("Bearer \(tokens.accessToken)")
    let gateway = MCPGateway(
      authorization: f.store,
      dispatcher: ToolDispatcher(modules: [
        ReminderTools(access: FakeReminders()), CalendarTools(access: FakeCalendar()),
        ContactTools(access: FakeContacts()), MapTools(access: FakeMaps()),
      ]))
    func request(_ method: String, version: String?, params: JSONDictionary? = nil) async throws
      -> MCPGateway.Reply
    {
      var headers: HTTPFields = [.contentType: "application/json", .accept: "application/json"]
      headers[HTTPField.Name("MCP-Protocol-Version")!] = version
      let message = JSONRPCMessage.request(
        id: 1, method: method, params: params.map(JSONValue.object))
      return try await gateway.respond(
        method: .post, headers: headers,
        body: JSONEncoder().encode(message), grant: grant)
    }
    func result(_ reply: MCPGateway.Reply) throws -> JSONDictionary {
      check(reply.status == .ok)
      let envelope = try JSONDecoder().decode(JSONValue.self, from: reply.data)
      return try require(envelope.dictionaryValue?["result"]?.dictionaryValue)
    }
    for version: String? in [nil, "2025-03-26", "2025-06-18", "2025-11-25"] {
      let structured = version == "2025-06-18" || version == "2025-11-25"
      // A conflicting body meta value must never override the HTTP version.
      let called = try result(
        await request(
          "tools/call", version: version,
          params: [
            "name": "connection_check", "arguments": [:],
            "_meta": ["io.modelcontextprotocol/protocolVersion": "2025-11-25"],
          ]))
      check((called["structuredContent"] != nil) == structured)
      check(called["isError"] == false)
      let listing = try result(await request("tools/list", version: version))
      let tools = try require(listing["tools"]?.arrayValue)
      for tool in tools {
        let object = try require(tool.dictionaryValue)
        check((object["outputSchema"] != nil) == structured)
      }
      let edit = try require(
        tools.first { $0.dictionaryValue?["name"] == "reminders_edit" }?.dictionaryValue)
      let schema = try require(edit["inputSchema"]?.dictionaryValue)
      let properties = try require(schema["properties"]?.dictionaryValue)
      let changes = try require(
        properties["changes"]?.dictionaryValue?["properties"]?.dictionaryValue)
      check(changes["due"]?.dictionaryValue?["properties"]?.dictionaryValue?["date"] != nil)
      check(
        changes["clear"]?.dictionaryValue?["items"]?.dictionaryValue?["enum"]?.arrayValue == [
          "notes", "due", "start", "url", "location",
        ])
      let fetched = try result(
        await request(
          "tools/call", version: version,
          params: [
            "name": "reminders_fetch",
            "arguments": ["query": ["listIDs": ["fixture"], "due": "today"]],
          ]))
      check(fetched["isError"] == false)
    }
    check(try await request("tools/list", version: "unsupported").status == .badRequest)
    for version in ["2025-03-26", "2025-11-25"] {
      let initialized = try result(
        await request(
          "initialize", version: nil,
          params: [
            "protocolVersion": .string(version), "clientInfo": ["name": "fixture", "version": "1"],
            "capabilities": ["experimental": ["codex/auth-change": [:]]],
          ]))
      check(initialized["protocolVersion"] == .string(version))
    }
  }
}
