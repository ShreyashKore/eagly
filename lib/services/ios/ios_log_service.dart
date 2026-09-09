import '../../features/logs/data/models/log_entry.dart';
import '../tools/tool_process_runner.dart';
import 'ios_backend.dart';
import 'libimobiledevice_ios_log_service.dart';
import 'rust_ios_log_service.dart';

/// Live syslog streaming for one iOS device.
abstract interface class IosLogService {
  /// Starts a stream. Each call is an independent session: eagly opens one log
  /// stream per tab and several tabs may watch the same device, so stopping one
  /// must never disturb another.
  ///
  /// The returned session's `stop()` tears down the underlying process or Rust
  /// task; the stream closing on its own means the device went away.
  ToolStreamSession<LogEntry> startSyslog({
    required String deviceId,
    required String processName,
  });
}

IosLogService createIosLogService() {
  return useRustIosBackend
      ? RustIosLogService()
      : LibimobiledeviceIosLogService();
}
