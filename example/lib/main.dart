import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nativeflow/nativeflow.dart';

import 'app/adapter_catalog.dart';
import 'app/event_log.dart';
import 'screens/background_screen.dart';
import 'screens/capabilities_screen.dart';
import 'screens/events_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/overlay_screen.dart';
import 'screens/presentation_screen.dart';
import 'screens/runtime_screen.dart';

/// NativeFlow example: a driver app that exercises every public API.
///
/// Every screen calls the real plugin; results (including honest platform
/// refusals such as `unavailable`) are shown in a snackbar and the log.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrap();
  runApp(const ExampleApp());
}

/// Android: started by NativeFlow in a background Flutter engine when the
/// runtime is active but no UI exists (app swiped away, process restarted
/// by the OS, reboot restore, or a JobScheduler task). It re-attaches the
/// same adapters, which then receive `recover(runtimeRestored)`.
@pragma('vm:entry-point')
void nativeFlowBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await bootstrap();
  // No UI here: finish OS background tasks ourselves.
  NativeFlow.events.on(RuntimeEventType.backgroundTask).listen((e) {
    final id = e.payload['taskId'];
    if (id is String && e.payload['expired'] != true) {
      NativeFlow.completeBackgroundTask(id);
    }
  });
}

/// Shared by the UI and the background engine.
Future<void> bootstrap() async {
  await NativeFlow.initialize(
    config: const NativeFlowConfig(logVerbosity: LogVerbosity.verbose),
    backgroundEntrypoint: nativeFlowBackground,
  );
  EventLog.instance; // start capturing events and logs
  for (final adapter in AdapterCatalog.defaults) {
    await NativeFlow.attach(adapter);
  }
}

/// The example's root widget.
class ExampleApp extends StatelessWidget {
  /// Creates the app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NativeFlow',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.teal,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: const HomeScreen(),
  );
}

/// One entry per API area.
class HomeScreen extends StatelessWidget {
  /// Creates the home screen.
  const HomeScreen({super.key});

  static final _screens = <(IconData, String, String, Widget Function())>[
    (
      Icons.play_circle,
      'Runtime & adapters',
      'start/stop, attach/detach, sessions, recovery',
      RuntimeScreen.new,
    ),
    (
      Icons.verified_user,
      'Capabilities & permissions',
      'capabilities(), status, request, requestRequired',
      CapabilitiesScreen.new,
    ),
    (
      Icons.bolt,
      'Events',
      'event bus, emit (transient / persisted), log',
      EventsScreen.new,
    ),
    (
      Icons.notifications,
      'Notifications',
      'channels, actions, deep links, groups, full-screen',
      NotificationsScreen.new,
    ),
    (
      Icons.picture_in_picture,
      'Overlay (Android)',
      'show, update, move, resize, hide, state',
      OverlayScreen.new,
    ),
    (
      Icons.dynamic_feed,
      'Presentation & Live Activities',
      'present, activities, widgets',
      PresentationScreen.new,
    ),
    (
      Icons.schedule,
      'Background tasks & logging',
      'schedule/complete tasks, log verbosity',
      BackgroundScreen.new,
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: StreamBuilder<RuntimeState>(
        stream: NativeFlow.states,
        builder: (_, _) => Text('NativeFlow · ${NativeFlow.state.name}'),
      ),
    ),
    body: ListView(
      children: [
        for (final (icon, title, subtitle, builder) in _screens)
          ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => builder())),
          ),
      ],
    ),
  );
}
