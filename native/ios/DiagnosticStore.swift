import Foundation

// No free-form messages: callers use fixed event names and numeric counters only.
final class DiagnosticStore {
  static let shared = DiagnosticStore()
  private let queue = DispatchQueue(label: "mimi.diagnostics")
  let directory: URL
  private let maxBytes: Int
  private let fileCount: Int
  private(set) var sessionID = UUID().uuidString
  private var sequence = 0
  private var storageFailed = false
  private let numericKeys: Set<String> = ["sourceFinals", "translationFinals", "cloudBytes", "audioFrames", "audioSeconds", "recognitionUpdates", "translationUpdates", "peak", "elapsed", "dropped", "conversionFailures", "translationMS", "audioGapSeconds", "recognitionRestarts", "code", "permission", "pip", "running", "foreground", "receivedBytes"]
  private let domains: Set<String> = ["kAFAssistantErrorDomain", "SFSpeechErrorDomain", "NSURLErrorDomain", "NSPOSIXErrorDomain", "NSCocoaErrorDomain", "AVFoundationErrorDomain", "Translation.TranslationError", "MimiPrototype"]

  init(directory: URL? = nil, maxBytes: Int = 131072, fileCount: Int = 6) {
    self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("MimiDiagnostics", isDirectory: true)
    self.maxBytes = max(1024, maxBytes); self.fileCount = max(2, fileCount)
    do {
      try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
      var url = self.directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
      try url.setResourceValues(values)
    } catch { storageFailed = true }
  }
  private func logURL(_ index: Int) -> URL { directory.appendingPathComponent("events-\(index).jsonl") }
  private func token(_ value: String) -> String {
    guard value.count <= 80, value.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil else { return "redacted" }
    return value
  }
  func begin(source: String, target: String) {
    queue.sync { sessionID = UUID().uuidString; sequence = 0 }
    record("session", "begin", source: source, target: target)
  }
  func record(_ stage: String, _ event: String, metrics: [String: Double] = [:], error: Error? = nil, source: String? = nil, target: String? = nil) {
    queue.sync {
      sequence += 1
      var object: [String: Any] = ["schema": 1, "eventID": UUID().uuidString, "timestamp": ISO8601DateFormatter().string(from: Date()), "sessionID": sessionID, "sequence": sequence, "stage": token(stage), "event": token(event), "os": ProcessInfo.processInfo.operatingSystemVersionString, "appVersion": token(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "test"), "process": Bundle.main.bundleIdentifier?.hasSuffix("MimiBroadcast") == true ? "broadcast" : "host"]
      object["metrics"] = metrics.filter { numericKeys.contains($0.key) && $0.value.isFinite }
      if let error { let e = error as NSError; object["error"] = ["domain": domains.contains(e.domain) ? e.domain : "other", "code": e.code] }
      if let source { object["source"] = token(source) }; if let target { object["target"] = token(target) }
      do {
        let line = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data([10])
        guard line.count <= maxBytes else { storageFailed = true; return }
        let current = (try? Data(contentsOf: logURL(0))) ?? Data()
        if current.count + line.count > maxBytes {
          for index in stride(from: fileCount - 1, through: 1, by: -1) {
            let destination = logURL(index)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            if FileManager.default.fileExists(atPath: logURL(index - 1).path) { try FileManager.default.moveItem(at: logURL(index - 1), to: destination) }
          }
          try line.write(to: logURL(0), options: .atomic)
        } else { try (current + line).write(to: logURL(0), options: .atomic) }
        protect(logURL(0))
      } catch { storageFailed = true }
    }
  }
  private func protect(_ url: URL) {
    #if os(iOS)
    try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    #endif
  }
  func snapshot(running: Bool, pip: Bool, metrics: [String: Double]) {
    queue.sync {
      let object: [String: Any] = ["schema": 2, "timestamp": ISO8601DateFormatter().string(from: Date()), "sessionID": sessionID, "running": running, "pip": pip, "storageFailed": storageFailed, "metrics": metrics.filter { numericKeys.contains($0.key) && $0.value.isFinite }]
      do {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let url = directory.deletingLastPathComponent().appendingPathComponent("probe-status.json")
        try data.write(to: url, options: .atomic); protect(url)
      } catch { storageFailed = true }
    }
  }
  func previousWasRunning() -> Bool {
    queue.sync {
      let url = directory.deletingLastPathComponent().appendingPathComponent("probe-status.json")
      guard let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
      let wasRunning = object["running"] as? Bool == true
      if wasRunning, let id = object["sessionID"] as? String, UUID(uuidString: id) != nil { sessionID = id }
      return wasRunning
    }
  }
  func report() -> String {
    queue.sync {
      var result = "Mimi local diagnostics · schema 1\nCaptured: \(ISO8601DateFormatter().string(from: Date()))\nStorage failure: \(storageFailed)\nNo audio, transcripts or credentials. Historical records; not a live device connection.\n"
      for index in (0..<fileCount).reversed() { if let data = try? Data(contentsOf: logURL(index)), data.count <= maxBytes, let text = String(data: data, encoding: .utf8) { result += text } }
      return result
    }
  }
  func export() throws -> URL {
    let url = directory.appendingPathComponent("diagnostics.txt")
    try Data(report().utf8).write(to: url, options: .atomic); protect(url)
    return url
  }
}
