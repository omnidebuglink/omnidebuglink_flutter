import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../element_tree.dart';
import '../omni_debug_link.dart';
import '../pointer_injector.dart';

/// input_text / send_key / set_component (targeted writes only: Dart AOT has
/// no runtime reflection, so set_component supports an enumerated set of
/// operations instead of arbitrary member writes).
void registerTextTasks() {
  final t = OmniDebugLink.tasks;

  t.register(
    'input_text',
    (task) async {
      OmniDebugLink.ensureActionsEnabled();
      final text = task.str('text') ?? '';
      final path = task.str('path');
      final key = task.str('key');
      final widgetType = task.str('widget_type');
      final index = task.intOrNull('index', min: 0) ?? 0;

      EditableText? editable;
      if (path != null && path.isNotEmpty ||
          key != null || widgetType != null) {
        // Locator mode: find + act atomically. Note text is the VALUE being
        // typed, not a locator (use key / widget_type / path here).
        final node = OmniDebugLinkElementTree.capture().locate(
          path: path,
          key: key,
          widgetType: widgetType,
          index: index,
        );
        editable = _findEditableIn(node.element);
        if (editable == null) {
          throw OmniDebugLinkTaskException('NOT_FOUND',
              'the matched widget has no EditableText in its subtree; try '
              'widget_type=TextField, or tap the field first and omit all '
              'locators to use the focused field');
        }
      } else {
        final focus = FocusManager.instance.primaryFocus;
        if (focus == null) {
          throw OmniDebugLinkTaskException('NOT_FOUND',
              'no focused input (tap the field first, or pass key / '
              'widget_type / path)');
        }
        editable = _findEditableIn(focus.context as Element?);
      }
      if (editable == null) {
        throw OmniDebugLinkTaskException('NOT_FOUND',
            'the focused node is not a text field; pass key / widget_type / '
            'path');
      }

      final controller = editable.controller;
      controller.value = controller.value.copyWith(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: TextRange.empty,
      );
      return {
        'applied': true,
        'text': text,
        'field': path ?? key ?? widgetType ?? 'focused',
      };
    },
    description:
        'Type text into a Flutter text field and fire the controller\'s '
        'listeners so app logic reacts. Locate the field by key / '
        'widget_type (substring; text is the value being typed, not a '
        'locator) or exact path; omit all locators to target the currently '
        'focused field. Setting controller.value triggers onChanged '
        'listeners like real typing.',
    payloadSchema:
        '{"type":"object","properties":{"path":{"type":"string","description":"exact node path (fallback; prefer key)"},"key":{"type":"string","description":"widget key substring (preferred locator)"},"widget_type":{"type":"string","description":"widget type substring, e.g. TextField"},"index":{"type":"integer","minimum":0,"default":0,"description":"nth match when several widgets match"},"text":{"type":"string","description":"text to enter"}},"required":["text"],"additionalProperties":false}',
  );

  t.register(
    'send_key',
    (task) async {
      OmniDebugLink.ensureActionsEnabled();
      final key = task.str('key')?.toLowerCase();
      if (key == null) {
        throw OmniDebugLinkTaskException('TASK_INVALID', 'key is required');
      }
      final focus = FocusManager.instance.primaryFocus;
      if (focus == null) {
        throw OmniDebugLinkTaskException('NOT_FOUND',
            'no focused node to receive the key event');
      }
      // Soft dispatch through the real focus pipeline; hardware keys
      // (Android back etc.) cannot be injected from Dart.
      final physicalKey = switch (key) {
        'enter' || 'return' || 'submit' => PhysicalKeyboardKey.enter,
        'escape' || 'cancel' => PhysicalKeyboardKey.escape,
        'tab' => PhysicalKeyboardKey.tab,
        'space' => PhysicalKeyboardKey.space,
        _ => null,
      };
      if (physicalKey == null) {
        throw OmniDebugLinkTaskException('TASK_INVALID',
            'unsupported key "$key" (try enter/escape/tab/space)');
      }
      Duration stamp() => Duration(
          microseconds: DateTime.now().microsecondsSinceEpoch);
      final logicalKey =
          LogicalKeyboardKey.findKeyByKeyId(physicalKey.usbHidUsage);
      final downResult = focus.onKeyEvent?.call(
            focus,
            KeyDownEvent(
              physicalKey: physicalKey,
              logicalKey:
                  logicalKey ?? LogicalKeyboardKey.findKeyByKeyId(0x70000)!,
              timeStamp: stamp(),
            ),
          ) ??
          KeyEventResult.ignored;
      final upResult = focus.onKeyEvent?.call(
            focus,
            KeyUpEvent(
              physicalKey: physicalKey,
              logicalKey:
                  logicalKey ?? LogicalKeyboardKey.findKeyByKeyId(0x70000)!,
              timeStamp: stamp(),
            ),
          ) ??
          KeyEventResult.ignored;
      return {
        'key': key,
        'focused': focus.debugLabel ?? focus.hashCode.toString(),
        'handled': downResult == KeyEventResult.handled ||
            upResult == KeyEventResult.handled,
      };
    },
    description:
        'Send a key event (enter/escape/tab/space) to the currently focused '
        'node through Flutter\'s focus pipeline. Hardware keys (Android '
        'back/home) cannot be injected from Dart — use tap_screen on the '
        'on-screen control instead.',
    payloadSchema:
        '{"type":"object","properties":{"key":{"type":"string","enum":["enter","escape","tab","space"],"description":"enter/return/submit map to enter; escape/cancel to escape"}},"required":["key"],"additionalProperties":false}',
  );

  t.register(
    'set_component',
    (task) async {
      OmniDebugLink.ensureActionsEnabled();
      final values = task.payload['values'];
      if (values is! Map<String, dynamic> || values.isEmpty) {
        throw OmniDebugLinkTaskException('TASK_INVALID',
            'values must be a non-empty object of operation -> argument');
      }
      final node = OmniDebugLinkElementTree.capture().locate(
        path: task.str('path'),
        key: task.str('key'),
        text: task.str('text'),
        widgetType: task.str('widget_type'),
        index: task.intOrNull('index', min: 0) ?? 0,
      );
      final element = node.element;
      if (!element.mounted) {
        throw OmniDebugLinkTaskException('NOT_FOUND',
            'matched widget was unmounted; retry with the same locator');
      }

      final results = <String, dynamic>{};
      for (final entry in values.entries) {
        try {
          results[entry.key] =
              await _applySet(element, entry.key, entry.value);
        } on OmniDebugLinkTaskException catch (e) {
          results[entry.key] = {'ok': false, 'error': e.message};
        } catch (e) {
          results[entry.key] = {'ok': false, 'error': e.toString()};
        }
      }
      return {
        'target': node.props['widgetType'],
        'key': node.props['key'],
        'path': node.path,
        'results': results,
      };
    },
    description:
        'Targeted widget state writes (Flutter has no runtime reflection, '
        'so an enumerated operation set instead of arbitrary fields): '
        'text (set a TextField/EditableText controller text), '
        'scroll_offset / scroll_to_end / scroll_to_start (drive the nearest '
        'Scrollable), checked (tap a Switch/Checkbox to toggle it). '
        'Locate the widget by key / text / widget_type (+ index) or exact '
        'path — prefer key. values maps operation name to its argument. '
        'Anything else: use ui_click / tap_screen / input_text.',
    payloadSchema:
        '{"type":"object","properties":{"path":{"type":"string","description":"exact node path (fallback; prefer key)"},"key":{"type":"string","description":"widget key substring (preferred locator)"},"text":{"type":"string","description":"visible text substring"},"widget_type":{"type":"string","description":"widget type substring"},"index":{"type":"integer","minimum":0,"default":0,"description":"nth match when several widgets match"},"values":{"type":"object","additionalProperties":true,"description":"operation name -> argument: {text: string, scroll_offset: number, checked: bool}"}},"required":["values"],"additionalProperties":false}',
  );
}

