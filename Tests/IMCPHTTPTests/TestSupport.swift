import Testing

func eventually(
  _ condition: () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation,
  isolation: isolated (any Actor)? = #isolation
) async throws {
  let deadline = ContinuousClock.now + .seconds(3)
  while !(await condition()), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  try #require(
    await condition(), "Timed out waiting for runtime state", sourceLocation: sourceLocation)
}
