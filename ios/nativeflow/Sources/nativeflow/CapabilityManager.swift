import Foundation
import UIKit
import UserNotifications

#if canImport(ActivityKit)
  import ActivityKit
#endif

enum Status {
  static let supported = "supported"
  static let partial = "partiallySupported"
  static let permissionRequired = "permissionRequired"
  static let restricted = "restricted"
  static let unavailable = "unavailable"
}

/// Honest iOS capability report. iOS has no Android-style persistent
/// service: long-lived background execution exists only through specific,
/// App-Review-checked background modes that the app itself must declare.
final class CapabilityManager {
  static let all = [
    "backgroundExecution", "persistentRuntime", "network", "location", "microphone", "audio",
    "notifications", "overlay", "fullscreen", "bootRecovery", "liveActivity", "widget",
    "backgroundProcessing",
  ]

  private let info: [String: Any]
  init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) { self.info = info }

  var backgroundModes: Set<String> { Set(info["UIBackgroundModes"] as? [String] ?? []) }
  var permittedTaskIdentifiers: Set<String> {
    Set(info["BGTaskSchedulerPermittedIdentifiers"] as? [String] ?? [])
  }

  /// A declared mode that legitimately keeps the app running in background.
  var hasContinuousMode: Bool { !backgroundModes.isDisjoint(with: ["location", "audio", "voip"]) }

  func report(_ done: @escaping ([String: String]) -> Void) {
    notificationStatus { notifications in
      var result: [String: String] = [:]
      for c in Self.all { result[c] = c == "notifications" ? notifications : self.syncStatus(c) }
      done(result)
    }
  }

  func status(_ capability: String, _ done: @escaping (String) -> Void) {
    if capability == "notifications" { notificationStatus(done) } else { done(syncStatus(capability)) }
  }

  func syncStatus(_ capability: String) -> String {
    switch capability {
    case "backgroundExecution":
      return Status.partial  // finite background time (~30 s) after leaving foreground
    case "persistentRuntime":
      return hasContinuousMode ? Status.partial : Status.unavailable
    case "network":
      return Status.supported
    case "location":
      return locationStatus()
    case "microphone":
      return microphoneStatus()
    case "audio":
      return backgroundModes.contains("audio") ? Status.supported : Status.unavailable
    case "liveActivity":
      return liveActivityStatus()
    case "widget":
      return Status.supported
    case "backgroundProcessing":
      guard !permittedTaskIdentifiers.isEmpty,
        !backgroundModes.isDisjoint(with: ["fetch", "processing"])
      else { return Status.unavailable }
      switch UIApplication.shared.backgroundRefreshStatus {
      case .available: return Status.partial  // the OS decides when tasks run
      default: return Status.restricted
      }
    default:
      return Status.unavailable  // overlay, fullscreen, bootRecovery
    }
  }

  // MARK: - Individual capabilities

  private func notificationStatus(_ done: @escaping (String) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let s: String
      switch settings.authorizationStatus {
      case .notDetermined: s = Status.permissionRequired
      case .denied: s = Status.restricted
      default: s = Status.supported
      }
      DispatchQueue.main.async { done(s) }
    }
  }

  // CoreLocation / AVFoundation are looked up dynamically on purpose: a
  // static reference would make App Store Connect demand location and
  // microphone purpose strings from every app using NativeFlow (ITMS-90683).
  // NativeFlow only reports these; the app's own location/audio library
  // requests them.
  private func locationStatus() -> String {
    guard info["NSLocationWhenInUseUsageDescription"] != nil
      || info["NSLocationAlwaysAndWhenInUseUsageDescription"] != nil,
      let cls = NSClassFromString("CLLocationManager") as? NSObject.Type
    else { return Status.unavailable }
    let raw = (cls.init().value(forKey: "authorizationStatus") as? NSNumber)?.intValue ?? 0
    switch raw {
    case 0: return Status.permissionRequired  // notDetermined
    case 3, 4: return Status.supported  // authorizedAlways, authorizedWhenInUse
    default: return Status.restricted  // restricted, denied
    }
  }

  private func microphoneStatus() -> String {
    guard info["NSMicrophoneUsageDescription"] != nil,
      let cls = NSClassFromString("AVAudioSession") as? NSObject.Type,
      let session = cls.value(forKey: "sharedInstance") as? NSObject
    else { return Status.unavailable }
    switch (session.value(forKey: "recordPermission") as? NSNumber)?.uint32Value ?? 0 {
    case 0x6772_6E74: return Status.supported  // 'grnt'
    case 0x6465_6E79: return Status.restricted  // 'deny'
    default: return Status.permissionRequired  // 'undt'
    }
  }

  private func liveActivityStatus() -> String {
    guard info["NSSupportsLiveActivities"] as? Bool == true else { return Status.unavailable }
    #if canImport(ActivityKit)
      if #available(iOS 16.1, *) {
        return ActivityAuthorizationInfo().areActivitiesEnabled ? Status.supported : Status.restricted
      }
    #endif
    return Status.unavailable
  }

  // MARK: - Requests

  /// Only notifications can be requested by NativeFlow on iOS; everything
  /// else is either owned by the app's own library or not requestable.
  func request(_ capability: String, _ done: @escaping (String) -> Void) {
    status(capability) { current in
      guard capability == "notifications", current == Status.permissionRequired else {
        return done(current)
      }
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
        self.notificationStatus(done)
      }
    }
  }
}
