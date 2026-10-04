import EventKit
import Foundation

/// The main actor owns EventKit objects and serializes mutations. Fetch callbacks
/// snapshot their result before crossing back to the main actor; no EK object escapes.
@MainActor
public final class EventKitReminders: AppleAccess, ReminderAccess {
  public private(set) var enabled: Bool
  private let eventStore: EventKitStore
  private var store: EKEventStore { eventStore.value }
  private var catalog: EventKitCatalog { EventKitCatalog(store: store, entity: .reminder) }
  private var activeFetches = 0

  public init(enabled: Bool = false, eventStore: EventKitStore = EventKitStore()) {
    self.enabled = enabled
    self.eventStore = eventStore
  }
  public var available: Bool {
    enabled && EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
  }
  public func setEnabled(_ value: Bool) { enabled = value }
  public func requestAccess() async throws -> Bool {
    try await store.requestFullAccessToReminders()
  }

  private func calendar(_ id: String, writing: Bool = false) throws -> EKCalendar {
    try requireAccess()
    return try catalog.get(id, writing: writing)
  }
  private func reminder(_ id: String, writing: Bool = false) throws -> EKReminder {
    try requireAccess()
    guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, reminder.refresh()
    else {
      throw ToolFailure(
        "not_found", "Reminder was not found. Fetch the list again to obtain current identifiers.")
    }
    if writing, !reminder.calendar.allowsContentModifications {
      throw ToolFailure("read_only", "This reminder list is read-only.")
    }
    return reminder
  }
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
  func get(id: String) throws -> ReminderRecord {
    guard let record = Self.record(try reminder(id)) else {
      throw ToolFailure("read_failed", "Reminder has no list.")
    }
    return record
  }

