import 'dart:developer' as developer;

/// Severity of a single log record.
enum LogLevel { debug, info, warning, error }

/// How much NativeFlow logs. Also forwarded to the native runtime.
enum LogVerbosity {
  disabled,
  errors,
  normal,
  verbose;

  bool allows(LogLevel level) => switch (this) {
    LogVerbosity.disabled => false,
    LogVerbosity.errors => level == LogLevel.error,
    LogVerbosity.normal => level != LogLevel.debug,
    LogVerbosity.verbose => true,
  };
}

/// Receives log records. Replace to route NativeFlow logs into your own
/// logging stack.
typedef LogSink = void Function(
  LogLevel level,
  String message, {
  Map<String, Object?>? fields,
  Object? error,
});

/// Structured logger used by NativeFlow.
///
/// Records carry a message and a small map of non-sensitive fields
/// (ids, states, counts). Event payloads, tokens and headers are never
/// passed to the logger by NativeFlow itself.
class NativeFlowLogger {
  NativeFlowLogger({this.verbosity = LogVerbosity.errors, LogSink? sink})
    : sink = sink ?? _defaultSink;

  LogVerbosity verbosity;
  LogSink sink;

  void debug(String message, [Map<String, Object?>? fields]) =>
      _log(LogLevel.debug, message, fields);
  void info(String message, [Map<String, Object?>? fields]) =>
      _log(LogLevel.info, message, fields);
  void warning(String message, [Map<String, Object?>? fields]) =>
      _log(LogLevel.warning, message, fields);
  void error(String message, {Object? error, Map<String, Object?>? fields}) =>
      _log(LogLevel.error, message, fields, error);

  void _log(
    LogLevel level,
    String message,
    Map<String, Object?>? fields, [
    Object? error,
  ]) {
    if (verbosity.allows(level)) {
      sink(level, message, fields: fields, error: error);
    }
  }

  static void _defaultSink(
    LogLevel level,
    String message, {
    Map<String, Object?>? fields,
    Object? error,
  }) {
    developer.log(
      fields == null || fields.isEmpty ? message : '$message $fields',
      name: 'nativeflow',
      level: switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
      },
      error: error,
    );
  }
}
