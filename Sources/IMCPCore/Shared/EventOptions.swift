import EventKit
import Foundation
import SwiftMCP

enum RepeatFrequency: String, Codable, CaseIterable, Sendable {
  case daily, weekly, monthly, yearly
}

@Schema
struct RepeatDay: Codable, Sendable {
  /// Sunday = 1 through Saturday = 7.
  let day: Int
  /// Ordinal within the month/year; omit for every matching weekday.
  var week: Int?
}

@Schema
struct RepeatRule: Codable, Sendable {
  let frequency: RepeatFrequency
  var interval: Int?
  var weekdays: [RepeatDay]?
  var monthDays: [Int]?
  var months: [Int]?
  var yearWeeks: [Int]?
  var yearDays: [Int]?
  var positions: [Int]?
  /// Inclusive ISO 8601 timestamp. Mutually exclusive with count.
  var until: String?
  var count: Int?

  func native() throws -> EKRecurrenceRule {
    guard (1...1000).contains(interval ?? 1), until == nil || count == nil,
      count.map({ (1...100000).contains($0) }) ?? true
    else { throw invalidArguments("Invalid recurrence interval or end.") }
    let values: [([Int]?, Int, Bool)] = [
      (monthDays, 31, true), (months, 12, false), (yearWeeks, 53, true),
      (yearDays, 366, true), (positions, 366, true),
    ]
    for (list, maximum, signed) in values {
      if let list {
        guard !list.isEmpty, list.count <= maximum * 2, Set(list).count == list.count,
          list.allSatisfy({ $0 != 0 && $0 <= maximum && $0 >= (signed ? -maximum : 1) })
        else { throw invalidArguments("Invalid recurrence selector.") }
      }
    }
    if let weekdays {
      guard !weekdays.isEmpty, weekdays.count <= 14, frequency != .daily,
        Set(weekdays.map { "\($0.day):\($0.week ?? 0)" }).count == weekdays.count,
        weekdays.allSatisfy({
          (1...7).contains($0.day) && (-53...53).contains($0.week ?? 0)
            && (frequency != .weekly || ($0.week ?? 0) == 0)
            && (frequency != .monthly || (-5...5).contains($0.week ?? 0))
        })
      else { throw invalidArguments("Invalid recurrence weekdays.") }
    }
    guard monthDays == nil || frequency == .monthly,
      (months == nil && yearWeeks == nil && yearDays == nil) || frequency == .yearly,
      positions == nil || weekdays != nil || monthDays != nil || months != nil || yearWeeks != nil
        || yearDays != nil
    else { throw invalidArguments("Recurrence selectors do not apply to this frequency.") }
    let end: EKRecurrenceEnd?
    if let until {
      end = EKRecurrenceEnd(end: try NativeDates.parse(until))
    } else if let count {
      end = EKRecurrenceEnd(occurrenceCount: count)
    } else {
      end = nil
    }
    let nativeFrequency: EKRecurrenceFrequency
    switch frequency {
    case .daily: nativeFrequency = .daily
    case .weekly: nativeFrequency = .weekly
    case .monthly: nativeFrequency = .monthly
    case .yearly: nativeFrequency = .yearly
    }
    return EKRecurrenceRule(
      recurrenceWith: nativeFrequency, interval: interval ?? 1,
      daysOfTheWeek: weekdays?.map {
        EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0.day)!, weekNumber: $0.week ?? 0)
      },
      daysOfTheMonth: monthDays?.map(NSNumber.init(value:)),
      monthsOfTheYear: months?.map(NSNumber.init(value:)),
      weeksOfTheYear: yearWeeks?.map(NSNumber.init(value:)),
      daysOfTheYear: yearDays?.map(NSNumber.init(value:)),
      setPositions: positions?.map(NSNumber.init(value:)), end: end)
  }

  init(_ rule: EKRecurrenceRule) {
    switch rule.frequency {
    case .daily: frequency = .daily
    case .weekly: frequency = .weekly
    case .monthly: frequency = .monthly
    case .yearly: frequency = .yearly
    @unknown default: frequency = .daily
    }
    interval = rule.interval == 1 ? nil : rule.interval
    weekdays = rule.daysOfTheWeek?.map {
      RepeatDay(day: $0.dayOfTheWeek.rawValue, week: $0.weekNumber == 0 ? nil : $0.weekNumber)
    }
    monthDays = rule.daysOfTheMonth?.map(\.intValue)
    months = rule.monthsOfTheYear?.map(\.intValue)
    yearWeeks = rule.weeksOfTheYear?.map(\.intValue)
    yearDays = rule.daysOfTheYear?.map(\.intValue)
    positions = rule.setPositions?.map(\.intValue)
    until = rule.recurrenceEnd?.endDate.map(NativeDates.string)
    count = rule.recurrenceEnd.flatMap { $0.occurrenceCount > 0 ? $0.occurrenceCount : nil }
  }
}

