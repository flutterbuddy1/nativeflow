import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nativeflow/nativeflow.dart';

import '../app/ui.dart';

/// `scheduleBackgroundTask / completeBackgroundTask` and logger verbosity.
class BackgroundScreen extends StatefulWidget {
  /// Creates the screen.
  const BackgroundScreen({super.key});

  @override
  State<BackgroundScreen> createState() => _BackgroundScreenState();
}

class _BackgroundScreenState extends State<BackgroundScreen> {
  final _tasks = <String, String>{}; // taskId -> kind
  late final StreamSubscription<RuntimeEvent> _sub;

  @override
  void initState() {
    super.initState();
    _sub = NativeFlow.events.on(RuntimeEventType.backgroundTask).listen((e) {
      final id = e.payload['taskId'] as String?;
      if (id == null) return;
      setState(
        () => e.payload['expired'] == true
            ? _tasks.remove(id)
            : _tasks[id] = '${e.payload['kind']}',
      );
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Background & logging')),
    body: ListView(
      children: [
        Section(
          title: 'scheduleBackgroundTask()',
          subtitle:
              'Android: JobScheduler. iOS: BGTaskScheduler (unavailable on the '
              'simulator). The OS decides when it runs; it arrives as a backgroundTask event.\n'
              'Android, run now: adb shell cmd jobscheduler run -f com.example.nativeflow_example 20038',
          children: [
            for (final kind in BackgroundTaskKind.values)
              CallButton(
                'schedule ${kind.name}',
                () => run(
                  context,
                  'schedule ${kind.name}',
                  () => NativeFlow.scheduleBackgroundTask(
                    kind: kind,
                    earliestIn: Duration.zero,
                  ),
                ),
              ),
          ],
        ),
        Section(
          title: 'Granted tasks → completeBackgroundTask()',
          subtitle: 'Must be completed before the OS deadline.',
          children: [
            if (_tasks.isEmpty) const Text('none yet'),
            for (final MapEntry(key: id, value: kind) in _tasks.entries)
              CallButton('complete $kind ${id.substring(0, 8)}', () async {
                await run(
                  context,
                  'completeBackgroundTask',
                  () => NativeFlow.completeBackgroundTask(id),
                );
                setState(() => _tasks.remove(id));
              }),
          ],
        ),
        Section(
          title: 'NativeFlow.logger.verbosity',
          subtitle:
              'Applies to Dart now and to native logs on the next initialize.',
          children: [
            SegmentedButton<LogVerbosity>(
              segments: [
                for (final v in LogVerbosity.values)
                  ButtonSegment(value: v, label: Text(v.name)),
              ],
              selected: {NativeFlow.logger.verbosity},
              onSelectionChanged: (v) =>
                  setState(() => NativeFlow.logger.verbosity = v.single),
            ),
          ],
        ),
      ],
    ),
  );
}
