import 'package:flutter/material.dart';
import 'package:nativeflow/nativeflow.dart';

import '../app/ui.dart';

/// `NativeFlow.present` and `NativeFlow.activities.*`.
class PresentationScreen extends StatefulWidget {
  /// Creates the screen.
  const PresentationScreen({super.key});

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  String? _activityId;
  int _eta = 8;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Presentation')),
    body: ListView(
      children: [
        Section(
          title: 'NativeFlow.present(RuntimePresentation)',
          subtitle:
              'State intent once. Android updates the foreground notification '
              '(or posts one); iOS updates the running Live Activity (or posts a notification).',
          children: [
            FilledButton(
              onPressed: () {
                _eta = _eta > 1 ? _eta - 1 : 8;
                run(
                  context,
                  'present',
                  () => NativeFlow.present(
                    RuntimePresentation(
                      title: 'Trip in progress',
                      body: '${(_eta * .4).toStringAsFixed(1)} km to drop-off',
                      progress: 1 - _eta / 9,
                      values: {'eta': '$_eta min', 'status': 'On trip'},
                      actions: const [
                        NotificationAction(
                          id: 'sos',
                          label: 'SOS',
                          opensApp: true,
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: const Text('present()'),
            ),
          ],
        ),
        Section(
          title: 'Live Activity (iOS 16.1+)',
          subtitle:
              'Rendered by the example\'s NativeFlowWidgets extension. '
              'Android reports unavailable.',
          children: [
            CallButton(
              'activities.status()',
              () => run(
                context,
                'activities.status',
                NativeFlow.activities.status,
              ),
            ),
            CallButton('start()', () async {
              final id = await run(
                context,
                'activities.start',
                () => NativeFlow.activities.start(
                  attributes: {'rider': 'Asha'},
                  state: {'status': 'Arriving', 'eta': '4 min'},
                ),
              );
              if (id != null) setState(() => _activityId = id);
            }),
            CallButton(
              'update()',
              _activityId == null
                  ? null
                  : () => run(
                      context,
                      'activities.update',
                      () => NativeFlow.activities.update(_activityId!, {
                        'status': 'Picked up',
                        'eta': '12 min',
                      }),
                    ),
            ),
            CallButton(
              'end()',
              _activityId == null
                  ? null
                  : () async {
                      await run(
                        context,
                        'activities.end',
                        () => NativeFlow.activities.end(
                          _activityId!,
                          finalState: {'status': 'Completed', 'eta': '0 min'},
                        ),
                      );
                      setState(() => _activityId = null);
                    },
            ),
          ],
        ),
        Section(
          title: 'Home-screen widget (iOS)',
          subtitle:
              'Writes to the App Group and reloads the DriverStatus widget.',
          children: [
            CallButton(
              'activities.updateWidget()',
              () => run(
                context,
                'updateWidget',
                () => NativeFlow.activities.updateWidget(
                  appGroup: 'group.com.example.nativeflowExample',
                  key: 'driver',
                  kind: 'DriverStatus',
                  data: {
                    'status': NativeFlow.state.isActive ? 'Online' : 'Offline',
                    'detail': 'Updated ${TimeOfDay.now().format(context)}',
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
