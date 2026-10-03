import Foundation
import SwiftMCP

/// Typed function signatures are the source of tool names, input schemas, output
/// schemas, and dispatch. Authorization and availability remain in ToolDispatcher.
@MCPServer(name: "Reminders", toolNaming: .snakeCase)
final class ReminderTools: Sendable {
  let access: any ReminderAccess
  init(access: any ReminderAccess) { self.access = access }

  /// List Reminders accounts. Account support for new lists varies.
  @MCPTool(hints: [.readOnly, .idempotent])
  func remindersAccounts() async throws -> AppleAccounts { try await access.accounts() }

  /// Create a list in an exact account.
  @MCPTool
  func remindersListCreate(accountID: String, title: String) async throws -> AppleList {
    try validateIdentifier(accountID)
    try validateTitle(title)
    return try await access.createList(accountID: accountID, title: title)
  }

  /// Rename an exact list.
  @MCPTool(hints: [.destructive])
  func remindersListRename(id: String, title: String) async throws -> AppleList {
    try validateIdentifier(id)
    try validateTitle(title)
    return try await access.renameList(id: id, title: title)
  }

  /// Delete an exact list and all its reminders.
  @MCPTool(hints: [.destructive])
  func remindersListDelete(id: String) async throws -> Deletion {
    try validateIdentifier(id)
    try await access.deleteList(id: id)
    return Deletion(deleted: true, id: id)
  }

  /// List Reminders lists with exact identifiers, account context, and write availability.
  @MCPTool(hints: [.readOnly, .idempotent])
  func remindersLists() async throws -> ReminderLists {
    ReminderLists(lists: try await access.lists())
  }

  /// Search selected lists. Due presets default to incomplete; upcoming starts tomorrow.
  @MCPTool(hints: [.readOnly, .idempotent])
  func remindersFetch(query: ReminderQuery) async throws -> ReminderPage {
    try await access.fetch(query.resolve())
  }

  /// Read one exact reminder, including completed items.
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

  /// Edit an exact reminder. Omission preserves fields; clear removes them. Set completed to complete/reopen.
  @MCPTool(hints: [.destructive])
  func remindersEdit(id: String, changes: ReminderChanges) async throws -> ReminderRecord {
    try validateIdentifier(id)
    try changes.validate()
    return try await access.edit(id: id, changes: changes)
  }

  /// Move a reminder to an exact list. Use the returned id afterward.
  @MCPTool(hints: [.destructive])
  func remindersMove(id: String, listID: String) async throws -> ReminderRecord {
    try validateIdentifier(id)
    try validateIdentifier(listID)
    return try await access.move(id: id, listID: listID)
  }

  /// Delete an exact reminder using native recurrence behavior.
  @MCPTool(hints: [.destructive])
  func remindersDelete(id: String) async throws -> ReminderDeletion {
    try validateIdentifier(id)
    try await access.delete(id: id)
    return ReminderDeletion(deleted: true, id: id)
  }
}
