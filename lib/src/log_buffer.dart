import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'dart:ui' show ErrorCallback;

/// Ring buffer of captured Flutter-side logs (capacity 1000, newest last).
///
/// Capture matrix (be honest in docs):
/// - FlutterError (build/layout exceptions): always captured (onError chained).
/// - Uncaught platform dispatch errors: always captured (PlatformDispatcher.onError).
/// - debugPrint: captured while the link is started.
/// - Uncaught async errors + print(): only inside OmniDebugLink.bootstrap's zone.
/// - Native platform logs / anything before start(): NOT captured (no history).
class OmniDebugLinkLogBuffer {
  static const capacity = 1000;
  static const maxMessageChars = 4096;
  static const maxStackChars = 8192;

  final _entries = Queue<Map<String, dynamic>>();

  void record(String message,
      {String level = 'log', String? stack, int? ts}) {
    if (message.length > maxMessageChars) {
      message = '${message.substring(0, maxMessageChars)}…';
    }
    if (stack != null && stack.length > maxStackChars) {
      stack = '${stack.substring(0, maxStackChars)}…';
    }
    final entry = <String, dynamic>{
      'ts': ts ?? DateTime.now().millisecondsSinceEpoch,
      'level': level,
      'message': message,
      if (stack != null && stack.isNotEmpty && level != 'log') 'stack': stack,
    };
    _entries.add(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
  }

  void recordError(Object error, StackTrace? stack) {
    record(error.toString(), level: 'error', stack: stack?.toString());
  }

  /// Newest first, with level/contains/limit/sinceMs filters.
  List<Map<String, dynamic>> read({
    String? level,
    String? contains,
    int limit = 50,
    int? sinceMs,
  }) {
    int severity(String s) => switch (s) {
          'log' => 0,
          'warning' => 1,
          'error' => 2,
          _ => -1,
        };
    final minSev = severity(level ?? '');
    final out = <Map<String, dynamic>>[];
    for (final e in _entries.toList().reversed) {
      if (minSev >= 0 && (severity(e['level'] as String? ?? 'log') < minSev)) {
        continue;
      }
      if (contains != null &&
          !(e['message'] as String).toLowerCase().contains(contains.toLowerCase())) {
        continue;
      }
      if (sinceMs != null && (e['ts'] as int) < sinceMs) continue;
      out.add(e);
      if (out.length >= limit) break;
    }
    return out;
  }

  // ---------------------------------------------------------- hook install

  FlutterExceptionHandler? _prevFlutterError;
  ErrorCallback? _prevPlatformError;
  DebugPrintCallback? _prevDebugPrint;
  bool _installed = false;

  void install() {
    if (_installed) return;
    _installed = true;

    _prevFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      // Include the exception text itself — toStringShort() alone only says
      // "Exception caught by widgets library" and forces stack-reading to
      // guess what happened.
      record(
        '${details.toStringShort()}\n${details.exception}',
        level: 'error',
        stack: details.stack?.toString(),
      );
      _prevFlutterError?.call(details);
    };

    _prevPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      recordError(error, stack);
      return _prevPlatformError?.call(error, stack) ?? true;
    };

    _prevDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        // debugPrint throttles long lines; record the full text ourselves.
        final firstLine = message.split('\n').first;
        record(firstLine.length < 200 ? message : firstLine);
      }
      _prevDebugPrint?.call(message, wrapWidth: wrapWidth);
    };
  }

  void restore() {
    if (!_installed) return;
    _installed = false;
    FlutterError.onError = _prevFlutterError;
    PlatformDispatcher.instance.onError = _prevPlatformError;
    if (_prevDebugPrint != null) debugPrint = _prevDebugPrint!;
  }

  void clear() => _entries.clear();
}
