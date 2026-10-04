import Foundation
import HTTPTypes
import SwiftMCP
import Testing

@testable import IMCPCore

struct ToolSettingsTests {
  @Test func persistedToolPolicyControlsDiscoveryAndStaleCalls() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("services.json")
    var settings = try JSONDecoder().decode(
      ServiceSettings.self,
      from: Data(#"{"remindersEnabled":true}"#.utf8))
    check(settings.disabledTools.isEmpty)
    let reminders = FakeReminders()
    let dispatcher = ToolDispatcher(testReminders: reminders)
    let catalog = await dispatcher.catalog()
    check(catalog.contains { $0.name == "reminders_delete" && $0.service == .reminders })
    check(catalog.contains { $0.name == "reminders_get" && $0.readOnly })
    check(await reminders.writes.isEmpty)
    check(await reminders.reads == 0)
    check(await dispatcher.tools().contains { $0.name == "reminders_delete" })

    settings.disabledTools.insert("reminders_delete")
    try settings.save(to: url)
    let restored = try ServiceSettings.load(from: url)
    // A new dispatcher represents a restarted app loading the saved policy.
    let restarted = ToolDispatcher(testReminders: reminders)
    await restarted.setDisabledTools(restored.disabledTools)
    check(await !restarted.tools().contains { $0.name == "reminders_delete" })
    check(await restarted.tools().contains { $0.name == "reminders_get" })
    await expectFailure {
      try await restarted.call("reminders_delete", arguments: ["id": "fixture"])
    }
    check(await reminders.writes.isEmpty)
    _ = try await restarted.call("reminders_get", arguments: ["id": "fixture"])
    await restarted.setDisabledTools([])
    _ = try await restarted.call("reminders_delete", arguments: ["id": "fixture"])
    check(await reminders.writes == ["delete:fixture"])
    await reminders.setAvailable(false)
    check(await restarted.tools().map(\.name) == ["connection_check"])
    await expectFailure {
      try await restarted.call("reminders_delete", arguments: ["id": "fixture"])
    }
    check(await reminders.writes == ["delete:fixture"])
  }

  @Test func livePolicyAppliesToEveryAuthorizedClient() async throws {
    let f = try AuthorizationFixture()
    defer { f.cleanup() }
    let reminders = FakeReminders()
    let dispatcher = ToolDispatcher(testReminders: reminders)
    let gateway = MCPGateway(authorization: f.store, dispatcher: dispatcher)
    var grants: [UUID] = []
    for _ in 0..<2 {
      let tokens = try await f.tokens()
      grants.append(try await f.store.authenticate("Bearer \(tokens.accessToken)"))
    }
    await dispatcher.setDisabledTools(["reminders_delete"])
    for grant in grants {
      let request = JSONRPCMessage.request(
        id: 1, method: "tools/call",
        params: .object(["name": "reminders_delete", "arguments": ["id": "fixture"]]))
      let reply = try await gateway.respond(
        method: .post,
        headers: [.contentType: "application/json", .accept: "application/json"],
        body: JSONEncoder().encode(request), grant: grant)
      let json = try JSONDecoder().decode(JSONValue.self, from: reply.data)
      check(json.dictionaryValue?["result"]?.dictionaryValue?["isError"] == true)
    }
    check(await reminders.writes.isEmpty)
  }
}
