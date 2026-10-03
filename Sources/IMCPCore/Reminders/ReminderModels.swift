import Foundation
import SwiftMCP

struct ReminderList: Codable, Sendable {
  let id: String
  let title: String
  let account: String
  let accountID: String
  let writable: Bool
}

struct ReminderRecord: Codable, Sendable {
  let id: String
  let listID: String
  let title: String
  let notes: String?
  let priority: Int
  let completed: Bool
  /// Preserve native components, including floating dates and their optional time zone.
  let due: DateComponents?
}

struct ReminderPage: Codable, Sendable {
  let reminders: [ReminderRecord]
  let total: Int
  let nextOffset: Int?
}

enum FieldChange<Value: Sendable>: Sendable {
  case unchanged
  case set(Value)
  case clear
}

struct ReminderChanges: Sendable {
  var title: String?
  var notes: FieldChange<String> = .unchanged
  var due: FieldChange<DateComponents> = .unchanged
  var priority: Int?
  var completed: Bool?

  init(_ fields: JSONDictionary, creating: Bool = false) throws {
    guard !fields.isEmpty,
      Set(fields.keys).isSubset(of: ["title", "notes", "due", "priority", "completed"])
    else {
      throw ToolFailure(
        "invalid_arguments", "Provide only title, notes, due, priority, or completed changes.")
    }
    if let raw = fields["title"] {
      guard case .string(let value) = raw,
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        value.utf8.count <= 1024
      else {
        throw ToolFailure("invalid_arguments", "Title must be nonempty and at most 1024 bytes.")
      }
      title = value
    }
    if creating, title == nil {
      throw ToolFailure("invalid_arguments", "A title is required when creating a reminder.")
    }
    if let raw = fields["notes"] {
      switch raw {
      case .null: notes = .clear
      case .string(let value) where value.utf8.count <= 16384: notes = .set(value)
      default:
        throw ToolFailure(
          "invalid_arguments", "Notes must be text up to 16384 bytes, or null to clear.")
      }
    }
    if let raw = fields["due"] {
      switch raw {
      case .null: due = .clear
      case .string(let value): due = .set(try Self.dateComponents(value))
      default:
        throw ToolFailure("invalid_arguments", "Due must be a date string, or null to clear.")
      }
    }
    if let raw = fields["priority"] {
      guard case .integer(let value) = raw, (0...9).contains(value) else {
        throw ToolFailure(
          "invalid_arguments", "Priority must be an integer from 0 (none) to 9; 1 is highest.")
      }
      priority = value
    }
    if let raw = fields["completed"] {
      guard case .bool(let value) = raw else {
        throw ToolFailure("invalid_arguments", "Completed must be true or false.")
      }
      completed = value
    }
  }

  static func dateComponents(_ value: String) throws -> DateComponents {
    let invalid = ToolFailure(
      "invalid_arguments",
      "Use YYYY-MM-DD or YYYY-MM-DDTHH:MM:SSZ / ±HH:MM. Timed due dates are stored in UTC.")
    guard
      value.range(
        of: #"^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2}))?$"#,
        options: .regularExpression) != nil
    else { throw invalid }
    let dateOnly = value.count == 10
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.isLenient = false
    formatter.dateFormat = dateOnly ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    guard let date = formatter.date(from: value) else { throw invalid }
    // DateFormatter may normalize invalid calendar dates; verify the local date/time
    // with the explicitly supplied offset before accepting it.
    if !dateOnly, !value.hasSuffix("Z") {
      let suffix = String(value.suffix(6))
      let hour = Int(suffix.dropFirst().prefix(2))!
      let minute = Int(suffix.suffix(2))!
      guard hour <= 23, minute <= 59 else { throw invalid }
      formatter.timeZone = TimeZone(
        secondsFromGMT: (hour * 3600 + minute * 60) * (suffix.first == "-" ? -1 : 1))
    }
    guard
      formatter.string(from: date) == value
        || (!dateOnly && value.hasSuffix("+00:00")
          && formatter.string(from: date) == value.dropLast(6) + "Z")
    else { throw invalid }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var components = calendar.dateComponents(
      dateOnly ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute, .second], from: date)
    components.calendar = calendar
    components.timeZone = dateOnly ? nil : calendar.timeZone
    return components
  }
}

@MainActor
protocol ReminderAccess: Sendable {
  var available: Bool { get }
  func lists() throws -> [ReminderList]
  func fetch(listID: String, completed: Bool?, offset: Int, limit: Int) async throws -> ReminderPage
  func get(id: String) throws -> ReminderRecord
  func create(listID: String, changes: ReminderChanges) throws -> ReminderRecord
  func edit(id: String, changes: ReminderChanges) throws -> ReminderRecord
  func delete(id: String) throws
}
