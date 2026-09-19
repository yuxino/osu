import UIKit

// Fixed authored text rendered by the production painter. Pixel checks catch
// text that measures too tall and disappears, including at accessibility sizes.
@MainActor enum LyricsRenderFixture {
  static func run() -> (Bool, String) {
    let directory = DiagnosticStore.shared.directory.deletingLastPathComponent().appendingPathComponent("lyrics-layout", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var rows: [[String: Any]] = []
      var passed = true
      let category = UIApplication.shared.preferredContentSizeCategory
      let name = category.isAccessibilityCategory ? "largest" : "regular"
      for long in [false, true] {
        let label = name + (long ? "-long" : "-short")
        let previous = long ? "前一句有些长，但读完之后仍应留下一行，让人能接着看懂。" : "上一句仍然可见"
        let current = long ? String(repeating: "今天我们继续看日语视频，字幕会跟着声音出现，不需要停留在应用里。", count: 5) : "字幕跟着声音出现。"
        let original = long ? "You can keep watching the video in its original app while the translated lyrics appear above it. " + String(repeating: "The next sentence arrives shortly. ", count: 3) : "Keep watching in your video app."
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: LyricsPainter.size, format: format)
        let image = renderer.image { context in
          LyricsPainter.draw(in: context.cgContext, bounds: CGRect(origin: .zero, size: LyricsPainter.size), previous: previous, current: current, original: original, progress: 1)
        }
        try? image.pngData()?.write(to: directory.appendingPathComponent(label + ".png"))
        let prior = visiblePixels(image, in: CGRect(x: 48, y: 20, width: 864, height: 85))
        let active = visiblePixels(image, in: CGRect(x: 48, y: 112, width: 864, height: 168))
        let source = visiblePixels(image, in: CGRect(x: 48, y: 326, width: 864, height: 80))
        var durations: [Double] = []
        for index in 0..<30 {
          let start = CACurrentMediaTime()
          autoreleasepool {
            _ = renderer.image { context in
              LyricsPainter.draw(in: context.cgContext, bounds: CGRect(origin: .zero, size: LyricsPainter.size), previous: previous, current: current, original: original, progress: CGFloat(index) / 29)
            }
          }
          durations.append((CACurrentMediaTime() - start) * 1000)
        }
        durations.sort()
        let visible = prior > 100 && active > 100 && source > 100
        passed = passed && visible
        rows.append(["case": label, "previousPixels": prior, "currentPixels": active, "originalPixels": source, "scaledPreviousFont": UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 34), maximumPointSize: 51).pointSize, "medianRenderMS": durations[15], "p95RenderMS": durations[28], "visible": visible])
      }
      let document: [String: Any] = ["cases": rows, "category": category.rawValue, "passed": passed, "scope": "Fixed text, production CoreGraphics painter; simulator timings are not phone performance", "timestamp": ISO8601DateFormatter().string(from: Date())]
      try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("result.json"), options: .atomic)
      return (passed, "lyrics_visibility_at_current_text_size")
    } catch { return (false, "lyrics_layout_export_failed") }
  }
  private static func visiblePixels(_ image: UIImage, in rect: CGRect) -> Int {
    guard let crop = image.cgImage?.cropping(to: rect), let data = crop.dataProvider?.data, let bytes = CFDataGetBytePtr(data), crop.bitsPerPixel == 32 else { return 0 }
    var count = 0
    for y in 0..<crop.height {
      for x in 0..<crop.width {
        let index = y * crop.bytesPerRow + x * 4
        if max(bytes[index], bytes[index + 1], bytes[index + 2]) > 30 { count += 1 }
      }
    }
    return count
  }
}
