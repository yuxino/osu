import Foundation

struct AudioPacket {
  let audio: Data?
  let event: String?
  let dropped: Double
  let conversionFailures: Double
}
struct AudioPacketDecoder {
  enum Failure: Error { case oversized, invalid }
  private var bytes = Data()
  let key: String
  init(key: String) { self.key = key }
  mutating func append(_ data: Data) throws -> [AudioPacket] {
    bytes.append(data)
    guard bytes.count <= 65536 else { throw Failure.oversized }
    var packets: [AudioPacket] = []
    while let end = bytes.firstIndex(of: 10) {
      let line = bytes.prefix(upTo: end); bytes.removeSubrange(...end)
      guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], object["key"] as? String == key else { throw Failure.invalid }
      let event = object["event"] as? String
      if let event, !["started", "heartbeat", "paused", "resumed", "conversion_failed"].contains(event) { throw Failure.invalid }
      var audio: Data?
      if let encoded = object["audio"] as? String {
        guard let raw = Data(base64Encoded: encoded), !raw.isEmpty, raw.count <= 32768, raw.count % 2 == 0 else { throw Failure.invalid }
        audio = raw
      }
      guard event != nil || audio != nil else { throw Failure.invalid }
      let dropped = object["dropped"] as? Double ?? 0, failures = object["conversionFailures"] as? Double ?? 0
      guard dropped.isFinite, failures.isFinite, dropped >= 0, failures >= 0 else { throw Failure.invalid }
      packets.append(.init(audio: audio, event: event, dropped: dropped, conversionFailures: failures))
    }
    return packets
  }
}
