import '../omni_debug_link.dart';

void registerBasicTasks() {
  final t = OmniDebugLink.tasks;
  t.register(
    'ping',
    (task) => {'pong': true, 'sentAt': task.payload['sentAt']},
    description:
        'Round-trip liveness probe; echoes sentAt back with pong=true.',
    payloadSchema:
        '{"type":"object","properties":{"sentAt":{"type":"integer"}},"additionalProperties":false}',
  );

  t.register(
    'echo',
    (task) => task.payload,
    description:
        'Returns the payload unchanged. Useful for smoke-testing the relay loop.',
    payloadSchema: '{"type":"object","additionalProperties":true}',
  );

  t.register(
    'get_stats',
    (_) => <String, dynamic>{
          'libVersion': OmniDebugLink.libVersion,
          'appVersion': OmniDebugLink.appVersion,
          'platform': 'flutter',
          'dartMode': OmniDebugLink.vmBridge.isRelease ? 'release' : 'debug',
          'vmService': OmniDebugLink.vmBridge.available,
          'uptimeMs': OmniDebugLink.uptimeMs,
          'tasksCount': OmniDebugLink.tasks.size,
          'actionsEnabled': OmniDebugLink.actionsEnabled,
          'connected': OmniDebugLink.state == LinkState.connected,
        },
    description:
        'Basic runtime stats: lib/app version, debug/release mode, VM service availability, uptime, task count, connection state.',
  );
}