  func fetch(_ query: ResolvedReminderQuery) async throws -> ReminderPage {
    let calendars = try query.listIDs.map { try calendar($0) }
    let predicate: NSPredicate
    switch query.completed {
    case false:
      predicate = store.predicateForIncompleteReminders(
        withDueDateStarting: nil, ending: nil, calendars: calendars)
    case true:
      predicate = store.predicateForCompletedReminders(
        withCompletionDateStarting: nil, ending: nil, calendars: calendars)
    case nil:
      predicate = store.predicateForReminders(in: calendars)
    }
    guard activeFetches < 4 else {
      throw ToolFailure("busy", "Too many Reminders reads are in progress. Try again shortly.")
    }
    activeFetches += 1
    defer { activeFetches -= 1 }
    let fetch = ReminderFetch(store: store)
    let records = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        fetch.continuation = continuation
        fetch.request = store.fetchReminders(matching: predicate) { reminders in
          let records = reminders?.compactMap {
            Self.record($0, summary: true, includeNotes: query.search != nil)
          }
          Task { @MainActor in fetch.finish(records) }
        }
        fetch.timeout = Task { @MainActor in
          do { try await Task.sleep(for: .seconds(15)) } catch { return }
          fetch.cancel(
            ToolFailure("timeout", "Reminders did not respond in time. No data was changed."))
        }
        if Task.isCancelled { fetch.cancel(CancellationError()) }
      }
    } onCancel: {
      Task { @MainActor in fetch.cancel(CancellationError()) }
    }
    try requireAccess()
    // EventKit has no text search or offset predicate. Native completion filtering
    // narrows the fetch; date-only/floating semantics are evaluated consistently in
    // the query timezone before pagination. Nothing is retained between calls.
    return query.page(records)
  }

  func create(listID: String, changes: ReminderChanges) throws -> ReminderRecord {
    let calendar = try calendar(listID, writing: true)
    let reminder = EKReminder(eventStore: store)
    reminder.calendar = calendar
    try apply(changes, to: reminder)
    return try save(reminder)
  }
  func edit(id: String, changes: ReminderChanges) throws -> ReminderRecord {
    let reminder = try reminder(id, writing: true)
    try apply(changes, to: reminder)
    return try save(reminder)
  }
  func move(id: String, listID: String) throws -> ReminderRecord {
    let destination = try calendar(listID, writing: true)
    let reminder = try reminder(id, writing: true)
    if reminder.calendar.calendarIdentifier == destination.calendarIdentifier {
      return try get(id: id)
    }
    reminder.calendar = destination
    return try save(reminder)
  }
  func delete(id: String) throws {
    let reminder = try reminder(id, writing: true)
    do { try store.remove(reminder, commit: true) } catch {
      reminder.reset()
      throw ToolFailure(
        "write_failed",
        "EventKit did not confirm deletion. Read the reminder again before retrying.")
    }
  }
  private func save(_ reminder: EKReminder) throws -> ReminderRecord {
    do { try store.save(reminder, commit: true) } catch {
      reminder.reset()
      throw ToolFailure(
        "write_failed", "EventKit did not confirm the save. Read the list again before retrying.")
    }
    guard let record = Self.record(reminder) else {
      throw ToolFailure("read_failed", "Saved reminder has no list. Fetch lists again.")
    }
    return record
  }
  private func apply(_ changes: ReminderChanges, to reminder: EKReminder) throws {
    // Resolve the entire update before mutating the EventKit object.
    let due = try changes.due?.components()
    let start = try changes.start?.components()
    let effectiveStart =
      changes.clear?.contains(.start) == true ? nil : start ?? reminder.startDateComponents
    let options = try EventOptions(alarms: changes.alarms, recurrence: changes.recurrence)
    let nativeAlarms = options.alarms ?? reminder.alarms ?? []
    if changes.alarms != nil || changes.start != nil || changes.clear?.contains(.start) == true,
      effectiveStart == nil,
      nativeAlarms.contains(where: { TimeAlarm.supports($0) && $0.absoluteDate == nil })
    {
      throw invalidArguments("Relative alarms require a start date.")
    }
    options.apply(to: reminder)
    if let start { reminder.startDateComponents = start }
    if let url = changes.url { reminder.url = URL(string: url) }
    if let location = changes.location { reminder.location = location }
    if changes.clear?.contains(.start) == true { reminder.startDateComponents = nil }
    if changes.clear?.contains(.url) == true { reminder.url = nil }
    if changes.clear?.contains(.location) == true { reminder.location = nil }
    if let title = changes.title { reminder.title = title }
    if let notes = changes.notes { reminder.notes = notes }
    if changes.clear?.contains(.notes) == true { reminder.notes = nil }
    if let due { reminder.dueDateComponents = due }
    if changes.clear?.contains(.due) == true { reminder.dueDateComponents = nil }
    if let priority = changes.priority { reminder.priority = priority }
    if let completed = changes.completed { reminder.isCompleted = completed }
  }
  nonisolated static func record(
    _ reminder: EKReminder, summary: Bool = false, includeNotes: Bool = true
  ) -> ReminderRecord? {
    guard let calendar = reminder.calendar else { return nil }
    if summary {
      return ReminderRecord(
        id: reminder.calendarItemIdentifier,
        listID: calendar.calendarIdentifier, title: reminder.title ?? "",
        notes: includeNotes ? reminder.notes : nil, priority: reminder.priority,
        completed: reminder.isCompleted, due: AppleDate(components: reminder.dueDateComponents))
    }
    let alarms = (reminder.alarms ?? []).compactMap(TimeAlarm.init)
    let other = (reminder.alarms?.count ?? 0) - alarms.count
    return ReminderRecord(
      id: reminder.calendarItemIdentifier, listID: calendar.calendarIdentifier,
      title: reminder.title ?? "", notes: reminder.notes, priority: reminder.priority,
      completed: reminder.isCompleted, due: AppleDate(components: reminder.dueDateComponents),
      start: AppleDate(components: reminder.startDateComponents), url: reminder.url?.absoluteString,
      location: reminder.location, recurrence: reminder.recurrenceRules?.map(RepeatRule.init),
      alarms: alarms.isEmpty ? nil : alarms, otherAlarms: other == 0 ? nil : other)
  }
}

@MainActor
private final class ReminderFetch {
  let store: EKEventStore
  var continuation: CheckedContinuation<[ReminderRecord], Error>?
  var request: Any?
  var timeout: Task<Void, Never>?
  init(store: EKEventStore) { self.store = store }
  func finish(_ records: [ReminderRecord]?) {
    guard let continuation else { return }
    self.continuation = nil
    timeout?.cancel()
    timeout = nil
    request = nil
    if let records {
      continuation.resume(returning: records)
    } else {
      continuation.resume(
        throwing: ToolFailure(
          "read_failed", "Reminders could not be read. Check permission and try again."))
    }
  }
  func cancel(_ error: Error) {
    guard let continuation else { return }
    self.continuation = nil
    if let request { store.cancelFetchRequest(request) }
    request = nil
    timeout?.cancel()
    timeout = nil
    continuation.resume(throwing: error)
  }
}
