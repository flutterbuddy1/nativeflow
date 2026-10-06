# Recovery

NativeFlow provides a **recoverable runtime** with **best-effort persistent
execution**. It never claims "always alive".

## Adapter-level: RecoveryPolicy

```dart
await NativeFlow.initialize(config: const NativeFlowConfig(
  recoveryPolicy: RecoveryPolicy(
    maxAttempts: 10,                     // null = retry forever (with backoff)
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(minutes: 5),
    multiplier: 2.0,
    jitter: 0.2,                         // ±20 % so a fleet doesn't reconnect in lockstep
    waitForNetwork: true,                // hold retries while offline
  ),
));
```

Per adapter: `RuntimeAdapter(recoveryPolicy: ...)`.

Flow after `start` throws or `ctx.reportFailure(e)`:

1. `attempts++`. If the policy is exhausted → `failed` + `adapterFailed` event.
2. Offline and `waitForNetwork` → `waitingForNetwork`. Retried the moment
   `networkAvailable` arrives.
3. Otherwise `recover(adapterFailure)` runs after `delayFor(attempt)`.
4. Success resets `attempts` to 0.

`RecoveryPolicy.none` disables retries.

## Runtime-level

| Situation | Android | iOS |
|---|---|---|
| Process killed by the OS | `START_STICKY` restart → `runtime.recovered{service_restart}` → background engine → adapters `recover` | — |
| Restart loop (5 restarts in 10 min) | Gives up → `interrupted{restartLoop}` | — |
| App relaunched while interrupted | Restored by the UI's `initialize` → `recovered{appLaunch}` | `recovered{appLaunch}` whenever intent was recorded |
| Service time limit (Android 15 `dataSync`) | `interrupted{timeLimit}`, restored on next launch | — |
| Reboot | Only with `restoreOnBoot: true` → `recovered{boot}`. If Android refuses (Android 15 type restrictions), `interrupted{restoreNotAllowed}` + a "Tap to resume" notification | Not possible |
| App update | `recovered{package_replaced}` | — |
| `stop()` | Intent cleared; nothing is ever restored | Same |

Recovery only restores intent the app recorded with `start()`.

## Designing adapters for recovery

- Keep a checkpoint (last server message id) and resume from it in
  `recover`.
- Persist events you must not lose (`persist: true`) and de-duplicate by
  `event.id`.
- Make `stop` idempotent: the default `recover` calls it before `start`.
