import Foundation

/// Two visible lines and bounded retired IDs; never writes subtitle text to disk.
struct LyricTrack {
  struct Line: Equatable {
    let id: String
    var text: String
    var final: Bool
  }
  private(set) var current: Line?
  private(set) var previous: Line?
  private var retired: [String] = []

  /// Returns true only when a new utterance replaces the current one.
  @discardableResult mutating func update(_ text: String, id: String, final: Bool) -> Bool {
    let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(400))
    guard !text.isEmpty else { return false }
    // Without an upstream ID, show the latest text without inventing a boundary.
    if id.isEmpty { current = Line(id: "", text: text, final: false); previous = nil; return false }
    if current?.id == id {
      guard current?.final != true else { return false }
      current = Line(id: id, text: text, final: final); return false
    }
    if previous?.id == id {
      if previous?.final != true { previous = Line(id: id, text: text, final: final) }
      return false
    }
    guard !retired.contains(id) else { return false }
    if let old = previous { retired.append(old.id); retired = Array(retired.suffix(32)) }
    let advances = current != nil
    previous = current; current = Line(id: id, text: text, final: final)
    return advances
  }
}
