import EventKit
import Foundation
import Testing

@testable import IMCPCore

struct ReminderCallbackTests {
  @Test @MainActor func backgroundCallbackSnapshotsBeforeReturningToMainActor() async {
    // Exercise the production completion on a real background queue with unsaved
    // EventKit values. No permission request, fetch, or save touches Apple data.
    let records: [ReminderRecord]? = await withCheckedContinuation { continuation in
      let completion = EventKitReminders.fetchCompletion(includeNotes: false) {
        MainActor.assertIsolated()
        continuation.resume(returning: $0)
      }
      DispatchQueue.global().async {
        let store = EKEventStore()
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = "Callback fixture"
        reminder.notes = "Omitted from summary"
        completion([reminder])
      }
    }
    #expect(records?.count == 1)
    #expect(records?.first?.title == "Callback fixture")
    #expect(records?.first?.notes == nil)
  }

  @Test @MainActor func callbackPreservesFailedVersusEmptyFetch() async {
    for failed in [false, true] {
      let records: [ReminderRecord]? = await withCheckedContinuation { continuation in
        let completion = EventKitReminders.fetchCompletion(includeNotes: true) {
          continuation.resume(returning: $0)
        }
        DispatchQueue.global().async { completion(failed ? nil : []) }
      }
      #expect(failed ? records == nil : records?.isEmpty == true)
    }
  }
}
