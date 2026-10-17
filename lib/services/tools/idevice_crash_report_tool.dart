import 'dart:io';

import '../ios/ios_crash_report_service.dart';
import '../../utils/utils.dart';
import 'tool_process_runner.dart';

class IdeviceCrashReportTool({super.executablePath}) extends ToolProcessRunner {
  this : super(executableName: 'idevicecrashreport');

  /// Copies (non-destructively, with `-k`) and extracts (`-e`) crash reports
  /// from [deviceId] into a fresh temp directory, then parses each report file.
  /// The returned [CrashReportPullResult.outputDir] should be deleted by the
  /// caller once finished.
  Future<CrashReportPullResult> pullReports(String deviceId) async {
    final outputDir = await Directory.systemTemp.createTemp('eagly-crashes-');
    try {
      // -k keeps the reports on the device, -e extracts the raw report files.
      final result = await runText([
        '-u',
        deviceId,
        '-k',
        '-e',
        outputDir.path,
      ]);

      if (!result.isSuccess) {
        final details = describeCommandFailure(
          'Failed to read crash reports from $deviceId.',
          result,
        );
        logError('idevicecrashreport failed for $deviceId', details);
        await cleanupCrashReportDir(outputDir);
        throw CrashReportException(details);
      }

      final reports = await collectCrashReports(outputDir, logger);
      logSuccess('Read ${reports.length} crash report(s) from $deviceId');
      return CrashReportPullResult(reports: reports, outputDir: outputDir);
    } on CrashReportException {
      rethrow;
    } on ProcessException catch (error) {
      await cleanupCrashReportDir(outputDir);
      logError('ProcessException reading crash reports for $deviceId', error);
      throw CrashReportException(
        'Failed to read crash reports: ${describeError(error)}',
      );
    } catch (error) {
      await cleanupCrashReportDir(outputDir);
      logError('Unexpected error reading crash reports for $deviceId', error);
      throw CrashReportException(
        'Failed to read crash reports: ${describeError(error)}',
      );
    }
  }
}
