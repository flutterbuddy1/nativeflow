/// State of the single native runtime (Android foreground service / iOS
/// background configuration). Owned by the native layer; Dart mirrors it.
enum RuntimeState {
  /// Not running; nothing will be restored.
  stopped,

  /// Start requested; the native runtime is coming up.
  starting,

  /// Running (on Android, the foreground service is active).
  running,

  /// Stop requested; the native runtime is shutting down.
  stopping,

  /// The OS stopped the runtime without the app asking (service time limit,
  /// failed restart, boot restore not permitted). Call `NativeFlow.start()`
  /// again from the foreground to resume.
  interrupted,

  /// The runtime is being restored after process recreation or reboot.
  recovering;

  /// Whether the runtime is running or being restored.
  bool get isActive =>
      this == RuntimeState.running || this == RuntimeState.recovering;

  /// Parses a wire name; unknown values map to [stopped].
  static RuntimeState parse(Object? wire) => RuntimeState.values.firstWhere(
    (s) => s.name == wire,
    orElse: () => RuntimeState.stopped,
  );
}

/// Lifecycle state of one attached adapter.
enum SessionState {
  /// Attached but the runtime is not running.
  idle,

  /// [RuntimeAdapter.start] is running.
  starting,

  /// The adapter started or recovered successfully.
  running,

  /// Paused by the runtime (iOS background suspension, Android service
  /// interruption). Resumes automatically.
  paused,

  /// A start or recovery attempt failed; waiting for the backoff delay.
  recovering,

  /// Recovery is waiting for connectivity (policy `waitForNetwork`).
  waitingForNetwork,

  /// [RuntimeAdapter.stop] is running.
  stopping,

  /// Stopped by the runtime or by detach.
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
