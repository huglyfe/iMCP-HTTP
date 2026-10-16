import Foundation
import SwiftMCP

@Schema struct AutomationAccount: Codable, Sendable {
  let id: String
  let title: String
}
@Schema struct AutomationAccounts: Codable, Sendable { let accounts: [AutomationAccount] }
@Schema struct MailboxRecord: Codable, Sendable {
  let id: String
  let accountID: String
  let path: [String]
  let unreadCount: Int
}
@Schema struct Mailboxes: Codable, Sendable {
  let mailboxes: [MailboxRecord]
  let nextOffset: Int?
}
@Schema struct MailMessage: Codable, Sendable {
  let id: String
  let mailboxID: String
  let subject: String
  let sender: String
  let receivedAt: String?
  let read: Bool
  let flagged: Bool
  let body: String?
  let bodyTruncated: Bool?
}
@Schema struct MailSummary: Codable, Sendable {
  let id: String
  let mailboxID: String
  let subject: String
  let sender: String
  let receivedAt: String?
  let read: Bool
  let flagged: Bool
  init(_ detail: MailMessage) {
    id = detail.id
    mailboxID = detail.mailboxID
    subject = detail.subject
    sender = detail.sender
    receivedAt = detail.receivedAt
    read = detail.read
    flagged = detail.flagged
  }
}
@Schema struct MailPage: Codable, Sendable {
  let messages: [MailSummary]
  let nextOffset: Int?
}

/// Mail exposes no mailbox ID; encode account ID and exact path components without delimiter collisions.
struct MailboxTarget: Codable, Sendable {
  let accountID: String
  let path: [String]
  var id: String {
    get throws {
      let value = try JSONEncoder().encode(self).base64EncodedString()
      guard value.utf8.count <= 8192 else {
        throw ToolFailure("limit_exceeded", "Mailbox path exceeds the supported identifier size.")
      }
      return value
    }
  }
  init(accountID: String, path: [String]) {
    self.accountID = accountID
    self.path = path
  }
  init(id: String) throws {
    guard id.utf8.count <= 8192, let data = Data(base64Encoded: id),
      let target = try? JSONDecoder().decode(Self.self, from: data), !target.path.isEmpty,
      target.path.count <= 32
    else { throw invalidArguments("Use the exact mailboxID from mail_mailboxes.") }
    try validateIdentifier(target.accountID)
    for name in target.path { try validateTitle(name) }
    self = target
  }
  var arguments: [ScriptValue] { [.text(accountID), .list(path.map(ScriptValue.text))] }
}
func validateMailID(_ id: String) throws {
  guard let value = Int32(id), value > 0, String(value) == id else {
    throw invalidArguments("Use the exact message ID returned by mail_fetch.")
  }
}

@MainActor protocol MailAccess: Sendable {
  var available: Bool { get }
  func accounts() async throws -> AutomationAccounts
  func mailboxes(accountID: String, offset: Int, limit: Int) async throws -> Mailboxes
  func fetch(target: MailboxTarget, search: String?, unreadOnly: Bool, offset: Int, limit: Int)
    async throws -> MailPage
  func get(id: String, target: MailboxTarget, maxCharacters: Int) async throws -> MailMessage
  func edit(id: String, target: MailboxTarget, read: Bool?, flagged: Bool?) async throws
    -> MailMessage
  func move(id: String, target: MailboxTarget, destination: MailboxTarget) async throws
    -> MailMessage
  func delete(id: String, target: MailboxTarget) async throws -> Deletion
  func createMailbox(accountID: String, parent: MailboxTarget?, name: String) async throws
    -> MailboxRecord
  func renameMailbox(target: MailboxTarget, name: String) async throws -> MailboxRecord
}

