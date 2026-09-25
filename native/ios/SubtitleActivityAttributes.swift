import ActivityKit
import Foundation

struct SubtitleActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var original: String
    var translated: String
    var status: String
    var showsOriginal: Bool
  }
  let sessionID: String
}
