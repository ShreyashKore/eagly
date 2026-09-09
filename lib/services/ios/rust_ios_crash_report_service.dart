import 'dart:io';

import '../../features/app_log/app_logger.dart';
import '../../src/rust/api/ios.dart' as rust;
import 'ios_crash_report_service.dart';

/// [IosCrashReportService] backed by the `idevice` crate's
/// `com.apple.crashreportcopymobile` client.
class RustIosCrashReportService implements IosCrashReportService {
  final AppLogger _logger = AppLogger(source: 'RustIosCrashReportService');

  @override
  Future<CrashReportPullResult> pullReports(String deviceId) async {
    final outputDir = await Directory.systemTemp.createTemp('eagly-crashes-');
    try {
      await rust.pullIosCrashReports(udid: deviceId, outputDir: outputDir.path);

      final reports = await collectCrashReports(outputDir, _logger);
      _logger.success('Read ${reports.length} crash report(s) from $deviceId');
      return CrashReportPullResult(reports: reports, outputDir: outputDir);
    } catch (error) {
      await cleanupCrashReportDir(outputDir);
      _logger.error(
        'Failed to read crash reports for $deviceId',
        detail: error.toString(),
      );
      throw CrashReportException('Failed to read crash reports: $error');
    }
  }
}
