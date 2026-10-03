import Foundation
import SwiftMCP

/// The wire format and EventKit boundary share one date model. No Foundation
/// calendar/locale serialization leaks into tool results.
@Schema
struct ReminderDate: Codable, Sendable, Equatable {
  /// Gregorian date, exactly YYYY-MM-DD.
  let date: String
  /// Optional local clock time, exactly HH:MM:SS. Omit for a date-only deadline.
  let time: String?
  /// Optional timezone identifier, such as America/New_York or GMT. Requires time.
  /// Omit with time for a floating local deadline that follows the Mac's timezone.
  let timeZone: String?

  func components(floatingTimeZone: TimeZone = .current) throws -> DateComponents {
    guard date.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil,
      date.count == 10,
      time.map({
        $0.count == 8
          && $0.range(
            of: #"^[0-9]{2}:[0-9]{2}:[0-9]{2}$"#, options: .regularExpression) != nil
      }) ?? true,
      timeZone == nil || time != nil
    else { throw invalidArguments("Use date YYYY-MM-DD and optional time HH:MM:SS and timeZone.") }
    let zone: TimeZone
    if let timeZone {
      guard let value = TimeZone(identifier: timeZone) else {
        throw invalidArguments("Unknown timezone identifier.")
      }
      zone = value
    } else {
      zone = time == nil ? TimeZone(secondsFromGMT: 0)! : floatingTimeZone
    }
    let formatter = Self.formatter(timeZone: zone, timed: time != nil)
    let text = date + (time.map { "T" + $0 } ?? "")
    guard let instant = formatter.date(from: text), formatter.string(from: instant) == text else {
      throw invalidArguments("Invalid calendar date or nonexistent local time in this timezone.")
    }
    var components = formatter.calendar.dateComponents(
      time == nil ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute, .second],
      from: instant)
    components.calendar = formatter.calendar
    components.timeZone = timeZone == nil ? nil : zone
    return components
  }

  init?(components: DateComponents?) {
    guard let components, components.year != nil, components.month != nil, components.day != nil
    else { return nil }
    let timed = components.hour != nil
    let zone = components.timeZone ?? .current
    var normalized = components
    if var native = components.calendar, native.identifier != .gregorian {
      native.timeZone = zone
      guard let instant = native.date(from: components) else { return nil }
      var gregorian = Calendar(identifier: .gregorian)
      gregorian.timeZone = zone
      normalized = gregorian.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: instant)
    }
    guard let year = normalized.year, (1...9999).contains(year),
      let month = normalized.month, let day = normalized.day
    else { return nil }
    date = String(format: "%04d-%02d-%02d", year, month, day)
    time =
      timed
      ? String(
        format: "%02d:%02d:%02d",
        normalized.hour ?? 0, normalized.minute ?? 0, normalized.second ?? 0) : nil
    timeZone = timed ? components.timeZone?.identifier : nil
  }

  func instant(in zone: TimeZone) -> Date? {
    // Native snapshots are already calendar values. Calendar resolves floating
    // times across DST changes without creating a DateFormatter for every row.
    let day = date.split(separator: "-").compactMap { Int($0) }
    let clock = time?.split(separator: ":").compactMap { Int($0) }
    guard day.count == 3, clock == nil || clock?.count == 3 else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? zone
    return calendar.date(
      from: DateComponents(
        year: day[0], month: day[1], day: day[2],
        hour: clock?[0], minute: clock?[1], second: clock?[2]))
  }

  private static func formatter(timeZone: TimeZone, timed: Bool) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    formatter.calendar = calendar
    formatter.timeZone = timeZone
    formatter.isLenient = false
    formatter.dateFormat = timed ? "yyyy-MM-dd'T'HH:mm:ss" : "yyyy-MM-dd"
    return formatter
  }
}

extension ReminderDate {
  init(date: String, time: String? = nil, timeZone: String? = nil) {
    self.date = date
    self.time = time
    self.timeZone = timeZone
  }

  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    date = try values.decode(String.self, forKey: .date)
    time = try values.optional(String.self, forKey: .time)
    timeZone = try values.optional(String.self, forKey: .timeZone)
  }
}
