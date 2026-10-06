import 'package:flutter/material.dart';
import 'package:nativeflow/nativeflow.dart';

import '../adapters/mqtt_adapter.dart';
import '../adapters/websocket_adapter.dart';
import '../app/adapter_catalog.dart';
import '../app/ui.dart';

/// `NativeFlow.start / stop / attach / detach / sessions / state / network`.
class RuntimeScreen extends StatefulWidget {
  /// Creates the screen.
  const RuntimeScreen({super.key});

  @override
  State<RuntimeScreen> createState() => _RuntimeScreenState();
}

class _RuntimeScreenState extends State<RuntimeScreen> {
  final _title = TextEditingController(text: 'You are online');
  final _body = TextEditingController(text: 'Receiving ride requests');
  bool _persistent = true;
  bool _restoreOnBoot = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _start() => run(context, 'start', () async {
    // Only asks for what attached adapters need, and only if missing.
    await NativeFlow.permissions.requestRequired();
    await NativeFlow.start(
      RuntimeOptions(
        notification: ForegroundNotification(
          title: _title.text,
          body: _body.text,
          actions: const [
            NotificationAction(id: 'go_offline', label: 'Go offline'),
          ],
        ),
        persistent: _persistent,
        restoreOnBoot: _restoreOnBoot,
      ),
    );
  });

  bool _attached(RuntimeAdapter a) =>
      NativeFlow.sessions.any((s) => s.id == a.id);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Runtime & adapters')),
      body: StreamBuilder<Object?>(
        // Rebuild on any runtime state or network change.
        stream: NativeFlow.events.stream,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Section(
              title: 'State',
              children: [
                Chip(label: Text('runtime: ${NativeFlow.state.name}')),
                Chip(label: Text('network: ${NativeFlow.network}')),
                Chip(
                  label: Text(
                    'background engine: ${NativeFlow.isBackgroundEngine}',
                  ),
                ),
              ],
            ),
            Section(
              title: 'Start / stop',
              subtitle:
                  'Android: one foreground service for all adapters. '
                  'iOS: records intent; adapters pause before suspension.',
              children: [
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: 'Notification title',
                  ),
                ),
                TextField(
                  controller: _body,
                  decoration: const InputDecoration(
                    labelText: 'Notification body',
                  ),
                ),
                SwitchListTile(
                  title: const Text('persistent (sticky restart)'),
                  value: _persistent,
                  onChanged: (v) => setState(() => _persistent = v),
                ),
                SwitchListTile(
                  title: const Text('restoreOnBoot'),
                  value: _restoreOnBoot,
                  onChanged: (v) => setState(() => _restoreOnBoot = v),
                ),
                FilledButton(
                  onPressed: _start,
                  child: const Text('NativeFlow.start()'),
                ),
                FilledButton.tonal(
                  onPressed: () => run(context, 'stop', NativeFlow.stop),
                  child: const Text('NativeFlow.stop()'),
                ),
              ],
            ),
            Section(
              title: 'Adapters',
              subtitle:
                  'Each wraps the app\'s own library. Attaching while running '
                  'updates the single service\'s requirements.',
              children: [
                for (final a in AdapterCatalog.all)
                  FilterChip(
                    label: Text(a.id),
                    selected: _attached(a),
                    onSelected: (on) async {
                      await run(
                        context,
                        on ? 'attach ${a.id}' : 'detach ${a.id}',
                        () async {
                          on
                              ? await NativeFlow.attach(a)
                              : await NativeFlow.detach(a.id);
                        },
                      );
                      if (mounted) setState(() {});
                    },
                  ),
              ],
            ),
            Section(
              title: 'Sessions',
              subtitle:
                  'Live state per adapter. Simulate failures to watch backoff, '
                  'network-aware retries and the failed state.',
              children: [for (final s in NativeFlow.sessions) _SessionTile(s)],
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile(this.session);

  final RuntimeSession session;

  @override
  Widget build(BuildContext context) => StreamBuilder<SessionState>(
    stream: session.states,
    builder: (context, _) {
      final demo = AdapterCatalog.demo;
      return Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${session.id}: ${session.state.name}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'attempts ${session.attempts}'
                '${session.lastError == null ? '' : ' · ${session.lastError}'}',
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (session.adapter == demo) ...[
                    CallButton('fail next start ×2', () => demo.failNext = 2),
                    CallButton('break connection', demo.breakConnection),
                  ],
                  if (session.adapter is WebSocketAdapter)
                    CallButton(
                      'send echo',
                      () => (session.adapter as WebSocketAdapter).send(
                        'ping ${DateTime.now()}',
                      ),
                    ),
                  if (session.adapter is MqttAdapter)
                    CallButton(
                      'publish',
                      () => (session.adapter as MqttAdapter).publish(
                        'hello ${DateTime.now()}',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
