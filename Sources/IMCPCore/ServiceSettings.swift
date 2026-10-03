import Darwin
import Foundation

public struct ServiceSettings: Codable, Sendable {
  public let remindersEnabled: Bool
  public init(remindersEnabled: Bool = false) { self.remindersEnabled = remindersEnabled }
  public static func load(from url: URL) throws -> ServiceSettings {
    guard FileManager.default.fileExists(atPath: url.path) else { return ServiceSettings() }
    return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
  }
  public func save(to url: URL) throws {
    try JSONEncoder().encode(self).write(to: url, options: .atomic)
  }
}

/// The app holds one lease even while paused, preventing stale grants/settings
/// in a second process from overwriting a later revocation. OS releases on exit.
public final class StateDirectoryLock: Sendable {
  private let descriptor: Int32
  public init(directory: URL) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let descriptor = open(
      directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(descriptor)
      throw CocoaError(.fileLocking)
    }
    self.descriptor = descriptor
  }
  deinit { close(descriptor) }
}
