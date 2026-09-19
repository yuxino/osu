import UIKit

// Exercise real timer-driven frame submission after an actual system preference
// change. A forced painter progress value would not verify Reduce Motion.
@MainActor enum MotionFixture {
  static func run(in view: UIView, reduced: Bool, completion: @escaping (Bool, String) -> Void) {
    let picture = SubtitlePicture()
    view.backgroundColor = .systemBackground
    let title = UILabel(frame: CGRect(x: 24, y: 90, width: view.bounds.width - 48, height: 44))
    title.text = "字幕动画检查"; title.font = .preferredFont(forTextStyle: .title2); view.addSubview(title)
    picture.preview.frame = CGRect(x: 24, y: 160, width: view.bounds.width - 48, height: (view.bounds.width - 48) * LyricsPainter.aspect)
    view.addSubview(picture.preview); picture.layout()
    picture.resetLyrics(original: "The first sentence.", translated: "第一句字幕。")
    picture.updateOriginal("The first sentence.", id: "first", final: true)
    picture.updateTranslation("第一句字幕。", id: "first", final: true)
    Task { @MainActor in
      let actual = UIAccessibility.isReduceMotionEnabled
      guard actual == reduced else { completion(false, "motion_preference_does_not_match_requested_test"); return }
      picture.start()
      try? await Task.sleep(nanoseconds: 1_100_000_000)
      let before = picture.diagnostics["frames"] as? Int64 ?? 0, began = CACurrentMediaTime()
      picture.updateOriginal("The next sentence.", id: "next", final: true)
      picture.updateTranslation("下一句字幕。", id: "next", final: true)
      try? await Task.sleep(nanoseconds: 600_000_000)
      let delta = (picture.diagnostics["frames"] as? Int64 ?? 0) - before
      let elapsed = CACurrentMediaTime() - began
      picture.stop()
      let textVisible = picture.preview.accessibilityValue?.contains("下一句字幕。") == true
      let passed = before > 0 && elapsed < 1.5 && textVisible &&
        (reduced ? (1...4).contains(delta) : delta >= 8) &&
        picture.diagnostics["mediaCreated"] as? Bool == false
      let report: [String: Any] = ["passed": passed, "reduceMotion": actual, "transitionFrames": delta, "elapsed": elapsed, "currentTextRetained": textVisible, "timestamp": ISO8601DateFormatter().string(from: Date()), "scope": "Actual system preference and production frame timers on Simulator; authored text only. Does not establish real PiP or phone performance."]
      let file = DiagnosticStore.shared.directory.deletingLastPathComponent().appendingPathComponent(reduced ? "motion-reduced.json" : "motion-normal.json")
      do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic) }
      catch { completion(false, "motion_report_write_failed"); return }
      completion(passed, reduced ? "reduced_motion_skips_transition_burst" : "normal_motion_animates_new_line")
    }
  }
}
