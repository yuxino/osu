import Foundation

enum SubtitleEngine: String { case apple, alibaba }

enum AlibabaProtocol {
  static let endpoint = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=qwen3.5-livetranslate-flash-realtime")!
  static let sources = ["auto", "zh", "en", "ja", "ko"]
  static let targets = ["zh", "en", "ja"]
  enum Failure: Int, Error { case invalidConfiguration = 1, invalidEvent, oversized, authentication, quota, service, timeout, transport, overload }
  enum Event: Equatable {
    case ready, finished, ignored
    case source(String, String, Bool)
    case translation(String, String, Bool)
    case failure(Failure)
  }
  static func valid(source: String, target: String) -> Bool { sources.contains(source) && targets.contains(target) && source != target }
  static func json(_ object: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) }
  static func setup(source: String, target: String) throws -> String {
    guard valid(source: source, target: target) else { throw Failure.invalidConfiguration }
    var transcription: [String: Any] = ["model": "qwen3-asr-flash-realtime"]
    if source != "auto" { transcription["language"] = source }
    return try json(["event_id": UUID().uuidString, "type": "session.update", "session": ["modalities": ["text"], "sample_rate": 16000, "input_audio_format": "pcm", "input_audio_transcription": transcription, "translation": ["language": target]]])
  }
  static func finish() throws -> String { try json(["event_id": UUID().uuidString, "type": "session.finish"]) }
  static func audio(_ data: Data) throws -> String {
    guard !data.isEmpty, data.count <= 32768, data.count % 2 == 0 else { throw Failure.oversized }
    return try json(["event_id": UUID().uuidString, "type": "input_audio_buffer.append", "audio": data.base64EncodedString()])
  }
  static func decode(_ data: Data) throws -> Event {
    guard data.count <= 131072 else { throw Failure.oversized }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let type = object["type"] as? String else { throw Failure.invalidEvent }
    func text(_ key: String) throws -> String {
      let value = object[key] as? String ?? ""
      guard value.utf8.count <= 16384 else { throw Failure.oversized }
      return value
    }
    func identifier(_ key: String) throws -> String {
      let value = try text(key); guard value.utf8.count <= 128 else { throw Failure.oversized }; return value
    }
    func combined() throws -> String {
      let value = try text("text") + text("stash")
      guard value.utf8.count <= 16384 else { throw Failure.oversized }
      return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    switch type {
    case "session.updated": return .ready
    case "session.finished": return .finished
    case "conversation.item.input_audio_transcription.text": return .source(try combined(), try identifier("item_id"), false)
    case "conversation.item.input_audio_transcription.completed": return .source(try text("transcript"), try identifier("item_id"), true)
    case "response.text.text", "response.audio_transcript.text": return .translation(try combined(), try identifier("response_id"), false)
    case "response.text.done": return .translation(try text("text"), try identifier("response_id"), true)
    case "response.audio_transcript.done": return .translation(try text("transcript"), try identifier("response_id"), true)
    case "error", "conversation.item.input_audio_transcription.failed":
      let code = (object["error"] as? [String: Any])?["code"] as? String ?? ""
      if ["invalid_api_key", "InvalidApiKey", "Unauthorized", "AuthenticationError"].contains(code) { return .failure(.authentication) }
      if ["insufficient_quota", "Throttling", "RateLimitExceeded", "rate_limit_exceeded"].contains(code) { return .failure(.quota) }
      return .failure(.service) // Never expose arbitrary upstream messages or error codes.
    default: return .ignored
    }
  }
}

// Realtime captions must never die because a handshake was slow. The queue
// holds the newest two seconds of PCM; overflow drops the oldest audio (it has
// already played) instead of failing the session.
struct BoundedAudioQueue {
  static let capacity = 64000
  private(set) var bytes = 0
  private var chunks: [Data] = []
  mutating func append(_ data: Data) {
    guard !data.isEmpty, data.count % 2 == 0, data.count <= 32768, data.count <= Self.capacity else { return }
    chunks.append(data); bytes += data.count
    while bytes > Self.capacity, !chunks.isEmpty {
      bytes -= chunks.removeFirst().count
    }
    while chunks.count > 256, !chunks.isEmpty {
      bytes -= chunks.removeFirst().count
    }
  }
  mutating func next() -> Data? { guard !chunks.isEmpty else { return nil }; let data = chunks.removeFirst(); bytes -= data.count; return data }
  mutating func clear() { chunks.removeAll(); bytes = 0 }
}

struct CloudPreviewGate {
  private var finals: [String] = []
  mutating func accept(id: String, final: Bool) -> Bool {
    guard !id.isEmpty else { return true }
    guard !finals.contains(id) else { return false }
    if final { finals.append(id); if finals.count > 32 { finals.removeFirst() } }
    return true
  }
}
