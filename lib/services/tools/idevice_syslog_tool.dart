import '../../features/logs/data/models/log_entry.dart';
import '../../features/logs/services/log_parsers/ios_syslog_parser.dart';
import 'tool_process_runner.dart';

class IdeviceSyslogTool({super.executablePath}) extends ToolProcessRunner {
  this : super(executableName: 'idevicesyslog');

  ToolStreamSession<LogEntry> start({
    required String deviceId,
    required String processName,
  }) => streamLogLines(
    ['-u', deviceId],
    parser: IosSyslogParser(),
    tag: 'idevicesyslog',
    subject: processName,
  );
}
