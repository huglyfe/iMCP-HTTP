import SwiftMCP

@MCPServer(name: "Contacts", toolNaming: .snakeCase)
final class ContactTools: Sendable {
  let access: any ContactAccess
  init(access: any ContactAccess) { self.access = access }

  /// List Contacts accounts.
  @MCPTool(hints: [.readOnly, .idempotent])
  func contactsAccounts() async throws -> AppleAccounts { try await access.accounts() }

  /// Search individual cards in an account by name, phone, or email. Optionally restrict to a group.
  @MCPTool(hints: [.readOnly, .idempotent])
  func contactsFetch(
    accountID: String, search: String? = nil, groupID: String? = nil,
    offset: Int = 0, limit: Int = 100
  ) async throws -> ContactPage {
    try validateIdentifier(accountID)
    if let groupID { try validateIdentifier(groupID) }
    try validatePage(offset: offset, limit: limit, search: search)
    return try await access.fetch(
      accountID: accountID, search: search, groupID: groupID, offset: offset, limit: limit)
  }

  /// Read one exact stored card. Linked cards are not merged.
  @MCPTool(hints: [.readOnly, .idempotent])
  func contactsGet(id: String) async throws -> ContactRecord {
    try validateIdentifier(id)
    return try await access.get(id: id)
  }

  /// Create a contact in an exact account.
  @MCPTool
  func contactsCreate(accountID: String, changes: ContactChanges) async throws -> ContactRecord {
    try validateIdentifier(accountID)
    try changes.validate(creating: true)
    return try await access.create(accountID: accountID, changes: changes)
  }

  /// Edit one stored card. Omitted fields stay unchanged; empty strings/arrays clear fields.
  @MCPTool(hints: [.destructive])
  func contactsEdit(id: String, changes: ContactChanges) async throws -> ContactRecord {
    try validateIdentifier(id)
    try changes.validate()
    return try await access.edit(id: id, changes: changes)
  }

  /// Delete one exact stored contact card.
  @MCPTool(hints: [.destructive])
  func contactsDelete(id: String) async throws -> Deletion {
    try validateIdentifier(id)
    try await access.delete(id: id)
    return Deletion(deleted: true, id: id)
  }

  /// List contact groups in an exact account.
  @MCPTool(hints: [.readOnly, .idempotent])
  func contactsGroups(accountID: String) async throws -> ContactGroups {
    try validateIdentifier(accountID)
    return try await access.groups(accountID: accountID)
  }

  /// Create a contact group in an exact account.
  @MCPTool
  func contactsGroupCreate(accountID: String, name: String) async throws -> ContactGroup {
    try validateIdentifier(accountID)
    try validateTitle(name)
    return try await access.createGroup(accountID: accountID, name: name)
  }

  /// Rename an exact contact group.
  @MCPTool(hints: [.destructive])
  func contactsGroupRename(id: String, name: String) async throws -> ContactGroup {
    try validateIdentifier(id)
    try validateTitle(name)
    return try await access.renameGroup(id: id, name: name)
  }

  /// Delete a contact group, preserving its contacts.
  @MCPTool(hints: [.destructive])
  func contactsGroupDelete(id: String) async throws -> Deletion {
    try validateIdentifier(id)
    try await access.deleteGroup(id: id)
    return Deletion(deleted: true, id: id)
  }

  /// Add or remove one contact from a group. Both must belong to the same account.
  @MCPTool(hints: [.destructive, .idempotent])
  func contactsGroupMembership(contactID: String, groupID: String, member: Bool) async throws
    -> GroupMembership
  {
    try validateIdentifier(contactID)
    try validateIdentifier(groupID)
    return try await access.membership(contactID: contactID, groupID: groupID, member: member)
  }
}
