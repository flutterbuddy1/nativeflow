import 'package:flutter/material.dart';
import 'package:nativeflow/nativeflow.dart';

import 'event_log.dart';

/// Runs a NativeFlow call, logs it and shows the outcome. Platform
/// refusals (e.g. `unavailable` on iOS for overlays) are shown, not hidden.
Future<T?> run<T>(
  BuildContext context,
  String label,
  Future<T> Function() call,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await call();
    final text = result == null ? '$label ✓' : '$label → $result';
    EventLog.instance.add('call  $text');
    messenger.showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
    return result;
  } on NativeFlowException catch (e) {
    final text = '$label ✗ ${e.code.name}: ${e.message}';
    EventLog.instance.add('call  $text');
    messenger.showSnackBar(SnackBar(content: Text(text)));
    return null;
  }
}

/// A titled card grouping related actions.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    ),
  );
}

/// Compact button for an API call.
class CallButton extends StatelessWidget {
  const CallButton(this.label, this.onPressed, {super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) =>
      OutlinedButton(onPressed: onPressed, child: Text(label));
}

/// Colour-coded capability status chip.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final CapabilityStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      CapabilityStatus.supported => Colors.green,
      CapabilityStatus.partiallySupported => Colors.teal,
      CapabilityStatus.permissionRequired => Colors.orange,
      CapabilityStatus.restricted => scheme.error,
      CapabilityStatus.unavailable => scheme.outline,
    };
    return Chip(
      label: Text(status.name, style: TextStyle(color: color, fontSize: 12)),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}
