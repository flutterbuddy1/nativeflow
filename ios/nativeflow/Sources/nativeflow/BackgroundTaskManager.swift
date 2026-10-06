import BackgroundTasks
import Foundation
import UIKit

/// BGTaskScheduler integration. The OS decides if and when tasks run; we
/// surface each grant as a persisted `nativeflow.background.task` event and
/// the app must complete it before the deadline.
final class BackgroundTaskManager {
  static var refreshId: String { (Bundle.main.bundleIdentifier ?? "app") + ".nativeflow.refresh" }
  static var processingId: String { (Bundle.main.bundleIdentifier ?? "app") + ".nativeflow.processing" }

  private var running: [String: BGTask] = [:]
  private let onTask: (_ taskId: String, _ kind: String) -> Void
  private let onExpired: (_ taskId: String) -> Void

  init(onTask: @escaping (String, String) -> Void, onExpired: @escaping (String) -> Void) {
    self.onTask = onTask
    self.onExpired = onExpired
  }

  /// Must run before the app finishes launching. Registering an identifier
  /// missing from Info.plist crashes, so only declared ones are registered.
  func register(permitted: Set<String>) {
    for (id, kind) in [(Self.refreshId, "refresh"), (Self.processingId, "processing")]
    where permitted.contains(id) {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] task in
        self?.handle(task, kind: kind)
      }
    }
  }

  func schedule(kind: String, earliestSeconds: Double) throws {
    let request: BGTaskRequest
    if kind == "processing" {
      let r = BGProcessingTaskRequest(identifier: Self.processingId)
      r.requiresNetworkConnectivity = true
      request = r
    } else {
      request = BGAppRefreshTaskRequest(identifier: Self.refreshId)
    }
    request.earliestBeginDate = Date(timeIntervalSinceNow: earliestSeconds)
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch let error as BGTaskScheduler.Error where error.code == .unavailable {
      throw PluginError.unavailable(
        "BGTaskScheduler is unavailable (simulator, or Background App Refresh is off)")
    }
  }

  func complete(taskId: String, success: Bool) {
    running.removeValue(forKey: taskId)?.setTaskCompleted(success: success)
  }

  private func handle(_ task: BGTask, kind: String) {
    let taskId = UUID().uuidString
    running[taskId] = task
    task.expirationHandler = { [weak self] in
      DispatchQueue.main.async {
        self?.onExpired(taskId)
        self?.complete(taskId: taskId, success: false)
      }
    }
    onTask(taskId, kind)
  }
}
