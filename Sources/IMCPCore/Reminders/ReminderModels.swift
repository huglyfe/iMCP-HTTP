import Foundation
import SwiftMCP

typealias ReminderList = AppleList
typealias ReminderLists = AppleLists

@Schema
struct ReminderRecord: Codable, Sendable {
  let id: String
  let listID: String
  let title: String
  let notes: String?
  let priority: Int
  let completed: Bool
  let due: AppleDate?
  var start: AppleDate?
  var url: String?
  var location: String?
  var recurrence: [RepeatRule]?
  var alarms: [TimeAlarm]?
  var otherAlarms: Int?

}

@Schema
struct ReminderSummary: Codable, Sendable {
  let id: String
  let listID: String
  let title: String
  let priority: Int
  let completed: Bool
  let due: AppleDate?
  init(_ record: ReminderRecord) {
    id = record.id
    listID = record.listID
    title = record.title
    priority = record.priority
    completed = record.completed
    due = record.due
  }
}

@Schema
struct ReminderPage: Codable, Sendable {
  let reminders: [ReminderSummary]
  let total: Int
  let nextOffset: Int?
  /// The resolved timezone used for date filtering and sorting.
  let timeZone: String
}

typealias ReminderDeletion = Deletion

enum ReminderClearField: String, Codable, CaseIterable, Hashable, Sendable {
  case notes, due, start, url, location
}

@Schema
struct ReminderChanges: Codable, Sendable {
  /// Nonempty text, at most 1024 UTF-8 bytes. Required on create.
  var title: String?
  /// At most 16384 UTF-8 bytes. Omit to preserve; use clear to remove.
  var notes: String?
  var due: AppleDate?
  var start: AppleDate?
  var url: String?
  var location: String?
  /// Replace the native schedule; [] removes recurrence.
  var recurrence: [RepeatRule]?
  /// Replace display alarms; [] removes them. Other alarm types are preserved.
  var alarms: [TimeAlarm]?
  /// Integer 0 through 9; 0 means none, 1 is highest.
  var priority: Int?
  /// True completes the reminder; false reopens it.
  var completed: Bool?
  /// Remove these fields. A field cannot also be assigned in this change.
  var clear: [ReminderClearField]?

  func validate(creating: Bool = false) throws {
    if let title { try validateTitle(title) }
    if creating, title == nil { throw invalidArguments("A title is required on create.") }
    if let notes, notes.utf8.count > 16384 {
      throw invalidArguments("Notes must be at most 16384 UTF-8 bytes.")
    }
    if let priority, !(0...9).contains(priority) {
      throw invalidArguments("Priority must be an integer from 0 through 9.")
    }
    let fields = clear ?? []
    guard Set(fields).count == fields.count,
      !(fields.contains(.notes) && notes != nil), !(fields.contains(.due) && due != nil),
      !(fields.contains(.start) && start != nil), !(fields.contains(.url) && url != nil),
      !(fields.contains(.location) && location != nil)
    else {
      throw invalidArguments("Do not assign and clear the same field or repeat clear fields.")
    }
    guard
      title != nil || notes != nil || due != nil || priority != nil || completed != nil
        || start != nil || url != nil || location != nil || recurrence != nil || alarms != nil
        || !fields.isEmpty
    else { throw invalidArguments("Provide at least one change.") }
    if let due { _ = try due.components() }
    if let start { _ = try start.components() }
    try validateURL(url)
    if (location?.utf8.count ?? 0) > 1024 { throw invalidArguments("Location is too long.") }
    try EventOptions.validate(alarms: alarms, recurrence: recurrence)
  }
}

extension ReminderChanges {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    title = try values.optional(String.self, forKey: .title)
    notes = try values.optional(String.self, forKey: .notes)
    due = try values.optional(AppleDate.self, forKey: .due)
    start = try values.optional(AppleDate.self, forKey: .start)
    url = try values.optional(String.self, forKey: .url)
    location = try values.optional(String.self, forKey: .location)
    recurrence = try values.optional([RepeatRule].self, forKey: .recurrence)
    alarms = try values.optional([TimeAlarm].self, forKey: .alarms)
    priority = try values.optional(Int.self, forKey: .priority)
    completed = try values.optional(Bool.self, forKey: .completed)
    clear = try values.optional([ReminderClearField].self, forKey: .clear)
  }
}

@MainActor
protocol ReminderAccess: Sendable {
  var available: Bool { get }
  func accounts() throws -> AppleAccounts
  func createList(accountID: String, title: String) throws -> AppleList
  func renameList(id: String, title: String) throws -> AppleList
  func deleteList(id: String) throws
  func lists() throws -> [ReminderList]
  func fetch(_ query: ResolvedReminderQuery) async throws -> ReminderPage
  func get(id: String) throws -> ReminderRecord
  func create(listID: String, changes: ReminderChanges) throws -> ReminderRecord
  func edit(id: String, changes: ReminderChanges) throws -> ReminderRecord
  func move(id: String, listID: String) throws -> ReminderRecord
  func delete(id: String) throws
}

@Schema
struct ReminderCreate: Codable, Sendable {
  var title: String
  var notes: String?
  var due: AppleDate?
  var start: AppleDate?
  var url: String?
  var location: String?
  var recurrence: [RepeatRule]?
  var alarms: [TimeAlarm]?
  var priority: Int?
  var completed: Bool?
  var clear: [ReminderClearField]?
  var patch: ReminderChanges {
    ReminderChanges(
      title: title, notes: notes, due: due, start: start, url: url, location: location,
      recurrence: recurrence, alarms: alarms, priority: priority, completed: completed, clear: clear
    )
  }
}
extension ReminderCreate {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    title = try values.decode(String.self, forKey: .title)
    notes = try values.optional(String.self, forKey: .notes)
    due = try values.optional(AppleDate.self, forKey: .due)
    start = try values.optional(AppleDate.self, forKey: .start)
    url = try values.optional(String.self, forKey: .url)
    location = try values.optional(String.self, forKey: .location)
    recurrence = try values.optional([RepeatRule].self, forKey: .recurrence)
    alarms = try values.optional([TimeAlarm].self, forKey: .alarms)
    priority = try values.optional(Int.self, forKey: .priority)
    completed = try values.optional(Bool.self, forKey: .completed)
    clear = try values.optional([ReminderClearField].self, forKey: .clear)
  }
}
