import 'dart:async';
import 'dart:ui' show Size;

import '../element_tree.dart';
import '../omni_debug_link.dart';
import '../widget_info.dart';

/// Shared schema fragment for the key/text/widget_type locator params.
const _locatorDoc =
    'Locate the widget by key / text / widget_type (substrings, '
    'case-insensitive, all given filters must match) plus index (0-based, '
    'which match to use when several match), or by exact path from '
    'ui_traverse. Prefer key — paths are long and short-lived.';

const _locatorSchema =
    '"path":{"type":"string","description":"exact node path (fallback; prefer key)"},'
    '"key":{"type":"string","description":"widget key substring (preferred locator)"},'
    '"text":{"type":"string","description":"visible text substring"},'
    '"widget_type":{"type":"string","description":"widget type substring"},'
    '"index":{"type":"integer","minimum":0,"default":0,"description":"nth match when several widgets match the locator"}';

void registerUiReadTasks() {
  final t = OmniDebugLink.tasks;

  t.register(
    'ui_traverse',
    (task) {
      final tree = OmniDebugLinkElementTree.capture();
      if (task.boolOf('flat', def: true)) {
        return tree.flatJson();
      }
      final path = task.str('path');
      final depth = task.intOrNull('depth', min: 0) ?? 1;
      if (path == null || path.isEmpty) return tree.traverseJson(depth: depth);
      final node = tree.resolve(path);
      return tree.traverseJson(depth: depth, start: node);
    },
    description:
        'Dump the current widget tree of the Flutter app. Default (flat=true) '
        'returns a readable flat list: one entry per widget with depth, name, '
        'key, text, rect, center (logical px + 0-1 normalized) and path — '
        'much friendlier than nested JSON. flat=false returns the nested '
        'tree (depth levels; path selects a starting node). Keys are the '
        'stable addressing aid: use find_objects / ui_click with key=... ',
    payloadSchema:
        '{"type":"object","properties":{"flat":{"type":"boolean","default":true,"description":"flat readable list (default) vs nested tree"},"path":{"type":"string","description":"nested mode only: starting node path; empty = whole tree"},"depth":{"type":"integer","minimum":0,"default":1,"description":"nested mode only: levels to include"}},"additionalProperties":false}',
  );

  t.register(
    'find_objects',
    (task) {
      final tree = OmniDebugLinkElementTree.capture();
      final text = task.str('text');
      final key = task.str('key');
      final widgetType = task.str('widget_type');
      if (text == null && key == null && widgetType == null) {
        throw OmniDebugLinkTaskException('TASK_INVALID',
            'provide at least one of text / key / widget_type');
      }
      final view = OmniDebugLinkElementTree.viewLogicalSize();
      final objects = tree
          .findNodes(
            text: text,
            key: key,
            widgetType: widgetType,
            limit: task.intOrNull('limit', min: 1, max: 200) ?? 50,
          )
          .map((n) {
        final p = Map<String, dynamic>.from(n.props);
        final rect = p['rect'];
        if (rect is List && view != Size.zero) {
          final cx = ((rect[0] as num) + (rect[2] as num)) / 2;
          final cy = ((rect[1] as num) + (rect[3] as num)) / 2;
          p['center'] = [cx.round(), cy.round()];
          p['center01'] = [
            (cx / view.width).toStringAsFixed(4),
            (cy / view.height).toStringAsFixed(4),
          ];
        }
        return p;
      }).toList();
      return {
        'count': objects.length,
        'objects': objects,
        'hint':
            'pass the same key/text/widget_type directly to ui_click / '
            'view_component / input_text — finder + action run atomically in '
            'one task, so the path cannot go stale',
      };
    },
    description:
        'Find widgets by text / key / widget_type (substrings, '
        'case-insensitive, all filters must match), returning path, rect and '
        'center (logical px + 0-1 normalized for tap_screen). Prefer key '
        'lookups; for actions, pass the same locator straight to ui_click '
        'instead of transcribing the path.',
    payloadSchema:
        '{"type":"object","properties":{"text":{"type":"string","description":"visible text to match (substring, case-insensitive)"},"key":{"type":"string","description":"widget key to match (substring, case-insensitive)"},"widget_type":{"type":"string","description":"widget type name to match (substring, case-insensitive)"},"limit":{"type":"integer","minimum":1,"maximum":200,"default":50}},"additionalProperties":false}',
  );

  t.register(
    'view_component',
    (task) {
      final tree = OmniDebugLinkElementTree.capture();
      final node = tree.locate(
        path: task.str('path'),
        key: task.str('key'),
        text: task.str('text'),
        widgetType: task.str('widget_type'),
        index: task.intOrNull('index', min: 0) ?? 0,
      );
      if (!node.element.mounted) {
        throw OmniDebugLinkTaskException('NOT_FOUND',
            'matched widget was unmounted before inspection; retry');
      }
      final widget = node.element.widget;
      return <String, dynamic>{
        'widgetType': widget.runtimeType.toString(),
        'key': formatKey(widget.key),
        'widget': describeWidget(widget),
        'renderObject': describeRenderObject(node.element.renderObject),
        'rect': node.props['rect'],
        'snapshot': node.props,
      };
    },
    description:
        'Inspect one widget in detail: curated widget properties (text, '
        'value, enabled, callback presence), render object type/size, rect '
        'and node snapshot. $_locatorDoc Note: release builds with '
        '--obfuscate mangle widgetType names.',
    payloadSchema:
        '{"type":"object","properties":{$_locatorSchema},"additionalProperties":false}',
  );

  t.register(
    'wait_for',
    (task) async {
      final key = task.str('key');
      final textContains = task.str('text_contains');
      final widgetType = task.str('widget_type');
      final path = task.str('path');
      if (key == null && textContains == null && widgetType == null &&
          (path == null || path.isEmpty)) {
        throw OmniDebugLinkTaskException('TASK_INVALID',
            'provide at least one of key / text_contains / widget_type / path');
      }
      final timeoutMs =
          task.intOrNull('timeout_ms', min: 100, max: 60000) ?? 10000;
      final start = DateTime.now();

      while (true) {
        try {
          final tree = OmniDebugLinkElementTree.capture();
          final node = path != null && path.isNotEmpty
              ? tree.resolve(path)
              : tree.locate(
                  key: key,
                  text: textContains,
                  widgetType: widgetType,
                );
          return {
            'waitedMs': DateTime.now().millisecondsSinceEpoch -
                start.millisecondsSinceEpoch,
            'found': true,
            'node': node.props,
          };
        } on OmniDebugLinkTaskException {
          // not found yet — keep polling
        }
        final waited = DateTime.now().millisecondsSinceEpoch -
            start.millisecondsSinceEpoch;
        if (waited >= timeoutMs) {
          return {
            'waitedMs': waited,
            'found': false,
          };
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    },
    description:
        'Wait until a widget exists (polling every 0.2s): match by key '
        '(preferred), text_contains or widget_type substring, or an exact '
        'path. Returns found=true with waitedMs, or found=false on timeout '
        '(never an error). Typical use: ui_click then wait_for the target '
        'panel\'s key.',
    payloadSchema:
        '{"type":"object","properties":{"key":{"type":"string","description":"widget key substring"},"text_contains":{"type":"string","description":"visible text substring"},"widget_type":{"type":"string","description":"widget type substring"},"path":{"type":"string","description":"exact node path"},"timeout_ms":{"type":"integer","minimum":100,"maximum":60000,"default":10000}},"additionalProperties":false}',
  );
}
