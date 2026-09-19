import UIKit

enum LyricsPainter {
  static let size = CGSize(width: 960, height: 440)
  static var aspect: CGFloat { size.height / size.width }

  static func draw(in context: CGContext, bounds: CGRect, previous: String, current: String, original: String, progress: CGFloat) {
    guard bounds.width > 0, bounds.height > 0 else { return }
    context.saveGState(); defer { context.restoreGState() }
    context.translateBy(x: bounds.minX, y: bounds.minY)
    context.scaleBy(x: bounds.width / size.width, y: bounds.height / size.height)
    context.setFillColor(UIColor.black.cgColor); context.fill(CGRect(origin: .zero, size: size))
    let p = max(0, min(1, progress)), ease = 1 - pow(1 - p, 3)
    let hasPrevious = !previous.isEmpty
    let currentY: CGFloat = original.isEmpty ? 84 : 112
    let currentHeight: CGFloat = original.isEmpty ? 272 : 168
    if hasPrevious {
      text(previous, rect: CGRect(x: 48, y: currentY + (24 - currentY) * ease, width: 864, height: currentHeight + (72 - currentHeight) * ease), fontSize: 60 - 26 * ease, weight: .medium, opacity: 1 - 0.64 * ease)
    }
    text(current, rect: CGRect(x: 48, y: currentY + (hasPrevious ? 68 * (1 - ease) : 0), width: 864, height: currentHeight), fontSize: 60, weight: .semibold, opacity: hasPrevious ? ease : 1)
    if !original.isEmpty {
      text(original, rect: CGRect(x: 48, y: 326, width: 864, height: 80), fontSize: 32, weight: .regular, opacity: 0.58)
    }
  }

  private static func text(_ value: String, rect: CGRect, fontSize: CGFloat, weight: UIFont.Weight, opacity: CGFloat) {
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byWordWrapping; paragraph.lineSpacing = 8
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
