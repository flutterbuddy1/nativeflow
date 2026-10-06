# Overlays (Android)

A floating window over other apps, such as a driver's status bubble. It is
rendered with **native views** from a small declarative tree, so it keeps
working when no Flutter engine exists. It is restored with the runtime after
process recreation.

On iOS every call throws `unavailable`; iOS has no equivalent. Use a
[Live Activity](presentation.md).

## Setup

```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
```

```dart
if (await NativeFlow.overlay.status() == CapabilityStatus.permissionRequired) {
  await NativeFlow.overlay.requestPermission(); // opens "Display over other apps"
}
```

`unavailable` means it is not declared, or the device is a low-RAM (Go) device.

## Content

| Node | Properties |
|---|---|
| `OverlayCard` | `children`, `axis` (vertical/horizontal), `background`, `cornerRadius`, `padding`, `actionId` (tap) |
| `OverlayText` | `text`, `size`, `color`, `bold`, `maxLines` |
| `OverlayButton` | `actionId`, `label`; `OverlayButton.close()` hides natively |
| `OverlayImage` | PNG/JPEG `bytes` (≤ 256 KB), `width`, `height` |
| `OverlayProgress` | `value` 0..1, or null for indeterminate |

At most 32 nodes. Sizes are logical pixels.

## Control

```dart
await NativeFlow.overlay.show(const OverlayWindow(
  x: 16, y: 180, draggable: true,
  content: OverlayCard(children: [
    OverlayText('Online · 2 requests', bold: true),
    OverlayProgress(),
    OverlayButton(actionId: 'go_offline', label: 'Go offline'),
    OverlayButton.close(),
  ]),
));
await NativeFlow.overlay.update(newContent);     // same window, new content
await NativeFlow.overlay.move(200, 400);
await NativeFlow.overlay.resize(260, null);       // null = wrap content
final s = await NativeFlow.overlay.state();       // visible, x, y, width, height
await NativeFlow.overlay.hide();

NativeFlow.overlay.actions.listen((e) => handle(e.payload['actionId']));
NativeFlow.overlay.closed.listen((_) => ...);
```

Dragging beyond the touch slop moves the window; the position is persisted.
Taps on buttons and cards are persisted events, delivered even if the app is
dead at the time.

## Why not Flutter widgets?

A Flutter-rendered overlay needs a running engine, and the moment you need
the overlay most (app closed) is exactly when there may be none. An optional
engine-backed overlay with a native fallback is on the [roadmap](ROADMAP.md).
