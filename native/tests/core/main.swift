import Foundation

func check(_ condition: Bool, _ name: String) {
  guard condition else { fatalError("FAIL: \(name)") }; print("PASS: \(name)")
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("mimi-tests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let journal = DiagnosticStore(directory: root.appendingPathComponent("logs"), maxBytes: 1024, fileCount: 3)
journal.begin(source: "ja-JP", target: "zh-Hans")
let session = journal.sessionID
journal.record("speech", "failed", metrics: ["audioFrames": 3, "secret": 55, "peak": .nan], error: NSError(domain: "private-transcript-secret", code: 42, userInfo: [NSLocalizedDescriptionKey: "SECRET_TEXT", "audio": "SECRET_AUDIO"]))
let report = journal.report()
check(!report.contains("SECRET") && !report.contains("private-transcript") && !report.contains("secret"), "error descriptions and unknown fields are not logged")
check(report.contains("42") && report.contains("timestamp") && report.contains(session), "error code, time and session identity survive")
journal.snapshot(running: true, pip: true, metrics: ["audioFrames": 3])
check(journal.previousWasRunning(), "unfinished session detected")
let reopened = DiagnosticStore(directory: root.appendingPathComponent("logs"), maxBytes: 1024, fileCount: 3)
check(reopened.previousWasRunning() && reopened.sessionID == session, "relaunch recovers the interrupted session identity")
journal.snapshot(running: false, pip: false, metrics: [:])
check(!journal.previousWasRunning(), "stopped snapshot replaces active state")
journal.begin(source: "en-US", target: "none")
check(journal.sessionID != session, "new sessions have distinct IDs")
for i in 0..<100 { journal.record("session", "counters", metrics: ["audioFrames": Double(i)]) }
let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("logs"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }
check(files.count <= 3, "bounded journal file count")
for url in files {
  let data = try Data(contentsOf: url); check(data.count <= 1024, "bounded journal size")
  for line in String(decoding: data, as: UTF8.self).split(separator: "\n") { _ = try JSONSerialization.jsonObject(with: Data(line.utf8)) }
}
let export = try journal.export()
check(try String(contentsOf: export, encoding: .utf8).contains("99"), "export includes most recent counters")
check(!PairReadiness.needsDownload.canStart && !PairReadiness.unsupported.canStart && !PairReadiness.checking.canStart && !PairReadiness.requiresNewerOS.canStart, "unsupported/unprepared pairs cannot start")
check(PairReadiness.installed.canStart && PairReadiness.transcriptionOnly.canStart, "ready and explicit original-only modes can start")
check(LanguageSelection.identifier(Locale.Language(identifier: "zh-Hans")) != LanguageSelection.identifier(Locale.Language(identifier: "zh-Hant")), "Chinese script variants remain distinct")
check(LanguageSelection(source: "ja-JP", target: "").targetLanguage == nil, "no implicit auto-target in original-only mode")
var decoder = AudioPacketDecoder(key: "test-key")
func packet(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) + Data([10]) }
let valid = try packet(["key": "test-key", "audio": Data([0, 1, 2, 3]).base64EncodedString(), "dropped": 2])
check(try decoder.append(valid.prefix(5)).isEmpty, "split packet waits for remainder")
let decoded = try decoder.append(valid.dropFirst(5))
check(decoded.count == 1 && decoded[0].audio == Data([0, 1, 2, 3]) && decoded[0].dropped == 2, "chunked PCM and counters decoded intact")
for bad in [try packet(["key": "wrong", "audio": "AAE="]), try packet(["key": "test-key", "audio": "AA=="]), try packet(["key": "test-key", "event": "SECRET_TEXT"]), Data(repeating: 65, count: 65537)] {
  var rejected = false; var parser = AudioPacketDecoder(key: "test-key")
  do { _ = try parser.append(bad) } catch { rejected = true }
  check(rejected, "unauthorized, malformed or oversized packet rejected")
}
print("All native core checks passed.")

check(LanguageSelection.identifier(Locale.Language(identifier: "zh-CN")) == "zh-Hans", "system Chinese locale matches the saved simplified target")
