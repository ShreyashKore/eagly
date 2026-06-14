import 'dart:io';

import '../../features/crash_reports/data/crash_report.dart';
import '../../utils/utils.dart';
import 'tool_process_runner.dart';

/// The result of pulling crash reports off a device: the reports themselves and
/// the temporary directory they were copied into (so the caller can clean it up
/// once it is done reading the files).
class CrashReportPullResult {
  const CrashReportPullResult({required this.reports, required this.outputDir});

  final List<CrashReport> reports;
  final Directory outputDir;
}

/// Thrown when `idevicecrashreport` cannot read reports from the device.
class CrashReportException implements Exception {
  CrashReportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class IdeviceCrashReportTool extends ToolProcessRunner {
  IdeviceCrashReportTool({super.executablePath})
    : super(executableName: 'idevicecrashreport');

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
        await _cleanup(outputDir);
        throw CrashReportException(details);
      }

      final reports = await _collectReports(outputDir);
      logSuccess('Read ${reports.length} crash report(s) from $deviceId');
      return CrashReportPullResult(reports: reports, outputDir: outputDir);
    } on CrashReportException {
      rethrow;
    } on ProcessException catch (error) {
      await _cleanup(outputDir);
      logError('ProcessException reading crash reports for $deviceId', error);
      throw CrashReportException(
        'Failed to read crash reports: ${describeError(error)}',
      );
    } catch (error) {
      await _cleanup(outputDir);
      logError('Unexpected error reading crash reports for $deviceId', error);
      throw CrashReportException(
        'Failed to read crash reports: ${describeError(error)}',
      );
    }
  }

  Future<List<CrashReport>> _collectReports(Directory dir) async {
    final reports = <CrashReport>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (!lower.endsWith('.ips') && !lower.endsWith('.crash')) continue;

      try {
        final stat = await entity.stat();
        final content = await readTextLenient(entity);
        reports.add(
          CrashReport.fromFile(
            fileName: extractFileName(entity.path),
            filePath: entity.path,
            content: content,
            modified: stat.modified,
            sizeBytes: stat.size,
          ),
        );
      } catch (error) {
        logError('Failed to read crash report ${entity.path}', error);
      }
    }

    // Newest first.
    reports.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return reports;
  }

  Future<void> _cleanup(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