EditableText? _findEditableIn(Element? element) {
  if (element == null) return null;
  EditableText? found;
  if (element.widget is EditableText) {
    found = element.widget as EditableText;
  }
  element.debugVisitOnstageChildren((child) {
    found ??= _findEditableIn(child);
  });
  return found;
}

Future<Map<String, dynamic>> _applySet(
    Element element, String op, dynamic arg) async {
  switch (op) {
    case 'text':
      final editable = _findEditableIn(element);
      if (editable == null) {
        throw OmniDebugLinkTaskException(
            'NOT_FOUND', 'no EditableText in the subtree');
      }
      final text = arg?.toString() ?? '';
      final before = editable.controller.text;
      editable.controller.value =
          editable.controller.value.copyWith(text: text);
      return {'ok': true, 'before': before, 'after': text};

    case 'scroll_offset':
    case 'scroll_to_end':
    case 'scroll_to_start':
      final position = _findScrollPosition(element);
      final before = position.pixels;
      double target;
      if (op == 'scroll_to_end') {
        target = position.maxScrollExtent;
      } else if (op == 'scroll_to_start') {
        target = 0;
      } else {
        final v = arg is num ? arg.toDouble() : null;
        if (v == null) {
          throw OmniDebugLinkTaskException(
              'TASK_INVALID', 'scroll_offset requires a numeric argument');
        }
        target = v.clamp(position.minScrollExtent, position.maxScrollExtent);
      }
      await position.animateTo(target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut);
      return {'ok': true, 'before': before, 'after': position.pixels};

    case 'checked':
      final widget = element.widget;
      final bool? current = switch (widget) {
        Switch w => w.value,
        Checkbox w => w.value,
        SwitchListTile w => w.value,
        CheckboxListTile w => w.value,
        _ => null,
      };
      if (current == null) {
        throw OmniDebugLinkTaskException('NOT_FOUND',
            'node is not a Switch/Checkbox — toggling is done by tapping; '
            'use ui_click on the node');
      }
      // Toggling must go through the gesture pipeline so onChanged fires.
      final tree = OmniDebugLinkElementTree.capture();
      final rect = tree.globalRect(element);
      if (rect == null) {
        throw OmniDebugLinkTaskException('NOT_FOUND', 'no render object');
      }
      await OmniDebugLinkPointerInjector.tap(rect.center);
      return {'ok': true, 'before': current, 'after': '!$current (tapped)'};

    default:
      throw OmniDebugLinkTaskException('TASK_INVALID',
          'unsupported operation "$op" (supported: text, scroll_offset, '
          'scroll_to_end, scroll_to_start, checked)');
  }
}

ScrollPosition _findScrollPosition(Element element) {
  // Walk up to the nearest Scrollable's state (Scrollable has no public
  // position getter on the widget itself).
  ScrollPosition? found;
  element.visitAncestorElements((ancestor) {
    if (ancestor is StatefulElement && ancestor.state is ScrollableState) {
      found = (ancestor.state as ScrollableState).position;
      return false;
    }
    return true;
  });
  if (found == null) {
    throw OmniDebugLinkTaskException('NOT_FOUND',
        'no Scrollable ancestor of this node');
  }
  return found!;
}
