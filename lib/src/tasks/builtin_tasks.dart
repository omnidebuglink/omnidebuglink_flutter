import 'tasks_basics.dart';
import 'tasks_input.dart';
import 'tasks_logs.dart';
import 'tasks_perf.dart';
import 'tasks_prefs.dart';
import 'tasks_state.dart';
import 'tasks_text.dart';
import 'tasks_ui_read.dart';

/// Master table of built-in tasks. hot_reload is registered
/// separately after the VM service probe (see omni_debug_link.dart).
void registerAll() {
  registerBasicTasks();
  registerLogTasks();
  registerUiReadTasks();
  registerInputTasks();
  registerTextTasks();
  registerPrefsTasks();
  registerStateAndScreenshotTasks();
  registerPerfTasks();
}
