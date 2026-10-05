import Testing

@testable import IMCPCore

func expectFailure<T>(
  code: String? = nil, _ operation: () async throws -> T,
  sourceLocation: SourceLocation = #_sourceLocation,
  isolation: isolated (any Actor)? = #isolation
) async {
  do {
    _ = try await operation()
    Issue.record("Expected rejection", sourceLocation: sourceLocation)
  } catch {
    if let code {
      #expect(
        (error as? ToolFailure)?.code == code, "Received: \(error)", sourceLocation: sourceLocation)
    }
  }
}

func waitUntil(
  _ condition: () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation,
  isolation: isolated (any Actor)? = #isolation
) async throws {
  let deadline = ContinuousClock.now + .seconds(3)
  while !(await condition()), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  try #require(
    await condition(), "Timed out waiting for fixture state", sourceLocation: sourceLocation)
}
