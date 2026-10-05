import Foundation
import SwiftMCP
import Testing

@testable import IMCPCore

struct AutomationTests {
  @Test @MainActor func sharedRunnerRejectsOverlapAndIndependentRuntimesDoNotShareState()
    async throws
  {
    let execution = ScriptExecutionGate()
    let runner = AutomationRunner { _, _, _ in await execution.run() }
    let mail = NativeMail(runner: runner, permissionCheck: { _ in true })
    let notes = NativeNotes(runner: runner, permissionCheck: { _ in true })
    mail.setEnabled(true)
    notes.setEnabled(true)
    let pending = Task { try await mail.accounts() }
    defer { pending.cancel() }
    try await waitUntil { await execution.started }
    await expectFailure(code: "busy") { try await notes.accounts() }
    let independent = AutomationRunner { _, _, _ in .list([]) }
    #expect(
      try await independent.run(app: .notes, operation: "accounts", arguments: []) == .list([]))
    await execution.finish()
    #expect(try await pending.value.accounts.isEmpty)
    #expect(try await notes.accounts().accounts.isEmpty)
  }

  @Test @MainActor func runnerReleasesItsSlotAfterFailure() async {
    let runner = AutomationRunner { _, _, _ in throw ToolFailure("fixture", "Expected failure") }
    for app in [AutomationApp.mail, .notes] {
      await expectFailure(code: "fixture") {
        try await runner.run(app: app, operation: "accounts", arguments: [])
      }
    }
  }

  @Test @MainActor func cancellationHoldsTheSlotUntilNativeExecutionReturns() async throws {
    let execution = ScriptExecutionGate()
    let runner = AutomationRunner { _, _, _ in await execution.run() }
    let pending = Task { try await runner.run(app: .mail, operation: "accounts", arguments: []) }
    defer { pending.cancel() }
    try await waitUntil { await execution.started }
    pending.cancel()
    await expectFailure(code: "busy") {
      try await runner.run(app: .notes, operation: "accounts", arguments: [])
    }
    await execution.finish()
    await #expect(throws: CancellationError.self) { try await pending.value }
    #expect(try await runner.run(app: .notes, operation: "accounts", arguments: []) == .list([]))
  }

  @Test @MainActor func deniedPermissionPreventsExecutionEvenWhenEnabled() async {
    let runner = FixtureScriptRunner()
    let mail = NativeMail(runner: runner, permissionCheck: { _ in false })
    let notes = NativeNotes(runner: runner, permissionCheck: { _ in false })
    mail.setEnabled(true)
    notes.setEnabled(true)
    await expectFailure(code: "permission_denied") { try await mail.accounts() }
    await expectFailure(code: "permission_denied") { try await notes.accounts() }
    #expect(runner.calls.isEmpty)
  }

  @Test @MainActor func nativeAdaptersMapResultsAndEnforcePermissionBeforeRunner() async throws {
    let runner = FixtureScriptRunner()
    let mail = NativeMail(runner: runner, permissionCheck: { _ in true })
    let notes = NativeNotes(runner: runner, permissionCheck: { _ in true })
    await expectFailure { try await mail.accounts() }
    await expectFailure { try await notes.accounts() }
    #expect(runner.calls.isEmpty)
    mail.setEnabled(true)
    notes.setEnabled(true)
    runner.result = .list([.list([.text("account"), .text("Fixture")])])
    #expect(try await mail.accounts().accounts.first?.id == "account")
    #expect(try await notes.accounts().accounts.first?.name == "Fixture")
    let target = MailboxTarget(accountID: "account", path: ["Inbox", "Has/slash", "quote\"\\"])
    let restored = try MailboxTarget(id: target.id)
    #expect(restored.path == target.path)
    runner.result = .list([
      .text("12"), .text("Subject|\nsecond"), .text("Sender"), .text("2026-10-04T00:00:00Z"),
      .boolean(false), .boolean(true), .text("body"), .boolean(true), .boolean(true),
    ])
    let message = try await mail.get(id: "12", target: target, maxCharacters: 4)
    #expect(message.body == "body" && message.bodyTruncated == true && message.flagged)
    #expect(runner.calls.last?.arguments == target.arguments + [.text("12"), .integer(4)])
    runner.result = .list([
      .text("note"), .text("folder"), .text("Title"), .text("2026-10-04T00:00:00Z"),
      .boolean(false), .boolean(false), .text("<div>Title</div>"), .text("Title"), .boolean(false),
      .boolean(true),
    ])
    _ = try await notes.create(folderID: "folder", title: "<b>literal</b>", body: "&\nline")
    #expect(
      runner.calls.last?.arguments == [
        .text("folder"), .text("<div>&lt;b&gt;literal&lt;/b&gt;</div><div>&amp;<br>line</div>"),
      ])
    runner.result = .boolean(true)
    #expect(try await notes.delete(id: "note").deleted)
    runner.error = ToolFailure("timeout", "Read back before retrying.")
    let before = runner.calls.count
    await expectFailure { try await mail.delete(id: "12", target: target) }
    #expect(runner.calls.count == before + 1)
  }

  @Test @MainActor func mailAndNotesValidateAndHonorToolSwitches() async throws {
    let runner = FixtureScriptRunner()
    let mail = NativeMail(runner: runner, permissionCheck: { _ in true })
    mail.setEnabled(true)
    let notes = NativeNotes(runner: runner, permissionCheck: { _ in true })
    notes.setEnabled(true)
    let dispatcher = ToolDispatcher(modules: [MailTools(access: mail), NoteTools(access: notes)])
    let mailboxID = try MailboxTarget(accountID: "account", path: ["Inbox"]).id
    let other = try MailboxTarget(accountID: "other", path: ["Inbox"]).id
    let invalid: [(String, JSONDictionary)] = [
      ("mail_fetch", ["mailboxID": "bad"]),
      ("mail_fetch", ["mailboxID": .string(mailboxID), "limit": 201]),
      ("mail_get", ["mailboxID": .string(mailboxID), "id": "12 OR 1"]),
      ("mail_edit", ["mailboxID": .string(mailboxID), "id": "12"]),
      (
        "mail_move",
        ["mailboxID": .string(mailboxID), "id": "12", "destinationMailboxID": .string(other)]
      ),
      ("mail_mailbox_create", ["accountID": "account", "name": "a/b"]),
      ("notes_create", ["folderID": "folder", "title": " "]),
      ("notes_edit", ["id": "note", "bodyHTML": .null]),
      ("notes_edit", ["id": "note", "bodyHTML": .string(String(repeating: "x", count: 16385))]),
      ("notes_append", ["id": "note", "text": ""]),
      ("notes_fetch", ["folderID": "folder", "unknown": true]),
    ]
    for (name, args) in invalid {
      await expectFailure { try await dispatcher.call(name, arguments: args) }
    }
    #expect(runner.calls.isEmpty)
    runner.result = .boolean(true)
    await dispatcher.setDisabledTools(["notes_delete", "mail_delete"])
    #expect(await !dispatcher.tools().contains { $0.name == "notes_delete" })
    await expectFailure { try await dispatcher.call("notes_delete", arguments: ["id": "note"]) }
    await expectFailure {
      try await dispatcher.call(
        "mail_delete", arguments: ["id": "12", "mailboxID": .string(mailboxID)])
    }
    #expect(runner.calls.isEmpty)
    await dispatcher.setDisabledTools([])
    _ = try await dispatcher.call("notes_delete", arguments: ["id": "note"])
    #expect(runner.calls.count == 1)
    notes.setEnabled(false)
    mail.setEnabled(false)
    #expect(await dispatcher.tools().map(\.name) == ["connection_check"])
  }
}

private actor ScriptExecutionGate {
  var started = false
  private var released = false
  private var continuation: CheckedContinuation<Void, Never>?
  func run() async -> ScriptValue {
    started = true
    if !released { await withCheckedContinuation { continuation = $0 } }
    return .list([])
  }
  func finish() {
    released = true
    continuation?.resume()
    continuation = nil
  }
}
