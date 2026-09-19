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

let setup = try JSONSerialization.jsonObject(with: Data(AlibabaProtocol.setup(source: "ja", target: "zh").utf8)) as! [String: Any]
let sessionConfig = setup["session"] as! [String: Any]
check(sessionConfig["sample_rate"] as? Int == 16000 && sessionConfig["modalities"] as? [String] == ["text"], "Mimi cloud session requests 16k text-only output")
check((sessionConfig["input_audio_transcription"] as? [String: Any])?["language"] as? String == "ja", "Japanese cloud source hint matches Mimi")
let auto = try JSONSerialization.jsonObject(with: Data(AlibabaProtocol.setup(source: "auto", target: "zh").utf8)) as! [String: Any]
check(((auto["session"] as? [String: Any])?["input_audio_transcription"] as? [String: Any])?["language"] == nil, "automatic recognition omits language hint")
check(!AlibabaProtocol.valid(source: "ja", target: "ja") && !AlibabaProtocol.valid(source: "unsupported", target: "zh"), "invalid cloud selections rejected")
let draft = try AlibabaProtocol.decode(Data("{\"type\":\"conversation.item.input_audio_transcription.text\",\"item_id\":\"one\",\"text\":\"今日\",\"stash\":\"は\"}".utf8))
check(draft == .source("今日は", "one", false), "cloud drafts replace confirmed text plus stash")
check(try AlibabaProtocol.decode(Data("{\"type\":\"error\",\"error\":{\"code\":\"SECRET_KEY\",\"message\":\"SECRET_TRANSCRIPT\"}}".utf8)) == .failure(.service), "cloud error messages and arbitrary codes are discarded")
var audioQueue = BoundedAudioQueue()
try audioQueue.append(Data(repeating: 0, count: 32000)); try audioQueue.append(Data(repeating: 0, count: 32000))
var overflow = false; do { try audioQueue.append(Data([0, 0])) } catch { overflow = true }
check(overflow && audioQueue.bytes == 64000, "cloud queue bounded at two seconds PCM")
_ = audioQueue.next(); check(audioQueue.bytes == 32000, "cloud queue accounts for dequeued audio")
audioQueue.clear(); check(audioQueue.bytes == 0 && audioQueue.next() == nil, "stop discards buffered audio")
var preview = CloudPreviewGate()
check(preview.accept(id: "utterance1", final: false) && preview.accept(id: "utterance1", final: true), "cloud draft and final accepted")
check(!preview.accept(id: "utterance1", final: false) && !preview.accept(id: "utterance1", final: true), "late drafts and duplicate finals cannot replace final")
check(preview.accept(id: "utterance2", final: true), "repeated text in a new utterance is not globally suppressed")
print("Alibaba protocol checks passed.")

var capture = CaptureReadiness()
check(capture.state(at: 0) == .idle, "new capture never trusts a previous running snapshot")
capture.start(); check(capture.state(at: 0) == .preparing, "preparing is distinct from capturing")
capture.receiverReady(); check(capture.state(at: 1) == .needsBroadcast, "ready listener still requires user broadcast authorization")
capture.connectionStarted(); check(capture.state(at: 2) == .connecting, "unauthenticated connection is not receiving")
capture.connectionReady(at: 3); check(capture.state(at: 3) == .waitingForAudio, "broadcast connection alone does not imply audio")
capture.audio(peak: 0, at: 4); check(capture.state(at: 4) == .silent, "silent PCM is not confused with missing broadcast")
capture.audio(peak: 0.1, at: 5); check(capture.state(at: 5) == .receiving, "audible PCM marks active reception")
capture.audio(peak: 0, at: 6); check(capture.state(at: 6) == .receiving, "a brief speech pause does not flicker to silence")
capture.audio(peak: 0, at: 10); check(capture.state(at: 10) == .silent, "sustained silence shown after hold period")
capture.heartbeat(at: 16); check(capture.state(at: 16) == .waitingForAudio, "live heartbeat without PCM remains connected")
capture.setPaused(true, at: 17); check(capture.state(at: 17) == .paused, "broadcast pause is explicit")
capture.setPaused(false, at: 18); check(capture.state(at: 18) == .waitingForAudio, "resume does not invent audio")
check(capture.state(at: 25) == .lost, "missing heartbeat expires stale connection")
capture.stop(); check(capture.state(at: 25) == .stopped, "stopped broadcast immediately clears connection")
capture.start(); capture.receiverReady(); check(capture.state(at: 26) == .needsBroadcast, "new session cannot reuse old permission or audio evidence")

