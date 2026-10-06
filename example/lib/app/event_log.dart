import 'package:flutter/foundation.dart';
import 'package:nativeflow/nativeflow.dart';

/// Every runtime event and NativeFlow log line, newest first.
class EventLog extends ChangeNotifier {
  EventLog._() {
    NativeFlow.events.stream.listen(
      (e) => add(
        '${e.id ?? '·'}  ${e.name}${e.adapterId == null ? '' : ' [${e.adapterId}]'}  ${e.payload}',
      ),
    );
    final previous = NativeFlow.logger.sink;
    NativeFlow.logger.sink = (level, message, {fields, error}) {
      previous(level, message, fields: fields, error: error);
      add('log.${level.name}  $message ${fields ?? ''}');
    };
  }

  static EventLog? _instance;

  /// Must be created after `NativeFlow.initialize` registers the event bus.
  static EventLog get instance => _instance ??= EventLog._();

  final entries = <String>[];

  void add(String line) {
    entries.insert(
      0,
      '${DateTime.now().toIso8601String().substring(11, 19)}  $line',
    );
    if (entries.length > 300) entries.removeLast();
    notifyListeners();
  }
}
