import 'package:flutter/foundation.dart';

/// Transport of the default network.
enum NetworkType {
  /// No network.
  none,

  /// Wi-Fi.
  wifi,

  /// Cellular data.
  cellular,

  /// Wired Ethernet.
  ethernet,

  /// A VPN.
  vpn,

  /// Any other or unrecognized transport.
  other,
}

/// Connectivity as reported by the OS (ConnectivityManager / NWPathMonitor).
///
/// `connected` means the OS considers the default network usable; it does
/// not prove that *your* server is reachable. Your adapter still owns
/// reconnect and health checks for its protocol.
@immutable
class NetworkState {
  /// Creates a network state.
  const NetworkState({
    required this.connected,
    this.type = NetworkType.none,
    this.metered = false,
  });

  /// Whether the OS considers the default network usable.
  final bool connected;

  /// Transport of the default network.
  final NetworkType type;

  /// Whether the network is metered.
  final bool metered;

  /// State before the native runtime has reported anything.
  static const unknown = NetworkState(connected: false);

  /// Decodes a native network map; `null` gives [unknown].
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
