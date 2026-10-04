import Darwin
import Foundation

public struct ServiceSettings: Codable, Sendable {
  public var remindersEnabled: Bool
  public var calendarEnabled: Bool
  public var contactsEnabled: Bool
  public var photosEnabled: Bool
  public var disabledTools: Set<String>
  public var mapsEnabled: Bool
  public init(
    remindersEnabled: Bool = false, calendarEnabled: Bool = false, contactsEnabled: Bool = false,
    mapsEnabled: Bool = false, photosEnabled: Bool = false, disabledTools: Set<String> = []
  ) {
    self.remindersEnabled = remindersEnabled
    self.calendarEnabled = calendarEnabled
    self.contactsEnabled = contactsEnabled
    self.mapsEnabled = mapsEnabled
    self.photosEnabled = photosEnabled
    self.disabledTools = disabledTools
  }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    photosEnabled = try values.decodeIfPresent(Bool.self, forKey: .photosEnabled) ?? false
    disabledTools = try values.decodeIfPresent(Set<String>.self, forKey: .disabledTools) ?? []
    remindersEnabled = try values.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? false
    calendarEnabled = try values.decodeIfPresent(Bool.self, forKey: .calendarEnabled) ?? false
    contactsEnabled = try values.decodeIfPresent(Bool.self, forKey: .contactsEnabled) ?? false
    mapsEnabled = try values.decodeIfPresent(Bool.self, forKey: .mapsEnabled) ?? false
  }
  public subscript(service: AppleService) -> Bool {
    get {
      switch service {
      case .photos: photosEnabled
      case .reminders: remindersEnabled
      case .calendar: calendarEnabled
      case .contacts: contactsEnabled
      case .maps: mapsEnabled
      default: false
      }
    }
    set {
      switch service {
      case .photos: photosEnabled = newValue
      case .reminders: remindersEnabled = newValue
      case .calendar: calendarEnabled = newValue
      case .contacts: contactsEnabled = newValue
      case .maps: mapsEnabled = newValue
      default: break
      }
    }
  }
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
