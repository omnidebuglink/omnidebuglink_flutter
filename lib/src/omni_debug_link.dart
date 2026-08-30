import 'dart:async';

import 'package:flutter/material.dart';

import 'link_connection.dart';
import 'log_buffer.dart';
import 'route_tracker.dart';
import 'task_registry.dart';
import 'tasks/builtin_tasks.dart';
import 'tasks/tasks_hotreload.dart';
import 'vm_bridge.dart';

export 'task_registry.dart';

enum LinkState { stopped, connecting, connected }

/// OmniDebugLink remote-debugging client entry point.
///
/// ```dart
/// // Recommended: one-call bootstrap (also captures uncaught async errors
/// // and print() via a guarded zone).
/// OmniDebugLink.bootstrap(
///   url: 'wss://api.omnidebuglink.dev/ws?token=<clientToken>',
///   app: const MyApp(),
/// );
///
/// // Or, if you manage zones yourself:
/// //   runApp(const MyApp());
/// //   OmniDebugLink.start('wss://api.omnidebuglink.dev/ws?token=<t>');
/// ```
class OmniDebugLink {
  OmniDebugLink._();

  static const libVersion = '0.1.0';

  /// Master switch for write/action tasks. false = read-only observation
  /// mode (reported in hello). Takes effect on the next hello; call
  /// [announce] to force an immediate resend.
  static bool actionsEnabled = true;

  static LinkState state = LinkState.stopped;

  static final OmniDebugLinkTaskRegistry tasks = OmniDebugLinkTaskRegistry();
  static final OmniDebugLinkLogBuffer logBuffer = OmniDebugLinkLogBuffer();
  static final OmniDebugLinkRouteTracker routeObserver =
      OmniDebugLinkRouteTracker();
  static final OmniDebugLinkVmBridge vmBridge = OmniDebugLinkVmBridge();

  static OmniDebugLinkConnection? _connection;
  static Timer? _helloCoalesce;
  static String? _appVersion;
  static bool _builtinsRegistered = false;
  static DateTime? _startedAt;

  // ---------------------------------------------------------------- start

  static Future<void> start(String url, {String? appVersion}) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (state != LinkState.stopped) return;
    _appVersion = appVersion;
    _startedAt ??= DateTime.now();

    logBuffer.install();

    tasks.onChanged = _scheduleHelloResend;
    if (!_builtinsRegistered) {
      _builtinsRegistered = true;
      registerAll(); // fires onChanged many times; coalesced below
    }

    logBuffer.record('debug link starting (lib $libVersion)',
        level: 'warning');

    final conn = OmniDebugLinkConnection(
      url: url,
      buildHello: _buildHello,
      onTask: _dispatch,
      onState: (connected) {
        state = connected ? LinkState.connected : LinkState.connecting;
        logBuffer.record('[omnidebuglink] ${connected ? "connected" : "disconnected"}',
            level: connected ? 'log' : 'warning');
      },
    )..onLog = (m) => logBuffer.record(m, level: 'warning');
    _connection = conn;
    state = LinkState.connecting;
    await conn.start();

    // Probe the VM service in the background; registers hot_reload
    // when available (debug/profile builds only).
    unawaited(vmBridge.probe().then((ok) {
      if (ok && state != LinkState.stopped) registerHotReloadTasks();
    }));
  }

  static void stop() {
    _connection?.close();
    _connection = null;
    _helloCoalesce?.cancel();
    _helloCoalesce = null;
    tasks.onChanged = null;
    logBuffer.restore();
    logBuffer.record('debug link stopped', level: 'warning');
    state = LinkState.stopped;
  }

  /// Force an immediate capability hello resend (e.g. after toggling
  /// actionsEnabled).
  static void announce() {
    if (state == LinkState.connected) _connection?.sendHello();
  }

  static Map<String, dynamic> _buildHello() => <String, dynamic>{
        'v': 1,
        'type': 'hello',
        'client': <String, dynamic>{
          'platform': 'flutter',
          'version': _appVersion ?? '?',
          'libVersion': libVersion,
          'actionsEnabled': actionsEnabled,
          'dartMode': vmBridge.isRelease ? 'release' : 'debug',
          'vmService': vmBridge.available,
        },
        'tasks': tasks.tasksJson(),
      };

  /// registerBuiltinTasks fires the onChanged callback ~21 times in a row;
  /// coalesce into a single hello resend on the next microtask tick.
  static void _scheduleHelloResend() {
    _helloCoalesce?.cancel();
    _helloCoalesce = Timer(Duration.zero, () {
      if (state == LinkState.connected) _connection?.sendHello();
    });
  }

  // ------------------------------------------------------------- dispatch

  static Future<void> _dispatch(
      String requestId, String type, Map<String, dynamic> payload) async {
    final conn = _connection;
    if (conn == null) return;
    final handler = tasks.handlerOf(type);
    if (handler == null) {
      conn.sendResultError(
          requestId,
          'UNKNOWN_TASK',
          'this client does not expose task type "$type" '
          '(call list_tasks to see available tasks)');
      return;
    }
    final task =
        OmniDebugLinkTaskRequest(requestId: requestId, type: type, payload: payload);
    try {
      final result = await handler(task);
      conn.sendResultOk(requestId, result);
    } on OmniDebugLinkTaskException catch (e) {
      conn.sendResultError(requestId, e.code, e.message);
    } catch (e, s) {
      logBuffer.recordError(e, s);
      conn.sendResultError(requestId, 'TASK_FAILED', e.toString());
    }
  }

  /// Throws when [actionsEnabled] is false; every write task calls this first.
  static void ensureActionsEnabled() {
    if (!actionsEnabled) {
      throw OmniDebugLinkTaskException('ACTIONS_DISABLED',
          'write/action tasks are disabled on this device '
          '(OmniDebugLink.actionsEnabled = false)');
    }
  }

  // ------------------------------------------------------- log capture API

  /// Escape hatch for apps that run their own zone: forward whatever your
  /// handler catches into read_logs.
  static void recordLog(String message, {String level = 'log', String? stack}) =>
      logBuffer.record(message, level: level, stack: stack);

  static void recordError(Object error, StackTrace? stack) =>
      logBuffer.recordError(error, stack);

  static String? get appVersion => _appVersion;

  static int? get uptimeMs => _startedAt == null
      ? null
      : DateTime.now().millisecondsSinceEpoch -
          _startedAt!.millisecondsSinceEpoch;

  // ------------------------------------------------------------ bootstrap

  /// One-call bootstrap: runs [app] inside a guarded zone that feeds uncaught
  /// async errors and print() output into read_logs, then starts the link.
  static void bootstrap({
    required String url,
    required Widget app,
    String? appVersion,
  }) {
    runZonedGuarded(() {
      WidgetsFlutterBinding.ensureInitialized();
      unawaited(start(url, appVersion: appVersion));
      runApp(app);
    }, (error, stack) {
      recordError(error, stack);
      FlutterError.presentError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'runZonedGuarded',
      ));
    }, zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
      recordLog(line);
      parent.print(zone, line);
    }));
  }
}
