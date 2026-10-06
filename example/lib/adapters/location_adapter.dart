import 'dart:async';

import 'package:nativeflow/nativeflow.dart';

/// A position from whatever location library you use (geolocator,
/// location, background_location...).
typedef Fix = ({double lat, double lng, DateTime at});

/// Location tracking architecture without NativeFlow owning GPS.
///
/// Inject your library's stream and your upload call. NativeFlow
/// contributes the `location` requirement, which makes the single Android
/// foreground service run with type `location` (declare it in your manifest)
/// and lets iOS report whether a continuous location background mode exists.
class LocationAdapter extends RuntimeAdapter {
  LocationAdapter({
    required this.positions,
    required this.upload,
    super.id = 'location',
  }) : super(
         requirements: const RuntimeRequirements(
           capabilities: {
             RuntimeCapability.location,
             RuntimeCapability.persistentRuntime,
             RuntimeCapability.network,
           },
         ),
       );

  final Stream<Fix> Function() positions;
  final Future<void> Function(Fix fix) upload;
  StreamSubscription<Fix>? _subscription;
  final _buffer = <Fix>[];

  @override
  Future<void> start(AdapterContext context) async {
    _subscription = positions().listen((fix) async {
      _buffer.add(fix);
      if (!context.network.connected) return; // keep buffering offline
      final batch = List.of(_buffer);
      _buffer.clear();
      for (final f in batch) {
        await upload(f);
      }
    }, onError: context.reportFailure);
  }

  @override
  Future<void> stop(AdapterContext context) async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

/// Stand-in for a real location stream in the demo.
Stream<Fix> simulatedPositions() => Stream.periodic(
  const Duration(seconds: 5),
  (i) => (lat: 12.97 + i * 1e-4, lng: 77.59 + i * 1e-4, at: DateTime.now()),
);
