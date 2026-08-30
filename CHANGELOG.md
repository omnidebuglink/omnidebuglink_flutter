# Changelog

## 0.1.0

首个版本。

- 协议层：v1 帧（hello/task/result/ping）、55s 心跳、180s 看门狗、指数退避重连（1s→30s）、
  关闭码 4000 永久停机、注册表变化自动重发 hello。
- 读 task：ui_traverse / find_objects / view_component / wait_for / screenshot（PNG）/
  read_logs / get_perf / get_state / prefs
- 写 task（受 actionsEnabled 门控）：ui_click / tap_screen / swipe / long_press /
  input_text / send_key / set_component（定向）/ prefs 写
- Flutter 独有：hot_reload（VM Service，仅 debug/profile；hot_restart 因依赖 flutter run 会话
  不可行，已移除）
- 接入 API：OmniDebugLink.bootstrap / start / stop / actionsEnabled / tasks.register /
  routeObserver / recordLog / recordError
