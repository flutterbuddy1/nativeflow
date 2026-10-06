import 'package:flutter/services.dart';

import '../core/errors.dart';

/// Names of every command the native runtimes accept. Native dispatch is a
/// closed whitelist of exactly these names.
abstract final class NativeMethod {
  /// `initialize`: Connects an engine and returns the native state snapshot.
  static const initialize = 'initialize';

  /// `capabilities`: Reports the status of every capability.
  static const capabilities = 'capabilities';

  /// `start`: Starts the native runtime.
  static const start = 'start';

  /// `stop`: Stops the native runtime and clears the intent to run.
  static const stop = 'stop';

  /// `setRequirements`: Updates the aggregated requirements of a running runtime.
  static const setRequirements = 'setRequirements';

  /// `appendEvent`: Persists an application event in the event store.
  static const appendEvent = 'appendEvent';

  /// `pendingEvents`: Returns a page of unacknowledged persisted events.
  static const pendingEvents = 'pendingEvents';

  /// `ackEvents`: Acknowledges persisted events up to an id.
  static const ackEvents = 'ackEvents';

  /// `permissionStatus`: Reports the status of one capability.
  static const permissionStatus = 'permissionStatus';

  /// `requestPermission`: Requests the permission for one capability.
  static const requestPermission = 'requestPermission';

  /// `createChannel`: Creates an Android notification channel.
  static const createChannel = 'createChannel';

  /// `showNotification`: Shows a notification.
  static const showNotification = 'showNotification';

  /// `cancelNotification`: Cancels a notification.
  static const cancelNotification = 'cancelNotification';

  /// `overlayShow`: Shows the overlay window.
  static const overlayShow = 'overlayShow';

  /// `overlayUpdate`: Replaces the overlay content.
  static const overlayUpdate = 'overlayUpdate';

  /// `overlayHide`: Hides the overlay window.
  static const overlayHide = 'overlayHide';

  /// `overlayMove`: Moves the overlay window.
  static const overlayMove = 'overlayMove';

  /// `overlayResize`: Resizes the overlay window.
  static const overlayResize = 'overlayResize';

  /// `overlayState`: Reports the overlay window state.
  static const overlayState = 'overlayState';

  /// `present`: Shows a [RuntimePresentation].
  static const present = 'present';

  /// `activityStart`: Starts a Live Activity.
  static const activityStart = 'activityStart';

  /// `activityUpdate`: Updates a Live Activity.
  static const activityUpdate = 'activityUpdate';

  /// `activityEnd`: Ends a Live Activity.
  static const activityEnd = 'activityEnd';

  /// `widgetUpdate`: Writes widget data and reloads widget timelines.
  static const widgetUpdate = 'widgetUpdate';

  /// `scheduleBackgroundTask`: Schedules an OS background task.
  static const scheduleBackgroundTask = 'scheduleBackgroundTask';

  /// `completeBackgroundTask`: Completes an OS background task.
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

/// [NativeFlowPlatform] over the `dev.nativeflow/runtime` method channel and
/// the `dev.nativeflow/events` event channel. Maps `PlatformException` codes
/// to [NativeFlowErrorCode]s.
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
