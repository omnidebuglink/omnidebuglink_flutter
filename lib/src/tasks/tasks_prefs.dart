import 'package:shared_preferences/shared_preferences.dart';

import '../omni_debug_link.dart';

void registerPrefsTasks() {
  OmniDebugLink.tasks.register(
    'prefs',
    (task) async {
      final action = task.str('action')?.toLowerCase();
      final key = task.str('key');
      if (action == null) {
        throw OmniDebugLinkTaskException('TASK_INVALID', 'action is required');
      }
      if (action != 'list' && key == null) {
        throw OmniDebugLinkTaskException('TASK_INVALID',
            'key is required for action "$action"');
      }
      final k = key ?? '';
      // Resolve the instance inside the handler; never cache across
      // start()/stop() cycles.
      final prefs = await SharedPreferences.getInstance();

      switch (action) {
        case 'get':
          if (!prefs.containsKey(k)) return {'key': k, 'exists': false};
          final v = prefs.get(k);
          return {
            'key': k,
            'exists': true,
            'type': _typeName(v),
            'value': v is bool || v is int || v is double || v is String
                ? v
                : v.toString(),
          };
        case 'set':
          OmniDebugLink.ensureActionsEnabled();
          final raw = task.payload['value'];
          if (raw == null) {
            throw OmniDebugLinkTaskException('TASK_INVALID',
                'set requires a value (string/int/bool/double)');
          }
          // value_type coerces (parity with the Android client): a JSON
          // string "42" with value_type=int stores int 42. Without it the
          // Dart type of the JSON value decides.
          final valueType = (task.str('value_type') ?? task.str('type'))
              ?.toLowerCase();
          final stored = switch (valueType) {
            'int' => await prefs.setInt(k, _toInt(raw)),
            'float' || 'double' => await prefs.setDouble(k, _toDouble(raw)),
            'bool' => await prefs.setBool(k, _toBool(raw)),
            'string' => await prefs.setString(k, raw.toString()),
            _ => switch (raw) {
                String s => await prefs.setString(k, s),
                bool b => await prefs.setBool(k, b),
                int i => await prefs.setInt(k, i),
                double d => await prefs.setDouble(k, d),
                _ => await prefs.setString(k, raw.toString()),
              },
          };
          // Echo the ACTUAL stored type, whatever storage decided.
          return {'key': k, 'set': stored, 'type': _typeName(prefs.get(k))};
        case 'delete':
          OmniDebugLink.ensureActionsEnabled();
          final ok = await prefs.remove(k);
          return {'key': k, 'deleted': ok};
        case 'list':
          final keys = prefs.getKeys().toList()..sort();
          return {
            'count': keys.length,
            'keys': keys.take(500).toList(),
          };
        default:
          throw OmniDebugLinkTaskException('TASK_INVALID',
              'unknown action "$action" (get|set|delete|list)');
      }
    },
    description:
        'Read/write/delete/list entries in the app\'s SharedPreferences '
        '(shared_preferences). action is get|set|delete|list; set requires '
        'value (string/int/bool/double) and optional value_type '
        '(string|int|float|bool) to coerce — {"value":"42","value_type":"int"} '
        'stores int 42 (same as the Android client).',
    payloadSchema:
        '{"type":"object","properties":{"action":{"type":"string","enum":["get","set","delete","list"]},"key":{"type":"string"},"value":{"description":"value to set (string/int/bool/double)"},"value_type":{"type":"string","enum":["string","int","float","bool"],"description":"coerce value to this type; default = the JSON value\'s own type"}},"required":["action","key"],"additionalProperties":false}',
  );
}

String _typeName(Object? v) => switch (v) {
      String _ => 'string',
      bool _ => 'bool',
      int _ => 'int',
      double _ => 'double',
      null => 'null',
      _ => 'other',
    };

int _toInt(Object raw) =>
    raw is int ? raw : int.parse(raw.toString().trim());

double _toDouble(Object raw) =>
    raw is double ? raw : double.parse(raw.toString().trim());

bool _toBool(Object raw) => switch (raw) {
      bool b => b,
      String s => s.toLowerCase() == 'true' || s == '1',
      num n => n != 0,
      _ => throw OmniDebugLinkTaskException(
          'TASK_INVALID', 'cannot coerce "$raw" to bool'),
    };
