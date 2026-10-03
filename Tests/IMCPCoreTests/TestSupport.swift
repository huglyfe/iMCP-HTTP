import Testing

func check(_ condition: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
  #expect(condition, sourceLocation: sourceLocation)
}
func require<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T {
  try #require(value, sourceLocation: sourceLocation)
}
func expectFailure<T>(
  _ operation: () async throws -> T, sourceLocation: SourceLocation = #_sourceLocation
) async {
  do {
    _ = try await operation()
    Issue.record("Expected rejection", sourceLocation: sourceLocation)
  } catch {}
}
