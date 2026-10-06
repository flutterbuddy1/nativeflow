import Foundation

/// Small persistent log of runtime events awaiting delivery to Dart.
///
/// Same JSON-lines format and semantics as the Android `EventStore`:
/// `add` / `ack` (cumulative) / `try` (redelivery attempt) / `meta`
/// (compaction header). A torn last line is skipped on load.
final class EventStore {
  struct Event {
    let id: Int64
    let type: String
    let ts: Int64
    let adapterId: String?
    let payload: [String: Any]
    var attempts: Int

    var map: [String: Any] {
      ["id": id, "type": type, "ts": ts, "adapterId": adapterId ?? NSNull(), "payload": payload]
    }
  }

  private let url: URL
  private let maxEvents: Int
  private let maxAge: TimeInterval
  private let maxAttempts: Int
  private let clock: () -> Date
  private let lock = NSLock()

  private var events: [Int64: Event] = [:]
  private var order: [Int64] = []
  private var nextId: Int64 = 1
  private var lines = 0
  private(set) var lastAck: Int64 = 0

  init(
    url: URL, maxEvents: Int = 1000, maxAge: TimeInterval = 7 * 24 * 3600,
    maxAttempts: Int = 10, clock: @escaping () -> Date = Date.init
  ) {
    self.url = url
    self.maxEvents = maxEvents
    self.maxAge = maxAge
    self.maxAttempts = maxAttempts
    self.clock = clock
    load()
  }

  @discardableResult
  func append(type: String, adapterId: String?, payload: [String: Any]) -> Event {
    lock.lock(); defer { lock.unlock() }
    let event = Event(
      id: nextId, type: type, ts: Int64(clock().timeIntervalSince1970 * 1000),
      adapterId: adapterId, payload: payload, attempts: 0)
    nextId += 1
    events[event.id] = event
    order.append(event.id)
    write(["op": "add", "id": event.id, "type": type, "ts": event.ts,
           "adapterId": adapterId ?? NSNull(), "payload": payload])
    prune()
    return event
  }

  /// Unacknowledged events after `after`; each counts as a delivery attempt.
  func pending(after: Int64, limit: Int) -> [Event] {
    lock.lock(); defer { lock.unlock() }
    prune()
    var result: [Event] = []
    for id in order where id > after {
      guard var e = events[id] else { continue }
      e.attempts += 1
      write(["op": "try", "id": id])
      if e.attempts > maxAttempts {
        remove(id)
        continue
      }
      events[id] = e
      result.append(e)
      if result.count == limit { break }
    }
    return result
  }

  func ack(upTo: Int64) {
    lock.lock(); defer { lock.unlock() }
    guard upTo > lastAck else { return }
    lastAck = min(upTo, nextId - 1)
    order.filter { $0 <= lastAck }.forEach(remove)
    write(["op": "ack", "upTo": lastAck])
    compactIfNeeded()
  }

  var count: Int {
    lock.lock(); defer { lock.unlock() }
    return events.count
  }

  // MARK: - Private (call with lock held)

  private func remove(_ id: Int64) {
    events[id] = nil
    order.removeAll { $0 == id }
  }

  private func prune() {
    let cutoff = Int64((clock().timeIntervalSince1970 - maxAge) * 1000)
    order.filter { (events[$0]?.ts ?? 0) < cutoff }.forEach(remove)
    while order.count > maxEvents { remove(order[0]) }
    compactIfNeeded()
  }

  private func compactIfNeeded() {
    guard lines >= 64, lines >= events.count * 2 else { return }
    var out = line(["op": "meta", "nextId": nextId, "lastAck": lastAck])
    for id in order {
      let e = events[id]!
      out += line(["op": "add", "id": e.id, "type": e.type, "ts": e.ts,
                   "adapterId": e.adapterId ?? NSNull(), "payload": e.payload, "attempts": e.attempts])
    }
    do {
      try Data(out.utf8).write(to: url, options: .atomic)
      lines = events.count + 1
    } catch {
      NFLog.error("Event store compaction failed: \(error)")
    }
  }

  private func line(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object),
      let s = String(data: data, encoding: .utf8)
    else { return "" }
    return s + "\n"
  }

  // ponytail: no fsync per append; survives process death, not power loss.
  private func write(_ object: [String: Any]) {
    let data = Data(line(object).utf8)
    let fm = FileManager.default
    if !fm.fileExists(atPath: url.path) {
      try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      fm.createFile(atPath: url.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    handle.seekToEndOfFile()
    handle.write(data)
    lines += 1
  }

  private func load() {
    guard let data = try? Data(contentsOf: url) else { return }
    for raw in data.split(separator: UInt8(ascii: "\n")) {
      lines += 1
      guard let o = (try? JSONSerialization.jsonObject(with: Data(raw))) as? [String: Any] else {
        continue  // torn write
      }
      switch o["op"] as? String {
      case "meta":
        nextId = max(nextId, int64(o["nextId"]) ?? 1)
        lastAck = max(lastAck, int64(o["lastAck"]) ?? 0)
      case "add":
        guard let id = int64(o["id"]), let type = o["type"] as? String else { continue }
        nextId = max(nextId, id + 1)
        if id > lastAck {
          events[id] = Event(
            id: id, type: type, ts: int64(o["ts"]) ?? 0, adapterId: o["adapterId"] as? String,
            payload: o["payload"] as? [String: Any] ?? [:], attempts: o["attempts"] as? Int ?? 0)
          order.append(id)
        }
      case "ack":
        lastAck = max(lastAck, int64(o["upTo"]) ?? 0)
        order.filter { $0 <= lastAck }.forEach(remove)
      case "try":
        if let id = int64(o["id"]) { events[id]?.attempts += 1 }
      default:
        continue
      }
    }
    // Terminate a torn last line so the next append starts cleanly.
    if let last = data.last, last != UInt8(ascii: "\n"),
      let handle = try? FileHandle(forWritingTo: url)
    {
      handle.seekToEndOfFile()
      handle.write(Data("\n".utf8))
      try? handle.close()
    }
  }

  private func int64(_ v: Any?) -> Int64? { (v as? NSNumber)?.int64Value }
}

/// Native logging gated by the Dart-side LogVerbosity index.
enum NFLog {
  /// 0 disabled, 1 errors, 2 normal, 3 verbose.
  static var level = 1

  static func debug(_ m: @autoclosure () -> String) { if level >= 3 { NSLog("[NativeFlow] %@", m()) } }
  static func info(_ m: @autoclosure () -> String) { if level >= 2 { NSLog("[NativeFlow] %@", m()) } }
  static func error(_ m: @autoclosure () -> String) { if level >= 1 { NSLog("[NativeFlow] %@", m()) } }
}
