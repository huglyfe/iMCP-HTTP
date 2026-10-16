import Foundation

@testable import IMCPCore

@MainActor final class FixtureBluetooth: BluetoothAccess {
  var available = true
  var calls = 0
  var lastData: Data?
  func scan(seconds: Int, serviceUUIDs: [String]) async throws -> BLEDevices {
    calls += 1
    return BLEDevices(devices: [])
  }
  func devices() throws -> BLEDevices {
    calls += 1
    return BLEDevices(devices: [])
  }
  func connect(id: String) async throws -> BLEDevice {
    calls += 1
    return BLEDevice(id: id, name: nil, rssi: nil, serviceUUIDs: [], connected: true)
  }
  func disconnect(id: String) async throws -> BLEDisconnected {
    calls += 1
    return BLEDisconnected(id: id, connected: false)
  }
  func services(id: String) async throws -> BLEServices {
    calls += 1
    return BLEServices(services: [])
  }
  func characteristics(serviceID: String) async throws -> BLECharacteristics {
    calls += 1
    return BLECharacteristics(characteristics: [])
  }
  func read(id: String) async throws -> BLEValue {
    calls += 1
    return BLEValue(characteristicID: id, base64: "AA==")
  }
  func write(id: String, data: Data, withResponse: Bool) async throws -> BLEWrite {
    calls += 1
    lastData = data
    return BLEWrite(characteristicID: id, acknowledged: withResponse)
  }
  func subscribe(id: String, enabled: Bool) async throws -> BLESubscription {
    calls += 1
    return BLESubscription(characteristicID: id, notifying: enabled)
  }
  func notifications(cursor: String?, limit: Int) throws -> BLEEvents {
    calls += 1
    return try BLEEventBuffer().page(cursor: cursor, limit: limit)
  }
}
