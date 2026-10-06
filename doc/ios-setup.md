# iOS setup

iOS has no persistent services. NativeFlow coordinates what Apple offers, and
your app must declare each mechanism it legitimately uses. App Review checks
these.

## Info.plist

```xml
<key>UIBackgroundModes</key>
<array>
  <string>location</string>   <!-- only if you really track location in background -->
  <string>fetch</string>      <!-- background app refresh tasks -->
  <string>processing</string> <!-- background processing tasks -->
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER).nativeflow.refresh</string>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER).nativeflow.processing</string>
</array>
<key>NSSupportsLiveActivities</key><true/>
```

Location and microphone usage strings belong to the library that requests
those permissions (for example `geolocator`). NativeFlow only reads their status.

## AppDelegate

```swift
import Flutter
import UIKit
import UserNotifications
import nativeflow

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required for NativeFlow.scheduleBackgroundTask: iOS only accepts
    // BGTaskScheduler handlers registered before launch finishes.
    NativeFlowPlugin.registerBackgroundTasks()
    // Lets FlutterAppDelegate forward notification taps/actions to plugins.
    UNUserNotificationCenter.current().delegate = self
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

## Live Activities and widgets

1. In Xcode: **File → New → Target → Widget Extension** (check *Include Live Activity*). Set its deployment target to iOS 16.1.
2. Add an **App Group** capability (for example `group.com.example.app`) to both the Runner and the extension if you use `updateWidget`.
3. Declare this struct in the extension **verbatim**. ActivityKit pairs the app and the extension by its type name:

```swift
import ActivityKit

struct NativeFlowActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable { var values: [String: String] }
  var values: [String: String]
}
```

4. Render `context.attributes.values` (fixed per activity) and
   `context.state.values` (updated by `activities.update` and `present`):

```swift
ActivityConfiguration(for: NativeFlowActivityAttributes.self) { ctx in
  VStack(alignment: .leading) {
    Text(ctx.state.values["title"] ?? ctx.state.values["status"] ?? "")
    Text("ETA \(ctx.state.values["eta"] ?? "-")")
  }.padding()
} dynamicIsland: { ctx in
  DynamicIsland {
    DynamicIslandExpandedRegion(.center) { Text(ctx.state.values["status"] ?? "") }
  } compactLeading: { Image(systemName: "car.fill") }
    compactTrailing: { Text(ctx.state.values["eta"] ?? "") }
    minimal: { Image(systemName: "car.fill") }
}
```

A home-screen widget reads what `NativeFlow.activities.updateWidget` wrote:

```swift
UserDefaults(suiteName: "group.com.example.app")?.dictionary(forKey: "driver") as? [String: String]
```

The example app contains a complete extension:
[`example/ios/NativeFlowWidgets`](../example/ios/NativeFlowWidgets/NativeFlowWidgets.swift).

## What iOS does with your runtime

| Situation | Behaviour |
|---|---|
| App in foreground | Adapters run normally |
| App backgrounded, no continuous mode | NativeFlow takes the ~30 s the OS grants, calls `pause` on adapters before it runs out, and calls `resume` on return |
| App backgrounded with a declared and required `location` / `audio` / `voip` mode | Adapters are left running; your library's mode keeps the app alive |
| App killed, relaunched (user, BGTask, location wake-up) | `runtime.recovered{reason: appLaunch}`; adapters get `recover` |
| Reboot | Nothing restarts until the user or the OS launches the app |

## Privacy manifest

The plugin ships `PrivacyInfo.xcprivacy` declaring `UserDefaults` access
(reasons CA92.1, 1C8F.1). It collects no data and does no tracking.
