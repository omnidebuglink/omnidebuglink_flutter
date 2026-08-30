import 'package:flutter/widgets.dart';

import '../element_tree.dart';
import '../omni_debug_link.dart';
import '../pointer_injector.dart';

const _coordDoc =
    'Coordinates are floats 0..1, origin at the TOP-LEFT corner of the screen. '
    'For a pixel (px, py) in a returned screenshot of size W×H (image origin '
    'top-left): x=(px+0.5)/W, y=(py+0.5)/H (no vertical flip).';

void registerInputTasks() {
  final t = OmniDebugLink.tasks;

  t.register(
    'ui_click',
    (task) async {
      OmniDebugLink.ensureActionsEnabled();
      final path = task.str('path');
      final key = task.str('key');
      final text = task.str('text');
      final widgetType = task.str('widget_type');
      if (path == null && key == null && text == null && widgetType == null) {
        throw OmniDebugLinkTaskException('TASK_INVALID',
            'provide a locator: key / text / widget_type (+ index), or path');
      }
      final tree = OmniDebugLinkElementTree.capture();
      // locate() + tap inside one task: the tree cannot change in between.
      final node = tree.locate(
        path: path,
        key: key,
        text: text,
        widgetType: widgetType,
        index: task.intOrNull('index', min: 0) ?? 0,
      );
      if (!node.element.mounted) {
        throw OmniDebugLinkTaskException('NOT_FOUND',
            'matched widget was unmounted before the tap; retry with the '
            'same locator');
      }
      // Fresh live rect (snapshot may predate a rebuild).
      final rect = tree.globalRect(node.element);
      if (rect == null) {
        throw OmniDebugLinkTaskException('NOT_FOUND',
            'matched widget has no render object right now; retry');
      }
      final center = rect.center;
      await OmniDebugLinkPointerInjector.tap(center);
      final hit = tree.hitTest(center);
      return {
        'target': node.props['widgetType'],
        'key': node.props['key'],
        'text': node.props['text'],
        'path': node.path,
        'tapAt': [center.dx.round(), center.dy.round()],
        'hitNode': hit?['widgetType'],
        'executed': true,
      };
    },
    description:
        'Click a widget through the real Flutter gesture pipeline '
        '(hit-testing + gesture arena, exactly like a real touch). Locate it '
        'by key / text / widget_type (substrings, case-insensitive) + index '
        'for the nth match, or by exact path — the finder and the tap run '
        'atomically in one call, so stale paths are not an issue. Prefer key. '
        'Use tap_screen to click by normalized screen coordinates instead.',
    payloadSchema:
        '{"type":"object","properties":{"path":{"type":"string","description":"exact node path (fallback; prefer key)"},"key":{"type":"string","description":"widget key substring (preferred locator)"},"text":{"type":"string","description":"visible text substring"},"widget_type":{"type":"string","description":"widget type substring"},"index":{"type":"integer","minimum":0,"default":0,"description":"nth match when several widgets match"}},"additionalProperties":false}',
  );

  t.register(
    'tap_screen',
    (task) async {
      OmniDebugLink.ensureActionsEnabled();
      final x = task.numOf('x');
      final y = task.numOf('y');
      if (x < 0 || x > 1 || y < 0 || y > 1) {
        throw OmniDebugLinkTaskException('TASK_INVALID',
            'x and y must be within 0..1');
      }
      final logical = OmniDebugLinkPointerInjector.toLogical(x, y);
      await OmniDebugLinkPointerInjector.tap(logical);
      final view =
          WidgetsBinding.instance.platformDispatcher.views.first;
      return {
        'x': x,
        'y': y,
        'px': logical.dx.round(),
        'py': logical.dy.round(),
        'screen': {
          'width': (view.physicalSize.width / view.devicePixelRatio).round(),
          'height': (view.physicalSize.height / view.devicePixelRatio).round(),
        },
        'executed': true,
      };
    },
    description:
        'Simulate a tap on the screen through the real gesture pipeline. '
        '$_coordDoc Returns the resolved logical pixel position and the '
        'screen size.',
    payloadSchema:
        '{"type":"object","properties":{"x":{"type":"number","minimum":0,"maximum":1,"description":"horizontal position, 0=left, 1=right"},"y":{"type":"number","minimum":0,"maximum":1,"description":"vertical position, 0=top, 1=bottom"}},"required":["x","y"],"additionalProperties":false}',
  );

  t.register(
    'swipe',
    (task) async {
      OmniDebugLink.ensureActionsEnabled();
      final x1 = task.numOf('x1'), y1 = task.numOf('y1');
      final x2 = task.numOf('x2'), y2 = task.numOf('y2');
      for (final v in [x1, y1, x2, y2]) {
        if (v < 0 || v > 1) {
          throw OmniDebugLinkTaskException('TASK_INVALID',
              'coordinates must be within 0..1');
        }
      }
      final durationMs =
          task.intOrNull('duration_ms', min: 50, max: 3000) ?? 300;
      final a = OmniDebugLinkPointerInjector.toLogical(x1, y1);
      final b = OmniDebugLinkPointerInjector.toLogical(x2, y2);
      await OmniDebugLinkPointerInjector.swipe(
          a, b, Duration(milliseconds: durationMs));
      return {
        'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2,
        'duration_ms': durationMs,
        'from': [a.dx.round(), a.dy.round()],
        'to': [b.dx.round(), b.dy.round()],
        'executed': true,
      };
    },
    description:
        'Simulate a swipe/drag through the real gesture pipeline (scroll '
        'lists, sliders, drag-and-drop; fling inertia works — moves are '
        'spread across the duration with realistic velocity). '
        '$_coordDoc duration_ms controls the gesture speed.',
    payloadSchema:
        '{"type":"object","properties":{"x1":{"type":"number","minimum":0,"maximum":1},"y1":{"type":"number","minimum":0,"maximum":1},"x2":{"type":"number","minimum":0,"maximum":1},"y2":{"type":"number","minimum":0,"maximum":1},"duration_ms":{"type":"integer","minimum":50,"maximum":3000,"default":300}},"required":["x1","y1","x2","y2"],"additionalProperties":false}',
  );

  t.register(
    'long_press',
    (task) async {
      OmniDebugLink.ensureActionsEnabled();
      final x = task.numOf('x'), y = task.numOf('y');
      if (x < 0 || x > 1 || y < 0 || y > 1) {
        throw OmniDebugLinkTaskException('TASK_INVALID',
            'x and y must be within 0..1');
      }
      final durationMs =
          task.intOrNull('duration_ms', min: 200, max: 5000) ?? 800;
      final p = OmniDebugLinkPointerInjector.toLogical(x, y);
      await OmniDebugLinkPointerInjector.longPress(
          p, Duration(milliseconds: durationMs));
      return {
        'x': x, 'y': y, 'duration_ms': durationMs,
        'px': p.dx.round(), 'py': p.dy.round(),
        'executed': true,
      };
    },
    description:
        'Simulate a long press at one screen point (pointer down, hold '
        'duration_ms, pointer up; no click event). $_coordDoc',
    payloadSchema:
        '{"type":"object","properties":{"x":{"type":"number","minimum":0,"maximum":1},"y":{"type":"number","minimum":0,"maximum":1},"duration_ms":{"type":"integer","minimum":200,"maximum":5000,"default":800}},"required":["x","y"],"additionalProperties":false}',
  );
}
