import Foundation
import SwiftMCP
import Testing

@testable import IMCPCore

struct ReminderTests {
  @Test func datesRoundTripWithoutFoundationDetails() throws {
    for date in [
      AppleDate(date: "2028-02-29"),
      AppleDate(date: "2026-10-03", time: "20:45:00", timeZone: "America/New_York"),
      AppleDate(date: "2026-10-03", time: "20:45:00"),
    ] {
      let components = try date.components()
      #expect(AppleDate(components: components) == date)
      let data = try JSONEncoder().encode(date)
      #expect(try JSONDecoder().decode(AppleDate.self, from: data) == date)
      let json = try JSONDictionary(encoding: date)
      #expect(Set(json.keys).isSubset(of: ["date", "time", "timeZone"]))
    }
    let day = try AppleDate(date: "2028-02-29").components()
    #expect(day.hour == nil && day.timeZone == nil)
    let zoned = try AppleDate(
      date: "2026-10-03", time: "20:45:00", timeZone: "America/New_York"
    ).components()
    #expect(zoned.day == 3 && zoned.hour == 20 && zoned.timeZone?.identifier == "America/New_York")
  }

  @Test func rejectsMalformedDatesAndDSTGaps() async throws {
    for date in [
      AppleDate(date: ""), AppleDate(date: "2026-02-29"),
      AppleDate(date: "2026-04-31"), AppleDate(date: "2026-00-01"),
      AppleDate(date: "2026-10-03\n"), AppleDate(date: "2026-10-03", time: "25:00:00"),
      AppleDate(date: "2026-10-03", timeZone: "GMT"),
      AppleDate(date: "2026-10-03", time: "09:00:00", timeZone: "invalid"),
      AppleDate(date: "2026-03-08", time: "02:30:00", timeZone: "America/New_York"),
    ] { await expectFailure { try date.components() } }
    _ = try AppleDate(
      date: "2026-11-01", time: "01:30:00", timeZone: "America/New_York"
    ).components()
  }

  @Test func rejectsInvalidChangesBeforeDispatch() async throws {
    let service = FakeReminders()
    let dispatcher = ToolDispatcher(testReminders: service)
    for fields: JSONDictionary in [
      [:], ["title": "  "], ["title": .null], ["priority": 10], ["priority": true],
      ["completed": "yes"], ["listID": "move"], ["due": "2026-10-03"],
      ["due": ["date": "2026-10-03", "typo": true]],
      ["due": ["date": "2026-02-29"]], ["notes": .null],
      ["clear": ["title"]], ["clear": ["due", "due"]],
      ["notes": "preserve", "clear": ["notes"]],
    ] {
      await expectFailure {
        try await dispatcher.call(
          "reminders_edit", arguments: ["id": "target", "changes": .object(fields)])
      }
    }
    await expectFailure {
      try await dispatcher.call(
        "reminders_create", arguments: ["listID": "list", "changes": ["notes": "No title"]])
    }
    await expectFailure {
      try await dispatcher.call("reminders_delete", arguments: ["id": "target", "force": true])
    }
    #expect(await service.writes.isEmpty)
  }

