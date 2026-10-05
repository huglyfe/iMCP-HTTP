import Foundation
import SwiftMCP

@Schema struct NoteFolder: Codable, Sendable {
  let id: String
  let name: String
  let containerID: String
  let shared: Bool
}
@Schema struct NoteFolders: Codable, Sendable {
  let folders: [NoteFolder]
  let nextOffset: Int?
}
@Schema struct NoteRecord: Codable, Sendable {
  let id: String
  let folderID: String
  let title: String
  let modifiedAt: String
  let locked: Bool
  let shared: Bool
  let bodyHTML: String?
  let plaintext: String?
  let bodyTruncated: Bool?
}
@Schema struct NotePage: Codable, Sendable {
  let notes: [NoteRecord]
  let nextOffset: Int?
}

@MainActor protocol NoteAccess: Sendable {
  var available: Bool { get }
  func accounts() async throws -> AutomationAccounts
  func folders(accountID: String, offset: Int, limit: Int) async throws -> NoteFolders
  func fetch(folderID: String, search: String?, offset: Int, limit: Int) async throws -> NotePage
  func get(id: String, maxCharacters: Int) async throws -> NoteRecord
  func create(folderID: String, title: String, body: String) async throws -> NoteRecord
  func edit(id: String, bodyHTML: String) async throws -> NoteRecord
  func append(id: String, text: String) async throws -> NoteRecord
  func move(id: String, folderID: String) async throws -> NoteRecord
  func delete(id: String) async throws -> Deletion
}
func validateNoteBody(_ body: String) throws {
  guard body.utf8.count <= 16384 else {
    throw invalidArguments("Note input must be at most 16384 UTF-8 bytes.")
  }
}
func noteHTML(_ text: String) -> String {
  text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    .replacingOccurrences(of: "\n", with: "<br>")
}

@MCPServer(name: "Notes", toolNaming: .snakeCase)
final class NoteTools: Sendable {
  let access: any NoteAccess
  init(access: any NoteAccess) { self.access = access }
  /// Discover Notes accounts by exact ID.
  @MCPTool(hints: [.readOnly]) func notesAccounts() async throws -> AutomationAccounts {
    try await access.accounts()
  }
  /// List folders in one account with exact IDs and parent context.
  @MCPTool(hints: [.readOnly])
  func notesFolders(accountID: String, offset: Int = 0, limit: Int = 100) async throws
    -> NoteFolders
  {
    try validateIdentifier(accountID)
    try validatePage(offset: offset, limit: limit)
    return try await access.folders(accountID: accountID, offset: offset, limit: limit)
  }
  /// Fetch summaries in one folder, optionally searching title/plaintext. Locked notes are searched by title only.
  @MCPTool(hints: [.readOnly])
  func notesFetch(folderID: String, search: String? = nil, offset: Int = 0, limit: Int = 100)
    async throws -> NotePage
  {
    try validateIdentifier(folderID)
    try validatePage(offset: offset, limit: limit, search: search)
    return try await access.fetch(folderID: folderID, search: search, offset: offset, limit: limit)
  }
  /// Read one note's HTML/plaintext, each capped at maxCharacters. Locked notes return metadata only.
  @MCPTool(hints: [.readOnly])
  func notesGet(id: String, maxCharacters: Int = 16384) async throws -> NoteRecord {
    try validateIdentifier(id)
    guard (1...65536).contains(maxCharacters) else {
      throw invalidArguments("maxCharacters must be 1–65536.")
    }
    return try await access.get(id: id, maxCharacters: maxCharacters)
  }
  /// Create a note from plain text in an exact folder; title becomes its first line.
  @MCPTool
  func notesCreate(folderID: String, title: String, body: String = "") async throws -> NoteRecord {
    try validateIdentifier(folderID)
    try validateTitle(title)
    try validateNoteBody(body)
    return try await access.create(folderID: folderID, title: title, body: body)
  }
  /// Replace the entire HTML body, including its first-line title. Rejects locked notes and attachments; formatting may normalize.
  @MCPTool(hints: [.destructive])
  func notesEdit(id: String, bodyHTML: String) async throws -> NoteRecord {
    try validateIdentifier(id)
    try validateNoteBody(bodyHTML)
    return try await access.edit(id: id, bodyHTML: bodyHTML)
  }
  /// Append escaped plain text while retaining existing HTML. Rejects locked notes, attachments, or oversized existing bodies.
  @MCPTool
  func notesAppend(id: String, text: String) async throws -> NoteRecord {
    try validateIdentifier(id)
    try validateNoteBody(text)
    guard !text.isEmpty else { throw invalidArguments("Append text must not be empty.") }
    return try await access.append(id: id, text: text)
  }
  /// Move one note to an exact folder in the same account. Use its returned ID afterward.
  @MCPTool(hints: [.destructive])
  func notesMove(id: String, folderID: String) async throws -> NoteRecord {
    try validateIdentifier(id)
    try validateIdentifier(folderID)
    return try await access.move(id: id, folderID: folderID)
  }
  /// Delete one exact note using Notes' native retention behavior. No bulk deletion or purge.
  @MCPTool(hints: [.destructive])
  func notesDelete(id: String) async throws -> Deletion {
    try validateIdentifier(id)
    return try await access.delete(id: id)
  }
}
extension NoteTools: AppleToolModule {
  var service: AppleService { .notes }
  var available: Bool { get async { await access.available } }
}

