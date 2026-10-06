import Flutter
import Foundation
import Network
import UIKit

/// Process-wide owner of the iOS runtime. There is no service to start:
/// "running" means the app recorded the intent and NativeFlow coordinates
/// what iOS legitimately offers (finite background time, BGTaskScheduler,
/// the app's own continuous background modes, notifications, Live
/// Activities). Everything runs on the main thread.
final class RuntimeSupervisor {
  static let shared = RuntimeSupervisor()

  enum State: String { case stopped, running, interrupted, recovering }

  private(set) var state = State.stopped
  let capabilities = CapabilityManager()
  let notifications = NotificationPresenter()
  let activities = ActivityManager()
  private(set) var tasksRegistered = false
  lazy var tasks = BackgroundTaskManager(
    onTask: { [weak self] id, kind in
      self?.emit("nativeflow.background.task", ["taskId": id, "kind": kind], persist: true)
    },
    onExpired: { [weak self] id in
      self?.emit("nativeflow.background.task", ["taskId": id, "expired": true])
    })

  let events: EventStore = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return EventStore(url: dir.appendingPathComponent("nativeflow/events.jsonl"))
  }()

  private let defaults = UserDefaults.standard
  private var sinks: [ObjectIdentifier: FlutterEventSink] = [:]
  private var outbox: [[String: Any]] = []
  private var monitor: NWPathMonitor?
  private(set) var network: [String: Any] = ["connected": false, "type": "none", "metered": false]
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var pauseWork: DispatchWorkItem?
  private var paused = false

  private var active: Bool {
    get { defaults.bool(forKey: "dev.nativeflow.active") }
    set { defaults.set(newValue, forKey: "dev.nativeflow.active") }
  }
  private var requirements: Set<String> {
    get { Set(defaults.stringArray(forKey: "dev.nativeflow.capabilities") ?? []) }
    set { defaults.set(Array(newValue), forKey: "dev.nativeflow.capabilities") }
  }

  private init() {
    NFLog.level = defaults.object(forKey: "dev.nativeflow.logLevel") as? Int ?? 1
    let nc = NotificationCenter.default
    nc.addObserver(
      self, selector: #selector(didEnterBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    nc.addObserver(
      self, selector: #selector(willEnterForeground),
      name: UIApplication.willEnterForegroundNotification, object: nil)
    // A new process with a recorded intent: the app was relaunched (by the
    // user, a background task, or a location/VoIP wake-up). Restore.
    if active {
      state = .running
      emit("nativeflow.runtime.recovered", ["reason": "appLaunch"], persist: true)
    }
  }

  func registerBackgroundTasks() {
    guard !tasksRegistered else { return }
    tasksRegistered = true
    tasks.register(permitted: capabilities.permittedTaskIdentifiers)
  }

  // MARK: - Commands

  func snapshot() -> [String: Any] {
    [
      "state": state.rawValue, "network": network, "backgroundEngine": false,
      "lastAck": events.lastAck, "capabilities": Array(requirements),
    ]
  }

  func initialize(logLevel: Int) -> [String: Any] {
    NFLog.level = logLevel
    defaults.set(logLevel, forKey: "dev.nativeflow.logLevel")
    startNetwork()
    return snapshot()
  }

  func start(_ config: [String: Any]) -> String {
    requirements = Self.capabilities(of: config)
    active = true
    if state != .running {
      state = .running
      emit("nativeflow.runtime.started")
    }
    return state.rawValue
  }

  func setRequirements(_ config: [String: Any]) {
    requirements = Self.capabilities(of: config)
  }

  func stop() -> String {
    active = false
    endBackgroundTask()
    paused = false
    if state != .stopped {
      state = .stopped
      emit("nativeflow.runtime.stopped")
    }
    return state.rawValue
  }

  /// Live Activity when one is running and enabled, otherwise a notification.
  func present(_ spec: [String: Any], completion: @escaping (Error?) -> Void) {
    if let id = activities.currentId, capabilities.syncStatus("liveActivity") == Status.supported {
      var values = spec["values"] as? [String: String] ?? [:]
      values["title"] = spec["title"] as? String
      values["body"] = spec["body"] as? String
      if let p = spec["progress"] as? NSNumber { values["progress"] = p.stringValue }
      do { try activities.update(id: id, state: values) } catch { return completion(error) }
      return completion(nil)
    }
    var n = spec
    n["id"] = NotificationPresenter.presentationId
    notifications.show(n, completion: completion)
  }

  static func capabilities(of config: [String: Any]) -> Set<String> {
    Set((config["requirements"] as? [String: Any])?["capabilities"] as? [String] ?? [])
  }

  // MARK: - App lifecycle

  /// iOS suspends apps shortly after backgrounding unless a declared
  /// continuous mode (location/audio/VoIP) keeps them running. In that case
  /// we do nothing; otherwise we take the finite background time the OS
  /// offers and pause adapters before it runs out, so they can close
  /// cleanly instead of being frozen mid-operation.
  @objc private func didEnterBackground() {
    guard state == .running, !keepsRunningInBackground else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "dev.nativeflow.pause") {
      [weak self] in self?.pauseNow()
    }
    let remaining = min(UIApplication.shared.backgroundTimeRemaining, 30)
    let work = DispatchWorkItem { [weak self] in self?.pauseNow() }
    pauseWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + max(0, remaining - 8), execute: work)
  }

  @objc private func willEnterForeground() {
    pauseWork?.cancel()
    endBackgroundTask()
    if paused {
      paused = false
      emit("nativeflow.runtime.resumed")
    }
  }

  private var keepsRunningInBackground: Bool {
    capabilities.hasContinuousMode
      && !requirements.isDisjoint(with: ["persistentRuntime", "location", "audio"])
  }

  private func pauseNow() {
    if !paused {
      paused = true
      emit("nativeflow.runtime.paused")
    }
    // Give Dart a few seconds to run pause() before releasing the time.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.endBackgroundTask() }
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }

  // MARK: - Network

  private func startNetwork() {
    guard monitor == nil else { return }
    let m = NWPathMonitor()
    m.pathUpdateHandler = { [weak self] path in
      let connected = path.status == .satisfied
      let type: String =
        !connected ? "none"
        : path.usesInterfaceType(.wifi) ? "wifi"
        : path.usesInterfaceType(.cellular) ? "cellular"
        : path.usesInterfaceType(.wiredEthernet) ? "ethernet"
        : path.usesInterfaceType(.other) ? "vpn" : "other"
      let next: [String: Any] = [
        "connected": connected, "type": type, "metered": path.isExpensive || path.isConstrained,
      ]
      DispatchQueue.main.async { self?.updateNetwork(next) }
    }
    m.start(queue: DispatchQueue(label: "dev.nativeflow.network"))
    monitor = m
  }

  private func updateNetwork(_ next: [String: Any]) {
    let was = network["connected"] as? Bool ?? false
    let now = next["connected"] as? Bool ?? false
    guard NSDictionary(dictionary: network) != NSDictionary(dictionary: next) else { return }
    network = next
    let type =
      now && !was ? "nativeflow.network.available"
      : !now && was ? "nativeflow.network.lost" : "nativeflow.network.changed"
    emit(type, next)
  }

  // MARK: - Events

  func addSink(_ owner: AnyObject, _ sink: @escaping FlutterEventSink) {
    sinks[ObjectIdentifier(owner)] = sink
  }

  func removeSink(_ owner: AnyObject) {
    sinks[ObjectIdentifier(owner)] = nil
  }

  /// Persisted events go to the store first; all events are batched per
  /// main-queue turn to Dart.
  @discardableResult
  func emit(_ type: String, _ payload: [String: Any] = [:], adapterId: String? = nil, persist: Bool = false)
    -> Int64?
  {
    let event: [String: Any] =
      persist
      ? events.append(type: type, adapterId: adapterId, payload: payload).map
      : [
        "type": type, "ts": Int64(Date().timeIntervalSince1970 * 1000),
        "adapterId": adapterId ?? NSNull(), "payload": payload,
      ]
    NFLog.debug("event \(type)")
    let first = outbox.isEmpty
    outbox.append(event)
    if first { DispatchQueue.main.async { [weak self] in self?.flush() } }
    return event["id"] as? Int64
  }

  private func flush() {
    guard !outbox.isEmpty else { return }
    let batch = outbox
    outbox.removeAll()
    for sink in sinks.values { sink(batch) }
  }
}
