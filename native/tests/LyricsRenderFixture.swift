import UIKit

// Fixed authored text rendered by the production painter. Pixel checks catch
// text that measures too tall and disappears, including at accessibility sizes.
@MainActor enum LyricsRenderFixture {
  static func run() -> (Bool, String) {
    let directory = DiagnosticStore.shared.directory.deletingLastPathComponent().appendingPathComponent("lyrics-layout", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var rows: [[String: Any]] = []
      let picture = SubtitlePicture()
      picture.resetLyrics(original: "Source text", translated: "只显示译文")
      let hiddenByDefault = !picture.showsOriginal && picture.preview.accessibilityValue == "只显示译文"
      picture.showsOriginal = true
      let visibleWhenEnabled = picture.preview.accessibilityValue == "Source text\n只显示译文"
      picture.showsOriginal = false
      picture.resetLyrics(original: "仅原文仍可阅读", translated: "", translationEnabled: false)
      let originalOnlyReadable = picture.preview.accessibilityValue == "仅原文仍可阅读"
      let hasCharacter = Bundle.main.url(forResource: "mimi-maid-v1", withExtension: "png") != nil
      var passed = hiddenByDefault && visibleWhenEnabled && originalOnlyReadable && hasCharacter
      let category = UIApplication.shared.preferredContentSizeCategory
      let name = category.isAccessibilityCategory ? "largest" : "regular"
      for (long, showsOriginal) in [(false, true), (true, true), (false, false), (true, false)] {
        let label = name + (long ? "-long" : "-short") + (showsOriginal ? "" : "-translation-only")
        let previous = long ? "前一句有些长，但读完之后仍应留下一行，让人能接着看懂。" : "上一句仍然可见"
        let current = long ? String(repeating: "今天我们继续看日语视频，字幕会跟着声音出现，不需要停留在应用里。", count: 5) : "字幕跟着声音出现。"
        let sourceText = long ? "You can keep watching the video in its original app while the translated lyrics appear above it. " + String(repeating: "The next sentence arrives shortly. ", count: 3) : "Keep watching in your video app."
        let original = showsOriginal ? sourceText : ""
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: LyricsPainter.size, format: format)
        let image = renderer.image { context in
          LyricsPainter.draw(in: context.cgContext, bounds: CGRect(origin: .zero, size: LyricsPainter.size), previous: previous, current: current, original: original, progress: 1)
        }
        try? image.pngData()?.write(to: directory.appendingPathComponent(label + ".png"))
        let prior = visiblePixels(image, in: CGRect(x: 48, y: 20, width: 644, height: 76))
        let active = visiblePixels(image, in: CGRect(x: 48, y: 120, width: 864, height: 178))
        let source = visiblePixels(image, in: showsOriginal ? CGRect(x: 48, y: 334, width: 864, height: 80) : CGRect(x: 48, y: 398, width: 864, height: 28))
        let character = visiblePixels(image, in: CGRect(x: 752, y: 28, width: 64, height: 64))
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
        let visible = prior > 100 && active > 100 && character > 100 && (showsOriginal ? source > 100 : source == 0)
        passed = passed && visible
        rows.append(["case": label, "showsOriginal": showsOriginal, "previousPixels": prior, "currentPixels": active, "originalPixels": source, "characterPixels": character, "scaledPreviousFont": UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 30), maximumPointSize: 45).pointSize, "medianRenderMS": durations[15], "p95RenderMS": durations[28], "visible": visible])
        if !showsOriginal {
          for progress: CGFloat in [0, 0.25, 0.5] {
            let frame = renderer.image { context in
              LyricsPainter.draw(in: context.cgContext, bounds: CGRect(origin: .zero, size: LyricsPainter.size), previous: previous, current: current, original: "", progress: progress)
            }
            try? frame.pngData()?.write(to: directory.appendingPathComponent(label + "-transition-\(Int(progress * 100)).png"))
          }
          let smallSize = CGSize(width: 240, height: 110)
          let small = UIGraphicsImageRenderer(size: smallSize, format: format).image { context in
            LyricsPainter.draw(in: context.cgContext, bounds: CGRect(origin: .zero, size: smallSize), previous: previous, current: current, original: "", progress: 1)
          }
          try? small.pngData()?.write(to: directory.appendingPathComponent(label + "-small.png"))
        }
      }
      let document: [String: Any] = ["cases": rows, "category": category.rawValue, "passed": passed, "hasCharacter": hasCharacter, "hiddenByDefault": hiddenByDefault, "visibleWhenEnabled": visibleWhenEnabled, "originalOnlyReadable": originalOnlyReadable, "scope": "Fixed text, production CoreGraphics painter; simulator timings are not phone performance", "timestamp": ISO8601DateFormatter().string(from: Date())]
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
