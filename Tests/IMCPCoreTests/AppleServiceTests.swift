import Contacts
import EventKit
import Foundation
import SwiftMCP
import Testing

@testable import IMCPCore

struct AppleServiceTests {
  private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(text.utf8))
  }

  @Test func strictDatesAndAllDayDSTBoundaries() async throws {
    for text in [
      "2026-02-29T12:00:00Z", "2026-10-03T12:00:00Z\n", "2026-10-03T12:00:00+01:00\n", "2026-10-03",
      "2026-10-03T12:00:00", "2026-10-03T25:00:00Z",
      "2026-10-03T12:00:00+25:00",
    ] {
      await expectFailure { try NativeDates.parse(text) }
    }
    let changes = try decode(
      EventChanges.self,
      #"{"title":"Fixture","start":"2026-03-08T05:00:00Z","end":"2026-03-09T04:00:00Z","timeZone":"America/New_York","allDay":true}"#
    )
    try changes.validate(creating: true)
    var bad = changes
    bad.end = "2026-03-09T05:00:00Z"
    await expectFailure { try bad.validate() }
    bad = changes
    bad.end = changes.start
    await expectFailure { try bad.validate() }
    for text in [
      #"{"start":"2026-10-03T12:00:00Z"}"#, #"{"title":null}"#,
      #"{"title":"Fixture","calendarID":"other"}"#,
      #"{"notes":"x","clear":["notes"]}"#, #"{"alarms":[{"at":"2026-10-03T12:00:00Z","typo":1}]}"#,
    ] {
      await expectFailure { try decode(EventChanges.self, text).validate() }
    }
  }

  @Test @MainActor func nativeAllDayWritesUseExclusiveDSTBoundaries() throws {
    // Unsaved objects only: no permission request, store query, or native save.
    let event = EKEvent(eventStore: EKEventStore())
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    for (start, end, month, firstDay, endDay) in [
      ("2026-11-01T04:00:00Z", "2026-11-02T05:00:00Z", 11, 1, 2),
      ("2026-03-08T05:00:00Z", "2026-03-09T04:00:00Z", 3, 8, 9),
      ("2026-10-12T04:00:00Z", "2026-10-14T04:00:00Z", 10, 12, 14),
    ] {
      let expectedStart = try #require(
        calendar.date(from: DateComponents(year: 2026, month: month, day: firstDay)))
      let expectedEnd = try #require(
        calendar.date(from: DateComponents(year: 2026, month: month, day: endDay)))
      let changes = EventChanges(
        start: start, end: end, timeZone: "America/New_York", allDay: true)
      try changes.validate()
      try EventKitCalendar.apply(changes, to: event)
      #expect(event.isAllDay)
      #expect(event.startDate == expectedStart)
      #expect(EventKitCalendar.exclusiveEnd(event) == expectedEnd)
      // Existing all-day time edits omit allDay and preserve it.
      var edit = changes
      edit.allDay = nil
      try EventKitCalendar.apply(edit, to: event)
      #expect(event.isAllDay)
      #expect(event.startDate == expectedStart)
      #expect(EventKitCalendar.exclusiveEnd(event) == expectedEnd)
    }
    let timed = EventChanges(
      start: "2026-10-12T13:00:00Z", end: "2026-10-12T14:00:00Z",
      timeZone: "America/New_York", allDay: false)
    try EventKitCalendar.apply(timed, to: event)
    #expect(!event.isAllDay)
    #expect(EventKitCalendar.exclusiveEnd(event) == (try NativeDates.parse(timed.end!)))
  }

  @Test(arguments: ["UTC", "America/New_York", "America/Los_Angeles", "Asia/Tokyo"])
  func allDayTimestampsPreserveCivilDates(floatingZone: String) throws {
    let zone = try #require(TimeZone(identifier: floatingZone))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    for (start, end, month, firstDay, endDay) in [
      ("2026-11-01T04:00:00Z", "2026-11-02T05:00:00Z", 11, 1, 2),
      ("2026-03-08T05:00:00Z", "2026-03-09T04:00:00Z", 3, 8, 9),
      ("2026-10-12T04:00:00Z", "2026-10-14T04:00:00Z", 10, 12, 14),
    ] {
      let changes = EventChanges(
        start: start, end: end, timeZone: "America/New_York", allDay: true)
      let schedule = try changes.schedule(floatingTimeZone: zone)
      #expect(
        schedule.start
          == calendar.date(from: DateComponents(year: 2026, month: month, day: firstDay)))
      #expect(
        schedule.end == calendar.date(from: DateComponents(year: 2026, month: month, day: endDay)))
      #expect(schedule.zone == zone)
    }
    // Timed events retain their exact instants, independent of the Mac timezone.
    let timed = EventChanges(
      start: "2026-03-08T05:00:00Z", end: "2026-03-09T04:00:00Z",
      timeZone: "America/New_York", allDay: false)
    let schedule = try timed.schedule(floatingTimeZone: zone)
    #expect(schedule.start == (try NativeDates.parse(timed.start!)))
    #expect(schedule.end == (try NativeDates.parse(timed.end!)))
    #expect(schedule.zone.identifier == "America/New_York")
  }

  @Test @MainActor func reminderDueWritesPreserveOrClearStart() throws {
    let reminder = EKReminder(eventStore: EKEventStore())
    let due = AppleDate(date: "2026-10-11")
    try EventKitReminders.apply(ReminderChanges(due: due), to: reminder)
    #expect(AppleDate(components: reminder.dueDateComponents) == due)
    #expect(reminder.startDateComponents == nil)
    let start = AppleDate(
      date: "2026-10-10", time: "09:00:00", timeZone: "America/New_York")
    try EventKitReminders.apply(ReminderChanges(start: start), to: reminder)
    try EventKitReminders.apply(ReminderChanges(due: AppleDate(date: "2026-10-12")), to: reminder)
    #expect(AppleDate(components: reminder.startDateComponents) == start)
    try EventKitReminders.apply(ReminderChanges(due: due, clear: [.start]), to: reminder)
    #expect(reminder.startDateComponents == nil)
    #expect(AppleDate(components: reminder.dueDateComponents) == due)
    let zone = TimeZone(identifier: "America/New_York")!
    let components = try due.components(floatingTimeZone: zone)
    #expect(components.timeZone == nil)
    #expect(components.calendar?.timeZone == zone)
  }

  @Test @MainActor func dateOnlyAllDayScheduleRoundTripsAndValidates() async throws {
    let changes = EventChanges(start: "2026-11-01", end: "2026-11-02", allDay: true)
    try changes.validate()
    let event = EKEvent(eventStore: EKEventStore())
    try EventKitCalendar.apply(changes, to: event)
    let schedule = try changes.schedule()
    #expect(event.startDate == schedule.start)
    #expect(EventKitCalendar.exclusiveEnd(event) == schedule.end)
    let edit = EventChanges(start: "2026-03-08", end: "2026-03-09", allDay: true)
    try EventKitCalendar.apply(edit, to: event)
    #expect(event.startDate == (try edit.schedule().start))
    #expect(EventKitCalendar.exclusiveEnd(event) == (try edit.schedule().end))
    for invalid in [
      EventChanges(start: "2026-02-30", end: "2026-03-02", allDay: true),
      EventChanges(start: "2026-11-02", end: "2026-11-01", allDay: true),
      EventChanges(start: "2026-11-01", end: "2026-11-02", allDay: false),
    ] { await expectFailure { try invalid.validate() } }
  }

  @Test @MainActor func calendarToolPreservesAllDayBeforeValidatingEdits() async throws {
    let calendar = FakeCalendar()
    calendar.allDay = true
    let dispatcher = ToolDispatcher(modules: [CalendarTools(access: calendar)])
    for changes: JSONDictionary in [
      ["start": "2026-11-01", "end": "2026-11-02"],
      [
        "start": "2026-11-01T04:00:00Z", "end": "2026-11-02T05:00:00Z",
        "timeZone": "America/New_York",
      ],
    ] {
      _ = try await dispatcher.call(
        "calendar_edit",
        arguments: [
          "id": "fixture", "start": "2026-11-01T04:00:00Z", "span": "thisEvent",
          "changes": .object(changes),
        ])
      #expect(calendar.lastEditChanges?.allDay == true)
    }
    calendar.allDay = false
    await expectFailure {
      try await dispatcher.call(
        "calendar_edit",
        arguments: [
          "id": "fixture", "start": "2026-11-01T04:00:00Z", "span": "thisEvent",
          "changes": ["start": "2026-11-01", "end": "2026-11-02"],
        ])
    }
    #expect(calendar.calls == ["edit:fixture", "edit:fixture"])
  }

  @Test @MainActor func contactStandardAndCustomLabelsRoundTrip() {
    let card = CNMutableContact()
    card.phoneNumbers = [
      CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "555-0100"))
    ]
    card.emailAddresses = [
      CNLabeledValue(label: "Fixture custom", value: "fixture@example.invalid" as NSString)
    ]
    let original = NativeContacts.record(card)
    #expect(original.phones?.first?.label == CNLabelHome)
    #expect(original.emails?.first?.label == "Fixture custom")
    NativeContacts.apply(ContactChanges(phones: original.phones, emails: original.emails), to: card)
    #expect(card.phoneNumbers.first?.label == CNLabelHome)
    #expect(card.emailAddresses.first?.label == "Fixture custom")
  }

  @Test func recurrenceAndAlarmsValidateWithoutAppleStores() async throws {
    let rule = try decode(
      RepeatRule.self, #"{"frequency":"monthly","weekdays":[{"day":2,"week":-1}],"count":6}"#)
    let native = try rule.native()
    #expect(native.frequency == .monthly && native.daysOfTheWeek?.first?.weekNumber == -1)
    #expect(native.recurrenceEnd?.occurrenceCount == 6)
    let roundtrip = try JSONDictionary(encoding: RepeatRule(native))
    #expect(roundtrip["frequency"] == "monthly" && roundtrip["count"] == 6)
    for text in [
      #"{"frequency":"weekly","interval":0}"#, #"{"frequency":"daily","weekdays":[{"day":2}]}"#,
      #"{"frequency":"weekly","weekdays":[{"day":2,"week":1}]}"#,
      #"{"frequency":"monthly","monthDays":[0]}"#,
      #"{"frequency":"monthly","months":[2]}"#, #"{"frequency":"yearly","yearDays":[367]}"#,
      #"{"frequency":"yearly","positions":[1]}"#, #"{"frequency":"daily","count":0}"#,
      #"{"frequency":"daily","count":2,"until":"2026-10-03T12:00:00Z"}"#,
    ] {
      await expectFailure { try decode(RepeatRule.self, text).native() }
    }
    let relative = try decode(TimeAlarm.self, #"{"offsetSeconds":-900}"#).native()
    #expect(relative.relativeOffset == -900)
    #expect(TimeAlarm(relative)?.offsetSeconds == -900)
    let absolute = try decode(TimeAlarm.self, #"{"at":"2026-10-03T12:00:00Z"}"#).native()
    #expect(TimeAlarm(absolute)?.at == "2026-10-03T12:00:00Z")
    let geofence = EKAlarm()
    geofence.structuredLocation = EKStructuredLocation(title: "Fixture")
    #expect(!TimeAlarm.supports(geofence) && TimeAlarm(geofence) == nil)
    for text in [
      "{}", #"{"at":"2026-10-03T12:00:00Z","offsetSeconds":0}"#, #"{"offsetSeconds":999999999}"#,
    ] {
      await expectFailure { try decode(TimeAlarm.self, text).native() }
    }
  }

  @Test func preparedEventOptionsPreserveUnrelatedAlarms() throws {
    // EventKit requires a store to construct a reminder. Never request access,
    // fetch records, or save this disposable in-memory value.
    let locationAlarm = EKAlarm()
    locationAlarm.structuredLocation = EKStructuredLocation(title: "Fixture")
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.alarms = [locationAlarm, EKAlarm(relativeOffset: -60)]
    let options = try EventOptions(
      alarms: [try decode(TimeAlarm.self, #"{"offsetSeconds":-900}"#)], recurrence: nil)
    options.apply(to: reminder)
    #expect(reminder.alarms?.count == 2)
    #expect(reminder.alarms?.contains(where: { $0.structuredLocation != nil }) == true)
    #expect(reminder.alarms?.contains(where: { $0.relativeOffset == -900 }) == true)
    try EventOptions(alarms: [], recurrence: nil).apply(to: reminder)
    #expect(reminder.alarms?.count == 1)
    #expect(reminder.alarms?.first?.structuredLocation != nil)
  }

  @Test @MainActor func contactPatchesPreserveUnrelatedFields() throws {
    // An unsaved value object; no CNContactStore is constructed or queried.
    let contact = CNMutableContact()
    contact.givenName = "Fixture"
    contact.familyName = "Preserved"
    contact.nickname = "Keep"
    contact.phoneNumbers = [
      CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "555-0100"))
    ]
    let changes = try decode(
      ContactChanges.self,
      #"{"givenName":"Updated","emails":[{"label":"work","value":"fixture@example.invalid"}],"birthday":{"month":2,"day":29}}"#
    )
    try changes.validate()
    NativeContacts.apply(changes, to: contact)
    #expect(
      contact.givenName == "Updated" && contact.familyName == "Preserved"
        && contact.nickname == "Keep")
    #expect(contact.phoneNumbers.first?.value.stringValue == "555-0100")
    #expect(contact.birthday?.year == nil && contact.birthday?.day == 29)
    let clear = try decode(
      ContactChanges.self, #"{"givenName":"","emails":[],"clear":["birthday"]}"#)
    try clear.validate()
    NativeContacts.apply(clear, to: contact)
    #expect(contact.givenName.isEmpty && contact.emailAddresses.isEmpty && contact.birthday == nil)
    let json = try JSONDictionary(encoding: NativeContacts.record(contact))
    #expect(json["givenName"] == nil && json["emails"] == nil && json["birthday"] == nil)
    #expect(json["familyName"] == "Preserved" && json["message"] == nil && json["success"] == nil)
  }

  @Test func disabledAdaptersDoNotConstructStores() async throws {
    let calendar = await EventKitCalendar()
    let contacts = await NativeContacts()
    for module in [
      CalendarTools(access: calendar) as any AppleToolModule, ContactTools(access: contacts),
    ] {
      let dispatcher = ToolDispatcher(modules: [module])
      #expect(await dispatcher.tools().map(\.name) == ["connection_check"])
      for tool in await module.mcpToolMetadata {
        await expectFailure { try await dispatcher.call(tool.name, arguments: [:]) }
      }
    }
    await expectFailure { try await calendar.accounts() }
    await expectFailure { try await calendar.lists() }
    await expectFailure { try await calendar.deleteList(id: "fixture") }
    await expectFailure { try await calendar.get(id: "fixture", start: Date()) }
    await expectFailure { try await contacts.accounts() }
    await expectFailure { try await contacts.get(id: "fixture") }
    await expectFailure { try await contacts.delete(id: "fixture") }
    await expectFailure { try await contacts.groups(accountID: "fixture") }
  }

  @Test func unselectedServicesStayDisabledAfterReload() throws {
    var settings = try decode(
      ServiceSettings.self, #"{"enabledServices":["reminders"],"disabledTools":[]}"#)
    #expect(
      settings[.reminders] && !settings[.calendar] && !settings[.contacts]
        && !settings[.maps])
    settings[.contacts] = true
    let restored = try JSONDecoder().decode(
      ServiceSettings.self, from: JSONEncoder().encode(settings))
    #expect(restored[.reminders] && restored[.contacts] && !restored[.calendar])
  }

  @Test func calendarAndContactsValidateBeforeDispatch() async throws {
    let calendar = FakeCalendar()
    let contacts = FakeContacts()
    let dispatcher = ToolDispatcher(modules: [
      CalendarTools(access: calendar), ContactTools(access: contacts),
    ])
    for args: JSONDictionary in [
      ["calendarIDs": [], "start": "2026-10-03T12:00:00Z", "end": "2026-10-04T12:00:00Z"],
      ["calendarIDs": ["list"], "start": "2026-10-03", "end": "2026-10-04"],
      ["calendarIDs": ["list"], "start": "2026-10-03T12:00:00Z", "end": "2028-10-04T12:00:00Z"],
    ] { await expectFailure { try await dispatcher.call("calendar_fetch", arguments: args) } }
    await expectFailure {
      try await dispatcher.call("calendar_delete", arguments: ["id": "event", "span": "thisEvent"])
    }
    await expectFailure {
      try await dispatcher.call(
        "calendar_delete",
        arguments: ["id": "event", "start": "2026-10-03T12:00:00Z", "span": "all"])
    }
    for changes: JSONDictionary in [
      [:], ["givenName": .null], ["typo": "x"], ["birthday": ["month": 2, "day": 30]],
      ["emails": [["value": ""]]], ["phones": [["value": "555-0100", "typo": true]]],
    ] {
      await expectFailure {
        try await dispatcher.call(
          "contacts_edit", arguments: ["id": "card", "changes": .object(changes)])
      }
    }
    await expectFailure {
      try await dispatcher.call(
        "contacts_create", arguments: ["accountID": "account", "changes": ["nickname": "Alone"]])
    }
    #expect(await calendar.calls.isEmpty)
    #expect(await contacts.calls.isEmpty)
    _ = try await dispatcher.call(
      "calendar_delete",
      arguments: ["id": "series", "start": "2026-10-03T12:00:00Z", "span": "futureEvents"])
    _ = try await dispatcher.call(
      "contacts_edit", arguments: ["id": "individual-card", "changes": ["familyName": "Changed"]])
    #expect(await calendar.calls == ["delete:series:2026-10-03T12:00:00Z:futureEvents"])
    #expect(await contacts.calls == ["edit:individual-card"])
    await calendar.setAvailable(false)
    await contacts.setAvailable(false)
    #expect(await dispatcher.tools().map(\.name) == ["connection_check"])
    await expectFailure {
      try await dispatcher.call("contacts_delete", arguments: ["id": "individual-card"])
    }
  }
}

@MainActor
final class FakeCalendar: CalendarAccess {
  var available = true
  var allDay = false
  var lastEditChanges: EventChanges?
  var calls: [String] = []
  func setAvailable(_ value: Bool) { available = value }
  func accounts() throws -> AppleAccounts { AppleAccounts(accounts: []) }
  func lists() throws -> [AppleList] { [] }
  func createList(accountID: String, title: String) throws -> AppleList {
    AppleList(
      id: "calendar", title: title, account: "Fixture", accountID: accountID, writable: true,
      editable: true)
  }
  func renameList(id: String, title: String) throws -> AppleList {
    try createList(accountID: "account", title: title)
  }
  func deleteList(id: String) throws { calls.append("delete-list:" + id) }
  func fetch(
    calendarIDs: [String], start: Date, end: Date, search: String?, offset: Int, limit: Int
  ) throws -> EventPage {
    calls.append("fetch")
    return EventPage(events: [], nextOffset: nil)
  }
  func get(id: String, start: Date) throws -> EventRecord {
    EventRecord(
      id: id, calendarID: "calendar", title: "Fixture", start: NativeDates.string(start),
      end: NativeDates.string(start.addingTimeInterval(3600)),
      timeZone: "GMT", allDay: allDay, notes: nil, location: nil, url: nil, availability: .busy,
      recurrence: nil, alarms: nil, otherAlarms: nil)
  }
  func create(calendarID: String, changes: EventChanges) throws -> EventRecord {
    calls.append("create")
    return try get(id: "created", start: NativeDates.parse(changes.start!))
  }
  func edit(id: String, start: Date, span: EventSpan, changes: EventChanges) throws -> EventRecord {
    calls.append("edit:" + id)
    lastEditChanges = changes
    return try get(id: id, start: start)
  }
  func move(id: String, start: Date, span: EventSpan, calendarID: String) throws -> EventRecord {
    calls.append("move:" + id)
    return try get(id: id, start: start)
  }
  func delete(id: String, start: Date, span: EventSpan) throws {
    calls.append("delete:\(id):\(NativeDates.string(start)):\(span.rawValue)")
  }
}

@MainActor
final class FakeContacts: ContactAccess {
  var available = true
  var calls: [String] = []
  func setAvailable(_ value: Bool) { available = value }
  func accounts() throws -> AppleAccounts { AppleAccounts(accounts: []) }
  func fetch(accountID: String, search: String?, groupID: String?, offset: Int, limit: Int) throws
    -> ContactPage
  {
    calls.append("fetch")
    return ContactPage(contacts: [], nextOffset: nil)
  }
  func get(id: String) throws -> ContactRecord {
    ContactRecord(
      id: id, givenName: "Fixture", middleName: nil, familyName: nil, prefix: nil, suffix: nil,
      nickname: nil,
      organization: nil, department: nil, jobTitle: nil, phones: nil, emails: nil, urls: nil,
      addresses: nil, birthday: nil)
  }
  func create(accountID: String, changes: ContactChanges) throws -> ContactRecord {
    calls.append("create")
    return try get(id: "created")
  }
  func edit(id: String, changes: ContactChanges) throws -> ContactRecord {
    calls.append("edit:" + id)
    return try get(id: id)
  }
  func delete(id: String) throws { calls.append("delete:" + id) }
  func groups(accountID: String) throws -> ContactGroups { ContactGroups(groups: []) }
  func createGroup(accountID: String, name: String) throws -> ContactGroup {
    ContactGroup(id: "group", name: name)
  }
  func renameGroup(id: String, name: String) throws -> ContactGroup {
    ContactGroup(id: id, name: name)
  }
  func deleteGroup(id: String) throws { calls.append("delete-group:" + id) }
  func membership(contactID: String, groupID: String, member: Bool) throws -> GroupMembership {
    GroupMembership(contactID: contactID, groupID: groupID, member: member)
  }
}

struct MapTests {
  @Test func coordinateValidationAndOptionalSteps() async throws {
    let maps = FakeMaps()
    let dispatcher = ToolDispatcher(modules: [MapTools(access: maps)])
    for position: JSONDictionary in [
      ["latitude": 91, "longitude": 0], ["latitude": 0, "longitude": 181], ["latitude": 0],
      ["latitude": 0, "longitude": 0, "typo": true],
    ] {
      await expectFailure {
        try await dispatcher.call(
          "maps_search", arguments: ["query": "Fixture", "near": .object(position)])
      }
    }
    await expectFailure {
      try await dispatcher.call("maps_search", arguments: ["query": "Fixture", "limit": 21])
    }
    await expectFailure {
      try await dispatcher.call("maps_search", arguments: ["query": "Fixture", "near": .null])
    }
    #expect(await maps.calls == 0)
    let result = try await dispatcher.call(
      "maps_directions",
      arguments: ["from": ["latitude": 0, "longitude": 0], "to": ["latitude": 1, "longitude": 1]])
    let json = try JSONDictionary(encoding: result)
    #expect(Set(json.keys) == ["distanceMeters", "travelSeconds"])
    let native = await NativeMaps()
    await expectFailure { try await native.search(query: "Fixture", near: nil, limit: 1) }
  }
}

@MainActor
final class FakeMaps: MapAccess {
  var available = true
  var calls = 0
  func search(query: String, near: Coordinates?, limit: Int) async throws -> Places {
    calls += 1
    return Places(places: [])
  }
  func directions(from: Coordinates, to: Coordinates, mode: TravelMode, includeSteps: Bool)
    async throws -> RouteRecord
  {
    calls += 1
    return RouteRecord(
      distanceMeters: 1234, travelSeconds: 120,
      steps: includeSteps ? [RouteStep(instruction: "Fixture", distanceMeters: 1234)] : nil)
  }
}

struct ReminderRangeTests {
  @Test func dueRangesUseExclusiveEndAndCompactResults() async throws {
    let records = ["2026-10-03", "2026-10-04", "2026-10-05"].enumerated().map { index, date in
      ReminderRecord(
        id: "item-\(index)", listID: "list", title: "Fixture", notes: "Detail-only text",
        priority: 0, completed: false, due: AppleDate(date: date))
    }
    let query = ReminderQuery(
      listIDs: ["list"], dueFrom: AppleDate(date: "2026-10-03"),
      dueBefore: AppleDate(date: "2026-10-05"), timeZone: "America/New_York")
    let page = try query.resolve().page(records)
    #expect(page.reminders.map(\.id) == ["item-0", "item-1"])
    let json = try JSONDictionary(encoding: page.reminders[0])
    #expect(json["notes"] == nil && json["alarms"] == nil && json["recurrence"] == nil)
    await expectFailure {
      try ReminderQuery(listIDs: ["list"], due: .today, dueFrom: AppleDate(date: "2026-10-03"))
        .resolve()
    }
    await expectFailure {
      try ReminderQuery(
        listIDs: ["list"], dueFrom: AppleDate(date: "2026-10-05"),
        dueBefore: AppleDate(date: "2026-10-03")
      ).resolve()
    }
  }
}
