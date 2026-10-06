import Foundation
import WidgetKit

#if canImport(ActivityKit)
  import ActivityKit

  /// Generic Live Activity attributes. ActivityKit matches attributes by type
  /// name, so the app's Widget Extension must declare an identical struct
  /// (see docs/PLATFORM_CAPABILITIES.md) and render `values` as it likes.
  public struct NativeFlowActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
      public var values: [String: String]
    }

    public var values: [String: String]
  }
#endif

#if canImport(ActivityKit)
  private typealias State = NativeFlowActivityAttributes.ContentState
#endif

enum PluginError: Error {
  case unavailable(String)
  case notFound
}

/// Live Activities (iOS 16.1+) and widget timeline refresh.
final class ActivityManager {
  func start(attributes: [String: String], state: [String: String]) throws -> String {
    #if canImport(ActivityKit)
      if #available(iOS 16.2, *) {
        let activity = try Activity.request(
          attributes: NativeFlowActivityAttributes(values: attributes),
          content: ActivityContent(state: State(values: state), staleDate: nil))
        return activity.id
      } else if #available(iOS 16.1, *) {
        let activity = try Activity.request(
          attributes: NativeFlowActivityAttributes(values: attributes),
          contentState: State(values: state))
        return activity.id
      }
    #endif
    throw PluginError.unavailable("Live Activities require iOS 16.1+")
  }

  func update(id: String, state: [String: String]) throws {
    #if canImport(ActivityKit)
      if #available(iOS 16.2, *) {
        guard let a = find(id) else { throw PluginError.notFound }
        Task { await a.update(ActivityContent(state: State(values: state), staleDate: nil)) }
        return
      } else if #available(iOS 16.1, *) {
        guard let a = find(id) else { throw PluginError.notFound }
        Task { await a.update(using: State(values: state)) }
        return
      }
    #endif
    throw PluginError.unavailable("Live Activities require iOS 16.1+")
  }

  func end(id: String, state: [String: String]?) throws {
    #if canImport(ActivityKit)
      if #available(iOS 16.2, *) {
        guard let a = find(id) else { throw PluginError.notFound }
        let content = state.map { ActivityContent(state: State(values: $0), staleDate: nil) }
        Task { await a.end(content, dismissalPolicy: .default) }
        return
      } else if #available(iOS 16.1, *) {
        guard let a = find(id) else { throw PluginError.notFound }
        Task { await a.end(using: state.map { State(values: $0) }, dismissalPolicy: .default) }
        return
      }
    #endif
    throw PluginError.unavailable("Live Activities require iOS 16.1+")
  }

  /// Id of the most recent running NativeFlow activity, if any.
  var currentId: String? {
    #if canImport(ActivityKit)
      if #available(iOS 16.1, *) {
        return Activity<NativeFlowActivityAttributes>.activities.last { $0.activityState == .active }?.id
      }
    #endif
    return nil
  }

  func updateWidget(appGroup: String, key: String, data: [String: String], kind: String?) throws {
    guard let defaults = UserDefaults(suiteName: appGroup) else {
      throw PluginError.unavailable("App Group \(appGroup) is not configured")
    }
    defaults.set(data, forKey: key)
    if let kind { WidgetCenter.shared.reloadTimelines(ofKind: kind) } else {
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private func find(_ id: String) -> Activity<NativeFlowActivityAttributes>? {
      Activity<NativeFlowActivityAttributes>.activities.first { $0.id == id }
    }
  #endif
}