@MCPServer(name: "Mail", toolNaming: .snakeCase)
final class MailTools: Sendable {
  let access: any MailAccess
  init(access: any MailAccess) { self.access = access }
  /// Discover Mail accounts. Mail may launch and synchronize; no messages are sent.
  @MCPTool(hints: [.readOnly]) func mailAccounts() async throws -> AutomationAccounts {
    try await access.accounts()
  }
  /// Discover account-qualified mailbox handles; names alone never target writes.
  @MCPTool(hints: [.readOnly])
  func mailMailboxes(accountID: String, offset: Int = 0, limit: Int = 100) async throws -> Mailboxes
  {
    try validateIdentifier(accountID)
    try validatePage(offset: offset, limit: limit)
    return try await access.mailboxes(accountID: accountID, offset: offset, limit: limit)
  }
  /// Fetch one mailbox in native order; search matches subject or sender. Pages are not snapshots.
  @MCPTool(hints: [.readOnly])
  func mailFetch(
    mailboxID: String, search: String? = nil, unreadOnly: Bool = false, offset: Int = 0,
    limit: Int = 100
  ) async throws -> MailPage {
    let target = try MailboxTarget(id: mailboxID)
    try validatePage(offset: offset, limit: limit, search: search)
    return try await access.fetch(
      target: target, search: search, unreadOnly: unreadOnly, offset: offset, limit: limit)
  }
  /// Get a message and bounded plain-text body from its exact mailbox. Does not mark it read or fetch remote images.
  @MCPTool(hints: [.readOnly])
  func mailGet(id: String, mailboxID: String, maxCharacters: Int = 16384) async throws
    -> MailMessage
  {
    try validateMailID(id)
    let target = try MailboxTarget(id: mailboxID)
    guard (1...65536).contains(maxCharacters) else {
      throw invalidArguments("maxCharacters must be 1–65536.")
    }
    return try await access.get(id: id, target: target, maxCharacters: maxCharacters)
  }
  /// Change read/flagged status on one exact message; omitted fields are preserved.
  @MCPTool func mailEdit(id: String, mailboxID: String, read: Bool? = nil, flagged: Bool? = nil)
    async throws -> MailSummary
  {
    try validateMailID(id)
    let target = try MailboxTarget(id: mailboxID)
    guard read != nil || flagged != nil else { throw invalidArguments("Provide read or flagged.") }
    return MailSummary(try await access.edit(id: id, target: target, read: read, flagged: flagged))
  }
  /// Move a message to an exact mailbox in the same account. Use its returned ID afterward.
  @MCPTool(hints: [.destructive])
  func mailMove(id: String, mailboxID: String, destinationMailboxID: String) async throws
    -> MailSummary
  {
    try validateMailID(id)
    let target = try MailboxTarget(id: mailboxID)
    let destination = try MailboxTarget(id: destinationMailboxID)
    guard target.accountID == destination.accountID else {
      throw invalidArguments("Cross-account Mail moves are unsupported.")
    }
    return MailSummary(try await access.move(id: id, target: target, destination: destination))
  }
  /// Delete one exact message using Mail's native delete behavior. Trash/retention depends on the account.
  @MCPTool(hints: [.destructive])
  func mailDelete(id: String, mailboxID: String) async throws -> Deletion {
    try validateMailID(id)
    return try await access.delete(id: id, target: MailboxTarget(id: mailboxID))
  }
  /// Create one mailbox in an explicit account/optional parent. Mailbox deletion requires Mail's UI.
  @MCPTool
  func mailMailboxCreate(accountID: String, name: String, parentMailboxID: String? = nil)
    async throws -> MailboxRecord
  {
    try validateIdentifier(accountID)
    try validateTitle(name)
    guard !name.contains("/") else {
      throw invalidArguments("Mailbox name must be one path component, without slash.")
    }
    let parent = try parentMailboxID.map { try MailboxTarget(id: $0) }
    guard parent == nil || parent?.accountID == accountID else {
      throw invalidArguments("Parent must belong to the selected account.")
    }
    return try await access.createMailbox(accountID: accountID, parent: parent, name: name)
  }
  /// Rename one mailbox. Its old handle becomes stale; refresh child mailbox handles afterward.
  @MCPTool
  func mailMailboxRename(mailboxID: String, name: String) async throws -> MailboxRecord {
    try validateTitle(name)
    guard !name.contains("/") else {
      throw invalidArguments("Mailbox name must not contain slash.")
    }
    return try await access.renameMailbox(target: MailboxTarget(id: mailboxID), name: name)
  }
}
extension MailTools: AppleToolModule {
  var service: AppleService { .mail }
  var available: Bool { get async { await access.available } }
}

