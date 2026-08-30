import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidebuglink/src/element_tree.dart';

void main() {
  testWidgets('element tree rect is in LOGICAL pixels', (tester) async {
    // TestFlutterView defaults: logical 800x600, devicePixelRatio 3.0.
    // If globalRect() returned physical pixels, a full-width box would
    // report width 2400 instead of 800.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: Key('probe_box'),
              width: 200,
              height: 100,
              child: Text('probe'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final view = tester.view;
    expect(view.devicePixelRatio, 3.0);

    final tree = OmniDebugLinkElementTree.capture();
    final matches = tree.findNodes(key: 'probe_box');
    expect(matches, isNotEmpty);
    final rect = tree.globalRect(matches.first.element)!;
    // Logical expectations: width 200, height 100, centered in 800x600.
    expect(rect.width, closeTo(200, 1.0),
        reason: 'physical would be 600 at dpr 3');
    expect(rect.height, closeTo(100, 1.0),
        reason: 'physical would be 300 at dpr 3');
    expect(rect.center.dx, closeTo(400, 1.0));
    expect(rect.center.dy, closeTo(300, 1.0));

    final flat = tree.flatJson();
    expect(flat['viewSize'], [800, 600]);
    final entry = (flat['nodes'] as List).firstWhere(
      (n) => n['key'] == 'probe_box',
      orElse: () => throw 'probe_box not in flat dump',
    );
    // center01 must be within 0..1 — the field-report bug. Values are
    // strings (toStringAsFixed) for payload compactness.
    final center01 = entry['center01'] as List;
    for (final v in center01) {
      final d = double.parse(v as String);
      expect(d >= 0 && d <= 1, isTrue,
          reason: 'center01 out of range: $center01');
    }
    expect(double.parse(center01[0] as String), closeTo(0.5, 0.01));
    expect(double.parse(center01[1] as String), closeTo(0.5, 0.01));
  });
}
