import Foundation
import SwiftMCP

@Schema
struct ConnectionCheck: Codable, Sendable {
  let connected: Bool
  let appleDataAccessed: Bool
  let message: String
}

public actor ToolDispatcher {
  private let reminders: ReminderTools?
  public init(reminders: EventKitReminders? = nil) {
    self.reminders = reminders.map { ReminderTools(access: $0) }
  }
  init(testReminders: any ReminderAccess) { reminders = ReminderTools(access: testReminders) }

  private static let connectionTool = MCPToolMetadata(
    name: "connection_check",
    description: "Verify this authorized connection without accessing Apple data.",
    parameters: [], returnType: ConnectionCheck.self,
    isConsequential: false, annotations: .init(hints: [.readOnly, .idempotent]))

  func tools() async -> [MCPToolMetadata] {
    guard let reminders, await reminders.access.available else { return [Self.connectionTool] }
    return [Self.connectionTool] + reminders.mcpToolMetadata
  }

  func call(_ name: String, arguments: JSONDictionary) async throws -> Encodable & Sendable {
    if name == "connection_check" {
      guard arguments.isEmpty else { throw invalidArguments("This tool takes no arguments.") }
      return ConnectionCheck(
        connected: true, appleDataAccessed: false,
        message: "iMCP-HTTP connection verified. No Apple data accessed.")
    }
    guard let reminders, let metadata = reminders.mcpToolMetadata.first(where: { $0.name == name })
    else { throw ToolFailure("unknown_tool", "Unknown or disabled tool") }
    guard await reminders.access.available else {
      throw ToolFailure(
        "service_unavailable", "Reminders is disabled or macOS permission is unavailable.")
    }
    guard Set(arguments.keys).isSubset(of: Set(metadata.parameters.map(\.name))) else {
      throw invalidArguments("Unknown argument. Consult the tool schema.")
    }
    return try await reminders.callTool(name, arguments: arguments)
  }
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
