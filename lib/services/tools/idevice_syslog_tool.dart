import 'dart:async';
import 'dart:io';

import '../../data/log_entry.dart';
import '../ios_syslog_parser.dart';
import 'tool_process_runner.dart';

class IdeviceSyslogTool extends ToolProcessRunner {
  IdeviceSyslogTool({super.executablePath})
    : super(executableName: 'idevicesyslog');

  ToolStreamSession<LogEntry> start({
    required String deviceId,
    required String processName,
  }) {
    Process? process;
    var stopRequested = false;
    var stopFuture = Future<void>.value();
    late final StreamController<LogEntry> controller;
    final parser = IosSyslogParser();

    Future<void> stop() {
      if (stopRequested) {
        return stopFuture;
      }
      stopRequested = true;
      stopFuture = stopProcess(process);
      return stopFuture;
    }

    controller = StreamController<LogEntry>(
      onListen: () async {
        try {
          process = await startProcess(['-u', deviceId]);
          final stderrFuture = stderrText(process!);
          var emittedLogs = false;

          await for (final line in stdoutLines(process!)) {
            for (final entry in parser.addLine(line)) {
              emittedLogs = true;
              controller.add(entry);
            }
          }

          final trailingEntry = parser.flush();
          if (trailingEntry != null) {
            emittedLogs = true;
            controller.add(trailingEntry);
          }

          final stderrOutput = (await stderrFuture).trim();
          if (!emittedLogs && stderrOutput.isNotEmpty) {
            controller.add(
              buildToolErrorEntry(
                stderrOutput,
                tag: 'idevicesyslog',
                processName: processName,
              ),
            );
          }
        } on ProcessException catch (error) {
          logError('Failed to start idevicesyslog for $processName', error);
          controller.add(
            buildToolErrorEntry(
              'Failed to start idevicesyslog: ${describeError(error)}',
              tag: 'idevicesyslog',
              processName: processName,
            ),
          );
        } catch (error) {
          logError(
            'Unexpected error while streaming idevicesyslog for $processName',
            error,
          );
          controller.add(
            buildToolErrorEntry(
              'idevicesyslog error: ${describeError(error)}',
              tag: 'idevicesyslog',
              processName: processName,
            ),
          );
        } finally {
          await stop();
          await controller.close();
        }
      },
      onCancel: stop,
    );

    return ToolStreamSession(stream: controller.stream, onStop: stop);
  }
}
