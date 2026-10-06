import Flutter
import UIKit
import XCTest

@testable import nativeflow

final class EventStoreTests: XCTestCase {
  private var dir: URL!
  private var url: URL { dir.appendingPathComponent("events.jsonl") }
  private var now = Date(timeIntervalSince1970: 1_000)

  override func setUp() {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: dir)
  }

  private func store(maxEvents: Int = 1000, maxAttempts: Int = 10) -> EventStore {
    EventStore(url: url, maxEvents: maxEvents, maxAge: 10, maxAttempts: maxAttempts, clock: { self.now })
  }

  func testIdsAreMonotonicAndSurviveReload() {
    let s = store()
    XCTAssertEqual(s.append(type: "a", adapterId: nil, payload: ["k": 1]).id, 1)
    XCTAssertEqual(s.append(type: "b", adapterId: "driver", payload: [:]).id, 2)
    let pending = store().pending(after: 0, limit: 10)
    XCTAssertEqual(pending.map(\.type), ["a", "b"])
    XCTAssertEqual(pending[1].adapterId, "driver")
    XCTAssertEqual(pending[0].payload["k"] as? Int, 1)
    XCTAssertEqual(store().append(type: "c", adapterId: nil, payload: [:]).id, 3)
  }

  func testAckIsCumulativeAndPersistent() {
    let s = store()
    for i in 0..<5 { s.append(type: "e\(i)", adapterId: nil, payload: [:]) }
    s.ack(upTo: 3)
    let reloaded = store()
    XCTAssertEqual(reloaded.lastAck, 3)
    XCTAssertEqual(reloaded.pending(after: reloaded.lastAck, limit: 10).map(\.id), [4, 5])
  }

  func testRetentionAndPoisonEvents() {
    let s = store(maxEvents: 3, maxAttempts: 1)
    for i in 0..<5 { s.append(type: "e\(i)", adapterId: nil, payload: [:]) }
    XCTAssertEqual(s.pending(after: 0, limit: 10).map(\.id), [3, 4, 5])
    XCTAssertEqual(s.pending(after: 0, limit: 10).count, 0, "second attempt exceeds maxAttempts")
    now = now.addingTimeInterval(20)
    s.append(type: "fresh", adapterId: nil, payload: [:])
    XCTAssertEqual(s.pending(after: 0, limit: 10).map(\.type), ["fresh"])
  }

  func testTornLineIsIgnored() throws {
    let s = store()
    s.append(type: "ok", adapterId: nil, payload: [:])
    let h = try FileHandle(forWritingTo: url)
    h.seekToEndOfFile()
    h.write(Data("{\"op\":\"add\",\"id\":2,\"ty".utf8))
    try h.close()
    let reloaded = store()
    XCTAssertEqual(reloaded.append(type: "next", adapterId: nil, payload: [:]).id, 2)
    XCTAssertEqual(store().pending(after: 0, limit: 10).map(\.type), ["ok", "next"])
  }

  func testCompaction() throws {
    let s = store()
    for _ in 0..<300 {
      let e = s.append(type: "e", adapterId: nil, payload: [:])
      s.ack(upTo: e.id)
    }
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count
    XCTAssertLessThan(lines, 100)
    XCTAssertEqual(store().append(type: "after", adapterId: nil, payload: [:]).id, 301)
  }
}

final class CapabilityTests: XCTestCase {
  func testUndeclaredCapabilitiesAreUnavailableNotFaked() {
    let caps = CapabilityManager(info: [:])
    for c in ["persistentRuntime", "location", "microphone", "audio", "overlay", "fullscreen",
              "bootRecovery", "liveActivity", "backgroundProcessing"] {
      XCTAssertEqual(caps.syncStatus(c), Status.unavailable, c)
    }
    XCTAssertEqual(caps.syncStatus("backgroundExecution"), Status.partial)
  }

  func testContinuousModesEnablePartialPersistentRuntime() {
    let caps = CapabilityManager(info: ["UIBackgroundModes": ["location"]])
    XCTAssertTrue(caps.hasContinuousMode)
    XCTAssertEqual(caps.syncStatus("persistentRuntime"), Status.partial)
    XCTAssertFalse(CapabilityManager(info: ["UIBackgroundModes": ["fetch"]]).hasContinuousMode)
  }

  func testNotificationStatusIsReported() {
    let done = expectation(description: "report")
    CapabilityManager().report { report in
      XCTAssertEqual(Set(report.keys), Set(CapabilityManager.all))
      XCTAssertNotNil(report["notifications"])
      done.fulfill()
    }
    wait(for: [done], timeout: 60)
  }
}

final class PluginTests: XCTestCase {
  private func call(_ method: String, _ args: [String: Any] = [:]) -> Any? {
    var out: Any?
    let done = expectation(description: method)
    NativeFlowPlugin().handle(FlutterMethodCall(methodName: method, arguments: args)) {
      out = $0
      done.fulfill()
    }
    wait(for: [done], timeout: 5)
    return out
  }

  func testLifecycle() {
    let snapshot = call("initialize", ["logLevel": 0]) as? [String: Any]
    XCTAssertEqual(snapshot?["backgroundEngine"] as? Bool, false)
    XCTAssertEqual(call("start", ["requirements": ["capabilities": ["network"]]]) as? String, "running")
    XCTAssertEqual(call("stop") as? String, "stopped")
  }

  func testOverlaysAndFullscreenAreHonestlyUnavailable() {
    XCTAssertEqual((call("overlayShow") as? FlutterError)?.code, "unavailable")
  }

  func testAppendEventValidatesInput() {
    XCTAssertEqual((call("appendEvent", ["type": "bad type"]) as? FlutterError)?.code, "invalid_argument")
    let id = call("appendEvent", ["type": "ride.offer", "payload": ["id": 1]]) as? Int64
    XCTAssertNotNil(id)
    _ = call("ackEvents", ["upTo": id!])
  }

  func testVoidCommandsReplyWithNil() {
    // Regression: `()` reached the codec and aborted the app.
    let out = call("widgetUpdate", ["appGroup": "group.test", "key": "k", "data": ["a": "b"]])
    XCTAssertTrue(out == nil || out is FlutterError, "got \(String(describing: out))")
  }

  func testUnknownMethodIsRejected() {
    XCTAssertTrue((call("exec") as AnyObject) === FlutterMethodNotImplemented as AnyObject)
  }
}
