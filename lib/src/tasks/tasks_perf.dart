import 'dart:io' show Platform, ProcessInfo;

import 'package:flutter/scheduler.dart';

import '../omni_debug_link.dart';

/// Keeps the most recent FrameTiming samples via SchedulerBinding's timing
/// callback (engine-reported, no per-frame sampling loop needed).
final List<FrameTiming> _recentTimings = [];
bool _timingHookInstalled = false;

void _ensureTimingHook() {
  if (_timingHookInstalled) return;
  _timingHookInstalled = true;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    _recentTimings.addAll(timings);
    if (_recentTimings.length > 600) {
      _recentTimings.removeRange(0, _recentTimings.length - 600);
    }
  });
}

void registerPerfTasks() {
  // Register at link START, not on first get_perf: the timings callback only
  // reports frames rendered AFTER registration (field-report bug — every
  // interaction happened before the first call, so the buffer stayed empty
  // and sampledFrames was always 0).
  _ensureTimingHook();
  OmniDebugLink.tasks.register(
    'get_perf',
    (task) async {
      final samples =
          task.intOrNull('samples', min: 1, max: 300) ?? 30;
      // Frames only exist while something is animating. If fewer than
      // requested are buffered, actively collect for up to 3s so a single
      // call right after triggering an animation still gets data.
      if (_recentTimings.length < samples) {
        final deadline =
            DateTime.now().add(const Duration(milliseconds: 3000));
        while (_recentTimings.length < samples &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      final took = _recentTimings.length > samples
          ? _recentTimings.sublist(_recentTimings.length - samples)
          : List<FrameTiming>.from(_recentTimings);

      final frame = <String, dynamic>{};
      if (took.isNotEmpty) {
        final buildMs =
            took.map((t) => t.buildDuration.inMicroseconds / 1000).toList();
        final rasterMs =
            took.map((t) => t.rasterDuration.inMicroseconds / 1000).toList();
        final totalMs = took.map(_totalMs).toList();
        buildMs.sort();
        rasterMs.sort();
        totalMs.sort();

        double fpsAvg(List<double> ms) =>
            ms.isEmpty ? 0 : 1000 / (ms.reduce((a, b) => a + b) / ms.length);

        frame['sampledFrames'] = took.length;
        frame['frameMs'] = {
          'avg': _avg(totalMs), 'min': totalMs.first, 'max': totalMs.last,
          'p50': _pct(totalMs, 0.50), 'p95': _pct(totalMs, 0.95),
          'p99': _pct(totalMs, 0.99),
        };
        frame['cpuFrameMs'] = {
          'avg': _avg(buildMs), 'max': buildMs.last,
          'p95': _pct(buildMs, 0.95),
        };
        frame['gpuFrameMs'] = {
          'avg': _avg(rasterMs), 'max': rasterMs.last,
          'p95': _pct(rasterMs, 0.95),
        };
        frame['fps'] = {'avg': fpsAvg(totalMs)};
      } else {
        frame['sampledFrames'] = 0;
        frame['hint'] = 'no frames rendered in the last 3s — trigger an '
            'animation/transition (or call this during one) to sample frame '
            'times; a static screen renders zero frames';
      }

      return <String, dynamic>{
        'memory': {
          'rssBytes': ProcessInfo.currentRss,
          'maxRssBytes': ProcessInfo.maxRss,
        },
        'frame': frame,
        'platform': {
          'operatingSystem': Platform.operatingSystem,
          'operatingSystemVersion': Platform.operatingSystemVersion,
          'numberOfProcessors': Platform.numberOfProcessors,
        },
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    },
    description:
        'Measure app performance: process memory (RSS), and frame timings '
        'from the Flutter engine (frame/build(UI)/raster(GPU) ms with '
        'p50/p95/p99 and fps over the last N rendered frames). Use for lag '
        'spike and jank investigations. Frame data needs frames to have been '
        'rendered while the link was running.',
    payloadSchema:
        '{"type":"object","properties":{"samples":{"type":"integer","minimum":1,"maximum":300,"default":30,"description":"recent frames to aggregate"}},"additionalProperties":false}',
  );
}

double _totalMs(FrameTiming t) =>
    (t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds) / 1000;

double _avg(List<double> sorted) =>
    sorted.isEmpty ? 0 : sorted.reduce((a, b) => a + b) / sorted.length;

/// Nearest-rank percentile on a sorted list.
double _pct(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final rank = ((p * sorted.length).ceil() - 1).clamp(0, sorted.length - 1);
  return sorted[rank];
}
