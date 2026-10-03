import EventKit
import Foundation
import SwiftMCP

enum EventSpan: String, Codable, CaseIterable, Sendable {
  case thisEvent, futureEvents
  var native: EKSpan { self == .thisEvent ? .thisEvent : .futureEvents }
}
enum EventClearField: String, Codable, CaseIterable, Sendable { case notes, location, url }
enum EventAvailability: String, Codable, CaseIterable, Sendable {
  case busy, free, tentative, unavailable
}

@Schema
struct EventRecord: Codable, Sendable {
  let id: String
  let calendarID: String
  let title: String
  let start: String
  let end: String
  let timeZone: String?
  let allDay: Bool
  let notes: String?
  let location: String?
  let url: String?
  let availability: EventAvailability?
  let recurrence: [RepeatRule]?
  let alarms: [TimeAlarm]?
  let otherAlarms: Int?
}
@Schema
struct EventSummary: Codable, Sendable {
  let id: String
  let calendarID: String
  let title: String
  let start: String
  let end: String
  let timeZone: String?
  let allDay: Bool
  let location: String?
  init(_ record: EventRecord) {
    id = record.id
    calendarID = record.calendarID
    title = record.title
    start = record.start
    end = record.end
    timeZone = record.timeZone
    allDay = record.allDay
    location = record.location
  }
}

@Schema
struct EventPage: Codable, Sendable {
  let events: [EventSummary]
  let nextOffset: Int?
}

@Schema
struct EventChanges: Codable, Sendable {
  var title: String?
  /// ISO 8601 timestamp with offset. Supply start and end together.
  var start: String?
  /// Exclusive end. All-day boundaries must be midnight in timeZone.
  var end: String?
  /// IANA timezone, required on create and when changing times.
  var timeZone: String?
  var allDay: Bool?
  var notes: String?
  var location: String?
  var url: String?
  var availability: EventAvailability?
  /// Replace recurrence; [] removes it.
  var recurrence: [RepeatRule]?
  /// Replace display alarms; [] removes them. Other alarm types are preserved.
  var alarms: [TimeAlarm]?
  var clear: [EventClearField]?

  func validate(creating: Bool = false) throws {
    if let title { try validateTitle(title) }
    guard !creating || (title != nil && start != nil && end != nil && timeZone != nil) else {
      throw invalidArguments("Create requires title, start, end, and timeZone.")
    }
    let hasSchedule = start != nil || end != nil || timeZone != nil || allDay != nil
    if hasSchedule {
      guard let start, let end, let timeZone, let zone = TimeZone(identifier: timeZone),
        try NativeDates.parse(start) < NativeDates.parse(end)
      else { throw invalidArguments("Provide start, a later end, and a valid timeZone together.") }
      if allDay == true {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        for text in [start, end] {
          let date = try NativeDates.parse(text)
          guard calendar.startOfDay(for: date) == date else {
            throw invalidArguments("All-day events require midnight boundaries in timeZone.")
          }
        }
      }
    }
    guard (notes?.utf8.count ?? 0) <= 16384, (location?.utf8.count ?? 0) <= 1024 else {
      throw invalidArguments("Notes or location is too long.")
    }
    try validateURL(url)
    try EventOptions.validate(alarms: alarms, recurrence: recurrence)
    let fields = clear ?? []
    guard Set(fields).count == fields.count,
      !(fields.contains(.notes) && notes != nil), !(fields.contains(.location) && location != nil),
      !(fields.contains(.url) && url != nil)
    else { throw invalidArguments("Conflicting clear fields.") }
    guard
      title != nil || hasSchedule || notes != nil || location != nil || url != nil
        || availability != nil || recurrence != nil || alarms != nil || !fields.isEmpty
    else {
      throw invalidArguments("Provide at least one change.")
    }
  }
}

@MainActor
protocol CalendarAccess: Sendable {
  var available: Bool { get }
  func accounts() throws -> AppleAccounts
  func lists() throws -> [AppleList]
  func createList(accountID: String, title: String) throws -> AppleList
  func renameList(id: String, title: String) throws -> AppleList
  func deleteList(id: String) throws
  func fetch(
    calendarIDs: [String], start: Date, end: Date, search: String?, offset: Int, limit: Int
  ) throws -> EventPage
  func get(id: String, start: Date) throws -> EventRecord
  func create(calendarID: String, changes: EventChanges) throws -> EventRecord
  func edit(id: String, start: Date, span: EventSpan, changes: EventChanges) throws -> EventRecord
  func move(id: String, start: Date, span: EventSpan, calendarID: String) throws -> EventRecord
  func delete(id: String, start: Date, span: EventSpan) throws
}

extension EventChanges {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    title = try values.optional(String.self, forKey: .title)
    start = try values.optional(String.self, forKey: .start)
    end = try values.optional(String.self, forKey: .end)
    timeZone = try values.optional(String.self, forKey: .timeZone)
    allDay = try values.optional(Bool.self, forKey: .allDay)
    notes = try values.optional(String.self, forKey: .notes)
    location = try values.optional(String.self, forKey: .location)
    url = try values.optional(String.self, forKey: .url)
    availability = try values.optional(EventAvailability.self, forKey: .availability)
    recurrence = try values.optional([RepeatRule].self, forKey: .recurrence)
    alarms = try values.optional([TimeAlarm].self, forKey: .alarms)
    clear = try values.optional([EventClearField].self, forKey: .clear)
  }
}
