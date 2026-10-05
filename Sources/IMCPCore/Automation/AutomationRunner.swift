import AppKit
import Carbon
import Foundation
import OSAKit

/// Values, never executable source, cross the script boundary.
indirect enum ScriptValue: Sendable, Equatable {
  case text(String)
  case integer(Int)
  case boolean(Bool)
  case list([ScriptValue])
  func string() throws -> String {
    guard case .text(let value) = self else { throw Self.invalidResult }
    return value
  }
  func int() throws -> Int {
    guard case .integer(let value) = self else { throw Self.invalidResult }
    return value
  }
  func bool() throws -> Bool {
    guard case .boolean(let value) = self else { throw Self.invalidResult }
    return value
  }
  func array(_ count: Int? = nil) throws -> [ScriptValue] {
    guard case .list(let values) = self, count == nil || count == values.count else {
      throw Self.invalidResult
    }
    return values
  }
  static var invalidResult: ToolFailure {
    ToolFailure("invalid_result", "The app returned an unsupported scripting result.")
  }
  fileprivate var descriptor: NSAppleEventDescriptor {
    switch self {
    case .text(let value): NSAppleEventDescriptor(string: value)
    case .integer(let value): NSAppleEventDescriptor(int32: Int32(value))
    case .boolean(let value): NSAppleEventDescriptor(boolean: value)
    case .list(let values):
      {
        let list = NSAppleEventDescriptor.list()
        for (i, value) in values.enumerated() { list.insert(value.descriptor, at: i + 1) }
        return list
      }()
    }
  }
  fileprivate init(_ descriptor: NSAppleEventDescriptor, budget: inout Int, depth: Int = 0) throws {
    guard depth < 8, budget > 0 else {
      throw ToolFailure("result_too_large", "Request a smaller page or body range.")
    }
    budget -= 1
    switch descriptor.descriptorType {
    case typeAEList:
      var values: [ScriptValue] = []
      if descriptor.numberOfItems > 0 {
        for i in 1...descriptor.numberOfItems {
          guard let item = descriptor.atIndex(i) else { throw Self.invalidResult }
          values.append(try ScriptValue(item, budget: &budget, depth: depth + 1))
        }
      }
      self = .list(values)
    case typeBoolean, typeTrue, typeFalse: self = .boolean(descriptor.booleanValue)
    case typeSInt16, typeSInt32: self = .integer(Int(descriptor.int32Value))
    case typeLongDateTime:
      guard let value = descriptor.dateValue else { throw Self.invalidResult }
      self = .text(value.ISO8601Format())
    default:
      guard let value = descriptor.stringValue else { throw Self.invalidResult }
      budget -= value.utf8.count
      guard budget >= 0 else {
        throw ToolFailure("result_too_large", "Request a smaller page or body range.")
      }
      self = .text(value)
    }
  }
}

enum AutomationApp: String, Sendable {
  case mail = "Mail"
  case notes = "Notes"
  var bundleID: String { self == .mail ? "com.apple.mail" : "com.apple.Notes" }
}

@MainActor protocol ScriptRunning: Sendable {
  func run(app: AutomationApp, operation: String, arguments: [ScriptValue]) async throws
    -> ScriptValue
}

