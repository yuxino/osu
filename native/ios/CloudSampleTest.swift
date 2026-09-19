import AVFoundation

// A fixed synthetic utterance, never microphone or browser audio. Kept only in RAM.
final class CloudSampleTest {
  private let synthesizer = AVSpeechSynthesizer()
  private let queue = DispatchQueue(label: "mimi.cloud.sample")
  private var epoch = 0
  private var pcm = Data()
  private var converter: AVAudioConverter?
  private let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
  func prepare(completion: @escaping (Data?) -> Void) {
    cancel(); let current = queue.sync { epoch }
    guard let voice = AVSpeechSynthesisVoice(language: "ja-JP") else { completion(nil); return }
    let utterance = AVSpeechUtterance(string: "こんにちは。今日は日本語の字幕をテストしています。明日は友達と公園に行きます。")
    utterance.voice = voice; utterance.rate = 0.45
    synthesizer.write(utterance) { [weak self] buffer in
      guard let self, let input = buffer as? AVAudioPCMBuffer else { return }
      self.queue.async {
        guard self.epoch == current else { return }
        if input.frameLength == 0 {
          let result = self.pcm; self.pcm.removeAll(); self.epoch += 1
          DispatchQueue.main.async { completion(result.isEmpty ? nil : result) }; return
        }
        if self.converter == nil { self.converter = AVAudioConverter(from: input.format, to: self.output) }
        guard let converter = self.converter, let destination = AVAudioPCMBuffer(pcmFormat: self.output, frameCapacity: AVAudioFrameCount(Double(input.frameLength) * 16000 / input.format.sampleRate) + 32) else { return }
        var supplied = false; var error: NSError?
        converter.convert(to: destination, error: &error) { _, state in
          if supplied { state.pointee = .noDataNow; return nil }; supplied = true; state.pointee = .haveData; return input
        }
        guard error == nil, let samples = destination.int16ChannelData?[0], self.pcm.count + Int(destination.frameLength) * 2 <= 640000 else {
          self.epoch += 1; self.pcm.removeAll(); DispatchQueue.main.async { completion(nil) }; return
        }
        self.pcm.append(Data(bytes: samples, count: Int(destination.frameLength) * 2))
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
      guard let self else { return }
      let timedOut = self.queue.sync { () -> Bool in
        guard self.epoch == current else { return false }; self.epoch += 1; self.pcm.removeAll(); return true
      }
      if timedOut { self.synthesizer.stopSpeaking(at: .immediate); completion(nil) }
    }
  }
  func cancel() { synthesizer.stopSpeaking(at: .immediate); queue.sync { epoch += 1; pcm.removeAll(); converter = nil } }
}
