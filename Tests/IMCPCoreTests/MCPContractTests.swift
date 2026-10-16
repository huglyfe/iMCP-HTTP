import Foundation
import HTTPTypes
import SwiftMCP
import Testing

@testable import IMCPCore

struct MCPContractTests {
  @Test func protocolVersionControlsResultsAndSchemas() async throws {
    let f = try await AuthorizationFixture()
    defer { f.cleanup() }
    let tokens = try await f.tokens()
    let grant = try await f.store.authenticate("Bearer \(tokens.accessToken)")
    let (mail, notes) = await MainActor.run {
      let runner = FixtureScriptRunner()
      let mail = NativeMail(runner: runner, permissionCheck: { _ in true })
      let notes = NativeNotes(runner: runner, permissionCheck: { _ in true })
      mail.setEnabled(true)
      notes.setEnabled(true)
      return (mail, notes)
    }
    let gateway = MCPGateway(
      authorization: f.store,
      dispatcher: ToolDispatcher(modules: [
        ReminderTools(access: FakeReminders()), CalendarTools(access: FakeCalendar()),
        ContactTools(access: FakeContacts()), MapTools(access: FakeMaps()),
        BluetoothTools(access: FixtureBluetooth()), MailTools(access: mail),
        NoteTools(access: notes),
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
      #expect(reply.status == .ok)
      let envelope = try JSONDecoder().decode(JSONValue.self, from: reply.data)
      return try #require(envelope.dictionaryValue?["result"]?.dictionaryValue)
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
      #expect((called["structuredContent"] != nil) == structured)
      #expect(called["isError"] == false)
      let listing = try result(await request("tools/list", version: version))
      let tools = try #require(listing["tools"]?.arrayValue)
      for tool in tools {
        let object = try #require(tool.dictionaryValue)
        #expect((object["outputSchema"] != nil) == structured)
      }
      if structured {
        for tool in tools {
          let output = try #require(tool.dictionaryValue?["outputSchema"]?.dictionaryValue)
          #expect(output["required"]?.arrayValue?.isEmpty == false)
        }
        let connection = try #require(
          tools.first { $0.dictionaryValue?["name"] == "connection_check" }?.dictionaryValue)
        let required = try #require(
          connection["outputSchema"]?.dictionaryValue?["required"]?.arrayValue)
        #expect(Set(required.compactMap(\.stringValue)) == ["connected", "appleDataAccessed"])
      }
      for (name, required) in [
        ("reminders_create", ["title"]), ("calendar_create", ["title", "start", "end"]),
      ] {
        let tool = try #require(
          tools.first { $0.dictionaryValue?["name"] == .string(name) }?.dictionaryValue)
        let input = try #require(
          tool["inputSchema"]?.dictionaryValue?["properties"]?.dictionaryValue?["changes"]?
            .dictionaryValue)
        #expect(
          Set(input["required"]?.arrayValue?.compactMap(\.stringValue) ?? []) == Set(required))
      }
      if structured {
        for (name, array, forbidden) in [
          ("mail_fetch", "messages", "body"), ("notes_fetch", "notes", "bodyHTML"),
        ] {
          let tool = try #require(
            tools.first { $0.dictionaryValue?["name"] == .string(name) }?.dictionaryValue)
          let properties = try #require(
            tool["outputSchema"]?.dictionaryValue?["properties"]?.dictionaryValue?[array]?
              .dictionaryValue?["items"]?.dictionaryValue?["properties"]?.dictionaryValue)
          #expect(properties[forbidden] == nil)
        }
      }
      for arguments: JSONDictionary in [
        ["id": "fixture"],
        ["id": 1, "changes": ["title": "Fixture"]],
        ["id": "fixture", "changes": ["due": .null]],
      ] {
        let failure = try result(
          await request(
            "tools/call", version: version,
            params: ["name": "reminders_edit", "arguments": .object(arguments)]))
        #expect(failure["isError"] == true)
        #expect(failure["_meta"]?.dictionaryValue?["errorCode"] == "invalid_arguments")
      }
      let malformed = try await request(
        "tools/call", version: version,
        params: ["name": "connection_check", "arguments": "invalid"])
      let malformedEnvelope = try JSONDecoder().decode(JSONValue.self, from: malformed.data)
      #expect(malformedEnvelope.dictionaryValue?["error"]?.dictionaryValue?["code"] == -32602)
      let edit = try #require(
        tools.first { $0.dictionaryValue?["name"] == "reminders_edit" }?.dictionaryValue)
      let schema = try #require(edit["inputSchema"]?.dictionaryValue)
      let properties = try #require(schema["properties"]?.dictionaryValue)
      let changes = try #require(
        properties["changes"]?.dictionaryValue?["properties"]?.dictionaryValue)
      #expect(changes["due"]?.dictionaryValue?["properties"]?.dictionaryValue?["date"] != nil)
      #expect(
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
      #expect(fetched["isError"] == false)
      for name in ["mail_accounts", "notes_accounts", "ble_devices"] {
        let response = try result(
          await request(
            "tools/call", version: version, params: ["name": .string(name), "arguments": [:]]))
        #expect(response["isError"] == false)
        #expect((response["structuredContent"] != nil) == structured)
      }
      let rejected = try result(
        await request(
          "tools/call", version: version,
          params: [
            "name": "ble_write",
            "arguments": ["characteristicID": .string(UUID().uuidString), "base64": "bad!"],
          ]))
      #expect(rejected["isError"] == true)
    }
    #expect(try await request("tools/list", version: "unsupported").status == .badRequest)
    for version in ["2025-03-26", "2025-11-25"] {
      let initialized = try result(
        await request(
          "initialize", version: nil,
          params: [
            "protocolVersion": .string(version), "clientInfo": ["name": "fixture", "version": "1"],
            "capabilities": ["experimental": ["codex/auth-change": [:]]],
          ]))
      #expect(initialized["protocolVersion"] == .string(version))
    }
  }
}
