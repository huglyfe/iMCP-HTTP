import Foundation
import SwiftMCP
import Testing

@testable import IMCPCore

struct PhotoTests {
  @Test func photoQueriesValidateBeforeAdapterAccess() async throws {
    let photos = FakePhotos()
    let dispatcher = ToolDispatcher(modules: [PhotoTools(access: photos)])
    check(await dispatcher.tools().map(\.name).contains("photos_fetch"))
    for query: JSONDictionary in [
      ["limit": 201], ["offset": -1], ["albumID": ""], ["media": "document"],
      ["from": "2026-10-03"], ["favorite": .null], ["unknown": true],
      ["from": "2026-10-04T00:00:00Z", "before": "2026-10-03T00:00:00Z"],
    ] {
      await expectFailure {
        try await dispatcher.call("photos_fetch", arguments: ["query": .object(query)])
      }
    }
    check(await photos.calls == 0)
    _ = try await dispatcher.call(
      "photos_fetch", arguments: ["query": ["media": "image", "favorite": true]])
    check(await photos.calls == 1)
    await dispatcher.setDisabledTools(["photos_fetch"])
    await expectFailure { try await dispatcher.call("photos_fetch", arguments: ["query": [:]]) }
    check(await photos.calls == 1)
    await photos.disable()
    check(await dispatcher.tools().map(\.name) == ["connection_check"])
    await expectFailure { try await dispatcher.call("photos_get", arguments: ["id": "fixture"]) }
    check(await photos.calls == 1)
  }

  @Test func photosStayDisabledUntilSelectedAndNativeDisabledReadsFail() async throws {
    let old = try JSONDecoder().decode(
      ServiceSettings.self,
      from: Data(#"{"enabledServices":["reminders"],"disabledTools":[]}"#.utf8))
    check(!old[.photos])
    var updated = old
    updated[.photos] = true
    let restored = try JSONDecoder().decode(
      ServiceSettings.self, from: JSONEncoder().encode(updated))
    check(restored[.photos] && restored[.reminders])
    // Disabled calls must fail before any native PhotoKit library fetch or permission prompt.
    let native = await NativePhotos()
    await expectFailure { try await native.albums(offset: 0, limit: 1) }
    await expectFailure { try await native.fetch(PhotoQuery()) }
    await expectFailure { try await native.get(id: "fixture") }
    let dispatcher = ToolDispatcher(photos: native)
    check(await dispatcher.tools().map(\.name) == ["connection_check"])
    check(await dispatcher.catalog().count == 3)
  }
}

@MainActor
final class FakePhotos: PhotoAccess {
  var available = true
  var calls = 0
  func disable() { available = false }
  func albums(offset: Int, limit: Int) throws -> PhotoAlbums {
    calls += 1
    return PhotoAlbums(albums: [], nextOffset: nil)
  }
  func fetch(_ query: PhotoQuery) throws -> PhotoPage {
    calls += 1
    return PhotoPage(assets: [], nextOffset: nil)
  }
  func get(id: String) throws -> PhotoRecord {
    calls += 1
    return PhotoRecord(
      id: id, media: "image", createdAt: nil, width: 1, height: 1,
      durationSeconds: nil, favorite: false)
  }
}
