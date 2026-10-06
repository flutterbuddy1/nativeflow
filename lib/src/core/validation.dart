import 'dart:convert';

import 'errors.dart';

final _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$');

/// Upper bound for a serialized event payload. Events are runtime signals,
/// not a data store; large blobs belong in the app's own storage.
const maxPayloadBytes = 32 * 1024;

/// Validates adapter ids, event types, action ids and channel ids.
String validateId(String value, String what) {
  if (!_idPattern.hasMatch(value)) {
    throw NativeFlowException(
      NativeFlowErrorCode.invalidArgument,
      'Invalid $what "$value": use 1-64 chars of [A-Za-z0-9_.:-], '
      'starting with a letter or digit.',
    );
  }
  return value;
}

/// Ensures [payload] contains only JSON values (null, bool, num, String,
/// List, Map with String keys) and is at most [maxPayloadBytes] encoded.
Map<String, Object?> validatePayload(Map<String, Object?> payload) {
  _checkJson(payload, 0);
  final size = utf8.encode(jsonEncode(payload)).length;
  if (size > maxPayloadBytes) {
    throw NativeFlowException(
      NativeFlowErrorCode.invalidArgument,
      'Event payload is $size bytes; the limit is $maxPayloadBytes.',
    );
  }
  return payload;
}

void _checkJson(Object? value, int depth) {
  if (depth > 16) {
    throw const NativeFlowException(
      NativeFlowErrorCode.invalidArgument,
      'Event payload is nested deeper than 16 levels.',
    );
  }
  switch (value) {
    case null || bool() || String():
      return;
    case final num n:
      if (n is double && !n.isFinite) {
        throw const NativeFlowException(
          NativeFlowErrorCode.invalidArgument,
          'Event payload contains NaN or Infinity.',
        );
      }
    case final List<Object?> l:
      for (final v in l) {
        _checkJson(v, depth + 1);
      }
    case final Map<Object?, Object?> m:
      for (final e in m.entries) {
        if (e.key is! String) {
          throw const NativeFlowException(
            NativeFlowErrorCode.invalidArgument,
            'Event payload map keys must be strings.',
          );
        }
        _checkJson(e.value, depth + 1);
      }
    default:
      throw NativeFlowException(
        NativeFlowErrorCode.invalidArgument,
        'Event payload contains a non-JSON value of type '
        '${value.runtimeType}.',
      );
  }
}
