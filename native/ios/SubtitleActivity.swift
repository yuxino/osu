import ActivityKit
import Foundation

// Legacy cleanup: earlier experimental builds created the Live Activity in the
// host process. End any leftovers at launch. Island sessions now belong to the
// broadcast extension, whose activities the host cannot see or end.
@MainActor final class SubtitleActivity {
  init() {
    let abandoned = Activity<SubtitleActivityAttributes>.activities
    Task { for activity in abandoned { await activity.end(nil, dismissalPolicy: .immediate) } }
  }
}
