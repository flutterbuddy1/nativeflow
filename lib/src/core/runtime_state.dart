/// State of the single native runtime (Android foreground service / iOS
/// background configuration). Owned by the native layer; Dart mirrors it.
enum RuntimeState {
  stopped,
  starting,
  running,
  stopping,

  /// The OS stopped the runtime without the app asking (service time limit,
  /// failed restart, boot restore not permitted). Call `NativeFlow.start()`
  /// again from the foreground to resume.
  interrupted,

  /// The runtime is being restored after process recreation or reboot.
  recovering;

  bool get isActive =>
      this == RuntimeState.running || this == RuntimeState.recovering;

  static RuntimeState parse(Object? wire) => RuntimeState.values.firstWhere(
    (s) => s.name == wire,
    orElse: () => RuntimeState.stopped,
  );
}

/// Lifecycle state of one attached adapter.
enum SessionState {
  /// Attached but the runtime is not running.
  idle,
  starting,
  running,

  /// Paused by the runtime (iOS background suspension, Android service
  /// interruption). Resumes automatically.
  paused,

  /// A start or recovery attempt failed; waiting for the backoff delay.
  recovering,

  /// Recovery is waiting for connectivity (policy `waitForNetwork`).
  waitingForNetwork,
  stopping,
  stopped,

  /// Recovery gave up after the policy's maximum attempts.
  failed;

  static const _allowed = <SessionState, Set<SessionState>>{
    idle: {starting, recovering, stopped},
    starting: {running, recovering, failed, stopping},
    running: {paused, recovering, stopping},
    paused: {running, recovering, stopping},
    recovering: {running, recovering, waitingForNetwork, failed, stopping},
    waitingForNetwork: {recovering, stopping},
    stopping: {stopped, idle},
    stopped: {starting, idle},
    failed: {starting, recovering, stopping, idle},
  };

  /// Whether a transition from this state to [next] is legal. Illegal
  /// transitions indicate a runtime bug and throw.
  bool canTransitionTo(SessionState next) => _allowed[this]!.contains(next);
}
