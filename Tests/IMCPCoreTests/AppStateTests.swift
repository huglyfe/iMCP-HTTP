import Foundation
import Testing

@testable import IMCPCore

struct AppStateTests {
  @Test func stateOwnershipAndServicePersistence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var owner: StateDirectoryLock? = try StateDirectoryLock(directory: directory)
    check(owner != nil)
    do {
      _ = try StateDirectoryLock(directory: directory)
      Issue.record("Two app instances must not own one store")
    } catch {}
    let settings = directory.appendingPathComponent("services.json")
    check(try !ServiceSettings.load(from: settings).remindersEnabled)
    try ServiceSettings(remindersEnabled: true).save(to: settings)
    check(try ServiceSettings.load(from: settings).remindersEnabled)
    try ServiceSettings(remindersEnabled: false).save(to: settings)
    check(try !ServiceSettings.load(from: settings).remindersEnabled)
    owner = nil
    _ = try StateDirectoryLock(directory: directory)
  }
}
