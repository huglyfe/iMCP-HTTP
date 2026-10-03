import Foundation
import SwiftMCP

@MCPServer(name: "Calendar", toolNaming: .snakeCase)
final class CalendarTools: Sendable {
  let access: any CalendarAccess
  init(access: any CalendarAccess) { self.access = access }

  /// List Calendar accounts. Account support for new calendars varies.
  @MCPTool(hints: [.readOnly, .idempotent])
  func calendarAccounts() async throws -> AppleAccounts { try await access.accounts() }

  /// List calendars and their write access.
  @MCPTool(hints: [.readOnly, .idempotent])
  func calendarLists() async throws -> AppleLists { AppleLists(lists: try await access.lists()) }

  /// Create a calendar in an exact account.
  @MCPTool
  func calendarListCreate(accountID: String, title: String) async throws -> AppleList {
    try validateIdentifier(accountID)
    try validateTitle(title)
    return try await access.createList(accountID: accountID, title: title)
  }

  /// Rename an exact calendar.
  @MCPTool(hints: [.destructive])
  func calendarListRename(id: String, title: String) async throws -> AppleList {
    try validateIdentifier(id)
    try validateTitle(title)
    return try await access.renameList(id: id, title: title)
  }

  /// Delete an exact calendar and all its events.
  @MCPTool(hints: [.destructive])
  func calendarListDelete(id: String) async throws -> Deletion {
    try validateIdentifier(id)
    try await access.deleteList(id: id)
    return Deletion(deleted: true, id: id)
  }

  /// Fetch occurrences overlapping an ISO 8601 range, up to 366 days. Search matches title, notes, or location.
  @MCPTool(hints: [.readOnly, .idempotent])
  func calendarFetch(
    calendarIDs: [String], start: String, end: String, search: String? = nil,
    offset: Int = 0, limit: Int = 100
  ) async throws -> EventPage {
    try validatePage(offset: offset, limit: limit, search: search)
    guard !calendarIDs.isEmpty, calendarIDs.count <= 50, Set(calendarIDs).count == calendarIDs.count
    else {
      throw invalidArguments("Choose 1–50 distinct calendar IDs.")
    }
    try calendarIDs.forEach(validateIdentifier)
    let from = try NativeDates.parse(start)
    let to = try NativeDates.parse(end)
    guard to > from, to.timeIntervalSince(from) <= 366 * 86400 else {
      throw invalidArguments("Range must be positive and at most 366 days.")
    }
    return try await access.fetch(
      calendarIDs: calendarIDs, start: from, end: to,
      search: search, offset: offset, limit: limit)
  }

  /// Read one occurrence using its returned id and start.
  @MCPTool(hints: [.readOnly, .idempotent])
  func calendarGet(id: String, start: String) async throws -> EventRecord {
    try validateIdentifier(id)
    return try await access.get(id: id, start: NativeDates.parse(start))
  }

  /// Create an event in an exact calendar. Returns the saved event.
  @MCPTool
  func calendarCreate(calendarID: String, changes: EventChanges) async throws -> EventRecord {
    try validateIdentifier(calendarID)
    try changes.validate(creating: true)
    return try await access.create(calendarID: calendarID, changes: changes)
  }

  /// Edit an occurrence or this and future occurrences. Omitted fields stay unchanged; shared events may notify attendees.
  @MCPTool(hints: [.destructive])
  func calendarEdit(id: String, start: String, span: EventSpan, changes: EventChanges) async throws
    -> EventRecord
  {
    try validateIdentifier(id)
    try changes.validate()
    return try await access.edit(
      id: id, start: NativeDates.parse(start), span: span, changes: changes)
  }

  /// Move an occurrence or this and future occurrences. Use the returned id and start afterward.
  @MCPTool(hints: [.destructive])
  func calendarMove(id: String, start: String, span: EventSpan, calendarID: String) async throws
    -> EventRecord
  {
    try validateIdentifier(id)
    try validateIdentifier(calendarID)
    return try await access.move(
      id: id, start: NativeDates.parse(start), span: span, calendarID: calendarID)
  }

  /// Delete an occurrence or this and future occurrences; shared events may notify attendees.
  @MCPTool(hints: [.destructive])
  func calendarDelete(id: String, start: String, span: EventSpan) async throws -> Deletion {
    try validateIdentifier(id)
    try await access.delete(id: id, start: NativeDates.parse(start), span: span)
    return Deletion(deleted: true, id: id)
  }
}
