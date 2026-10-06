/// NativeFlow: a native runtime layer for long-running, event-driven
/// Flutter workloads. NativeFlow owns the runtime; your libraries own the
/// protocol; the OS owns background policy.
library;

export 'src/adapter/adapter_context.dart' show AdapterContext, RecoveryReason;
export 'src/adapter/runtime_adapter.dart';
export 'src/core/errors.dart';
export 'src/core/native_flow.dart';
export 'src/core/runtime.dart'
    show
        BackgroundTaskKind,
        NativeFlowConfig,
        NativeFlowRuntime,
        RuntimeOptions;
export 'src/core/runtime_capability.dart';
export 'src/core/runtime_requirement.dart';
export 'src/core/runtime_session.dart';
export 'src/core/runtime_state.dart';
export 'src/events/runtime_event.dart';
export 'src/events/runtime_event_bus.dart';
export 'src/logging/logger.dart';
export 'src/network/network_state.dart';
export 'src/notification/notifications.dart';
export 'src/overlay/overlay.dart';
export 'src/permissions/permissions.dart';
export 'src/platform/native_flow_platform.dart' show NativeFlowPlatform;
export 'src/presentation/presentation.dart';
export 'src/recovery/recovery_policy.dart';
