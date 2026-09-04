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
      ref: v0.2.0
```

## Quick start

```dart
import 'package:omnidebuglink/omnidebuglink.dart';

void main() {
  OmniDebugLink.bootstrap(          // recommended: takes over the zone,
    token: '<clientToken>',              // catching uncaught async errors & print
    appVersion: '1.2.0',
    app: const MyApp(),
  );
}
```

Or manage the lifecycle yourself:

```dart
runApp(const MyApp());
await OmniDebugLink.start('<clientToken>');  // relay URL is baked in
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

Flutter's element tree rebuilds constantly and is 70+ levels deep, so **path addressing is unreliable by design**: operation tasks locate targets by `key` / `text` / `widget_type` substring (+`index`), and locating + acting happen atomically inside one task. Path is only an exact-address fallback.

Read tasks:

| Task | What it does |
|---|---|
| `ui_traverse` | Widget tree snapshot, **flat list by default** (depth/name/key/text/rect/center, token-efficient; `flat:false` for nested, 3000-node cap) |
| `find_objects` | Search by text / key / widget_type substring; matches carry center coords and a hint to pass the same locator straight to an action task |
| `view_component` | One widget in depth: targeted properties + renderObject info, same locators |
| `wait_for` | Poll every 200 ms until a key / text / widget_type / path appears; timeout returns `found: false`, not an error |
| `screenshot` | PNG via `OffsetLayer.toImage` (`__odl_file` envelope), downsampling loop to fit the base64 budget |
| `read_logs` | Subscription buffer (no history before start): Flutter framework errors, platform-dispatched errors, `debugPrint` |
| `get_perf` | FrameTiming percentiles (p50/p95/p99) + RSS |
| `get_state` | App state + route stack (register `OmniDebugLink.routeObserver` in `MaterialApp`) |
| `prefs` | Read SharedPreferences (get / list) |

Write tasks (all gated by `actionsEnabled`):

| Task | What it does |
|---|---|
| `ui_click` | Real gesture tap (`GestureBinding.handlePointerEvent`) on a target located by key/text/widget_type/index/path — atomically in one call |
| `tap_screen` | Tap at normalized 0-1 coordinates (top-left origin) |
| `swipe` | Drag gesture with per-frame `delta` + increasing timestamps (velocity tracking needs both) |
| `long_press` | Pointer down, hold (recognizer's own timer fires), up |
| `input_text` | Write text into a field located by key/widget_type/path or the current focus (`text` is the VALUE to enter, not a locator) |
| `set_component` | Targeted mutations only (no reflection in AOT): text / scroll_offset / scroll_to_end / scroll_to_start / checked |
| `send_key` | Soft-dispatched enter / escape / tab / space |
| `prefs` | Write / delete SharedPreferences with valueType coercion |

Flutter-only (debug/profile builds with a reachable VM Service): `hot_reload` — reloads sources in place, pairs great with an AI edit→reload→verify loop. No `hot_restart`: that RPC requires a `flutter run` session, which standalone apps never have.

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

Released under the [MIT License](LICENSE).
