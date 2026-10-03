import Foundation
import SwiftMCP

@Schema
struct ConnectionCheck: Codable, Sendable {
  let connected: Bool
  let appleDataAccessed: Bool
}

public actor ToolDispatcher {
  private let modules: [any AppleToolModule]
  public init(
    reminders: EventKitReminders? = nil, calendar: EventKitCalendar? = nil,
    contacts: NativeContacts? = nil, maps: NativeMaps? = nil
  ) {
    var modules: [any AppleToolModule] = []
    if let reminders { modules.append(ReminderTools(access: reminders)) }
    if let calendar { modules.append(CalendarTools(access: calendar)) }
    if let contacts { modules.append(ContactTools(access: contacts)) }
    if let maps { modules.append(MapTools(access: maps)) }
    self.modules = modules
  }
  init(testReminders: any ReminderAccess) { modules = [ReminderTools(access: testReminders)] }
  init(modules: [any AppleToolModule]) { self.modules = modules }

  private static let connectionTool = MCPToolMetadata(
    name: "connection_check",
    description: "Verify this authorized connection without accessing Apple data.",
    parameters: [], returnType: ConnectionCheck.self,
    isConsequential: false, annotations: .init(hints: [.readOnly, .idempotent]))

  func tools() async -> [MCPToolMetadata] {
    var metadata = [Self.connectionTool]
    for module in modules where await module.available { metadata += await module.mcpToolMetadata }
    return metadata
  }

  func call(_ name: String, arguments: JSONDictionary) async throws -> Encodable & Sendable {
    if name == "connection_check" {
      guard arguments.isEmpty else { throw invalidArguments("This tool takes no arguments.") }
      return ConnectionCheck(
        connected: true, appleDataAccessed: false)
    }
    for module in modules {
      guard let metadata = await module.mcpToolMetadata.first(where: { $0.name == name }) else {
        continue
      }
      guard await module.available else {
        throw ToolFailure(
          "service_unavailable", "Service is disabled or macOS permission is unavailable.")
      }
      guard Set(arguments.keys).isSubset(of: Set(metadata.parameters.map(\.name))),
        !arguments.values.contains(.null)
      else {
        throw invalidArguments("Unknown or null argument. Consult the tool schema.")
      }
      return try await module.callTool(name, arguments: arguments)
    }
    throw ToolFailure("unknown_tool", "Unknown tool")
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

protocol AppleToolModule: MCPToolProviding, Sendable {
  var available: Bool { get async }
}
extension ReminderTools: AppleToolModule {
  var available: Bool { get async { await access.available } }
}
extension CalendarTools: AppleToolModule {
  var available: Bool { get async { await access.available } }
}
extension ContactTools: AppleToolModule {
  var available: Bool { get async { await access.available } }
}
