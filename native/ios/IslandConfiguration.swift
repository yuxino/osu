import Foundation

// Sent only over the authenticated loopback connection, never persisted or logged.
// The broadcast extension creates and owns its own Live Activity, so no activity
// identifier crosses the process boundary.
struct IslandConfiguration: Codable {
  let key: String
  let credential: String
  let source: String
  let target: String
  let showsOriginal: Bool

  static func decode(_ data: Data, key: String) throws -> Self {
    let value = try JSONDecoder().decode(Self.self, from: data)
    guard value.key == key,
          (8...512).contains(value.credential.utf8.count),
          value.credential.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }),
          AlibabaProtocol.valid(source: value.source, target: value.target) else { throw Failure.invalid }
    return value
  }
  enum Failure: Error { case invalid }
}

// Bound UTF-8 bytes, not grapheme count: emoji can use many bytes per character.
func islandText(_ text: String) -> String {
  var result = ""
  let cleaned = String(text.unicodeScalars.filter { $0.value >= 32 || $0.value == 10 })
  for character in cleaned {
    guard result.utf8.count + String(character).utf8.count <= 600 else { break }
    result.append(character)
  }
  return result
}
