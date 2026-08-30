import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import '../omni_debug_link.dart';
import '../screenshot.dart';

void registerStateAndScreenshotTasks() {
  final t = OmniDebugLink.tasks;

  t.register(
    'get_state',
    (_) {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      final view = views.first;
      final mq = MediaQueryData.fromView(view);
      final tracker = OmniDebugLink.routeObserver;
      return <String, dynamic>{
        'platform': {
          'operatingSystem': Platform.operatingSystem,
          'operatingSystemVersion': Platform.operatingSystemVersion,
        },
        'locale': WidgetsBinding.instance.platformDispatcher.locale.toString(),
        'screens': views
            .map((v) => {
                  'logicalSize': [
                    (v.physicalSize.width / v.devicePixelRatio).round(),
                    (v.physicalSize.height / v.devicePixelRatio).round(),
                  ],
                  'devicePixelRatio': v.devicePixelRatio,
                })
            .toList(),
        'mediaQuery': {
          'size': [mq.size.width.round(), mq.size.height.round()],
          'padding': [mq.padding.left, mq.padding.top, mq.padding.right, mq.padding.bottom],
          'textScaleFactor': mq.textScaler.scale(1.0),
          'platformBrightness': mq.platformBrightness.name,
          'alwaysUse24HourFormat': mq.alwaysUse24HourFormat,
        },
        'routes': tracker.attached
            ? {'stack': tracker.stack, 'recentEvents': tracker.history}
            : null,
        'routesHint': tracker.attached
            ? null
            : 'add OmniDebugLink.routeObserver to MaterialApp.navigatorObservers '
                'to enable route reporting',
      };
    },
    description:
        'Snapshot of app/platform state: OS, locale, screen(s), MediaQuery '
        '(size, safe-area padding, text scale, brightness) and the current '
        'route stack (requires OmniDebugLink.routeObserver in '
        'navigatorObservers).',
  );

  t.register(
    'screenshot',
    (task) => OmniDebugLinkScreenshot.capture(
      maxSize: task.intOrNull('max_size', min: 64, max: 4096) ?? 1280,
    ),
    description:
        'Capture the app screen and return it as a PNG image (native image '
        'content block, reflects the most recent rendered frame). max_size '
        'caps the longest edge in pixels (default 1280). Coordinates map to '
        'screenshots as: x=(px+0.5)/W, y=(py+0.5)/H with the origin at the '
        'TOP-LEFT.',
    payloadSchema:
        '{"type":"object","properties":{"max_size":{"type":"integer","minimum":64,"maximum":4096,"default":1280,"description":"cap for the longest edge in pixels"}},"additionalProperties":false}',
  );
}
