import '../core/runtime.dart';
import '../core/runtime_capability.dart';
import '../platform/native_flow_platform.dart';

/// `NativeFlow.permissions`. Never requests anything on its own: call
/// [request] (or [requestRequired]) from a user-visible flow.
class NativeFlowPermissions {
  NativeFlowPermissions(this._runtime);

  final NativeFlowRuntime _runtime;

  Future<CapabilityStatus> status(RuntimeCapability capability) =>
      _call(NativeMethod.permissionStatus, capability);

  /// Shows the OS prompt or settings screen for [capability] and returns
  /// the resulting status. Returns immediately if nothing can be requested
  /// (already granted, restricted, unavailable).
  Future<CapabilityStatus> request(RuntimeCapability capability) =>
      _call(NativeMethod.requestPermission, capability);

  /// Requests, one by one, only the capabilities needed by currently
  /// attached adapters that are in [CapabilityStatus.permissionRequired].
  Future<CapabilityReport> requestRequired() async {
    final result = <RuntimeCapability, CapabilityStatus>{};
    for (final c in _runtime.requirements.capabilities) {
      var s = await status(c);
      if (s == CapabilityStatus.permissionRequired) s = await request(c);
      result[c] = s;
    }
    return result;
  }

  Future<CapabilityStatus> _call(String method, RuntimeCapability c) async {
    _runtime.ensureInitialized();
    return CapabilityStatus.parse(
      await _runtime.platform.invoke<String>(method, {'capability': c.name}),
    );
  }
}
