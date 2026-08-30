import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'task_registry.dart';

/// Full-screen capture via the root render view's OffsetLayer, encoded as
/// PNG (dart:ui has no JPEG encoder; UI screenshots are flat-color
/// dominated so PNG sits comfortably in the base64 budget).
class OmniDebugLinkScreenshot {
  /// Budget applies to the base64 STRING length (base64 inflates 4/3), kept
  /// under the relay's ~900KB single-message cap.
  static const maxBase64Length = 850000;
  static const minLongestEdge = 200;

  static Future<Map<String, dynamic>> capture({int maxSize = 1280}) async {
    await SchedulerBinding.instance.endOfFrame; // scene must be complete
    final renderView = WidgetsBinding.instance.renderViews.first;
    // RenderObject.layer is nominally protected; the root layer is the only
    // public-ish handle on the composited scene (flutter_test does the same).
    // ignore: invalid_use_of_protected_member
    final layer = renderView.layer;
    if (layer is! OffsetLayer) {
      throw OmniDebugLinkTaskException('NO_FRAME',
          'nothing has been rendered yet; retry after the first frame');
    }
    // RenderView is not a RenderBox — take logical size from the view.
    final view =
        WidgetsBinding.instance.platformDispatcher.views.first;
    final logicalSize = Size(
      view.physicalSize.width / view.devicePixelRatio,
      view.physicalSize.height / view.devicePixelRatio,
    );

    // Cap the longest edge at maxSize via pixelRatio (physical resolution
    // is logical * dpr).
    final longest = logicalSize.longestSide;
    var pixelRatio = 1.0;
    if (longest * view.devicePixelRatio > maxSize) {
      pixelRatio = maxSize / longest;
    }

    var image = await _toImage(layer, logicalSize, pixelRatio);
    final originalWidth = image.width;
    final originalHeight = image.height;

    var bytes = await _pngBytes(image);
    var b64 = base64Encode(bytes);
    var downscales = 0;
    while (b64.length > maxBase64Length && downscales < 3) {
      final next = await _downscale(image, 0.75);
      image.dispose();
      image = next;
      bytes = await _pngBytes(image);
      b64 = base64Encode(bytes);
      downscales++;
      if (image.width < minLongestEdge || image.height < minLongestEdge) break;
    }
    if (b64.length > maxBase64Length) {
      image.dispose();
      throw OmniDebugLinkTaskException('SCREENSHOT_TOO_LARGE',
          'encoded screenshot still exceeds $maxBase64Length base64 chars after downscaling; try a smaller maxSize');
    }

    final result = <String, dynamic>{
      'format': 'png',
      'width': image.width,
      'height': image.height,
      'originalWidth': originalWidth,
      'originalHeight': originalHeight,
      'bytes': bytes.length,
      '__odl_file': {'mime': 'image/png', 'data': b64},
    };
    image.dispose();
    return result;
  }

  static Future<ui.Image> _toImage(
      OffsetLayer layer, Size logicalSize, double pixelRatio) {
    return layer.toImage(Offset.zero & logicalSize, pixelRatio: pixelRatio);
  }

  static Future<List<int>> _pngBytes(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw OmniDebugLinkTaskException('TASK_FAILED',
          'image.toByteData returned null');
    }
    return data.buffer.asUint8List();
  }

  static Future<ui.Image> _downscale(ui.Image source, double scale) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final w = (source.width * scale).round();
    final h = (source.height * scale).round();
    canvas.scale(w / source.width, h / source.height);
    canvas.drawImage(source, Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    final out = await picture.toImage(w, h);
    picture.dispose();
    return out;
  }
}
