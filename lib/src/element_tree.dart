import 'package:flutter/material.dart';

import 'task_registry.dart';
import 'widget_info.dart';

/// A snapshot of the element tree captured through
/// Element.debugVisitOnstageChildren (onstage children only — plain
/// visitChildren would include offstage overlay entries and confuse path
/// indices). The snapshot is built synchronously; paths are only valid until
/// the next rebuild, so every task re-captures.
class OmniDebugLinkElementTree {
  OmniDebugLinkElementTree._(this.root);

  final ElementNode root;
  static const maxNodes = 3000;
  int nodeCount = 0;
  bool truncated = false;

  static OmniDebugLinkElementTree capture() {
    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement == null) {
      throw OmniDebugLinkTaskException('NO_TREE',
          'no frame has been rendered yet; retry after the first frame');
    }
    final tree = OmniDebugLinkElementTree._(ElementNode('0', rootElement));
    final ctx = _CaptureContext();
    // Walk synchronously (no awaits — a frame boundary mid-walk can unmount
    // elements under us).
    tree._build(tree.root, '0', 1, true, ctx);
    tree.nodeCount = ctx.count;
    tree.truncated = ctx.truncated;
    return tree;
  }

  void _build(ElementNode node, String path, int depth, bool pointerEnabled,
      _CaptureContext ctx) {
    ctx.count++;
    node.props = _props(node.element, path, pointerEnabled);
    final element = node.element;
    bool childPointerEnabled = pointerEnabled;
    final w = element.widget;
    if (w is IgnorePointer && w.ignoring) childPointerEnabled = false;
    if (w is AbsorbPointer && w.absorbing) childPointerEnabled = false;

    element.debugVisitOnstageChildren((child) {
      if (ctx.count >= maxNodes) {
        ctx.truncated = true;
        return;
      }
      final childPath = '$path/${node.children.length}';
      final childNode = ElementNode(childPath, child);
      node.children.add(childNode);
      _build(childNode, childPath, depth + 1, childPointerEnabled, ctx);
    });
  }

  Map<String, dynamic> _props(Element element, String path,
      bool pointerEnabled) {
    final widget = element.widget;
    final m = <String, dynamic>{
      'path': path,
      'widgetType': widget.runtimeType.toString(),
    };
    final key = formatKey(widget.key);
    if (key != null) m['key'] = key;
    final text = extractText(element);
    if (text != null && text.isNotEmpty) m['text'] = text;
    final rect = globalRect(element);
    if (rect != null) {
      m['rect'] = [
        rect.left.round(),
        rect.top.round(),
        rect.right.round(),
        rect.bottom.round(),
      ];
      m['size'] = [
        (rect.right - rect.left).round(),
        (rect.bottom - rect.top).round(),
      ];
      m['visible'] = rect.width > 0.5 && rect.height > 0.5;
    } else {
      m['visible'] = false;
    }
    if (!pointerEnabled) m['enabled'] = false;
    _addChecked(m, widget);
    return m;
  }

  void _addChecked(Map<String, dynamic> m, Widget w) {
    if (w is Switch) m['checked'] = w.value;
    if (w is Checkbox) m['checked'] = w.value;
    if (w is SwitchListTile) m['checked'] = w.value;
    if (w is CheckboxListTile) m['checked'] = w.value;
  }

  /// Global LOGICAL-pixel rect (origin top-left of the view); null when the
  /// render object is detached (transient during rebuilds).
  ///
  /// The transform up to the root RenderView includes the root layer's
  /// device-pixel-ratio matrix, so the raw result is in PHYSICAL pixels —
  /// verified by test/coordinate_space_test.dart (200-logical box reported
  /// 600 at dpr 3). Pointer events and all task outputs use logical pixels,
  /// so divide by dpr here (single-view assumption, like elsewhere).
  Rect? globalRect(Element element) {
    try {
      final ro = element.renderObject;
      final rootRo = root.element.renderObject;
      if (ro is! RenderBox || !ro.attached || !ro.hasSize || rootRo == null) {
        return null;
      }
      final transform = ro.getTransformTo(rootRo);
      final dpr = WidgetsBinding
          .instance.platformDispatcher.views.first.devicePixelRatio;
      final topLeft =
          MatrixUtils.transformPoint(transform, Offset.zero) / dpr;
      final bottomRight = MatrixUtils.transformPoint(
              transform, Offset(ro.size.width, ro.size.height)) /
          dpr;
      return Rect.fromLTRB(
          topLeft.dx, topLeft.dy, bottomRight.dx, bottomRight.dy);
    } catch (_) {
      return null;
    }
  }

  /// Resolve "0", "0/3/2" (index = position among onstage children).
  ElementNode resolve(String path) {
    final segments = path.split('/');
    if (segments.isEmpty || segments.first != '0') {
      throw OmniDebugLinkTaskException('BAD_PATH',
          'path must start at the root "0" (e.g. "0/3/2"), got "$path"');
    }
    var node = root;
    for (final seg in segments.skip(1)) {
      final idx = int.tryParse(seg);
      if (idx == null || idx < 0 || idx >= node.children.length) {
        throw OmniDebugLinkTaskException('NOT_FOUND',
            'no node at "$path" in the current tree (paths are only valid '
            'within a single interaction; re-run ui_traverse or find_objects '
            'to get fresh paths)');
      }
      node = node.children[idx];
    }
    return node;
  }

  /// Substring (case-insensitive) search over text / key / widgetType,
  /// returning live nodes (find + act can complete atomically within one
  /// task — the primary addressing mode on Flutter, where raw paths are
  /// long and short-lived).
  List<ElementNode> findNodes({
    String? text,
    String? key,
    String? widgetType,
    int limit = 200,
  }) {
    final out = <ElementNode>[];
    bool matches(ElementNode node) {
      final p = node.props;
      if (text != null &&
          !(p['text'] as String? ?? '')
              .toLowerCase()
              .contains(text.toLowerCase())) {
        return false;
      }
      if (key != null &&
          !(p['key'] as String? ?? '')
              .toLowerCase()
              .contains(key.toLowerCase())) {
        return false;
      }
      if (widgetType != null &&
          !(p['widgetType'] as String)
              .toLowerCase()
              .contains(widgetType.toLowerCase())) {
        return false;
      }
      return true;
    }

    void visit(ElementNode node) {
      if (out.length >= limit) return;
      if (matches(node)) out.add(node);
      _visitChildren(node, visit);
    }

    visit(root);
    return out;
  }

  /// Props snapshots of [findNodes] matches.
  List<Map<String, dynamic>> find({
    String? text,
    String? key,
    String? widgetType,
    int limit = 200,
  }) =>
      findNodes(text: text, key: key, widgetType: widgetType, limit: limit)
          .map((n) => Map<String, dynamic>.from(n.props))
          .toList();

  /// Unified locator resolution for action tasks: an explicit [path]
  /// (precise fallback), or key/text/widgetType substring match with [index]
  /// picking the nth match (disambiguation when "Item 1" also matches
  /// "Item 10"). Find + act in one call so the tree cannot change in between.
  ElementNode locate({
    String? path,
    String? key,
    String? text,
    String? widgetType,
    int index = 0,
  }) {
    final hasFinder = key != null || text != null || widgetType != null;
    if (!hasFinder && (path == null || path.isEmpty)) {
      throw OmniDebugLinkTaskException('TASK_INVALID',
          'provide a locator: key / text / widget_type (+ index), or path');
    }
    if (path != null && path.isNotEmpty) return resolve(path);
    final matches = findNodes(
        key: key, text: text, widgetType: widgetType, limit: 500);
    if (matches.isEmpty) {
      throw OmniDebugLinkTaskException('NOT_FOUND',
          'no widget matches '
          '{key: $key, text: $text, widget_type: $widgetType}; re-run '
          'find_objects to see what is on screen');
    }
    if (index < 0 || index >= matches.length) {
      throw OmniDebugLinkTaskException('NOT_FOUND',
          'index $index out of range: ${matches.length} widget(s) match '
          '{key: $key, text: $text, widget_type: $widgetType}');
    }
    return matches[index];
  }

  void _visitChildren(ElementNode node, void Function(ElementNode) visitor) {
    for (final c in node.children) {
      visitor(c);
    }
  }

  /// Deepest visible node whose rect contains the logical point.
  Map<String, dynamic>? hitTest(Offset point) {
    Map<String, dynamic>? best;
    int bestDepth = -1;

    void visit(ElementNode node, int depth) {
      final rect = _rectOf(node);
      if (rect == null || !rect.contains(point)) return;
      if (node.children.isEmpty) {
        if (depth > bestDepth) {
          bestDepth = depth;
          best = Map<String, dynamic>.from(node.props);
        }
      } else {
        for (final c in node.children) {
          visit(c, depth + 1);
        }
        if (bestDepth < 0) {
          bestDepth = depth;
          best = Map<String, dynamic>.from(node.props);
        }
      }
    }

    visit(root, 0);
    return best;
  }

  Rect? _rectOf(ElementNode node) {
    final r = node.props['rect'];
    if (r is! List) return null;
    return Rect.fromLTRB(
        (r[0] as num).toDouble(),
        (r[1] as num).toDouble(),
        (r[2] as num).toDouble(),
        (r[3] as num).toDouble());
  }

  /// JSON dump for ui_traverse (whole tree, or the subtree at [start]).
  Map<String, dynamic> traverseJson({int depth = 1, ElementNode? start}) {
    Map<String, dynamic> nodeJson(ElementNode node, int remaining) {
      final m = Map<String, dynamic>.from(node.props);
      if (remaining > 1 && node.children.isNotEmpty) {
        m['children'] =
            node.children.map((c) => nodeJson(c, remaining - 1)).toList();
      } else if (node.children.isNotEmpty) {
        m['childCount'] = node.children.length;
      }
      return m;
    }

    return <String, dynamic>{
      'root': nodeJson(start ?? root, depth < 1 ? 1 : depth),
      'nodeCount': nodeCount,
      'truncated': truncated,
    };
  }

  /// Flat, readable dump for ui_traverse: one entry per node with depth /
  /// name / key / text / rect / center / visible. Nested mode shows tree
  /// structure but wastes tokens on Flutter's deep wrapper chains; the flat
  /// list is the default for AI consumption.
  Map<String, dynamic> flatJson() {
    final view = viewLogicalSize();
    final nodes = <Map<String, dynamic>>[];

    void visit(ElementNode node, int depth) {
      if (nodes.length >= maxNodes) return;
      final p = node.props;
      final entry = <String, dynamic>{
        'depth': depth,
        'name': p['widgetType'],
        'visible': p['visible'] ?? false,
      };
      if (p['key'] != null) entry['key'] = p['key'];
      if (p['text'] != null) entry['text'] = p['text'];
      if (p['enabled'] == false) entry['enabled'] = false;
      if (p['checked'] != null) entry['checked'] = p['checked'];
      final rect = _rectOf(node);
      if (rect != null) {
        entry['rect'] = p['rect'];
        final c = rect.center;
        entry['center'] = [c.dx.round(), c.dy.round()];
        if (view != Size.zero) {
          entry['center01'] = [
            (c.dx / view.width).toStringAsFixed(4),
            (c.dy / view.height).toStringAsFixed(4),
          ];
        }
      }
      entry['path'] = node.path;
      nodes.add(entry);
      for (final c in node.children) {
        visit(c, depth + 1);
      }
    }

    visit(root, 0);
    return <String, dynamic>{
      'flat': true,
      'viewSize': [view.width.round(), view.height.round()],
      'nodes': nodes,
      'nodeCount': nodeCount,
      'truncated': truncated,
    };
  }

  /// Logical size of the first view (for normalizing coordinates).
  static Size viewLogicalSize() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return Size(
      view.physicalSize.width / view.devicePixelRatio,
      view.physicalSize.height / view.devicePixelRatio,
    );
  }
}

class _CaptureContext {
  int count = 0;
  bool truncated = false;
}

class ElementNode {
  ElementNode(this.path, this.element);

  final String path;
  final Element element;
  final List<ElementNode> children = [];
  Map<String, dynamic> props = const {};
}
