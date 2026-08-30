# omnidebuglink (Flutter)

OmniDebugLink 的 Flutter 客户端 SDK：把运行中的 Flutter App 接入 OmniDebugLink 中继，
让 AI 编程工具（经 MCP）可以直接在你的 App 上执行调试与自动化操作——遍历 widget 树、
点击/滑动、截图、读日志、看性能、读改 SharedPreferences，以及 Flutter 独有的
**hot_reload**（AI 改完代码远程热重载继续测）。

纯 Dart 包，无 platform channel。协议与通用规范见
[clients/CLAUDE.md](https://github.com/omnidebuglink/omnidebuglink_flutter)（仓库内 `../CLAUDE.md`）。

## 安装（git 依赖）

```yaml
dependencies:
  omnidebuglink:
    git:
      url: https://github.com/omnidebuglink/omnidebuglink_flutter.git
      ref: v0.1.0
```

## 快速接入

```dart
import 'package:omnidebuglink/omnidebuglink.dart';

void main() {
  OmniDebugLink.bootstrap(          // 推荐：一键接管 zone，捕获未捕获异步错误与 print
    url: 'wss://api.omnidebuglink.dev/ws?token=<clientToken>',
    appVersion: '1.2.0',
    app: const MyApp(),
  );
}
```

或自己管理生命周期：

```dart
runApp(const MyApp());
await OmniDebugLink.start('wss://api.omnidebuglink.dev/ws?token=<clientToken>');
```

路由栈上报（可选，不挂则 get_state 的 routes 为 null 并附引导）：

```dart
MaterialApp(navigatorObservers: [OmniDebugLink.routeObserver], ...)
```

要点：

- **一台设备一对 token**。两条连接复用同一 token 会互踢，SDK 收到关闭码 4000 后会永久停机并打警告。
- `OmniDebugLink.actionsEnabled`（默认 true）：写操作总开关，false = 只读观察模式，随 hello 上报。
- `OmniDebugLink.tasks.register(type, handler, description:, payloadSchema:)` 可注册自定义 task，
  注册表变化自动重发能力清单，服务端零改动。

## 内置 task（19 + 2）

读：`ui_traverse`（widget 树 dump）/ `find_objects` / `view_component` / `wait_for` / `screenshot`（PNG）
/ `read_logs` / `get_perf` / `get_state` / `prefs`
写：`ui_click` / `tap_screen` / `swipe` / `long_press` / `input_text` / `set_component`（定向操作）
/ `send_key`（软派发）/ `prefs`(set/delete)
Flutter 独有：`hot_reload`（仅 debug/profile 包，VM Service 可用时才注册；无 hot_restart——该 RPC
需要 flutter run 会话，独立运行的 App 不可用）
基础：`echo` / `ping` / `get_stats`

坐标约定：**0-1 归一化、原点左上**（同 Android 端；Unity 端为左下）。截图换算
`x=(px+0.5)/W, y=(py+0.5)/H`，无垂直翻转。

## 日志捕获范围（如实）

| 来源 | 能否捕获 |
|---|---|
| Flutter 框架错误（build/layout 异常） | ✅ |
| 未捕获平台派发错误 | ✅ |
| `debugPrint` | ✅（link 启动期间） |
| 未捕获 async 错误 / `print` | 仅 `bootstrap()` 的 zone 内 ✅ |
| 原生日志（logcat/nslog） | ❌ |
| start 之前的日志 | ❌（无历史） |

自有 zone 的 App 可用 `OmniDebugLink.recordLog / recordError` 手动转发。

## 已知限制

- release 包（AOT）无运行时反射：`set_component` 只支持定向操作（text / scroll / checked），
  看不到任意 State 字段；`--obfuscate` 会打乱 widgetType 名称。
- 硬件按键（Android back/home）无法从 Dart 注入，用 `tap_screen` 点屏幕控件替代。
- `hot_restart` 不可行（该 RPC 需要 flutter run 会话，独立运行的 App 上不存在），SDK 不提供；
  需要重置状态时手动重启 App。

## License

同 OmniDebugLink 项目。
