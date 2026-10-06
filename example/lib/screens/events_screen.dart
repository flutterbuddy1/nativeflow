import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nativeflow/nativeflow.dart';

import '../app/event_log.dart';
import '../app/ui.dart';

/// `NativeFlow.events` (stream / on / named) and `NativeFlow.emit`.
class EventsScreen extends StatefulWidget {
  /// Creates the screen.
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  int _named = 0;
  int _networkEvents = 0;
  late final List<StreamSubscription<RuntimeEvent>> _subs;

  @override
  void initState() {
    super.initState();
    // Typed and named subscriptions next to the global log.
    _subs = [
      NativeFlow.events
          .named('demo.persisted')
          .listen((_) => setState(() => _named++)),
      NativeFlow.events
          .on(RuntimeEventType.networkChanged)
          .listen((_) => setState(() => _networkEvents++)),
    ];
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Events')),
    body: Column(
      children: [
        Section(
          title: 'NativeFlow.emit',
          subtitle:
              'Persisted events go through the native store: they survive '
              'process death and are redelivered until acknowledged (ids shown in the log).',
          children: [
            CallButton(
              'emit transient',
              () => run(
                context,
                'emit demo.transient',
                () => NativeFlow.emit(
                  'demo.transient',
                  payload: {'at': DateTime.now().toIso8601String()},
                ),
              ),
            ),
            CallButton(
              'emit persisted',
              () => run(
                context,
                'emit demo.persisted',
                () => NativeFlow.emit(
                  'demo.persisted',
                  payload: {'fare': 182},
                  persist: true,
                ),
              ),
            ),
            CallButton(
              'invalid name (rejected)',
              () => run(
                context,
                'emit nativeflow.reserved',
                () => NativeFlow.emit('nativeflow.reserved'),
              ),
            ),
            Chip(label: Text('named(demo.persisted): $_named')),
            Chip(label: Text('on(networkChanged): $_networkEvents')),
          ],
        ),
        const Divider(),
        Expanded(
          child: ListenableBuilder(
            listenable: EventLog.instance,
            builder: (context, _) => ListView.builder(
              itemCount: EventLog.instance.entries.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: Text(
                  EventLog.instance.entries[i],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
