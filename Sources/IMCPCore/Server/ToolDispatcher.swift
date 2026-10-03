import Foundation
import SwiftMCP

public actor ToolDispatcher {
  private let reminders: (any ReminderAccess)?
  public init(reminders: EventKitReminders? = nil) { self.reminders = reminders }
  init(testReminders: any ReminderAccess) { reminders = testReminders }

  func tools() async -> [MCPToolMetadata] {
    var tools = [
      MCPToolMetadata(
        name: "connection_check",
        description: "Verify this authorized connection without accessing Apple data.",
        parameters: [], isConsequential: false, annotations: .init(hints: [.readOnly, .idempotent]))
    ]
    if await reminders?.available == true { tools += Self.reminderTools }
    return tools
  }

  func call(_ name: String, arguments: JSONDictionary) async throws -> JSONDictionary {
    if name == "connection_check" {
      try keys(arguments, allowed: [])
      return [
        "connected": true, "appleDataAccessed": false,
        "message": "iMCP-HTTP connection verified. No Apple data accessed.",
      ]
    }
    guard Self.reminderTools.contains(where: { $0.name == name }), let reminders else {
      throw ToolFailure("unknown_tool", "Unknown or disabled tool")
    }
    guard await reminders.available else {
      throw ToolFailure(
        "service_unavailable", "Reminders is disabled or macOS permission is unavailable.")
    }
    switch name {
    case "reminders_lists":
      try keys(arguments, allowed: [])
      return ["lists": try JSONValue(encoding: await reminders.lists())]
    case "reminders_fetch":
      try keys(arguments, allowed: ["listID", "completed", "offset", "limit"])
      let completed: Bool?
      if let raw = arguments["completed"] {
        guard case .bool(let value) = raw else {
          throw ToolFailure(
            "invalid_arguments", "Completed must be a boolean, or omitted for all reminders.")
        }
        completed = value
      } else {
        completed = nil
      }
      return try JSONDictionary(
        encoding: await reminders.fetch(
          listID: identifier(arguments, "listID"), completed: completed,
          offset: integer(arguments, "offset", default: 0, range: 0...100000),
          limit: integer(arguments, "limit", default: 100, range: 1...200)))
    case "reminders_get":
      try keys(arguments, allowed: ["id"])
      return try JSONDictionary(encoding: await reminders.get(id: identifier(arguments, "id")))
    case "reminders_create", "reminders_edit":
      let creating = name == "reminders_create"
      let target = creating ? "listID" : "id"
      try keys(arguments, allowed: [target, "changes"])
      let id = try identifier(arguments, target)
      guard case .object(let fields) = arguments["changes"] else {
        throw ToolFailure("invalid_arguments", "Changes must be an object.")
      }
      let changes = try ReminderChanges(fields, creating: creating)
      let result =
        creating
        ? try await reminders.create(listID: id, changes: changes)
        : try await reminders.edit(id: id, changes: changes)
      return try JSONDictionary(encoding: result)
    case "reminders_delete":
      try keys(arguments, allowed: ["id"])
      let id = try identifier(arguments, "id")
      try await reminders.delete(id: id)
      return ["deleted": true, "id": .string(id)]
    default: throw ToolFailure("unknown_tool", "Unknown tool")
    }
  }

  private func keys(_ fields: JSONDictionary, allowed: Set<String>) throws {
    guard Set(fields.keys).isSubset(of: allowed) else {
      throw ToolFailure("invalid_arguments", "Unknown argument. Consult the tool schema.")
    }
  }
  private func identifier(_ fields: JSONDictionary, _ key: String) throws -> String {
    guard case .string(let id) = fields[key], !id.isEmpty, id.utf8.count <= 1024 else {
      throw ToolFailure("invalid_arguments", "An exact, nonempty identifier is required.")
    }
    return id
  }
  private func integer(
    _ fields: JSONDictionary, _ key: String, default value: Int, range: ClosedRange<Int>
  ) throws -> Int {
    guard let raw = fields[key] else { return value }
    guard case .integer(let number) = raw, range.contains(number) else {
      throw ToolFailure("invalid_arguments", "Invalid \(key). Consult the tool schema.")
    }
    return number
  }
  private static let reminderTools: [MCPToolMetadata] = {
    let id = MCPParameterInfo(
      name: "id", type: String.self,
      description: "Exact opaque reminder identifier returned by fetch or get.", isRequired: true)
    let list = MCPParameterInfo(
      name: "listID", type: String.self,
      description: "Exact opaque list identifier from reminders_lists; no default list fallback.",
      isRequired: true)
    let changes = MCPParameterInfo(
      name: "changes", type: JSONDictionary.self,
      description:
        "Fields: title (nonempty string, required on create), notes (string or null to clear), due (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS with Z or ±HH:MM, or null to clear), priority (integer 0–9; 0 none, 1 highest), completed (boolean). Omitted fields remain unchanged. Timed due dates normalize to UTC. No list moves or recurrence editing.",
      isRequired: true)
    return [
      MCPToolMetadata(
        name: "reminders_lists",
        description:
          "List available Reminders lists with account/source identifiers and write availability.",
        parameters: [], isConsequential: false, annotations: .init(hints: [.readOnly, .idempotent])),
      MCPToolMetadata(
        name: "reminders_fetch",
        description:
          "Fetch one exact list, sorted by identifier. Includes completed items unless filtered. Pagination is not a snapshot: restart from offset zero if the list changes.",
        parameters: [
          list,
          .init(
            name: "completed", type: Bool.self,
            description: "Optional completion filter; omit for both.", isRequired: false),
          .init(
            name: "offset", type: Int.self, description: "0–100000; default 0.", isRequired: false),
          .init(
            name: "limit", type: Int.self, description: "1–200; default 100.", isRequired: false),
        ], isConsequential: false, annotations: .init(hints: [.readOnly, .idempotent])),
      MCPToolMetadata(
        name: "reminders_get",
        description:
          "Read the exact reminder, including completed reminders. Due dates retain native DateComponents and timezone.",
        parameters: [id], isConsequential: false,
        annotations: .init(hints: [.readOnly, .idempotent])),
      MCPToolMetadata(
        name: "reminders_create",
        description:
          "Create a reminder in an explicitly identified writable list. Do not retry a failed or interrupted save before checking for the item.",
        parameters: [list, changes], annotations: .init(hints: [])),
      MCPToolMetadata(
        name: "reminders_edit",
        description:
          "Patch the exact reminder, preserving omitted fields. Setting completed true completes it; false reopens it. Read back after any uncertain outcome before retrying.",
        parameters: [id, changes], annotations: .init(hints: [.destructive])),
      MCPToolMetadata(
        name: "reminders_delete",
        description:
          "Permanently delete the exact reminder, including completed reminders. Verify absence if the call is interrupted; do not blindly retry.",
        parameters: [id], annotations: .init(hints: [.destructive])),
    ]
  }()
}

struct ToolFailure: LocalizedError, MCPToolErrorMetaProviding, Sendable {
  let code: String
  let message: String
  init(_ code: String, _ message: String) {
    self.code = code
    self.message = message
  }
  var errorDescription: String? { message }
  var toolErrorMeta: JSONDictionary { ["errorCode": .string(code)] }
}
