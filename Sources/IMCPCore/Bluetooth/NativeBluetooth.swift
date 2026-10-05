import CoreBluetooth
import Foundation

@MainActor
public final class NativeBluetooth: NSObject, AppleAccess, BluetoothAccess,
  @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate
{
  public private(set) var enabled = false
  private var suspended = false
  private var central: CBCentralManager?
  private var peripherals: [UUID: CBPeripheral] = [:]
  private var advertisements: [UUID: BLEDevice] = [:]
  private var serviceHandles: [String: CBService] = [:]
  private var characteristicHandles: [String: CBCharacteristic] = [:]
  private var events = BLEEventBuffer()
  enum Operation {
    case power, scan, connect, disconnect, services, characteristics, read, write, notify
  }
  private struct Pending {
    let token: UUID
    let kind: Operation
    let target: AnyObject?
    let peripheral: CBPeripheral?
    let continuation: CheckedContinuation<Void, Error>
    let timer: Task<Void, Never>
  }
  private var pending: Pending?
  public override init() { super.init() }
  public var available: Bool { enabled && !suspended && CBManager.authorization == .allowedAlways }
  public var status: String {
    if !enabled { return "Disabled" }
    if CBManager.authorization != .allowedAlways {
      return "Bluetooth access unavailable in System Settings"
    }
    if let central, central.state != .poweredOn { return "Bluetooth is not powered on" }
    return "Enabled"
  }
  public func requestAccess() async throws -> Bool {
    let central = manager()
    try await waitForInitialization(state: { central.state }, seconds: 30)
    return CBManager.authorization == .allowedAlways
  }
  public func setEnabled(_ enabled: Bool) {
    self.enabled = enabled
    if !enabled { reset() }
  }
  /// Pause/quit release radio activity without altering saved enablement.
  public func resume() { suspended = false }
  public func suspend() {
    suspended = true
    reset()
  }
  private func reset() {
    central?.stopScan()
    finish(.failure(ToolFailure("cancelled", "Bluetooth activity stopped.")))
    for peripheral in peripherals.values {
      central?.cancelPeripheralConnection(peripheral)
      peripheral.delegate = nil
    }
    peripherals.removeAll()
    advertisements.removeAll()
    serviceHandles.removeAll()
    characteristicHandles.removeAll()
    events = BLEEventBuffer()
    central?.delegate = nil
    central = nil
  }
  private func manager() -> CBCentralManager {
    if let central { return central }
    let central = CBCentralManager(
      delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    self.central = central
    return central
  }
  // Only the initial unknown/resetting state is awaited. Radio-off is an actionable failure.
  func waitForInitialization(state: () -> CBManagerState, seconds: Int = 15) async throws {
    guard pending == nil else {
      throw ToolFailure("busy", "Another Bluetooth operation is in progress.")
    }
    if state() == .unknown || state() == .resetting {
      try await wait(kind: .power, target: nil, peripheral: nil, seconds: seconds) {}
    }
  }
  private func ready() async throws -> CBCentralManager {
    try requireAccess()
    let central = manager()
    try await waitForInitialization(state: { central.state })
    // Disable or pause can invalidate this manager while initialization is suspended.
    try requireAccess()
    guard pending == nil else {
      throw ToolFailure("busy", "Another Bluetooth operation is in progress.")
    }
    guard central === self.central, central.state == .poweredOn else {
      throw ToolFailure("bluetooth_unavailable", "Bluetooth is not powered on.")
    }
    return central
  }
  func wait(
    kind: Operation, target: AnyObject?, peripheral: CBPeripheral?, seconds: Int = 15,
    start: () -> Void
  ) async throws {
    guard pending == nil else {
      throw ToolFailure("busy", "Another Bluetooth operation is in progress.")
    }
    try Task.checkCancellation()
    let token = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let timer = Task { [weak self] in
          do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
          self?.expire(token: token, scanCompleted: kind == .scan)
        }
        pending = Pending(
          token: token, kind: kind, target: target, peripheral: peripheral,
          continuation: continuation, timer: timer)
        start()
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.expire(token: token, scanCompleted: false, cancelled: true)
      }
    }
    try Task.checkCancellation()
  }
  private func expire(token: UUID, scanCompleted: Bool, cancelled: Bool = false) {
    guard let pending, pending.token == token else { return }
    if pending.kind == .scan { central?.stopScan() }
    // A late callback must never satisfy a later operation. Drop the connection and its handles.
    if let peripheral = pending.peripheral {
      invalidate(peripheral)
      central?.cancelPeripheralConnection(peripheral)
    }
    finish(
      scanCompleted
        ? .success(())
        : .failure(
          ToolFailure(
            cancelled ? "cancelled" : "timeout",
            "Bluetooth operation interrupted. A write may have completed; inspect device state before retrying."
          )))
  }
  private func finish(_ result: Result<Void, Error>) {
    guard let pending else { return }
    self.pending = nil
    pending.timer.cancel()
    pending.continuation.resume(with: result)
  }
  func complete(_ kind: Operation, target: AnyObject, error: Error?) {
    guard pending?.kind == kind, pending?.target === target else { return }
    finish(
      error == nil
        ? .success(())
        : .failure(
          ToolFailure(
            "bluetooth_error", "The peripheral rejected or could not complete the operation.")))
  }
  private func device(_ peripheral: CBPeripheral) -> BLEDevice {
    let ad = advertisements[peripheral.identifier]
    return BLEDevice(
      id: peripheral.identifier.uuidString, name: ad?.name ?? peripheral.name, rssi: ad?.rssi,
      serviceUUIDs: ad?.serviceUUIDs ?? [], connected: peripheral.state == .connected)
  }
  private func peripheral(_ id: String, connected: Bool = true) throws -> CBPeripheral {
    guard let uuid = UUID(uuidString: id), let value = peripherals[uuid] else {
      throw ToolFailure("not_found", "Scan again to find this peripheral.")
    }
    if connected && value.state != .connected {
      throw ToolFailure("not_connected", "Connect to this peripheral first.")
    }
    return value
  }
  private func characteristic(_ id: String) throws -> (CBPeripheral, CBCharacteristic) {
    guard let value = characteristicHandles[id], let peripheral = value.service?.peripheral,
      peripheral.state == .connected
    else {
      throw ToolFailure(
        "stale_handle", "Discover the connected peripheral's services and characteristics again.")
    }
    return (peripheral, value)
  }
  private func invalidate(_ peripheral: CBPeripheral) {
    characteristicHandles = characteristicHandles.filter {
      $0.value.service?.peripheral !== peripheral
    }
    serviceHandles = serviceHandles.filter { $0.value.peripheral !== peripheral }
    peripheral.delegate = nil
  }
  func scan(seconds: Int, serviceUUIDs: [String]) async throws -> BLEDevices {
    let central = try await ready()
    advertisements.removeAll()
    peripherals = peripherals.filter { $0.value.state == .connected }
    try await wait(kind: .scan, target: nil, peripheral: nil, seconds: seconds) {
      central.scanForPeripherals(
        withServices: serviceUUIDs.isEmpty ? nil : serviceUUIDs.map { CBUUID(string: $0) },
        options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    return BLEDevices(
      devices: advertisements.keys.compactMap { peripherals[$0].map(device) }.sorted {
        $0.id < $1.id
      })
  }
  func devices() throws -> BLEDevices {
    try requireAccess()
    return BLEDevices(devices: peripherals.values.map(device).sorted { $0.id < $1.id })
  }
  func connect(id: String) async throws -> BLEDevice {
    let central = try await ready()
    let peripheral = try peripheral(id, connected: false)
    if peripheral.state == .connected { return device(peripheral) }
    guard peripheral.state == .disconnected else {
      throw ToolFailure("busy", "Wait for this peripheral to disconnect before connecting again.")
    }
    guard peripherals.values.filter({ $0.state == .connected }).count < 4 else {
      throw ToolFailure(
        "limit_exceeded", "Disconnect a device first; at most four may be connected.")
    }
    peripheral.delegate = self
    try await wait(kind: .connect, target: peripheral, peripheral: peripheral) {
      central.connect(peripheral)
    }
    return device(peripheral)
  }
  func disconnect(id: String) async throws -> BLEDisconnected {
    let central = try await ready()
    let peripheral = try peripheral(id, connected: false)
    if peripheral.state != .disconnected {
      try await wait(kind: .disconnect, target: peripheral, peripheral: peripheral) {
        central.cancelPeripheralConnection(peripheral)
      }
    }
    invalidate(peripheral)
    return BLEDisconnected(id: id, connected: false)
  }
  func services(id: String) async throws -> BLEServices {
    _ = try await ready()
    let peripheral = try peripheral(id)
    if peripheral.services == nil {
      try await wait(kind: .services, target: peripheral, peripheral: peripheral) {
        peripheral.discoverServices(nil)
      }
    }
    let values = peripheral.services ?? []
    guard values.count <= 64 else {
      throw ToolFailure("limit_exceeded", "This peripheral exposes more than 64 services.")
    }
    return BLEServices(
      services: values.map { value in
        let id = serviceHandles.first { $0.value === value }?.key ?? UUID().uuidString
        serviceHandles[id] = value
        return BLEService(id: id, uuid: value.uuid.uuidString, primary: value.isPrimary)
      })
  }
  func characteristics(serviceID: String) async throws -> BLECharacteristics {
    _ = try await ready()
    guard let service = serviceHandles[serviceID], let peripheral = service.peripheral,
      peripheral.state == .connected
    else { throw ToolFailure("stale_handle", "Discover services again.") }
    if service.characteristics == nil {
      try await wait(kind: .characteristics, target: service, peripheral: peripheral) {
        peripheral.discoverCharacteristics(nil, for: service)
      }
    }
    let values = service.characteristics ?? []
    let newCount = values.filter { value in !characteristicHandles.values.contains { $0 === value }
    }.count
    guard characteristicHandles.count + newCount <= 1024 else {
      throw ToolFailure("limit_exceeded", "Too many characteristics; disconnect a device first.")
    }
    return BLECharacteristics(
      characteristics: values.map { value in
        let id = characteristicHandles.first { $0.value === value }?.key ?? UUID().uuidString
        characteristicHandles[id] = value
        let flags: [(CBCharacteristicProperties, String)] = [
          (.read, "read"), (.write, "write"), (.writeWithoutResponse, "writeWithoutResponse"),
          (.notify, "notify"), (.indicate, "indicate"),
          (.authenticatedSignedWrites, "authenticatedSignedWrites"),
          (.extendedProperties, "extendedProperties"),
          (.notifyEncryptionRequired, "notifyEncryptionRequired"),
          (.indicateEncryptionRequired, "indicateEncryptionRequired"),
        ]
        return BLECharacteristic(
          id: id, uuid: value.uuid.uuidString,
          properties: flags.filter { value.properties.contains($0.0) }.map(\.1),
          notifying: value.isNotifying)
      })
  }
  func read(id: String) async throws -> BLEValue {
    _ = try await ready()
    let (peripheral, value) = try characteristic(id)
    guard value.properties.contains(.read), !value.isNotifying else {
      throw ToolFailure(
        "unsupported_operation", "Characteristic must support read and be unsubscribed first.")
    }
    try await wait(kind: .read, target: value, peripheral: peripheral) {
      peripheral.readValue(for: value)
    }
    return BLEValue(characteristicID: id, base64: (value.value ?? Data()).base64EncodedString())
  }
  func write(id: String, data: Data, withResponse: Bool) async throws -> BLEWrite {
    _ = try await ready()
    let (peripheral, value) = try characteristic(id)
    let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
    guard value.properties.contains(withResponse ? .write : .writeWithoutResponse) else {
      throw ToolFailure("unsupported_operation", "Characteristic does not support this write mode.")
    }
    guard data.count <= peripheral.maximumWriteValueLength(for: type) else {
      throw invalidArguments("Payload exceeds the negotiated write size; no bytes were written.")
    }
    if withResponse {
      try await wait(kind: .write, target: value, peripheral: peripheral) {
        peripheral.writeValue(data, for: value, type: type)
      }
    } else {
      guard peripheral.canSendWriteWithoutResponse else {
        throw ToolFailure("busy", "Peripheral's write queue is full. No bytes were queued.")
      }
      peripheral.writeValue(data, for: value, type: type)
    }
    return BLEWrite(characteristicID: id, acknowledged: withResponse)
  }
  func subscribe(id: String, enabled: Bool) async throws -> BLESubscription {
    _ = try await ready()
    let (peripheral, value) = try characteristic(id)
    guard
      !value.properties.intersection([
        .notify, .indicate, .notifyEncryptionRequired, .indicateEncryptionRequired,
      ]).isEmpty
    else {
      throw ToolFailure(
        "unsupported_operation", "Characteristic does not support notifications or indications.")
    }
    if value.isNotifying != enabled {
      try await wait(kind: .notify, target: value, peripheral: peripheral) {
        peripheral.setNotifyValue(enabled, for: value)
      }
    }
    return BLESubscription(characteristicID: id, notifying: value.isNotifying)
  }
  func notifications(cursor: String?, limit: Int) throws -> BLEEvents {
    try requireAccess()
    return try events.page(cursor: cursor, limit: limit)
  }

  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard central === self.central else { return }
    powerStateChanged(central.state)
  }
  func powerStateChanged(_ state: CBManagerState) {
    if pending?.kind == .power {
      guard state != .unknown, state != .resetting else { return }
      finish(.success(()))
    }
    if state != .poweredOn {
      for peripheral in peripherals.values { invalidate(peripheral) }
      peripherals.removeAll()
      advertisements.removeAll()
      events = BLEEventBuffer()
      finish(.failure(ToolFailure("bluetooth_unavailable", "Bluetooth became unavailable.")))
    }
  }
  public func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi: NSNumber
  ) {
    guard central === self.central, pending?.kind == .scan,
      peripherals.count < 128 || peripherals[peripheral.identifier] != nil
    else { return }
    peripherals[peripheral.identifier] = peripheral
    advertisements[peripheral.identifier] = BLEDevice(
      id: peripheral.identifier.uuidString,
      name: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name,
      rssi: rssi.intValue,
      serviceUUIDs: (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(
        \.uuidString), connected: peripheral.state == .connected)
  }
  public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard central === self.central else { return }
    complete(.connect, target: peripheral, error: nil)
  }
  public func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    guard central === self.central else { return }
    complete(
      .connect, target: peripheral, error: ToolFailure("connection_failed", "Connection failed."))
    invalidate(peripheral)
  }
  public func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    guard central === self.central else { return }
    if pending?.kind == .disconnect {
      complete(.disconnect, target: peripheral, error: error)
    } else if pending?.peripheral === peripheral {
      finish(
        .failure(
          ToolFailure(
            "disconnected", "Peripheral disconnected; a pending write may have completed.")))
    }
    invalidate(peripheral)
  }
  public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    complete(.services, target: peripheral, error: error)
  }
  public func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) { complete(.characteristics, target: service, error: error) }
  public func peripheral(
    _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
  ) { complete(.write, target: characteristic, error: error) }
  public func peripheral(
    _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: Error?
  ) { complete(.notify, target: characteristic, error: error) }
  public func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    if characteristic.isNotifying, error == nil,
      let id = characteristicHandles.first(where: { $0.value === characteristic })?.key,
      let data = characteristic.value, data.count <= 512
    {
      events.append(id: id, data: data)
    } else {
      complete(.read, target: characteristic, error: error)
    }
  }
  public func peripheral(
    _ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]
  ) {
    if pending?.peripheral === peripheral {
      finish(
        .failure(
          ToolFailure("stale_handle", "GATT services changed. Reconnect and discover again.")))
    }
    invalidate(peripheral)
    central?.cancelPeripheralConnection(peripheral)
  }
}
