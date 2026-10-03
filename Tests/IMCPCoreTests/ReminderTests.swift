import Foundation
import SwiftMCP
import Testing

@testable import IMCPCore

struct ReminderTests {
  @Test func datesAndPatchSemantics() throws {
    let unchanged = try ReminderChanges(["title": "Updated"])
    if case .unchanged = unchanged.notes {
    } else {
      Issue.record("Omitted notes must remain unchanged")
    }
    if case .unchanged = unchanged.due {} else { Issue.record("Omitted due must remain unchanged") }
    let clearing = try ReminderChanges([
      "notes": .null, "due": .null, "completed": false, "priority": 0,
    ])
    if case .clear = clearing.notes {} else { Issue.record("Null must clear notes") }
    if case .clear = clearing.due {} else { Issue.record("Null must clear due") }
    check(clearing.completed == false)
    let day = try ReminderChanges.dateComponents("2028-02-29")
    check(day.day == 29 && day.month == 2 && day.hour == nil && day.timeZone == nil)
    let instant = try ReminderChanges.dateComponents("2026-10-03T20:45:00-04:00")
    check(instant.day == 4 && instant.hour == 0 && instant.minute == 45)
    check(instant.timeZone?.secondsFromGMT() == 0)
    _ = try ReminderChanges.dateComponents("2026-10-03T20:45:00+00:00")
    _ = try ReminderChanges.dateComponents("2026-10-03T20:45:00Z")
  }

  @Test func rejectsInvalidChangesBeforeDispatch() async throws {
    for value in [
      "", "tomorrow", "2026-02-29", "2026-04-31", "2026-00-01", "2026-10-03T25:00:00Z",
      "2026-10-03T20:45:00", "2026-10-03T20:45:00+24:00", "2026-10-03T20:45:00-00:00",
      "2026-10-03junk",
    ] {
      await expectFailure { try ReminderChanges.dateComponents(value) }
    }
    for fields: JSONDictionary in [
      [:], ["title": "  "], ["title": .null], ["priority": 10], ["priority": true],
      ["completed": "yes"], ["listID": "move"], ["due": 123], ["notes": .array([])],
    ] {
      await expectFailure { try ReminderChanges(fields) }
    }
    await expectFailure { try ReminderChanges(["notes": "No title"], creating: true) }
    let service = FakeReminders()
    let dispatcher = ToolDispatcher(testReminders: service)
    await expectFailure {
      try await dispatcher.call(
        "reminders_edit",
        arguments: ["id": "target", "changes": ["title": "New", "due": "invalid"]])
    }
    await expectFailure {
      try await dispatcher.call("reminders_create", arguments: ["changes": ["title": "New"]])
    }
    await expectFailure {
      try await dispatcher.call("reminders_fetch", arguments: ["listID": "list", "limit": 201])
    }
    await expectFailure {
      try await dispatcher.call("reminders_delete", arguments: ["id": "target", "force": true])
    }
    check(await service.writes.isEmpty)
  }

  @Test func serviceGatesAndExactTargets() async throws {
    let service = FakeReminders()
    let dispatcher = ToolDispatcher(testReminders: service)
    check(await dispatcher.tools().count == 7)
    _ = try await dispatcher.call(
      "reminders_edit", arguments: ["id": "exact-item", "changes": ["completed": true]])
    check(await service.writes == ["edit:exact-item"])
    let changes = try require(await service.lastChanges)
    check(changes.completed == true && changes.title == nil)
    if case .unchanged = changes.due {
    } else {
      Issue.record("Completion must not change the due date")
    }
    await service.setAvailable(false)
    check(await dispatcher.tools().map(\.name) == ["connection_check"])
    await expectFailure {
      try await dispatcher.call("reminders_get", arguments: ["id": "exact-item"])
    }
    await expectFailure {
      try await dispatcher.call("reminders_delete", arguments: ["id": "exact-item"])
    }
    check(await service.writes == ["edit:exact-item"])
    await service.setAvailable(true)
    await service.setFailure(ToolFailure("read_only", "Fixture read-only account"))
    do {
      _ = try await dispatcher.call("reminders_delete", arguments: ["id": "completed-item"])
      Issue.record("A failed deletion must not return success")
    } catch let error as ToolFailure { check(error.code == "read_only") }
    check(await service.writes.last == "delete:completed-item")
  }

  @Test func disabledEventKitNeverReadsData() async {
    let service = await EventKitReminders()
    check(await !service.available)
    await expectFailure { try await service.lists() }
    await expectFailure { try await service.get(id: "disposable-nonexistent") }
    await expectFailure { try await service.delete(id: "disposable-nonexistent") }
  }
}

@MainActor
private final class FakeReminders: ReminderAccess {
  var available = true
  var writes: [String] = []
  var lastChanges: ReminderChanges?
  var failure: ToolFailure?
  func setAvailable(_ value: Bool) { available = value }
  func setFailure(_ value: ToolFailure) { failure = value }
  func lists() throws -> [ReminderList] { [] }
  func fetch(listID: String, completed: Bool?, offset: Int, limit: Int) async throws -> ReminderPage
  {
    ReminderPage(reminders: [], total: 0, nextOffset: nil)
  }
  func get(id: String) throws -> ReminderRecord {
    if let failure { throw failure }
    return ReminderRecord(
      id: id, listID: "fixture-list", title: "Fixture", notes: nil, priority: 0, completed: false,
      due: nil)
  }
  func create(listID: String, changes: ReminderChanges) throws -> ReminderRecord {
    writes.append("create:" + listID)
    lastChanges = changes
    return try get(id: "created")
  }
  func edit(id: String, changes: ReminderChanges) throws -> ReminderRecord {
    writes.append("edit:" + id)
    lastChanges = changes
    return try get(id: id)
  }
  func delete(id: String) throws {
    writes.append("delete:" + id)
    if let failure { throw failure }
  }
}
