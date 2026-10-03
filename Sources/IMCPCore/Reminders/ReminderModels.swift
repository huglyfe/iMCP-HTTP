import Foundation
import SwiftMCP

@Schema
struct ReminderList: Codable, Sendable {
  let id: String
  let title: String
  let account: String
  let accountID: String
  let writable: Bool
}

@Schema
struct ReminderLists: Codable, Sendable {
  let lists: [ReminderList]
}

@Schema
struct ReminderRecord: Codable, Sendable {
  let id: String
  let listID: String
  let title: String
  let notes: String?
  let priority: Int
  let completed: Bool
  let due: ReminderDate?
  /// Existing recurrence and alarms are preserved, but are not editable yet.
  var isRecurring: Bool = false
  var hasAlarms: Bool = false
}

@Schema
struct ReminderPage: Codable, Sendable {
  let reminders: [ReminderRecord]
  let total: Int
  let nextOffset: Int?
  /// The resolved timezone used for date filtering and sorting.
  let timeZone: String
}

@Schema
struct ReminderDeletion: Codable, Sendable {
  let deleted: Bool
  let id: String
}

enum ReminderClearField: String, Codable, CaseIterable, Hashable, Sendable {
  case notes, due
}

@Schema
struct ReminderChanges: Codable, Sendable {
  /// Nonempty text, at most 1024 UTF-8 bytes. Required on create.
  var title: String?
  /// At most 16384 UTF-8 bytes. Omit to preserve; use clear to remove.
  var notes: String?
  var due: ReminderDate?
  /// Integer 0 through 9; 0 means none, 1 is highest.
  var priority: Int?
  /// True completes the reminder; false reopens it.
  var completed: Bool?
  /// Remove these fields. A field cannot also be assigned in this change.
  var clear: [ReminderClearField]?

  func validate(creating: Bool = false) throws {
    if let title {
      guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        title.utf8.count <= 1024
      else { throw invalidArguments("Title must be nonempty and at most 1024 UTF-8 bytes.") }
    }
    if creating, title == nil { throw invalidArguments("A title is required on create.") }
    if let notes, notes.utf8.count > 16384 {
      throw invalidArguments("Notes must be at most 16384 UTF-8 bytes.")
    }
    if let priority, !(0...9).contains(priority) {
      throw invalidArguments("Priority must be an integer from 0 through 9.")
    }
    let fields = clear ?? []
    guard Set(fields).count == fields.count,
      !(fields.contains(.notes) && notes != nil), !(fields.contains(.due) && due != nil)
    else {
      throw invalidArguments("Do not assign and clear the same field or repeat clear fields.")
    }
    guard
      title != nil || notes != nil || due != nil || priority != nil || completed != nil
        || !fields.isEmpty
    else { throw invalidArguments("Provide at least one change.") }
    if let due { _ = try due.components() }
  }
}

extension ReminderChanges {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    title = try values.optional(String.self, forKey: .title)
    notes = try values.optional(String.self, forKey: .notes)
    due = try values.optional(ReminderDate.self, forKey: .due)
    priority = try values.optional(Int.self, forKey: .priority)
    completed = try values.optional(Bool.self, forKey: .completed)
    clear = try values.optional([ReminderClearField].self, forKey: .clear)
  }
}

@MainActor
protocol ReminderAccess: Sendable {
  var available: Bool { get }
  func lists() throws -> [ReminderList]
  func fetch(_ query: ResolvedReminderQuery) async throws -> ReminderPage
  func get(id: String) throws -> ReminderRecord
  func create(listID: String, changes: ReminderChanges) throws -> ReminderRecord
  func edit(id: String, changes: ReminderChanges) throws -> ReminderRecord
  func move(id: String, listID: String) throws -> ReminderRecord
  func delete(id: String) throws
}

func invalidArguments(_ message: String) -> ToolFailure {
  ToolFailure("invalid_arguments", message)
}

func validateIdentifier(_ id: String) throws {
  guard !id.isEmpty, id.utf8.count <= 1024 else {
    throw invalidArguments("An exact, nonempty identifier of at most 1024 UTF-8 bytes is required.")
  }
}

// Codable normally ignores unknown fields and treats null as absent. Tool inputs
// deliberately reject both: misspellings must not turn a requested edit into a no-op.
private struct InputKey: CodingKey {
  var stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

extension Decoder {
  func rejectUnknownFields<Key: CodingKey>(_ type: Key.Type) throws {
    let values = try container(keyedBy: InputKey.self)
    guard values.allKeys.allSatisfy({ Key(stringValue: $0.stringValue) != nil }) else {
      throw invalidArguments("Unknown field. Consult the tool schema.")
    }
  }
}

extension KeyedDecodingContainer {
  func optional<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
    guard contains(key) else { return nil }
    return try decode(type, forKey: key)
  }
}
