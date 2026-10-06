import 'dart:developer' as developer;

/// Severity of a single log record.
enum LogLevel {
  /// Detailed diagnostics.
  debug,

  /// Notable lifecycle steps.
  info,

  /// Recoverable problems.
  warning,

  /// Failures.
  error,
}

/// How much NativeFlow logs. Also forwarded to the native runtime.
enum LogVerbosity {
  /// Log nothing.
  disabled,

  /// Errors only.
  errors,

  /// Everything except debug records.
  normal,

  /// Everything.
  verbose;

  /// Whether a record at [level] is logged.
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
  /// Creates a logger. [sink] defaults to `dart:developer` `log`.
  NativeFlowLogger({this.verbosity = LogVerbosity.errors, LogSink? sink})
    : sink = sink ?? _defaultSink;

  /// Current verbosity; records below it are dropped.
  LogVerbosity verbosity;

  /// Where records are written.
  LogSink sink;

  /// Logs a debug record.
  void debug(String message, [Map<String, Object?>? fields]) =>
      _log(LogLevel.debug, message, fields);

  /// Logs an informational record.
  void info(String message, [Map<String, Object?>? fields]) =>
      _log(LogLevel.info, message, fields);

  /// Logs a warning.
  void warning(String message, [Map<String, Object?>? fields]) =>
      _log(LogLevel.warning, message, fields);

  /// Logs an error, with an optional [error] object.
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
