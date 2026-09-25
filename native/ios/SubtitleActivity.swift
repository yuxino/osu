import ActivityKit
import Foundation

// Retirement cleanup: dynamic island builds up to 17 created the Live Activity
// in the host process and could leave leftovers behind. End those at launch;
// the mode itself is retired (docs/dynamic-island-retirement.md).
@MainActor final class SubtitleActivity {
  init() {
    let abandoned = Activity<SubtitleActivityAttributes>.activities
    Task { for activity in abandoned { await activity.end(nil, dismissalPolicy: .immediate) } }
  }
}
