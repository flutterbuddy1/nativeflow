import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../core/runtime.dart';
import '../core/runtime_capability.dart';
import '../core/validation.dart';
import '../events/runtime_event.dart';
import '../platform/native_flow_platform.dart';

/// Declarative overlay UI, rendered with native Android views.
///
/// Overlays outlive the Flutter UI (a driver's floating bubble must work
/// while the app is closed), so they cannot depend on a Flutter engine.
/// The node set is intentionally small and bounded.
sealed class OverlayNode {
  /// Base constructor for node subclasses.
  const OverlayNode();

  /// Serializes this node for the native renderer.
  Map<String, Object?> toMap();
}

/// Layout direction of an [OverlayCard].
enum OverlayAxis {
  /// Top to bottom.
  vertical,

  /// Start to end.
  horizontal,
}

/// A rounded container laying out [children] along [axis].
class OverlayCard extends OverlayNode {
  /// Creates a card.
  const OverlayCard({
    this.children = const [],
    this.axis = OverlayAxis.vertical,
    this.background,
    this.cornerRadius = 16,
    this.padding = 12,
    this.actionId,
  });

  /// Child nodes, in order.
  final List<OverlayNode> children;

  /// Direction in which [children] are laid out.
  final OverlayAxis axis;

  /// Fill color; `null` uses the native default.
  final Color? background;

  /// Corner radius in logical pixels.
  final double cornerRadius;

  /// Inner padding in logical pixels.
  final double padding;

  /// Emitted as an overlay action when the card itself is tapped.
  final String? actionId;

  @override
  Map<String, Object?> toMap() => {
    't': 'card',
    'children': [for (final c in children) c.toMap()],
    'axis': axis.name,
    'background': background?.toARGB32(),
    'cornerRadius': cornerRadius,
    'padding': padding,
    'actionId': actionId == null ? null : validateId(actionId!, 'action id'),
  };
}

/// A text label.
class OverlayText extends OverlayNode {
  /// Creates a text label.
  const OverlayText(
    this.text, {
    this.size = 14,
    this.color,
    this.bold = false,
    this.maxLines = 2,
  });

  /// The text shown.
  final String text;

  /// Font size in logical pixels.
  final double size;

  /// Text color; `null` uses the native default.
  final Color? color;

  /// Whether the text is bold.
  final bool bold;

  /// Lines shown before the text is truncated.
  final int maxLines;

  @override
  Map<String, Object?> toMap() => {
    't': 'text',
    'text': text,
    'size': size,
    'color': color?.toARGB32(),
    'bold': bold,
    'maxLines': maxLines,
  };
}

/// A button. Taps arrive as [RuntimeEventType.overlayAction] events with
/// `payload['actionId']`.
class OverlayButton extends OverlayNode {
  /// Creates a button reporting [actionId] when tapped.
  const OverlayButton({required this.actionId, required this.label});

  /// Closes the overlay natively (works without Flutter) and emits
  /// [RuntimeEventType.overlayClosed].
  const OverlayButton.close({this.label = 'Close'}) : actionId = closeActionId;

  /// Action id reserved for [OverlayButton.close].
  static const closeActionId = 'close';

  /// Id reported when tapped; 1-64 chars of `[A-Za-z0-9_.:-]`.
  final String actionId;

  /// Button text.
  final String label;

  @override
  Map<String, Object?> toMap() => {
    't': 'button',
    'actionId': validateId(actionId, 'action id'),
    'label': label,
  };
}

/// PNG/JPEG bytes, at most 256 KB.
class OverlayImage extends OverlayNode {
  /// Creates an image from encoded [bytes].
  const OverlayImage(this.bytes, {this.width = 40, this.height = 40});

  /// Encoded PNG or JPEG data.
  final Uint8List bytes;

  /// Width in logical pixels.
  final double width;

  /// Height in logical pixels.
  final double height;

  @override
  Map<String, Object?> toMap() {
    if (bytes.lengthInBytes > 256 * 1024) {
      throw const NativeFlowException(
        NativeFlowErrorCode.invalidArgument,
        'Overlay images are limited to 256 KB.',
      );
    }
    return {'t': 'image', 'bytes': bytes, 'width': width, 'height': height};
  }
}

/// [value] in 0..1, or `null` for indeterminate.
class OverlayProgress extends OverlayNode {
  /// Creates a progress indicator.
  const OverlayProgress({this.value});

  /// Progress in 0..1, or `null` for indeterminate.
  final double? value;

  @override
  Map<String, Object?> toMap() => {'t': 'progress', 'value': value};
}

/// Window placement for an overlay. Coordinates are logical pixels from
/// the top-left of the screen.
@immutable
class OverlayWindow {
  /// Creates a window description.
  const OverlayWindow({
    required this.content,
    this.x = 0,
    this.y = 200,
    this.width,
    this.height,
    this.draggable = true,
  });

