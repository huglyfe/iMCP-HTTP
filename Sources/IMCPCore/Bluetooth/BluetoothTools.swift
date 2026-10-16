import Foundation
import SwiftMCP

@Schema struct BLEDevice: Codable, Sendable {
  let id: String
  let name: String?
  let rssi: Int?
  let serviceUUIDs: [String]
  let connected: Bool
}
@Schema struct BLEDevices: Codable, Sendable { let devices: [BLEDevice] }
@Schema struct BLEService: Codable, Sendable {
  let id: String
  let uuid: String
  let primary: Bool
}
@Schema struct BLEServices: Codable, Sendable { let services: [BLEService] }
@Schema struct BLECharacteristic: Codable, Sendable {
  let id: String
  let uuid: String
  let properties: [String]
  let notifying: Bool
}
@Schema struct BLECharacteristics: Codable, Sendable { let characteristics: [BLECharacteristic] }
@Schema struct BLEValue: Codable, Sendable {
  let characteristicID: String
  let base64: String
}
@Schema struct BLEWrite: Codable, Sendable {
  let characteristicID: String
  /// True only after a successful ATT write response. It does not prove a device-level action.
  let acknowledged: Bool
}
@Schema struct BLESubscription: Codable, Sendable {
  let characteristicID: String
  let notifying: Bool
}
@Schema struct BLEDisconnected: Codable, Sendable {
  let id: String
  let connected: Bool
}
@Schema struct BLEEvent: Codable, Sendable {
  let sequence: Int
  let characteristicID: String
  let base64: String
  let receivedAt: String
}
@Schema struct BLEEvents: Codable, Sendable {
  let events: [BLEEvent]
  let nextCursor: String
  let dropped: Bool
}

/// A shared, non-consuming bounded log. Slow clients can detect lost values.
struct BLEEventBuffer {
  private let epoch = UUID().uuidString
  private var sequence = 0
  private var events: [BLEEvent] = []
  mutating func append(id: String, data: Data) {
    sequence += 1
    events.append(
      BLEEvent(
        sequence: sequence, characteristicID: id, base64: data.base64EncodedString(),
        receivedAt: Date().ISO8601Format()))
    if events.count > 256 { events.removeFirst(events.count - 256) }
  }
  func page(cursor: String?, limit: Int) throws -> BLEEvents {
    var after = 0
    if let cursor {
      let parts = cursor.split(separator: ":", omittingEmptySubsequences: false)
      guard parts.count == 2, parts[0] == epoch, let parsed = Int(parts[1]), parsed >= 0,
        parsed <= sequence
      else {
        throw ToolFailure("stale_cursor", "Start notification polling again without a cursor.")
      }
      after = parsed
    }
    let page = Array(events.filter { $0.sequence > after }.prefix(limit))
    return BLEEvents(
      events: page, nextCursor: "\(epoch):\(page.last?.sequence ?? sequence)",
      dropped: after < (events.first?.sequence ?? 1) - 1)
  }
}

func validateBLEUUIDs(_ values: [String]) throws {
  guard values.count <= 32, Set(values.map { $0.uppercased() }).count == values.count,
    values.allSatisfy({ value in
      (value.count == 4 || value.count == 8)
        ? value.allSatisfy(\.isHexDigit) && value.utf8.count == value.count
        : UUID(uuidString: value) != nil
    })
  else {
    throw invalidArguments("Use up to 32 distinct 16-bit, 32-bit, or full Bluetooth service UUIDs.")
  }
}
func validateBLEHandle(_ value: String) throws {
  guard UUID(uuidString: value) != nil else {
    throw invalidArguments("Use the exact identifier returned by BLE discovery.")
  }
}

@MainActor protocol BluetoothAccess: Sendable {
  var available: Bool { get }
  func scan(seconds: Int, serviceUUIDs: [String]) async throws -> BLEDevices
  func devices() throws -> BLEDevices
  func connect(id: String) async throws -> BLEDevice
  func disconnect(id: String) async throws -> BLEDisconnected
  func services(id: String) async throws -> BLEServices
  func characteristics(serviceID: String) async throws -> BLECharacteristics
  func read(id: String) async throws -> BLEValue
  func write(id: String, data: Data, withResponse: Bool) async throws -> BLEWrite
  func subscribe(id: String, enabled: Bool) async throws -> BLESubscription
  func notifications(cursor: String?, limit: Int) throws -> BLEEvents
}

