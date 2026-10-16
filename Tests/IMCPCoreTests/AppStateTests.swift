import Foundation
import Testing

@testable import IMCPCore

struct AppStateTests {
  @Test func stateOwnershipAndServicePersistence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var owner: StateDirectoryLock? = try StateDirectoryLock(directory: directory)
    #expect(owner != nil)
    do {
      _ = try StateDirectoryLock(directory: directory)
      Issue.record("Two app instances must not own one store")
    } catch {}
    let settings = directory.appendingPathComponent("services.json")
    #expect(try !ServiceSettings.load(from: settings)[.reminders])
    try ServiceSettings(enabledServices: [.reminders]).save(to: settings)
    #expect(try ServiceSettings.load(from: settings)[.reminders])
    try ServiceSettings().save(to: settings)
    #expect(try !ServiceSettings.load(from: settings)[.reminders])
    owner = nil
    _ = try StateDirectoryLock(directory: directory)
  }
}
