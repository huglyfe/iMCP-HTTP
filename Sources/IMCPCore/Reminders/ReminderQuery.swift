import Foundation
import SwiftMCP

enum ReminderDueFilter: String, Codable, CaseIterable, Sendable {
  case any, today, overdue, upcoming, undated
}

enum ReminderSort: String, Codable, CaseIterable, Sendable {
  case id, due
}

@Schema
struct ReminderQuery: Codable, Sendable {
  /// One to fifty exact list identifiers from reminders_lists. No default list fallback.
  let listIDs: [String]
  /// Case- and diacritic-insensitive substring in title or notes; at most 512 UTF-8 bytes.
  var search: String?
  /// Omit for both states, except date presets default to incomplete reminders.
  var completed: Bool?
  /// any (default), today, overdue, upcoming (tomorrow onward), or undated.
  var due: ReminderDueFilter?
  /// Timezone for date presets and sorting; defaults to the Mac's current timezone.
  var timeZone: String?
  /// id (default) or due (earliest first, undated last, stable ID tie breaker).
  var sort: ReminderSort?
  /// Zero-based offset, 0 through 100000. Pages are not a snapshot.
  var offset: Int?
  /// Page size, 1 through 200; default 100.
  var limit: Int?

  func resolve(now: Date = Date(), defaultTimeZone: TimeZone = .current) throws
    -> ResolvedReminderQuery
  {
    guard (1...50).contains(listIDs.count), Set(listIDs).count == listIDs.count else {
      throw invalidArguments("Provide one to fifty distinct list identifiers.")
    }
    for id in listIDs { try validateIdentifier(id) }
    let search = search?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let search, search.isEmpty || search.utf8.count > 512 {
      throw invalidArguments("Search must be nonempty and at most 512 UTF-8 bytes.")
    }
    guard (0...100000).contains(offset ?? 0), (1...200).contains(limit ?? 100) else {
      throw invalidArguments("Offset must be 0–100000 and limit must be 1–200.")
    }
    let zone: TimeZone
    if let timeZone {
      guard let value = TimeZone(identifier: timeZone) else {
        throw invalidArguments("Unknown query timezone identifier.")
      }
      zone = value
    } else {
      zone = defaultTimeZone
    }
    return ResolvedReminderQuery(
      listIDs: listIDs, search: search,
      completed: completed ?? (due == nil || due == .any ? nil : false),
      due: due ?? .any, timeZone: zone, sort: sort ?? .id, offset: offset ?? 0,
      limit: limit ?? 100, now: now)
  }
}

extension ReminderQuery {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    listIDs = try values.decode([String].self, forKey: .listIDs)
    search = try values.optional(String.self, forKey: .search)
    completed = try values.optional(Bool.self, forKey: .completed)
    due = try values.optional(ReminderDueFilter.self, forKey: .due)
    timeZone = try values.optional(String.self, forKey: .timeZone)
    sort = try values.optional(ReminderSort.self, forKey: .sort)
    offset = try values.optional(Int.self, forKey: .offset)
    limit = try values.optional(Int.self, forKey: .limit)
  }
}

/// Resolve the clock and timezone once, so a single fetch cannot cross a day boundary.
struct ResolvedReminderQuery: Sendable {
  let listIDs: [String]
  let search: String?
  let completed: Bool?
  let due: ReminderDueFilter
  let timeZone: TimeZone
  let sort: ReminderSort
  let offset: Int
  let limit: Int
  let now: Date

  func page(_ records: [ReminderRecord]) -> ReminderPage {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let today = calendar.startOfDay(for: now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
    // Calculate each due instant once, rather than parsing during every sort comparison.
    let matching = records.compactMap { record -> (ReminderRecord, Date?)? in
      guard listIDs.contains(record.listID), completed == nil || completed == record.completed
      else {
        return nil
      }
      if let search,
        ![record.title, record.notes ?? ""].contains(where: {
          $0.range(
            of: search, options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")) != nil
        })
      {
        return nil
      }
      let instant = record.due?.instant(in: timeZone)
      switch due {
      case .any: break
      case .undated: if record.due != nil { return nil }
      case .today:
        guard let instant, instant >= today, instant < tomorrow else { return nil }
      case .upcoming:
        guard let instant, instant >= tomorrow else { return nil }
      case .overdue:
        guard let instant, instant < (record.due?.time == nil ? today : now) else { return nil }
      }
      return (record, instant)
    }.sorted { lhs, rhs in
      if sort == .due, lhs.1 != rhs.1 {
        guard let left = lhs.1 else { return false }
        guard let right = rhs.1 else { return true }
        return left < right
      }
      return lhs.0.id < rhs.0.id
    }
    let page = matching.dropFirst(offset).prefix(limit).map(\.0)
    return ReminderPage(
      reminders: page, total: matching.count,
      nextOffset: offset + page.count < matching.count ? offset + page.count : nil,
      timeZone: timeZone.identifier)
  }
}
