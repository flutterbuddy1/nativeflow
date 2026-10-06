# Logging

```dart
await NativeFlow.initialize(config: const NativeFlowConfig(
  logVerbosity: LogVerbosity.normal, // disabled | errors (default) | normal | verbose
));

NativeFlow.logger.verbosity = LogVerbosity.verbose;         // change at runtime (Dart)
NativeFlow.logger.sink = (level, message, {fields, error}) { // route to your logger
  myLogger.log(level.name, message, fields, error);
};
```

| Verbosity | Levels emitted |
|---|---|
| `disabled` | none |
| `errors` | error |
| `normal` | info, warning, error |
| `verbose` | debug, info, warning, error |

The verbosity passed to `initialize` is also applied to native logs: tag
`NativeFlow` in logcat, prefix `[NativeFlow]` in the iOS console.

## What is never logged

Records carry only ids, states, counts and error types. NativeFlow never logs:

- event payloads (`RuntimeEvent.toString()` omits them)
- notification content
- exception messages from your adapters (only the exception type)
- tokens, headers or credentials of any kind

Your own `ctx.logger` calls are your responsibility. Pass fields, not secrets.
