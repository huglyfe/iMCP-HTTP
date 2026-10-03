import EventKit
import Foundation

/// The main actor owns EventKit objects and serializes mutations. Fetch callbacks
/// snapshot their result before crossing back to the main actor; no EK object escapes.
@MainActor
public final class EventKitReminders: ReminderAccess {
  public private(set) var enabled: Bool
  private lazy var store = EKEventStore()
  private var activeFetches = 0

  public init(enabled: Bool = false) { self.enabled = enabled }
  public var available: Bool {
    enabled && EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
  }
  public var status: String {
    if !enabled { return "Disabled" }
    return available
      ? "Enabled for all approved clients" : "Reminders access is unavailable in System Settings"
  }
  public func setEnabled(_ value: Bool) { enabled = value }
  public func requestAccess() async throws -> Bool {
    try await store.requestFullAccessToReminders()
  }

  private func requireAccess() throws {
    guard enabled else {
      throw ToolFailure("service_disabled", "Enable Reminders in the iMCP-HTTP app.")
    }
    guard available else {
      throw ToolFailure("permission_denied", "Allow Reminders access in System Settings.")
    }
    try Task.checkCancellation()
  }
  private func calendar(_ id: String, writing: Bool = false) throws -> EKCalendar {
    try requireAccess()
    guard let calendar = store.calendar(withIdentifier: id),
      calendar.allowedEntityTypes.contains(.reminder)
    else {
      throw ToolFailure("not_found", "Reminder list was not found. List available lists again.")
    }
    if writing, !calendar.allowsContentModifications {
      throw ToolFailure("read_only", "This reminder list is read-only.")
    }
    return calendar
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
  func lists() throws -> [ReminderList] {
    try requireAccess()
    return store.calendars(for: .reminder).map {
      ReminderList(
        id: $0.calendarIdentifier, title: $0.title, account: $0.source.title,
        accountID: $0.source.sourceIdentifier, writable: $0.allowsContentModifications)
    }.sorted { $0.id < $1.id }
  }
  func get(id: String) throws -> ReminderRecord { Self.record(try reminder(id)) }

  func fetch(listID: String, completed: Bool?, offset: Int, limit: Int) async throws -> ReminderPage
  {
    let calendar = try calendar(listID)
    guard activeFetches < 4 else {
      throw ToolFailure("busy", "Too many Reminders reads are in progress. Try again shortly.")
    }
    activeFetches += 1
    defer { activeFetches -= 1 }
    let fetch = ReminderFetch(store: store)
    let records = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        fetch.continuation = continuation
        fetch.request = store.fetchReminders(matching: store.predicateForReminders(in: [calendar]))
        { reminders in
          let records = reminders?.map(Self.record)
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
    let matching = records.filter { completed == nil || $0.completed == completed }.sorted {
      $0.id < $1.id
    }
    let page = Array(matching.dropFirst(offset).prefix(limit))
    return ReminderPage(
      reminders: page, total: matching.count,
      nextOffset: offset + page.count < matching.count ? offset + page.count : nil)
  }

  func create(listID: String, changes: ReminderChanges) throws -> ReminderRecord {
    let calendar = try calendar(listID, writing: true)
    let reminder = EKReminder(eventStore: store)
    reminder.calendar = calendar
    apply(changes, to: reminder)
    return try save(reminder)
  }
  func edit(id: String, changes: ReminderChanges) throws -> ReminderRecord {
    let reminder = try reminder(id, writing: true)
    apply(changes, to: reminder)
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
    return Self.record(reminder)
  }
  private func apply(_ changes: ReminderChanges, to reminder: EKReminder) {
    if let title = changes.title { reminder.title = title }
    switch changes.notes {
    case .unchanged: break
    case .clear: reminder.notes = nil
    case .set(let value): reminder.notes = value
    }
    switch changes.due {
    case .unchanged: break
    case .clear: reminder.dueDateComponents = nil
    case .set(let value): reminder.dueDateComponents = value
    }
    if let priority = changes.priority { reminder.priority = priority }
    if let completed = changes.completed { reminder.isCompleted = completed }
  }
  nonisolated private static func record(_ reminder: EKReminder) -> ReminderRecord {
    ReminderRecord(
      id: reminder.calendarItemIdentifier, listID: reminder.calendar.calendarIdentifier,
      title: reminder.title ?? "", notes: reminder.notes, priority: reminder.priority,
      completed: reminder.isCompleted, due: reminder.dueDateComponents)
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
