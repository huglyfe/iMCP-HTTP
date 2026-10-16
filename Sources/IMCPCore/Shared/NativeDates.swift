import Foundation

enum NativeDates {
  static func parse(_ text: String) throws -> Date {
    guard text.utf8.count == 20 || text.utf8.count == 25,
      text.range(
        of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$"#,
        options: .regularExpression) != nil,
      let date = ISO8601DateFormatter().date(from: text)
    else { throw invalidArguments("Use an ISO 8601 timestamp with seconds and a UTC offset.") }
    // ISO8601DateFormatter can normalize invalid dates. Validate the local fields too.
    let offset = String(text.suffix(text.hasSuffix("Z") ? 1 : 6))
    let zone: TimeZone
    if offset == "Z" {
      zone = TimeZone(secondsFromGMT: 0)!
    } else {
      guard let hours = Int(offset.dropFirst().prefix(2)), let minutes = Int(offset.suffix(2)),
        hours <= 23, minutes < 60,
        let parsed = TimeZone(
          secondsFromGMT: (hours * 3600 + minutes * 60) * (offset.first == "-" ? -1 : 1))
      else { throw invalidArguments("Invalid UTC offset.") }
      zone = parsed
    }
    _ = try AppleDate(date: String(text.prefix(10)), time: String(text.dropFirst(11).prefix(8)))
      .components(floatingTimeZone: zone)
    return date
  }
  static func string(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
