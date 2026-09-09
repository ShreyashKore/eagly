import 'dart:io';

import '../../features/crash_reports/data/crash_report.dart';
import '../../features/app_log/app_logger.dart';
import '../../utils/utils.dart';
import 'ios_backend.dart';
import 'libimobiledevice_ios_crash_report_service.dart';
import 'rust_ios_crash_report_service.dart';

/// The result of pulling crash reports off a device: the reports themselves and
/// the temporary directory they were copied into (so the caller can clean it up
/// once it is done reading the files).
class CrashReportPullResult {
  const CrashReportPullResult({required this.reports, required this.outputDir});

  final List<CrashReport> reports;
  final Directory outputDir;
}

/// Thrown when crash reports cannot be read from the device.
class CrashReportException implements Exception {
  CrashReportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Crash report retrieval for one iOS device.
///
/// Both backends copy reports to a temp directory rather than handing back
/// bytes, because the viewer re-reads the file from disk by path.
abstract interface class IosCrashReportService {
  /// Copies reports off the device, leaving them in place. The caller owns the
  /// returned directory and should delete it when finished.
  Future<CrashReportPullResult> pullReports(String deviceId);
}

IosCrashReportService createIosCrashReportService() {
  return useRustIosBackend
      ? RustIosCrashReportService()
      : LibimobiledeviceIosCrashReportService();
}

/// Parses every crash report file under [dir], newest first.
///
/// Shared by both backends: they differ only in how the files get there.
Future<List<CrashReport>> collectCrashReports(
  Directory dir,
  AppLogger logger,
) async {
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
      logger.error(
        'Failed to read crash report ${entity.path}',
        detail: error.toString(),
      );
    }
  }

  // Newest first.
  reports.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return reports;
}

/// Best-effort removal of a partially-populated output directory.
Future<void> cleanupCrashReportDir(Directory dir) async {
  try {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  } catch (_) {}
}