@MainActor public final class NativeNotes: AutomationAccess, NoteAccess {
  public init(runner: AutomationRunner) { super.init(app: .notes, runner: runner) }
  init(runner: any ScriptRunning, permissionCheck: @escaping @Sendable (AutomationApp) -> Bool) {
    super.init(app: .notes, runner: runner, permissionCheck: permissionCheck)
  }
  func accounts() async throws -> AutomationAccounts {
    let values = try await run("accounts").array()
    return AutomationAccounts(
      accounts: try values.map {
        let row = try $0.array(2)
        return AutomationAccount(id: try row[0].string(), name: try row[1].string())
      })
  }
  private func note(_ value: ScriptValue) throws -> NoteRecord {
    let row = try value.array(10)
    return NoteRecord(
      id: try row[0].string(), folderID: try row[1].string(), title: try row[2].string(),
      modifiedAt: try row[3].string(), locked: try row[4].bool(), shared: try row[5].bool(),
      bodyHTML: try row[9].bool() ? row[6].string() : nil,
      plaintext: try row[9].bool() ? row[7].string() : nil,
      bodyTruncated: try row[9].bool() ? row[8].bool() : nil)
  }
  func folders(accountID: String, offset: Int, limit: Int) async throws -> NoteFolders {
    let values = try await run("folders", [.text(accountID), .integer(offset), .integer(limit)])
      .array(2)
    return NoteFolders(
      folders: try values[0].array().map {
        let row = try $0.array(4)
        return NoteFolder(
          id: try row[0].string(), name: try row[1].string(), containerID: try row[2].string(),
          shared: try row[3].bool())
      }, nextOffset: try values[1].bool() ? offset + limit : nil)
  }
  func fetch(folderID: String, search: String?, offset: Int, limit: Int) async throws -> NotePage {
    let values = try await run(
      "fetch", [.text(folderID), .text(search ?? ""), .integer(offset), .integer(limit)]
    ).array(2)
    return NotePage(
      notes: try values[0].array().map(note),
      nextOffset: try values[1].bool() ? offset + limit : nil)
  }
  func get(id: String, maxCharacters: Int) async throws -> NoteRecord {
    try await note(run("get", [.text(id), .integer(maxCharacters)]))
  }
  func create(folderID: String, title: String, body: String) async throws -> NoteRecord {
    try await note(
      run(
        "create",
        [.text(folderID), .text("<div>\(noteHTML(title))</div><div>\(noteHTML(body))</div>")]))
  }
  func edit(id: String, bodyHTML: String) async throws -> NoteRecord {
    try await note(run("edit", [.text(id), .text(bodyHTML)]))
  }
  func append(id: String, text: String) async throws -> NoteRecord {
    try await note(run("append", [.text(id), .text("<div>\(noteHTML(text))</div>")]))
  }
  func move(id: String, folderID: String) async throws -> NoteRecord {
    try await note(run("move", [.text(id), .text(folderID)]))
  }
  func delete(id: String) async throws -> Deletion {
    guard try await run("delete", [.text(id)]).bool() else { throw ScriptValue.invalidResult }
    return Deletion(deleted: true, id: id)
  }
}
