import Foundation

@testable import IMCPCore

@MainActor final class FixtureScriptRunner: ScriptRunning {
  struct Call {
    let app: AutomationApp
    let operation: String
    let arguments: [ScriptValue]
  }
  var calls: [Call] = []
  var result: ScriptValue = .list([])
  var error: ToolFailure?
  func run(app: AutomationApp, operation: String, arguments: [ScriptValue]) async throws
    -> ScriptValue
  {
    calls.append(Call(app: app, operation: operation, arguments: arguments))
    if let error { throw error }
    return result
  }
}
