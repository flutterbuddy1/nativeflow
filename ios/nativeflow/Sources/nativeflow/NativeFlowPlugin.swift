import Flutter
import UIKit
import UserNotifications

/// Flutter bridge. A closed set of channel commands mapped onto
/// `RuntimeSupervisor`; there is no generic dispatch.
public class NativeFlowPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let supervisor = RuntimeSupervisor.shared

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = NativeFlowPlugin()
    let channel = FlutterMethodChannel(name: "dev.nativeflow/runtime", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    FlutterEventChannel(name: "dev.nativeflow/events", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance)
    registrar.addApplicationDelegate(instance)
  }

  /// Call from `application(_:didFinishLaunchingWithOptions:)` BEFORE it
  /// returns if you use `NativeFlow.scheduleBackgroundTask`. iOS requires
  /// BGTaskScheduler handlers to be registered during launch, which may be
  /// earlier than Flutter plugin registration.
  public static func registerBackgroundTasks() {
    RuntimeSupervisor.shared.registerBackgroundTasks()
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    supervisor.addSink(self, events)
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    supervisor.removeSink(self)
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let s = supervisor
    switch call.method {
    case "initialize":
      result(s.initialize(logLevel: args["logLevel"] as? Int ?? 1))
    case "capabilities":
      s.capabilities.report { report in
        var r = report
        if r["backgroundProcessing"] == Status.partial, !s.tasksRegistered {
          r["backgroundProcessing"] = Status.unavailable
        }
        result(r)
      }
    case "start":
      result(s.start(args))
    case "stop":
      result(s.stop())
    case "setRequirements":
      s.setRequirements(args)
      result(nil)
    case "appendEvent":
      guard let type = args["type"] as? String, Self.validId(type) else {
        return result(Self.error("invalid_argument", "Invalid event type"))
      }
      let adapterId = args["adapterId"] as? String
      if let a = adapterId, !Self.validId(a) {
        return result(Self.error("invalid_argument", "Invalid adapter id"))
      }
      let payload = args["payload"] as? [String: Any] ?? [:]
      guard JSONSerialization.isValidJSONObject(payload),
        let data = try? JSONSerialization.data(withJSONObject: payload), data.count <= 32 * 1024
      else { return result(Self.error("invalid_argument", "Payload must be JSON and at most 32 KB")) }
      result(s.emit(type, payload, adapterId: adapterId, persist: true))
    case "pendingEvents":
      let after = (args["after"] as? NSNumber)?.int64Value ?? 0
      result(s.events.pending(after: after, limit: args["limit"] as? Int ?? 100).map(\.map))
    case "ackEvents":
      s.events.ack(upTo: (args["upTo"] as? NSNumber)?.int64Value ?? 0)
      result(nil)
    case "permissionStatus":
      s.capabilities.status(args["capability"] as? String ?? "") { result($0) }
    case "requestPermission":
      s.capabilities.request(args["capability"] as? String ?? "") { result($0) }
    case "createChannel":
      result(nil)  // Android-only concept; iOS has no channels.
    case "showNotification":
      s.notifications.show(args) { result($0.map(Self.notificationError)) }
    case "cancelNotification":
      s.notifications.cancel((args["id"] as? NSNumber)?.intValue ?? 0)
      result(nil)
    case "present":
      s.present(args) { result($0.map(Self.notificationError)) }
    case "activityStart":
      run(result) {
        try s.activities.start(
          attributes: args["attributes"] as? [String: String] ?? [:],
          state: args["state"] as? [String: String] ?? [:])
      }
    case "activityUpdate":
      run(result) {
        try s.activities.update(
          id: args["activityId"] as? String ?? "", state: args["state"] as? [String: String] ?? [:])
      }
    case "activityEnd":
      run(result) {
        try s.activities.end(id: args["activityId"] as? String ?? "", state: args["state"] as? [String: String])
      }
    case "widgetUpdate":
      run(result) {
        try s.activities.updateWidget(
          appGroup: args["appGroup"] as? String ?? "", key: args["key"] as? String ?? "",
          data: args["data"] as? [String: String] ?? [:], kind: args["kind"] as? String)
      }
    case "scheduleBackgroundTask":
      guard s.tasksRegistered else {
        return result(
          Self.error("unavailable", "Call NativeFlowPlugin.registerBackgroundTasks() in AppDelegate"))
      }
      run(result) {
        try s.tasks.schedule(
          kind: args["kind"] as? String ?? "refresh",
          earliestSeconds: (args["earliestSeconds"] as? NSNumber)?.doubleValue ?? 900)
      }
    case "completeBackgroundTask":
      s.tasks.complete(taskId: args["taskId"] as? String ?? "", success: args["success"] as? Bool ?? true)
      result(nil)
    case "overlayShow", "overlayUpdate", "overlayHide", "overlayMove", "overlayResize", "overlayState":
      result(Self.error("unavailable", "Overlays are not available on iOS"))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func run(_ result: FlutterResult, _ body: () throws -> Any?) {
    do {
      let value = try body()
      // Void-returning commands yield `()`, which the codec cannot encode.
      result(value is Void ? nil : value)
    } catch PluginError.unavailable(let message) {
      result(Self.error("unavailable", message))
    } catch PluginError.notFound {
      result(Self.error("invalid_argument", "No such Live Activity"))
    } catch {
      result(Self.error("platform", error.localizedDescription))
    }
  }

  /// The user has not authorized notifications: report it honestly.
  static func notificationError(_ error: Error) -> FlutterError {
    if error is NotificationPresenter.NotAuthorized
      || (error as? UNError)?.code == .notificationsNotAllowed
    {
      return Self.error("permission_required", "Notifications are not authorized")
    }
    if case PluginError.notFound = error { return Self.error("invalid_argument", "No such Live Activity") }
    return Self.error("platform", error.localizedDescription)
  }

  static func error(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }

  static func validId(_ s: String) -> Bool {
    s.range(of: "^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$", options: .regularExpression) != nil
  }

  // MARK: - UNUserNotificationCenterDelegate (forwarded by FlutterAppDelegate)

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard let (type, payload) = NotificationPresenter.event(for: response) else { return }
    supervisor.emit(type, payload, persist: true)
    completionHandler()
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    guard notification.request.content.userInfo[NotificationPresenter.marker] as? Bool == true else {
      return
    }
    completionHandler([.banner, .list, .sound])
  }
}
