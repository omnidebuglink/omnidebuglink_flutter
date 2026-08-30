import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Injects pointer events through GestureBinding.instance.handlePointerEvent —
/// the same entry the test framework uses — so hit-testing, the gesture arena
/// and all recognizers run exactly as for a real touch. Callbacks are never
/// invoked directly.
class OmniDebugLinkPointerInjector {
  static int _nextPointer = 1;

  /// Current monotonic-ish timestamp: recognizers (double-tap windows,
  /// velocity trackers) compare event timestamps, so they must increase
  /// across events within and across gestures.
  static Duration _stamp() =>
      Duration(microseconds: DateTime.now().microsecondsSinceEpoch);

  /// Convert 0-1 normalized coordinates (origin top-left) to logical pixels
  /// in the view's global space. Pointer positions are logical pixels —
  /// never multiply by devicePixelRatio (only physicalSize is physical).
  static Offset toLogical(double x, double y, {int viewId = 0}) {
    final view = WidgetsBinding
        .instance.platformDispatcher.views.firstWhere((v) => v.viewId == viewId,
            orElse: () =>
                WidgetsBinding.instance.platformDispatcher.views.first);
    return Offset(
      x * view.physicalSize.width / view.devicePixelRatio,
      y * view.physicalSize.height / view.devicePixelRatio,
    );
  }

  static void _down(int pointer, Offset pos, int viewId) =>
      GestureBinding.instance.handlePointerEvent(PointerDownEvent(
        pointer: pointer,
        position: pos,
        kind: PointerDeviceKind.touch,
        timeStamp: _stamp(),
        viewId: viewId,
      ));

  static void _move(int pointer, Offset pos, Offset delta, int viewId) =>
      GestureBinding.instance.handlePointerEvent(PointerMoveEvent(
        pointer: pointer,
        position: pos,
        delta: delta,
        timeStamp: _stamp(),
        viewId: viewId,
      ));

  static void _up(int pointer, Offset pos, int viewId) =>
      GestureBinding.instance.handlePointerEvent(PointerUpEvent(
        pointer: pointer,
        position: pos,
        kind: PointerDeviceKind.touch,
        timeStamp: _stamp(),
        viewId: viewId,
      ));

  /// Down + Up at the same point, a few ms apart (tap recognizers check the
  /// down->up window and slop).
  static Future<void> tap(Offset logical, {int viewId = 0}) async {
    final pointer = _nextPointer++;
    _down(pointer, logical, viewId);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    _up(pointer, logical, viewId);
  }

  /// Down, hold (recognizer's own timer fires the long-press callback),
  /// Up. No click semantics.
  static Future<void> longPress(Offset logical, Duration hold,
      {int viewId = 0}) async {
    final pointer = _nextPointer++;
    _down(pointer, logical, viewId);
    await Future<void>.delayed(hold);
    _up(pointer, logical, viewId);
  }

  /// Down -> interpolated moves (16ms apart; Scrollable inertia needs real
  /// movement history with delta+timeStamp) -> Up.
  static Future<void> swipe(Offset a, Offset b, Duration duration,
      {int viewId = 0}) async {
    final pointer = _nextPointer++;
    _down(pointer, a, viewId);
    final moveCount = (duration.inMilliseconds / 16).round().clamp(2, 200);
    // Spreading moves so total wall time ~= duration keeps velocity
    // estimation realistic (Scrollable fling inertia depends on it).
    final stepDelay = Duration(
        microseconds:
            (duration.inMicroseconds / moveCount).round());
    var last = a;
    for (var i = 1; i <= moveCount; i++) {
      await Future<void>.delayed(stepDelay);
      final t = i / moveCount;
      final target = Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
      _move(pointer, target, target - last, viewId);
      last = target;
    }
    await Future<void>.delayed(const Duration(milliseconds: 16));
    _up(pointer, b, viewId);
  }
}
