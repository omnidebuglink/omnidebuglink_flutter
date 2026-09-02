# omnidebuglink (Flutter)

OmniDebugLink client SDK for Flutter: connect a running Flutter app to the
OmniDebugLink relay so AI coding tools (via MCP) can debug and automate it
directly — traverse the widget tree, tap/swipe, screenshot, read logs,
inspect performance, read/write preferences, plus the Flutter-exclusive
**hot_reload** (AI edits code, hot-reloads remotely, keeps testing).

Pure Dart package, no platform channels. Protocol and shared client rules:
see `../CLAUDE.md` in this repo.

## Install (git dependency)

```yaml
dependencies:
  omnidebuglink:
    git:
      url: https://github.com/omnidebuglink/omnidebuglink_flutter.git
      ref: v0.1.0
```

## Quick start

```dart
import 'package:omnidebuglink/omnidebuglink.dart';

void main() {
  OmniDebugLink.bootstrap(          // recommended: takes over the zone,
    url: 'wss://api.omnidebuglink.dev/ws?token=<clientToken>', // catching uncaught async errors & print
    appVersion: '1.2.0',
    app: const MyApp(),
  );
}
```

Or manage the lifecycle yourself:

```dart
runApp(const MyApp());
await OmniDebugLink.start('wss://api.omnidebuglink.dev/ws?token=<clientToken>');
```

Route-stack reporting (optional — without it get_state returns routes:null
plus guidance):

```dart
MaterialApp(navigatorObservers: [OmniDebugLink.routeObserver], ...)
```

Key points:

- **One token pair per device.** Two connections sharing a token kick each
  other; on close code 4000 the SDK stops permanently and logs a warning.
- `OmniDebugLink.actionsEnabled` (default true): master switch for write
  operations — false = read-only observation mode, announced with hello.
- `OmniDebugLink.tasks.register(type, handler, description:, payloadSchema:)`
  registers custom tasks; registry changes re-announce capabilities
  automatically, zero server changes.

## Built-in tasks (19 + 2 conditional)

Read: `ui_traverse` (widget tree dump) / `find_objects` / `view_component` /
`wait_for` / `screenshot` (PNG) / `read_logs` / `get_perf` / `get_state` / `prefs`
Write: `ui_click` / `tap_screen` / `swipe` / `long_press` / `input_text` /
`set_component` (targeted operations) / `send_key` (soft dispatch) / `prefs` (set/delete)
Flutter-only: `hot_reload` (registered only in debug/profile builds when the
VM Service is reachable; no hot_restart — that RPC requires a flutter run
session, which standalone apps don't have)
Basics: `echo` / `ping` / `get_stats`

Coordinates: **normalized 0-1, top-left origin** (same as Android; Unity is
bottom-left). Screenshot conversion `x=(px+0.5)/W, y=(py+0.5)/H`, no flip.

## Log capture scope (honest)

| Source | Captured? |
|---|---|
| Flutter framework errors (build/layout) | yes |
| Uncaught platform-dispatched errors | yes |
| `debugPrint` | yes (while the link is started) |
| Uncaught async errors / `print` | only inside the `bootstrap()` zone |
| Native logs (logcat/nslog) | no |
| Anything logged before start | no (no history) |

Apps with their own zone can forward manually via
`OmniDebugLink.recordLog / recordError`.

## Known limitations

- Release builds (AOT) have no runtime reflection: `set_component` only
  supports targeted operations (text / scroll / checked); `--obfuscate`
  scrambles widgetType names.
- Hardware keys (Android back/home) cannot be injected from Dart — use
  `tap_screen` on the on-screen controls instead.
- `hot_restart` is not feasible (the RPC requires a flutter run session) and
  is deliberately not provided; restart the app manually to reset state.

## License

Same as the OmniDebugLink project.
