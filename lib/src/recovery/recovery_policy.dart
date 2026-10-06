import 'dart:math';

import 'package:flutter/foundation.dart';

/// How NativeFlow retries an adapter whose start/recover failed or that
/// reported a failure via `AdapterContext.reportFailure`.
///
/// Delay for attempt `n` (1-based) is
/// `min(maxDelay, initialDelay * multiplier^(n-1))` with ±[jitter] spread,
/// so a fleet of devices does not reconnect in lockstep.
@immutable
class RecoveryPolicy {
  const RecoveryPolicy({
    this.maxAttempts = 10,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(minutes: 5),
    this.multiplier = 2.0,
    this.jitter = 0.2,
    this.waitForNetwork = true,
  }) : assert(maxAttempts == null || maxAttempts >= 0),
       assert(multiplier >= 1),
       assert(jitter >= 0 && jitter < 1);

  /// `null` retries forever (still with backoff).
  final int? maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final double multiplier;
  final double jitter;

  /// Hold retries while the device is offline and retry immediately when
  /// connectivity returns.
  final bool waitForNetwork;

  /// Never retry.
  static const none = RecoveryPolicy(maxAttempts: 0);

  bool allowsAttempt(int attempt) =>
      maxAttempts == null || attempt <= maxAttempts!;

  Duration delayFor(int attempt, [Random? random]) {
    assert(attempt >= 1);
    final base = initialDelay.inMicroseconds * pow(multiplier, attempt - 1);
    final capped = min(base.toDouble(), maxDelay.inMicroseconds.toDouble());
    final spread = jitter == 0
        ? 1.0
        : 1 + ((random ?? _random).nextDouble() * 2 - 1) * jitter;
    return Duration(microseconds: (capped * spread).round());
  }

  static final _random = Random();
}
