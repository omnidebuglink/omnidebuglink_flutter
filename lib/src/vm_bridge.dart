import 'dart:async';
import 'dart:developer' show Service;

import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

/// Bridge to the local Dart VM Service, powering hot_reload.
///
/// The VM service only exists in debug builds (and profile builds started
/// with --observe). probe() must be called before [available] is meaningful;
/// registration of the hot-reload tasks is gated on it so release builds
/// never advertise them (list_tasks / UNKNOWN_TASK pre-interception stay
/// accurate).
class OmniDebugLinkVmBridge {
  bool _available = false;
  Uri? _serverUri;

  bool get available => _available;
  bool get isRelease => kReleaseMode;

  /// Returns true when a VM service is reachable.
  Future<bool> probe() async {
    if (kReleaseMode) return false; // no VM service in AOT
    try {
      final info = await Service.getInfo();
      final uri = info.serverUri;
      if (uri == null) return false;
      _serverUri = uri;
      _available = true;
      return true;
    } catch (_) {
      _available = false;
      return false;
    }
  }

  Uri? get _wsUri {
    final uri = _serverUri;
    if (uri == null) return null;
    // http://host:port/authToken/ -> ws://host:port/authToken/ws
    return uri.replace(
        scheme: 'ws',
        path: uri.path.endsWith('/') ? '${uri.path}ws' : '${uri.path}/ws');
  }

  /// Lazily connect on every call: the connection is cheap and this stays
  /// correct across hot reloads (cached clients would go stale).
  Future<vm.VmService> _connect() async {
    final wsUri = _wsUri;
    if (wsUri == null) {
      throw StateError('VM service not available (debug/profile builds only)');
    }
    return vmServiceConnectUri(wsUri.toString());
  }

  Future<vm.VmService> connect() => _connect();

  /// The main UI isolate (the one whose sources a hot reload swaps).
  Future<vm.IsolateRef> mainIsolate(vm.VmService client) async {
    final vmInfo = await client.getVM();
    final isolates = vmInfo.isolates ?? const <vm.IsolateRef>[];
    if (isolates.isEmpty) throw StateError('VM reports no isolates');
    return isolates.firstWhere((i) => i.name == 'main', orElse: () => isolates.first);
  }
}
