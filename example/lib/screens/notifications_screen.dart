import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nativeflow/nativeflow.dart';

import '../app/ui.dart';

/// `NativeFlow.notifications.*` — rendered natively, so taps and actions
/// work (and are persisted) even when Flutter is not running.
class NotificationsScreen extends StatefulWidget {
  /// Creates the screen.
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _received = <String>[];
  late final List<StreamSubscription<RuntimeEvent>> _subs;

  @override
  void initState() {
    super.initState();
    _subs = [
      NativeFlow.notifications.taps.listen((e) => _add('tap ${e.payload}')),
      NativeFlow.notifications.actions.listen(
        (e) => _add('action ${e.payload}'),
      ),
    ];
  }

  void _add(String s) => setState(() => _received.insert(0, s));

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _show(String label, RuntimeNotification n) =>
      run(context, 'show $label', () => NativeFlow.notifications.show(n));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: ListView(
      children: [
        Section(
          title: 'Channels (Android 8+; no-op on iOS)',
          children: [
            CallButton(
              'createChannel rides (high = heads-up)',
              () => run(
                context,
                'createChannel',
                () => NativeFlow.notifications.createChannel(
                  const NotificationChannel(
                    id: 'rides',
                    name: 'Ride requests',
                    description: 'New ride offers',
                    importance: NotificationImportance.high,
                  ),
                ),
              ),
            ),
          ],
        ),
        Section(
          title: 'show()',
          children: [
            CallButton(
              'simple',
              () => _show(
                'simple',
                const RuntimeNotification(
                  id: 10,
                  title: 'Hello',
                  body: 'From NativeFlow',
                ),
              ),
            ),
            CallButton(
              'actions + payload',
              () => _show(
                'actions',
                const RuntimeNotification(
                  id: 11,
                  title: 'New ride request',
                  body: '2.4 km · ₹182',
                  channelId: 'rides',
                  actions: [
                    NotificationAction(
                      id: 'accept',
                      label: 'Accept',
                      opensApp: true,
                    ),
                    NotificationAction(id: 'decline', label: 'Decline'),
                  ],
                  payload: {'ride': 42},
                ),
              ),
            ),
            CallButton(
              'deep link',
              () => _show(
                'deep link',
                RuntimeNotification(
                  id: 12,
                  title: 'Trip receipt',
                  body: 'Tap to open ride 42',
                  deepLink: Uri.parse('nativeflow-example://ride/42'),
                ),
              ),
            ),
            CallButton('group ×2', () async {
              for (final i in [13, 14]) {
                await _show(
                  'group $i',
                  RuntimeNotification(
                    id: i,
                    title: 'Message $i',
                    group: 'chat',
                  ),
                );
              }
            }),
            CallButton(
              'ongoing',
              () => _show(
                'ongoing',
                const RuntimeNotification(
                  id: 15,
                  title: 'Uploading logs',
                  ongoing: true,
                ),
              ),
            ),
            CallButton(
              'full-screen call',
              () => _show(
                'incoming call',
                const RuntimeNotification(
                  id: 16,
                  title: 'Rider calling',
                  body: 'Asha',
                  fullScreen: FullScreenReason.incomingCall,
                  actions: [
                    NotificationAction(
                      id: 'answer',
                      label: 'Answer',
                      opensApp: true,
                    ),
                  ],
                ),
              ),
            ),
            CallButton(
              'full-screen alarm',
              () => _show(
                'alarm',
                const RuntimeNotification(
                  id: 17,
                  title: 'Shift starts',
                  fullScreen: FullScreenReason.alarm,
                ),
              ),
            ),
          ],
        ),
        Section(
          title: 'cancel()',
          children: [
            for (final id in [10, 11, 12, 13, 14, 15, 16, 17])
              CallButton(
                'cancel $id',
                () => run(
                  context,
                  'cancel $id',
                  () => NativeFlow.notifications.cancel(id),
                ),
              ),
          ],
        ),
        Section(
          title: 'taps / actions streams',
          subtitle: 'Also delivered after the app was killed — check the Events log after relaunch.',
          children: [for (final r in _received) Text(r)],
        ),
      ],
    ),
  );
}
