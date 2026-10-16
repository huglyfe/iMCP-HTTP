import Foundation
import OSAKit
import Testing

@testable import IMCPCore

@Suite(.serialized)
struct ScriptExecutionTests {
  @Test func scriptBoundaryKeepsHostileTextAsDataAndPreservesTypes() throws {
    let values: [ScriptValue] = [
      .text("\" & do shell script \"false\" --\n\\ quotes | 😀"), .boolean(true), .integer(123),
      .list([.text(""), .boolean(false)]),
    ]
    let result = try AutomationRunner.evaluate(
      source: "on dispatch(operation, args)\nreturn args\nend dispatch", operation: "fixture",
      arguments: values)
    #expect(try result.array() == values)
  }

  @Test func interpreterDeadlineInterruptsAnInfiniteLoop() throws {
    // An interpreter loop must be interrupted by the host deadline without sending any Apple events.
    do {
      _ = try AutomationRunner.evaluate(
        source: "on dispatch(operation,args)\nrepeat\nset x to 1\nend repeat\nend dispatch",
        operation: "fixture", arguments: [], timeout: .milliseconds(20))
      Issue.record("Expected script deadline")
    } catch { #expect((error as? ToolFailure)?.code == "timeout") }
  }

  @Test func noteAppendPreservesBodyClosingTagAndFragments() throws {
    let notesSource = try AutomationRunner.source(for: .notes)
    let appendStart = try #require(notesSource.range(of: "on appendHTML("))
    let appendEnd = try #require(notesSource.range(of: "end appendHTML"))
    let helper = String(notesSource[appendStart.lowerBound..<appendEnd.upperBound])
    let harness =
      helper
      + "\non dispatch(operation,args)\nreturn my appendHTML(item 1 of args, item 2 of args)\nend dispatch"
    let appended = try AutomationRunner.evaluate(
      source: harness, operation: "fixture",
      arguments: [.text("<html><body>keep</BODY></html>"), .text("<div>added</div>")])
    #expect(try appended.string() == "<html><body>keep<div>added</div></BODY></html>")
    let fragment = try AutomationRunner.evaluate(
      source: harness, operation: "fixture",
      arguments: [.text("<div>keep</div>"), .text("<div>added</div>")])
    #expect(try fragment.string() == "<div>keep</div><div>added</div>")

  }

  @Test func noteRecordUsesKnownFolderWithoutReadingContainer() throws {
    let source = try AutomationRunner.source(for: .notes)
    let start = try #require(source.range(of: "on noteRecord("))
    let end = try #require(source.range(of: "end noteRecord"))
    // Use Notes terminology with a local record, never send Apple events. The
    // fixture deliberately has no container property, like the failing shared note.
    let helper = String(source[start.lowerBound..<end.upperBound])
      .replacingOccurrences(of: "tell application", with: "using terms from application")
      .replacingOccurrences(of: "end tell", with: "end using terms from")
    let harness =
      helper + """

        on dispatch(operation, args)
          using terms from application id "com.apple.Notes"
            set target to {id:"fixture-note", name:"Shared fixture", modification date:current date, password protected:true, shared:true}
          end using terms from
          return my noteRecord(target, "fixture-folder", 100)
        end dispatch
        """
    let result = try AutomationRunner.evaluate(source: harness, operation: "fixture", arguments: [])
    let fields = try result.array(10)
    #expect(try fields[0].string() == "fixture-note")
    #expect(try fields[1].string() == "fixture-folder")
    #expect(try fields[4].bool())
    #expect(try fields[5].bool())
    #expect(try !fields[9].bool())
  }

  @Test func mailEditReadbackFailureIsUncertainAfterMutation() throws {
    let source = try AutomationRunner.source(for: .mail)
    let start = try #require(source.range(of: "    if operation is \"edit\" then"))
    let end = try #require(source.range(of: "    if operation is \"move\" then"))
    let branch = String(source[start.lowerBound..<end.lowerBound])
    let harness = """
      on messageRecord(msg, bodyLimit)
        error number -1728
      end messageRecord
      on dispatch(operation, args)
        using terms from application id "com.apple.mail"
          set msg to {read status:false, flagged status:false}
          try
            \(branch)
          on error messageValue number errorNumber
            return {errorNumber, read status of msg, flagged status of msg}
          end try
        end using terms from
      end dispatch
      """
    let result = try AutomationRunner.evaluate(
      source: harness, operation: "edit",
      arguments: [.text(""), .text(""), .text(""), .text("true"), .text("true")]
    ).array(3)
    #expect(try result[0].int() == 9005)
    #expect(try result[1].bool())
    #expect(try result[2].bool())
  }

  @Test func fixedScriptsCompileWithoutExecutingAppHandlers() throws {
    for app in [AutomationApp.mail, .notes] {
      let script = OSAScript(source: try AutomationRunner.source(for: app))
      var error: NSDictionary?
      #expect(script.compileAndReturnError(&error))
    }
  }

  @Test func scriptingErrorsAreSanitizedAndUncertainWritesAreExplicit() throws {
    for (number, code) in [
      (-1743, "permission_denied"), (-1712, "timeout"), (9001, "not_found"),
      (9005, "uncertain_outcome"), (-10000, "automation_failed"),
    ] {
      #expect(AutomationRunner.failure(number: number).code == code)
    }
    do {
      _ = try AutomationRunner.evaluate(
        source:
          "on dispatch(operation, args)\nerror \"private body and account\" number -10000\nend dispatch",
        operation: "fixture", arguments: [])
      Issue.record("Expected sanitized error")
    } catch {
      #expect(!error.localizedDescription.contains("private body"))
    }
  }

}
