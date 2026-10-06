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
  const OverlayNode();
  Map<String, Object?> toMap();
}

enum OverlayAxis { vertical, horizontal }

class OverlayCard extends OverlayNode {
  const OverlayCard({
    this.children = const [],
    this.axis = OverlayAxis.vertical,
    this.background,
    this.cornerRadius = 16,
    this.padding = 12,
    this.actionId,
  });

  final List<OverlayNode> children;
  final OverlayAxis axis;
  final Color? background;
  final double cornerRadius;
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

class OverlayText extends OverlayNode {
  const OverlayText(
    this.text, {
    this.size = 14,
    this.color,
    this.bold = false,
    this.maxLines = 2,
  });

  final String text;
  final double size;
  final Color? color;
  final bool bold;
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

class OverlayButton extends OverlayNode {
  const OverlayButton({required this.actionId, required this.label});

  final String actionId;
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
  const OverlayImage(this.bytes, {this.width = 40, this.height = 40});

  final Uint8List bytes;
  final double width;
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
  const OverlayProgress({this.value});

  final double? value;

  @override
  Map<String, Object?> toMap() => {'t': 'progress', 'value': value};
}

/// Window placement for an overlay. Coordinates are logical pixels from
/// the top-left of the screen.
@immutable
class OverlayWindow {
  const OverlayWindow({
    required this.content,
    this.x = 0,
    this.y = 200,
    this.width,
    this.height,
    this.draggable = true,
  });

  final OverlayNode content;
  final double x;
  final double y;

  /// `null` wraps content.
  final double? width;
  final double? height;
  final bool draggable;

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

  static const maxNodes = 32;

  static int _count(Map<String, Object?> node) =>
      1 +
      ((node['children'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .fold(0, (sum, c) => sum + _count(c));
}

@immutable
class OverlayState {
  const OverlayState({
    required this.visible,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
  });

  final bool visible;
  final double x, y, width, height;

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
  NativeFlowOverlay(this._runtime);

  final NativeFlowRuntime _runtime;

  Future<CapabilityStatus> status() =>
      _runtime.permissions.status(RuntimeCapability.overlay);

  /// Opens the system "Display over other apps" screen.
  Future<CapabilityStatus> requestPermission() =>
      _runtime.permissions.request(RuntimeCapability.overlay);

  Future<void> show(OverlayWindow window) =>
      _invoke(NativeMethod.overlayShow, window.toMap());

  Future<void> update(OverlayNode content) =>
      _invoke(NativeMethod.overlayUpdate, {'content': content.toMap()});

  Future<void> hide() => _invoke(NativeMethod.overlayHide, const {});

  Future<void> move(double x, double y) =>
      _invoke(NativeMethod.overlayMove, {'x': x, 'y': y});

  Future<void> resize(double? width, double? height) =>
      _invoke(NativeMethod.overlayResize, {'width': width, 'height': height});

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