  /// Root node of the overlay content.
  final OverlayNode content;

  /// Left edge in logical pixels.
  final double x;

  /// Top edge in logical pixels.
  final double y;

  /// Width in logical pixels; `null` wraps content.
  final double? width;

  /// Height in logical pixels; `null` wraps content.
  final double? height;

  /// Whether the user can drag the window.
  final bool draggable;

  /// Serializes this window. Throws [NativeFlowException] with
  /// `invalidArgument` if the content exceeds [maxNodes] or contains an
  /// invalid node.
  Map<String, Object?> toMap() {
    final content = this.content.toMap();
    if (_count(content) > maxNodes) {
      throw const NativeFlowException(
        NativeFlowErrorCode.invalidArgument,
        'Overlays are limited to $maxNodes nodes.',
      );
    }
    return {
      'content': content,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'draggable': draggable,
    };
  }

  /// Maximum number of nodes in one overlay tree.
  static const maxNodes = 32;

  static int _count(Map<String, Object?> node) =>
      1 +
      ((node['children'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .fold(0, (sum, c) => sum + _count(c));
}

/// Current position, size and visibility of the overlay window.
@immutable
class OverlayState {
  /// Creates an overlay state.
  const OverlayState({
    required this.visible,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
  });

  /// Whether the overlay is shown.
  final bool visible;

  /// Position and size in logical pixels; zero when not visible.
  final double x, y, width, height;

  /// Decodes a native state map; `null` gives a hidden state.
  factory OverlayState.fromMap(Map<Object?, Object?>? m) => m == null
      ? const OverlayState(visible: false)
      : OverlayState(
          visible: m['visible'] == true,
          x: (m['x'] as num?)?.toDouble() ?? 0,
          y: (m['y'] as num?)?.toDouble() ?? 0,
          width: (m['width'] as num?)?.toDouble() ?? 0,
          height: (m['height'] as num?)?.toDouble() ?? 0,
        );
}

/// `NativeFlow.overlay` (Android). One overlay window per app; it is
/// restored with the runtime after process recreation.
///
/// Requires `SYSTEM_ALERT_WINDOW` in the app manifest and the user's
/// "Display over other apps" grant. On iOS every call throws
/// [NativeFlowErrorCode.unavailable].
class NativeFlowOverlay {
  /// Creates the controller. Use `NativeFlow.overlay` instead.
  NativeFlowOverlay(this._runtime);

  final NativeFlowRuntime _runtime;

  /// Status of [RuntimeCapability.overlay].
  Future<CapabilityStatus> status() =>
      _runtime.permissions.status(RuntimeCapability.overlay);

  /// Opens the system "Display over other apps" screen.
  Future<CapabilityStatus> requestPermission() =>
      _runtime.permissions.request(RuntimeCapability.overlay);

  /// Shows [window], replacing any overlay already shown. Throws
  /// [NativeFlowException] with `invalidArgument` if it exceeds
  /// [OverlayWindow.maxNodes] or contains an invalid node.
  Future<void> show(OverlayWindow window) =>
      _invoke(NativeMethod.overlayShow, window.toMap());

  /// Replaces the content of the shown overlay with [content].
  Future<void> update(OverlayNode content) =>
      _invoke(NativeMethod.overlayUpdate, {'content': content.toMap()});

  /// Removes the overlay window.
  Future<void> hide() => _invoke(NativeMethod.overlayHide, const {});

  /// Moves the overlay window to ([x], [y]) in logical pixels.
  Future<void> move(double x, double y) =>
      _invoke(NativeMethod.overlayMove, {'x': x, 'y': y});

  /// Resizes the overlay window; `null` wraps content.
  Future<void> resize(double? width, double? height) =>
      _invoke(NativeMethod.overlayResize, {'width': width, 'height': height});

  /// Current position, size and visibility of the overlay window.
  Future<OverlayState> state() async {
    _runtime.ensureInitialized();
    return OverlayState.fromMap(
      await _runtime.platform.invoke<Map<Object?, Object?>>(
        NativeMethod.overlayState,
      ),
    );
  }

  /// Button/card taps; `payload['actionId']`.
  Stream<RuntimeEvent> get actions =>
      _runtime.bus.on(RuntimeEventType.overlayAction);

  /// The overlay was removed by the user (close button / drag to dismiss).
  Stream<RuntimeEvent> get closed =>
      _runtime.bus.on(RuntimeEventType.overlayClosed);

  Future<void> _invoke(String method, Map<String, Object?> args) {
    _runtime.ensureInitialized();
    return _runtime.platform.invoke<void>(method, args);
  }
}
