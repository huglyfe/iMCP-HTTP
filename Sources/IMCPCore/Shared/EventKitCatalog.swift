import EventKit
import Foundation
import SwiftMCP

@Schema
struct AppleAccount: Codable, Sendable {
  let id: String
  let title: String
}
@Schema
struct AppleAccounts: Codable, Sendable { let accounts: [AppleAccount] }

@Schema
struct AppleList: Codable, Sendable {
  let id: String
  let title: String
  let account: String
  let accountID: String
  let writable: Bool
  let editable: Bool
}
@Schema
struct AppleLists: Codable, Sendable { let lists: [AppleList] }

@Schema
struct Deletion: Codable, Sendable {
  let deleted: Bool
  let id: String
}

@MainActor
struct EventKitCatalog {
  let store: EKEventStore
  let entity: EKEntityType

  func accounts() -> AppleAccounts {
    AppleAccounts(
      accounts: store.sources.map {
        AppleAccount(id: $0.sourceIdentifier, title: $0.title)
      }.sorted { $0.id < $1.id })
  }
  func lists() -> [AppleList] {
    store.calendars(for: entity).map(Self.record).sorted { $0.id < $1.id }
  }
  func get(_ id: String, writing: Bool = false) throws -> EKCalendar {
    try validateIdentifier(id)
    guard let list = store.calendar(withIdentifier: id),
      list.allowedEntityTypes.contains(entity == .event ? .event : .reminder)
    else { throw ToolFailure("not_found", "List was not found. Fetch available lists again.") }
    if writing, !list.allowsContentModifications {
      throw ToolFailure("read_only", "This list is read-only.")
    }
    return list
  }
  func create(accountID: String, title: String) throws -> AppleList {
    try validateIdentifier(accountID)
    try validateTitle(title)
    guard let source = store.source(withIdentifier: accountID) else {
      throw ToolFailure("not_found", "Account was not found.")
    }
    let list = EKCalendar(for: entity, eventStore: store)
    list.source = source
    list.title = title
    return try save(list)
  }
  func rename(id: String, title: String) throws -> AppleList {
    try validateTitle(title)
    let list = try get(id)
    guard !list.isImmutable else { throw ToolFailure("read_only", "This list cannot be renamed.") }
    list.title = title
    return try save(list)
  }
  func delete(id: String) throws {
    let list = try get(id)
    guard !list.isImmutable else { throw ToolFailure("read_only", "This list cannot be deleted.") }
    do { try store.removeCalendar(list, commit: true) } catch {
      list.reset()
      throw ToolFailure("write_failed", "Deletion was not confirmed. Fetch lists before retrying.")
    }
  }
  private func save(_ list: EKCalendar) throws -> AppleList {
    do { try store.saveCalendar(list, commit: true) } catch {
      list.reset()
      throw ToolFailure(
        "write_failed",
        "Save was not confirmed. The account may reject this operation. Fetch lists before retrying."
      )
    }
    return Self.record(list)
  }
  static func record(_ list: EKCalendar) -> AppleList {
    AppleList(
      id: list.calendarIdentifier, title: list.title, account: list.source.title,
      accountID: list.source.sourceIdentifier, writable: list.allowsContentModifications,
      editable: !list.isImmutable)
  }
}
