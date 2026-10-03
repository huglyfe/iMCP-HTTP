import EventKit
import Foundation

@MainActor
public final class EventKitCalendar: AppleAccess, CalendarAccess {
  public private(set) var enabled: Bool
  private let eventStore: EventKitStore
  private var store: EKEventStore { eventStore.value }
  private var catalog: EventKitCatalog { EventKitCatalog(store: store, entity: .event) }
  public init(enabled: Bool = false, eventStore: EventKitStore = EventKitStore()) {
    self.enabled = enabled
    self.eventStore = eventStore
  }
  public var available: Bool {
    enabled && EKEventStore.authorizationStatus(for: .event) == .fullAccess
  }
  public func setEnabled(_ enabled: Bool) { self.enabled = enabled }
  public func requestAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }

  func accounts() throws -> AppleAccounts {
    try requireAccess()
    return catalog.accounts()
  }
  func lists() throws -> [AppleList] {
    try requireAccess()
    return catalog.lists()
  }
  func createList(accountID: String, title: String) throws -> AppleList {
    try requireAccess()
    return try catalog.create(accountID: accountID, title: title)
  }
  func renameList(id: String, title: String) throws -> AppleList {
    try requireAccess()
    return try catalog.rename(id: id, title: title)
  }
  func deleteList(id: String) throws {
    try requireAccess()
    try catalog.delete(id: id)
  }

  func fetch(
    calendarIDs: [String], start: Date, end: Date, search: String?, offset: Int, limit: Int
  ) throws -> EventPage {
    try requireAccess()
    let calendars = try calendarIDs.map { try catalog.get($0) }
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
    let records = store.events(matching: predicate).filter { event in
      guard let search else { return true }
      return [event.title ?? "", event.notes ?? "", event.location ?? ""].contains {
        $0.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }
    }.sorted {
      $0.startDate == $1.startDate
        ? ($0.eventIdentifier ?? "") < ($1.eventIdentifier ?? "") : $0.startDate < $1.startDate
    }
    return EventPage(
      events: records.dropFirst(offset).prefix(limit).map { EventSummary(Self.record($0)) },
      nextOffset: offset + limit < records.count ? offset + limit : nil)
  }
  private func event(id: String, start: Date, writing: Bool = false) throws -> EKEvent {
    try requireAccess()
    guard let initial = store.event(withIdentifier: id), let calendar = initial.calendar else {
      throw ToolFailure("not_found", "Event was not found. Fetch events again.")
    }
    let predicate = store.predicateForEvents(
      withStart: start, end: start.addingTimeInterval(1), calendars: [calendar])
    let matches = store.events(matching: predicate).filter {
      $0.eventIdentifier == id && $0.startDate == start
    }
    guard matches.count == 1, let event = matches.first, event.refresh(), event.startDate == start
    else {
      throw ToolFailure(
        "not_found", "This occurrence changed or was not found. Fetch events again.")
    }
    if writing, !event.calendar.allowsContentModifications {
      throw ToolFailure("read_only", "This calendar is read-only.")
    }
    return event
  }
  func get(id: String, start: Date) throws -> EventRecord {
    Self.record(try event(id: id, start: start))
  }
  func create(calendarID: String, changes: EventChanges) throws -> EventRecord {
    try requireAccess()
    try changes.validate(creating: true)
    let event = EKEvent(eventStore: store)
    event.calendar = try catalog.get(calendarID, writing: true)
    try apply(changes, to: event)
    return try save(event, span: .thisEvent)
  }
  func edit(id: String, start: Date, span: EventSpan, changes: EventChanges) throws -> EventRecord {
    try changes.validate()
    let event = try event(id: id, start: start, writing: true)
    if changes.recurrence != nil, event.hasRecurrenceRules, span == .thisEvent {
      throw invalidArguments("Changing a repeating schedule requires futureEvents scope.")
    }
    // Preserve all-day semantics when allDay is omitted during a time edit.
    if changes.start != nil, changes.allDay == nil, event.isAllDay {
      var checked = changes
      checked.allDay = true
      try checked.validate()
    }
    try apply(changes, to: event)
    return try save(event, span: span.native)
  }
  func move(id: String, start: Date, span: EventSpan, calendarID: String) throws -> EventRecord {
    let event = try event(id: id, start: start, writing: true)
    let destination = try catalog.get(calendarID, writing: true)
    if event.calendar.calendarIdentifier == calendarID { return Self.record(event) }
    event.calendar = destination
    return try save(event, span: span.native)
  }
  func delete(id: String, start: Date, span: EventSpan) throws {
    let event = try event(id: id, start: start, writing: true)
    do { try store.remove(event, span: span.native, commit: true) } catch {
      event.reset()
      throw ToolFailure("write_failed", "Deletion was not confirmed. Fetch events before retrying.")
    }
  }
  private func save(_ event: EKEvent, span: EKSpan) throws -> EventRecord {
    do { try store.save(event, span: span, commit: true) } catch {
      event.reset()
      throw ToolFailure("write_failed", "Save was not confirmed. Fetch events before retrying.")
    }
    return Self.record(event)
  }
  private func apply(_ changes: EventChanges, to event: EKEvent) throws {
    let start = try changes.start.map(NativeDates.parse)
    let end = try changes.end.map(NativeDates.parse)
    try EventOptions.apply(alarms: changes.alarms, recurrence: changes.recurrence, to: event)
    if let title = changes.title { event.title = title }
    if let timeZone = changes.timeZone { event.timeZone = TimeZone(identifier: timeZone) }
    if let allDay = changes.allDay { event.isAllDay = allDay }
    if let start, let end {
      event.startDate = start
      event.endDate = end
    }
    if let notes = changes.notes { event.notes = notes }
    if let location = changes.location { event.location = location }
    if let url = changes.url { event.url = URL(string: url) }
    if changes.clear?.contains(.notes) == true { event.notes = nil }
    if changes.clear?.contains(.location) == true { event.location = nil }
    if changes.clear?.contains(.url) == true { event.url = nil }
    if let availability = changes.availability {
      switch availability {
      case .busy: event.availability = .busy
      case .free: event.availability = .free
      case .tentative: event.availability = .tentative
      case .unavailable: event.availability = .unavailable
      }
    }
  }
  static func record(_ event: EKEvent) -> EventRecord {
    let availability: EventAvailability?
    switch event.availability {
    case .busy: availability = .busy
    case .free: availability = .free
    case .tentative: availability = .tentative
    case .unavailable: availability = .unavailable
    default: availability = nil
    }
    let alarms = (event.alarms ?? []).compactMap(TimeAlarm.init)
    let other = (event.alarms?.count ?? 0) - alarms.count
    return EventRecord(
      id: event.eventIdentifier, calendarID: event.calendar.calendarIdentifier,
      title: event.title ?? "", start: NativeDates.string(event.startDate),
      end: NativeDates.string(event.endDate),
      timeZone: event.timeZone?.identifier, allDay: event.isAllDay, notes: event.notes,
      location: event.location, url: event.url?.absoluteString, availability: availability,
      recurrence: event.recurrenceRules?.map(RepeatRule.init),
      alarms: alarms.isEmpty ? nil : alarms,
      otherAlarms: other == 0 ? nil : other)
  }
}
