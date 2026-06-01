import 'package:eagly/data/log_entry.dart';

import '../ui/log_tab_view/log_tab_controller.dart';

extension LogEntryCollectionExt on Iterable<LogEntry> {

  String formatForCopy(LogCopyFormat format) {
    return map((log) => log._formatLogEntryForCopy(log, format)).join('\n');
  }
}

extension LogEntryExt on LogEntry {

  String _formatLogEntryForCopy(LogEntry log, LogCopyFormat format) {
    return switch (format) {
      LogCopyFormat.messageOnly => log.message,
      LogCopyFormat.timestampAndMessage => '${log.timestamp} ${log.message}',
      LogCopyFormat.fullLine =>
      '${log.timestamp} ${log.packageName ?? log.pid} ${log.tid} ${log.level} ${log.tag}: ${log.message}',
    };
  }
}