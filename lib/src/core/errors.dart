/// Machine-readable reason for a [NativeFlowException].
enum NativeFlowErrorCode {
  /// A NativeFlow API was used before `NativeFlow.initialize` completed.
  notInitialized,

  /// An argument failed validation (id format, payload size or shape, limits).
  invalidArgument,

  /// An adapter with the same id is already attached.
  duplicateAdapter,

  /// No adapter with the given id is attached.
  unknownAdapter,

  /// A capability required by the requested operation needs a permission
  /// the user has not granted.
  permissionRequired,

  /// The capability does not exist on this platform/device/configuration.
  unavailable,

  /// The OS refused the operation (e.g. starting a foreground service from
  /// the background on Android 12+).
  notAllowed,

  /// Any other native failure.
  platform,
}

/// Error thrown by NativeFlow APIs.
///
/// Native failures are mapped to a [NativeFlowErrorCode]; branch on [code],
/// not on [message].
class NativeFlowException implements Exception {
  /// Creates an exception with [code], a human-readable [message] and
  /// optional [details].
  const NativeFlowException(this.code, this.message, {this.details});

  /// Machine-readable reason for the failure.
  final NativeFlowErrorCode code;

  /// Human-readable description, for logs. Not meant to be parsed.
  final String message;

  /// Optional extra data supplied by the native layer.
  final Object? details;

  @override
  String toString() => 'NativeFlowException(${code.name}): $message';
}
