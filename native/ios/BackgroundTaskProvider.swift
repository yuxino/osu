import UIKit

// The simulator harness can expire or deny a task without changing system state.
@MainActor struct BackgroundTaskProvider {
  typealias ExpirationHandler = @MainActor @Sendable () -> Void
  let begin: (String, @escaping ExpirationHandler) -> UIBackgroundTaskIdentifier
  let end: (UIBackgroundTaskIdentifier) -> Void

  static let application = BackgroundTaskProvider(
    begin: { UIApplication.shared.beginBackgroundTask(withName: $0, expirationHandler: $1) },
    end: { UIApplication.shared.endBackgroundTask($0) }
  )
}
