import UIKit
import ImageIO

enum LyricsPainter {
  static let size = CGSize(width: 960, height: 440)
  static var aspect: CGFloat { size.height / size.width }
  // Decode the existing character once at its rendered size, not on each frame.
  static let character: UIImage? = {
    guard let url = Bundle.main.url(forResource: "mimi-maid-v1", withExtension: "png"),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 160,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
          ] as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
  }()

  static func draw(in context: CGContext, bounds: CGRect, previous: String, current: String, original: String, progress: CGFloat) {
    guard bounds.width > 0, bounds.height > 0 else { return }
    context.saveGState(); defer { context.restoreGState() }
    context.translateBy(x: bounds.minX, y: bounds.minY)
    context.scaleBy(x: bounds.width / size.width, y: bounds.height / size.height)
    context.setFillColor(UIColor(white: 0.035, alpha: 1).cgColor); context.fill(CGRect(origin: .zero, size: size))
    signature()
    context.setFillColor(UIColor(white: 1, alpha: 0.12).cgColor)
    context.fill(CGRect(x: 48, y: 108, width: 864, height: 1))
    let p = max(0, min(1, progress)), ease = 1 - pow(1 - p, 3)
    let hasPrevious = !previous.isEmpty
    let currentY: CGFloat = 118
    let currentHeight: CGFloat = original.isEmpty ? 272 : 180
    if hasPrevious {
      text(previous, rect: CGRect(x: 48, y: 24, width: 644, height: 72), fontSize: 30, weight: .regular, opacity: 0.46)
    }
    // Keep text in separate bands even when a long sentence changes. The new
    // line settles upward without overlapping the previous line or disappearing.
    text(current, rect: CGRect(x: 48, y: currentY + (hasPrevious ? 24 * (1 - ease) : 0), width: 864, height: currentHeight), fontSize: 66, weight: .medium, opacity: hasPrevious ? 0.56 + 0.44 * ease : 1)
    if !original.isEmpty {
      text(original, rect: CGRect(x: 48, y: 334, width: 864, height: 80), fontSize: 32, weight: .regular, opacity: 0.62)
    }
  }

  private static func signature() {
    character?.draw(in: CGRect(x: 752, y: 28, width: 64, height: 64))
    let base = UIFont.systemFont(ofSize: 40, weight: .semibold)
    let font = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 40) } ?? base
    ("Osu" as NSString).draw(at: CGPoint(x: 829, y: 35), withAttributes: [
      .font: font, .foregroundColor: UIColor(white: 0.9, alpha: 1), .kern: -0.5
    ])
  }

  private static func text(_ value: String, rect: CGRect, fontSize: CGFloat, weight: UIFont.Weight, opacity: CGFloat) {
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .left; paragraph.lineBreakMode = .byWordWrapping; paragraph.lineSpacing = 8
    let font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: fontSize, weight: weight), maximumPointSize: fontSize * 1.5)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(white: 1, alpha: opacity), .paragraphStyle: paragraph]
    let visible = String(value.suffix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !visible.isEmpty else { return }
    func height(of candidate: String) -> CGFloat {
      ceil((candidate as NSString).boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height)
    }
    func draw(_ candidate: String, height: CGFloat) {
      (candidate as NSString).draw(with: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
    }
    if value.count <= 400 {
      let measured = height(of: visible)
      if measured <= floor(rect.height) { draw(visible, height: measured); return }
    }

    // Keep the readable tail, trimming whole short words or one grapheme at a
    // time. Search the boundaries instead of shaping every discarded prefix
    // again on each animation frame (particularly expensive for long CJK text).
    var starts: [String.Index] = []
    var start = visible.startIndex
    while start < visible.endIndex {
      let wordLimit = visible.index(start, offsetBy: 32, limitedBy: visible.endIndex) ?? visible.endIndex
      if let split = visible[start..<wordLimit].firstIndex(where: { $0.isWhitespace }) {
        start = visible.index(after: split)
        while start < visible.endIndex, visible[start].isWhitespace { start = visible.index(after: start) }
      } else {
        start = visible.index(after: start)
      }
      if start < visible.endIndex { starts.append(start) }
    }
    var lower = 0, upper = starts.count
    var fitted: (text: String, height: CGFloat)?
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      let candidate = "… " + visible[starts[middle]...]
      let measured = height(of: candidate)
      if measured <= floor(rect.height) { fitted = (candidate, measured); upper = middle }
      else { lower = middle + 1 }
    }
    if let fitted { draw(fitted.text, height: fitted.height) }
  }
}
