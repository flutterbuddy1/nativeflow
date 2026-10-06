import Foundation
import UserNotifications

/// UNUserNotificationCenter rendering. Responses are recognised by the
/// `nativeflow` marker in userInfo so other notification plugins are left
/// alone.
final class NotificationPresenter {
  static let marker = "nativeflow"
  static let presentationId = Int.max - 1
  private let center = UNUserNotificationCenter.current()

  /// Thrown when the user has not authorized notifications.
  struct NotAuthorized: Error {}

  func show(_ spec: [String: Any], completion: @escaping (Error?) -> Void) {
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        DispatchQueue.main.async { self.post(spec, completion: completion) }
      default:
        DispatchQueue.main.async { completion(NotAuthorized()) }
      }
    }
  }

  private func post(_ spec: [String: Any], completion: @escaping (Error?) -> Void) {
    let id = (spec["id"] as? NSNumber)?.intValue ?? 0
    let content = UNMutableNotificationContent()
    content.title = spec["title"] as? String ?? ""
    content.body = spec["body"] as? String ?? ""
    content.sound = .default
    if let group = spec["group"] as? String { content.threadIdentifier = group }
    var info: [String: Any] = [Self.marker: true, "notificationId": id]
    if let link = spec["deepLink"] as? String { info["deepLink"] = link }
    if let data = spec["payload"] as? [String: Any], !data.isEmpty { info["data"] = data }
    content.userInfo = info

    let actions = (spec["actions"] as? [[String: Any]] ?? []).prefix(3)
    let post = {
      self.center.add(
        UNNotificationRequest(identifier: Self.identifier(id), content: content, trigger: nil),
        withCompletionHandler: completion)
    }
    guard !actions.isEmpty else { return post() }

    // One category per distinct action set, merged with existing categories.
    let unActions = actions.map {
      UNNotificationAction(
        identifier: $0["id"] as? String ?? "", title: $0["label"] as? String ?? "",
        options: ($0["opensApp"] as? Bool ?? false) ? [.foreground] : [])
    }
    let categoryId = "nativeflow." + unActions.map(\.identifier).joined(separator: ",")
    content.categoryIdentifier = categoryId
    center.getNotificationCategories { existing in
      var all = existing.filter { $0.identifier != categoryId }
      all.insert(UNNotificationCategory(identifier: categoryId, actions: unActions, intentIdentifiers: []))
      self.center.setNotificationCategories(all)
      post()
    }
  }

  func cancel(_ id: Int) {
    center.removeDeliveredNotifications(withIdentifiers: [Self.identifier(id)])
    center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(id)])
  }

  static func identifier(_ id: Int) -> String { "nativeflow.\(id)" }

  /// Event (type, payload) for a response, or nil if it is not ours.
  static func event(for response: UNNotificationResponse) -> (String, [String: Any])? {
    let info = response.notification.request.content.userInfo
    guard info[marker] as? Bool == true else { return nil }
    let isTap = response.actionIdentifier == UNNotificationDefaultActionIdentifier
    if response.actionIdentifier == UNNotificationDismissActionIdentifier { return nil }
    var payload: [String: Any] = [
      "notificationId": info["notificationId"] ?? 0,
      "deepLink": info["deepLink"] ?? NSNull(),
      "data": info["data"] ?? NSNull(),
    ]
    if !isTap { payload["actionId"] = response.actionIdentifier }
    return (isTap ? "nativeflow.notification.tap" : "nativeflow.notification.action", payload)
  }
}