@MCPServer(name: "Bluetooth LE", toolNaming: .snakeCase)
final class BluetoothTools: Sendable {
  let access: any BluetoothAccess
  init(access: any BluetoothAccess) { self.access = access }
  /// Scan nearby BLE advertisements for 1–15 seconds, optionally filtering service UUIDs. At most 128 devices.
  @MCPTool(hints: [.readOnly])
  func bleScan(seconds: Int = 5, serviceUUIDs: [String] = []) async throws -> BLEDevices {
    guard (1...15).contains(seconds) else {
      throw invalidArguments("Scan duration must be 1–15 seconds.")
    }
    try validateBLEUUIDs(serviceUUIDs)
    return try await access.scan(seconds: seconds, serviceUUIDs: serviceUUIDs)
  }
  /// List devices retained from this app's scans and connections.
  @MCPTool(hints: [.readOnly])
  func bleDevices() async throws -> BLEDevices { try await access.devices() }
  /// Connect to an exact scanned peripheral. Connections are shared by approved clients; no automatic reconnect.
  @MCPTool
  func bleConnect(id: String) async throws -> BLEDevice {
    try validateBLEHandle(id)
    return try await access.connect(id: id)
  }
  /// Disconnect and invalidate this peripheral's service/characteristic handles and subscriptions.
  @MCPTool
  func bleDisconnect(id: String) async throws -> BLEDisconnected {
    try validateBLEHandle(id)
    return try await access.disconnect(id: id)
  }
  /// Discover GATT services on a connected peripheral. Use returned handles, including for duplicate UUIDs.
  @MCPTool(hints: [.readOnly])
  func bleServices(id: String) async throws -> BLEServices {
    try validateBLEHandle(id)
    return try await access.services(id: id)
  }
  /// Discover GATT characteristics and supported properties in one exact service.
  @MCPTool(hints: [.readOnly])
  func bleCharacteristics(serviceID: String) async throws -> BLECharacteristics {
    try validateBLEHandle(serviceID)
    return try await access.characteristics(serviceID: serviceID)
  }
  /// Read bytes as base64. Unsubscribe first when this characteristic is notifying.
  @MCPTool(hints: [.readOnly])
  func bleRead(characteristicID: String) async throws -> BLEValue {
    try validateBLEHandle(characteristicID)
    return try await access.read(id: characteristicID)
  }
  /// Write base64 bytes. Without-response writes report queued, never acknowledged. No retries or device-specific encoding.
  @MCPTool(hints: [.destructive])
  func bleWrite(characteristicID: String, base64: String, withResponse: Bool = true) async throws
    -> BLEWrite
  {
    try validateBLEHandle(characteristicID)
    guard base64.utf8.count <= 684, let data = Data(base64Encoded: base64), data.count <= 512 else {
      throw invalidArguments(
        "Supply strict base64 encoding of at most 512 bytes; the device may impose a smaller limit."
      )
    }
    return try await access.write(id: characteristicID, data: data, withResponse: withResponse)
  }
  /// Enable notifications/indications; CoreBluetooth chooses the supported delivery mode. Poll ble_notifications for values.
  @MCPTool
  func bleSubscribe(characteristicID: String) async throws -> BLESubscription {
    try validateBLEHandle(characteristicID)
    return try await access.subscribe(id: characteristicID, enabled: true)
  }
  /// Disable notifications/indications for this characteristic for every approved client.
  @MCPTool
  func bleUnsubscribe(characteristicID: String) async throws -> BLESubscription {
    try validateBLEHandle(characteristicID)
    return try await access.subscribe(id: characteristicID, enabled: false)
  }
  /// Poll the shared last 256 values without consuming them. Retain nextCursor; dropped means values were overwritten.
  @MCPTool(hints: [.readOnly])
  func bleNotifications(cursor: String? = nil, limit: Int = 100) async throws -> BLEEvents {
    try validatePage(offset: 0, limit: limit)
    if let cursor { try validateIdentifier(cursor) }
    return try await access.notifications(cursor: cursor, limit: limit)
  }
}
extension BluetoothTools: AppleToolModule {
  var service: AppleService { .bluetooth }
  var available: Bool { get async { await access.available } }
}