  @Test func serviceGatesPatchesAndMoves() async throws {
    let service = FakeReminders()
    let dispatcher = ToolDispatcher(testReminders: service)
    #expect(await dispatcher.tools().count == 12)
    _ = try await dispatcher.call(
      "reminders_edit",
      arguments: ["id": "exact-item", "changes": ["completed": true, "clear": ["due"]]])
    let changes = try #require(await service.lastChanges)
    #expect(changes.completed == true && changes.title == nil && changes.notes == nil)
    #expect(changes.due == nil && changes.clear == [.due])
    let moved = try await dispatcher.call(
      "reminders_move", arguments: ["id": "exact-item", "listID": "destination"])
    let result = try JSONDictionary(encoding: moved)
    #expect(result["id"] == "moved-id" && result["listID"] == "destination")
    #expect(await service.writes == ["edit:exact-item", "move:exact-item:destination"])
    await service.setAvailable(false)
    #expect(await dispatcher.tools().map(\.name) == ["connection_check"])
    for name in ["reminders_get", "reminders_delete", "reminders_move"] {
      await expectFailure { try await dispatcher.call(name, arguments: ["id": "exact-item"]) }
    }
    #expect(await service.writes.count == 2)
    await service.setAvailable(true)
    await service.setFailure(ToolFailure("read_only", "Fixture read-only account"))
    for name in ["reminders_delete", "reminders_move"] {
      var arguments: JSONDictionary = ["id": "exact-item"]
      if name == "reminders_move" { arguments["listID"] = "destination" }
      do {
        _ = try await dispatcher.call(name, arguments: arguments)
        Issue.record("A failed mutation must not return success")
      } catch let error as ToolFailure { #expect(error.code == "read_only") }
    }
  }

  @Test func queriesValidateBeforeReading() async throws {
    let service = FakeReminders()
    let dispatcher = ToolDispatcher(testReminders: service)
    for query: JSONDictionary in [
      ["listIDs": []], ["listIDs": ["list", "list"]], ["listIDs": [""]],
      ["listIDs": ["list"], "limit": 201], ["listIDs": ["list"], "offset": -1],
      ["listIDs": ["list"], "due": "someday"], ["listIDs": ["list"], "search": " "],
      ["listIDs": ["list"], "timeZone": "invalid"], ["listIDs": ["list"], "completed": .null],
      ["listIDs": ["list"], "limti": 10],
    ] {
      await expectFailure {
        try await dispatcher.call("reminders_fetch", arguments: ["query": .object(query)])
      }
    }
    #expect(await service.reads == 0)
    _ = try await dispatcher.call(
      "reminders_fetch", arguments: ["query": ["listIDs": ["list"], "due": "today"]])
    #expect(await service.lastQuery?.completed == false)
    #expect(await service.reads == 1)
  }

  @Test func datePresetsSearchSortingAndPagination() throws {
    // Spring transition day is 23 hours; tomorrow must be a calendar day, not +86400.
    let zone = TimeZone(identifier: "America/New_York")!
    let now = ISO8601DateFormatter().date(from: "2026-03-08T16:00:00Z")!
    func item(_ id: String, _ date: AppleDate?, completed: Bool = false, list: String = "list")
      -> ReminderRecord
    {
      ReminderRecord(
        id: id, listID: list, title: "Café errands", notes: nil,
        priority: 0, completed: completed, due: date)
    }
    let records = [
      item("past-day", .init(date: "2026-03-07")),
      item("today", .init(date: "2026-03-08")),
      item("past-time", .init(date: "2026-03-08", time: "09:00:00", timeZone: zone.identifier)),
      item("tomorrow", .init(date: "2026-03-09")),
      item("midnight", .init(date: "2026-03-09", time: "04:00:00", timeZone: "GMT")),
      item("undated", nil), item("completed", .init(date: "2026-03-08"), completed: true),
      item("other-list", .init(date: "2026-03-08"), list: "other"),
    ]
    func page(_ due: ReminderDueFilter, offset: Int = 0, limit: Int = 100) throws -> ReminderPage {
      try ReminderQuery(
        listIDs: ["list"], search: "CAFE", due: due,
        timeZone: zone.identifier, sort: .due, offset: offset, limit: limit
      )
      .resolve(now: now).page(records)
    }
    #expect(try page(.today).reminders.map(\.id) == ["today", "past-time"])
    #expect(try page(.overdue).reminders.map(\.id) == ["past-day", "past-time"])
    #expect(try Set(page(.upcoming).reminders.map(\.id)) == ["tomorrow", "midnight"])
    #expect(try page(.undated).reminders.map(\.id) == ["undated"])
    let first = try page(.any, limit: 2)
    let second = try page(.any, offset: 2, limit: 2)
    #expect(first.total == 7 && first.nextOffset == 2 && second.nextOffset == 4)
    #expect(Set(first.reminders.map(\.id)).isDisjoint(with: second.reminders.map(\.id)))
    #expect(try page(.any, offset: 100).reminders.isEmpty)
    #expect(try page(.any).reminders.last?.id == "undated")
    let multiple = try ReminderQuery(listIDs: ["list", "other"], completed: true)
      .resolve(now: now, defaultTimeZone: zone).page(records)
    #expect(multiple.reminders.map(\.id) == ["completed"])
    #expect(multiple.timeZone == zone.identifier)
  }

  @Test func nativeCalendarConversionAndFallBoundary() throws {
    var native = DateComponents()
    native.calendar = Calendar(identifier: .buddhist)
    native.timeZone = TimeZone(secondsFromGMT: 0)
    native.year = 2569
    native.month = 10
    native.day = 3
    native.hour = 9
    #expect(
      AppleDate(components: native)
        == AppleDate(date: "2026-10-03", time: "09:00:00", timeZone: "GMT"))
    let now = ISO8601DateFormatter().date(from: "2026-11-01T17:00:00Z")!
    let late = ReminderRecord(
      id: "late", listID: "list", title: "Fixture", notes: "needle",
      priority: 0, completed: false,
      due: .init(date: "2026-11-02", time: "04:30:00", timeZone: "GMT"))
    let future = ReminderRecord(
      id: "future", listID: "list", title: "Fixture", notes: nil,
      priority: 0, completed: false, due: .init(date: "9999-12-31"))
    let undated = ReminderRecord(
      id: "undated", listID: "list", title: "Fixture", notes: nil,
      priority: 0, completed: false, due: nil)
    let today = try ReminderQuery(
      listIDs: ["list"], search: "needle", due: .today, timeZone: "America/New_York"
    )
    .resolve(now: now).page([late, future, undated])
    #expect(today.reminders.map(\.id) == ["late"])
    let sorted = try ReminderQuery(listIDs: ["list"], sort: .due).resolve(now: now).page([
      undated, future,
    ])
    #expect(sorted.reminders.map(\.id) == ["future", "undated"])
  }

