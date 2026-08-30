import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Reflection-free curated widget property dump. Dart AOT forbids
/// dart:mirrors, so everything here is a static switch over concrete widget
/// types. Unknown types degrade to {widgetType, key}.
Map<String, dynamic> describeWidget(Widget widget) {
  final m = <String, dynamic>{};
  final w = widget;

  if (w is Text) {
    m['data'] = w.data ?? w.textSpan?.toPlainText();
    if (w.style?.fontSize != null) m['fontSize'] = w.style?.fontSize;
    if (w.overflow != null) m['overflow'] = w.overflow.toString();
  } else if (w is EditableText) {
    m['text'] = w.controller.text;
    m['obscureText'] = w.obscureText;
    m['readOnly'] = w.readOnly;
    m['maxLines'] = w.maxLines;
  } else if (w is TextField) {
    m['text'] = w.controller?.text;
    m['obscureText'] = w.obscureText;
    m['readOnly'] = w.readOnly;
    m['maxLines'] = w.maxLines;
    m['enabled'] = w.enabled;
  } else if (w is Icon) {
    m['icon'] = w.icon.toString();
  } else if (w is Switch) {
    m['value'] = w.value;
    m['enabled'] = w.onChanged != null;
  } else if (w is Checkbox) {
    m['value'] = w.value;
    m['enabled'] = w.onChanged != null;
  } else if (w is Slider) {
    m['value'] = w.value;
    m['min'] = w.min;
    m['max'] = w.max;
    m['divisions'] = w.divisions;
    m['enabled'] = w.onChanged != null;
  } else if (w is SwitchListTile) {
    m['value'] = w.value;
    m['title'] = _widgetText(w.title);
  } else if (w is CheckboxListTile) {
    m['value'] = w.value;
    m['title'] = _widgetText(w.title);
  } else if (w is AppBar) {
    m['title'] = _widgetText(w.title);
    m['automaticallyImplyLeading'] = w.automaticallyImplyLeading;
  } else if (w is ButtonStyleButton) {
    m['onPressed'] = w.onPressed != null;
    m['child'] = _widgetText(w.child);
  } else if (w is IconButton) {
    m['onPressed'] = w.onPressed != null;
    m['tooltip'] = w.tooltip;
  } else if (w is InkWell) {
    m['onTap'] = w.onTap != null;
  } else if (w is GestureDetector) {
    m['onTap'] = w.onTap != null;
    m['onLongPress'] = w.onLongPress != null;
  } else if (w is FloatingActionButton) {
    m['onPressed'] = w.onPressed != null;
  } else if (w is Image) {
    if (w.width != null) m['width'] = w.width;
    if (w.height != null) m['height'] = w.height;
  } else if (w is Padding) {
    m['padding'] = w.padding.toString();
  } else if (w is SizedBox) {
    m['width'] = w.width;
    m['height'] = w.height;
  } else if (w is ListView) {
    m['scrollDirection'] = w.scrollDirection.name;
  } else if (w is GridView) {
    m['scrollDirection'] = w.scrollDirection.name;
  } else if (w is Scrollable) {
    m['axis'] = w.axisDirection.name;
  }

  if (m.isEmpty) return <String, dynamic>{};
  return m;
}

String? _widgetText(Widget? widget) {
  if (widget == null) return null;
  if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText();
  return null;
}

/// Best-effort readable text of an element's widget subtree (single level:
/// Text data or EditableText controller). Returns null when nothing obvious.
String? extractText(Element element) {
  final w = element.widget;
  if (w is Text) return w.data ?? w.textSpan?.toPlainText();
  if (w is EditableText) return w.controller.text;
  if (w is TextField) return w.controller?.text;
  if (w is Tooltip) return w.message;
  var found = false;
  String? result;
  // Only look one level down for a Text child (RichText/EditableText render).
  element.debugVisitOnstageChildren((child) {
    if (!found) {
      final cw = child.widget;
      if (cw is RichText) {
        result = cw.text.toPlainText();
        found = true;
      } else if (cw is Text) {
        result = cw.data ?? cw.textSpan?.toPlainText();
        found = true;
      }
    }
  });
  return result;
}

/// Curated render-object info for view_component.
Map<String, dynamic> describeRenderObject(RenderObject? ro) {
  if (ro == null) return <String, dynamic>{};
  final m = <String, dynamic>{
    'type': ro.runtimeType.toString(),
  };
  if (ro is RenderBox && ro.attached && ro.hasSize) {
    m['size'] = [ro.size.width.round(), ro.size.height.round()];
  }
  if (ro is RenderParagraph) {
    m['text'] = ro.text.toPlainText();
  }
  if (ro is RenderEditable) {
    m['text'] = ro.plainText;
  }
  return m;
}

/// Formats a Key for display: ValueKey -> its value, others -> toString.
String? formatKey(Key? key) {
  if (key == null) return null;
  if (key is ValueKey<dynamic>) return key.value.toString();
  return key.toString();
}
