import 'dart:async';
import 'dart:convert';

/// A task invocation received from the relay.
class OmniDebugLinkTaskRequest {
  OmniDebugLinkTaskRequest({
    required this.requestId,
    required this.type,
    Map<String, dynamic>? payload,
  }) : payload = payload ?? <String, dynamic>{};

  /// Relay-assigned id; echoed verbatim on the result frame.
  final String requestId;
  final String type;
  final Map<String, dynamic> payload;

  String? str(String key) => payload[key] as String?;

  int intOf(String key, {int? def, int? min, int? max}) {
    final raw = payload[key];
    var v = raw is int ? raw : (raw is num ? raw.toInt() : def);
    if (v == null) throw OmniDebugLinkTaskException('TASK_INVALID', 'missing integer field "$key"');
    if (min != null && v < min) v = min;
    if (max != null && v > max) v = max;
    return v;
  }

  int? intOrNull(String key, {int? min, int? max}) {
    final raw = payload[key];
    var v = raw is int ? raw : (raw is num ? raw.toInt() : null);
    if (v == null) return null;
    if (min != null && v < min) v = min;
    if (max != null && v > max) v = max;
    return v;
  }

  double numOf(String key) {
    final raw = payload[key];
    if (raw is num) return raw.toDouble();
    throw OmniDebugLinkTaskException('TASK_INVALID', 'missing numeric field "$key"');
  }

  bool boolOf(String key, {bool def = false}) {
    final raw = payload[key];
    return raw is bool ? raw : def;
  }
}

/// Task failure carrying a protocol error code (SUCCESS_PATH uses `ok:true`,
/// so this is the only failure channel).
class OmniDebugLinkTaskException implements Exception {
  OmniDebugLinkTaskException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

typedef OmniDebugLinkTaskHandler = FutureOr<Object?> Function(
    OmniDebugLinkTaskRequest task);

class _TaskSpec {
  _TaskSpec(this.type, this.handler, this.description, this.payloadSchema);

  final String type;
  final OmniDebugLinkTaskHandler handler;
  final String? description;
  final Object? payloadSchema; // Map or JSON string
}

class OmniDebugLinkTaskRegistry {
  final _specs = <String, _TaskSpec>{};

  /// Called (coalesced by the owner) whenever register/unregister changes the
  /// capability list, so a fresh hello can be sent. May fire on any call.
  void Function()? onChanged;

  void register(String type, OmniDebugLinkTaskHandler handler,
      {String? description, Object? payloadSchema}) {
    _specs[type] = _TaskSpec(type, handler, description, payloadSchema);
    onChanged?.call();
  }

  bool unregister(String type) {
    final removed = _specs.remove(type) != null;
    if (removed) onChanged?.call();
    return removed;
  }

  bool get isRegistered => _specs.isNotEmpty;

  int get size => _specs.length;

  bool has(String type) => _specs.containsKey(type);

  OmniDebugLinkTaskHandler? handlerOf(String type) => _specs[type]?.handler;

  /// [{type, description?, payloadSchema?}] for the hello frame.
  List<Map<String, dynamic>> tasksJson() {
    return _specs.values.map((s) {
      final m = <String, dynamic>{'type': s.type};
      if (s.description != null && s.description!.isNotEmpty) {
        m['description'] = s.description;
      }
      if (s.payloadSchema != null) {
        Object? schema = s.payloadSchema;
        if (schema is String) {
          try {
            schema = jsonDecode(schema);
          } catch (_) {
            // keep raw string if not valid JSON
          }
        }
        m['payloadSchema'] = schema;
      }
      return m;
    }).toList();
  }
}