var backlog = PCMBacklog(), referencePCM = Data(), deliveredPCM = Data()
// Uneven ReplayKit chunks plus a 400 ms slow consumer; compare every byte, not just counts.
for index in 0..<4000 {
  let chunk = Data((0..<(index % 3 + 1) * 232).map { UInt8(($0 + index) % 256) })
  try backlog.append(chunk); referencePCM.append(chunk)
  if index % 20 == 19 { while let batch = backlog.take() { deliveredPCM.append(batch) } }
}
while let batch = backlog.take() { deliveredPCM.append(batch) }
check(deliveredPCM == referencePCM, "4000 variable audio chunks survive simulated backpressure byte for byte")
try backlog.append(Data(repeating: 1, count: 64000))
do { try backlog.append(Data([2, 3])); check(false, "PCM overflow must throw") } catch {}
check(backlog.count == 64000, "overflow neither corrupts nor silently replaces queued audio")
backlog.clear(); check(backlog.take() == nil, "stopping clears pending PCM")
let delivery = PCMDeliveryBuffer()
var delivered = Data()
var scheduledOnce = true
for index in 0..<60 {
  let result = delivery.append(Data(repeating: UInt8(index), count: 800))
  scheduledOnce = scheduledOnce && (index == 0 ? result == .schedule : result == .buffered)
}
check(scheduledOnce, "main queue gets only one scheduled drain under backpressure")
while let chunk = delivery.next() { delivered.append(chunk) }
check(delivered == (0..<60).reduce(into: Data()) { $0.append(Data(repeating: UInt8($1), count: 800)) }, "busy main thread retains 1.5 seconds in correct order")
check(delivery.append(Data([1, 2])) == .schedule, "drain re-arms after empty queue")
delivery.cancel(); check(delivery.next() == nil && delivery.append(Data([3, 4])) == .closed, "cancel prevents stale-session audio delivery")
let overloaded = PCMDeliveryBuffer(); _ = overloaded.append(Data(repeating: 0, count: 64000))
check(overloaded.append(Data([0, 0])) == .overflow && overloaded.next() == nil, "host overflow is explicit and bounded")
var heartbeatParser = AudioPacketDecoder(key: "test-key")
check(try heartbeatParser.append(packet(["key": "test-key", "event": "heartbeat"]))[0].event == "heartbeat", "broadcast heartbeat needs no audio payload")

let defaultsName = "Osu.Tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: defaultsName)!
defer { defaults.removePersistentDomain(forName: defaultsName) }
defaults.set("apple", forKey: "mimi.engine"); defaults.set("en-US", forKey: "mimi.source")
SubtitleDefaults.migrate(defaults)
check(defaults.string(forKey: "mimi.engine") == "alibaba" && defaults.string(forKey: "mimi.alibaba.source") == "auto" && defaults.string(forKey: "mimi.alibaba.target") == "zh", "old English demo default migrates to automatic recognition and Chinese subtitles")
defaults.set("ja", forKey: "mimi.alibaba.source"); SubtitleDefaults.migrate(defaults)
check(defaults.string(forKey: "mimi.alibaba.source") == "ja", "deliberate manual override survives subsequent launches")
check(LanguageSelection(source: "zh-CN", target: "zh-Hans").localSelection.target.isEmpty, "same-language Apple selection becomes original-only instead of unsupported")
check(LanguageSelection(source: "ja-JP", target: "zh-Hans").localSelection.target == "zh-Hans", "different source and target retain translation")
print("Capture, buffering and automatic-language checks passed.")

var lyrics = LyricTrack()
check(!lyrics.update("今天", id: "a", final: false), "first lyric does not animate from a placeholder")
check(!lyrics.update("今天天气很好。", id: "a", final: true) && lyrics.previous == nil, "partial revisions stay on one lyric line")
check(lyrics.update("我们出发吧。", id: "b", final: false) && lyrics.previous?.text == "今天天气很好。", "a new utterance advances the previous line")
check(!lyrics.update("迟到的旧句", id: "a", final: false) && lyrics.current?.id == "b", "late old events cannot replace the current lyric")
lyrics.update("我们出发吧。", id: "b", final: true)
check(lyrics.update("我们出发吧。", id: "c", final: false), "identical words in a different utterance still advance")
check(!lyrics.update("更早的结果", id: "a", final: true) && lyrics.current?.id == "c", "retired utterances cannot roll the display backwards")
lyrics.update(String(repeating: "字幕", count: 1000), id: "c", final: true)
check(lyrics.current?.text.count == 400, "live lyric text stays bounded")
lyrics = LyricTrack()
check(lyrics.current == nil && lyrics.previous == nil, "restart clears previous-session lyric history")
lyrics.update("无编号首句", id: "", final: true)
check(!lyrics.update("无编号后续句", id: "", final: true) && lyrics.current?.text == "无编号后续句", "missing IDs degrade to live text instead of freezing after a final")
