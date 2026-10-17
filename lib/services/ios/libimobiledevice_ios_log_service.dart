import '../../features/logs/data/models/log_entry.dart';
import '../tools/idevice_syslog_tool.dart';
import '../tools/tool_process_runner.dart';
import 'ios_log_service.dart';

/// [IosLogService] backed by the bundled `idevicesyslog` process.
class LibimobiledeviceIosLogService implements IosLogService {
  LibimobiledeviceIosLogService({IdeviceSyslogTool? ideviceSyslogTool})
    : _tool = ideviceSyslogTool ?? IdeviceSyslogTool();

  final IdeviceSyslogTool _tool;

  @override
  ToolStreamSession<LogEntry> startSyslog({
    required String deviceId,
    required String processName,
  }) => _tool.start(deviceId: deviceId, processName: processName);
}
