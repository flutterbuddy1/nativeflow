import 'package:flutter/services.dart';

import '../core/errors.dart';

/// Names of every command the native runtimes accept. Native dispatch is a
/// closed whitelist of exactly these names.
abstract final class NativeMethod {
  static const initialize = 'initialize';
  static const capabilities = 'capabilities';
  static const start = 'start';
  static const stop = 'stop';
  static const setRequirements = 'setRequirements';
  static const appendEvent = 'appendEvent';
  static const pendingEvents = 'pendingEvents';
  static const ackEvents = 'ackEvents';
  static const permissionStatus = 'permissionStatus';
  static const requestPermission = 'requestPermission';
  static const createChannel = 'createChannel';
  static const showNotification = 'showNotification';
  static const cancelNotification = 'cancelNotification';
  static const overlayShow = 'overlayShow';
  static const overlayUpdate = 'overlayUpdate';
  static const overlayHide = 'overlayHide';
  static const overlayMove = 'overlayMove';
  static const overlayResize = 'overlayResize';
  static const overlayState = 'overlayState';
  static const present = 'present';
  static const activityStart = 'activityStart';
  static const activityUpdate = 'activityUpdate';
  static const activityEnd = 'activityEnd';
  static const widgetUpdate = 'widgetUpdate';
  static const scheduleBackgroundTask = 'scheduleBackgroundTask';
  static const completeBackgroundTask = 'completeBackgroundTask';

  /// Native → Dart (Android): stop adapters in this engine because another
  /// engine is taking ownership.
  static const release = 'release';
}

/// Transport between the Dart API and a native runtime.
abstract class NativeFlowPlatform {
  /// Commands. Throws [NativeFlowException] on failure.
  Future<T?> invoke<T>(String method, [Map<String, Object?>? arguments]);

  /// Batches of events pushed by the native runtime.
  Stream<List<Object?>> get events;

  /// Handles calls initiated by the native runtime.
  void setCallHandler(Future<Object?> Function(String method) handler);
}

class MethodChannelNativeFlowPlatform implements NativeFlowPlatform {
  static const _methods = MethodChannel('dev.nativeflow/runtime');
  static const _events = EventChannel('dev.nativeflow/events');

  @override
  Future<T?> invoke<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw NativeFlowException(
        _codes[e.code] ?? NativeFlowErrorCode.platform,
        e.message ?? e.code,
        details: e.details,
      );
    } on MissingPluginException {
      throw const NativeFlowException(
        NativeFlowErrorCode.unavailable,
        'NativeFlow has no native implementation on this platform.',
      );
    }
  }

  @override
  late final Stream<List<Object?>> events = _events
      .receiveBroadcastStream()
      .map((batch) => batch as List<Object?>);

  @override
  void setCallHandler(Future<Object?> Function(String method) handler) {
    _methods.setMethodCallHandler((call) => handler(call.method));
  }

  static const _codes = {
    'invalid_argument': NativeFlowErrorCode.invalidArgument,
    'permission_required': NativeFlowErrorCode.permissionRequired,
    'unavailable': NativeFlowErrorCode.unavailable,
    'not_allowed': NativeFlowErrorCode.notAllowed,
    'not_initialized': NativeFlowErrorCode.notInitialized,
  };
}
