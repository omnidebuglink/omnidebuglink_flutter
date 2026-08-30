import 'dart:async';

import 'package:vm_service/vm_service.dart' as vm;

import '../omni_debug_link.dart';

/// hot_reload — the Flutter-exclusive capability. Registered only after a
/// successful VM service probe (debug builds, and profile builds started
/// with --observe), so release builds never advertise it.
///
/// NOTE: there is deliberately NO hot_restart task. The hotRestart RPC is
/// not part of the core VM protocol — it is an external service registered
/// by `flutter run` (flutter_tools via DDS). A standalone-launched app
/// (installed APK tapped open) always gets -32601, and pure Dart cannot
/// restart the process by itself (kill leaves nobody to relaunch). Removed
/// after field testing; see clients/flutter/CLAUDE.md pitfall 25.
void registerHotReloadTasks() {
  if (!OmniDebugLink.vmBridge.available) return;

  OmniDebugLink.tasks.register(
    'hot_reload',
    (task) async {
      final bridge = OmniDebugLink.vmBridge;
      vm.VmService? client;
      try {
        client = await bridge.connect();
        final isolate = await bridge.mainIsolate(client);
        final report = await client.reloadSources(isolate.id!);
        return <String, dynamic>{
          'ok': true,
          'isolate': isolate.id,
          'isolateName': isolate.name,
          'reloaded': report.success,
          'details': {
            'loadedLibraryCount': report.json?['loadedLibraryCount'],
            'finalLibraryCount': report.json?['finalLibraryCount'],
            'errors': report.json?['errors'],
          },
        };
      } catch (e) {
        throw OmniDebugLinkTaskException('VM_SERVICE_UNAVAILABLE',
            'hot reload failed: $e (VM service reachable at start but not '
            'anymore? available in debug/profile builds only)');
      } finally {
        unawaited(client?.dispose());
      }
    },
    description:
        'Trigger a Dart hot reload on the running app (debug/profile builds '
        'only; the whole point of the Flutter debug loop: edit code, hot '
        'reload, keep testing — UI state is preserved). Reloads the main '
        'isolate\'s sources and returns the engine\'s reload report. To '
        'reset UI state, relaunch the app (there is no hot_restart: it '
        'requires a flutter run session and cannot work standalone).',
  );
}
