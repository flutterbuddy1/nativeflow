# Permissions

NativeFlow **never requests a permission on its own** and never declares a
dangerous permission for you (except `POST_NOTIFICATIONS`, which it requests
only when asked).

```dart
final s = await NativeFlow.permissions.status(RuntimeCapability.location);
final after = await NativeFlow.permissions.request(RuntimeCapability.overlay);

// Requests, one by one, only capabilities that attached adapters require
// and that are currently permissionRequired:
final report = await NativeFlow.permissions.requestRequired();
```

`request` returns immediately with the current status when nothing can be
requested (already granted, `restricted`, `unavailable`, or no visible
activity on Android).

| Capability | Android request | iOS request |
|---|---|---|
| notifications | `POST_NOTIFICATIONS` prompt (13+) | Authorization prompt |
| location | Fine + coarse prompt (while-in-use) | Not requested by NativeFlow: use your location library |
| microphone | `RECORD_AUDIO` prompt | Not requested by NativeFlow: use your audio library |
| overlay | "Display over other apps" settings screen | — |
| fullscreen | "Full-screen intents" settings screen (14+) | — |

Why location and microphone are not requested on iOS: statically linking
CoreLocation/AVFoundation would make App Store Connect demand purpose strings
from every app using NativeFlow. NativeFlow reads their status dynamically.

## Start-time checks (Android)

Android 14+ crashes a foreground service started with the `location` or
`microphone` type without the matching permission. NativeFlow checks first:
`start()` and `attach()` throw `NativeFlowException(permissionRequired)` instead.

```dart
await NativeFlow.permissions.requestRequired();
await NativeFlow.start();
```
