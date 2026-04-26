import '../services/log_file_service.dart';

String formatExportLogsMessage(LogExportResult result) {
  return result.error ??
      (result.fileName == null
          ? 'Logs exported successfully.'
          : 'Logs exported to ${result.fileName}.');
}
