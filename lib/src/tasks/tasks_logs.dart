import '../omni_debug_link.dart';

void registerLogTasks() {
  OmniDebugLink.tasks.register(
    'read_logs',
    (task) {
      final logs = OmniDebugLink.logBuffer.read(
        level: task.str('level'),
        contains: task.str('contains'),
        limit: task.intOrNull('limit', min: 1, max: 500) ?? 50,
        sinceMs: task.intOrNull('since_ms'),
      );
      return {'count': logs.length, 'logs': logs};
    },
    description:
        'Read Flutter-side logs captured since the debug link started (newest '
        'first): Flutter framework errors, uncaught platform errors, '
        'debugPrint and print output. No history before start and no native '
        'platform logs. level filters by minimum severity '
        '(log|warning|error), contains matches message text.',
    payloadSchema:
        '{"type":"object","properties":{"level":{"type":"string","enum":["log","warning","error"],"description":"minimum severity filter; omit for everything"},"contains":{"type":"string","description":"only messages containing this text (case-insensitive)"},"limit":{"type":"integer","minimum":1,"maximum":500,"default":50},"since_ms":{"type":"integer","description":"only entries with ts >= this epoch ms"}},"additionalProperties":false}',
  );
}
