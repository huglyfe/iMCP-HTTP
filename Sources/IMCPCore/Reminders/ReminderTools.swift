import Foundation
import SwiftMCP

/// Typed function signatures are the source of tool names, input schemas, output
/// schemas, and dispatch. Authorization and availability remain in ToolDispatcher.
@MCPServer(name: "Reminders", toolNaming: .snakeCase)
final class ReminderTools: Sendable {
  let access: any ReminderAccess
  init(access: any ReminderAccess) { self.access = access }

  /// List Reminders lists with exact identifiers, account context, and write availability.
  @MCPTool(hints: [.readOnly, .idempotent])
  func remindersLists() async throws -> ReminderLists {
    ReminderLists(lists: try await access.lists())
  }

  /// Search selected lists by title/notes, completion, and due dates. Today includes the
  /// whole local day; overdue includes past timed deadlines and date-only deadlines
  /// before today; upcoming starts tomorrow. Date presets default to incomplete items.
  /// Pagination is not a snapshot: restart at zero after changes. No Apple data is cached.
  @MCPTool(hints: [.readOnly, .idempotent])
  func remindersFetch(query: ReminderQuery) async throws -> ReminderPage {
    try await access.fetch(query.resolve())
  }

  /// Read one exact reminder, including completed items. Recurrence/alarm flags describe
  /// native fields that are preserved but not yet editable.
  @MCPTool(hints: [.readOnly, .idempotent])
  func remindersGet(id: String) async throws -> ReminderRecord {
    try validateIdentifier(id)
    return try await access.get(id: id)
  }

  /// Create a reminder in an explicitly identified writable list. Title is required.
  /// Check for the item before retrying an interrupted or failed save.
  @MCPTool
  func remindersCreate(listID: String, changes: ReminderChanges) async throws -> ReminderRecord {
    try validateIdentifier(listID)
    try changes.validate(creating: true)
    return try await access.create(listID: listID, changes: changes)
  }

  /// Patch an exact reminder. Omitted fields are preserved; clear removes notes/due.
  /// Completed true/false completes/reopens. Native recurring reminders follow Apple
  /// recurrence behavior. Read back after an uncertain outcome before retrying.
  @MCPTool(hints: [.destructive])
  func remindersEdit(id: String, changes: ReminderChanges) async throws -> ReminderRecord {
    try validateIdentifier(id)
    try changes.validate()
    return try await access.edit(id: id, changes: changes)
  }

  /// Move one exact reminder to an exact writable destination list. Both lists must be
  /// writable. Returns the saved reminder: its identifier can change across accounts.
  /// Re-fetch the source and destination after an uncertain outcome before retrying.
  @MCPTool(hints: [.destructive])
  func remindersMove(id: String, listID: String) async throws -> ReminderRecord {
    try validateIdentifier(id)
    try validateIdentifier(listID)
    return try await access.move(id: id, listID: listID)
  }

  /// Permanently delete the exact reminder. Native recurring reminders follow Apple's
  /// deletion behavior. Verify absence after an interrupted call before retrying.
  @MCPTool(hints: [.destructive])
  func remindersDelete(id: String) async throws -> ReminderDeletion {
    try validateIdentifier(id)
    try await access.delete(id: id)
    return ReminderDeletion(deleted: true, id: id)
  }
}