@Schema
struct TimeAlarm: Codable, Sendable {
  /// ISO 8601 timestamp; use either at or offsetSeconds.
  var at: String?
  /// Seconds relative to the item's start; negative means before.
  var offsetSeconds: Double?

  func native() throws -> EKAlarm {
    guard (at == nil) != (offsetSeconds == nil) else {
      throw invalidArguments("An alarm requires either at or offsetSeconds.")
    }
    if let at { return EKAlarm(absoluteDate: try NativeDates.parse(at)) }
    guard let offsetSeconds, offsetSeconds.isFinite, abs(offsetSeconds) <= 366 * 86400 else {
      throw invalidArguments("Alarm offset must be within one year of the start.")
    }
    return EKAlarm(relativeOffset: offsetSeconds)
  }
  static func supports(_ alarm: EKAlarm) -> Bool {
    alarm.structuredLocation == nil && alarm.type == .display
  }
  init?(_ alarm: EKAlarm) {
    guard Self.supports(alarm) else { return nil }
    at = alarm.absoluteDate.map(NativeDates.string)
    offsetSeconds = alarm.absoluteDate == nil ? alarm.relativeOffset : nil
  }
}

enum EventOptions {
  static func validate(alarms: [TimeAlarm]?, recurrence: [RepeatRule]?) throws {
    guard (alarms?.count ?? 0) <= 8, (recurrence?.count ?? 0) <= 1 else {
      throw invalidArguments("Use at most eight alarms and one recurrence rule.")
    }
    _ = try alarms?.map { try $0.native() }
    _ = try recurrence?.map { try $0.native() }
  }
  static func apply(alarms: [TimeAlarm]?, recurrence: [RepeatRule]?, to item: EKCalendarItem) throws
  {
    let nativeAlarms = try alarms?.map { try $0.native() }
    let rules = try recurrence?.map { try $0.native() }
    if let nativeAlarms {
      // Time edits must not erase geofence, audio, email, or procedure alarms.
      item.alarms = (item.alarms ?? []).filter { !TimeAlarm.supports($0) } + nativeAlarms
    }
    if let rules { item.recurrenceRules = rules }
  }
}

extension RepeatDay {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    day = try values.decode(Int.self, forKey: .day)
    week = try values.optional(Int.self, forKey: .week)
  }
}

extension RepeatRule {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    frequency = try values.decode(RepeatFrequency.self, forKey: .frequency)
    interval = try values.optional(Int.self, forKey: .interval)
    weekdays = try values.optional([RepeatDay].self, forKey: .weekdays)
    monthDays = try values.optional([Int].self, forKey: .monthDays)
    months = try values.optional([Int].self, forKey: .months)
    yearWeeks = try values.optional([Int].self, forKey: .yearWeeks)
    yearDays = try values.optional([Int].self, forKey: .yearDays)
    positions = try values.optional([Int].self, forKey: .positions)
    until = try values.optional(String.self, forKey: .until)
    count = try values.optional(Int.self, forKey: .count)
  }
}

extension TimeAlarm {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    at = try values.optional(String.self, forKey: .at)
    offsetSeconds = try values.optional(Double.self, forKey: .offsetSeconds)
  }
}
