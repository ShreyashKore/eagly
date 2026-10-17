import 'dart:async';

import '../../features/app_log/app_logger.dart';
import '../../features/logs/data/models/log_entry.dart';
import '../../features/logs/services/log_parsers/ios_syslog_parser.dart';
import '../../src/rust/api/ios.dart' as rust;
import '../../utils/log_entry_utils.dart';
import '../tools/tool_process_runner.dart';
import 'ios_log_service.dart';

/// [IosLogService] backed by the `idevice` crate's syslog relay client.
///
/// Rust emits raw lines, byte-identical to what `idevicesyslog` prints, and the
/// same [IosSyslogParser] turns them into [LogEntry]s for both backends — it is
/// stateful (multi-line continuations, `\M-` meta-escapes) and well tested, so
/// moving it across the bridge would buy nothing and risk a lot.
class RustIosLogService implements IosLogService {
  static int _nextSessionId = 0;

  final AppLogger _logger = AppLogger(source: 'RustIosLogService');

  @override
  ToolStreamSession<LogEntry> startSyslog({
    required String deviceId,
    required String processName,
  }) {
    // Rust keys its cancellation registry by this id rather than by UDID, so
    // that two tabs on one device stop independently.
    final sessionId = '$deviceId-${_nextSessionId++}';

    final parser = IosSyslogParser();
    late final StreamController<LogEntry> controller;
    StreamSubscription<String>? subscription;
    var stopped = false;
    var ended = false;

    Future<void> stop() async {
      if (stopped) return;
      stopped = true;
      await subscription?.cancel();
      // Cancelling the Dart subscription alone does not stop the Rust task —
      // flutter_rust_bridge does not propagate cancellation — so the tokio task
      // and its lockdown session leak without this. Only for a stream that was
      // started and is still live: Rust keeps a stop with no start to claim it.
      if (subscription != null && !ended) {
        await rust.stopIosSyslog(sessionId: sessionId);
      }
    }

    controller = StreamController<LogEntry>(
      onListen: () {
        _logger.info('Starting iOS syslog stream for $processName');
        subscription = rust
            .startIosSyslog(udid: deviceId, sessionId: sessionId)
            .listen(
              (line) {
                for (final entry in parser.addLine(line)) {
                  controller.add(entry);
                }
              },
              onError: (Object error) {
                _logger.error(
                  'iOS syslog stream failed for $processName',
                  detail: error.toString(),
                );
                controller.add(
                  LogEntryUtils.buildToolError(
                    message: 'idevice syslog error: $error',
                    tag: 'idevice',
                    processName: processName,
                  ),
                );
              },
              onDone: () async {
                // The Rust task has already dropped its registry entry.
                ended = true;
                final trailing = parser.flush();
                if (trailing != null) controller.add(trailing);
                _logger.info('iOS syslog stream ended for $processName');
                await stop();
                await controller.close();
              },
            );
      },
      onCancel: stop,
    );

    return ToolStreamSession(stream: controller.stream, onStop: stop);
  }
}
