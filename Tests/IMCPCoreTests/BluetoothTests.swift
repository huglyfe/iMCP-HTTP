import CoreBluetooth
import Foundation
import SwiftMCP
import Testing

@testable import IMCPCore

struct BluetoothTests {
  @Test func notificationPollingIsBoundedNonconsumingAndDetectsLoss() throws {
    var buffer = BLEEventBuffer()
    for index in 1...300 { buffer.append(id: "characteristic", data: Data([UInt8(index % 256)])) }
    let first = try buffer.page(cursor: nil, limit: 100)
    #expect(first.dropped && first.events.first?.sequence == 45 && first.events.count == 100)
    let repeated = try buffer.page(cursor: nil, limit: 100)
    #expect(repeated.nextCursor == first.nextCursor)
    let second = try buffer.page(cursor: first.nextCursor, limit: 200)
    #expect(
      !second.dropped && second.events.first?.sequence == 145 && second.events.last?.sequence == 300
    )
    #expect(try buffer.page(cursor: second.nextCursor, limit: 100).events.isEmpty)
    for _ in 1...300 { buffer.append(id: "characteristic", data: Data()) }
    #expect(try buffer.page(cursor: second.nextCursor, limit: 10).dropped)
    #expect(throws: ToolFailure.self) {
      try BLEEventBuffer().page(cursor: first.nextCursor, limit: 10)
    }
    #expect(throws: ToolFailure.self) { try buffer.page(cursor: "invalid", limit: 10) }
  }

  @Test @MainActor func operationDeadlineReleasesThePendingSlot() async {
    let native = NativeBluetooth()
    await expectFailure(code: "timeout") {
      try await native.wait(kind: .read, target: NSObject(), peripheral: nil, seconds: 0) {}
    }
    await expectFailure(code: "timeout") {
      try await native.wait(kind: .write, target: NSObject(), peripheral: nil, seconds: 0) {}
    }
  }

  @Test @MainActor func onlyMatchingCallbackCompletesPendingOperation() async throws {
    let native = NativeBluetooth()
    let target = NSObject()
    var started = false
    let task = Task {
      try await native.wait(kind: .read, target: target, peripheral: nil) { started = true }
    }
    defer { task.cancel() }
    try await waitUntil { started }
    native.complete(.write, target: target, error: nil)
    native.complete(.read, target: NSObject(), error: nil)
    await expectFailure(code: "busy") {
      try await native.wait(kind: .write, target: target, peripheral: nil) {}
    }
    native.complete(.read, target: target, error: nil)
    try await task.value
  }

  @Test(arguments: [false, true]) @MainActor
  func cancellationAndPauseReleasePendingOperation(pause: Bool) async throws {
    let native = NativeBluetooth()
    native.setEnabled(true)
    var started = false
    let task = Task {
      try await native.wait(kind: .read, target: NSObject(), peripheral: nil) { started = true }
    }
    defer { task.cancel() }
    try await waitUntil { started }
    if pause {
      native.suspend()
      await expectFailure(code: "cancelled") { try await task.value }
      #expect(native.enabled)
    } else {
      task.cancel()
      await expectFailure(code: "cancelled") { try await task.value }
    }
    await expectFailure(code: "timeout") {
      try await native.wait(kind: .read, target: NSObject(), peripheral: nil, seconds: 0) {}
    }
  }

  @Test(arguments: [CBManagerState.poweredOn, .poweredOff, .unauthorized, .unsupported]) @MainActor
  func initializationWaitsThroughTransientStates(terminal: CBManagerState) async throws {
    let native = NativeBluetooth()
    var state = CBManagerState.unknown
    var inspected = false
    let task = Task {
      try await native.waitForInitialization(state: {
        inspected = true
        return state
      })
    }
    defer { task.cancel() }
    try await waitUntil { inspected }
    native.powerStateChanged(.unknown)
    state = .resetting
    native.powerStateChanged(state)
    await expectFailure(code: "busy") {
      try await native.waitForInitialization(state: { state })
    }
    state = terminal
    native.powerStateChanged(state)
    try await task.value
    // A settled manager does not need a second callback to proceed.
    try await native.waitForInitialization(state: { state }, seconds: 0)
  }

  @Test @MainActor func initializationIsBoundedAndCanBeStopped() async throws {
    let native = NativeBluetooth()
    await expectFailure(code: "timeout") {
      try await native.waitForInitialization(state: { .unknown }, seconds: 0)
    }
    var inspected = false
    let task = Task {
      try await native.waitForInitialization(state: {
        inspected = true
        return .unknown
      })
    }
    defer { task.cancel() }
    try await waitUntil { inspected }
    native.suspend()
    await expectFailure(code: "cancelled") { try await task.value }
  }

  @Test @MainActor func toolsValidateBeforeRadioAndPreserveWriteAcknowledgement() async throws {
    let fake = FixtureBluetooth()
    let dispatcher = ToolDispatcher(modules: [BluetoothTools(access: fake)])
    let id = UUID().uuidString
    for (name, arguments): (String, JSONDictionary) in [
      ("ble_scan", ["seconds": 0]), ("ble_scan", ["seconds": 16]),
      ("ble_scan", ["serviceUUIDs": ["not-a-uuid"]]),
      ("ble_scan", ["serviceUUIDs": ["ABCD", "abcd"]]),
      ("ble_connect", ["id": "device name"]),
      ("ble_write", ["characteristicID": .string(id), "base64": "!!"]),
      (
        "ble_write",
        [
          "characteristicID": .string(id),
          "base64": .string(Data(repeating: 0, count: 513).base64EncodedString()),
        ]
      ),
      ("ble_write", ["characteristicID": .string(id), "base64": "AA==", "withResponse": .null]),
      ("ble_notifications", ["limit": 201]),
    ] { await expectFailure { try await dispatcher.call(name, arguments: arguments) } }
    #expect(fake.calls == 0)
    let write =
      try await dispatcher.call(
        "ble_write",
        arguments: ["characteristicID": .string(id), "base64": "AAEC", "withResponse": false])
      as? BLEWrite
    #expect(write?.acknowledged == false && fake.lastData == Data([0, 1, 2]))
    await dispatcher.setDisabledTools(["ble_write"])
    await expectFailure {
      try await dispatcher.call(
        "ble_write", arguments: ["characteristicID": .string(id), "base64": "AA=="])
    }
    #expect(fake.calls == 1)
    fake.available = false
    #expect(await dispatcher.tools().map(\.name) == ["connection_check"])
    let native = NativeBluetooth()
    await expectFailure { try await native.scan(seconds: 1, serviceUUIDs: []) }
    await expectFailure { try native.notifications(cursor: nil, limit: 1) }
  }

  @Test @MainActor func newServicesRemainOptInAndCatalogDoesNotRequestPermissions() async throws {
    let old = try JSONDecoder().decode(
      ServiceSettings.self, from: Data(#"{"enabledServices":["maps"],"disabledTools":[]}"#.utf8))
    #expect(!old[.bluetooth] && !old[.mail] && !old[.notes])
    let automation = AutomationRunner()
    let dispatcher = ToolDispatcher(
      bluetooth: NativeBluetooth(), mail: NativeMail(runner: automation),
      notes: NativeNotes(runner: automation))
    #expect(await dispatcher.tools().map(\.name) == ["connection_check"])
    let catalog = await dispatcher.catalog()
    #expect(catalog.contains { $0.name == "ble_write" && !$0.readOnly })
    #expect(catalog.contains { $0.name == "notes_get" && $0.readOnly })
    var settings = old
    settings[.mail] = true
    settings[.notes] = true
    settings[.bluetooth] = true
    let restored = try JSONDecoder().decode(
      ServiceSettings.self, from: JSONEncoder().encode(settings))
    #expect(restored[.mail] && restored[.notes] && restored[.bluetooth])
  }
}
