import 'package:nativeflow/nativeflow.dart';

/// A worker with controllable failures, to watch NativeFlow's recovery
/// (backoff, network wait, `failed` after max attempts) without a server.
class DemoAdapter extends RuntimeAdapter {
  DemoAdapter({super.id = 'demo'})
    : super(
        requirements: const RuntimeRequirements(
          capabilities: {RuntimeCapability.backgroundExecution},
        ),
        recoveryPolicy: const RecoveryPolicy(
          maxAttempts: 5,
          initialDelay: Duration(seconds: 1),
          maxDelay: Duration(seconds: 8),
        ),
      );

  /// How many upcoming start/recover calls should throw.
  int failNext = 0;
  AdapterContext? _context;

  @override
  Future<void> start(AdapterContext context) async {
    _context = context;
    if (failNext > 0) {
      failNext--;
      throw StateError('simulated start failure');
    }
    context.logger.info('demo adapter running', {
      'reason': context.recoveryReason?.name,
      'attempt': context.attempt,
    });
  }

  /// Simulates the connection breaking while running.
  void breakConnection() =>
      _context?.reportFailure(StateError('simulated disconnect'));
}
