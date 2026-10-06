import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../core/runtime.dart';
import '../core/validation.dart';
import '../events/runtime_event.dart';
import '../platform/native_flow_platform.dart';

enum NotificationImportance { min, low, normal, high }

/// Android notification channel (Android 8+). Ignored on iOS.
@immutable
class NotificationChannel {
  const NotificationChannel({
    required this.id,
    required this.name,
    this.description,
    this.importance = NotificationImportance.normal,
  });

  final String id;
  final String name;
  final String? description;

  /// `high` enables heads-up display.
  final NotificationImportance importance;

  Map<String, Object?> toMap() => {
    'id': validateId(id, 'channel id'),
    'name': name,
    'description': description,
    'importance': importance.name,
  };
}

/// A button on a notification. Taps arrive as
/// [RuntimeEventType.notificationAction] events, even if they happened
/// while Flutter was not running.
@immutable
class NotificationAction {
  const NotificationAction({
    required this.id,
    required this.label,
    this.opensApp = false,
  });

  final String id;
  final String label;

  /// Bring the app to the foreground when tapped.
  final bool opensApp;

  Map<String, Object?> toMap() => {
    'id': validateId(id, 'action id'),
    'label': label,
    'opensApp': opensApp,
  };
}

/// Why a notification may take over the screen. Android only allows
/// full-screen intents for these cases (and requires the user-grantable
/// USE_FULL_SCREEN_INTENT permission on Android 14+).
enum FullScreenReason { incomingCall, alarm }

@immutable
class RuntimeNotification {
  const RuntimeNotification({
    required this.id,
    required this.title,
    this.body,
    this.channelId,
    this.actions = const [],
    this.deepLink,
    this.group,
    this.ongoing = false,
    this.fullScreen,
    this.payload = const {},
  });

  /// Positive id; reuse it to update the notification. Id 1 is reserved
  /// for the runtime's foreground notification on Android.
  final int id;
  final String title;
  final String? body;
  final String? channelId;
  final List<NotificationAction> actions;

  /// Opened in the app when the notification body is tapped. Delivered as
  /// `payload['deepLink']` on the tap event and as the launch intent data.
  final Uri? deepLink;

  /// Android group key / iOS thread identifier.
  final String? group;
  final bool ongoing;

  /// Request a full-screen presentation (Android only). Falls back to a
  /// heads-up notification when the capability is not granted.
  final FullScreenReason? fullScreen;

  /// Small JSON payload returned with tap/action events.
  final Map<String, Object?> payload;

  Map<String, Object?> toMap() {
    if (id <= reservedForegroundId) {
      throw const NativeFlowException(
        NativeFlowErrorCode.invalidArgument,
        'Notification ids must be greater than $reservedForegroundId.',
      );
    }
    if (actions.length > 3) {
      throw const NativeFlowException(
        NativeFlowErrorCode.invalidArgument,
        'At most 3 notification actions are supported.',
      );
    }
    return {
      'id': id,
      'title': title,
      'body': body,
      'channelId': channelId == null
          ? null
          : validateId(channelId!, 'channel id'),
      'actions': [for (final a in actions) a.toMap()],
      'deepLink': deepLink?.toString(),
      'group': group,
      'ongoing': ongoing,
      'fullScreen': fullScreen?.name,
      'payload': validatePayload(payload),
    };
  }

  static const reservedForegroundId = 1;
}

/// The Android foreground-service notification shown while the runtime is
/// running. The OS requires it; keep it honest about what the app is doing.
@immutable
class ForegroundNotification {
  const ForegroundNotification({
    this.title,
    this.body,
    this.channelId,
    this.actions = const [],
    this.smallIcon,
  });

  /// Defaults to the app's name.
  final String? title;
  final String? body;

  /// Defaults to a low-importance "Background activity" channel.
  final String? channelId;
  final List<NotificationAction> actions;

  /// Android drawable resource name. Defaults to the app icon.
  final String? smallIcon;

  Map<String, Object?> toMap() => {
    'title': title,
    'body': body,
    'channelId': channelId == null
        ? null
        : validateId(channelId!, 'channel id'),
    'actions': [for (final a in actions) a.toMap()],
    'smallIcon': smallIcon,
  };
}

/// `NativeFlow.notifications`. Rendering is native, so notifications and
/// their actions work while Flutter is not running.
class NativeFlowNotifications {
  NativeFlowNotifications(this._runtime);

  final NativeFlowRuntime _runtime;

  Future<void> createChannel(NotificationChannel channel) =>
      _invoke(NativeMethod.createChannel, channel.toMap());

  Future<void> show(RuntimeNotification notification) =>
      _invoke(NativeMethod.showNotification, notification.toMap());

  Future<void> cancel(int id) =>
      _invoke(NativeMethod.cancelNotification, {'id': id});

  /// Body taps. `payload` contains `notificationId`, `deepLink` and the
  /// notification's own payload under `data`.
  Stream<RuntimeEvent> get taps =>
      _runtime.bus.on(RuntimeEventType.notificationTapped);

  /// Action button taps. `payload['actionId']` identifies the button.
  Stream<RuntimeEvent> get actions =>
      _runtime.bus.on(RuntimeEventType.notificationAction);

  Future<void> _invoke(String method, Map<String, Object?> args) {
    _runtime.ensureInitialized();
    return _runtime.platform.invoke<void>(method, args);
  }
}