/// One bounded operation across Mail and Notes; no subprocess, shell, or client-supplied program.
@MainActor public final class AutomationRunner: ScriptRunning {
  typealias Execute = @Sendable (AutomationApp, String, [ScriptValue]) async throws -> ScriptValue
  private let execute: Execute
  private var busy = false
  public init() { execute = Self.execute }
  init(execute: @escaping Execute) { self.execute = execute }
  func run(app: AutomationApp, operation: String, arguments: [ScriptValue]) async throws
    -> ScriptValue
  {
    guard !busy else {
      throw ToolFailure("busy", "Another Mail or Notes operation is in progress.")
    }
    try Task.checkCancellation()
    busy = true
    defer { busy = false }
    let result = try await execute(app, operation, arguments)
    try Task.checkCancellation()
    return result
  }
  @concurrent private static func execute(
    app: AutomationApp, operation: String, arguments: [ScriptValue]
  ) async throws -> ScriptValue {
    try evaluate(source: source(for: app), operation: operation, arguments: arguments)
  }
  nonisolated static func source(for app: AutomationApp) throws -> String {
    guard let url = Bundle.module.url(forResource: app.rawValue, withExtension: "applescript")
    else { throw ScriptValue.invalidResult }
    return try String(contentsOf: url, encoding: .utf8)
  }
  nonisolated static func evaluate(
    source: String, operation: String, arguments: [ScriptValue], timeout: Duration = .seconds(20)
  )
    throws -> ScriptValue
  {
    return try autoreleasepool {
      guard let language = OSALanguage(forName: "AppleScript") else {
        throw ScriptValue.invalidResult
      }
      let instance = OSALanguageInstance(language: language)
      // OSA invokes this callback during interpretation and Apple-event waits. The pointer
      // belongs to this synchronous execution and is removed before its storage is released.
      let deadline = UnsafeMutablePointer<ContinuousClock.Instant>.allocate(capacity: 1)
      deadline.initialize(to: .now + timeout)
      defer {
        deadline.deinitialize(count: 1)
        deadline.deallocate()
      }
      guard
        OSASetActiveProc(
          instance.componentInstance,
          { context in
            guard let context else { return OSErr(userCanceledErr) }
            let end = context.assumingMemoryBound(to: ContinuousClock.Instant.self).pointee
            return ContinuousClock.now >= end ? OSErr(userCanceledErr) : OSErr(noErr)
          }, deadline) == noErr
      else { throw ScriptValue.invalidResult }
      defer { OSASetActiveProc(instance.componentInstance, nil, nil) }
      let script = OSAScript(source: source, from: nil, languageInstance: instance, using: [])
      let event = NSAppleEventDescriptor(
        eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent),
        targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID))
      event.setParam(
        NSAppleEventDescriptor(string: "dispatch"), forKeyword: AEKeyword(keyASSubroutineName))
      event.setParam(
        ScriptValue.list([.text(operation), .list(arguments)]).descriptor,
        forKeyword: AEKeyword(keyDirectObject))
      var error: NSDictionary?
      guard let result = script.executeAppleEvent(event, error: &error) else {
        if ContinuousClock.now >= deadline.pointee { throw failure(number: -1712) }
        throw failure(number: (error?[OSAScriptErrorNumber] as? NSNumber)?.intValue ?? 0)
      }
      var budget = 1_048_576
      return try ScriptValue(result, budget: &budget)
    }
  }
  nonisolated static func failure(number: Int) -> ToolFailure {
    switch number {
    case -1743, -1744:
      ToolFailure(
        "permission_denied",
        "Allow this app to control Mail or Notes in System Settings → Privacy & Security → Automation."
      )
    case -1712:
      ToolFailure(
        "timeout",
        "The app did not finish in time. A write may have completed; read back before retrying.")
    case -1728, 9001:
      ToolFailure(
        "not_found", "The exact account, container, or item no longer exists. Discover it again.")
    case 9002:
      ToolFailure(
        "unsupported_operation",
        "Locked notes and notes with attachments cannot be edited through these tools.")
    case 9005:
      ToolFailure(
        "uncertain_outcome",
        "The app accepted a mutation but readback failed. Inspect the destination before retrying.")
    case 9006:
      ToolFailure("unsupported_operation", "Cross-account Notes moves are unsupported.")
    case 9007:
      ToolFailure(
        "unsupported_operation",
        "Creating a child under a mailbox whose name contains slash is unsupported.")
    case 9003:
      ToolFailure(
        "limit_exceeded", "The result or operation exceeds the supported bound. Narrow the request."
      )
    case 9004:
      ToolFailure(
        "ambiguous_target",
        "More than one target matched. Refresh discovery; no write was performed.")
    default:
      ToolFailure(
        "automation_failed",
        "The app could not complete the operation. A write may have completed; read back before retrying."
      )
    }
  }
}

@MainActor public class AutomationAccess: AppleAccess {
  let app: AutomationApp
  let runner: any ScriptRunning
  private let permissionCheck: @Sendable (AutomationApp) -> Bool
  public private(set) var enabled = false
  init(
    app: AutomationApp, runner: any ScriptRunning,
    permissionCheck: @escaping @Sendable (AutomationApp) -> Bool = {
      permission($0, prompt: false) == noErr
    }
  ) {
    self.app = app
    self.runner = runner
    self.permissionCheck = permissionCheck
  }
  public var available: Bool { enabled && permissionCheck(app) }
  public func setEnabled(_ enabled: Bool) { self.enabled = enabled }
  public func requestAccess() async throws -> Bool {
    let app = app
    // Launch only the selected target on the owner's explicit enable action.
    if !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).contains(
      where: { !$0.isTerminated })
    {
      guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
      else { throw ToolFailure("app_unavailable", "The selected Apple app is not installed.") }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = false
      _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
    return await Self.requestPermission(app)
  }
  @concurrent private static func requestPermission(_ app: AutomationApp) async -> Bool {
    permission(app, prompt: true) == noErr
  }
  nonisolated private static func permission(_ app: AutomationApp, prompt: Bool) -> OSStatus {
    let target = NSAppleEventDescriptor(bundleIdentifier: app.bundleID)
    return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, prompt)
  }
  func run(_ operation: String, _ arguments: [ScriptValue] = []) async throws -> ScriptValue {
    try requireAccess()
    return try await runner.run(app: app, operation: operation, arguments: arguments)
  }
}
