import 'package:flutter/foundation.dart';

enum NetworkType { none, wifi, cellular, ethernet, vpn, other }

/// Connectivity as reported by the OS (ConnectivityManager / NWPathMonitor).
///
/// `connected` means the OS considers the default network usable; it does
/// not prove that *your* server is reachable. Your adapter still owns
/// reconnect and health checks for its protocol.
@immutable
class NetworkState {
  const NetworkState({
    required this.connected,
    this.type = NetworkType.none,
    this.metered = false,
  });

  final bool connected;
  final NetworkType type;
  final bool metered;

  static const unknown = NetworkState(connected: false);

  factory NetworkState.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return unknown;
    return NetworkState(
      connected: map['connected'] == true,
      type: NetworkType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => NetworkType.other,
      ),
      metered: map['metered'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NetworkState &&
      other.connected == connected &&
      other.type == type &&
      other.metered == metered;

  @override
  int get hashCode => Object.hash(connected, type, metered);

  @override
  String toString() =>
      'NetworkState(${connected ? 'connected' : 'offline'}, ${type.name}'
      '${metered ? ', metered' : ''})';
}
