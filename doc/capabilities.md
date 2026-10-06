# Capabilities

Adapters declare **what** they need as `RuntimeCapability`s. Each platform
decides **how** to deliver it and reports honestly:

| Status | Meaning | What to do |
|---|---|---|
| `supported` | Available now | — |
| `partiallySupported` | Available within platform limits (time limits, OS scheduling) | Design for interruption |
| `permissionRequired` | The user can grant it | `NativeFlow.permissions.request(c)` from a visible screen |
| `restricted` | Disabled by the user or device policy; the app cannot request it | Explain it, or link to Settings |
| `unavailable` | Not offered here, or not declared in your manifest / Info.plist | Declare it, or don't rely on it |

```dart
final caps = await NativeFlow.capabilities();
if (!caps[RuntimeCapability.overlay]!.isUsable) { /* fall back to a notification */ }
```

## Matrix

| Capability | Android mechanism | Android status | iOS mechanism | iOS status |
|---|---|---|---|---|
| backgroundExecution | Foreground service | supported | Finite background time (~30 s) | partiallySupported |
| persistentRuntime | Foreground service + `START_STICKY` + background engine | supported; partiallySupported on 15+ if only `dataSync` declared | Only via app-declared `location`/`audio`/`voip` mode | partiallySupported if declared, else unavailable |
| network | `ConnectivityManager` callbacks | supported | `NWPathMonitor` | supported |
| location | FGS type `location` | supported / permissionRequired / unavailable (not declared) | App's own location library + background mode | supported / permissionRequired / restricted / unavailable (no usage string) |
| microphone | FGS type `microphone` | same as location | App's own audio library | same pattern |
| audio | FGS type `mediaPlayback` | supported if declared | `audio` background mode | supported if declared |
| notifications | Notification APIs, channels | supported / permissionRequired (13+) / restricted (disabled) | `UNUserNotificationCenter` | supported / permissionRequired / restricted |
| overlay | `TYPE_APPLICATION_OVERLAY` | supported / permissionRequired / unavailable (not declared, Go device) | — | unavailable |
| fullscreen | Full-screen intent (calls/alarms) | supported / permissionRequired (14+) / unavailable | — (use CallKit for calls) | unavailable |
| bootRecovery | `BOOT_COMPLETED` receiver | partiallySupported | — | unavailable |
| liveActivity | — | unavailable | ActivityKit (16.1+) | supported / restricted / unavailable |
| widget | — | unavailable | WidgetKit reloads + App Group | supported |
| backgroundProcessing | JobScheduler | partiallySupported | BGTaskScheduler | partiallySupported / restricted / unavailable |


Statuses are evaluated on the device at call time. A status never claims more
than the OS will actually deliver.

## OEM and battery restrictions (Android)

Some manufacturers (Xiaomi/MIUI, Huawei/EMUI, Oppo/ColorOS, Vivo, Samsung
"Sleeping apps", OnePlus) kill foreground services or block boot receivers
beyond AOSP rules. NativeFlow cannot override that and does not try. It
reports `interrupted`, restores on the next legitimate opportunity (sticky
restart, app launch, reboot opt-in), and posts a "Tap to resume" notification
when the OS refuses. Guide users to the vendor's battery settings
(see dontkillmyapp.com) from your own UI if your use case needs it.

Doze: foreground-service processes keep network access, but the CPU can
sleep between network events; Dart timers may fire late with the screen off.
Use server-driven keepalives or push (FCM) for latency-critical wakeups.
