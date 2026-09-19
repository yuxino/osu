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
    if hasPrevious {
      text(previous, rect: CGRect(x: 48, y: 112 - 82 * ease, width: 864, height: 156 - 108 * ease), fontSize: 60 - 26 * ease, weight: .medium, opacity: 1 - 0.64 * ease)
    }
    text(current, rect: CGRect(x: 48, y: 112 + (hasPrevious ? 68 * (1 - ease) : 0), width: 864, height: 168), fontSize: 60, weight: .semibold, opacity: hasPrevious ? ease : 1)
    if !original.isEmpty {
      text(original, rect: CGRect(x: 48, y: 326, width: 864, height: 80), fontSize: 32, weight: .regular, opacity: 0.58)
    }
  }

  private static func text(_ value: String, rect: CGRect, fontSize: CGFloat, weight: UIFont.Weight, opacity: CGFloat) {
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byWordWrapping; paragraph.lineSpacing = 8
    let font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: fontSize, weight: weight), maximumPointSize: fontSize * 1.5)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(white: 1, alpha: opacity), .paragraphStyle: paragraph]
    var visible = String(value.suffix(400)), clipped = value.count > 400
    func trimWord() {
      if let split = visible.firstIndex(where: { $0.isWhitespace }), visible.distance(from: visible.startIndex, to: split) < 32 {
        visible = String(visible[visible.index(after: split)...]).trimmingCharacters(in: .whitespacesAndNewlines)
      } else if !visible.isEmpty { visible.removeFirst() }
    }
    if clipped { trimWord() }
    while !visible.isEmpty {
      let candidate = clipped ? "… " + visible : visible
      let height = (candidate as NSString).boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height
      if ceil(height) <= floor(rect.height) {
        (candidate as NSString).draw(with: CGRect(x: rect.minX, y: rect.midY - ceil(height) / 2, width: rect.width, height: ceil(height)), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        return
      }
      trimWord(); clipped = true
    }
  }
}
