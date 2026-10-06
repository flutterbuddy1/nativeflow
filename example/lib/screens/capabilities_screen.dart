import 'package:flutter/material.dart';
import 'package:nativeflow/nativeflow.dart';

import '../app/ui.dart';

/// `NativeFlow.capabilities()` and `NativeFlow.permissions.*`.
class CapabilitiesScreen extends StatefulWidget {
  /// Creates the screen.
  const CapabilitiesScreen({super.key});

  @override
  State<CapabilitiesScreen> createState() => _CapabilitiesScreenState();
}

class _CapabilitiesScreenState extends State<CapabilitiesScreen> {
  CapabilityReport _report = const {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final report = await NativeFlow.capabilities();
    if (mounted) setState(() => _report = report);
  }

  Future<void> _request(RuntimeCapability c) async {
    await run(
      context,
      'permissions.request(${c.name})',
      () => NativeFlow.permissions.request(c),
    );
    await _refresh();
  }

  Future<void> _status(RuntimeCapability c) => run(
    context,
    'permissions.status(${c.name})',
    () => NativeFlow.permissions.status(c),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Capabilities'),
      actions: [
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: ListView(
      children: [
        Section(
          title: 'permissions.requestRequired()',
          subtitle:
              'Requests, one by one, only what attached adapters need and '
              'is currently permissionRequired. Nothing is ever requested automatically.',
          children: [
            FilledButton(
              onPressed: () async {
                await run(context, 'requestRequired', () async {
                  final r = await NativeFlow.permissions.requestRequired();
                  return r.map((k, v) => MapEntry(k.name, v.name));
                });
                await _refresh();
              },
              child: const Text('Request what adapters need'),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Tap a row to request; long-press to re-read its status.',
          ),
        ),
        for (final entry in _report.entries)
          ListTile(
            title: Text(entry.key.name),
            trailing: StatusChip(entry.value),
            onTap: entry.value == CapabilityStatus.permissionRequired
                ? () => _request(entry.key)
                : null,
            onLongPress: () => _status(entry.key),
          ),
      ],
    ),
  );
}
