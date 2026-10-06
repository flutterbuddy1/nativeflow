import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nativeflow/nativeflow.dart';

import '../app/ui.dart';

/// `NativeFlow.overlay.*` (Android). On iOS every call reports
/// `unavailable` — shown as-is.
class OverlayScreen extends StatefulWidget {
  /// Creates the screen.
  const OverlayScreen({super.key});

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> {
  int _requests = 2;
  double _progress = .2;
  final _received = <String>[];
  late final List<StreamSubscription<RuntimeEvent>> _subs;

  @override
  void initState() {
    super.initState();
    _subs = [
      NativeFlow.overlay.actions.listen(
        (e) => setState(
          () => _received.insert(0, 'action ${e.payload['actionId']}'),
        ),
      ),
      NativeFlow.overlay.closed.listen(
        (_) => setState(() => _received.insert(0, 'closed by user')),
      ),
    ];
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  OverlayNode _content() => OverlayCard(
    actionId: 'open_app',
    children: [
      OverlayText('Online · $_requests requests', bold: true),
      const OverlayText('Drag me anywhere', size: 12),
      OverlayProgress(value: _progress),
      const OverlayCard(
        axis: OverlayAxis.horizontal,
        padding: 0,
        background: Color(0x00000000),
        children: [
          OverlayButton(actionId: 'go_offline', label: 'Go offline'),
          OverlayButton.close(),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Overlay')),
    body: ListView(
      children: [
        Section(
          title: 'Permission',
          subtitle: 'Needs SYSTEM_ALERT_WINDOW in the manifest and the user\'s grant.',
          children: [
            CallButton(
              'status()',
              () => run(context, 'overlay.status', NativeFlow.overlay.status),
            ),
            CallButton(
              'requestPermission()',
              () => run(
                context,
                'overlay.requestPermission',
                NativeFlow.overlay.requestPermission,
              ),
            ),
          ],
        ),
        Section(
          title: 'Window',
          subtitle: 'Native views: keeps working with the app closed; restored with the runtime.',
          children: [
            FilledButton(
              onPressed: () => run(
                context,
                'overlay.show',
                () => NativeFlow.overlay.show(
                  OverlayWindow(x: 16, y: 180, content: _content()),
                ),
              ),
              child: const Text('show()'),
            ),
            CallButton('update()', () {
              _requests++;
              _progress = (_progress + .2) % 1;
              run(
                context,
                'overlay.update',
                () => NativeFlow.overlay.update(_content()),
              );
            }),
            CallButton(
              'move(200, 400)',
              () => run(
                context,
                'overlay.move',
                () => NativeFlow.overlay.move(200, 400),
              ),
            ),
            CallButton(
              'resize(260, null)',
              () => run(
                context,
                'overlay.resize',
                () => NativeFlow.overlay.resize(260, null),
              ),
            ),
            CallButton(
              'resize(wrap)',
              () => run(
                context,
                'overlay.resize',
                () => NativeFlow.overlay.resize(null, null),
              ),
            ),
            CallButton(
              'state()',
              () => run(context, 'overlay.state', () async {
                final s = await NativeFlow.overlay.state();
                return 'visible=${s.visible} x=${s.x.round()} y=${s.y.round()} '
                    '${s.width.round()}×${s.height.round()}';
              }),
            ),
            CallButton(
              'hide()',
              () => run(context, 'overlay.hide', NativeFlow.overlay.hide),
            ),
          ],
        ),
        Section(
          title: 'actions / closed streams',
          children: [for (final r in _received) Text(r)],
        ),
      ],
    ),
  );
}
