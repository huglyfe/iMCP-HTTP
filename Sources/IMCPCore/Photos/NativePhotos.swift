import Foundation
import Photos

/// PhotoKit owns the library. No image cache, file export, database copy, or change observer.
@MainActor
public final class NativePhotos: AppleAccess, PhotoAccess {
  public private(set) var enabled = false
  public init() {}
  public var available: Bool {
    guard enabled else { return false }
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    return status == .authorized || status == .limited
  }
  public func setEnabled(_ enabled: Bool) { self.enabled = enabled }
  public func requestAccess() async throws -> Bool {
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    return status == .authorized || status == .limited
  }

  func albums(offset: Int, limit: Int) throws -> PhotoAlbums {
    try requireAccess()
    let options = PHFetchOptions()
    options.wantsIncrementalChangeDetails = false
    let regular = PHAssetCollection.fetchAssetCollections(
      with: .album, subtype: .any, options: options)
    let smart = PHAssetCollection.fetchAssetCollections(
      with: .smartAlbum, subtype: .any, options: options)
    var page: [PhotoAlbum] = []
    var visible = 0
    for result in [regular, smart] {
      for index in 0..<result.count {
        let album = result.object(at: index)
        guard album.assetCollectionSubtype != .smartAlbumAllHidden else { continue }
        if visible >= offset {
          if page.count == limit {
            return PhotoAlbums(albums: page, nextOffset: offset + page.count)
          }
          page.append(PhotoAlbum(id: album.localIdentifier, title: album.localizedTitle ?? ""))
        }
        visible += 1
      }
    }
    return PhotoAlbums(albums: page, nextOffset: nil)
  }

  func fetch(_ query: PhotoQuery) throws -> PhotoPage {
    try requireAccess()
    try query.validate()
    let offset = query.offset ?? 0
    let limit = query.limit ?? 100
    let options = PHFetchOptions()
    options.includeHiddenAssets = false
    options.wantsIncrementalChangeDetails = false
    options.fetchLimit = offset + limit + 1
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    var predicates: [NSPredicate] = []
    if let from = query.from {
      predicates.append(
        NSPredicate(format: "creationDate >= %@", try NativeDates.parse(from) as NSDate))
    }
    if let before = query.before {
      predicates.append(
        NSPredicate(format: "creationDate < %@", try NativeDates.parse(before) as NSDate))
    }
    if let favorite = query.favorite {
      predicates.append(NSPredicate(format: "favorite == %@", NSNumber(value: favorite)))
    }
    if let media = query.media {
      let type: PHAssetMediaType =
        switch media {
        case .image: .image
        case .video: .video
        case .audio: .audio
        }
      predicates.append(NSPredicate(format: "mediaType == %d", type.rawValue))
    }
    options.predicate =
      predicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    let result: PHFetchResult<PHAsset>
    if let id = query.albumID {
      guard
        let album = PHAssetCollection.fetchAssetCollections(
          withLocalIdentifiers: [id], options: nil
        ).firstObject,
        album.assetCollectionSubtype != .smartAlbumAllHidden
      else {
        throw ToolFailure("not_found", "Album was not found or is unavailable.")
      }
      result = PHAsset.fetchAssets(in: album, options: options)
    } else {
      result = PHAsset.fetchAssets(with: options)
    }
    var assets: [PhotoRecord] = []
    for index in offset..<max(offset, min(result.count, offset + limit)) {
      assets.append(Self.record(result.object(at: index)))
    }
    return PhotoPage(
      assets: assets, nextOffset: result.count > offset + limit ? offset + limit : nil)
  }

  func get(id: String) throws -> PhotoRecord {
    try requireAccess()
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
      !asset.isHidden
    else {
      throw ToolFailure("not_found", "Asset was not found or is unavailable.")
    }
    return Self.record(asset)
  }

  private static func record(_ asset: PHAsset) -> PhotoRecord {
    let media =
      switch asset.mediaType {
      case .image: "image"
      case .video: "video"
      case .audio: "audio"
      default: "unknown"
      }
    return PhotoRecord(
      id: asset.localIdentifier, media: media,
      createdAt: asset.creationDate.map(NativeDates.string), width: asset.pixelWidth,
      height: asset.pixelHeight, durationSeconds: asset.mediaType == .image ? nil : asset.duration,
      favorite: asset.isFavorite)
  }
}
