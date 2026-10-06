/// Something an application may need from the OS to do its work.
///
/// Capabilities describe *what* is needed; each platform decides *how*
/// (foreground service type, background mode, etc.) and reports honestly
/// via [CapabilityStatus] whether it can deliver it.
enum RuntimeCapability {
  /// Keep doing work while the app UI is not visible.
  backgroundExecution,

  /// Long-lived, best-effort execution across UI destruction and process
  /// recreation (Android foreground service; iOS only with a legitimate
  /// continuous background mode such as location or audio).
  persistentRuntime,

  /// Network connectivity awareness.
  network,
  location,
  microphone,

  /// Audio playback while backgrounded.
  audio,
  notifications,

  /// Floating windows over other apps (Android only).
  overlay,

  /// Full-screen interruptions such as incoming calls and alarms.
  fullscreen,

  /// Restoring a runtime the user left running after a device reboot.
  bootRecovery,

  /// iOS Live Activities / Dynamic Island.
  liveActivity,

  /// Home-screen widget refresh.
  widget,

  /// OS-scheduled deferred work (iOS BGTaskScheduler).
  backgroundProcessing,
}

/// What a platform can actually deliver for a [RuntimeCapability].
enum CapabilityStatus {
  /// Available now.
  supported,

  /// Available with platform-imposed limits (time limits, system
  /// scheduling, OEM policies). See docs/PLATFORM_CAPABILITIES.md.
  partiallySupported,

  /// Available after the user grants a permission. Request it with
  /// `NativeFlow.permissions.request`.
  permissionRequired,

  /// Exists on this platform but is disabled by the user, device policy,
  /// or OS settings; the app cannot request it programmatically.
  restricted,

  /// Not offered on this platform, OS version, or app configuration
  /// (e.g. missing manifest/Info.plist declarations).
  unavailable;

  /// Whether the capability can be used right now (possibly with limits).
  bool get isUsable =>
      this == CapabilityStatus.supported ||
      this == CapabilityStatus.partiallySupported;

  static CapabilityStatus parse(Object? wire) => CapabilityStatus.values
      .firstWhere((s) => s.name == wire, orElse: () => unavailable);
}

/// Snapshot of every capability's status on the current device.
typedef CapabilityReport = Map<RuntimeCapability, CapabilityStatus>;
