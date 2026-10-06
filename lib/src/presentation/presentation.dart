import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../core/runtime.dart';
import '../core/runtime_capability.dart';
import '../notification/notifications.dart';
import '../platform/native_flow_platform.dart';

/// Platform-neutral "show the user what the runtime is doing".
///
/// You state intent; the platform picks the surface:
/// * Android — updates the foreground-service notification (or posts a
///   regular notification when the runtime is not running).
/// * iOS — updates the current Live Activity when one is running and
///   enabled, otherwise posts a notification.
@immutable
class RuntimePresentation {
  /// Creates a presentation.
  const RuntimePresentation({
    required this.title,
    this.body,
    this.progress,
    this.actions = const [],
    this.values = const {},
  });

  /// Title text.
  final String title;

  /// Body text.
  final String? body;

  /// 0..1, shown as a progress bar where supported.
  final double? progress;

  /// Action buttons, where the surface supports them.
  final List<NotificationAction> actions;

  /// Extra string values for Live Activity content state (iOS).
  final Map<String, String> values;

  /// Serializes this presentation for the platform channel.
  Map<String, Object?> toMap() => {
    'title': title,
    'body': body,
    'progress': progress,
    'actions': [for (final a in actions) a.toMap()],
    'values': values,
  };
}

/// `NativeFlow.activities` — iOS Live Activities and widget refresh.
///
/// Live Activities require iOS 16.1+, `NSSupportsLiveActivities` in the
/// app's Info.plist, and a Widget Extension that declares
/// `NativeFlowActivityAttributes` (see docs/PLATFORM_CAPABILITIES.md).
/// On Android, [start]/[update]/[end] throw
/// [NativeFlowErrorCode.unavailable]; use `NativeFlow.present`.
class NativeFlowActivities {
  /// Creates the controller. Use `NativeFlow.activities` instead.
  NativeFlowActivities(this._runtime);

  final NativeFlowRuntime _runtime;

  /// Status of [RuntimeCapability.liveActivity].
  Future<CapabilityStatus> status() =>
      _runtime.permissions.status(RuntimeCapability.liveActivity);

  /// Starts a Live Activity and returns its id. [attributes] are fixed for
  /// the activity's lifetime; [state] can change via [update].
  Future<String> start({
    Map<String, String> attributes = const {},
    required Map<String, String> state,
  }) async {
    final id = await _invoke<String>(NativeMethod.activityStart, {
      'attributes': attributes,
      'state': state,
    });
    if (id == null) {
      throw const NativeFlowException(
        NativeFlowErrorCode.platform,
        'Live Activity did not start.',
      );
    }
    return id;
  }

  /// Replaces the content state of the Live Activity [activityId].
  Future<void> update(String activityId, Map<String, String> state) =>
      _invoke<void>(NativeMethod.activityUpdate, {
        'activityId': activityId,
        'state': state,
      });

  /// Ends the Live Activity [activityId], optionally showing [finalState].
  Future<void> end(String activityId, {Map<String, String>? finalState}) =>
      _invoke<void>(NativeMethod.activityEnd, {
        'activityId': activityId,
        'state': finalState,
      });

  /// Writes [data] to the shared App Group `UserDefaults` under [key] and
  /// reloads widget timelines ([kind] or all). iOS only.
  Future<void> updateWidget({
    required String appGroup,
    required String key,
    required Map<String, String> data,
    String? kind,
  }) => _invoke<void>(NativeMethod.widgetUpdate, {
    'appGroup': appGroup,
    'key': key,
    'data': data,
    'kind': kind,
  });

  Future<T?> _invoke<T>(String method, Map<String, Object?> args) {
    _runtime.ensureInitialized();
    return _runtime.platform.invoke<T>(method, args);
  }
}
