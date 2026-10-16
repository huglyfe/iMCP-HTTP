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
  var startDate: String?
  var endDate: String?
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
  let startDate: String?
  let endDate: String?
  let allDay: Bool
  let location: String?
  init(_ record: EventRecord) {
    id = record.id
    calendarID = record.calendarID
    title = record.title
    start = record.start
    end = record.end
    timeZone = record.timeZone
    startDate = record.startDate
    endDate = record.endDate
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
  /// Timestamp with offset for timed events; YYYY-MM-DD for allDay. Supply start/end together.
  var start: String?
  /// Exclusive end timestamp, or YYYY-MM-DD for allDay.
  var end: String?
  /// IANA timezone required for timed schedules. All-day dates float in the Mac timezone.
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

  func schedule(floatingTimeZone: TimeZone = .current) throws -> (
    start: Date, end: Date, zone: TimeZone, allDay: Bool
  ) {
    guard let start, let end else {
      throw invalidArguments("Provide start and end together when changing the schedule.")
    }
    let allDay = allDay ?? false
    if let timeZone, TimeZone(identifier: timeZone) == nil {
      throw invalidArguments("Unknown timezone identifier.")
    }
    let zone: TimeZone
    if allDay {
      zone = floatingTimeZone
    } else {
      guard let name = timeZone, let value = TimeZone(identifier: name) else {
        throw invalidArguments("Timed events require a valid timeZone.")
      }
      zone = value
    }
    func boundary(_ text: String) throws -> Date {
      if allDay, text.count == 10 {
        let day = AppleDate(date: text)
        _ = try day.components(floatingTimeZone: zone)
        guard let date = day.instant(in: zone) else {
          throw invalidArguments("Invalid all-day date.")
        }
        return date
      }
      let date = try NativeDates.parse(text)
      if allDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? zone
        guard calendar.startOfDay(for: date) == date else {
          throw invalidArguments("All-day boundaries must be dates or local midnight timestamps.")
        }
        // All-day events float in the Mac timezone. Preserve the input's civil
        // date rather than letting EventKit round a foreign-zone instant.
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        calendar.timeZone = zone
        guard let localDate = calendar.date(from: day),
          calendar.dateComponents([.year, .month, .day], from: localDate) == day
        else { throw invalidArguments("Invalid all-day date in the Mac timezone.") }
        return localDate
      }
      return date
    }
    let from = try boundary(start)
    let to = try boundary(end)
    guard to > from else { throw invalidArguments("End must be after start.") }
    return (from, to, zone, allDay)
  }

  func validate(creating: Bool = false) throws {
    if let title { try validateTitle(title) }
    guard !creating || (title != nil && start != nil && end != nil) else {
      throw invalidArguments(
        "Create requires title, start, and end; timed events also require timeZone.")
    }
    let hasSchedule = start != nil || end != nil || timeZone != nil || allDay != nil
    if hasSchedule { _ = try schedule() }
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

@Schema
struct EventCreate: Codable, Sendable {
  var title: String
  /// Timestamp with offset for timed events; YYYY-MM-DD when allDay is true.
  var start: String
  /// Exclusive end timestamp or all-day date.
  var end: String
  /// Required for timed events; date-only all-day values float in the Mac timezone.
  var timeZone: String?
  var allDay: Bool?
  var notes: String?
  var location: String?
  var url: String?
  var availability: EventAvailability?
  var recurrence: [RepeatRule]?
  var alarms: [TimeAlarm]?
  var clear: [EventClearField]?
  var patch: EventChanges {
    EventChanges(
      title: title, start: start, end: end, timeZone: timeZone, allDay: allDay, notes: notes,
      location: location, url: url, availability: availability, recurrence: recurrence,
      alarms: alarms, clear: clear)
  }
}
extension EventCreate {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    title = try values.decode(String.self, forKey: .title)
    start = try values.decode(String.self, forKey: .start)
    end = try values.decode(String.self, forKey: .end)
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
