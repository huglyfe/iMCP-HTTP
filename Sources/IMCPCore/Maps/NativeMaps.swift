import Foundation
import MapKit

@MainActor
public final class NativeMaps: AppleAccess, MapAccess {
  public private(set) var enabled: Bool
  private var activeRequests = 0
  public init(enabled: Bool = false) { self.enabled = enabled }
  public var available: Bool { enabled }
  public func setEnabled(_ enabled: Bool) { self.enabled = enabled }
  public func requestAccess() async throws -> Bool { true }

  func search(query: String, near: Coordinates?, limit: Int) async throws -> Places {
    try requireAccess()
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    request.region =
      near.map {
        MKCoordinateRegion(center: $0.native, latitudinalMeters: 10000, longitudinalMeters: 10000)
      }
      ?? MKCoordinateRegion(MKMapRect.world)
    let operation = MKLocalSearch(request: request)
    return try await perform(
      cancel: { operation.cancel() },
      start: { finish in
        operation.start { response, _ in
          guard let response else {
            finish(.failure(ToolFailure("read_failed", "Maps search failed.")))
            return
          }
          let places = response.mapItems.prefix(limit).map {
            PlaceRecord(
              name: $0.name, address: $0.placemark.title,
              coordinate: Coordinates(
                latitude: $0.placemark.coordinate.latitude,
                longitude: $0.placemark.coordinate.longitude),
              phone: $0.phoneNumber, url: $0.url?.absoluteString)
          }
          finish(.success(Places(places: places)))
        }
      })
  }
  func directions(from: Coordinates, to: Coordinates, mode: TravelMode, includeSteps: Bool)
    async throws -> RouteRecord
  {
    try requireAccess()
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.native))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.native))
    request.transportType = mode == .driving ? .automobile : .walking
    request.requestsAlternateRoutes = false
    let operation = MKDirections(request: request)
    return try await perform(
      cancel: { operation.cancel() },
      start: { finish in
        operation.calculate { response, _ in
          guard let response else {
            finish(.failure(ToolFailure("read_failed", "Maps directions failed.")))
            return
          }
          guard let route = response.routes.first else {
            finish(.failure(ToolFailure("not_found", "No route was found.")))
            return
          }
          finish(
            .success(
              RouteRecord(
                distanceMeters: route.distance, travelSeconds: route.expectedTravelTime,
                steps: includeSteps
                  ? route.steps.filter { !$0.instructions.isEmpty }.map {
                    RouteStep(instruction: $0.instructions, distanceMeters: $0.distance)
                  } : nil)))
        }
      })
  }

  private func perform<Value: Sendable>(
    cancel: @escaping () -> Void,
    start: (@escaping @Sendable (Result<Value, ToolFailure>) -> Void) -> Void
  ) async throws -> Value {
    try requireAccess()
    guard activeRequests < 4 else {
      throw ToolFailure("busy", "Too many Maps requests. Try again shortly.")
    }
    activeRequests += 1
    defer { activeRequests -= 1 }
    let pending = MapRequest<Value>(cancel: cancel)
    let result = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        pending.continuation = continuation
        start { result in Task { @MainActor in pending.finish(result.mapError { $0 as Error }) } }
        pending.timer = Task { @MainActor in
          do { try await Task.sleep(for: .seconds(20)) } catch { return }
          pending.cancel(ToolFailure("timeout", "Maps did not respond in time."))
        }
        if Task.isCancelled { pending.cancel(CancellationError()) }
      }
    } onCancel: {
      Task { @MainActor in pending.cancel(CancellationError()) }
    }
    try requireAccess()
    return result
  }
}

@MainActor
private final class MapRequest<Value: Sendable> {
  var continuation: CheckedContinuation<Value, Error>?
  var timer: Task<Void, Never>?
  private var cancelOperation: (() -> Void)?
  init(cancel: @escaping () -> Void) { cancelOperation = cancel }
  func finish(_ result: Result<Value, Error>) {
    guard let continuation else { return }
    self.continuation = nil
    timer?.cancel()
    timer = nil
    cancelOperation = nil
    continuation.resume(with: result)
  }
  func cancel(_ error: Error) {
    let operation = cancelOperation
    finish(.failure(error))
    operation?()
  }
}
