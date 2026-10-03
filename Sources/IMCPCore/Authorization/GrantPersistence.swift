import Foundation

/// One actor owns this snapshot. Replace on disk before publishing any in-memory change.
/// Only credential hashes are persisted; there is no recoverable server secret.
struct GrantPersistence: Sendable {
  struct Snapshot: Codable {
    var version = 1
    let issuer: String
    var grants: [ClientGrant]
  }
  let url: URL
  let issuer: String

  func load() throws -> [ClientGrant] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
    guard snapshot.version == 1, snapshot.issuer == issuer,
      snapshot.grants.count <= 64, Set(snapshot.grants.map(\.id)).count == snapshot.grants.count
    else { throw OAuthFailure("invalid_store") }
    return snapshot.grants
  }

  func save(_ grants: [ClientGrant]) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    let data = try JSONEncoder().encode(Snapshot(issuer: issuer, grants: grants))
    // A private sibling file prevents a world-readable interval before the atomic replacement.
    let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard
      FileManager.default.createFile(
        atPath: temporary.path, contents: nil,
        attributes: [.posixPermissions: 0o600])
    else { throw OAuthFailure("server_error") }
    let handle = try FileHandle(forWritingTo: temporary)
    do {
      try handle.write(contentsOf: data)
      try handle.synchronize()
      try handle.close()
    } catch {
      try? handle.close()
      throw error
    }
    guard rename(temporary.path, url.path) == 0 else { throw OAuthFailure("server_error") }
  }
}