@MainActor public final class NativeMail: AutomationAccess, MailAccess {
  public init(runner: AutomationRunner) { super.init(app: .mail, runner: runner) }
  init(runner: any ScriptRunning, permissionCheck: @escaping @Sendable (AutomationApp) -> Bool) {
    super.init(app: .mail, runner: runner, permissionCheck: permissionCheck)
  }
  func accounts() async throws -> AutomationAccounts {
    let rows = try await run("accounts").array()
    return AutomationAccounts(
      accounts: try rows.map {
        let row = try $0.array(2)
        return AutomationAccount(id: try row[0].string(), title: try row[1].string())
      })
  }
  private func mailbox(_ value: ScriptValue, accountID: String) throws -> MailboxRecord {
    let row = try value.array(2)
    let path = try row[0].array().map { try $0.string() }
    return MailboxRecord(
      id: try MailboxTarget(accountID: accountID, path: path).id, accountID: accountID, path: path,
      unreadCount: try row[1].int())
  }
  private func message(_ value: ScriptValue, target: MailboxTarget) throws -> MailMessage {
    let row = try value.array(9)
    return MailMessage(
      id: try row[0].string(), mailboxID: try target.id, subject: try row[1].string(),
      sender: try row[2].string(), receivedAt: try row[3].string().isEmpty ? nil : row[3].string(),
      read: try row[4].bool(),
      flagged: try row[5].bool(), body: try row[8].bool() ? row[6].string() : nil,
      bodyTruncated: try row[8].bool() ? row[7].bool() : nil)
  }
  func mailboxes(accountID: String, offset: Int, limit: Int) async throws -> Mailboxes {
    let values = try await run("mailboxes", [.text(accountID), .integer(offset), .integer(limit)])
      .array(2)
    return Mailboxes(
      mailboxes: try values[0].array().map { try mailbox($0, accountID: accountID) },
      nextOffset: try values[1].bool() ? offset + limit : nil)
  }
  func fetch(target: MailboxTarget, search: String?, unreadOnly: Bool, offset: Int, limit: Int)
    async throws -> MailPage
  {
    let values = try await run(
      "fetch",
      target.arguments + [
        .text(search ?? ""), .boolean(unreadOnly), .integer(offset), .integer(limit),
      ]
    ).array(2)
    return MailPage(
      messages: try values[0].array().map { MailSummary(try message($0, target: target)) },
      nextOffset: try values[1].bool() ? offset + limit : nil)
  }
  func get(id: String, target: MailboxTarget, maxCharacters: Int) async throws -> MailMessage {
    try await message(
      run("get", target.arguments + [.text(id), .integer(maxCharacters)]), target: target)
  }
  func edit(id: String, target: MailboxTarget, read: Bool?, flagged: Bool?) async throws
    -> MailMessage
  {
    try await message(
      run(
        "edit",
        target.arguments + [
          .text(id), .text(read.map(String.init) ?? ""), .text(flagged.map(String.init) ?? ""),
        ]), target: target)
  }
  func move(id: String, target: MailboxTarget, destination: MailboxTarget) async throws
    -> MailMessage
  {
    try await message(
      run("move", target.arguments + [.text(id), .list(destination.path.map(ScriptValue.text))]),
      target: destination)
  }
  func delete(id: String, target: MailboxTarget) async throws -> Deletion {
    guard try await run("delete", target.arguments + [.text(id)]).bool() else {
      throw ScriptValue.invalidResult
    }
    return Deletion(deleted: true, id: id)
  }
  func createMailbox(accountID: String, parent: MailboxTarget?, name: String) async throws
    -> MailboxRecord
  {
    try await mailbox(
      run(
        "createMailbox",
        [.text(accountID), .list((parent?.path ?? []).map(ScriptValue.text)), .text(name)]),
      accountID: accountID)
  }
  func renameMailbox(target: MailboxTarget, name: String) async throws -> MailboxRecord {
    try await mailbox(
      run("renameMailbox", target.arguments + [.text(name)]), accountID: target.accountID)
  }
}
