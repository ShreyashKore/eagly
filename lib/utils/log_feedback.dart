import '../services/app_install_service.dart';
import '../services/log_file_service.dart';

String formatAppInstallMessage(AppInstallResult result) {
  return result.error ??
      result.message ??
      (result.fileName == null
          ? 'App installed successfully.'
          : 'Installed ${result.fileName}.');
}

String formatExportLogsMessage(LogExportResult result) {
  return result.error ??
      (result.fileName == null
          ? 'Logs exported successfully.'
          : 'Logs exported to ${result.fileName}.');
}
