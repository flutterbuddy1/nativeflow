import 'package:flutter/foundation.dart';

import 'runtime_capability.dart';

/// Immutable description of what an adapter needs from the runtime.
///
/// The runtime aggregates the requirements of every attached adapter into
/// a single native session (one Android foreground service, one iOS
/// background configuration), never one per adapter.
@immutable
class RuntimeRequirements {
  /// Creates requirements for [capabilities].
  const RuntimeRequirements({this.capabilities = const {}});

  /// Capabilities the adapter needs.
  final Set<RuntimeCapability> capabilities;

  /// No requirements.
  static const none = RuntimeRequirements();

  /// Union of all [requirements].
  static RuntimeRequirements merge(Iterable<RuntimeRequirements> requirements) {
    return RuntimeRequirements(
      capabilities: {for (final r in requirements) ...r.capabilities},
    );
  }

  /// Whether [capability] is required.
  bool requires(RuntimeCapability capability) =>
      capabilities.contains(capability);

  /// Serializes these requirements for the platform channel.
  Map<String, Object?> toMap() => {
    'capabilities': [for (final c in capabilities) c.name]..sort(),
  };

  @override
  bool operator ==(Object other) =>
      other is RuntimeRequirements &&
      setEquals(other.capabilities, capabilities);

  @override
  int get hashCode => Object.hashAllUnordered(capabilities);

  @override
  String toString() =>
      'RuntimeRequirements(${capabilities.map((c) => c.name).join(', ')})';
}
