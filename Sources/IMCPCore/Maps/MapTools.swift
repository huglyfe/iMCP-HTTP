import Foundation
import MapKit
import SwiftMCP

@Schema
struct Coordinates: Codable, Sendable {
  let latitude: Double
  let longitude: Double
  func validate() throws {
    guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude),
      (-180...180).contains(longitude)
    else {
      throw invalidArguments("Latitude must be -90–90 and longitude -180–180.")
    }
  }
  var native: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}
extension Coordinates {
  init(from decoder: Decoder) throws {
    try decoder.rejectUnknownFields(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    latitude = try values.decode(Double.self, forKey: .latitude)
    longitude = try values.decode(Double.self, forKey: .longitude)
  }
}

@Schema
struct PlaceRecord: Codable, Sendable {
  let name: String?
  let address: String?
  let coordinate: Coordinates
  let phone: String?
  let url: String?
}
@Schema
struct Places: Codable, Sendable { let places: [PlaceRecord] }
enum TravelMode: String, Codable, CaseIterable, Sendable { case driving, walking }
@Schema
struct RouteStep: Codable, Sendable {
  let instruction: String
  let distanceMeters: Double
}
@Schema
struct RouteRecord: Codable, Sendable {
  let distanceMeters: Double
  let travelSeconds: Double
  let steps: [RouteStep]?
}

@MainActor
protocol MapAccess: Sendable {
  var available: Bool { get }
  func search(query: String, near: Coordinates?, limit: Int) async throws -> Places
  func directions(from: Coordinates, to: Coordinates, mode: TravelMode, includeSteps: Bool)
    async throws -> RouteRecord
}

@MCPServer(name: "Maps", toolNaming: .snakeCase)
final class MapTools: Sendable {
  let access: any MapAccess
  init(access: any MapAccess) { self.access = access }

  /// Search places or addresses. Optional near biases results; no device location is read.
  @MCPTool(hints: [.readOnly])
  func mapsSearch(query: String, near: Coordinates? = nil, limit: Int = 10) async throws -> Places {
    try validatePage(offset: 0, limit: limit, search: query)
    guard limit <= 20 else { throw invalidArguments("Limit must be 1–20.") }
    try near?.validate()
    return try await access.search(query: query, near: near, limit: limit)
  }

  /// Get driving or walking distance and travel time. Include instructions only when needed.
  @MCPTool(hints: [.readOnly])
  func mapsDirections(
    from: Coordinates, to: Coordinates, mode: TravelMode = .driving, includeSteps: Bool = false
  ) async throws -> RouteRecord {
    try from.validate()
    try to.validate()
    return try await access.directions(from: from, to: to, mode: mode, includeSteps: includeSteps)
  }
}

extension MapTools: AppleToolModule {
  var service: AppleService { .maps }
  var available: Bool { get async { await access.available } }
}
