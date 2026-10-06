/// Machine-readable reason for a [NativeFlowException].
enum NativeFlowErrorCode {
  notInitialized,
  invalidArgument,
  duplicateAdapter,
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

class NativeFlowException implements Exception {
  const NativeFlowException(this.code, this.message, {this.details});

  final NativeFlowErrorCode code;
  final String message;
  final Object? details;

  @override
  String toString() => 'NativeFlowException(${code.name}): $message';
}
