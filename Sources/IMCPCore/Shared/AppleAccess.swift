import EventKit
import Foundation

@MainActor
public protocol AppleAccess: Sendable {
  var enabled: Bool { get }
  var available: Bool { get }
  var status: String { get }
  func setEnabled(_ enabled: Bool)
  func requestAccess() async throws -> Bool
}

extension AppleAccess {
  public var status: String {
    !enabled ? "Disabled" : available ? "Enabled" : "Access unavailable in System Settings"
  }
  func requireAccess() throws {
    guard enabled else {
      throw ToolFailure("service_disabled", "Enable this service in iMCP-HTTP.")
    }
    guard available else {
      throw ToolFailure("permission_denied", "Allow access in System Settings.")
    }
    try Task.checkCancellation()
  }
}

@MainActor
public final class EventKitStore {
  lazy var value = EKEventStore()
  public init() {}
}
