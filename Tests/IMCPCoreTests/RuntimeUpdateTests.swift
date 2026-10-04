import Foundation
import Testing

@testable import IMCPCore

struct RuntimeUpdateTests {
  @Test func authorizationPublishesOwnerStateChangesWithoutPolling() async throws {
    let f = try AuthorizationFixture()
    defer { f.cleanup() }
    var updates = await f.store.updates().makeAsyncIterator()
    let initial = try require(await updates.next())
    check(initial.approvals.isEmpty && initial.clients.isEmpty)
    let id = try await f.store.begin(f.fields())
    let pending = try require(await updates.next())
    check(pending.approvals.map(\.id) == [id])
    try await f.store.decide(id: id, approve: true)
    check(try require(await updates.next()).approvals.isEmpty)
    let callback = try require(await f.store.callback(for: id))
    _ = await updates.next()
    let code = try require(
      URLComponents(url: callback, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "code" }?.value)
    _ = try await f.store.exchange(f.exchangeFields(code))
    let authorized = try require(await updates.next())
    check(authorized.clients.count == 1)
    try await f.store.revoke(authorized.clients[0].id)
    check(try require(await updates.next()).clients.isEmpty)
    _ = try await f.store.begin(f.fields())
    _ = await updates.next()
    await f.store.setAccepting(false)
    check(try require(await updates.next()).approvals.isEmpty)
  }

  @Test func replacingTheUIObserverFinishesThePreviousStream() async throws {
    let f = try AuthorizationFixture()
    defer { f.cleanup() }
    var old = await f.store.updates().makeAsyncIterator()
    _ = await old.next()
    var current = await f.store.updates().makeAsyncIterator()
    _ = await current.next()
    check(await old.next() == nil)
    let id = try await f.store.begin(f.fields())
    check(try require(await current.next()).approvals.map(\.id) == [id])
  }

}