  @Test func disabledEventKitNeverReadsData() async {
    let service = await EventKitReminders()
    #expect(await !service.available)
    await expectFailure { try await service.lists() }
    await expectFailure { try await service.get(id: "disposable-nonexistent") }
    await expectFailure { try await service.delete(id: "disposable-nonexistent") }
    await expectFailure {
      try await service.move(id: "disposable-nonexistent", listID: "destination")
    }
    await expectFailure { try await service.fetch(ReminderQuery(listIDs: ["fixture"]).resolve()) }
  }
}

@MainActor
final class FakeReminders: ReminderAccess {
  var available = true
  var writes: [String] = []
  var reads = 0
  var lastChanges: ReminderChanges?
  var lastQuery: ResolvedReminderQuery?
  var failure: ToolFailure?
  func setAvailable(_ value: Bool) { available = value }
  func setFailure(_ value: ToolFailure) { failure = value }
  func accounts() throws -> AppleAccounts { AppleAccounts(accounts: []) }
  func createList(accountID: String, title: String) throws -> AppleList {
    AppleList(
      id: "list", title: title, account: "Fixture", accountID: accountID, writable: true,
      editable: true)
  }
  func renameList(id: String, title: String) throws -> AppleList {
    try createList(accountID: "account", title: title)
  }
  func deleteList(id: String) throws { writes.append("delete-list:" + id) }
  func lists() throws -> [ReminderList] { [] }
  func fetch(_ query: ResolvedReminderQuery) async throws -> ReminderPage {
    reads += 1
    lastQuery = query
    return query.page([])
  }
  func get(id: String) throws -> ReminderRecord {
    if let failure { throw failure }
    return ReminderRecord(
      id: id, listID: "fixture-list", title: "Fixture", notes: nil,
      priority: 0, completed: false, due: nil)
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
  func move(id: String, listID: String) throws -> ReminderRecord {
    writes.append("move:" + id + ":" + listID)
    if let failure { throw failure }
    return ReminderRecord(
      id: "moved-id", listID: listID, title: "Fixture", notes: nil,
      priority: 0, completed: false, due: nil)
  }
  func delete(id: String) throws {
    writes.append("delete:" + id)
    if let failure { throw failure }
  }
}
