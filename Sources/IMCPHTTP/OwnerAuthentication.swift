import AppKit
import LocalAuthentication

@MainActor
protocol OwnerAuthenticating: AnyObject {
  func authenticate() async throws
  func cancel()
}

enum OwnerAuthenticationError: Error {
  case cancelled, unavailable, failed
}

/// A fresh context for every approval: no app-wide unlocked state or password handling.
@MainActor
final class MacOwnerAuthentication: OwnerAuthenticating {
  private var context: LAContext?

  func authenticate() async throws {
    let context = LAContext()
    self.context = context
    defer {
      context.invalidate()
      if self.context === context { self.context = nil }
    }
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
      throw OwnerAuthenticationError.unavailable
    }
    NSApp.activate(ignoringOtherApps: true)
    do {
      guard
        try await context.evaluatePolicy(
          .deviceOwnerAuthentication,
          localizedReason: "Approve this client's access to your enabled Apple services.")
      else { throw OwnerAuthenticationError.failed }
    } catch let error as LAError {
      switch error.code {
      case .userCancel, .appCancel, .systemCancel: throw OwnerAuthenticationError.cancelled
      default: throw OwnerAuthenticationError.failed
      }
    }
  }

  func cancel() {
    context?.invalidate()
    context = nil
  }
}
