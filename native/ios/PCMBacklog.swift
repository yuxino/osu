import Foundation

// Two seconds of 16 kHz mono PCM16. Overflow is explicit; never skip speech silently.
struct PCMBacklog {
  enum Failure: Error { case invalid, overflow }
  private var storage = Data()
  var count: Int { storage.count }
  mutating func append(_ data: Data) throws {
    guard !data.isEmpty, data.count % 2 == 0 else { throw Failure.invalid }
    guard storage.count + data.count <= 64000 else { throw Failure.overflow }
    storage.append(data)
  }
  mutating func take(upTo limit: Int = 3200) -> Data? {
    guard !storage.isEmpty, limit >= 2 else { return nil }
    let count = min(storage.count, limit / 2 * 2)
    let result = Data(storage.prefix(count)); storage.removeFirst(count); return result
  }
  mutating func clear() { storage.removeAll(keepingCapacity: true) }
}

// Coalesces background delivery into one bounded main-queue drain.
final class PCMDeliveryBuffer {
  enum Result { case schedule, buffered, closed, overflow }
  private let lock = NSLock()
  private var backlog = PCMBacklog()
  private var scheduled = false, closed = false
  func append(_ data: Data) -> Result {
    lock.lock(); defer { lock.unlock() }
    guard !closed else { return .closed }
    do { try backlog.append(data) }
    catch { closed = true; backlog.clear(); return .overflow }
    guard !scheduled else { return .buffered }
    scheduled = true; return .schedule
  }
  func next() -> Data? {
    lock.lock(); defer { lock.unlock() }
    guard !closed else { return nil }
    guard let data = backlog.take(upTo: 6400) else { scheduled = false; return nil }
    return data
  }
  func cancel() { lock.lock(); closed = true; backlog.clear(); lock.unlock() }
}
