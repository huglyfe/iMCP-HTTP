import Foundation
import SwiftMCP

@Schema
struct PhotoAlbum: Codable, Sendable {
  let id: String
  let title: String
}
@Schema
struct PhotoAlbums: Codable, Sendable {
  let albums: [PhotoAlbum]
  let nextOffset: Int?
}
@Schema
struct PhotoRecord: Codable, Sendable {
  let id: String
  let media: String
  let createdAt: String?
  let width: Int
  let height: Int
  let durationSeconds: Double?
  let favorite: Bool
}
@Schema
struct PhotoPage: Codable, Sendable {
  let assets: [PhotoRecord]
  let nextOffset: Int?
}
enum PhotoMedia: String, Codable, CaseIterable, Sendable { case image, video, audio }

@Schema
struct PhotoQuery: Codable, Sendable {
  var albumID: String?
  /// Inclusive creation timestamp, ISO 8601 with an explicit offset.
  var from: String?
  /// Exclusive creation timestamp.
  var before: String?
  var media: PhotoMedia?
  var favorite: Bool?
  var offset: Int?
  var limit: Int?

  func validate() throws {
    if let albumID { try validateIdentifier(albumID) }
    try validatePage(offset: offset ?? 0, limit: limit ?? 100)
    let start = try from.map(NativeDates.parse)
    let end = try before.map(NativeDates.parse)
    if let start, let end, end <= start {
      throw invalidArguments("before must be later than from.")
    }
  }
}
extension PhotoQuery {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    albumID = try values.optional(String.self, forKey: .albumID)
    from = try values.optional(String.self, forKey: .from)
    before = try values.optional(String.self, forKey: .before)
    media = try values.optional(PhotoMedia.self, forKey: .media)
    favorite = try values.optional(Bool.self, forKey: .favorite)
    offset = try values.optional(Int.self, forKey: .offset)
    limit = try values.optional(Int.self, forKey: .limit)
  }
}

@MainActor
protocol PhotoAccess: Sendable {
  var available: Bool { get }
  func albums(offset: Int, limit: Int) throws -> PhotoAlbums
  func fetch(_ query: PhotoQuery) throws -> PhotoPage
  func get(id: String) throws -> PhotoRecord
}

@MCPServer(name: "Photos", toolNaming: .snakeCase)
final class PhotoTools: Sendable {
  let access: any PhotoAccess
  init(access: any PhotoAccess) { self.access = access }

  /// List albums with exact identifiers. Pages are not snapshots.
  @MCPTool(hints: [.readOnly])
  func photosAlbums(offset: Int = 0, limit: Int = 100) async throws -> PhotoAlbums {
    try validatePage(offset: offset, limit: limit)
    return try await access.albums(offset: offset, limit: limit)
  }

  /// Fetch image/video/audio metadata, newest first. No media bytes, downloads, or hidden assets.
  @MCPTool(hints: [.readOnly])
  func photosFetch(query: PhotoQuery) async throws -> PhotoPage {
    try query.validate()
    return try await access.fetch(query)
  }

  /// Read metadata for one exact visible asset. Does not export the file or download iCloud media.
  @MCPTool(hints: [.readOnly])
  func photosGet(id: String) async throws -> PhotoRecord {
    try validateIdentifier(id)
    return try await access.get(id: id)
  }
}
extension PhotoTools: AppleToolModule {
  var service: AppleService { .photos }
  var available: Bool { get async { await access.available } }
}
