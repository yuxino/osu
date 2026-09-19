import UIKit
import ReplayKit

/// ReplayKit owns consent and has no public cancellation callback.
/// Cancelling its panel leaves the home screen ready to retry or cancel locally.
final class SystemBroadcastPicker {
  private let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))

  func attach(to view: UIView) {
    picker.preferredExtension = "com.yuxino.osu.MimiBroadcast"
    picker.showsMicrophoneButton = false
    picker.alpha = 0.01
    picker.isUserInteractionEnabled = false
    picker.accessibilityElementsHidden = true
    view.insertSubview(picker, at: 0)
  }

  func present() -> Bool {
    guard picker.window != nil, let button = picker.subviews.compactMap({ $0 as? UIButton }).first else { return false }
    // Forward to the public UIKit control, without private ReplayKit selectors.
    button.sendActions(for: .touchUpInside)
    return true
  }
}
